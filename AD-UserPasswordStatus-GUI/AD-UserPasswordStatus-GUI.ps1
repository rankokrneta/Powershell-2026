#requires -Version 5.1
<##
.SYNOPSIS
    GUI tool for checking Active Directory user password/lockout status and unlocking locked accounts.

.NOTES
    Author: Ranko Krneta
    Storage:
      - Config: same folder as this script
      - Optional saved credential: Windows DPAPI encrypted file in current user's LocalAppData
#>

$script:AppName = 'AD User Password / Lockout Check'
$script:AppVersion = '1.7.1-github-clean'
$script:AppAuthor = 'Ranko Krneta'
$script:ScriptPath = $MyInvocation.MyCommand.Path
$script:ScriptDir = Split-Path -Parent $script:ScriptPath
$script:ConfigPath = Join-Path $script:ScriptDir 'AD-UserPasswordStatus-GUI.config.json'
$script:CredentialDir = Join-Path $env:LOCALAPPDATA 'ADUserPasswordStatusGUI'
$script:CredentialPath = Join-Path $script:CredentialDir 'ad-credential.xml'
$script:ShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AD User Password Status GUI.lnk'
# GitHub-clean version: no environment-specific domain controllers are hardcoded.
# Add your own DC hostname/FQDN in the GUI with the + button, or use Discover DCs.
$script:DefaultDomainControllers = @()

$script:CurrentUser = $null
$script:CurrentSummary = ''
$script:AdCredential = $null
$script:CredentialSource = 'Current Windows session'
$script:StartupLog = New-Object System.Collections.Generic.List[string]

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue } catch { }

function Add-StartupLog {
    param([Parameter(Mandatory)][string]$Text)
    [void]$script:StartupLog.Add($Text)
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Message {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = $script:AppName,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon) | Out-Null
}

function Ensure-ActiveDirectoryModule {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
    }
    catch {
        $initialError = $_.Exception.Message
    }

    $capability = $null
    try {
        $capability = Get-WindowsCapability -Online -Name 'Rsat.ActiveDirectory.DS-LDS.Tools*' -ErrorAction Stop | Select-Object -First 1
    }
    catch {
        Show-Message "ActiveDirectory PowerShell module is not available and RSAT capability detection failed.`r`n`r`nInitial module error:`r`n$initialError`r`n`r`nCapability detection error:`r`n$($_.Exception.Message)" 'Missing Active Directory module' ([System.Windows.Forms.MessageBoxIcon]::Error)
        exit 1
    }

    if ($null -eq $capability) {
        Show-Message "ActiveDirectory PowerShell module is not available and Windows did not return the RSAT Active Directory capability.`r`n`r`nInstall RSAT manually: Active Directory Domain Services and Lightweight Directory Tools." 'Missing RSAT capability' ([System.Windows.Forms.MessageBoxIcon]::Error)
        exit 1
    }

    if ($capability.State -ne 'Installed') {
        if (-not (Test-IsAdministrator)) {
            $ask = [System.Windows.Forms.MessageBox]::Show(
                "RSAT Active Directory tools are not installed.`r`n`r`nThe tool needs Administrator elevation to install:`r`n$($capability.Name)`r`n`r`nRelaunch as Administrator now?",
                'Install RSAT Active Directory tools',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($ask -eq [System.Windows.Forms.DialogResult]::Yes) {
                $args = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $script:ScriptPath))
                Start-Process -FilePath powershell.exe -ArgumentList $args -Verb RunAs | Out-Null
                exit 100
            }
            else {
                exit 1
            }
        }

        Show-Message "RSAT Active Directory tools will now be installed.`r`n`r`nThis can take several minutes. Please wait until Windows finishes the operation." 'Installing RSAT' ([System.Windows.Forms.MessageBoxIcon]::Information)
        try {
            Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop | Out-Null
        }
        catch {
            Show-Message "RSAT installation failed.`r`n`r`nCapability:`r`n$($capability.Name)`r`n`r`nError:`r`n$($_.Exception.Message)`r`n`r`nIf this machine uses WSUS/GPO restrictions, Windows may be blocked from downloading Features on Demand." 'RSAT install failed' ([System.Windows.Forms.MessageBoxIcon]::Error)
            exit 1
        }

        try {
            $doubleCheck = Get-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
            if ($doubleCheck.State -ne 'Installed') {
                throw "Capability state after install is '$($doubleCheck.State)', expected 'Installed'."
            }
        }
        catch {
            Show-Message "RSAT install finished but the double-check failed.`r`n`r`nError:`r`n$($_.Exception.Message)" 'RSAT double-check failed' ([System.Windows.Forms.MessageBoxIcon]::Error)
            exit 1
        }
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Show-Message 'RSAT Active Directory tools are installed and the ActiveDirectory PowerShell module was found.' 'RSAT installed' ([System.Windows.Forms.MessageBoxIcon]::Information)
        return $true
    }
    catch {
        Show-Message "RSAT appears installed, but importing the ActiveDirectory module still failed.`r`n`r`nError:`r`n$($_.Exception.Message)`r`n`r`nTry closing and reopening the tool, or restarting Windows." 'ActiveDirectory import failed' ([System.Windows.Forms.MessageBoxIcon]::Error)
        exit 1
    }
}

[void](Ensure-ActiveDirectoryModule)

function Get-AppConfig {
    $default = [PSCustomObject]@{
        DomainControllers = $script:DefaultDomainControllers
        LastSelectedDomainController = ''
    }

    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        return $default
    }

    try {
        $cfg = Get-Content -LiteralPath $script:ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $dcs = @()
        if ($cfg.DomainControllers) { $dcs += @($cfg.DomainControllers) }
        foreach ($dc in $script:DefaultDomainControllers) {
            if ($dcs -notcontains $dc) { $dcs += $dc }
        }
        if ($dcs.Count -eq 0) { $dcs = $script:DefaultDomainControllers }

        $last = [string]$cfg.LastSelectedDomainController
        if ([string]::IsNullOrWhiteSpace($last)) { $last = '' }

        return [PSCustomObject]@{
            DomainControllers = $dcs
            LastSelectedDomainController = $last
        }
    }
    catch {
        Add-StartupLog "Config read failed, using defaults: $($_.Exception.Message)"
        return $default
    }
}

function Save-AppConfig {
    param(
        [string[]]$DomainControllers,
        [string]$LastSelectedDomainController
    )
    try {
        $clean = @()
        foreach ($dc in $DomainControllers) {
            if (-not [string]::IsNullOrWhiteSpace($dc)) {
                $v = $dc.Trim()
                if ($clean -notcontains $v) { $clean += $v }
            }
        }
        foreach ($dc in $script:DefaultDomainControllers) {
            if ($clean -notcontains $dc) { $clean += $dc }
        }
        $cfg = [PSCustomObject]@{
            DomainControllers = $clean
            LastSelectedDomainController = $LastSelectedDomainController
            UpdatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
        $cfg | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8 -Force
    }
    catch {
        Add-LogLine "WARNING: Failed to save config: $($_.Exception.Message)"
    }
}

function Get-ComboItems {
    $items = @()
    for ($i = 0; $i -lt $cmbServer.Items.Count; $i++) {
        $items += [string]$cmbServer.Items[$i]
    }
    return $items
}

function Add-ComboServerItem {
    param([Parameter(Mandatory)][string]$Server)
    $s = $Server.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($s)) { return }
    if (-not $cmbServer.Items.Contains($s)) {
        [void]$cmbServer.Items.Add($s)
    }
}

function Save-CurrentServerList {
    $selected = $cmbServer.Text.Trim()
    Save-AppConfig -DomainControllers (Get-ComboItems) -LastSelectedDomainController $selected
}

function Add-LogLine {
    param([Parameter(Mandatory)][string]$Text)
    if ($null -eq $txtLog) {
        Add-StartupLog $Text
        return
    }
    $timestamp = (Get-Date).ToString('HH:mm:ss')
    $txtLog.AppendText("[$timestamp] $Text`r`n")
}

function Set-HiddenAttribute {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (Test-Path -LiteralPath $Path) {
            $item = Get-Item -LiteralPath $Path -Force
            $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
        }
    }
    catch { }
}

function Load-SavedCredential {
    param([switch]$Quiet)
    if (-not (Test-Path -LiteralPath $script:CredentialPath)) {
        if (-not $Quiet) { Show-Message 'No saved credential was found.' 'Saved credential' ([System.Windows.Forms.MessageBoxIcon]::Information) }
        return $false
    }
    try {
        $cred = Import-Clixml -LiteralPath $script:CredentialPath -ErrorAction Stop
        if ($cred -isnot [System.Management.Automation.PSCredential]) {
            throw 'Saved file did not contain a PSCredential object.'
        }
        $script:AdCredential = $cred
        $script:CredentialSource = "Saved DPAPI credential: $($cred.UserName)"
        if (-not $Quiet) { Show-Message "Saved credential loaded for:`r`n$($cred.UserName)" 'Saved credential loaded' ([System.Windows.Forms.MessageBoxIcon]::Information) }
        return $true
    }
    catch {
        $script:AdCredential = $null
        $script:CredentialSource = 'Current Windows session'
        if (-not $Quiet) { Show-Message "Saved credential could not be loaded.`r`n`r`nError:`r`n$($_.Exception.Message)" 'Saved credential failed' ([System.Windows.Forms.MessageBoxIcon]::Warning) }
        return $false
    }
}

function Save-CredentialSecure {
    param([Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential)
    try {
        New-Item -Path $script:CredentialDir -ItemType Directory -Force | Out-Null
        $Credential | Export-Clixml -LiteralPath $script:CredentialPath -Force
        Set-HiddenAttribute -Path $script:CredentialDir
        Set-HiddenAttribute -Path $script:CredentialPath
        $script:AdCredential = $Credential
        $script:CredentialSource = "Saved DPAPI credential: $($Credential.UserName)"
        return $true
    }
    catch {
        Show-Message "Credential could not be saved.`r`n`r`nError:`r`n$($_.Exception.Message)" 'Save credential failed' ([System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
}

function Remove-SavedCredential {
    try {
        if (Test-Path -LiteralPath $script:CredentialPath) {
            Remove-Item -LiteralPath $script:CredentialPath -Force -ErrorAction Stop
        }
        if ($script:CredentialSource -like 'Saved DPAPI credential:*') {
            $script:AdCredential = $null
            $script:CredentialSource = 'Current Windows session'
        }
        return $true
    }
    catch {
        Show-Message "Saved credential could not be removed.`r`n`r`nError:`r`n$($_.Exception.Message)" 'Forget credential failed' ([System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
}

[void](Load-SavedCredential -Quiet)
if ($script:AdCredential) { Add-StartupLog 'Saved DPAPI credential loaded for this Windows user/profile.' }

function ConvertTo-LdapEscapedString {
    param([Parameter(Mandatory)][string]$Value)
    $escaped = $Value -replace '\\', '\5c'
    $escaped = $escaped -replace '\*', '\2a'
    $escaped = $escaped -replace '\(', '\28'
    $escaped = $escaped -replace '\)', '\29'
    $escaped = $escaped -replace "`0", '\00'
    return $escaped
}

function Normalize-UserQuery {
    param([Parameter(Mandatory)][string]$Query)
    $q = $Query.Trim()
    if ($q -match '\\') { $q = ($q -split '\\')[-1] }
    return $q.Trim()
}

function Test-IsIPAddress {
    param([string]$Value)
    $ip = $null
    return [System.Net.IPAddress]::TryParse($Value, [ref]$ip)
}

function Resolve-ServerForAD {
    param([string]$Server)
    $s = $Server.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }

    if (Test-IsIPAddress $s) {
        try {
            $ptr = Resolve-DnsName -Name $s -Type PTR -ErrorAction Stop | Select-Object -First 1
            if ($ptr.NameHost) {
                $resolved = $ptr.NameHost.TrimEnd('.')
                Add-LogLine "Resolved DC IP $s to $resolved."
                return $resolved
            }
        }
        catch {
            Add-LogLine "WARNING: Could not resolve PTR/reverse DNS for $s. Kerberos may fail when using IP addresses."
        }
    }
    return $s
}

function Get-SelectedServerForAD {
    $raw = $cmbServer.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        Add-ComboServerItem -Server $raw
        Save-CurrentServerList
    }
    return Resolve-ServerForAD -Server $raw
}

function Get-PasswordExpiryInfo {
    param([Parameter(Mandatory)]$User)
    if ($User.PasswordNeverExpires) { return [PSCustomObject]@{ Text = 'Never expires'; Days = $null } }
    $raw = $User.'msDS-UserPasswordExpiryTimeComputed'
    if ($null -eq $raw -or $raw -eq 0 -or [Int64]$raw -eq 9223372036854775807) {
        return [PSCustomObject]@{ Text = 'Not available'; Days = $null }
    }
    try {
        $expiry = [DateTime]::FromFileTime([Int64]$raw)
        $days = [Math]::Floor(($expiry - (Get-Date)).TotalDays)
        return [PSCustomObject]@{ Text = $expiry.ToString('yyyy-MM-dd HH:mm:ss'); Days = $days }
    }
    catch { return [PSCustomObject]@{ Text = 'Unable to calculate'; Days = $null } }
}

function New-AdParamsBase {
    param([string]$Server)
    $params = @{ ErrorAction = 'Stop' }
    if (-not [string]::IsNullOrWhiteSpace($Server)) { $params.Server = $Server }
    if ($null -ne $script:AdCredential) { $params.Credential = $script:AdCredential }
    return $params
}

function Find-ADUserSmart {
    param(
        [Parameter(Mandatory)][string]$Query,
        [string]$Server
    )
    $q = Normalize-UserQuery -Query $Query
    if ([string]::IsNullOrWhiteSpace($q)) { throw 'Enter a username, UPN, or email address.' }

    $escaped = ConvertTo-LdapEscapedString -Value $q
    $ldapFilter = "(|(sAMAccountName=$escaped)(userPrincipalName=$escaped)(mail=$escaped))"
    $properties = @(
        'LockedOut','Enabled','PasswordExpired','PasswordLastSet','msDS-UserPasswordExpiryTimeComputed',
        'UserPrincipalName','SamAccountName','Mail','DisplayName','PasswordNeverExpires','LastBadPasswordAttempt',
        'badPwdCount','AccountLockoutTime','DistinguishedName'
    )

    $params = New-AdParamsBase -Server $Server
    $params.LDAPFilter = $ldapFilter
    $params.Properties = $properties

    $users = @(Get-ADUser @params)
    if ($users.Count -eq 0) { throw "No AD user found for '$Query'. Try samAccountName, UPN, or email address." }
    if ($users.Count -gt 1) {
        $matches = ($users | Select-Object -First 10 | ForEach-Object { "$($_.SamAccountName) / $($_.UserPrincipalName)" }) -join "`r`n"
        throw "Multiple users found. Search more precisely.`r`n`r`n$matches"
    }
    return $users[0]
}

function Test-IsSspiOrCredentialError {
    param([Parameter(Mandatory)]$Exception)
    $text = $Exception.ToString()
    return ($text -match 'SSPI|Kerberos|target principal name|logon failure|unknown user name|bad password|The user name or password is incorrect|Current security context')
}

function Prompt-ForAdCredential {
    param([string]$Message = 'Enter AD credentials for querying Active Directory.')
    try {
        $cred = Get-Credential -Message $Message
        if ($null -ne $cred) {
            $script:AdCredential = $cred
            $script:CredentialSource = "Session credential: $($cred.UserName)"
            Add-LogLine "Session AD credential set for $($cred.UserName)."
            return $true
        }
    }
    catch {
        Add-LogLine "Credential prompt failed: $($_.Exception.Message)"
    }
    return $false
}

function Set-Field {
    param([Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Value)
    if ($fieldLabels.ContainsKey($Name)) {
        if ($null -eq $Value -or $Value -eq '') { $fieldLabels[$Name].Text = '-' }
        else { $fieldLabels[$Name].Text = [string]$Value }
    }
}

function Clear-Fields {
    foreach ($key in $fieldLabels.Keys) {
        $fieldLabels[$key].Text = '-'
        $fieldLabels[$key].ForeColor = [System.Drawing.Color]::Black
    }
    $script:CurrentUser = $null
    $script:CurrentSummary = ''
    $btnUnlock.Enabled = $false
    $btnCopy.Enabled = $false
}

function Build-SummaryText {
    param([Parameter(Mandatory)]$User, [Parameter(Mandatory)]$ExpiryInfo, [string]$ServerUsed)
@"
AD user check
-------------
Display name:              $($User.DisplayName)
SamAccountName:            $($User.SamAccountName)
UPN:                       $($User.UserPrincipalName)
Email:                     $($User.Mail)
Enabled:                   $($User.Enabled)
Locked out:                $($User.LockedOut)
Password expired:          $($User.PasswordExpired)
Password never expires:    $($User.PasswordNeverExpires)
Password last set:         $($User.PasswordLastSet)
Password expiry:           $($ExpiryInfo.Text)
Days until expiry:         $($ExpiryInfo.Days)
Last bad password attempt: $($User.LastBadPasswordAttempt)
Bad password count:        $($User.badPwdCount)
Account lockout time:      $($User.AccountLockoutTime)
Domain controller used:    $ServerUsed
Checked at:                $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
}

function Apply-UserResultToGui {
    param([Parameter(Mandatory)]$User, [Parameter(Mandatory)]$Expiry, [string]$ServerUsed)
    $script:CurrentUser = $User
    $script:CurrentSummary = Build-SummaryText -User $User -ExpiryInfo $Expiry -ServerUsed $ServerUsed

    Set-Field 'Display name' $User.DisplayName
    Set-Field 'SamAccountName' $User.SamAccountName
    Set-Field 'UPN' $User.UserPrincipalName
    Set-Field 'Email' $User.Mail
    Set-Field 'Enabled' $User.Enabled
    Set-Field 'Locked out' $User.LockedOut
    Set-Field 'Password expired' $User.PasswordExpired
    Set-Field 'Password never expires' $User.PasswordNeverExpires
    Set-Field 'Password last set' $User.PasswordLastSet
    Set-Field 'Password expiry' $Expiry.Text
    Set-Field 'Days until expiry' $Expiry.Days
    Set-Field 'Last bad password attempt' $User.LastBadPasswordAttempt
    Set-Field 'Bad password count' $User.badPwdCount
    Set-Field 'Account lockout time' $User.AccountLockoutTime

    if ($User.LockedOut) {
        $fieldLabels['Locked out'].ForeColor = [System.Drawing.Color]::Red
        $btnUnlock.Enabled = $true
        Add-LogLine 'User is locked out. Unlock button enabled.'
    } else {
        $fieldLabels['Locked out'].ForeColor = [System.Drawing.Color]::DarkGreen
        $btnUnlock.Enabled = $false
        Add-LogLine 'User is not locked out.'
    }

    if ($User.PasswordExpired) { $fieldLabels['Password expired'].ForeColor = [System.Drawing.Color]::Red }
    else { $fieldLabels['Password expired'].ForeColor = [System.Drawing.Color]::DarkGreen }

    if ($false -eq $User.Enabled) { $fieldLabels['Enabled'].ForeColor = [System.Drawing.Color]::Red }
    else { $fieldLabels['Enabled'].ForeColor = [System.Drawing.Color]::DarkGreen }

    if ($null -ne $Expiry.Days -and $Expiry.Days -lt 0) {
        $fieldLabels['Password expiry'].ForeColor = [System.Drawing.Color]::Red
        $fieldLabels['Days until expiry'].ForeColor = [System.Drawing.Color]::Red
    }
    elseif ($null -ne $Expiry.Days -and $Expiry.Days -le 7) {
        $fieldLabels['Password expiry'].ForeColor = [System.Drawing.Color]::DarkOrange
        $fieldLabels['Days until expiry'].ForeColor = [System.Drawing.Color]::DarkOrange
    }
    $btnCopy.Enabled = $true
}

function Check-User {
    Clear-Fields
    $query = $txtUser.Text.Trim()
    $server = Get-SelectedServerForAD
    if ([string]::IsNullOrWhiteSpace($query)) {
        Show-Message 'Enter a username, UPN, or email address.' 'Missing username' ([System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    try {
        $credLabel = if ($script:AdCredential) { $script:CredentialSource } else { 'Current Windows session' }
        Add-LogLine "Checking AD user '$query' on server '$server' using $credLabel..."
        $user = Find-ADUserSmart -Query $query -Server $server
        $expiry = Get-PasswordExpiryInfo -User $user
        Apply-UserResultToGui -User $user -Expiry $expiry -ServerUsed $server
    }
    catch {
        $firstError = $_.Exception
        if ((Test-IsSspiOrCredentialError -Exception $firstError) -and ($null -eq $script:AdCredential)) {
            Add-LogLine "AD query failed with security/credential error: $($firstError.Message)"
            $ask = [System.Windows.Forms.MessageBox]::Show(
                "AD query failed with a Kerberos/credential error.`r`n`r`nThis usually happens when the PC is not using a domain security context for this AD query.`r`n`r`nDo you want to enter AD credentials and retry?",
                'AD credentials required',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($ask -eq [System.Windows.Forms.DialogResult]::Yes) {
                if (Prompt-ForAdCredential -Message 'Enter AD credentials. Example: DOMAIN\username or username@example.local') {
                    try {
                        Add-LogLine "Retrying AD user '$query' with session credential..."
                        $user = Find-ADUserSmart -Query $query -Server $server
                        $expiry = Get-PasswordExpiryInfo -User $user
                        Apply-UserResultToGui -User $user -Expiry $expiry -ServerUsed $server
                        return
                    }
                    catch {
                        Add-LogLine "Retry failed: $($_.Exception.Message)"
                        Show-Message $_.Exception.Message 'AD check failed' ([System.Windows.Forms.MessageBoxIcon]::Warning)
                        return
                    }
                }
            }
        }
        Add-LogLine "ERROR: $($firstError.Message)"
        Show-Message $firstError.Message 'AD check failed' ([System.Windows.Forms.MessageBoxIcon]::Warning)
    }
}

function Unlock-CurrentUser {
    if ($null -eq $script:CurrentUser) {
        Show-Message 'Check a user first.' 'No user selected' ([System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    if (-not $script:CurrentUser.LockedOut) {
        Show-Message 'This user is not currently locked out.' 'Nothing to unlock' ([System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $confirmText = "Unlock this AD account?`r`n`r`nDisplay name: $($script:CurrentUser.DisplayName)`r`nSamAccountName: $($script:CurrentUser.SamAccountName)`r`nUPN: $($script:CurrentUser.UserPrincipalName)"
    $confirm = [System.Windows.Forms.MessageBox]::Show($confirmText, 'Confirm account unlock', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Add-LogLine 'Unlock cancelled.'
        return
    }

    try {
        $server = Get-SelectedServerForAD
        $params = New-AdParamsBase -Server $server
        $params.Identity = $script:CurrentUser.DistinguishedName
        Unlock-ADAccount @params
        Add-LogLine "Unlocked account '$($script:CurrentUser.SamAccountName)'. Refreshing status..."
        Start-Sleep -Seconds 1
        Check-User
    }
    catch {
        Add-LogLine "ERROR unlocking account: $($_.Exception.Message)"
        Show-Message $_.Exception.Message 'Unlock failed' ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 2500
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        $ok = $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) { return $false }
        $client.EndConnect($async)
        return $true
    }
    catch { return $false }
    finally { $client.Close() }
}

function Test-SelectedDomainController {
    $server = Get-SelectedServerForAD
    if ([string]::IsNullOrWhiteSpace($server)) {
        Show-Message 'Select or enter a domain controller first.' 'Missing domain controller' ([System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    Add-LogLine "Testing DC '$server'..."
    $adws = Test-TcpPort -ComputerName $server -Port 9389
    $ldap = Test-TcpPort -ComputerName $server -Port 389
    $kerb = Test-TcpPort -ComputerName $server -Port 88
    Add-LogLine "Test $server TCP 9389 (AD Web Services / AD PowerShell cmdlets): $(if($adws){'OK'}else{'FAILED'})"
    Add-LogLine "Test $server TCP 389 (LDAP): $(if($ldap){'OK'}else{'FAILED'})"
    Add-LogLine "Test $server TCP 88 (Kerberos): $(if($kerb){'OK'}else{'FAILED'})"
    $msg = "DC test result for:`r`n$server`r`n`r`nTCP 9389 - AD Web Services / AD PowerShell cmdlets: $(if($adws){'OK'}else{'FAILED'})`r`nTCP 389 - LDAP: $(if($ldap){'OK'}else{'FAILED'})`r`nTCP 88 - Kerberos: $(if($kerb){'OK'}else{'FAILED'})"
    Show-Message $msg 'DC test complete' ([System.Windows.Forms.MessageBoxIcon]::Information)
}

function Get-DomainCandidates {
    $domains = @()
    $serverText = $cmbServer.Text.Trim()
    if ($serverText -match '^[^.]+\.(.+)$') { $domains += $Matches[1] }
    if ($env:USERDNSDOMAIN) { $domains += $env:USERDNSDOMAIN.ToLowerInvariant() }
    return @($domains | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Discover-DomainControllers {
    $found = @()
    Add-LogLine 'Discovering domain controllers...'

    # Query AD via currently selected DC when possible.
    try {
        $server = Get-SelectedServerForAD
        if (-not [string]::IsNullOrWhiteSpace($server)) {
            $params = New-AdParamsBase -Server $server
            $params.Filter = '*'
            $dcs = Get-ADDomainController @params
            foreach ($dc in $dcs) {
                if ($dc.HostName) { $found += $dc.HostName.TrimEnd('.') }
            }
        }
    }
    catch {
        Add-LogLine "AD-based DC discovery failed: $($_.Exception.Message)"
    }

    # DNS SRV discovery.
    foreach ($domain in (Get-DomainCandidates)) {
        try {
            $records = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$domain" -Type SRV -ErrorAction Stop
            foreach ($rec in $records) {
                if ($rec.NameTarget) { $found += $rec.NameTarget.TrimEnd('.') }
            }
        }
        catch {
            Add-LogLine "DNS SRV discovery failed for ${domain}: $($_.Exception.Message)"
        }
    }

    foreach ($dc in $script:DefaultDomainControllers) { $found += $dc }
    $unique = @($found | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().TrimEnd('.') } | Select-Object -Unique)

    foreach ($dc in $unique) { Add-ComboServerItem -Server $dc }
    if ($unique.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($cmbServer.Text)) { $cmbServer.Text = [string]$unique[0] }
        Save-CurrentServerList
        Add-LogLine "Discovered DC hostname/FQDN candidates: $($unique -join ', ')"
        Show-Message "Added discovered DC hostname/FQDN candidates to the dropdown:`r`n`r`n$($unique -join "`r`n")`r`n`r`nUse hostname/FQDN entries rather than IP addresses when possible." 'Domain controllers discovered' ([System.Windows.Forms.MessageBoxIcon]::Information)
    }
    else {
        Show-Message 'No domain controllers were discovered. Check VPN/network/DNS, then try again.' 'No DCs discovered' ([System.Windows.Forms.MessageBoxIcon]::Warning)
    }
}

function Add-DomainControllerManual {
    $value = [Microsoft.VisualBasic.Interaction]::InputBox('Enter domain controller hostname/FQDN or IP address:', 'Add domain controller', '')
    if ([string]::IsNullOrWhiteSpace($value)) { return }
    Add-ComboServerItem -Server $value
    $cmbServer.Text = $value.Trim().TrimEnd('.')
    Save-CurrentServerList
    Add-LogLine "Added domain controller '$($cmbServer.Text)'."
}

function Remove-SelectedDomainController {
    $selected = $cmbServer.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($selected)) { return }
    $confirm = [System.Windows.Forms.MessageBox]::Show("Remove this domain controller from the dropdown?`r`n`r`n$selected", 'Remove domain controller', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    if ($cmbServer.Items.Contains($selected)) { $cmbServer.Items.Remove($selected) }
    if ($cmbServer.Items.Count -gt 0) { $cmbServer.SelectedIndex = 0 } else { $cmbServer.Text = '' }
    Save-CurrentServerList
    Add-LogLine "Removed domain controller '$selected'."
}

function Test-CurrentCredential {
    if ($null -eq $script:AdCredential) {
        Show-Message 'No AD credential is currently set.' 'Credential test' ([System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    $server = Get-SelectedServerForAD
    try {
        $params = New-AdParamsBase -Server $server
        $domain = Get-ADDomain @params
        Show-Message "Credential test successful.`r`n`r`nCredential:`r`n$($script:AdCredential.UserName)`r`n`r`nDomain:`r`n$($domain.DNSRoot)`r`n`r`nServer:`r`n$server" 'Credential test OK' ([System.Windows.Forms.MessageBoxIcon]::Information)
        Add-LogLine "Credential test OK for $($script:AdCredential.UserName)."
    }
    catch {
        Show-Message "Credential test failed.`r`n`r`nCredential:`r`n$($script:AdCredential.UserName)`r`n`r`nError:`r`n$($_.Exception.Message)" 'Credential test failed' ([System.Windows.Forms.MessageBoxIcon]::Warning)
        Add-LogLine "Credential test failed: $($_.Exception.Message)"
    }
}

function Get-CredentialStatusText {
    $saved = if (Test-Path -LiteralPath $script:CredentialPath) { 'Yes' } else { 'No' }
    $current = if ($script:AdCredential) { $script:AdCredential.UserName } else { 'None - current Windows session will be used' }
    return "Current credential: $current`r`nSource: $($script:CredentialSource)`r`nSaved DPAPI credential exists: $saved`r`nStorage path:`r`n$script:CredentialPath"
}

function Show-AdvancedCredentialsDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Advanced credentials'
    $dlg.StartPosition = 'CenterParent'
    $dlg.Size = New-Object System.Drawing.Size(620, 385)
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $info = New-Object System.Windows.Forms.Label
    $info.Location = New-Object System.Drawing.Point(16, 14)
    $info.Size = New-Object System.Drawing.Size(570, 80)
    $info.Text = "Credentials are protected with Windows DPAPI and saved only for the current Windows user on this PC.`r`nThe password is not stored as plaintext and the file cannot simply be copied to another PC/user profile.`r`nRecommended: use a dedicated least-privilege AD account, not a Domain Admin account."
    $dlg.Controls.Add($info)

    $status = New-Object System.Windows.Forms.TextBox
    $status.Location = New-Object System.Drawing.Point(18, 105)
    $status.Size = New-Object System.Drawing.Size(570, 95)
    $status.Multiline = $true
    $status.ReadOnly = $true
    $status.ScrollBars = 'Vertical'
    $status.Text = Get-CredentialStatusText
    $dlg.Controls.Add($status)

    $refreshStatus = { $status.Text = Get-CredentialStatusText }

    $btnSet = New-Object System.Windows.Forms.Button
    $btnSet.Text = 'Set session credentials'
    $btnSet.Location = New-Object System.Drawing.Point(18, 218)
    $btnSet.Size = New-Object System.Drawing.Size(175, 32)
    $dlg.Controls.Add($btnSet)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save current credentials'
    $btnSave.Location = New-Object System.Drawing.Point(208, 218)
    $btnSave.Size = New-Object System.Drawing.Size(175, 32)
    $dlg.Controls.Add($btnSave)

    $btnLoad = New-Object System.Windows.Forms.Button
    $btnLoad.Text = 'Load saved credentials'
    $btnLoad.Location = New-Object System.Drawing.Point(398, 218)
    $btnLoad.Size = New-Object System.Drawing.Size(175, 32)
    $dlg.Controls.Add($btnLoad)

    $btnForget = New-Object System.Windows.Forms.Button
    $btnForget.Text = 'Forget saved credentials'
    $btnForget.Location = New-Object System.Drawing.Point(18, 265)
    $btnForget.Size = New-Object System.Drawing.Size(175, 32)
    $dlg.Controls.Add($btnForget)

    $btnTest = New-Object System.Windows.Forms.Button
    $btnTest.Text = 'Test current credentials'
    $btnTest.Location = New-Object System.Drawing.Point(208, 265)
    $btnTest.Size = New-Object System.Drawing.Size(175, 32)
    $dlg.Controls.Add($btnTest)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(398, 265)
    $btnClose.Size = New-Object System.Drawing.Size(175, 32)
    $dlg.Controls.Add($btnClose)

    $btnSet.Add_Click({
        if (Prompt-ForAdCredential -Message 'Enter AD credentials. Example: DOMAIN\username or username@example.local') { & $refreshStatus }
    })
    $btnSave.Add_Click({
        if ($null -eq $script:AdCredential) {
            if (-not (Prompt-ForAdCredential -Message 'Enter AD credentials to save securely with Windows DPAPI.')) { return }
        }
        if (Save-CredentialSecure -Credential $script:AdCredential) {
            Add-LogLine 'Credential saved with Windows DPAPI for the current Windows user.'
            Show-Message 'Credential saved securely with Windows DPAPI for this Windows user/profile.' 'Credential saved' ([System.Windows.Forms.MessageBoxIcon]::Information)
            & $refreshStatus
        }
    })
    $btnLoad.Add_Click({ if (Load-SavedCredential) { Add-LogLine 'Saved credential loaded.'; & $refreshStatus } })
    $btnForget.Add_Click({
        $confirm = [System.Windows.Forms.MessageBox]::Show('Delete the saved DPAPI credential from this PC?', 'Forget saved credential', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            if (Remove-SavedCredential) {
                Add-LogLine 'Saved credential removed.'
                Show-Message 'Saved credential removed from this PC.' 'Credential removed' ([System.Windows.Forms.MessageBoxIcon]::Information)
                & $refreshStatus
            }
        }
    })
    $btnTest.Add_Click({ Test-CurrentCredential; & $refreshStatus })
    $btnClose.Add_Click({ $dlg.Close() })

    [void]$dlg.ShowDialog($form)
}

function Show-AboutDialog {
    $text = "$script:AppName`r`nVersion: $script:AppVersion`r`nCreated by: $script:AppAuthor`r`n`r`nPurpose:`r`nCheck AD user password/lockout status and unlock locked accounts when permissions allow.`r`n`r`nCredential note:`r`nThe tool can use current Windows session credentials, temporary session credentials, or an optional DPAPI-protected saved credential."
    Show-Message $text 'About' ([System.Windows.Forms.MessageBoxIcon]::Information)
}

function Ensure-DesktopShortcutPrompt {
    try {
        $target = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $args = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:ScriptPath`""
        $wsh = New-Object -ComObject WScript.Shell

        if (Test-Path -LiteralPath $script:ShortcutPath) {
            $shortcut = $wsh.CreateShortcut($script:ShortcutPath)
            $shortcut.TargetPath = $target
            $shortcut.Arguments = $args
            $shortcut.WorkingDirectory = $script:ScriptDir
            $shortcut.Save()
            Add-StartupLog 'Desktop shortcut already exists and was updated to the current script path.'
            return
        }

        $ask = [System.Windows.Forms.MessageBox]::Show('Do you want to create a desktop shortcut for this tool?', 'Create desktop shortcut', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ask -eq [System.Windows.Forms.DialogResult]::Yes) {
            $shortcut = $wsh.CreateShortcut($script:ShortcutPath)
            $shortcut.TargetPath = $target
            $shortcut.Arguments = $args
            $shortcut.WorkingDirectory = $script:ScriptDir
            $shortcut.Save()
            Add-StartupLog 'Desktop shortcut created.'
        }
    }
    catch {
        Add-StartupLog "Shortcut setup failed: $($_.Exception.Message)"
    }
}

# ---------------- GUI ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "$script:AppName v$script:AppVersion - $script:AppAuthor"
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1000, 720)
$form.MinimumSize = New-Object System.Drawing.Size(940, 650)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = "$script:AppName   |   v$script:AppVersion   |   $script:AppAuthor"
$lblHeader.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$lblHeader.Location = New-Object System.Drawing.Point(16, 12)
$lblHeader.Size = New-Object System.Drawing.Size(760, 28)
$lblHeader.Anchor = 'Top, Left, Right'
$form.Controls.Add($lblHeader)

$btnAbout = New-Object System.Windows.Forms.Button
$btnAbout.Text = 'About'
$btnAbout.Location = New-Object System.Drawing.Point(865, 10)
$btnAbout.Size = New-Object System.Drawing.Size(95, 28)
$btnAbout.Anchor = 'Top, Right'
$form.Controls.Add($btnAbout)

$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Text = 'Username / UPN / email:'
$lblUser.Location = New-Object System.Drawing.Point(16, 55)
$lblUser.Size = New-Object System.Drawing.Size(165, 24)
$form.Controls.Add($lblUser)

$txtUser = New-Object System.Windows.Forms.TextBox
$txtUser.Location = New-Object System.Drawing.Point(190, 52)
$txtUser.Size = New-Object System.Drawing.Size(450, 24)
$txtUser.Anchor = 'Top, Left, Right'
$txtUser.Text = ''
$form.Controls.Add($txtUser)

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = 'Check user'
$btnCheck.Location = New-Object System.Drawing.Point(655, 50)
$btnCheck.Size = New-Object System.Drawing.Size(110, 28)
$btnCheck.Anchor = 'Top, Right'
$form.Controls.Add($btnCheck)

$btnUnlock = New-Object System.Windows.Forms.Button
$btnUnlock.Text = 'Unlock account'
$btnUnlock.Location = New-Object System.Drawing.Point(775, 50)
$btnUnlock.Size = New-Object System.Drawing.Size(145, 28)
$btnUnlock.Anchor = 'Top, Right'
$btnUnlock.Enabled = $false
$form.Controls.Add($btnUnlock)

$lblServer = New-Object System.Windows.Forms.Label
$lblServer.Text = 'Domain controller:'
$lblServer.Location = New-Object System.Drawing.Point(16, 90)
$lblServer.Size = New-Object System.Drawing.Size(165, 24)
$form.Controls.Add($lblServer)

$cmbServer = New-Object System.Windows.Forms.ComboBox
$cmbServer.Location = New-Object System.Drawing.Point(190, 87)
$cmbServer.Size = New-Object System.Drawing.Size(450, 24)
$cmbServer.Anchor = 'Top, Left, Right'
$cmbServer.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
$form.Controls.Add($cmbServer)

$btnAddDc = New-Object System.Windows.Forms.Button
$btnAddDc.Text = '+'
$btnAddDc.Location = New-Object System.Drawing.Point(655, 85)
$btnAddDc.Size = New-Object System.Drawing.Size(35, 28)
$btnAddDc.Anchor = 'Top, Right'
$form.Controls.Add($btnAddDc)

$btnRemoveDc = New-Object System.Windows.Forms.Button
$btnRemoveDc.Text = '-'
$btnRemoveDc.Location = New-Object System.Drawing.Point(695, 85)
$btnRemoveDc.Size = New-Object System.Drawing.Size(35, 28)
$btnRemoveDc.Anchor = 'Top, Right'
$form.Controls.Add($btnRemoveDc)

$btnTestDc = New-Object System.Windows.Forms.Button
$btnTestDc.Text = 'Test DC'
$btnTestDc.Location = New-Object System.Drawing.Point(735, 85)
$btnTestDc.Size = New-Object System.Drawing.Size(80, 28)
$btnTestDc.Anchor = 'Top, Right'
$form.Controls.Add($btnTestDc)

$btnDiscoverDc = New-Object System.Windows.Forms.Button
$btnDiscoverDc.Text = 'Discover DCs'
$btnDiscoverDc.Location = New-Object System.Drawing.Point(820, 85)
$btnDiscoverDc.Size = New-Object System.Drawing.Size(100, 28)
$btnDiscoverDc.Anchor = 'Top, Right'
$form.Controls.Add($btnDiscoverDc)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = 'Copy summary'
$btnCopy.Location = New-Object System.Drawing.Point(820, 120)
$btnCopy.Size = New-Object System.Drawing.Size(100, 28)
$btnCopy.Anchor = 'Top, Right'
$btnCopy.Enabled = $false
$form.Controls.Add($btnCopy)

$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = 'User status'
$grp.Location = New-Object System.Drawing.Point(16, 125)
$grp.Size = New-Object System.Drawing.Size(944, 355)
$grp.Anchor = 'Top, Bottom, Left, Right'
$form.Controls.Add($grp)

$fieldLabels = @{}
$fields = @(
    'Display name','SamAccountName','UPN','Email','Enabled','Locked out','Password expired','Password never expires',
    'Password last set','Password expiry','Days until expiry','Last bad password attempt','Bad password count','Account lockout time'
)
$y = 28
foreach ($field in $fields) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "${field}:"
    $label.Location = New-Object System.Drawing.Point(18, $y)
    $label.Size = New-Object System.Drawing.Size(205, 22)
    $grp.Controls.Add($label)

    $value = New-Object System.Windows.Forms.Label
    $value.Text = '-'
    $value.Location = New-Object System.Drawing.Point(230, $y)
    $value.Size = New-Object System.Drawing.Size(680, 22)
    $value.Anchor = 'Top, Left, Right'
    $grp.Controls.Add($value)
    $fieldLabels[$field] = $value
    $y += 23
}

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = 'Log:'
$lblLog.Location = New-Object System.Drawing.Point(16, 495)
$lblLog.Size = New-Object System.Drawing.Size(80, 20)
$lblLog.Anchor = 'Bottom, Left'
$form.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(16, 518)
$txtLog.Size = New-Object System.Drawing.Size(944, 130)
$txtLog.Anchor = 'Bottom, Left, Right'
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$form.Controls.Add($txtLog)

$config = Get-AppConfig
foreach ($dc in @($config.DomainControllers)) { Add-ComboServerItem -Server $dc }
if ($cmbServer.Items.Contains($config.LastSelectedDomainController)) { $cmbServer.Text = $config.LastSelectedDomainController }
elseif ($cmbServer.Items.Count -gt 0) { $cmbServer.SelectedIndex = 0 }

$btnCheck.Add_Click({ Check-User })
$btnUnlock.Add_Click({ Unlock-CurrentUser })
$btnCopy.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($script:CurrentSummary)) {
        [System.Windows.Forms.Clipboard]::SetText($script:CurrentSummary)
        Add-LogLine 'Summary copied to clipboard.'
    }
})
$btnAddDc.Add_Click({ Add-DomainControllerManual })
$btnRemoveDc.Add_Click({ Remove-SelectedDomainController })
$btnTestDc.Add_Click({ Test-SelectedDomainController })
$btnDiscoverDc.Add_Click({ Discover-DomainControllers })
$btnAbout.Add_Click({
    $mods = [System.Windows.Forms.Control]::ModifierKeys
    if ((($mods -band [System.Windows.Forms.Keys]::Control) -eq [System.Windows.Forms.Keys]::Control) -and (($mods -band [System.Windows.Forms.Keys]::Shift) -eq [System.Windows.Forms.Keys]::Shift)) {
        Show-AdvancedCredentialsDialog
    }
    else {
        Show-AboutDialog
    }
})
$cmbServer.Add_SelectedIndexChanged({ Save-CurrentServerList })
$txtUser.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Check-User
        $_.SuppressKeyPress = $true
    }
})
$form.Add_FormClosing({ Save-CurrentServerList })

Ensure-DesktopShortcutPrompt
Add-LogLine "Ready. Enter samAccountName, UPN, or email. Example: username or username@example.local"
foreach ($line in $script:StartupLog) { Add-LogLine $line }

[void]$form.ShowDialog()
