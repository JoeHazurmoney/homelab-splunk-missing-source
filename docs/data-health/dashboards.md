# How to read the data-health dashboards

This guide is for anyone watching the **HL Data Health** app in Splunk: the person who runs this lab, or a SOC analyst who has never read the searches behind it. It explains every panel in screen order: what it shows, where the number comes from, what good and bad look like, and what to do next. You don't need to know SPL to use it.

It is a **living document**. The Manage view is generated: edit `tools/gen_dh_manage.js` and run `node tools/gen_dh_manage.js` instead of editing `dh_manage.xml` (`tests/spl/run.sh`, check `manage-generated`, fails when the two differ). Any change that adds, renames or removes a panel or a filter updates this file in the same pull request. `tests/spl/run.sh` fails (check `docs-coverage`) when a panel has no entry here, or when an entry names a panel that no longer exists. Every panel's description on screen ends with "Guide (project repo): docs/data-health/dashboards.md > *dashboard* > *panel*": this file, in the project's repository, and the entry below.

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
| On hold: Splunk has indexed nothing … | Splunk indexed nothing for 2 minutes; everything went quiet at once, which is Splunk's problem, not each host's. | Check that the Splunk container runs and receives: HEC on 8088 (wd2l and the Ansible markers) and port 9997 on the *hl-net* Docker network, where Cribl delivers everything collected. |
| On hold: catching up after a pause (sleep or restart) at … | Splunk or the PC paused; statuses are held for 5 minutes while data catches up. | None: wait 5 min. |
| Muted until …: *reason* | Muted on Manage. | None while muted. |
| Added less than 1 h ago: waiting for its first data | Just added to the expected list; no data yet. | None yet: wait up to 1 h for its first data. |
| Test block until … (data dropped on purpose): *reason* | A test is deliberately dropping this data in Cribl. | Remove the test block when the test ends (Manage, Test blocks tab, gives the command). |
| Stopped with Ansible at … by … and not started again | Someone ran the role's `stop` and no `start` followed. | Start it again with the role: *ansible-playbook site.yml --tags start --limit host* (this starts the Splunk agent on that host). |
| The VM is off: Hyper-V event … | Hyper-V reports the VM was turned off, shut down or saved. | Start the VM in Hyper-V, or mute it if it is meant to be off. |
| Possible deliberate blinding: … just before the data stopped | A tamper sign (a log cleared, auditd stopped, the agent stopped, a big clock step) appeared close to when the data stopped, and not during Ansible work. | Escalate: someone may be hiding activity. |
| Cribl DOWN: the real state is unknown … | Everything collected (the agents and the UDM) passes through Cribl Stream, and Cribl itself has stopped reporting. So nobody can tell whether this data stopped or just can't get through. HEC data (wd2l, the markers) doesn't use Cribl, so Splunk itself still looks fine. | Check the *cribl* container on HOMEPC (`docker ps --filter name=cribl`), then run the role's *--tags verify --limit homepc*. |
| Cribl DOWN: nothing from Cribl itself … | The row for Cribl: its own logs (each worker logs every minute) stopped arriving. | The same as above. |
| The relay … is DOWN: this data comes through it … | This data comes through another relay host that is itself down, so its real state is unknown. | Fix the relay first. |
| The device does not answer the network probe … | The device doesn't answer the regular ping from *hl-devprobe* on pi5. | Check the power and network of the device. |
| The device probe (hl-devprobe on pi5) stopped reporting on this device | The probe service on pi5 (*hl-devprobe*, which pings each device every minute into a file pi5's agent forwards) has gone quiet. | Check *hl-devprobe* on pi5 (`systemctl status hl-devprobe.timer`), or rerun the role's *--tags probe --limit pi5*. |
| The device answers the network probe but sends no logs … | The device is up but sends no logs; its logging settings probably changed. | Check the remote syslog settings on the device. |
| The Splunk agent reports late (not yet missing) … | The Splunk agent on the host is slow to report: busy, stopping, or its network path to Cribl (port 9997 on HOMEPC, where agents deliver data) is slow. | Check the agent with the role (*--tags status* shows whether the agent runs and is connected); then check the network path from the host to Cribl. |
| The Splunk agent stopped reporting … | The host is down or cut off from Cribl, the agent crashed, or someone stopped it outside Ansible. | Ping or SSH to the host; then check the agent with the role (*--tags status*). |
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
| **On hold: Splunk has indexed nothing new for … s** (or "nothing yet") | red | Splunk itself isn't receiving data. | Same as above. | The Splunk container is running and receives on HEC 8088 and on port 9997 from Cribl (*hl-net*). |
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
  - **Limit from**: where the limit comes from: *Override (set on Manage)*, *Fixed limit on its expected row* (a limit written on the item's expected-list row), *Learned from its history* (at least 3 days), *Profile default* ("(learning)" while it has fewer than 3 days of history), *Profile default (the row's profile is unknown)* (the profile is misspelt or unknown, so the continuous default is used), or *None (INFO: never alerts)*. **About the limit** says the same in a sentence.
  - **Mute or test block**: "muted until … (reason)" or "test block until hh:mm", each with its time zone (for example "test block until 16:46 MDT").
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
- **What it shows:** one fact per row: Agent version (with "(expected 10.6.1.1)" when it differs), Operating system, Agent type, Last heartbeat, Last connection to Cribl, Last Ansible marker (action, when, by whom, run id), Last Hyper-V event and Last device probe. A host without one shows a single row: "No forwarder facts: this host has no Splunk agent or no Splunk agent has connected yet" (a network device, a syslog-only host, or an agent that has never connected).
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

Where you change what the app expects and how it alerts: mute data during planned work, change how long an item may stay silent, keep the expected list up to date, run test blocks, and see who changed what. The page has four tabs: **Mute & thresholds**, **Expected list**, **Test blocks (admin)** and **Admin log**. Each tab holds its own forms, and each form has its preview and its result right below it.

### Before you start

- **Who may do what.** Anyone who can open the app may mute, unmute and set or clear a limit. Adding or adopting expected rows and test blocks need the **dh_admin** role; without it the preview says "Needs the dh_admin role" and nothing can be applied.
- **Nothing is written until you choose Apply.** A form shows a preview of the change as you fill it in. The change is written only when you open that form's **Confirm (writes the change)** list and choose the line that starts with **Apply**. There is no other button: choosing that line writes the change at once and records it on the Admin log tab.
- **Each form stands alone.** Every form that writes has its own Reason, Ticket and Confirm, and a choice under one form's Confirm writes only that form's change. (The test-block form has no Confirm: it writes nothing.)
- **Boxes apply as you go.** There is no Submit button on Manage. A list applies as soon as you pick from it; a text box applies when you press Enter or click outside it. Lists that depend on a host (the items of a host, a host's sourcetypes and raw sources) fill as soon as you pick the host.
- **Until a form is filled in**, its preview area shows what to fill in instead of a table. A required box (Reason, Host name) must not be empty. Optional boxes hold `-`, which means "none"; leave it there unless you have a value.
- **The Confirm list** appears once the form is filled in. It offers the Apply line only when the preview's **Check** column says "OK: …"; otherwise it says "No results", and the Check column says what to fix.
- **Changing the form clears the confirmation.** If you change any box of a form after choosing Apply, its Confirm choice is cleared and its result disappears; the change you already applied stays applied.
- **A confirmation fits only once.** It fits only the state you previewed, and never again after its change was applied, even if that change has since expired and been cleaned up. After a reload, or when you come back to a tab, the result may say "Nothing written: this confirmation fits only the state you previewed, …". That is expected: the change was applied the first time. Check the tables or the Admin log tab.
- **The tables don't refresh by themselves.** Manage never refreshes on its own. After applying a change, reload the page to see it in the tables of the tab.
- **Times** are shown in the time zone of your Splunk account (Settings > your name > Preferences) and always end with the zone, for example `2026-10-31 17:46 MDT`. That may differ from your PC clock.
- **If "This visualization has a potential security risk" appears after Apply** (the result stays empty with a red icon, and nothing is written until you click the icon and then **Run Query**): Dashboard Studio's risky-command check is still on. Apply writes with `outputlookup`, which is on Studio's risky list, so the server app hl_server_base turns that check off (`enable_risky_command_check_dashboard = false` in its `default/web.conf`). If the prompt appears, that setting is not in effect: check `splunk btool web list settings --debug | grep risky` (it should show `false` from `apps/hl_server_base/default/web.conf`) and that hl_server_base is deployed (the role's `server` tag, which restarts splunkd). If btool already shows `false`, splunkd hasn't restarted since the deploy or the page is stale: restart splunkd, then reload the page.

### Item IDs

Every expected item has an **Item ID** of five parts, `level|index|host|sourcetype|source`, with `*` for the parts its level doesn't use:

| Item ID | Shown on Manage as | What it is |
|---|---|---|
| `host\|*\|pi5\|*\|*` | pi5: whole host | The host itself. Muting it mutes everything it sends. |
| `sourcetype\|enclave1\|pi5\|syslog\|*` | pi5 › syslog (enclave1) | One kind of data (sourcetype) from that host, in that index. |
| `source\|linux\|h8\|app\|/var/log/app-*.log` | h8 › app › /var/log/app-*.log (linux) | One file or input (source) of a sourcetype. Dates and rotation numbers in file names are replaced by `*` (the normalized form). |

Manage shows items in words and keeps the Item ID in the last column of its tables, for searching and for the admin log. A **test block** has a shorter key, `host|sourcetype|raw source` with `*` for "all" (`pi5|*|*` is the whole host), shown as "pi5: whole host", "pi5 › syslog" or "pi5 › linux_secure › /var/log/secure.1 (exact source)".

### Mute & thresholds tab

Mute an item during planned work, so it does not alert, or change its **limit**: how long it may stay silent before it counts as late.

#### Recipe: Mute a host for maintenance

1. Open **Manage** and stay on the **Mute & thresholds** tab.
2. **Host**: choose the host, for example `pi5`.
3. **Item**: choose the line that ends in **whole host**, for example "pi5: whole host (OK)". This mutes everything the host sends.
4. **Action**: leave **Mute**. **Mute for**: choose how long, from 1 hour to 30 days.
5. **Reason (required)**: type why, for example "patching, see CHG-123", and press Enter. **Ticket**: replace `-` with the change number if there is one.
6. Read the preview, **Mute or limit: preview**. It shows **Change** "Mute", the item, **Now** ("Not muted; no limit override"), **After the change** ("Muted until 2026-10-31 21:46 MDT (patching); …") and **Check** "OK: choose Apply under Confirm to write this change".
7. Open **Confirm (writes the change)** and choose the line "Apply: mute pi5: whole host for 4 hours". The change is written at once: **Mute or limit: result** says "Done: Mute pi5: whole host".
8. Reload the page: the mute is listed under **Current mutes and limit overrides**. Within a minute the Overview shows the host and its items as MUTED.

To end a mute early, do the same with **Action** **Unmute** (the Mute for list is then ignored). A mute also ends by itself at its end time.

#### Recipe: Silence one noisy sourcetype

Follow the recipe above, but at step 3 choose the sourcetype's line instead of the whole host, for example "pi5 › syslog (enclave1) (LATE)". Only that sourcetype is muted; the host and its other data keep alerting.

#### Recipe: Change how long an item may stay silent

1. In **Thresholds: how long each item may stay silent**, find the item (type a word of its name in **Search the thresholds (words separated by *)** and press Enter). **Limit applied (s)** is its limit now and **Applied from** says where it comes from.
2. **Host** and **Item**: choose the item.
3. **Action**: **Set limit**. **New limit in seconds (Set limit only)**: replace `-` with the new limit, for example `1800` for 30 minutes (at least 60), and press Enter.
4. Write a **Reason** and press Enter. Check the preview: **After the change** shows "limit override 30 minutes (1800 s)".
5. **Confirm (writes the change)**: choose "Apply: set the limit of … to 30 minutes (1800 s)". The result says "Done: Set limit …".
6. To go back to the app's own limit later, do the same with **Action** **Clear limit**.

If the item is muted when you set or clear its limit, the mute and its reason stay as they are.

#### Inputs

| Input | What to enter |
|---|---|
| Host | The host whose item you want to change. Its items fill the next list at once. |
| Item | The item: the host's own row ("whole host", which covers everything it sends), or one of its sourcetypes or sources, with its status in brackets. |
| Action | Mute, Unmute, Set limit or Clear limit. |
| Mute for | How long a mute lasts: 1 hour to 30 days (the most allowed). Used by Mute only. |
| New limit in seconds (Set limit only) | For Set limit: how long the item may stay silent, in seconds (at least 60). Keep `-` for the other actions. |
| Reason (required) | Why you make the change. It goes to the admin log and, for a mute, is shown as the mute reason. |
| Ticket (optional, - for none) | A ticket or change number, or `-`. |
| Confirm (writes the change) | Choose the Apply line to write the change shown in the preview. |
| Search the thresholds (words separated by *) | Narrows the Thresholds table to items whose name, description or cause contains every word. `*` shows all. |

#### Mute or limit: preview
- **What it shows:** the change you are about to make. Columns: **Change** (Mute, Unmute, Set limit or Clear limit), **Item**, **Now**, **After the change** (mute end and reason; limit override), and **Check**: "OK: choose Apply under Confirm …", or what to fix (for example "Write a reason", "A mute lasts at most 30 days", "This item is not muted: nothing to unmute").
- **Where it comes from:** your form checked against the current mutes and overrides. Nothing is written.
- **How to read it:** when Check says OK, choose Apply under Confirm. Until the form is filled in, this area shows what to fill in.

#### Mute or limit: result
- **What it shows:** after you choose Apply, one row: **Result** ("Done: Mute pi5: whole host", or "Nothing written: …" when the confirmation no longer fits), with the **Time**, **Who**, **Change**, **Item**, **Detail** (before → after), **Reason**, **Ticket** and **Item ID** of the change.
- **Where it comes from:** the write itself, which also adds the admin-log row.
- **How to read it:** "Done" means it is written. "Nothing written" after a reload or a return to the tab is expected: the change was applied the first time. To make another change, change the form and choose Apply again.

#### Current mutes and limit overrides
- **What it shows:** every mute and limit override in force. Columns: **Item**, **Muted until** ("-" if only a limit is set), **Reason**, **Ticket**, **Limit override** (for example "20 minutes (1200 s)"), **Set by**, **Set at**, **Item ID**.
- **Where it comes from:** the overrides table (`dh_overrides`).
- **How to read it:** look for mutes nobody needs any more: they hide problems. Expired mutes disappear within a minute. Reload the page after a change to see it here.

#### Thresholds: how long each item may stay silent
- **What it shows:** one row per expected item, with its limit and where it comes from. Columns:

  | Column | Meaning |
  |---|---|
  | Item | The item in words. |
  | Profile | heartbeat, periodic, continuous, sporadic or info (see [Statuses](#statuses)). |
  | Limit applied (s) | The limit in force now. |
  | Applied from | Where it comes from: Override (set on Manage), Fixed limit on its expected row, Learned from its history, Profile default, Profile default (the row's profile is unknown), or None (INFO: never alerts). |
  | About the applied limit | The same in a sentence. |
  | Learned limit (s) | What the app learned from at least 3 days of history, kept within the profile's lowest and highest allowed values. |
  | Learned before bounds (s) | The learned value before it was kept within those values. |
  | Default limit (s) | The profile's default. |
  | Configured limit (s) | A fixed limit written on the item's expected row, if any. |
  | Days covered, Days skipped | Days of history learned from (the last 14 at most: the indexes keep 14 days), and days skipped because Splunk was up too little to learn from them. |
  | Suggested profile | The profile the app would choose from what it saw. |
  | Managed by | ansible (from the inventory) or ui (added on Manage). |
  | Item ID | The item's ID. |

- **Where it comes from:** the current statuses, the learned baselines and the expected list.
- **How to read it:** "Profile default" with fewer than 3 days covered means the app is still learning. A learned limit far from the default can be a reason to change the profile, or to set a limit (recipe above).

### Expected list tab

Tell the app about data it should expect, so it alerts when that data stops. Rows that Ansible manages are changed in the Ansible inventory, not here. This tab needs the **dh_admin** role.

#### Recipe: Add an expected row

1. Open **Manage**, tab **Expected list**. Use the first form, **Add an expected row**.
2. **Level**: Host (the host itself), Sourcetype (one kind of data) or Source (one file or input).
3. **Index**: the index the data goes to (only the indexes the app watches are listed); for a host row choose "None (host row)".
4. **Host name**: type the host, for example `pi5`, and press Enter. A domain (`.mshome.net`) is cut off.
5. **Sourcetype (not for a host row)** and, for a source row, **Source (source rows only)**: replace `-` with the name.
6. **Collection (how it arrives)**: uf (Splunk agent), syslog or hec. For data that comes through a relay, put the relay in **Via relay**.
7. **Profile**: how the data arrives (see [Statuses](#statuses)); for **periodic**, also fill in **Interval in seconds (periodic only)**. **Criticality**: 1 and 2 alert when the data goes missing; 3 and 4 don't.
8. **Owner**, **Site**, **Runbook link** and **Description** are optional (keep `-`). Write a **Reason** and press Enter.
9. Check **Add an expected row: preview**: **Now** "Not on the expected list" (or how the row is now, for a change), **After the change**, and **Check** "OK: …".
10. **Confirm (writes the change)**: choose "Apply: add pi5 › syslog (enclave1) to the expected list (profile continuous, criticality 2)". **Add an expected row: result** says "Done: Add expected row …".
11. The new item starts as PENDING; it becomes OK when data arrives, or NEVER_SEEN if nothing arrives within an hour.

Running the form again for an item you added here updates its row (the preview says "Update expected row"); its "expected since" time is kept.

#### Recipe: Adopt something unregistered

1. In **Unregistered: seen in the last 7 d but not expected**, find the item that should be watched.
2. In the second form, **Adopt an unregistered item**: **Unregistered item**: choose it ("pi5 › cron (linux), last seen …").
3. **Criticality**: choose it. Write a **Reason** and press Enter.
4. Check **Adopt: preview**: the collection and profile the app suggests are in **After the change**.
5. **Confirm (writes the change)**: choose "Apply: adopt …". **Adopt: result** says "Done: Adopt …". After a reload, the item has left the Unregistered table; it gets a status within a minute.

#### Inputs

| Input | What to enter |
|---|---|
| Level | Host, Sourcetype or Source. |
| Index | Where the data goes; only the indexes the app watches are listed. "None (host row)" for a host row. |
| Host name | The host name, short or full (it is shortened). Required. |
| Sourcetype (not for a host row) | For sourcetype and source rows. |
| Source (source rows only) | For source rows: the file or input name. |
| Collection (how it arrives) | uf (Splunk agent), syslog, or hec (HTTP Event Collector). |
| Via relay (optional, - for none) | For data that comes through a relay host, the relay (for example pi5). |
| Profile | heartbeat, periodic, continuous, sporadic or info; each label gives its default limit. |
| Interval in seconds (periodic only) | How often a periodic input runs. |
| Criticality | 1 (highest) to 4. Criticality 1 and 2 raise the missing-data alert. |
| Owner (optional, - for none) | Who looks after it. |
| Site (optional, - for none) | Where it is. |
| Runbook link (optional, - for none) | A link to its how-to page. |
| Description (optional, - for none) | A short description. |
| Unregistered item | Adopt form: an item that sends data but isn't expected, from the Unregistered table. |
| Reason (required) | Why you make the change (each form has its own). |
| Ticket (optional, - for none) | A ticket or change number, or `-`. |
| Confirm (writes the change) | Choose the Apply line to write the change shown in the preview. |

The adopt form's **Criticality** is the same list as the add form's.

#### Add an expected row: preview
- **What it shows:** the expected-list row you are about to add or change. Columns: **Change** (Add expected row or Update expected row), **Item**, **Now**, **After the change** (profile, criticality, how it arrives) and **Check** (for example "Enter the sourcetype", or "This item is managed by ansible: change the Ansible inventory instead").
- **Where it comes from:** your form checked against the expected list. Nothing is written.
- **How to read it:** when Check says OK, choose Apply under Confirm.

#### Add an expected row: result
- **What it shows:** "Done: Add expected row …" or "Nothing written: …", with the details of the change, as for mutes.
- **Where it comes from:** the write itself, which also adds the admin-log row.
- **How to read it:** a new row starts as PENDING and becomes NEVER_SEEN if nothing arrives within an hour.

#### Unregistered: seen in the last 7 d but not expected
- **What it shows:** hosts and sourcetypes that sent data in the last 7 days but are not on the expected list. Columns: **Item**, **Level**, **Index**, **Host**, **Sourcetype**, **Sources** (how many), **Last seen**, **First seen**, **Suggested profile** (once the app has 3 days of history), **Days covered**, **Item ID**.
- **Where it comes from:** the arrival records compared with the expected list.
- **How to read it:** each row is either something new that should be watched (adopt it with the form below) or noise to ignore. Unregistered data is never alerted on.

#### Adopt: preview
- **What it shows:** the expected row that adopting the chosen item would add, with the collection and profile filled in from what the app knows. Columns as for the add preview.
- **Where it comes from:** the unregistered item, its learned baseline and its forwarder facts. Nothing is written.
- **How to read it:** when Check says OK, choose Apply under Confirm.

#### Adopt: result
- **What it shows:** "Done: Adopt …" or "Nothing written: …".
- **Where it comes from:** the write itself.
- **How to read it:** the item leaves the Unregistered table and gets a status within a minute.

### Test blocks (admin) tab

A **test block** throws a host's real data away in **Cribl Stream**, before it reaches Splunk, so you can check that the app notices the data going missing. It applies only to the linux, windows and network indexes and needs the **dh_admin** role. It starts in Cribl about 20 seconds after the command runs, and it ends by itself. The affected items show their real status (late, then missing) with the label "test block until hh:mm". Remove a block as soon as the test is over: in production, a block control is itself a way to blind monitoring.

This tab writes nothing. It checks your request and shows the Ansible command that sets or removes the block (the role's *cribl_block* tag). The role writes Cribl's block table and a copy that Splunk reads for the label and for **Current test blocks**.

#### Recipe: Run a test block

1. Open **Manage**, tab **Test blocks (admin)**.
2. **Action**: Add a test block. **Host**: choose the host. The table **Raw sources of the host (24 h)** fills with what it sent.
3. **Block level**: Whole host, One sourcetype, or One exact raw source. For the last two, choose it in **Sourcetype or raw source**.
4. **Block for**: 5 minutes to 24 hours. Write a **Reason** and press Enter.
5. Check **Test block: preview**: **Check** says OK.
6. Copy the line in **Test block: command** and run it on pi5, in the repository's `ansible` folder. When it finishes, it lists the active blocks.
7. Reload the page: **Current test blocks** lists the block. Watch the Overview: the blocked items turn LATE, then MISSING, labelled "test block until hh:mm".
8. To end it early: **Action** Remove a test block, with the same host and level and a reason, then run the new command.

A source block needs the **exact raw source** name, as listed in the raw sources table; a rotated or dated file name won't match later files, so block that file's sourcetype instead.

#### Inputs

| Input | What to enter |
|---|---|
| Action | Add a test block or Remove a test block. |
| Host | The host to block. Its raw sources fill the table and the next list at once. |
| Block level | Whole host (all its data), One sourcetype, or One exact raw source. |
| Sourcetype or raw source | For the lower levels: the sourcetype, or the exact raw source name (listed with its normalized form). Not needed for a whole-host block. |
| Block for | How long: 5 minutes to 24 hours (the most allowed). |

The form also has its own **Reason (required)** and **Ticket (optional, - for none)**, as above. It has no Confirm: nothing is written from here.

#### Test block: preview
- **What it shows:** the block you are about to add or remove. Columns: **Change**, **Item** (the block key in words), **Now**, **After the change**, **Check** and **Normalized source** (for reference only).
- **Where it comes from:** your form checked against the current block table. Nothing is written.
- **How to read it:** when Check says OK, the command below is ready.

#### Test block: command
- **What it shows:** the one command to run, or "Not ready: …" with the reason the preview gave.
- **Where it comes from:** the checked request, turned into the role's *cribl_block* command (the reason keeps only plain characters).
- **How to read it:** run it on pi5. The role posts a maintenance marker before and after, so the Cribl change doesn't count as tampering.

#### Raw sources of the host (24 h)
- **What it shows:** the exact source names the chosen host sent to the linux, windows and network indexes in the last 24 hours. Columns: **Index**, **Sourcetype**, **Source (raw name)**, **Normalized source** (the name with dates and rotation numbers as `*`), **Events**, **Last seen**.
- **Where it comes from:** the indexed data of this one host (one of the four panels that read raw events; see the start of this guide).
- **How to read it:** a source-level block must use one of these exact raw names.

#### Current test blocks
- **What it shows:** every block in the test-block table. Columns: **Item** (the block key in words), **Until**, **Reason**, **Set by**, **State** ("test block until hh:mm", or "expired: no longer applied (it leaves this list at the next cribl_block run)"), **Block key**.
- **Where it comes from:** the copy of Cribl's block table that the role's *cribl_block* tag writes into Splunk.
- **How to read it:** blocked data is **thrown away** in Cribl before it reaches Splunk, so a block is a real outage, on purpose. Remove blocks as soon as a test ends.

### Admin log tab

Every change made on Manage, newest first.

#### Recipe: Find who muted something

1. Open **Manage**, tab **Admin log**.
2. **Search the log (words separated by *)**: type words that must all appear, for example `mute*pi5`, and press Enter.
3. Read **Who**, **Time**, **Reason** and **Ticket** of the rows. **Detail** shows the state before → after.

#### Inputs

| Input | What to enter |
|---|---|
| Search the log (words separated by *) | Words that must all appear in a row (who, change, item, detail, reason or ticket), separated by `*`; not case-sensitive. `*` shows all. |

#### Admin log (every change made on Manage)
- **What it shows:** the last 1000 changes that match the search. Columns: **Time**, **Who**, **Change** (Mute, Unmute, Set limit, Clear limit, Add expected row, Adopt; Add test block or Remove test block only on older rows, since a test block is now set by the role), **Item**, **Detail** (before → after, as recorded at the time; times in it are in the time zone of whoever made the change), **Reason**, **Ticket**, **Item ID** (for a test block, its key).
- **Where it comes from:** the admin log, written by every applied change. It is also copied to the `data_health` index every 5 minutes (which keeps 14 days) and kept 90 days in the table.
- **How to read it:** use it to answer "who muted this, and why?".

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
- **How to read it:** adopt what should be watched (Manage, Expected list tab); ignore the rest.

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
