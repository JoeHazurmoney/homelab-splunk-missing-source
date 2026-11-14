# Testing

Two kinds of tests: suites you run from a checkout, and the fault-injection matrix (spec §12) run on
the real hosts. Results from each task's own checks are in [spec §14](specs/2026-10-30-design.md#14-spike-findings-2026-10-30).

## CI

Two required checks run on every pull request (`.github/workflows/`). GitHub can't protect `main` on
this private repo, so the rule is kept by convention: merge only when both are green, and
`.githooks/pre-push` blocks direct pushes to `main` (enable it once per clone with
`git config core.hooksPath .githooks`).

| Workflow | Runs | Proves |
|---|---|---|
| `lint.yml` | `yamllint --strict .`; `ansible-lint --strict` (profile `production`) from `ansible/` after installing `requirements.yml`; `shellcheck` on every tracked `*.sh`; PSScriptAnalyzer (errors and warnings) on every `*.ps1` / `*.psm1` | the YAML, the role, the shell and PowerShell scripts are clean |
| `pr-issue-link.yml` | the PR title is a Conventional Commit, and the body says `Closes #<n>` for an open issue | every change is tied to an issue |

No CI job reaches Splunk, Cribl or the hosts; the suites below need them.

## The same lint on pi5

`scripts/bootstrap-pi.sh` installs yamllint and ansible-lint (`~/.venvs/ansible-lint`, linked into
`~/.local/bin`):

```bash
cd ~/homelab-splunk-missing-source && yamllint --strict .
cd ansible && ansible-lint --strict && ansible-playbook site.yml --syntax-check
```

## Test suites

| Suite | Where and how | Proves |
|---|---|---|
| `tests/spl/run.sh` | Git Bash on HOMEPC, with `hl_data_health` deployed (`--tags server`, or `tests/spl/dev-deploy.sh`, which swaps the app in without restarting splunkd). `tests/spl/run.sh` runs everything; `tests/spl/run.sh '1*'` some cases; `--scale [hosts]` the generated scale case (300 hosts by default). It reads the admin password from `DH_PASS_FILE` and never prints it. A full run needs `node`: it checks that the committed Manage view is the output of `tools/gen_dh_manage.js` (edit the generator, never `dh_manage.xml`) | every evaluator and macro fixture case under `tests/spl/cases/` gives the expected status, cause and transitions (run at a fixed clock). A full run also checks that lookup names resolve (`lookup-names`, `lookup-names-static`), that no search looks back past the indexes' retention (`retention-windows`), the saved searches' settings against `savedsearches.expect.csv`, the views statically (`dash_check.py`), and that every macro, panel and input is documented in `docs/data-health/` and nothing documented is gone. It uploads `dhtest_*` lookups and removes them; it writes nothing to KV or an index |
| `tests/spl/dash.sh panels` | as above | every read-only data source of every view runs without errors, and each drilldown returns the field it passes on |
| `tests/spl/dash.sh load [hosts]` | as above | the Overview's searches over the 300-host fixture load in under 3 s and match the generated mix |
| `tests/spl/dash.sh writes` | as above | Manage's writes end to end on throwaway collections: preview, confirm, apply, the admin log, that a repeated or stale confirmation writes nothing, and the test-block command |
| `tests/spl/dash.sh sync` | as above | *DH Sync expected*, as written, upserts by `_key`, so rows it doesn't change stay as they were |
| `tests/server/hl_server_app_test.sh` | on Linux: `sh tests/server/hl_server_app_test.sh ansible/roles/homelab_splunk/files/hl_server_app.sh` (Git Bash's `sha256sum` output breaks it) | the `server` helper's handling of `local/inputs.conf` across a token rotation: stale encrypted token copies dropped, a retired `splunktcptoken` stanza removed, stanzas the role never shipped left alone, no change when nothing changed |
| `tests/cribl/hl_cribl_config_test.sh` | anywhere with a POSIX sh, for example in the Cribl container: `docker cp` the helper and the test to `cribl:/tmp/`, then `docker exec cribl sh /tmp/hl_cribl_config_test.sh /tmp/hl_cribl_config.sh` | the `cribl` helper's file swap: changes reported and copied, the pushed-files record left pending until committed, dropped files deleted, files the role never pushed kept, a retry after a revert copies the file back. It uses a throwaway volume folder |

`tests/spl/` uses throwaway objects named `dhtest_*` and removes them on exit.

## Fault-injection matrix (spec §12)

Task 14 (issue #15) ran it on the real hosts. Each row: what is injected, what the Overview must
show, the limit, and what was measured (the time from the injection, T0, to the status or cause
appearing in `index=data_health source=dh:transition`). Rows 9, 13 and 16b need Taylor at the
UniFi UI, an elevated PowerShell and the PC's power menu, so they run last and are marked pending
until then.

**Why the times exceed the first limits.** An entity's age is taken at the fast tracker's last run
(`dh_asof`), and the evaluator runs once a minute, so each status lands up to about 2 minutes after
its threshold is crossed: a heartbeat (90 s) reads LATE at about 2.5–3.5 min and DOWN at about
4–4.5 min after a stop; a row with threshold *t* reads LATE at about *t* + 2 min and MISSING at
about 2*t* + 2 min. The Within column gives the limits restated from these measurements (the first
limit in brackets); spec §12 has the same.

**Run:** 2026-11-10 01:39Z to 2026-11-11 05:00Z; row 9 2026-11-13 00:01–03:19Z (rows 13 and 16b pending) · branch `feat/14-e2e`
from `8984bce` (= main `d4a7930`), with each fix in Findings deployed as it was made · Splunk 10.6.0.5 ·
Cribl 4.20.4 · UF 10.6.1.1 · TA_nix 10.3.4 · TA_windows 11.0.3

| # | Inject | Expected on the Overview | Within | Measured | Pass | Notes |
|---|---|---|---|---|---|---|
| 1 | `--tags stop --limit wd2l-recv` | DOWN, "Stopped with Ansible at `<time>` by `<user>` and not started again" | ≤ 5 min (was ≤ 3 min) | LATE 2 min 25 s, DOWN 4 min 25 s | Pass | T0 = UF stop 01:58:35Z; the cause showed from LATE on, on the host and every child. DH Alert missing fired. The `stop` marker suppressed the SERVICE_STOP finding |
| 2 | `systemctl stop SplunkForwarder` over ssh (no marker) | DOWN, "The Splunk agent stopped reporting: the host is down or cut off from Cribl (port 9997) or the agent crashed or was stopped outside Ansible"; after `start`, the tamper finding "SERVICE_STOP SplunkForwarder", with sudo's `USER_CMD` naming `AUID="taylorb"` | ≤ 5 min (was ≤ 3 min) | LATE 3 min 24 s ("reports late"), DOWN 4 min 24 s | Pass | Run twice: the first run's finding was suppressed by row 1's `start` marker 3 min earlier (900 s window, by design), so it was repeated 16 min clear of markers: finding unsuppressed, DH Alert tamper fired. DH Alert missing was throttled (1 h per entity after row 1) |
| 3 | `Stop-VM wd2l-logsrv -TurnOff`; then `Stop-VM wd2l-logsrv` (guest shutdown) | DOWN, "The VM is off: Hyper-V event 18502 (turned off) at `<time>`"; for the guest shutdown "… 18504 (shut down by the host) …" | ≤ 5 min (was ≤ 3 min) | TurnOff: LATE 3 min 15 s, DOWN 4 min 15 s. Shutdown: LATE 3 min 4 s, DOWN 4 min 4 s | Pass | `Stop-VM` without `-TurnOff` goes through the Shutdown IC and logs 18506 + **18504**, not 18508 (18508 needs a poweroff inside the guest; WSL's utility VM logged one during this run). DH Alert missing fired once (throttled the second time). Reboot tamper noise: see Findings |
| 4 | disable the `/var/log/secure` input | DEGRADED, linux_secure LATE→MISSING, "The Splunk agent works but this input stopped: its file is unreadable or was moved or rotated or auditd or rsyslog stopped or audit rules were removed" | threshold (+ ≤ 2 min) | against a 300 s override: LATE 6 min 18 s, MISSING 11 min 18 s | Pass | The row is sporadic (24 h while learning), so a temporary 300 s limit was set with Manage's own form over REST, and cleared afterwards. `sudo -n true` every minute kept the file busy. The override itself made the quiet row MISSING at once (and alert), before the injection |
| 5 | disable TA_nix `cpu` | `cpu` MISSING, "The Splunk agent works but this input stopped: …" | ≤ 6 min (was ≤ 3 min) | LATE 3 min 4 s, MISSING 5 min 4 s | Pass | Threshold 120 s; MISSING is 2 × 120 s + the evaluator lag. No alert: criticality 3, and DH Alert missing takes 1–2 only |
| 6 | `sudo service auditd stop` | linux_audit MISSING, "Possible deliberate blinding: auditd stopped (DAEMON_END) auid=`<n>` at `<time>` just before the data stopped", + tamper "auditd stopped (DAEMON_END)" | threshold / ≤ 5 min | tamper alert 4 min 57 s; linux_audit LATE 16 min 57 s, MISSING 31 min 57 s (threshold 900 s, continuous default) | Pass | T0 = auditd stop 03:26:03Z; finding `wd2l-recv\|audit_daemon_end\|1794281100` "auditd stopped (DAEMON_END) auid=1000", unsuppressed; DH Alert tamper 03:31, DH Alert missing 03:59. auditd started again 03:58:29Z (wd2l's audit gap on wd2l-recv: 32 min 26 s, expected). The unmarked start reloaded the rules: an `audit_config_change` finding (295 events), DH Alert tamper 04:01 (R12) |
| 7 | `--tags stop --limit pi5` | pi5 DOWN, "Stopped with Ansible at `<time>` by `<user>` and not started again"; the UDM's syslog stays OK; pi5's `hl:devprobe` row goes LATE then MISSING with the same cause | ≤ 5 min; probe: threshold | DOWN 4 min 28 s; `hl:devprobe` LATE 3 min 28 s, MISSING 6 min 28 s | Pass | A UDM event was indexed at 03:15:21Z with pi5's UF stopped. The `udm` host row (probe liveness) is sporadic, 24 h, so it stays OK. DH Alert missing fired for the host row and the probe row |
| 8 | `systemctl stop hl-devprobe.timer` on pi5 | pi5's `hl:devprobe` row LATE, "The device probe (hl-devprobe on pi5) stopped reporting on this device" (the `udm` host row stays OK) | 180 s + ≤ 2 min (was ≤ 1 min) | LATE 4 min 42 s after the last probe line (4 min 38 s after the stop) | Pass | Action "Check hl-devprobe on pi5: systemctl status hl-devprobe.timer (or rerun: … --tags probe --limit pi5)". Restored with `--tags probe` |
| 9 | UDM remote syslog off | the `udm` syslog row LATE then MISSING, "The device answers the network probe but sends no logs: its logging settings probably changed" | threshold (+ ≤ 2 min) | against a 900 s override: LATE ≤ 16 min 21 s, MISSING ≤ 31 min 21 s (from the UDM's last event, 00:37:39Z; T_off is no earlier); OK 1 min 52 s after the first event back | Pass | Taylor, 2026-11-13: the row is sporadic (learned ≈ 14–16 h), so it ran against a temporary 900 s limit set with Manage's form at 00:01:30Z. Taylor gave no times after the first Wi-Fi toggle (23:57/23:59Z on 11-12) and reported it "worked exactly like expected". The records pin the detection, not T_off or T_on: UniFi logs nothing over syslog when remote logging is switched, and no test toggle after the first can be picked out (the test phone's 00:22–00:32Z events move with a second phone and a watch; then nothing from it until 03:32Z). Last UDM event 00:37:39Z, first back 03:17:08Z, and Cribl's UDP input received nothing in between, so Cribl dropped nothing. Bracket: T_off ≥ 00:37:39Z; T_on 01:12:39–03:17:08Z. Transitions: OK→LATE 00:54:00Z and LATE→MISSING 01:09:00Z, both with the expected cause (`probe_no_logs`); MISSING→OK 03:19:00Z. DH Alert missing 01:10:01Z (the next two runs throttled). The `udm` host row stayed OK (pi5's probe: 226 lines, all `reachable=1`). The limit then stayed on for 25.5 h: see Findings |
| 10 | `docker stop cribl` | `cribl` DOWN, "Cribl DOWN: nothing from Cribl itself so every collected stream is unknown"; every collected row "Cribl DOWN: the real state is unknown (this data passes through Cribl and Cribl is not reporting)"; **no** "Splunk not receiving" banner | ≤ 6 min (was ≤ 3 min) | `cribl` LATE 3 min 6 s, DOWN 5 min 6 s | Pass | T0 = container exit 03:01:54Z. From 03:07 all 27 non-OK `via=cribl` rows read the relay cause; before that the UF host rows read `hb_late`/`hb_missing` (and DH Alert missing fired for the four UF host rows with that cause at 03:07, then for `cribl` at 03:08). Banner "Up to date" throughout (HEC flows). While LATE the `cribl` row read "This stream stopped while the host still sends others": fixed (Findings). Restarted 03:07:44Z; UFs reconnected after 7 s (wd2l-recv) to 5 min 8 s (homepc, the UF's own backoff); all OK 03:14; `--tags verify` green |
| 11 | add a Drop route in Cribl's UI (no marker) | tamper finding "Cribl routes create (`<route>`) by admin"; the affected sourcetype MISSING, "Possible deliberate blinding: Cribl routes create (`<route>`) by admin at `<time>` just before the data stopped" | ≤ 15 min | finding 4 min 11 s (DH Alert tamper 5 min); linux_secure LATE 6 min, MISSING 11 min | Pass | Through Cribl's API as admin (a throwaway playbook): route `r_e2e` first, filter `sourcetype=='linux_secure'`, output `devnull`, at 03:21:00Z. wd2l-recv's linux_secure had a 300 s limit for the test (Manage's form, cleared after) and `sudo -n true` every minute. Finding `cribl\|cribl_routes\|1794367200`, unsuppressed, kept in `dh_tamper`; the restore's first `--tags cribl` run (its `cribl` marker 11 min 48 s after the route was added) later marked it suppressed (Findings). It first read "Cribl routes reorder (r_uf)": fixed (Findings). DH Alert missing fired. `--tags cribl` does **not** revert an API or UI edit (by design: it compares with its own record); its load check failed on the extra route. Restored by the API with the saved routes, then `--tags cribl` passed with `changed=0` and no Cribl restart (no UDP gap) |
| 12 | Splunk restart while Cribl buffers | no MISSING rows after recovery; through the `server` tag no UF data lost, UF data up to ≈ 2.5 min late, UDP syslog lost during the ≈ 2 min hold; record any gap | recovery + threshold | hold 2 min 13 s; PENDING 03:41–03:46; all OK 8 min 11 s after the run started | Pass | `--tags server -e hl_server_force_restart=true --limit homepc` 03:37:27–03:40:20Z: `cribl_hold` 03:38:00Z, splunkd down 03:38:09Z, up 03:40:03Z, `cribl_release` 03:40:13Z. The banner read "On hold: … indexed nothing new for 146 s", then "Catching up …" with every row PENDING, then "Up to date" at 03:46:11Z. No transition, no alert, no skipped search. UF data: every minute's `cpu`/`PerfmonMk:CPU` count unchanged on all four hosts (nothing lost); at most 136 s late. No UDM event fell in the hold (it is sporadic), so the UDP loss could not be counted |
| 13 | clear a **test** event log (`New-EventLog HLTest` → `wevtutil cl HLTest`) | tamper finding "104 event log HLTest cleared by `<user>`" on HOMEPC | ≤ 5 min | pending | pending (Taylor) | Needs an elevated PowerShell on HOMEPC; `Remove-EventLog -LogName HLTest` after |
| 14 | test block host / sourcetype / source | that level missing, labelled "test block until hh:mm", cause "Test block until `<time>` (data dropped on purpose): `<reason>`" once the row goes LATE | threshold + ≤ 2 min after the drop starts (was ≤ 1 min) | host: `cpu` LATE 3 min 52 s (threshold 120 s), MISSING 5 min 52 s; sourcetype: 7 min 3 s; source: 6 min 53 s (both against 300 s limits) | Pass | On wd2l-recv, 10 min each with `--tags cribl_block`: `wd2l-recv\|*\|*`, `wd2l-recv\|linux_secure\|*`, `wd2l-recv\|syslog\|/var/log/messages`. Each dropped only its own level: the host row (heartbeat) stayed OK under the host block, and only the named row was labelled under the other two. linux_secure and `/var/log/messages` got temporary 300 s limits (Manage's form, cleared after) so they go LATE within the block. The drop started 28–45 s after the play's `until` time (the API write plus Cribl's refresh). Every Cribl lookup change was a suppressed finding (`cribl_block` marker). No alert (the children that went LATE are criticality 3, or LATE only). At the end both Cribl's table and the mirror held the header only |
| 15 | mute a host | MUTED with its children, expiry shown | ≤ 1 min | 32 s (MUTED); unmuted rows OK within 47 s | Pass | wd2l-recv, 1 h, with the searches Manage's form runs (plan, then Apply), over REST. All 24 rows MUTED at the next evaluator run, cause "Muted until 2026-11-11 05:29 GMT: `<reason>`"; Host detail shows "muted until 22:29 MST (`<reason>`)". Unmuted the same way; `dh_overrides` empty after. The browser check of the form is the controller's |
| 16 | restart splunkd; sleep and wake the PC | PENDING, **no** false alerts | — | splunkd restart: no PENDING needed (down 9 s), no alert. Sleep and wake: pending | 16a Pass; 16b pending | 16a: `docker exec -u splunk wd2l-splunk /opt/splunk/bin/splunk restart` (outside the role, so no Cribl hold) at 04:31:34Z: down 04:31:40–04:31:49Z. The banner stayed "Up to date" and every row OK: the tracker's gap was shorter than the 150 s resume gap, so nothing was held, and nothing alerted. One 30-s sample sent just before the shutdown was lost on wd2l-logsrv, wd2l-recv and homepc (≈ 10–25 s of UF data; pi5 complete), more than the 3 s §13 quoted. Row 12 covers the long restart (PENDING 5 min, no alert). 16b (sleep and wake HOMEPC) is Taylor's |
| 17 | deploy twice | the second run reports 0 changes | — | run 1: `changed=1` (homepc); run 2: `changed=0` on all four hosts | Pass | Run 1's change: the container's `dh_expected_ansible.csv` differed from main's render (most likely left by a branch's earlier push); the sync then wrote 0 rows. Each run posts the two `cribl` markers by design |
| 18 | `uninstall` then `install` | contract passes; after `uninstall` alone the host's rows stay expected; `hl_expected: false` plus `--tags expected` retires its UF-derived rows (`dh_extra_expected` rows stay); `hl_expected` back to `true` plus `--tags expected` brings them back | — | wd2l-recv: contract passed, rows stayed, 23 retired, 23 back and OK at the next run. Probe: removed and back | Pass | wd2l-recv, with the STIG rules loaded: "uninstall contract passed: rpm=absent … auditctl_diff=0, nouser_new=0, units_new=0"; the STIG rules stayed loaded and wd2l's 54 rules were untouched. The host's 24 rows stayed expected and went DOWN; they read "stopped outside Ansible" until a fix (Findings) made it "Uninstalled with Ansible at `<time>` by `<user>` and not installed again". `hl_expected: false` went into the host's `host_vars` (an `-e` would apply to every host), then `--tags expected` retired 23 rows; its `wd2l:health` row (added on Manage) and the `dh_extra_expected` rows stayed. `--tags install,apps,audit_rules --limit wd2l-recv`, the line removed, `--tags expected`: 23 rows back, all OK. The new UF re-read its files from the start (≈ 17,000 duplicate events, 596 of them in `wd2l_uf_audit`). Probe: `--tags probe_remove --limit pi5` removed all its files and the timer; `--tags probe --limit pi5` put them back; wd2l's rules and `90-wd2l.conf` on pi5 unchanged |
| 19 | wd2l | `soak-check.sh` + its dashboard unchanged | — | unchanged: no `gap`, `time_status`, `sender_boot_reset` or `gaps_forgotten` record; the same 3 unbalanced streams; rule files and audit counts as before | Pass | `soak-check.sh` from 01:39Z before the first injection (baseline) and over the whole run (2026-11-12 14:26Z). wd2l's own records saw only what the matrix did to it, and recovered each time: row 3 (`stream_lost` ×2 and "nothing arriving" while its sender wd2l-logsrv was off; "the sender stopped cleanly" for the guest shutdown), rows 12 and 16a ("SIEM delivery: spool growing" while splunkd restarted, OK within 1 min 20 s), and one 12 s "nothing arriving" on pi5 during a `server` run from pi5 (§13's known risk). Every new stream balanced; the unbalanced ones are the same 3 with the same counts (`3033f78a…` 1549/1038, `f3996819…` 671/661, `00ebbd36…` 297/207). Receiver health as before (pi5 time `alarm`, the known one). `wd2l.rules`, `wd2l-quadlet.rules` and `90-wd2l.conf` mtimes and `auditctl -l` counts (pi5 162 / 74 wd2l / 10 hl, wd2l-logsrv 134/42/10, wd2l-recv 146/54/10; enabled 1, lost 0) equal the preflight's. No file in wd2l's Splunk app changed; its dashboard's sha256 is unchanged |

### Static checks for the run

| Check | Result |
|---|---|
| `ansible-lint --strict`, `yamllint --strict`, `ansible-playbook site.yml --syntax-check` | Pass: on pi5, rc 0 each; ansible-lint (profile `production`) 0 failures, 0 warnings in 75 files. `shellcheck` 0.11.0 on all tracked `*.sh`: no findings |
| `splunk btool check` (no findings in the role's apps) | Pass: `docker exec -u splunk wd2l-splunk … btool check` lists 30 lines, all in wd2l's own `wd2l/local/savedsearches.conf` (`alert_type`, `alert_comparator`, `alert_threshold` "Invalid key" in 10 stanzas); 0 in `hl_*` apps. wd2l's file was not touched |
| AppInspect on `hl_data_health` | Pass after a fix: AppInspect 4.4.0 in a throwaway `python:3.14.10-slim` container on a `git archive` of the app. Before: 1 failure (`check_that_setup_has_not_been_performed`: `[install] is_configured = true`) and 6 warnings. After removing `is_configured` and adding `[id]`: 0 errors, 0 failures, 4 warnings, 102 passed. The 4 warnings are expected: 1-minute schedules (by design), `collections.conf` (informational), `admin` without `sc_admin` (Splunk Cloud only), and "PRIVATE IP 10.6.1.1", which is the UF version string |
| `tests/spl/run.sh` (fixtures + static checks) | Pass: 94 passed, 0 failed at the end of the run (2026-11-12), with this run's new checks `app-conf`, `37-data-host-late`, `38-tamper-cribl-request` and `39-ansible-uninstall` (each failed before its fix) |
| `tests/spl/dash.sh` `panels`, `load`, `writes` and `sync` (one mode per run), and `tests/spl/run.sh --scale 300` | Pass: each PASS; the Overview loaded in 0.94 s (limit 3 s); 6000 entities evaluated in 0.545 s (limit 10 s) |

### Findings

Defects the run found, each fixed on the branch with a check that failed before and passes after,
and deployed with `--tags server --limit homepc` (a reload, no splunkd restart):

| # | Row | What was wrong | Fix and check | Commit |
|---|---|---|---|---|
| F1 | static | AppInspect failed `check_that_setup_has_not_been_performed` (`[install] is_configured = true` in `hl_data_health/default/app.conf`, with no setup page) and warned that there was no `[id]` stanza | `is_configured` removed, `[id]` name and version added; `tests/spl/run.sh` case `app-conf` | `6e4c0cc` |
| F2 | 10 | While its own logs were LATE (not yet MISSING), the `cribl` row read "This stream stopped while the host still sends others", which is wrong for a host whose only liveness is its own data | new cause `host_late` ("Cribl late: …" for `cribl`, "Everything from this host is late …" for other agentless hosts); fixture `37-data-host-late` | `0010dab` |
| F3 | 11 | Adding a route logs one `create` and a `reorder` for every route it moves, in the same second; the finding took the first row, so it read "Cribl routes reorder (r_uf) by admin" instead of naming the new route | `dh_tamper_cribl` sorts reorders last; the finding now reads "Cribl routes create (r_e2e) by admin" (and "delete" for a removal); fixture `38-tamper-cribl-request`, built from the real 5 events | `f37711a` |
| F4 | 18 | After `--tags uninstall` the host's rows read "stopped outside Ansible", ignoring the `uninstall` marker | new cause `ansible_uninstall`: "Uninstalled with Ansible at `<time>` by `<user>` and not installed again", with the reinstall-or-retire action; fixture `39-ansible-uninstall` | `31b2582` |
| F5 | 18 | `tasks/uf_linux_uninstall.yml`'s header said the next `expected` run retires the host's rows; it doesn't (by design) | the comment now says the rows stay until `hl_expected: false` and `--tags expected` | `bba1e77` |

Documentation the run corrected (this branch):
- **`--tags cribl` doesn't revert an edit made in Cribl's UI or API** (row 11). It compares the repo's
  files with its own record of what it pushed, so it reports no change; its load check then fails
  while Cribl's route list differs from the repo's. Undo the edit in Cribl, then `--tags cribl`
  must pass. In the runbook and `running-the-role.md` §5.
- **Retire a host through its `host_vars`, never `-e hl_expected=false`** (row 18): an extra var
  overrides every host's value, so `--tags expected` would retire every UF host's rows. In
  `running-the-role.md` §4.
- **What a reinstall and an outside restart cost** (rows 16a and 18), in `running-the-role.md` and
  spec §13: a splunkd restart outside the role lost one 30-s sample (≈ 10–25 s of UF data) on three
  hosts, not the 3 s first measured; a reinstalled UF has no record of what it read, so it re-reads
  every monitored file and duplicates what was indexed before (≈ 17,000 events on wd2l-recv).
- Rows 5 and 14 didn't alert, and shouldn't: their rows are criticality 3, and *DH Alert missing*
  takes criticality 1–2 only (§7.3).

Test artefacts (not defects):
- **Row 9's 900 s limit stayed on for 25.5 h** (set 2026-11-13 00:01:30Z, cleared 2026-11-14 02:32:43Z with Manage's form; the row went back to its learned 49755 s, OK). With syslog on, the quiet UDM kept crossing it: after row 9's window the `udm` syslog row made 11 LATE, 9 MISSING and 11 OK transitions and fired 8 *DH Alert missing* (a 9th MISSING throttled), all reading "The device answers the network probe but sends no logs …". Nothing else changed; the `udm` host row stayed OK.

Open, for a ruling (not changed):
- **A later Ansible marker suppresses an earlier tamper finding** (row 11). Suppression looks
  15 min both ways from a finding (`dh_tamper_finish`, `abs(marker − finding) ≤ dh_tamper_window_secs`).
  The route was added at 03:21:00Z with no marker, and the finding was unsuppressed and alerted
  (03:26). The restore's first `--tags cribl` run posted its marker at 03:32:48Z, and the 03:35 *DH
  Tamper* run re-marked the finding `suppressed=1`, naming that marker. So the Overview's tamper
  panel and Host detail, which leave out suppressed findings, no longer show the Drop, and the
  runbook's own fix (run the role) is what hid it. The forward look is needed because some markers
  follow the change they cover: `restart` posts its marker once the UF is back, after the restart's
  `SERVICE_STOP`. Narrowing it (for example: look forward only for `start` and `restart`, or never
  re-mark a finding that has already alerted) is a design change.
- **Reboot tamper noise** (R12, row 3). An unmarked reboot raises findings, and *DH Alert tamper*
  throttles per host **and code** for 1 h, not per host: the hard power-off gave 1 finding and 1
  alert (the rule load at boot, `audit_config_change`, 137 events); the clean shutdown gave 4
  findings (`svcstop_rsyslog`, `svcstop_splunkforwarder`, `audit_daemon_end` auid=0, and the boot's
  `audit_config_change`) and 3 alerts (the 4th throttled by the first boot's). Row 6's unmarked
  auditd start gave one more `audit_config_change` alert. Whether 3–4 alerts per unmarked reboot is
  acceptable is the controller's call; row 16b adds HOMEPC's count.

Not caused by the run, recorded because they overlapped it:
- **2026-11-10 02:27:54–02:30:43Z: Windows Update replaced WSL** and Docker Desktop restarted both
  containers (Splunk and Cribl down ≈ 2 min 50 s). No row's measured window overlapped; data health
  read PENDING 02:32–02:37 and raised no transition and no alert, as row 16 expects.
- **2026-11-12 10:40–10:47Z: HOMEPC's network was reconfigured** (Hyper-V switch changes for VMs
  named `bootc-lab-*`, not in the inventory). pi5 logged "No route to host" to Cribl; pi5,
  wd2l-recv and wd2l-logsrv went LATE (wd2l-recv's host row MISSING for 1 min, one *DH Alert
  missing*), all OK by 10:47Z. No row ran then.
- The two HOMEPC Hyper-V channels never seen in task 6 (R13) now appear: `Hyper-V-Worker-Admin`
  (row 3's 18502, 18504 and 18506 among them) and `Hyper-V-VMMS-Admin`.
