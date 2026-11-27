<#
.SYNOPSIS
    Collect bounded local device health results for SelfX Service.
.DESCRIPTION
    Runs as SYSTEM only when the service receives the fixed HEALTH request. Reads services,
    Defender, BitLocker, disks, pending-reboot markers, the offline Windows Update Agent
    cache and the Intune Win32 app reporting cache. Missing sources are
    Unknown, not OK. Intune cloud compliance cannot be inferred offline; an administrator can
    supply a compliance check. Optional scripts run from the protected HealthChecks folder: a script of the
    project from App\HealthChecks, an own script of the company from Config\HealthChecks only when it is listed
    in Config\SelfX.Config.json with its current SHA256 (Resolve-SelfXScriptPath in SelfXPaths.ps1).
    Health_Config.xml is read from the configuration folder (Config next to App).
    Dot-sourcing defines functions only. -Collect writes a single compact JSON response.
    -CacheFile (set by the service) also stores the result for the background status cache:
    a full collection replaces the file, a single check replaces only its own rows.
.NOTES
    Version: 3.1.0
    History:
    2.3.0  2026-10-28  Wolfgang Baeck  Initial local health checks and extension contract.
    2.8.2  2026-11-23  fubu2k          Security: the WinRT libraries are checked against SelfX.Files.json when they are loaded
                                       (SelfXWinRT.ps1); a difference = no orchestrator information.
    3.1.0  2026-11-27  fubu2k          Health_Config.xml from the configuration folder; own health scripts of the company only from
                                       Config\HealthChecks with an entry in SelfX.Config.json (SelfXPaths.ps1)
#>
    param([switch]$Collect, [string]$OnlyId = '', [string]$OnlyName = '', [string]$CacheFile = '')

    function New-SelfXHealthResult {
        # Pending is a warning (action outstanding, e.g. updates to install), not an error.
        param([string]$Id, [ValidateSet('OK','Pending','Error','Unknown')][string]$Status,
        [string]$Detail, [string]$Name = '')
    [pscustomobject]@{
        Id = $Id; Name = $Name; Status = $Status
        Detail = $Detail.Substring(0, [Math]::Min(600, $Detail.Length))
        CheckedAt = [datetime]::UtcNow.ToString('o')
    }
}

function Format-SelfXHealthTime {
    # Times in detail texts are written as UTC markers; the GUI (SystemInfo.ps1) shows them in the
    # time zone of the user. Unspecified kinds must be passed as UTC by the caller.
    param([datetime]$Time)
    if ($Time.Kind -eq [DateTimeKind]::Local) { $Time = $Time.ToUniversalTime() }
    '{utc:' + $Time.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) + '}'
}

function Get-SelfXServiceHealth {
    param([string]$Name, [string]$Expected = 'Running', [string]$Id = 'Service')
    try {
        $service = Get-Service -Name $Name -ErrorAction Stop
        $status = if ("$($service.Status)" -eq $Expected) { 'OK' } else { 'Error' }
        New-SelfXHealthResult $Id $status "$Name : $($service.Status) (expected $Expected)" $Name
    } catch { New-SelfXHealthResult $Id Error $_.Exception.Message $Name }
}

function Get-SelfXDiskHealth {
    param([double]$UsedPercentError, [double]$MinimumFreeGB)
    try {
        $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)
        if (-not $disks.Count) { throw 'No fixed disks were returned.' }
        foreach ($disk in $disks) {
            if ($disk.Size -le 0 -or $null -eq $disk.FreeSpace) {
                New-SelfXHealthResult Disk Unknown "Cannot read capacity: $($disk.DeviceID)" $disk.DeviceID
                continue
            }
            $used = 100 * (1 - $disk.FreeSpace / $disk.Size)
            $free = $disk.FreeSpace / 1GB
            $status = if ($used -ge $UsedPercentError -or $free -lt $MinimumFreeGB) { 'Error' } else { 'OK' }
            New-SelfXHealthResult Disk $status ('{0}: {1:N1}% used; {2:N1} GB free' -f $disk.DeviceID, $used, $free) $disk.DeviceID
        }
    } catch { New-SelfXHealthResult Disk Unknown $_.Exception.Message }
}

# Paths of the configuration (Health_Config.xml) and of the health scripts (App\HealthChecks, Config\HealthChecks).
. (Join-Path $PSScriptRoot 'SelfXPaths.ps1')

# Defender status through CIM (SelfXDefender.ps1, no Defender module).
. (Join-Path $PSScriptRoot 'SelfXDefender.ps1')

function Get-SelfXDefenderHealth {
    try {
        $mp = Get-SelfXDefenderStatus
        if ($null -eq $mp -or $null -eq $mp.AMServiceEnabled -or $null -eq $mp.AntivirusEnabled -or
            $null -eq $mp.RealTimeProtectionEnabled -or $null -eq $mp.AntivirusSignatureAge -or
            $null -eq $mp.DefenderSignaturesOutOfDate) {
            throw 'Defender did not return the required health properties.'
        }
        $healthy = $mp.AMServiceEnabled -and $mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled -and
            -not $mp.DefenderSignaturesOutOfDate -and $mp.AntivirusSignatureAge -le 7
        $status = if ($healthy) { 'OK' } else { 'Error' }
        $updated = 'unknown'
        if ($mp.AntivirusSignatureLastUpdated -is [datetime]) { $updated = Format-SelfXHealthTime $mp.AntivirusSignatureLastUpdated }
        New-SelfXHealthResult Defender $status ("Signature version {0}; last update {1}; Product={2}; Engine={3}; Service={4}; Antivirus={5}; RealTime={6}; SignatureAgeDays={7}; Mode={8}" -f
            $mp.AntivirusSignatureVersion, $updated, $mp.AMProductVersion, $mp.AMEngineVersion,
            $mp.AMServiceEnabled, $mp.AntivirusEnabled, $mp.RealTimeProtectionEnabled, $mp.AntivirusSignatureAge, $mp.AMRunningMode)
    } catch { New-SelfXHealthResult Defender Unknown $_.Exception.Message }
}

# BitLocker status through CIM (SelfXDeviceSecurity.ps1, no BitLocker module).
. (Join-Path $PSScriptRoot 'SelfXDeviceSecurity.ps1')

function Get-SelfXBitLockerHealth {
    try {
        $volumes = @(Get-SelfXBitLockerVolumes)
        $volumes = @($volumes | Where-Object { "$($_.VolumeType)" -in @('OperatingSystem','FixedData') })
        if (-not $volumes.Count) { throw 'No fixed BitLocker volumes were returned.' }
        foreach ($volume in $volumes) {
            if ($null -eq $volume.ProtectionStatus -or $null -eq $volume.VolumeStatus) {
                New-SelfXHealthResult BitLocker Unknown 'Required BitLocker status properties are missing.' $volume.MountPoint
                continue
            }
            $status = if ("$($volume.ProtectionStatus)" -eq 'On' -and "$($volume.VolumeStatus)" -eq 'FullyEncrypted') { 'OK' } else { 'Error' }
            New-SelfXHealthResult BitLocker $status ("{0}: Protection={1}; Encryption={2}" -f
                $volume.MountPoint, $volume.ProtectionStatus, $volume.VolumeStatus) $volume.MountPoint
        }
    } catch { New-SelfXHealthResult BitLocker Unknown $_.Exception.Message }
}

# Check and load of the WinRT libraries for the orchestrator (SelfXWinRT.ps1).
. (Join-Path $PSScriptRoot 'SelfXWinRT.ps1')

# Windows Update Agent: ISystemInformation.RebootRequired (documented, readable without administrator rights).
function Get-SelfXWuaRebootRequired {
    return [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired
}

# Windows Update orchestrator (Windows 11 24H2+, what Settings > Windows Update shows): titles of the updates
# that are installed and wait for the restart (AttentionRequiredReason ReadyToReboot).
function New-SelfXOrchestratorManager {
    # PowerShell 7 cannot load the Windows Runtime type by name: it uses SelfXWinRT.dll from the folder WinRT of the
    # install folder. Import-SelfXWinRT (SelfXWinRT.ps1) checks the DLLs against SelfX.Code.json and keeps them open
    # while it loads them; any difference throws and nothing is loaded. Throws when the API is not available.
    param([string]$ClientId)
    Import-SelfXWinRT -InstallFolder $PSScriptRoot
    return [SelfX.SelfXWinRT]::CreateUpdateManager($ClientId)
}

function Get-SelfXOrchestratorRebootTitles {
    try { $manager = New-SelfXOrchestratorManager 'SelfX.Health' } catch { return @() }
    @(foreach ($update in @($manager.GetApplicableUpdates())) {
        if ($update -and $update.AttentionRequiredInfo -and "$($update.AttentionRequiredInfo.Reason)" -eq 'ReadyToReboot') { "$($update.Title)" }
    })
}

function Get-SelfXPendingRebootMarkers {
    # Read-only registry markers. PendingFileRenameOperations is ignored on purpose: many
    # installers and security products set it permanently, which would cause false errors.
    $markers = @()
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $markers += 'Component Based Servicing'
    }
    # Updates installed by the orchestrator (Windows 11 24H2+) do not always set this key: the documented
    # Windows Update APIs below are asked as well. They only add markers; failing APIs do not hide the registry.
    $wuaReboot = $false
    try { $wuaReboot = Get-SelfXWuaRebootRequired } catch { }
    $waiting = @()
    try { $waiting = @(Get-SelfXOrchestratorRebootTitles | Where-Object { $_ }) } catch { }
    if ($waiting.Count) { $markers += 'Windows Update (' + ($waiting -join ', ') + ')' }
    elseif ($wuaReboot -or (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        $markers += 'Windows Update'
    }
    $names = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName'
    $active = (Get-ItemProperty -LiteralPath "$names\ActiveComputerName" -Name ComputerName -ErrorAction Stop).ComputerName
    $pending = (Get-ItemProperty -LiteralPath "$names\ComputerName" -Name ComputerName -ErrorAction Stop).ComputerName
    if (-not $active -or -not $pending) { throw 'Computer name registry values are missing.' }
    if ($active -ne $pending) { $markers += 'Computer rename' }
    $markers
}

# Read-only times that tell how long a restart has been waiting: the last restart (CIM) and the last successful
# Windows update installation (IAutomaticUpdatesResults, UTC with an unspecified kind). Either one may be missing.
function Get-SelfXRestartTimes {
    $boot = $null
    $install = $null
    try { $boot = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime } catch { }
    try { $install = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results.LastInstallationSuccessDate } catch { }
    [pscustomobject]@{ LastBoot = $boot; LastInstall = $install }
}

function Get-SelfXPendingRebootTimeText {
    # " Last restart {utc}; last update installed {utc}." The installation time is only named when it is after the
    # last restart (otherwise it cannot be the update that waits). Failing sources only shorten the text.
    try { $times = Get-SelfXRestartTimes } catch { return '' }
    $parts = @()
    $boot = $times.LastBoot
    if ($boot -is [datetime] -and $boot.Year -gt 2000) {
        if ($boot.Kind -eq [DateTimeKind]::Unspecified) { $boot = [datetime]::SpecifyKind($boot, [DateTimeKind]::Utc) }
        $parts += 'Last restart ' + (Format-SelfXHealthTime $boot)
        $install = $times.LastInstall
        if ($install -is [datetime] -and $install.Year -gt 2000) {
            $install = [datetime]::SpecifyKind($install, [DateTimeKind]::Utc)
            if ($install -gt $boot.ToUniversalTime()) { $parts += 'last update installed ' + (Format-SelfXHealthTime $install) }
        }
    }
    if ($parts.Count) { return ' ' + ($parts -join '; ') + '.' }
    return ''
}

function Get-SelfXPendingRebootHealth {
    try {
        $markers = @(Get-SelfXPendingRebootMarkers)
        if ($markers.Count) { New-SelfXHealthResult PendingReboot Error ('Restart required: ' + ($markers -join ', ') + '.' + (Get-SelfXPendingRebootTimeText)) }
        else { New-SelfXHealthResult PendingReboot OK 'No restart pending.' }
    } catch { New-SelfXHealthResult PendingReboot Unknown $_.Exception.Message }
}

function Get-SelfXUpdateSearchResult {
    # Searches only the local Windows Update Agent cache (Online = false): no network scan,
    # no download and no installation. ConfigMgr deployments are not part of this cache view.
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searcher.Online = $false
    $result = $searcher.Search('IsInstalled=0 and IsHidden=0')
    # OperationResultCode: 2 = Succeeded, 3 = SucceededWithErrors.
    if ($result.ResultCode -notin @(2, 3)) { throw "Windows Update search result code $($result.ResultCode)." }
    $titles = @(foreach ($update in $result.Updates) { if (-not $update.BrowseOnly) { "$($update.Title)" } })
    $lastSearch = $null
    try { $lastSearch = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results.LastSearchSuccessDate } catch { $lastSearch = $null }
    [pscustomobject]@{ Titles = $titles; LastSearch = $lastSearch }
}

function Get-SelfXUpdateHealth {
    param([int]$MaxSearchAgeDays = 14)
    try {
        $search = Get-SelfXUpdateSearchResult
        $titles = @($search.Titles | Where-Object { $_ })
        # Installed by the orchestrator and only waiting for the restart: shown on the "Restart pending" row.
        $restart = @()
        try { $restart = @(Get-SelfXOrchestratorRebootTitles | Where-Object { $_ }) } catch { }
        $titles = @($titles | Where-Object { $restart -notcontains $_ })
        $restartText = ''
        if ($restart.Count) { $restartText = " $($restart.Count) installed update(s) wait for the restart." }
        $last = $search.LastSearch
        $lastText = 'unknown'
        $stale = $true
        if ($last -is [datetime] -and $last.Year -gt 2000) {
            # IAutomaticUpdatesResults.LastSearchSuccessDate is UTC (returned with an unspecified kind).
            if ($last.Kind -ne [DateTimeKind]::Local) { $last = [datetime]::SpecifyKind($last, [DateTimeKind]::Utc) }
            $lastText = Format-SelfXHealthTime $last
            $stale = ([datetime]::UtcNow - $last.ToUniversalTime()).TotalDays -gt $MaxSearchAgeDays
        }
        if ($titles.Count) {
            New-SelfXHealthResult Updates Pending (("{0} update(s) to install (last scan {1}): {2}" -f $titles.Count, $lastText, ($titles -join '; ')) + $restartText)
        } elseif ($stale -and -not $restart.Count) {
            # An empty cache that is old or was never filled does not prove the device is current.
            New-SelfXHealthResult Updates Unknown "No pending updates in the local cache, but the last successful scan ($lastText) is older than $MaxSearchAgeDays day(s) or unknown."
        } else {
            New-SelfXHealthResult Updates OK ("No updates to install (last scan $lastText)." + $restartText)
        }
    } catch { New-SelfXHealthResult Updates Unknown $_.Exception.Message }
}

function Get-SelfXAppReports {
    # This is an implementation-specific IME cache, not an installed-software inventory or live Intune query.
    # Layout: Win32Apps\<user object id>\<app id>_<revision> (older layouts: ...\<app id>\...). The app is the
    # last key segment that is a GUID (optionally with _<revision>); the user segment before it is never used.
    $root = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($key in (Get-ChildItem -LiteralPath $root -Recurse -ErrorAction Stop)) {
        $values = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
        $message = $values.EnforcementStateMessage
        if (-not $message) { continue }
        $report = ConvertFrom-Json -InputObject $message -ErrorAction Stop
        $segments = @($key.Name -split '\\')
        $index = -1
        $id = ''
        for ($i = $segments.Count - 1; $i -ge 0; $i--) {
            if ($segments[$i] -match '^([0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})(_\d+)?$') { $id = $Matches[1]; $index = $i; break }
        }
        if ($index -lt 1) { throw "Cannot identify app in $($key.Name)" }
        $name = $values.DisplayName
        if (-not $name) { $name = $report.ApplicationName }
        [pscustomobject]@{
            Id = $id; Name = "$name"; State = $report.EnforcementState; ErrorCode = $report.ErrorCode
            AppKey = 'Registry::' + ($segments[0..$index] -join '\'); UserKey = 'Registry::' + ($segments[0..($index - 1)] -join '\')
        }
    }
}

function Get-SelfXImeAppNames {
    # The IME registry cache contains no app names; the app policies in the IME logs do ("Id":"..","Name":"..").
    # Only the newest logs are read, only for the requested IDs. Returns a hashtable id (lower case) -> name.
    param([string[]]$Ids, [string]$LogFolder = (Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'))
    $names = @{}
    $wanted = @($Ids | Where-Object { $_ } | ForEach-Object { "$_".ToLowerInvariant() } | Sort-Object -Unique)
    if (-not $wanted.Count -or -not (Test-Path -LiteralPath $LogFolder)) { return $names }
    $files = @(Get-ChildItem -LiteralPath $LogFolder -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'AppWorkload*.log' -or $_.Name -like 'IntuneManagementExtension*.log' } |
        Where-Object { $_.Length -lt 50MB } | Sort-Object LastWriteTime -Descending | Select-Object -First 4)
    foreach ($file in $files) {
        try {
            # The IME keeps its log open: read with shared access.
            $stream = [IO.FileStream]::new($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { $text = (New-Object IO.StreamReader($stream)).ReadToEnd() } finally { $stream.Dispose() }
        } catch { continue }
        foreach ($match in [regex]::Matches($text, '"Id":"([0-9a-fA-F-]{36})","Name":"((?:[^"\\]|\\.)*)"')) {
            $id = $match.Groups[1].Value.ToLowerInvariant()
            if ($wanted -contains $id -and -not $names.ContainsKey($id)) {
                try { $names[$id] = [regex]::Unescape($match.Groups[2].Value) } catch { $names[$id] = $match.Groups[2].Value }
            }
        }
        if ($names.Count -ge $wanted.Count) { break }
    }
    return $names
}

function Format-SelfXAppError {
    # Intune error codes are stored as signed 32-bit numbers (for example -2016345060 = 0x87D1041C).
    param($Code)
    $value = 0L
    if ($null -eq $Code -or -not [long]::TryParse("$Code", [ref]$value) -or $value -eq 0) { return '' }
    if ($value -lt 0) { $value += 4294967296L }
    return ('0x{0:X8}' -f $value)
}

function Get-SelfXApplicationHealth {
    param([System.Xml.XmlElement]$Configuration, [string]$Root = $PSScriptRoot)
    try {
        $reports = @(Get-SelfXAppReports)
        # Names from Health_Config (Application Id/Name), otherwise from the cache, otherwise from the IME logs.
        $configured = @($Configuration.SelectNodes('Application') | ForEach-Object { $_.GetAttribute('Id') } | Where-Object { $_ })
        $missing = @(foreach ($report in $reports) { if (-not $report.Name -and $configured -notcontains $report.Id) { $report.Id } })
        $logNames = @{}
        if ($missing.Count) { $logNames = Get-SelfXImeAppNames -Ids $missing }
        $included = @()
        foreach ($report in $reports) {
            $name = $report.Name
            $mapping = @($Configuration.SelectNodes('Application') | Where-Object { $_.GetAttribute('Id') -eq $report.Id })
            if ($mapping.Count) { $name = $mapping[0].GetAttribute('Name') }
            if (-not $name -and $logNames.ContainsKey("$($report.Id)".ToLowerInvariant())) { $name = $logNames["$($report.Id)".ToLowerInvariant()] }
            if (-not $name) { $name = $report.Id }
            $excluded = $false
            foreach ($entry in $Configuration.SelectNodes('Exclude')) {
                if ($name -like $entry.GetAttribute('Name') -or $report.Id -like $entry.GetAttribute('Name')) { $excluded = $true }
            }
            if ($excluded) { continue }
            $state = 0
            if (-not [int]::TryParse("$($report.State)", [ref]$state)) { $state = 0 }
            # 3000-3999: the app does not apply to this device (requirements not met); it is not counted.
            if ($state -ge 3000 -and $state -lt 4000) { continue }
            # Only known success is OK. In-progress, absent and unsupported cache states remain Unknown.
            $status = if ($state -eq 1000) { 'OK' } elseif ($state -ge 5000 -and $state -lt 6000) { 'Error' } else { 'Unknown' }
            $code = Format-SelfXAppError $report.ErrorCode
            $included += [pscustomobject]@{ Name = $name; Status = $status; State = $(if ($code) { "error $code" } else { "state $state" }) }
        }
        foreach ($app in $Configuration.SelectNodes('Application[@Script]')) {
            $excluded = $false
            foreach ($entry in $Configuration.SelectNodes('Exclude')) {
                if ($app.GetAttribute('Name') -like $entry.GetAttribute('Name') -or
                    ($app.GetAttribute('Id') -and $app.GetAttribute('Id') -like $entry.GetAttribute('Name'))) { $excluded = $true }
            }
            if ($excluded) { continue }
            $check = Get-SelfXCustomHealth -Check $app -Root $Root -Id Applications
            $included += [pscustomobject]@{ Name = $check.Name; Status = $check.Status; State = $check.Detail }
        }
        $errors = @($included | Where-Object Status -eq 'Error')
        $unknown = @($included | Where-Object Status -eq 'Unknown')
        $status = if ($errors.Count) { 'Error' } elseif (-not $included.Count -or $unknown.Count) { 'Unknown' } else { 'OK' }
        if (-not $included.Count) {
            $detail = 'No Intune app results in the local cache yet.'
        } elseif (-not $errors.Count -and -not $unknown.Count) {
            $detail = "All $($included.Count) app(s) installed."
        } else {
            $parts = @()
            if ($errors.Count) { $parts += "$($errors.Count) of $($included.Count) app(s) could not be installed: " + (($errors | ForEach-Object { "$($_.Name) ($($_.State))" }) -join '; ') + '.' }
            if ($unknown.Count) { $parts += "$($unknown.Count) app(s) not installed yet or status unknown: " + (($unknown | ForEach-Object { "$($_.Name) ($($_.State))" }) -join '; ') + '.' }
            $detail = $parts -join ' '
        }
        New-SelfXHealthResult Applications $status $detail
    } catch { New-SelfXHealthResult Applications Unknown $_.Exception.Message }
}

function Invoke-SelfXHealthScript {
    param([string]$Path, [int]$TimeoutSeconds)
    # Same PowerShell 7 (fixed machine-wide path) that the service uses for this script.
    $exe = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'PowerShell 7 is not installed (expected: %ProgramFiles%\PowerShell\7\pwsh.exe).' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Path`""
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = [IO.Path]::GetDirectoryName($Path)
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        # Custom output must not corrupt the collector's JSON or block a full pipe: both streams are
        # drained asynchronously; only the last stdout line is used as detail text.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        [void]$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Health check timeout; failed to terminate process $($process.Id)." }
            throw "Health check exceeded $TimeoutSeconds seconds."
        }
        $output = ''
        if ($stdout.Wait(5000)) { $output = $stdout.Result }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
    } finally { $process.Dispose() }
}

function Get-SelfXHealthScriptText {
    # Last non-empty stdout line of a health script, without control characters, at most 400 characters.
    param([string]$Output)
    $line = @("$Output" -split "`r?`n" | ForEach-Object { ($_ -replace '[\x00-\x1F\x7F]', ' ').Trim() } | Where-Object { $_ }) | Select-Object -Last 1
    if (-not $line) { return '' }
    return $line.Substring(0, [Math]::Min(400, $line.Length))
}

function Get-SelfXCustomHealth {
    # FailStatus is the status for a non-zero exit code (Compliance uses Pending as a warning).
    param([System.Xml.XmlElement]$Check, [string]$Root, [string]$Id = 'Custom',
        [ValidateSet('Error','Pending')][string]$FailStatus = 'Error')
    $name = $Check.GetAttribute('Name')
    try {
        $file = $Check.GetAttribute('Script')
        if ($file -notmatch '^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,90}\.ps1$' -or $file.Contains('..')) { throw 'Invalid health script filename.' }
        # The script of the project (App\HealthChecks) wins; an own script (Config\HealthChecks) needs its entry in SelfX.Config.json.
        $path = Resolve-SelfXScriptPath -Folder 'HealthChecks' -FileName $file -CodeRoot $Root
        if (-not $path) { throw "Health script not found or not listed in SelfX.Config.json: $file" }
        # Reject reparse points rather than allowing a protected filename to redirect outside the package.
        foreach ($target in @((Split-Path -Parent $path), $path)) {
            if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Health script reparse points are not allowed.' }
        }
        $timeout = 30
        if ($Check.HasAttribute('TimeoutSeconds')) {
            if (-not [int]::TryParse($Check.GetAttribute('TimeoutSeconds'), [ref]$timeout) -or $timeout -lt 1 -or $timeout -gt 30) { throw 'TimeoutSeconds must be between 1 and 30.' }
        }
        $run = Invoke-SelfXHealthScript -Path $path -TimeoutSeconds $timeout
        $code = $run.ExitCode
        $status = if ($code -eq 0) { 'OK' } else { $FailStatus }
        # The exit code defines the status; the last output line of the script is shown as detail.
        $text = Get-SelfXHealthScriptText $run.Output
        if (-not $text) { $text = "Exit code: $code" }
        New-SelfXHealthResult $Id $status $text $name
    } catch { New-SelfXHealthResult $Id Error $_.Exception.Message $name }
}

function Get-SelfXHealth {
    # OnlyId/OnlyName restrict collection to one check (used by the per-row OK/recheck button).
    param([string]$Root = $PSScriptRoot, [string]$OnlyId = '', [string]$OnlyName = '')
    $want = { param($id, $name = $null) (-not $OnlyId -or $OnlyId -eq $id) -and ($null -eq $name -or -not $OnlyName -or $OnlyName -eq $name) }
    try {
        $config = New-Object System.Xml.XmlDocument
        $config.XmlResolver = $null
        $XmlSettings = New-Object System.Xml.XmlReaderSettings
        $XmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $XmlSettings.XmlResolver = $null
        $XmlReader = [System.Xml.XmlReader]::Create((Get-SelfXConfigPath -Name 'Health_Config.xml' -CodeRoot $Root), $XmlSettings)
        Try { $config.Load($XmlReader) } Finally { $XmlReader.Dispose() }
        if ($config.DocumentElement.LocalName -ne 'HealthConfig') { throw 'Invalid Health_Config.xml root.' }
        if (-not $config.SelectSingleNode('/HealthConfig/Applications')) { throw 'Applications configuration is missing.' }
        $disk = $config.SelectSingleNode('/HealthConfig/Disk')
        if (-not $disk) { throw 'Disk configuration is missing.' }
        $used = 0.0; $free = 0.0
        if (-not [double]::TryParse($disk.GetAttribute('UsedPercentError'), [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$used) -or $used -le 0 -or $used -gt 100 -or [double]::IsNaN($used)) { throw 'UsedPercentError must be greater than 0 and at most 100.' }
        if (-not [double]::TryParse($disk.GetAttribute('MinimumFreeGB'), [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$free) -or $free -lt 0 -or [double]::IsInfinity($free) -or [double]::IsNaN($free)) { throw 'MinimumFreeGB must be a non-negative finite number.' }
        $checks = @($config.SelectNodes('/HealthConfig/CustomChecks/Check'))
        $updateAge = 14
        $updates = $config.SelectSingleNode('/HealthConfig/Updates')
        if ($updates -and $updates.HasAttribute('MaxSearchAgeDays') -and
            (-not [int]::TryParse($updates.GetAttribute('MaxSearchAgeDays'), [ref]$updateAge) -or $updateAge -lt 1 -or $updateAge -gt 365)) {
            throw 'MaxSearchAgeDays must be between 1 and 365.'
        }
        $services = @($config.SelectNodes('/HealthConfig/Services/Service'))
        $scriptChecks = @($config.SelectNodes('/HealthConfig/CustomChecks/Check | /HealthConfig/Applications/Application[@Script] | /HealthConfig/Compliance'))
        if ($scriptChecks.Count -gt 5 -or $services.Count -gt 16) { throw 'At most 5 script checks in total and 16 additional services are supported.' }
        $results = @(
            if (& $want IME) { Get-SelfXServiceHealth -Name IntuneManagementExtension -Id IME }
            if (& $want Defender) { Get-SelfXDefenderHealth }
            if (& $want Compliance) {
                $compliance = $config.SelectSingleNode('/HealthConfig/Compliance')
                if ($compliance) { Get-SelfXCustomHealth $compliance $Root Compliance -FailStatus Pending }
                else { New-SelfXHealthResult Compliance Unknown 'Intune evaluates compliance in the cloud; Windows stores no local compliance state. See the Company Portal, or configure the Compliance check in Health_Config.xml.' }
            }
            if (& $want Applications) { Get-SelfXApplicationHealth -Configuration $config.SelectSingleNode('/HealthConfig/Applications') -Root $Root }
            if (& $want Disk) { Get-SelfXDiskHealth $used $free }
            if (& $want BitLocker) { Get-SelfXBitLockerHealth }
            if (& $want PendingReboot) { Get-SelfXPendingRebootHealth }
            if (& $want Updates) { Get-SelfXUpdateHealth -MaxSearchAgeDays $updateAge }
            foreach ($service in $services) {
                if (-not (& $want Service $service.GetAttribute('Name'))) { continue }
                if ($service.GetAttribute('Expected') -notin @('Running','Stopped') -or $service.GetAttribute('Name') -notmatch '^[A-Za-z0-9_.-]+$') {
                    New-SelfXHealthResult Service Error 'Invalid service name or Expected value.' $service.GetAttribute('Name')
                } else { Get-SelfXServiceHealth -Name $service.GetAttribute('Name') -Expected $service.GetAttribute('Expected') }
            }
            foreach ($check in $checks) {
                if (& $want Custom $check.GetAttribute('Name')) { Get-SelfXCustomHealth $check $Root }
            }
        )
        # Multi-row checks (Disk, BitLocker) are narrowed to the requested drive afterwards.
        if ($OnlyId -and $OnlyName) { $results = @($results | Where-Object { $_.Name -eq $OnlyName -or -not $_.Name }) }
        foreach ($result in $results) {
            # When="NotOK" offers the remediation only while the status is not OK (default: Always).
            $matches = @($config.SelectNodes('/HealthConfig/Remediations/Remediation') | Where-Object {
                $_.GetAttribute('Id') -eq $result.Id -and
                (-not $_.HasAttribute('Name') -or $_.GetAttribute('Name') -eq $result.Name)
            })
            $script = ''
            if ($matches.Count -gt 1) { throw "Ambiguous remediation for $($result.Id) / $($result.Name)." }
            if ($matches.Count -eq 1) {
                $when = 'Always'
                if ($matches[0].HasAttribute('When')) { $when = $matches[0].GetAttribute('When') }
                if ($when -cnotin @('Always','NotOK')) { throw "Invalid remediation When value for $($result.Id)." }
                $script = $matches[0].GetAttribute('Script')
                if ($script -notmatch '^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,90}\.ps1$' -or $script.Contains('..')) {
                    throw "Invalid remediation filename for $($result.Id)."
                }
                if ($when -eq 'NotOK' -and $result.Status -eq 'OK') { $script = '' }
            }
            $result | Add-Member -NotePropertyName Remediation -NotePropertyValue $script
        }
        return $results
    } catch { New-SelfXHealthResult Collection Error $_.Exception.Message }
}

function Update-SelfXHealthCache {
    # Stores results for the background status cache. A full collection replaces the file; a single
    # check replaces only the rows of that check and keeps their position. Without a full cache a
    # single check is not stored, so the cache never contains only part of the checks.
    # The cache is shared by all users and every signed-in user can request a single check (HEALTH <Id> <name>),
    # so a single check never ADDS rows: an unknown name or Id leaves the cache unchanged.
    param([Parameter(Mandatory = $true)][string]$Path, [object[]]$Results, [string]$OnlyId = '', [string]$OnlyName = '')
    $items = @($Results)
    # 'Collection' is only the placeholder for "no result" and is never stored.
    if (@($items | Where-Object { "$($_.Id)" -eq 'Collection' }).Count) { return }
    if ($OnlyId) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
        # Windows PowerShell 5.1 returns a JSON array as one object; assigning it first unrolls the items.
        $parsed = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -ErrorAction Stop
        $cached = @($parsed)
        $merged = New-Object System.Collections.Generic.List[object]
        $inserted = $false
        foreach ($entry in $cached) {
            if ("$($entry.Id)" -eq $OnlyId -and (-not $OnlyName -or "$($entry.Name)" -eq $OnlyName)) {
                if (-not $inserted) { foreach ($result in $items) { $merged.Add($result) }; $inserted = $true }
            } else { $merged.Add($entry) }
        }
        if (-not $inserted) { return }
        $items = $merged.ToArray()
    }
    # Write a temporary file and rename it, so readers never see a half-written cache.
    $temp = "$Path.tmp"
    [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject @($items) -Depth 4 -Compress), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

if ($Collect) {
    $ErrorActionPreference = 'Stop'
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    # Logging to ProgramData\SelfX\Logs (SelfXLog.ps1); the JSON response on stdout is not changed by it.
    $logScript = Join-Path $PSScriptRoot 'SelfXLog.ps1'
    if (Test-Path -LiteralPath $logScript) { . $logScript; Initialize-SelfXLog -Component 'HealthStatus' } else { function Write-SelfXLog { param($Message, $Level) } }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $name = ''
    if ($OnlyName) { $name = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($OnlyName)) }
    $results = @(Get-SelfXHealth -Root $PSScriptRoot -OnlyId $OnlyId -OnlyName $name)
    if (-not $results.Count) { $results = @(New-SelfXHealthResult Collection Unknown 'The requested check is no longer configured or returned no result.' $name) }
    foreach ($result in $results) {
        $label = $(if ($result.Name) { "$($result.Id) $($result.Name)" } else { "$($result.Id)" })
        $level = $(if ($result.Status -eq 'Error') { 'Warning' } else { 'Info' })
        Write-SelfXLog ("{0}: {1} - {2}" -f $label, $result.Status, $result.Detail) $level
    }
    if ($CacheFile) {
        # The cache is an optimization; a failure must not change the response.
        try { Update-SelfXHealthCache -Path $CacheFile -Results $results -OnlyId $OnlyId -OnlyName $name } catch { Write-SelfXLog "Status cache not updated: $($_.Exception.Message)" Warning }
    }
    Write-SelfXLog ("Health check {0} finished: {1} result(s) in {2:N1} s." -f $(if ($OnlyId) { "$OnlyId $name".Trim() } else { '(all)' }), $results.Count, $watch.Elapsed.TotalSeconds)
    ConvertTo-Json -InputObject $results -Depth 4 -Compress
}
