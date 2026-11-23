<#
.SYNOPSIS
    Clear the auto-complete list of classic Outlook and start Outlook again.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Closes classic Outlook (OUTLOOK.EXE) of the user's own session
    (first by asking it to close, after 10 seconds by ending it), waits up to 30 seconds until it has closed and starts
    Outlook with the switch /cleanautocompletecache. Outlook then clears the list of suggested e-mail addresses
    (auto-complete list) and builds it again while the user sends mail. Mailbox, contacts, profile and data files are
    not changed. Mails that are being written and not saved as a draft may be lost.
    The program path is independent of the Office version, the bitness and the installation type (SelfXOffice.ps1):
    path of the running Outlook, App Paths registration, Office InstallRoot; only a file below Program Files is used,
    nothing is searched in PATH. When no valid path is found, nothing is closed. The new Outlook (olk.exe) has no such
    switch and is not affected. Does not restart Windows.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = Outlook started with the switch; exit 1 = classic Outlook not found or could not be closed.

.NOTES
    Name    : SelfX_Outlook_CleanAutoComplete.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.8.0    2026-11-23  fubu2k               Program path independent of Office version and bitness; own session only; logging and exit code
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

$officeHelper = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXOffice.ps1'
if (-not (Test-Path -LiteralPath $officeHelper -PathType Leaf)) { throw 'SelfXOffice.ps1 is missing in the installation folder.' }
. $officeHelper

$outlook = @(Get-SelfXOwnSessionProcess -Name 'OUTLOOK')
$processPath = $outlook | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path
$outlookPath = Get-SelfXOfficeAppPath -Application Outlook -ProcessPath $processPath
if (-not $outlookPath) {
	# Nothing is closed: without a valid program path Outlook could not be started again.
	throw 'Classic Outlook (OUTLOOK.EXE) was not found in a program folder (the new Outlook has no auto-complete switch). Nothing was closed.'
}

if ($outlook.Count) {
	Write-SelfXLog "Closing $($outlook.Count) Outlook process(es)."
	if (-not (Close-SelfXOwnSessionProcess -Name 'OUTLOOK')) { throw 'Outlook is still running after 40 seconds; the auto-complete list was not cleared.' }
} else {
	Write-SelfXLog 'Outlook is not running.'
}

# Outlook clears the auto-complete list while it starts; the start is not waited for.
Start-Process -FilePath $outlookPath -ArgumentList '/cleanautocompletecache'
Write-SelfXLog "Outlook started with /cleanautocompletecache ($outlookPath)."
exit 0
