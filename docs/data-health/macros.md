# hl_data_health macros: what each one is for

This is the reference for every search macro in `splunk/apps/hl_data_health/default/macros.conf`, in the same order and groups as the file. It is a **living document**: any change that adds, renames or removes a macro updates this file in the same pull request. `tests/spl/run.sh` fails (check `docs-coverage`) when a macro has no entry here, or when an entry names a macro that no longer exists.

## The pipeline in one paragraph

Every minute, the **arrival tracker** (saved search *DH Tracker fast*) records when each index, host, sourcetype and source last delivered data, and when each forwarder last called in; an hourly twin (*DH Tracker slow*) backfills the same facts. Every minute after that, the **evaluator** (*DH Evaluate*) compares those times with the **expected list** (`dh_expected`), works out a status for each expected entity (OK, LATE, MISSING, …) with a likely cause and a next action, and writes the result to the `dh_status` collection; every status change is also written to the `data_health` index as a *transition*. Nightly and hourly searches learn what is normal (*DH Baseline daily*, *DH Baseline compute*, *DH Volume hourly*), look for signs of tampering (*DH Tamper*), tidy up (*DH Prune*), and write the daily report (*DH Daily SoH report*). The **alerts** read the transitions and tamper findings, and the **dashboards** read `dh_status` and the summary events. Each macro below is one step of this pipeline.

**Words used below.** An *entity* is one thing that should send data: a host, a sourcetype on a host, or one source of a sourcetype on a host. Its `entity_id` is `level|index|host|sourcetype|source`, with `*` for the parts its level doesn't use. A *collection* is a KV store table. *Epoch* means seconds since 1970 (UTC).

**How to read an entry.** The heading is the macro as you would call it, with its argument names. *Arguments* that name a lookup let the tests (`tests/spl/`) run the same macro on fixture tables. *Used by* says which saved search, dashboard panel or other macro calls it.

## Lookup names

The real collection behind each lookup. Saved searches call these instead of typing the names, so a test can check they all agree.

### `dh_lookup_expected`
The expected list, `dh_expected`: every entity that should send data. Used by: the name check in `tests/spl/run.sh`.

### `dh_lookup_state_fast`
`dh_state_fast`: when each index/host/sourcetype/source last delivered data, as seen by the arrival tracker. Used by: *DH Tracker fast*.

### `dh_lookup_state_slow`
`dh_state_slow`: the same facts from the hourly backfill. Used by: *DH Tracker slow*.

### `dh_lookup_fwd`
`dh_fwd`: one row per host with its forwarder facts (last heartbeat, last connection, version, last Ansible marker, last Hyper-V event, last device probe). Used by: *DH Tracker fast*, *DH Daily SoH report*.

### `dh_lookup_overrides`
`dh_overrides`: mutes and threshold overrides set on the Manage dashboard. Used by: *DH Prune*, *DH Daily SoH report*.

### `dh_lookup_baseline`
`dh_baseline`: what is normal for each entity (learned silence limit, hourly volume). Used by: *DH Baseline compute*.

### `dh_lookup_meta`
`dh_meta`: run times of the trackers and the admin-log copy. The banner and the evaluator's gate read it. Used by: *DH Tracker fast*, *DH Tracker slow*, *DH Admin log copy*.

### `dh_lookup_blocks`
`hl_ingest_block`: the test-block table (owned by the `hl_server_base` app). Until that app is installed the table doesn't exist and is read as empty. Used by: *DH Prune*.

### `dh_lookup_tamper`
`dh_tamper`: tamper findings with their suppression. Used by: *DH Tamper*.

### `dh_lookup_status`
`dh_status`: the evaluator's output, one row per expected entity. Used by: *DH Evaluate*, *DH Daily SoH report*.

### `dh_lookup_volume`
`dh_volume`: last hour's event count per entity against its usual count. Used by: *DH Volume hourly*.

### `dh_lookup_admin_log`
`dh_admin_log`: every change made on the Manage dashboard. Used by: *DH Admin log copy*.

## Entities and normalization

### `dh_indexes`
The indexes the trackers watch: `linux, windows, network, wd2l_uf_audit, enclave1, wd2l`. `data_health` (this app's own output) and `wd2l_audit` are left out on purpose. Used by: *DH Tracker fast*, *DH Tracker slow*, *DH Baseline daily*, *DH Volume hourly*, the Host detail chart.

### `dh_host_norm(h)`
Turns a host name into its short lowercase form (`WD2L-RECV.mshome.net` becomes `wd2l-recv`), so the same machine always gets the same name. The test-block rule at ingest uses the same rule. Arguments: `h`, a field or expression. Used by: nearly every step that reads a host.

### `dh_source_norm(s)`
Turns a source path into a pattern: dates, times and long numbers become `*`, and a rotation suffix such as `.1` or `.2.gz` becomes `.*`. So `audit-2026-10-30.jsonl` and `audit-2026-10-31.jsonl` count as one source. Arguments: `s`, a field or expression. Used by: the trackers, the evaluator, baselines, volume, Manage.

### `dh_state_entity_ids`
For one row of arrival data, the three entities it counts toward: its source, its sourcetype and its host. Used by: `dh_eval_load`, `dh_daily_from_minutes`, `dh_volume_flag`.

### `dh_expected_rows(expected)`
The enabled rows of the expected list, normalized, one per entity. Only `0`, `false`, `no` or `off` disable a row, so a typo never switches monitoring off. Arguments: `expected`, the expected-list lookup. Used by: the evaluator, the daily baseline, prune, the unregistered list.

## Tunables

Fixed numbers the pipeline uses. Change them in `local/macros.conf`, never in `default/`.

### `dh_skew_secs`
**600 seconds.** When data arrives more than this long after (or before) its own timestamp, the entity is flagged for clock skew. Raise it to tolerate slower or more backfilled sources; lower it to catch smaller clock errors (more noise). Used by: `dh_state_merge`, `dh_eval_load`.

### `dh_gate_stale_secs`
**120 seconds.** If the arrival tracker hasn't run for this long, the evaluator stops trusting its data: every status shows PENDING and no alerts fire, and the banner says "On hold". Raise it to ride out a slow scheduler; lower it to notice a stuck tracker sooner. Used by: `dh_eval_gate_read`, `dh_ui_banner`.

### `dh_gate_rx_secs`
**120 seconds.** If Splunk has indexed nothing at all for this long, it is treated as "not receiving": statuses are held as PENDING (everything going silent at once is Splunk's problem, not every host's). Raise it on a very quiet lab; lower it to react sooner. Used by: `dh_eval_gate_read`, `dh_ui_banner`.

### `dh_gate_resume_secs`
**300 seconds.** After a pause (PC sleep, a Splunk restart) the evaluator holds statuses as PENDING for this long while data catches up, so a wake-up doesn't raise false alerts. Raise it if backlogs take longer to drain; lower it to see real statuses sooner. Used by: `dh_eval_gate_read`, `dh_ui_banner`.

### `dh_resume_gap_secs`
**150 seconds.** A gap this long between two runs of the arrival tracker counts as a pause (and starts the hold above). Raise it if the scheduler is often late; lower it to catch shorter pauses. Used by: `dh_meta_fast`.

### `dh_never_seen_secs`
**3600 seconds.** A newly expected entity that has never sent anything is PENDING for this long, then NEVER_SEEN. Raise it for inputs that take long to start; lower it to report missing inputs sooner. Used by: `dh_eval_status`.

### `dh_tamper_window_secs`
**900 seconds.** A tamper finding this close to the start of a silence makes the cause "possible deliberate blinding"; a finding this close to an Ansible marker is treated as the role's own work and suppressed. Raise it to link findings further apart (more false links); lower it to link only very close ones. Used by: `dh_eval_cause`, `dh_tamper_finish`.

## Profiles and thresholds

### `dh_profile_defaults`
For each expected row's profile, the default silence limit and the bounds a learned limit is clamped to: heartbeat 90 s; periodic 2 × interval + 60 s; continuous 900 s (learned 300–3600 s); sporadic 86400 s (learned 7200–604800 s); info never alerts. An unknown or misspelt profile is treated as continuous and reported as `invalid_profile`. Used by: the evaluator, `dh_daily_from_minutes`, `dh_ui_thresholds`.

### `dh_threshold`
Picks the silence limit that applies, and says where it came from: a Manage override, then `max_gap_secs` on the expected row, then the learned value (once there are 3 covered days), then the profile default. It also sets `learning` and a short note. Used by: the evaluator, `dh_ui_thresholds`.

## Statuses

### `dh_eval_mute`
Applies active mutes: the entity's own, or its host's (a host mute covers everything the host sends). Expired mutes are ignored. Used by: `dh_eval`.

### `dh_eval_liveness`
For a host row, chooses how "is the host alive" is judged: the forwarder heartbeat (UF hosts), the device probe (devices behind the relay), or else any data from the host. Used by: `dh_eval`.

### `dh_eval_status`
Computes the real status: MUTED, INFO, NEVER_SEEN, PENDING (new and not yet seen), MISSING (silent more than twice the limit), LATE (silent more than the limit) or OK. Ages are measured at the arrival tracker's last run, so a slow evaluator doesn't make data look late. Used by: `dh_eval`.

### `dh_eval_gate_read(meta)`
Reads the arrival tracker's run times and decides whether statuses can be trusted right now: tracker stale, Splunk not receiving, or catching up after a pause. When any applies, every status becomes PENDING and no alert fires. Arguments: `meta`, the run-time lookup. Used by: `dh_eval`.

### `dh_eval_transition`
Decides `since` (when the current status began), `prev_status`, and whether this run is a status change worth recording. A held (PENDING) run, or a new entity whose first status is OK, is not a change. Used by: `dh_eval`.

### `dh_eval_rollup`
Rolls a host's rows up to DOWN (its liveness is missing, or, for agentless hosts, every stream is missing), DEGRADED (something is late or missing) or OK. It also notes entities that arrive through a relay that is DOWN. Used by: `dh_eval`.

## Likely cause and action

### `dh_eval_cause`
Picks the most likely cause of an entity that is not OK, in a fixed order: the hold, a mute, "just added" (newly expected and not yet seen), a test block, an Ansible stop, the VM being off, a tamper finding, a relay down, the device probe, the heartbeat, and finally "this stream stopped". Used by: `dh_eval`.

### `dh_eval_cause_text`
Turns each cause code into the plain sentence shown in the Cause column and the next step shown in the Action column (for example "Start it again with the role: ansible-playbook site.yml --tags start --limit wd2l-recv"). The texts use the names the panels use ("Splunk agent", not UF or splunkd) and say what any command does. The full list is in [dashboards.md](dashboards.md#causes-what-the-cause-column-can-say). Used by: `dh_eval`.

## Evaluator steps over lookups

### `dh_eval_load(expected, state_fast, state_slow)`
Loads the enabled expected rows and joins each with the latest arrival at its level (source, sourcetype or whole host), taking the later of the fast and slow trackers. Arguments: the expected list and the two arrival tables. Used by: `dh_eval`.

### `dh_eval_facts(fwd, overrides, baseline, tamper, prev)`
Adds the facts each row needs: forwarder heartbeat, last Ansible marker, last Hyper-V event and device probe (by host); the entity's and its host's override; the learned baseline; tamper findings on the host (marking those suppressed by a marker); and the previous status. Used by: `dh_eval`.

### `dh_eval_blocks(blocks)`
Marks rows covered by an active test block (whole host, a sourcetype, or one exact raw source) so the cause says "test block until hh:mm". Only the linux, windows and network indexes can be blocked. Arguments: `blocks`, the test-block table. Used by: `dh_eval`.

### `dh_eval_output`
Shapes each row into the `dh_status` record (the fields the dashboards read) and stamps it with `evaluated_at`. Used by: `dh_eval`.

## The evaluator

### `dh_eval(expected, state_fast, state_slow, fwd, overrides, baseline, meta, blocks, tamper, prev, now)`
The whole evaluator: it chains the steps above, reads only lookups and writes nothing. `now` is the time to evaluate at, so the tests can use a fixed clock. Used by: `dh_evaluate`, `tests/spl/run.sh`.

### `dh_evaluate`
`dh_eval` over the real collections at the current time. Used by: *DH Evaluate*.

### `dh_transition_rows`
From the evaluator's output, the rows whose status changed, shaped as transition events (the entity's host is renamed `dh_host` so Splunk doesn't overwrite it). Used by: *DH Evaluate*.

### `dh_collect_transitions`
Writes those rows to `index=data_health source=dh:transition`. The alerts, the Recently recovered panel and the daily report read them. Used by: *DH Evaluate*.

### `dh_status_keep(expected, status)`
Lets *DH Evaluate* drop `dh_status` rows of entities that are no longer expected: when there are such rows, it returns the fresh rows for a full rewrite; otherwise nothing. Nothing is dropped while the expected list is empty. Used by: *DH Evaluate*.

## Tracker steps

### `dh_state_merge(state, now)`
Merges a minute's arrival counts with what the table already holds: latest times win, the earliest first-seen is kept, and only keys that saw new data are rewritten. Arguments: `state`, the table being updated; `now`. Used by: *DH Tracker fast*, *DH Tracker slow*.

### `dh_fwd_from_hb`
Forwarder heartbeats (each Splunk agent reports its own metrics every 30 s), per host; the indexer's own host is left out. Used by: *DH Tracker fast*.

### `dh_fwd_from_tcpin`
The indexer's record of each forwarder connection: time, guid, version, OS and type. Used by: *DH Tracker fast*.

### `dh_fwd_from_markers`
The latest Ansible marker per host (`stop`, `start`, …, with who ran it and the run id). Used by: *DH Tracker fast*.

### `dh_fwd_from_hyperv`
The latest Hyper-V lifecycle event per VM (started, turned off, shut down, saved, reset), read from the Windows Worker-Admin log. Used by: *DH Tracker fast*.

### `dh_fwd_from_probe`
The latest device-probe result per device (reachable or not), from the probe on the relay. Used by: *DH Tracker fast*.

### `dh_fwd_fold(fwd, now)`
Merges the five sources above with the existing `dh_fwd` rows, keeping the latest of each fact. Arguments: `fwd`, the forwarder table; `now`. Used by: *DH Tracker fast*.

### `dh_meta_fast(meta, now)`
Writes the arrival tracker's run record: this run's time, the previous run, the last time anything arrived, and the time of the last pause (a gap over `dh_resume_gap_secs`). Arguments: `meta`; `now`. Used by: *DH Tracker fast*.

## Tunables (task 11)

### `dh_clock_step_secs`
**300 seconds.** A clock change the operating system reports at least this large is a tamper finding ("big clock step"). Raise it to ignore bigger time corrections; lower it to catch smaller ones (normal NTP corrections may then show). Used by: `dh_tamper_win`, `dh_tamper_linux`.

### `dh_tamper_lookback_secs`
**604800 seconds (7 days).** How far back DH Tamper re-checks each finding against Ansible markers on every run. Raise it to re-check older findings (slower); lower it to stop sooner. Keep it equal to `dh_tamper_finding_earliest`. Used by: `dh_tamper_finish`.

### `dh_tamper_finding_earliest`
**`-7d`.** The event-time window DH Tamper reads findings from. Widen it to catch findings that arrive later (slower runs); narrow it to read less. It must match `dh_tamper_lookback_secs` (a test checks this). Used by: *DH Tamper*.

### `dh_tamper_marker_earliest`
**`-7d-15m`.** The window for Ansible markers: the findings' window plus `dh_tamper_window_secs`, so a finding at the edge still meets its marker. Change it only together with the findings' window: narrower and an old finding would lose its marker and be reported as tamper; wider only costs time. Used by: *DH Tamper*.

### `dh_volume_ratio`
**0.2 (20 %).** An hour is a volume drop when it has fewer than this share of its usual count for that hour of day. Raise it to flag milder drops; lower it to flag only near-silence. Used by: `dh_volume_flag`.

### `dh_volume_min_median`
**100 events.** Volume drops are flagged only where the usual hourly count is at least this, so quiet streams don't flap. Raise it to watch only busier streams; lower it to watch quieter ones (more noise). Used by: `dh_volume_flag`.

### `dh_volume_min_up_minutes`
**54 minutes.** An hour is judged only if Splunk was up for at least this many of its minutes; otherwise its low count is Splunk's fault. Raise it to judge only fully covered hours; lower it to judge partial ones. Used by: `dh_volume_flag`.

### `dh_suggest_continuous_secs`
**1800 seconds.** In the baseline, an entity whose typical longest daily silence is at most this is suggested as `continuous`, otherwise `sporadic`. Raise it to suggest continuous for gappier streams; lower it to suggest sporadic more often. It is only a suggestion shown on Manage. Used by: `dh_baseline_compute`.

### `dh_state_retention_secs`
**2592000 seconds (30 days).** Arrival rows older than this that no expected entity uses are pruned daily. Raise it to keep history of retired streams longer; lower it to keep the tables smaller. Used by: `dh_prune_mark_state`.

### `dh_fwd_retention_secs`
**2592000 seconds (30 days).** Forwarder rows not updated for this long, of hosts no longer expected, are pruned daily. Raise it to keep facts about retired hosts longer; lower it to forget them sooner. Used by: `dh_prune_mark_fwd`.

### `dh_tamper_retention_secs`
**2592000 seconds (30 days).** Tamper findings older than this are pruned from the collection (the `data_health` index keeps them). Raise it to keep them on Host detail longer; lower it to keep the collection smaller. Used by: `dh_prune_mark_tamper`.

### `dh_volume_retention_secs`
**172800 seconds (2 days).** Volume rows not updated for this long are pruned. Raise it to keep stale hourly rows longer (nothing reads them); lower it to clean up sooner. Used by: `dh_prune_mark_volume`.

### `dh_baseline_retention_secs`
**2592000 seconds (30 days).** Baseline rows not recomputed for this long (the entity stopped sending) are pruned. Raise it to keep what was learned about a stream that comes back after a long break; lower it to forget it sooner. Used by: `dh_prune_mark_baseline`.

### `dh_admin_retention_secs`
**7776000 seconds (90 days).** Admin-log rows older than this, already copied to the index, are pruned from the collection. Raise it to see more history on Manage; lower it to keep the table small (the index keeps a copy either way). Used by: `dh_prune_mark_admin_log`.

### `dh_fwd_expected_version`
**`10.6.1.1`.** The Splunk agent version the role installs. Agents on another version are listed in the daily report and flagged on Host detail. Change it when the role pins a new version. Used by: `dh_soh_fwd`, `dh_ui_fwd`.

### `dh_fwd_disconnect_secs`
**900 seconds.** An agent with no heartbeat or connection for this long is listed as disconnected in the daily report. Raise it to list only longer silences; lower it to list shorter ones. Used by: `dh_soh_fwd`.

### `dh_lag_warn_secs`
**60 seconds.** Sourcetypes whose data usually arrives at least this long after it was written (95th percentile) are listed as slow in the daily report. Raise it to list only very slow ones; lower it to list more. Used by: `dh_soh_lag`.

## Summary writes

Each writes rows to the `data_health` index as sourcetype `stash`, which doesn't count against the licence.

### `dh_collect_daily`
Writes the per-day records (`source=dh:daily`). Used by: *DH Baseline daily*.

### `dh_collect_volume`
Writes flagged volume hours (`source=dh:volume`). Used by: *DH Volume hourly*.

### `dh_collect_tamper`
Writes new tamper findings and suppression changes (`source=dh:tamper`). Used by: *DH Tamper*.

### `dh_collect_admin`
Writes copies of the admin log (`source=dh:admin`). Used by: *DH Admin log copy*.

### `dh_collect_soh`
Writes the daily report rows (`source=dh:soh`). Used by: *DH Daily SoH report*.

## Baselines (DH Baseline daily and compute)

### `dh_daily_from_minutes(fwd, expected)`
For each entity and completed day: how many events, how many active minutes, the longest and 95th-percentile silence, how late data arrived, and the hourly counts. Only minutes when Splunk (and, for agent hosts, the agent) were up count, so PC sleep never looks like silence; a silence still open at midnight carries into the next day. Arguments: `fwd`, `expected`. Used by: *DH Baseline daily*.

### `dh_daily_todo(now)`
The completed days of the last 14 that have no daily record yet, so a missed night is caught up on the next run. Used by: *DH Baseline daily*, `dh_daily_window`.

### `dh_daily_window(now)`
The time window that covers those days (empty when nothing is due). Used by: *DH Baseline daily*.

### `dh_baseline_compute(days, now)`
From the last `days` daily records: the learned silence limit (1.5 × the 90th percentile of the daily longest silence, plus 120 s, before the profile's clamp), how many days were covered, the usual count per hour of day, and a suggested profile. Days under 50 % covered are skipped. Used by: *DH Baseline compute*.

## Volume (DH Volume hourly)

### `dh_volume_flag(baseline, now)`
Compares the last full hour's count per entity with its usual count for that hour of day, and flags a drop below `dh_volume_ratio` (when the usual count is at least `dh_volume_min_median`, Splunk was up, and there are 3 days of history). Used by: *DH Volume hourly*.

## Tamper (DH Tamper)

### `dh_tamper_win`
Finds Windows tamper indicators: security or event log cleared (1102, 104), event logging shut down (1100), audit policy changed (4719), a service installed (4697, 7045), the Splunk agent or Event Log service stopped or its start type changed (7036, 7040), and big clock steps. The provider is checked as well as the event ID. Used by: *DH Tamper*.

### `dh_tamper_linux`
Finds Linux tamper indicators: auditd stopped or aborted, audit rules changed, the Splunk agent, auditd or rsyslog stopped, events of the `hl-*` and `wd2l-*` audit keys, and big clock steps. Used by: *DH Tamper*.

### `dh_tamper_finish(tamper, now)`
Groups indicators into findings (one per host, kind and 5-minute bucket), re-checks each finding of the last 7 days against every Ansible marker (a finding within `dh_tamper_window_secs` of a marker is the role's own work and is suppressed), and marks which ones still need writing to the index. Used by: *DH Tamper*.

### `dh_tamper_collect_rows`
Shapes findings for writing to the index. Used by: *DH Tamper*.

## Alerts

### `dh_alert_missing_rows`
The transitions to MISSING of entities with criticality 1 or 2 (no criticality counts as 2). Used by: *DH Alert missing*.

### `dh_alert_tamper_rows`
New tamper findings that are not suppressed. Used by: *DH Alert tamper*.

## Admin log copy

### `dh_admin_copy_rows(meta, now)`
The admin-log rows written since the last copy (and at least 60 s old), for copying to the index. Used by: *DH Admin log copy*.

## Prune

Each "mark" macro marks the rows to delete; the prune searches rewrite a table only when something is marked.

### `dh_prune_mark_blocks(now)`
Test blocks that have expired, or that have no key or no valid expiry. Used by: *DH Prune* (every minute).

### `dh_prune_mark_overrides(now)`
Expired mutes are cleared; an override row with nothing left is deleted. Used by: *DH Prune* (every minute).

### `dh_prune_mark_status(expected)`
`dh_status` rows of entities that are no longer expected (none while the expected list is empty). Used by: `dh_status_keep`.

### `dh_prune_mark_state(expected, now)`
Arrival rows older than `dh_state_retention_secs` that no expected entity uses. Used by: `dh_prune_mark_dh_state_fast`, `dh_prune_mark_dh_state_slow`.

### `dh_prune_mark_fwd(expected, now)`
Forwarder rows not updated for `dh_fwd_retention_secs`, of hosts no longer expected. Used by: `dh_prune_mark_dh_fwd`.

### `dh_prune_mark_tamper(now)`
Tamper findings older than `dh_tamper_retention_secs`. Used by: `dh_prune_mark_dh_tamper`.

### `dh_prune_mark_volume(now)`
Volume rows older than `dh_volume_retention_secs`. Used by: `dh_prune_mark_dh_volume`.

### `dh_prune_mark_baseline(now)`
Baseline rows not updated for `dh_baseline_retention_secs`. Used by: `dh_prune_mark_dh_baseline`.

### `dh_prune_mark_admin_log(meta, now)`
Admin-log rows older than `dh_admin_retention_secs` that have already been copied to the index. Used by: `dh_prune_mark_dh_admin_log`.

### `dh_prune_mark_dh_state_fast`
`dh_prune_mark_state` over the real `dh_state_fast`. Used by: *DH Prune daily* (which calls `dh_prune_mark_<collection>` by name).

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

Each section macro turns its input into report rows (`section`, `item`, `value`, plus a few extras).

### `dh_soh_outages(status, now)`
From the transitions of the last 7 days: each outage (a stretch of LATE, MISSING or NEVER_SEEN) that ended in the last 24 hours or is still open, with its duration and how it ended (`end_status`), plus the mean time to recover. An outage counts as open only while `dh_status` still shows the entity bad. Used by: *DH Daily SoH report*, `dh_ui_recovered`.

### `dh_soh_flapping(now)`
Entities with 3 or more status changes in the last 24 hours. Used by: *DH Daily SoH report*.

### `dh_soh_status`
From `dh_status`: entities that never arrived, and expected rows with a profile the app doesn't know. Used by: *DH Daily SoH report*.

### `dh_soh_fwd(now)`
Agents on another version than `dh_fwd_expected_version`, and agents silent for `dh_fwd_disconnect_secs`. Used by: *DH Daily SoH report*.

### `dh_soh_mutes(now)`
Active mutes, and those ending within 24 hours. Used by: *DH Daily SoH report*.

### `dh_soh_lag`
Sourcetypes whose 95th-percentile arrival delay on the latest day is at least `dh_lag_warn_secs`. Used by: *DH Daily SoH report*.

### `dh_soh_volume(now)`
Entities with flagged volume drops in the last 24 hours, with how many hours and the lowest ratio. Used by: *DH Daily SoH report*.

### `dh_soh_licence(now)`
Yesterday's indexed bytes against the active licence's daily quota, and the days until the licence expires. Used by: *DH Daily SoH report*.

### `dh_soh_skipped`
This app's scheduled searches that were skipped in the last 24 hours, and a total. Used by: *DH Daily SoH report*.

## Dashboards (task 12)

These macros hold the SPL behind the dashboard panels, so the tests run exactly what the panels run. [dashboards.md](dashboards.md) explains the panels themselves.

### `dh_ui_time_fmt`
**`%Y-%m-%d %H:%M`.** How dates are shown in dashboard tables. Used by: most `dh_ui_*` macros.

### `dh_ui_headers`
The plain column headers of every dashboard table ("Silent for / limit" instead of `age_vs_threshold`, "Host" instead of `host`). It is the last step of each table's search; the macros and tests keep the field names. Used by: every table panel.

### `dh_ui_current_secs`
**150 seconds.** A `dh_status` row more than this behind the newest one is ignored by the dashboards: it belongs to an entity that is no longer expected and hasn't been cleaned up yet. The evaluator rewrites every row once a minute, so this is two and a half runs. Raise it if the evaluator is often slow; lower it to hide retired entities sooner. Used by: `dh_ui_status`, `dh_ui_status_attrs`.

### `dh_ui_eval_stale_secs`
**180 seconds.** If the evaluator hasn't written statuses for this long, the banner says "Out of date". Raise it to tolerate a slow scheduler; lower it to warn sooner (one late run may then trip it). Used by: `dh_ui_banner`.

### `dh_ui_status(status)`
The current rows of `dh_status` (see `dh_ui_current_secs`). Used by: the Overview, Host detail and Manage panels.

### `dh_ui_filter`
Applies the Overview filters (site, owner, index, criticality, status, search text). The dashboard sets the filter values as fields first. Search text is made of words separated by `*` that must all appear in the entity, its description or its cause, compared literally (so `%`, `_` or `.` mean themselves). Used by: the Overview panels, Manage's threshold table.

### `dh_ui_kpi`
The KPI tile numbers, separately for hosts, sourcetypes and sources: expected, OK, late, missing (including never seen), muted and waiting (PENDING). Used by: Overview, KPI tiles.

### `dh_ui_attention(now)`
One row per host that has late, missing or never-seen data, worst first, with its children, since when, the likely cause and the next action. Used by: Overview, Needs attention.

### `dh_ui_attention_headline`
The one-line summary above Needs attention: all fine, how many hosts need attention, or on hold. Used by: Overview, How many hosts need attention.

### `dh_ui_banner(meta, status, now)`
The banner text and colour: Up to date, On hold, Out of date or Catching up (see [the banner states](dashboards.md#the-banner-is-the-data-current)). Used by: Overview, Is the data current?

### `dh_ui_tamper_24h(status, now)`
Unsuppressed tamper findings first seen in the last 24 hours (by when they were recorded, so late findings count), one per finding, with the host's filter attributes. Used by: Overview, Tamper findings.

### `dh_ui_status_attrs(status)`
Adds the filter attributes (site, owner, criticality, status, roll-up, description) of each row's entity from the current `dh_status` rows, so the Overview filters also apply to recoveries and tamper findings. Used by: `dh_ui_tamper_24h`, `dh_ui_recovered`.

### `dh_ui_recovered(status, now)`
Outages that ended with a return to OK in the last 24 hours (a mute or an INFO profile is not a recovery). Used by: Overview, Recently recovered.

### `dh_ui_host_children(volume)`
One host's expected rows: status, age against its limit, profile, where the limit comes from, any mute or test block, and last hour's volume. Used by: Host detail, Expected data from this host.

### `dh_ui_fwd(now)`
One host's forwarder facts as readable lines: version (flagged if not the expected one), OS, last heartbeat, last connection, last Ansible marker, last VM event, last probe. Used by: Host detail, Forwarder.

### `dh_ui_hyperv`
Hyper-V Worker-Admin events with the VM name and what each event ID means. Used by: Host detail, Hyper-V VM events.

### `dh_ui_thresholds(baseline, expected)`
For each entity: the configured limit, the profile default, the learned value before and after its clamp, the covered days, and the limit actually applied with its origin. Used by: Manage, Thresholds.

### `dh_ui_unregistered(expected, state_fast, state_slow, baseline, now)`
Sourcetypes and hosts that sent data in the last 7 days but are not on the expected list, with a suggested profile. Used by: Manage (Unregistered, and the Adopt list), Daily state of health.

### `dh_ui_actor`
Who is signed in (from the server, never from the page) and all their roles, including roles they inherit. Used by: the Manage previews and writes.

### `dh_ui_roles_expand`
Adds the roles that the user's roles import, three levels deep. If the user may not read the role list, only their own roles count. Used by: `dh_ui_actor`.

### `dh_ui_roles_step`
One level of that expansion. Used by: `dh_ui_roles_expand`.

### `dh_ui_host_terms`
Turns a host name picked on a dashboard into a safe search filter for that host and its FQDN form; anything that isn't a plain host name matches nothing. This keeps text from the page from ever becoming part of a search. Used by: Host detail (chart, agent errors), Manage (raw sources).

### `dh_ui_clean(fields)`
Trims form values; empty or `-` means "none". Arguments: `fields`, the field names. Used by: the Manage plan macros.

### `dh_ui_override_plan(overrides, now)`
Checks a mute, unmute, threshold or clear request (reason required, mutes end within 30 days) and shows the override before and after. It also makes the confirmation code that the Apply choice carries. Used by: Manage, form 1.

### `dh_ui_override_write(overrides, admin_log, now)`
Writes the override when the confirmation matches the current state, and logs it. A repeat or stale confirmation writes nothing. Used by: Manage, form 1.

### `dh_ui_expected_plan(expected, now)`
Checks a new or changed expected row (dh_admin only; Ansible-managed rows are refused) and shows it before and after, with its confirmation code. Used by: Manage, forms 2 and 3.

### `dh_ui_expected_write(expected, admin_log, now)`
Writes the expected row when the confirmation matches, and logs it. Used by: Manage, forms 2 and 3.

### `dh_ui_adopt_row(baseline, fwd)`
Turns an unregistered entity into an expected-row request: agent hosts become `uf`, others `syslog`. An agent host's own row gets the `heartbeat` profile; any other row takes the baseline's suggestion, else continuous. Used by: Manage, form 3.

### `dh_ui_block_plan(blocks, now)`
Checks a test-block request (dh_admin only; 60 s to 24 h; a source block needs an exact raw source) and shows the block before and after, with the normalized source for reference and its confirmation code. Used by: Manage, form 4.

### `dh_ui_block_rows(blocks, now)`
The whole new test-block table for a confirmed request; when that would leave the table empty, one placeholder row that matches nothing (DH Prune removes it within a minute). Used by: `dh_ui_block_write`.

### `dh_ui_block_write(blocks, admin_log, now)`
Rewrites the test-block table (key column first, as the ingest rule needs) and logs the change. Used by: Manage, form 4.

### `dh_ui_log(admin_log, now)`
Adds one admin-log row per applied change and returns the result line ("applied: …" or "nothing applied: …"). Used by: the three write macros.
