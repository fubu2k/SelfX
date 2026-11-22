<#
.SYNOPSIS
    Reads the Microsoft Defender status and updates the signatures through CIM (no Defender module).

.DESCRIPTION
    Dot-sourced by HealthStatus.ps1, HealthChecks\Check-Compliance.ps1 and SelfX_Defender_UpdateSignature.ps1.
    The Defender module (Get-MpComputerStatus, Update-MpSignature) runs in PowerShell 7 only through the Windows PowerShell 5.1
    compatibility layer. These functions use the CIM classes of namespace root\Microsoft\Windows\Defender that the cmdlets wrap:
      - MSFT_MpComputerStatus: same properties and types as Get-MpComputerStatus (checked on Windows 11 build 26300:
        service, antivirus, antispyware and real-time flags, signature age and version, product and engine version, running
        mode; the last update is a local DateTime). Readable without administrator rights.
      - MSFT_MpSignature.Update (static method, optional UpdateSource): same as Update-MpSignature without -UpdateSource, so the
        sources and their order come from the Defender policy of the device. Needs administrator rights (the service runs it as SYSTEM).
    Both throw when Defender is not available (for example another antivirus product is active); callers show "unknown" or an error.

.NOTES
    Name    : SelfXDefender.ps1
    Package : SelfX Service
    Context : User (read) and System (update), dot-sourced
    Version : 2.6.10

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version: CIM instead of Get-MpComputerStatus / Update-MpSignature
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
