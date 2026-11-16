# homelab-splunk-missing-source

This repo sends a home lab's logs to Splunk and tells you when any of them stop. It deploys:

- Splunk agents ([UF](docs/glossary.md#universal-forwarder-uf)) and add-ons
  ([TAs](docs/glossary.md#add-on-ta)) on each host.
- [Hardened audit rules](docs/glossary.md#hardened-audit-rules) on the Linux hosts, and a
  [focused Windows audit policy](docs/running-the-role.md#what-each-deploy-tag-does).
- [Cribl Stream](docs/glossary.md#cribl-stream) between every collected source and Splunk. It also
  takes [syslog](docs/glossary.md#syslog-udp-syslog) from the network's router.
- `hl_data_health`, a Splunk app built only from SPL and the [KV store](docs/glossary.md#kv-store).

One [Ansible](docs/glossary.md#ansible) role, run from [pi5](docs/glossary.md#pi5), deploys it all.
In this lab the hosts are:

- Two AlmaLinux 10 VMs.
- A Windows 11 PC ([HOMEPC](docs/glossary.md#homepc)).
- A Raspberry Pi 5 (pi5).
- A UniFi Dream Machine ([the UDM](docs/glossary.md#udm)).

[Hosts in this lab](docs/architecture.md#hosts-in-this-lab) lists their inventory names.

**The question it answers: "Am I blind somewhere?"** The data-health app tells a SOC analyst within
minutes when a host, sourcetype or source stops sending. It names the likely cause and the next step.

- The [expected list](docs/glossary.md#expected-list) comes from the same
  [inventory](docs/glossary.md#inventory-host_vars-group_vars) that deploys the inputs, so the two
  can't drift apart.
- Each input's [limit](docs/glossary.md#limit-threshold) follows how often it sends. The app learns
  limits where it can.
- A UF's [heartbeat](docs/glossary.md#heartbeat-liveness) is tracked apart from its data.

## What is wd2l?

wd2l is a separate project that was already running in this lab. It runs on the three Linux hosts:
the two VMs and pi5. It gathers their logs and audit trails and sends them to Splunk over
[HEC](docs/glossary.md#hec-http-event-collector), into the index `enclave1`. Its Splunk is the
`wd2l-splunk` container on HOMEPC, and this repo deploys into that same Splunk. This repo watches
wd2l's data, and its UFs read wd2l's audit trail. It never changes wd2l's own files. After it changes
Splunk, the role checks that wd2l's HEC is healthy and its data still arrives.

## Quick start

1. **Check first.** `wd2l-splunk` must be running on HOMEPC. On HOMEPC, in PowerShell, any folder:

   ```powershell
   docker ps --filter name=wd2l-splunk
   ```

   You should see a line whose status starts with `Up`.
2. **Do the one-time setup.** Follow
   [One-time setup](docs/running-the-role.md#1-one-time-setup) in `docs/running-the-role.md`. It has
   eight steps, and each says what you should see.
3. **Deploy and check.** Log in to pi5 and go to the Ansible folder
   ([how](docs/running-the-role.md#how-to-run-a-command)).

   **Warning:** a deploy can restart splunkd and lose some UDP syslog, the logs the UDM sends.
   Nobody resends a line lost in the gap ([costs](docs/running-the-role.md#costs-of-a-run)).

   On pi5, any folder:

   ```bash
   cd ~/homelab-splunk-missing-source/ansible
   . ~/.venvs/ansible/bin/activate            # "No such file"? Your Ansible came from dnf: skip this line
   ansible-playbook site.yml                  # deploy everything (removes nothing)
   ansible-playbook site.yml --tags verify    # UFs connected, Cribl healthy, no expected item missing
   ```

   [Tags](docs/glossary.md#tags-never) pick what the role does, so `--tags verify` runs only the check.
   Both runs should end with `failed=0`. If `verify` says "Not evaluated", it **failed**: wait 5 min
   and run it again. [What you should see](docs/running-the-role.md#first-deploy-what-you-should-see)
   says more.
4. **Look.** Open the **HL Data Health** app in Splunk Web, then its Overview. In this lab Splunk Web
   is `http://127.0.0.1:8000` on HOMEPC. Log in as `admin`. Its password is in the file named in
   [Secrets](docs/running-the-role.md#secrets). A healthy Overview has a green banner that starts "Up
   to date", and an empty *Needs attention* table.

## Common tasks

On pi5, in `~/homelab-splunk-missing-source/ansible`, with the venv on:

```bash
# Stop one forwarder for maintenance, then start it again
ansible-playbook site.yml --tags stop --limit wd2l-recv
ansible-playbook site.yml --tags start --limit wd2l-recv

# Turn off one input on every host
ansible-playbook site.yml -e '{"hl_disabled_inputs":["monitor:///var/log/secure"]}' --tags apps,expected

# Block pi5's data for a 15-minute test
ansible-playbook site.yml --tags cribl_block --limit homepc -e hl_block_key='pi5|*|*' -e hl_block_minutes=15 -e "hl_block_reason='test'"

# Remove a forwarder cleanly (the play fails if anything is left)
ansible-playbook site.yml --tags uninstall --limit wd2l-recv
```

- `wd2l-recv` is an inventory name, one of the two VMs.
- `monitor:///var/log/secure` is an `inputs.conf` stanza ([glossary](docs/glossary.md#inputsconf-propsconf)).
- `pi5|*|*` is a test-block key. The block drops pi5's real data on purpose, so alerts can fire
  ([Test blocks](docs/running-the-role.md#test-blocks)).

`uninstall` doesn't stop the app expecting the host's data. To do that, see
[Retiring a host](docs/running-the-role.md#retiring-a-host). Every tag is in
[docs/running-the-role.md](docs/running-the-role.md).

## Documents

| Document | For |
|---|---|
| [docs/architecture.md](docs/architecture.md) | How data flows. The ports, indexes, sourcetypes and retention. |
| [docs/running-the-role.md](docs/running-the-role.md) | Setup, every tag with examples, the vault, troubleshooting. |
| [docs/data-health-design.md](docs/data-health-design.md) | How "missing" is decided, and how to port it to production. |
| [docs/data-health/dashboards.md](docs/data-health/dashboards.md) | The analyst's guide to the four dashboards. |
| [docs/data-health/macros.md](docs/data-health/macros.md) | What each macro does. |
| [docs/runbook-missing-data.md](docs/runbook-missing-data.md) | What to do for each cause the Overview shows. |
| [docs/testing.md](docs/testing.md) | How to run each test suite. |
| [docs/glossary.md](docs/glossary.md) | The words the docs use, for a reader new to this lab. |
| [docs/specs/](docs/specs/) | The approved design and its Cribl addendum. They record every decision. |
| [docs/records/](docs/records/) | Records of test runs on the real hosts, such as the fault-injection run. |

## Licence

MIT. See [LICENSE](LICENSE).
