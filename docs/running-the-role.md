# Running the role

One play (`ansible/site.yml`) runs the role `homelab_splunk` on every managed host. **Tags pick what
it does.** A bare run deploys. Anything that removes, stops or restarts needs its own tag (those tags
carry `never`). Run everything from `ansible/` on pi5.

## 1. One-time setup

| Step | Where | What |
|---|---|---|
| 1 | HOMEPC, **elevated** PowerShell | `.\scripts\bootstrap-windows-sshd.ps1`: OpenSSH Server, PowerShell as its shell, port 22 open to pi5 only. The key goes in `administrators_authorized_keys`, so the SSH session is elevated |
| 2 | pi5 | `scripts/bootstrap-pi.sh`: ansible-core and the collections, the Ansible key (`~/.ssh/id_ecdsa_homelab_ansible`), and the vault (random values, encrypted; its password file is `~/.config/hl_splunk/vault-pass`). It reports any vault key that is missing |
| 3 | HOMEPC | `.\scripts\add-ansible-key.ps1`: puts pi5's public key on HOMEPC and the two VMs |
| 4 | HOMEPC | `.\scripts\sync-to-pi.ps1` (add `-IncludePackages` to send `ansible/files/packages/` too). It keeps pi5's vault and its downloaded packages |
| 5 | HOMEPC, **desktop** PowerShell | `docker pull cribl/cribl@sha256:cb2b2e32933e492f439b5825b0c36f420df2fa986fe36d5f31fce6755190eb71`. Over SSH, Docker Desktop has no credential store, so the role never pulls |
| 6 | pi5 | `ansible all -m ping` and `ansible homepc -m ansible.windows.win_ping` |

**The vault** (`inventory/group_vars/all/vault.yml`, never committed; the shape is in
`vault.yml.example`): `vault_hl_uf_admin_password`, `vault_hl_s2s_token` (the UFs, Cribl and Splunk all
use it), `vault_hl_markers_token` (HEC), `vault_hl_cribl_admin_password`. Edit it with
`ansible-vault edit inventory/group_vars/all/vault.yml`.

**The packages** go in `ansible/files/packages/` on pi5 (gitignored). `--tags download --limit pi5`
fetches the UF packages and checks the pinned sha256. Copy the TAs there by hand, and pin their sha256
in `roles/homelab_splunk/defaults/main.yml` (`hl_tas`).

## 2. Deploy

`ansible-playbook site.yml` runs these tags in this order (each can also run alone):

| Tag | Hosts | Does |
|---|---|---|
| `server` | homepc | the Splunk apps `hl_server_base` and `hl_data_health`: swaps `default/`, keeps `local/` and UI-written lookups; restarts splunkd only for indexes/inputs/props changes |
| `server_network` | homepc | creates `hl-net`, attaches `wd2l-splunk` live, re-attaches if needed |
| `cribl` | homepc | the `cribl` container (compose, image by digest), the admin password, the `cribl/` config, a self-test |
| `install` | UF hosts | the pinned UF, FIPS where the kernel has it, `hl_uf_outputs` (→ Cribl, token, `useACK`), boot-start, the tamper audit rules (Linux) |
| `apps` | UF hosts | the TAs (unmodified) and the role's input apps; restarts the UF only on change |
| `audit_rules` | Linux UF hosts | the STIG sample rules + the privileged-command rules; rolls back if wd2l's rules would drop |
| `audit_policy` | homepc | backs up `auditpol` once, then the focused subset |
| `probe` | pi5 | `hl-devprobe`: pings each syslog device every 60 s into a file pi5's UF reads |
| `expected` | homepc | renders the expected list from the whole inventory and syncs it |

Use `--limit <host>` to touch one host. `expected` reads every host's inventory, so it never needs
the others to be up.

## 3. Day-to-day tags

| Tag | Example | Notes |
|---|---|---|
| `status` | `--tags status --limit wd2l-recv` | service, version/build, last connect, last token refusal, apps, FIPS |
| `stop` / `start` / `restart` | `--tags stop --limit wd2l-recv` | posts a marker first (stop) or after (start), so the Overview says "Stopped with Ansible …" |
| `verify` | `--tags verify` | UFs running and connected through Cribl, their `_internal` seen in Splunk, Cribl healthy |
| `cribl_block` | `--tags cribl_block -e "hl_block_key='wd2l-recv\|linux_secure\|*'" -e hl_block_minutes=30 -e "hl_block_reason='E2E row 4'"` | a test block in Cribl (≤ 24 h, a reason is required); clear it with `-e hl_block_clear=true`; the Manage dashboard prints this line for you |
| `download` | `--tags download --limit pi5` | the UF packages |

**Turning things off:**
- One input: `-e '{"hl_disabled_inputs":["monitor:///var/log/secure"]}' --tags apps,expected`. Rerun
  without `-e` to turn it back on. To make it permanent, set `hl_disabled_inputs` in the host's `host_vars`.
- Change an input's profile or criticality, or declare its maximum silence: `hl_input_overrides` in
  `host_vars` (for example `{"monitor:///var/log/cron": {profile: sporadic, criticality: 4}}`).
- Rows Ansible can't derive (what reaches Splunk through wd2l): `dh_extra_expected` in
  `group_vars/splunk_server.yml`.

## 4. Removing things

Run in reverse deploy order. Each removal checks a **contract** and fails the play if anything is left.

| Tag | Removes | The contract checks |
|---|---|---|
| `uninstall` | the UF, its apps, tamper rules, the account, packages the role added | rpm/MSI, folders, units, account, mail spool, `~/.splunk`, `auditctl -l` = the install-time baseline, no new unowned files; Windows: uninstall key, service key, group memberships, user rights |
| `apps_remove` | the role's input apps (and the TAs' role-owned `local/inputs.conf`); `-e '{"hl_apps_only":[…]}'` for some | `hl_uf_outputs` stays unless named, so the heartbeat continues |
| `audit_rules_remove` | the STIG rules | `auditctl -l` = the baseline before the first `audit_rules` |
| `audit_policy_remove` | restores `auditpol` from the backup | the policy matches the backup row by row |
| `probe_remove` | hl-devprobe's units, script, logrotate, log folder | nothing is left |
| `cribl_remove` | the `cribl` container, its volume and the compose folder | `docker ps -a` / `docker volume ls` |
| `server_remove` | the Splunk apps and their KV collections; `hl-net` (if the role created it and nothing else is attached); index data only with `-e hl_purge_index_data=true` | the apps, collections and network; `wd2l-splunk`'s ports and volumes unchanged; HEC healthy |

A full removal: `--tags uninstall,apps_remove,audit_rules_remove,audit_policy_remove,probe_remove,cribl_remove,server_remove`.

## 5. Troubleshooting

| Symptom | Look at |
|---|---|
| `install` fails at "Wait for the UF to connect to Cribl" | the token: `--tags status` shows `last_refusal`. Cribl must be up (`--tags verify --limit homepc`); port 9997 on HOMEPC must be reachable from the host |
| `cribl` stops at "The Cribl image is not on HOMEPC" | pull it in a desktop session (setup step 5) |
| `cribl` stops at the admin password | a container created by hand with another password: `--tags cribl_remove`, then `--tags cribl` |
| `server` fails with btool findings | only findings in the role's apps fail the play; read the listed lines |
| a VM is unreachable | the VMs are started by hand; `ansible_host` is `<vm>.mshome.net`, reached through HOMEPC's sshd |
| sudo asks for a password | add `-K` |
| "the rendered expected list has no rows" | the inventory groups `uf_linux` / `uf_windows` are empty |
| Overview shows "On hold" | see the banner rows in [dashboards.md](data-health/dashboards.md) |

Every role-made change shows up as an **Ansible marker** (`index=data_health source=dh:marker`), so
the data-health app knows the role's own work from tampering.
