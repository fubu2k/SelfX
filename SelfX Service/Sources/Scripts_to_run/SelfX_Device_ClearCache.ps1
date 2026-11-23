<#
.SYNOPSIS
    Clear the local Windows DNS client cache.

.DESCRIPTION
    Calls the CIM method Clear of MSFT_DNSClientCache (root\StandardCimv2), which is what Clear-DnsClientCache
    does, as the signed-in user from the SelfX GUI (works without administrator rights). Clears the machine DNS client resolver cache, not browser caches or
    DNS server records. Subsequent name lookups must be resolved again; existing network
    adapters and applications are not restarted.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = cache cleared; exit 1 = the call failed.

.NOTES
    Name    : SelfX_Device_ClearCache.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.10

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.6.10   2026-11-22  fubu2k               CIM method instead of Clear-DnsClientCache (no compatibility layer in PowerShell 7)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }

try {
	# Remove cached DNS answers so subsequent lookups can retrieve current records.
	$result = Invoke-CimMethod -Namespace 'root\StandardCimv2' -ClassName MSFT_DNSClientCache -MethodName Clear -ErrorAction Stop
	if ($result -and $result.PSObject.Properties['ReturnValue'] -and $null -ne $result.ReturnValue -and [int]$result.ReturnValue -ne 0) { throw "The DNS client returned $($result.ReturnValue)." }
	Write-SelfXLog 'DNS client cache cleared.'
	exit 0
} catch {
	Write-SelfXLog "Could not clear the DNS client cache: $($_.Exception.Message)" Error
	exit 1
}
