# Handoff: task 6 — forwarder apps and input toggles

Issue #7 · branch `feat/6-forwarder-apps`, **stacked on `feat/5-uf-windows`** · drafted in a cloud
session on 2026-11-01 with no access to the hosts.

**State:** **ran live on all four UFs on 2026-11-08; checks 1–10 are in spec §14.14.** The Linux hosts ran from
pi5; HOMEPC's `apps` runs were done by the controller on Taylor's direct approval, in stages (Hyper-V and
Perfmon, then PowerShell, then the big channels). End state: every §4 row with data to send arrives
(`probe.log` waits for task 8), and `verify` is green on all four. Steady licence use is ≈ 529 MB/day; the Windows
backfill was a one-time ≈ 111 MB. **What the live run changed from the table below:** the TA packages are `.spl` and
pinned (`hl_tas`); the breakers were rebuilt from the TAs' `props.conf`; the Windows stanzas set `source` and
`sourcetype`, which Cribl-delivered data would otherwise lose; Perfmon is `PerfmonMk:*`, so check 6's
`Perfmon:*` finds nothing; check 3's SPL needs `rex max_match=0 "(?<l>\n)"`, because `split(_raw,"\n")` returns 1;
check 10's mark is the real 10 GB/day, not 500 MB.

**The body below describes the draft and is superseded by spec §14.14 where they differ.**

## What the branch adds

| Path | What |
|---|---|
| `defaults/main.yml` | the `probe.log` row (`hosts: [pi5]`); `hl_tas` (versions, file names, **empty sha256**); the input-app lists |
| `meta/argument_specs.yml` | the input schema gains an optional `hosts` |
| `vars/main.yml` | `hl_inputs_effective` / `hl_inputs_enabled`: this host's rows after `hl_input_overrides`, `hl_disabled_inputs` and `hosts` |
| `templates/uf/inputs.conf.j2` | one renderer for every app: `disabled = 0`, `index`, `sourcetype` (monitors), `interval` (scripts, perfmon), `renderXml = true` + `start_from = oldest` (event logs) |
| `templates/uf/input_app.conf.j2` | `app.conf` with `[hl] managed = true` |
| `tasks/uf_linux_apps.yml` | Splunk_TA_nix unmodified (swap everything but `local/`, only on a version change) → the role's `local/inputs.conf` in the TA, `hl_uf_linux_inputs`, `hl_uf_wd2l_inputs` → `hl_uf_outputs` → restart only on change → connected → marker |
| `tasks/uf_windows_apps.yml` | the same for Splunk_TA_windows (unpacked with Windows' `tar.exe`) and `hl_uf_windows_inputs` |
| `tasks/uf_*_apps_remove.yml` | removes the role's input apps (`[hl] managed` only) and the role's `local/inputs.conf` in the TA; **keeps `hl_uf_outputs`** unless it's named in `hl_apps_only` (without it the UF sends nothing, heartbeat included) |
| `cribl/local/cribl/breakers.yml` + `in_splunk_tcp.breakerRulesets` | **Cribl now breaks UF data** (§14.7 c), so TA_nix's indexer props no longer apply. The ruleset keeps each TA_nix script run whole, stamped with the current time, and breaks `linux_audit` per record on `msg=audit(` |

**Why everything is in `local/`:** `local/` beats every app's `default/` (spec §5.5). Splunk_TA_windows
sorts before `hl_uf_windows_inputs` (uppercase first), and its default stanzas say `disabled = 1`, so a
`default/` stanza in our app would lose.

## Before running

1. Tasks 4 and 5 are merged.
2. **Pin the TAs** (from `splunk-ta-local`, spec §3): copy `Splunk_TA_nix` 10.3.4 and
   `Splunk_TA_windows` 11.0.3 packages into `ansible/files/packages/` on pi5. Then set `file:` and
   `sha256:` in `defaults/main.yml` `hl_tas` (`sha256sum ansible/files/packages/*.tgz`). Commit that
   change; the play refuses an empty pin.
3. **pi5's wd2l audit sourcetype** (spec §4.4 pi5 row, "confirmed in task 6"): read wd2l's pi5
   role (or `index=wd2l_audit host=pi5 | stats count by sourcetype` in Splunk). Set
   `hl_wd2l_audit_sourcetype:` in `inventory/host_vars/pi5.yml`. Today pi5 falls back to `wd2l:audit`.
4. Redeploy Cribl for the breakers: `--tags cribl --limit homepc` (Cribl restarts; UFs ACK).

## Run

```bash
ansible-playbook site.yml --tags apps --limit wd2l-recv -v
ansible-playbook site.yml --tags apps --limit wd2l-recv     # expect changed=0
# then wd2l-logsrv, pi5, homepc
```

## Checks (recorded in spec §14.14 "Task 6 checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | **Every §4 row arrives** with the right index/host/source/sourcetype | after 10 min: `\| tstats count latest(_time) as t where index IN (linux,windows,network,wd2l_uf_audit) earliest=-15m by index host sourcetype source \| eval age=now()-t` | one row per enabled input per host; probe.log only after task 8 | a missing file monitor: `splunk list monitor` as splunkfwd, then file permissions (CAP_DAC_READ_SEARCH covers reads) |
| 2 | `btool` precedence | on a VM: `sudo -u splunkfwd /opt/splunkforwarder/bin/splunk btool inputs list monitor:///var/log/secure --debug`; on HOMEPC: `& 'C:\Program Files\SplunkUniversalForwarder\bin\splunk.exe' btool inputs list WinEventLog://Security --debug` | `disabled = 0` comes from our app's `local/inputs.conf` | — |
| 3 | **Multi-line TA_nix events whole** (§11 row 6) | `index=linux host=wd2l-recv* sourcetype=ps earliest=-10m \| eval lines=mvcount(split(_raw,"\n")) \| stats count avg(lines)` (ps runs every 30 s, so expect ≈ 20 events with many lines each); repeat for top, df, netstat, interfaces, vmstat | one event per run, many lines each | if the events are single lines, the breaker isn't applied: in Cribl's UI open Sources → in_splunk_tcp → Event Breakers, and check `hl_uf_breakers` is attached and the rule's condition matches. Compare with the TA's `default/props.conf` (`grep -A8 '^\[ps\]'`) |
| 4 | **`_time` right** (§11 row 6) | `index=linux earliest=-15m \| eval lag=_indextime-_time \| stats max(lag) min(lag) by sourcetype` | lag within ±60 s for every sourcetype (the scripted ones use the current time) | a big lag on `linux_audit`: the timestamp anchor; on syslog files: time zone (`useFwdTimezone: true` on in_splunk_tcp) |
| 5 | Windows events whole | `index=windows sourcetype=XmlWinEventLog earliest=-15m \| eval ok=if(match(_raw,"^<Event") AND match(_raw,"</Event>$"),1,0) \| stats count by ok source` | ok=1 only | if Cribl splits the XML, add a rule for `sourcetype=='XmlWinEventLog'` that never breaks (as for TA_nix) and takes the time from `<TimeCreated SystemTime=` |
| 6 | Perfmon | `index=windows sourcetype=Perfmon:* earliest=-10m \| stats count by sourcetype` | CPU and Memory, about 10 each | — |
| 7 | Idempotence | second run | `changed=0`, no restart | — |
| 8 | **Toggle** (spec §5.3 "turn off receipt") | `-e '{"hl_disabled_inputs":["monitor:///var/log/secure"]}' --tags apps --limit wd2l-recv`, then the Overview after the threshold; then rerun without | the stanza leaves `local/inputs.conf`; linux_secure goes LATE → MISSING; it comes back | — |
| 9 | apps_remove | `--tags apps_remove --limit wd2l-recv`, then `--tags apps` | the input apps go and the heartbeat stays; then everything returns | — |
| 10 | Licence | `index=_internal source=*license_usage.log type=Usage earliest=-1h \| stats sum(b) by idx` | well under 500 MB/day in total | lower TA_nix intervals or switch inputs off |

## Then

- Spec: §14.14; §13's "Index-time parsing moved to Cribl" risk, with the breaker as the fix.
- `docs/data-health/*.md`: no macro or panel changed.
- PR: `feat(apps): forwarder apps, TA inputs, toggles and Cribl event breakers (task 6)`, `Closes #7`.
