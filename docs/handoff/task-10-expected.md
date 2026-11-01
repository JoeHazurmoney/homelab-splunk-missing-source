# Handoff: task 10 — the expected list: `expected` tag, DH Sync expected, DH Discover unregistered

Issue #11 · branch `feat/10-expected`, **stacked on `feat/8-udm-probe`** · drafted in a cloud session
on 2026-11-01.

**State:** written; yamllint and ansible-lint clean; the dashboards' static check and the docs coverage check
(`tests/spl/dash_check.py check|docs`) pass here. The CSV template was rendered from the real inventory
through the role: **85 rows** (6 host rows; per host every enabled input; HOMEPC's 7 channels as source
rows; the UDM; Cribl). The new SPL (`dh_sync_*`, `dh_discover_summary`, two saved searches) and
fixture case `97-sync-plan` have **not run in Splunk**.

## What the branch adds

| Path | What |
|---|---|
| `templates/expected/dh_expected_ansible.csv.j2` | rows from **hostvars of every UF host** (so a VM that is off, or outside `--limit`, stays expected): host row (heartbeat, `via=cribl`, `hypervisor`), one sourcetype row per enabled input (inputs that share a sourcetype merge, and the most critical wins), source rows for `track_source`; each syslog device (host + sourcetype); Cribl (`host` and `cribl/cribl`, heartbeat, `max_gap_secs: 120`); `dh_extra_expected`. `entity_id` is left empty: Splunk computes it with `dh_source_norm` |
| `tasks/expected.yml` | render on the controller → refuse an empty file → copy into `hl_data_health/lookups/` only when the sha256 differs → `\| savedsearch "DH Sync expected"` → show what it wrote |
| `defaults/main.yml`, `host_vars/wd2l-*.yml` | `dh_extra_expected: []`; `hl_hypervisor: hyperv` on the VMs |
| `macros.conf` | `dh_sync_rows`, `dh_sync_sig`, `dh_sync_plan` (add / update / retire, UI rows untouched, **nothing written while the file has no valid rows**), `dh_discover_summary` |
| `savedsearches.conf` | `DH Sync expected` (*/5, `max_concurrent=1`), `DH Discover unregistered` (*/15, one `dh:discover` record per run) |
| `tests/spl/cases/97-sync-plan/` | add (new, FQDN host row, source row, a UI row taken over), update (expected_since kept), retire, untouched (unchanged, disabled, UI-only), invalid level dropped |
| `tests/spl/savedsearches.expect.csv`, `docs/data-health/macros.md` | the two searches; the four macros |

**DH Discover unregistered:** the spec names it (§7.3, */15) but not what it writes. The draft
writes one summary record per run (count, hosts, up to 50 ids) to `index=data_health
source=dh:discover`. Manage's "adopt" tab and the Daily report already list unregistered entities
live. **Ask Taylor** whether to keep the record (for trends) or drop the search.

## Before running

1. Tasks 6 and 8 are verified (the inputs and the probe exist).
2. **`dh_extra_expected`:** what reaches Splunk through wd2l (spec §4.4 "existing" row:
   `enclave1/syslog`, continuous, `via=wd2l-recv`). Find the hosts with
   `| tstats count where index=enclave1 earliest=-24h by host sourcetype`, and add one row per host to
   `inventory/group_vars/splunk_server.yml` (example in `defaults/main.yml`, `collection: hec`).
3. pi5's wd2l sourcetype (task 6 "Before running" 3) must be set first, or its row will be wrong.

## Run

```bash
ansible-playbook site.yml --tags server --limit homepc          # deploys the new macros and searches
tests/spl/run.sh 97-sync-plan                                   # on HOMEPC: the fixture case
tests/spl/run.sh                                                # full suite + static checks
ansible-playbook site.yml --tags expected --limit homepc -v
ansible-playbook site.yml --tags expected --limit homepc        # expect changed=0 (written=0)
```

## Checks (record in spec §14.15 "Task 10 checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | Fixture `97-sync-plan` and the full suite | `tests/spl/run.sh` | all PASS, including savedsearch-settings and docs-coverage | a diff in 93: compare the `dh_change` column first. KV number fields can come back as `2.0`, which `dh_sync_sig` rounds; check `interval_secs` |
| 2 | **Each enabled input has a row** (done-when) | `\| inputlookup dh_expected where managed_by="ansible" enabled=1 \| stats count by host level` | 85 rows plus `dh_extra_expected`: wd2l-recv 20 sourcetype + 2 source + host; pi5 21 + 2 + host; HOMEPC 3 + 7 + host; UDM 2; Cribl 2 | compare with `\| inputlookup dh_expected_ansible.csv` |
| 3 | Idempotence | second `--tags expected`; also wait 5 min | `written=0`; the scheduled run writes nothing | a row rewritten every time: its signature differs between the file and KV (KV type coercion); add `round(tonumber())` to that field in `dh_sync_sig` |
| 4 | **Removing one retires it** (done-when) | `-e '{"hl_disabled_inputs":["monitor:///var/log/cron"]}' --tags expected` (the input itself can stay) | the cron source rows get `enabled=0`; DH Evaluate drops their status within a minute; the Overview stops showing them. Rerun without `-e`: they come back, with a fresh grace period | — |
| 5 | UI rows untouched | add a row on Manage → Expected list, then run `--tags expected` | the UI row stays `managed_by=ui` | — |
| 6 | Empty-file guard | in the container, back up the file, then `printf 'entity_id,level\n' > …/lookups/dh_expected_ansible.csv`; run `\| savedsearch "DH Sync expected"`; restore it | `written=0`, nothing retired | — |
| 7 | Overview | after 5 min | every host appears; nothing NEVER_SEEN except what truly isn't there yet | NEVER_SEEN for TA_nix rows: a sourcetype the TA names differently; compare `\| tstats count where index=linux by sourcetype` |
| 8 | Discover | after 15 min: `index=data_health source=dh:discover \| head 1` | one record | — (see the Taylor question above) |
| 9 | `verify`'s "every expected sourcetype seen" (spec §5.3) | not built yet: add it to `tasks/verify.yml` now that the list exists (`\| inputlookup dh_status where status!="OK"` via REST), or leave it to task 14 | — | — |

## Then

- Spec: §14.15; §7.3 (what DH Discover writes, once Taylor decides).
- `docs/data-health/dashboards.md`: no panel changed.
- PR: `feat(expected): expected list from the inventory, DH Sync expected and discovery (task 10)`, `Closes #11`.
