#!/bin/sh
# Tests for ansible/roles/homelab_splunk/files/hl_cribl_config.sh (the in-container helper of the
# `cribl` tag, spec 5.3). Needs only a POSIX sh, sha256sum, awk and stat; it runs anywhere, for
# example inside the Cribl container:
#   docker cp ansible/roles/homelab_splunk/files/hl_cribl_config.sh cribl:/tmp/
#   docker cp tests/cribl/hl_cribl_config_test.sh cribl:/tmp/
#   docker exec cribl sh /tmp/hl_cribl_config_test.sh /tmp/hl_cribl_config.sh
# Each run uses its own throwaway CRIBL_VOLUME_DIR, so it never touches a real volume.
set -u
helper=${1:?usage: $0 <path to hl_cribl_config.sh>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
# check <name> <command...>: the command's exit status decides
check() {
  name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
has() { printf '%s\n' "$1" | grep -q -- "$2"; }
present() { [ -f "$1" ]; }
absent() { [ ! -f "$1" ]; }

vol=$work/vol
stage=$work/stage
mkdir -p "$vol/local/cribl" "$stage/local/cribl/pipelines/p1"
echo "a: 1" >"$stage/local/cribl/a.yml"
echo "p: 1" >"$stage/local/cribl/pipelines/p1/conf.yml"
run() { CRIBL_VOLUME_DIR=$vol sh "$helper" "$@"; }
m=$vol/local/.hl_pushed.manifest
live=$vol/local/cribl

out=$(run install "$stage")
check "first install reports changed" has "$out" "HL_RESULT=changed"
check "first install copies a.yml" present "$live/a.yml"
check "first install copies a pipeline" present "$live/pipelines/p1/conf.yml"
check "install leaves the record pending" present "$m.pending"
check "install does not commit" absent "$m"

# A failed Cribl restart means no commit: the next run must still see a change (and restart)
out=$(run install "$stage")
check "install with a pending record reports changed" has "$out" "HL_RESULT=changed"

out=$(run commit)
check "commit reports committed" has "$out" "HL_RESULT=committed"
check "commit writes the record" present "$m"
check "commit clears the pending record" absent "$m.pending"
out=$(run install "$stage")
check "install after commit reports unchanged" has "$out" "HL_RESULT=unchanged"
check "unchanged leaves nothing pending" absent "$m.pending"
out=$(run commit)
check "commit with nothing pending is a no-op" has "$out" "HL_RESULT=nothing"

# A file dropped from the repo list is deleted from the volume, and that is a change
rm -rf "$stage/local/cribl/pipelines"
out=$(run install "$stage")
check "a dropped file reports changed" has "$out" "HL_RESULT=changed"
check "a dropped file is named in HL_CHANGED" has "$out" "HL_CHANGED=.*pipelines/p1/conf.yml"
check "a dropped file is deleted" absent "$live/pipelines/p1/conf.yml"
check "a kept file stays" present "$live/a.yml"
run commit >/dev/null
out=$(run install "$stage")
check "after the drop is committed: unchanged" has "$out" "HL_RESULT=unchanged"

# A file Cribl owns (in no record) is never touched
echo "cribl's own" >"$live/messages.yml"
run install "$stage" >/dev/null
check "a file the role never pushed stays" present "$live/messages.yml"

# An edited file is a change, and is copied
echo "a: 2" >"$stage/local/cribl/a.yml"
out=$(run install "$stage")
check "an edited file reports changed" has "$out" "HL_CHANGED=a.yml"
check "an edited file is copied" grep -q "a: 2" "$live/a.yml"

echo "$fails failure(s)"
[ "$fails" -eq 0 ]
