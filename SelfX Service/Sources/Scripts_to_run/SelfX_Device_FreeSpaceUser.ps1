<#
.SYNOPSIS
    Free up disk space in the profile of the signed-in user: recycle bin, TEMP and the Teams cache.

.DESCRIPTION
    First part of the repair "Free up space" on the disk row (Health_Config.xml, Remediation UserScript). SelfX starts it as the
    signed-in user after one confirmation and starts SelfX_Device_FreeSpace.ps1 through the service afterwards.
    - Empties the recycle bin of the user without a further question (cannot be undone).
    - Removes the items below the TEMP folder of the user. Files in use stay (normal while applications run).
    - Removes the Teams cache of the user (same folders as SelfX_Teams_ResetCache.ps1) only while no Teams process of this
      session runs. Teams is never closed: a running call must not end. When Teams runs, the cache is skipped (exit code 2).
    Nothing outside the profile of the user is touched; nothing runs with more rights than the user has. No parameters.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = done (also when files in use remain); exit 2 = done, the Teams cache was skipped because Teams runs.

.NOTES
    Name    : SelfX_Device_FreeSpaceUser.ps1
    Package : SelfX Service
    Context : User
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version (first part of "Free up space"; recycle bin and TEMP as in
                                              SelfX_Device_DeviceSlow.ps1, Teams cache folders as in SelfX_Teams_ResetCache.ps1)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# Removes the given items one by one; locked or denied items stay and are only counted.
function Remove-SelfXFreeSpaceItems {
	param([object[]]$Items, [string]$Label)
	$removed = 0; $kept = 0; $bytes = 0
	foreach ($item in @($Items)) {
		$size = 0
		if (-not $item.PSIsContainer) { $size = $item.Length }
		try {
			Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
			$removed++
			$bytes += $size
		} catch { $kept++ }
	}
	Write-SelfXLog ("{0}: {1} item(s) removed (files at the top level: {2:N1} MB), {3} item(s) in use or not accessible." -f $Label, $removed, ($bytes / 1MB), $kept)
}

# Recycle bin of the user: permanent, without a second question (the user confirmed the list in SelfX). Windows PowerShell
# reports an error for an empty recycle bin, which is not a failure of this action.
try {
	Clear-RecycleBin -Force -Confirm:$false -ErrorAction Stop
	Write-SelfXLog 'Recycle bin emptied.'
} catch {
	Write-SelfXLog "Recycle bin: $($_.Exception.Message) (empty or not accessible)."
}

# TEMP of the user. A link below TEMP is removed itself (Remove-Item does not follow it); the user has these rights anyway.
if ($env:TEMP -and (Test-Path -LiteralPath $env:TEMP -PathType Container)) {
	Remove-SelfXFreeSpaceItems -Items @(Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue) -Label 'TEMP'
}

# Teams cache only while Teams of this session is closed: the action never ends a call or a meeting.
$session = (Get-Process -Id $PID).SessionId
$teams = @(Get-Process -Name 'ms-teams', 'msteams', 'Teams' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
if ($teams.Count) {
	Write-SelfXLog "Teams cache skipped: $($teams.Count) Teams process(es) of this session run."
	exit 2
}
$items = @()
$teamsClassicPath = Join-Path $env:APPDATA 'Microsoft\Teams'
$newTeamsCachePath = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
if (Test-Path -LiteralPath $teamsClassicPath) {
	$items += @(Get-ChildItem -LiteralPath $teamsClassicPath -Directory -Force |
		Where-Object { $_.Name -in @('application cache', 'blob storage', 'databases', 'GPUcache', 'IndexedDB', 'Local Storage', 'tmp') })
}
if (Test-Path -LiteralPath $newTeamsCachePath) { $items += @(Get-ChildItem -LiteralPath $newTeamsCachePath -Force) }
Remove-SelfXFreeSpaceItems -Items $items -Label 'Teams cache'
exit 0
