# How to read the data-health dashboards

This guide is for anyone who watches the **HL Data Health** app in Splunk. That may be the person who runs this lab, or an analyst who has never read the searches behind the app. It explains every panel in screen order. For each panel it says what the panel shows, where the numbers come from, what good and bad look like, and what to do next. You don't need to write SPL to use it.

Every panel's description on screen ends with "Guide (project repo): docs/data-health/dashboards.md > *dashboard* > *panel*". That points to the entry for the panel in this file, which lives in the project's repository.

The macros behind the panels are in [macros.md](macros.md).

**Keeping this guide current.** Any change that adds, renames or removes a panel or a filter must update this file in the same pull request. `tests/spl/run.sh` fails (check `docs-coverage`) when a panel has no entry here. It also fails when an entry names a panel that no longer exists. The Manage view is generated. Edit `tools/gen_dh_manage.js`, never `dh_manage.xml`. Then regenerate the view. In the repository root on your PC:

```bash
node tools/gen_dh_manage.js
```

The `manage-generated` check in `tests/spl/run.sh` fails when the two files differ.

## The idea in four lines

- The app keeps an [expected list](../glossary.md#expected-list). It names every host that should send data. It also names every kind of data (sourcetype) and every file (source) on a host.
- Every minute the app checks when each of them last sent something. It gives each one a **status** ([what each means](../data-health-design.md#statuses-and-roll-up)).
- The dashboards show those statuses, from the app's own records. Only four panels read the raw events. Each reads one host, and only when you open it. They are the events chart, the Splunk agent errors and the Hyper-V VM events on Host detail, and the list of a host's raw sources on Manage.
- When everything on the expected list is arriving, the Overview says so. When something isn't, it says what, since when, the likely cause and what to do.

## Statuses, causes and words

- What each status and host roll-up means, and how long each takes to show: [data-health-design.md](../data-health-design.md#statuses-and-roll-up).
- Each cause the Cause column can show, and what to do about it: [the runbook](../runbook-missing-data.md#causes-in-the-order-the-app-checks-them).
- Words this guide uses, such as Splunk agent, Ansible marker and normalized source: [the glossary](../glossary.md).

## The banner: is the data current?

The banner at the top of the Overview says whether you can trust the page right now. It checks four things:

1. **Is Splunk receiving?** Has anything at all been indexed in the last 2 minutes?
2. **Is the arrival tracker running?** The background search *DH Tracker fast* records, every minute, when each item last sent data. Has it run in the last 2 minutes?
3. **Is the status search running?** The background search *DH Evaluate* turns those times into statuses every minute. Has it written statuses in the last 3 minutes?
4. **Is the app catching up after a pause?** After PC sleep or a Splunk restart, the app holds statuses for 5 minutes while delayed data arrives.

| Banner (start of the text) | Colour | What it means | What the page does meanwhile | What to check |
|---|---|---|---|---|
| **Up to date: data is arriving and statuses were refreshed at hh:mm** | green | All four checks pass. | It shows real statuses, and alerts work. | Nothing. |
| **On hold: the arrival tracker (DH Tracker fast) last ran … ago** (or "has never run") | red | The arrival tracker has stopped. The app can't tell whether data arrives. | Every status shows PENDING, no alerts fire, and Needs attention lists nothing. | See the first check below. |
| **On hold: Splunk has indexed nothing new for … s** (or "nothing yet") | red | Splunk itself isn't receiving data. | Same as above. | See the second check below. |
| **Out of date: the status search (DH Evaluate) last ran … ago** (or "has not run yet") | red | Arrivals are recorded, but statuses aren't refreshed. | It shows the last statuses it has, which may be old. No new alerts fire, because alerts come from status changes. | See the third check below. |
| **Catching up: Splunk or the PC paused and resumed at hh:mm (sleep or restart)** | amber | The app detected a pause. | Statuses show PENDING for 5 minutes and no alerts fire. So a wake-up raises no false alarms. | Nothing. Wait 5 minutes. |

What to check for each red banner:

1. **Tracker stopped.** In Splunk Web, open *Settings > Searches, reports, and alerts*. Is *DH Tracker fast* enabled and scheduled? Is the scheduler skipping it? See Daily state of health > Skipped searches.
2. **Splunk not receiving.** The Splunk container must be running. It receives on HEC port 8088, and on port 9997 from Cribl (the *hl-net* Docker network).
3. **Status search stopped.** Is *DH Evaluate* enabled, scheduled and not skipped?

When more than one problem applies, the banner lists them all, separated by ";". Times (hh:mm) use the time zone of your Splunk account (Settings > your name > Preferences). That may differ from your PC clock.

**Worked example.** The banner says *"Up to date: data is arriving and statuses were refreshed at 14:32"*. This means three things. Splunk is indexing new data. The search that records arrivals ran within the last 2 minutes. The search that makes statuses wrote them at 14:32, within the last 3 minutes. So every status on the page is fresh.

## Overview

The analyst's view: is anything missing, and what should you do about it? It refreshes every 60 seconds. Click any row of the three tables to open Host detail for that host.

### Filters

The filters at the top apply to every panel except the banner. "All" turns a filter off.

| Input | What it does |
|---|---|
| Site | Shows only items of this site, taken from the expected list. |
| Owner | Shows only items of this owner. |
| Index | Shows only items of this index. Host rows have no index, so a host's own status drops out. |
| Criticality | Shows only items of this criticality. 1 is the most important. |
| Status | Shows only items with this status. Host DOWN and Host DEGRADED show hosts with that roll-up. |
| Search text (words separated by *) | Shows only items whose name, description or cause contains every word. `*` separates words, and nothing else is special, so `50%` means exactly that. |

### Is the data current?
- **What it shows:** the banner. It says whether the page can be trusted right now.
- **Where it comes from:** the run times of the two background searches, and the time of the last indexed data.
- **How to read it:** see [the banner states](#the-banner-is-the-data-current) above. Green means trust the page. Red or amber means the statuses below are held or old. Fix what the banner says first.

### Tamper findings (24 h)
- **What it shows:** how many signs of possible tampering the app first recorded in the last 24 hours.
- **Where it comes from:** it counts the tamper findings first recorded in the last 24 hours that Ansible work doesn't explain. The filters apply.
- **How to read it:** 0 is good. Any other number means you should read the Tamper findings table at the bottom. Escalate if the finding isn't explained.

### KPI tiles
There are three rows of six tiles: one row for hosts, one for sourcetypes and one for sources. Each level is counted on its own. A dead host with five missing inputs shows 1 missing host and 5 missing sourcetypes or sources, not 6. All counts follow the filters.

| Tile | What it counts | Good | Bad means |
|---|---|---|---|
| Hosts expected | Hosts on the expected list. | Matches your inventory. | A host was added or removed. |
| Hosts OK | Hosts whose heartbeat (or data) arrives on time. | When nothing is wrong: Hosts expected minus Hosts muted. | A gap means hosts are late, missing or waiting. |
| Hosts late | Hosts whose heartbeat is late. | 0 | A host or its path to Splunk is slow. |
| Hosts missing | Hosts silent for more than twice their limit, or that never sent anything. | 0 | A host is down or cut off. See Needs attention. |
| Hosts muted | Hosts muted on purpose. | What you expect. | A forgotten mute hides problems. Check Manage. |
| Hosts waiting (PENDING) | Hosts with no trusted status yet. | 0 | The app is on hold (see the banner), or a host was just added. |
| Sourcetypes expected | Kinds of data expected per host. | — | — |
| Sourcetypes OK | Those arriving on time. | — | — |
| Sourcetypes late | Those later than their limit. | 0 | A log stopped or slowed. |
| Sourcetypes missing | Those silent for more than twice their limit, or never arrived. | 0 | See Needs attention. |
| Sourcetypes muted | Those muted. | — | — |
| Sourcetypes waiting (PENDING) | Those with no trusted status yet. | 0 | As for hosts. |
| Sources expected | Individual files or inputs expected. | — | — |
| Sources OK | Those arriving on time. | — | — |
| Sources late | Those later than their limit. | 0 | One file or script stopped or slowed. |
| Sources missing | Those silent for more than twice their limit, or never arrived. | 0 | See Needs attention. |
| Sources muted | Those muted. | — | — |
| Sources waiting (PENDING) | Those with no trusted status yet. | 0 | As for hosts. |

### How many hosts need attention
- **What it shows:** one line. It reads "All expected data is arriving", "1 host needs attention", "N hosts need attention", or "On hold (see the banner above)".
- **Where it comes from:** it counts the hosts that have at least one late, missing or never-seen item. The filters apply.
- **How to read it:** green "All expected data is arriving" is the goal. Red means you should work through the table below, top row first. Amber "On hold" means you should fix the banner's problem first. Until then, nothing can be listed.

### Needs attention
- **What it shows:** one row per host with something late, missing or never seen. The columns are:
  - **Host**.
  - **State**: DOWN or DEGRADED.
  - **Worst status**.
  - **Bad items**: how many, and the first five.
  - **Since** and **For**: when the oldest problem began, and how long ago.
  - **Criticality**.
  - **Cause**.
  - **Action**.
  - **Runbook**.
- **Where it comes from:** the current statuses of the expected list, grouped by host.
- **How to read it:** the worst row is on top. The order is DOWN before DEGRADED, then the worst status, then criticality (1 first), then the oldest problem. An empty table means nothing needs attention, and the line above says so.
- **For each row:** read the **Cause** (the [runbook](../runbook-missing-data.md#causes-in-the-order-the-app-checks-them) explains each one) and do the **Action**. Open the runbook if the row has one. Click the row to see the full picture on Host detail.
- **Times in the Cause:** the times inside the Cause text are fixed when *DH Evaluate* runs. They use the server's time zone, not yours. In this lab that is UTC, so the text says `GMT`.

### Recently recovered (back to OK in the last 24 h)
- **What it shows:** items whose data stopped and came back to OK in the last 24 hours. The columns are **Back to OK at**, **Host**, **Item ID**, **Down since** and **Down for**.
- **Where it comes from:** the recorded status changes. Each stretch of LATE, MISSING or NEVER_SEEN that ended with a change back to OK is listed. Muting a dead item, or switching it to INFO, is not a recovery.
- **How to read it:** a short list of short outages is normal, for example reboots and restarts. The same item many times means it is flapping (see Daily state of health). A long outage that recovered may still need an explanation.

### Tamper findings (first seen in the last 24 h)
- **What it shows:** each sign of possible tampering that the app first recorded in the last 24 hours. The columns are:
  - **First seen**: when the app first recorded it.
  - **Time**: when it happened.
  - **Host**.
  - **What was seen**: for example "1102 security log cleared" or "SERVICE_STOP auditd".
  - **Events**, **Code** and **Detail**.
- **Where it comes from:** the findings of the background search *DH Tamper*. The table keeps the latest state of each finding. It leaves out the role's own work: a finding that an Ansible [marker](../glossary.md#marker-ansible-marker) for the host explains. The role posts its marker before each change it makes. The exact window is in [Tamper indicators](../data-health-design.md#tamper-indicators).
- **A finding is judged once.** The app decides when it first stores a finding whether Ansible work explains it. A marker that comes later never hides it.
- **One install, one finding.** Installing a Windows service logs two events, a 7045 and a 4697. The app folds them into one finding named "7045+4697 service installed: …". It alerts once.
- **How to read it:** empty is good. A finding means someone may have tried to switch off logging. Check whether planned work explains it. A reboot also stops services. If nothing explains it, **escalate**. Click the row to see the host.

## Host detail

Everything about one host. Pick the host at the top, or arrive here by clicking a row on the Overview.

| Input | What it does |
|---|---|
| Host | The host to show. Each host is listed with its roll-up, for example "wd2l-recv (DEGRADED)". |

### Expected data from this host
- **What it shows:** each item this host should send. The columns are:
  - **Item**: the host itself (with how its liveness is judged: heartbeat, probe or data), *index / sourcetype*, or *index / sourcetype / source*.
  - **Status**.
  - **Silent for / limit**: "400 s / 300 s" means silent for 400 s against a limit of 300 s. It says "never arrived" if nothing came yet.
  - **Profile**: how the item usually sends data ([profiles](../data-health-design.md#the-five-ideas)).
  - **Limit from**: where the limit comes from (see the list below the columns). **About the limit** says the same in a sentence.
  - **Mute or test block**: "muted until … (reason)" or "test block until hh:mm". Each has its time zone, for example "test block until 16:46 MDT".
  - **Since**, **Cause**, **Action**. The times inside the Cause use the server's time zone, as on the Overview.
  - **Last hour volume**: last hour against the usual count. "x0.1 of median FLAGGED" means a tenth of the usual count, flagged as a drop. A note says why an item isn't judged.
  - **Clock wrong**: 1 when the data's own timestamps are far from when it arrived.
  - **Item ID**: the item's full identifier.
- **Limit from, in full:**
  - *Override (set on Manage)*.
  - *Fixed limit on its expected row*: a limit written on the item's expected-list row.
  - *Learned from its history*: it needs at least 3 days.
  - *Profile default*: it adds "(learning)" while the item has fewer than 3 days of history.
  - *Profile default (the row's profile is unknown)*: the profile is misspelt or unknown, so the continuous default is used.
  - *None (INFO: never alerts)*.
- **Where it comes from:** the current statuses of the expected list for this host, plus last hour's volume.
- **How to read it:** the host's own row is first. Its sourcetypes and sources follow, worst first. All OK is good. For each bad row, follow the action. An OK status with "FLAGGED" volume means data still arrives, but far less than usual. That is worth a look.

### Events in the last 24 h by sourcetype
- **What it shows:** a stacked column chart of how many events this host sent, per sourcetype, in 10-minute steps over the last 24 hours.
- **Where it comes from:** it counts the indexed events of this host. It is one of the four panels that read raw events (see the start of this guide).
- **How to read it:** steady bars are normal. A gap shows when a stream stopped. A sudden drop or spike is worth comparing with the status changes below.

### Forwarder (the Splunk agent on the host)
- **What it shows:** one fact per row. The facts are:
  - Agent version, with "(expected 10.6.1.1)" when it differs.
  - Operating system and Agent type.
  - Last heartbeat and Last connection to Cribl.
  - Last Ansible marker: the action, when, by whom and the run id.
  - Last Hyper-V event and Last device probe.
- **A host with no agent** shows one row: "No forwarder facts: this host has no Splunk agent or no Splunk agent has connected yet". That fits a network device, a syslog-only host, or an agent that has never connected.
- **Where it comes from:** what the arrival tracker last recorded for this host.
- **How to read it:** a heartbeat a few seconds old is good. A heartbeat that is minutes old, with the host DOWN, means the agent or the host stopped. The last Ansible marker or Hyper-V event often explains why. A version flag means the agent needs the role's install.

### Latest Splunk agent errors and warnings (24 h)
- **What it shows:** the 25 latest error and warning lines that this host's Splunk agent wrote about itself. The columns are **Time**, **Level**, **Agent component** (the part of the agent that complained, for example the file reader) and **Message**.
- **Where it comes from:** the agent's own log, as Splunk received it (the `_internal` index). It covers this host only, for the last 24 hours.
- **Who can see it:** the *dh_analyst* role can search `_internal`, so analysts can use this panel. That also lets them read all of Splunk's own logs.
- **How to read it:** empty is good. Lines about file permissions, a missing file or a blocked output explain a missing input. Read them before you change anything.

### Tamper findings on this host
- **What it shows:** every tamper finding on this host that the app still holds (30 days), newest first. It leaves out findings that Ansible work explains. The columns are **Time**, **What was seen**, **Events**, **Code**, **Detail** and **Finding ID**.
- **Where it comes from:** the findings of *DH Tamper* for this host.
- **How to read it:** empty is good. The Overview's Tamper findings entries say what to do.

### Status changes (7 d)
- **What it shows:** the latest 200 status changes of this host's items in the last 7 days. The columns are **Time**, **Item ID**, **From status**, **Status** (the new one) and the **Cause** at the time.
- **Where it comes from:** the status changes the app records every minute.
- **How to read it:** use it to see when a problem started, and whether it keeps coming back.

### Hyper-V VM events (7 d)
- **What it shows:** this VM's lifecycle events, as [Hyper-V](../glossary.md#hyper-v) on the PC reports them. The columns are **Time**, **Host**, **VM**, **Event ID** and its **Meaning**. The meanings are:
  - 18500: started.
  - 18502: turned off.
  - 18504: shut down by the host.
  - 18506: shutdown initiated.
  - 18508: shut down by the guest OS.
  - 18510: saved.
  - 18514: reset by the guest.
  - 12050: failed to restore.
  - Any other ID shows as "other".
- **Where it comes from:** the Hyper-V Worker-Admin log of the PC, for this VM only, over the last 7 days.
- **How to read it:** it is empty for a physical host or a device. "Turned off" or "shut down" just before the host went DOWN explains the outage. Start the VM.

### Runbooks (click to open)
- **What it shows:** the how-to pages linked to this host's expected items. The columns are **Runbook** and **Items** (how many items use it).
- **Where it comes from:** the runbook column of the expected list. Only web links (`http://` or `https://`) are listed, so a click never opens anything else.
- **How to read it:** click a row to open the page in a new tab. Empty means no runbook was set.

## Manage

Use Manage to change what the app expects and how it alerts. You can:
- Mute data during planned work.
- Change how long an item may stay silent.
- Keep the expected list up to date.
- Run test blocks.
- See who changed what.

The page has four tabs: **Mute & thresholds**, **Expected list**, **Test blocks (admin)** and **Admin log**. Each tab holds its own forms. Each form has its preview and its result right below it.

### Before you start

- **Who may do what.** Anyone who can open the app may mute, unmute, and set or clear a limit. Adding or adopting expected rows, retiring them, and test blocks need the **dh_admin** role. Without it, the preview says "Needs the dh_admin role" and nothing can be applied.
- **Nothing is written until you choose Apply.** A form shows a preview of the change as you fill it in. To write the change, open that form's **Confirm (writes the change)** list. Then choose the line that starts with **Apply**. There is no other button. That choice writes the change at once and records it on the Admin log tab.
- **Each form stands alone.** Every form that writes has its own Reason, Ticket and Confirm. A choice under one form's Confirm writes only that form's change. The test-block form has no Confirm, because it writes nothing.
- **Boxes apply as you go.** There is no Submit button on Manage. A list applies as soon as you pick from it. A text box applies when you press Enter or click outside it. Lists that depend on a host fill as soon as you pick the host. Those are the items of a host, and a host's sourcetypes and raw sources.
- **Until a form is filled in,** its preview area shows what to fill in instead of a table. A required box (Reason, Host name) must not be empty. Optional boxes hold `-`, which means "none". Leave it there unless you have a value.
- **The Confirm list** appears once the form is filled in. It offers the Apply line only when the preview's **Check** column says "OK: …". Otherwise it says "No results", and the Check column says what to fix.
- **Changing the form clears the confirmation.** Suppose you change any box of a form after you choose Apply. Its Confirm choice is cleared and its result disappears. The change you already applied stays applied.
- **A confirmation fits only once.** It fits only the state you previewed. It never fits again after its change was applied, even if that change has since expired and been cleaned up. After a reload, or when you come back to a tab, the result may say "Nothing written: this confirmation fits only the state you previewed, …". That is expected, because the change was applied the first time. Check the tables or the Admin log tab.
- **The tables don't refresh by themselves.** After you apply a change, reload the page to see it in the tables of the tab.
- **Times** use the time zone of your Splunk account (Settings > your name > Preferences). They always end with the zone, for example `2026-10-31 17:46 MDT`. That may differ from your PC clock.
- **Open Manage links only from people you trust.** An add or adopt link can carry a ready-made Confirm choice in its URL. Opening it applies that change as you. This works because Dashboard Studio's risky-command check is off on this Splunk (see the next point). A retire link can't do this. Its confirmation also needs a key that only admins can read.
- **If "This visualization has a potential security risk" appears after Apply,** the check is on again. The result stays empty with a red icon, and nothing is written until you click the icon and then **Run Query**. Apply writes with `outputlookup`, which is on Studio's risky list. So the server app `hl_server_base` turns the check off (`enable_risky_command_check_dashboard = false` in its `default/web.conf`). Why it is off, and its cost, are in [the risky-command check](../running-the-role.md#the-dashboard-risky-command-check-is-off). To see which value Splunk uses, run this on HOMEPC, in PowerShell. In this lab the Splunk container is `wd2l-splunk`:

  ```powershell
  docker exec -u splunk wd2l-splunk sh -c "/opt/splunk/bin/splunk btool web list settings --debug | grep risky"
  ```

  The `enable_risky_command_check_dashboard` line should show `false` from `apps/hl_server_base/default/web.conf`. Suppose it does, and the prompt still appears. Then splunkd hasn't restarted since the deploy, or the page is stale. Restart splunkd, then reload the page. Suppose it doesn't show `false`. Then deploy `hl_server_base` with the role's `server` tag, which restarts splunkd.

### Item IDs

Every expected item has an **Item ID** of five parts, `level|index|host|sourcetype|source`. A `*` stands for a part its level doesn't use. Manage shows an Item ID in words:

- `host|*|pi5|*|*` shows as "pi5: whole host". It is the host itself. Muting it mutes everything the host sends.
- `sourcetype|enclave1|pi5|syslog|*` shows as "pi5 › syslog (enclave1)". It is one kind of data (sourcetype) from that host, in that index.
- `source|linux|h8|app|/var/log/app-*.log` shows as "h8 › app › /var/log/app-*.log (linux)". It is one file or input (source) of a sourcetype. Dates and rotation numbers in file names become `*`. That is the [normalized source](../glossary.md#normalized-source).

Manage keeps the Item ID in the last column of its tables, for searching and for the admin log.

A **test block** has a shorter key, `host|sourcetype|raw source`, with `*` for "all". For example, `pi5|*|*` is the whole host. Manage shows it as "pi5: whole host", "pi5 › syslog" or "pi5 › linux_secure › /var/log/secure.1 (exact source)".

### Mute & thresholds tab

Use this tab for two jobs. You can mute an item during planned work, so that it doesn't alert. You can also change its **limit**, which is how long it may stay silent before it counts as late.

#### Recipe: Mute a host for maintenance

1. Open **Manage** and stay on the **Mute & thresholds** tab.
2. **Host**: choose the host, for example `pi5`.
3. **Item**: choose the line that ends in **whole host**, for example "pi5: whole host (OK)". This mutes everything the host sends.
4. **Action**: leave **Mute**. **Mute for**: choose how long, from 1 hour to 30 days.
5. **Reason (required)**: type why, for example "patching, see CHG-123", and press Enter. **Ticket**: replace `-` with the change number, if there is one.
6. Read the preview, **Mute or limit: preview**. It shows **Change** "Mute" and the item. **Now** reads "Not muted; no limit override". **After the change** reads "Muted until 2026-10-31 21:46 MDT (patching); …". **Check** reads "OK: choose Apply under Confirm to write this change".
7. Open **Confirm (writes the change)** and choose the line "Apply: mute pi5: whole host for 4 hours". The change is written at once. **Mute or limit: result** says "Done: Mute pi5: whole host".
8. Reload the page. The mute is listed under **Current mutes and limit overrides**. Within a minute the Overview shows the host and its items as MUTED.

To end a mute early, do the same with **Action** set to **Unmute**. The Mute for list is then ignored. A mute also ends by itself at its end time.

#### Recipe: Silence one noisy sourcetype

Follow the recipe above, but at step 3 choose the sourcetype's line, for example "pi5 › syslog (enclave1) (LATE)". Only that sourcetype is muted. The host and its other data keep alerting.

#### Recipe: Change how long an item may stay silent

1. In **Thresholds: how long each item may stay silent**, find the item. Type a word of its name in **Search the thresholds (words separated by *)** and press Enter. **Limit applied (s)** is its limit now. **Applied from** says where it comes from.
2. **Host** and **Item**: choose the item.
3. **Action**: **Set limit**. **New limit in seconds (Set limit only)**: replace `-` with the new limit, and press Enter. For example, use `1800` for 30 minutes. The least allowed is 60.
4. Write a **Reason** and press Enter. Check the preview. **After the change** shows "limit override 30 minutes (1800 s)".
5. **Confirm (writes the change)**: choose "Apply: set the limit of … to 30 minutes (1800 s)". The result says "Done: Set limit …".
6. To go back to the app's own limit later, do the same with **Action** set to **Clear limit**.

Suppose the item is muted when you set or clear its limit. The mute and its reason stay as they are.

#### Inputs

| Input | What to enter |
|---|---|
| Host | The host whose item you want to change. Its items fill the next list at once. |
| Item | The host's own row ("whole host", which covers everything it sends), or one of its sourcetypes or sources. Its status is in brackets. |
| Action | Mute, Unmute, Set limit or Clear limit. |
| Mute for | How long a mute lasts, from 1 hour to 30 days (the most allowed). Only Mute uses it. |
| New limit in seconds (Set limit only) | For Set limit: how long the item may stay silent, in seconds (at least 60). Keep `-` for the other actions. |
| Reason (required) | Why you make the change. It goes to the admin log, and a mute shows it as the mute reason. |
| Ticket (optional, - for none) | A ticket or change number, or `-`. |
| Confirm (writes the change) | Choose the Apply line to write the change shown in the preview. |
| Search the thresholds (words separated by *) | Narrows the Thresholds table to items whose name, description or cause contains every word. `*` shows all. |

#### Mute or limit: preview
- **What it shows:** the change you are about to make. The columns are:
  - **Change**: Mute, Unmute, Set limit or Clear limit.
  - **Item**.
  - **Now**.
  - **After the change**: the mute end and reason, and the limit override.
  - **Check**: "OK: choose Apply under Confirm …", or what to fix. Examples are "Write a reason", "A mute lasts at most 30 days" and "This item is not muted: nothing to unmute".
- **Where it comes from:** your form, checked against the current mutes and overrides. Nothing is written.
- **How to read it:** when Check says OK, choose Apply under Confirm. Until the form is filled in, this area shows what to fill in.

#### Mute or limit: result
- **What it shows:** after you choose Apply, one row. **Result** reads "Done: Mute pi5: whole host", or "Nothing written: …" when the confirmation no longer fits. The row also gives the **Time**, **Who**, **Change**, **Item**, **Detail** (before → after), **Reason**, **Ticket** and **Item ID** of the change.
- **Where it comes from:** the write itself, which also adds the admin-log row.
- **How to read it:** "Done" means it is written. "Nothing written" after a reload or a return to the tab is expected, because the change was applied the first time. To make another change, change the form and choose Apply again.

#### Current mutes and limit overrides
- **What it shows:** every mute and limit override in force. The columns are **Item**, **Muted until** ("-" if only a limit is set), **Reason**, **Ticket**, **Limit override** (for example "20 minutes (1200 s)"), **Set by**, **Set at** and **Item ID**.
- **Where it comes from:** the overrides table (`dh_overrides`).
- **How to read it:** look for mutes nobody needs any more, because they hide problems. Expired mutes disappear within a minute. Reload the page after a change to see it here.

#### Thresholds: how long each item may stay silent
- **What it shows:** one row per expected item, with its limit and where it comes from. The columns are:

  | Column | Meaning |
  |---|---|
  | Item | The item in words. |
  | Profile | heartbeat, periodic, continuous, sporadic or info (see [profiles](../data-health-design.md#the-five-ideas)). |
  | Limit applied (s) | The limit in force now. |
  | Applied from | Where the limit comes from. The choices are the same as for Limit from on Host detail. |
  | About the applied limit | The same in a sentence. |
  | Learned limit (s) | What the app learned from at least 3 days of history. It stays within the profile's lowest and highest allowed values. |
  | Learned before bounds (s) | The learned value before it was kept within those values. |
  | Default limit (s) | The profile's default. |
  | Configured limit (s) | A fixed limit written on the item's expected row, if any. |
  | Days covered, Days skipped | Days of history the app learned from, and days it skipped (a day when Splunk was up too little). It looks back 14 days at most, because the indexes keep 14 days. |
  | Suggested profile | The profile the app would choose from what it saw. |
  | Managed by | ansible (from the inventory) or ui (added on Manage). |
  | Item ID | The item's ID. |

- **Where it comes from:** the current statuses, the learned baselines and the expected list.
- **How to read it:** "Profile default" with fewer than 3 days covered means the app is still learning. A learned limit far from the default can be a reason to change the profile. It can also be a reason to set a limit (see the recipe above).

### Expected list tab

Use this tab to tell the app about data it should expect, so that it alerts when that data stops. You can also retire what is gone for good. This tab needs the **dh_admin** role.

Ansible manages some rows. You change those in the Ansible inventory, not here. The one exception is retiring a row the inventory still lists. That retirement holds until the inventory catches up.

#### Recipe: Add an expected row

1. Open **Manage**, tab **Expected list**. Use the first form, **Add an expected row**.
2. **Level**: Host (the host itself), Sourcetype (one kind of data) or Source (one file or input).
3. **Index**: the index the data goes to. Only the indexes the app watches are listed. For a host row, choose "None (host row)".
4. **Host name**: type the host, for example `pi5`, and press Enter. A domain (`.mshome.net`) is cut off.
5. **Sourcetype (not for a host row)**: replace `-` with the name. For a source row, also fill in **Source (source rows only)**.
6. **Collection (how it arrives)**: uf (Splunk agent), syslog or hec. For data that comes through a relay, put the relay in **Via relay**.
7. **Profile**: how the data arrives (see [profiles](../data-health-design.md#the-five-ideas)). For **periodic**, also fill in **Interval in seconds (periodic only)**. **Criticality**: 1 and 2 alert when the data goes missing. 3 and 4 don't.
8. **Owner**, **Site**, **Runbook link** and **Description** are optional. Keep `-` if you have no value. Write a **Reason** and press Enter.
9. Check **Add an expected row: preview**. **Now** reads "Not on the expected list", or shows how the row is now if you change one. **After the change** shows the new row. **Check** reads "OK: …".
10. **Confirm (writes the change)**: choose "Apply: add pi5 › syslog (enclave1) to the expected list (profile continuous, criticality 2)". **Add an expected row: result** says "Done: Add expected row …".
11. The new item starts as PENDING. It becomes OK when data arrives. It becomes NEVER_SEEN if nothing arrives within an hour.

Suppose you run the form again for an item you added here. It updates the row, and the preview says "Update expected row". The row's "expected since" time is kept.

#### Recipe: Adopt something unregistered

1. In **Unregistered: seen in the last 7 d but not expected**, find the item that should be watched.
2. In the second form, **Adopt an unregistered item**: choose the **Unregistered item**, for example "pi5 › cron (linux), last seen …".
3. **Criticality**: choose it. Write a **Reason** and press Enter.
4. Check **Adopt: preview**. **After the change** shows the collection and profile the app suggests.
5. **Confirm (writes the change)**: choose "Apply: adopt …". **Adopt: result** says "Done: Adopt …". After a reload, the item has left the Unregistered table. It gets a status within a minute.

#### Recipe: Retire a host that is gone for good

Use this when a host or a stream is gone for good and nobody will bring it back. A mute hides it for 30 days at most. A retirement stops the app expecting it.

1. Check **Retirement candidates: expected but silent for 7 d or more**. It lists the items with no data for 7 days or more.
2. In the third form, **Retire an expected item**, set **Retire or undo** to Retire. Then choose the **Expected item**: the whole host ("pi9: whole host (3 rows)") or one of its rows.
3. Write a **Reason**, and a **Ticket** if you have one. Press Enter.
4. Check **Retire: preview**. It has one line for each row that will retire. Suppose **After the change** says the Ansible inventory still lists the item. Then remove it from the inventory too ([Retiring a host](../running-the-role.md#retiring-a-host) has the steps). Until then the retirement holds, and *DH Sync expected* leaves the row disabled.
5. **Confirm (writes the change)**: choose "Apply: retire …". **Retire: result** says "Done: Retire …" for each row. Within a minute the item leaves the Overview and stops alerting. Nothing is deleted. Each row stays on the expected list, disabled, with who retired it, when and why.

To bring an item back, choose **Undo a retirement** in the same form.
- A row added on Manage is expected again at once.
- A row that Ansible manages comes back from the inventory. *DH Sync expected* adds it again within 5 minutes, while the inventory still lists it.
- Once the inventory has dropped the row, add it to the inventory again instead.
- Don't use **Add an expected row** for an Ansible row. It would make the row yours instead of Ansible's.

#### Inputs

| Input | What to enter |
|---|---|
| Level | Host, Sourcetype or Source. |
| Index | Where the data goes, from the indexes the app watches. Use "None (host row)" for a host row. |
| Host name | The host name, short or full (it is shortened). Required. |
| Sourcetype (not for a host row) | For sourcetype and source rows. |
| Source (source rows only) | For source rows: the file or input name. |
| Collection (how it arrives) | uf (Splunk agent), syslog, or hec (HTTP Event Collector). |
| Via relay (optional, - for none) | For data that comes through a relay host, the relay (for example pi5). |
| Profile | heartbeat, periodic, continuous, sporadic or info. Each label gives its default limit. |
| Interval in seconds (periodic only) | How often a periodic input runs. |
| Criticality | 1 (highest) to 4. Criticality 1 and 2 raise the missing-data alert. |
| Owner (optional, - for none) | Who looks after it. |
| Site (optional, - for none) | Where it is. |
| Runbook link (optional, - for none) | A link to its how-to page. |
| Description (optional, - for none) | A short description. |
| Unregistered item | Adopt form: an item that sends data but isn't expected, from the Unregistered table. |
| Retire or undo | Retire form: Retire (stop expecting it) or Undo a retirement. |
| Expected item | Retire form: a whole host (all its rows) or one row. Retire lists the expected items, and Undo lists the retired ones. |
| Reason (required) | Why you make the change. Each form has its own. |
| Ticket (optional, - for none) | A ticket or change number, or `-`. |
| Confirm (writes the change) | Choose the Apply line to write the change shown in the preview. |

The adopt form's **Criticality** is the same list as the add form's.

#### Add an expected row: preview
- **What it shows:** the expected-list row you are about to add or change. The columns are **Change** (Add expected row or Update expected row), **Item**, **Now**, **After the change** (profile, criticality, how it arrives) and **Check**. Check may say "Enter the sourcetype" or "This item is managed by ansible: change the Ansible inventory instead".
- **Where it comes from:** your form, checked against the expected list. Nothing is written.
- **How to read it:** when Check says OK, choose Apply under Confirm.

#### Add an expected row: result
- **What it shows:** "Done: Add expected row …" or "Nothing written: …", with the details of the change, as for mutes.
- **Where it comes from:** the write itself, which also adds the admin-log row.
- **How to read it:** a new row starts as PENDING. It becomes NEVER_SEEN if nothing arrives within an hour.

#### Unregistered: seen in the last 7 d but not expected
- **What it shows:** hosts and sourcetypes that sent data in the last 7 days but are not on the expected list. The columns are **Item**, **Level**, **Index**, **Host**, **Sourcetype**, **Sources** (how many), **Last seen**, **First seen**, **Suggested profile** (once the app has 3 days of history), **Days covered** and **Item ID**.
- **Where it comes from:** the arrival records, compared with the expected list.
- **How to read it:** each row is either something new that should be watched, or noise to ignore. Adopt the first kind with the form below. The app never alerts on unregistered data.

#### Adopt: preview
- **What it shows:** the expected row that adopting the chosen item would add. The collection and profile are filled in from what the app knows. The columns are as for the add preview.
- **Where it comes from:** the unregistered item, its learned baseline and its Splunk agent facts. Nothing is written.
- **How to read it:** when Check says OK, choose Apply under Confirm.

#### Adopt: result
- **What it shows:** "Done: Adopt …" or "Nothing written: …".
- **Where it comes from:** the write itself.
- **How to read it:** the item leaves the Unregistered table and gets a status within a minute.

#### Retirement candidates: expected but silent for 7 d or more
- **What it shows:** expected items with no data for 7 days or more, or never seen though expected for 7 days. Muted items are included, because a host that is gone is often kept muted. The columns are **Item**, **Host**, **Level**, **Status**, **Last seen**, **Silent for**, **Expected since** and **Item ID**.
- **Where it comes from:** the current statuses. The 7 days come from the tunable `dh_retire_candidate_secs`.
- **How to read it:** each row is either something that will come back or something gone for good. Leave the first kind, or mute it. Retire the second kind with the form below. A long list here often means the Ansible inventory lags behind the real hosts.

#### Retire: preview
- **What it shows:** one line for each row you are about to retire or bring back. The columns are as for the add preview. **Check** says why a row can't be applied, for example "Needs the dh_admin role" or "Nothing to retire: …".
- **Where it comes from:** your form, checked against the expected list. Nothing is written.
- **How to read it:** when Check says OK, choose Apply under Confirm. The confirmation fits only this preview, and only once.

#### Retire: result
- **What it shows:** "Done: Retire …" (or "Done: Undo retirement …") for each row, or "Nothing written: …".
- **Where it comes from:** the write itself, which also adds one admin-log row for each row.
- **How to read it:** a retired item leaves the Overview within a minute. Its row stays on the expected list, disabled.

### Test blocks (admin) tab

A **test block** throws a host's real data away in [Cribl Stream](../glossary.md#cribl-stream), before the data reaches Splunk. Use it to check that the app notices data going missing. See [test blocks](../glossary.md#test-block).
- It applies only to the linux, windows and network indexes.
- It needs the **dh_admin** role.
- It ends by itself.
- The affected items show their real status, first late and then missing. They carry the label "test block until hh:mm".
- Cribl takes a short time to start dropping data after the command runs. [Test blocks](../running-the-role.md#test-blocks) gives the timing.

Remove a block as soon as the test is over. In production, a block control is itself a way to blind monitoring.

This tab writes nothing. It checks your request. It then shows the Ansible command that sets or removes the block (the role's *cribl_block* tag). The role writes Cribl's block table. It also writes a copy that Splunk reads for the label and for **Current test blocks**.

#### Recipe: Run a test block

1. Open **Manage**, tab **Test blocks (admin)**.
2. **Action**: Add a test block. **Host**: choose the host. The table **Raw sources of the host (24 h)** fills with what the host sent.
3. **Block level**: Whole host, One sourcetype, or One exact raw source. For the last two, choose it in **Sourcetype or raw source**.
4. **Block for**: 5 minutes to 24 hours. Write a **Reason** and press Enter.
5. Check **Test block: preview**. **Check** must say OK.
6. Copy the line in **Test block: command**. Run it on pi5, in `~/homelab-splunk-missing-source/ansible`, with the venv on ([how to run a command](../running-the-role.md#how-to-run-a-command)). When it finishes, it lists the active blocks.
7. Reload the page. **Current test blocks** lists the block. Watch the Overview. The blocked items turn LATE, then MISSING, with the label "test block until hh:mm".
8. To end it early, set **Action** to Remove a test block, with the same host and level and a reason. Then run the new command.

A source block needs the **exact raw source** name, as the raw sources table lists it. A rotated or dated file name won't match later files. Block that file's sourcetype instead.

#### Inputs

| Input | What to enter |
|---|---|
| Action | Add a test block or Remove a test block. |
| Host | The host to block. Its raw sources fill the table and the next list at once. |
| Block level | Whole host (all its data), One sourcetype, or One exact raw source. |
| Sourcetype or raw source | For the lower levels: the sourcetype, or the exact raw source name (listed with its normalized form). A whole-host block doesn't need it. |
| Block for | How long, from 5 minutes to 24 hours (the most allowed). |
| Reason (required: 3 to 120 letters, digits, spaces or _ . : / # ( ) -) | Why you set or remove the block. The role checks the same rule, so a preview that says OK also runs on pi5. |

This form has no Ticket box, because the *cribl_block* tag stores no ticket. It has no Confirm, because nothing is written from here. The reason goes into the command.

#### Test block: preview
- **What it shows:** the block you are about to add or remove. The columns are **Change**, **Item** (the block key in words), **Now**, **After the change**, **Check** and **Normalized source** (for reference only).
- **Where it comes from:** your form, checked against the current block table. Nothing is written.
- **How to read it:** when Check says OK, the command below is ready.

#### Test block: command
- **What it shows:** the one command to run. If the request isn't ready, it shows "Not ready: …" with the reason the preview gave.
- **Where it comes from:** the checked request, turned into the role's *cribl_block* command. The reason keeps only plain characters.
- **How to read it:** run it on pi5. The role posts a maintenance marker before and after, so the Cribl change doesn't count as tampering.

#### Raw sources of the host (24 h)
- **What it shows:** the exact source names the chosen host sent to the linux, windows and network indexes in the last 24 hours. The columns are **Index**, **Sourcetype**, **Source (raw name)**, **Normalized source** (the name with dates and rotation numbers as `*`), **Events** and **Last seen**.
- **Where it comes from:** the indexed data of this one host. It is one of the four panels that read raw events (see the start of this guide).
- **How to read it:** a source-level block must use one of these exact raw names.

#### Current test blocks
- **What it shows:** every block in the test-block table. The columns are:
  - **Item**: the block key in words.
  - **Until**, **Reason** and **Set by**.
  - **State**: "test block until hh:mm", or "expired: no longer applied (it leaves this list at the next cribl_block run)".
  - **Block key**.
- **Where it comes from:** the copy of Cribl's block table that the role's *cribl_block* tag writes into Splunk.
- **How to read it:** Cribl **throws away** blocked data before it reaches Splunk. So a block is a real outage, on purpose. Remove blocks as soon as a test ends.

### Admin log tab

This tab lists every change made on Manage, newest first.

#### Recipe: Find who muted something

1. Open **Manage**, tab **Admin log**.
2. **Search the log (words separated by *)**: type words that must all appear, for example `mute*pi5`, and press Enter.
3. Read **Who**, **Time**, **Reason** and **Ticket** of the rows. **Detail** shows the state before → after.

#### Inputs

| Input | What to enter |
|---|---|
| Search the log (words separated by *) | Words that must all appear in a row (who, change, item, detail, reason or ticket), separated by `*`. The search is not case-sensitive, and `*` alone shows all. |

#### Admin log (every change made on Manage)
- **What it shows:** the last 1000 changes that match the search. The columns are:
  - **Time** and **Who**.
  - **Change**: Mute, Unmute, Set limit, Clear limit, Add expected row, Adopt, Retire or Undo retirement.
  - **Item**.
  - **Detail**: before → after, as recorded at the time. Times in it use the time zone of whoever made the change.
  - **Reason** and **Ticket**.
  - **Item ID**: for a test block, its key.
- **Old rows:** Add test block and Remove test block appear only on older rows. The role now sets test blocks.
- **Where it comes from:** the admin log, which every applied change writes. The app also copies it to the `data_health` index every 5 minutes. The index keeps 14 days. The table keeps 90 days.
- **How to read it:** use it to answer "who muted this, and why?".

## Daily state of health

This is the engineering view. It shows the report made every day at 07:00 UTC, plus the live unregistered list. In this lab, 07:00 UTC is the server's time zone, and it is midnight in Denver in winter. The page doesn't refresh. Reopen it the next day.

### Report time
- **What it shows:** when the report on screen was made.
- **Where it comes from:** the latest daily report.
- **How to read it:** it should be today at 07:00 UTC, shown in your own time zone. It may be the morning after the PC was off. "no report yet" means the report search hasn't run.

### Outages (24 h)
- **What it shows:** how many outages ended in the last 24 hours or are still open. An outage is a stretch of late, missing or never-seen data.
- **Where it comes from:** the recorded status changes.
- **How to read it:** a few is normal in a lab. Many means something keeps failing. See the Outages table.

### Outages still open
- **What it shows:** how many of those outages have not recovered yet.
- **Where it comes from:** outages whose item is still bad now, counted per item.
- **How to read it:** these items should appear on the Overview's Needs attention. This number can be larger than the number of hosts there, because one host can have several open items.

### Mean time to recover (24 h)
- **What it shows:** how long the outages that ended lasted, on average.
- **Where it comes from:** the start and end of each ended outage.
- **How to read it:** lower is better. A jump means problems took longer to notice or fix.

### Licence used yesterday (% of the daily quota)
- **What it shows:** yesterday's indexed data as a share of the licence's daily limit.
- **Where it comes from:** Splunk's licence usage log and licence settings.
- **How to read it:** below 100 % is fine. Near or above it, Splunk warns and may eventually block searching. Reduce what you collect.

### Days until the licence expires
- **What it shows:** the days until the active licence ends.
- **Where it comes from:** Splunk's licence settings.
- **How to read it:** plan a new licence well before 0. After expiry, alerts and roles stop working.

### Outages in the last 24 h
- **What it shows:** each outage, longest first. The columns are **Item ID**, **Started**, **Ended** ("still open" if not yet) and **For** (how long it lasted).
- **Where it comes from:** the recorded status changes.
- **How to read it:** long outages deserve a reason. Repeated short ones point to flapping.

### Flapping (3 or more status changes in 24 h)
- **What it shows:** items that changed status 3 or more times in a day. The columns are **Item ID** and **Status changes (24 h)**.
- **Where it comes from:** the recorded status changes.
- **How to read it:** an item that keeps stopping and starting usually has a limit that is too tight. Raise it on Manage. The sender may also be unstable.

### Never arrived, or a bad profile
- **What it shows:** expected items that have never sent anything, and expected rows whose profile the app doesn't know. It treats an unknown profile as continuous. The columns are **Kind** ("never arrived" or "unknown profile"), **Item ID** and **Detail** ("expected since …", or the note about the profile).
- **Where it comes from:** the current statuses.
- **How to read it:** fix the input, or remove the row. Fix misspelt profiles in the inventory.

### Forwarders: wrong version or disconnected
- **What it shows:** Splunk agents that aren't on the expected version, and agents that haven't called in for 15 minutes. The columns are **Kind** ("wrong version" or "disconnected"), **Host**, **Version** and **Last seen**.
- **Where it comes from:** the Splunk agent facts.
- **How to read it:** for a wrong version, re-run the role's install. For a disconnected agent, check the host.

### Unregistered: seen in the last 7 d but not expected
- **What it shows:** the same live list and columns as on Manage. It lists data that arrives but isn't on the expected list.
- **Where it comes from:** the arrival records, compared with the expected list.
- **How to read it:** adopt what should be watched (Manage, Expected list tab). Ignore the rest.

### Slow arrival (lag p95 of 60 s or more)
- **What it shows:** sourcetypes whose data usually arrives a minute or more after it was written, on the latest day. The columns are **Item ID**, **Delay p95 (s)** and **Day**. Delay p95 means that 95 % of events arrived within this many seconds.
- **Where it comes from:** the daily records of arrival delay.
- **How to read it:** a large lag can make data look late. It usually means a spool, a slow path, or a wrong clock on the sender.

### Volume drops (24 h)
- **What it shows:** items that had hours with far fewer events than usual. "Far fewer" means below 20 % of their usual count for that hour. The columns are **Item ID**, **Hours flagged** and **Lowest share of usual**. A value of 0.05 means 5 % of the usual count.
- **Where it comes from:** the hourly volume checks.
- **How to read it:** data still arrives, but much less of it. An input may be partly broken, or the source got quieter.

### Skipped searches (24 h)
- **What it shows:** this app's background searches that Splunk skipped. The columns are **Search** and **Times skipped**. A row "total" sums them.
- **Where it comes from:** Splunk's scheduler log.
- **How to read it:** the total should be 0. Skipped tracker or status searches turn the banner red.

### Active and expiring mutes
- **What it shows:** the mutes in force, and those ending within 24 hours. The columns are **Kind** ("active" or "ends within 24 h"), **Item ID**, **Until**, **Reason**, **Ticket** and **Set by**. A mute that ends soon appears under both kinds.
- **Where it comes from:** the overrides table.
- **How to read it:** check that each mute is still needed. An expiring mute starts alerting again if the problem is still there.
