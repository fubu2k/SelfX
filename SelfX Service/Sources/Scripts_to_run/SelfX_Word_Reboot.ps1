<#
.SYNOPSIS
    Close Microsoft Word and start it again.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Closes the WINWORD.EXE processes of the user's
    session, retains the executable path, waits until Word has closed (at most 15 seconds) and
    starts Word again. Documents are not explicitly reopened (Word offers its document recovery);
    unsaved changes can be lost. Does not restart Windows.
    The program path is independent of the Office version, the bitness and the installation type and is checked (SelfXOffice.ps1,
    Restart-SelfXOfficeApp): below Program Files, no link; if no valid path is known, nothing is closed.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = Word restarted or not running; exit 1 = Word could not be closed.

.NOTES
    Name    : SelfX_Word_Reboot.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.19

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.8.0    2026-11-23  fubu2k               Program path from the closed process or from App Paths; nothing is closed when it is unknown
    2.8.19   2026-11-23  fubu2k               Program path and restart through Restart-SelfXOfficeApp (SelfXOffice.ps1); path is checked (Program Files, no link)
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

$result = Restart-SelfXOfficeApp -Application Word -TimeoutSeconds 15
if (-not $result.WasRunning) {
	Write-SelfXLog 'Word is not running; nothing to restart.'
	exit 0
}
Write-SelfXLog 'Word started again.'
exit 0
