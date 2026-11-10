# Handoff: task 11b — data health adapted to Cribl

Issue #25 · branch `feat/11b-dh-cribl` (on `main`) · drafted in a cloud session on 2026-11-01; run and corrected on 2026-11-09 (spec §14.18).

**State:** the draft below ran in Splunk on 2026-11-09 (spec §14.18). Its fixtures and regexes were
corrected against real data: `dh_tamper_cribl` read Splunk's auto-extracted JSON fields twice (doubled
into multivalues, so it found nothing on real events) and now uses the eval `spath()`; `dh_ui_block_command`
read a field the plan had dropped; the writer and DH Prune's block branch were removed instead of left for
later (see "Rulings that changed this note" below).

## Rulings that changed this note
- Writer and Prune: `dh_ui_block_write`, `dh_ui_block_rows`, `dh_prune_mark_blocks` and DH Prune's block branch are gone (controller, R1). `cribl_block` is the only writer of the mirror.
- `Agent ID (guid)` row dropped from Host detail (R5).
- Browser checks are the controller's (R12); this task proves them through panel searches.

## What the branch changes

| Area | Change |
|---|---|
| **"Cribl DOWN" cause** (§7.5, §7.6) | `relay_down` with `via=cribl` reads "Cribl DOWN: the real state is unknown …", with the action "Check the cribl container … `--tags verify --limit homepc`". The `cribl` host row itself (no data) reads "Cribl DOWN: nothing from Cribl itself …". Other relays keep the generic text. The relay logic itself is unchanged (the expected rows from task 10 carry `via=cribl`) |
| **Forwarder identity** (§7.3, §8, spike §14.7 e) | `dh_fwd_from_tcpin` → **`dh_fwd_from_ufint`**: the UF's own splunkd.log. Last connect = `Connected to idx=`; OS + arch = `loader - System info:`; build = `Splunkd starting (build …)`, mapped to a version by the new lookup **`dh_uf_builds`** (`b2ae2962645c,10.6.1.1`). Splunk's own lines are left out. *DH Tracker fast* reads `index=_internal sourcetype=splunkd (…)` instead of `group=tcpin_connections`. Host detail: "Last connection to Splunk" → "**Last connection to Cribl**" |
| **Cribl tamper indicator** (§7.6) | **`dh_tamper_cribl`**: any create/update/delete/reorder/upload of routes, pipelines, outputs, inputs or lookups in `index=cribl sourcetype=cribl:audit` is a finding on host `cribl`. *DH Tamper* appends it. The role's own changes are suppressed by its `cribl`/`cribl_block` markers (`target_host=cribl`, task 3b) |
| **Test block** (§7.2 open item, §7.7, §7.8) | Answered by task 3b's `cribl_block` tag, which **mirrors** Cribl's table into Splunk's `hl_ingest_block`. So the evaluator's label input works as it is, and DH Prune's block branch keeps tidying the mirror (harmless). New **`dh_ui_block_command`** turns a block plan row into the `cribl_block` command for the Manage form |
| **Probe wording** (§7.6) | new tunable **`dh_probe_host`** (`"pi5"`); `probe_stale` names it ("Check hl-devprobe on pi5: …") instead of the relay |
| Other wording | `gate_no_rx`, `hb_late`, `hb_missing`: port 9997 is Cribl's now, and 10514/20514 are gone |
| Fixtures | **new:** `94-cribl-down` (evaluator), `95-tamper-cribl`, `96-ui-block-command`; **updated:** `10-pending-no-rx`, `14-heartbeat-missing`, `21-probe-unreachable`, `93-ui-manage-words` (texts), `40-fwd-fold` (`ufint` rows replace `tcpin`; the raw lines are stored with `;` for `,` and swapped back in the search, because the runner splits the fixture CSVs on commas), `87-ui-host` (label) |
| Docs | `macros.md` (4 new, 1 replaced), `dashboards.md` (cause rows, banner, Host detail label) |

## Manage: the Test blocks tab (done on this branch, on top of #31)

- `tools/gen_dh_manage.js` (the view is generated; never edit the XML): the **Confirm** input, the
  apply search and the "result" panel of the test-block form are gone. A new panel, **Test block:
  command**, shows `dh_ui_block_command`'s line once the preview says OK. The intro says the block is
  set in Cribl by the role. `cond_bk_done` is no longer generated. `dh_manage.xml` was regenerated.
- `dh_ui_block_plan`'s "After the change" now reads "…; Cribl applies it about 20 s after the command
  runs". The `test_block` cause action reads "Remove the test block when the test ends (Manage >
  Test blocks gives the command)".
- `tests/spl/dash.sh writes`: the block apply/repeat/prune steps became checks of the command (set
  and clear) and that the form wrote no file. The admin-log total is now **6** (no block rows).
- `docs/data-health/dashboards.md`: the Test blocks section, the recipe and the "Test block: command"
  entry are rewritten; "Current test blocks" reads the mirror.

## Before running

Tasks 3b, 4 and 10 are verified (Cribl data, UF `_internal` through Cribl, `via=cribl` rows). Deploy:
`ansible-playbook site.yml --tags server --limit homepc`.

## Checks (recorded in spec §14.18 "Task 11b checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | Fixtures | `tests/spl/run.sh` and `tests/spl/dash.sh writes` (on HOMEPC; `tests/spl/dev-deploy.sh` first) | all PASS, including 94, 95, 96, 97 and the updated ones | read the diff; for 40, check the `rex` against the real lines (check 2) |
| 1b | **Manage's form** (12e's open item, plus this tab; browser check is the controller's, R12) | the panel searches `ds_bk_plan` and `ds_bk_command` over REST (and `tests/spl/dash.sh writes`) with one test block as the data: `wd2l-recv\|linux_secure\|*` (R9) | the preview, then a command line; no Confirm; Current test blocks lists it | the generator's layout (`blocks` rows) |
| 2 | **Forwarder identity from real lines** | `index=_internal sourcetype=splunkd host=wd2l-recv* ("Connected to idx=" OR "System info:" OR "Splunkd starting") \| head 5`; and the same for `host=homepc` | the regexes match. **Windows wording** (from task 5 check 11): if `System info:` differs, adjust the `rex` in `dh_fwd_from_ufint` and add a Windows row to `40-fwd-fold` | — |
| 3 | **Host detail shows UF version and last connect again** (done-when) | the Host detail panel search for wd2l-recv and homepc over REST (browser check is the controller's, R12) | Agent version 10.6.1.1, Operating system "Linux x86_64" / "Windows x64", Last connection to Cribl < 1 min ago. No Agent ID row (R5) | the identity lines appear only at a UF start: R7 fills `dh_fwd` once with a manual dispatch over a wider window; never restart a UF to get them |
| 4 | **The Cribl tamper finding fires** (done-when; R10) | save a Drop function (filter `false`, so it drops nothing) to `pl_test_block` through Cribl's API as admin, ≥ 15 min away from any `cribl*` marker; wait ≤ 10 min; restore the function (PATCH the original back, or `--tags cribl --limit homepc` if that leaves a difference) | a tamper finding on host `cribl` ("Cribl pipelines update (pl_test_block) by admin"), not suppressed; the Overview's tamper panel shows it. **The finding stays in `dh_tamper`**: do not delete it | no `cribl:audit` events: task 3b check 7 |
| 5 | Suppression of the role's own work | `--tags cribl_block …` (task 3b check 12) | its `lookups` entries are suppressed (inside the marker window) | the marker's `target_host` must be `cribl` |
| 6 | **Cribl DOWN** (E2E §12; R11) | `docker stop cribl` **once**; the `cribl` row needs MISSING (2 × 120 s plus the 1-minute evaluator), so keep it down ≥ 5 min and at most what the check needs; note the UDP loss | `cribl` DOWN; every `via=cribl` row "Cribl DOWN: the real state is unknown"; **no** "Splunk not receiving" banner (HEC still flows); then `docker start cribl`; count the stop | a banner: HEC isn't flowing either; check wd2l |
| 7 | Probe stale names pi5 (R4; T8's check 9 wording) | `systemctl stop hl-devprobe.timer` on pi5, past 180 s | pi5's `hl:devprobe` row (not the `udm` host row, which is sporadic, 24 h) goes LATE with "Check hl-devprobe on pi5: …" (cause `probe_stale`; fix round 1); then restore with `--tags probe --limit pi5`; no action says "on the relay" | — |
| 8 | Test-block label | `--tags cribl_block -e "hl_block_key='wd2l-recv\|linux_secure\|*'" -e hl_block_minutes=10 -e "hl_block_reason='11b label'"` (R9: this one block serves checks 1b and 8; clear it afterwards) | the row shows "test block until hh:mm" (done-when, R2; linux_secure is sporadic, so the cause "test_block" shows only past its 24 h threshold; fixture 23 proves the cause) | the mirror wasn't written: `\| inputlookup hl_ingest_block` |

## Then

- Spec: §14.18; §7.2's open item closed (the mirror, no scheduled expiry); §7.3 and §8 (`dh_fwd_from_ufint`, `dh_uf_builds`, DH Prune); §7.6 (`dh_tamper_cribl`, `dh_probe_host`); §7.7, §7.8.
- PR: `feat(data-health): Cribl relay cause, UF identity from _internal, Cribl tamper indicator (task 11b)`, `Closes #25`.
