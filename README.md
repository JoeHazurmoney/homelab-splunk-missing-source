# homelab-splunk-missing-source

Splunk Universal Forwarders, TAs, STIG-style auditing and syslog for a homelab (two AlmaLinux 10
VMs, a Windows 11 PC, a Raspberry Pi 5 and a UniFi Dream Machine), with **Cribl Stream** between
every collected source and Splunk. One Ansible role, run from the Pi, deploys it all. A data-health
app (`hl_data_health`, SPL plus KV store only) tells a SOC analyst within minutes when a host,
sourcetype or source stops sending, why it stopped, and what to do next.

**The question it answers: "Am I blind somewhere?"** The expected list is generated from the
same inventory that deploys the inputs, so it can't drift. Thresholds follow each input's cadence and
are learned where they can be. A forwarder's heartbeat is tracked apart from its data. Every finding
comes with a likely cause and the next step.

## Quick start

This repo deploys around an existing `wd2l-splunk` container on HOMEPC. First do the one-time setup
in [docs/running-the-role.md](docs/running-the-role.md#1-one-time-setup). Then, on pi5, the Ansible
controller:

```bash
cd ~/homelab-splunk-missing-source/ansible
. ~/.venvs/ansible/bin/activate
ansible-playbook site.yml --tags download --limit pi5   # UF packages, sha256-checked
ansible-playbook site.yml                               # deploy everything (never removes anything)
ansible-playbook site.yml --tags verify                 # UFs connected, Cribl healthy, every expected row seen
```

Then open the **HL Data Health** app in Splunk (`http://127.0.0.1:8000` on HOMEPC) → Overview.

| Want to… | Run (from `ansible/` on pi5) |
|---|---|
| stop one forwarder (maintenance) | `ansible-playbook site.yml --tags stop --limit wd2l-recv`, and `--tags start` afterwards |
| turn off one input everywhere | `ansible-playbook site.yml -e '{"hl_disabled_inputs":["monitor:///var/log/secure"]}' --tags apps,expected` |
| block data for a test | `ansible-playbook site.yml --tags cribl_block --limit homepc -e hl_block_key='pi5\|*\|*' -e hl_block_minutes=15 -e "hl_block_reason='test'"` |
| remove a forwarder cleanly | `ansible-playbook site.yml --tags uninstall --limit wd2l-recv` (the play fails if anything is left) |

## Documents

| Document | For |
|---|---|
| [docs/architecture.md](docs/architecture.md) | how data flows; the ports, indexes, sourcetypes and retention |
| [docs/running-the-role.md](docs/running-the-role.md) | setup, every tag with examples, toggles, the vault, troubleshooting |
| [docs/data-health-design.md](docs/data-health-design.md) | how "missing" is decided, and how to port it to production |
| [docs/data-health/dashboards.md](docs/data-health/dashboards.md) | the analyst's guide to the four dashboards |
| [docs/data-health/macros.md](docs/data-health/macros.md) | what each macro does |
| [docs/runbook-missing-data.md](docs/runbook-missing-data.md) | what to do for each cause the Overview shows |
| [docs/testing.md](docs/testing.md) | how to run each test suite |
| [docs/glossary.md](docs/glossary.md) | the words the docs use, for a reader new to this lab |
| [docs/specs/](docs/specs/) | the approved design and its Cribl addendum (the record of every decision) |
| [docs/records/](docs/records/) | records of test runs on the real hosts, such as the fault-injection run |
