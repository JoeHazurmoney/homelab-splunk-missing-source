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

`OK` · `LATE` (over the threshold) · `MISSING` (over 2 × the threshold) · `NEVER_SEEN` (expected for
more than 1 h, never arrived) · `MUTED` · `PENDING` · `INFO`.

A host is **DOWN** when its liveness is missing (or, without a heartbeat or probe, when every stream
is missing), **DEGRADED** when some child is late or missing, otherwise **OK**. A host mute covers its
children.

**PENDING (the gate):** when the fast tracker hasn't run for 2 min, when Splunk has received nothing
for 2 min, or within 5 min of a resume (PC sleep, restart), everything is held as PENDING and no alert
fires. A pause in the lab doesn't page anyone.

## Cribl as the relay

Everything collected passes through Cribl, so every UF and syslog row carries `via=cribl`, and
`cribl` is itself an expected host (heartbeat: its workers' own logs). If `cribl` is DOWN, every
`via=cribl` row says "Cribl DOWN: the real state is unknown". HEC (wd2l, markers) doesn't use Cribl, so
the "Splunk not receiving" banner stays off: the two failures look different.

Because Splunk sees only Cribl's connection, a forwarder's version, OS and last connect come from the
**UF's own `_internal`** (`Connected to idx=`, `System info:`, `Splunkd starting (build …)`). The
lookup `dh_uf_builds` maps build to version; add a row with each new pinned UF.

**Known limits:**
- "Cribl DOWN" appears about 5–6 min after Cribl stops (2 × 120 s plus an evaluator minute). Until
  then the UF host rows read "The Splunk agent stopped reporting".
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
  `/etc/audit`). On EL10, `service auditd stop` writes `DAEMON_END` and no `SERVICE_STOP`.
- **Cribl:** any create, update, delete, reorder or upload of routes, pipelines, outputs, inputs or
  lookups in Cribl's audit log (`sourcetype=cribl:audit`). The log can't tell a Drop route from
  another edit, so every change outside a `cribl` marker window counts. Cribl's free licence has no
  RBAC, so the user is always `admin`.
- **Clock steps** of 5 minutes or more.

The volume check flags an hour below 20 % of the same hour's 14-day median (where that median is
≥ 100 events and there are at least 3 covered days). It catches partial blinding.

## Test block

A test block drops real data in Cribl (`pl_test_block`) so you can test the alerting end to end. The
status stays real, and the row is labelled "test block until hh:mm". The role's `cribl_block` tag sets
it in Cribl and writes the same table into Splunk (`hl_ingest_block`) for the label; the Manage form
only shows that command. Only `linux`, `windows` and `network` can be blocked. Expiry is checked per
event; nothing removes expired rows on a schedule. Every change is in Cribl's audit log and counts as
tampering outside a marker window.

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
