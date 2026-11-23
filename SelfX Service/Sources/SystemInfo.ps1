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
    Version : 2.8.8

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version: System information tab
    2.8.8    2026-11-22  fubu2k               Optional latency measurements (default gateway, DNS lookup and connection time to configured targets;
                                              Network_Test_Config.xml, off by default)
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
	Collected_At = 'Collected at'; Error = 'Error'; Yes = 'Yes'; No = 'No'; Not_Available = 'n/a'
	Not_Enrolled = 'Not enrolled / unknown'; No_WiFi = 'No Wi-Fi connection'
	Category_Health = 'Health status'; Health_IME = 'IME service'; Health_Defender = 'Microsoft Defender'
	Health_Compliance = 'Compliance'; Health_Applications = 'Company apps (Intune)'
	Health_Disk = 'Disk capacity'; Health_BitLocker = 'BitLocker'; Health_PendingReboot = 'Pending reboot'
	Health_Updates = 'Updates to install'; Health_Service = 'Service'
	Health_Custom = 'Custom check'; Health_Collection = 'Health collection'
	Health_OK = 'OK'; Health_Pending = 'Pending'; Health_Error = 'Error'; Health_Unknown = 'Unknown'
	Health_Unavailable = 'Local health report unavailable: {0}'
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

function ConvertTo-SelfXHealthInfo {
    param([object[]]$Results)
    foreach ($result in $Results) {
        $property = Get-SelfXInfoText "Health_$($result.Id)"
        if ($result.Name) { $property += " ($($result.Name))" }
        $detailText = Format-SelfXUserTimeText "$($result.Detail)"
        $value = (Get-SelfXInfoText "Health_$($result.Status)") + ' - ' + $detailText
        $item = New-SelfXInfoItem (Get-SelfXInfoText 'Category_Health') $property $value $result.Status
        $item | Add-Member -NotePropertyName Remediation -NotePropertyValue "$($result.Remediation)"
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

# Reads Network_Test_Config.xml. Entries that are not valid are skipped and named in Errors; a file that cannot
# be read switches the measurements off. Limits: up to MaxTargets targets, 1-5 samples, 200-5000 ms timeout.
function Read-SelfXNetworkTestConfig {
	param([Parameter(Mandatory = $true)][string]$Path, [int]$MaxTargets = 5)
	$errors = New-Object System.Collections.Generic.List[string]
	$targets = New-Object System.Collections.Generic.List[object]
	$result = [pscustomobject]@{ Enabled = $false; Gateway = $true; Samples = 3; TimeoutMs = 2000; Targets = @(); Errors = @() }
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
		if ($label -notmatch '^[A-Za-z0-9._ -]{1,40}\z') { $errors.Add("Target $count has no valid Label (letters, digits . _ - and space, up to 40)."); continue }
		if (-not (Test-SelfXNetworkHostName $name)) { $errors.Add("Target '$label' has no valid Host (DNS name or IPv4 address): skipped."); continue }
		$port = 0
		if ($portText) {
			if (-not ([int]::TryParse($portText, [ref]$port) -and $port -ge 1 -and $port -le 65535)) { $errors.Add("Target '$label' has no valid Port (1-65535): skipped."); continue }
		}
		if (@($targets | Where-Object { $_.Label -eq $label }).Count) { $errors.Add("Target '$label' is listed twice: the first entry is used."); continue }
		$targets.Add([pscustomobject]@{ Label = $label; Host = $name; Port = $port })
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

# Info items for the network measurements: default gateway (ping), per target the DNS lookup and, with a Port,
# the connection time. The whole run stops after DeadlineSeconds; targets not reached are shown as not measured.
function Get-SelfXNetworkMeasureItems {
	param(
		[string]$Category,
		$Config,
		[string[]]$Gateways = @(),
		[int]$DeadlineSeconds = 20
	)
	$items = New-Object System.Collections.Generic.List[object]
	if (-not $Config -or -not $Config.Enabled) { return $items.ToArray() }
	$deadline = [datetime]::UtcNow.AddSeconds($DeadlineSeconds)
	if ($Config.Gateway) {
		$gateway = @($Gateways | Where-Object { Test-SelfXIPv4Literal $_ } | Select-Object -First 1)
		if ($gateway.Count) {
			$info = ConvertTo-SelfXLatencyInfo (Measure-SelfXPingLatency -Address $gateway[0] -Samples $Config.Samples -TimeoutMs $Config.TimeoutMs -Deadline $deadline)
			$items.Add((New-SelfXInfoItem $Category (Get-SelfXInfoText 'Latency_Gateway') $info.Value $info.Status))
		}
	}
	foreach ($target in @($Config.Targets)) {
		$address = $target.Host
		$dnsSkipped = $false
		if (-not (Test-SelfXIPv4Literal $target.Host)) {
			$dns = Measure-SelfXDnsLatency -HostName $target.Host -Samples $Config.Samples -TimeoutMs $Config.TimeoutMs -Deadline $deadline
			$info = ConvertTo-SelfXLatencyInfo $dns
			$items.Add((New-SelfXInfoItem $Category (Get-SelfXInfoText 'Latency_Dns' $target.Label) ('{0}: {1}' -f $target.Host, $info.Value) $info.Status))
			$address = $dns.Address
			$dnsSkipped = ($dns.Skipped -and -not $dns.Stats.Sent)
		}
		if ($target.Port -gt 0) {
			if ($address) {
				$info = ConvertTo-SelfXLatencyInfo (Measure-SelfXTcpLatency -Address $address -Port $target.Port -Samples $Config.Samples -TimeoutMs $Config.TimeoutMs -Deadline $deadline)
			} elseif ($dnsSkipped) {
				$info = [pscustomobject]@{ Value = (Get-SelfXInfoText 'Latency_Skipped'); Status = '' }
			} else {
				$info = [pscustomobject]@{ Value = (Get-SelfXInfoText 'Latency_Failed' $Config.Samples $Config.Samples); Status = 'Error' }
			}
			$items.Add((New-SelfXInfoItem $Category (Get-SelfXInfoText 'Latency_Connection' $target.Label) ('{0}:{1}: {2}' -f $target.Host, $target.Port, $info.Value) $info.Status))
		}
	}
	return $items.ToArray()
}

# Collects all information and returns a list of Category/Property/Value objects.
function Get-SelfXSystemInfo {
	param(
		[string]$InternetTestHost = 'www.msftconnecttest.com',
		[int]$InternetTestPort = 80,
		[string]$NetworkTestConfigPath = '',
		[hashtable]$Text = @{},
		[switch]$IncludeHealth
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

	# CIM and registry sources; each one may fail on its own without stopping the report.
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

	# Windows
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
	$items.Add((New-SelfXInfoItem $catWindows (& $L 'Time_Zone') (Invoke-SelfXSafe { (Get-TimeZone).DisplayName })))

	# User and management
	$dsreg = Get-SelfXDsregStatus
	$upn = Invoke-SelfXSafe { & "$env:SystemRoot\System32\whoami.exe" /upn 2>$null }
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Current_User') "$env:USERDOMAIN\$env:USERNAME"))
	if ("$upn" -match '@') { $items.Add((New-SelfXInfoItem $catUser (& $L 'User_Principal_Name') "$upn".Trim())) }
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Domain') $cs.Domain))
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Entra_Joined') (& $dsregYesNo $dsreg['AzureAdJoined'])))
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Domain_Joined') (& $dsregYesNo $dsreg['DomainJoined'])))
	if ($dsreg['TenantName']) { $items.Add((New-SelfXInfoItem $catUser (& $L 'Tenant') $dsreg['TenantName'])) }
	if ($dsreg['DeviceId']) { $items.Add((New-SelfXInfoItem $catUser (& $L 'Entra_Device_Id') $dsreg['DeviceId'])) }
	$mdmUpn = Get-SelfXMdmEnrollmentUpn
	if ($mdmUpn) { $items.Add((New-SelfXInfoItem $catUser (& $L 'Intune_User') $mdmUpn)) }
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Intune_Last_Sync') (Get-SelfXIntuneLastSync)))

	# Network: connection types, VPN, internet test and addresses of all IP-enabled adapters
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
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'Internet_Reachable') (& $yesNo (Test-SelfXTcpConnection -HostName $InternetTestHost -Port $InternetTestPort))))

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
	$proxySettings = Invoke-SelfXSafe { Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop }
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'Proxy') (ConvertTo-SelfXProxyText $proxySettings)))
	$driveLetters = Invoke-SelfXSafe { @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [IO.DriveType]::Network } | ForEach-Object { $_.Name.TrimEnd('\') }) }
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'Network_Drives') (Get-SelfXNetworkDriveText $driveLetters)))
	# Optional latency measurements (only with an enabled Network_Test_Config.xml).
	if ($NetworkTestConfigPath -and (Test-Path -LiteralPath $NetworkTestConfigPath -PathType Leaf)) {
		$measureConfig = Invoke-SelfXSafe { Read-SelfXNetworkTestConfig -Path $NetworkTestConfigPath }
		foreach ($measureItem in @(Invoke-SelfXSafe { Get-SelfXNetworkMeasureItems -Category $catNetwork -Config $measureConfig -Gateways $gateways })) {
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

# Saves the items to Path. The format follows the file extension: .csv, .json, .html, anything else = text.
function Export-SelfXSystemInfo {
	param(
		[object[]]$Items,
		[string]$Path,
		[string]$Title = 'System information'
	)
	switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
		'.csv'  { $Items | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 }
		'.json' { $Items | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8 }
		'.html' {
			$Items | ConvertTo-Html -Title "$Title - $env:COMPUTERNAME" -PreContent ("<h2>{0} - {1}</h2>" -f [System.Net.WebUtility]::HtmlEncode($Title), $env:COMPUTERNAME) |
				Set-Content -Path $Path -Encoding UTF8
		}
		default { ConvertTo-SelfXSystemInfoText -Items $Items | Set-Content -Path $Path -Encoding UTF8 }
	}
}
