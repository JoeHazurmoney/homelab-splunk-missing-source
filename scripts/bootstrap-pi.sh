#!/usr/bin/env bash
# Prepare pi5 as the Ansible controller (spec 5.1). Run it on the Pi from the synced repo:
#   bash ~/homelab-splunk-missing-source/scripts/bootstrap-pi.sh
# Safe to re-run: every step checks before it changes anything, and existing keys, vault
# passwords and vault contents are never replaced.
#
# 1. ansible-core >= 2.18: from dnf when its candidate is new enough, otherwise a venv in
#    ~/.venvs/ansible; the commands are linked into ~/.local/bin.
# 2. ansible-lint + yamllint in ~/.venvs/ansible-lint (the same checks CI runs).
# 3. The collections in ansible/requirements.yml.
# 4. The Ansible SSH key ~/.ssh/id_ecdsa_homelab_ansible (ECDSA P-256: the VMs' sshd is FIPS).
# 5. The vault: password file ~/.config/hl_splunk/vault-pass, ANSIBLE_VAULT_PASSWORD_FILE in
#    ~/.bashrc.d/hl-ansible.sh, and ansible/inventory/group_vars/all/vault.yml with random values,
#    encrypted (the plaintext never touches the disk).
# It needs sudo only if ansible-core comes from dnf.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ansible_dir=$repo/ansible
min_core=2.18
core_spec='ansible-core>=2.18,<2.22'
lint_spec='ansible-lint yamllint'
venv=$HOME/.venvs/ansible
lint_venv=$HOME/.venvs/ansible-lint
bin_dir=$HOME/.local/bin
key=$HOME/.ssh/id_ecdsa_homelab_ansible
key_comment=homelab-ansible@pi5
vault=$ansible_dir/inventory/group_vars/all/vault.yml
vault_pass=$HOME/.config/hl_splunk/vault-pass
rc_file=$HOME/.bashrc.d/hl-ansible.sh

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
# version_ge A B: true when version A >= version B
version_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }
link_bins() { # link_bins <dir> <name>...: put the named commands from <dir> on PATH
  local dir=$1 name
  shift
  mkdir -p "$bin_dir"
  for name in "$@"; do
    if [ -x "$dir/$name" ]; then ln -sfn "$dir/$name" "$bin_dir/$name"; fi
  done
}

[ -f "$ansible_dir/requirements.yml" ] || die "run this from the synced repo (no $ansible_dir/requirements.yml)"

# --- 1. ansible-core ---
core_bins='ansible ansible-config ansible-console ansible-doc ansible-galaxy ansible-inventory ansible-playbook ansible-pull ansible-vault'
rpm_core=
if rpm -q ansible-core > /dev/null 2>&1; then rpm_core=$(rpm -q --qf '%{VERSION}' ansible-core); fi
if [ -x "$venv/bin/ansible" ]; then
  log "ansible-core: venv $venv exists; making sure it satisfies $core_spec"
  "$venv/bin/pip" install --quiet --disable-pip-version-check "$core_spec"
  ansible_bin=$venv/bin
elif [ -n "$rpm_core" ] && version_ge "$rpm_core" "$min_core"; then
  log "ansible-core: $rpm_core from dnf is already installed"
  ansible_bin=/usr/bin
else
  dnf_core=$(dnf -q repoquery --latest-limit 1 --qf '%{version}' ansible-core 2>/dev/null | tail -n1 || true)
  if [ -n "$dnf_core" ] && version_ge "$dnf_core" "$min_core"; then
    log "ansible-core: installing $dnf_core from dnf"
    sudo dnf install -y ansible-core
    ansible_bin=/usr/bin
  else
    log "ansible-core: dnf offers ${dnf_core:-nothing} (< $min_core); creating the venv $venv"
    mkdir -p "$(dirname "$venv")"
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet --disable-pip-version-check --upgrade pip
    "$venv/bin/pip" install --quiet --disable-pip-version-check "$core_spec"
    ansible_bin=$venv/bin
  fi
fi
if [ "$ansible_bin" = "$venv/bin" ]; then
  # shellcheck disable=SC2086  # word splitting of the command list is intended
  link_bins "$ansible_bin" $core_bins
fi
core_version=$("$ansible_bin/ansible" --version | head -n1)
log "using $core_version ($ansible_bin)"

# --- 2. lint tools ---
if [ ! -x "$lint_venv/bin/ansible-lint" ]; then
  log "lint: creating the venv $lint_venv"
  mkdir -p "$(dirname "$lint_venv")"
  python3 -m venv "$lint_venv"
  "$lint_venv/bin/pip" install --quiet --disable-pip-version-check --upgrade pip
fi
# shellcheck disable=SC2086  # word splitting of the package list is intended
"$lint_venv/bin/pip" install --quiet --disable-pip-version-check $lint_spec
link_bins "$lint_venv/bin" yamllint
# ansible-lint warns unless its venv's bin is on PATH, so it gets a wrapper instead of a link
# (rm first: writing through an old symlink would overwrite the venv's own entry point)
rm -f "$bin_dir/ansible-lint"
# shellcheck disable=SC2016  # $PATH and $@ are meant literally, for the wrapper
printf '#!/bin/sh\nPATH="%s/bin:$PATH" exec "%s/bin/ansible-lint" "$@"\n' "$lint_venv" "$lint_venv" > "$bin_dir/ansible-lint"
chmod 755 "$bin_dir/ansible-lint"
log "lint: $(PATH=$lint_venv/bin:$PATH ansible-lint --version | head -n1)"

# --- 3. collections ---
log "collections: installing from ansible/requirements.yml"
"$ansible_bin/ansible-galaxy" collection install -r "$ansible_dir/requirements.yml"

# --- 4. SSH key ---
if [ -f "$key" ]; then
  log "ssh key: $key exists"
else
  log "ssh key: creating $key (ECDSA P-256, no passphrase: Ansible runs unattended)"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ecdsa -b 256 -N '' -C "$key_comment" -f "$key"
fi
ssh-keygen -l -f "$key.pub" | grep -q '^256 .*(ECDSA)$' || die "$key is not an ECDSA P-256 key"

# --- 5. vault ---
if [ ! -f "$vault_pass" ]; then
  [ ! -f "$vault" ] || die "$vault exists but its password file $vault_pass is missing; restore it, or move the vault aside to generate a new one"
  log "vault: creating the password file $vault_pass"
  mkdir -p "$(dirname "$vault_pass")" && chmod 700 "$(dirname "$vault_pass")"
  (umask 077 && python3 -c 'import secrets; print(secrets.token_urlsafe(32))' > "$vault_pass")
fi
chmod 600 "$vault_pass"

rc_line="export ANSIBLE_VAULT_PASSWORD_FILE=\"\$HOME/.config/hl_splunk/vault-pass\""
if [ "$(cat "$rc_file" 2>/dev/null || true)" != "$rc_line" ]; then
  log "vault: setting ANSIBLE_VAULT_PASSWORD_FILE in $rc_file"
  mkdir -p "$(dirname "$rc_file")"
  printf '%s\n' "$rc_line" > "$rc_file"
fi
export ANSIBLE_VAULT_PASSWORD_FILE=$vault_pass

if [ -f "$vault" ]; then
  # shellcheck disable=SC2016  # the literal vault header
  head -n1 "$vault" | grep -q '^\$ANSIBLE_VAULT;' || die "$vault is not encrypted; encrypt it: ansible-vault encrypt $vault"
  "$ansible_bin/ansible-vault" view "$vault" > /dev/null || die "$vault does not decrypt with $vault_pass"
  log "vault: $vault exists and decrypts"
  for k in vault_hl_uf_admin_password vault_hl_s2s_token vault_hl_markers_token vault_hl_cribl_admin_password; do
    "$ansible_bin/ansible-vault" view "$vault" | grep -q "^$k:" ||
      log "vault: $k is missing; add it with: ansible-vault edit ${vault#"$repo"/} (see group_vars/all/vault.yml.example)"
  done
else
  log "vault: generating $vault with random values"
  {
    printf '# Generated by scripts/bootstrap-pi.sh on %s. Edit with: ansible-vault edit %s\n' "$(date -Is)" "${vault#"$repo"/}"
    printf 'vault_hl_uf_admin_password: "%s"\n' "$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
    printf 'vault_hl_s2s_token: "%s"\n' "$(python3 -c 'import uuid; print(uuid.uuid4())')"
    printf 'vault_hl_markers_token: "%s"\n' "$(python3 -c 'import uuid; print(uuid.uuid4())')"
    # Cribl wants 3 of 4 classes (lower, upper but not first, digit but not last, other): retry until all 4
    printf 'vault_hl_cribl_admin_password: "%s"\n' "$(python3 -c '
import re, secrets
while True:
    p = secrets.token_urlsafe(24)
    if re.search("[a-z]", p) and re.search("[A-Z]", p[1:]) and re.search("[0-9]", p[:-1]) and re.search("[^A-Za-z0-9]", p):
        print(p)
        break
')"
  } | (umask 077 && "$ansible_bin/ansible-vault" encrypt --output "$vault")
  chmod 600 "$vault"
fi

log "done. Public key to install on HOMEPC and the VMs (scripts/add-ansible-key.ps1 does this):"
cat "$key.pub"
