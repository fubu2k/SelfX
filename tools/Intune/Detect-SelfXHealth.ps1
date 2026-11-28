<#
.SYNOPSIS
    Intune Remediations detection script: reports the SelfX device status of a Windows 11 device in one line.

.DESCRIPTION
    Upload this file as the detection script of a script package in Intune (Devices > Scripts and remediations). No remediation
    script is needed. Settings: Run this script using the logged-on credentials = No (SYSTEM), Run script in 64-bit PowerShell = Yes,
    Enforce script signature check = No (Yes only when the file is signed). Windows 11 only: Intune does not manage Windows Server.

    The script reads the status cache of the SelfX service, %ProgramData%\SelfX\Cache\Health.json, and changes nothing. The cache is
    used only when
      - Windows is Windows 11 (product type workstation) and SelfX is installed (%ProgramFiles%\SelfX\Config exists),
      - neither %ProgramData%\SelfX, the folder Cache nor the file is a link,
      - the file is owned by SYSTEM (S-1-5-18) or the Administrators group (S-1-5-32-544), checked by SID,
      - the file has 1 to 60000 bytes and is valid JSON with the rows of HealthStatus.ps1,
      - the file is younger than two intervals of the background checks (IntervalMinutes of Background in
        %ProgramFiles%\SelfX\Config\Health_Config.xml, 5-1440, default 15; the file is read without DTD).
    The cache is opened once (others can read it, but not change, rename or delete it while it is open); owner, age and content are
    taken while it stays open.

    Output: exactly one line of at most 2000 characters (Intune keeps at most 2048), for example
      SelfX Error | IME=OK; Defender=OK; Compliance=Pending; Applications=Error; Disk=OK | FailedApps=<app id>:0x87D1041C
    Per check type the worst status of its rows (Error, Pending, Unknown, OK), then at most 20 failed apps with their error code
    (Stalled for a download that has not moved, - without a valid code). Only check types, status values, app IDs and error codes are
    written: no names, no detail texts, no user names, no paths. The line has no time, so it only changes when the status changes.
    Exit code 1: a row is Error, or the status cache cannot be used (the line says why: SelfX Unavailable | ...). Otherwise 0.

.NOTES
    Name    : Detect-SelfXHealth.ps1
    Package : tools (uploaded to Intune by the administrator; not part of the SelfX package)
    Context : SYSTEM (Intune Management Extension, Windows PowerShell 5.1), Windows 11 only
    Version : 3.1.0
    Plain ASCII, so Intune reads it as UTF-8 also with an enforced signature check (no byte order mark). Dot-sourcing the file only
    defines the functions (tools\Test-SelfXHealthDetection.ps1 tests them).

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-28  fubu2k               Initial version
#>

$script:SelfXDetectMaxLength = 2000
$script:SelfXDetectMaxCacheBytes = 60000
$script:SelfXDetectMaxApps = 20
$script:SelfXDetectTrustedOwners = @('S-1-5-18', 'S-1-5-32-544')
# The check types of HealthStatus.ps1 in a fixed order; other types follow sorted by name.
$script:SelfXDetectTypes = @('Collection', 'IME', 'Defender', 'Compliance', 'Applications', 'Disk', 'BitLocker', 'PendingReboot', 'Updates', 'Service', 'Custom')
$script:SelfXDetectStatus = @('OK', 'Unknown', 'Pending', 'Error')

function Get-SelfXDetectProductType {
    # ProductType of Windows: WinNT = workstation (Windows 11), ServerNT and LanmanNT = Windows Server. Tests replace this function.
    return "$((Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -Name ProductType -ErrorAction Stop).ProductType)"
}

function Get-SelfXDetectOwnerSid {
    # Owner of a file as SID (never as a name: names are localized). Tests replace this function.
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value
}

function Get-SelfXDetectRoots {
    # %ProgramData%\SelfX and %ProgramFiles%\SelfX (the 64-bit folder also from a 32-bit PowerShell).
    $programFiles = $env:ProgramW6432
    if (-not $programFiles) { $programFiles = [Environment]::GetFolderPath('ProgramFiles') }
    return [pscustomobject]@{
        Data    = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SelfX'
        Install = Join-Path $programFiles 'SelfX'
    }
}

function Test-SelfXDetectLink {
    # True when the path is a link (junction or symbolic link).
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-SelfXDetectInterval {
    # IntervalMinutes of <Background> in Health_Config.xml (5-1440, default 15), like the service. The file is read without DTD; a file
    # that cannot be read throws (the caller reports it).
    param([Parameter(Mandatory = $true)][string]$ConfigFile)
    $interval = 15
    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) { return $interval }
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($ConfigFile, $settings)
    try { $document.Load($reader) } finally { $reader.Dispose() }
    $node = $document.SelectSingleNode('/HealthConfig/Background')
    $value = 0
    if ($node -and [int]::TryParse($node.GetAttribute('IntervalMinutes'), [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -and $value -ge 5 -and $value -le 1440) {
        $interval = $value
    }
    return $interval
}

function New-SelfXDetectResult {
    param([Parameter(Mandatory = $true)][string]$Line, [Parameter(Mandatory = $true)][int]$ExitCode)
    if ($Line.Length -gt $script:SelfXDetectMaxLength) { $Line = $Line.Substring(0, $script:SelfXDetectMaxLength) }
    return [pscustomobject]@{ Line = $Line; ExitCode = $ExitCode }
}

function Get-SelfXDetectProblem {
    # The result for a status cache that cannot be used: a fixed text, exit code 1.
    param([Parameter(Mandatory = $true)][string]$Reason)
    return (New-SelfXDetectResult -Line "SelfX Unavailable | $Reason" -ExitCode 1)
}

function Get-SelfXDetectRank {
    param([string]$Status)
    $rank = [Array]::IndexOf($script:SelfXDetectStatus, $Status)
    # Any other value counts as Unknown.
    if ($rank -lt 0) { $rank = 1 }
    return $rank
}

function Format-SelfXHealthLine {
    # One line from the rows of the cache. Reads only Id, Status and Apps (Id, Problem, Code) of each row; never Name or Detail.
    param([object[]]$Rows)
    $worst = @{}
    $apps = New-Object System.Collections.Generic.List[string]
    $more = 0
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $id = "$($row.Id)"
        if ($id -cnotmatch '^[A-Za-z]{1,32}\z') { continue }
        $rank = Get-SelfXDetectRank -Status "$($row.Status)"
        # The placeholder row of a failed collection is an error.
        if ($id -eq 'Collection') { $rank = 3 }
        if (-not $worst.ContainsKey($id) -or $rank -gt $worst[$id]) { $worst[$id] = $rank }
        if ($id -ne 'Applications' -or $null -eq $row.PSObject.Properties['Apps']) { continue }
        foreach ($app in @($row.Apps)) {
            if ($null -eq $app) { continue }
            $appId = "$($app.Id)"
            if ($appId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z') { continue }
            $problem = "$($app.Problem)"
            if ($problem -ceq 'Stalled') { $value = 'Stalled' }
            elseif ($problem -ceq 'Failed') {
                $code = "$($app.Code)"
                if ($code -match '^0x[0-9a-fA-F]{8}\z') { $value = '0x' + $code.Substring(2).ToUpperInvariant() } else { $value = '-' }
            } else { continue }
            $text = $appId.ToLowerInvariant() + ':' + $value
            if ($apps.Contains($text)) { continue }
            if ($apps.Count -ge $script:SelfXDetectMaxApps) { $more++; continue }
            $apps.Add($text)
        }
    }
    if ($worst.Count -eq 0) { return (Get-SelfXDetectProblem -Reason 'status cache has no results') }
    $order = @($script:SelfXDetectTypes | Where-Object { $worst.ContainsKey($_) }) + @($worst.Keys | Where-Object { $script:SelfXDetectTypes -notcontains $_ } | Sort-Object)
    $overall = 0
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($type in $order) {
        if ($worst[$type] -gt $overall) { $overall = $worst[$type] }
        $parts.Add("$type=$($script:SelfXDetectStatus[$worst[$type]])")
    }
    $line = "SelfX $($script:SelfXDetectStatus[$overall]) | " + ($parts -join '; ')
    if ($apps.Count) {
        # Apps are added while the line stays within the limit; the rest is counted.
        $appText = ' | FailedApps='
        $taken = 0
        foreach ($app in $apps) {
            $next = $(if ($taken) { ', ' } else { '' }) + $app
            if (($line.Length + $appText.Length + $next.Length + 16) -gt $script:SelfXDetectMaxLength) { break }
            $appText += $next
            $taken++
        }
        $more += ($apps.Count - $taken)
        if ($more -gt 0) { $appText += $(if ($taken) { " (+$more more)" } else { "(+$more more)" }) }
        $line += $appText
    }
    $exitCode = $(if ($overall -eq 3) { 1 } else { 0 })
    return (New-SelfXDetectResult -Line $line -ExitCode $exitCode)
}

function Read-SelfXHealthCache {
    # Opens the cache once and returns the result (line and exit code). DataRoot = %ProgramData%\SelfX, Now = time in UTC.
    param([Parameter(Mandatory = $true)][string]$DataRoot, [Parameter(Mandatory = $true)][int]$IntervalMinutes, [Parameter(Mandatory = $true)][datetime]$Now)
    $cacheFolder = Join-Path $DataRoot 'Cache'
    $cacheFile = Join-Path $cacheFolder 'Health.json'
    if (-not (Test-Path -LiteralPath $cacheFile -PathType Leaf)) { return (Get-SelfXDetectProblem -Reason 'status cache missing') }
    foreach ($path in @($DataRoot, $cacheFolder, $cacheFile)) {
        if (Test-SelfXDetectLink -Path $path) { return (Get-SelfXDetectProblem -Reason 'status cache is behind a link') }
    }
    $stream = [IO.File]::Open($cacheFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        # The file stays open: it cannot be replaced while owner, time and content are read.
        if ($script:SelfXDetectTrustedOwners -notcontains (Get-SelfXDetectOwnerSid -Path $cacheFile)) { return (Get-SelfXDetectProblem -Reason 'status cache has an untrusted owner') }
        $length = $stream.Length
        if ($length -le 0 -or $length -gt $script:SelfXDetectMaxCacheBytes) { return (Get-SelfXDetectProblem -Reason "status cache is empty or larger than $($script:SelfXDetectMaxCacheBytes) bytes") }
        $written = [IO.File]::GetLastWriteTimeUtc($cacheFile)
        $maxAge = 2 * $IntervalMinutes
        $age = ($Now.ToUniversalTime() - $written).TotalMinutes
        if ($age -gt $maxAge) { return (Get-SelfXDetectProblem -Reason "status cache is older than $maxAge minutes (two intervals of the background checks)") }
        # A time far in the future is not trusted either (5 minutes allow for a clock correction).
        if ($age -lt -5) { return (Get-SelfXDetectProblem -Reason 'status cache has a time in the future') }
        $bytes = New-Object byte[] $length
        $read = 0
        while ($read -lt $length) {
            $count = $stream.Read($bytes, $read, $length - $read)
            if ($count -le 0) { break }
            $read += $count
        }
        if ($read -ne $length) { return (Get-SelfXDetectProblem -Reason 'status cache could not be read completely') }
    } finally { $stream.Dispose() }
    try {
        $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
        # Windows PowerShell 5.1 returns a JSON array as one object; assigning it first unrolls the items.
        $parsed = ConvertFrom-Json -InputObject $text -ErrorAction Stop
        $rows = @($parsed)
    } catch { return (Get-SelfXDetectProblem -Reason 'status cache is not valid JSON') }
    return (Format-SelfXHealthLine -Rows $rows)
}

function Invoke-SelfXHealthDetection {
    # The whole detection: Windows 11, installation, interval, cache. Returns an object with Line and ExitCode.
    param([Parameter(Mandatory = $true)][string]$DataRoot, [Parameter(Mandatory = $true)][string]$InstallRoot, [datetime]$Now = [datetime]::UtcNow)
    if ((Get-SelfXDetectProductType) -ne 'WinNT') { return (Get-SelfXDetectProblem -Reason 'Windows 11 only') }
    $configFolder = Join-Path $InstallRoot 'Config'
    if (-not (Test-Path -LiteralPath $configFolder -PathType Container)) { return (Get-SelfXDetectProblem -Reason 'SelfX is not installed') }
    try { $interval = Get-SelfXDetectInterval -ConfigFile (Join-Path $configFolder 'Health_Config.xml') }
    catch { return (Get-SelfXDetectProblem -Reason 'Health_Config.xml cannot be read') }
    return (Read-SelfXHealthCache -DataRoot $DataRoot -IntervalMinutes $interval -Now $Now)
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    try {
        $roots = Get-SelfXDetectRoots
        $result = Invoke-SelfXHealthDetection -DataRoot $roots.Data -InstallRoot $roots.Install
    } catch {
        # Fail closed with a fixed text: the message of the exception could name a path.
        $result = Get-SelfXDetectProblem -Reason "detection failed ($($_.Exception.GetType().Name))"
    }
    Write-Output $result.Line
    exit $result.ExitCode
}
