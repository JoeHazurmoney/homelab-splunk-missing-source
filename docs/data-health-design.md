# How the data-health app decides something is missing

The full model is in [the spec](specs/2026-10-30-design.md) §2 and §7. This page is the short version,
plus what changes in production. The `hl_data_health` app is search-time SPL plus the
[KV store](glossary.md#kv-store). It has no scripts, no custom commands and no index-time config.

## The five ideas

1. **The expected list comes from the deployment code.** The role's input rows render two files: the
   UFs' `inputs.conf` and `dh_expected_ansible.csv`. The saved search *DH Sync expected* merges that
   CSV into the KV collection `dh_expected`.
   - It upserts by `_key`: it adds new rows and updates changed ones.
   - It switches off rows whose input left the inventory.
   - It never overwrites an enabled row added on Manage (`managed_by=ui`), even for the same item.
   - An empty file changes nothing.
2. **Cadence profiles, not one threshold.** A [profile](glossary.md#profile) says how an item
   usually sends data. Each profile has a default limit, called its maximum silence.

   | Profile | For | Maximum silence |
   |---|---|---|
   | heartbeat | UF `_internal`; Cribl's own logs | UF 90 s; Cribl 120 s |
   | periodic | scripted inputs, the device probe | 2 × interval + 60 s |
   | continuous | busy logs | learned (5–60 min); 15 min while learning |
   | sporadic | event-driven logs | learned (2 h – 7 d); 24 h while learning |
   | info | tracked, never alerts | — |

   The app learns a limit for continuous and sporadic items:
   - It takes each of the last 14 days' longest gap. It counts only time when the host and Splunk
     were both up.
   - It needs at least 3 such days. Until then, it uses the "while learning" value above.
   - The limit is 1.5 × the 90th percentile of those gaps, plus 120 s. It stays inside the
     profile's range above.

   Four sources can set a limit. The first one that applies wins:
   1. A Manage override.
   2. The input's declared `max_gap_secs`.
   3. The learned value.
   4. The profile's default.

   The dashboards always say which one applied.
3. **Liveness apart from data.** A UF's `_internal` metrics, sent every 30 s, are its heartbeat. A
   device with no agent gets one from pi5's probe, a ping every 60 s. So "up but not logging" and
   "down" are different findings.
4. **State, not scans.** Trackers run `tstats` every minute, by index time, so backfilled data counts.
   They store the last arrival for each index, host, sourcetype and source in the KV store.
   *DH Evaluate* turns that into a status for each item. It writes **changes** to
   `index=data_health source=dh:transition`. The dashboards read the KV store, so they stay fast at
   hundreds of hosts.
5. **Every finding has a likely cause and an action.** The evidence is the heartbeat, Ansible
   markers, Hyper-V VM events, the relay (Cribl) and tamper indicators. See the
   [runbook](runbook-missing-data.md).

## Statuses and roll-up

Each item on the expected list has one status. The status depends on the item's limit: how long it
may stay silent. The profile table above sets that limit.

In the table below, "the Action column" means the **Action** column of the Overview's
[*Needs attention*](data-health/dashboards.md#needs-attention) table. It names the next step for
each row.

| Status | What it means | What to do |
|---|---|---|
| OK | Data arrived within its limit. | Nothing. |
| LATE | Silent longer than its limit, but not yet twice as long. | Look at the cause. Often it recovers by itself. |
| MISSING | Silent more than twice its limit. This is what alerts (for criticality 1 and 2). | Follow the Action column. |
| NEVER_SEEN | On the expected list for more than an hour, and it has never sent anything. | Check that the input is deployed and sending. The Action column says where. |
| MUTED | Muted on purpose on Manage, with a reason and an end time. A host mute covers everything it sends. | Nothing while muted. Unmute on Manage when the work is done. |
| PENDING | No trusted status right now. No alerts fire. | See below the table. |
| INFO | Tracked for reference only. It never alerts. | Nothing. |

PENDING has two causes:
- The app is on hold (the gate, below).
- The item was added less than an hour ago and hasn't sent anything yet.

If the banner says "On hold", fix what it says. Otherwise wait.

**Host roll-up.** A host also gets an overall state from its items:

| Roll-up | What it means |
|---|---|
| DOWN | The host itself looks dead: its heartbeat (or, for a device, its probe) is missing. A host with no agent is DOWN when every item it should send is missing. |
| DEGRADED | The host is alive, but some of its items are late, missing or never seen. |
| OK | Everything the host should send is arriving. |
| MUTED | The host is muted. |
| PENDING | The app is on hold (see the [banner](data-health/dashboards.md#the-banner-is-the-data-current)). |

**PENDING (the gate).** The gate holds every status as PENDING, and no alert fires. It closes in
three cases:
- The fast tracker hasn't run for 2 min.
- Splunk has received nothing for 2 min.
- A resume (PC sleep or restart) happened less than 5 min ago.

So a pause in the lab doesn't page anyone.

## How long until LATE, MISSING or DOWN

A status changes a little after its limit is crossed, not at once. Two searches, each run once a
minute, add the delay:

1. *DH Tracker fast* records when each item last arrived. A silence can wait up to 1 min for its
   next run.
2. *DH Evaluate* turns those times into statuses. It measures each age at the tracker's last run,
   which can be up to 1 min old.

So a status shows up to about 2 min after its limit is crossed.

| What stops | Its limit | LATE after about | MISSING or DOWN after about | Measured in the fault-injection run |
|---|---|---|---|---|
| A UF (its host row) | 90 s | 2.5–3.5 min | DOWN: 4–5 min | LATE 2 min 25 s to 3 min 24 s; DOWN 4 min 4 s to 4 min 28 s |
| Cribl (the `cribl` row) | 120 s | 3–4 min | DOWN: 5–6 min | LATE 3 min 6 s; DOWN 5 min 6 s |
| Any other item | *t* | *t* + 2 min | MISSING: 2 × *t* + 2 min | `cpu` (120 s): LATE 3 min 4 s; MISSING 5 min 4 s |
| An item that never arrives | — | — | NEVER_SEEN: 1 h after it was added | — |

Why these times:
- **A UF: 4–5 min to DOWN.** DOWN needs 3 min without a heartbeat (2 × 90 s). The tracker and the
  evaluator add up to 2 min. A UF sends a heartbeat every 30 s, so its last one can come up to 30 s
  before the stop. That takes a little off.
- **Cribl: 5–6 min to DOWN.** Cribl has no UF. Its heartbeat is its own logs, which each worker
  writes once a minute. So its limit is 120 s. DOWN needs 4 min of silence (2 × 120 s), plus the same
  2 min.
- **Until Cribl is DOWN,** the UF host rows read "The Splunk agent stopped reporting". Their
  heartbeats also pass through Cribl, and their shorter limit runs out first. Once `cribl` is DOWN,
  every `via=cribl` row reads "Cribl DOWN" instead.

The [fault-injection record](records/2026-11-fault-injection-run.md) has every measurement.

## Alerts

| Alert | Fires when | Throttle |
|---|---|---|
| *DH Alert missing* | An item with criticality 1 or 2 goes MISSING. Unset counts as 2. It runs every minute. | 1 h per item, so one item alerts at most once an hour. |
| *DH Alert tamper* | *DH Tamper* stores a new tamper finding that isn't the role's own work. *DH Tamper* runs every 5 min, and the alert 1 min later. | 1 h per host and indicator code, so a reboot finding can't hide a later log clear. |

LATE, NEVER_SEEN and criticality 3 and 4 never alert. A tamper finding shows at the next *DH Tamper*
run, up to 5 min after its event is indexed. Its alert follows about 1 min later. Measured: findings
3 min 39 s to 4 min 52 s after the event, and alerts 4 min 57 s to 5 min 50 s.

## Cribl as the relay

Everything collected passes through Cribl. So every UF and syslog row carries `via=cribl`. `cribl`
is itself an expected host, and its heartbeat is its workers' own logs. If `cribl` is DOWN, every
`via=cribl` row says "Cribl DOWN: the real state is unknown". HEC (wd2l and markers) doesn't use
Cribl. So the "Splunk not receiving" banner stays off, and the two failures look different.

Splunk sees only Cribl's connection. So a UF's version, OS and last connect come from the **UF's own
`_internal`**: `Connected to idx=`, `System info:` and `Splunkd starting (build …)`. The lookup
`dh_uf_builds` maps a build to a version. Add a row each time you pin a new UF version.

**Known limits:**
- "Cribl DOWN" takes about 5–6 min to appear after Cribl stops. The UF host rows show their own cause
  first ([why](#how-long-until-late-missing-or-down)).
- On a `via=cribl` row, a tamper finding within 15 min of a Cribl outage takes precedence. The row
  reads "Possible deliberate blinding", not "Cribl DOWN".
- A `via=cribl` row also takes host `cribl`'s tamper findings. So a Drop route added in Cribl shows
  as the cause for the rows it blinds. A marker for the row's own host doesn't silence it.

## Tamper indicators

A tamper finding within 15 min of a silence turns the cause into "Possible deliberate blinding". One
exception: DH Tamper marks a finding as the role's own work. That needs an Ansible marker for the
host from up to 15 min before the finding, or up to 60 s after it (clock skew). The role posts its marker before each
change it makes.

DH Tamper decides this once, when it first stores the finding. (A Splunk agent stop is judged a
little later, then never changes: see [The Splunk agent stop](#the-splunk-agent-stop).) A marker
posted later never hides a finding that already alerted. An example is a marker from a restore run.

The indicators:
- **Windows:** event IDs 1102 (log cleared), 104, 1100, 4719 (audit policy changed) and 4697 or 7045
  (service installed). Also 7036 and 7040 (SplunkForwarder or EventLog stopped, or its start type
  changed). Windows Server logs 7036 by default. Desktop Windows (8 and later) doesn't. In this lab:
  HOMEPC runs Windows 11 Pro and logs no 7036. The Splunk agent's own shutdown line (below) now
  covers desktop Windows. `win7036` stays for Windows Server. A host shutdown shows as event 1074
  (names the user and the reason) or 6006.
- **Linux:** auditd `DAEMON_END` or `DAEMON_ABORT`, `CONFIG_CHANGE`, and `SERVICE_STOP` of
  SplunkForwarder, auditd or rsyslog. Also audit keys `hl-*` and `wd2l-*`, which cover writes to the
  UF's config, to rsyslog and to `/etc/audit`. On EL10, `systemctl stop auditd` is refused.
  `service auditd stop` works. It writes `DAEMON_END` (with the auid), not `SERVICE_STOP`. A host
  shutdown writes the audit record `SYSTEM_SHUTDOWN`.
- **The Splunk agent's own log:** the line "Shutting down splunkd" in `_internal`, on Windows and
  Linux. It gives the code `uf_shutdown`. Only hosts with a universal forwarder count. A full
  Splunk server restarts for ordinary reasons, so it never gives a finding.
- **Cribl:** any create, update, delete, reorder or upload of routes, pipelines, outputs, inputs or
  lookups in Cribl's audit log (`sourcetype=cribl:audit`). The log can't tell a Drop route from any
  other edit. So every change outside a `cribl` marker window counts. Cribl's free licence has no
  RBAC, so the user is always `admin`.
- **Clock steps** of 5 min or more.

### The Splunk agent stop

Stopping the Splunk agent for a few minutes hides activity without the host ever reaching DOWN.
So an agent stop is a tamper finding, unless something explains it. Four rules:

- **One stop, one finding (the fold).** The shutdown line (`uf_shutdown`), the Linux
  `svcstop_splunkforwarder` and the Windows `win7036` for the Splunk agent can all describe one
  stop. Different codes on one host within 15 min (`dh_tamper_window_secs`) make one finding, for
  example "Splunk agent stopped (SERVICE_STOP + shutdown line)". Two lines of the same code never
  fold, so a role `restart` that stops the agent twice gives two findings and one row on the panel.
- **The hold.** The evidence for a stop often arrives after the stop. A Linux shutdown record is
  only sent when the VM boots again. So the app doesn't judge an agent stop when it first sees it.
  The finding is *pending*. The same hold applies to `svcstop_auditd`, `svcstop_rsyslog`,
  `audit_daemon_end`, `audit_daemon_abort` and `win1100` when an agent stop is on the same host
  within 15 min, because a host shutdown also writes those. The same codes on a host whose agent
  kept running are judged at once, as before.
- **Explained at once** when a marker covers the stop (the rule above), reason *role work*, or when
  the host's own shutdown record is from 10 min before the stop to 2 min after it, reason *host
  shutdown*. A 1074 ranks first because it names the user and the reason. The window is lopsided on
  purpose: if someone stops the agent, works, and then reboots, the reboot explains the stop only
  when it comes within 2 min.
- **Otherwise it waits** until the host's Splunk agent is heard from again, plus 10 min
  (`dh_tamper_settle_secs`) for late records. Then, if nothing explains it, the finding is judged
  *unexplained* and *DH Alert tamper* fires once. If the agent never comes back, the finding stays
  pending and never alerts. The host is DOWN then, and DOWN alerts on its own.

A pending finding explains nothing: the cause "Possible deliberate blinding" ignores it. Once judged,
a finding never changes. Findings stored before this feature have no state and read as judged.

The *Restarts and agent stops* panel on the Overview (24 h) and Host detail (7 d) shows every
episode, explained or not, with what explained it. So a planned shutdown doesn't alert, and it
doesn't vanish either.

The volume check flags an hour below 20 % of the same hour's 14-day median. It needs a median of at
least 100 events and at least 3 covered days. It catches partial blinding.

## Test block

A [test block](glossary.md#test-block) drops real data in Cribl so you can test the alerting end to
end. How it works and how to set one: [running-the-role.md](running-the-role.md#test-blocks).

## Porting to production

| Here | In production |
|---|---|
| The expected list comes from Ansible's inventory. | Generate it from the deployment pipeline the same way. Examples are deployment-server serverclasses, the CMDB or Terraform state. Use one source for both the inputs and the expectations. |
| One search head, with the KV store. | A search-head cluster replicates the KV store. Keep **one writer per collection**, because a KV `key_field` upsert replaces whole records. |
| A single Cribl instance. | The relay row works the same for each worker group. Give each group its own expected row and `via`. |
| Index-time parsing. | Splunk applies no index-time rule to Cribl-delivered data. Redo a TA's line breaking, timestamps and `source`/`sourcetype` rewrites in Cribl's event breakers or on the UF stanza. |
| UF identity. | Read it from the UF's own `_internal`, never from `tcpin_connections`, which shows only the relay. Identify hosts by name, never by IP. |
| The test block in Cribl. | It ports with Cribl, not with Splunk. Treat block changes as privileged, because a block control is itself a way to blind monitoring. |
| The Dashboard risky-command check is off. | Keep it on in production and accept "Run Query" on Manage's writes. Or move those writes out of dashboards. With it off, a crafted link can run a mute, limit, add or adopt write as whoever opens it ([why it is off here](running-the-role.md#the-dashboard-risky-command-check-is-off)). |
| 14-day retention. | Every lookback must stay within the shortest retention. The `retention-windows` test in `tests/spl/run.sh` checks it. |
| Splunk Cloud. | Everything here is search-time SPL plus KV, so it works. The block stays in Cribl. |
| TrackMe. | This app is a yardstick. It answers the same questions (expected, cadence, liveness, cause) in plain SPL. |
