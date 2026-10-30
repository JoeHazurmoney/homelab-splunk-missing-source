#!/usr/bin/env bash
# Generates the scale fixture for run.sh --scale: <hosts> UF hosts x 20 expected entities each
# (1 host row, 3 log sourcetypes, 16 TA_nix scripted sources), their tracker state, forwarder
# rows, baselines, a few mutes, blocks and tamper findings. Times are relative to NOW.
# Usage: tests/spl/gen-scale.sh <hosts> <out-dir>
set -euo pipefail
hosts=${1:?hosts}
out=${2:?out-dir}
mkdir -p "$out"
awk -v hosts="$hosts" -v out="$out" 'BEGIN {
  E = out "/expected.csv"; SF = out "/state_fast.csv"; SS = out "/state_slow.csv"; F = out "/fwd.csv"
  B = out "/baseline.csv"; O = out "/overrides.csv"; T = out "/tamper.csv"; K = out "/blocks.csv"
  print "level,index,host,sourcetype,source,collection,profile,interval_secs,criticality" > E
  print "index,host,sourcetype,source,first_seen,last_indextime,last_eventtime,last_count,lag" > SF
  print "index,host,sourcetype,source,first_seen,last_indextime,last_eventtime,last_count,lag" > SS
  print "host,last_heartbeat,last_marker_action,last_marker_time,last_marker_by" > F
  print "entity_id,learned_gap_secs,days" > B
  print "entity_id,mute_until,reason,ticket" > O
  print "host,time,indicator,detail" > T
  print "k,until,reason,set_by" > K
  n = split("cpu:30 ps:30 vmstat:60 top:60 interfaces:60 netstat:60 df:300 openPorts:300 lastlog:300 package:3600 Unix:Service:3600 Linux:SELinuxConfig:3600 Unix:SSHDConfig:3600 Unix:UserAccounts:3600 Unix:Uptime:86400 Unix:Version:86400", TA, " ")
  for (i = 1; i <= hosts; i++) {
    h = sprintf("scale-h%03d.mshome.net", i); s = sprintf("scale-h%03d", i)
    hb = (i % 10 == 0) ? "NOW-400" : "NOW-10"
    print "host,," h ",,,uf,heartbeat,,1" > E
    print s "," hb "," ((i % 25 == 0) ? "stop,NOW-420,taylorb" : ",,") > F
    split("syslog:/var/log/messages:continuous linux_secure:/var/log/secure:sporadic linux_audit:/var/log/audit/audit.log:continuous", L, " ")
    for (j = 1; j <= 3; j++) {
      split(L[j], p, ":")
      print "sourcetype,linux," h "," p[1] ",,uf," p[3] ",,2" > E
      t = (j == 1 && i % 7 == 0) ? "NOW-5000" : "NOW-60"
      print "linux," s "," p[1] "," p[2] ",NOW-864000," t "," t ",10,0" > SF
      print "linux," s "," p[1] "," p[2] ".1,NOW-1728000,NOW-90000,NOW-90000,10,0" > SS
      if (i % 2 == 0) print "sourcetype|linux|" s "|" p[1] "|*,1200,14" > B
    }
    for (j = 1; j <= n; j++) {
      m = split(TA[j], q, ":"); iv = q[m]; st = q[1]; for (x = 2; x < m; x++) st = st ":" q[x]
      print "source,linux," h "," st "," st ",uf,periodic," iv ",3" > E
      t = (j == 3 && i % 11 == 0) ? "NOW-5000" : "NOW-20"
      print "linux," s "," st "," st ",NOW-864000," t "," t ",1,1" > SF
    }
    if (i % 50 == 0) print "host|*|" s "|*|*,NOW+3600,scale mute,CHG-" i > O
    if (i % 60 == 0) print s ",NOW-430,1102 security log cleared,EventCode=1102" > T
    if (i % 100 == 0) print s "|*|*,NOW+600,scale block,admin" > K
  }
}'
