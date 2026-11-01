# Testing: fault injection, measured (spec §12)

Filled in by task 14 (issue #15) on the real hosts. Each row: what was injected, what the Overview
must show, the limit, and **what was measured** (the time from the injection to the status or cause
appearing). The procedure for each row is in `docs/handoff/task-14-e2e.md`.

**Run:** date ____ · commit ____ · Splunk 10.6.0.5 · Cribl 4.20.4 · UF 10.6.1.1 · TA_nix 10.3.4 · TA_windows 11.0.3

## The matrix

| # | Inject | Expected on the Overview | Within | Measured | Pass | Notes |
|---|---|---|---|---|---|---|
| 1 | `--tags stop --limit wd2l-recv` | DOWN, "stopped via Ansible, not restarted" | ≤ 3 min | | | |
| 2 | `systemctl stop SplunkForwarder` over ssh (no marker) | DOWN, "heartbeat missing"; after `start`, annotated "stopped by auid=taylorb" | ≤ 3 min | | | |
| 3 | `Stop-VM wd2l-logsrv -TurnOff` | DOWN, "VM off (Hyper-V)" | ≤ 3 min | | | |
| 4 | disable the `/var/log/secure` input | DEGRADED, linux_secure LATE→MISSING, cause "heartbeat OK, input" | threshold | | | |
| 5 | disable TA_nix `cpu` | `cpu` MISSING | ≤ 3 min | | | |
| 6 | `sudo service auditd stop` | linux_audit MISSING + tamper "auditd stopped" | threshold / ≤ 5 min | | | |
| 7 | `--tags stop --limit pi5` | pi5 DOWN, "stopped via Ansible"; UDM syslog stays OK; UDM probe goes stale | ≤ 3 min; probe: threshold | | | |
| 8 | `systemctl stop hl-devprobe.timer` on pi5 | UDM's probe stale ("check hl-devprobe on pi5") | threshold | | | |
| 9 | UDM remote syslog off | UDM MISSING, "reachable, not logging" | threshold | | | |
| 10 | `docker stop cribl` | `cribl` DOWN; every collected row "Cribl DOWN: the real state is unknown"; **no** "Splunk not receiving" banner | ≤ 3 min | | | |
| 11 | add a Drop route in Cribl's UI (no marker) | tamper "possible deliberate blinding", plus the affected sourcetype MISSING | ≤ 15 min | | | |
| 12 | Splunk restart while Cribl buffers | no MISSING rows after recovery; the persistent queue drains (lag spike in SoH); record any gap | recovery + threshold | | | |
| 13 | clear a **test** event log (`New-EventLog HLTest` → `wevtutil cl HLTest`) | tamper 104 on HOMEPC | ≤ 5 min | | | |
| 14 | test block host / sourcetype / source | that level missing, labelled test block | threshold + ≤ 1 min | | | |
| 15 | mute a host | MUTED with its children, expiry shown | ≤ 1 min | | | |
| 16 | restart splunkd; sleep and wake the PC | PENDING, **no** false alerts | — | | | |
| 17 | deploy twice | the second run reports 0 changes | — | | | |
| 18 | `uninstall` then `install` | contract passes; rows retire and return | — | | | |
| 19 | wd2l | `soak-check.sh` + its dashboard unchanged | — | | | |

## Static checks

| Check | Result |
|---|---|
| `ansible-lint --strict`, `yamllint --strict`, `ansible-playbook site.yml --syntax-check` | |
| `splunk btool check` (no findings in the role's apps) | |
| AppInspect on `hl_data_health` | |
| `tests/spl/run.sh` (fixtures + static checks) | |
| `tests/spl/dash.sh writes panels load` and `tests/spl/run.sh --scale 300` (< 3 s / < 10 s) | |

## Findings

(anything that failed, what changed because of it, and the commit)
