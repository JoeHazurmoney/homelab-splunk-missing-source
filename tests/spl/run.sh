#!/usr/bin/env bash
# Fixture tests for the hl_data_health evaluator and tracker macros (spec §7, task 9).
#
# Evaluator cases: a directory under cases/ holds fixture tables (any of expected, state_fast,
# state_slow, fwd, overrides, baseline, meta, blocks, tamper, prev; a missing one falls back to
# fixtures/defaults/) and the expected results: out.csv (the columns it names, for every evaluated
# entity) and, optionally, transitions.csv (the rows the evaluator would collect to data_health).
# Macro cases: a directory with search.spl runs that search instead of the evaluator; @name@ in it
# becomes the case's name.csv fixture lookup and @NOW@ the clock. Every *.csv there is uploaded.
# Fixture cells may say NOW, NOW-300 or NOW+60; everything runs at NOW=2000000000.
#
# The runner copies the tables into the app's lookups/ as dhtest_<case>_<table>.csv, runs the
# search through REST, diffs the results and exits non-zero on any mismatch.
# The dhtest_ files are removed afterwards. Nothing is written to KV or to an index.
#
# shellcheck disable=SC2016  # backticks here are Splunk macro calls, not shell expansions
# Usage: tests/spl/run.sh [case-glob]     e.g. tests/spl/run.sh '1*'
#        tests/spl/run.sh --scale [hosts] the generated scale case (default 300 hosts x 20)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/spl/lib.sh
. "$here/lib.sh"

NOW=2000000000
TABLES="expected state_fast state_slow fwd overrides baseline meta blocks tamper prev"
work=$(mktemp -d)
cleanup() {
  rm -rf "$work"
  dh_docker exec -u root "$DH_CONTAINER" sh -c "rm -f $DH_APP_DIR/lookups/dhtest_*.csv"
}
trap cleanup EXIT

# render <file> <header-file>: print <file> with the columns of <header-file> (missing ones empty)
# and NOW[+-n] replaced by epoch seconds. An empty <file> name prints the header file itself.
render() {
  awk -F, -v OFS=, -v now="$NOW" -v hdrfile="$2" '
    function t(v) { if (v ~ /^NOW([+-][0-9]+)?$/) return now + substr(v, 4); return v }
    BEGIN { getline hdr < hdrfile; sub(/\r$/, "", hdr); n = split(hdr, H, ","); print hdr }
    { sub(/\r$/, "") }
    FNR == 1 { for (i = 1; i <= NF; i++) C[$i] = i; next }
    /^[[:space:]]*$/ { next }
    { line = ""
      for (i = 1; i <= n; i++) { v = (H[i] in C) ? t($(C[H[i]])) : ""; line = line (i > 1 ? "," : "") v }
      print line }' "${1:-$2}"
}

# upload <id> <dir>: render and copy every table of a case into the app's lookups/.
upload() {
  local id=$1 dir=$2 t src f
  mkdir -p "$work/$id"
  if [ -f "$dir/search.spl" ]; then # macro case: its own tables, as written
    for f in "$dir"/*.csv; do
      t=$(basename "$f" .csv)
      case $t in out | transitions) continue ;; esac
      render "$f" "$f" >"$work/$id/dhtest_${id}_$t.csv"
    done
  else
    for t in $TABLES; do
      src=""
      [ -f "$dir/$t.csv" ] && src="$dir/$t.csv"
      render "$src" "$here/fixtures/defaults/$t.csv" >"$work/$id/dhtest_${id}_$t.csv"
    done
  fi
  dh_docker cp "$(dh_hostpath "$work/$id")/." "$DH_CONTAINER:$DH_APP_DIR/lookups/"
  dh_docker exec -u root "$DH_CONTAINER" chown splunk:splunk "$DH_APP_DIR/lookups/" -R
  # splunkd only sees lookup files copied in out of band after this reload.
  dh_curl -o "$work/reload.out" -X POST "$DH_MGMT/services/data/lookup-table-files/_reload"
}

eval_call() { # the evaluator over a case's fixture tables
  local id=$1 args="" t
  for t in $TABLES; do args="$args dhtest_${id}_$t.csv,"; done
  printf '| `dh_eval(%s %s)`' "$args" "$NOW"
}

base_search() { # base_search <id> <dir>: the case's search.spl (substituted, one line) or dh_eval
  if [ -f "$2/search.spl" ]; then
    tr -d '\r' <"$2/search.spl" | tr '\n' ' ' | sed "s/@NOW@/$NOW/g; s/@\([a-z_]*\)@/dhtest_${1}_\1.csv/g"
  else
    eval_call "$1"
  fi
}

line_expr() { # eval expression joining the named columns with commas (nulls as empty)
  local cols=$1 expr="" c
  IFS=, read -ra cs <<<"$cols"
  for c in "${cs[@]}"; do
    expr="$expr${expr:+.\",\".}if(isnull('$c'),\"\",tostring('$c'))"
  done
  printf '%s' "$expr"
}

errors() { # print the search's error messages, for a failing case
  dh_search "$1" json | grep -o '"type":"\(ERROR\|FATAL\)","text":"[^"]*"' | sort -u | head -5 || true
}

# check <id> <dir> <expected-file> <spl-suffix>: run, diff, report. Returns 1 on a mismatch.
check() {
  local id=$1 dir=$2 exp=$3 suffix=$4 cols spl
  cols=$(head -1 "$exp" | tr -d '\r')
  # The trailer row proves the pipeline ran to the end (an empty expectation can't pass on a
  # search that failed) and counts the rows.
  spl="$(base_search "$id" "$dir") $suffix | eval _raw=$(line_expr "$cols") | fields _raw"
  spl="$spl | appendpipe [ stats count as dh_n | eval _raw=\"~rows \".dh_n | fields _raw ]"
  render "$exp" "$exp" | tail -n +2 | sed '/^$/d' >"$work/$id.body"
  { cat "$work/$id.body"; echo "~rows $(wc -l <"$work/$id.body" | tr -d ' ')"; } | LC_ALL=C sort >"$work/$id.want"
  dh_search "$spl" raw | tr -d '\r' | sed '/^$/d' | LC_ALL=C sort >"$work/$id.got"
  if diff -u --label want --label got "$work/$id.want" "$work/$id.got" >"$work/$id.diff"; then
    return 0
  fi
  echo "  columns: $cols"
  sed 's/^/  /' "$work/$id.diff"
  errors "$spl" | sed 's/^/  search: /'
  return 1
}

# Macro arguments can't contain macros (10.6.0.5: "The macro expression ... is invalid"), so
# dh_evaluate names the real lookups literally. This keeps them equal to the dh_lookup_* macros.
names_check() {
  local spl got m
  spl='| rest splunk_server=local count=0 /servicesNS/nobody/'$DH_APP'/admin/macros | search eai:acl.app='$DH_APP
  spl="$spl | stats"
  for m in evaluate lookup_expected lookup_state_fast lookup_state_slow lookup_fwd lookup_overrides \
    lookup_baseline lookup_meta lookup_blocks lookup_tamper lookup_status; do
    spl="$spl values(eval(if(title==\"dh_$m\", definition, null()))) as $m"
  done
  spl="$spl | eval want=\"\`dh_eval(\".lookup_expected.\", \".lookup_state_fast.\", \".lookup_state_slow.\", \".lookup_fwd.\", \".lookup_overrides.\", \".lookup_baseline.\", \".lookup_meta.\", \".lookup_blocks.\", \".lookup_tamper.\", \".lookup_status.\", now())\`\""
  spl="$spl | eval _raw=if(evaluate==want, \"same\", \"dh_evaluate is: \".evaluate.\" want: \".want) | fields _raw"
  got=$(dh_search "$spl" raw | tr -d '\r' | sed '/^$/d')
  if [ "$got" = "same" ]; then echo "PASS lookup-names"; return 0; fi
  echo "  $got"
  echo "FAIL lookup-names"
  return 1
}

run_cases() {
  local pattern=${1:-*} pass=0 fail=0 dir name id ok
  if [ "$pattern" = "*" ]; then
    if names_check; then pass=$((pass + 1)); else fail=$((fail + 1)); fi
  fi
  for dir in "$here"/cases/$pattern/; do
    [ -f "$dir/out.csv" ] || continue
    name=$(basename "$dir")
    id=$(printf '%s' "$name" | tr -c 'a-zA-Z0-9\n' '_')
    upload "$id" "$dir"
    ok=1
    check "$id" "$dir" "$dir/out.csv" "" || ok=0
    if [ -f "$dir/transitions.csv" ]; then
      check "$id" "$dir" "$dir/transitions.csv" '| `dh_transition_rows`' || ok=0
    fi
    if [ "$ok" -eq 1 ]; then pass=$((pass + 1)); echo "PASS $name"; else fail=$((fail + 1)); echo "FAIL $name"; fi
    dh_docker exec -u root "$DH_CONTAINER" sh -c "rm -f $DH_APP_DIR/lookups/dhtest_${id}_*.csv"
  done
  echo "$pass passed, $fail failed"
  [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
}

# The status mix gen-scale.sh produces for <hosts> hosts (20 entities each): hosts i%50 are muted;
# of the rest, i%10 lose their heartbeat (host row MISSING), i%7 their syslog, i%11 their vmstat.
scale_want() {
  local n=$1 muted missing
  muted=$((n / 50))
  muted=$((muted * 20))
  missing=$(((n / 10 - n / 50) + (n / 7 - n / 350) + (n / 11 - n / 550)))
  printf 'MISSING %s\nMUTED %s\nOK %s\n' "$missing" "$muted" $((20 * n - muted - missing)) | awk '$2 > 0'
}

run_scale() {
  local hosts=${1:-300} dir="$work/scale_src" id=scale sid json dur ok=1
  mkdir -p "$dir"
  bash "$here/gen-scale.sh" "$hosts" "$dir"
  upload "$id" "$dir"
  echo "scale: $(($(wc -l <"$dir/expected.csv") - 1)) expected rows, $(($(wc -l <"$dir/state_fast.csv") - 1)) state rows"
  sid=$(dh_curl "$DH_MGMT/servicesNS/admin/$DH_APP/search/jobs" -d exec_mode=blocking -d output_mode=json \
    --data-urlencode "search=$(eval_call "$id") | stats count by status" | grep -o '"sid":"[^"]*"' | cut -d'"' -f4)
  json=$(dh_curl "$DH_MGMT/servicesNS/admin/$DH_APP/search/jobs/$sid?output_mode=json")
  dur=$(printf '%s' "$json" | grep -o '"runDuration":[0-9.]*' | head -1 | cut -d: -f2)
  dh_curl "$DH_MGMT/servicesNS/admin/$DH_APP/search/jobs/$sid/results?output_mode=csv&count=0" |
    awk -F, 'NR > 1 { gsub(/"/, ""); print $1, $2 }' | LC_ALL=C sort >"$work/scale.got"
  dh_curl -o "$work/del.out" -X DELETE "$DH_MGMT/servicesNS/admin/$DH_APP/search/jobs/$sid"
  scale_want "$hosts" | LC_ALL=C sort >"$work/scale.want"
  sed 's/^/scale: status /' "$work/scale.got"
  if ! diff -u --label want --label got "$work/scale.want" "$work/scale.got"; then
    echo "scale: FAIL status mix"
    ok=0
  fi
  local count
  count=$(awk '{ s += $2 } END { print s + 0 }' "$work/scale.got")
  if [ "$count" -ne $((20 * hosts)) ]; then
    echo "scale: FAIL $count rows, want $((20 * hosts))"
    ok=0
  fi
  echo "scale: $count entities evaluated in ${dur}s (limit 10 s)"
  if ! awk -v d="$dur" 'BEGIN { exit !(d != "" && d < 10) }'; then
    echo "scale: FAIL too slow"
    ok=0
  fi
  [ "$ok" -eq 1 ] && echo "scale: PASS"
  [ "$ok" -eq 1 ]
}

if [ "${1:-}" = "--scale" ]; then run_scale "${2:-300}"; else run_cases "${1:-*}"; fi
