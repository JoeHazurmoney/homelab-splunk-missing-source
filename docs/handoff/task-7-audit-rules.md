# Handoff: task 7 — STIG audit rules on the Linux UF hosts

Issue #8 · branch `feat/7-audit-rules`, **stacked on `feat/6-forwarder-apps`** (it needs nothing from 4–6
except the shared state helpers, so it can be verified any time after task 4) · drafted in a cloud
session on 2026-11-01.

**State:** written; yamllint and ansible-lint clean. The rule-building script was run here against fake `30-stig.rules`/`31-privileged.rules` files: `-D/-b/-f/-e` are filtered out, the privileged rules are
generated and de-duplicated, and `b32` is dropped when `hl_audit_arches` has no `b32`. **Not run on a
host.**

## What the branch adds

| Path | What |
|---|---|
| `defaults/main.yml` | source paths, `hl_stig_rules_file: /etc/audit/rules.d/50-hl-stig.rules`, `hl_audit_immutable: false` (argument spec allows only false) |
| `tasks/audit_rules.yml` | baseline `auditctl -l` (first run only) → build: 30-stig.rules without `-D/-b/-f/-e` and comments, + the output of the `## find …`/`## filecap …` commands from 31-privileged.rules (sorted, de-duplicated) → write → `augenrules --load` on change → check wd2l's rule count is unchanged and `enabled` isn't 2 → **rescue: remove the file, reload, fail** |
| `tasks/audit_rules_remove.yml` | delete → reload → `auditctl -l` equals the baseline (the UF's own `hl-*` tamper rules left out of the comparison) and wd2l's rules still loaded |

**Why the rollback:** `50-hl-stig.rules` sorts **before** `wd2l.rules`. augenrules stops at a failing
file, so a rejected line would drop wd2l's rules (spec §5.3 `uninstall` describes the same trap). The
rescue puts the host back the way it was.

## Before running

- `rpm -q audit-rules` on each host (the spike found `audit-rules-4.0.3-5.el10` on the VMs). pi5: check that
  `/usr/share/audit-rules/30-stig.rules` exists there too.
- `rpm -q libcap-ng-utils` (`filecap`). Without it, the filecap lines generate nothing; that's fine,
  but note it.
- pi5 ABIs: as task 4 "Before running" 4 (`hl_audit_arches`).

## Run

```bash
ansible-playbook site.yml --tags audit_rules --limit wd2l-recv -v
ansible-playbook site.yml --tags audit_rules --limit wd2l-recv     # expect changed=0
```

## Checks (record in spec §14.13 "Task 7 checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | Rules loaded | the play prints `HL_RULES`, `HL_PRIV`, wd2l's count; `sudo auditctl -l \| wc -l` | about 66 STIG rules (33 b32 + 33 b64, spec §5.3) plus the privileged ones; wd2l unchanged | the play rolled back: run `sudo auditctl -R /tmp/copy-of-50-hl-stig.rules` on a copy to find the rejected line |
| 2 | Not immutable | `sudo auditctl -s` | `enabled 1` | — |
| 3 | Idempotence | second run | `changed=0` (the build is sorted; a package update that adds a setuid binary changes it, as it should) | — |
| 4 | Volume (§13 risk) | after an hour: `index=linux sourcetype=linux_audit earliest=-1h \| stats count by host` and the licence by `idx=linux` | acceptable (record it) | drop the noisiest keys with `hl_input_overrides`, or exclude rules by key in the build |
| 5 | **`service auditd stop` on EL10** (§12 row 6, "task 7/14 must confirm") | on wd2l-recv: `sudo service auditd stop`; look for `SERVICE_STOP` in `/var/log/audit/audit.log` and in Splunk (`index=linux sourcetype=linux_audit SERVICE_STOP`) after `sudo service auditd start` | it stops (`systemctl stop` is refused: `RefuseManualStop=yes`), and `SERVICE_STOP … unit=auditd` is logged | record what happened; §12's row and §7.6's tamper indicator depend on it |
| 6 | Remove | `--tags audit_rules_remove --limit wd2l-recv` | "audit rules restored"; wd2l's rules loaded | the diff is printed (up to 20 lines) |
| 7 | Re-apply | `--tags audit_rules` | as check 1 | — |
| 8 | wd2l | `soak-check.sh` | green | — |

Then wd2l-logsrv and pi5.

## Then

- Spec: §14.13; §12 row 6 (whether `service auditd stop` works and emits `SERVICE_STOP`).
- PR: `feat(audit): STIG audit rules with rollback and exact removal (task 7)`, `Closes #8`.
