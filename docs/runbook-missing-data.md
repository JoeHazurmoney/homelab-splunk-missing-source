# Runbook: something is missing

Start on the **Overview** of the HL Data Health app. Each row of *Needs attention* is a host with its
worst item, the **Cause** and the **Action**. Click a row to open **Host detail**. This page covers
each cause: what it means, what to check first, and what to do.

Before you start:

- A command with `--tags …` is an `ansible-playbook site.yml` run. Run it on pi5, as
  [How to run a command](running-the-role.md#how-to-run-a-command) says.
- Run searches in the HL Data Health app, and don't use `punct`
  ([Searching](running-the-role.md#searching)).
- Never run the `splunk` CLI as root on a UF
  ([why](running-the-role.md#never-run-splunk-as-root-on-a-uf)).
- The Cause column shows times in the scheduler's time zone, not yours. In this lab that is UTC, so
  the text says `GMT`.

**Read the banner first.** If it says *On hold*, every status is PENDING on purpose, and no alert
fires. Fix what the banner names before you look at single rows.

## Causes, in the order the app checks them

The first cause that fits wins. `<…>` marks the parts the app fills in. The commands for each cause
are in [Steps for each cause](#steps-for-each-cause).

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
| **Possible deliberate blinding: `<indicator>` at `<time>` just before the data stopped** | A tamper indicator came within 15 min of the silence. No Ansible marker covers it. | **Escalate.** Keep the evidence before you fix anything. [Steps](#possible-deliberate-blinding). |
| **Cribl DOWN: the real state is unknown (this data passes through Cribl and Cribl is not reporting)** | Everything collected goes through Cribl, and Cribl isn't reporting. The data itself may be fine. | Check the Cribl container, then fix Cribl. [Steps](#cribl-is-down). |
| **The relay `<via>` is DOWN: this data comes through it so its real state is unknown** | Another relay host that carries this data is down. | Look at that host's row. Fix the relay first. |
| **The device does not answer the network probe: the device or its network is down** | The device doesn't answer pi5's ping. | Check the device's power and network. [Steps](#device-problems). |
| **The device probe (hl-devprobe on pi5) stopped reporting on this device** | The probe stopped. The device may be fine. | Check the probe on pi5. [Steps](#device-problems). |
| **The device answers the network probe but sends no logs: its logging settings probably changed** | The device is up, but its syslog doesn't arrive. | Fix the device's remote syslog setting. [Steps](#device-problems). |
| **The Splunk agent reports late (not yet missing): the agent is busy or stopping or its network path to Cribl (port 9997) is slow** | The heartbeat is slow, but not yet missing. | Usually it passes. If not, check the path to port 9997. [Steps](#the-splunk-agent-is-late-or-stopped). |
| **The Splunk agent stopped reporting: the host is down or cut off from Cribl (port 9997) or the agent crashed or was stopped outside Ansible** | There is no heartbeat. | Check the host, then start the agent. [Steps](#the-splunk-agent-is-late-or-stopped). |
| **The Splunk agent works but this input has never sent anything: input not enabled or wrong index or sourcetype or no permission to read it** | The agent works, but this input never delivered. | Check the input's settings, then redeploy the apps. [Steps](#the-agent-works-but-an-input-is-missing). |
| **The Splunk agent works but sends no data at all: its apps or inputs were removed or it cannot forward or a test block drops it** | The heartbeat is fine, but every stream stopped. | Check for test blocks, then redeploy the apps. [Steps](#the-agent-works-but-an-input-is-missing). |
| **The Splunk agent works but this input stopped: its file is unreadable or was moved or rotated or auditd or rsyslog stopped or audit rules were removed** | One stream stopped while the host still sends others. | Find out why the input stopped, then fix it. [Steps](#the-agent-works-but-an-input-is-missing). |
| **Cribl DOWN: nothing from Cribl itself so every collected stream is unknown** | This is the `cribl` row. Its workers' own logs stopped. | As for *Cribl DOWN* above. |
| **Nothing at all from this host (it has no Splunk agent): the host is down or its syslog path is broken** | A host without an agent sends nothing. | Check the host and its syslog path. |
| **Never arrived since it was added: the input is not deployed or not sending** | An expected item on a host without an agent has never arrived. | Check that it is deployed. Deploy it, or [retire the row](#retire-a-row-that-never-arrived). |
| **Cribl late: nothing recent from Cribl itself (not yet DOWN) so collected streams may soon be unknown** | This is the `cribl` row while its own logs are late. It lasts about 2 min before *Cribl DOWN*. | As for *Cribl DOWN* above. |
| **Everything from this host is late (not yet missing; it has no Splunk agent): the host or its syslog path is slow or stopping** | Every stream of a host without an agent is late. None is missing yet. | Check the host and its syslog path. |
| **Everything from this host is late or missing (it has no Splunk agent): the host or its syslog path is slow or stopping** | Every stream of a host without an agent is late. Some are already missing. | Check the host and its syslog path. |
| **This stream stopped while the host still sends others: its program or input stopped** | Only this stream stopped. For `enclave1` rows, that means wd2l's delivery. | Check the program behind the stream. |

## Steps for each cause

### On hold: the tracker or Splunk

Two causes put the whole app on hold. The banner names the one that applies.

**The tracker isn't running.** Check whether the search runs or Splunk skips it. In this lab, a skip
usually means WSL2 (the Linux layer Docker Desktop runs on) is short of CPU. In Splunk Web, in the
HL Data Health app:

```
index=_internal sourcetype=scheduler savedsearch_name="DH Tracker fast" earliest=-15m | stats count by status
```

Enable the search if it is off. If Splunk skips it, find out why.

**Splunk isn't receiving.** Check the Splunk container and its HEC health. On HOMEPC, in PowerShell,
any folder:

```powershell
docker ps --filter name=wd2l-splunk
curl.exe -sk https://127.0.0.1:8088/services/collector/health
```

Also check that Splunk listens on port 9997 on the `hl-net` Docker network. Cribl delivers
everything it collects there. Then get the container running and receiving.

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

Then start the UF. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags start --limit <host>
```

`<host>` is the host's inventory name, such as `wd2l-recv`.

**If the start fails,** the `start` marker posted before it becomes the host's last marker. The
cause then moves to a general Splunk agent cause
([details](running-the-role.md#stop-start-and-restart)).

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

**If the install fails,** the `install` marker posted before it becomes the host's last marker. The
cause then moves to a general Splunk agent cause
([details](running-the-role.md#stop-start-and-restart)).

### Possible deliberate blinding

Someone may be hiding activity. Do these in order:

1. **Escalate.** Keep the evidence before you fix anything.
2. **Read the finding.** Use the Overview's tamper panel and Host detail's tamper events. Or search
   in Splunk Web, in the HL Data Health app:

   ```
   | inputlookup dh_tamper | search host=<host> | table time code indicator detail suppressed
   ```

3. **Don't expect a role run to hide it.** The run's marker comes after the indicator, and the app
   decides suppression once ([why](data-health-design.md#tamper-indicators)).
4. **If the indicator is Cribl's own,** undo the edit in Cribl. An example is
   `Cribl pipelines update (pl_test_block) by admin`. The `cribl` tag doesn't revert edits made in
   Cribl, so use Cribl's UI and fix the object the indicator names. In this lab, the UI is
   `http://127.0.0.1:9000` on HOMEPC.
5. **Then run `cribl` until it passes.** On pi5, in `~/homelab-splunk-missing-source/ansible`, venv
   on:

   ```bash
   ansible-playbook site.yml --tags cribl --limit homepc
   ```

   Its load check fails while Cribl's route list differs from the repo's. The
   [fault-injection run](records/2026-11-fault-injection-run.md) saw this with an added route. The
   check only confirms that the role's objects exist, so an edit inside a pipeline passes it
   ([details](running-the-role.md#cribl-doesnt-undo-edits-made-in-cribl)).

### Cribl is down

Check the container. On HOMEPC, in PowerShell, any folder:

```powershell
docker ps --filter name=cribl
docker logs --tail 50 cribl
```

If the container is stopped, start it. On HOMEPC, in PowerShell, any folder:

```powershell
docker start cribl
```

Or let the role start it, then check the result. On pi5, in
`~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags cribl --limit homepc
ansible-playbook site.yml --tags verify --limit homepc
```

### Device problems

These causes are for a device with no Splunk agent, such as the UDM. pi5's probe pings the device
every 60 s.

- **The device doesn't answer the probe.** Look for `reachable=0` in the probe's log. On pi5, any
  folder:

  ```bash
  tail -3 /var/log/hl-devprobe/probe.log
  ```

  If the device is off, check its power and network.

- **The probe stopped reporting.** The device may be fine. The cause shows on the device's host row,
  or on pi5's `hl:devprobe` row while pi5's heartbeat is OK. On pi5, any folder:

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
  check the UniFi UI: remote syslog goes to `192.168.1.27`, port `5514`, UDP.

### The Splunk agent is late or stopped

Read the agent's state first. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags status --limit <host>
```

The output's `last_connect` shows when the agent last connected.

- **Late (not yet missing).** It usually passes. If it doesn't, check the network path from the host
  to port 9997 on HOMEPC.
- **Stopped reporting.** Ping the host or SSH to it. If the agent is down, start it:

  ```bash
  ansible-playbook site.yml --tags start --limit <host>
  ```

  Once the agent is back, find who stopped it. On Linux, search in Splunk Web, in the HL Data Health
  app:

  ```
  index=linux host=<host> sourcetype=linux_audit SERVICE_STOP SplunkForwarder
  ```

  The person's `auid` is on sudo's `USER_CMD` record. On Windows, look for event 7036 in
  `source="XmlWinEventLog:System"`.

### The agent works but an input is missing

The heartbeat is fine, so look at the input. Open Host detail → latest agent errors for it.

- **This input never sent anything.** Check its settings on the host. On the Linux host, any folder:

  ```bash
  sudo -u splunkfwd /opt/splunkforwarder/bin/splunk btool inputs list <stanza> --debug
  ```

  `<stanza>` is an `inputs.conf` stanza, such as `monitor:///var/log/secure`. Run it as
  `splunkfwd`, never as root. Then redeploy the apps. On pi5, in
  `~/homelab-splunk-missing-source/ansible`, venv on:

  ```bash
  ansible-playbook site.yml --tags apps --limit <host>
  ```

- **No data at all.** Open Manage → Test blocks to look for a block that drops this host. Check the
  agent's apps with `--tags status --limit <host>` (the `apps` line). Then redeploy the apps with
  the command above.
- **This input stopped.** Its file may be unreadable, moved or rotated. Or auditd, rsyslog or the
  audit rules may have stopped. On the host, any folder:

  ```bash
  sudo auditctl -s
  systemctl status auditd rsyslog
  ```

  Fix the input, then run `--tags apps --limit <host>` or `--tags audit_rules --limit <host>`.

### Retire a row that never arrived

Turn the input off with `hl_disabled_inputs`
([Turning things off](running-the-role.md#turning-things-off)). For a row added on Manage, retire it
there.

## Known limits

The limits are in data-health-design.md:

- [How long each status takes to show](data-health-design.md#how-long-until-late-missing-or-down).
- [The limits of the Cribl causes](data-health-design.md#cribl-as-the-relay).
- [Which tamper findings count, and when a marker hides one](data-health-design.md#tamper-indicators).

## Planned work

- **Mute first.** Open Manage → Mute & thresholds. A reason and an expiry of 30 days or less are
  required. A host mute covers all its items.
- **Use the role for stops and starts.** Its markers make the Overview say "Stopped with Ansible".
  They also keep the role's own changes from counting as tampering.
- **A host that is gone for good:** retire it ([Retiring a host](running-the-role.md#retiring-a-host)).

## After an incident

- *Daily state of health* lists outages with their durations and mean time to restore (MTTR). It
  also lists flapping items, never-seen and unregistered data, and UFs off the expected version.
  Other lines cover lag p95, volume flags, licence usage, skipped searches and expiring mutes.
- The status changes are in `index=data_health source=dh:transition`. Search it for any timeline you
  need.
- Raw data, status changes and markers are kept 14 days.
