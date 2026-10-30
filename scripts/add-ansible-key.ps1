#Requires -Version 5.1
<#
.SYNOPSIS
    Authorize the Pi's Ansible key on the VMs and on HOMEPC (spec 5.1).
.DESCRIPTION
    Run on HOMEPC after scripts/bootstrap-pi.sh (which creates the key) and
    scripts/bootstrap-windows-sshd.ps1. Idempotent.
      1. Reads ~/.ssh/id_ecdsa_homelab_ansible.pub from the Pi (ssh pi5).
      2. Appends it to ~/.ssh/authorized_keys of taylorb on each VM, logging in with this PC's
         existing key ~/.ssh/id_ecdsa_wd2l_lab. The VMs must be running.
      3. Adds it to C:\ProgramData\ssh\administrators_authorized_keys through
         bootstrap-windows-sshd.ps1 -AuthorizedKey (the key text, not a file). That needs
         elevation: run this script from an elevated PowerShell, or accept the UAC prompt it
         opens; that window stays open on failure, and the log is
         C:\ProgramData\hl_bootstrap\bootstrap-sshd.log.
.EXAMPLE
    .\scripts\add-ansible-key.ps1
.EXAMPLE
    .\scripts\add-ansible-key.ps1 -SkipVm
#>
[CmdletBinding()]
param(
    # ssh host (alias in ~/.ssh/config) of the Pi
    [string]$PiHost = 'pi5',
    # The public key on the Pi, relative to the home directory
    [string]$PiKeyPath = '.ssh/id_ecdsa_homelab_ansible.pub',
    # VM names; each is reached as <name>.<VmDomain>
    [string[]]$Vm = @('wd2l-logsrv', 'wd2l-recv'),
    [string]$VmDomain = 'mshome.net',
    [string]$VmUser = 'taylorb',
    # This PC's existing key for the VMs
    [string]$VmKey = (Join-Path $env:USERPROFILE '.ssh\id_ecdsa_wd2l_lab'),
    # Leave out the VMs (for example while they are off)
    [switch]$SkipVm,
    # Leave out HOMEPC itself
    [switch]$SkipWindows
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
    Write-Information "==> $Message" -InformationAction Continue
}
# Full path: from Git Bash, PATH would pick its own ssh (no access to the Windows ssh-agent).
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'

# 1. The Pi's public key. The strict pattern also guarantees it is safe inside the single-quoted
#    shell words below (no quotes, no shell metacharacters).
$key = ((& $ssh $PiHost "cat $PiKeyPath") | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not read $PiKeyPath on $PiHost; run scripts/bootstrap-pi.sh there first" }
if ($key -notmatch '^ecdsa-sha2-nistp256 [A-Za-z0-9+/]+={0,2} [A-Za-z0-9@._-]+$') {
    throw "Unexpected key from ${PiHost}: $key"
}
Write-Step "Pi key: $key"

# 2. The VMs
if (-not $SkipVm) {
    # No double quotes in the remote command: Windows PowerShell 5.1 drops them on the way to ssh.exe.
    $remote = "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; " +
        "if grep -qxF -e '$key' ~/.ssh/authorized_keys; then echo already authorized; " +
        "else echo '$key' >> ~/.ssh/authorized_keys; echo added; fi; " +
        "if command -v restorecon >/dev/null; then restorecon -R ~/.ssh; fi"
    foreach ($name in $Vm) {
        $target = "$VmUser@$name.$VmDomain"
        Write-Step "Authorizing the key on $target"
        & $ssh -i $VmKey -o IdentitiesOnly=yes $target $remote
        if ($LASTEXITCODE -ne 0) { throw "ssh to $target failed (exit $LASTEXITCODE); is the VM running?" }
    }
}

# 3. HOMEPC (administrators_authorized_keys, needs elevation)
if (-not $SkipWindows) {
    # The key travels as a parameter, never through a file another process could swap before the
    # elevated run reads it; the bootstrap validates it again.
    $bootstrap = Join-Path $PSScriptRoot 'bootstrap-windows-sshd.ps1'
    $log = Join-Path $env:ProgramData 'hl_bootstrap\bootstrap-sshd.log'
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Step 'Authorizing the key on HOMEPC'
        & $bootstrap -AuthorizedKey $key
        $exitCode = $LASTEXITCODE
    }
    else {
        Write-Step 'Authorizing the key on HOMEPC in an elevated window (accept the UAC prompt)'
        # -PauseOnError keeps that window open if it fails, so the error can be read
        $argList = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -AuthorizedKey "{1}" -PauseOnError' -f $bootstrap, $key
        $exitCode = (Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $argList).ExitCode
    }
    if ($exitCode -ne 0) {
        throw "bootstrap-windows-sshd.ps1 failed (exit $exitCode); see $log"
    }
}

Write-Step 'Done. Check from the Pi (ssh pi5), in ~/homelab-splunk-missing-source/ansible:'
Write-Step '  ansible uf_linux:syslog_relay -m ansible.builtin.ping'
Write-Step '  ansible uf_windows -m ansible.windows.win_ping'
