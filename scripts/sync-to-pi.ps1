<#
.SYNOPSIS
    Copy this repository's working tree to the Pi (spec 5.1).
.DESCRIPTION
    Packs the working tree with tar.exe (without .git, .superpowers, vault files and, unless
    -IncludePackages, ansible/files/packages), copies it to the Pi with scp, and unpacks it there into
    ~/<Destination> with scripts/sync-receive.sh, which keeps the Pi-only vault and packages.
    The archive goes through a temp file and scp rather than a "tar | ssh" pipe, because Windows
    PowerShell 5.1 pipes between native programs as text and would corrupt the archive.
    Runs as the normal user; ssh to the Pi uses the Windows OpenSSH client and ssh-agent.
.EXAMPLE
    .\scripts\sync-to-pi.ps1
.EXAMPLE
    .\scripts\sync-to-pi.ps1 -IncludePackages
#>
[CmdletBinding()]
param(
    # ssh host (alias in ~/.ssh/config) of the Pi
    [string]$PiHost = 'pi5',
    # Target directory on the Pi: a plain name directly under the home directory (no ., .., / or leading dot)
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Destination = 'homelab-splunk-missing-source',
    # Also send ansible/files/packages/ (UF packages, TAs); large, so off by default
    [switch]$IncludePackages
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Full paths: from Git Bash, PATH would pick its own tar and ssh (which cannot reach the Pi).
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
$scp = Join-Path $env:SystemRoot 'System32\OpenSSH\scp.exe'
$repo = Split-Path -Parent $PSScriptRoot
$archive = Join-Path ([IO.Path]::GetTempPath()) ('hl-sync-{0}.tgz' -f [guid]::NewGuid())
$excludes = @(
    './.git', './.superpowers', './ansible/.ansible', './ansible/inventory/group_vars/all/vault.yml',
    '*.vault-pass', '.vault-pass*', '__pycache__'
)
if (-not $IncludePackages) { $excludes += './ansible/files/packages' }
$tarArgs = @('-c', '-z', '-f', $archive) + ($excludes | ForEach-Object { "--exclude=$_" }) + @('-C', $repo, '.')

try {
    & $tar @tarArgs
    if ($LASTEXITCODE -ne 0) { throw "tar failed (exit $LASTEXITCODE)" }
    & $scp -q $archive "${PiHost}:hl-sync.tgz"
    if ($LASTEXITCODE -ne 0) { throw "scp to $PiHost failed (exit $LASTEXITCODE)" }
    # No double quotes in the remote command: Windows PowerShell 5.1 drops them on the way to ssh.exe.
    $remote = 'set -e; s=.cache/hl-sync; rm -rf $s; mkdir -p $s; tar -xzf hl-sync.tgz -C $s; ' +
        'rm -f hl-sync.tgz; bash $s/scripts/sync-receive.sh $s ' + $Destination
    & $ssh $PiHost $remote
    if ($LASTEXITCODE -ne 0) { throw "unpacking on $PiHost failed (exit $LASTEXITCODE)" }
}
finally {
    Remove-Item -LiteralPath $archive -ErrorAction SilentlyContinue
}
