# homelab-splunk-missing-source

Splunk Universal Forwarders, TAs, STIG-style auditing and syslog for a homelab (two AlmaLinux 10
VMs, a Windows 11 PC, a Raspberry Pi 5 and a UniFi Dream Machine), deployed by one Ansible role run
from the Pi, plus a data-health app that tells a SOC analyst within minutes when a host,
sourcetype or source stops sending, why, and what to do.

Work in progress. The design is in [docs/specs/2026-10-30-design.md](docs/specs/2026-10-30-design.md).
