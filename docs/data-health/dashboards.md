# How to read the data-health dashboards

This guide is for anyone watching the **HL Data Health** app in Splunk: the person who runs this lab, or a SOC analyst who has never read the searches behind it. It explains every panel in screen order: what it shows, where the number comes from, what good and bad look like, and what to do next. You don't need to know SPL to use it.

It is a **living document**. Any change that adds, renames or removes a panel or a filter updates this file in the same pull request. `tests/spl/run.sh` fails (check `docs-coverage`) when a panel has no entry here, or when an entry names a panel that no longer exists. Every panel's description on screen ends with "Guide: docs/data-health/dashboards.md, *dashboard* > *panel*", which points to its entry below.

The macros behind the panels are explained in [macros.md](macros.md).

## The idea in four lines

- The app keeps an **expected list**: every host, and every kind of data (sourcetype) or file (source) on a host, that should be sending data.
- Every minute it checks when each of them last sent something, and gives each a **status** (below).
- The dashboards show those statuses, from the app's own records. Only four panels read the raw events themselves, each for one host and only when you open it: on Host detail the events chart, the Splunk agent errors and the Hyper-V VM events, and on Manage the list of a host's raw sources.
- When everything on the expected list is arriving, the Overview says so in plain words; when something isn't, it says what, since when, the likely cause and what to do.

## Words used here

| Word | Meaning |
|---|---|
| Splunk agent | The Splunk Universal Forwarder: the program on a host that sends its logs to Splunk. |
| Ansible marker | A short note the Ansible role sends to Splunk whenever it stops, starts or changes a host's Splunk agent, saying what it did, who ran it and when. The app uses it to tell planned work from a real problem. |
| Normalized form (of a source) | The source name with its date, time or rotation number replaced by `*`, so `audit-2026-10-30.jsonl` and `audit-2026-10-31.jsonl` count as one source, `audit-*.jsonl`. |
| hec | HTTP Event Collector: data sent straight to Splunk over HTTPS (port 8088) instead of through an agent or syslog. |
| Limit (threshold) | How long an item may stay silent before it is late. |

## Statuses

Each expected item has one status. "Limit" means how long it may stay silent: its *threshold*. It comes from the item's profile (heartbeat 90 s; periodic twice its interval plus a minute; continuous 15 min; sporadic 24 h), from what the app has learned about it after 3 days, or from an override set on Manage. Host detail shows which.

| Status | What it means | What to do |
|---|---|---|
| OK | Data arrived within its limit. | Nothing. |
| LATE | Silent longer than its limit, but not yet twice as long. | Look at the cause. Often it recovers by itself. |
| MISSING | Silent more than twice its limit. This is what alerts (for criticality 1 and 2). | Follow the action in the Action column. |
| NEVER_SEEN | On the expected list for more than an hour and has never sent anything. | Check that the input is deployed and sending; the Action column says where. |
| MUTED | Muted on purpose on Manage, with a reason and an end time. A host mute covers everything it sends. | Nothing while muted. Unmute on Manage when the work is done. |
| PENDING | No trusted status right now: either the app itself is on hold (see the banner), or the item was added less than an hour ago and hasn't sent anything yet. No alerts fire. | If the banner says "On hold", fix what it says. Otherwise wait. |
| INFO | Tracked for reference only; it never alerts. | Nothing. |

**Host roll-up.** A host also gets an overall state from its items:

| Roll-up | What it means |
|---|---|
| DOWN | The host itself looks dead: its Splunk agent's heartbeat (or, for a network device, its probe) is missing; or, for a host without an agent, every item it should send is missing. |
| DEGRADED | The host is alive, but some of its items are late, missing or never seen. |
| OK | Everything the host should send is arriving. |
| MUTED | The host is muted. |
| PENDING | The app is on hold (see the banner). |

## Causes: what the Cause column can say

When something is late or missing, the app picks the most likely reason, checking them in this order. The Action column gives the next step, with the host name filled in.

| Cause shown (start of the text) | What it means | Action shown |
|---|---|---|
| On hold: the arrival tracker (DH Tracker fast) has not run for … (or has never run) | The background search that records arrivals hasn't run, so nothing can be judged. | Check that the scheduled search DH Tracker fast is enabled and not skipped. |
| On hold: Splunk has indexed nothing … | Splunk indexed nothing for 2 minutes; everything went quiet at once, which is Splunk's problem, not each host's. | Check that the Splunk container runs and its ports 9997 / 10514 / 20514 / 8088 are open (agents, the syslog relay and HTTP sends use them). |
| On hold: catching up after a pause (sleep or restart) at … | Splunk or the PC paused; statuses are held for 5 minutes while data catches up. | None: wait 5 min. |
| Muted until …: *reason* | Muted on Manage. | None while muted. |
| Added less than 1 h ago: waiting for its first data | Just added to the expected list; no data yet. | None yet: wait up to 1 h for its first data. |
| Test block until … (data dropped on purpose): *reason* | A test is deliberately dropping this data at ingest. | Remove the test block on Manage when the test ends. |
| Stopped with Ansible at … by … and not started again | Someone ran the role's `stop` and no `start` followed. | Start it again with the role: *ansible-playbook site.yml --tags start --limit host* (this starts the Splunk agent on that host). |
| The VM is off: Hyper-V event … | Hyper-V reports the VM was turned off, shut down or saved. | Start the VM in Hyper-V, or mute it if it is meant to be off. |
| Possible deliberate blinding: … just before the data stopped | A tamper sign (a log cleared, auditd stopped, the agent stopped, a big clock step) appeared close to when the data stopped, and not during Ansible work. | Escalate: someone may be hiding activity. |
| The relay … is DOWN: this data comes through it … | This data comes through a relay host (for example pi5) that is itself down, so its real state is unknown. | Fix the relay first. |
| The device does not answer the network probe … | The device doesn't answer the relay's regular ping. | Check the power and network of the device. |
| The device probe on the relay stopped reporting on this device | The probe service on the relay (*hl-devprobe*, which pings each device every minute) has gone quiet. | Check the device probe service (hl-devprobe) on the relay. |
| The device answers the network probe but sends no logs … | The device is up but sends no logs; its logging settings probably changed. | Check the remote syslog settings on the device. |
| The Splunk agent reports late (not yet missing) … | The Splunk agent on the host is slow to report: busy, stopping, or its network path to Splunk (port 9997, where agents deliver data) is slow. | Check the agent with the role (*--tags status* shows whether the agent runs and is connected); then check the network path from the host to Splunk. |
| The Splunk agent stopped reporting … | The host is down or cut off from Splunk, the agent crashed, or someone stopped it outside Ansible. | Ping or SSH to the host; then check the agent with the role (*--tags status*). |
| The Splunk agent works but this input has never sent anything … | The agent works, but this input has never sent anything: not enabled, wrong index or sourcetype, or no permission to read the file. | Check the input on the host: its settings (*splunk btool inputs list* on the host prints the inputs the agent really uses) and the agent errors on Host detail. |
| The Splunk agent works but sends no data at all … | Its apps or inputs were removed, it cannot forward, or a test block drops everything. | Re-deploy the agent's apps with the role (*--tags apps*) and check Manage for test blocks. |
| The Splunk agent works but this input stopped … | The file is unreadable, moved or rotated; or auditd or rsyslog stopped; or audit rules were removed. | Read the Splunk agent errors about this sourcetype on Host detail. |
| Never arrived since it was added … | A host without an agent never sent this. | Check that this input is deployed and sending. |
| Nothing at all from this host (it has no Splunk agent) … | A host without an agent sends nothing at all. | Check the host and its syslog path. |
| This stream stopped while the host still sends others … | One stream stopped; the host still sends others. | Check the program or input that sends this stream. |

## The banner: is the data current?

The banner at the top of the Overview says whether you can trust the page right now. It checks four things:

1. **Is Splunk receiving?** Has anything at all been indexed in the last 2 minutes?
2. **Is the arrival tracker running?** The background search *DH Tracker fast* records, every minute, when each item last sent data. Has it run in the last 2 minutes?
3. **Is the status search running?** The background search *DH Evaluate* turns those times into statuses every minute. Has it written statuses in the last 3 minutes?
4. **Is the app catching up after a pause?** After PC sleep or a Splunk restart, statuses are held for 5 minutes while delayed data arrives.

| Banner (start of the text) | Colour | What it means | What the page does meanwhile | What to check |
|---|---|---|---|---|
| **Up to date: data is arriving and statuses were refreshed at hh:mm** | green | All four checks pass. | Shows real statuses; alerts work. | Nothing. |
| **On hold: the arrival tracker (DH Tracker fast) last ran … ago** (or "has never run") | red | The arrival tracker has stopped, so the app can't tell whether data arrives. | Every status shows PENDING; no alerts fire; Needs attention lists nothing. | In Splunk, *Settings > Searches, reports, and alerts*: is *DH Tracker fast* enabled and scheduled? Is the scheduler skipping it (Daily state of health > Skipped searches)? |
| **On hold: Splunk has indexed nothing new for … s** (or "nothing yet") | red | Splunk itself isn't receiving data. | Same as above. | The Splunk container is running and its receiving ports (9997, 10514, 20514, 8088) are open. |
| **Out of date: the status search (DH Evaluate) last ran … ago** (or "has not run yet") | red | Arrivals are recorded, but statuses haven't been refreshed. | Shows the last statuses it has, which may be old. No new alerts fire either, because alerts come from status changes. | Is *DH Evaluate* enabled and scheduled, and not skipped? |
| **Catching up: Splunk or the PC paused and resumed at hh:mm (sleep or restart)** | amber | A pause was detected. | Statuses show PENDING for 5 minutes and no alerts fire, so a wake-up doesn't raise false alarms. | Nothing; wait 5 minutes. |

When more than one problem applies, the banner lists them all, separated by ";". Times (hh:mm) are shown in the time zone of your Splunk account (Settings > your name > Preferences), which may differ from your PC clock.

**Worked example.** *"Up to date: data is arriving and statuses were refreshed at 14:32"* means: Splunk is indexing new data; the background search that records when each stream last arrived ran within the last 2 minutes; and the search that turns those times into statuses last wrote them at 14:32, within the last 3 minutes. So every status on the page is fresh and can be trusted.

## Overview

The SOC view: is anything missing, and what to do about it. It refreshes every 60 seconds. Click any row of the three tables to open Host detail for that host.

### Filters

The filters at the top apply to every panel except the banner. "All" turns a filter off.

| Input | What it does |
|---|---|
| Site | Only items of this site (taken from the expected list). |
| Owner | Only items of this owner. |
| Index | Only items of this index. Host rows have no index, so a host's own status drops out. |
| Criticality | Only items of this criticality (1 is the most important). |
| Status | Only items with this status, or (Host DOWN / Host DEGRADED) of hosts with this roll-up. |
| Search text (words separated by *) | Only items whose name, description or cause contains every word. `*` separates words; nothing else is special, so `50%` means exactly that. |

### Is the data current?
- **What it shows:** the banner: whether the page can be trusted right now.
- **Where it comes from:** the run times of the two background searches and the time of the last indexed data.
- **How to read it:** see [the banner states](#the-banner-is-the-data-current) above. Green: trust the page. Red or amber: the statuses below are held or old; fix what it says first.

### Tamper findings (24 h)
- **What it shows:** how many signs of possible tampering were first recorded in the last 24 hours.
- **Where it comes from:** counts the tamper findings first recorded in the last 24 hours that are not explained by Ansible work, after the filters.
- **How to read it:** 0 is good. Anything else: read the Tamper findings table at the bottom, and escalate if it isn't explained.

### KPI tiles
Three rows of six tiles: one row for hosts, one for sourcetypes, one for sources. Each level is counted on its own, so a dead host with five missing inputs shows 1 missing host and 5 missing sourcetypes or sources, not 6. All counts follow the filters.

| Tile | What it counts | Good | Bad means |
|---|---|---|---|
| Hosts expected | Hosts on the expected list. | Matches your inventory. | A host was added or removed. |
| Hosts OK | Hosts whose heartbeat (or data) arrives on time. | When nothing is wrong: Hosts expected minus Hosts muted. | A gap means hosts are late, missing or waiting. |
| Hosts late | Hosts whose heartbeat is late. | 0 | A host or its path to Splunk is slow. |
| Hosts missing | Hosts that are silent more than twice their limit, or never sent anything. | 0 | A host is down or cut off: see Needs attention. |
| Hosts muted | Hosts muted on purpose. | What you expect. | A forgotten mute hides problems: check Manage. |
| Hosts waiting (PENDING) | Hosts with no trusted status yet. | 0 | The app is on hold (see the banner), or a host was just added. |
| Sourcetypes expected | Kinds of data expected per host. | — | — |
| Sourcetypes OK | Those arriving on time. | — | — |
| Sourcetypes late | Those later than their limit. | 0 | A log stopped or slowed. |
| Sourcetypes missing | Those silent more than twice their limit, or never arrived. | 0 | See Needs attention. |
| Sourcetypes muted | Those muted. | — | — |
| Sourcetypes waiting (PENDING) | Those with no trusted status yet. | 0 | As for hosts. |
| Sources expected | Individual files or inputs expected. | — | — |
| Sources OK | Those arriving on time. | — | — |
| Sources late | Those later than their limit. | 0 | One file or script stopped or slowed. |
| Sources missing | Those silent more than twice their limit, or never arrived. | 0 | See Needs attention. |
| Sources muted | Those muted. | — | — |
| Sources waiting (PENDING) | Those with no trusted status yet. | 0 | As for hosts. |

### How many hosts need attention
- **What it shows:** one line: "All expected data is arriving", "1 host needs attention", "N hosts need attention", or "On hold (see the banner above)".
- **Where it comes from:** counts the hosts that have at least one late, missing or never-seen item, after the filters.
- **How to read it:** green "All expected data is arriving" is the goal. Red: work through the table below, top row first. Amber "On hold": fix the banner's problem first; until then nothing can be listed.

### Needs attention
- **What it shows:** one row per host with something late, missing or never seen. Columns: **Host**; **State** (DOWN or DEGRADED); **Worst status**; **Bad items** (how many, and the first five); **Since** and **For** (when the oldest problem began, and how long ago); **Criticality**; **Cause**; **Action**; **Runbook**.
- **Where it comes from:** the current statuses of the expected list, grouped by host.
- **How to read it:** the worst row is on top: DOWN before DEGRADED, then the worst status, then criticality (1 first), then the oldest. Empty means nothing needs attention (the line above says so). For each row, read the **cause** (see [Causes](#causes-what-the-cause-column-can-say)) and do the **action**; open the runbook if there is one; click the row for the full picture on Host detail.

### Recently recovered (back to OK in the last 24 h)
- **What it shows:** items whose data stopped and has come back to OK in the last 24 hours. Columns: **Back to OK at**, **Host**, **Item ID**, **Down since**, **Down for**.
- **Where it comes from:** the recorded status changes: each stretch of LATE, MISSING or NEVER_SEEN that ended with a change back to OK. Muting a dead item, or switching it to INFO, is not counted as a recovery.
- **How to read it:** a short list of short outages is normal (reboots, restarts). The same item many times means it is flapping (see Daily state of health). A long outage that recovered may still need an explanation.

### Tamper findings (first seen in the last 24 h)
- **What it shows:** each sign of possible tampering first recorded in the last 24 hours. Columns: **First seen** (when the app first recorded it), **Time** (when it happened), **Host**, **What was seen** (for example "1102 security log cleared" or "SERVICE_STOP auditd"), **Events**, **Code**, **Detail**.
- **Where it comes from:** the findings of the background search *DH Tamper*, keeping the latest state of each and leaving out those that happened within 15 minutes of Ansible work (the role's own stops and changes).
- **How to read it:** empty is good. A finding means someone may have tried to switch off logging. Check whether planned work explains it (a reboot also stops services); if not, **escalate**. Click the row to see the host.

## Host detail

Everything about one host. Pick the host at the top, or arrive here by clicking a row on the Overview.

| Input | What it does |
|---|---|
| Host | The host to show. Hosts are listed with their roll-up, for example "wd2l-recv (DEGRADED)". |

### Expected data from this host
- **What it shows:** each item this host should send. Columns:
  - **Item**: the host itself (with how its liveness is judged: heartbeat, probe or data), *index / sourcetype*, or *index / sourcetype / source*.
  - **Status**.
  - **Silent for / limit**: "400 s / 300 s" means silent for 400 s against a limit of 300 s; "never arrived" if nothing came yet.
  - **Profile**.
  - **Limit from**: where the limit comes from: *override* (set on Manage), *max_gap_secs* (a fixed limit written on the item's expected-list row), *learned* (from at least 3 days of history), *default* (the profile's default; "(learning)" while it has fewer than 3 days of history), *invalid_profile* (the row's profile is misspelt or unknown, so the continuous default is used), or *none* (an INFO item that never alerts). **About the limit** says the same in a sentence.
  - **Mute or test block**: "muted until … (reason)" or "test block until hh:mm".
  - **Since**, **Cause**, **Action**.
  - **Last hour volume**: last hour against the usual count ("x0.1 of median FLAGGED" means a tenth of usual, flagged as a drop), or why it isn't judged.
  - **Clock wrong**: 1 when the data's own timestamps are far from when it arrived.
  - **Item ID**: the item's full identifier.
- **Where it comes from:** the current statuses of the expected list for this host, plus last hour's volume.
- **How to read it:** the host's own row is first, then its sourcetypes and sources, worst first. All OK is good. For each bad row, follow the action. A status of OK with "FLAGGED" volume means data still arrives but far less than usual: worth a look.

### Events in the last 24 h by sourcetype
- **What it shows:** a stacked column chart of how many events this host sent, per sourcetype, in 10-minute steps over the last 24 hours.
- **Where it comes from:** counts the indexed events of this host (one of the four panels that read raw events; see the start of this guide).
- **How to read it:** steady bars are normal. A gap shows when a stream stopped; a sudden drop or spike is worth comparing with the status changes below.

### Forwarder (the Splunk agent on the host)
- **What it shows:** one fact per row: Agent version (with "(expected 10.6.1.1)" when it differs), Operating system, Agent type, Agent ID (guid), Last heartbeat, Last connection to Splunk, Last Ansible marker (action, when, by whom, run id), Last Hyper-V event and Last device probe. A host without one shows a single row: "No forwarder facts: this host has no Splunk agent or no Splunk agent has connected yet" (a network device, a syslog-only host, or an agent that has never connected).
- **Where it comes from:** what the arrival tracker last recorded for this host.
- **How to read it:** a heartbeat a few seconds ago is good. A heartbeat minutes old with the host DOWN means the agent or host stopped; the last Ansible marker or Hyper-V event often explains why. A version flag means the agent needs the role's install.

### Latest Splunk agent errors and warnings (24 h)
- **What it shows:** the 25 latest error and warning lines that this host's Splunk agent wrote about itself. Columns: **Time**, **Level**, **Agent component** (the part of the agent that complained, for example the file reader), **Message**.
- **Where it comes from:** the agent's own log as received by Splunk, for this host only, last 24 hours.
- **How to read it:** empty is good. Lines about file permissions, a missing file, or a blocked output explain a missing input; read them before changing anything.

### Tamper findings on this host
- **What it shows:** every tamper finding on this host still held by the app (30 days), newest first, leaving out those explained by Ansible work. Columns: **Time**, **What was seen**, **Events**, **Code**, **Detail**, **Finding ID**.
- **Where it comes from:** the findings of *DH Tamper* for this host.
- **How to read it:** empty is good. See the Overview's Tamper findings for what to do.

### Status changes (7 d)
- **What it shows:** the latest 200 status changes of this host's items in the last 7 days: **Time**, **Item ID**, **From status**, **Status** (the new one) and the **Cause** at the time.
- **Where it comes from:** the status changes the app records every minute.
- **How to read it:** use it to see when a problem started, and whether it keeps coming back.

### Hyper-V VM events (7 d)
- **What it shows:** this VM's lifecycle events according to Hyper-V on the PC: **Time**, **Host**, **VM**, **Event ID** and its **Meaning**: started (18500), turned off (18502), shut down by the host (18504), shutdown initiated (18506), shut down by the guest OS (18508), saved (18510), reset by the guest (18514), failed to restore (12050), or other.
- **Where it comes from:** the Hyper-V Worker-Admin log of the PC, for this VM only, last 7 days.
- **How to read it:** empty for a physical host or a device. A "turned off" or "shut down" just before the host went DOWN explains it: start the VM.

### Runbooks (click to open)
- **What it shows:** the how-to pages linked to this host's expected items. Columns: **Runbook**, **Items** (how many use it).
- **Where it comes from:** the runbook column of the expected list.
- **How to read it:** click a row to open the page in a new tab. Empty means no runbook was set.

## Manage

Where the expected list, mutes, thresholds and test blocks are changed. It never refreshes by itself, and nothing is written until you confirm. Each change takes three steps:

1. Fill in one form (1 to 4) and the **Reason**, then press **Submit**. The *preview* panel shows the change, before and after, or why it is refused.
2. In that form's *confirm* list choose **Apply**, then press **Submit** again. The *result* panel says "applied: …", and the change is recorded in the admin log.
3. Pressing Submit again, or reloading the page, does not repeat the change: the confirmation fits only the state you previewed. You then see "nothing applied: …", which is expected.

Muting is open to analysts. Adding or adopting expected rows, and test blocks, need the **dh_admin** role.

### How Manage works
- **What it shows:** the short instructions at the top of the page: the three steps above, who may do what, and what a test block does.
- **Where it comes from:** fixed text.
- **How to read it:** read it once; this guide has the details.

### Inputs

| Input | What to enter |
|---|---|
| Reason (required for every change) | Why you are making the change. It goes to the admin log and, for a mute, is shown as the mute reason. |
| Ticket (- for none) | A ticket or change number, if there is one. |
| 1 Override: host | The host whose item you want to mute or override. Press Submit to load its items. |
| 1 Override: item (the host's own row mutes everything it sends) | The item. Choosing the host's own row mutes everything it sends. |
| 1 Override: action | Mute, Unmute, Set threshold or Clear threshold. |
| 1 Override: mute for | How long a mute lasts: 1 hour to 30 days (the most allowed). |
| 1 Override: threshold in seconds | For Set threshold: how long the item may stay silent (at least 60). |
| 1 Override: confirm | Choose Apply after checking the preview. |
| 2 Add row: level | host, sourcetype or source. |
| 2 Add row: index | Where the data goes (only indexes the app watches). Use "-" for a host row. |
| 2 Add row: host | The host name (short or full; it is shortened). |
| 2 Add row: sourcetype | For sourcetype and source rows. |
| 2 Add row: source | For source rows: the file or input name. |
| 2 Add row: collection | How the data arrives: uf (Splunk agent), syslog, or hec. |
| 2 Add row: via (relay) | For data that comes through a relay host, the relay (for example pi5). |
| 2 Add row: profile | heartbeat, periodic, continuous, sporadic or info (see [Statuses](#statuses)). |
| 2 Add row: interval in seconds (periodic only) | How often a periodic input runs. |
| 2 Add row: criticality | 1 (highest) to 4. Criticality 1 and 2 raise the missing-data alert. |
| 2 Add row: owner | Who looks after it. |
| 2 Add row: site | Where it is. |
| 2 Add row: runbook | A link to its how-to page. |
| 2 Add row: description | A short description. |
| 2 Add row: confirm | Choose Apply after checking the preview. |
| 3 Adopt: unregistered entity | An item that sends data but isn't expected (from the Unregistered table). |
| 3 Adopt: criticality | Its criticality. |
| 3 Adopt: confirm | Choose Apply after checking the preview. |
| Thresholds: search text (words separated by *) | Narrows the Thresholds table. |
| 4 Test block (admin): action | Add or Remove a block. |
| 4 Test block: host | The host to block. Press Submit to load its sources. |
| 4 Test block: level | The whole host, one sourcetype, or one exact source. |
| 4 Test block: sourcetype or raw source | The sourcetype, or the exact raw source name (listed with its normalized form). |
| 4 Test block: for | How long: 5 minutes to 24 hours. |
| 4 Test block: confirm | Choose Apply after checking the preview. |

### 1 Override (mute or threshold): preview
- **What it shows:** the override you are about to make. Columns: **Action** (override_mute, override_unmute, override_threshold or override_clear), **Item ID**, **Before** and **After** (mute end, threshold, reason), and **Check**: "ok: choose Apply …" or why it is refused (for example "a mute needs an expiry of at most 30 days").
- **Where it comes from:** your inputs checked against the current overrides. Nothing is written.
- **How to read it:** if the check says ok, choose Apply in "1 Override: confirm" and Submit.

### 1 Override (mute or threshold): result
- **What it shows:** one row: **Result** ("applied: …" once the change is written, or "nothing applied: …" when the confirmation no longer fits: a repeat, a reload, or someone changed it meanwhile), with **Time**, **Who**, **Action**, **Item ID**, **Detail**, **Reason** and **Ticket** of an applied change.
- **Where it comes from:** the write itself.
- **How to read it:** "nothing applied" after a reload is expected. To make another change, preview again.

### Current mutes and threshold overrides
- **What it shows:** every override in force. Columns: **Item ID**, **Muted until** ("-" if only a threshold is set), **Reason**, **Ticket**, **Threshold override (s)**, **Set by**, **Set at**.
- **Where it comes from:** the overrides table.
- **How to read it:** check for mutes nobody needs any more; they hide problems. Expired mutes disappear within a minute.

### 2 Add an expected row: preview
- **What it shows:** the expected-list row you are about to add or change. Columns: **Action** (expected_add), **Item ID**, **Before**, **After** and **Check** (for example "this entity is managed by ansible: change the inventory instead").
- **Where it comes from:** your inputs checked against the expected list. Nothing is written.
- **How to read it:** rows added by Ansible are changed through the inventory, not here. If the check says ok, confirm.

### 2 Add an expected row: result
- **What it shows:** "applied: …" or "nothing applied: …", as for overrides.
- **Where it comes from:** the write itself.
- **How to read it:** a new row starts as PENDING and becomes NEVER_SEEN if nothing arrives within an hour.

### Unregistered: seen in the last 7 d but not expected
- **What it shows:** hosts and sourcetypes that sent data in the last 7 days but are not on the expected list. Columns: **Item ID**, **Level**, **Index**, **Host**, **Sourcetype**, **Sources** (how many), **Last seen**, **First seen**, **Suggested profile** (from what the app learned, once it has 3 days), **Days covered**.
- **Where it comes from:** the arrival records compared with the expected list.
- **How to read it:** each row is either something new that should be watched (adopt it in form 3) or noise to ignore. Unregistered data is never alerted on.

### 3 Adopt: preview
- **What it shows:** the expected row that adopting the chosen item would add (collection and profile filled in from what the app knows). Columns: **Action** (expected_adopt), **Item ID**, **Before**, **After**, **Check**.
- **Where it comes from:** the unregistered item, its baseline and its forwarder facts. Nothing is written.
- **How to read it:** if the check says ok, confirm.

### 3 Adopt: result
- **What it shows:** "applied: …" or "nothing applied: …".
- **Where it comes from:** the write itself.
- **How to read it:** the item leaves the Unregistered table and gets a status within a minute.

### Thresholds: learned against configured
- **What it shows:** for each item: **Item ID**; **Profile**; **Managed by** (ansible or ui); **Configured limit (s)** (a fixed limit written on its expected-list row, if any); **Default limit (s)** of its profile; **Learned before bounds (s)** and **Learned limit (s)** (what the app learned, before and after it is kept within the profile's lowest and highest allowed values); **Days covered** and **Days skipped** (days with too little Splunk uptime to learn from); **Suggested profile**; and the **Limit applied (s)** with where it comes from (**Applied from**) and **About the applied limit**.
- **Where it comes from:** the current statuses, the learned baselines and the expected list.
- **How to read it:** "learning" with fewer than 3 days means the default is used for now. A learned limit far from the default can be a reason to change the profile, or to set a threshold override in form 1.

### 4 Test block: raw sources of the host (24 h)
- **What it shows:** the exact source names the chosen host sent to the linux, windows and network indexes in the last 24 hours. Columns: **Index**, **Sourcetype**, **Source (raw name)**, **Normalized source** (the name with dates and rotation numbers as `*`), **Events**, **Last seen**.
- **Where it comes from:** the indexed data of this host only.
- **How to read it:** a source-level block must use one of these exact raw names; a rotated or dated file name won't match later files (block its sourcetype instead).

### Current test blocks
- **What it shows:** every block in the test-block table. Columns: **Block key** (host, host|sourcetype, or host|sourcetype|exact source), **Until**, **Reason**, **Set by**, and **State** ("test block until hh:mm", or "expired" until it is cleaned up within about 2 minutes).
- **Where it comes from:** the test-block table that Splunk reads at ingest.
- **How to read it:** blocked data is **thrown away** before indexing, so a block is a real outage, on purpose. The affected items show their real status labelled "test block until hh:mm". Remove blocks as soon as a test ends; in production a block control is itself a way to blind monitoring.

### 4 Test block: preview
- **What it shows:** the block you are about to add or remove. Columns: **Action** (block_add or block_remove), **Block key**, **Normalized source** (for reference only), **Before**, **After**, **Check**.
- **Where it comes from:** your inputs checked against the current block table. Nothing is written.
- **How to read it:** if the check says ok, confirm.

### 4 Test block: result
- **What it shows:** "applied: …" or "nothing applied: …".
- **Where it comes from:** the rewrite of the block table.
- **How to read it:** Splunk picks up the change within about a minute.

### Admin log (every change made here)
- **What it shows:** the last 1000 changes. Columns: **Time**, **Who**, **Action** (for example override_mute or block_add), **Item ID** (for a test block, its key), **Detail** (before -> after), **Reason**, **Ticket**.
- **Where it comes from:** the admin log, written by every applied change.
- **How to read it:** use it to answer "who muted this, and why?". It is also copied to the `data_health` index every 5 minutes and kept 90 days in the table.

## Daily state of health

The engineering view: the report made every day at 07:00, plus the live unregistered list. It doesn't refresh; reopen it the next day.

### Report time
- **What it shows:** when the report shown was made.
- **Where it comes from:** the latest daily report.
- **How to read it:** it should be today at 07:00 (or the morning after the PC was off). "no report yet" means the report search hasn't run.

### Outages (24 h)
- **What it shows:** how many outages (stretches of late, missing or never-seen data) ended in the last 24 hours or are still open.
- **Where it comes from:** the recorded status changes.
- **How to read it:** a few is normal in a lab. Many means something keeps failing: see the Outages table.

### Outages still open
- **What it shows:** how many of those have not recovered yet.
- **Where it comes from:** outages whose item is still bad now, counted per item.
- **How to read it:** these items should appear on the Overview's Needs attention. The number can be larger than the number of hosts there, because one host can have several open items.

### Mean time to recover (24 h)
- **What it shows:** how long the outages that ended lasted on average.
- **Where it comes from:** the start and end of each ended outage.
- **How to read it:** lower is better; a jump means problems took longer to notice or fix.

### Licence used yesterday (% of the daily quota)
- **What it shows:** yesterday's indexed data as a share of the licence's daily limit.
- **Where it comes from:** Splunk's licence usage log and licence settings.
- **How to read it:** below 100 % is fine. Near or above it, Splunk warns and may eventually block searching: reduce what is collected.

### Days until the licence expires
- **What it shows:** days until the active licence ends.
- **Where it comes from:** Splunk's licence settings.
- **How to read it:** plan a new licence well before 0; after expiry, alerts and roles stop working.

### Outages in the last 24 h
- **What it shows:** each outage, longest first. Columns: **Item ID**, **Started**, **Ended** ("still open" if not yet), **For** (how long it lasted).
- **Where it comes from:** the recorded status changes.
- **How to read it:** long outages deserve a reason; repeated short ones point to flapping.

### Flapping (3 or more status changes in 24 h)
- **What it shows:** items that changed status 3 or more times in a day. Columns: **Item ID**, **Status changes (24 h)**.
- **Where it comes from:** the recorded status changes.
- **How to read it:** an item that keeps stopping and starting usually has a limit that is too tight (raise it on Manage) or an unstable sender.

### Never arrived, or a bad profile
- **What it shows:** expected items that have never sent anything, and expected rows whose profile the app doesn't know (treated as continuous). Columns: **Kind** ("never arrived" or "unknown profile"), **Item ID**, **Detail** ("expected since …", or the note about the profile).
- **Where it comes from:** the current statuses.
- **How to read it:** fix the input, or remove the row; fix misspelt profiles in the inventory.

### Forwarders: wrong version or disconnected
- **What it shows:** Splunk agents not on the expected version, and agents that haven't called in for 15 minutes. Columns: **Kind** ("wrong version" or "disconnected"), **Host**, **Version**, **Last seen**.
- **Where it comes from:** the forwarder facts.
- **How to read it:** re-run the role's install for a wrong version; check the host for a disconnected agent.

### Unregistered: seen in the last 7 d but not expected
- **What it shows:** the same live list and columns as on Manage: data that arrives but isn't on the expected list.
- **Where it comes from:** the arrival records compared with the expected list.
- **How to read it:** adopt what should be watched (Manage, form 3); ignore the rest.

### Slow arrival (lag p95 of 60 s or more)
- **What it shows:** sourcetypes whose data usually arrives a minute or more after it was written, on the latest day. Columns: **Item ID**, **Delay p95 (s)** (95 % of events arrived within this many seconds), **Day**.
- **Where it comes from:** the daily records of arrival delay.
- **How to read it:** a large lag can make data look late. It usually means a spool, a slow path, or a wrong clock on the sender.

### Volume drops (24 h)
- **What it shows:** items that had hours with far fewer events than usual (below 20 % of their usual count for that hour). Columns: **Item ID**, **Hours flagged**, **Lowest share of usual** (0.05 means 5 % of the usual count).
- **Where it comes from:** the hourly volume checks.
- **How to read it:** data still arrives, but much less of it: an input may be partly broken, or the source got quieter.

### Skipped searches (24 h)
- **What it shows:** this app's background searches that Splunk skipped. Columns: **Search**, **Times skipped**; a row "total" sums them.
- **Where it comes from:** Splunk's scheduler log.
- **How to read it:** the total should be 0. Skipped tracker or status searches make the banner go red.

### Active and expiring mutes
- **What it shows:** mutes in force, and those ending within 24 hours. Columns: **Kind** ("active" or "ends within 24 h"; a mute ending soon is listed under both), **Item ID**, **Until**, **Reason**, **Ticket**, **Set by**.
- **Where it comes from:** the overrides table.
- **How to read it:** check that each mute is still needed; an expiring mute will start alerting again if the problem is still there.
