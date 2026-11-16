# Roadmap: from nothing to a production rollout

This roadmap takes the customer from no data-health app to a signed-off production rollout. It is
written for the SOC lead first, and then for the Splunk and Cribl engineers who do the work.

**Scope.** Splunk Enterprise only. Splunk Cloud is out of scope.

## How to read it

- The features are in **priority order**. Do F1 first and F9 last. A feature starts when the ones it
  depends on are done.
- Each feature has a **goal**, a few **stories**, **acceptance criteria**, a **size** and its
  **dependencies**.
- Stories read "As a *role*, I want *x*, so that *y*".
- Sizes are rough. **S** is a few days. **M** is one to two weeks. **L** is more than two weeks.
  They depend on how many hosts, sites and Cribl worker groups the customer has.
- Where the customer's setup differs, the feature gives each option in a line. The options are one
  search head or a cluster, one Cribl worker group or several, and Linux or Windows hosts. The
  inventory may come from a CMDB, deployment-server serverclasses, Terraform or Ansible.
- The words are explained in [the glossary](../glossary.md). The model is in
  [the design page](../data-health-design.md).

| Role | Who |
|---|---|
| The SOC lead | Owns the outcome. Signs off. |
| The Splunk admin | Owns the app, the indexes, the roles and the searches. |
| The Cribl admin | Owns the routes, pipelines and Cribl's logs. |
| The host owners | Own the Linux and Windows hosts. |
| The inventory owner | Owns the list of hosts and inputs. |
| The analyst | Reads the dashboards every day. |

## F1 Homework

**Goal:** every source and setting the app needs is in place and proven.

**Stories:**
- As the Splunk admin, I want the platform ready, so that the app's searches run on time.
  See [section 1](prerequisites.md#1-splunk-platform).
- As the SOC lead, I want the right roles and a decision on `_internal`, so that access is on
  purpose. See [section 2](prerequisites.md#2-roles-and-permissions).
- As a host owner, I want every UF to send `_internal` and the right inputs, so that the app has a
  heartbeat for each host. See [section 3](prerequisites.md#3-splunk-universal-forwarders).
- As the Cribl admin, I want Cribl's logs, audit log and routes in place, so that the app can tell
  a Cribl outage from a host outage. See [section 4](prerequisites.md#4-cribl-stream).
- As a host owner, I want auditd, Windows event logs and device probes on, so that the app can see
  tampering and dead devices. See [section 5](prerequisites.md#5-hosts-and-devices).
- As the inventory owner, I want one source of truth in the app's row format, so that the expected
  list is right. See [section 6](prerequisites.md#6-the-inventory-feed).
- As the change owner, I want automation to post markers and a mute step in each change, so that
  planned work does not page anyone. See [section 7](prerequisites.md#7-change-process-markers-and-mutes).
- As the Splunk admin, I want the risky-command check on, so that a crafted link cannot change the
  app. See [section 8](prerequisites.md#8-security-settings).

**Acceptance:**
- Every row of [the summary table](prerequisites.md#summary-for-the-project-manager) is ticked.
- Each "Check" in the prerequisites ran and gave the stated result.

**Size:** M. **Depends on:** nothing.

## F2 Pilot install

**Goal:** the app runs on a non-production search head, for one site, and the team trusts what it
shows.

**Stories:**
- As the Splunk admin, I want to install the `hl_data_health` app on a non-production search head,
  so that I can test it without risk.
- As the Splunk admin, I want the pilot to cover one site, so that the first expected list stays
  small and easy to check.
- As the inventory owner, I want to feed the pilot site's hosts into the app, so that I can see
  that the rows are right.
- As the SOC lead, I want to wait out the learning period, so that learned limits are real.

**The learning period.** The app learns a limit for each *continuous* and *sporadic* item. It needs
at least 3 covered days. A covered day is one where the host and Splunk were both up for at least
half of it. Until then it uses a default. That is 15 minutes for continuous items and 24 hours for
sporadic ones. The dashboards say "profile default while learning (n of 3 days)". Plan at least 3 days, and a week is
better. See [the design page](../data-health-design.md#the-five-ideas).

**Acceptance:**
- The Overview banner says "Up to date" for a full day.
- Every pilot host has a row, and each row has a sensible status.
- The *DH Daily SoH report* ran at least 3 times.
- Learned limits show for the busy items after day 3.
- The scheduler shows no skipped runs for the app.

**Size:** M. **Depends on:** F1.

## F3 Inventory integration

**Goal:** the production inventory feeds the expected list on its own. The list stays right as hosts
come and go.

**Stories:**
- As the inventory owner, I want a job that writes the app's CSV from the source of truth, so that
  nobody edits the expected list by hand. Pick the option that fits:
  - **Deployment server:** build the rows from serverclasses and their apps.
  - **CMDB:** export the hosts and their inputs.
  - **Terraform or Ansible:** render the rows from the same variables that deploy the inputs.
- As the Splunk admin, I want the file delivered to the app and *DH Sync expected* to merge it, so
  that rows appear within minutes. In a search-head cluster, one member's copy of the file must reach
  all members. Run *DH Sync expected* on one member only. Manage adds its own rows (`managed_by=ui`).
- As the SOC lead, I want drift checks every week, so that the list does not rot.
  - Review the **Unregistered** list on Manage. It shows data that arrives but is not expected.
  - Review **Retirement candidates**. They show expected items silent for 7 days or more.
- As the inventory owner, I want a retire step when a host is decommissioned, so that it stops
  alerting. See [Retiring a host](../running-the-role.md#retiring-a-host) for the lab's way. A
  production equivalent removes the host from the feed. An admin can also retire it on Manage.

**Acceptance:**
- A new test host appears on the expected list within 10 minutes of joining the source.
- A removed test host's rows turn off after the next sync.
- A row added on Manage (`managed_by=ui`) is never overwritten by the feed.
- An empty file changes nothing.
- The weekly drift review is on a calendar with a named owner.

**Size:** L. **Depends on:** F2.

## F4 Tuning

**Goal:** the app's alerts are quiet and true. Each item has the right profile, limit and priority.

**Stories:**
- As the analyst, I want every item on the right profile, so that the limits fit how it sends data.
  The profiles are heartbeat, periodic, continuous, sporadic and info. See
  [the five ideas](../data-health-design.md#the-five-ideas).
- As the Splunk admin, I want to review the learned limits after the learning period, so that I
  catch bad ones. A sporadic item can read OK for a long silence. Set a fixed `max_gap_secs` for
  items that matter. It beats the learned value.
- As the analyst, I want an override on noisy items, so that they stop alerting. Use a mute with a
  reason and an end time, or set a limit, on the Manage page. See
  [Manage](../data-health/dashboards.md#manage).
- As the SOC lead, I want a criticality for each item, so that only the right items page. Alerts
  fire for criticality 1 and 2. Criticality 3 and 4 never alert.
- As the analyst, I want to review each **Unregistered** row, so that real data is adopted and noise
  is ignored.

**Acceptance:**
- For 7 days in a row, no alert is false.
- Every criticality 1 item has a reason written down.
- Flapping items on the daily report are zero, or each has an owner.
- Every mute has a reason and an end date.

**Size:** M. **Depends on:** F2. Start it in the pilot and finish it in each wave.

## F5 Alert routing

**Goal:** the app's alerts reach the customer's ticketing, SOAR or on-call tool, once and with the
right context.

**The alerts:**

| Alert | Fires when | Throttle |
|---|---|---|
| *DH Alert missing* | An item with criticality 1 or 2 goes MISSING. It runs every minute. | 1 hour per item |
| *DH Alert tamper* | A new tamper finding appears that no marker explains. It runs every 5 minutes. | 1 hour per host and indicator code |

Each alert writes an event to `index=data_health source=dh:alert`. It also shows in Triggered
Alerts. Email can be added in `local/` once SMTP is set up.

**Stories:**
- As the Splunk admin, I want to add a webhook, email or ticket action to each alert, so that the
  right tool gets it. Pick the option that fits:
  - **Ticketing or on-call tool with a Splunk add-on:** add its alert action to the saved search.
  - **SOAR:** have it read `index=data_health source=dh:alert`.
  - **Webhook or email:** use Splunk's built-in actions.
- As the on-call analyst, I want each alert to carry the entity, cause and next action, so that I
  can act without opening Splunk. The event already holds `entity_id`, `cause` and `action`.
- As the SOC lead, I want de-duplication, so that one outage makes one ticket. The throttle gives
  one alert an hour per item. The tool must also merge repeats by `entity_id` or by host and `code`.
  A UF host outage and the rows under it should not make a ticket each.
- As the SOC lead, I want a rule for who is paged for a Cribl outage, so that one call covers all
  the rows that read "Cribl DOWN".

**Acceptance:**
- A test block or a stopped test host makes one ticket, within the times in
  [the design page](../data-health-design.md#how-long-until-late-missing-or-down).
- A second alert for the same item inside one hour makes no new ticket.
- A tamper alert reaches the security on-call, not only the platform team.

**Size:** M. **Depends on:** F2. It must finish before the first production wave (F8).

## F6 Tamper coverage

**Goal:** the app can see someone switching off logging, and it does not cry wolf at planned work.

**Stories:**
- As the change owner, I want my automation to post a marker before each planned change, so that
  the app knows it was planned. Use the format in
  [prerequisites 7.1](prerequisites.md#71-maintenance-markers). Cover patching, restarts, UF
  upgrades and Cribl deploys.
- As the change owner, I want a way to post a marker alone, before a hand edit, so that a manual fix
  does not raise an alert. The lab has no such tool yet (lab issue #56). Build the customer's own.
- As the Cribl admin, I want Cribl's audit log in Splunk and a marker before each Cribl change, so
  that edits to routes and pipelines are findings unless planned. See
  [prerequisites 4.3](prerequisites.md#43-the-cribl-config-change-audit).
- As a Windows owner, I want the key events to arrive, so that a cleared log is a finding. Check
  that 7036 arrives on Windows Server. See
  [prerequisites 5.2](prerequisites.md#52-windows-security-and-system-logs).
- As a Linux owner, I want auditd and its rules on every host, so that a stopped logger is a
  finding. See [prerequisites 5.1](prerequisites.md#51-linux-auditd-its-rules-and-rsyslog).
- As the SOC lead, I want to try each indicator once on a test host, so that I know it works. See
  [the indicators](../data-health-design.md#tamper-indicators).

**Acceptance:**
- A planned change with a marker makes no tamper alert.
- The same change without a marker makes one alert. Other tamper indicators take about 5 minutes. A
  stopped agent takes 10 to 17 minutes after the agent comes back.
- Each of these gives a finding on a test host: a stopped agent, a stopped auditd, a cleared
  Windows log and a Cribl route change.

**Size:** M. **Depends on:** F2.

## F7 Training

**Goal:** every person who touches the app knows what it says and what to do.

Examples of each kind: see the training folder (to come, issue #67).

**Stories:**
- As an analyst, I want an analyst guide, so that I can read the Overview, Host detail and the
  daily report. It builds on [the dashboard guide](../data-health/dashboards.md).
- As an admin, I want an admin guide for Manage, so that I can mute, set limits, add, adopt and
  retire rows, and run test blocks. It builds on [Manage](../data-health/dashboards.md#manage).
- As an analyst, I want one runbook for each finding type, so that I know the next step. The lab
  runbook has a section for each cause. The customer's copy needs its own commands and contacts:
  - [On hold: the tracker or Splunk](../runbook-missing-data.md#on-hold-the-tracker-or-splunk)
  - [A test block](../runbook-missing-data.md#clear-a-test-block)
  - [A stop or uninstall by the automation](../runbook-missing-data.md#start-a-uf-that-ansible-stopped)
  - [Possible deliberate blinding](../runbook-missing-data.md#possible-deliberate-blinding)
  - [A Splunk agent stop with no explanation](../runbook-missing-data.md#splunk-agent-stopped-not-explained)
  - [Cribl is down](../runbook-missing-data.md#cribl-is-down)
  - [Device problems](../runbook-missing-data.md#device-problems)
  - [The Splunk agent is late or stopped](../runbook-missing-data.md#the-splunk-agent-is-late-or-stopped)
  - [An input is missing](../runbook-missing-data.md#the-agent-works-but-an-input-is-missing)
  - [A stream stopped](../runbook-missing-data.md#this-stream-stopped)
  - [Retire a row that never arrived](../runbook-missing-data.md#retire-a-row-that-never-arrived)
- As the SOC lead, I want an analyst deck, so that I can brief a room in 30 minutes.
- As the SOC lead, I want an admin deck, so that the people who change the app know the rules and the
  risks.
- As an analyst and an admin, I want hands-on exercises with test blocks, so that I practice on a
  test host. The exercise is to set a block, watch the status change, follow the runbook and clear
  the block. See [Test blocks](../running-the-role.md#test-blocks).
- As the SOC lead, I want a short quiz or sign-off per person, so that I know who is ready.

**Acceptance:**
- Each analyst did the exercise and found the cause shown for a blocked host.
- Each admin did a mute and a retire on a test host.
- The customer's runbook has a section for every cause above, with real commands and contacts.

**Size:** L. **Depends on:** F2 for the material. Give each wave's people their training before the
wave starts.

## F8 Staged rollout

**Goal:** move from the pilot to every production host, one wave at a time. A wave is a site or a
group of hosts. Each wave must pass its test before the next one starts.

**Stories:**
- As the SOC lead, I want a wave plan, so that each step is small. Good waves are a site, an OS or
  a business group. Keep the most critical hosts for later waves.
- As the Splunk admin, I want to install the app on the production search head, so that the pilot's
  work carries over. A search-head cluster needs the deployer and the one-writer rule.
- As the inventory owner, I want each wave's hosts added to the feed, so that the expected list grows
  with the waves.
- As the SOC lead, I want a per-wave acceptance test, so that each wave is proven.

**The per-wave test.** Reuse the
[fault-injection matrix](../records/2026-11-fault-injection-run.md#fault-injection-matrix-spec-12).
It lists the faults, the expected result and the time limit. For each wave, run these on a test
host in the wave. Use the customer's own commands:

| Test | What you do | Pass when |
|---|---|---|
| Planned stop | Stop the agent through the change process. | The host goes DOWN with a cause that names the automation. No tamper alert. |
| Unplanned stop | Stop the agent by hand, with no marker. | DOWN in 4–5 minutes. About 10 to 17 minutes after the agent comes back: one finding and one alert. Other tamper indicators take about 5 minutes. |
| Input off | Disable one input. | That row goes LATE and then MISSING. The cause says the input stopped. |
| Logger off | Stop auditd on Linux (on RHEL-family 10 hosts, use `service auditd stop`; `systemctl stop auditd` is refused). Clear a test event log on Windows. | A tamper finding and an alert in about 5 minutes. |
| Relay off | Stop one Cribl worker. | The `cribl` row goes DOWN and the rows behind it say "Cribl DOWN". |
| Test block | Block a test host's data in Cribl. | The row says "test block" and the status goes LATE. |
| Mute | Mute the host. | The host and its rows show MUTED within a minute. |
| Search head restart | Restart Splunk. | Pass when no false alert fires. A restart longer than about 2 minutes holds statuses as PENDING for 5 minutes. |

Run the relay and restart tests in the first wave only, and again after any change to Cribl or the
search head. The sleep and wake row of the matrix was not run in the lab, so skip it.

**Acceptance for each wave:**
- Every test above passed on a test host in the wave.
- No unexplained alert in the 3 days after.
- The wave's hosts all show on the expected list, with owners.

**Size:** L. **Depends on:** F3, F4, F5, F6, F7.

## F9 Production sign-off and operate

**Goal:** the SOC lead signs off, and the app becomes part of daily operations.

**Stories:**
- As the analyst, I want a daily review of the **Daily state of health** page, so that problems are
  found early. The page lists outages, flapping items, never-seen items, unregistered data, agents
  off version, slow arrival, volume drops, skipped searches and mutes that are about to end. See
  [Daily state of health](../data-health/dashboards.md#daily-state-of-health).
- As the SOC lead, I want KPIs, so that I can show the value. Use these:
  - Mean time to recover (MTTR) and the number of outages.
  - Flapping items.
  - Skipped searches.
  - Unregistered items and retirement candidates.
  - Tamper findings, and how many were explained.
- As the SOC lead, I want named owners for the feed, the app, Cribl and the runbooks, so that
  nothing is left without one.
- As the Splunk admin, I want to review limits, mutes and criticality each quarter, so that the
  settings do not rot. Also check the UF version macro, the build map and the retention.
- As the SOC lead, I want a keep-docs-current rule: any change to the app, the feed or the process
  updates the customer's runbooks and training in the same change.
- As the SOC lead, I want a sign-off record, so that the rollout is closed on paper.

**Acceptance:**
- Daily review is on the calendar with a named analyst and a backup.
- The KPI report goes out each month.
- The sign-off lists every wave, its test result and its owner.

**Size:** S to start, then ongoing. **Depends on:** F8.

## Open items from the proof of concept

These are open issues in the lab's own backlog. Each has a recommendation.

| Issue | In plain words | Before production? |
|---|---|---|
| #56 | The role can't post a marker alone, so a hand edit on a UF raises a false tamper alert. | **Yes.** Build the customer's equivalent in F6. Hand edits are common in production, and false tamper alerts teach people to ignore real ones. |
| #58 | A learned limit for a rarely quiet item grows during a long silence. The item flips from LATE back to OK with no data. | **Yes.** It can hide a real stop of a sporadic input. Until it is fixed, set a fixed `max_gap_secs` on important sporadic items in F4. |
| #59 | An unmarked Linux reboot still raises one tamper alert from the boot's audit-rule load. | **Before the first large Linux wave.** It makes noise, not a blind spot. A marker before each patch reboot hides it. |
| #60 | Small hardening of the agent-stop logic: the pairing window, a static check and one auid gap. | **No.** Detection of common cases is not affected. One edge case, an auditd stop followed by an agent stop that stays down, gives no alert. Do it after sign-off. |
| #53 | Minor leftovers. Counts and labels are wrong in rare fold cases. Analysts see a permission error on the Retire preview. | **Mostly no.** Fix the Retire preview error before F7, so training does not show it. The rest can wait. |

## Summary

| Feature | Goal | Size | Depends on |
|---|---|---|---|
| F1 Homework | Every source and setting in place | M | none |
| F2 Pilot install | App runs on a test search head for one site | M | F1 |
| F3 Inventory integration | Expected list fed from the source of truth | L | F2 |
| F4 Tuning | Quiet, true alerts | M | F2 |
| F5 Alert routing | Alerts reach tickets and on-call once | M | F2 |
| F6 Tamper coverage | Tampering is seen, planned work is not | M | F2 |
| F7 Training | Everyone knows what to do | L | F2 |
| F8 Staged rollout | Every host live, wave by wave | L | F3, F4, F5, F6, F7 |
| F9 Sign-off and operate | Signed off and part of daily work | S, then ongoing | F8 |
