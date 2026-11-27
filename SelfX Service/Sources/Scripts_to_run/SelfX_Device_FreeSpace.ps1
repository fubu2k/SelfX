<#
.SYNOPSIS
    Free up disk space on the system drive as SYSTEM: component store, Delivery Optimization cache, old files in Windows\Temp
    and old content of the Intune Management Extension.

.DESCRIPTION
    Second part of the repair "Free up space" on the disk row (Health_Config.xml, Remediation Script). Runs non-interactively as
    LOCAL SYSTEM through the local SelfX service; SelfX runs SelfX_Device_FreeSpaceUser.ps1 as the user before it. No parameters:
    nothing from the caller is used. Steps, each one independent of the others:
    1. Dism.exe from System32 with the fixed arguments /Online /Cleanup-Image /StartComponentCleanup (never /ResetBase, so
       installed updates can still be uninstalled).
    2. Delivery Optimization cache through Delete-DeliveryOptimizationCache -Force (pinned files stay), module loaded by its full
       path in System32.
    3. Windows\Temp: entries older than MinimumAgeDays, deleted by SelfXService.exe /cleanold:WindowsTemp (handle-based, never
       follows a link, only below this fixed folder; users can write to Windows\Temp).
    4. Intune content (Content\Incoming, Content\Staging, Windows\IMECache): entries older than MinimumAgeDays, by the same helper,
       only when no installation seems to run: no AgentExecutor.exe and no msiexec.exe process, and nothing in these folders
       changed during the last ImeQuietMinutes. This is a heuristic (Windows offers no query for it); when in doubt the step is
       skipped.
    Thresholds: element DiskCleanup of Health_Config.xml (MinimumAgeDays 1-365, default 7; ImeQuietMinutes 1-1440, default 60).
    An invalid value stops the script before anything is changed. Does not restart Windows, closes no program.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1): free space before and after, the result of every step.
    Exit 0 = all steps done or skipped on purpose; exit 1 = invalid settings or at least one step failed (the others still ran).

.NOTES
    Name    : SelfX_Device_FreeSpace.ps1
    Package : SelfX Service
    Context : System
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version (fixed arguments, fixed folders, handle-based deletion of old entries)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# Paths of the configuration (Health_Config.xml in Config next to App).
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXPaths.ps1')

# Thresholds from Health_Config.xml (DiskCleanup). Missing element or attribute = default; any other value than a whole number in
# the range throws, so nothing is deleted with a setting that the administrator did not mean.
function Read-SelfXDiskCleanupSettings {
	param([Parameter(Mandatory = $true)][string]$Path)
	$settings = [pscustomobject]@{ MinimumAgeDays = 7; ImeQuietMinutes = 60 }
	$document = New-Object System.Xml.XmlDocument
	$document.XmlResolver = $null
	$xmlSettings = New-Object System.Xml.XmlReaderSettings
	$xmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
	$xmlSettings.XmlResolver = $null
	$reader = [System.Xml.XmlReader]::Create($Path, $xmlSettings)
	try { $document.Load($reader) } finally { $reader.Dispose() }
	if ($document.DocumentElement.LocalName -ne 'HealthConfig') { throw 'Invalid Health_Config.xml root.' }
	$node = $document.SelectSingleNode('/HealthConfig/DiskCleanup')
	if (-not $node) { return $settings }
	foreach ($limit in @(@('MinimumAgeDays', 1, 365), @('ImeQuietMinutes', 1, 1440))) {
		if (-not $node.HasAttribute($limit[0])) { continue }
		$text = $node.GetAttribute($limit[0])
		if ($text -notmatch '^[0-9]{1,4}\z' -or [int]$text -lt $limit[1] -or [int]$text -gt $limit[2]) {
			throw "DiskCleanup $($limit[0]) must be a whole number from $($limit[1]) to $($limit[2])."
		}
		$settings.($limit[0]) = [int]$text
	}
	return $settings
}

# Reason why the Intune content must not be touched now, or '' when no installation seems to run.
function Get-SelfXImeBusyReason {
	param([string[]]$Folders, [int]$QuietMinutes, [datetime]$NowUtc)
	$running = @(Get-Process -Name 'AgentExecutor', 'msiexec' -ErrorAction SilentlyContinue)
	if ($running.Count) { return "$((@($running | ForEach-Object { $_.ProcessName }) | Sort-Object -Unique) -join ', ') runs" }
	$limit = $NowUtc.AddMinutes(-$QuietMinutes)
	foreach ($folder in $Folders) {
		if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
		# Reading only; Get-ChildItem does not follow links without -FollowSymlink.
		$items = @(Get-Item -LiteralPath $folder -Force) + @(Get-ChildItem -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue)
		if (@($items | Where-Object { $_.LastWriteTimeUtc -ge $limit -or $_.CreationTimeUtc -ge $limit }).Count) {
			return "changes during the last $QuietMinutes minutes in $([IO.Path]::GetFileName($folder))"
		}
	}
	return ''
}

# Result line of SelfXService.exe /cleanold: (SELFX-CLEANOLD-OK removed=<n> kept=<n> bytes=<n>), or $null.
function ConvertFrom-SelfXCleanOldOutput {
	param([object[]]$Lines)
	foreach ($line in @($Lines)) {
		if ("$line" -match '^SELFX-CLEANOLD-OK removed=([0-9]+) kept=([0-9]+) bytes=([0-9]+)$') {
			return [pscustomobject]@{ Removed = [int64]$Matches[1]; Kept = [int64]$Matches[2]; Bytes = [int64]$Matches[3] }
		}
	}
	return $null
}

function Get-SelfXSystemDriveFreeGB {
	$drive = New-Object System.IO.DriveInfo ([IO.Path]::GetPathRoot([Environment]::SystemDirectory))
	return [math]::Round($drive.AvailableFreeSpace / 1GB, 2)
}

$failed = 0
$system32 = [Environment]::SystemDirectory
$settings = Read-SelfXDiskCleanupSettings -Path (Get-SelfXConfigPath -Name 'Health_Config.xml')
Write-SelfXLog ("Free space before: {0} GB. MinimumAgeDays {1}, ImeQuietMinutes {2}." -f (Get-SelfXSystemDriveFreeGB), $settings.MinimumAgeDays, $settings.ImeQuietMinutes)

# 1. Component store. Fixed program and fixed arguments; /ResetBase is never used.
$dism = Join-Path $system32 'Dism.exe'
try {
	$process = Start-Process -FilePath $dism -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup' -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
	Write-SelfXLog "DISM component cleanup finished with exit code $($process.ExitCode)." $(if ($process.ExitCode -eq 0) { 'Info' } else { 'Warning' })
	if ($process.ExitCode -ne 0) { $failed++ }
} catch { $failed++; Write-SelfXLog "DISM component cleanup failed: $($_.Exception.Message)" Warning }

# 2. Delivery Optimization cache (pinned files stay). The module is loaded by its full path, not from the module path.
$doModule = Join-Path $system32 'WindowsPowerShell\v1.0\Modules\DeliveryOptimization\DeliveryOptimization.psd1'
try {
	if (-not (Test-Path -LiteralPath $doModule -PathType Leaf)) { throw 'The DeliveryOptimization module is missing.' }
	Import-Module -Name $doModule -ErrorAction Stop
	$null = Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
	Write-SelfXLog 'Delivery Optimization cache cleared (pinned files kept).'
} catch { $failed++; Write-SelfXLog "Delivery Optimization cache: $($_.Exception.Message)" Warning }

# 3. and 4. Old entries below fixed folders, through the delete helper of the installation (never follows a link).
$helper = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXService.exe'
$ime = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft Intune Management Extension\Content'
$imeFolders = @((Join-Path $ime 'Incoming'), (Join-Path $ime 'Staging'), (Join-Path ([Environment]::GetFolderPath('Windows')) 'IMECache'))
$roots = @('WindowsTemp')
$busy = Get-SelfXImeBusyReason -Folders $imeFolders -QuietMinutes $settings.ImeQuietMinutes -NowUtc ([datetime]::UtcNow)
if ($busy) { Write-SelfXLog "Intune content skipped: $busy (an installation may run)." }
else { $roots += @('ImeIncoming', 'ImeStaging', 'ImeCache') }
if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
	$failed++
	Write-SelfXLog 'Old files skipped: SelfXService.exe of the installation is missing.' Warning
} else {
	foreach ($root in $roots) {
		$output = @(& $helper "/cleanold:$root" "/minage:$($settings.MinimumAgeDays)" 2>&1)
		$code = $LASTEXITCODE
		$result = ConvertFrom-SelfXCleanOldOutput -Lines $output
		if ($code -eq 0 -and $result) {
			Write-SelfXLog ("{0}: {1} old item(s) removed ({2:N1} MB), {3} in use or kept." -f $root, $result.Removed, ($result.Bytes / 1MB), $result.Kept)
		} else {
			$failed++
			$reason = @($output | ForEach-Object { "$_" } | Where-Object { $_ -like 'SELFX-CLEANOLD-ERROR*' }) | Select-Object -First 1
			Write-SelfXLog "${root}: the delete helper ended with exit code $code. $reason" Warning
		}
	}
}

Write-SelfXLog ("Free space after: {0} GB." -f (Get-SelfXSystemDriveFreeGB))
if ($failed) {
	Write-Output "Free up space: $failed step(s) failed. Details in the SelfX log."
	exit 1
}
Write-Output 'Free up space: done.'
exit 0
