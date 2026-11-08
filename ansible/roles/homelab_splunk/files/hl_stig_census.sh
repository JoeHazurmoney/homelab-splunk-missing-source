#!/bin/bash
# What the kernel holds now (spec 5.3 audit_rules; run by the role on the target host, as root):
#   hl_stig_census.sh <STIG key ERE> <wd2l key ERE> <UF tamper key ERE>
# Prints HL_RULES, HL_STIG, HL_PRIV, HL_WD2L, HL_UF, HL_ORDER and auditctl -s's enabled/lost/backlog.
# HL_ORDER is "bad" when a wd2l or UF tamper rule comes after the first STIG rule: the exit filter is
# first-match by load order, so the STIG rules must load last or their path-less rules take over
# those rules' events and keys.
set -uo pipefail
export LC_ALL=C

stig_re=$1
wd2l_re=$2
uf_re=$3

listing=$(mktemp)
trap 'rm -f "$listing"' EXIT
if ! auditctl -l >"$listing"; then
    echo "HL_ERROR=auditctl -l failed"
    exit 2
fi

# Counts on a file, not a pipe: grep -c exits 1 on a count of 0, which pipefail would turn into a failure.
count() {
    grep -c -E -e "$1" "$listing" || true
}

echo "HL_RULES=$(wc -l <"$listing")"
echo "HL_STIG=$(count "$stig_re")"
echo "HL_PRIV=$(count '(-F key=|-k )privileged$')"
echo "HL_WD2L=$(count "$wd2l_re")"
echo "HL_UF=$(count "$uf_re")"

first_stig=$(grep -n -m 1 -E -e "$stig_re" "$listing" | cut -d: -f1)
last_own=$(grep -n -E -e "$wd2l_re" -e "$uf_re" "$listing" | tail -n 1 | cut -d: -f1)
if [ -z "$first_stig" ]; then
    echo "HL_ORDER=none"
elif [ -n "$last_own" ] && [ "$last_own" -gt "$first_stig" ]; then
    echo "HL_ORDER=bad"
else
    echo "HL_ORDER=ok"
fi

auditctl -s | awk '$1 == "enabled" || $1 == "lost" || $1 == "backlog" { print "HL_S_" $1 "=" $2 }'
