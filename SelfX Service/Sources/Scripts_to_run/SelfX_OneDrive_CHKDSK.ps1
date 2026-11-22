<#
.SYNOPSIS
    Schedule a check and repair of the Windows system drive at the next restart.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service". Schedules an offline scan and repair of the system drive (SystemDrive)
    with the CIM method Repair (OfflineScanAndFix) of MSFT_Volume (root\Microsoft\Windows\Storage), which is
    what Repair-Volume -OfflineScanAndFix does; Windows runs it at the next restart, the same as
    "chkdsk /f". Used for OneDrive files that are locked by a damaged reparse point
    (error 0x80071129). This script does not restart Windows; the user restarts later.
    The check at the next start can take several minutes.
    Before 2.6.0 the script answered the chkdsk prompt with "Y", which Windows in other
    display languages (for example German, "J") did not accept, so no check was scheduled.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Exit 0 = check scheduled; exit 1 = scheduling failed.

.NOTES
    Name    : SelfX_OneDrive_CHKDSK.ps1
    Package : SelfX Service
    Context : System
    Version : 2.6.10

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Runs as SYSTEM through the SelfX service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Repair-Volume -OfflineScanAndFix instead of "echo Y| chkdsk" (worked
                                              only in English Windows); logging (SelfXLog.ps1)
    2.6.10   2026-11-22  fubu2k               CIM method Repair instead of Repair-Volume (no compatibility layer in PowerShell 7)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }

$letter = "$env:SystemDrive".TrimEnd(':', '\')
try {
	# On the system drive the offline repair cannot run now; Windows schedules it for the next start.
	$volume = @(Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_Volume -ErrorAction Stop | Where-Object { "$($_.DriveLetter)" -eq $letter }) | Select-Object -First 1
	if (-not $volume) { throw "Drive $($letter): was not found." }
	$result = Invoke-CimMethod -InputObject $volume -MethodName Repair -Arguments @{ OfflineScanAndFix = $true } -ErrorAction Stop
	if ($null -ne $result.ReturnValue -and [int]$result.ReturnValue -ne 0) { throw "Repair returned $($result.ReturnValue)." }
	Write-SelfXLog "MSFT_Volume.Repair OfflineScanAndFix $($letter): ReturnValue $($result.ReturnValue), Output $($result.Output)"
	Write-Output "Check and repair of drive $($letter): scheduled for the next restart."
	exit 0
} catch {
	Write-SelfXLog "Could not schedule the check of drive $($letter): $($_.Exception.Message)" Error
	Write-Output "Could not schedule the check of drive $($letter): $($_.Exception.Message)"
	exit 1
}
