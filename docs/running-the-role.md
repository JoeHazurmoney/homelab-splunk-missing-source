# Running the role

This repo has one Ansible role, `homelab_splunk`. One playbook, `ansible/site.yml`, runs it on every
host the role manages. New to Ansible? The [glossary](glossary.md#ansible) explains playbook, role,
inventory, tags and vault.

These words are in the glossary too:

- The statuses: [OK, LATE, MISSING and NEVER_SEEN](glossary.md#status),
  [DOWN](glossary.md#roll-up) and [PENDING](glossary.md#pending-the-gate).
- A [profile](glossary.md#profile), and the [sporadic](glossary.md#sporadic) profile.
- The Overview, Host detail and Manage dashboards: see [the dashboards guide](data-health/dashboards.md).

**Tags pick what the role does.** A plain run deploys and never removes anything. It can restart
[splunkd](glossary.md#splunkd), Cribl or a UF when that service's config changed ([costs](#costs-of-a-run)). Removing,
stopping, restarting on demand and check-only runs each have their own tag. Those tags also carry
`never`, so they run only when you name them.

## How to run a command

You run every `ansible-playbook` command on [pi5](glossary.md#pi5), the Ansible controller.

1. Log in to pi5 from HOMEPC. Use Windows OpenSSH, not Git Bash's `ssh`
   ([why](#what-must-already-exist)).

   On HOMEPC, in PowerShell, any folder:

   ```powershell
   C:\Windows\System32\OpenSSH\ssh.exe pi5
   ```

   In this lab, the `pi5` alias and its key already exist on HOMEPC. You should get a shell on pi5. If
   the login fails, stop and ask the lab owner (in this lab: Taylor). For another lab, make the alias
   first ([values to change](#values-to-change-for-another-lab)).

2. Go to the repo's `ansible` folder and turn on the Ansible [venv](glossary.md#venv).

   On pi5, any folder:

   ```bash
   cd ~/homelab-splunk-missing-source/ansible
   . ~/.venvs/ansible/bin/activate
   ```

   If the second line says "No such file", your Ansible came from dnf. Skip that line.

The folder matters: its `ansible.cfg` names the inventory and the SSH key. `bootstrap-pi.sh` builds
the venv in [setup step 3](#step-3-set-up-ansible-on-pi5) only when dnf's ansible-core is too old.
On pi5 in this lab, the venv exists.

Below, each such block says **"On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on"**. That
means: run the two lines above first.

## 1. One-time setup

### What must already exist

The role deploys around these. It never creates them. Check each one before you start.

- [ ] **Docker Desktop is running.** "Signed-in session" means you are signed in to Windows on
  HOMEPC. Test: `docker ps` runs in PowerShell without an error.
- [ ] **The `wd2l-splunk` container is running** (Splunk 10.6.0.5). Test: `docker ps` shows it with a
  status that starts with "Up".
- [ ] **The Splunk admin password is in a file.** In this lab:
  `C:\Users\taylo\wd2l-splunk\secrets\splunk-admin-password`. Test: `Test-Path` on that file prints
  `True`.
- [ ] **A Splunk licence is in place.** Without a valid licence, alerts and roles stop. In this lab it
  is a Splunk Developer licence that expires on 2027-04-29
  ([details](architecture.md#indexes-and-retention)). The file is in
  `C:\Users\taylo\wd2l-splunk\secrets\`. Never commit it. Test: Splunk Web, Settings, Licensing.
- [ ] **Hyper-V has the two AlmaLinux VMs, and both are running.** You start them by hand, in Hyper-V
  Manager. Test: Hyper-V Manager shows both as Running.
- [ ] **`gh` (the GitHub CLI) is installed and signed in, with access to the repo.** Test:
  `gh auth status` shows you signed in.
- [ ] **An SSH alias `pi5` is in `~/.ssh/config` on HOMEPC.** Use it only through Windows OpenSSH
  (`C:\Windows\System32\OpenSSH\ssh.exe`). Git Bash's `ssh` can't use the Windows SSH agent, so it
  can't reach pi5. Test: [log in to pi5](#how-to-run-a-command).
- [ ] **HOMEPC's key `~\.ssh\id_ecdsa_wd2l_lab` logs in to the VMs.** In this lab the VM user is
  `taylorb`. [Step 4](#step-4-give-pi5s-key-to-the-vms-and-homepc) uses this key.
- [ ] **pi5 runs AlmaLinux 10 (aarch64), has `sudo` and has internet access.** It needs the internet
  for pip and `download.splunk.com`. Test: on pi5, `sudo -v` succeeds.

On HOMEPC, in PowerShell, any folder, the tests for the first three items are:

```powershell
docker ps --filter name=wd2l-splunk
Test-Path C:\Users\taylo\wd2l-splunk\secrets\splunk-admin-password
gh auth status
```

### Values to change for another lab

These files hold this lab's host names, users and addresses. Change them for other hosts:

- `ansible/inventory/hosts.yml` and `ansible/inventory/host_vars/`: the hosts and their users.
- `ansible/roles/homelab_splunk/defaults/main.yml`: HOMEPC's address and paths. They are
  `hl_collector`, `hl_marker_hec_url` and `hl_splunk_admin_password_file`.
- The `pi5` alias in `~/.ssh/config` on HOMEPC. The scripts use that name. Their `-PiHost` option
  sets another one.
- pi5's address, which you give `bootstrap-windows-sshd.ps1` in [step 1](#step-1-let-pi5-log-in-to-homepc).
- HOMEPC's address in the UDM's syslog setting, in [step 8](#step-8-point-the-udms-syslog-at-homepc).

### Setup steps

Do these once, in this order. The scripts on HOMEPC run in the root folder of a clone of this repo.
Clone it into any folder. `sync-to-pi.ps1` finds the repo from its own location. In this lab, the
clones live in `C:\Users\taylo\Documents\claude-code`. The repo is private here:
`JoeHazurmoney/homelab-splunk-missing-source`. Use its default branch, `main`.

On HOMEPC, in PowerShell, in the folder that will hold the clone:

```powershell
gh repo clone JoeHazurmoney/homelab-splunk-missing-source
cd homelab-splunk-missing-source
```

Windows 11 refuses local scripts by default. If PowerShell says running scripts is disabled, start
the script this way instead. On HOMEPC, in PowerShell, in the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\<name>.ps1
```

`<name>` is the script's name, such as `sync-to-pi`. Put the script's options after it.

#### Step 1: let pi5 log in to HOMEPC

First, get pi5's IPv4 address. [Log in to pi5](#how-to-run-a-command). Then, on pi5, any folder:

```bash
hostname -I
```

Use the LAN address it prints. Then, on HOMEPC, in an **elevated** PowerShell (Run as administrator),
in the repo folder:

```powershell
.\scripts\bootstrap-windows-sshd.ps1 -AllowFrom <pi address>
```

`<pi address>` is pi5's IPv4 address. In this lab it is `192.168.1.120`. That is the script's
default, so here you can leave `-AllowFrom` out.

The script:

- installs OpenSSH Server and makes PowerShell its shell;
- opens the SSH port (22/tcp) to pi5 only;
- turns password logins off.

Admin accounts use the file `administrators_authorized_keys` for their keys. So pi5 logs in with
admin rights. To undo it all, run the script again with `-Remove`.

The last line it prints starts with `==> Done.` You can test the login after
[step 4](#step-4-give-pi5s-key-to-the-vms-and-homepc), when pi5 has a key.

#### Step 2: copy the repo to pi5

On HOMEPC, in PowerShell, in the repo folder:

```powershell
.\scripts\sync-to-pi.ps1
```

It copies the repo to `~/homelab-splunk-missing-source` on pi5. Later runs keep pi5's vault and
packages. Add `-IncludePackages` to send `ansible/files/packages/` too (step 6). The last line reads
`synced into ~/homelab-splunk-missing-source`.

#### Step 3: set up Ansible on pi5

On pi5, any folder:

```bash
bash ~/homelab-splunk-missing-source/scripts/bootstrap-pi.sh
```

The script sets up:

- ansible-core 2.18 or newer. It comes from dnf if dnf's version is new enough. If not, the script
  builds the venv `~/.venvs/ansible` and links its commands into `~/.local/bin`.
- ansible-lint and yamllint.
- The Ansible collections (bundles of modules) in `ansible/requirements.yml`.
- The Ansible SSH key `~/.ssh/id_ecdsa_homelab_ansible`.
- The vault (see [Secrets](#secrets)).

It asks for pi5's sudo password only when it installs ansible-core from dnf. Its progress lines start
with `==> `. The last lines are `==> done.` and pi5's public key.

If a line says `vault: <key> is missing`, add that key. Use the command in the line, and look at
`vault.yml.example` for its shape. [Secrets](#secrets) lists the four keys.

Then **log out of pi5 and log in again.** The new login sets `ANSIBLE_VAULT_PASSWORD_FILE` from
`~/.bashrc.d/hl-ansible.sh`.

#### Step 4: give pi5's key to the VMs and HOMEPC

On HOMEPC, in PowerShell, in the repo folder:

```powershell
.\scripts\add-ansible-key.ps1
```

It puts pi5's public key on the VMs and on HOMEPC. The VMs must be running. To leave them out, add
`-SkipVm`. The HOMEPC part needs elevation: run the script elevated, or accept the UAC prompt it
opens. For each VM it prints `added` or `already authorized`. It ends by showing the two checks in
step 7.

#### Step 5: pull the Cribl image

On HOMEPC, in PowerShell **in the desktop session** (not over SSH), any folder:

```powershell
docker pull cribl/cribl@sha256:cb2b2e32933e492f439b5825b0c36f420df2fa986fe36d5f31fce6755190eb71
```

Docker Desktop has no credential store over SSH, so the role never pulls images. To check the pull,
run this. It prints the image ID.

```powershell
docker image inspect --format "{{.Id}}" cribl/cribl@sha256:cb2b2e32933e492f439b5825b0c36f420df2fa986fe36d5f31fce6755190eb71
```

#### Step 6: put the packages on pi5

The packages go in `ansible/files/packages/` on pi5. Git ignores that folder, so a fresh clone
doesn't have it. Sending files never deletes what is already on pi5. A sent file replaces a file with
the same name. So you can do the two parts below in either order.

**The UF packages.** The `download` tag fetches the Splunk agent ([UF](glossary.md#universal-forwarder-uf))
packages from `download.splunk.com`. It creates the folder on pi5.

On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags download --limit pi5
ls ~/homelab-splunk-missing-source/ansible/files/packages/
```

It gets UF 10.6.1.1, build `b2ae2962645c`: the x86_64 and aarch64 rpm and the Windows MSI. It checks
each one against its sha256 in `hl_uf_packages` in `defaults/main.yml`. You should see `failed=0` in
the recap, and the three files in the listing.

**The add-ons ([TAs](glossary.md#add-on-ta)).** You copy these by hand. Search
`https://splunkbase.splunk.com/` for each app by name. Save each file under the name given here:

- Splunk Add-on for Unix and Linux: `splunk-add-on-for-unix-and-linux_1034.spl` (Splunk_TA_nix 10.3.4)
- Splunk Add-on for Microsoft Windows: `splunk-add-on-for-microsoft-windows_1103.spl`
  (Splunk_TA_windows 11.0.3)

If Splunkbase gives a file another name, rename it. The role checks the content by sha256.

In this lab a copy is kept outside the repo, in
`C:\Users\taylo\Documents\claude-code\splunk-ta-local\`. Create the folder, then copy both files in. On
HOMEPC, in PowerShell, in the repo folder:

```powershell
New-Item -ItemType Directory -Force ansible\files\packages
```

Then send them. On HOMEPC, in PowerShell, in the repo folder:

```powershell
.\scripts\sync-to-pi.ps1 -IncludePackages
```

You can also copy them straight to pi5. Their sha256 is pinned in `hl_tas` in `defaults/main.yml`.
The `apps` tag fails on a missing file or one that doesn't match.

#### Step 7: check that Ansible reaches every host

On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible uf_linux -m ansible.builtin.ping
ansible uf_windows -m ansible.windows.win_ping
```

Each host should answer `SUCCESS` with `pong`. If a VM fails, check that it is running. The hosts
are listed in [Hosts in this lab](architecture.md#hosts-in-this-lab).

#### Step 8: point the UDM's syslog at HOMEPC

The role never logs in to the [UDM](glossary.md#udm), so you set this by hand. In the UniFi Network
UI, turn on remote syslog. The menu path depends on your UniFi version. Use these values:

- Server: HOMEPC's address. In this lab: `192.168.1.27`.
- Port: `5514`, UDP.

You don't need a new Windows firewall rule. Docker Desktop's existing rule lets the UDM's packets in.

If you skip this step, nothing fails. The Overview shows the UDM as missing after an hour. That is
expected ([status words](glossary.md#status)). Its cause reads "The device answers the network probe
but sends no logs: its logging settings probably changed". `verify` only reports the UDM row,
because its [profile](glossary.md#profile) is [sporadic](glossary.md#sporadic).

### Secrets

Secrets are never in the repo.

| Secret | Where it lives |
|---|---|
| The [vault](glossary.md#vault) | `inventory/group_vars/all/vault.yml` on pi5, encrypted. |
| The vault's password | `~/.config/hl_splunk/vault-pass`, on pi5 only. |
| The Splunk admin password | On HOMEPC. In this lab: `C:\Users\taylo\wd2l-splunk\secrets\splunk-admin-password`. |

The Splunk admin password is also the Splunk Web login for the user `admin`.

About the vault:

- It holds four keys: `vault_hl_uf_admin_password`, `vault_hl_s2s_token`, `vault_hl_markers_token`
  and `vault_hl_cribl_admin_password`.
- `vault_hl_s2s_token` is the [S2S](glossary.md#s2s-splunktcp) token. The UFs, Cribl and Splunk all
  use it. `vault_hl_markers_token` is the [HEC](glossary.md#hec-http-event-collector) token for
  [markers](glossary.md#marker-ansible-marker).
- `bootstrap-pi.sh` creates the vault with random values. It reports any key that is missing.
  `vault.yml.example` shows the vault's shape.

The role reads the Splunk admin password from its file at each REST call. It never copies it.

To edit the vault: on pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-vault edit inventory/group_vars/all/vault.yml
```

**To read one value,** such as the Cribl admin password: on pi5, in
`~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-vault view inventory/group_vars/all/vault.yml | grep vault_hl_cribl_admin_password
```

Ansible opens the vault with the password file named in `ANSIBLE_VAULT_PASSWORD_FILE` (set in
step 3). Cribl's login is the user `admin` and this password. Never paste the value anywhere.

`vault_hl_s2s_token_previous` exists only during a token rotation. A rotation has a fixed order:
follow [Rotating the S2S token](#rotating-the-s2s-token).

### After you change the repo

pi5 holds a copy of the repo, not a git clone. After any change on HOMEPC, copy it again.

On HOMEPC, in PowerShell, in the repo folder:

```powershell
.\scripts\sync-to-pi.ps1
```

## 2. Deploy

**Warning: a deploy can restart splunkd and lose UDP syslog for a short time.** The UDM sends
[UDP syslog](glossary.md#syslog-udp-syslog), and nobody resends a line lost in the gap. See
[Costs of a run](#costs-of-a-run).

A plain run deploys everything. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml
```

That is the same as `--tags deploy`. Every deploy task carries the tag `deploy`. The run goes through
the tags below, in this order. None of them removes anything. A few restart a service when its config
changed. Each tag can also run alone. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags apps --limit wd2l-recv
ansible-playbook site.yml --tags install --limit homepc
```

In the table, "UF hosts" means the groups `uf_linux` and `uf_windows`. "Linux UF hosts" means
`uf_linux`. [Hosts in this lab](architecture.md#hosts-in-this-lab) lists the names.

| Tag | Runs on | What it does | Needs first |
|---|---|---|---|
| `server` | homepc | Deploys the Splunk apps `hl_server_base` and `hl_data_health`. | `wd2l-splunk` running. Docker Desktop signed in. |
| `server_network` | homepc | Puts `wd2l-splunk` on the Docker network `hl-net`. | `wd2l-splunk` running. |
| `cribl` | homepc | Deploys the `cribl` container and its config. | The image ([step 5](#step-5-pull-the-cribl-image)), `hl-net` and the vault. |
| `install` | UF hosts | Installs the pinned UF and proves it connects through Cribl. | The UF package on pi5. Cribl up. |
| `apps` | UF hosts | Deploys the TAs and the role's input apps. | The TA packages on pi5, and `install`. |
| `audit_rules` | Linux UF hosts | Loads the [hardened audit rules](glossary.md#hardened-audit-rules). | The [`audit-rules` package](#audit-rules-package). |
| `audit_policy` | homepc | Turns on a focused set of Windows audit policy. | The elevated SSH session. |
| `probe` | pi5 | Installs the [device probe](glossary.md#device-probe-hl-devprobe). | `syslog_devices` in the inventory. |
| `expected` | homepc | Builds and syncs the [expected list](glossary.md#expected-list). | `server`. |

### First deploy: what you should see

1. **The recap.** Each host ends with `failed=0` and `unreachable=0` in the `PLAY RECAP`:

   ```
   wd2l-recv : ok=... changed=... unreachable=0 failed=0 skipped=... rescued=0 ignored=0
   ```

   If `failed` isn't 0, read the first red error, then see [Troubleshooting](#6-troubleshooting).
2. **Run `verify`.** You don't need to wait first. While every row is [PENDING](glossary.md#pending-the-gate),
   `verify` waits up to 150 s (`hl_verify_status_wait`) and checks every 15 s. A status needs up to
   about 2 min to show after data arrives ([why](data-health-design.md#how-long-until-late-missing-or-down)).
   On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags verify
   ```

3. **A pass** ends with `failed=0`. A debug line lists any LATE rows and any
   [sporadic](glossary.md#sporadic) rows that are quiet. They don't fail the run.
4. **"Not evaluated" is a failure.** It means every row was still PENDING after 150 s. Wait 5 min for
   *DH Evaluate*, then run `verify` again. Repeat until it passes. If it keeps failing, read the
   Overview's [banner](data-health/dashboards.md#the-banner-is-the-data-current).
5. **A healthy Overview** shows a green banner that starts "Up to date". The *Needs attention* table is
   empty. Items that haven't sent anything yet read PENDING for their first hour. That is normal.

[Verify](#verify) says exactly what `verify` fails on.

### What each deploy tag does

- **`server`** swaps each app's `default/` folder. It keeps `local/` and the lookups the UI wrote. It
  restarts splunkd only when `indexes`, `inputs`, `props` or `web` conf changes. Otherwise it reloads.
- **`server_network`** creates `hl-net` and attaches `wd2l-splunk` to it live. It attaches it again
  if needed.
- **`cribl`** runs the container with Docker Compose, the image by digest and 2
  [workers](glossary.md#worker). It sets Cribl's admin password and pushes the repo's `cribl/` config.
  After a change it runs a self-test (`hl_cribl_selftest`, below).
- **`install`** installs the pinned UF and the app `hl_uf_outputs`. That app sends to Cribl, with the
  S2S token and `useACK`, which makes the UF resend until Cribl confirms each batch. On a host whose
  kernel runs in [FIPS mode](glossary.md#fips-mode), the UF gets FIPS mode too. `install` also sets the
  UF to start at boot. On Linux, it adds the audit rules that watch the UF's own files.
- **`apps`** deploys the TAs unchanged, plus the role's input apps. It restarts the UF only when
  something changed.
- **`audit_rules`** writes the hardened audit rules to `/etc/audit/rules.d/zz-hl-zz-stig.rules`. They
  are the `audit-rules` package's sample rules plus privileged-command rules. The file loads last on
  purpose. The tag undoes itself if it would remove any of wd2l's audit rules.
- **`audit_policy`** backs up `auditpol` once. Then it turns on the focused subset. It only adds
  settings.
- **`probe`** installs `hl-devprobe`, a [systemd timer](glossary.md#systemd-timer) on pi5. Every 60 s it
  pings each syslog device.
  It writes the result to `/var/log/hl-devprobe/probe.log`, which pi5's UF reads. The devices are
  `syslog_devices` in `inventory/group_vars/splunk_server.yml`.
- **`expected`** builds the expected list from the whole inventory. Then it runs *DH Sync expected*,
  the saved search that merges that list into the app.

### `audit-rules` package

The `audit_rules` tag reads the sample rules in `/usr/share/audit-rules/`. They are
[auditd](glossary.md#auditd-audit-rules) rules. The role doesn't install
the `audit-rules` package. It must already be on each Linux UF host. To check, run this on pi5, in
`~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible uf_linux -m command -a 'rpm -q audit-rules'
```

Each host should print a package name and version. If one says the package is not installed, install
`audit-rules` with dnf on that host. Then run `audit_rules` again. Use the same Ansible form to run
one command on any host ([how to reach a host](runbook-missing-data.md#how-to-reach-a-host)).

**Keep the probe's path.** pi5's UF input watches exactly `/var/log/hl-devprobe/probe.log`. That
input doesn't follow `hl_probe_dir`. So leave `hl_probe_dir` at its default, or the probe's data stops.

### Costs of a run

- A rerun with nothing to change restarts nothing.
- A `server` run that restarts splunkd pauses Cribl for about 2 min 13 s. UDP syslog (the UDM) sent
  in that time is lost. UF data arrives up to 2.5 min late.
- A run restarts a service only when that service's config changed. These tags can restart one:
  `server` (splunkd), `cribl` (Cribl), `install` (a UF, when its outputs changed) and `apps` (a UF,
  when something changed).
- A `cribl` run that changes a file does a plain `docker restart cribl`. That costs about 12 s of UDP
  syslog.
- Both post markers, so the app knows the gap was the role's own work.
- A splunkd restart outside the role has no Cribl hold. Examples are a restart from Splunk Web or
  `docker exec … splunk restart`. In the [fault-injection run](records/2026-11-fault-injection-run.md),
  one such restart lost one 30-s sample on three of the four UFs. That is about 10–25 s of UF data.

### Listing the tags

On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --list-tags
```

It lists every tag. It also shows `never` and `always`. `always` is Ansible's own tag on the role's
argument check, which runs on every run.

### Choosing hosts with `--limit`

- `--limit <host>` or `--limit uf_linux` runs on only those hosts. `<host>` is an inventory name,
  such as `wd2l-recv`. [Hosts in this lab](architecture.md#hosts-in-this-lab) lists them. On pi5,
  `ansible-inventory --graph` shows the groups and their hosts.
- `expected` runs on homepc only. It reads every host's inventory, so use `--limit homepc` or no
  limit. The other hosts don't need to be up.

The Ansible key and the [ProxyJump](glossary.md#ssh-proxyjump) through HOMEPC are set in
`inventory/group_vars/uf_linux.yml`. How each host is reached, and why nothing is found by IP:
[architecture.md](architecture.md#hosts-and-data-paths).

## 3. Day-to-day and one-time tags (all `never`)

| Tag | Runs on | What it does |
|---|---|---|
| `status` | UF hosts | Reports each UF's state. Read-only. |
| `stop`, `start`, `restart` | UF hosts | Stops, starts or restarts the UF, with markers. |
| `verify` | all | Checks collection end to end. Read-only. |
| `cribl_block` | homepc | Sets or clears a [test block](#test-blocks) in Cribl. |
| `download` | pi5 | Fetches the UF packages ([step 6](#step-6-put-the-packages-on-pi5)). |

### Status

On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags status --limit wd2l-recv
```

It reports the service, the version (rpm or MSI) and build, `last_connect`, `last_close`, the apps
and FIPS. On Windows it also reports the service account.

### Stop, start and restart

On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags stop --limit wd2l-recv
ansible-playbook site.yml --tags start --limit wd2l-recv
ansible-playbook site.yml --tags restart --limit wd2l-recv
```

Each one posts an Ansible [marker](glossary.md#marker-ansible-marker):

- before every stop;
- before a start or restart that changes the service;
- again after a start or restart, once the UF is connected.

So the Overview says "Stopped with Ansible …", and the restart's own events aren't tamper findings.

A failed start is the one catch. The `start` marker goes out before the start, so after a failed
start it is the host's last marker. The cause then moves from "Stopped with Ansible … and not started
again" to a general Splunk agent cause. A failed `install` after `uninstall` works the same way.

### Verify

On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags verify
```

It only reads. It checks that:

- each UF runs on the vault's current token and is connected through Cribl;
- Splunk has each UF's `_internal` data;
- Cribl is healthy;
- no expected item is `MISSING` or `NEVER_SEEN`, unless its [profile](glossary.md#profile) is
  [sporadic](glossary.md#sporadic).

How it treats each status:

- A row that is `MISSING` or `NEVER_SEEN` and not sporadic fails the play.
- A row that is new and under an hour old is `PENDING`. It passes.
- A `LATE` row, and a sporadic row that is `MISSING` or `NEVER_SEEN`, are only reported.
- If every row is still `PENDING` after `hl_verify_status_wait` (150 s), the play **fails** with "Not
  evaluated". Wait about 5 min for *DH Evaluate*, then run it again.

### Test blocks

A [test block](glossary.md#test-block) drops a host's real data in Cribl, in the pipeline
`pl_test_block`. Use it to test the alerting end to end. The status stays real, and the row is
labelled "test block until hh:mm".

Set blocks with `cribl_block`. The Manage dashboard's Test blocks tab shows the command to run. You
can also write it by hand.

On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
# Set a 30-minute block
ansible-playbook site.yml --tags cribl_block --limit homepc -e hl_block_key='wd2l-recv|linux_secure|*' \
  -e hl_block_minutes=30 -e "hl_block_reason='Test the missing data alert'"

# Clear it before it ends
ansible-playbook site.yml --tags cribl_block --limit homepc -e hl_block_key='wd2l-recv|linux_secure|*' -e hl_block_clear=true

# No key: only prune expired rows
ansible-playbook site.yml --tags cribl_block --limit homepc
```

The rules:

- The key is `host|*|*`, `host|sourcetype|*` or `host|sourcetype|<exact raw source>`. Write the host
  short and in lowercase.
- A block lasts 1 to 1440 minutes (24 h). The default is 60.
- Setting a block needs a reason of 3–120 plain characters.
- Blocks apply only to the `linux`, `windows` and `network` indexes.

Timing:

- A set or a clear takes effect in Cribl about 15–17 s after the role's API update.
- Allow up to 45 s. The [fault-injection run](records/2026-11-fault-injection-run.md) measured 28–45 s
  before the first dropped event, with the API write included.
- A block stops dropping data at its "until" time, because Cribl checks the expiry on each event.
- Nothing removes expired rows from Cribl's table on a schedule. They leave it at the next
  `cribl_block` run.

Who writes the block table:

- `cribl_block` is the only tag that adds or removes blocks in Splunk's copy of the table,
  `hl_server_base/lookups/hl_ingest_block.csv`.
- `cribl` (when it seeds an empty Cribl table) and `cribl_remove` only reset that copy to its header.
- The Manage form writes nothing.

Cribl's audit log records every block change. `cribl_block` posts markers, so its own changes aren't
tamper findings. A change made any other way is one.

### Turning things off

**One input, on every host that has it.** On pi5, in `~/homelab-splunk-missing-source/ansible`,
venv on:

```bash
# Turn it off
ansible-playbook site.yml -e '{"hl_disabled_inputs":["monitor:///var/log/secure"]}' --tags apps,expected

# Turn it back on: the same tags, without -e
ansible-playbook site.yml --tags apps,expected
```

**One input on one host, or for good.** Set `hl_disabled_inputs` in that host's `host_vars` file.
Sync the repo. Then, on pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags apps --limit <host>
ansible-playbook site.yml --tags expected --limit homepc
```

**One forwarder.** If it will stay off, mute it on the Manage dashboard first. Then, on pi5, in
`~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags stop --limit <host>
```

**An input's [profile](glossary.md#profile), [criticality](glossary.md#criticality) or longest
silence.** Set `hl_input_overrides` in the host's `host_vars`. For example, in `ansible/inventory/host_vars/<host>.yml` on HOMEPC:

```yaml
hl_input_overrides: {"monitor:///var/log/cron": {profile: sporadic, criticality: 4}}
```

### Variables

Set these with `-e`, or in `group_vars` or `host_vars`. Every variable is documented in
`roles/homelab_splunk/meta/argument_specs.yml`. The defaults are in `defaults/main.yml`.

| Variable | Default | Effect |
|---|---|---|
| `hl_disabled_inputs` | `[]` | Input stanzas left out of the forwarder apps and the expected list. |
| `hl_input_overrides` | `{}` | Per-stanza `profile`, `criticality`, `enabled`, `track_source` and `max_gap_secs`. |
| `hl_expected` | `true` | Per host. `false` stops building the host's UF rows ([Retiring a host](#retiring-a-host)). |
| `dh_extra_expected` | `[]` | Expected rows Ansible can't derive, such as data that reaches Splunk through wd2l. Set in `group_vars/splunk_server.yml`. |
| `hl_block_key` | `""` | The test block's key ([Test blocks](#test-blocks)). |
| `hl_block_minutes` | `60` | How long the test block lasts. |
| `hl_block_reason` | `""` | Why the block is set. |
| `hl_block_clear` | `false` | `true` clears the block named by `hl_block_key`. |
| `hl_apps_only` | `[]` | Limits `server`, `server_remove` and `apps_remove` to these apps. |
| `hl_owner`, `hl_site`, `hl_host_criticality` | `taylorb`, `home`, `2` | The host's columns in the expected list. |
| `hl_server_force_restart` | `false` | `server` restarts splunkd even when nothing changed. |
| `hl_cribl_selftest` | `true` | After a Cribl change, sends one test line per device port and waits for it in Splunk. That line makes the device look alive for about one [limit](glossary.md#limit-threshold). |
| `hl_cribl_hold_on_splunk_restart` | `true` | Pauses Cribl during a splunkd restart, so no UF data is lost. `false` loses about 3 s of UF data instead of the UDP gap. |
| `hl_probe_interval` | `60` | Seconds between probe rounds. |
| `hl_uf_connect_timeout` | `180` | Seconds to wait for a UF to connect through Cribl. |
| `hl_verify_status_wait` | `150` | Seconds `verify` waits while every row is `PENDING`. |
| `hl_purge_index_data` | `false` | `server_remove` also deletes the removed indexes' data. |
| `hl_uninstall_without_baseline` | `false` | Lets `uninstall` check its contract without the install baselines. |
| `hl_uninstall_accept_new_units` | `false` | Lets the contract pass when unit files appeared while the UF was installed. |

An `hl_apps_only` example, on pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags apps_remove -e '{"hl_apps_only":["hl_uf_wd2l_inputs"]}'
```

## 4. Removing things (all `never`)

Remove in reverse deploy order. Tags always run in the role's order, so one command with several
tags is safe. Each removal checks a **contract**, a list of things that must be gone. The play fails
if anything is left.

| Tag | Runs on | Removes |
|---|---|---|
| `audit_policy_remove` | homepc | Restores `auditpol` from the backup. |
| `audit_rules_remove` | Linux UF hosts | The hardened audit rules (`zz-hl-zz-stig.rules`). |
| `probe_remove` | pi5 | hl-devprobe's units, script, logrotate file and log folder. |
| `apps_remove` | UF hosts | The role's input apps, and the role's `local/inputs.conf` in the TAs. |
| `uninstall` | UF hosts | The UF, its apps, the tamper rules, the account and packages the role added. |
| `cribl_remove` | homepc | The `cribl` container, its volume and the compose folder. |
| `server_remove` | homepc | The Splunk apps and their [KV store](glossary.md#kv-store) collections, and `hl-net` when safe. |

What each contract checks:

- **`audit_policy_remove`**: the policy matches the backup, row by row.
- **`audit_rules_remove`**: `auditctl -l` equals the baseline from before the first `audit_rules`.
- **`probe_remove`**: nothing is left.
- **`apps_remove`**: `hl_uf_outputs` stays unless you name it, so the heartbeat goes on. After a
  change, the role restarts the UF and checks it is still connected through Cribl. It skips that
  check when you named `hl_uf_outputs`, because the UF then sends nothing. Use `hl_apps_only` to
  remove only some apps.
- **`uninstall`**: nothing of the UF is left. That means no rpm or MSI, folders, units, account, mail
  spool or `~/.splunk`.
  - `auditctl -l` equals the install-time baseline, leaving out the hardened audit rules.
  - There are no new unowned files.
  - On Windows it also checks the uninstall key, the service key, group memberships and user rights.
- **`cribl_remove`**: `docker ps -a` and `docker volume ls` show nothing left. The image stays.
- **`server_remove`**: the apps, collections and network are gone. `wd2l-splunk`'s ports and volumes
  are unchanged, and HEC is healthy. It removes `hl-net` only if the role created it and nothing else
  is attached. Index data stays unless you add `-e hl_purge_index_data=true`.

A full removal, on pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags audit_policy_remove,audit_rules_remove,probe_remove,uninstall,cribl_remove,server_remove
```

### Retiring a host

**`uninstall` alone does not retire a host's expected rows.** A host that is only off must stay
expected. To [retire](glossary.md#retire) its rows:

1. In the host's `host_vars` file, set `hl_expected: false`. Or remove the host from `uf_linux` or
   `uf_windows` in the inventory.
2. [Sync the repo](#after-you-change-the-repo) to pi5.
3. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags expected --limit homepc
   ```

That retires only the host's UF-derived rows: its host row and its input rows. A
`dh_extra_expected` row that names the host stays, because that data doesn't depend on the UF.

**Don't pass `-e hl_expected=false`.** An extra var overrides every host's value. That run would
retire every UF host's rows.

The inventory is the normal way. Sometimes it lags behind a host's real removal. Then an admin can
retire the host in the app: Manage → Expected list → *Retire an expected item*. *DH Sync expected*
then keeps those rows disabled while the inventory still lists them. The run's output counts them as
`held`. Once the inventory drops them, the hold ends. Nothing is deleted.

### Putting a host back

On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags install,apps,audit_rules --limit <host>
```

Then remove the `hl_expected: false` line from the host's `host_vars`, and sync the repo. Then, on
pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags expected --limit homepc
```

Until the install, the host's rows read "Uninstalled with Ansible at … by … and not installed again".

**A reinstalled UF reads every monitored file again from the start.** It has no record of what the
old UF read. So everything still in those files is indexed again. In the fault-injection run that
was about 17,000 duplicate events on wd2l-recv, 596 of them in `wd2l_uf_audit`.

## 5. Things to know

### Never run `splunk` as root on a UF

`sudo splunk` [`btool`](glossary.md#btool) makes `splunk` run `chown -R` (a recursive ownership
change) over `/opt/splunkforwarder`. That fires the `hl-uf-config` [audit rule](glossary.md#auditd-audit-rules)
and raises a false tamper finding.
Run the CLI as the UF's own user, `splunkfwd`.

On a Linux UF host, any folder:

```bash
sudo -u splunkfwd /opt/splunkforwarder/bin/splunk btool inputs list <stanza> --debug
```

`<stanza>` is an `inputs.conf` stanza, such as `monitor:///var/log/secure`. See
[`btool`](glossary.md#btool).

Don't run this through `ansible <host> -b`. The `-b` flag runs the command as root, so it raises the
same false finding. On pi5, you are already on the host. For a VM, ask the lab owner (in this lab:
Taylor) for a shell on it. The role has no tested way to run `btool` as `splunkfwd` through Ansible.

### The Dashboard risky-command check is off

The setting is `enable_risky_command_check_dashboard = false`, in `hl_server_base/default/web.conf`.
It is off by choice:

- Manage's Apply writes with `outputlookup`. With the check on, Dashboard Studio holds every Apply
  until the viewer clicks "Run Query".
- The cost: the setting covers every dashboard on this Splunk, wd2l's too. A dashboard search with
  `outputlookup`, `collect` or `delete` now runs without a prompt.
- The Search page check stays on.

To turn the check back on, delete that file or set the value to `true`. Sync the repo. Then, on pi5,
in `~/homelab-splunk-missing-source/ansible`, venv on:

```bash
ansible-playbook site.yml --tags server
```

That run restarts splunkd.

### `cribl` doesn't undo edits made in Cribl

`cribl` compares the repo's files with its own record of what it pushed. It doesn't read Cribl's live
config. So after an edit in Cribl's UI or API, it reports no change and restarts nothing.

Its load check, "Check Cribl loaded the role's inputs, outputs, routes, pipelines and breakers", may
still catch it. It fails if the edit changed the route list or removed one of the role's objects. An
edit inside a pipeline passes it.

To fix it, undo the edit in Cribl:

1. Read Cribl's admin password ([how](#secrets)). The login is the user `admin`.
2. Open Cribl's UI. In this lab it is `http://127.0.0.1:9000` on HOMEPC.
3. Find the object the tamper indicator names, such as the pipeline `pl_test_block`.
4. Compare it with the repo's copy, and put it back as the repo has it. The files are in the repo's
   `cribl/local/cribl/` folder:
   - `pipelines/<name>/conf.yml` for a pipeline, and `pipelines/route.yml` for the route list.
   - `inputs.yml` for sources, `outputs.yml` for destinations and `breakers.yml` for event breakers.
5. Run this until it passes. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags cribl --limit homepc
   ```

A plain `cribl` run doesn't put the edit back. It only checks that the role's objects exist. The role
adds one syslog source per device to `inputs.yml` and fills in the S2S token, so those two values
differ from the repo's file. Don't use `cribl_remove` to reset Cribl. It deletes Cribl's volume and
the evidence of the edit.

An unmarked edit is a tamper finding, and it stays one. The `cribl` run's marker comes after the
edit, so it doesn't hide it (see the [runbook](runbook-missing-data.md)).

### Ansible markers

Every change the role makes shows up as an Ansible [marker](glossary.md#marker-ansible-marker). The
app uses markers to tell the role's own work from tampering. To see them, search in Splunk:

```
index=data_health source=dh:marker
```

Their fields are `action`, `target_host`, `by` and `run_id`.

### Searching

- Events that Cribl delivers have **no `punct` field**. So `dedup punct` or `by punct` silently drops
  them.
- `dh_*` objects (saved searches, macros, KV lookups) are visible only in the `hl_data_health` app
  context. Use the HL Data Health app in Splunk Web. Over REST, use
  `/servicesNS/nobody/hl_data_health/`. A `/services/` search reads 0 rows, with no error.

### Rotating the S2S token

Rotating `vault_hl_s2s_token` has three phases: expand, migrate, contract. Done in this order, it
loses nothing. `vault_hl_s2s_token_previous` keeps the old token accepted while the senders move.
Run the steps in order.

1. **Vault.** Make a new token. Set `vault_hl_s2s_token` to it, and set
   `vault_hl_s2s_token_previous` to the old value. The method is the one in
   [spec §14.11](specs/2026-10-30-design.md#1411-retention-and-token-rotation-2026-11-07) row 5. It
   works in a private folder, so no plain copy of the vault stays on disk. On pi5, in
   `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   umask 077
   work=$(mktemp -d)
   cp inventory/group_vars/all/vault.yml ~/vault.before-rotation
   ansible-vault decrypt inventory/group_vars/all/vault.yml --output "$work/vault.yml"
   python3 -c 'import uuid; print(uuid.uuid4())'
   ```

   The last command prints the new token. Edit `$work/vault.yml` with an editor. Copy the old
   `vault_hl_s2s_token` value to a new line, `vault_hl_s2s_token_previous: "<old>"`. Then put the
   new token in `vault_hl_s2s_token`. Then, in the same shell:

   ```bash
   ansible-vault encrypt "$work/vault.yml" --output inventory/group_vars/all/vault.yml
   shred -u "$work/vault.yml"
   rmdir "$work"
   ansible-vault view inventory/group_vars/all/vault.yml | grep -c '^vault_hl_'
   ```

   The last command must print `5`: the four keys plus the previous token. The copy
   `~/vault.before-rotation` is the old vault, still encrypted. Keep it until the rotation is
   finished.
2. **Expand.** On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags server --limit homepc
   ansible-playbook site.yml --tags cribl --limit homepc
   ```

   Splunk now accepts both tokens, through `[splunktcptoken://hl_cribl_previous]`. Cribl's
   `in_splunk_tcp` lists both, and `out_splunk` presents the new one. `server` must come first, or
   Splunk refuses Cribl's new token.
3. **Migrate.** On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags install --limit uf_linux:uf_windows
   ```

   Each UF presents the new token and restarts. Cribl still accepts any UF that hasn't moved yet.
4. **Check for stragglers.** On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags verify --limit uf_linux:uf_windows
   ```

   It must be green on every UF. It fails on a UF in either of these states:
   - `HL_TOKEN=stale`: its `default/outputs.conf` isn't on the vault's current token.
   - `HL_TOKEN=not_applied`: the file is right, but the running splunkd isn't using it. Either it
     started before the file was written, or a local token is older than the file. This is the loss
     the procedure exists to prevent.

   `install` can't heal `not_applied`, because the template reports no change. Instead, delete the
   `token` line from the UF's `hl_uf_outputs/local/outputs.conf`. Then, on pi5, in
   `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags restart --limit <host>
   ```

   **On a Linux UF, this hand edit raises an `hl-uf-config` tamper finding**, unless a marker covers
   it. A marker covers it only if it comes just before the edit or a minute after
   ([the window](data-health-design.md#tamper-indicators)). The `restart` run here comes later, so it
   doesn't. *DH Alert tamper* fires for the finding. That is expected here.

   Tell the analysts the host and the time of the edit before you make it. Then they can recognise
   the finding and don't escalate it
   ([how analysts read tamper findings](data-health/dashboards.md#tamper-findings-24-h)). A marker
   posted later never hides it.

5. **Contract.** Remove `vault_hl_s2s_token_previous` from the vault. Then run `cribl` first and
   `server` second. Cribl then stops accepting the old token before Splunk does, and it already
   presents the new one. On pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags cribl --limit homepc
   ansible-playbook site.yml --tags server --limit homepc
   ```

6. **Check the end state.** These commands print counts only. Never run `btool inputs list` without
   the `grep -c`, because it prints the `token` lines. Each must print `0`. On HOMEPC, in
   PowerShell, any folder:

   ```powershell
   docker exec -u 0 wd2l-splunk sh -c "grep -c hl_cribl_previous /opt/splunk/etc/apps/hl_server_base/local/inputs.conf"
   docker exec -u splunk wd2l-splunk sh -c "/opt/splunk/bin/splunk btool inputs list | grep -c hl_cribl_previous"
   ```

   Then, on pi5, in `~/homelab-splunk-missing-source/ansible`, venv on:

   ```bash
   ansible-playbook site.yml --tags cribl --limit homepc
   ansible-playbook site.yml --tags verify --limit uf_linux:uf_windows
   ```

   - The `cribl` run must end `changed=0`. Its load check fails unless Cribl's API has loaded exactly
     the expected number of `authTokens`: 1 now, 2 during a rotation. It reports only that count.
   - `verify` must be green on every UF.

   Finally, on pi5, run `shred -u ~/vault.before-rotation` to remove the encrypted copy of the old
   vault.

**What it costs.** Each run of steps 2 and 5 costs what those tags always cost
([Costs of a run](#costs-of-a-run)):

- A `server` run restarts splunkd with the Cribl hold. About 2 min of UDP syslog is lost per run, and
  UF data is delayed up to about 2.5 min.
- A `cribl` run restarts Cribl. It is about 12 s without its UDP listeners (measured
  14:47:16.5–14:47:28.2).

**Never edit the vault's previous value by hand mid-rotation, and never change the steps' order.**
The role refuses a previous value that equals the current one or isn't a UUID.

**`cribl reload` is not a shortcut.** After a reload, the running workers still refused a token that
was only in the pushed `inputs.yml`. The API still listed the old list
([spec §14.13](specs/2026-10-30-design.md#1413-loss-free-s2s-token-rotation-2026-11-08) row 5). Pushed
files need the restart.

**Cribl logs a refused token as a 3+4-character mask in `index=cribl`.** So a mistyped token leaks 7
characters there.

## 6. Troubleshooting

Run each `ansible-playbook` command here on pi5, in `~/homelab-splunk-missing-source/ansible`, venv
on.

### `install` fails at "Wait for the UF to connect to Cribl"

The play waits `hl_uf_connect_timeout` (180 s) before it fails. Check these:

1. Is Cribl up?

   ```bash
   ansible-playbook site.yml --tags verify --limit homepc
   ```

2. Can the host reach the [S2S](glossary.md#s2s-splunktcp) port 9997 on HOMEPC?
3. Is the token wrong? A wrong token looks like an ordinary close. `--tags status` shows
   `last_connect` and `last_close`:

   ```bash
   ansible-playbook site.yml --tags status --limit <host>
   ```

   Cribl also logs the refused token, masked, in `index=cribl`.

### `cribl` fails at "Check Cribl loaded the role's inputs, outputs, routes, pipelines and breakers"

Cribl's live config differs from the repo's. Most likely someone edited it in Cribl's UI or API. Undo
the edit in Cribl, then run `cribl` again
([`cribl` doesn't undo edits made in Cribl](#cribl-doesnt-undo-edits-made-in-cribl)).

### `cribl` stops at "The Cribl image is not on HOMEPC"

Pull the image in a desktop session ([step 5](#step-5-pull-the-cribl-image)).

### `cribl` stops at "hl-net is missing"

Create the network first:

```bash
ansible-playbook site.yml --tags server_network
```

### `cribl` fails at "Set the admin password" (its output is hidden)

Cribl refused both the vault's password and `admin`/`admin`. Someone changed the container's password
outside the role. Do one of these:

- Put the current password in the vault.
- Remove Cribl and deploy it again. This deletes Cribl's volume: its config, lookups and queue.

  ```bash
  ansible-playbook site.yml --tags cribl_remove
  ansible-playbook site.yml --tags cribl
  ```

### `server` fails with btool findings

Only findings in the role's apps fail the play. Read the lines it lists.

### A Docker command fails over SSH

Docker Desktop must be running in the signed-in session on HOMEPC.

### A VM is unreachable

You start the VMs by hand, so check that it is running. Its `ansible_host` is `<vm>.mshome.net`,
reached through HOMEPC's sshd.

### sudo asks for a password

Add `-K` to the command. Ansible then asks for the sudo password.

### "the rendered expected list has no rows"

The inventory groups `uf_linux` and `uf_windows` are empty.

### `verify` fails naming a row

That row is `MISSING` or `NEVER_SEEN`, and its profile isn't sporadic. See the
[runbook](runbook-missing-data.md). When every row is `PENDING`, `verify` waits
`hl_verify_status_wait`, then fails with "Not evaluated". Wait about 5 min and run it again
([first deploy](#first-deploy-what-you-should-see)).

### A search returns nothing for `dh_*` or `punct`

See [Searching](#searching).

### No markers in `index=data_health source=dh:marker`

Either [HEC](glossary.md#hec-http-event-collector) port 8088 isn't reachable from pi5, or
`vault_hl_markers_token` is wrong. Check HEC's health. On pi5, any folder:

```bash
curl -k https://192.168.1.27:8088/services/collector/health
```

In this lab HOMEPC is `192.168.1.27`. A healthy HEC answers `{"text":"HEC is healthy","code":17}`.

A failed marker fails these tags: `cribl`, `cribl_block`, `cribl_remove`, and on Linux `install`,
`apps`, `apps_remove`, `stop`, `start`, `restart` and `uninstall`. Elsewhere it only warns.

### A false `hl-uf-config` tamper finding after a CLI command

The `splunk` CLI ran as root. See [Never run `splunk` as root on a UF](#never-run-splunk-as-root-on-a-uf).

### The Overview shows "On hold"

See the banner rows in [dashboards.md](data-health/dashboards.md).
