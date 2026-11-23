<#
.SYNOPSIS
    Close running Excel processes and reopen the discovered Excel executable.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Finds the EXCEL.EXE processes of the user's
    session, retains the first executable path and terminates them. Unsaved workbook changes
    can be lost. Waits up to 15 seconds until Excel has stopped before launching the retained
    executable; workbooks are not explicitly reopened.
    Exits 0 when no Excel process exists. A missing path, failed termination or a surviving
    Excel process raise an error (exit 1) instead of starting another instance.
    The program path is independent of the Office version, the bitness and the installation type and is checked (SelfXOffice.ps1,
    Stop-SelfXOfficeApp): below Program Files, no link; if no valid path is known, nothing is closed.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).

.NOTES
    Name    : SelfX_Excel_Reboot.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-10-28  Wolfgang Baeck       Initial version (based on SelfX_Word_Reboot.ps1)
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1); only processes of the user's session
    2.8.19   2026-11-23  fubu2k               Program path and restart through Stop-SelfXOfficeApp (SelfXOffice.ps1); path is checked (Program Files, no link)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# The helper finds the program independent of the Office version and bitness and checks the path (SelfXOffice.ps1).
$officeHelper = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXOffice.ps1'
if (-not (Test-Path -LiteralPath $officeHelper -PathType Leaf)) { throw 'SelfXOffice.ps1 is missing in the installation folder.' }
. $officeHelper

$result = Stop-SelfXOfficeApp -Application Excel -TimeoutSeconds 15
if (-not $result.WasRunning) {
	Write-SelfXLog 'Excel is not running; nothing to restart.'
	exit 0
}
Write-SelfXLog "Closed $($result.ProcessCount) Excel process(es) ($($result.Path))."
Start-Process -FilePath $result.Path
Write-SelfXLog 'Excel started again.'
exit 0
