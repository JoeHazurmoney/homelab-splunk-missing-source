#!/bin/sh
# Runs inside the Cribl container (docker exec), copied there by the `cribl` and `cribl_block` tags
# (spec 5.3). Prints KEY=value lines for Ansible to read.
#
#   hl_cribl_config.sh install <stage>
#     <stage>/local/cribl/... holds the config files the role rendered. Copies each into
#     $CRIBL_VOLUME_DIR/local/cribl/ (or $CRIBL_HOME/local/cribl/ without a volume dir) and records
#     their sha256 in local/.hl_pushed.manifest. A file counts as changed when the rendered file
#     differs from what the role pushed last, or when the pushed file is missing. Cribl may rewrite
#     a file itself (it encrypts tokens), so the comparison is against the role's own record, not
#     against the live file; a UI edit is the tamper indicator's business (spec 7.6).
#     -> HL_RESULT=changed|unchanged, HL_CHANGED=<changed files, relative to local/cribl>
#
#   hl_cribl_config.sh remove
#     Deletes the files the manifest lists and the manifest (used when the volume is kept).
#     -> HL_RESULT=removed|absent
#
#   hl_cribl_config.sh lookup-path <file>
#     -> HL_LOOKUP=<absolute path of data/lookups/<file>, or empty>
set -eu
base=${CRIBL_VOLUME_DIR:-}
if [ -z "$base" ] || [ ! -d "$base" ]; then base=${CRIBL_HOME:-/opt/cribl}; fi
local_dir=$base/local
manifest=$local_dir/.hl_pushed.manifest

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
  if [ -z "$changed" ]; then
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
  cp -f "$new" "$manifest"
  chmod 600 "$manifest"
  echo "HL_RESULT=changed"
  echo "HL_CHANGED=$changed"
}

remove_config() {
  if [ ! -f "$manifest" ]; then
    echo "HL_RESULT=absent"
    return 0
  fi
  while read -r _sum path; do rm -f "$local_dir/cribl/$path"; done <"$manifest"
  rm -f "$manifest"
  echo "HL_RESULT=removed"
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

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  install) install_config "$@" ;;
  remove) remove_config ;;
  lookup-path) lookup_path "$@" ;;
  *)
    echo "usage: $0 install <stage> | remove | lookup-path <file>" >&2
    exit 64
    ;;
esac
