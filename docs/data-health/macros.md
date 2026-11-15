# hl_data_health macros: what each one is for

This page describes every search macro in `splunk/apps/hl_data_health/default/macros.conf`. Its entries follow the order and the groups of that file. [dashboards.md](dashboards.md) explains the panels. This page explains the building blocks behind them.

Keep this page current. A change that adds, renames or removes a macro must update this page in the same pull request. `tests/spl/run.sh` fails (check `docs-coverage`) when a macro has no entry here. It also fails when an entry names a macro that no longer exists.

## The pipeline in short

Each macro below is one step of this pipeline.

- **Arrival tracker.** The saved search *DH Tracker fast* runs every minute. It records when each index, host, sourcetype and source last sent data. It also records when each Splunk agent (UF) last called in. *DH Tracker slow* runs hourly and records the same facts again.
- **Evaluator.** *DH Evaluate* runs every minute. It compares those times with the [expected list](../glossary.md#expected-list), which lives in the `dh_expected` collection. It gives each item a status, such as OK, LATE or MISSING. It adds a likely cause and a next action. It writes the result to the `dh_status` collection. It also writes every status change to the `data_health` index as a *transition*.
- **Learning and checking.** Nightly and hourly searches learn what is normal: *DH Baseline daily*, *DH Baseline compute* and *DH Volume hourly*. *DH Tamper* looks for signs of tampering. *DH Prune* tidies up. *DH Daily SoH report* writes the daily report.
- **Alerts and dashboards.** The alerts read the transitions and the tamper findings. The dashboards read `dh_status` and the summary events.

**Words used below:**

- An *item* is one thing that should send data. It is a host, a sourcetype on a host, or one source of a sourcetype on a host. The field that names it is `entity_id`, in the form `level|index|host|sourcetype|source`. A `*` stands for a part its level doesn't use.
- A *collection* is a [KV store](../glossary.md#kv-store) table.
- *Epoch* means seconds since 1970 (UTC).

**How to read an entry:**

- The heading is the macro as you call it, with its argument names.
- Arguments that name a lookup let the tests in `tests/spl/` run the same macro on fixture tables.
- *Used by* names the saved search, dashboard panel or macro that calls it.

## Lookup names

Each entry gives the real collection behind a lookup name. Saved searches call these names instead of typing the collections. That way a test can check that they all agree.

### `dh_lookup_expected`
The expected list, `dh_expected`: every item that should send data. Used by: the name check in `tests/spl/run.sh`.

### `dh_lookup_state_fast`
`dh_state_fast`: when each index, host, sourcetype and source last delivered data, as the arrival tracker saw it. Used by: *DH Tracker fast*.

### `dh_lookup_state_slow`
`dh_state_slow`: the same facts from the hourly backfill. Used by: *DH Tracker slow*.

### `dh_lookup_fwd`
`dh_fwd`: one row per host with its Splunk agent facts. The facts are the last heartbeat, the last connection, the version, the last Ansible marker, the last Hyper-V event and the last device probe. Used by: *DH Tracker fast*, *DH Daily SoH report*.

### `dh_lookup_overrides`
`dh_overrides`: the mutes and limit overrides set on the Manage dashboard. Used by: *DH Prune*, *DH Daily SoH report*.

### `dh_lookup_baseline`
`dh_baseline`: what is normal for each item, meaning its learned silence limit and its hourly volume. Used by: *DH Baseline compute*.

### `dh_lookup_meta`
`dh_meta`: the run times of the trackers and of the admin-log copy. The banner and the evaluator's gate read it. Used by: *DH Tracker fast*, *DH Tracker slow*, *DH Admin log copy*.

### `dh_lookup_blocks`
`hl_ingest_block`: Splunk's copy of Cribl's test-block table. It is a lookup of the `hl_server_base` app. Only the role's *cribl_block* tag adds or removes blocks in it, and nothing in this app writes it. The *cribl* and *cribl_remove* tags only reset it to its header ([who writes it](../running-the-role.md#test-blocks)). Until that app is installed, the table doesn't exist and reads as empty. Used by: the `lookup-names` check in `tests/spl/run.sh`, which keeps it equal to the name `dh_evaluate` uses. `dh_evaluate` and the Manage Test blocks tab name `hl_ingest_block` directly. A macro argument can't hold a macro, so `dh_evaluate` can't call this one.

### `dh_lookup_tamper`
`dh_tamper`: the tamper findings, with their suppression and, for a Splunk agent stop, its state (pending or judged), what explains it and when the agent came back. Used by: *DH Tamper*.

### `dh_lookup_status`
`dh_status`: the evaluator's output, one row per expected item. Used by: *DH Evaluate*, *DH Daily SoH report*.

### `dh_lookup_volume`
`dh_volume`: last hour's event count per item, against its usual count. Used by: *DH Volume hourly*.

### `dh_lookup_admin_log`
`dh_admin_log`: every change made on the Manage dashboard. Used by: *DH Admin log copy*.

## Items and normalization

### `dh_indexes`
The indexes the trackers watch: `linux, windows, network, wd2l_uf_audit, enclave1, wd2l, cribl`. Three indexes are left out on purpose:
- `data_health` holds this app's own output.
- `wd2l_audit` is not watched.
- `cribl_metrics` is a metrics index. Its dimensions carry the data's hosts and sourcetypes.

Used by: *DH Tracker fast*, *DH Tracker slow*, *DH Baseline daily*, *DH Volume hourly*, the Host detail chart.

### `dh_host_norm(h)`
Turns a host name into its short lowercase form. For example, `WD2L-RECV.mshome.net` becomes `wd2l-recv`. The same machine then always gets the same name. The test-block rule at ingest uses the same rule. Arguments: `h`, a field or expression. Used by: nearly every step that reads a host.

### `dh_source_norm(s)`
Turns a source path into a pattern. Dates, times and long numbers become `*`. A rotation suffix such as `.1` or `.2.gz` becomes `.*`. So `audit-2026-10-30.jsonl` and `audit-2026-10-31.jsonl` count as one source. Arguments: `s`, a field or expression. Used by: the trackers, the evaluator, baselines, volume, Manage.

### `dh_state_entity_ids`
For one row of arrival data, gives the three items it counts toward: its source, its sourcetype and its host. Used by: `dh_eval_load`, `dh_daily_from_minutes`, `dh_volume_flag`.

### `dh_expected_rows(expected)`
The enabled rows of the expected list, normalized, one per item. Only `0`, `false`, `no` or `off` disables a row. So a typo never switches monitoring off. Arguments: `expected`, the expected-list lookup. Used by: the evaluator, the daily baseline, prune, the unregistered list.

## Tunables

These are fixed numbers the pipeline uses. Change them in `local/macros.conf`, never in `default/`.

### `dh_probe_host`
The host that runs the device probe (*hl-devprobe*). In this lab it is `pi5`, the role's `hl_probe_host`. The probe causes name it ("check hl-devprobe on pi5"). Change both together.

### `dh_skew_secs`
**600 seconds.** Data can arrive this long after (or before) its own timestamp. Past that, the item is flagged for clock skew. Raise it to accept slower or more backfilled sources. Lower it to catch smaller clock errors, with more noise. Used by: `dh_state_merge`, `dh_eval_load`.

### `dh_gate_stale_secs`
**120 seconds.** Suppose the arrival tracker hasn't run for this long. The evaluator then stops trusting its data. Every status shows PENDING, no alert fires, and the banner says "On hold". Raise it to ride out a slow scheduler. Lower it to notice a stuck tracker sooner. Used by: `dh_eval_gate_read`, `dh_ui_banner`.

### `dh_gate_rx_secs`
**120 seconds.** Suppose Splunk has indexed nothing at all for this long. It then counts as "not receiving", and every status is held as PENDING. When everything goes silent at once, the fault is Splunk's, not each host's. Raise it on a very quiet lab. Lower it to react sooner. Used by: `dh_eval_gate_read`, `dh_ui_banner`.

### `dh_gate_resume_secs`
**300 seconds.** After a pause, such as PC sleep or a Splunk restart, the evaluator holds every status as PENDING for this long. The data catches up meanwhile, so a wake-up raises no false alerts. Raise it if backlogs take longer to drain. Lower it to see real statuses sooner. Used by: `dh_eval_gate_read`, `dh_ui_banner`.

### `dh_resume_gap_secs`
**150 seconds.** A gap this long between two runs of the arrival tracker counts as a pause. It starts the hold above. Raise it if the scheduler is often late. Lower it to catch shorter pauses. Used by: `dh_meta_fast`.

### `dh_retire_candidate_secs`
**604800 seconds (7 days).** How long an expected item must be silent to appear as a retirement candidate on Manage. An item that is expected but has never been seen counts too. Raise it to list only items that have been gone longer. Used by: `dh_ui_retire_candidates`.

### `dh_never_seen_secs`
**3600 seconds.** A newly expected item that has never sent anything is PENDING for this long. After that it is NEVER_SEEN. Raise it for inputs that take long to start. Lower it to report missing inputs sooner. Used by: `dh_eval_status`.

### `dh_tamper_window_secs`
**900 seconds.** This number does two jobs:
- A tamper finding this close to the start of a silence makes the cause "possible deliberate blinding".
- A finding that comes at most this long after an Ansible marker for its host counts as the role's own work. It is then suppressed.

Raise it to link findings that are further apart, which gives more false links. Lower it to link only very close ones. Used by: `dh_eval_cause`, `dh_tamper_finish`.

### `dh_tamper_marker_slack_secs`
**60 seconds.** A marker up to this long *after* a finding still suppresses it. Markers carry pi5's clock, and findings carry the host's clock. A marker posted later, such as one from a restore run, never hides a finding. Raise it only if the hosts' clocks drift further apart. Used by: `dh_tamper_finish`.

### `dh_tamper_hostdown_before_secs`
**600 seconds.** A held Splunk agent stop is explained by a host-shutdown record that is at most this long *before* the stop. Raise it to accept older shutdown records. Lower it if a record from an earlier, unrelated shutdown is ever matched. Used by: `dh_tamper_finish`.

### `dh_tamper_hostdown_after_secs`
**120 seconds.** The same window, after the stop. A Windows 6006 record comes just after the agent stops. Raise it and a later reboot may explain an agent stop that was not part of it. Lower it and a slow shutdown may not be matched. Used by: `dh_tamper_finish`.

### `dh_tamper_settle_secs`
**600 seconds.** A held Splunk agent stop waits this long after the agent is heard from again. Then, if nothing explains it, it becomes a finding and alerts once. The wait lets late evidence arrive: a Linux shutdown record is only sent when the VM boots. Raise it to wait longer before alerting. Lower it to alert sooner. Used by: `dh_tamper_finish`.

## Profiles and thresholds

### `dh_profile_defaults`
For each expected row's profile, gives the default silence limit and the bounds that clamp a learned limit. A [profile](../glossary.md#profile) says how an item usually sends data. The values are:
- heartbeat: 90 s.
- periodic: 2 × the interval, plus 60 s.
- continuous: 900 s. A learned limit stays between 300 and 3600 s.
- sporadic: 86400 s. A learned limit stays between 7200 and 604800 s.
- info: never alerts.

An unknown or misspelt profile is treated as continuous and reported as `invalid_profile`. Used by: the evaluator, `dh_daily_from_minutes`, `dh_ui_thresholds`.

### `dh_threshold`
Picks the silence limit that applies, and says where it came from. The order is:
1. A Manage override.
2. `max_gap_secs` on the expected row.
3. The learned value, once there are 3 covered days.
4. The profile default.

It also sets `learning` and a short note. Used by: the evaluator, `dh_ui_thresholds`.

## Statuses

### `dh_eval_mute`
Applies the active mutes: the item's own, or its host's. A host mute covers everything the host sends. Expired mutes are ignored. Used by: `dh_eval`.

### `dh_eval_liveness`
For a host row, chooses how the app judges that the host is alive. It uses the Splunk agent heartbeat for UF hosts and the device probe for devices behind the relay. Otherwise it uses any data from the host. Used by: `dh_eval`.

### `dh_eval_status`
Computes the real status:
- MUTED, or INFO.
- NEVER_SEEN.
- PENDING: new, and not yet seen.
- MISSING: silent for more than twice the limit.
- LATE: silent for more than the limit.
- OK.

It measures ages at the arrival tracker's last run. So a slow evaluator doesn't make data look late. Used by: `dh_eval`.

### `dh_eval_gate_read(meta)`
Reads the arrival tracker's run times and decides whether statuses can be trusted right now. It checks three cases: the tracker is stale, Splunk is not receiving, or the app is catching up after a pause. If any case applies, every status becomes PENDING and no alert fires. Arguments: `meta`, the run-time lookup. Used by: `dh_eval`.

### `dh_eval_transition`
Decides three things: `since` (when the current status began), `prev_status`, and whether this run is a status change worth recording. A held (PENDING) run is not a change. Neither is a new item whose first status is OK. Used by: `dh_eval`.

### `dh_eval_rollup`
Rolls a host's rows up to one of three states:
- DOWN: its liveness is missing. For a host with no agent, it is DOWN when every stream is missing.
- DEGRADED: something is late or missing.
- OK.

It also notes items that arrive through a relay that is DOWN. Used by: `dh_eval`.

## Likely cause and action

### `dh_eval_cause`
Picks the most likely cause of an item that is not OK. The first rule that fits wins. The order is:
1. The hold: the gate is closed.
2. A mute.
3. "Just added": newly expected and not yet seen.
4. A test block.
5. An Ansible stop: the host row isn't OK, and its last marker is `stop`.
6. An Ansible uninstall: the host row isn't OK, and its last marker is `uninstall`.
7. The VM is off: the host row isn't OK, and its last Hyper-V event is a power-off, a shutdown or a save.
8. A tamper finding near the start of the silence.
9. A relay is down.
10. The device probe: the device doesn't answer, the probe stopped reporting, or the device answers but sends no logs.
11. The agent heartbeat: late, or missing.
12. A silent *hl:devprobe* row while its host's heartbeat is OK: the probe stopped reporting.
13. The agent works, but this input has never sent anything.
14. The agent works, but every input is missing.
15. The agent works, but this input stopped.
16. The host has no data at all, and it has no agent.
17. The item never arrived since it was added.
18. Everything from a host with no agent is late or missing, but the host isn't DOWN (`host_late`).
19. Last of all, "this stream stopped".

An item that is not LATE, MISSING or NEVER_SEEN gets a cause only for rules 1 to 3. A tamper finding counts at rule 8 only if the role's own marker doesn't explain it. Used by: `dh_eval`.

### `dh_eval_cause_text`
Turns each cause code into two sentences. One is the plain sentence shown in the Cause column. The other is the next step shown in the Action column. For example: "Start it again with the role: ansible-playbook site.yml --tags start --limit wd2l-recv". The texts use the names the panels use, such as "Splunk agent" instead of UF or splunkd. They say what any command does. [The runbook](../runbook-missing-data.md#causes-in-the-order-the-app-checks-them) lists every cause with what to do about it. The Cause column's times are built when *DH Evaluate* runs. They use the scheduler's time zone and end with its name. Used by: `dh_eval`.

## Evaluator steps over lookups

### `dh_eval_load(expected, state_fast, state_slow)`
Loads the enabled expected rows. It joins each row with the latest arrival at its level (source, sourcetype or whole host). It takes the later of the fast and slow trackers. Arguments: the expected list and the two arrival tables. Used by: `dh_eval`.

### `dh_eval_facts(fwd, overrides, baseline, tamper, prev)`
Adds the facts each row needs:
- The Splunk agent heartbeat, the last Ansible marker, and the last Hyper-V event and device probe, by host.
- The item's own override and its host's override.
- The learned baseline.
- The tamper findings on the host. A row that arrives through Cribl also gets the findings on host *cribl*, with those that a marker suppresses marked as such. A finding that is still pending (a Splunk agent stop that waits for its evidence) is marked the same way, on the host and on *cribl*, so it explains nothing. A finding with an empty or missing state counts as judged.
- The previous status.

Used by: `dh_eval`.

### `dh_eval_blocks(blocks)`
Marks rows that an active test block covers. A block covers a whole host, a sourcetype, or one exact raw source. The cause then says "test block until hh:mm". Only the linux, windows and network indexes can be blocked. Arguments: `blocks`, the test-block table. Used by: `dh_eval`.

### `dh_eval_output`
Shapes each row into the `dh_status` record, which holds the fields the dashboards read. It stamps the record with `evaluated_at`. Used by: `dh_eval`.

## The evaluator

### `dh_eval(expected, state_fast, state_slow, fwd, overrides, baseline, meta, blocks, tamper, prev, now)`
The whole evaluator. It chains the steps above, reads only lookups and writes nothing. `now` is the time to evaluate at, so the tests can use a fixed clock. Used by: `dh_evaluate`, `tests/spl/run.sh`.

### `dh_evaluate`
`dh_eval` over the real collections at the current time. Used by: *DH Evaluate*.

### `dh_transition_rows`
From the evaluator's output, takes the rows whose status changed. It shapes them as transition events. It renames the item's host to `dh_host` so that Splunk doesn't overwrite it. Used by: *DH Evaluate*.

### `dh_collect_transitions`
Writes those rows to `index=data_health source=dh:transition`. The alerts, the Recently recovered panel and the daily report read them. Used by: *DH Evaluate*.

### `dh_status_keep(expected, status)`
Lets *DH Evaluate* drop the `dh_status` rows of items that are no longer expected. When there are such rows, it returns the fresh rows for a full rewrite. Otherwise it returns nothing. Nothing is dropped while the expected list is empty. Arguments: `expected`, `status`. Used by: *DH Evaluate*.

## Tracker steps

### `dh_state_merge(state, now)`
Merges a minute's arrival counts with what the table already holds. The latest times win, and the earliest first-seen time stays. Only keys that saw new data are rewritten. Arguments: `state`, the table being updated; `now`. Used by: *DH Tracker fast*, *DH Tracker slow*.

### `dh_fwd_from_hb`
The Splunk agent heartbeats, per host. Each agent reports its own metrics every 30 s. The indexer's own host is left out. Used by: *DH Tracker fast*.

### `dh_fwd_from_ufint`
Reads each agent's own log lines. From them it takes three facts:
- The agent's last connection to Cribl ("Connected to idx=", every 30 s).
- Its operating system and processor type, from the lines it writes at each start.
- Its build, which the `dh_uf_builds` table turns into a version.

Splunk now sees only Cribl's connection, so it can't name the agents itself. Splunk's own lines are left out. Used by: *DH Tracker fast*.

### `dh_fwd_from_markers`
The latest Ansible [marker](../glossary.md#marker-ansible-marker) per host. It gives the action (`stop`, `start` and so on), who ran it and the run id. Used by: *DH Tracker fast*.

### `dh_fwd_from_hyperv`
The latest [Hyper-V](../glossary.md#hyper-v) lifecycle event per VM: started, turned off, shut down, saved or reset. It reads them from the Windows Worker-Admin log. Used by: *DH Tracker fast*.

### `dh_fwd_from_probe`
The latest device-probe result per device (reachable or not). It comes from hl-devprobe on pi5. Used by: *DH Tracker fast*.

### `dh_fwd_fold(fwd, now)`
Merges the five sources above with the existing `dh_fwd` rows. It keeps the latest value of each fact. Arguments: `fwd`, the agent-facts table; `now`. Used by: *DH Tracker fast*.

### `dh_meta_fast(meta, now)`
Writes the arrival tracker's run record. The record holds this run's time, the previous run, the last time anything arrived, and the time of the last pause. A gap over `dh_resume_gap_secs` counts as a pause. Arguments: `meta`; `now`. Used by: *DH Tracker fast*.

## Tunables for baselines, volume, tamper and pruning

### `dh_clock_step_secs`
**300 seconds.** A clock change at least this large, as the operating system reports it, is a tamper finding ("big clock step"). Raise it to ignore bigger time corrections. Lower it to catch smaller ones, though normal NTP corrections may then show. Used by: `dh_tamper_win`, `dh_tamper_linux`.

### `dh_tamper_lookback_secs`
**604800 seconds (7 days).** How old a finding *DH Tamper* still writes to the index. It writes a finding if the finding is new, or if its stored suppression isn't there yet. An older finding is never alerted again. Keep this inside the indexes' 14-day retention, because *DH Tamper* reads what it already wrote. Keep it equal to `dh_tamper_finding_earliest`. Used by: `dh_tamper_finish`.

### `dh_tamper_finding_earliest`
**`-7d`.** The event-time window that *DH Tamper* reads findings from. Widen it to catch findings that arrive later, for example after slower runs. Narrow it to read less. It must match `dh_tamper_lookback_secs`, and a test checks this. Used by: *DH Tamper*.

### `dh_tamper_marker_earliest`
**`-7d-15m`.** The window for Ansible markers. It is the findings' window plus `dh_tamper_window_secs`, so a finding at the edge still meets its marker. Change it only together with the findings' window. If it is narrower, an old finding loses its marker and is reported as tamper. If it is wider, it only costs time. Used by: *DH Tamper*.

### `dh_volume_ratio`
**0.2 (20 %).** An hour is a volume drop when it has fewer than this share of its usual count for that hour of day. Raise it to flag milder drops. Lower it to flag only near-silence. Used by: `dh_volume_flag`.

### `dh_volume_min_median`
**100 events.** Volume drops are flagged only where the usual hourly count is at least this. So quiet streams don't flap. Raise it to watch only busier streams. Lower it to watch quieter ones, with more noise. Used by: `dh_volume_flag`.

### `dh_volume_min_up_minutes`
**54 minutes.** An hour is judged only if Splunk was up for at least this many of its minutes. Otherwise its low count is Splunk's fault. Raise it to judge only fully covered hours. Lower it to judge partial ones. Used by: `dh_volume_flag`.

### `dh_suggest_continuous_secs`
**1800 seconds.** In the baseline, an item whose typical longest daily silence is at most this long is suggested as `continuous`. Any other item is suggested as `sporadic`. Raise it to suggest continuous for gappier streams. Lower it to suggest sporadic more often. It is only a suggestion, shown on Manage. Used by: `dh_baseline_compute`.

### `dh_state_retention_secs`
**2592000 seconds (30 days).** Arrival rows older than this are pruned daily, if no expected item uses them. Raise it to keep the history of retired streams longer. Lower it to keep the tables smaller. Used by: `dh_prune_mark_state`.

### `dh_fwd_retention_secs`
**2592000 seconds (30 days).** Agent-facts rows are pruned daily when they have not been updated for this long and their host is no longer expected. Raise it to keep facts about retired hosts longer. Lower it to forget them sooner. Used by: `dh_prune_mark_fwd`.

### `dh_tamper_retention_secs`
**2592000 seconds (30 days).** Tamper findings older than this are pruned from the collection. The `data_health` index keeps them for 14 days, its retention. Raise it to keep them on Host detail longer. Lower it to keep the collection smaller. Used by: `dh_prune_mark_tamper`.

### `dh_volume_retention_secs`
**172800 seconds (2 days).** Volume rows that have not been updated for this long are pruned. Raise it to keep stale hourly rows longer, though nothing reads them. Lower it to clean up sooner. Used by: `dh_prune_mark_volume`.

### `dh_baseline_retention_secs`
**2592000 seconds (30 days).** Baseline rows that have not been recomputed for this long are pruned, because the item stopped sending. Raise it to keep what the app learned about a stream that comes back after a long break. Lower it to forget that sooner. Used by: `dh_prune_mark_baseline`.

### `dh_admin_retention_secs`
**7776000 seconds (90 days).** Admin-log rows older than this are pruned from the collection, once they are copied to the index. Raise it to see more history on Manage. Lower it to keep the table small. The index keeps a copy for 14 days, its retention. Used by: `dh_prune_mark_admin_log`.

### `dh_fwd_expected_version`
**`10.6.1.1`.** The Splunk agent version the role installs. The daily report lists agents on another version, and Host detail flags them. Change it when the role pins a new version. Used by: `dh_soh_fwd`, `dh_ui_fwd`.

### `dh_fwd_disconnect_secs`
**900 seconds.** The daily report lists an agent as disconnected when it has had no heartbeat or connection for this long. Raise it to list only longer silences. Lower it to list shorter ones. Used by: `dh_soh_fwd`.

### `dh_lag_warn_secs`
**60 seconds.** The daily report lists a sourcetype as slow when its data usually arrives at least this long after it was written. "Usually" means the 95th percentile. Raise it to list only very slow ones. Lower it to list more. Used by: `dh_soh_lag`.

## Summary writes

Each macro here writes rows to the `data_health` index as sourcetype `stash`. That sourcetype doesn't count against the licence.

### `dh_collect_daily`
Writes the per-day records (`source=dh:daily`). Used by: *DH Baseline daily*.

### `dh_collect_volume`
Writes the flagged volume hours (`source=dh:volume`). Used by: *DH Volume hourly*.

### `dh_collect_tamper`
Writes new tamper findings and suppression changes (`source=dh:tamper`). Used by: *DH Tamper*.

### `dh_collect_admin`
Writes copies of the admin log (`source=dh:admin`). Used by: *DH Admin log copy*.

### `dh_collect_soh`
Writes the daily report rows (`source=dh:soh`). Used by: *DH Daily SoH report*.

## Baselines (DH Baseline daily and compute)

### `dh_daily_from_minutes(fwd, expected)`
For each item and each completed day, works out these facts:
- How many events arrived, and in how many active minutes.
- The longest silence and the 95th-percentile silence.
- How late the data arrived.
- The hourly counts.

Only minutes when Splunk was up count. For agent hosts the agent must have been up too. So PC sleep never looks like silence. A silence still open at midnight carries into the next day. Days and hours are UTC, whatever time zone the search runs in. Arguments: `fwd`, `expected`. Used by: *DH Baseline daily*.

### `dh_daily_todo(now)`
The completed days of the last 13 that have no daily record yet. So a missed night is caught up on the next run. It looks back 13 days, not 14. The indexes keep 14 days, so the raw data of the day that began 14 days ago may already be partly gone. Filling that day in would record a silence that never happened. Used by: *DH Baseline daily*, `dh_daily_window`.

### `dh_daily_window(now)`
The time window that covers those days. It is empty when nothing is due. Used by: *DH Baseline daily*.

### `dh_baseline_compute(days, now)`
Works from the daily records of the last `days` days. It gives these facts:
- The learned silence limit. It is 1.5 × the 90th percentile of the daily longest silence, plus 120 s, before the profile's clamp.
- How many days were covered. Days under 50 % covered are skipped.
- The usual count for each hour of the day.
- A suggested profile.

Used by: *DH Baseline compute*.

## Volume (DH Volume hourly)

### `dh_volume_flag(baseline, now)`
Compares the last full hour's count per item with its usual count for that hour of day. It flags a drop below `dh_volume_ratio`. It flags only when three things hold: the usual count is at least `dh_volume_min_median`, Splunk was up, and there are 3 days of history. Used by: *DH Volume hourly*.

## Tamper (DH Tamper)

### `dh_tamper_win`
Finds Windows tamper indicators:
- The security or event log was cleared (1102, 104).
- Event logging was shut down (1100).
- The audit policy changed (4719).
- A service was installed (4697, 7045).
- The Splunk agent or Event Log service stopped, or its start type changed (7036, 7040).
- Big clock steps.

It checks the provider as well as the event ID. Used by: *DH Tamper*.

### `dh_tamper_linux`
Finds Linux tamper indicators:
- auditd stopped or aborted.
- The audit rules changed.
- The Splunk agent, auditd or rsyslog stopped.
- Events of the `hl-*` and `wd2l-*` audit keys.
- Big clock steps.

Used by: *DH Tamper*.

### `dh_tamper_ufstop(fwd)`
Reads the Splunk agent's own log in `_internal`. The line "Shutting down splunkd" is the agent's own record that it stopped, and it becomes a finding with the code *uf_shutdown*. Only hosts that `fwd` (the *dh_fwd* lookup) lists as a universal forwarder count. A full Splunk server restarts for ordinary reasons, so it never raises a finding. Used by: *DH Tamper*.

### `dh_tamper_hostdown`
Reads evidence that the whole host shut down, not only the Splunk agent. On Windows that is event 1074 (names the user and the reason) and event 6006 (the event log service stopped). On Linux it is the audit record SYSTEM_SHUTDOWN. A 1074 or SYSTEM_SHUTDOWN ranks first, so it wins over a 6006 when both are close. Used by: *DH Tamper*.

### `dh_tamper_cribl`
Reads Cribl's audit log. Any create, update, delete, reorder or upload of routes, pipelines, outputs, inputs or lookups is a finding on the host *cribl*. The log can't tell a Drop function from any other pipeline edit, so every such change counts. The role's own changes fall inside its *cribl* and *cribl_block* marker windows, so they are suppressed. Used by: *DH Tamper*.

### `dh_tamper_finish(tamper, now)`
Groups indicators into findings. There is one finding per host, kind and 5-minute bucket. It then decides, once, whether each new finding is the role's own work.
- A finding is suppressed when an Ansible marker for its host came at most `dh_tamper_window_secs` before it. A marker that came at most `dh_tamper_marker_slack_secs` after it also counts.
- A stored finding keeps its suppression on every later run. So a later marker never hides it.
- If the finding's `dh_tamper` row is gone, the latest `dh:tamper` record (by index time) gives the stored state.
- A Splunk agent stop, and the host-shutdown records that come with it, is held as pending. A marker, a host-shutdown record, or the agent coming back and settling then judges it. A pending finding never alerts. A judged one never changes.
- It also marks which findings of the last 7 days still need writing to the index. An older finding never does, because the index keeps 14 days and the collection keeps 30.

Used by: *DH Tamper*.

### `dh_tamper_fold(now)`
One service install logs two Windows events: a 7045 (System log) and a 4697 (Security log). This step puts the pair into one finding, "7045+4697 service installed: …". Its detail holds both event IDs. The two events match on the service's key name or its program path. They must be at most `dh_tamper_window_secs` apart. Either event can arrive first. If one half is already stored and alerted, the other half joins that finding. So a service install alerts once. Findings stored before this step existed stay as they are. Used by: `dh_tamper_finish`.

It also folds the Splunk agent stop. The agent can log a shutdown line, a SERVICE_STOP and a 7036 stop for the same stop. If two of those different codes are on one host within `dh_tamper_window_secs`, they make one finding, "Splunk agent stopped (SERVICE_STOP + shutdown line)". The parts are in time order. A 7036 for another service (such as the event log) never folds, and two lines of the same code never fold with each other.

### `dh_tamper_collect_rows`
Shapes findings for writing to the index. Used by: *DH Tamper*.

## Alerts

### `dh_alert_missing_rows`
The transitions to MISSING of items with criticality 1 or 2. An item with no criticality counts as 2. Used by: *DH Alert missing*.

### `dh_alert_tamper_rows`
The new tamper findings that are not suppressed. Used by: *DH Alert tamper*.

## Admin log copy

### `dh_admin_copy_rows(meta, now)`
The admin-log rows written since the last copy, and at least 60 s old. They are ready to copy to the index. Used by: *DH Admin log copy*.

## Prune

Each "mark" macro marks the rows to delete. A prune search rewrites a table only when something is marked.

### `dh_prune_mark_overrides(now)`
Clears expired mutes. It deletes an override row that has nothing left. Used by: *DH Prune* (every minute).

### `dh_prune_mark_status(expected)`
Marks the `dh_status` rows of items that are no longer expected. It marks none while the expected list is empty. Used by: `dh_status_keep`.

### `dh_prune_mark_state(expected, now)`
Marks arrival rows older than `dh_state_retention_secs` that no expected item uses. Used by: `dh_prune_mark_dh_state_fast`, `dh_prune_mark_dh_state_slow`.

### `dh_prune_mark_fwd(expected, now)`
Marks agent-facts rows not updated for `dh_fwd_retention_secs`, of hosts that are no longer expected. Used by: `dh_prune_mark_dh_fwd`.

### `dh_prune_mark_tamper(now)`
Marks tamper findings older than `dh_tamper_retention_secs`. Used by: `dh_prune_mark_dh_tamper`.

### `dh_prune_mark_volume(now)`
Marks volume rows older than `dh_volume_retention_secs`. Used by: `dh_prune_mark_dh_volume`.

### `dh_prune_mark_baseline(now)`
Marks baseline rows not updated for `dh_baseline_retention_secs`. Used by: `dh_prune_mark_dh_baseline`.

### `dh_prune_mark_admin_log(meta, now)`
Marks admin-log rows older than `dh_admin_retention_secs` that were already copied to the index. Used by: `dh_prune_mark_dh_admin_log`.

### `dh_prune_mark_dh_state_fast`
`dh_prune_mark_state` over the real `dh_state_fast`. Used by: *DH Prune daily*, which calls `dh_prune_mark_<collection>` by name.

### `dh_prune_mark_dh_state_slow`
`dh_prune_mark_state` over the real `dh_state_slow`. Used by: *DH Prune daily*.

### `dh_prune_mark_dh_fwd`
`dh_prune_mark_fwd` over the real `dh_fwd`. Used by: *DH Prune daily*.

### `dh_prune_mark_dh_tamper`
`dh_prune_mark_tamper` at the current time. Used by: *DH Prune daily*.

### `dh_prune_mark_dh_volume`
`dh_prune_mark_volume` at the current time. Used by: *DH Prune daily*.

### `dh_prune_mark_dh_baseline`
`dh_prune_mark_baseline` at the current time. Used by: *DH Prune daily*.

### `dh_prune_mark_dh_admin_log`
`dh_prune_mark_admin_log` over the real `dh_meta`. Used by: *DH Prune daily*.

## Daily state of health report

Each section macro turns its input into report rows. A row has `section`, `item` and `value`, plus a few extras.

### `dh_soh_outages(status, now)`
Works from the transitions of the last 7 days. It lists each outage, which is a stretch of LATE, MISSING or NEVER_SEEN, that ended in the last 24 hours or is still open. Each row gives the duration and how it ended (`end_status`). It also gives the mean time to recover.
- An outage counts as open only while `dh_status` still shows the item as bad.
- An item that went bad more than 7 days ago and is still bad is listed too. It shows as open since its `since` time.

Used by: *DH Daily SoH report*, `dh_ui_recovered`.

### `dh_soh_flapping(now)`
Items with 3 or more status changes in the last 24 hours. Used by: *DH Daily SoH report*.

### `dh_soh_status`
Reads `dh_status`. It lists items that never arrived, and expected rows with a profile the app doesn't know. Used by: *DH Daily SoH report*.

### `dh_soh_fwd(now)`
Agents on a different version than `dh_fwd_expected_version`, and agents silent for `dh_fwd_disconnect_secs`. Used by: *DH Daily SoH report*.

### `dh_soh_mutes(now)`
Active mutes, and the mutes that end within 24 hours. Used by: *DH Daily SoH report*.

### `dh_soh_lag`
Sourcetypes whose 95th-percentile arrival delay on the latest day is at least `dh_lag_warn_secs`. Used by: *DH Daily SoH report*.

### `dh_soh_volume(now)`
Items with flagged volume drops in the last 24 hours. It gives how many hours were flagged and the lowest ratio. Used by: *DH Daily SoH report*.

### `dh_soh_licence(now)`
Yesterday's indexed bytes against the active licence's daily quota. It also gives the days until the licence expires. Used by: *DH Daily SoH report*.

### `dh_soh_skipped`
This app's scheduled searches that were skipped in the last 24 hours, with a total. Used by: *DH Daily SoH report*.

## Dashboard macros

These macros hold the SPL behind the dashboard panels, so the tests run exactly what the panels run. [dashboards.md](dashboards.md) explains the panels themselves.

### `dh_ui_time_fmt`
**`%Y-%m-%d %H:%M`.** How dates are shown in dashboard tables. Used by: most `dh_ui_*` macros.

### `dh_ui_time_fmt_tz`
**`%Y-%m-%d %H:%M %Z`.** The same format with the time zone. It is used for every time shown on Manage, and for the Unregistered list, which Daily state of health shares. Times follow the viewer's Splunk time zone, so the zone is spelled out. Used by: the Manage macros below, `dh_ui_unregistered`.

### `dh_ui_item_words(id)`
Shows an Item ID (`level|index|host|sourcetype|source`) in words. Examples are `pi5: whole host`, `pi5 › syslog (enclave1)` and `pi5 › linux_secure › /var/log/secure (linux)`. Anything else comes back unchanged. Arguments: `id`, the field or expression that holds the ID. Only what is shown changes. The stored IDs stay as they are. Used by: the Manage lists, previews, results and tables, `dh_ui_thresholds`.

### `dh_ui_block_words(k)`
Shows a test-block key in words. A key looks like `host|*|*`, `host|sourcetype|*` or `host|sourcetype|raw source`. Examples are `pi5: whole host`, `pi5 › syslog` and `pi5 › linux_secure › /var/log/secure.1 (exact source)`. Arguments: `k`, the key. Used by: Manage, Test blocks tab and Admin log.

### `dh_ui_action_words(action)`
Shows an admin-log action code in words:
- `override_mute`: Mute.
- `override_unmute`: Unmute.
- `override_threshold`: Set limit.
- `override_clear`: Clear limit.
- `expected_add`: Add expected row.
- `expected_adopt`: Adopt.
- `expected_retire`: Retire.
- `expected_unretire`: Undo retirement.
- `block_add`: Add test block.
- `block_remove`: Remove test block.

The codes stay in the admin log. Used by: the Manage plan macros, `dh_ui_log_words`.

### `dh_ui_secs_words(secs)`
Shows a number of seconds in words. It uses whole days, hours or minutes (`7 days`, `1 hour`, `20 minutes`), and otherwise seconds (`90 s`). Used by: the Manage previews and Confirm choices, `dh_ui_overrides`.

### `dh_ui_origin_words(origin)`
Shows where an item's limit comes from (the origin code of `dh_threshold`) in words:
- Override (set on Manage).
- Fixed limit on its expected row.
- Learned from its history.
- Profile default.
- Profile default (the row's profile is unknown).
- None (INFO: never alerts).

Used by: `dh_ui_thresholds`, `dh_ui_host_children`.

### `dh_ui_log_words`
Prepares admin-log rows for display. It shows the action and the item in words. It shows the time with its zone. It shows the `->` in the detail as `→`, and names `managed_by` and `threshold` as `managed by` and `limit`. The stored row is not changed. Used by: `dh_ui_log`, `dh_ui_admin_log`.

### `dh_ui_admin_log(admin_log)`
The admin log for display, newest first, with the words its search box looks in. Used by: Manage, Admin log tab.

### `dh_ui_hay_filter`
The search box of a table. It keeps the rows that contain every word of the box. Words are separated by `*`, are not case-sensitive, and are compared literally, as in `dh_ui_filter`. A lone `*` keeps everything. Used by: Manage, Admin log tab.

### `dh_ui_overrides(overrides)`
The mutes and limit overrides in force, for display. It shows the item in words, when the mute ends, and the limit override in words, with their zone. Used by: Manage, Current mutes and limit overrides.

### `dh_ui_blocks(blocks, now)`
The current test blocks, for display. It shows the key in words, until when (with its zone), and whether each block is still active. A row with the key `-` is left out. Used by: Manage, Current test blocks.

### `dh_ui_indexes`
The index choices of Manage's Add-row form. It reads `dh_indexes` at run time, so the list of watched indexes lives in one place. The add-row check uses `dh_indexes` too. Used by: Manage, Expected list tab, Index.

### `dh_ui_headers`
The plain column headers of every dashboard table. For example, it shows "Silent for / limit" instead of `age_vs_threshold`, and "Host" instead of `host`. It is the last step of each table's search. The macros and tests keep the field names. Used by: every table panel.

### `dh_ui_current_secs`
**150 seconds.** The dashboards ignore a `dh_status` row that is more than this behind the newest one. That row belongs to an item that is no longer expected and hasn't been cleaned up yet. The evaluator rewrites every row once a minute, so this is two and a half runs. Raise it if the evaluator is often slow. Lower it to hide retired items sooner. Used by: `dh_ui_status`, `dh_ui_status_attrs`.

### `dh_ui_eval_stale_secs`
**180 seconds.** If the evaluator hasn't written statuses for this long, the banner says "Out of date". Raise it to tolerate a slow scheduler. Lower it to warn sooner, though one late run may then trip it. Used by: `dh_ui_banner`.

### `dh_ui_status(status)`
The current rows of `dh_status` (see `dh_ui_current_secs`). Used by: the Overview, Host detail and Manage panels.

### `dh_ui_filter`
Applies the Overview filters: site, owner, index, criticality, status and search text. The dashboard sets the filter values as fields first. The search text is words separated by `*`. All of them must appear in the item, its description or its cause. They are compared literally, so `%`, `_` and `.` mean themselves. Used by: the Overview panels, Manage's threshold table.

### `dh_ui_kpi`
The KPI tile numbers for hosts, sourcetypes and sources, each counted separately. The numbers are expected, OK, late, missing (including never seen), muted, and waiting (PENDING). Used by: Overview, KPI tiles.

### `dh_ui_attention(now)`
One row per host that has late, missing or never-seen data, worst first. A row shows the host's children, since when, the likely cause and the next action. Used by: Overview, Needs attention.

### `dh_ui_attention_headline`
The one-line summary above Needs attention. It says all is fine, how many hosts need attention, or that the app is on hold. Used by: Overview, How many hosts need attention.

### `dh_ui_banner(meta, status, now)`
The banner text and colour: Up to date, On hold, Out of date or Catching up. See [the banner states](dashboards.md#the-banner-is-the-data-current). Used by: Overview, Is the data current?

### `dh_ui_tamper_24h(status, now)`
The unsuppressed tamper findings first seen in the last 24 hours. "First seen" is when the app recorded the finding, so late findings count. It gives one row per finding, with the host's filter attributes. Used by: Overview, Tamper findings.

### `dh_ui_status_attrs(status)`
Adds the filter attributes of each row's item, taken from the current `dh_status` rows. The attributes are site, owner, criticality, status, roll-up and description. So the Overview filters also apply to recoveries and tamper findings. Used by: `dh_ui_tamper_24h`, `dh_ui_recovered`.

### `dh_ui_recovered(status, now)`
The outages that ended with a return to OK in the last 24 hours. A mute or an INFO profile is not a recovery. Used by: Overview, Recently recovered.

### `dh_ui_host_children(volume)`
One host's expected rows. A row shows the status, the age against its limit, the profile, and where the limit comes from (in words, `dh_ui_origin_words`). It shows any mute or test block, with its time zone. It also shows last hour's volume. Used by: Host detail, Expected data from this host.

### `dh_ui_fwd(now)`
One host's Splunk agent facts as readable lines. The lines are the version (flagged if it isn't the expected one), the OS, the last heartbeat and the last connection. The rest are the last Ansible marker, the last VM event and the last probe. Used by: Host detail, Forwarder.

### `dh_ui_hyperv`
Hyper-V Worker-Admin events, with the VM name and what each event ID means. Used by: Host detail, Hyper-V VM events.

### `dh_ui_thresholds(baseline, expected)`
For each item, gives the limit actually applied and where it comes from, in words. It also gives these values:
- The learned value after and before its clamp.
- The profile default.
- The configured limit.
- The covered days.

The item in words comes first. Used by: Manage, Thresholds.

### `dh_ui_unregistered(expected, state_fast, state_slow, baseline, now)`
Sourcetypes and hosts that sent data in the last 7 days but are not on the expected list. Each row has a suggested profile. Times carry their zone. Used by: Manage (Unregistered, and the Adopt list), Daily state of health.

### `dh_ui_actor`
Who is signed in, and all their roles, including roles they inherit. The answer comes from the server, never from the page. Used by: the Manage previews and writes.

### `dh_ui_roles_expand`
Adds the roles that the user's roles import, three levels deep. If the user may not read the role list, only their own roles count. Used by: `dh_ui_actor`.

### `dh_ui_roles_step`
One level of that expansion. Used by: `dh_ui_roles_expand`.

### `dh_ui_host_terms`
Turns a host name picked on a dashboard into a safe search filter. The filter matches that host and its FQDN form. Anything that isn't a plain host name matches nothing. So text from the page never becomes part of a search. Used by: Host detail (chart, agent errors), Manage (raw sources).

### `dh_ui_clean(fields)`
Trims form values. An empty value or `-` means "none". Arguments: `fields`, the field names. Used by: the Manage plan macros.

### `dh_ui_override_plan(overrides, admin_log, now)`
Checks a mute, unmute, set-limit or clear-limit request. A reason is required, and a mute ends within 30 days. It returns these things:
- What is logged: `before`, `after` and `action`.
- What the preview shows in words: `ui_change`, `ui_item`, `ui_now`, `ui_after` and `check`.
- The text of the Confirm choice (`dh_label`). An example is "Apply: mute pi5 › syslog (enclave1) for 1 hour".
- The confirmation code that the choice carries.

The code also covers the item's admin-log times (`admin_log`). So a confirmation fits only once. After DH Prune removes an expired mute, the old state is back, but the log is not. Used by: Manage, Mute & thresholds tab.

### `dh_ui_override_write(overrides, admin_log, now)`
Writes the override when the confirmation matches the current state, and logs it. A repeat or stale confirmation writes nothing. Used by: Manage, Mute & thresholds tab.

### `dh_ui_expected_plan(expected, admin_log, now)`
Checks a new or changed expected row. These rules apply:
- Only `admin` or `dh_admin` may change it.
- The index must be one of `dh_indexes`.
- Ansible-managed rows are refused.

It shows the row before and after, in words for the preview and as logged. It gives the row's Confirm text and confirmation code. The code also covers the item's admin-log times, so a confirmation fits only once. That holds even when the change left the row as it was, because a reload or a revisited tab re-runs the write. Arguments: `admin_log`, the admin log. Used by: Manage, Expected list tab (add and adopt).

### `dh_ui_expected_write(expected, admin_log, now)`
Writes the expected row when the confirmation matches, and logs it. Used by: Manage, Expected list tab (add and adopt).

### `dh_ui_adopt_row(baseline, fwd)`
Turns an unregistered item into an expected-row request. Agent hosts become `uf`, and others become `syslog`. An agent host's own row gets the `heartbeat` profile. Any other row takes the baseline's suggestion, or continuous if there is none. Used by: Manage, Expected list tab (adopt).

### `dh_ui_retire_plan(expected, admin_log, nonce, now)`
The retire form's preview (Manage > Expected list). It takes one request: an expected item, Retire or Undo, a reason and an optional ticket. A whole host takes every row of that host.
- **Retire:** each enabled row gets `enabled=0`, who retired it, when and why, and `retired_hold=1`. Every other field stays, including who manages it.
- **Undo:** an Ansible row stops being held, and *DH Sync expected* adds it back. A row added in Manage is enabled again with a new grace period.
- Nothing is deleted.

It needs the dh_admin role (or Splunk's admin). The confirmation token also covers the retire key in `dh_retire_nonce`. Only admin and dh_admin can read that key. So a Manage link built by someone else can't apply a retirement. Used by: Manage.

### `dh_ui_retire_write(expected, admin_log, nonce, now)`
Applies a retire preview when its confirmation matches. It writes each row whole, changes the retire key, and adds one admin-log row per row. Used by: Manage.

### `dh_ui_retire_choices(expected)`
The retire form's item list. It shows each host as a whole, then its rows. It lists only the rows that the chosen action applies to: expected rows for Retire, and retired rows for Undo. Used by: Manage.

### `dh_ui_retire_candidates(status, now)`
Expected items with no data for at least `dh_retire_candidate_secs`, or never seen though expected for that long. Muted items are included. Used by: Manage (Retirement candidates).

### `dh_ui_block_command`
The test block lives in Cribl, so Manage shows the command to run instead of writing the block. The command is the role's *cribl_block* line for a checked request, which either sets a block (with minutes and a reason) or clears it. The key is in plain single quotes. The reason is cut down to plain characters. Used by: Manage, Test blocks tab.

### `dh_ui_block_plan(blocks, now)`
Checks a test-block request against Splunk's copy of the block table. It shows the block before and after, in words for the preview and as logged. It also shows the normalized source, for reference. These rules apply:
- It needs the dh_admin role (or Splunk's admin).
- A block lasts 1 minute to 24 hours.
- A source block needs an exact raw source.
- A sourcetype or source with a character the command can't carry is refused. Examples are a quote, `$`, a comma, a space or `{`.

Nothing is written from here. When the check says OK, `dh_ui_block_command` gives the role's command. Used by: Manage, Test blocks tab.

### `dh_ui_log(admin_log, now)`
Adds one admin-log row per applied change. It returns the result in words: "Done: Mute pi5: whole host", or "Nothing written: …" when the confirmation no longer fits. What is stored is unchanged. Used by: the three write macros (`dh_ui_override_write`, `dh_ui_expected_write`, `dh_ui_retire_write`).

## The expected list: sync and discovery

The role's `expected` tag writes `dh_expected_ansible.csv` from the inventory. *DH Sync expected* merges that file into `dh_expected` every 5 minutes, and right after each push. An enabled row added on the Manage dashboard is never overwritten.

### `dh_sync_rows(ansible)`
The Ansible rows, cleaned up the way a Manage row is:
- Level and host are lowercase, and the host's domain is dropped.
- Index and sourcetype are kept only below host level.
- The raw source is kept for a source row.
- The item ID is built from these parts.

A row that the file marks disabled counts as not in the file. Rows with an unknown level or no host are dropped. Arguments: `ansible`, the Ansible file. Used by: `dh_sync_plan`.

### `dh_sync_sig`
One fingerprint of the fields Ansible owns. Those fields are level, index, host, sourcetype and source. They also include collection, via, hypervisor, profile, interval and maximum gap. The last ones are criticality, owner, site, runbook and description. An unchanged row is never rewritten. Used by: `dh_sync_plan`.

### `dh_sync_plan(ansible, expected, now)`
The rows *DH Sync expected* writes, each with its reason:
- **add:** the row is new, or it was disabled before. A disabled Manage row counts too.
- **update:** a field Ansible owns changed. The "expected since" time is kept.
- **retire:** an Ansible row left the file, or the file marks it disabled. It is switched off, so its status goes. A later re-add starts a fresh grace period.
- **release:** a row retired in Manage that the file no longer lists. It stops being held and stays retired.

It also returns two kinds of row that it never writes. *DH Sync expected* counts them:
- **held:** the file still lists a row that was retired in Manage. The retirement holds until the inventory drops the row.
- **shadowed:** an enabled Manage row wins over the same item in the file.

A write carries the row's retirement fields, which Ansible doesn't own. The plan returns only the rows that change, plus the held and shadowed ones. It writes them as `_key` upserts, so `dh_expected` is never rewritten whole. A whole rewrite would matter, because DH Evaluate drops the status of any item missing from `dh_expected`. An enabled Manage row is never overwritten, even when Ansible lists the same item. Nothing is written while the Ansible file has no valid rows, so an empty or broken file can't retire the list. Arguments: the Ansible file, the expected list, `now`. Used by: *DH Sync expected*.

### `dh_discover_summary(expected, state_fast, state_slow, baseline, now)`
One summary row of what arrives without being expected: how many items, how many hosts, and up to 50 of their IDs. These are the same rows as Manage's adopt list and the Daily report's unregistered section. Used by: *DH Discover unregistered*.
