# Handoff: task 11b — data health adapted to Cribl

Issue #25 · branch `feat/11b-dh-cribl`, **stacked on `feat/10-expected`** · drafted in a cloud
session on 2026-11-01.

**State:** written; the dashboards' static check and the docs coverage check pass here. Three new
fixture cases plus four updated ones have **not run in Splunk**. The Manage dashboard itself is
**not touched** (PR #31, task 12e, rewrites it; see "Manage" below).

## What the branch changes

| Area | Change |
|---|---|
| **"Cribl DOWN" cause** (§7.5, §7.6) | `relay_down` with `via=cribl` reads "Cribl DOWN: the real state is unknown …", with the action "Check the cribl container … `--tags verify --limit homepc`". The `cribl` host row itself (no data) reads "Cribl DOWN: nothing from Cribl itself …". Other relays keep the generic text. The relay logic itself is unchanged (the expected rows from task 10 carry `via=cribl`) |
| **Forwarder identity** (§7.3, §8, spike §14.7 e) | `dh_fwd_from_tcpin` → **`dh_fwd_from_ufint`**: the UF's own splunkd.log. Last connect = `Connected to idx=`; OS + arch = `loader - System info:`; build = `Splunkd starting (build …)`, mapped to a version by the new lookup **`dh_uf_builds`** (`b2ae2962645c,10.6.1.1`). Splunk's own lines are left out. *DH Tracker fast* reads `index=_internal sourcetype=splunkd (…)` instead of `group=tcpin_connections`. Host detail: "Last connection to Splunk" → "**Last connection to Cribl**" |
| **Cribl tamper indicator** (§7.6) | **`dh_tamper_cribl`**: any create/update/delete/reorder/upload of routes, pipelines, outputs, inputs or lookups in `index=cribl sourcetype=cribl:audit` is a finding on host `cribl`. *DH Tamper* appends it. The role's own changes are suppressed by its `cribl`/`cribl_block` markers (`target_host=cribl`, task 3b) |
| **Test block** (§7.2 open item, §7.7, §7.8) | Answered by task 3b's `cribl_block` tag, which **mirrors** Cribl's table into Splunk's `hl_ingest_block`. So the evaluator's label input works as it is, and DH Prune's block branch keeps tidying the mirror (harmless). New **`dh_ui_block_command`** turns a block plan row into the `cribl_block` command for the Manage form |
| **Probe wording** (§7.6) | new tunable **`dh_probe_host`** (`"pi5"`); `probe_stale` names it ("Check hl-devprobe on pi5: …") instead of the relay |
| Other wording | `gate_no_rx`, `hb_late`, `hb_missing`: port 9997 is Cribl's now, and 10514/20514 are gone |
| Fixtures | **new:** `94-cribl-down` (evaluator), `95-tamper-cribl`, `96-ui-block-command`; **updated:** `10-pending-no-rx`, `14-heartbeat-missing`, `21-probe-unreachable` (texts), `40-fwd-fold` (`ufint` rows replace `tcpin`; the raw lines are stored with `;` for `,` and swapped back in the search, because the runner splits the fixture CSVs on commas), `87-ui-host` (label) |
| Docs | `macros.md` (4 new, 1 replaced), `dashboards.md` (cause rows, banner, Host detail label) |

## Manage (needs PR #31 first)

PR #31 (task 12e) rewrites `dh_manage.xml` into tabs. To avoid conflicts, this branch doesn't edit
the view. Once #31 is merged, finish 11b by editing the **Test blocks** tab:
1. Keep the plan step (`dh_ui_block_plan`) for the checks and the preview.
2. Replace the write step (`dh_ui_block_write`) with `| \`dh_ui_block_command\`` and show the
   `command` field as text the user copies (no Apply). Keep the admin-only check.
3. Add a line saying the block takes effect in Cribl 15–20 s after the command runs, and that the
   dashboard's label comes from the mirror.
4. Run `python3 tests/spl/dash_check.py check splunk/apps/hl_data_health` and the docs check, and
   update the Manage section of `dashboards.md`.
5. Then `dh_ui_block_write` and `dh_ui_block_rows` have no user left: delete them, with their entries in
   `macros.md` and their fixture rows in `91-ui-block-plan` if any.

## Before running

Tasks 3b, 4 and 10 are verified (Cribl data, UF `_internal` through Cribl, `via=cribl` rows). Deploy:
`ansible-playbook site.yml --tags server --limit homepc`.

## Checks (record in spec §14.16 "Task 11b checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | Fixtures | `tests/spl/run.sh` (on HOMEPC) | all PASS, including 94, 95 and 96 and the updated ones | read the diff; for 40, check the `rex` against the real lines (check 2) |
| 2 | **Forwarder identity from real lines** | `index=_internal sourcetype=splunkd host=wd2l-recv* ("Connected to idx=" OR "System info:" OR "Splunkd starting") \| head 5`; and the same for `host=homepc` | the regexes match. **Windows wording** (from task 5 check 11): if `System info:` differs, adjust the `rex` in `dh_fwd_from_ufint` and add a Windows row to `40-fwd-fold` | — |
| 3 | **Host detail shows UF version and last connect again** (done-when) | open Host detail for wd2l-recv | Agent version 10.6.1.1, Operating system "Linux x86_64", Last connection to Cribl < 1 min ago. Agent ID (guid) is now empty: no source gives it. Drop that row, or read the guid from the UF's `etc/instance.cfg` with a scripted input (Taylor's call) | the version comes only at a UF start, so restart the UF once (`--tags restart`) if `dh_fwd` predates the change |
| 4 | **The Cribl tamper finding fires** (done-when) | in Cribl's UI (no marker), add a Drop function to `pl_test_block` (filter `false`), save; wait ≤ 10 min | a tamper finding on host `cribl` ("Cribl pipelines update (pl_test_block) by admin"), not suppressed; the Overview's tamper panel shows it. Remove the function afterwards, or run `--tags cribl` (which replaces the file) | no `cribl:audit` events: task 3b check 7 |
| 5 | Suppression of the role's own work | `--tags cribl_block …` (task 3b check 12) | its `lookups` entries are suppressed (inside the marker window) | the marker's `target_host` must be `cribl` |
| 6 | **Cribl DOWN** (E2E §12) | `docker stop cribl`; ≤ 3 min | `cribl` DOWN; every `via=cribl` row "Cribl DOWN: the real state is unknown"; **no** "Splunk not receiving" banner (HEC still flows); then `docker start cribl` | a banner: HEC isn't flowing either; check wd2l |
| 7 | Probe stale names pi5 | `systemctl stop hl-devprobe.timer` on pi5, past 180 s | "Check hl-devprobe on pi5: …"; then start it again | — |
| 8 | Test-block label | `--tags cribl_block -e "hl_block_key='wd2l-recv\|linux_secure\|*'" -e hl_block_minutes=10 -e "hl_block_reason='11b label'"` | the row shows "Test block until hh:mm" and the cause "test_block" once it goes LATE | the mirror wasn't written: `\| inputlookup hl_ingest_block` |

## Then

- Spec: §14.16; §7.2's open item closed (the mirror); §7.3 and §8 (`dh_fwd_from_ufint`, `dh_uf_builds`);
  §7.6 (`dh_tamper_cribl`).
- PR: `feat(data-health): Cribl relay cause, UF identity from _internal, Cribl tamper indicator (task 11b)`,
  `Closes #25`. If the Manage edit waits for #31, say so in the PR and keep #25 open until it's done.
