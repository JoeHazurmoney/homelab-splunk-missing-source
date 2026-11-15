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
`hl_ingest_block`: Splunk's copy of Cribl's test-block table (the `hl_server_base` lookup that the role's *cribl_block* tag writes; nothing here writes it). Until that app is installed the table doesn't exist and is read as empty. Used by: nothing. `dh_evaluate` and the Manage Test blocks tab name `hl_ingest_block` directly.

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
The indexes the trackers watch: `linux, windows, network, wd2l_uf_audit, enclave1, wd2l, cribl`. `data_health` (this app's own output), `wd2l_audit` and `cribl_metrics` (a metrics index, whose dimensions carry the data's hosts and sourcetypes) are left out on purpose. Used by: *DH Tracker fast*, *DH Tracker slow*, *DH Baseline daily*, *DH Volume hourly*, the Host detail chart.

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

### `dh_probe_host`
The host that runs the device probe (*hl-devprobe*): `pi5`, the role's `hl_probe_host`. The probe causes name it ("check hl-devprobe on pi5"). Change both together.

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
**900 seconds.** A tamper finding this close to the start of a silence makes the cause "possible deliberate blinding"; a finding that comes at most this long after an Ansible marker for its host is treated as the role's own work and suppressed. Raise it to link findings further apart (more false links); lower it to link only very close ones. Used by: `dh_eval_cause`, `dh_tamper_finish`.

### `dh_tamper_marker_slack_secs`
**60 seconds.** A marker up to this long *after* a finding still suppresses it, because markers carry pi5's clock and findings the host's. A marker posted later, such as a restore run's, never hides a finding. Raise it only if the hosts' clocks drift further apart. Used by: `dh_tamper_finish`.

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
Picks the most likely cause of an entity that is not OK, in a fixed order: the hold, a mute, "just added" (newly expected and not yet seen), a test block, an Ansible stop, the VM being off, a tamper finding, a relay down, the device probe, a silent *hl:devprobe* row while its host's heartbeat is OK, the heartbeat, and finally "this stream stopped". Used by: `dh_eval`.

### `dh_eval_cause_text`
Turns each cause code into the plain sentence shown in the Cause column and the next step shown in the Action column (for example "Start it again with the role: ansible-playbook site.yml --tags start --limit wd2l-recv"). The texts use the names the panels use ("Splunk agent", not UF or splunkd) and say what any command does. The full list is in [dashboards.md](dashboards.md#causes-what-the-cause-column-can-say). Used by: `dh_eval`.

## Evaluator steps over lookups

### `dh_eval_load(expected, state_fast, state_slow)`
Loads the enabled expected rows and joins each with the latest arrival at its level (source, sourcetype or whole host), taking the later of the fast and slow trackers. Arguments: the expected list and the two arrival tables. Used by: `dh_eval`.

### `dh_eval_facts(fwd, overrides, baseline, tamper, prev)`
Adds the facts each row needs: forwarder heartbeat, last Ansible marker, last Hyper-V event and device probe (by host); the entity's and its host's override; the learned baseline; tamper findings on the host, and on host *cribl* too for a row that arrives through Cribl (marking those suppressed by a marker); and the previous status. Used by: `dh_eval`.

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

### `dh_fwd_from_ufint`
Each agent's own log lines: its last connection to Cribl ("Connected to idx=", every 30 s), and from the lines it writes at each start, its operating system and processor type and its build, turned into a version by the `dh_uf_builds` table. Splunk now sees only Cribl's connection, so it can't name the agents itself. Splunk's own lines are left out. Used by: *DH Tracker fast*.

### `dh_fwd_from_markers`
The latest Ansible marker per host (`stop`, `start`, …, with who ran it and the run id). Used by: *DH Tracker fast*.

### `dh_fwd_from_hyperv`
The latest Hyper-V lifecycle event per VM (started, turned off, shut down, saved, reset), read from the Windows Worker-Admin log. Used by: *DH Tracker fast*.

### `dh_fwd_from_probe`
The latest device-probe result per device (reachable or not), from hl-devprobe on pi5. Used by: *DH Tracker fast*.

### `dh_fwd_fold(fwd, now)`
Merges the five sources above with the existing `dh_fwd` rows, keeping the latest of each fact. Arguments: `fwd`, the forwarder table; `now`. Used by: *DH Tracker fast*.

### `dh_meta_fast(meta, now)`
Writes the arrival tracker's run record: this run's time, the previous run, the last time anything arrived, and the time of the last pause (a gap over `dh_resume_gap_secs`). Arguments: `meta`; `now`. Used by: *DH Tracker fast*.

## Tunables (task 11)

### `dh_clock_step_secs`
**300 seconds.** A clock change the operating system reports at least this large is a tamper finding ("big clock step"). Raise it to ignore bigger time corrections; lower it to catch smaller ones (normal NTP corrections may then show). Used by: `dh_tamper_win`, `dh_tamper_linux`.

### `dh_tamper_lookback_secs`
**604800 seconds (7 days).** How old a finding DH Tamper still writes to the index (when it is new, or its stored suppression isn't there yet). An older finding is never alerted again. Keep it inside the indexes' 14-day retention, inside which DH Tamper reads what it already wrote. Keep it equal to `dh_tamper_finding_earliest`. Used by: `dh_tamper_finish`.

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
**2592000 seconds (30 days).** Tamper findings older than this are pruned from the collection (the `data_health` index keeps them for 14 days, its retention). Raise it to keep them on Host detail longer; lower it to keep the collection smaller. Used by: `dh_prune_mark_tamper`.

### `dh_volume_retention_secs`
**172800 seconds (2 days).** Volume rows not updated for this long are pruned. Raise it to keep stale hourly rows longer (nothing reads them); lower it to clean up sooner. Used by: `dh_prune_mark_volume`.

### `dh_baseline_retention_secs`
**2592000 seconds (30 days).** Baseline rows not recomputed for this long (the entity stopped sending) are pruned. Raise it to keep what was learned about a stream that comes back after a long break; lower it to forget it sooner. Used by: `dh_prune_mark_baseline`.

### `dh_admin_retention_secs`
**7776000 seconds (90 days).** Admin-log rows older than this, already copied to the index, are pruned from the collection. Raise it to see more history on Manage; lower it to keep the table small (the index keeps a copy for 14 days, its retention). Used by: `dh_prune_mark_admin_log`.

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
The completed days of the last 13 that have no daily record yet, so a missed night is caught up on the next run. Not 14: the indexes keep 14 days, so the raw data of the day that began 14 days ago may already be partly gone, and filling it in would record a silence that never happened. Used by: *DH Baseline daily*, `dh_daily_window`.

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

### `dh_tamper_cribl`
Cribl's audit log: any create, update, delete, reorder or upload of routes, pipelines, outputs, inputs or lookups is a finding on the host *cribl*. The log can't tell a Drop function from any other pipeline edit, so every such change counts. The role's own changes fall inside its *cribl* and *cribl_block* marker windows and are suppressed. Used by: *DH Tamper*.

### `dh_tamper_finish(tamper, now)`
Groups indicators into findings (one per host, kind and 5-minute bucket) and decides, once, whether each new finding is the role's own work: suppressed when an Ansible marker for its host came at most `dh_tamper_window_secs` before it (or `dh_tamper_marker_slack_secs` after it). A stored finding keeps its suppression on every later run, so a later marker never hides it; if its `dh_tamper` row is gone, the latest `dh:tamper` record (by index time) gives it. Marks which findings of the last 7 days still need writing to the index (an older one never does: the index keeps 14 days, the collection 30). Used by: *DH Tamper*.

### `dh_tamper_fold(now)`
One service install logs two Windows events: a 7045 (System log) and a 4697 (Security log). This step puts the pair into one finding, "7045+4697 service installed: …", with both event IDs in its detail. The two events match on the service's key name or its program path, at most `dh_tamper_window_secs` apart. Either event can arrive first. If one half is already stored (and alerted), the other joins that finding, so a service install alerts once. Findings stored before this step existed are left as they are. Used by: `dh_tamper_finish`.

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
From the transitions of the last 7 days: each outage (a stretch of LATE, MISSING or NEVER_SEEN) that ended in the last 24 hours or is still open, with its duration and how it ended (`end_status`), plus the mean time to recover. An outage counts as open only while `dh_status` still shows the entity bad. An entity that went bad more than 7 days ago and is still bad is listed too, as open since its `since` time. Used by: *DH Daily SoH report*, `dh_ui_recovered`.

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

### `dh_ui_time_fmt_tz`
**`%Y-%m-%d %H:%M %Z`.** The same with the time zone, for every time shown on Manage (and the Unregistered list, which Daily state of health shares). Times follow the viewer's Splunk time zone, so the zone is spelled out. Used by: the Manage macros below, `dh_ui_unregistered`.

### `dh_ui_item_words(id)`
An Item ID (`level|index|host|sourcetype|source`) in words: `pi5: whole host`, `pi5 › syslog (enclave1)`, `pi5 › linux_secure › /var/log/secure (linux)`. Anything else comes back unchanged. Arguments: `id`, the field or expression holding the ID. Only what is shown changes; the stored IDs stay as they are. Used by: the Manage lists, previews, results and tables, `dh_ui_thresholds`.

### `dh_ui_block_words(k)`
A test-block key (`host|*|*`, `host|sourcetype|*`, `host|sourcetype|raw source`) in words: `pi5: whole host`, `pi5 › syslog`, `pi5 › linux_secure › /var/log/secure.1 (exact source)`. Arguments: `k`, the key. Used by: Manage, Test blocks tab and Admin log.

### `dh_ui_action_words(action)`
An admin-log action code in words: `override_mute` Mute, `override_unmute` Unmute, `override_threshold` Set limit, `override_clear` Clear limit, `expected_add` Add expected row, `expected_adopt` Adopt, `block_add` Add test block, `block_remove` Remove test block. The codes stay in the admin log. Used by: the Manage plan macros, `dh_ui_log_words`.

### `dh_ui_secs_words(secs)`
A number of seconds in words: whole days, hours or minutes (`7 days`, `1 hour`, `20 minutes`), else seconds (`90 s`). Used by: the Manage previews and Confirm choices, `dh_ui_overrides`.

### `dh_ui_origin_words(origin)`
Where an item's limit comes from (`dh_threshold`'s origin code) in words: Override (set on Manage), Fixed limit on its expected row, Learned from its history, Profile default, Profile default (the row's profile is unknown), None (INFO: never alerts). Used by: `dh_ui_thresholds`, `dh_ui_host_children`.

### `dh_ui_log_words`
Admin-log rows for display: the action and item in words, the time with its zone, and the detail's `->` shown as `→` (with `managed by` and `limit` for `managed_by` and `threshold`). The stored row is not changed. Used by: `dh_ui_log`, `dh_ui_admin_log`.

### `dh_ui_admin_log(admin_log)`
The admin log, newest first, for display, with the words its search box looks in. Used by: Manage, Admin log tab.

### `dh_ui_hay_filter`
The search box of a table: keeps the rows that contain every word of the box (words separated by `*`, not case-sensitive, compared literally as in `dh_ui_filter`). `*` keeps everything. Used by: Manage, Admin log tab.

### `dh_ui_overrides(overrides)`
The mutes and limit overrides in force, for display: the item in words, when the mute ends and the limit override in words, with their zone. Used by: Manage, Current mutes and limit overrides.

### `dh_ui_blocks(blocks, now)`
The current test blocks for display: the key in words, until when (with its zone) and whether each is still active. Used by: Manage, Current test blocks.

### `dh_ui_indexes`
The index choices of Manage's Add-row form, read from `dh_indexes` at run time, so the list of watched indexes lives in one place (the add-row check uses `dh_indexes` too). Used by: Manage, Expected list tab, Index.

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
One host's expected rows: status, age against its limit, profile, where the limit comes from (in words, `dh_ui_origin_words`), any mute or test block (with its time zone), and last hour's volume. Used by: Host detail, Expected data from this host.

### `dh_ui_fwd(now)`
One host's forwarder facts as readable lines: version (flagged if not the expected one), OS, last heartbeat, last connection, last Ansible marker, last VM event, last probe. Used by: Host detail, Forwarder.

### `dh_ui_hyperv`
Hyper-V Worker-Admin events with the VM name and what each event ID means. Used by: Host detail, Hyper-V VM events.

### `dh_ui_thresholds(baseline, expected)`
For each entity: the limit actually applied and where it comes from (in words), the learned value after and before its clamp, the profile default, the configured limit and the covered days, with the item in words first. Used by: Manage, Thresholds.

### `dh_ui_unregistered(expected, state_fast, state_slow, baseline, now)`
Sourcetypes and hosts that sent data in the last 7 days but are not on the expected list, with a suggested profile; times carry their zone. Used by: Manage (Unregistered, and the Adopt list), Daily state of health.

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

### `dh_ui_override_plan(overrides, admin_log, now)`
Checks a mute, unmute, set-limit or clear-limit request (reason required, mutes end within 30 days). It returns what is logged (`before`, `after`, `action`), what the preview shows in words (`ui_change`, `ui_item`, `ui_now`, `ui_after`, `check`), the Confirm choice's text (`dh_label`, for example "Apply: mute pi5 › syslog (enclave1) for 1 hour") and the confirmation code that the choice carries. The code also covers the item's admin-log times (`admin_log`), so a confirmation fits only once: after DH Prune removes an expired mute, the old state is back but the log is not. Used by: Manage, Mute & thresholds tab.

### `dh_ui_override_write(overrides, admin_log, now)`
Writes the override when the confirmation matches the current state, and logs it. A repeat or stale confirmation writes nothing. Used by: Manage, Mute & thresholds tab.

### `dh_ui_expected_plan(expected, admin_log, now)`
Checks a new or changed expected row (dh_admin only; the index must be one of `dh_indexes`; Ansible-managed rows are refused) and shows it before and after, in words for the preview and as logged, with its Confirm text and confirmation code. The code also covers the item's admin-log times, so a confirmation fits only once even when the change left the row as it was (a reload or a revisited tab re-runs the write). Arguments: `admin_log`, the admin log. Used by: Manage, Expected list tab (add and adopt).

### `dh_ui_expected_write(expected, admin_log, now)`
Writes the expected row when the confirmation matches, and logs it. Used by: Manage, Expected list tab (add and adopt).

### `dh_ui_adopt_row(baseline, fwd)`
Turns an unregistered entity into an expected-row request: agent hosts become `uf`, others `syslog`. An agent host's own row gets the `heartbeat` profile; any other row takes the baseline's suggestion, else continuous. Used by: Manage, Expected list tab (adopt).

### `dh_ui_block_command`
The test block lives in Cribl, so Manage shows the command to run instead of writing it: the role's *cribl_block* line for a checked request (setting with minutes and reason, or clearing), with the key in plain single quotes and the reason reduced to plain characters. Used by: Manage, Test blocks tab.

### `dh_ui_block_plan(blocks, now)`
Checks a test-block request (dh_admin only; 1 minute to 24 hours; a source block needs an exact raw source; a sourcetype or source with a character the command can't carry, such as a quote, `$`, a comma, a space or `{`, is refused) against Splunk's copy of the block table and shows the block before and after, in words for the preview and as logged, with the normalized source for reference. Nothing is written from here: when the check says OK, `dh_ui_block_command` gives the role's command. Used by: Manage, Test blocks tab.

### `dh_ui_log(admin_log, now)`
Adds one admin-log row per applied change and returns the result in words ("Done: Mute pi5: whole host", or "Nothing written: …" when the confirmation no longer fits). What is stored is unchanged. Used by: the two write macros (`dh_ui_override_write`, `dh_ui_expected_write`).

## The expected list (task 10)

The role's `expected` tag writes `dh_expected_ansible.csv` from the inventory. *DH Sync expected*
merges it into `dh_expected` every 5 minutes, and right after each push. An enabled row added on
the Manage dashboard is never overwritten.

### `dh_sync_rows(ansible)`
The Ansible rows, cleaned up the way a Manage row is: level and host in lowercase, the host's domain dropped, index and sourcetype only below host level, the raw source kept for a source row, and the entity id built from them. A row the file marks disabled counts as not in the file, and rows with an unknown level or no host are dropped. Arguments: `ansible`, the Ansible file. Used by: `dh_sync_plan`.

### `dh_sync_sig`
One fingerprint of the fields Ansible owns (level, index, host, sourcetype, source, collection, via, hypervisor, profile, interval, maximum gap, criticality, owner, site, runbook, description), so an unchanged row is never rewritten. Used by: `dh_sync_plan`.

### `dh_sync_plan(ansible, expected, now)`
The rows *DH Sync expected* writes, each with its reason: **add** (new, or disabled before, a disabled Manage row included), **update** (a field Ansible owns changed; the "expected since" time is kept), **retire** (an Ansible row that left the file or that the file marks disabled: switched off, so its status goes and a later re-add starts a fresh grace period). It returns only the rows that change, written as `_key` upserts, so `dh_expected` is never rewritten whole (DH Evaluate drops the status of any entity missing from it). An enabled Manage row is never overwritten, not even when Ansible lists the same entity, and nothing is written while the Ansible file has no valid rows, so an empty or broken file can't retire the list. Arguments: the Ansible file, the expected list, `now`. Used by: *DH Sync expected*.

### `dh_discover_summary(expected, state_fast, state_slow, baseline, now)`
One summary row of what arrives without being expected: how many entities, how many hosts, and up to 50 of their ids. The same rows as Manage's "adopt" list and the Daily report's "unregistered" section. Used by: *DH Discover unregistered*.
