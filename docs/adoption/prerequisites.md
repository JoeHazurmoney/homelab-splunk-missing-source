# Prerequisites: the homework before you install

This is a checklist. It lists every source and setting that `hl_data_health` needs in order to run.
The customer's Splunk admin, Cribl admin and Linux and Windows owners do the work. The SOC lead
reviews the result. It is feature F1 of [the roadmap](roadmap.md).

The app finds data that should arrive and does not. Each item below feeds one part of that job.
If an item is missing, one status, cause or panel breaks. The "Without it" line says which.

**Scope.** This is for Splunk Enterprise only. Splunk Cloud is out of scope.

**How each item reads:**
- **What:** the thing you must have.
- **Why:** what the app does with it.
- **Check:** how to prove it. The line says where to run it.
- **Without it:** what breaks.

Where the lab does something one way, the item says what your production setup must provide. The
lab's words are in [the design page](../data-health-design.md) and
[the architecture page](../architecture.md).

## 1. Splunk platform

### 1.1 Splunk Enterprise version

- **What:** Splunk Enterprise on the version the app was proven on. The lab server runs 10.6.0.5.
  The lab forwarders run 10.6.1.1. Another version is a risk. Test it in the pilot
  ([F2](roadmap.md#f2-pilot-install)).
- **Why:** the app is search-time SPL plus the KV store. It has no scripts and no custom commands.
  The macros and dashboards were tested on that version only.
- **Check:** on the search head, in Search:

  ```
  | rest splunk_server=local /services/server/info | table version build
  ```

- **Without it:** unknown. The docs promise nothing for other versions.

### 1.2 One search head or a search-head cluster

- **What:** pick one layout. The app works on one search head. A cluster is possible, with one rule:
  run each scheduled writer on one member only. Each KV collection has a known set of writers. A KV
  upsert replaces the whole record. Two writers that change the same row would overwrite each other.
- **Why:** each collection lists its writers in the comments of
  `splunk/apps/hl_data_health/default/collections.conf`. For example, only *DH Evaluate* writes
  `dh_status`. `dh_expected` has two writers: *DH Sync expected* (inventory rows) and Manage (rows
  added on screen, `managed_by=ui`).
- **Check:** on each search head, in Search. The KV store must be healthy:

  ```
  | rest /services/kvstore/status | table splunk_server current.status
  ```

  Then check that each scheduled search runs once per minute, not twice:

  ```
  index=_internal sourcetype=scheduler app=hl_data_health savedsearch_name="DH Evaluate" earliest=-10m
  | stats count by host
  ```

  The count should be about 10 on one host.
- **Without it:** flapping statuses and lost rows in the KV store.
- **Not proven:** the lab runs one search head. The cluster setup is a design rule from
  [Porting to production](../data-health-design.md#porting-to-production). It was not tested.

### 1.3 The `data_health` index, and the other indexes

- **What:** the index `data_health` must exist. The app writes its own records there. They are
  transitions, tamper findings, the daily report and the admin log. The markers
  ([section 7](#7-change-process-markers-and-mutes)) go there too.
- **What else:** the macro `dh_indexes` lists the indexes the trackers watch. It ships with the lab's
  names: `linux, windows, network, wd2l_uf_audit, enclave1, wd2l, cribl`. Edit it to your own list.
  `data_health` is not in it.
- **Why:** the trackers read `dh_indexes`. The tamper search also reads `_internal` and
  `data_health`, not only `windows`, `linux` and `cribl`.
- **Check:** on the search head, in Search:

  ```
  | eventcount summarize=false index=linux index=windows index=network index=cribl index=data_health
  | stats sum(count) by index
  ```

- **Without it:** a missing index means a stream the app cannot see. Its rows go MISSING or
  NEVER_SEEN.

### 1.4 Retention, and lookbacks inside it

- **What:** every index the app reads must keep data longer than the app looks back. The lab keeps
  14 days (`frozenTimePeriodInSecs = 1209600`). The longest lookback is 14 days. *DH Alert tamper*
  and the baseline searches look back that far. The `_internal` index must keep at least as long.
  The lab keeps it 30 days.
- **Why:** a lookback past retention reads nothing for the old days. The learned limits are wrong
  then.
- **Check:** on the search head, in Search:

  ```
  | rest splunk_server=* /services/data/indexes
  | search title IN (linux, windows, network, cribl, data_health, _internal)
  | table splunk_server title frozenTimePeriodInSecs
  ```

  Every value must be at least 1209600. If your retention is shorter, shorten the lookbacks.
  The test `retention-windows` in `tests/spl/run.sh` checks the lookbacks against the lab's 14 days.
  Run it from a checkout of this repo ([testing](../testing.md#run-testssplrunsh-and-dashsh)).
- **Without it:** learned limits and tamper findings use less history than they should.

### 1.5 Scheduler capacity

- **What:** the search head must run these searches on time. Four run every minute: *DH Tracker
  fast*, *DH Evaluate*, *DH Prune* and *DH Alert missing*. The rest run every 5 or 15 minutes,
  hourly or daily. The lab gives the four one-minute searches top priority. Each search allows one run at a time.
- **Why:** a skipped run is a gap in the data. If the tracker is late for 2
  minutes, the app holds all statuses as PENDING and sends no alerts.
- **Check:** on the search head, in Search. Look for skipped runs:

  ```
  index=_internal sourcetype=scheduler app=hl_data_health status=skipped earliest=-24h
  | stats count by savedsearch_name reason
  ```

  A busy search head shows skips. Ask the Splunk admin for room before the pilot.
- **Without it:** statuses show PENDING with the banner "On hold". Alerts stop.

### 1.6 Licence volume

- **What:** the app adds little licensed volume. It writes its records with `collect` as sourcetype
  `stash`, which does not count against the licence. The markers do count. The docs give no number
  for them. They are one small event per change.
- **Why:** the licence is mostly for the data you already collect. The lab's own collection is about
  529 MB/day. That is not a number for your site.
- **Check:** in Splunk Web, Settings, Licensing. Then check the *Licence used yesterday* tile on
  [Daily state of health](../data-health/dashboards.md#daily-state-of-health) after the pilot.
- **Without it:** an expired licence stops searches, so the app's alerts stop too.

## 2. Roles and permissions

### 2.1 The two roles

- **What:** `dh_analyst` and `dh_admin`. Their definitions are in
  `splunk/apps/hl_server_base/default/authorize.conf`. In the lab, that app also creates the
  indexes. In production, make the same two roles in your own app.
  - `dh_analyst` can search, read the dashboards and mute.
  - `dh_admin` is `dh_analyst` plus the right to edit the expected list and see test blocks.
  - Neither role has `run_collect`, `run_mcollect` or `schedule_rtsearch`.
  - In your copy of the roles, remove the lab-only indexes (such as `enclave1` and `wd2l`) from
    `srchIndexesAllowed` in the stanza `[role_dh_analyst]` of
    `splunk/apps/hl_server_base/default/authorize.conf`.
- **Why:** the dashboards check for the roles by name. The KV store access in
  `metadata/default.meta` names them too.
- **Check:** on the search head, in Search:

  ```
  | rest /services/authorization/roles | search title IN (dh_analyst, dh_admin)
  | table title srchIndexesAllowed imported_roles
  ```

- **Without it:** Manage says "Needs the dh_admin role" and writes nothing.

### 2.2 The `_internal` trade-off

- **What:** `dh_analyst` may read `_internal`. This is a choice. The Host detail panel *Latest Splunk
  agent errors and warnings* reads it. The commonest causes point to that panel.
- **The cost:** `_internal` holds Splunk's own logs. Analysts can read all of them.
- **Your options:** keep it, or remove `_internal` from the role's `srchIndexesAllowed`. Then that
  panel shows nothing to analysts. Give `_internal` to `dh_admin` users in another role.
- **Check:** the same search as 2.1. Look for `_internal` in the list.
- **Without it:** that one panel is empty. The statuses still work.

### 2.3 The owner of the saved searches

- **What:** the scheduled searches are shared with owner `nobody`. They run as Splunk's system user.
  That user must write the KV store and read every index the app tracks.
- **Why:** if a search runs as a user with less access, it sees fewer events. Hosts then look
  missing.
- **Check:** on the search head, in Search:

  ```
  index=_internal sourcetype=scheduler app=hl_data_health earliest=-15m
  | stats count by savedsearch_name user status
  ```

  Every row should show the same system user and the status `success`.
- **Without it:** wrong MISSING statuses, or no writes to the KV store.

### 2.4 Who may set test blocks

- **What:** a short named list of people. A [test block](../glossary.md#test-block) drops real data
  in Cribl. The Manage tab only shows the command. The lab's Test blocks (admin) tab shows an Ansible
  command (the role's `cribl_block` tag), not a generic Cribl command. Your Cribl admin must replace
  it with their own way to set and clear a block, for example their own automation against the same
  Cribl lookup. The command is run by someone with access to the Cribl API. See [section 4.5](#45-the-test-block-lookup-and-pipeline).
- **Why:** a way to drop data on purpose is also a way to blind the SOC.
- **Check:** list the people who hold `dh_admin` and the Cribl admin rights. The two lists should be
  short.
- **Without it:** anyone with Cribl admin rights can hide a host, and the SOC sees only a tamper
  finding.

## 3. Splunk Universal Forwarders

### 3.1 `_internal` forwarded from every UF

- **What:** each UF sends its own `_internal` logs to Splunk. That includes `metrics.log` and
  `splunkd.log`. Through Cribl, the route must not drop or rewrite them.
- **Why:** this is the heartbeat. The metrics line arrives every 30 seconds. The limit is 90
  seconds. The app also reads the UF's own lines `Connected to idx=`, `System info:` and `Splunkd
  starting (build …)`. It gets the UF's version, OS and last connect from them. It does not use
  `tcpin_connections`, because that shows only the relay.
- **Check:** on the search head, in Search:

  ```
  | tstats max(_indextime) as hb where index=_internal source=*metrics.log* earliest=-1h by host
  | eval age=now()-hb | sort - age
  ```

  Every UF host must appear, with an age under 90 seconds.
- **Without it:** the host shows DOWN or "The Splunk agent stopped reporting". The app cannot tell a
  dead host from a silent one.

### 3.2 The shutdown line

- **What:** the line `Shutting down splunkd` (component `Shutdown`) reaches `_internal`.
- **Why:** it is the agent's own record that it stopped. It makes the `uf_shutdown` tamper finding.
  See [The Splunk agent stop](../data-health-design.md#the-splunk-agent-stop). Only hosts with a UF
  count.
- **Check:** on the search head, in Search. Restart one test UF first:

  ```
  index=_internal sourcetype=splunkd component=Shutdown "Shutting down splunkd" earliest=-1h
  ```

- **Without it:** a short agent stop is not a finding. The *Restarts and agent stops* panel is
  empty.

### 3.3 The UF version policy

- **What:** one pinned UF version, and a map from its build to the version. The macro
  `dh_fwd_expected_version` holds the version. The lookup `dh_uf_builds` maps a build to a version.
  Add a row each time you pin a new UF.
- **Why:** the UF logs its build, not its version. The daily report lists agents on another version.
- **Check:** In the HL Data Health app, open Search and run:

  ```
  | inputlookup dh_fwd | table host version os fwd_type
  ```

  The version column should show your version, not "build …".
- **Without it:** the version shows as a build hash. The report flags every agent as off version.

### 3.4 The apps and inputs for each OS

- **What:** the TAs and inputs that make the data you want watched. The lab list is in
  [What is collected](../architecture.md#what-is-collected). In short:
  - Linux: files `/var/log/messages`, `cron`, `secure` and `audit/audit.log`, plus the Splunk
    Add-on for Unix and Linux scripts.
  - Windows: the event logs Security, System and Application, plus any others you track.
- **Why:** each input becomes a row on the expected list ([section 6](#6-the-inventory-feed)).
- **Check:** on the search head, in Search:

  ```
  | tstats count where index IN (linux, windows) earliest=-24h by host sourcetype
  ```

- **Without it:** a missing input shows NEVER_SEEN after one hour.

### 3.5 Never run the splunk CLI as root on a UF

- **What:** run `splunk` on a Linux UF as the UF's own user. Never use `sudo splunk`.
- **Why:** `sudo splunk` changes ownership of the UF folder. That fires the `hl-uf-config` audit rule.
  The app then raises a false tamper finding and an alert. See
  [the rule](../running-the-role.md#never-run-splunk-as-root-on-a-uf).
- **Check:** ask the Linux owners. Add the rule to the team's run notes.
- **Without it:** false tamper alerts.

## 4. Cribl Stream

### 4.1 Routes and pipelines that deliver to Splunk

- **What:** the routes send every source to Splunk. The UFs' data keeps the index and sourcetype
  the UF set. Check that your Cribl output does not add fields that change `host`, `source` or
  `sourcetype`.
- **Why:** the app watches arrival in Splunk, by index time. It checks the `via` setting of each row
  to name Cribl as a cause.
- **Check:** in Cribl, look at Routes. In Splunk, run:

  ```
  | tstats max(_indextime) as last where index IN (linux, windows, network) earliest=-1h by index
  ```

- **Without it:** whole indexes go MISSING.

### 4.2 Cribl's own logs and metrics in Splunk

- **What:** Cribl sends its own logs to the index `cribl`, and its metrics to `cribl_metrics`. The
  lab host value is `cribl`, and the sourcetype is `cribl`. The host name `cribl` is a shipped
  default in the macros `dh_eval_facts` and `dh_tamper_cribl`. If your Cribl host has another name,
  change it in both macros.
- **Why:** Cribl has no UF. Its own logs are its heartbeat. Its limit is 120 seconds. The metrics
  index is not tracked by the app. Send it anyway if you want to chart Cribl.
- **Check:** on the search head, in Search:

  ```
  | tstats max(_indextime) as last where index=cribl sourcetype=cribl earliest=-15m by host
  | eval age=now()-last
  ```

  Each worker group should show an age under 120 seconds.
- **Without it:** the `cribl` row is NEVER_SEEN or DOWN, and every row that passes through Cribl
  reads "Cribl DOWN".

### 4.3 The Cribl config-change audit

- **What:** Cribl's audit log goes to the index `cribl` with sourcetype `cribl:audit`.
- **Why:** it is a tamper source. The app reads these actions: create, update, delete, reorder and
  upload. They must be on routes, pipelines, outputs, inputs or lookups. The log cannot tell a Drop
  route from other edits. So every change outside a maintenance marker is a finding.
- **Check:** change a harmless setting in a test Cribl group. Then, in Search:

  ```
  index=cribl sourcetype="cribl:audit" earliest=-1h | table _time action type user id
  ```

- **Without it:** a Drop route that hides a host is not a tamper finding.
- **Know this:** the audit log is silent when nobody edits. So it has no expected row.

### 4.4 One expected row and `via` for each worker group

- **What:** each Cribl worker group gets its own expected row. Each row that passes through a group
  names it in `via`.
- **Why:** if the group stops, the rows behind it read "Cribl DOWN" and not "host missing".
- **Check the code:** as shipped, the app names one relay, `cribl`. It is written in the macros
  `dh_eval_facts` and `dh_tamper_cribl`. Two or more groups with other names need a change in
  those macros. Plan this with the app's owner. See the notes in
  [Porting to production](../data-health-design.md#porting-to-production).
- **Check the data:** the search in 4.2 shows one host value for each group.
- **Without it:** when one group fails, its rows show host-level causes, which sends people to the
  wrong place.

### 4.5 The test-block lookup and pipeline

- **What:** a lookup and a pipeline in Cribl that drop events for a host on request. The lab calls
  them `hl_ingest_block` and `pl_test_block`. Splunk keeps a mirror of the table.
- **Why:** it lets you test the alerts end to end without breaking a real log. It is also the
  [per-wave acceptance test](roadmap.md#f8-staged-rollout).
- **Check:** this is optional. Without the mirror, the app reads an empty table and works. If you
  want it, the Cribl admin must say how a block is set and cleared. The Manage tab shows the lab's
  Ansible command (the role's `cribl_block` tag). Your Cribl admin replaces it with their own way,
  for example their own automation against the same Cribl lookup.
- **Treat it as privileged:** a block control is itself a way to blind monitoring. See
  [section 2.4](#24-who-may-set-test-blocks) and [section 8](#8-security-settings).
- **Without it:** no end-to-end test. Use a muted test host instead.

### 4.6 Event breaking moved to Cribl

- **What:** Splunk applies no index-time rule to data that Cribl delivers. Redo line breaking,
  timestamps and `source` and `sourcetype` rewrites in Cribl event breakers. Or do it on the UF
  stanza.
- **Why:** the app matches the exact sourcetype and source names. A wrong name looks like a
  missing stream.
- **Check:** compare the sourcetypes in Splunk with the expected list:

  ```
  | tstats count where index IN (linux, windows, network) earliest=-24h by sourcetype
  ```

- **Without it:** broken events. Auditd records may merge, and the tamper search misses them.

## 5. Hosts and devices

### 5.1 Linux: auditd, its rules and rsyslog

- **What:** auditd runs and writes `/var/log/audit/audit.log`. A UF reads it into the index `linux`
  with sourcetype `linux_audit`. rsyslog writes `/var/log/messages` and `secure`.
- **What the app reads (tamper):**
  - `DAEMON_END` and `DAEMON_ABORT`
  - `CONFIG_CHANGE`
  - `SERVICE_STOP` of SplunkForwarder, auditd or rsyslog
  - `SYSTEM_SHUTDOWN` (it explains a host shutdown)
  - `TIME_INJOFFSET`, and the line "System clock was stepped" for clock steps of 5 minutes or more
  - watch keys that start with `hl-` or `wd2l-`. These are the lab's key prefixes. The lab's rules
    cover the UF folder, rsyslog config and `/etc/audit`. You change the prefixes in the macro
    `dh_tamper_linux`.
  - The app does not read `USER_CMD`.
- **Why:** these are signs that someone stopped or edited logging.
- **Check:** on the Linux host, in a shell:

  ```
  sudo auditctl -s
  sudo auditctl -l | grep -c 'hl-'
  ```

  On the search head, in Search:

  ```
  index=linux sourcetype=linux_audit earliest=-1h | stats count by type
  ```

- **Without it:** tamper findings for Linux do not appear. The `linux_audit` row goes MISSING.

### 5.2 Windows Security and System logs

- **What:** the UF reads the logs in XML form (`renderXml=true`). The sourcetype is
  `XmlWinEventLog`. The classic text form does not work, because the app reads XML tags.
- **What the app reads (tamper):**

  | Event ID | Log | Meaning |
  |---|---|---|
  | 1102 | Security | Security log cleared |
  | 104 | System | An event log cleared |
  | 1100 | Security | Event logging service shut down |
  | 4719 | Security | Audit policy changed |
  | 4697 | Security | Service installed |
  | 7045 | System | Service installed |
  | 7036 | System | Service stopped (SplunkForwarder, EventLog) |
  | 7040 | System | Service start type changed |
  | 4616 | Security | System time changed (5 minutes or more) |
  | 1 (Kernel-General) | System | System clock changed. The app reads it as a clock step (5 minutes or more). |
  | 1074, 6006 | System | Host shutdown (explains an agent stop) |

- **Know this:** Windows Server logs 7036 by default. Desktop Windows 8 and later does not. The
  agent's own shutdown line covers desktop hosts. For servers, check that 7036 arrives.
- **Check:** on the search head, in Search:

  ```
  index=windows sourcetype=XmlWinEventLog earliest=-24h
  | rex field=_raw "<EventID[^>]*>(?<id>[0-9]+)</EventID>"
  | stats count by source id
  ```

  Also confirm the audit policy writes the events (for example 4719 and 4697 need the policy
  change and service categories enabled).
- **Without it:** the Windows tamper findings do not appear. A Security row goes MISSING.

### 5.3 Hypervisor events (optional)

- **What:** if guests are VMs, a log of power events from the hypervisor. The lab uses
  `Microsoft-Windows-Hyper-V-Worker-Admin` with event IDs 18500, 18502, 18504, 18508, 18510 and
  18514. The VM name must be in the event. A production equivalent, such as vCenter events, needs a
  change to the macro `dh_fwd_from_hyperv`.
- **Why:** it gives the cause "The VM is off", with the event and the time.
- **Check:** in Search:

  ```
  index=windows source="XmlWinEventLog:Microsoft-Windows-Hyper-V-Worker-Admin" earliest=-7d
  | stats count
  ```

- **Without it:** a VM that is off reads as a dead UF. The status is still right. The cause text
  is less exact. Nothing else breaks.

### 5.4 Devices with no agent: syslog and a probe

- **What:** each device sends syslog through Cribl. A separate probe pings the device every 60
  seconds. It writes a line such as `device=<name> ip=<ip> reachable=1|0`. The lab's probe is
  `hl-devprobe`. Its lines go to the index `network` with sourcetype `hl:devprobe`. The probe host
  is named in the macro `dh_probe_host`. The lab's probe host is `pi5`, shipped as that macro's
  default. Change it to the host that runs your probe.
- **Why:** a device has no heartbeat. The probe says "up". The syslog says "logging". Together they
  tell "down" from "up but not logging".
- **Check:** in Search:

  ```
  index=network sourcetype="hl:devprobe" earliest=-15m | stats latest(reachable) by device
  ```

- **Without it:** a silent device reads "Nothing at all from this host". That is a guess.

## 6. The inventory feed

### 6.1 One source of truth

- **What:** one system that lists every input and every expectation. It can be a CMDB, the
  deployment server's serverclasses, Terraform state or Ansible. Use one source for both what you
  deploy and what you expect.
- **Why:** if two sources disagree, the app watches what was never deployed, or misses what was.
- **Check:** ask the owner to show how a new host enters the list. Add one test host and see its
  rows appear.
- **Without it:** the expected list drifts. The Unregistered and Retirement candidates panels fill
  up.

### 6.2 The row format

- **What:** a CSV file named `dh_expected_ansible.csv` in the app's lookups. The lab's role renders
  it. Your feed must write the same columns:

  | Column | Meaning |
  |---|---|
  | `level` | `host`, `sourcetype` or `source` |
  | `index`, `host`, `sourcetype`, `source` | The item. Host in short lowercase form. |
  | `collection` | `uf`, `syslog` or `hec` in the lab |
  | `via` | The relay, such as `cribl`. Empty if none. |
  | `hypervisor` | The VM's hypervisor, if any |
  | `profile` | `heartbeat`, `periodic`, `continuous`, `sporadic` or `info` |
  | `interval_secs` | For `periodic` items |
  | `max_gap_secs` | An optional fixed limit |
  | `criticality` | 1 is highest. Alerts fire for 1 and 2. Unset counts as 2. |
  | `owner`, `site`, `runbook`, `description` | Text for the dashboards |
  | `enabled` | 1 or 0 |

  The `entity_id` column stays empty. The sync computes it.
- **Why:** this is the one place the app learns what to expect.
- **Check:** In the HL Data Health app, open Search and run:

  ```
  | inputlookup dh_expected_ansible | stats count by level collection profile
  ```

- **Without it:** nothing is expected, so nothing can go missing. The role refuses an empty file.

### 6.3 The sync and the owner

- **What:** the search *DH Sync expected* runs every 5 minutes. It merges the CSV into `dh_expected`.
  It adds new rows and changes edited ones. It turns off rows whose input left the file. It never
  overwrites an enabled row added on Manage (`managed_by=ui`). An empty file changes nothing.
- **Who:** name one owner for the feed. Name a second person for hand-added Manage rows.
- **Check:** In the HL Data Health app, open Search and run:

  ```
  | inputlookup dh_expected | stats count by managed_by enabled
  ```

- **Without it:** a new host is never watched, and a retired host keeps alerting.

## 7. Change process: markers and mutes

### 7.1 Maintenance markers

- **What:** your automation posts one event before each planned change to a host. The lab's role
  posts it to Splunk's HEC input, not through Cribl. Do the same, so a Cribl outage does not hide
  the marker. The event must have:

  | Field | Value |
  |---|---|
  | index | `data_health` |
  | source | `dh:marker` |
  | sourcetype | `hl:marker` |
  | `target_host` | the host, short and lowercase |
  | `action` | what is being done, such as `stop` or `restart` |
  | `by` | who or what ran it |
  | `run_id` | one ID for all markers of a run |
  | `reason` | optional. Why the change is made. The app adds it to the explanation of an agent stop. |
  | `tags` | optional text. The app keeps it but does not read it. |

  Use `cribl` as `target_host` for a Cribl change.
- **Why:** a tamper finding is hidden when a marker for that host came up to 15 minutes before it.
  It can also come up to 60 seconds after. So post the marker **before** the change. The app also
  uses the marker to name a stop in its causes, for example "Stopped with Ansible".
- **Check:** in Search, after a planned change:

  ```
  index=data_health source="dh:marker" earliest=-1h | table _time target_host action by run_id
  ```

- **Without it:** every planned change raises a tamper alert.
- **Known gap:** a hand edit on a host, with no marker, is a finding. The lab has no marker-only
  tool yet (lab issue #56). Your automation needs one. See [F6](roadmap.md#f6-tamper-coverage).

### 7.2 Mutes for planned work

- **What:** the change ticket tells the on-call person to mute the host on Manage first. A mute needs
  a reason and an end time of 30 days or less. A host mute covers everything the host sends.
- **Why:** a mute stops the alert. A marker explains tamper findings. You need both for a big
  maintenance.
- **Check:** In the HL Data Health app, open Search and run:

  ```
  | inputlookup dh_overrides | table entity_id mute_until reason set_by
  ```

- **Without it:** planned work pages the on-call team.

## 8. Security settings

- **Keep the Dashboard risky-command check ON.**
  - **What:** the setting `enable_risky_command_check_dashboard`. The lab turns it off, so Manage's
    Apply works without a prompt. That is an unsafe choice for production.
  - **What it means:** each Manage write (mute, limit, add, adopt) shows a "Run Query" prompt.
    Users click it. Or move those writes out of dashboards.
  - **Why:** with the check off, a crafted link can run a mute or a limit as whoever opens it. A
    mute can hide a real outage. See
    [why the lab turns it off](../running-the-role.md#the-dashboard-risky-command-check-is-off).
  - **Check:** on the search head, in a shell:

    ```
    splunk btool web list settings --debug | grep risky
    ```

    It must not say `false`. The setting also covers every other dashboard on the instance.
  - **Without it:** hidden outages through a bad link.
- **Control the test block.** Review the list from 2.4 each quarter. Treat any Cribl change to the
  block lookup or pipeline as a security event.
- **Open Manage links only from people you trust.**

## Summary for the project manager

| Item | Owner role | Done? |
|---|---|---|
| 1.1 Splunk version confirmed | Splunk admin | [ ] |
| 1.2 Search head layout and KV store healthy | Splunk admin | [ ] |
| 1.3 `data_health` and source indexes exist | Splunk admin | [ ] |
| 1.4 Retention checked against lookbacks | Splunk admin | [ ] |
| 1.5 Scheduler has room | Splunk admin | [ ] |
| 1.6 Licence checked | Splunk admin | [ ] |
| 2.1 Roles made | Splunk admin | [ ] |
| 2.2 `_internal` decision made | SOC lead | [ ] |
| 2.3 Searches run as the system user | Splunk admin | [ ] |
| 2.4 Test-block users named | SOC lead | [ ] |
| 3.1 UF `_internal` arrives | Splunk admin | [ ] |
| 3.2 Shutdown line arrives | Splunk admin | [ ] |
| 3.3 UF version and build map set | Splunk admin | [ ] |
| 3.4 TAs and inputs deployed | Linux and Windows owners | [ ] |
| 3.5 No root splunk CLI rule shared | Linux owners | [ ] |
| 4.1 Cribl routes deliver | Cribl admin | [ ] |
| 4.2 Cribl logs arrive | Cribl admin | [ ] |
| 4.3 Cribl audit arrives | Cribl admin | [ ] |
| 4.4 One row per worker group | Cribl admin | [ ] |
| 4.5 Test-block lookup (optional) | Cribl admin | [ ] |
| 4.6 Breakers redone | Cribl admin | [ ] |
| 5.1 Linux auditd and rules | Linux owners | [ ] |
| 5.2 Windows XML logs and events | Windows owners | [ ] |
| 5.3 Hypervisor events (optional) | Virtualization owner | [ ] |
| 5.4 Device syslog and probe | Network owner | [ ] |
| 6.1 Inventory source chosen | Inventory owner | [ ] |
| 6.2 Row format produced | Inventory owner | [ ] |
| 6.3 Sync owner named | SOC lead | [ ] |
| 7.1 Markers posted by automation | Change owner | [ ] |
| 7.2 Mute step in change process | Change owner | [ ] |
| 8 Risky-command check ON | Splunk admin | [ ] |
