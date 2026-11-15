# Running the role

One play (`ansible/site.yml`) runs the role `homelab_splunk` on every managed host. **Tags pick what
it does.** A bare run deploys. Anything that removes, stops, restarts or only checks needs its own
tag (those tags carry `never`). Run everything from `ansible/` on pi5, the Ansible controller:

```bash
cd ~/homelab-splunk-missing-source/ansible
. ~/.venvs/ansible/bin/activate     # when bootstrap-pi.sh built the venv (it does on pi5)
```

The commands below omit `ansible-playbook site.yml`.

## 1. One-time setup

**What must already exist** (the role deploys around these and never creates them):

- HOMEPC: Windows 11 with Docker Desktop running in a signed-in session, and the `wd2l-splunk`
  container (Splunk 10.6.0.5) with its admin password in
  `C:\Users\taylo\wd2l-splunk\secrets\splunk-admin-password`. Hyper-V with the two AlmaLinux VMs.
- An SSH alias `pi5` in HOMEPC's `~/.ssh/config`, used through **Windows OpenSSH**
  (`C:\Windows\System32\OpenSSH\ssh.exe`). pi5 is reached only that way; Git Bash's ssh has no
  access to the Windows agent.
- The VMs are running (they are started by hand) and `~\.ssh\id_ecdsa_wd2l_lab` on HOMEPC logs in to
  them as `taylorb`.
- pi5: AlmaLinux 10 (aarch64) with `sudo`, and internet access for pip and `download.splunk.com`.

The inventory names this lab's hosts and users (`inventory/hosts.yml`, `inventory/host_vars/`), and
`defaults/main.yml` names HOMEPC's address and paths (`hl_collector`, `hl_marker_hec_url`,
`hl_splunk_admin_password_file`). Change those for other hosts.

**The setup steps**, in this order, from the root of a clone of this repo on HOMEPC
(`gh repo clone JoeHazurmoney/homelab-splunk-missing-source`, a private repo). Windows 11 refuses
local scripts by default; if PowerShell says running scripts is disabled, run each one as
`powershell -ExecutionPolicy Bypass -File .\scripts\<name>.ps1`.

| Step | Where | What |
|---|---|---|
| 1 | HOMEPC, **elevated** PowerShell | `.\scripts\bootstrap-windows-sshd.ps1`: OpenSSH Server, PowerShell as its shell, 22/tcp open to pi5 only, password logins off. Keys go in `administrators_authorized_keys`, so the SSH session is elevated. `-Remove` undoes it |
| 2 | HOMEPC | `.\scripts\sync-to-pi.ps1`: copies the repo to pi5's `~/homelab-splunk-missing-source`. Later runs keep pi5's vault and packages. Add `-IncludePackages` to send `ansible/files/packages/` too |
| 3 | pi5 | `bash ~/homelab-splunk-missing-source/scripts/bootstrap-pi.sh`: ansible-core ≥ 2.18 (from dnf if new enough, otherwise the venv `~/.venvs/ansible`, linked into `~/.local/bin`), ansible-lint and yamllint, the collections in `ansible/requirements.yml`, the Ansible key `~/.ssh/id_ecdsa_homelab_ansible`, and the vault. **Log in again afterwards**: `ANSIBLE_VAULT_PASSWORD_FILE` is set in `~/.bashrc.d/hl-ansible.sh` |
| 4 | HOMEPC | `.\scripts\add-ansible-key.ps1`: puts pi5's public key on the VMs and HOMEPC. The VMs must be running; `-SkipVm` leaves them out. For HOMEPC it needs elevation: run it elevated, or accept the UAC prompt it opens |
| 5 | HOMEPC, **desktop** PowerShell | `docker pull cribl/cribl@sha256:cb2b2e32933e492f439b5825b0c36f420df2fa986fe36d5f31fce6755190eb71`. Docker Desktop has no credential store over SSH, so the role never pulls |
| 6 | pi5 and HOMEPC | the packages, below |
| 7 | pi5 | `ansible uf_linux -m ansible.builtin.ping` and `ansible uf_windows -m ansible.windows.win_ping` |
| 8 | UniFi Network UI | Remote syslog to HOMEPC: server `192.168.1.27`, port `5514`, UDP. The role never logs in to the UDM, so this is the only place it is set. No new Windows firewall rule is needed: Docker Desktop's existing rule lets the UDM's packets in. If this step is missing, nothing fails: the `udm` row reads NEVER_SEEN an hour after it is first expected (MISSING if it stops later), with the cause "The device answers the network probe but sends no logs", and `verify` only reports it, because the row is sporadic |

**The packages** go in `ansible/files/packages/` on pi5 (gitignored). The UF packages come from
`--tags download --limit pi5`, which fetches them from `download.splunk.com` and checks each against
its sha256 in `defaults/main.yml` (`hl_uf_packages`, 10.6.1.1 build `b2ae2962645c`: x86_64 and
aarch64 rpm, windows MSI). The TAs are copied by hand: `splunk-add-on-for-unix-and-linux_1034.spl`
(Splunk_TA_nix 10.3.4) and `splunk-add-on-for-microsoft-windows_1103.spl` (Splunk_TA_windows
11.0.3), from Splunkbase under those exact names (this lab keeps a copy outside the repo, in
`C:\Users\taylo\Documents\claude-code\splunk-ta-local\`). Put them in `ansible/files/packages/` on HOMEPC
and run `sync-to-pi.ps1 -IncludePackages`, or copy them straight to pi5. Their sha256 is pinned in
`hl_tas` in `defaults/main.yml`, and `apps` fails on a missing file or one that doesn't match.

**Secrets** (never in the repo):

| Secret | Lives in |
|---|---|
| `vault_hl_uf_admin_password`, `vault_hl_s2s_token` (UFs, Cribl and Splunk all use it), `vault_hl_markers_token` (HEC), `vault_hl_cribl_admin_password` | `inventory/group_vars/all/vault.yml` on pi5 (encrypted; the shape is in `vault.yml.example`). `bootstrap-pi.sh` generates it with random values and reports any key that is missing. Edit with `ansible-vault edit inventory/group_vars/all/vault.yml` |
| the vault's password | `~/.config/hl_splunk/vault-pass` on pi5 only |
| the Splunk admin password | `C:\Users\taylo\wd2l-splunk\secrets\splunk-admin-password` on HOMEPC; read there at each REST call, never copied |
| the Splunk Developer licence file | `C:\Users\taylo\wd2l-splunk\secrets\` on HOMEPC; never commit it |

`vault_hl_s2s_token_previous` exists only during a token rotation. Rotating the S2S token has a fixed
order (expand, migrate, contract): follow [spec §13](specs/2026-10-30-design.md#13-risks).

After changing anything in the repo, run `.\scripts\sync-to-pi.ps1` again: pi5 holds a copy, not a
git clone.

## 2. Deploy

A bare `ansible-playbook site.yml` (the same as `--tags deploy`) runs these in this order. Each can
also run alone with `--tags <name>`. None of them removes anything.

| Tag | Hosts | Does | Needs |
|---|---|---|---|
| `server` | homepc | the Splunk apps `hl_server_base` and `hl_data_health`: swaps `default/`, keeps `local/` and UI-written lookups; restarts splunkd only when `indexes`, `inputs`, `props` or `web` conf changes, otherwise reloads | `wd2l-splunk` running, Docker Desktop signed in |
| `server_network` | homepc | creates `hl-net`, attaches `wd2l-splunk` live, re-attaches if needed | `wd2l-splunk` running |
| `cribl` | homepc | the `cribl` container (compose, image by digest, 2 workers), the admin password, the `cribl/` config, a self-test after a change | the image pulled (setup step 5), `hl-net`, the vault |
| `install` | UF hosts | the pinned UF, FIPS where the kernel has it, `hl_uf_outputs` (→ Cribl, token, `useACK`), boot-start, the tamper audit rules (Linux); proves the UF connected through Cribl | the UF package on pi5, Cribl up |
| `apps` | UF hosts | the TAs (unmodified) and the role's input apps; restarts the UF only on change | the TA packages on pi5, `install` |
| `audit_rules` | Linux UF hosts | the STIG sample rules plus privileged-command rules in `/etc/audit/rules.d/zz-hl-zz-stig.rules`, which loads last on purpose; rolls back if wd2l's rules would drop | auditd's `audit-rules` package |
| `audit_policy` | homepc | backs up `auditpol` once, then turns on the focused subset (add-only) | the elevated SSH session |
| `probe` | pi5 | `hl-devprobe`, a systemd timer: pings each syslog device every 60 s into a file pi5's UF reads | `syslog_devices` in `group_vars/splunk_server.yml` |
| `expected` | homepc | renders the expected list from the whole inventory and syncs it (*DH Sync expected*) | `server` |

**Costs of a run.** A rerun with nothing to change restarts nothing. A `server` run that restarts
splunkd pauses Cribl for about 2 min 14 s, so UDP syslog (the UDM) sent during that time is lost and
UF data arrives up to 2.5 min late. A `cribl` run that changes a file does a plain `docker restart
cribl`, costing about 12 s of UDP syslog. Both post markers, so the gap is attributable. A splunkd
restart outside the role (Splunk Web, `docker exec … splunk restart`) has no Cribl hold: task 14 lost
one 30-s sample (about 10–25 s of UF data) on three of the four UFs that way.

`ansible-playbook site.yml --list-tags` lists every tag. It also shows `never` and `always`
(Ansible's own tag on the role's argument check, which runs on every run).

**`--limit`:** use `--limit <host>` or `--limit uf_linux` to touch only some hosts. `expected` runs on
homepc only and reads every host's inventory, so it needs `--limit homepc` (or no limit) and never
needs the other hosts to be up.

The Ansible key and the ProxyJump through HOMEPC are in `inventory/group_vars/uf_linux.yml`. Docker
Desktop's NAT hides source addresses, so nothing here is identified by IP.

## 3. Day-to-day tags (all `never`)

| Tag | Hosts | Example | Notes |
|---|---|---|---|
| `status` | UF hosts | `--tags status --limit wd2l-recv` | read-only: service, version (rpm or MSI) and build, `last_connect`, `last_close`, apps, FIPS; on Windows also the service account |
| `stop` / `start` / `restart` | UF hosts | `--tags stop --limit wd2l-recv` | posts a marker before each stop, start or restart that changes the service, and again after a start or restart, so the Overview says "Stopped with Ansible …" and the restart's own events aren't tamper findings |
| `verify` | all | `--tags verify` | read-only: UFs running on the vault's current token and connected through Cribl, their `_internal` seen in Splunk, Cribl healthy, and every expected row seen. Fails on a `MISSING` or `NEVER_SEEN` row whose profile isn't sporadic |
| `cribl_block` | homepc | see below | a test block in Cribl |
| `download` | pi5 (`--limit pi5`) | `--tags download --limit pi5` | the UF packages |

**Test blocks** are set with `cribl_block`, from the command the Manage dashboard shows (Test blocks
tab), or by hand:

```bash
ansible-playbook site.yml --tags cribl_block --limit homepc -e hl_block_key='wd2l-recv|linux_secure|*' \
  -e hl_block_minutes=30 -e "hl_block_reason='E2E row 4'"
ansible-playbook site.yml --tags cribl_block --limit homepc -e hl_block_key='wd2l-recv|linux_secure|*' -e hl_block_clear=true
ansible-playbook site.yml --tags cribl_block --limit homepc     # no key: only prunes expired rows
```

The key is `host|*|*`, `host|sourcetype|*` or `host|sourcetype|<exact raw source>`, with the host
short and lowercase. A block lasts at most 24 h (1440 minutes), needs a reason of 3–120 plain
characters, and applies only to `linux`, `windows` and `network`. Set and cleared blocks take effect
in about 15–17 s. Expiry is checked per event, so a block stops exactly at its time; nothing prunes
Cribl's table on a schedule, and expired rows leave it at the next `cribl_block` run. `cribl_block`
is the only tag that adds or removes blocks in Splunk's mirror (`hl_server_base/lookups/hl_ingest_block.csv`);
`cribl` (when it seeds an empty Cribl table) and `cribl_remove` only reset it to its header. The
Manage form writes nothing.

**Turning things off:**
- One input, on every host that has it: `-e '{"hl_disabled_inputs":["monitor:///var/log/secure"]}' --tags apps,expected`.
  Run the same tags without `-e` to turn it back on. For one host or permanently, set
  `hl_disabled_inputs` in that host's `host_vars`, then `--tags apps --limit <host>` and
  `--tags expected --limit homepc`.
- One forwarder: `--tags stop --limit <host>`. Mute it on the Manage dashboard first if it will stay
  off.
- Change an input's profile or criticality, or declare its maximum silence: `hl_input_overrides` in
  `host_vars` (for example `{"monitor:///var/log/cron": {profile: sporadic, criticality: 4}}`).

**Variables** you can set with `-e`, or in `group_vars` / `host_vars`. Every variable is documented
in `roles/homelab_splunk/meta/argument_specs.yml`, with defaults in `defaults/main.yml`.

| Variable | Default | Effect |
|---|---|---|
| `hl_disabled_inputs` | `[]` | input stanzas left out of the forwarder apps and the expected list |
| `hl_input_overrides` | `{}` | per-stanza `profile`, `criticality`, `enabled`, `track_source`, `max_gap_secs` |
| `hl_expected` | `true` | per host; `false` stops rendering the host's UF rows (see §4) |
| `dh_extra_expected` | `[]` | expected rows Ansible can't derive (what reaches Splunk through wd2l); `group_vars/splunk_server.yml` |
| `hl_block_key`, `hl_block_minutes` (60), `hl_block_reason`, `hl_block_clear` (`false`) | | `cribl_block`, above |
| `hl_apps_only` | `[]` | limit `server`, `server_remove` and `apps_remove` to these apps; `-e '{"hl_apps_only":["hl_uf_wd2l_inputs"]}'` |
| `hl_owner`, `hl_site`, `hl_host_criticality` | `taylorb`, `home`, `2` | the host's columns in the expected list |
| `hl_server_force_restart` | `false` | `server` restarts splunkd even with nothing changed |
| `hl_cribl_selftest` | `true` | after a Cribl change, send one test line per device port and wait for it in Splunk |
| `hl_cribl_hold_on_splunk_restart` | `true` | pause Cribl during a splunkd restart so no UF data is lost; `false` loses about 3 s of UF data instead of the UDP gap |
| `hl_probe_interval` | `60` | seconds between probe rounds |
| `hl_uf_connect_timeout` | `180` | seconds to wait for a UF to connect through Cribl |
| `hl_verify_status_wait` | `150` | seconds `verify` waits while every row is `PENDING` |
| `hl_purge_index_data` | `false` | `server_remove` also deletes the removed indexes' data |
| `hl_uninstall_without_baseline` | `false` | let `uninstall` check its contract without the install baselines |
| `hl_uninstall_accept_new_units` | `false` | let the contract pass when unit files appeared while the UF was installed |

## 4. Removing things (all `never`)

Run in reverse deploy order. Tags always run in the role's order, so one command with several tags is
safe. Each removal checks a **contract** and fails the play if anything is left.

| Tag | Hosts | Removes | The contract checks |
|---|---|---|---|
| `uninstall` | UF hosts | the UF, its apps, tamper rules, the account, packages the role added | rpm/MSI, folders, units, account, mail spool, `~/.splunk`, `auditctl -l` = the install-time baseline (the STIG rules left out), no new unowned files; Windows: uninstall key, service key, group memberships, user rights |
| `apps_remove` | UF hosts | the role's input apps (and the TAs' role-owned `local/inputs.conf`); `-e '{"hl_apps_only":[…]}'` for some | `hl_uf_outputs` stays unless named, so the heartbeat continues |
| `audit_rules_remove` | Linux UF hosts | the STIG rules (`zz-hl-zz-stig.rules`) | `auditctl -l` = the baseline before the first `audit_rules` |
| `audit_policy_remove` | homepc | restores `auditpol` from the backup | the policy matches the backup row by row |
| `probe_remove` | pi5 | hl-devprobe's units, script, logrotate, log folder | nothing is left |
| `cribl_remove` | homepc | the `cribl` container, its volume and the compose folder | `docker ps -a`, `docker volume ls`; the image stays |
| `server_remove` | homepc | the Splunk apps and their KV collections; `hl-net` (if the role created it and nothing else is attached); index data only with `-e hl_purge_index_data=true` | the apps, collections and network; `wd2l-splunk`'s ports and volumes unchanged; HEC healthy |

A full removal: `--tags audit_policy_remove,audit_rules_remove,probe_remove,uninstall,cribl_remove,server_remove`.

**`uninstall` alone does not retire a host's expected rows**, because a host that is merely off must
stay expected. To retire them, set `hl_expected: false` in the host's `host_vars` (or remove the host
from `uf_linux` / `uf_windows`) and run `--tags expected --limit homepc`. That retires only the
host's UF-derived rows (its host row and input rows). Any `dh_extra_expected` row naming the host
stays, because that data doesn't depend on the UF. **Don't pass `-e hl_expected=false`:** an extra
var overrides every host's value, so that run would retire every UF host's rows.

The inventory is the normal way. When it lags behind a host's real removal, an admin can retire the
host from the app (Manage → Expected list → *Retire an expected item*); *DH Sync expected* then
leaves those rows disabled while the inventory still lists them (the run's output counts them as
`held`) and lets go once the inventory drops them. Nothing is deleted.

To put a host back: `--tags install,apps,audit_rules --limit <host>`, then remove the
`hl_expected: false` line and run `--tags expected --limit homepc`. Until the install, its rows read
"Uninstalled with Ansible at … by … and not installed again". **A reinstalled UF re-reads every monitored file from the start** (it has no record of what
the old one read), so everything still in those files is indexed again: about 17,000 duplicate
events on wd2l-recv in task 14, 596 of them in `wd2l_uf_audit`.

## 5. Things to know

**Never run the `splunk` CLI as root on a UF.** `sudo splunk btool …` makes `splunk` run `chown -R`
over `/opt/splunkforwarder`, which fires the `hl-uf-config` audit rule and raises a false tamper
finding. Run it as the UF's own user: `sudo -u splunkfwd /opt/splunkforwarder/bin/splunk btool
inputs list <stanza> --debug`.

**The Dashboard risky-command check is off, by choice** (`hl_server_base/default/web.conf`,
`enable_risky_command_check_dashboard = false`). Manage's Apply writes with `outputlookup`, so with
the check on, Dashboard Studio holds every Apply until the viewer clicks "Run Query". It matters
because the setting covers every dashboard on this Splunk, wd2l's included: a dashboard search with
`outputlookup`, `collect` or `delete` now runs without a prompt. The Search page check stays on. To
turn it back on, delete that file or set the value to `true`, then run `--tags server`, which restarts
splunkd.

**`cribl` doesn't undo an edit made in Cribl's UI or API.** It compares the repo's files with its
own record of what it pushed, not with Cribl's live config, so after a UI edit it reports no change
and restarts nothing. Its load check ("Check Cribl loaded the role's inputs, outputs, routes,
pipelines and breakers") then fails if the edit changed the route list or removed one of the role's
objects; an edit inside a pipeline passes it. Undo the edit in Cribl (UI or API) and rerun `--tags
cribl --limit homepc` until it passes. An unmarked edit is a tamper finding, and it stays one: the
`cribl` run's marker comes after the edit, so it doesn't hide it (see the
[runbook](runbook-missing-data.md)).

Every role-made change shows up as an **Ansible marker** (`index=data_health source=dh:marker`,
fields `action`, `target_host`, `by`, `run_id`), so the data-health app knows the role's own work
from tampering.

### Searching

- Events delivered by Cribl have **no `punct` field**, so `dedup punct` or `by punct` silently drops
  them.
- `dh_*` objects (saved searches, macros, KV lookups) are visible only in the `hl_data_health` app
  context: use the HL Data Health app in Splunk Web, or
  `/servicesNS/nobody/hl_data_health/` over REST. A `/services/` search reads 0 rows with no error.

## 6. Troubleshooting

| Symptom | Look at |
|---|---|
| `install` fails at "Wait for the UF to connect to Cribl" | Cribl up? (`--tags verify --limit homepc`). Port 9997 on HOMEPC reachable from the host? A wrong token looks like an ordinary close: `--tags status` shows `last_connect` and `last_close`, and Cribl logs the refused token masked in `index=cribl`. The play waits `hl_uf_connect_timeout` (180 s) before it fails |
| `cribl` fails at "Check Cribl loaded the role's inputs, outputs, routes, pipelines and breakers" | Cribl's live config differs from the repo's, most likely an edit in Cribl's UI or API: see [§5](#5-things-to-know). Undo it in Cribl, then rerun |
| `cribl` stops at "The Cribl image is not on HOMEPC" | pull it in a desktop session (setup step 5) |
| `cribl` stops at `hl-net is missing` | run `--tags server_network` first |
| `cribl` fails at "Set the admin password" (its output is hidden) | Cribl refused both the vault's password and `admin`/`admin`: the container's password was changed outside the role. Put the current one in the vault, or `--tags cribl_remove` then `--tags cribl` (that deletes Cribl's volume: its config, lookups and queue) |
| `server` fails with btool findings | only findings in the role's apps fail the play; read the listed lines |
| a Docker command fails over SSH | Docker Desktop must be running in the signed-in session on HOMEPC |
| a VM is unreachable | the VMs are started by hand; `ansible_host` is `<vm>.mshome.net`, reached through HOMEPC's sshd |
| sudo asks for a password | add `-K` |
| "the rendered expected list has no rows" | the inventory groups `uf_linux` / `uf_windows` are empty |
| `verify` fails naming a row | that row is `MISSING` or `NEVER_SEEN`; see the [runbook](runbook-missing-data.md). When every row is `PENDING` it waits `hl_verify_status_wait`, then reports "Not evaluated" |
| a search returns nothing for `dh_*` or `punct` | [Searching](#searching) |
| no markers in `index=data_health source=dh:marker` | HEC 8088 not reachable from pi5, or a wrong `vault_hl_markers_token`; from pi5: `curl -k https://192.168.1.27:8088/services/collector/health`. A failed marker fails `cribl`, `cribl_block`, `cribl_remove` and the Linux `install`, `stop`, `start`, `restart` and `uninstall`; elsewhere it only warns |
| a false tamper finding `hl-uf-config` after a CLI command | the `splunk` CLI ran as root (see §5) |
| Overview shows "On hold" | see the banner rows in [dashboards.md](data-health/dashboards.md) |
