# Handoff: task 5 — Windows UF on HOMEPC → Cribl, and the audit policy

Issue #6 · branch `feat/5-uf-windows` · drafted in a cloud session on 2026-11-01 with no access to
HOMEPC, then brought to task 4's final Linux rules and run live on 2026-11-08.

**State:** **ran live on HOMEPC on 2026-11-08; checks 1–14 pass** (spec §14.12). Three live fixes: the
MSI arguments as one string (a quoted list item made msiexec wait on a hidden usage dialog), the
audit-restore compare (empty global-SACL rows after `/restore`), and `cmd:` for the PowerShell blocks
that Ansible's free-form splitter rejected. End state: the UF installed, connected and `verify`-green,
the audit policy applied. Taylor approved the elevated changes through the role's tags (2026-11-08).
Fix round 1 (the review): the uninstall contract fails closed (ADSI members, checked `secedit`),
`C:\ProgramData\hl_splunk` has a protected ACL, the MSI has a 900 s timeout, and every PowerShell block
uses `cmd: |` with quoted Jinja values (spec §14.12 "Fix round 1").

## What the branch adds

| Path | What |
|---|---|
| `defaults/main.yml` | `hl_uf_win_home`, service, virtual account `NT SERVICE\SplunkForwarder`, groups by SID (Event Log Readers S-1-5-32-573, Performance Monitor Users S-1-5-32-558), `hl_win_state_dir`, `hl_audit_policy` (15 subcategories by GUID) |
| `tasks/uf_windows_install.yml` | refuse an unknown UF → the `uf` record written → MSI (sha256 on both ends; `AGREETOLICENSE=Yes LAUNCHSPLUNK=0 SERVICESTARTTYPE=auto INSTALLDIR="…"` as one string, no credentials on the command line, log kept in `C:\ProgramData\hl_splunk`) → product code + service SID + account + groups recorded, the virtual account asserted → FIPS lines only if `HKLM\…\Lsa\FipsAlgorithmPolicy\Enabled=1` → `user-seed.conf` → `hl_uf_outputs` → groups → start → connected (every run) → mgmt listener check (no UF listener on 8089 or off loopback) → FIPS check (the running process) → marker (best effort) |
| `tasks/uf_windows_outputs.yml` | the same templates as Linux (`hl_collector=127.0.0.1` from `group_vars/uf_windows.yml`); drops the stale local token on change |
| `tasks/uf_windows_connected.yml` | task 4's final rules (`uf_linux_connected.yml`) in PowerShell: no fast fail on a close, the Splunk-side proof counts only `_internal` after the service process's start, an unknown start fails |
| `tasks/uf_windows_uninstall.yml` | marker → stop → out of the groups (by SID) → MSI uninstall by product code → folder → user rights still naming the SID (`secedit /export`, `win_user_right` remove) → contract (uninstall key, folder, service key, memberships, rights) |
| `tasks/uf_windows_service.yml` | start/stop/restart + markers (best effort); status (service, account, MSI version, build from `etc\splunk.version`, last connect, last close, apps, FIPS from the running process) |
| `tasks/audit_policy.yml` | `auditpol /backup` **once** (a rerun never overwrites the original), then add-only `/set`: turn on what the subset wants, never turn off what the PC had; read back |
| `tasks/audit_policy_remove.yml` | `auditpol /restore`, then a fresh backup compared row by row (GUID + setting) with the original, where an empty global-SACL row counts as none; fails on any other difference; deletes the backup |
| `tasks/uf_windows_contract.yml` | the §5.6 Windows contract, fail-closed: members through ADSI, `secedit` checked |
| `tasks/win_state_dir.yml` | the role's folder with a protected ACL (SYSTEM + Administrators), set only when it differs |
| `vars/main.yml` `hl_win_acct_ps` | PowerShell helpers: `Get-HlGroupMemberSids`, `Remove-HlGroupMember`, `Get-HlUserRights` |
| `tasks/marker_best_effort.yml` | `marker.yml` in a block whose rescue only warns (the `cribl_hold` pattern), for the Windows UF's markers |
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

## Checks (recorded in spec §14.12 "Task 5 checks")

| # | Check | How | Pass | If it fails |
|---|---|---|---|---|
| 1 | MSI install | first run | green | open `C:\ProgramData\hl_splunk\uf-msi-install.log` and search for `Return value 3` |
| 2 | **Virtual account** | the play records `account`; or `(Get-CimInstance Win32_Service -Filter "Name='SplunkForwarder'").StartName` | `NT SERVICE\SplunkForwarder` | if it's LocalSystem, add `USE_LOCAL_SYSTEM=0` to the MSI arguments (or accept LocalSystem and drop the group steps; ask Taylor) |
| 3 | **Windows FIPS** (§13 "still unchecked") | `Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy` | record the value. If 1: the play checks the running splunkd: both `splunk-launch.conf` lines and `lib\ossl-modules\fips140-3\fips.dll` loaded in the service process (not `splunk show fips-mode`, which needs a login) | — |
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

- Spec: §14.12 with the results; §4.1 (mgmt), §13 (Windows FIPS), §5.6 (the MSI's user rights, the shared state file). Done.
- PR: `feat(uf): Windows UF install, uninstall, service control and audit policy (task 5)`, `Closes #6`.
