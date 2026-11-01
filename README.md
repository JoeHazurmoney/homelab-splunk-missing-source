# homelab-splunk-missing-source

Splunk Universal Forwarders, TAs, STIG-style auditing and syslog for a homelab (two AlmaLinux 10
VMs, a Windows 11 PC, a Raspberry Pi 5 and a UniFi Dream Machine), with **Cribl Stream** between
every collected source and Splunk. One Ansible role, run from the Pi, deploys it all. A data-health
app tells a SOC analyst within minutes when a host, sourcetype or source stops sending, why it
stopped, and what to do next.

**The question it answers: "Am I blind somewhere?"** The expected list is generated from the
same inventory that deploys the inputs, so it can't drift. Thresholds follow each input's cadence. A
forwarder's heartbeat is tracked apart from its data. Every finding comes with a likely cause and the
next step.

## Quick start

On the Pi (the Ansible controller), after the one-time bootstraps in
[docs/running-the-role.md](docs/running-the-role.md#1-one-time-setup):

```bash
cd ~/homelab-splunk-missing-source/ansible
ansible-playbook site.yml --tags download --limit pi5   # UF packages, sha256-checked
ansible-playbook site.yml                               # deploy everything (never removes anything)
ansible-playbook site.yml --tags verify                 # UFs connected, Cribl healthy
```

Then open the **HL Data Health** app in Splunk (`http://127.0.0.1:8000` on HOMEPC) → Overview.

| Want to… | Run |
|---|---|
| stop one forwarder (maintenance) | `--tags stop --limit wd2l-recv` (and `--tags start` afterwards) |
| turn off one input | `-e '{"hl_disabled_inputs":["monitor:///var/log/secure"]}' --tags apps,expected` |
| block data for a test | `--tags cribl_block -e "hl_block_key='pi5\|*\|*'" -e hl_block_minutes=15 -e "hl_block_reason='test'"` |
| remove a forwarder cleanly | `--tags uninstall --limit wd2l-recv` (the play fails if anything is left) |

## Documents

| Document | For |
|---|---|
| [docs/architecture.md](docs/architecture.md) | how data flows, the ports, the indexes and sourcetypes |
| [docs/running-the-role.md](docs/running-the-role.md) | setup, every tag with examples, toggles, the vault, troubleshooting |
| [docs/data-health-design.md](docs/data-health-design.md) | how "missing" is decided, and how to port it to production |
| [docs/data-health/dashboards.md](docs/data-health/dashboards.md) | the analyst's guide to the four dashboards |
| [docs/data-health/macros.md](docs/data-health/macros.md) | what each macro does |
| [docs/runbook-missing-data.md](docs/runbook-missing-data.md) | what to do for each cause the Overview shows |
| [docs/testing.md](docs/testing.md) | the fault-injection results, with measured detection times |
| [docs/specs/](docs/specs/) | the approved design and its Cribl addendum (the record of every decision) |
