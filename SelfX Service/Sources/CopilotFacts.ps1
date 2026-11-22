<#
.SYNOPSIS
    Collects the facts for the optional hand-over to Copilot Chat from the device status that SelfX already shows
    (read only, no new queries of the device except the local values named below).

.DESCRIPTION
    Get-SelfXCopilotFacts returns the facts table that New-SelfXCopilotPrompt (CopilotPrompt.ps1) accepts. It reads
    only local, cheap values: the registry values of the Windows version, the boot time of the process clock, the
    fixed drives (name, size, free space) and the rows of the device status that the window has already collected.
    It starts no process, opens no network connection and writes nothing.

    From the device status only the technical check Id, the state (OK, Pending, Error, Unknown) and the detail text
    are taken. The detail text is cleaned by the prompt builder (placeholders for names, addresses and identifiers).
    Information items of the System information page (computer name, user name, addresses, serial numbers, ...)
    are never used.

.NOTES
    Name    : CopilotFacts.ps1
    Package : SelfX Service
    Context : GUI helper (signed-in user), functions only
    Version : 2.8.10

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.10   2026-11-22  fubu2k               Initial version
#>

function ConvertTo-SelfXCopilotStatusRows {
	<#
	.SYNOPSIS
	    Turns the health items of the window (Status, HealthId, HealthName, Detail) into status rows.
	    Items without a technical check Id are skipped.
	#>
	param([object[]]$HealthItems = @())
	$rows = New-Object System.Collections.Generic.List[object]
	foreach ($item in @($HealthItems)) {
		if ($null -eq $item) { continue }
		if (-not ($item.PSObject.Properties.Name -contains 'HealthId')) { continue }
		$id = "$($item.HealthId)"
		if ($id -notmatch '^[A-Za-z0-9_.-]{1,60}$') { continue }
		$state = switch ("$($item.Status)".ToLowerInvariant()) { 'ok' { 'OK' } 'pending' { 'Pending' } 'error' { 'Error' } default { 'Unknown' } }
		$name = $id
		if ($item.PSObject.Properties.Name -contains 'HealthName' -and "$($item.HealthName)" -match '^[A-Za-z0-9 _.():-]{1,60}$') { $name = "$id ($($item.HealthName))" }
		$detail = ''
		if ($item.PSObject.Properties.Name -contains 'Detail') { $detail = "$($item.Detail)" }
		$rows.Add(@{ Name = $name; State = $state; Detail = $detail })
		if ($rows.Count -ge 40) { break }
	}
	return $rows.ToArray()
}

function Get-SelfXCopilotDiskFacts {
	# Fixed drives only: drive letter, percent used, free space in GB (no labels, no paths).
	$disks = New-Object System.Collections.Generic.List[object]
	try {
		foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
			if ($drive.DriveType -ne [System.IO.DriveType]::Fixed -or -not $drive.IsReady) { continue }
			$letter = "$($drive.Name)".Substring(0, 2)
			if ($letter -notmatch '^[A-Za-z]:$' -or $drive.TotalSize -le 0) { continue }
			$used = [int][math]::Round(100 * ($drive.TotalSize - $drive.TotalFreeSpace) / $drive.TotalSize)
			$disks.Add(@{ Drive = $letter; UsedPercent = [math]::Min([math]::Max($used, 0), 100); FreeGB = [int][math]::Floor($drive.TotalFreeSpace / 1GB) })
			if ($disks.Count -ge 6) { break }
		}
	}
	catch { }
	return $disks.ToArray()
}

function Get-SelfXCopilotFacts {
	<#
	.SYNOPSIS
	    Facts table for New-SelfXCopilotPrompt: Windows version, SelfX version and language, uptime, disks and the
	    device status rows. Every part is optional; a part that cannot be read is left out.
	#>
	param(
		[object[]]$HealthItems = @(),
		[string]$SelfXVersion = '',
		[string]$Language = ''
	)
	$facts = @{}
	try {
		$cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
		if ($cv.ProductName) { $facts.WindowsEdition = "$($cv.ProductName)" }
		if ($cv.DisplayVersion) { $facts.WindowsVersion = "$($cv.DisplayVersion)" }
		if ($cv.CurrentBuildNumber) { $facts.WindowsBuild = ('{0}.{1}' -f $cv.CurrentBuildNumber, [int]$cv.UBR) }
	}
	catch { }
	if ($SelfXVersion) { $facts.SelfXVersion = $SelfXVersion }
	if ($Language) { $facts.Language = $Language }
	try { $facts.UptimeDays = [math]::Floor([Environment]::TickCount64 / 86400000) } catch { }
	$disks = @(Get-SelfXCopilotDiskFacts)
	if ($disks.Count) { $facts.Disks = $disks }
	$status = @(ConvertTo-SelfXCopilotStatusRows -HealthItems $HealthItems)
	if ($status.Count) { $facts.Status = $status }
	return $facts
}
