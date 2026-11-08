#!/bin/sh
# Runs as root inside the Splunk container (docker exec), copied there by the `server` and
# `server_remove` tags (spec 5.3). Prints KEY=value lines for Ansible to read.
#
#   hl_server_app.sh install <stage> <app> [seed_lookup ...]
#     <stage>/<app>.tar holds the app as the role built it. Swaps in every shipped top-level
#     directory except local/ (default/, README/, ...), metadata/default.meta and the shipped
#     lookups, and keeps local/, local.meta and every other lookup (UI-written ones). A seed
#     lookup (one the UI or another tag rewrites, such as hl_ingest_block.csv) is copied only
#     when the app has none yet. Changes nothing when the installed files already match.
#     -> HL_RESULT=changed|unchanged, HL_CHANGED=<changed files, app-relative>
#
#   hl_server_app.sh remove <app>
#     Deletes the app, its private user-level objects (etc/users/*/<app>) and nothing else, and
#     only if its app.conf carries the role's marker ([hl] managed = true).
#     -> HL_RESULT=removed|absent|unmanaged, HL_CONFS=<default/*.conf it had>,
#        HL_INDEXES=<stanzas of its indexes.conf>
#
#   hl_server_app.sh purge <index> ...
#     Deletes the on-disk data of indexes that no config defines any more (after a restart);
#     btool runs as splunk (chroot --userspec: the image has no su or runuser).
#     -> HL_PURGED=<names>, HL_KEPT=<names still defined or protected>
set -eu
splunk_home=${SPLUNK_HOME:-/opt/splunk}
apps=$splunk_home/etc/apps
db=$splunk_home/var/lib/splunk

is_managed() {
  # [hl] stanza with managed = true in default/app.conf
  awk '
    /^[[:space:]]*\[/ { s = $0; gsub(/[[:space:]]/, "", s); in_hl = (s == "[hl]"); next }
    in_hl && /^[[:space:]]*managed[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]*$/, "", v)
      if (tolower(v) == "true" || v == "1") found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$1/default/app.conf" 2>/dev/null
}

# Top-level directories the role swaps wholesale: everything but local/, lookups/ and metadata/.
swap_dirs() {
  for d in "$@"; do
    [ -d "$d" ] || continue
    for e in "$d"/*/; do
      [ -d "$e" ] || continue
      n=${e%/}; n=${n##*/}
      case $n in local | lookups | metadata) ;; *) echo "$n" ;; esac
    done
  done | LC_ALL=C sort -u
}

# splunkd writes each splunktcptoken's token, encrypted, into the app's local/inputs.conf, and local
# beats default. A stanza the role stops shipping (the previous token, at the end of a rotation,
# spec 13) would keep its local copy and the old token would still be accepted, so a splunktcptoken
# stanza default/ named before this run and doesn't any more goes from local/, whole. Stanzas the
# role never shipped, and other apps, are not touched. <old default> <new default> <local> <temp>
drop_stale_token_stanzas() {
  awk -v old="$1" -v new="$2" '
    function stanzas(f, set, line, key) {
      while ((getline line < f) > 0) {
        if (line ~ /^[[:space:]]*\[/) {
          key = line; gsub(/[[:space:]]/, "", key)
          if (key ~ /^\[splunktcptoken:\/\//) set[key] = 1
        }
      }
      close(f)
    }
    BEGIN { stanzas(old, was); stanzas(new, now); drop = 0 }
    /^[[:space:]]*\[/ { s = $0; gsub(/[[:space:]]/, "", s); drop = (s in was) && !(s in now) }
    !drop { print }
  ' "$3" >"$4"
  cat "$4" >"$3"
  rm -f "$4"
}

# sha256 manifest of the managed files under $1, paths relative to it.
manifest() {
  root=$1; shift
  [ -d "$root" ] || return 0
  (
    cd "$root"
    for d in $dirs; do [ -d "$d" ] && find "$d" -type f; done
    [ -f metadata/default.meta ] && echo metadata/default.meta
    for l in $shipped; do [ -f "lookups/$l" ] && echo "lookups/$l"; done
    true
  ) | LC_ALL=C sort | (cd "$root" && xargs -r sha256sum)
}

install_app() {
  stage=$1; app=$2; shift 2
  seeds=" $* "
  src=$stage/x/$app
  dst=$apps/$app
  rm -rf "$stage/x"
  mkdir -p "$stage/x"
  tar -xf "$stage/$app.tar" -C "$stage/x"
  [ -f "$src/default/app.conf" ] || { echo "HL_ERROR=$app.tar has no $app/default/app.conf" >&2; exit 2; }
  if [ -d "$dst" ] && ! is_managed "$dst"; then
    echo "HL_ERROR=$dst exists but is not role-managed ([hl] managed = true); refusing to overwrite" >&2
    exit 3
  fi

  dirs=$(swap_dirs "$src" "$dst")
  shipped=""
  missing_seeds=""
  if [ -d "$src/lookups" ]; then
    for f in "$src"/lookups/*; do
      [ -f "$f" ] || continue
      n=${f##*/}
      case $seeds in
        *" $n "*) [ -f "$dst/lookups/$n" ] || missing_seeds="$missing_seeds $n" ;;
        *) shipped="$shipped $n" ;;
      esac
    done
  fi

  old=$stage/old.manifest
  new=$stage/new.manifest
  manifest "$dst" >"$old"
  manifest "$src" >"$new"
  changed=$(LC_ALL=C sort "$old" "$new" | uniq -u | awk '{print $2}' | LC_ALL=C sort -u | tr '\n' ' ')
  for n in $missing_seeds; do changed="${changed}lookups/$n "; done

  if [ -z "$changed" ]; then
    echo "HL_RESULT=unchanged"
    echo "HL_CHANGED="
    return 0
  fi

  # Before the swap, while default/inputs.conf still names what the role owned: a failed run can
  # then only leave a stale local copy of a stanza default still sets, which the next run handles.
  case " $changed " in
    *" default/inputs.conf "*)
      if [ -f "$dst/local/inputs.conf" ] && [ -f "$dst/default/inputs.conf" ]; then
        drop_stale_token_stanzas "$dst/default/inputs.conf" "$src/default/inputs.conf" "$dst/local/inputs.conf" "$stage/local_inputs.conf"
      fi
      ;;
  esac

  mkdir -p "$dst/metadata" "$dst/lookups"
  for d in $dirs; do
    rm -rf "$dst/.hl_new_$d" "$dst/.hl_old_$d"
    if [ -d "$src/$d" ]; then cp -a "$src/$d" "$dst/.hl_new_$d"; fi
    if [ -e "$dst/$d" ]; then mv "$dst/$d" "$dst/.hl_old_$d"; fi
    if [ -d "$dst/.hl_new_$d" ]; then mv "$dst/.hl_new_$d" "$dst/$d"; fi
    rm -rf "$dst/.hl_old_$d"
  done
  if [ -f "$src/metadata/default.meta" ]; then
    cp -f "$src/metadata/default.meta" "$dst/metadata/default.meta"
  else
    rm -f "$dst/metadata/default.meta"
  fi
  for n in $shipped $missing_seeds; do cp -f "$src/lookups/$n" "$dst/lookups/$n"; done
  # splunkd copies a splunktcptoken's token into local/inputs.conf, encrypted, on its first start,
  # and that copy beats default/. When the shipped inputs.conf changed (a rotated token), drop the
  # stale copies of the token keys that default/inputs.conf sets, so splunkd reads the new value.
  case " $changed " in
    *" default/inputs.conf "*)
      if [ -f "$dst/local/inputs.conf" ]; then
        awk -v def="$dst/default/inputs.conf" '
          BEGIN {
            while ((getline l < def) > 0) {
              if (l ~ /^[[:space:]]*\[/) { s = l; gsub(/[[:space:]]/, "", s) }
              else if (l ~ /^[[:space:]]*token[[:space:]]*=/) has[s] = 1
            }
          }
          /^[[:space:]]*\[/ { s = $0; gsub(/[[:space:]]/, "", s) }
          !(has[s] && $0 ~ /^[[:space:]]*token[[:space:]]*=/) { print }
        ' "$dst/local/inputs.conf" >"$stage/local_inputs.conf"
        cat "$stage/local_inputs.conf" >"$dst/local/inputs.conf"
        rm -f "$stage/local_inputs.conf"
      fi
      ;;
  esac
  chown -R splunk:splunk "$dst"
  chmod -R u=rwX,go=rX "$dst/default" "$dst/metadata" "$dst/lookups"
  # Tokens are rendered into default/inputs.conf: readable by splunkd only.
  if [ -f "$dst/default/inputs.conf" ]; then chmod 600 "$dst/default/inputs.conf"; fi
  echo "HL_RESULT=changed"
  echo "HL_CHANGED=$changed"
}

remove_app() {
  app=$1
  dst=$apps/$app
  if [ ! -d "$dst" ]; then
    echo "HL_RESULT=absent"
    echo "HL_CONFS="
    echo "HL_INDEXES="
    return 0
  fi
  if ! is_managed "$dst"; then
    echo "HL_RESULT=unmanaged"
    return 0
  fi
  confs=""
  for f in "$dst"/default/*.conf "$dst"/local/*.conf; do
    [ -f "$f" ] && confs="$confs ${f##*/}"
  done
  idx=""
  for f in "$dst/default/indexes.conf" "$dst/local/indexes.conf"; do
    [ -f "$f" ] || continue
    idx="$idx $(sed -n 's/^[[:space:]]*\[\([^]]*\)\][[:space:]]*$/\1/p' "$f" | grep -v '^default$' | tr '\n' ' ')"
  done
  rm -rf "$dst"
  for u in "$splunk_home"/etc/users/*/"$app"; do
    [ -d "$u" ] && rm -rf "$u"
  done
  # The config tracker's snapshot folders for the app (empty directories in practice)
  for s in "$splunk_home"/var/run/splunk/confsnapshot/*/apps/"$app"; do
    [ -d "$s" ] && rm -rf "$s"
  done
  echo "HL_RESULT=removed"
  echo "HL_CONFS=$(echo "$confs" | tr ' ' '\n' | LC_ALL=C sort -u | tr '\n' ' ')"
  echo "HL_INDEXES=$(echo "$idx" | tr ' ' '\n' | LC_ALL=C sort -u | tr '\n' ' ')"
}

purge_indexes() {
  purged=""
  kept=""
  # Every index any config still defines; refuse to purge anything if that list can't be read.
  listing=$(chroot --userspec=splunk:splunk / "$splunk_home/bin/splunk" btool indexes list 2>/dev/null) || {
    echo "HL_ERROR=btool indexes list failed; purging nothing" >&2
    exit 4
  }
  printf '%s\n' "$listing" | grep -qxF '[main]' || {
    echo "HL_ERROR=btool indexes list has no [main]; purging nothing" >&2
    exit 4
  }
  for i in "$@"; do
    case $i in
      "" | _* | main | history | summary | splunklogger | enclave1 | wd2l | wd2l_audit | *[!a-z0-9_-]*)
        kept="$kept $i"
        continue
        ;;
    esac
    if printf '%s\n' "$listing" | grep -qxF "[$i]"; then
      kept="$kept $i"
      continue
    fi
    rm -rf "${db:?}/$i" "${db:?}/$i.dat"
    purged="$purged $i"
  done
  echo "HL_PURGED=$purged"
  echo "HL_KEPT=$kept"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  install) install_app "$@" ;;
  remove) remove_app "$@" ;;
  purge) purge_indexes "$@" ;;
  *)
    echo "usage: $0 install <stage> <app> [seed ...] | remove <app> | purge <index> ..." >&2
    exit 64
    ;;
esac
