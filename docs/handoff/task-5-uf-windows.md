# Handoff: task 5 — Windows UF on HOMEPC → Cribl, and the audit policy

Issue #6 · branch `feat/5-uf-windows`, **stacked on `feat/4-uf-linux`** · drafted in a cloud
session on 2026-11-01 with no access to HOMEPC.

**State:** written; yamllint and ansible-lint (production) clean; `--syntax-check` OK. Every `win_shell` block was parsed by
PowerShell 7.4's parser, with Jinja swapped for placeholders: no syntax errors (one false positive
from the placeholder swap in `cribl_remove.yml`'s `--format '{{.Names}}'`). **Nothing has run on
HOMEPC.**

**Stop and ask Taylor first (spec §11):** the MSI install, the group changes and `auditpol` all need
elevation on the PC. The SSH session is already elevated, but the rule is to ask before running
anything elevated there.

## What the branch adds

| Path | What |
|---|---|
| `defaults/main.yml` | `hl_uf_win_home`, service, virtual account `NT SERVICE\SplunkForwarder`, groups by SID (Event Log Readers S-1-5-32-573, Performance Monitor Users S-1-5-32-558), `hl_win_state_dir`, `hl_audit_policy` (15 subcategories by GUID) |
| `tasks/uf_windows_install.yml` | refuse an unknown UF → MSI (sha256 on both ends; `AGREETOLICENSE=Yes LAUNCHSPLUNK=0 SERVICESTARTTYPE=auto`, no credentials on the command line, log kept in `C:\ProgramData\hl_splunk`) → product code + service SID + account recorded → FIPS lines only if `HKLM\…\Lsa\FipsAlgorithmPolicy\Enabled=1` → `user-seed.conf` → `hl_uf_outputs` → groups → start → connected → mgmt listener check → FIPS check → marker |
| `tasks/uf_windows_outputs.yml` | the same templates as Linux (`hl_collector=127.0.0.1` from `group_vars/uf_windows.yml`); drops the stale local token on change |
| `tasks/uf_windows_connected.yml` | the same rules as Linux, in PowerShell |
| `tasks/uf_windows_uninstall.yml` | marker → stop → out of the groups (by SID) → MSI uninstall by product code → folder → user rights still naming the SID (`secedit /export`, `win_user_right` remove) → contract (uninstall key, folder, service key, memberships, rights) |
| `tasks/uf_windows_service.yml` | start/stop/restart + markers; status (service, build, last connect/refusal, apps) |
| `tasks/audit_policy.yml` | `auditpol /backup` **once** (a rerun never overwrites the original), then `/set` only the subcategories whose setting differs |
| `tasks/audit_policy_remove.yml` | `auditpol /restore`, then a fresh backup compared row by row (GUID + setting) with the original; fails on any difference; deletes the backup |
| `tasks/verify.yml` | adds the Windows UF |

**The subset** (spec §5.3 "focused subset"): Logon/Logoff (Logon, Logoff, Special Logon, Account
Lockout, Other Logon/Logoff, Group Membership), Account Management (User Account, Computer Account,
Other), Security Group Management, Audit Policy Change, Authentication Policy Change, Security System
Extension (4697), System Integrity, and Process Creation (success only, no command line). The GUIDs
are Microsoft's fixed subcategory GUIDs. `auditpol /list /subcategory:* /v` on HOMEPC confirms them
(check 9).

## Before running

1. Taylor says yes to the elevated changes.
2. The task 4 packages exist on pi5 (`--tags download` fetched the MSI too).
3. Cribl is healthy (task 3b).

## Run

```bash
ansible-playbook site.yml --tags install --limit homepc -v
ansible-playbook site.yml --tags install --limit homepc            # expect changed=0
ansible-playbook site.yml --tags status --limit homepc
ansible-playbook site.yml --tags audit_policy --limit homepc
ansible-playbook site.yml --tags audit_policy --limit homepc       # expect changed=0
```

## Checks (record in spec §14.11 "Task 5 checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | MSI install | first run | green | open `C:\ProgramData\hl_splunk\uf-msi-install.log` and search for `Return value 3` |
| 2 | **Virtual account** | the play records `account`; or `(Get-CimInstance Win32_Service -Filter "Name='SplunkForwarder'").StartName` | `NT SERVICE\SplunkForwarder` | if it's LocalSystem, add `USE_LOCAL_SYSTEM=0` to the MSI arguments (or accept LocalSystem and drop the group steps; ask Taylor) |
| 3 | **Windows FIPS** (§13 "still unchecked") | `Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy` | record the value. If 1: `splunk show fips-mode` says enabled (the play checks) | — |
| 4 | **Mgmt listener** (§4.1 "to verify in task 5") | the play's mgmt task; `Get-NetTCPConnection -State Listen \| ? LocalPort -in 8089,8090` | nothing of the UF on 8089; 8090 on 127.0.0.1 only, or nothing (UDS-like, as on Linux) | if the UF took 8089, `web.conf` wasn't read: `splunk btool web list settings --debug` |
| 5 | Token doesn't flap | second run; `Select-String token 'C:\Program Files\SplunkUniversalForwarder\etc\apps\hl_uf_outputs\*\outputs.conf'` | `changed=0`; local/ holds the encrypted copy | as task 4 check 2 |
| 6 | Connected through Cribl | the play | `_internal` for `homepc` < 120 s old | `127.0.0.1:9997` is Cribl's published port; `Test-NetConnection 127.0.0.1 -Port 9997` |
| 7 | Wrong token caught | `-e vault_hl_s2s_token=wrong-on-purpose`, then rerun without | fails at connect, then recovers | as task 4 check 7 |
| 8 | Groups | `Get-LocalGroupMember -SID S-1-5-32-573`, `-SID S-1-5-32-558` | the virtual account is in both | — |
| 9 | Audit policy applied | `auditpol /get /category:* /r \| ConvertFrom-Csv \| ? 'Inclusion Setting' -ne 'No Auditing'`; Security log shows 4688 after starting `notepad` | the 15 subcategories as listed; 4688 present, with no command line | a GUID that `auditpol` rejects: `auditpol /list /subcategory:* /v` and fix it in defaults |
| 10 | **Exact restore** | `--tags audit_policy_remove`, then `--tags audit_policy` again | "restored exactly"; reapplied | if the compare differs only in a column we don't set, narrow the key in `audit_policy_remove.yml` (it uses GUID + Subcategory + Setting Value) |
| 11 | **Windows forwarder identity wording** (for task 11b, §7.3) | `Select-String -Path 'C:\Program Files\SplunkUniversalForwarder\var\log\splunk\splunkd.log' -Pattern 'System info','Splunkd starting','Connected to idx' \| select -Last 5` | copy the three lines into the task 11b note | — |
| 12 | Uninstall contract | `--tags uninstall --limit homepc` | contract passes (no product, folder, service key, membership or right) | an orphan right: the play removes it via `win_user_right`; if that fails, `secedit /export` and check by hand |
| 13 | Reinstall | `--tags install --limit homepc` | as check 1 | — |
| 14 | wd2l-splunk unaffected | HEC health, wd2l dashboard | healthy | — |

## Then

- Spec: §14.11 with the results; §4.1 (mgmt), §13 (Windows FIPS), §5.6 (anything the contract needed).
- PR: `feat(uf): Windows UF install, uninstall, service control and audit policy (task 5)`, `Closes #6`.
- Tasks 4 and 5 can be verified in either order; both are stacked here only to keep one line of history.
