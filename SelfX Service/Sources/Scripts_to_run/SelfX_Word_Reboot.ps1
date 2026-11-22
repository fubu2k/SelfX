<#
.SYNOPSIS
    Close Microsoft Word and start it again.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Closes the WINWORD.EXE processes of the user's
    session, retains the executable path, waits until Word has closed (at most 15 seconds) and
    starts Word again. Documents are not explicitly reopened (Word offers its document recovery);
    unsaved changes can be lost. Does not restart Windows.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = Word restarted or not running; exit 1 = Word could not be closed.

.NOTES
    Name    : SelfX_Word_Reboot.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Moved to SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Only WINWORD.EXE of the user (was every process named *word*, which also
                                              closed for example 1Password or WordPad); several Word processes no
                                              longer break the start; logging
    2.8.0    2026-11-23  fubu2k               No start by program name: the path is taken from the closed process or from App Paths, nothing is
                                              closed when it is unknown (code review finding N8)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

$session = (Get-Process -Id $PID).SessionId
$word = @(Get-Process -Name WINWORD -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
if (-not $word.Count) {
	Write-SelfXLog 'Word is not running; nothing to restart.'
	exit 0
}
# Capture the executable path before termination removes its process metadata.
$wordPath = $word | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path
if (-not $wordPath) {
	# No search through the program path: the path comes from the machine-wide App Paths registration (administrators only).
	$appPath = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\WINWORD.EXE' -ErrorAction SilentlyContinue).'(default)'
	if ($appPath -and (Test-Path -LiteralPath $appPath.Trim('"') -PathType Leaf)) { $wordPath = $appPath.Trim('"') }
}
if (-not $wordPath) { throw 'The program path of Word could not be determined; Word was not closed.' }
Write-SelfXLog "Closing $($word.Count) Word process(es) ($wordPath)."
$word | Stop-Process -Force -ErrorAction Stop
for ($i = 0; $i -lt 15 -and (Get-Process -Name WINWORD -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }); $i++) { Start-Sleep -Seconds 1 }
if (Get-Process -Name WINWORD -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }) {
	throw 'Word is still running after 15 seconds; it was not restarted.'
}
Start-Process -FilePath $wordPath
Write-SelfXLog 'Word started again.'
exit 0
