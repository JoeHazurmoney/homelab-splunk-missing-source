# How the data-health app decides something is missing

The full model is in [the spec](specs/2026-10-30-design.md) §2 and §7. This page is the short version,
plus what changes in production. `hl_data_health` is SPL plus KV store only: no scripts, no custom
commands, no index-time config.

## The five ideas

1. **The expected list comes from the deployment code.** The role's input rows render both the
   forwarders' `inputs.conf` and `dh_expected_ansible.csv`. *DH Sync expected* merges that file into the
   KV collection `dh_expected` by `_key` upserts: it adds new rows, updates changed ones, and switches
   off rows whose input left the inventory. An enabled row added on the Manage dashboard
   (`managed_by=ui`) is never overwritten, even for the same entity, and an empty file changes nothing.
2. **Cadence profiles, not one threshold.**

   | Profile | For | Maximum silence |
   |---|---|---|
   | heartbeat | UF `_internal`; Cribl's own logs | UF 90 s; Cribl 120 s |
   | periodic | scripted inputs, the device probe | 2 × interval + 60 s |
   | continuous | busy logs | learned (5–60 min); 15 min while learning |
   | sporadic | event-driven logs | learned (2 h – 7 d); 24 h while learning |
   | info | tracked, never alerts | — |

   Learned = `clamp(1.5 × p90(daily max gap over 14 days) + 120 s)`, counting only time when the host
   and Splunk were up, once there are at least 3 covered days. Precedence: a Manage override, then the
   input's declared `max_gap_secs`, then the learned value, then the default. The dashboards always say
   which one applied.
3. **Liveness apart from data.** A UF's `_internal` metrics (every 30 s) are its heartbeat. A device
   without an agent gets one from pi5's probe (a ping every 60 s). "Up but not logging" and "down"
   become different findings.
4. **State, not scans.** Trackers (`tstats`, every minute, by index time so backfill counts) record
   the last arrival per index/host/sourcetype/source in KV. *DH Evaluate* turns that into a status per
   entity, and writes **changes** to `index=data_health source=dh:transition`. The dashboards read KV,
   so they stay fast at hundreds of hosts.
5. **Every finding has a likely cause and an action.** The evidence: heartbeat, Ansible markers,
   Hyper-V VM events, the relay (Cribl) and tamper indicators. See the
   [runbook](runbook-missing-data.md).

## Statuses and roll-up

Each item on the expected list has one status. Its limit is how long it may stay silent: its
threshold, from the profile table above.

| Status | What it means | What to do |
|---|---|---|
| OK | Data arrived within its limit. | Nothing. |
| LATE | Silent longer than its limit, but not yet twice as long. | Look at the cause. Often it recovers by itself. |
| MISSING | Silent more than twice its limit. This is what alerts (for criticality 1 and 2). | Follow the action in the Action column. |
| NEVER_SEEN | On the expected list for more than an hour and has never sent anything. | Check that the input is deployed and sending; the Action column says where. |
| MUTED | Muted on purpose on Manage, with a reason and an end time. A host mute covers everything it sends. | Nothing while muted. Unmute on Manage when the work is done. |
| PENDING | No trusted status right now: either the app itself is on hold (the gate, below), or the item was added less than an hour ago and hasn't sent anything yet. No alerts fire. | If the banner says "On hold", fix what it says. Otherwise wait. |
| INFO | Tracked for reference only; it never alerts. | Nothing. |

**Host roll-up.** A host also gets an overall state from its items:

| Roll-up | What it means |
|---|---|
| DOWN | The host itself looks dead: its Splunk agent's heartbeat (or, for a network device, its probe) is missing; or, for a host without an agent, every item it should send is missing. |
| DEGRADED | The host is alive, but some of its items are late, missing or never seen. |
| OK | Everything the host should send is arriving. |
| MUTED | The host is muted. |
| PENDING | The app is on hold (see the [banner](data-health/dashboards.md#the-banner-is-the-data-current)). |

**PENDING (the gate):** when the fast tracker hasn't run for 2 min, when Splunk has received nothing
for 2 min, or within 5 min of a resume (PC sleep, restart), everything is held as PENDING and no alert
fires. A pause in the lab doesn't page anyone.

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
  evaluator add up to 2 min. The UF sends a heartbeat every 30 s, so its last one can come up to
  30 s before the stop, which takes a little off.
- **Cribl: 5–6 min to DOWN.** Cribl has no UF. Its heartbeat is its own logs, which each worker
  writes once a minute. So its limit is 120 s, and DOWN needs 4 min of silence (2 × 120 s), plus the
  same 2 min.
- **Until Cribl is DOWN,** the UF host rows read "The Splunk agent stopped reporting". Their
  heartbeats also pass through Cribl, and their shorter limit runs out first. Once `cribl` is DOWN,
  every `via=cribl` row reads "Cribl DOWN" instead.

The [fault-injection record](records/2026-11-fault-injection-run.md) has every measurement.

## Alerts

| Alert | Fires when | Throttle |
|---|---|---|
| *DH Alert missing* | an item with criticality 1 or 2 (unset counts as 2) goes MISSING. It runs every minute. | 1 h per item, so one item alerts at most once an hour |
| *DH Alert tamper* | *DH Tamper* stores a new tamper finding that isn't the role's own work. *DH Tamper* runs every 5 min and the alert 1 min later. | 1 h per host and indicator code, so a reboot finding can't hide a later log clear |

LATE, NEVER_SEEN and criticality 3 and 4 never alert. A tamper finding shows at the next *DH Tamper*
run, up to 5 min after its event is indexed, and its alert about 1 min later. Measured: findings 3 min
39 s to 4 min 52 s after the event, alerts 4 min 57 s to 5 min 50 s.

## Cribl as the relay

Everything collected passes through Cribl, so every UF and syslog row carries `via=cribl`, and
`cribl` is itself an expected host (heartbeat: its workers' own logs). If `cribl` is DOWN, every
`via=cribl` row says "Cribl DOWN: the real state is unknown". HEC (wd2l, markers) doesn't use Cribl, so
the "Splunk not receiving" banner stays off: the two failures look different.

Because Splunk sees only Cribl's connection, a forwarder's version, OS and last connect come from the
**UF's own `_internal`** (`Connected to idx=`, `System info:`, `Splunkd starting (build …)`). The
lookup `dh_uf_builds` maps build to version; add a row with each new pinned UF.

**Known limits:**
- "Cribl DOWN" takes about 5–6 min to appear after Cribl stops; the UF host rows show their own
  cause first ([why](#how-long-until-late-missing-or-down)).
- On a `via=cribl` row, a tamper finding within 15 min of a Cribl outage takes precedence: the row
  reads "Possible deliberate blinding", not "Cribl DOWN".
- A `via=cribl` row also takes host `cribl`'s tamper findings, so a Drop added in Cribl explains the
  rows it blinds. A marker for the row's own host doesn't silence it.

## Tamper indicators

Findings within 15 minutes of a silence become "possible deliberate blinding", unless DH Tamper
marked them as the role's own work. A finding is the role's own work when an Ansible marker for its
host came at most 15 minutes before it (or up to 60 s after, for clock skew). The role posts its
marker before each change it makes. This is decided once, when the finding is first stored: a
marker posted later, for example by a restore run, never hides a finding that already alerted.
The indicators:
- **Windows:** 1102 (log cleared), 104, 1100, 4719 (audit policy changed), 4697/7045 (service
  installed), 7036/7040 (SplunkForwarder or EventLog stopped or its start type changed).
- **Linux:** auditd `DAEMON_END`/`DAEMON_ABORT`, `CONFIG_CHANGE`, `SERVICE_STOP` of SplunkForwarder,
  auditd or rsyslog, and audit keys `hl-*` and `wd2l-*` (writes to the UF's config, rsyslog or
  `/etc/audit`). On EL10, `systemctl stop auditd` is refused; `service auditd stop` works and writes `DAEMON_END`
  (with the auid), not `SERVICE_STOP`.
- **Cribl:** any create, update, delete, reorder or upload of routes, pipelines, outputs, inputs or
  lookups in Cribl's audit log (`sourcetype=cribl:audit`). The log can't tell a Drop route from
  another edit, so every change outside a `cribl` marker window counts. Cribl's free licence has no
  RBAC, so the user is always `admin`.
- **Clock steps** of 5 minutes or more.

The volume check flags an hour below 20 % of the same hour's 14-day median (where that median is
≥ 100 events and there are at least 3 covered days). It catches partial blinding.

## Test block

A test block drops real data in Cribl so you can test the alerting end to end. How it works and how
to set one: [running-the-role.md](running-the-role.md#test-blocks).

## Porting to production

| Here | In production |
|---|---|
| the expected list from Ansible's inventory | generate it from the deployment pipeline (deployment-server serverclasses, the CMDB, Terraform state) the same way: one source for both the inputs and the expectations |
| one search head, KV store | a search-head cluster replicates KV; keep **one writer per collection** (a KV `key_field` upsert replaces whole records) |
| a Cribl single instance | the relay row works the same per worker group; give each group its own expected row and `via` |
| index-time parsing | Splunk applies no index-time rule to Cribl-delivered data, so a TA's line breaking, timestamps and `source`/`sourcetype` rewrites must be redone in Cribl's event breakers or on the UF stanza |
| forwarder identity | from the UF's own `_internal`, never `tcpin_connections` (it shows only the relay); identify hosts by name, never by IP |
| the test block in Cribl | it ports with Cribl, not with Splunk. Treat block changes as privileged: in production a block control is itself a blinding vector |
| the Dashboard risky-command check off | keep it on in production and accept "Run Query" on Manage's writes, or move those writes out of dashboards |
| 14-day retention | every lookback must stay within the shortest retention; the `retention-windows` test in `tests/spl/run.sh` checks it |
| Splunk Cloud | everything here is search-time SPL plus KV, so it works; the block stays in Cribl |
| TrackMe | this app is a yardstick: the same questions (expected, cadence, liveness, cause) answered in plain SPL |
