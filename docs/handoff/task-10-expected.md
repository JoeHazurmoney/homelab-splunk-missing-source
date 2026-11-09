# Handoff: task 10 — the expected list: `expected` tag, DH Sync expected, DH Discover unregistered

Issue #11 · branch `feat/10-expected` · drafted in a cloud session on 2026-11-01, finished on the real
hosts on 2026-11-09.

**State:** finished; every check below ran on the real hosts. Results are in spec §14.17.

## What the branch adds

| Path | What |
|---|---|
| `templates/expected/dh_expected_ansible.csv.j2` | rows from **hostvars of every UF host** (so a VM that is off, or outside `--limit`, stays expected): host row (heartbeat, `via=cribl`, `hypervisor`), one sourcetype row per enabled input (inputs that share a sourcetype merge, and the most critical wins), source rows for `track_source`; each syslog device (host + sourcetype); Cribl (`host` and `cribl/cribl`, heartbeat, `max_gap_secs: 120`); `dh_extra_expected`. `entity_id` is left empty: Splunk computes it with `dh_source_norm` |
| `tasks/expected.yml` | render on the controller → refuse an empty file → copy into `hl_data_health/lookups/` only when the sha256 differs → `\| savedsearch "DH Sync expected"` → show what it wrote |
| `defaults/main.yml`, `host_vars/wd2l-*.yml`, `group_vars/splunk_server.yml` | `dh_extra_expected` (the `enclave1` pairs, real values in `group_vars/splunk_server.yml`); `hl_hypervisor: hyperv` on the VMs |
| `tasks/verify.yml` | `verify` on the Splunk server reads `dh_status` through the container (spec 5.3) |
| `macros.conf` | `dh_indexes` gains `cribl`; `dh_sync_rows`, `dh_sync_sig`, `dh_sync_plan` (add / update / retire by `_key`, enabled UI rows untouched, **nothing written while the file has no valid rows**), `dh_discover_summary` |
| `savedsearches.conf` | `DH Sync expected` (*/5, `max_concurrent=1`), `DH Discover unregistered` (*/15, one `dh:discover` record per run) |
| `tests/spl/cases/97-sync-plan/`, `98-sync-empty-file/`, `99-sync-invalid-file/` | add (new, FQDN host row, source row, a disabled UI row replaced), update (expected_since kept), retire (including a row the file disables), untouched (unchanged, disabled, an enabled UI row kept even with an Ansible row on the same entity, UI-only), invalid level dropped; nothing written for an empty or all-invalid file |
| `tests/spl/run.sh`, `tests/spl/dash.sh`, `tests/spl/savedsearches.expect.csv`, `docs/data-health/macros.md` | the static upsert-only check on `dh_expected`, `dash.sh sync` (the saved search on a throwaway KV copy), the two searches, the four macros |

**DH Discover unregistered** (Taylor, 2026-11-07): the spec names it (§7.3, */15); it writes one summary record per run (count, hosts, up to 50 ids) to `index=data_health source=dh:discover`. Manage's "adopt" tab and the Daily report list unregistered entities live. Spec §7.3 records this.

## Before running

1. Tasks 6 and 8 are verified (the inputs and the probe exist).
2. **`dh_extra_expected`:** what reaches Splunk through wd2l (spec §4.4 "existing" row:
   `enclave1/syslog`, continuous, `via=wd2l-recv`). One row per host in
   `inventory/group_vars/splunk_server.yml`, from `| tstats count where index=enclave1 earliest=-24h by host sourcetype`.
3. pi5's wd2l sourcetype (task 6 "Before running" 3) must be set first, or its row will be wrong.

## Run

```bash
ansible-playbook site.yml --tags server --limit homepc          # deploys the new macros and searches
tests/spl/run.sh 97-sync-plan                                   # on HOMEPC: the fixture case
tests/spl/run.sh                                                # full suite + static checks
tests/spl/dash.sh sync                                          # the sync on a throwaway KV copy
ansible-playbook site.yml --tags expected --limit homepc -v
ansible-playbook site.yml --tags expected --limit homepc        # expect changed=0 (written=0)
```

## Checks (record in spec §14.17 "Task 10 checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | Fixture `97-sync-plan` and the full suite | `tests/spl/run.sh` | all PASS, including savedsearch-settings and docs-coverage | a diff in 93: compare the `dh_change` column first. KV number fields can come back as `2.0`, which `dh_sync_sig` rounds; check `interval_secs` |
| 2 | **Each enabled input has a row** (done-when) | `\| inputlookup dh_expected where managed_by="ansible" enabled=1 \| stats count by host level` | a row per enabled input, per the rendered file (§14.17) | compare with `\| inputlookup dh_expected_ansible.csv` |
| 3 | Idempotence | second `--tags expected`; also wait 5 min | `written=0`; the scheduled run writes nothing | a row rewritten every time: its signature differs between the file and KV (KV type coercion); add `round(tonumber())` to that field in `dh_sync_sig` |
| 4 | **Removing one retires it** (done-when) | `-e '{"hl_disabled_inputs":["monitor:///var/log/cron"]}' --tags expected --limit homepc` (the input itself stays, so the UFs aren't touched; `-e` applies to all hosts) | the cron source rows get `enabled=0`; DH Evaluate drops their status within a minute; the Overview stops showing them. Rerun without `-e`: they come back, with a fresh grace period | — |
| 5 | UI rows untouched | a UI row on another entity (add one on Manage → Expected list, or an upsert) and a UI row on the same entity as an Ansible row; run `--tags expected` | the UI rows stay `managed_by=ui`, unchanged | — |
| 6 | Empty-file guard | in the container, back up the file, then `printf 'entity_id,level\n' > …/lookups/dh_expected_ansible.csv`; run `\| savedsearch "DH Sync expected"`; restore it | `written=0`, nothing retired | — |
| 7 | Overview | after 5 min | every host appears; `udm` and its probe row are OK; nothing NEVER_SEEN except what truly isn't there yet | NEVER_SEEN for TA_nix rows: a sourcetype the TA names differently; compare `\| tstats count where index=linux by sourcetype` |
| 8 | Discover | after 15 min: `index=data_health source=dh:discover \| head 1` | one record per run, the entities each explained (§14.17) | — |
| 9 | `verify`'s "every expected row seen" (spec §5.3) | `--tags verify --limit homepc` | MISSING or NEVER_SEEN on a non-sporadic row fails, naming it; LATE and sporadic are reported; all PENDING = "not evaluated" | — |

## Then

- Spec: §14.17; §7.3 (what DH Discover writes).
- `docs/data-health/dashboards.md`: no panel changed.
- PR: `feat(expected): expected list from the inventory, DH Sync expected and discovery (task 10)`, `Closes #11`.
