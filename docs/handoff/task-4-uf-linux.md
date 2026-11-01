# Handoff: task 4 — Linux UF on wd2l-logsrv, wd2l-recv and pi5 → Cribl

Issue #5 · branch `feat/4-uf-linux`, **stacked on `feat/3b-cribl`** (rebase onto `main` after 3b
merges) · drafted in a cloud session on 2026-11-01 with no access to the hosts.

**State:** written; yamllint, ansible-lint (production) and shellcheck clean; `--syntax-check` OK. The tamper
rules and `hl_uf_outputs` templates were rendered locally. **Nothing has run on a host.**

## What the branch adds

| Path | What |
|---|---|
| `inventory/hosts.yml` | pi5 joins `uf_linux` (it stays in `syslog_relay` until task 8 retires the group) |
| `splunk_indexer` → `hl_collector` | defaults, argument specs, `group_vars/uf_windows.yml` (127.0.0.1) |
| `defaults/main.yml` | UF version/build/home/user, the three pinned packages (spec §14.3), `hl_uf_mgmt`, the state folder, `hl_uf_linux_packages: [sysstat]`, `hl_audit_arches`, `hl_server_host` |
| `templates/uf/hl_uf_outputs/default/*.j2` | `outputs.conf` (→ `hl_collector:9997`, token, `useACK = true`), `limits.conf` (`maxKBps = 0`), `web.conf` (`mgmtHostPort`), `app.conf` (`[hl] managed`) |
| `templates/uf/zz-hl-uf-tamper.rules.j2` | spec §5.4 rules, b32 + b64, only for paths that exist |
| `tasks/uf_linux_install.yml` | baselines (nouser, `auditctl -l`, unit list) → sysstat → rpm (sha256 on the controller and the host) → FIPS lines (only if `fips_enabled=1`; a missing file means not FIPS) → `user-seed.conf` (only if no `etc/passwd`) → `hl_uf_outputs` → boot-start → tamper rules → start → connected → FIPS mode check → marker |
| `tasks/uf_linux_outputs.yml` | shared with task 6's `apps`; drops the UF's stale encrypted token from `local/outputs.conf` when `default/outputs.conf` changes |
| `tasks/uf_linux_connected.yml` | the UF's splunkd.log: the latest `Connected to idx=<collector>:9997` is newer than the latest token refusal; then the host's `_internal` in Splunk < 120 s old (REST search delegated to homepc) |
| `tasks/uf_linux_tamper.yml` | render, `augenrules --load` on change, then check `hl-uf-config` rules are loaded **and wd2l's rule count is unchanged** |
| `tasks/uf_linux_uninstall.yml` | spec §5.6 order, then the full contract (rpm, home, units, polkit, user/group, mail, tamper, `auditctl` vs the baseline, new nouser paths vs the baseline, packages) |
| `tasks/uf_linux_service.yml` | start/stop/restart (marker: before a stop, after a start), status (service, rpm, build, last connect, last refusal, apps, FIPS) |
| `tasks/verify.yml` | Linux UF running + connected + seen in Splunk; Cribl healthy |
| `tasks/download.yml` | `get_url` with the pinned sha256 into `ansible/files/packages/` |
| `tasks/main.yml` | `become: true` on every `uf_linux` import |

## Before running

1. Task 3b is merged and Cribl is healthy (`--tags verify --limit homepc`).
2. On pi5: `ansible-playbook site.yml --tags download --limit pi5` (about 700 MB in total; the sha256 is checked).
3. **sudo:** the tasks use `become`. If sudo asks for a password on a VM or on pi5, add `-K`.
4. **pi5 audit ABIs:** `grep -o 'arch=b[0-9]*' /etc/audit/rules.d/wd2l.rules | sort -u` on pi5. If wd2l
   uses only `b64` there, add `hl_audit_arches: [b64]` to `inventory/host_vars/pi5.yml`.
5. Start the VMs (they stay manually started).

## Run (one host at a time, in this order)

```bash
ansible-playbook site.yml --tags install --limit wd2l-recv -v
ansible-playbook site.yml --tags install --limit wd2l-recv        # expect changed=0
ansible-playbook site.yml --tags status  --limit wd2l-recv
# then wd2l-logsrv, then pi5
```

## Checks (record in spec §14.10 "Task 4 checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | Install path | first run | all green; the `connected` and `_internal` waits pass | read the failing task; the most likely failure is `boot-start` flags (try without `--answer-yes --no-prompt`, keep `--accept-license`) |
| 2 | **Token encryption doesn't flap** (§11 row 4) | second run, plus `sudo grep -rn token /opt/splunkforwarder/etc/apps/hl_uf_outputs/` | `changed=0`; default/ has plaintext and local/ has `$7$…`/`$8$…` | if the UF rewrote `default/outputs.conf` itself, move the template to `local/`, keep a sha256 of the rendered text in the state file, and compare that instead of the file |
| 3 | Tamper rules | `sudo auditctl -l \| grep hl-` | 10 rules on the VMs (5 paths × 2 ABIs); wd2l's count unchanged (the play checks) | `augenrules` error about `arch=b32` → see "Before running" 4 |
| 4 | **CLI over UDS with outputs configured** (§14.2) | `--tags status`; on the host, `sudo -u splunkfwd /opt/splunkforwarder/bin/splunk status` and `sudo ss -ltnp \| grep -E '8089\|8090'` | status works; record whether anything listens on TCP | if the CLI needs TCP mgmt, note it; `status` reads only systemd and the log, so the role doesn't depend on it |
| 5 | FIPS (VMs) | the play runs `splunk show fips-mode` | `FIPS mode enabled.` | check `etc/splunk-launch.conf` was written **before** the first start (`hl_uf_fresh`) |
| 6 | pi5 not FIPS | pi5's run | the FIPS tasks are skipped, no error | — |
| 7 | **`verify` catches a wrong token** (§11 row 4) | `--tags install --limit wd2l-recv -e vault_hl_s2s_token=wrong-on-purpose` | fails at "Wait for the UF to connect" (refusal) | if it passes, the refusal wording differs: `grep -i -E 'token\|closed' splunkd.log` and widen the pattern in `uf_linux_connected.yml` |
| 8 | Token rotation recovers | rerun without `-e` | outputs changes, the stale local token is dropped, the UF reconnects | — |
| 9 | **When shutdown lines and auditd `SERVICE_STOP` arrive** (§14.2, deferred here) | a) `--tags stop --limit wd2l-recv`, wait 3 min, `--tags start`; b) `sudo systemctl stop SplunkForwarder`, wait 3 min, `start`. In Splunk: `index=_internal host=wd2l-recv* source=*splunkd.log ("Shutting down" OR "shutting down") \| eval lag=_indextime-_time \| table _time _indextime lag _raw` and `index=linux host=wd2l-recv* sourcetype=linux_audit SERVICE_STOP` (the audit input is task 6: until then, read `/var/log/audit/audit.log` on the host) | write down both lags | input for task 11's "annotated after recovery" cause |
| 10 | Markers | `index=data_health source=dh:marker \| table _time action target_host by run_id` | install/stop/start rows with `target_host=wd2l-recv` | HEC 8088 not reachable from pi5, or the token is wrong (`curl -k https://192.168.1.27:8088/services/collector/health` from pi5) |
| 11 | Data health sees it | Overview: wd2l-recv's heartbeat row OK within 3 min | yes | `dh_fwd` heartbeat comes from `_internal` metrics by host |
| 12 | **Uninstall contract** | `--tags uninstall --limit wd2l-recv` | the contract passes; `auditctl -l` equals the baseline | a new nouser path: the play prints up to 20; usually a leftover owned by splunkfwd's uid |
| 13 | Reinstall | `--tags install --limit wd2l-recv` | as check 1 | — |
| 14 | wd2l | `soak-check.sh` on wd2l-recv after all three hosts | green | — |
| 15 | 3b's restart-loss test | now possible: task 3b's check 6 | see 3b | — |

**Restart budget:** none on Splunk (3b's check 6 has its own).

## Then

- Spec: §14.10 with the results; §14.2: the deferred items answered; §5.3 `install`: whatever check 1/2/4
  changed.
- PR: `feat(uf): Linux UF install, uninstall, service control, markers and tamper rules (task 4)`,
  body `Closes #5` plus the check table.
- Rebase `feat/5-uf-windows` onto `main`.
