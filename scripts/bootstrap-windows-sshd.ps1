#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-time, elevated: let Ansible on the Pi reach HOMEPC over OpenSSH (spec 5.1).
.DESCRIPTION
    Idempotent; run it again at any time. It:
      1. installs the OpenSSH Server capability (if sshd is missing),
      2. allows 22/tcp from the Pi only (its own firewall rule; the capability's any-address rule
         is disabled, checked again after sshd has started),
      3. makes Windows PowerShell the default shell of SSH sessions,
      4. sets sshd to start automatically and starts it,
      5. turns off password logins (PasswordAuthentication no in sshd_config; only keys are used),
         checks the config with sshd -t and restarts sshd,
      6. with -AuthorizedKey or -AuthorizedKeyFile, adds the public key(s) to
         C:\ProgramData\ssh\administrators_authorized_keys (the file sshd uses for members of
         Administrators, so the session is elevated) and locks the file to Administrators and
         SYSTEM. scripts/add-ansible-key.ps1 calls this with -AuthorizedKey for the Pi's key.
    Everything it changes is recorded in C:\ProgramData\hl_bootstrap\sshd.json; -Remove undoes
    exactly that and nothing else. Progress and errors are also logged to
    C:\ProgramData\hl_bootstrap\bootstrap-sshd.log.
.EXAMPLE
    .\scripts\bootstrap-windows-sshd.ps1
.EXAMPLE
    .\scripts\bootstrap-windows-sshd.ps1 -AuthorizedKey 'ecdsa-sha2-nistp256 AAAA... homelab-ansible@pi5'
.EXAMPLE
    .\scripts\bootstrap-windows-sshd.ps1 -Remove
#>
[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    # The only address allowed to connect to 22/tcp (pi5)
    [Parameter(ParameterSetName = 'Install')]
    [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}$')]
    [string]$AllowFrom = '192.168.1.120',

    # OpenSSH public key line(s) to authorize for administrators
    [Parameter(ParameterSetName = 'Install')]
    [string[]]$AuthorizedKey,

    # A file with OpenSSH public key line(s) to authorize, for a direct elevated run
    [Parameter(ParameterSetName = 'Install')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AuthorizedKeyFile,

    # Undo what earlier runs recorded
    [Parameter(ParameterSetName = 'Remove', Mandatory = $true)]
    [switch]$Remove,

    # On failure, wait for Enter before exiting (keeps a separate elevated window open)
    [switch]$PauseOnError
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateDir = Join-Path $env:ProgramData 'hl_bootstrap'
$StateFile = Join-Path $StateDir 'sshd.json'
$LogFile = Join-Path $StateDir 'bootstrap-sshd.log'
$RuleName = 'HL-OpenSSH-Server-From-Pi'
$BuiltinRuleName = 'OpenSSH-Server-In-TCP'
$SshDir = Join-Path $env:ProgramData 'ssh'
$KeysFile = Join-Path $SshDir 'administrators_authorized_keys'
$SshdConfig = Join-Path $SshDir 'sshd_config'
$SshdExe = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'
$OpenSshRegKey = 'HKLM:\SOFTWARE\OpenSSH'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
# One key per line, no options prefix (so no command= or from= can ride along), no line breaks
$KeyPattern = '\A(ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|ssh-rsa) [A-Za-z0-9+/]+={0,3}( [!-~]+)?\z'
$PasswordMarker = '# hl_bootstrap: keys only. scripts/bootstrap-windows-sshd.ps1 -Remove restores the previous setting.'
$PasswordLine = 'PasswordAuthentication no'

function Write-Step([string]$Message) {
    Write-Information "==> $Message" -InformationAction Continue
    Write-LogLine $Message
}

function Write-LogLine([string]$Message) {
    if (-not (Test-Path -LiteralPath $StateDir)) { New-Item -ItemType Directory -Path $StateDir | Out-Null }
    Add-Content -LiteralPath $LogFile -Value ('{0:s} {1}' -f (Get-Date), $Message) -Encoding ascii
}

function Read-State {
    $state = @{
        CapabilityName = $null; CapabilityInstalled = $false
        FirewallRuleCreated = $false; BuiltinRuleDisabled = $false
        DefaultShellSet = $false; PreviousDefaultShell = $null
        ServiceRecorded = $false; PreviousStartType = $null; PreviousStatus = $null
        PasswordAuthChanged = $false; PasswordAuthPreviousLine = $null
        KeysFileCreated = $false; KeysAdded = @()
    }
    if (Test-Path -LiteralPath $StateFile) {
        $saved = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        foreach ($p in $saved.PSObject.Properties) { $state[$p.Name] = $p.Value }
        $state.KeysAdded = @($state.KeysAdded | Where-Object { $_ })
    }
    return $state
}

function Save-State([hashtable]$State) {
    if (-not (Test-Path -LiteralPath $StateDir)) { New-Item -ItemType Directory -Path $StateDir | Out-Null }
    $State | ConvertTo-Json | Out-File -LiteralPath $StateFile -Encoding ascii
}

function Read-RawLine([string]$Path) {
    if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path }
}

function Read-KeyLine([string]$Path) {
    Read-RawLine $Path | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Write-AsciiLine([string]$Path, [string[]]$Line) {
    # Overwrites the content only, so the file keeps its ACL
    [IO.File]::WriteAllLines($Path, [string[]]@($Line), (New-Object System.Text.ASCIIEncoding))
}

function Save-KeyFile([string[]]$Line) {
    # Other lines (comments, keys added by hand) are written back unchanged
    Write-AsciiLine $KeysFile $Line
    Protect-KeyFile
}

function Protect-KeyFile {
    # sshd ignores the file unless only Administrators and SYSTEM can write it (SIDs: locale-proof)
    & icacls.exe $KeysFile /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed on $KeysFile (exit $LASTEXITCODE)" }
}

function Disable-BuiltinRule([hashtable]$State) {
    # The capability adds an allow-from-any rule for 22/tcp, possibly only when sshd first starts,
    # so this runs both before and after sshd starts.
    $builtin = Get-NetFirewallRule -Name $BuiltinRuleName -ErrorAction SilentlyContinue
    if ($builtin -and "$($builtin.Enabled)" -eq 'True') {
        Write-Step "Disabling the capability's any-address rule $BuiltinRuleName"
        Disable-NetFirewallRule -Name $BuiltinRuleName
        $State.BuiltinRuleDisabled = $true
        Save-State $State
    }
}

function Test-SshdConfig {
    # Continue: in Windows PowerShell 5.1, redirected stderr of a native program would otherwise throw
    $ErrorActionPreference = 'Continue'
    $out = & $SshdExe -t 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sshd -t rejected $SshdConfig (exit $LASTEXITCODE): $out" }
}

function Disable-PasswordLogin([hashtable]$State) {
    # sshd writes sshd_config from sshd_config_default on its first start
    for ($i = 0; ($i -lt 15) -and -not (Test-Path -LiteralPath $SshdConfig); $i++) { Start-Sleep -Seconds 1 }
    if (-not (Test-Path -LiteralPath $SshdConfig)) { throw "$SshdConfig did not appear after sshd started" }
    $lines = @(Read-RawLine $SshdConfig)
    $marker = [array]::IndexOf([string[]]$lines, $PasswordMarker)
    if ($marker -ge 0 -and $marker + 1 -lt $lines.Count -and $lines[$marker + 1].Trim() -eq $PasswordLine) {
        Write-Step 'Password logins are already off'
        return
    }
    # The first global PasswordAuthentication wins, and global settings must come before any Match
    $match = -1
    $active = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*Match\s') { $match = $i; break }
        if ($active -lt 0 -and $lines[$i] -match '^\s*PasswordAuthentication\s') { $active = $i }
    }
    if ($active -ge 0 -and $lines[$active].Trim() -match '^PasswordAuthentication\s+no$') {
        Write-Step "Password logins are already off ($SshdConfig)"
        return
    }
    if ($active -ge 0) {
        $previous = $lines[$active]
        $new = @($lines | Select-Object -First $active) + $PasswordMarker + $PasswordLine +
            @($lines | Select-Object -Skip ($active + 1))
    }
    else {
        $previous = $null
        $at = if ($match -ge 0) { $match } else { $lines.Count }
        $new = @($lines | Select-Object -First $at) + $PasswordMarker + $PasswordLine + @($lines | Select-Object -Skip $at)
    }
    Write-Step "Turning off password logins in $SshdConfig (was: $(if ($previous) { $previous } else { 'not set, default yes' }))"
    $State.PasswordAuthChanged = $true
    $State.PasswordAuthPreviousLine = $previous
    Save-State $State
    Write-AsciiLine $SshdConfig $new
    try { Test-SshdConfig }
    catch {
        Write-AsciiLine $SshdConfig $lines
        $State.PasswordAuthChanged = $false
        $State.PasswordAuthPreviousLine = $null
        Save-State $State
        throw
    }
    Restart-Service -Name sshd
    Write-Step 'sshd restarted with password logins off'
}

function Restore-PasswordLogin([hashtable]$State) {
    if (-not $State.PasswordAuthChanged -or -not (Test-Path -LiteralPath $SshdConfig)) { return }
    $lines = @(Read-RawLine $SshdConfig)
    $marker = [array]::IndexOf([string[]]$lines, $PasswordMarker)
    if ($marker -lt 0) {
        Write-Step "The bootstrap's PasswordAuthentication line is gone from $SshdConfig; leaving the file as it is"
        return
    }
    $before = @($lines | Select-Object -First $marker)
    $after = @($lines | Select-Object -Skip ($marker + 2))
    $restored = if ($State.PasswordAuthPreviousLine) { $before + [string]$State.PasswordAuthPreviousLine + $after } else { $before + $after }
    Write-AsciiLine $SshdConfig $restored
    Write-Step "Restored the previous PasswordAuthentication setting in $SshdConfig"
}

function Get-RequestedKey([string[]]$Key, [string]$File) {
    $all = @($Key | Where-Object { $_ } | ForEach-Object { $_.Trim() })
    if ($File) { $all += @(Read-KeyLine $File) }
    foreach ($k in $all) { if ($k -cnotmatch $KeyPattern) { throw "Not a plain OpenSSH public key line: $k" } }
    return $all
}

function Install-HlSshd([string]$AllowFrom, [string[]]$AuthorizedKey, [string]$AuthorizedKeyFile) {
    $state = Read-State
    # Validate the key(s) before changing anything
    $new = @(Get-RequestedKey $AuthorizedKey $AuthorizedKeyFile)
    if (($AuthorizedKey -or $AuthorizedKeyFile) -and -not $new) { throw 'No public key was given' }

    # 1. OpenSSH Server
    if (-not (Get-Service -Name sshd -ErrorAction SilentlyContinue)) {
        $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
        if (-not $cap) { throw 'The OpenSSH.Server capability is not offered on this Windows build.' }
        Write-Step "Installing $($cap.Name) (takes a minute)"
        Add-WindowsCapability -Online -Name $cap.Name | Out-Null
        $state.CapabilityName = $cap.Name
        $state.CapabilityInstalled = $true
        Save-State $state
    }
    else { Write-Step 'OpenSSH Server is installed' }

    # 2. Firewall: 22/tcp from the Pi only, before sshd starts listening
    $rule = Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
    if (-not $rule) {
        Write-Step "Allowing 22/tcp from $AllowFrom only (firewall rule $RuleName)"
        New-NetFirewallRule -Name $RuleName -DisplayName "OpenSSH Server (sshd) from the Ansible Pi $AllowFrom" `
            -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress $AllowFrom -Action Allow -Profile Any | Out-Null
        $state.FirewallRuleCreated = $true
        Save-State $state
    }
    else {
        $current = ($rule | Get-NetFirewallAddressFilter).RemoteAddress
        if ("$current" -ne $AllowFrom) {
            Write-Step "Firewall rule $RuleName now allows $AllowFrom (was $current)"
            Set-NetFirewallRule -Name $RuleName -RemoteAddress $AllowFrom
        }
        else { Write-Step "Firewall rule $RuleName allows $AllowFrom" }
    }
    Disable-BuiltinRule $state

    # 3. Default shell
    $shell = (Get-ItemProperty -Path $OpenSshRegKey -Name DefaultShell -ErrorAction SilentlyContinue)
    $currentShell = if ($shell) { $shell.DefaultShell } else { $null }
    if ($currentShell -ne $PowerShellExe) {
        Write-Step "Default SSH shell: $PowerShellExe"
        if (-not $state.DefaultShellSet) { $state.PreviousDefaultShell = $currentShell }
        if (-not (Test-Path -LiteralPath $OpenSshRegKey)) { New-Item -Path $OpenSshRegKey -Force | Out-Null }
        New-ItemProperty -Path $OpenSshRegKey -Name DefaultShell -Value $PowerShellExe -PropertyType String -Force | Out-Null
        $state.DefaultShellSet = $true
        Save-State $state
    }

    # 4. Service
    $svc = Get-Service -Name sshd
    if (-not $state.ServiceRecorded) {
        $state.PreviousStartType = "$($svc.StartType)"
        $state.PreviousStatus = "$($svc.Status)"
        $state.ServiceRecorded = $true
        Save-State $state
    }
    if ("$($svc.StartType)" -ne 'Automatic') { Set-Service -Name sshd -StartupType Automatic }
    if ("$($svc.Status)" -ne 'Running') { Start-Service -Name sshd }
    Write-Step 'sshd is running and starts automatically'

    # 5. Keys only
    Disable-PasswordLogin $state
    Disable-BuiltinRule $state

    # 6. Authorized key(s)
    if ($new) {
        if (-not (Test-Path -LiteralPath $SshDir)) { throw "$SshDir is missing; is sshd installed?" }
        if (-not (Test-Path -LiteralPath $KeysFile)) {
            $state.KeysFileCreated = $true
            Save-State $state
        }
        $have = @(Read-KeyLine $KeysFile)
        $add = @($new | Where-Object { $have -notcontains $_ })
        if ($add) {
            Save-KeyFile (@(Read-RawLine $KeysFile) + $add)
            $state.KeysAdded = @($state.KeysAdded) + $add
            Save-State $state
            Write-Step "Authorized $($add.Count) key(s) for administrators in $KeysFile"
        }
        else {
            Protect-KeyFile
            Write-Step "The key is already authorized in $KeysFile"
        }
    }
    Write-Step "Done. State: $StateFile; log: $LogFile"
}

function Uninstall-HlSshd {
    if (-not (Test-Path -LiteralPath $StateFile)) {
        Write-Step "Nothing recorded in $StateFile; nothing to remove"
        return
    }
    $state = Read-State

    if ($state.KeysAdded -and (Test-Path -LiteralPath $KeysFile)) {
        $keep = @(Read-RawLine $KeysFile | Where-Object { $state.KeysAdded -notcontains $_.Trim() })
        if (($keep | Where-Object { $_.Trim() }) -or -not $state.KeysFileCreated) {
            Save-KeyFile $keep
            Write-Step "Removed the bootstrap's key(s) from $KeysFile"
        }
        else {
            Remove-Item -LiteralPath $KeysFile
            Write-Step "Deleted $KeysFile (it held only the bootstrap's key)"
        }
    }

    Restore-PasswordLogin $state

    if ($state.FirewallRuleCreated -and (Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue)) {
        Remove-NetFirewallRule -Name $RuleName
        Write-Step "Removed firewall rule $RuleName"
    }

    if ($state.DefaultShellSet) {
        if ($state.PreviousDefaultShell) {
            New-ItemProperty -Path $OpenSshRegKey -Name DefaultShell -Value $state.PreviousDefaultShell -PropertyType String -Force | Out-Null
        }
        elseif (Test-Path -LiteralPath $OpenSshRegKey) {
            Remove-ItemProperty -Path $OpenSshRegKey -Name DefaultShell -ErrorAction SilentlyContinue
        }
        Write-Step 'Restored the default SSH shell'
    }

    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($state.CapabilityInstalled) {
        if ($svc) { Stop-Service -Name sshd -Force }
        Write-Step "Removing $($state.CapabilityName)"
        $result = Remove-WindowsCapability -Online -Name $state.CapabilityName
        if ($result.RestartNeeded) { Write-Step 'Windows asks for a restart to finish removing OpenSSH Server' }
        # The capability's any-address rule came with it
        if (Get-NetFirewallRule -Name $BuiltinRuleName -ErrorAction SilentlyContinue) { Remove-NetFirewallRule -Name $BuiltinRuleName }
        Write-Step "$SshDir (host keys, sshd_config) is left in place; delete it by hand for a clean slate"
    }
    else {
        if ($svc -and $state.ServiceRecorded) {
            Set-Service -Name sshd -StartupType $state.PreviousStartType
            if ($state.PreviousStatus -eq 'Stopped') { Stop-Service -Name sshd -Force }
            elseif ($state.PasswordAuthChanged) { Restart-Service -Name sshd }
            Write-Step "sshd is back to $($state.PreviousStartType) / $($state.PreviousStatus)"
        }
        if ($state.BuiltinRuleDisabled -and (Get-NetFirewallRule -Name $BuiltinRuleName -ErrorAction SilentlyContinue)) {
            Enable-NetFirewallRule -Name $BuiltinRuleName
            Write-Step "Re-enabled firewall rule $BuiltinRuleName"
        }
    }

    Write-Step 'Removed everything the bootstrap had recorded'
    # Last: the state file, the log and the folder (no Write-Step after this, it would recreate the log)
    Remove-Item -LiteralPath $StateFile, $LogFile -ErrorAction SilentlyContinue
    if (-not (Get-ChildItem -LiteralPath $StateDir)) { Remove-Item -LiteralPath $StateDir }
}

try {
    if ($Remove) { Uninstall-HlSshd }
    else { Install-HlSshd -AllowFrom $AllowFrom -AuthorizedKey $AuthorizedKey -AuthorizedKeyFile $AuthorizedKeyFile }
}
catch {
    Write-LogLine "ERROR: $_"
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    Write-Information "Failed. Log: $LogFile" -InformationAction Continue
    if ($PauseOnError) { [void](Read-Host 'Press Enter to close this window') }
    exit 1
}
