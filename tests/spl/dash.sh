#!/usr/bin/env bash
# Dashboard tests for hl_data_health (spec §7.8, §8; task 12), against the deployed app on the local
# wd2l-splunk container. Each mode takes the SPL straight from the view definitions
# (dash_check.py queries), so it tests what the dashboards run.
#
#   panels         every read-only data source of every view (Host detail and Manage on a real
#                  host): no search errors, and each drilldown source returns the field it passes on.
#                  Chains run as post-process searches on their base's job, as Studio runs them.
#   load [hosts]   the 300-host fixture (gen-scale.sh) evaluated into throwaway KV collections, then
#                  the Overview's searches run at once against them: the load (first dispatch to
#                  last result) must be under 3 s, and the KPIs and Needs attention must match the
#                  generated mix.
#   writes         the Manage writes end to end on throwaway KV collections and a throwaway CSV:
#                  preview -> confirm -> apply, the stored rows, the admin log, that a repeated or
#                  stale confirmation applies nothing, and the test-block command (task 11b).
#   sync           DH Sync expected, the search as written in savedsearches.conf, on a throwaway KV
#                  copy of dh_expected: it upserts by _key, so the rows it doesn't change stay as
#                  they were (DH Evaluate drops the status of any entity missing from dh_expected).
#
# Throwaway collections, lookup definitions and files are named dhtest_* and removed on exit.
# Usage: tests/spl/dash.sh panels | load [hosts] | writes | sync
# shellcheck disable=SC2016  # backticks here are Splunk macro calls, not shell expansions
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/spl/run.sh
. "$here/run.sh"

KV_MADE=""
dash_cleanup() {
  local c
  for c in $KV_MADE; do
    dh_curl -o /dev/null -X DELETE "$DH_MGMT/servicesNS/nobody/$DH_APP/data/transforms/lookups/$c"
    dh_curl -o /dev/null -X DELETE "$DH_MGMT/servicesNS/nobody/$DH_APP/storage/collections/config/$c"
  done
  # The REST deletes leave empty local/ files behind.
  # shellcheck disable=SC2016  # expanded inside the container
  [ -z "$KV_MADE" ] || dh_docker exec -u root "$DH_CONTAINER" sh -c 'for f in "$1"/local/collections.conf "$1"/local/transforms.conf; do [ -s "$f" ] || rm -f "$f"; done' sh "$DH_APP_DIR"
  cleanup
}
trap dash_cleanup EXIT

# kv_make <name> <like>: a throwaway KV collection and lookup definition with the fields of <like>.
kv_make() {
  local name=$1 fields code
  fields=$(conf_lines "$here/../../splunk/apps/$DH_APP/default/transforms.conf" | grep -F "|[$2]|fields_list = " | sed 's/.*fields_list = //')
  KV_MADE="$KV_MADE $name"
  code=$(dh_curl -o "$work/kv.out" -w '%{http_code}' "$DH_MGMT/servicesNS/nobody/$DH_APP/storage/collections/config" -d "name=$name")
  case $code in 200 | 201 | 409) ;; *) echo "kv_make $name: collection $code" >&2; return 1 ;; esac
  code=$(dh_curl -o "$work/kv.out" -w '%{http_code}' "$DH_MGMT/servicesNS/nobody/$DH_APP/data/transforms/lookups" \
    -d "name=$name" -d external_type=kvstore -d "collection=$name" --data-urlencode "fields_list=$fields")
  case $code in 200 | 201 | 409) ;; *) echo "kv_make $name: lookup $code" >&2; return 1 ;; esac
  # The KV service creates a collection added to an existing app only on this reload (task 11).
  dh_curl -o "$work/kv.out" -X POST "$DH_MGMT/servicesNS/nobody/$DH_APP/storage/collections/config/_reload"
}

# job <spl> [mode]: a search job; prints its sid (mode normal: at once; blocking: when done).
job() {
  dh_curl "$DH_MGMT/servicesNS/admin/$DH_APP/search/jobs" -d "tz=$DH_TZ" -d "exec_mode=${2:-blocking}" -d output_mode=json \
    --data-urlencode "search=$1" | grep -o '"sid":"[^"]*"' | cut -d'"' -f4
}
job_info() { dh_curl "$DH_MGMT/servicesNS/admin/$DH_APP/search/jobs/$1?output_mode=json"; }
job_field() { printf '%s' "$1" | grep -o "\"$2\":[^,}]*" | head -1 | cut -d: -f2- | tr -d '"'; }
job_errors() { printf '%s' "$1" | grep -o '"type":"\(ERROR\|FATAL\)","text":"[^"]*"' | sed 's/.*"text":"//; s/"$//' | sort -u || true; }
job_csv() { dh_curl "$DH_MGMT/servicesNS/admin/$DH_APP/search/jobs/$1/results?output_mode=csv&count=0"; }
job_del() { dh_curl -o /dev/null -X DELETE "$DH_MGMT/servicesNS/admin/$DH_APP/search/jobs/$1"; }

# queries <view> [tok=value ...]: "ds<TAB>spl" lines from the view's definition.
queries() { dash queries "$DH_APP_DIR" "$@" | tr -d '\r'; }

# first <spl>: the first value of the first column of a search's results.
first() { dh_search "$1" csv | tr -d '\r' | sed -n '2p' | cut -d, -f1 | tr -d '"'; }

########## panels
# pp <sid> <spl> [mode]: a job's results through a post-process search (what a ds.chain does;
# on 10.6 the v1 results endpoint refuses post-processing, and v2 takes it only as a POST).
pp() {
  dh_curl "$DH_MGMT/servicesNS/admin/$DH_APP/search/v2/jobs/$1/results" --data-urlencode "search=$2" -d "output_mode=${3:-csv}" -d count=0
}

panels() {
  local fail=0 view ds base spl sid info errs rows dur host unreg args drill note f csv
  local -A base_sid=()
  host=$(first '| `dh_ui_status(dh_status)` | where level=="host" | stats count by host | table host')
  unreg=$(first '| `dh_ui_unregistered(dh_expected, dh_state_fast, dh_state_slow, dh_baseline, now())` | table entity_id')
  echo "panels: host=$host unregistered=${unreg:-none}"
  # The drilldown sources and the field each passes to Host detail (dash_check prints them).
  drill=$({ dash check "$DH_APP_DIR" || true; } | sed -n 's/^drilldown \([a-z_]*\)\.[a-z_]* -> .*=<\([A-Za-z_]*\)> from \([a-z_]*\)$/\1.\3 \2/p')
  for view in dh_overview dh_host dh_manage dh_soh; do
    args=()
    case $view in
      dh_host) args=("host=$host") ;;
      dh_manage) args=("ov_host=$host" "ov_entity=host|*|$host|*|*" "bk_host=$host" "ov_reason=panel check" "ex_reason=panel check" "ad_reason=panel check" "bk_reason=panel check" "rt_reason=panel check" "rt_entity=host|*|$host|*|*" "ex_host=dhtest-panel" "ad_entity=${unreg:-sourcetype|linux|dhtest-panel|syslog|*}") ;;
    esac
    # Searches run as jobs; chains run as post-process searches on their base's job, as in Studio.
    while IFS=$'\t' read -r ds base spl; do
      case $spl in "#unset"*) echo "SKIP $view.$ds (${spl#\#}: a write waits for its confirmation)"; continue ;; esac
      if [ "$base" = "-" ]; then
        sid=$(job "$spl")
        base_sid[$ds]=$sid
        info=$(job_info "$sid")
        csv=$(job_csv "$sid" | tr -d '\r')
        rows=$(job_field "$info" resultCount)
        dur="$(job_field "$info" runDuration)s"
      else
        sid=${base_sid[$base]:-}
        if [ -z "$sid" ]; then echo "FAIL $view.$ds: base $base has no job"; fail=1; continue; fi
        info=$(pp "$sid" "$spl" json)
        csv=$(pp "$sid" "$spl" | tr -d '\r')
        rows=$(printf '%s\n' "$csv" | sed '/^$/d' | tail -n +2 | wc -l | tr -d ' ')
        dur="post-process of $base"
      fi
      errs=$(job_errors "$info" | grep -v 'hl_ingest_block' || true)
      if [ -n "$errs" ]; then
        echo "FAIL $view.$ds: $errs"
        fail=1
      else
        note=""
        if job_errors "$info" | grep -q hl_ingest_block; then note=" (hl_ingest_block is not defined yet: task 3)"; fi
        echo "PASS $view.$ds rows=$rows $dur$note"
      fi
      f=$(printf '%s\n' "$drill" | awk -v k="$view.$ds" '$1 == k { print $2 }')
      if [ -n "$f" ] && [ "${rows:-0}" -eq 0 ]; then
        echo "  ($view.$ds has no rows here, so its drilldown field is not checked on this run)"
      elif [ -n "$f" ] && ! printf '%s\n' "$csv" | head -1 | tr -d '"' | tr ',' '\n' | grep -qx "$f"; then
        echo "FAIL $view.$ds: drilldown field '$f' is not in its results"
        fail=1
      fi
    done < <(dash chains "$DH_APP_DIR" "$view" "${args[@]}" | tr -d '\r')
  done
  for sid in "${base_sid[@]}"; do job_del "$sid"; done
  [ "$fail" -eq 0 ] && echo "panels: PASS"
  [ "$fail" -eq 0 ]
}

########## load
load() {
  local hosts=${1:-300} dir="$work/scale_src" id=scale ds spl sids="" sid t0 t1 wall ok=1 n info dur maxdur=0 got want
  mkdir -p "$dir"
  bash "$here/gen-scale.sh" "$hosts" "$dir"
  upload "$id" "$dir"
  kv_make dhtest_kv_status dh_status
  kv_make dhtest_kv_meta dh_meta
  # The evaluator over the fixture, into KV (a full replace), and a current tracker row.
  sid=$(job "$(eval_call "$id") | outputlookup dhtest_kv_status | stats count")
  n=$(job_csv "$sid" | tr -d '"\r' | sed -n 2p); job_del "$sid"
  sid=$(job '| makeresults | eval name="tracker_fast", _key=name, last_run=now(), last_rx=now(), resumed_at=now()-86400 | fields _key name last_run last_rx resumed_at | outputlookup dhtest_kv_meta')
  job_del "$sid"
  echo "load: $n dh_status rows in KV (dhtest_kv_status) for $hosts hosts"
  # The Overview's data sources against the KV copies, dispatched in parallel as the browser does
  # (chains joined to their base, so each runs whole: an upper bound). The load is the wall time
  # from the first dispatch to the last result, including this client's REST round trips.
  local names=() spls=()
  while IFS=$'\t' read -r ds spl; do
    names+=("$ds")
    spls+=("$(printf '%s' "$spl" | sed 's/\<dh_status\>/dhtest_kv_status/g; s/\<dh_meta\>/dhtest_kv_meta/g')")
  done < <(queries dh_overview)
  t0=$(date +%s%N)
  for n in "${!names[@]}"; do job "${spls[$n]}" >"$work/sid.${names[$n]}" & done
  wait
  t1=$(date +%s%N)
  for ds in "${names[@]}"; do sids="$sids $ds=$(cat "$work/sid.$ds")"; done
  wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", (b - a) / 1e9 }')
  for sid in $sids; do
    info=$(job_info "${sid#*=}")
    dur=$(job_field "$info" runDuration)
    maxdur=$(awk -v a="$maxdur" -v b="$dur" 'BEGIN { print (b > a) ? b : a }')
    if [ -n "$(job_errors "$info")" ]; then echo "load: FAIL ${sid%%=*}: $(job_errors "$info")"; ok=0; fi
    printf 'load: %-14s %5ss  rows=%s\n' "${sid%%=*}" "$dur" "$(job_field "$info" resultCount)"
  done
  # Results: the KPIs and the number of hosts needing attention follow the generator's mix.
  # The KPIs per level: hosts are muted every 50th; of the rest, every 10th loses its heartbeat
  # (host missing), every 7th its syslog (a sourcetype) and every 11th its vmstat (a source).
  got=$(job_csv "$(cat "$work/sid.ds_kpi")" | tr -d '"\r' | awk -F, 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i } NR == 2 { print $c["host_expected"], $c["host_missing"], $c["sourcetype_missing"], $c["source_missing"], $c["host_muted"] + $c["sourcetype_muted"] + $c["source_muted"] }')
  want=$(awk -v n="$hosts" 'BEGIN { m = int(n / 50); print n, int(n / 10) - m, int(n / 7) - int(n / 350), int(n / 11) - int(n / 550), 20 * m }')
  if [ "$got" != "$want" ]; then echo "load: FAIL KPIs (hosts, host/sourcetype/source missing, muted) got '$got' want '$want'"; ok=0; fi
  got=$(job_csv "$(cat "$work/sid.ds_attention")" | tail -n +2 | grep -c . || true)
  want=$(awk -v n="$hosts" 'BEGIN { for (i = 1; i <= n; i++) if (i % 50 && (i % 10 == 0 || i % 7 == 0 || i % 11 == 0)) c++; print c + 0 }')
  if [ "$got" != "$want" ]; then echo "load: FAIL Needs attention has $got hosts, want $want"; ok=0; fi
  for sid in $sids; do job_del "${sid#*=}"; done
  echo "load: Overview loaded in ${wall}s (slowest search ${maxdur}s; limit 3 s)"
  if ! awk -v w="$wall" 'BEGIN { exit !(w < 3) }'; then echo "load: FAIL too slow"; ok=0; fi
  [ "$ok" -eq 1 ] && echo "load: PASS"
  [ "$ok" -eq 1 ]
}

########## writes
# w_run <ds> <tok=value ...>: run one Manage data source with the throwaway lookups; prints CSV.
w_run() {
  local ds=$1 spl
  shift
  spl=$(queries dh_manage "$@" | awk -F'\t' -v d="$ds" '$1 == d { print $2 }')
  case $spl in "" | "#"*) echo "w_run: $ds not runnable: $spl" >&2; return 1 ;; esac
  spl=$(printf '%s' "$spl" | sed 's/\<dh_overrides\>/dhtest_kv_overrides/g; s/\<dh_admin_log\>/dhtest_kv_admin_log/g; s/\<dh_expected\>/dhtest_kv_expected/g; s/\<hl_ingest_block\>/dhtest_w_blocks.csv/g; s/\<dh_retire_nonce\>/dhtest_kv_nonce/g')
  if [ -n "${DH_DEBUG:-}" ]; then dh_search "$spl" xml | grep -o '<msg[^<]*' | sed "s/^/  $ds: /" >&2 || true; fi
  # (actor_roles is multivalued: dropped so that every row stays on one CSV line)
  dh_search "$spl | fields - actor_roles" csv | tr -d '\r'
}
col() { awk -F, -v n="$1" 'NR == 1 { for (i = 1; i <= NF; i++) { gsub(/"/, "", $i); c[$i] = i } next } { v = $c[n]; gsub(/"/, "", v); print v }'; }
# ccol <name>: like col, for CSV whose cells may hold commas (a real CSV reader).
ccol() { PYTHONIOENCODING=utf-8 python -c 'import csv, sys; [print(r.get(sys.argv[1], "")) for r in csv.DictReader(sys.stdin)]' "$1" | tr -d '\r'; }
expect() { # expect <label> <got> <want-regex>
  if printf '%s' "$2" | grep -Eq -- "$3"; then echo "PASS $1"; else echo "FAIL $1: got '$2', want /$3/"; WFAIL=1; fi
}
kv_get() { dh_search "| inputlookup $1 | $2" csv | tr -d '\r'; }

writes() {
  WFAIL=0
  local ov tok res ex ad bk tok0
  kv_make dhtest_kv_overrides dh_overrides
  kv_make dhtest_kv_admin_log dh_admin_log
  kv_make dhtest_kv_expected dh_expected
  kv_make dhtest_kv_nonce dh_retire_nonce
  ov=("ov_host=dhtest-w1" "ov_entity=host|*|dhtest-w1|*|*" "ov_action=mute" "ov_duration=3600" "ov_reason=writes test" "ov_ticket=CHG-12")
  # Override: preview, then apply with the previewed token.
  tok=$(w_run ds_ov_plan "${ov[@]}" | col dh_token)
  expect "override preview gives a token" "$tok" '^[0-9a-f]{32}$'
  res=$(w_run ds_ov_apply "${ov[@]}" "ov_confirm=$tok" | col Result)
  expect "override applied" "$res" '^Done: Mute dhtest-w1: whole host$'
  res=$(kv_get dhtest_kv_overrides 'eval ok=if(mute_until>now()+3500 AND mute_until<=now()+3600, 1, 0) | table _key ok reason ticket set_by')
  expect "override row (key, expiry, reason, ticket, set_by)" "$(printf '%s' "$res" | sed -n 2p)" '^"host\|\*\|dhtest-w1\|\*\|\*",1,"writes test","CHG-12",admin$'
  res=$(w_run ds_ov_apply "${ov[@]}" "ov_confirm=$tok" | col Result)
  expect "override repeat (reload) applies nothing" "$res" '^Nothing written'
  res=$(w_run ds_ov_apply "${ov[@]}" "ov_confirm=0123456789abcdef0123456789abcdef" | col Result)
  expect "override with a wrong confirmation applies nothing" "$res" '^Nothing written'
  # DH Prune removes an expired mute row without a limit, which restores the state the mute was
  # previewed in: the confirmation must still not fit (the admin-log time is in the token).
  kv_get dhtest_kv_overrides 'where 1==0 | outputlookup dhtest_kv_overrides' >/dev/null
  res=$(w_run ds_ov_apply "${ov[@]}" "ov_confirm=$tok" | col Result)
  expect "override after a prune of its row applies nothing" "$res" '^Nothing written'
  tok=$(w_run ds_ov_plan "${ov[@]}" | col dh_token)
  res=$(w_run ds_ov_apply "${ov[@]}" "ov_confirm=$tok" | col Result)
  expect "override applied again from a new preview" "$res" '^Done: Mute dhtest-w1: whole host$'
  ov[2]="ov_action=unmute"
  tok=$(w_run ds_ov_plan "${ov[@]}" | col dh_token)
  res=$(w_run ds_ov_apply "${ov[@]}" "ov_confirm=$tok" | col Result)
  expect "unmute applied" "$res" '^Done: Unmute dhtest-w1: whole host$'
  res=$(kv_get dhtest_kv_overrides 'eval m=coalesce(mute_until, "none") | table m')
  expect "unmute cleared mute_until" "$(printf '%s' "$res" | sed -n 2p)" '^none$'
  res=$(kv_get dhtest_kv_admin_log 'stats count, values(action) as a | eval a=mvjoin(a, " ") | table count a')
  expect "admin log: one row per applied change" "$(printf '%s' "$res" | sed -n 2p)" '^3,"override_mute override_unmute"$'
  # Expected row: add, and a repeat.
  ex=("ex_level=sourcetype" "ex_index=linux" "ex_host=DHTEST-W2.mshome.net" "ex_sourcetype=syslog" "ex_profile=continuous" "ex_reason=writes test")
  tok=$(w_run ds_ex_plan "${ex[@]}" | col dh_token)
  tok0=$tok
  res=$(w_run ds_ex_apply "${ex[@]}" "ex_confirm=$tok" | col Result)
  expect "expected row applied" "$res" '^Done: Add expected row dhtest-w2 .{1,3} syslog \(linux\)$'
  res=$(kv_get dhtest_kv_expected 'eval es=if(abs(expected_since-now())<120, "now", expected_since) | table _key host managed_by enabled profile collection criticality es')
  expect "expected row stored" "$(printf '%s' "$res" | sed -n 2p)" '^"sourcetype\|linux\|dhtest-w2\|syslog\|\*","?dhtest-w2"?,ui,1,continuous,uf,2,now$'
  res=$(w_run ds_ex_apply "${ex[@]}" "ex_confirm=$tok" | col Result)
  expect "expected row repeat applies nothing" "$res" '^Nothing written'
  # An identical update of a UI row leaves the row as it was; the admin-log time in the token still
  # makes its confirmation fit only once.
  tok=$(w_run ds_ex_plan "${ex[@]}" | col dh_token)
  res=$(w_run ds_ex_apply "${ex[@]}" "ex_confirm=$tok" | col Result)
  expect "identical update of a UI row applied" "$res" '^Done: Add expected row'
  res=$(w_run ds_ex_apply "${ex[@]}" "ex_confirm=$tok" | col Result)
  expect "identical update repeat applies nothing" "$res" '^Nothing written'
  # The row removed again (the state the first add was previewed in): its confirmation still fits no more.
  kv_get dhtest_kv_expected 'where host!="dhtest-w2" | outputlookup dhtest_kv_expected' >/dev/null
  res=$(w_run ds_ex_apply "${ex[@]}" "ex_confirm=$tok0" | col Result)
  expect "expected row after its removal applies nothing" "$res" '^Nothing written'
  # Adopt.
  ad=("ad_entity=sourcetype|linux|dhtest-w3|cpu|*" "ad_crit=3" "ad_reason=writes test")
  tok=$(w_run ds_ad_plan "${ad[@]}" | col dh_token)
  res=$(w_run ds_ad_apply "${ad[@]}" "ad_confirm=$tok" | col Result)
  expect "adopt applied" "$res" '^Done: Adopt dhtest-w3 .{1,3} cpu \(linux\)$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-w3 | table managed_by profile collection criticality')
  expect "adopted row stored" "$(printf '%s' "$res" | sed -n 2p)" '^ui,continuous,syslog,3$'
  # Test block (task 11b): the block lives in Cribl, so the form writes nothing; it shows the role's
  # cribl_block command. A throwaway block table with one live block on the requested key makes the
  # remove case previewable; it and the admin log stay as they were.
  bk=("bk_action=add" "bk_host=dhtest-w4" "bk_level=source" "bk_target=linux_secure|/var/log/secure.1" "bk_duration=900" "bk_reason=writes test")
  printf 'k,until,reason,set_by
dhtest-w4|linux_secure|/var/log/secure.1,%s,writes test,admin
' "$(($(date +%s) + 3600))" >"$work/dhtest_w_blocks.csv"
  dh_docker cp "$(dh_hostpath "$work/dhtest_w_blocks.csv")" "$DH_CONTAINER:$DH_APP_DIR/lookups/dhtest_w_blocks.csv"
  dh_docker exec -u root "$DH_CONTAINER" chown splunk:splunk "$DH_APP_DIR/lookups/dhtest_w_blocks.csv"
  dh_curl -o "$work/reload.out" -X POST "$DH_MGMT/services/data/lookup-table-files/_reload"
  local bk_sum0 bk_sum1
  bk_sum0=$(dh_docker exec -u root "$DH_CONTAINER" md5sum "$DH_APP_DIR/lookups/dhtest_w_blocks.csv")
  res=$(w_run ds_bk_plan "${bk[@]}" | col source_norm)
  expect "block preview shows the normalized source" "$res" '^/var/log/secure\.\*$'
  res=$(w_run ds_bk_command "${bk[@]}" | col Command)
  expect "block command sets the exact-source block" "$res" "^ansible-playbook site.yml --tags cribl_block --limit homepc -e hl_block_key='dhtest-w4\|linux_secure\|/var/log/secure\.1' -e hl_block_minutes=15 -e hl_block_reason='writes test'\$"
  bk[0]="bk_action=remove"
  res=$(w_run ds_bk_command "${bk[@]}" | col Command)
  expect "block command clears it" "$res" "^ansible-playbook site.yml --tags cribl_block --limit homepc -e hl_block_key='dhtest-w4\|linux_secure\|/var/log/secure\.1' -e hl_block_clear=true\$"
  bk_sum1=$(dh_docker exec -u root "$DH_CONTAINER" md5sum "$DH_APP_DIR/lookups/dhtest_w_blocks.csv")
  expect "the block form left its table as it was" "$bk_sum1" "^${bk_sum0%% *}"
  # An unknown key cannot be removed: the preview says why and there is no command.
  bk=("bk_action=remove" "bk_host=dhtest-w4" "bk_level=host" "bk_target=-" "bk_duration=900" "bk_reason=writes test")
  res=$(w_run ds_bk_command "${bk[@]}" | col Command)
  expect "block command for a key with no active block" "$res" '^Not ready: This has no active test block'
  res=$(kv_get dhtest_kv_admin_log 'stats count')
  expect "admin log: every applied change, nothing for the refused ones (no block rows: task 11b)" "$(printf '%s' "$res" | sed -n 2p)" '^6$'
  # Retire (#48): a whole host with an Ansible row and a UI row; the retire key; undo.
  local rt n0 n1
  res=$(w_run ds_rt_plan "rt_action=retire" "rt_entity=host|*|dhtest-w5|*|*" "rt_reason=writes test" "rt_ticket=-" | ccol check | sort -u)
  expect "retire preview before the key exists" "$res" '^Not ready yet'
  dh_search '| makeresults | eval _key="retire", nonce="seed-w", rotated_at=now() | table _key nonce rotated_at | outputlookup append=true key_field=_key dhtest_kv_nonce' csv >/dev/null
  dh_search '| makeresults count=2 | streamstats count as i | eval st=if(i==1, "syslog", "auth"), entity_id="sourcetype|linux|dhtest-w5|".st."|*", _key=entity_id, level="sourcetype", index="linux", host="dhtest-w5", sourcetype=st, collection="uf", profile="continuous", criticality=2, managed_by=if(i==1, "ansible", "ui"), enabled=1, expected_since=now()-9000 | fields - i st | outputlookup append=true key_field=_key dhtest_kv_expected' csv >/dev/null
  rt=("rt_action=retire" "rt_entity=host|*|dhtest-w5|*|*" "rt_reason=writes test" "rt_ticket=CHG-R")
  tok=$(w_run ds_rt_plan "${rt[@]}" | ccol dh_token | sort -u)
  expect "retire preview gives one token for the host's rows" "$tok" '^[0-9a-f]{32}$'
  res=$(w_run ds_rt_confirm "${rt[@]}" | ccol label)
  expect "retire confirmation offers one Apply line" "$res" '^Apply: retire dhtest-w5: whole host \(2 rows\)$'
  n0=$(kv_get dhtest_kv_nonce 'table nonce' | sed -n 2p)
  res=$(w_run ds_rt_apply "${rt[@]}" "rt_confirm=$tok" | ccol Result | sort | tr '\n' ';')
  expect "retire applied to both rows" "$res" '^Done: Retire dhtest-w5 .{1,3} auth \(linux\);Done: Retire dhtest-w5 .{1,3} syslog \(linux\);$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-w5 | sort entity_id | eval e=sourcetype.":".managed_by.":".enabled.":".retired_by.":".retired_hold.":".retired_ticket.":".if(expected_since<now()-8000, "kept", "new") | stats list(e) as e | eval e=mvjoin(e, " ")' | sed -n 2p)
  expect "retired rows kept, disabled, held, owner kept" "$res" '^"?auth:ui:0:admin:1:CHG-R:kept syslog:ansible:0:admin:1:CHG-R:kept"?$'
  n1=$(kv_get dhtest_kv_nonce 'table nonce' | sed -n 2p)
  if [ -n "$n0" ] && [ "$n0" != "$n1" ]; then echo "PASS retire key rotated by the apply"; else echo "FAIL retire key not rotated ('$n0' -> '$n1')"; WFAIL=1; fi
  res=$(w_run ds_rt_apply "${rt[@]}" "rt_confirm=$tok" | ccol Result)
  expect "retire repeat applies nothing" "$res" '^Nothing written'
  rt=("rt_action=unretire" "rt_entity=host|*|dhtest-w5|*|*" "rt_reason=writes test undo" "rt_ticket=-")
  tok=$(w_run ds_rt_plan "${rt[@]}" | ccol dh_token | sort -u)
  res=$(w_run ds_rt_apply "${rt[@]}" "rt_confirm=$tok" | ccol Result | sort | tr '\n' ';')
  expect "undo applied to both rows" "$res" '^Done: Undo retirement dhtest-w5 .{1,3} auth \(linux\);Done: Undo retirement dhtest-w5 .{1,3} syslog \(linux\);$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-w5 | sort entity_id | eval e=sourcetype.":".managed_by.":".enabled.":".coalesce(retired_by, "-").":".retired_hold.":".if(expected_since<now()-8000, "kept", "new") | stats list(e) as e | eval e=mvjoin(e, " ")' | sed -n 2p)
  expect "undo: the UI row is expected again, the Ansible row waits for the sync" "$res" '^"?auth:ui:1:-:0:new syslog:ansible:0:admin:0:kept"?$'
  res=$(kv_get dhtest_kv_admin_log 'stats count')
  expect "admin log: one row per retired and per restored row" "$(printf '%s' "$res" | sed -n 2p)" '^10$'
  [ "$WFAIL" -eq 0 ] && echo "writes: PASS"
  [ "$WFAIL" -eq 0 ]
}

########## sync: DH Sync expected on a throwaway KV copy of dh_expected (spec 7.2, task 10)
sync() {
  WFAIL=0
  local src=$work/sync_src spl res
  mkdir -p "$src"
  : >"$src/search.spl"
  cat >"$src/ansible.csv" <<'EOF'
entity_id,level,index,host,sourcetype,source,collection,via,hypervisor,profile,interval_secs,max_gap_secs,criticality,owner,site,runbook,description,enabled
,sourcetype,linux,dhtest-s1,syslog,,uf,cribl,,continuous,,,2,taylorb,home,,,1
,sourcetype,linux,dhtest-s2,syslog,,uf,cribl,,continuous,,,1,taylorb,home,,,1
,sourcetype,linux,dhtest-new,syslog,,uf,cribl,,continuous,,,2,taylorb,home,,,1
,sourcetype,linux,dhtest-s5,syslog,,uf,cribl,,continuous,,,2,taylorb,home,,,1
EOF
  cat >"$src/seed.csv" <<'EOF'
entity_id,level,index,host,sourcetype,source,collection,via,hypervisor,profile,interval_secs,max_gap_secs,criticality,owner,site,runbook,description,managed_by,enabled,expected_since,retired_by,retired_hold
sourcetype|linux|dhtest-s1|syslog|*,sourcetype,linux,dhtest-s1,syslog,,uf,cribl,,continuous,,,2,taylorb,home,,,ansible,1,NOW-9000
sourcetype|linux|dhtest-s2|syslog|*,sourcetype,linux,dhtest-s2,syslog,,uf,cribl,,continuous,,,3,taylorb,home,,,ansible,1,NOW-9000
sourcetype|linux|dhtest-s3|syslog|*,sourcetype,linux,dhtest-s3,syslog,,uf,cribl,,continuous,,,2,taylorb,home,,,ansible,1,NOW-9000
sourcetype|linux|dhtest-s4|syslog|*,sourcetype,linux,dhtest-s4,syslog,,uf,,,sporadic,,,3,ops,lab,,,ui,1,NOW-5000
sourcetype|linux|dhtest-s5|syslog|*,sourcetype,linux,dhtest-s5,syslog,,uf,cribl,,continuous,,,2,taylorb,home,,,ansible,0,NOW-9000,admin,1
EOF
  upload sync "$src"
  kv_make dhtest_kv_expected dh_expected
  kv_make dhtest_kv_nonce dh_retire_nonce
  dh_search '| inputlookup dhtest_sync_seed.csv | eval _key=entity_id | fields - dh_* | outputlookup append=true key_field=_key dhtest_kv_expected' csv >/dev/null
  spl=$(conf_lines "$here/../../splunk/apps/$DH_APP/default/savedsearches.conf" | grep -F '|[DH Sync expected]|search = ' | sed 's/.*|search = //')
  if [ -z "$spl" ]; then echo "sync: FAIL DH Sync expected not found"; return 1; fi
  spl=$(printf '%s' "$spl" | sed 's/\<dh_expected_ansible\>/dhtest_sync_ansible.csv/g; s/\<dh_expected\>/dhtest_kv_expected/g; s/\<dh_retire_nonce\>/dhtest_kv_nonce/g')
  res=$(dh_search "$spl" csv | tr -d '\r' | col written)
  expect "first sync writes only the three changes" "$res" '^3$'
  res=$(kv_get dhtest_kv_expected 'stats count')
  expect "no row left dh_expected" "$(printf '%s' "$res" | sed -n 2p)" '^6$'
  res=$(kv_get dhtest_kv_nonce 'stats count')
  expect "the sync created the retire key" "$(printf '%s' "$res" | sed -n 2p)" '^1$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-s5 | table managed_by enabled retired_by retired_hold')
  expect "a row retired in Manage stays retired while the file lists it (held)" "$(printf '%s' "$res" | sed -n 2p)" '^ansible,0,admin,1$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-s1 | table managed_by enabled criticality expected_since')
  expect "an unchanged row keeps its expected_since" "$(printf '%s' "$res" | sed -n 2p)" '^ansible,1,2,1999991000(\.0)?$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-s2 | table enabled criticality expected_since')
  expect "an updated row keeps its expected_since" "$(printf '%s' "$res" | sed -n 2p)" '^1,1,1999991000(\.0)?$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-s3 | table enabled expected_since')
  expect "a row that left the file is retired" "$(printf '%s' "$res" | sed -n 2p)" '^0,1999991000(\.0)?$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-s4 | table managed_by enabled expected_since')
  expect "a UI row stays" "$(printf '%s' "$res" | sed -n 2p)" '^ui,1,1999995000(\.0)?$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-new | eval es=if(abs(expected_since-now())<120, "now", expected_since) | table managed_by enabled es')
  expect "a new row starts its grace now" "$(printf '%s' "$res" | sed -n 2p)" '^ansible,1,now$'
  res=$(dh_search "$spl" csv | tr -d '\r')
  expect "a second sync writes nothing (KV types read back as written)" "$(printf '%s' "$res" | col written)" '^0$'
  expect "the second sync still counts the held row" "$(printf '%s' "$res" | col held)" '^1$'
  res=$(kv_get dhtest_kv_expected 'search host=dhtest-s5 | table enabled retired_hold')
  expect "the held row is still retired after two syncs" "$(printf '%s' "$res" | sed -n 2p)" '^0,1$'
  [ "$WFAIL" -eq 0 ] && echo "sync: PASS"
  [ "$WFAIL" -eq 0 ]
}

case ${1:-} in
  panels) panels ;;
  load) load "${2:-300}" ;;
  writes) writes ;;
  sync) sync ;;
  *) echo "usage: $0 panels | load [hosts] | writes | sync" >&2; exit 2 ;;
esac
