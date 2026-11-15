# Glossary

These are the words the docs use that a Splunk Core Certified User may not know. Core Splunk words
(index, sourcetype, source, host, lookup, report, alert, dashboard) are not here.

Values marked "In this lab" are this lab's. Change them for yours.

## Splunk admin words

### Universal Forwarder (UF)
The Splunk agent: a small Splunk program on a host. It reads the host's logs and sends them on.
The docs say "Splunk agent (UF)" the first time, then "UF". Here every UF sends to Cribl, not
straight to Splunk.

### Add-on (TA)
A Splunk app that knows how to collect and parse one kind of data. This lab uses
`Splunk_TA_nix` (Linux) and `Splunk_TA_windows` (Windows). The role deploys them unchanged and
puts its own settings in their `local/` folder.

### HEC (HTTP Event Collector)
A way to send events straight to Splunk over HTTPS, without a UF. It listens on port 8088. In
this lab, wd2l and the Ansible markers use it, so they don't pass through Cribl.

### S2S (splunktcp)
The protocol a UF uses to send data, on port 9997. Here each sender must show a secret token.
The UFs send S2S to Cribl, and Cribl sends S2S on to Splunk.

### KV store
A small database inside Splunk. An app keeps tables in it, called collections, and reads them as
lookups. The data-health app keeps its expected list, statuses, mutes and findings there.

### `btool`
A Splunk command that shows the settings Splunk really uses, merged from every app, and which file
each one came from. On a UF, run it as the UF's own user, never as root
([why](running-the-role.md#never-run-splunk-as-root-on-a-uf)).

### `inputs.conf`, `props.conf`
Splunk settings files. `inputs.conf` says what to collect. `props.conf` says how to parse it.
An app's `local/` settings win over its `default/` settings.

### App deployment and restarts
Putting an app's files into Splunk. Some changes need splunkd to restart. Others need only a reload.
The role restarts splunkd only when it must ([costs](running-the-role.md#costs-of-a-run)).

## Words from outside Splunk

### Ansible
A tool that sets up hosts from a central machine over SSH. Its code says how each host should
look, and Ansible makes it so. In this lab it runs on pi5.

### Playbook, role
A playbook is the file you run (`site.yml`). A role is a packaged set of tasks. Here one role,
`homelab_splunk`, does all the work.

### Inventory, `host_vars`, `group_vars`
The inventory lists the hosts and their groups. `host_vars` and `group_vars` hold settings for one
host or one group.

### Tags, `never`
A tag picks which part of the role runs, for example `--tags stop`. A task tagged `never` runs only
when you ask for its tag by name. So a plain run never removes, stops or restarts anything.

### `--limit`
Runs the play on only some hosts, for example `--limit wd2l-recv`.

### Vault
An encrypted file of secrets, opened with a password. Here it is
`inventory/group_vars/all/vault.yml` on pi5 ([secrets](running-the-role.md#secrets)).

### Cribl Stream
A program that sits between senders and Splunk. It receives data, can change or drop it, and sends
it on. In this lab, everything collected passes through it
([architecture](architecture.md#inside-cribl)).

### Worker
One Cribl process that handles data. In this lab Cribl runs 2 workers. Each worker logs about itself
every minute.

### Source, destination (Cribl)
Where Cribl receives data (a source) and where it sends it (a destination, also called an output).

### Route, pipeline
A route picks which data goes where. The first route that matches wins. A pipeline is a list of
steps that change or drop events. The test block is a pipeline.

### Event breaker
A Cribl rule that splits a stream of text into events and finds each event's time. Splunk doesn't
split or time-stamp data that Cribl sends, so this lab does that work in Cribl.

### Persistent queue
Cribl's disk buffer. When Splunk can't take data, Cribl keeps it on disk and sends it later.

### Docker, container
Docker runs programs in containers: each one is a closed box with its own files. In this lab,
Splunk (`wd2l-splunk`) and Cribl (`cribl`) are containers on HOMEPC.

### Docker Desktop
The Windows app that runs Docker on HOMEPC. It works only while someone is signed in.

### `hl-net`
A Docker network that joins the Cribl and Splunk containers. Cribl reaches Splunk's port 9997 on
it, by container name.

### Docker NAT
Docker Desktop hides each sender's real address. Cribl sees every sender as the same address. So
nothing in this lab is named by IP address
([architecture](architecture.md#hosts-and-data-paths)).

### SSH, ProxyJump
SSH logs in to a host to run commands. ProxyJump reaches a host through another host. Here Ansible
reaches the two VMs through HOMEPC ([architecture](architecture.md#hosts-and-data-paths)).

### auditd, audit rules
auditd is the Linux service that records security events, such as a file change or a service stop,
in `/var/log/audit/audit.log`. Audit rules say what to record. Each rule can carry a key, such as
`hl-uf-config`, that names it in the log.

### Hardened audit rules
A strict set of Linux audit rules, plus rules for privileged commands. The `audit_rules` tag loads
them from `zz-hl-zz-stig.rules`.

### rsyslog
The Linux service that writes system logs to files such as `/var/log/messages`.

### Windows event logs, event ID
Windows keeps its logs in channels, such as Security and System. Each event has a number, its event
ID. For example, 1102 means the Security log was cleared.

### Hyper-V
Windows' built-in tool for running virtual machines (VMs). It logs an event when a VM starts or
stops.

### FIPS mode
An operating-system setting that allows only approved encryption. The two VMs run in FIPS mode, so
their UFs do too.

## This lab

### HOMEPC
In this lab: the Windows 11 PC (192.168.1.27). It runs Docker Desktop (Splunk and Cribl), Hyper-V
with the two VMs, and a UF.

### pi5
In this lab: a Raspberry Pi 5 running AlmaLinux 10 (192.168.1.120). It is the Ansible controller:
you run every `ansible-playbook` command there. It also has a UF and runs the device probe.

### wd2l-logsrv, wd2l-recv
In this lab: the two AlmaLinux 10 VMs on HOMEPC. Each has a UF.

### wd2l
In this lab: a separate project on the three Linux hosts. It takes their logs and audit trails and
sends them to Splunk over HEC (index `enclave1`). This repo reads wd2l's data but never changes
wd2l's files. The Splunk container, `wd2l-splunk`, was there before this repo.

### UDM
In this lab: the UniFi Dream Machine (192.168.1.1), the network's router. It has no agent. It sends
syslog to Cribl on port 5514 (UDP).

## The data-health app's own words

### Expected list
Everything that should be sending data: each host, and each sourcetype or source on a host. The
role builds it from the same inventory that deploys the inputs. You can add rows on the Manage
dashboard too.

### Item, Item ID
One row of the expected list: a host, a sourcetype on a host, or a source. Its Item ID has five
parts, `level|index|host|sourcetype|source`, with `*` for parts it doesn't use.

### Normalized source
A source name with its date, time or rotation number replaced by `*`. So `audit-2026-10-30.jsonl`
and `audit-2026-10-31.jsonl` both count as `audit-*.jsonl`.

### Status
What the app says about an item now: OK, LATE, MISSING, NEVER_SEEN, MUTED, PENDING or INFO
([statuses](data-health-design.md#statuses-and-roll-up)).

### PENDING, the gate
PENDING means "no trusted status yet". The app holds every status as PENDING when it can't judge,
for example after the PC sleeps. No alert fires then. This hold is called the gate.

### Roll-up
A host's overall state, from its items: DOWN, DEGRADED or OK.

### Profile
How an item usually sends data: heartbeat, periodic, continuous, sporadic or info. The profile sets
its default limit ([profiles](data-health-design.md#the-five-ideas)).

### Limit (threshold)
How long an item may stay silent before it is LATE. After twice the limit it is MISSING.

### Learned limit
A limit the app works out from an item's last 14 days, once it has at least 3 days of history.

### Override
A limit set by hand on the Manage dashboard. It wins over every other limit.

### Criticality
How much an item matters, from 1 (most) to 4. Only 1 and 2 raise the missing-data alert.

### Heartbeat, liveness
Liveness is how the app knows a host is up, apart from its data. For a UF it is the heartbeat:
the UF's own `_internal` metrics, every 30 s.

### Device probe (`hl-devprobe`)
A timer on pi5 that pings each syslog device every 60 s and writes the result to a file. pi5's UF
sends that file. It tells "device down" apart from "device up but not logging".

### Relay, `via`
A host that other data passes through. In this lab that is Cribl. An item with `via=cribl` reads
"Cribl DOWN" when Cribl is down.

### Marker (Ansible marker)
A short event the role sends to Splunk when it stops, starts or changes a host: what it did, who
ran it and when.
The app uses it to tell planned work from a real problem.

### Mute
A pause on an item's alerts, set on Manage with a reason and an end time (30 days at most).

### Test block
A test that drops a host's real data in Cribl on purpose, so you can check that the app notices
([how](running-the-role.md#test-blocks)).

### Tamper indicator, tamper finding
A tamper indicator is an event that may mean someone is hiding activity, such as a cleared log or a
stopped auditd. A tamper finding is the app's record of one. A finding is "suppressed" when an
Ansible marker shows it was the role's own work
([indicators](data-health-design.md#tamper-indicators)).

### Cause, action
For each item that is late or missing, the app names a likely cause and the next step
([the runbook](runbook-missing-data.md)).

### Unregistered
Data that arrives but isn't on the expected list. The app never alerts on it. You can adopt it on
Manage.

### Retire
Stop expecting an item that is gone for good. Its row stays on the expected list, turned off
([how](running-the-role.md#retiring-a-host)).

### Manage
The app's dashboard for changes: mutes, limits, the expected list and test blocks
([guide](data-health/dashboards.md#manage)).

### `dh_admin`, `dh_analyst`
The app's two Splunk roles. An analyst can mute items and set limits. An admin can also change the
expected list and use the test-block form.
