<#
.SYNOPSIS
    Reads the Microsoft Defender status and updates the signatures through CIM (no Defender module).

.DESCRIPTION
    Dot-sourced by HealthStatus.ps1, HealthChecks\Check-Compliance.ps1, SelfX_Defender_UpdateSignature.ps1 and SelfX_Defender_QuickScan.ps1.
    The Defender module (Get-MpComputerStatus, Update-MpSignature) runs in PowerShell 7 only through the Windows PowerShell 5.1
    compatibility layer. These functions use the CIM classes of namespace root\Microsoft\Windows\Defender that the cmdlets wrap:
      - MSFT_MpComputerStatus: same properties and types as Get-MpComputerStatus (checked on Windows 11 build 26300:
        service, antivirus, antispyware and real-time flags, signature age and version, product and engine version, running
        mode; the last update is a local DateTime). Readable without administrator rights.
      - MSFT_MpSignature.Update (static method, optional UpdateSource): same as Update-MpSignature without -UpdateSource, so the
        sources and their order come from the Defender policy of the device. Needs administrator rights (the service runs it as SYSTEM).
      - MSFT_MpScan.Start (static method, ScanType 1 = quick scan, as mpcmdrun -scantype 1 and Start-MpScan -ScanType QuickScan): runs
        a scan and returns when it has finished. Needs administrator rights (the service runs it as SYSTEM).
      - MSFT_MpThreatDetection and MSFT_MpThreat: detections of the Defender log with the threat id and name. Only counts and names
        are read, never file paths.
    All of them throw when Defender is not available (for example another antivirus product is active); callers show "unknown" or an error.

.NOTES
    Name    : SelfXDefender.ps1
    Package : SelfX Service
    Context : User (read) and System (update, scan), dot-sourced
    Version : 2.8.15

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version: CIM instead of Get-MpComputerStatus / Update-MpSignature
    2.8.15   2026-11-23  fubu2k               Start-SelfXDefenderQuickScan, Get-SelfXDefenderDetection (quick scan action)
#>

$Script:SelfXDefenderNamespace = 'root\Microsoft\Windows\Defender'

# Defender status (one MSFT_MpComputerStatus instance). Throws when the class cannot be read; $null when there is no instance.
function Get-SelfXDefenderStatus {
	@(Get-CimInstance -Namespace $Script:SelfXDefenderNamespace -ClassName MSFT_MpComputerStatus -ErrorAction Stop) | Select-Object -First 1
}

# Updates the signatures from the sources of the Defender policy. Throws when Defender reports an error.
function Update-SelfXDefenderSignature {
	$result = Invoke-CimMethod -Namespace $Script:SelfXDefenderNamespace -ClassName MSFT_MpSignature -MethodName Update -ErrorAction Stop
	if ($result -and $result.PSObject.Properties['ReturnValue'] -and $null -ne $result.ReturnValue -and [int]$result.ReturnValue -ne 0) {
		throw "Defender signature update returned $($result.ReturnValue)."
	}
}

# Runs a Defender quick scan and returns when it has finished (the call blocks, as Start-MpScan). Throws when Defender reports an error.
# TimeoutSeconds is the limit of the CIM operation, not of the scan on the device.
function Start-SelfXDefenderQuickScan {
	param([int]$TimeoutSeconds = 2300)
	$result = Invoke-CimMethod -Namespace $Script:SelfXDefenderNamespace -ClassName MSFT_MpScan -MethodName Start -Arguments @{ ScanType = [byte]1 } -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop
	if ($result -and $result.PSObject.Properties['ReturnValue'] -and $null -ne $result.ReturnValue -and [int]$result.ReturnValue -ne 0) {
		throw "Defender quick scan returned $($result.ReturnValue)."
	}
}

# Threats that Defender detected since the given time (local DateTime): one object per threat id with Name and Count.
# Names are shortened and limited to harmless characters (they are written to the log and shown to nobody else); no path is read.
function Get-SelfXDefenderDetection {
	param([Parameter(Mandatory = $true)][datetime]$Since)
	$detections = @(Get-CimInstance -Namespace $Script:SelfXDefenderNamespace -ClassName MSFT_MpThreatDetection -ErrorAction Stop |
		Where-Object { $_.InitialDetectionTime -and ([datetime]$_.InitialDetectionTime) -ge $Since })
	$names = @{}
	if ($detections.Count) {
		foreach ($threat in @(Get-CimInstance -Namespace $Script:SelfXDefenderNamespace -ClassName MSFT_MpThreat -ErrorAction SilentlyContinue)) {
			if ($null -ne $threat.ThreatID) { $names["$($threat.ThreatID)"] = "$($threat.ThreatName)" }
		}
	}
	foreach ($group in ($detections | Group-Object { "$($_.ThreatID)" })) {
		$name = if ($names.ContainsKey($group.Name)) { ($names[$group.Name] -replace '[^A-Za-z0-9:/._!#@\-]', '?') } else { '' }
		if ($name.Length -gt 80) { $name = $name.Substring(0, 80) }
		[pscustomobject]@{ ThreatId = $group.Name; Name = $(if ($name) { $name } else { 'unknown' }); Count = $group.Count }
	}
}
