# Handoff: task 8 — UDM syslog through Cribl, and the device probe on pi5

Issue #9 · branch `feat/8-udm-probe`, **stacked on `feat/7-audit-rules`** (needs 3b and 4; the probe
file is read by task 6's `hl_uf_linux_inputs`) · drafted in a cloud session on 2026-11-01.

**State:** implemented and live on pi5 (2026-11-09). Results are in spec §14.16, which supersedes the
checks below where they differ. UniFi remote syslog is `192.168.1.27`, port `5514`, UDP (Taylor set it
in the UI). The UDM side is the Cribl config from task 3b (`in_udm_syslog` on 5514/udp,
host/index/sourcetype/source from the port, `pl_syslog_pre` for the receive time).

**Note:** the issue's title text still describes the retired rsyslog relay. The Cribl addendum
replaced it (pi5 is a UF host; the UDM sends straight to Cribl). This branch deletes the
`syslog_relay` group and its two placeholder task files. Nothing was ever built on pi5 for it, so
there is nothing to clean up there.

## What the branch adds

| Path | What |
|---|---|
| `inventory/hosts.yml`, `site.yml`, `tasks/main.yml` | `syslog_relay` retired; new tags `probe` (deploy) and `probe_remove` (never), on `hl_probe_host` (pi5) |
| `defaults/main.yml`, `vars/main.yml` | `hl_probe_host`, `hl_probe_interval: 60`, `hl_probe_dir`; `hl_probe_devices` = the Splunk server's `syslog_devices` (pi5 isn't in that group) |
| `templates/probe/hl-devprobe.sh.j2` | one `ping -c 1 -W 2` per device → `time=<iso8601> device=<name> ip=<ip> reachable=1\|0 rtt_ms=<ms>`; prints nothing |
| `templates/probe/hl-devprobe.service.j2` / `.timer.j2` | oneshot every 60 s; `StandardOutput/StandardError=null` and `LogLevelMax=warning` so systemd's own per-run lines stay out of the journal (and so out of rsyslog → wd2l); hardened (`ProtectSystem=strict`, only `CAP_NET_RAW`) |
| `templates/probe/hl-devprobe.logrotate.j2` | daily, 7 kept |
| `tasks/probe.yml` / `tasks/probe_remove.yml` | install, start, wait for a line per device / undo exactly what the state file recorded, then check nothing is left |

## Before running

1. Tasks 3b, 4 and 6 are verified (pi5's UF reads `probe.log`).
2. **Taylor's gate (spec §11), done:** UniFi remote syslog is `192.168.1.27`, port `5514`, UDP; CEF arrives.

## Run

```bash
ansible-playbook site.yml --tags probe --limit pi5 -v
ansible-playbook site.yml --tags probe --limit pi5        # expect changed=0
```

## Checks (results in spec §14.16 "Task 8 checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | **UDM events arrive** | `index=network host=udm sourcetype=unifi:syslog earliest=-15m \| stats count latest(_raw) by source` | events with `source=syslog:udm` | no events at all: on HOMEPC `Get-NetFirewallRule -DisplayName 'Docker Desktop Backend' \| Get-NetFirewallPortFilter` (read-only). If UDP 5514 from 192.168.1.1 is blocked, **stop and ask Taylor** before adding the inbound rule (elevation, spec §11). Cribl's live capture (Sources → in_udm_syslog → Live) shows whether packets reach Cribl |
| 2 | **No new firewall rule needed** (§11 row 8) | as check 1 | arrives with the existing Docker rule | — |
| 3 | **A UDM CEF sample** (deferred from task 2, §14.2) | 3 raw events (`index=network host=udm \| head 3 \| table _time _indextime _raw`), **redacted** (MACs, IPs, client and device names), into §14.16 | — | — |
| 4 | **`_time` decision** (§3, §11 row 8) | compare the CEF header timestamp with `_indextime` over a day; does it carry a zone? | keep the receive time (default) unless the device time is reliable **and** zoned. Then remove the Eval in `pl_syslog_pre` and set `timestampTimezone` on `in_udm_syslog` | — |
| 5 | Probe lines arrive | `index=network sourcetype=hl:devprobe earliest=-10m \| stats count latest(reachable) by device` | ≈ 10 per device, `reachable=1` | the UF input (task 6) on pi5: `splunk list monitor` |
| 6 | **Nothing leaks into wd2l** (spec §3 pi5 row, §4.4) | on pi5: `journalctl --since -10min \| grep -i devprobe`; in Splunk: `index=enclave1 host=pi5* devprobe earliest=-30m` | both empty | `LogLevelMax` didn't silence systemd's own lines: switch to a long-running `Type=simple` loop (`while :; do …; sleep 60; done`), so systemd logs only once at boot. Update the E2E row to `systemctl stop hl-devprobe.service` |
| 7 | **UDM host block** (§7.7, §11 row 8) | `--tags cribl_block -e "hl_block_key='udm\|*\|*'" -e hl_block_minutes=5 -e "hl_block_reason='task 8 check'"`; wait 30 s, then watch `index=network host=udm` | no new UDM events until it's cleared or expires; then they return | see task 3b check 12 |
| 8 | Data health | Overview: `udm` and its probe row | OK (after task 10's expected rows) | — |
| 9 | Probe stale | `sudo systemctl stop hl-devprobe.timer`; wait past 180 s | UDM's probe goes stale ("check hl-devprobe on pi5" after task 11b) | restart it: `--tags probe --limit pi5` |
| 10 | `probe_remove` then `probe` | both tags | "nothing is left", then back | — |
| 11 | **wd2l `soak-check.sh`** (§11 row 8 done-when) | on wd2l-recv | green | — |

## Then

- Spec: §14.16 (CEF sample, time decision, firewall, journal); §3 UDM row and §4.4 if the time source
  changed; §12's probe row if check 6 changed the unit.
- `docs/data-health/*.md`: unchanged unless the cause wording moves (task 11b).
- PR: `feat(probe): device probe on pi5, UDM through Cribl, syslog relay retired (task 8)`, `Closes #9`.
