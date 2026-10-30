#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-time, elevated: let Ansible on the Pi reach HOMEPC over OpenSSH (spec 5.1).
.DESCRIPTION
    Idempotent; run it again at any time. It:
      1. installs the OpenSSH Server capability (if sshd is missing),
      2. allows 22/tcp from the Pi only (its own firewall rule; the capability's any-address rule is disabled),
      3. makes Windows PowerShell the default shell of SSH sessions,
      4. sets sshd to start automatically and starts it,
      5. with -AuthorizedKeyFile, adds that public key to C:\ProgramData\ssh\administrators_authorized_keys
         (the file sshd uses for members of Administrators, so the session is elevated) and locks the
         file to Administrators and SYSTEM. scripts/add-ansible-key.ps1 calls this for the Pi's key.
    Everything it changes is recorded in C:\ProgramData\hl_bootstrap\sshd.json; -Remove undoes
    exactly that and nothing else.
.EXAMPLE
    .\scripts\bootstrap-windows-sshd.ps1
.EXAMPLE
    .\scripts\bootstrap-windows-sshd.ps1 -AuthorizedKeyFile $env:TEMP\pi5.pub
.EXAMPLE
    .\scripts\bootstrap-windows-sshd.ps1 -Remove
#>
[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    # The only address allowed to connect to 22/tcp (pi5)
    [Parameter(ParameterSetName = 'Install')]
    [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}$')]
    [string]$AllowFrom = '192.168.1.120',

    # A file with one or more OpenSSH public keys to authorize for administrators
    [Parameter(ParameterSetName = 'Install')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$AuthorizedKeyFile,

    # Undo what earlier runs recorded
    [Parameter(ParameterSetName = 'Remove', Mandatory = $true)]
    [switch]$Remove
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateDir = Join-Path $env:ProgramData 'hl_bootstrap'
$StateFile = Join-Path $StateDir 'sshd.json'
$RuleName = 'HL-OpenSSH-Server-From-Pi'
$BuiltinRuleName = 'OpenSSH-Server-In-TCP'
$KeysFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
$OpenSshRegKey = 'HKLM:\SOFTWARE\OpenSSH'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$KeyPattern = '^(ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|ssh-rsa) [A-Za-z0-9+/]+={0,3}( .*)?$'

function Write-Step([string]$Message) {
    Write-Information "==> $Message" -InformationAction Continue
}

function Read-State {
    $state = @{
        CapabilityName = $null; CapabilityInstalled = $false
        FirewallRuleCreated = $false; BuiltinRuleDisabled = $false
        DefaultShellSet = $false; PreviousDefaultShell = $null
        ServiceRecorded = $false; PreviousStartType = $null; PreviousStatus = $null
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

function Save-KeyFile([string[]]$Line) {
    # Other lines (comments, keys added by hand) are written back unchanged
    [IO.File]::WriteAllLines($KeysFile, [string[]]@($Line), (New-Object System.Text.ASCIIEncoding))
    Protect-KeyFile
}

function Protect-KeyFile {
    # sshd ignores the file unless only Administrators and SYSTEM can write it (SIDs: locale-proof)
    & icacls.exe $KeysFile /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed on $KeysFile (exit $LASTEXITCODE)" }
}

function Install-HlSshd([string]$AllowFrom, [string]$AuthorizedKeyFile) {
    $state = Read-State

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
    $builtin = Get-NetFirewallRule -Name $BuiltinRuleName -ErrorAction SilentlyContinue
    if ($builtin -and "$($builtin.Enabled)" -eq 'True') {
        Write-Step "Disabling the capability's any-address rule $BuiltinRuleName"
        Disable-NetFirewallRule -Name $BuiltinRuleName
        $state.BuiltinRuleDisabled = $true
        Save-State $state
    }

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

    # 5. Authorized key(s)
    if ($AuthorizedKeyFile) {
        $new = @(Read-KeyLine $AuthorizedKeyFile)
        if (-not $new) { throw "$AuthorizedKeyFile has no public key" }
        foreach ($k in $new) { if ($k -notmatch $KeyPattern) { throw "Not an OpenSSH public key: $k" } }
        $keysDir = Split-Path -Parent $KeysFile
        if (-not (Test-Path -LiteralPath $keysDir)) { throw "$keysDir is missing; is sshd installed?" }
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
    Write-Step "Done. State: $StateFile"
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
        Write-Step "C:\ProgramData\ssh (host keys, sshd_config) is left in place; delete it by hand for a clean slate"
    }
    else {
        if ($svc -and $state.ServiceRecorded) {
            Set-Service -Name sshd -StartupType $state.PreviousStartType
            if ($state.PreviousStatus -eq 'Stopped') { Stop-Service -Name sshd -Force }
            Write-Step "sshd is back to $($state.PreviousStartType) / $($state.PreviousStatus)"
        }
        if ($state.BuiltinRuleDisabled -and (Get-NetFirewallRule -Name $BuiltinRuleName -ErrorAction SilentlyContinue)) {
            Enable-NetFirewallRule -Name $BuiltinRuleName
            Write-Step "Re-enabled firewall rule $BuiltinRuleName"
        }
    }

    Remove-Item -LiteralPath $StateFile
    if (-not (Get-ChildItem -LiteralPath $StateDir)) { Remove-Item -LiteralPath $StateDir }
    Write-Step 'Removed everything the bootstrap had recorded'
}

if ($Remove) { Uninstall-HlSshd } else { Install-HlSshd -AllowFrom $AllowFrom -AuthorizedKeyFile $AuthorizedKeyFile }
