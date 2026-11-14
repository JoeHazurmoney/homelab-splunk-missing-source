# Runbook: something is missing

Start on the **Overview** of the HL Data Health app. Each row of *Needs attention* is a host with its
worst child, the **Cause** and the **Action**. Click it for **Host detail**. This page expands each
cause: what it means, what to check first, and what to do.

- `--tags …` commands are `ansible-playbook site.yml --tags …`, run from `ansible/` on pi5
  ([running-the-role.md](running-the-role.md)).
- Run searches in the HL Data Health app. `dh_*` lookups are invisible from other apps and read as
  empty, without an error. Cribl-delivered events have no `punct` field, so don't `dedup punct`.
- **Never run the `splunk` CLI as root on a UF.** `sudo splunk …` runs `chown -R` over
  `/opt/splunkforwarder` and raises a false `hl-uf-config` tamper finding. Use
  `sudo -u splunkfwd /opt/splunkforwarder/bin/splunk …`.

**Read the banner first.** If it says *On hold*, every status is PENDING on purpose, and no alert
fires. Fix what the banner names before looking at single rows.

## Causes, in the order the app checks them

The first cause that fits wins. `<…>` marks the parts the app fills in.

| Cause (as shown) | What it means | Check first | Do |
|---|---|---|---|
| **On hold: the arrival tracker (DH Tracker fast) has not run for `<n>` s**, or **On hold: the arrival tracker (DH Tracker fast) has never run** | the tracker that records arrivals isn't running, so nothing can be judged | `index=_internal sourcetype=scheduler savedsearch_name="DH Tracker fast" earliest=-15m \| stats count by status` | enable the search, or find why it is skipped (WSL2 short of CPU) |
| **On hold: Splunk has indexed nothing for `<n>` s**, or **On hold: Splunk has indexed nothing yet** | everything went quiet at once: a Splunk problem, not a host problem | `docker ps --filter name=wd2l-splunk` on HOMEPC; HEC: `curl -sk https://127.0.0.1:8088/services/collector/health` | get the container running and receiving |
| **On hold: catching up after a pause (sleep or restart) at `<time>`; statuses held for 5 min** | the PC slept or Splunk restarted | — | wait 5 min |
| **Muted until `<time>`: `<reason>`** (or "no reason given") | muted on Manage | Manage → Mute & thresholds | nothing while muted |
| **Added less than 1 h ago: waiting for its first data** | newly expected, not yet seen | — | wait up to 1 h |
| **Test block until `<time>` (data dropped on purpose): `<reason>`** | a test is dropping this data in Cribl | Manage → Test blocks → Current test blocks | when the test is over: `--tags cribl_block --limit homepc -e hl_block_key='<key>' -e hl_block_clear=true` |
| **Stopped with Ansible at `<time>` by `<user>` and not started again** | the role stopped the UF (`--tags stop`) and nothing started it again | `index=data_health source=dh:marker target_host=<host> \| table _time action by run_id` | `--tags start --limit <host>` |
| **Uninstalled with Ansible at `<time>` by `<user>` and not installed again** | the role removed the UF (`--tags uninstall`) and nothing installed it again; the host stays expected on purpose | `index=data_health source=dh:marker target_host=<host> action=uninstall` | install it again (`--tags install,apps,audit_rules --limit <host>`), or retire its rows: `hl_expected: false` in its `host_vars`, then `--tags expected --limit homepc` |
| **The VM is off: Hyper-V event `<id>` (`<turned off \| shut down by the host \| shut down by the guest OS \| saved>`) at `<time>`** | Hyper-V says the VM was turned off, shut down or saved | Hyper-V Manager on HOMEPC | start the VM, or mute the host while it's meant to be off |
| **Possible deliberate blinding: `<indicator>` at `<time>` just before the data stopped** | a tamper indicator happened within 15 min of the silence, outside any Ansible marker for that host. For data through Cribl the indicator can be Cribl's own, for example `Cribl pipelines update (pl_test_block) by admin` | the Overview's tamper panel; Host detail's tamper events; `\| inputlookup dh_tamper \| search host=<host> \| table time code indicator detail suppressed` | **escalate**; preserve the evidence before fixing anything. A role run afterwards doesn't hide the finding: its marker comes after the indicator, and a finding's suppression is decided once. A `--tags cribl` run doesn't revert an edit made in Cribl's UI, so check the named object at `http://127.0.0.1:9000` on HOMEPC and undo the edit there; then `--tags cribl --limit homepc` must pass (its load check fails while Cribl's route list differs from the repo's, as task 14 row 11 showed; it checks only that the role's inputs, outputs and pipelines exist, so an edit inside a pipeline passes it) |
| **Cribl DOWN: the real state is unknown (this data passes through Cribl and Cribl is not reporting)** | everything collected goes through Cribl, and Cribl isn't reporting; the data may be fine | `docker ps --filter name=cribl` on HOMEPC; `docker logs --tail 50 cribl` | `docker start cribl`, or `--tags cribl --limit homepc`; then `--tags verify --limit homepc` |
| **The relay `<via>` is DOWN: this data comes through it so its real state is unknown** | another relay host this data comes through is down | that host's row | fix the relay first |
| **The device does not answer the network probe: the device or its network is down** | the device doesn't answer pi5's ping | on pi5: `tail -3 /var/log/hl-devprobe/probe.log` (`reachable=0`) | check the device's power and network |
| **The device probe (hl-devprobe on pi5) stopped reporting on this device** | the probe stopped; the device may be fine. Shows on the device's host row, or on pi5's `hl:devprobe` row while pi5's heartbeat is OK | on pi5: `systemctl status hl-devprobe.timer`; `tail -3 /var/log/hl-devprobe/probe.log`. If pi5 itself is DOWN, fix that first: the probe's file rides on pi5's UF | `--tags probe --limit pi5` |
| **The device answers the network probe but sends no logs: its logging settings probably changed** | the device is up, but its syslog doesn't arrive | the UniFi UI: remote syslog to `192.168.1.27`, port `5514`, UDP | fix the setting |
| **The Splunk agent reports late (not yet missing): the agent is busy or stopping or its network path to Cribl (port 9997) is slow** | the heartbeat is slow, not yet missing | `--tags status --limit <host>` (`last_connect`) | usually transient; check the path from the host to HOMEPC's 9997 |
| **The Splunk agent stopped reporting: the host is down or cut off from Cribl (port 9997) or the agent crashed or was stopped outside Ansible** | no heartbeat | ping or SSH; `--tags status --limit <host>`. Once the UF is back, who stopped it: `index=linux host=<host> sourcetype=linux_audit SERVICE_STOP SplunkForwarder` (the person's auid is on sudo's `USER_CMD` record), or Windows event 7036 in `source="XmlWinEventLog:System"` | `--tags start --limit <host>` |
| **The Splunk agent works but this input has never sent anything: input not enabled or wrong index or sourcetype or no permission to read it** | the agent works, but this input never delivered | Host detail → latest agent errors; on a Linux host: `sudo -u splunkfwd /opt/splunkforwarder/bin/splunk btool inputs list <stanza> --debug` | `--tags apps --limit <host>` |
| **The Splunk agent works but sends no data at all: its apps or inputs were removed or it cannot forward or a test block drops it** | the heartbeat is fine, but every stream stopped | Manage → Test blocks; `--tags status --limit <host>` (`apps`) | `--tags apps --limit <host>` |
| **The Splunk agent works but this input stopped: its file is unreadable or was moved or rotated or auditd or rsyslog stopped or audit rules were removed** | one stream stopped while the host still sends others | Host detail → latest agent errors for that path; on the host: `sudo auditctl -s`, `systemctl status auditd rsyslog` | fix the input; `--tags apps --limit <host>` or `--tags audit_rules --limit <host>` |
| **Cribl DOWN: nothing from Cribl itself so every collected stream is unknown** | the `cribl` row: its workers' own logs stopped | as for "Cribl DOWN" above | as for "Cribl DOWN" above |
| **Nothing at all from this host (it has no Splunk agent): the host is down or its syslog path is broken** | an agentless host sends nothing | the host and its syslog path | — |
| **Never arrived since it was added: the input is not deployed or not sending** | an expected entity has never arrived | is it deployed? | deploy it, or retire the row (`hl_disabled_inputs`, or Manage for a row added there) |
| **Cribl late: nothing recent from Cribl itself (not yet DOWN) so collected streams may soon be unknown** | the `cribl` row while its own logs are late but not yet missing: the 2 minutes before "Cribl DOWN" | as for "Cribl DOWN" above | as for "Cribl DOWN" above |
| **Everything from this host is late (not yet missing; it has no Splunk agent): the host or its syslog path is slow or stopping** | every stream of an agentless host is late, none missing yet | the host and its syslog path | — |
| **This stream stopped while the host still sends others: its program or input stopped** | as it says; for `enclave1` rows, wd2l's delivery | the program behind the stream | — |

## Known limits

- "Cribl DOWN" appears about 5–6 min after Cribl stops. Until then the UF host rows read "The Splunk
  agent stopped reporting".
- On a `via=cribl` row, a tamper finding within 15 min of a Cribl outage reads as tamper, not
  "Cribl DOWN".
- A marker for the row's own host within 15 min silences a Cribl tamper finding for that row.
- On EL10, `systemctl stop auditd` is refused; `service auditd stop` works and logs `DAEMON_END`
  (with the auid), not `SERVICE_STOP`.

## Planned work

- **Mute** first (Manage → Mute & thresholds: a reason and an expiry ≤ 30 days are required). A host
  mute covers its children.
- Use the role for stops and starts. Its markers make the Overview say "Stopped with Ansible", and
  they keep the role's own changes from counting as tampering.
- A host that is gone for good: `uninstall`, then retire its rows with `hl_expected: false` and
  `--tags expected --limit homepc` ([running-the-role.md §4](running-the-role.md#4-removing-things-all-never)).

## After an incident

- *Daily state of health* lists outages with their durations and MTTR, flapping entities, never-seen
  and unregistered data, forwarders off the expected version, lag p95, volume flags, licence usage,
  skipped searches and expiring mutes.
- The transitions are in `index=data_health source=dh:transition` for any timeline you need.
- Raw data, transitions and markers are kept 14 days.
