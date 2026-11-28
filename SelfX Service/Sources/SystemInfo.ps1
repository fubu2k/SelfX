<#
.SYNOPSIS
    Collects read-only information about the device for the "System information" tab of SelfX.

.DESCRIPTION
    Gathers device, Windows, user/management and network details that the support desk usually asks for
    (computer name, serial number, OS build, Entra ID / Intune state, IP addresses, VPN, internet access, ...).
    The result is a list of objects with Category, Property and Value that the GUI shows grouped by category
    and that can be copied or exported as TXT, HTML, CSV or JSON.

    Labels are passed in with -Text (a hashtable built from the language file by Get-SelfXSystemInfoTexts).
    Missing labels fall back to the English defaults defined in this script, so the collector also works
    on its own.

    Based on the idea and data points of the "System Information Tool" by Jannik Reinhard
    (https://github.com/JayRHa/windows-system-information, MIT License, Copyright (c) 2026 Jannik Reinhard).

    This script only reads information. It does not change, restart or sign out anything.
    -IncludeHealth also requests the local service health report. Administrators may configure
    extension scripts for this report; they must be read-only. The built-in collector does not
    query Intune online. The only built-in network access is the optional TCP internet test.

.NOTES
    Name    : SystemInfo.ps1
    Package : SelfX Service
    Context : User (dot-sourced by Self_X.ps1 and SelfX_Tray.ps1, run in a background runspace)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version: System information tab
    2.8.8    2026-11-22  fubu2k               Optional latency measurements (default gateway, DNS lookup and connection time to configured targets;
                                              Network_Test_Config.xml, off by default)
    2.8.9    2026-11-23  fubu2k               CSV export: text cells starting with = + - @ tab CR LF get a leading apostrophe (CSV/formula injection, finding N7)
    2.8.25   2026-11-24  fubu2k               Row "Citrix Workspace" (version of the app, only when installed; also in the support ticket)
    2.8.26   2026-11-24  fubu2k               Export: the file name is used literally (-LiteralPath); a name with [ ] from the save dialog no longer fails or matches other files
    3.1.0    2026-11-27  fubu2k               Connection check with verdict: targets get Group (Local, Internet, Microsoft, Company) and Kind (Vpn, Intranet), up to 12 targets,
                                              four group rows and one result sentence (pure function Get-SelfXConnectionVerdict), 15 second limit, setting HostNames
    3.1.0    2026-11-27  fubu2k               Health rows carry UserRemediation (part of a repair that SelfX runs in the context of the user)
    3.1.0    2026-11-28  fubu2k               Get-SelfXSystemInfo -ServerRows (rows of the class Server) and -TerminalServer (no kinds of connection); what is
                                              not shown is not read. Status request answered UNAVAILABLE TerminalServer: no status rows
    3.1.0    2026-11-28  fubu2k               Row "Company apps": a known error code of an app gets a short explanation with a tip in the language of the
                                              user (texts AppError_<code>, Add-SelfXAppErrorText); unknown codes stay as they are
#>

# English default labels. Keys are identical to the <SystemInfo> section of Languages\en.xml.
$Script:SelfXInfoDefaultText = @{
	Category_Device = 'Device'; Category_Windows = 'Windows'; Category_User = 'User and management'
	Category_Network = 'Network'; Category_Report = 'Report'
	Computer_Name = 'Computer name'; Manufacturer = 'Manufacturer'; Model = 'Model'; Serial_Number = 'Serial number'
	BIOS_Version = 'BIOS version'; Processor = 'Processor'; Memory = 'Memory (RAM)'; Free_Space = 'Free space {0}'
	Free_Space_Value = '{0} of {1} ({2}%)'; Battery = 'Battery'
	Windows_Version = 'Windows version'; OS_Build = 'OS build'; Last_Boot = 'Last boot'; Uptime = 'Uptime'
	Uptime_Value = '{0} day(s) {1:D2}:{2:D2} h'; Uptime_Restart_Hint = 'restart recommended (not "Shut down")'; Last_Update = 'Last update installed'; Time_Zone = 'Time zone'
	Current_User = 'Current user'; User_Principal_Name = 'User principal name'; Domain = 'Domain / workgroup'
	Entra_Joined = 'Entra ID joined'; Domain_Joined = 'Domain joined'; Tenant = 'Tenant'; Entra_Device_Id = 'Entra device ID'
	Intune_User = 'Intune enrolled user'; Intune_Last_Sync = 'Last Intune sync'
	LAN_Connected = 'LAN connected'; WiFi_Connected = 'Wi-Fi connected'; WWAN_Connected = 'Mobile broadband connected'
	WiFi_SSID = 'Wi-Fi network (SSID)'; VPN_Connected = 'VPN connected'; Internet_Reachable = 'Internet reachable'
	IPv4 = 'IPv4 address(es)'; IPv6 = 'IPv6 address(es)'; Gateway = 'Default gateway'; DNS = 'DNS server(s)'; MAC = 'MAC address(es)'
	Proxy = 'Proxy (user setting)'; Proxy_None = 'No proxy'; Proxy_Manual = 'Manual proxy'; Proxy_Script = 'Automatic configuration script'
	Network_Drives = 'Network drives'; Network_Drives_None = 'None'
	Latency_Gateway = 'Latency: default gateway'; Latency_Dns = 'DNS lookup: {0}'; Latency_Connection = 'Connection: {0}'
	Latency_Value = '{0} ms (min {1}, max {2}, {3} of {4} lost)'; Latency_Failed = 'not reachable ({0} of {1} failed)'
	Latency_Skipped = 'not measured (time limit reached)'
	Check_Local = 'Local network (Wi-Fi, router)'; Check_Internet = 'Internet'; Check_Microsoft = 'Microsoft services (Intune, Entra ID)'
	Check_Company = 'Company network'; Check_Result = 'Connection result'
	Check_State_Ok = 'reachable ({0} of {1})'; Check_State_Partial = 'partly reachable ({0} of {1})'; Check_State_Fail = 'not reachable ({0} of {1})'
	Check_State_None = 'not measured'
	Verdict_LocalDown = 'Your Wi-Fi or router does not answer.'; Verdict_InternetDown = 'The internet cannot be reached.'
	Verdict_MicrosoftDown = 'The internet works, but the Microsoft services for the management of this device cannot be reached.'
	Verdict_CompanyVpn = 'The internet works, but the company network cannot be reached: check the VPN.'
	Verdict_CompanyIntranet = 'The internet works, but the company network cannot be reached: check the network connection at your location.'
	Verdict_Partial = 'Most connections work, but some targets cannot be reached.'; Verdict_AllOk = 'Everything can be reached.'
	Verdict_NoData = 'Nothing could be measured.'
	Collected_At = 'Collected at'; Error = 'Error'; Yes = 'Yes'; No = 'No'; Not_Available = 'n/a'
	Not_Enrolled = 'Not enrolled / unknown'; No_WiFi = 'No Wi-Fi connection'
	Category_Health = 'Health status'; Health_IME = 'IME service'; Health_Defender = 'Microsoft Defender'
	Health_Compliance = 'Compliance'; Health_Applications = 'Company apps (Intune)'
	Health_Disk = 'Disk capacity'; Health_BitLocker = 'BitLocker'; Health_PendingReboot = 'Pending reboot'
	Health_Updates = 'Updates to install'; Health_Service = 'Service'
	Health_Custom = 'Custom check'; Health_Collection = 'Health collection'
	Health_OK = 'OK'; Health_Pending = 'Pending'; Health_Error = 'Error'; Health_Unknown = 'Unknown'
	Health_Unavailable = 'Local health report unavailable: {0}'
	# Error codes of app installations (Intune Management Extension), as HRESULT. Only codes with a source; the key is AppError_ and the
	# eight hex digits. Sources (Microsoft Learn): "Intune app installation error reference" (0x87D1041C, 0x8000FFFF); "MsiExec.exe and
	# InstMsi.exe error messages" (Windows Installer 1602, 1603, 1618, 1619, 1625, 1632, 1638, 3010 as 0x8007xxxx); "System error codes
	# (0-499)" (5 access denied, 112 disk full). The text says what happened and what the user can do; it never starts an action.
	AppError_87D1041C = 'The app was installed but is not found any more (for example, it was removed). Required apps are installed again at the next sync.'
	AppError_8000FFFF = 'An unexpected error occurred during the installation. Restart the device and try again. If it fails again, contact the support.'
	AppError_80070643 = 'A serious error occurred during the installation. Restart the device and try again. If it fails again, contact the support.'
	AppError_80070642 = 'The installation was cancelled. Start it again and do not cancel it.'
	AppError_80070652 = 'Another installation was running at the same time. Wait until it has finished, then try again.'
	AppError_80070653 = 'The installation file could not be opened. Try again later. If it fails again, contact the support.'
	AppError_80070659 = 'The installation is blocked by a rule of the device. Contact the support.'
	AppError_80070660 = 'The folder for temporary files is full or cannot be used. Free up disk space and try again.'
	AppError_80070666 = 'Another version of this app is already installed. Contact the support.'
	AppError_80070BC2 = 'The installation needs a restart. Restart the device.'
	AppError_80070070 = 'There is not enough space on the disk. Free up disk space and try again.'
	AppError_80070005 = 'Access was denied during the installation. Contact the support.'
}
# Labels used by the current collection (defaults overlaid with the -Text hashtable of Get-SelfXSystemInfo).
$Script:SelfXInfoText = $Script:SelfXInfoDefaultText.Clone()

function Get-SelfXInfoText {
	# Returns the label for Key; extra arguments are inserted into {0}, {1}, ... placeholders.
	param(
		[string]$Key,
		[Parameter(ValueFromRemainingArguments = $true)]
		[object[]]$Arguments
	)
	$value = $Script:SelfXInfoText[$Key]
	if ([string]::IsNullOrEmpty($value)) { $value = $Script:SelfXInfoDefaultText[$Key] }
	if ([string]::IsNullOrEmpty($value)) { $value = $Key }
	if ($Arguments -and $Arguments.Count) {
		try { return [string]::Format($value, $Arguments) }
		catch { return [string]::Format($Script:SelfXInfoDefaultText[$Key], $Arguments) }
	}
	return $value
}

# Proxy setting of the signed-in user as text: the kind of setting with its value (server and port, address of
# the configuration script). Credentials in an address (user:password@host) are masked and long values are cut,
# so a password never reaches the screen or an export. Settings: object with ProxyEnable, ProxyServer and
# AutoConfigURL (values of HKCU\...\Internet Settings); $null = not readable.
function Hide-SelfXAddressCredentials {
	param([string]$Text)
	$clean = "$Text".Trim()
	$clean = [regex]::Replace($clean, '(?<=://)[^/@\s;]+@', '***@')
	$clean = [regex]::Replace($clean, '(?<=^|[;=\s])[^/@\s;=]+:[^/@\s;=]*@', '***@')
	if ($clean.Length -gt 200) { $clean = $clean.Substring(0, 200) + '...' }
	return $clean
}

function ConvertTo-SelfXProxyText {
	param($Settings)
	if ($null -eq $Settings) { return '' }
	$kinds = New-Object System.Collections.Generic.List[string]
	if ([int]$Settings.ProxyEnable -eq 1 -and -not [string]::IsNullOrWhiteSpace("$($Settings.ProxyServer)")) {
		$kinds.Add(('{0}: {1}' -f (Get-SelfXInfoText 'Proxy_Manual'), (Hide-SelfXAddressCredentials "$($Settings.ProxyServer)")))
	}
	if (-not [string]::IsNullOrWhiteSpace("$($Settings.AutoConfigURL)")) {
		$kinds.Add(('{0}: {1}' -f (Get-SelfXInfoText 'Proxy_Script'), (Hide-SelfXAddressCredentials "$($Settings.AutoConfigURL)")))
	}
	if (-not $kinds.Count) { return (Get-SelfXInfoText 'Proxy_None') }
	return ($kinds -join '; ')
}

# Drive letters of the mapped network drives of the signed-in user (also disconnected ones). Only the letters,
# never the share paths. No network access: the drive type is a local information.
function Get-SelfXNetworkDriveText {
	param([string[]]$Letters)
	$valid = @($Letters | Where-Object { $_ })
	if (-not $valid.Count) { return (Get-SelfXInfoText 'Network_Drives_None') }
	return (($valid | Sort-Object) -join ', ')
}

# Uptime text and status. From WarnDays days without a restart the row is a warning (Pending) with a hint.
# Read-only: SelfX never restarts Windows. Note: with fast startup "Shut down" does not reset the uptime.
function Get-SelfXUptimeInfo {
	param([timespan]$Uptime, [int]$WarnDays = 7)
	$text = Get-SelfXInfoText 'Uptime_Value' $Uptime.Days $Uptime.Hours $Uptime.Minutes
	if ($Uptime.TotalDays -ge $WarnDays) {
		return [pscustomobject]@{ Value = ('{0} ({1})' -f $text, (Get-SelfXInfoText 'Uptime_Restart_Hint')); Status = 'Pending' }
	}
	return [pscustomobject]@{ Value = $text; Status = '' }
}

function ConvertTo-SelfXCitrixWorkspaceText {
	# Version text of the Citrix Workspace app from the entries of the program list (objects with DisplayName and DisplayVersion),
	# for example "24.9.10.64 (Citrix Workspace 2409)". $null when the app is not installed. Other Citrix products whose name
	# starts with "Citrix Workspace" (Environment Management agent, browser) are ignored; the Receiver is not supported.
	param($Entries)
	$apps = @($Entries | Where-Object {
		$_ -and "$($_.DisplayName)" -match '^Citrix Workspace' -and "$($_.DisplayName)" -notmatch 'Environment Management|Browser|Session Recording|Web Extension'
	})
	if (-not $apps.Count) { return $null }
	$best = $apps | Sort-Object -Descending -Property @{ Expression = { $v = $null; if ([version]::TryParse("$($_.DisplayVersion)", [ref]$v)) { $v } else { [version]'0.0' } } } | Select-Object -First 1
	$name = ("$($best.DisplayName)" -replace '[\x00-\x1F]', '').Trim()
	$version = ("$($best.DisplayVersion)" -replace '[\x00-\x1F]', '').Trim()
	if ($name.Length -gt 60) { $name = $name.Substring(0, 60) }
	if ($version.Length -gt 30) { $version = $version.Substring(0, 30) }
	if ($version) { return "$version ($name)" }
	return $name
}

function Get-SelfXCitrixWorkspaceText {
	# Reads the program list of the machine (64 bit and 32 bit view; the Workspace app is installed per machine, for example
	# through Intune) and returns the version text, or $null when the app is not installed. Only reads.
	$entries = foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
		Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
			Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue | Select-Object DisplayName, DisplayVersion
		}
	}
	return (ConvertTo-SelfXCitrixWorkspaceText -Entries @($entries))
}

function New-SelfXInfoItem {
	param(
		[string]$Category,
		[string]$Property,
		$Value,
		[string]$Status = ''
	)
	# Empty values are shown as "n/a" (localized).
	if ($null -eq $Value -or "$Value" -eq '') { $Value = Get-SelfXInfoText 'Not_Available' }
	[pscustomobject]@{
		Category = $Category
		Property = $Property
		Value    = ($Value -join ', ')
		Status   = $Status
	}
}

function Update-SelfXTimeZone {
    # .NET caches the time zone per process. SelfX and the tray icon run for a long time (for example
    # across the automatic time zone change after the OOBE), so the cache is cleared before times are shown.
    [TimeZoneInfo]::ClearCachedData()
}

function ConvertTo-SelfXUserTime {
    # Converts a time to the current time zone of the user. Utc and Local kinds are converted exactly;
    # Unspecified is treated as UTC (all times of the service are transported in UTC).
    param([datetime]$Time)
    Update-SelfXTimeZone
    if ($Time.Kind -eq [DateTimeKind]::Local) { $Time = $Time.ToUniversalTime() }
    return [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::SpecifyKind($Time, [DateTimeKind]::Utc), [TimeZoneInfo]::Local)
}

function Format-SelfXUserTimeText {
    # Replaces the UTC markers {utc:yyyy-MM-ddTHH:mm:ssZ} that HealthStatus.ps1 (SYSTEM) writes into
    # the detail texts with the time in the time zone and date format of the user.
    param([string]$Text)
    if ($Text -notmatch '\{utc:') { return $Text }
    return [regex]::Replace($Text, '\{utc:(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\}', {
        param($match)
        try {
            $utc = [datetime]::ParseExact($match.Groups[1].Value, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal')
            (ConvertTo-SelfXUserTime $utc).ToString('g')
        } catch { $match.Value }
    })
}

function Add-SelfXAppErrorText {
	# Row "Company apps": HealthStatus.ps1 (SYSTEM) writes the codes in English as "error 0x8XXXXXXX". For every known code (an
	# English default AppError_<8 hex digits> exists) the explanation in the language of the user is added once at the end. An exit
	# code of an installer written as 0x0000XXXX is looked up as the Windows error 0x8007XXXX. Unknown codes stay as they are.
	param([AllowEmptyString()][string]$Detail)
	if ($Detail -notmatch 'error 0x[0-9A-Fa-f]{8}') { return $Detail }
	$added = New-Object System.Collections.Generic.List[string]
	$notes = New-Object System.Collections.Generic.List[string]
	foreach ($match in [regex]::Matches($Detail, 'error 0x([0-9A-Fa-f]{8})')) {
		$hex = $match.Groups[1].Value.ToUpperInvariant()
		if ($hex -match '^0000([0-9A-F]{4})$') { $hex = '8007' + $Matches[1] }
		$key = "AppError_$hex"
		if ($added.Contains($key) -or -not $Script:SelfXInfoDefaultText.ContainsKey($key)) { continue }
		$added.Add($key)
		$notes.Add(('0x{0}: {1}' -f $hex, (Get-SelfXInfoText $key)))
	}
	if (-not $notes.Count) { return $Detail }
	return ($Detail + ' ' + ($notes -join ' '))
}

function ConvertTo-SelfXHealthInfo {
    param([object[]]$Results)
    foreach ($result in $Results) {
        $property = Get-SelfXInfoText "Health_$($result.Id)"
        if ($result.Name) { $property += " ($($result.Name))" }
        $detailText = Format-SelfXUserTimeText "$($result.Detail)"
        if ("$($result.Id)" -eq 'Applications') { $detailText = Add-SelfXAppErrorText $detailText }
        $value = (Get-SelfXInfoText "Health_$($result.Status)") + ' - ' + $detailText
        $item = New-SelfXInfoItem (Get-SelfXInfoText 'Category_Health') $property $value $result.Status
        $item | Add-Member -NotePropertyName Remediation -NotePropertyValue "$($result.Remediation)"
        # Optional first part of the repair in the context of the user (Health_Config.xml UserScript).
        $item | Add-Member -NotePropertyName UserRemediation -NotePropertyValue "$($result.UserRemediation)"
        # Technical identity of the check, used by the per-row recheck button.
        $item | Add-Member -NotePropertyName HealthId -NotePropertyValue "$($result.Id)"
        $item | Add-Member -NotePropertyName HealthName -NotePropertyValue "$($result.Name)"
        # Detail without the status prefix, shown on the status cards.
        $item | Add-Member -NotePropertyName Detail -NotePropertyValue $detailText
        $item
    }
}

function Set-SelfXInfoText {
    # Overlays the localized labels on the English defaults.
    param([hashtable]$Text = @{})
    $Script:SelfXInfoText = $Script:SelfXInfoDefaultText.Clone()
    foreach ($key in $Text.Keys) { if (-not [string]::IsNullOrEmpty($Text[$key])) { $Script:SelfXInfoText[$key] = $Text[$key] } }
}

function Get-SelfXHealthCheckInfo {
    # Re-runs one health check through the local service and returns its row(s).
    # A failure returns one Unknown row that keeps the check identity so it can be retried.
    param([string]$Id, [string]$Name = '', [hashtable]$Text = @{})
    Set-SelfXInfoText $Text
    try {
        ConvertTo-SelfXHealthInfo -Results @(Get-SelfXServiceHealthReport -Id $Id -Name $Name)
    } catch {
        $property = Get-SelfXInfoText "Health_$Id"
        if ($Name) { $property += " ($Name)" }
        $item = New-SelfXInfoItem (Get-SelfXInfoText 'Category_Health') $property (Get-SelfXInfoText 'Health_Unavailable' $_.Exception.Message) 'Unknown'
        $item | Add-Member -NotePropertyName Remediation -NotePropertyValue ''
        $item | Add-Member -NotePropertyName UserRemediation -NotePropertyValue ''
        $item | Add-Member -NotePropertyName HealthId -NotePropertyValue $Id
        $item | Add-Member -NotePropertyName HealthName -NotePropertyValue $Name
        $item | Add-Member -NotePropertyName Detail -NotePropertyValue (Get-SelfXInfoText 'Health_Unavailable' $_.Exception.Message)
        $item
    }
}

function Get-SelfXStatusData {
    # Device status for the GUI and the tray icon (runs in a background runspace):
    #   Cached = status cache of the background checks (STATUS, immediate), Full = all checks now (HEALTH),
    #   Single = one check now. Returns Mode, Ok, Items (status rows), CollectedAt, IntervalMinutes,
    #   State, Id, Name and Message (error text when Ok is false).
    param([ValidateSet('Cached', 'Full', 'Single')][string]$Mode, [string]$Id = '', [string]$Name = '', [hashtable]$Text = @{})
    Set-SelfXInfoText $Text
    $data = [pscustomobject]@{ Mode = $Mode; Ok = $true; Items = @(); CollectedAt = $null; IntervalMinutes = 0; State = ''; Id = $Id; Name = $Name; Message = '' }
    try {
        switch ($Mode) {
            'Cached' {
                $status = Get-SelfXServiceStatusCache
                $data.CollectedAt = $status.CollectedAt
                $data.IntervalMinutes = $status.IntervalMinutes
                $data.State = $status.State
                if (@($status.Results).Count) { $data.Items = @(ConvertTo-SelfXHealthInfo -Results @($status.Results)) }
            }
            'Full' {
                $data.Items = @(ConvertTo-SelfXHealthInfo -Results @(Get-SelfXServiceHealthReport))
                $data.CollectedAt = [datetime]::UtcNow
            }
            'Single' {
                $data.Items = @(Get-SelfXHealthCheckInfo -Id $Id -Name $Name -Text $Text)
                $data.CollectedAt = [datetime]::UtcNow
            }
        }
    } catch {
        $data.Ok = $false
        $data.Message = $_.Exception.Message
    }
    return $data
}

function Get-SelfXSystemInfoCachePath {
    # Per-user cache of the last collected system information (no administrator data).
    return (Join-Path $env:LOCALAPPDATA 'SelfX\SystemInfo.json')
}

function Save-SelfXSystemInfoCache {
    # Stores the information rows (not the status rows) so the next start can show them immediately.
    param([object[]]$Items, [string]$Culture = '', [string]$Path = (Get-SelfXSystemInfoCachePath))
    $rows = @($Items | Where-Object { $_ -and -not "$($_.Status)" } | ForEach-Object {
        [pscustomobject]@{ Category = "$($_.Category)"; Property = "$($_.Property)"; Value = "$($_.Value)" } })
    if (-not $rows.Count) { return }
    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $data = [pscustomobject]@{ CollectedAt = [datetime]::UtcNow.ToString('o'); Culture = $Culture; Items = $rows }
    $temp = "$Path.tmp"
    [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $data -Depth 4 -Compress), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Read-SelfXSystemInfoCache {
    # Returns CollectedAt and Items of the cache, or $null when it is missing, invalid or in another language.
    param([string]$Culture = '', [string]$Path = (Get-SelfXSystemInfoCachePath))
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        $data = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -ErrorAction Stop
        if ("$($data.Culture)" -ne $Culture) { return $null }
        $items = @($data.Items | Where-Object { $_.Category -and $_.Property } | ForEach-Object {
            New-SelfXInfoItem "$($_.Category)" "$($_.Property)" "$($_.Value)" })
        if (-not $items.Count) { return $null }
        # Windows PowerShell 5.1 returns the time as text, PowerShell 7 already as [datetime] (kind lost when converted back to text).
        $collected = $data.CollectedAt
        if ($collected -is [datetime]) { $collected = $collected.ToUniversalTime() }
        else { $collected = [datetime]::Parse("$collected", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) }
        return [pscustomobject]@{ CollectedAt = $collected; Items = $items }
    } catch { return $null }
}

# Runs a script block and returns $null instead of throwing, so one failing source does not stop the report.
function Invoke-SelfXSafe {
	param([scriptblock]$ScriptBlock)
	try { & $ScriptBlock } catch { $null }
}

function Format-SelfXBytes {
	param([double]$Bytes)
	if ($Bytes -ge 1TB) { return '{0:N1} TB' -f ($Bytes / 1TB) }
	return '{0:N1} GB' -f ($Bytes / 1GB)
}

# Parses "dsregcmd /status" into a hashtable (for example AzureAdJoined = YES).
function Get-SelfXDsregStatus {
	$result = @{}
	$output = Invoke-SelfXSafe { & "$env:SystemRoot\System32\dsregcmd.exe" /status 2>$null }
	foreach ($line in $output) {
		if ($line -match '^\s*([A-Za-z]+)\s*:\s*(.+?)\s*$') {
			if (-not $result.ContainsKey($Matches[1])) { $result[$Matches[1]] = $Matches[2] }
		}
	}
	return $result
}

# Returns the most recent Intune (OMA-DM) server contact of all MDM accounts.
# ServerLastAccessTime of the OMA-DM account (ConnInfo) is written in the local time of the device, although
# the value ends with "Z" (for example 20261106T123322Z at 12:33 CET = 11:33 UTC). Converting it from UTC would
# show a time in the future, so it is read as local time.
function ConvertFrom-SelfXOmaDmTime {
	param([string]$Value)
	$parsed = [datetime]::MinValue
	if ([datetime]::TryParseExact("$Value".Trim(), "yyyyMMdd'T'HHmmss'Z'", [Globalization.CultureInfo]::InvariantCulture,
		[Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) { return $parsed }
	return $null
}

function Get-SelfXIntuneLastSync {
	$accountsPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
	$dates = foreach ($account in (Get-ChildItem -Path $accountsPath -ErrorAction SilentlyContinue)) {
		$time = (Get-ItemProperty -Path "$($account.PSPath)\Protected\ConnInfo" -ErrorAction SilentlyContinue).ServerLastAccessTime
		if ($time) { ConvertFrom-SelfXOmaDmTime $time }
	}
	$last = $dates | Sort-Object -Descending | Select-Object -First 1
	if ($last) { return $last.ToString('yyyy-MM-dd HH:mm:ss') }
	return Get-SelfXInfoText 'Not_Enrolled'
}

# Returns the UPN of the user that enrolled the device in Intune.
function Get-SelfXMdmEnrollmentUpn {
	foreach ($enrollment in (Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
		$props = Get-ItemProperty -Path $enrollment.PSPath -ErrorAction SilentlyContinue
		if ($props.ProviderID -eq 'MS DM Server' -and $props.UPN) { return $props.UPN }
	}
	return $null
}

# Returns the SSID of the connected Wi-Fi network (netsh), or $null.
function Get-SelfXWifiSsid {
	$output = Invoke-SelfXSafe { & "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>$null }
	foreach ($line in $output) {
		if ($line -match '^\s*SSID\s*:\s*(.+?)\s*$') { return $Matches[1] }
	}
	return $null
}

# Tests a TCP connection with a timeout. Used for the "Internet reachable" line.
function Test-SelfXTcpConnection {
	param(
		[string]$HostName,
		[int]$Port = 80,
		[int]$TimeoutMs = 3000
	)
	if (-not $HostName) { return $false }
	$client = New-Object System.Net.Sockets.TcpClient
	try {
		$async = $client.BeginConnect($HostName, $Port, $null, $null)
		if ($async.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
			$client.EndConnect($async)
			return $true
		}
		return $false
	}
	catch { return $false }
	finally { $client.Close() }
}

# Adapters of common VPN clients (also used to keep VPN tunnels out of the LAN detection).
$Script:SelfXVpnAdapterPattern = 'VPN|AnyConnect|GlobalProtect|Fortinet|WireGuard|Pulse|Zscaler|PANGP|TAP-Windows'

# Detects an active VPN: Windows VPN profiles first, then adapters of common VPN clients.
function Test-SelfXVpnConnection {
	$vpn = @(Invoke-SelfXSafe { Get-VpnConnection -ErrorAction Stop }) + @(Invoke-SelfXSafe { Get-VpnConnection -AllUserConnection -ErrorAction Stop })
	if ($vpn | Where-Object { $_.ConnectionStatus -eq 'Connected' }) { return $true }
	$vpnAdapters = Invoke-SelfXSafe {
		Get-SelfXNetAdapters | Where-Object {
			$_.Status -eq 'Up' -and $_.InterfaceDescription -match $Script:SelfXVpnAdapterPattern
		}
	}
	return [bool]$vpnAdapters
}

# Classifies the connected adapters (objects of Get-SelfXNetAdapters, SelfXNetwork.ps1) into LAN, Wi-Fi and mobile broadband.
# An adapter counts when it is Up and either a hardware adapter or carries a default route (GatewayIndexes).
# Virtual network adapters of virtual machines (Hyper-V, VMware, VirtualBox guests) report the physical
# medium "Unspecified" and are no hardware adapters, so the default route identifies them as LAN connection.
# The virtual switch adapters of a Hyper-V host (vEthernet), VPN tunnels and Bluetooth never count as LAN.
function Get-SelfXConnectionTypes {
	param(
		[object[]]$Adapters = @(),
		[int[]]$GatewayIndexes = @()
	)
	$result = [pscustomobject]@{ Lan = $false; WiFi = $false; Wwan = $false }
	foreach ($adapter in @($Adapters | Where-Object { $_ -and "$($_.Status)" -eq 'Up' })) {
		$physicalMedium = "$($adapter.PhysicalMediaType)"
		$ndisMedium = "$($adapter.NdisPhysicalMedium)"
		$hardware = ($adapter.HardwareInterface -eq $true) -or ($adapter.ConnectorPresent -eq $true)
		$routed = $GatewayIndexes -contains [int]$adapter.ifIndex
		if (-not ($hardware -or $routed)) { continue }
		if ($physicalMedium -match '802\.11' -or $ndisMedium -eq '9') { $result.WiFi = $true; continue }
		if ($physicalMedium -eq 'Wireless WAN' -or $ndisMedium -eq '8') { $result.Wwan = $true; continue }
		if ($physicalMedium -match 'Bluetooth' -or $ndisMedium -eq '10') { continue }
		if ("$($adapter.InterfaceDescription)" -match $Script:SelfXVpnAdapterPattern -or "$($adapter.InterfaceDescription)" -match 'Hyper-V Virtual Ethernet Adapter') { continue }
		if (("$($adapter.MediaType)" -eq '802.3') -and (($hardware -and $physicalMedium -eq '802.3') -or $routed)) { $result.Lan = $true }
	}
	return $result
}

# Interface indexes with a default route (IPv4 or IPv6), i.e. adapters that connect to other networks.
function Get-SelfXGatewayInterfaceIndexes {
	return @(Invoke-SelfXSafe { Get-SelfXDefaultRouteInterfaceIndexes })
}

# Network measurements (optional, off by default). Targets come only from Network_Test_Config.xml
# (writable by administrators only), never from the user. Everything runs in the user context and only reads.

# True for a DNS name (letters, digits, hyphen, dots; labels up to 63 characters, total up to 253) or an IPv4 address.
function Test-SelfXNetworkHostName {
	param([string]$Name)
	if ([string]::IsNullOrEmpty($Name) -or $Name.Length -gt 253) { return $false }
	return ($Name -match '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\z')
}

# True for an IPv4 address in dotted notation (no DNS lookup is measured for it).
function Test-SelfXIPv4Literal {
	param([string]$Name)
	if ($Name -notmatch '^\d{1,3}(\.\d{1,3}){3}\z') { return $false }
	$address = $null
	return [Net.IPAddress]::TryParse($Name, [ref]$address)
}

# Groups and kinds of targets. The file selects from these fixed lists; it cannot add to them.
$Script:SelfXNetworkGroups = @('Local', 'Internet', 'Microsoft', 'Company')
$Script:SelfXNetworkKinds = @('Vpn', 'Intranet')

# Reads Network_Test_Config.xml. Entries that are not valid are skipped and named in Errors; a file that cannot
# be read switches the measurements off. Limits: up to MaxTargets targets, 1-5 samples, 200-5000 ms timeout.
# A target may name a Group (Local, Internet, Microsoft, Company; without Group it is measured but not part of the
# verdict) and, for Company only, a Kind (Vpn, Intranet).
function Read-SelfXNetworkTestConfig {
	param([Parameter(Mandatory = $true)][string]$Path, [int]$MaxTargets = 12)
	$errors = New-Object System.Collections.Generic.List[string]
	$targets = New-Object System.Collections.Generic.List[object]
	$result = [pscustomobject]@{ Enabled = $false; Gateway = $true; Microsoft = $true; HostNames = $true; Samples = 3; TimeoutMs = 2000; Targets = @(); Errors = @() }
	$doc = New-Object Xml.XmlDocument
	$doc.XmlResolver = $null
	$reader = $null
	try {
		$settings = New-Object Xml.XmlReaderSettings
		$settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
		$settings.XmlResolver = $null
		$reader = [Xml.XmlReader]::Create($Path, $settings)
		$doc.Load($reader)
	} catch {
		$result.Errors = @("The file cannot be read: $($_.Exception.Message)")
		return $result
	} finally {
		if ($reader) { $reader.Dispose() }
	}
	$node = $doc.SelectSingleNode('/Network_Test_Config/Settings')
	if (-not $node) { $result.Errors = @('Settings element is missing.'); return $result }
	$result.Enabled = ($node.GetAttribute('Enabled').Trim() -eq 'True')
	$result.Gateway = ($node.GetAttribute('Gateway').Trim() -ne 'False')
	$result.Microsoft = ($node.GetAttribute('Microsoft').Trim() -ne 'False')
	$result.HostNames = ($node.GetAttribute('HostNames').Trim() -ne 'False')
	$value = 0
	$text = $node.GetAttribute('Samples').Trim()
	if ($text) {
		if ([int]::TryParse($text, [ref]$value) -and $value -ge 1 -and $value -le 5) { $result.Samples = $value }
		else { $errors.Add('Samples must be a number from 1 to 5: 3 is used.') }
	}
	$text = $node.GetAttribute('TimeoutMs').Trim()
	if ($text) {
		if ([int]::TryParse($text, [ref]$value) -and $value -ge 200 -and $value -le 5000) { $result.TimeoutMs = $value }
		else { $errors.Add('TimeoutMs must be a number from 200 to 5000: 2000 is used.') }
	}
	$count = 0
	foreach ($target in @($doc.SelectNodes('/Network_Test_Config/Targets/Target'))) {
		$count++
		if ($count -gt $MaxTargets) { $errors.Add("More than $MaxTargets targets: the rest is ignored."); break }
		$label = $target.GetAttribute('Label').Trim()
		$name = $target.GetAttribute('Host').Trim()
		$portText = $target.GetAttribute('Port').Trim()
		$group = $target.GetAttribute('Group').Trim()
		$kind = $target.GetAttribute('Kind').Trim()
		if ($label -notmatch '^[A-Za-z0-9._ -]{1,40}\z') { $errors.Add("Target $count has no valid Label (letters, digits . _ - and space, up to 40)."); continue }
		if (-not (Test-SelfXNetworkHostName $name)) { $errors.Add("Target '$label' has no valid Host (DNS name or IPv4 address): skipped."); continue }
		$port = 0
		if ($portText) {
			if (-not ([int]::TryParse($portText, [ref]$port) -and $port -ge 1 -and $port -le 65535)) { $errors.Add("Target '$label' has no valid Port (1-65535): skipped."); continue }
		}
		if ($group -and ($Script:SelfXNetworkGroups -cnotcontains $group)) { $errors.Add("Target '$label' has no valid Group (Local, Internet, Microsoft, Company): skipped."); continue }
		if ($kind) {
			if ($Script:SelfXNetworkKinds -cnotcontains $kind) { $errors.Add("Target '$label' has no valid Kind (Vpn, Intranet): skipped."); continue }
			if ($group -cne 'Company') { $errors.Add("Target '$label': Kind is only valid with Group Company: skipped."); continue }
		}
		if (@($targets | Where-Object { $_.Label -eq $label }).Count) { $errors.Add("Target '$label' is listed twice: the first entry is used."); continue }
		$targets.Add([pscustomobject]@{ Label = $label; Host = $name; Port = $port; Group = $group; Kind = $kind })
	}
	$result.Targets = $targets.ToArray()
	$result.Errors = $errors.ToArray()
	return $result
}

# Minimum, average and maximum (whole milliseconds) of the samples; $null in Samples = lost or failed.
function Get-SelfXLatencyStats {
	param([object[]]$Samples = @())
	$values = @($Samples | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
	$sent = @($Samples).Count
	$stats = [pscustomobject]@{ Sent = $sent; Lost = ($sent - $values.Count); Min = $null; Avg = $null; Max = $null }
	if ($values.Count) {
		$measure = $values | Measure-Object -Minimum -Maximum -Average
		$stats.Min = [int][math]::Round($measure.Minimum)
		$stats.Avg = [int][math]::Round($measure.Average)
		$stats.Max = [int][math]::Round($measure.Maximum)
	}
	return $stats
}

# Time of a name resolution through the Windows resolver (its cache applies, so repeated samples can be faster).
# Returns Stats, Address (first IPv4 address, otherwise the first address; $null if it did not resolve) and Skipped
# (the Deadline was reached before all samples were taken).
function Measure-SelfXDnsLatency {
	param([string]$HostName, [int]$Samples = 3, [int]$TimeoutMs = 2000, [datetime]$Deadline = [datetime]::MaxValue)
	$times = New-Object System.Collections.Generic.List[object]
	$address = $null
	for ($i = 0; $i -lt $Samples; $i++) {
		if ([datetime]::UtcNow -gt $Deadline) { break }
		$elapsed = $null
		try {
			$stopwatch = [Diagnostics.Stopwatch]::StartNew()
			$task = [Net.Dns]::GetHostAddressesAsync($HostName)
			if ($task.Wait($TimeoutMs)) {
				$stopwatch.Stop()
				$found = @($task.Result)
				if ($found.Count) {
					$elapsed = $stopwatch.Elapsed.TotalMilliseconds
					if (-not $address) {
						$ipv4 = @($found | Where-Object { $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork })
						$address = "$(if ($ipv4.Count) { $ipv4[0] } else { $found[0] })"
					}
				}
			}
		} catch { $elapsed = $null }
		$times.Add($elapsed)
	}
	return [pscustomobject]@{ Stats = (Get-SelfXLatencyStats $times.ToArray()); Address = $address; Skipped = ($times.Count -lt $Samples) }
}

# Time to open a TCP connection to Address:Port (the connection is closed at once, no data is sent).
function Measure-SelfXTcpLatency {
	param([string]$Address, [int]$Port, [int]$Samples = 3, [int]$TimeoutMs = 2000, [datetime]$Deadline = [datetime]::MaxValue)
	$times = New-Object System.Collections.Generic.List[object]
	for ($i = 0; $i -lt $Samples; $i++) {
		if ([datetime]::UtcNow -gt $Deadline) { break }
		$elapsed = $null
		$client = New-Object System.Net.Sockets.TcpClient
		try {
			$stopwatch = [Diagnostics.Stopwatch]::StartNew()
			$async = $client.BeginConnect($Address, $Port, $null, $null)
			if ($async.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
				$client.EndConnect($async)
				$stopwatch.Stop()
				$elapsed = $stopwatch.Elapsed.TotalMilliseconds
			}
		} catch { $elapsed = $null }
		finally { $client.Close() }
		$times.Add($elapsed)
	}
	return [pscustomobject]@{ Stats = (Get-SelfXLatencyStats $times.ToArray()); Skipped = ($times.Count -lt $Samples) }
}

# Round-trip time of ICMP echo requests to Address (used for the default gateway).
function Measure-SelfXPingLatency {
	param([string]$Address, [int]$Samples = 3, [int]$TimeoutMs = 2000, [datetime]$Deadline = [datetime]::MaxValue)
	$times = New-Object System.Collections.Generic.List[object]
	$ping = New-Object System.Net.NetworkInformation.Ping
	try {
		for ($i = 0; $i -lt $Samples; $i++) {
			if ([datetime]::UtcNow -gt $Deadline) { break }
			$elapsed = $null
			try {
				$reply = $ping.Send($Address, $TimeoutMs)
				if ($reply.Status -eq [Net.NetworkInformation.IPStatus]::Success) { $elapsed = [double]$reply.RoundtripTime }
			} catch { $elapsed = $null }
			$times.Add($elapsed)
		}
	} finally { $ping.Dispose() }
	return [pscustomobject]@{ Stats = (Get-SelfXLatencyStats $times.ToArray()); Skipped = ($times.Count -lt $Samples) }
}

# Text and status of one measurement: all lost = Error, some lost = Pending (warning), otherwise no status.
function ConvertTo-SelfXLatencyInfo {
	param($Measurement)
	if ($Measurement.Skipped -and -not $Measurement.Stats.Sent) {
		return [pscustomobject]@{ Value = (Get-SelfXInfoText 'Latency_Skipped'); Status = '' }
	}
	$stats = $Measurement.Stats
	if ($stats.Lost -ge $stats.Sent) {
		return [pscustomobject]@{ Value = (Get-SelfXInfoText 'Latency_Failed' $stats.Lost $stats.Sent); Status = 'Error' }
	}
	$status = $(if ($stats.Lost) { 'Pending' } else { '' })
	return [pscustomobject]@{ Value = (Get-SelfXInfoText 'Latency_Value' $stats.Avg $stats.Min $stats.Max $stats.Lost $stats.Sent); Status = $status }
}

# Outcome of one measurement series: NotMeasured (no sample taken), Failed (all samples lost) or Reached.
function Get-SelfXMeasurementOutcome {
	param($Measurement)
	if (-not $Measurement.Stats.Sent) { return 'NotMeasured' }
	if ($Measurement.Stats.Lost -ge $Measurement.Stats.Sent) { return 'Failed' }
	return 'Reached'
}

# State of a group from the number of reached and failed targets: None (nothing measured), Ok, Partial or Fail.
function Get-SelfXGroupState {
	param([int]$Reached = 0, [int]$Failed = 0)
	if (($Reached + $Failed) -le 0) { return 'None' }
	if ($Failed -le 0) { return 'Ok' }
	if ($Reached -le 0) { return 'Fail' }
	return 'Partial'
}

# The verdict as an Id (Verdict_<Id> is the text). Pure function: only the four group states and the question whether
# the failing company targets are expected to need a VPN go in. A gateway that does not answer ping does not count as
# "router down" while the internet works (many firewalls drop ICMP): it only makes the result "Partial".
function Get-SelfXConnectionVerdict {
	param(
		[ValidateSet('Ok', 'Partial', 'Fail', 'None')][string]$Local = 'None',
		[ValidateSet('Ok', 'Partial', 'Fail', 'None')][string]$Internet = 'None',
		[ValidateSet('Ok', 'Partial', 'Fail', 'None')][string]$Microsoft = 'None',
		[ValidateSet('Ok', 'Partial', 'Fail', 'None')][string]$Company = 'None',
		[bool]$CompanyVpnExpected = $true
	)
	$internetUp = ($Internet -eq 'Ok' -or $Internet -eq 'Partial')
	if ($Local -eq 'Fail' -and -not $internetUp) { return 'LocalDown' }
	if ($Internet -eq 'Fail') { return 'InternetDown' }
	if ($internetUp) {
		if ($Microsoft -eq 'Fail') { return 'MicrosoftDown' }
		if ($Company -eq 'Fail') { return $(if ($CompanyVpnExpected) { 'CompanyVpn' } else { 'CompanyIntranet' }) }
	}
	$states = @($Local, $Internet, $Microsoft, $Company)
	if ($states -contains 'Fail' -or $states -contains 'Partial') { return 'Partial' }
	if ($states -contains 'Ok') { return 'AllOk' }
	return 'NoData'
}

# Status of an info row for a group state (OK, Pending, Error or none) and for a verdict.
function Get-SelfXCheckStatus {
	param([string]$State)
	switch ($State) { 'Ok' { return 'OK' } 'Partial' { return 'Pending' } 'Fail' { return 'Error' } default { return '' } }
}
function Get-SelfXVerdictStatus {
	param([string]$Verdict)
	switch ($Verdict) { 'AllOk' { return 'OK' } 'Partial' { return 'Pending' } 'NoData' { return '' } default { return 'Error' } }
}

# Value of a measurement row: with HostNames = False only the result, without the name and port of the target.
function Format-SelfXMeasureValue {
	param([string]$HostText, [string]$Result, [bool]$ShowHost = $true)
	if ($ShowHost) { return ('{0}: {1}' -f $HostText, $Result) }
	return $Result
}

# Info items for the network measurements: first the four group rows and the result sentence, then the details:
# default gateway (ping), per target the DNS lookup and, with a Port, the connection time. Targets are measured
# in the order Local, Internet, Microsoft, Company, others. The whole run stops after DeadlineSeconds; targets not
# reached are shown as not measured and do not count. InternetTestReachable is the result of the "Internet reachable"
# test of the system information (counts as one Internet target); $null = no result.
function Get-SelfXNetworkMeasureItems {
	param(
		[string]$Category,
		$Config,
		[string[]]$Gateways = @(),
		[object]$InternetTestReachable = $null,
		[int]$DeadlineSeconds = 15
	)
	if (-not $Config -or -not $Config.Enabled) { return @() }
	$details = New-Object System.Collections.Generic.List[object]
	$deadline = [datetime]::UtcNow.AddSeconds($DeadlineSeconds)
	$showHosts = ($null -eq $Config.HostNames) -or [bool]$Config.HostNames
	$useMicrosoft = ($null -eq $Config.Microsoft) -or [bool]$Config.Microsoft
	$reached = @{ Local = 0; Internet = 0; Microsoft = 0; Company = 0 }
	$failed = @{ Local = 0; Internet = 0; Microsoft = 0; Company = 0 }
	$companyFailedKinds = New-Object System.Collections.Generic.List[string]
	if ($null -ne $InternetTestReachable) {
		if ([bool]$InternetTestReachable) { $reached['Internet']++ } else { $failed['Internet']++ }
	}
	if ($Config.Gateway) {
		$gateway = @($Gateways | Where-Object { Test-SelfXIPv4Literal $_ } | Select-Object -First 1)
		if ($gateway.Count) {
			$ping = Measure-SelfXPingLatency -Address $gateway[0] -Samples $Config.Samples -TimeoutMs $Config.TimeoutMs -Deadline $deadline
			$info = ConvertTo-SelfXLatencyInfo $ping
			$details.Add((New-SelfXInfoItem $Category (Get-SelfXInfoText 'Latency_Gateway') $info.Value $info.Status))
			$outcome = Get-SelfXMeasurementOutcome $ping
			if ($outcome -eq 'Reached') { $reached['Local']++ } elseif ($outcome -eq 'Failed') { $failed['Local']++ }
		}
	}
	$rank = @{ Local = 0; Internet = 1; Microsoft = 2; Company = 3 }
	$index = 0
	$ordered = @(@($Config.Targets) | Where-Object { $_ } | ForEach-Object {
		$groupName = "$($_.Group)"
		[pscustomobject]@{ Target = $_; Rank = $(if ($rank.ContainsKey($groupName)) { $rank[$groupName] } else { 9 }); Index = $index++ }
	} | Sort-Object Rank, Index | ForEach-Object { $_.Target })
	foreach ($target in $ordered) {
		$group = "$($target.Group)"
		if ($group -eq 'Microsoft' -and -not $useMicrosoft) { continue }
		$address = $target.Host
		$dnsSkipped = $false
		$outcome = 'NotMeasured'
		if (-not (Test-SelfXIPv4Literal $target.Host)) {
			$dns = Measure-SelfXDnsLatency -HostName $target.Host -Samples $Config.Samples -TimeoutMs $Config.TimeoutMs -Deadline $deadline
			$info = ConvertTo-SelfXLatencyInfo $dns
			$details.Add((New-SelfXInfoItem $Category (Get-SelfXInfoText 'Latency_Dns' $target.Label) (Format-SelfXMeasureValue $target.Host $info.Value $showHosts) $info.Status))
			$address = $dns.Address
			$dnsSkipped = ($dns.Skipped -and -not $dns.Stats.Sent)
			$outcome = Get-SelfXMeasurementOutcome $dns
		}
		if ($target.Port -gt 0) {
			if ($address) {
				$tcp = Measure-SelfXTcpLatency -Address $address -Port $target.Port -Samples $Config.Samples -TimeoutMs $Config.TimeoutMs -Deadline $deadline
				$info = ConvertTo-SelfXLatencyInfo $tcp
				$outcome = Get-SelfXMeasurementOutcome $tcp
			} elseif ($dnsSkipped) {
				$info = [pscustomobject]@{ Value = (Get-SelfXInfoText 'Latency_Skipped'); Status = '' }
				$outcome = 'NotMeasured'
			} else {
				$info = [pscustomobject]@{ Value = (Get-SelfXInfoText 'Latency_Failed' $Config.Samples $Config.Samples); Status = 'Error' }
				$outcome = 'Failed'
			}
			$details.Add((New-SelfXInfoItem $Category (Get-SelfXInfoText 'Latency_Connection' $target.Label) (Format-SelfXMeasureValue ('{0}:{1}' -f $target.Host, $target.Port) $info.Value $showHosts) $info.Status))
		}
		if ($reached.ContainsKey($group)) {
			if ($outcome -eq 'Reached') { $reached[$group]++ }
			elseif ($outcome -eq 'Failed') {
				$failed[$group]++
				if ($group -eq 'Company') { $companyFailedKinds.Add("$($target.Kind)") }
			}
		}
	}
	$summary = New-Object System.Collections.Generic.List[object]
	$states = @{}
	foreach ($group in $Script:SelfXNetworkGroups) {
		if ($group -eq 'Microsoft' -and -not $useMicrosoft) { $states[$group] = 'None'; continue }
		$state = Get-SelfXGroupState -Reached $reached[$group] -Failed $failed[$group]
		$states[$group] = $state
		$total = $reached[$group] + $failed[$group]
		$text = $(if ($state -eq 'None') { Get-SelfXInfoText 'Check_State_None' } else { Get-SelfXInfoText "Check_State_$state" $reached[$group] $total })
		$summary.Add((New-SelfXInfoItem $Category (Get-SelfXInfoText "Check_$group") $text (Get-SelfXCheckStatus $state)))
	}
	$vpnExpected = ($companyFailedKinds.Count -eq 0) -or (@($companyFailedKinds | Where-Object { $_ -ne 'Intranet' }).Count -gt 0)
	$verdict = Get-SelfXConnectionVerdict -Local $states['Local'] -Internet $states['Internet'] -Microsoft $states['Microsoft'] -Company $states['Company'] -CompanyVpnExpected $vpnExpected
	$summary.Add((New-SelfXInfoItem $Category (Get-SelfXInfoText 'Check_Result') (Get-SelfXInfoText "Verdict_$verdict") (Get-SelfXVerdictStatus $verdict)))
	return (@($summary.ToArray()) + @($details.ToArray()))
}

# Collects all information and returns a list of Category/Property/Value objects.
function Get-SelfXSystemInfo {
	param(
		[string]$InternetTestHost = 'www.msftconnecttest.com',
		[int]$InternetTestPort = 80,
		[string]$NetworkTestConfigPath = '',
		[hashtable]$Text = @{},
		[switch]$IncludeHealth,
		# Environment_Mode TerminalServer (SelfXEnvironment.ps1, Get-SelfXViewScope): no rows of LAN, Wi-Fi, mobile and VPN.
		[switch]$TerminalServer,
		# Rows of the class Server (device, Windows, management, addresses, connection check). False for a normal user on a terminal server.
		[bool]$ServerRows = $true
	)

	# Overlay the localized labels on the English defaults.
	Set-SelfXInfoText $Text
	$L = { param($k) Get-SelfXInfoText $k }
	# All local times below (boot, Intune sync, collected at) use the current time zone of the user.
	Update-SelfXTimeZone

	$items = New-Object System.Collections.Generic.List[object]
	$yesNo = { param($v) if ($v) { Get-SelfXInfoText 'Yes' } else { Get-SelfXInfoText 'No' } }
	# dsregcmd reports YES/NO in English; show them in the UI language.
	$dsregYesNo = { param($v) switch ("$v") { 'YES' { Get-SelfXInfoText 'Yes' } 'NO' { Get-SelfXInfoText 'No' } default { $v } } }

	$catDevice = Get-SelfXInfoText 'Category_Device'
	$catWindows = Get-SelfXInfoText 'Category_Windows'
	$catUser = Get-SelfXInfoText 'Category_User'
	$catNetwork = Get-SelfXInfoText 'Category_Network'
	$catReport = Get-SelfXInfoText 'Category_Report'

	# CIM and registry sources; each one may fail on its own without stopping the report. Environment_Mode TerminalServer: rows of the
	# class Server (the device, Windows, the management and the addresses of the server) only with ServerRows (elevated administrators),
	# and the kinds of connection (LAN, Wi-Fi, mobile, VPN) not at all. What is not shown is not read (no dsregcmd, no internet test).
	if ($ServerRows) {
		$cs   = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop }
		$os   = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop }
		$bios = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop }
		$cpu  = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1 }
		$cv   = Invoke-SelfXSafe { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop }

		# Device
		$items.Add((New-SelfXInfoItem $catDevice (& $L 'Computer_Name') $env:COMPUTERNAME))
		$items.Add((New-SelfXInfoItem $catDevice (& $L 'Manufacturer') $cs.Manufacturer))
		$items.Add((New-SelfXInfoItem $catDevice (& $L 'Model') $cs.Model))
		$items.Add((New-SelfXInfoItem $catDevice (& $L 'Serial_Number') $bios.SerialNumber))
		$items.Add((New-SelfXInfoItem $catDevice (& $L 'BIOS_Version') $bios.SMBIOSBIOSVersion))
		$items.Add((New-SelfXInfoItem $catDevice (& $L 'Processor') ("$($cpu.Name)".Trim())))
		if ($cs.TotalPhysicalMemory) {
			$items.Add((New-SelfXInfoItem $catDevice (& $L 'Memory') (Format-SelfXBytes $cs.TotalPhysicalMemory)))
		}
		$systemDrive = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop }
		if ($systemDrive.Size) {
			$freePercent = [math]::Round(($systemDrive.FreeSpace / $systemDrive.Size) * 100)
			$items.Add((New-SelfXInfoItem $catDevice (Get-SelfXInfoText 'Free_Space' $env:SystemDrive) (Get-SelfXInfoText 'Free_Space_Value' (Format-SelfXBytes $systemDrive.FreeSpace) (Format-SelfXBytes $systemDrive.Size) $freePercent)))
		}
		$battery = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1 }
		if ($battery) {
			$items.Add((New-SelfXInfoItem $catDevice (& $L 'Battery') ("$($battery.EstimatedChargeRemaining)%")))
		}
	}
	# Citrix Workspace app (only when installed); the row also goes into the support ticket (device information).
	$citrixText = Invoke-SelfXSafe { Get-SelfXCitrixWorkspaceText }
	if ($citrixText) { $items.Add((New-SelfXInfoItem $catDevice 'Citrix Workspace' $citrixText)) }

	# Windows
	if ($ServerRows) {
		$osName = "$($os.Caption)".Replace('Microsoft ', '')
		$items.Add((New-SelfXInfoItem $catWindows (& $L 'Windows_Version') ("$osName $($cv.DisplayVersion)".Trim())))
		if ($cv.CurrentBuild) {
			$build = $cv.CurrentBuild
			if ($null -ne $cv.UBR) { $build = "$build.$($cv.UBR)" }
			$items.Add((New-SelfXInfoItem $catWindows (& $L 'OS_Build') $build))
		}
		if ($os.LastBootUpTime) {
			$uptime = (Get-Date) - $os.LastBootUpTime
			$items.Add((New-SelfXInfoItem $catWindows (& $L 'Last_Boot') $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')))
			$uptimeInfo = Get-SelfXUptimeInfo -Uptime $uptime
			$items.Add((New-SelfXInfoItem $catWindows (& $L 'Uptime') $uptimeInfo.Value $uptimeInfo.Status))
		}
		$lastUpdate = Invoke-SelfXSafe { Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1 }
		if ($lastUpdate) {
			$items.Add((New-SelfXInfoItem $catWindows (& $L 'Last_Update') ('{0} ({1})' -f $lastUpdate.InstalledOn.ToString('yyyy-MM-dd'), $lastUpdate.HotFixID)))
		}
	}
	$items.Add((New-SelfXInfoItem $catWindows (& $L 'Time_Zone') (Invoke-SelfXSafe { (Get-TimeZone).DisplayName })))

	# User and management
	$upn = Invoke-SelfXSafe { & "$env:SystemRoot\System32\whoami.exe" /upn 2>$null }
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Current_User') "$env:USERDOMAIN\$env:USERNAME"))
	if ("$upn" -match '@') { $items.Add((New-SelfXInfoItem $catUser (& $L 'User_Principal_Name') "$upn".Trim())) }
	if ($ServerRows) {
		$dsreg = Get-SelfXDsregStatus
		$items.Add((New-SelfXInfoItem $catUser (& $L 'Domain') $cs.Domain))
		$items.Add((New-SelfXInfoItem $catUser (& $L 'Entra_Joined') (& $dsregYesNo $dsreg['AzureAdJoined'])))
		$items.Add((New-SelfXInfoItem $catUser (& $L 'Domain_Joined') (& $dsregYesNo $dsreg['DomainJoined'])))
		if ($dsreg['TenantName']) { $items.Add((New-SelfXInfoItem $catUser (& $L 'Tenant') $dsreg['TenantName'])) }
		if ($dsreg['DeviceId']) { $items.Add((New-SelfXInfoItem $catUser (& $L 'Entra_Device_Id') $dsreg['DeviceId'])) }
		$mdmUpn = Get-SelfXMdmEnrollmentUpn
		if ($mdmUpn) { $items.Add((New-SelfXInfoItem $catUser (& $L 'Intune_User') $mdmUpn)) }
		$items.Add((New-SelfXInfoItem $catUser (& $L 'Intune_Last_Sync') (Get-SelfXIntuneLastSync)))
	}

	# Network: connection types, VPN, internet test and addresses of all IP-enabled adapters
	if (-not $TerminalServer) {
		$connections = Get-SelfXConnectionTypes -Adapters @(Invoke-SelfXSafe { Get-SelfXNetAdapters }) -GatewayIndexes (Get-SelfXGatewayInterfaceIndexes)
		$lanUp  = $connections.Lan
		$wifiUp = $connections.WiFi
		$wwanUp = $connections.Wwan
		$ssid = Get-SelfXWifiSsid
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'LAN_Connected') (& $yesNo $lanUp)))
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'WiFi_Connected') (& $yesNo $wifiUp)))
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'WWAN_Connected') (& $yesNo $wwanUp)))
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'WiFi_SSID') $(if ($ssid) { $ssid } else { Get-SelfXInfoText 'No_WiFi' })))
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'VPN_Connected') (& $yesNo (Test-SelfXVpnConnection))))
	}
	if ($ServerRows) {
		$internetReachable = [bool](Test-SelfXTcpConnection -HostName $InternetTestHost -Port $InternetTestPort)
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'Internet_Reachable') (& $yesNo $internetReachable)))

		$nics = @(Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction Stop })
		$ipv4 = @($nics | ForEach-Object { $_.IPAddress } | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Sort-Object -Unique)
		$ipv6 = @($nics | ForEach-Object { $_.IPAddress } | Where-Object { $_ -match ':' -and $_ -notmatch '^fe80' } | Sort-Object -Unique)
		$gateways = @($nics | ForEach-Object { $_.DefaultIPGateway } | Where-Object { $_ } | Sort-Object -Unique)
		$dns = @($nics | ForEach-Object { $_.DNSServerSearchOrder } | Where-Object { $_ } | Select-Object -Unique)
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'IPv4') $ipv4))
		if ($ipv6.Count) { $items.Add((New-SelfXInfoItem $catNetwork (& $L 'IPv6') $ipv6)) }
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'Gateway') $gateways))
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'DNS') $dns))
		$items.Add((New-SelfXInfoItem $catNetwork (& $L 'MAC') (@($nics | ForEach-Object { $_.MACAddress } | Where-Object { $_ } | Sort-Object -Unique))))
	}
	$proxySettings = Invoke-SelfXSafe { Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop }
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'Proxy') (ConvertTo-SelfXProxyText $proxySettings)))
	$driveLetters = Invoke-SelfXSafe { @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [IO.DriveType]::Network } | ForEach-Object { $_.Name.TrimEnd('\') }) }
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'Network_Drives') (Get-SelfXNetworkDriveText $driveLetters)))
	# Optional connection check and latency measurements (only with an enabled Network_Test_Config.xml; rows of the class Server).
	if ($ServerRows -and $NetworkTestConfigPath -and (Test-Path -LiteralPath $NetworkTestConfigPath -PathType Leaf)) {
		$measureConfig = Invoke-SelfXSafe { Read-SelfXNetworkTestConfig -Path $NetworkTestConfigPath }
		foreach ($measureItem in @(Invoke-SelfXSafe { Get-SelfXNetworkMeasureItems -Category $catNetwork -Config $measureConfig -Gateways $gateways -InternetTestReachable $internetReachable })) {
			if ($measureItem) { $items.Add($measureItem) }
		}
	}

	$items.Add((New-SelfXInfoItem $catReport (& $L 'Collected_At') (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
	if ($IncludeHealth) {
		try {
			foreach ($health in (ConvertTo-SelfXHealthInfo -Results @(Get-SelfXServiceHealthReport))) { $items.Add($health) }
		} catch {
			$detail = Get-SelfXInfoText 'Health_Unavailable' $_.Exception.Message
			$items.Add((New-SelfXInfoItem (Get-SelfXInfoText 'Category_Health') (Get-SelfXInfoText 'Health_Collection') $detail 'Unknown'))
		}
	}
	return $items
}

# Formats the items as plain text with one [Category] block per group (used for copy and TXT export).
function ConvertTo-SelfXSystemInfoText {
	param([object[]]$Items)
	$lines = New-Object System.Collections.Generic.List[string]
	foreach ($group in ($Items | Group-Object Category)) {
		$lines.Add("[$($group.Name)]")
		foreach ($item in $group.Group) { $lines.Add(('{0,-28}: {1}' -f $item.Property, $item.Value)) }
		$lines.Add('')
	}
	return ($lines -join [Environment]::NewLine)
}

# Neutralizes CSV/formula injection (OWASP "CSV Injection"): a text cell that starts with = + - @ or a tab, CR or LF can be
# run as a formula when the file is opened in Excel (values such as the Wi-Fi SSID come from outside). Such a value gets a
# leading apostrophe; spreadsheet programs then show it as plain text. Only the CSV export uses this (HTML is encoded by
# ConvertTo-Html, JSON and TXT are not evaluated). Non-text values and all other text stay unchanged.
function ConvertTo-SelfXCsvSafeValue {
	param($Value)
	if ($Value -isnot [string]) { return $Value }
	if ($Value.Length -gt 0 -and "=+-@`t`r`n".IndexOf($Value[0]) -ge 0) { return ("'" + $Value) }
	return $Value
}

# Returns copies of the items with every text property made safe for CSV (see ConvertTo-SelfXCsvSafeValue).
# The original items (shown in the window, used for copy and the other formats) are not changed.
function ConvertTo-SelfXCsvSafeItems {
	param([object[]]$Items)
	foreach ($item in $Items) {
		$copy = [ordered]@{}
		foreach ($property in $item.PSObject.Properties) { $copy[$property.Name] = ConvertTo-SelfXCsvSafeValue $property.Value }
		[pscustomobject]$copy
	}
}

# Saves the items to Path. The format follows the file extension: .csv, .json, .html, anything else = text.
function Export-SelfXSystemInfo {
	param(
		[object[]]$Items,
		[string]$Path,
		[string]$Title = 'System information'
	)
	switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
		'.csv'  { ConvertTo-SelfXCsvSafeItems -Items $Items | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 }
		'.json' { $Items | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Path -Encoding UTF8 }
		'.html' {
			$Items | ConvertTo-Html -Title "$Title - $env:COMPUTERNAME" -PreContent ("<h2>{0} - {1}</h2>" -f [System.Net.WebUtility]::HtmlEncode($Title), $env:COMPUTERNAME) |
				Set-Content -LiteralPath $Path -Encoding UTF8
		}
		default { ConvertTo-SelfXSystemInfoText -Items $Items | Set-Content -LiteralPath $Path -Encoding UTF8 }
	}
}
