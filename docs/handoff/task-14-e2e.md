# Handoff: task 14 — end-to-end fault injection

Issue #15 · branch `feat/14-e2e`, **stacked on `feat/13-docs`** · drafted in a cloud session on
2026-11-01. This branch adds the empty results page `docs/testing.md` and this procedure. It has no
code.

**Run it last:** every earlier task merged, everything deployed (`ansible-playbook site.yml` twice, the
second with `changed=0`), and data health past its first 2 hours (no PENDING rows from new expected
rows). Learned thresholds need ≥ 3 covered days. Until then, continuous and sporadic rows use the
"learning" defaults (15 min / 24 h), and rows 4 and 6 take that long.

## How to measure

For each row:
1. Note the time T0 (UTC) and inject.
2. Watch the Overview (it refreshes every 60 s), or run:
   `| inputlookup dh_status where host="<host>" | table entity_id status cause since`.
3. The measured time is `since` (when the status changed) − T0. `index=data_health source=dh:transition`
   has the exact time.
4. Undo the injection, and wait until the row is OK again before the next row on the same host.
5. Fill in the row in `docs/testing.md` (Measured, Pass, Notes).

**Mute nothing during the matrix** except in row 15. **Alerts:** rows 1–11 and 13–14 should
raise *DH Alert missing* / *DH Alert tamper* (Triggered Alerts). Row 16 must raise none.

## The rows

| # | Inject | Undo | Notes |
|---|---|---|---|
| 1 | `ansible-playbook site.yml --tags stop --limit wd2l-recv` | `--tags start --limit wd2l-recv` | the marker drives the cause |
| 2 | `ssh taylorb@wd2l-recv.mshome.net` (through HOMEPC) and `sudo systemctl stop SplunkForwarder` | `sudo systemctl start SplunkForwarder` | after the start, the row is annotated with the auid from auditd `SERVICE_STOP` |
| 3 | on HOMEPC: `Stop-VM wd2l-logsrv -TurnOff` | `Start-VM wd2l-logsrv` | the cause comes from Hyper-V 18502; task 11 verified the `VmName` extraction |
| 4 | `-e '{"hl_disabled_inputs":["monitor:///var/log/secure"]}' --tags apps --limit wd2l-recv` (**not** `expected`, so the row stays expected) | rerun `--tags apps --limit wd2l-recv` without `-e` | the sporadic threshold: 24 h while learning, so do it after the learning days, or set `max_gap_secs` with an override first |
| 5 | `-e '{"hl_disabled_inputs":["script://./bin/cpu.sh"]}' --tags apps --limit wd2l-recv` | rerun without `-e` | periodic: 2 × 30 + 60 = 120 s |
| 6 | on wd2l-recv: `sudo service auditd stop` | `sudo service auditd start` | task 7 check 5 confirmed whether this works on EL10 |
| 7 | `--tags stop --limit pi5` | `--tags start --limit pi5` | the UDM's syslog goes straight to Cribl, so it stays OK; its probe goes stale (`probe.log` rides on pi5's UF) |
| 8 | on pi5: `sudo systemctl stop hl-devprobe.timer` | `--tags probe --limit pi5` | |
| 9 | UniFi UI: remote syslog off (**Taylor**) | back on | sporadic threshold, as row 4 |
| 10 | on HOMEPC: `docker stop cribl` | `docker start cribl` | then check the UFs reconnect (`--tags verify`) |
| 11 | Cribl UI → Routes: a new route `r_e2e` at the top, filter `sourcetype=='linux_secure'`, output **devnull** | delete the route, or `--tags cribl --limit homepc` (which replaces `route.yml`) | two findings: the tamper (`cribl_routes`) and linux_secure MISSING |
| 12 | `--tags server -e hl_server_force_restart=true --limit homepc` | — | expect the gap that task 3b check 6 measured (or none, if it was fixed); no MISSING after recovery |
| 13 | elevated PowerShell on HOMEPC: `New-EventLog -LogName HLTest -Source HLTest; Write-EventLog -LogName HLTest -Source HLTest -EventId 1 -Message x; wevtutil cl HLTest` | `Remove-EventLog -LogName HLTest` | the 104 comes from System; **elevation on HOMEPC: ask Taylor** |
| 14 | `--tags cribl_block` with `wd2l-recv\|*\|*`, then `wd2l-recv\|linux_secure\|*`, then `wd2l-recv\|syslog\|/var/log/messages`, 10 min each | `-e hl_block_clear=true` | the label is "test block until hh:mm" |
| 15 | Manage → Mute & thresholds: mute wd2l-recv's whole host for 1 hour | unmute | the children show MUTED |
| 16 | a) `docker exec wd2l-splunk /opt/splunk/bin/splunk restart`; b) put HOMEPC to sleep for 10 min | — | PENDING, then OK; **no alerts** in Triggered Alerts |
| 17 | `ansible-playbook site.yml` twice | — | the second: `changed=0` on every host |
| 18 | `--tags uninstall --limit wd2l-recv`, then `--tags expected`; then `--tags install,apps --limit wd2l-recv` and `--tags expected` | — | the contract passes; the rows retire (`enabled=0`), then return |
| 19 | on wd2l-recv: `soak-check.sh` | — | green; wd2l's dashboard unchanged |

**Restart budget (Splunk):** row 12 (1), row 16a (1), plus any `server` deploys. Cribl restarts are free.

## Then

- Fill in `docs/testing.md`, including the static-check table and findings.
- Update the Obsidian handoff and log (`docs/handoff/README.md` has the text to paste).
- PR: `test(e2e): fault-injection matrix with measured detection times (task 14)`, `Closes #15`.
- Spec §13: close or update each risk the matrix covered (the Cribl restart loss, parsing in Cribl,
  the licence date 2026-12-09).
