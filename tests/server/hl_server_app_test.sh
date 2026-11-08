#!/bin/sh
# Tests for ansible/roles/homelab_splunk/files/hl_server_app.sh's handling of the app's local
# inputs.conf (spec 5.3, 13). Needs a POSIX sh, tar, sha256sum and awk; `chown` is shimmed on PATH,
# because the helper chowns to the splunk user, which only exists in the Splunk container. Run:
#   sh tests/server/hl_server_app_test.sh ansible/roles/homelab_splunk/files/hl_server_app.sh
# Run it on Linux: Git Bash's sha256sum prints *path, which hides the helper's "default/inputs.conf"
# match. Each run uses its own throwaway SPLUNK_HOME.
set -u
helper=${1:?usage: $0 <path to hl_server_app.sh>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
check() {
  name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
has() { printf '%s\n' "$1" | grep -q -- "$2"; }
absent_in() { ! grep -q -- "$2" "$1"; }

mkdir -p "$work/bin" "$work/home/etc/apps" "$work/stage"
printf '#!/bin/sh\nexit 0\n' >"$work/bin/chown"
chmod +x "$work/bin/chown"
apps=$work/home/etc/apps
app=hl_server_base
loc=$apps/$app/local/inputs.conf

# build <inputs.conf content>: the app's tar as the role would ship it
build() {
  rm -rf "$work/build"
  mkdir -p "$work/build/$app/default"
  printf '[hl]\nmanaged = true\n' >"$work/build/$app/default/app.conf"
  printf '%s\n' "$1" >"$work/build/$app/default/inputs.conf"
  tar -C "$work/build" -cf "$work/stage/$app.tar" "$app"
}
run() { PATH=$work/bin:$PATH SPLUNK_HOME=$work/home sh "$helper" install "$work/stage" "$app"; }

# --- Expand: both tokens shipped ---
build '[splunktcptoken://hl_cribl]
token = tok-current

[splunktcptoken://hl_cribl_previous]
token = tok-previous

[http://hl_markers]
token = tok-hec
disabled = 0'
out=$(run)
check "expand installs" has "$out" "HL_RESULT=changed"

# What splunkd writes on its first start: each token, encrypted, into the app's local/inputs.conf
mkdir -p "$apps/$app/local"
cat >"$loc" <<'CONF'
[splunktcptoken://hl_cribl]
token = $7$encrypted-current

[splunktcptoken://hl_cribl_previous]
token = $7$encrypted-previous

[splunktcptoken://someone_elses]
token = $7$not-ours

[monitor:///var/log/kept]
index = main
CONF

# --- Contract: default drops the previous stanza ---
build '[splunktcptoken://hl_cribl]
token = tok-current

[http://hl_markers]
token = tok-hec
disabled = 0'
out=$(run)
check "contract changes the app" has "$out" "HL_RESULT=changed"
check "contract names default/inputs.conf" has "$out" "HL_CHANGED=.*default/inputs.conf"
check "the previous stanza is gone from local/" absent_in "$loc" "hl_cribl_previous"
check "the previous token's local copy is gone" absent_in "$loc" "encrypted-previous"
check "a stanza the role never shipped stays" grep -q "splunktcptoken://someone_elses" "$loc"
check "its token stays" grep -q 'not-ours' "$loc"
check "another stanza stays" grep -q "monitor:///var/log/kept" "$loc"
check "the current token's stale copy is dropped (default still sets it)" absent_in "$loc" "encrypted-current"

# A rerun with nothing changed touches nothing, even a stanza default never had
cat >"$loc" <<'CONF'
[splunktcptoken://someone_elses]
token = $7$not-ours
CONF
out=$(run)
check "no change: unchanged" has "$out" "HL_RESULT=unchanged"
check "no change: local/ untouched" grep -q 'not-ours' "$loc"

echo "$fails failure(s)"
[ "$fails" -eq 0 ]
