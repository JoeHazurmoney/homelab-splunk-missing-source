# Runbook: something is missing

Start on the **Overview** of the HL Data Health app. Each row of *Needs attention* is a host with its
worst item, the **Cause** and the **Action**. Click a row to open **Host detail**. This page covers
each cause: what it means, what to check first, and what to do. The dashboards are described in
[the dashboards guide](data-health/dashboards.md): the
[Overview](data-health/dashboards.md#overview), [Host detail](data-health/dashboards.md#host-detail)
and [Manage](data-health/dashboards.md#manage).

Words used here are in the [glossary](glossary.md):

- The **Splunk agent** is the [UF](glossary.md#universal-forwarder-uf). The app's messages say
  "Splunk agent". The docs say "UF".
- Statuses: [LATE, MISSING and NEVER_SEEN](glossary.md#status), [DOWN](glossary.md#roll-up) and
  [PENDING](glossary.md#pending-the-gate). Also [profile](glossary.md#profile) and
  [sporadic](glossary.md#sporadic).
- [Marker](glossary.md#marker-ansible-marker), [tamper indicator](glossary.md#tamper-indicator-tamper-finding),
  [relay](glossary.md#relay-via) and [arrival tracker](glossary.md#arrival-tracker-dh-evaluate).
- [S2S](glossary.md#s2s-splunktcp): port 9997 is its port. [auditd and rsyslog](glossary.md#auditd-audit-rules),
  [`btool`](glossary.md#btool) and [wd2l](glossary.md#wd2l).

Before you start:

- A command with `--tags …` is an `ansible-playbook site.yml` run. Run it on pi5, as
  [How to run a command](running-the-role.md#how-to-run-a-command) says.
- To run one command on a Linux host, see [How to reach a host](#how-to-reach-a-host).
- Run searches in the HL Data Health app, and don't use `punct`
  ([Searching](running-the-role.md#searching)).
- Never run the `splunk` CLI as root on a UF
  ([why](running-the-role.md#never-run-splunk-as-root-on-a-uf)).
- The Cause column shows times in the scheduler's time zone, not yours
  ([why](data-health/dashboards.md#needs-attention)). In this lab that is UTC, so the text says `GMT`.

**Read the banner first.** If it says *On hold*, every status is PENDING on purpose, and no alert
fires. Fix what the banner names before you look at single rows.

## How to reach a host

Run commands on a Linux host from pi5, with Ansible. On pi5, in
`~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible <host> -b -m command -a 'auditctl -s'
```

`<host>` is an inventory name, such as `wd2l-recv`
([the names](architecture.md#hosts-in-this-lab)). The flag `-b` runs the command with sudo. Leave it
out when the command needs no sudo. If sudo asks for a password, add `-K`. HOMEPC can't SSH to the
VMs on its own ([why](architecture.md#hosts-and-data-paths)).

**One exception:** don't use `-b` for `splunk btool`. It runs as root there, which raises a false
tamper finding. See [Never run `splunk` as root on a UF](running-the-role.md#never-run-splunk-as-root-on-a-uf).

## Causes, in the order the app checks them

The first cause that fits wins. `<…>` marks the parts the app fills in. The commands for each cause
are in [Steps for each cause](#steps-for-each-cause). A **syslog path** is the route a device's logs
take: its remote syslog setting, the network, and HOMEPC's UDP port.

| Cause (as shown) | What it means | What to do |
|---|---|---|
| **On hold: the arrival tracker (DH Tracker fast) has not run for `<n>` s**, or **On hold: the arrival tracker (DH Tracker fast) has never run** | The search that records arrivals isn't running. Nothing can be judged. | Enable the search, or find why Splunk skips it. [Steps](#on-hold-the-tracker-or-splunk). |
| **On hold: Splunk has indexed nothing for `<n>` s**, or **On hold: Splunk has indexed nothing yet** | Everything went quiet at once. That is a Splunk problem, not a host problem. | Get the Splunk container running and receiving. [Steps](#on-hold-the-tracker-or-splunk). |
| **On hold: catching up after a pause (sleep or restart) at `<time>`; statuses held for 5 min** | The PC slept or Splunk restarted. | Wait 5 min. |
| **Muted until `<time>`: `<reason>`** (or "no reason given") | Someone muted it on Manage. | Nothing while muted. See Manage → Mute & thresholds. |
| **Added less than 1 h ago: waiting for its first data** | The item is new on the expected list. It hasn't sent anything yet. | Wait up to 1 h. |
| **Test block until `<time>` (data dropped on purpose): `<reason>`** | A test is dropping this data in Cribl. | When the test is over, clear the block. [Steps](#clear-a-test-block). |
| **Stopped with Ansible at `<time>` by `<user>` and not started again** | The role stopped the UF (`--tags stop`). Nothing started it again. | Start it again. [Steps](#start-a-uf-that-ansible-stopped). |
| **Uninstalled with Ansible at `<time>` by `<user>` and not installed again** | The role removed the UF (`--tags uninstall`). The host stays expected on purpose. | Install it again, or retire its rows. [Steps](#put-back-a-uf-that-ansible-uninstalled). |
| **The VM is off: Hyper-V event `<id>` (`<what happened>`) at `<time>`** | Hyper-V says the VM was turned off, shut down (by the host or the guest OS) or saved. | Check Hyper-V Manager on HOMEPC. Start the VM, or mute the host while it's meant to be off. |
| **Possible deliberate blinding: `<indicator>` at `<time>` just before the data stopped** | A tamper indicator came within 15 min of the silence. No Ansible marker covers it. | **Escalate** to the lab owner. Save the evidence first. [Steps](#possible-deliberate-blinding). |
| **Cribl DOWN: the real state is unknown (this data passes through Cribl and Cribl is not reporting)** | Everything collected goes through Cribl, and Cribl isn't reporting. The data itself may be fine. | Check the Cribl container, then fix Cribl. [Steps](#cribl-is-down). |
| **The relay `<via>` is DOWN: this data comes through it so its real state is unknown** | Another relay host that carries this data is down. | Click the relay's own row on the Overview. Fix it first, using the cause shown there. |
| **The device does not answer the network probe: the device or its network is down** | The device doesn't answer pi5's ping. | Check the device's power and network. [Steps](#device-problems). |
| **The device probe (hl-devprobe on pi5) stopped reporting on this device** | The probe stopped. The device may be fine. | Check the probe on pi5. [Steps](#device-problems). |
| **The device answers the network probe but sends no logs: its logging settings probably changed** | The device is up, but its syslog doesn't arrive. A UDM with remote syslog off shows this cause. | Fix the device's remote syslog setting. [Steps](#device-problems). |
| **The Splunk agent reports late (not yet missing): the agent is busy or stopping or its network path to Cribl (port 9997) is slow** | The heartbeat is slow, but not yet missing. | Usually it passes. If not, check the path to Cribl's port 9997. [Steps](#the-splunk-agent-is-late-or-stopped). |
| **The Splunk agent stopped reporting: the host is down or cut off from Cribl (port 9997) or the agent crashed or was stopped outside Ansible** | There is no heartbeat. | Check the host, then start the agent. [Steps](#the-splunk-agent-is-late-or-stopped). |
| **The Splunk agent works but this input has never sent anything: input not enabled or wrong index or sourcetype or no permission to read it** | The agent works, but this input never delivered. | Check the input's settings, then redeploy the apps. [Steps](#the-agent-works-but-an-input-is-missing). |
| **The Splunk agent works but sends no data at all: its apps or inputs were removed or it cannot forward or a test block drops it** | The heartbeat is fine, but every stream stopped. | Check for test blocks, then redeploy the apps. [Steps](#the-agent-works-but-an-input-is-missing). |
| **The Splunk agent works but this input stopped: its file is unreadable or was moved or rotated or auditd or rsyslog stopped or audit rules were removed** | One stream stopped while the host still sends others. | Find out why the input stopped, then fix it. [Steps](#the-agent-works-but-an-input-is-missing). |
| **Cribl DOWN: nothing from Cribl itself so every collected stream is unknown** | This is the `cribl` row. Its workers' own logs stopped. | As for [*Cribl DOWN*](#cribl-is-down), below. |
| **Nothing at all from this host (it has no Splunk agent): the host is down or its syslog path is broken** | A host without an agent sends nothing. | Check the host and its syslog path. [Steps](#device-problems). |
| **Never arrived since it was added: the input is not deployed or not sending** | An expected item on a host with no agent and no probe has never arrived. | Remove or retire the row. [Steps](#retire-a-row-that-never-arrived). |
| **Cribl late: nothing recent from Cribl itself (not yet DOWN) so collected streams may soon be unknown** | This is the `cribl` row while its own logs are late. It lasts about 2 min before *Cribl DOWN*. | As for [*Cribl DOWN*](#cribl-is-down), below. |
| **Everything from this host is late (not yet missing; it has no Splunk agent): the host or its syslog path is slow or stopping** | Every stream of a host without an agent is late. None is missing yet. | Check the host and its syslog path. [Steps](#device-problems). |
| **Everything from this host is late or missing (it has no Splunk agent): the host or its syslog path is slow or stopping** | Every stream of a host without an agent is late. Some are already missing. | Check the host and its syslog path. [Steps](#device-problems). |
| **This stream stopped while the host still sends others: its program or input stopped** | Only this stream stopped. For `enclave1` rows, that means wd2l's delivery. | Check the program behind the stream. [Steps](#this-stream-stopped). |

## Steps for each cause

### On hold: the tracker or Splunk

Two causes put the whole app on hold. The banner names the one that applies.

**The tracker isn't running.** The [arrival tracker](glossary.md#arrival-tracker-dh-evaluate) is the
saved search *DH Tracker fast*. Check whether it runs or Splunk skips it. In Splunk Web, in the
HL Data Health app:

```
index=_internal sourcetype=scheduler savedsearch_name="DH Tracker fast" earliest=-15m | stats count by status
```

You should see `status=success` with a count of about 15, one run a minute. Then:

- **No rows:** the search is off. In Splunk Web, open *Settings > Searches, reports, and alerts*.
  Enable *DH Tracker fast* and check that it is scheduled.
- **`status=skipped`:** Splunk's scheduler is skipping it. In this lab, a skip usually means WSL2 (the
  Linux layer Docker Desktop runs on) is short of CPU. The Daily state of health panel
  [Skipped searches](data-health/dashboards.md#skipped-searches-24-h) counts the skips. If they
  continue, tell the lab owner (in this lab: Taylor).

**Splunk isn't receiving.** Check the Splunk container and its HEC health. On HOMEPC, in PowerShell,
any folder:

```powershell
docker ps --filter name=wd2l-splunk
curl.exe -sk https://127.0.0.1:8088/services/collector/health
```

You should see a `wd2l-splunk` line whose status starts with `Up`. The second command prints
`{"text":"HEC is healthy","code":17}`. If the container isn't listed, or says `Exited`, start it.
On HOMEPC, in PowerShell, any folder:

```powershell
docker start wd2l-splunk
```

Then run the two checks again. If HEC still isn't healthy, tell the lab owner.

Cribl delivers everything it collects to Splunk's S2S port, 9997, on the `hl-net` Docker network. To
check that both containers are on that network, run this on HOMEPC, in PowerShell, any folder:

```powershell
docker network inspect hl-net --format "{{range .Containers}}{{.Name}} {{end}}"
```

It should print `wd2l-splunk` and `cribl`. If `wd2l-splunk` is missing, attach it again. On pi5, in
`~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags server_network
```

### Clear a test block

Manage → Test blocks → Current test blocks lists each block and its key. When the test is over, clear
the block. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags cribl_block --limit homepc -e hl_block_key='<key>' -e hl_block_clear=true
```

`<key>` is the block's key, such as `wd2l-recv|linux_secure|*`. More on blocks:
[Test blocks](running-the-role.md#test-blocks).

### Start a UF that Ansible stopped

First check who stopped it and when. In Splunk Web, in the HL Data Health app:

```
index=data_health source=dh:marker target_host=<host> | table _time action by run_id
```

`<host>` is the host's inventory name in lowercase, such as `wd2l-recv`. The marker's `target_host`
is stored that way. You should see a row like this (an example):

| _time | action | by | run_id |
|---|---|---|---|
| 2026-11-12 04:31:34 | stop | taylorb | 20261112T043134Z-taylorb |

Then start the UF. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags start --limit <host>
```

**If the start fails,** the cause changes. The `start` marker went out before the start, so it is now
the host's latest marker. The cause moves to a general Splunk agent cause
([details](running-the-role.md#stop-start-and-restart)). Next:
[The Splunk agent is late or stopped](#the-splunk-agent-is-late-or-stopped).

### Put back a UF that Ansible uninstalled

First check who removed it. In Splunk Web, in the HL Data Health app:

```
index=data_health source=dh:marker target_host=<host> action=uninstall
```

The host stays on the expected list on purpose. A host that is only off must keep alerting. Then
pick one:

- **Install it again.** On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

  ```bash
  ansible-playbook site.yml --tags install,apps,audit_rules --limit <host>
  ```

- **Retire its rows,** if the host is gone for good. The steps are in
  [Retiring a host](running-the-role.md#retiring-a-host).

**If the install fails,** the `install` marker went out before it, so it is now the host's latest
marker. The cause moves to a general Splunk agent cause
([details](running-the-role.md#stop-start-and-restart)). Next:
[The Splunk agent is late or stopped](#the-splunk-agent-is-late-or-stopped).

### Possible deliberate blinding

Someone may be hiding activity. Do these in order:

1. **Escalate.** Tell the lab owner (in this lab: Taylor). Save the evidence before you fix
   anything:
   - The result of the `dh_tamper` search in step 2.
   - The marker search below, with the same `<host>`.
   - A screenshot of the Overview.

   In Splunk Web, in the HL Data Health app, the marker search is:

   ```
   index=data_health source=dh:marker target_host=<host> | table _time action by run_id
   ```

2. **Read the finding.** Use the Overview's tamper panel and Host detail's tamper events. Or search
   in Splunk Web, in the HL Data Health app:

   ```
   | inputlookup dh_tamper | search host=<host> | table time code indicator detail suppressed
   ```

   `host` here is the host's short name in lowercase, as the Overview shows it. `suppressed` is `1`
   when an Ansible marker covers the finding, so it was the role's own work. Any other value means no
   marker covers it.
3. **Don't expect a role run to hide it.** The run's marker comes after the indicator, and the app
   decides suppression once ([why](data-health-design.md#tamper-indicators)).
4. **If the indicator is Cribl's own,** undo the edit in Cribl. An example is
   `Cribl pipelines update (pl_test_block) by admin`. The `cribl` tag doesn't revert edits made in
   Cribl. Follow [the steps to undo an edit in Cribl](running-the-role.md#cribl-doesnt-undo-edits-made-in-cribl).
   They give the login, the repo's copy to compare with, and the `cribl` run to finish with.
   The [fault-injection run](records/2026-11-fault-injection-run.md) saw that run fail on an added
   route.

### Cribl is down

Check the container. On HOMEPC, in PowerShell, any folder:

```powershell
docker ps --filter name=cribl
docker logs --tail 50 cribl
```

A healthy `docker ps` line shows `Up` in its status and the name `cribl`. If the line is missing or
says `Exited`, pick one option:

1. **Start it with Docker.** On HOMEPC, in PowerShell, any folder:

   ```powershell
   docker start cribl
   ```

2. **Let the role start it.** The `cribl` tag runs `docker compose up -d`, so it starts a stopped
   container. Then check the result. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags cribl --limit homepc
   ansible-playbook site.yml --tags verify --limit homepc
   ```

   A good `verify` ends with `failed=0`.

If Cribl stays down, keep the last 50 log lines from `docker logs`. Send them to the lab owner.

### Device problems

These causes are for a device with no Splunk agent, such as the UDM. pi5's probe pings the device
every 60 s and writes one line per ping. A good line has `reachable=1`. A bad line has `reachable=0`
and no `rtt_ms`. These two are examples:

```
time=2026-11-14T10:00:01.123Z device=udm ip=192.168.1.1 reachable=1 rtt_ms=0.8
time=2026-11-14T10:01:01.145Z device=udm ip=192.168.1.1 reachable=0 rtt_ms=
```

- **The device doesn't answer the probe.** Look for `reachable=0` in the probe's log. On pi5, any
  folder:

  ```bash
  tail -3 /var/log/hl-devprobe/probe.log
  ```

  If the device is off, check its power and network.

- **The probe stopped reporting.** The device may be fine. The cause shows on the device's host row.
  It can also show on pi5's `hl:devprobe` row while pi5's heartbeat is OK. Type
  `hl:devprobe` in the Overview's *Search text* filter to find it. On pi5, any folder:

  ```bash
  systemctl status hl-devprobe.timer
  tail -3 /var/log/hl-devprobe/probe.log
  ```

  If pi5 itself is DOWN, fix that first. The probe's file travels on pi5's UF. Then restore the
  probe. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

  ```bash
  ansible-playbook site.yml --tags probe --limit pi5
  ```

- **The device answers but sends no logs.** Its logging settings probably changed. In this lab,
  check the UniFi UI: remote syslog goes to `192.168.1.27`, port `5514`, UDP
  ([setup step 8](running-the-role.md#step-8-point-the-udms-syslog-at-homepc)).

- **Nothing at all, or everything late, from a host with no agent.** Check that the host is on and
  that its syslog path is intact. For the UDM, that means its remote syslog setting, the network, and
  HOMEPC's UDP port 5514. For a device the probe pings, also read the probe lines above.

### The Splunk agent is late or stopped

Read the agent's state first. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags status --limit <host>
```

The output's `last_connect` shows when the agent last connected. A UF logs a connection every 30 s.
The UF's heartbeat limit is 90 s ([profiles](data-health-design.md#the-five-ideas)). So a
`last_connect` more than 90 s old means the agent isn't connected.

- **Late (not yet missing).** It usually passes. If it doesn't, check the network path from the host
  to port 9997 on HOMEPC.
- **Stopped reporting.** Check that the host is up. For a Linux host, on pi5, in
  `~/homelab-splunk-missing-source/ansible`, venv on:

  ```bash
  ansible <host> -m ansible.builtin.ping
  ```

  For HOMEPC, use `-m ansible.windows.win_ping` instead.

  If the host answers and the agent is down, start it:

  ```bash
  ansible-playbook site.yml --tags start --limit <host>
  ```

  Once the agent is back, find who stopped it. Follow the steps for the host's OS.

**On Linux,** search in Splunk Web, in the HL Data Health app:

```
index=linux host=<host> sourcetype=linux_audit SERVICE_STOP SplunkForwarder
```

Then find the person. Sudo writes a `USER_CMD` record for each command. Its `auid` is the ID of the
user who logged in. Search the minutes around the stop time:

```
index=linux host=<host> sourcetype=linux_audit USER_CMD
```

**On Windows,** use the steps for your Windows type:

1. On Windows Server, look for event 7036 in the System log. In Splunk Web, in the HL Data Health app:

   ```
   index=windows host=<host> source="XmlWinEventLog:System" 7036
   ```

2. Desktop Windows doesn't log 7036 (in this lab: HOMEPC). There, search `_internal` instead:

   ```
   index=_internal host=<host> "Shutting down splunkd"
   ```

3. That line often arrives only when the UF starts again. So wait for the UF to come back before you
   search.

### The agent works but an input is missing

The heartbeat is fine, so look at the input. Open Host detail →
[Latest Splunk agent errors and warnings](data-health/dashboards.md#latest-splunk-agent-errors-and-warnings-24-h).

- **This input never sent anything.** Check its settings on the host. Run `btool` as `splunkfwd`,
  never as root. On pi5 you are on the host already. For a VM, ask the lab owner (in this lab: Taylor)
  for a shell on it. On the Linux host, any folder:

  ```bash
  sudo -u splunkfwd /opt/splunkforwarder/bin/splunk btool inputs list <stanza> --debug
  ```

  `<stanza>` is an `inputs.conf` stanza, such as `monitor:///var/log/secure`. In the output, read:
  - **`disabled`:** `disabled = 1` means the input is off.
  - **`index`:** a wrong index sends the data where the app doesn't look.
  - **`sourcetype`:** a wrong sourcetype makes the data a different item.
  - **The file path** at the start of each line. It shows which app set the value. A `local/` file
    beats a `default/` file.
  - **A missing stanza:** the input isn't deployed.

  If the stanza is missing or differs from the repo, redeploy the apps. Redeploying won't fix a file
  the agent can't read. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

  ```bash
  ansible-playbook site.yml --tags apps --limit <host>
  ```

- **No data at all.** Open Manage → Test blocks to look for a block that drops this host. Then check
  the agent's apps. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

  ```bash
  ansible-playbook site.yml --tags status --limit <host>
  ```

  Read the `apps` line. If an app is missing, redeploy the apps:

  ```bash
  ansible-playbook site.yml --tags apps --limit <host>
  ```

- **This input stopped.** Its file may be unreadable, moved or rotated. Or auditd, rsyslog or the
  audit rules may have stopped. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

  ```bash
  ansible <host> -b -m command -a 'auditctl -s'
  ansible <host> -m command -a 'systemctl status auditd rsyslog'
  ```

  A stopped service makes Ansible print `FAILED` with return code 3. Read the output below it. Fix
  the input, then run one of these:

  ```bash
  ansible-playbook site.yml --tags apps --limit <host>
  ansible-playbook site.yml --tags audit_rules --limit <host>
  ```

### This stream stopped

Only one stream stopped, and the host still sends others. Find the program that writes the stream,
and check that it runs. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible <host> -m command -a 'systemctl status <service>'
```

`<service>` is the program's service name. For `enclave1` rows, the program is [wd2l](glossary.md#wd2l).
Tell the lab owner (in this lab: Taylor).

### Retire a row that never arrived

A row can reach this cause only on a host with neither a UF nor a probe. Remove the row, or retire it:

- **A row from Ansible** (a `dh_extra_expected` row): remove it from `dh_extra_expected` in
  `ansible/inventory/group_vars/splunk_server.yml`. [Sync the repo](running-the-role.md#after-you-change-the-repo).
  Then, on pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

  ```bash
  ansible-playbook site.yml --tags expected --limit homepc
  ```

- **Any row, including one from Ansible:** retire it on Manage → Expected list → *Retire an expected
  item*. The retirement holds until the inventory drops the row
  ([Retiring a host](running-the-role.md#retiring-a-host)).
- **A row added on Manage:** retire it there.

Don't use `hl_disabled_inputs` for this. It only filters a UF's input stanzas, so it never touches
these rows.

## Known gaps

The known gaps are in data-health-design.md:

- [How long each status takes to show](data-health-design.md#how-long-until-late-missing-or-down).
- [The limits of the Cribl causes](data-health-design.md#cribl-as-the-relay).
- [Which tamper findings count, and when a marker hides one](data-health-design.md#tamper-indicators).

## Before planned maintenance

- **Mute first.** Open Manage → Mute & thresholds. A reason and an expiry of 30 days or less are
  required. A host mute covers all its items.
- **Use the role for stops and starts.** Its markers make the Overview say "Stopped with Ansible".
  They also keep the role's own changes from counting as tampering.
- **Retire a host that is gone for good.** See
  [Retiring a host](running-the-role.md#retiring-a-host).

## After an incident

- Open *Daily state of health*
  ([guide](data-health/dashboards.md#daily-state-of-health)). It lists outages with their durations
  and mean time to restore (MTTR). It also lists flapping items, never-seen and unregistered data,
  and UFs off the expected version.
- The same page covers lag p95 (slow arrival), volume flags, licence usage, skipped searches and
  expiring mutes.
- The status changes are in `index=data_health source=dh:transition`. Search it for any timeline you
  need.
- Raw data, status changes and markers are kept 14 days.
