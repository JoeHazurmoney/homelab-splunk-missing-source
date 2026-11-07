#!/bin/sh
# Runs inside the Cribl container (docker exec), copied there by the `cribl` and `cribl_block` tags
# (spec 5.3). Prints KEY=value lines for Ansible to read. Tests: tests/cribl/hl_cribl_config_test.sh.
#
#   hl_cribl_config.sh install <stage>
#     <stage>/local/cribl/... holds the config files the role rendered. Copies each changed one into
#     $CRIBL_VOLUME_DIR/local/cribl/ (or $CRIBL_HOME/local/cribl/ without a volume dir), deletes the
#     files the role pushed before but no longer ships, and writes their sha256 to
#     local/.hl_pushed.manifest.pending. A file counts as changed when the rendered file differs
#     from what the role last committed, or when the pushed file is missing. The comparison is
#     against the role's own record, not the live file, because a UI save may rewrite the file; a UI
#     edit is the tamper indicator's business (spec 7.6). A pending record left by an earlier run
#     (its Cribl restart or load check failed) counts as a change, so that run is retried.
#     -> HL_RESULT=changed|unchanged, HL_CHANGED=<changed or deleted files, relative to local/cribl>
#
#   hl_cribl_config.sh commit
#     After Cribl restarted and loaded the config: the pending record becomes the record.
#     -> HL_RESULT=committed|nothing
#
#   hl_cribl_config.sh lookup-path <file>
#     -> HL_LOOKUP=<absolute path of data/lookups/<file>, or empty>
#
#   hl_cribl_config.sh lookup-cat <file>
#     -> the content of data/lookups/<file> (nothing when Cribl has none)
set -eu
base=${CRIBL_VOLUME_DIR:-}
if [ -z "$base" ] || [ ! -d "$base" ]; then base=${CRIBL_HOME:-/opt/cribl}; fi
local_dir=$base/local
manifest=$local_dir/.hl_pushed.manifest
pending=$manifest.pending

install_config() {
  stage=$1
  src=$stage/local/cribl
  [ -d "$src" ] || { echo "HL_ERROR=$src is missing" >&2; exit 2; }
  mkdir -p "$local_dir/cribl"
  new=$stage/new.manifest
  (cd "$src" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | xargs -r sha256sum) >"$new"
  changed=""
  while read -r sum path; do
    old=$(awk -v p="$path" '$2 == p { print $1 }' "$manifest" 2>/dev/null || true)
    if [ "$old" != "$sum" ] || [ ! -f "$local_dir/cribl/$path" ]; then changed="$changed$path "; fi
  done <"$new"
  # Files the role pushed before (committed or pending) that it no longer ships
  dropped=""
  cat "$manifest" "$pending" 2>/dev/null | awk '{ print $2 }' | LC_ALL=C sort -u >"$stage/old.paths"
  while read -r path; do
    if ! awk -v p="$path" '$2 == p { f = 1 } END { exit !f }' "$new"; then dropped="$dropped$path "; fi
  done <"$stage/old.paths"
  if [ -z "$changed" ] && [ -z "$dropped" ] && [ ! -f "$pending" ]; then
    echo "HL_RESULT=unchanged"
    echo "HL_CHANGED="
    return 0
  fi
  # Keep the owner Cribl gave its own local/ tree
  owner=$(stat -c %u:%g "$local_dir")
  for path in $changed; do
    mkdir -p "$(dirname "$local_dir/cribl/$path")"
    cp -f "$src/$path" "$local_dir/cribl/$path.hl_new"
    mv -f "$local_dir/cribl/$path.hl_new" "$local_dir/cribl/$path"
    chown "$owner" "$local_dir/cribl/$path"
    chmod 600 "$local_dir/cribl/$path"
  done
  for path in $dropped; do rm -f "$local_dir/cribl/$path"; done
  cp -f "$new" "$pending"
  chmod 600 "$pending"
  echo "HL_RESULT=changed"
  echo "HL_CHANGED=$changed$dropped"
}

commit_config() {
  if [ ! -f "$pending" ]; then
    echo "HL_RESULT=nothing"
    return 0
  fi
  mv -f "$pending" "$manifest"
  echo "HL_RESULT=committed"
}

lookup_path() {
  for d in "$base/data/lookups" "${CRIBL_HOME:-/opt/cribl}/data/lookups"; do
    if [ -f "$d/$1" ]; then
      echo "HL_LOOKUP=$d/$1"
      return 0
    fi
  done
  echo "HL_LOOKUP="
}

lookup_cat() {
  p=$(lookup_path "$1" | sed 's/^HL_LOOKUP=//')
  [ -z "$p" ] || cat "$p"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  install) install_config "$@" ;;
  commit) commit_config ;;
  lookup-path) lookup_path "$@" ;;
  lookup-cat) lookup_cat "$@" ;;
  *)
    echo "usage: $0 install <stage> | commit | lookup-path <file> | lookup-cat <file>" >&2
    exit 64
    ;;
esac
