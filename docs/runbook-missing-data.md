# Runbook: something is missing

Start on the **Overview**. Each row of *Needs attention* is a host with its worst child, the
**Cause** and the **Action**. Click it for **Host detail**. This page expands each cause: what it
means, what to check, and the command. Commands run from `ansible/` on pi5.

**Read the banner first.** If it says *On hold*, every status is PENDING on purpose, and no alert
fires. Fix what the banner names (a tracker not running, Splunk not receiving, or a resume after sleep)
before looking at single rows.

## Causes, in the order the app checks them

| Cause (as shown) | What it means | Check | Do |
|---|---|---|---|
| **Test block until …** | a test is dropping this data in Cribl on purpose | Manage → Test blocks → Current test blocks | `--tags cribl_block -e "hl_block_key='<key>'" -e hl_block_clear=true` when the test is over |
| **Stopped with Ansible at … by …** | the role stopped the UF (`--tags stop`) and nothing started it again | `index=data_health source=dh:marker target_host=<host>` | `--tags start --limit <host>` |
| **The VM is off: Hyper-V event …** | Hyper-V says the VM was turned off, shut down or saved | Hyper-V Manager | start the VM, or mute the host while it's meant to be off |
| **Possible deliberate blinding: …** | a tamper indicator (log cleared, audit policy changed, service stopped, Cribl config changed …) happened just before the data stopped, outside any Ansible marker | the Overview's tamper panel; Host detail's tamper events | **escalate**; don't "fix" it first, preserve the evidence |
| **Cribl DOWN: the real state is unknown** | everything collected goes through Cribl, and Cribl isn't reporting; the data may be fine | `docker ps --filter name=cribl` on HOMEPC; Cribl UI `http://127.0.0.1:9000` | `docker start cribl`, or `--tags cribl --limit homepc`; then `--tags verify --limit homepc` |
| **The relay … is DOWN** | another relay host this data comes through is down | that host's row | fix the relay first |
| **The device does not answer the network probe** | the device (UDM) doesn't answer pi5's ping | the device's power and network | — |
| **The device probe (hl-devprobe on pi5) stopped reporting** | the probe itself stopped; the device may be fine | on pi5: `systemctl status hl-devprobe.timer`; `tail /var/log/hl-devprobe/probe.log` | `--tags probe --limit pi5` |
| **The device answers the network probe but sends no logs** | the device is up, but its remote syslog changed | the UniFi UI: remote syslog → `192.168.1.27:5514/udp` | fix the setting |
| **The Splunk agent reports late** | the heartbeat is slow, not yet missing | `--tags status --limit <host>` (last connect) | usually transient; check the path from the host to Cribl's 9997 |
| **The Splunk agent stopped reporting** | no heartbeat: the host is down, cut off from Cribl, the UF crashed, or someone stopped it outside Ansible | ping/SSH; `--tags status --limit <host>`; once the UF is back, the shutdown lines and auditd `SERVICE_STOP` (with the auid) show who stopped it | `--tags start --limit <host>` |
| **… has never sent anything** | the agent works, but this input never delivered | on the host: `splunk btool inputs list <stanza> --debug`; Host detail → latest agent errors | `--tags apps --limit <host>` |
| **… sends no data at all** | the heartbeat is fine, but every stream stopped: apps removed, outputs broken, or a test block | Host detail; Manage → Test blocks | `--tags apps --limit <host>` |
| **… this input stopped** | one stream stopped while the host still sends others: the file is unreadable or moved, auditd or rsyslog stopped, audit rules removed | Host detail → latest agent errors for that path; `auditctl -s`; `systemctl status rsyslog` | fix the input; `--tags apps` or `--tags audit_rules` |
| **Never arrived since it was added** | an expected entity has never arrived | is it deployed? | deploy it, or retire the row |
| **Nothing at all from this host** | an agentless host sends nothing | the host and its syslog path | — |
| **This stream stopped while the host still sends others** | as it says | the program behind the stream | — |

## Planned work

- **Mute** first (Manage → Mute & thresholds: a reason and an expiry ≤ 30 days are required). A host
  mute covers its children.
- Use the role for stops and starts. Its markers make the Overview say "Stopped with Ansible", and
  they keep the role's own changes from counting as tampering.

## After an incident

- *Daily state of health* lists outages with their durations and MTTR, flapping entities, never-seen
  and unregistered data, forwarders off the expected version, lag p95, volume flags, licence usage,
  skipped searches and expiring mutes.
- The transitions are in `index=data_health source=dh:transition` for any timeline you need.
