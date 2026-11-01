# How the data-health app decides something is missing

The full model is in [the spec](specs/2026-10-30-design.md) §2 and §7. This page is the short version,
plus what changes in production.

## The five ideas

1. **The expected list comes from the deployment code.** The role's input rows render both the
   forwarders' `inputs.conf` and `dh_expected_ansible.csv`. *DH Sync expected* merges that file into the
   KV collection `dh_expected`: it adds new rows, updates changed ones, and switches off rows whose
   input left the inventory. Rows added on the Manage dashboard (`managed_by=ui`) are never touched,
   and an empty file changes nothing.
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
`cribl` is itself an expected host. If `cribl` is DOWN, every `via=cribl` row says "Cribl DOWN: the
real state is unknown". HEC (wd2l, markers) doesn't use Cribl, so the "Splunk not receiving" banner
stays off: the two failures look different.

Because Splunk sees only Cribl's connection, a forwarder's version, OS and last connect come from the
**UF's own `_internal`** (`Connected to idx=`, `System info:`, `Splunkd starting (build …)`). A small
table maps build to version.

## Tamper indicators

Findings within 15 minutes of a silence, outside an Ansible marker window, become "possible deliberate
blinding":
- **Windows:** 1102 (log cleared), 104, 4719 (audit policy changed), 1100, 4697/7045 (service
  installed), 7036/7040 (SplunkForwarder or EventLog stopped or changed).
- **Linux:** auditd `DAEMON_END`/`ABORT`, `CONFIG_CHANGE`, `SERVICE_STOP` of SplunkForwarder, auditd or
  rsyslog, and audit keys `hl-*` and `wd2l-*` (writes to the UF's config, rsyslog or `/etc/audit`).
- **Cribl:** any change to routes, pipelines, outputs, inputs or lookups in Cribl's audit log. The log
  can't tell a Drop route from another edit, so every change outside a `cribl` marker counts.
- **Clock steps** of 5 minutes or more.

The volume check flags an hour below 20 % of the same hour's 14-day median (where that median is
≥ 100 events). It catches partial blinding.

## Test block

A test block drops real data in Cribl (`pl_test_block`) so you can test the alerting end to end. The
status stays real, and the row is labelled "test block until hh:mm". The role's `cribl_block` tag sets
it and mirrors the table into Splunk for the label. Only `linux`, `windows` and `network` can be
blocked. Every change is in Cribl's audit log and counts as tampering outside a marker window.

## Porting to production

| Here | In production |
|---|---|
| the expected list from Ansible's inventory | generate it from the deployment pipeline (deployment-server serverclasses, the CMDB, Terraform state) the same way: one source for both the inputs and the expectations |
| one search head, KV store | a search-head cluster replicates KV; keep **one writer per collection** (a KV `key_field` upsert replaces whole records) |
| Cribl single instance | the Cribl relay row works the same per worker group; give each group its own expected row and `via` |
| the test block in Cribl | it ports with Cribl, not with Splunk. Treat block changes as privileged: they are a blinding vector |
| Splunk Cloud | everything here is search-time SPL plus KV, so it works; the block stays in Cribl |
| TrackMe | this app is a yardstick: the same questions (expected, cadence, liveness, cause) answered in plain SPL |
