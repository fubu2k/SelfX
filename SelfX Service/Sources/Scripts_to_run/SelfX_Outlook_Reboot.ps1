<#
.SYNOPSIS
    Close classic Microsoft Outlook and start it again.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Closes the OUTLOOK.EXE processes of the user's
    session, retains the executable path, waits until Outlook has closed (at most 30 seconds) and
    starts Outlook again. Mails that are being written and not saved as a draft are lost; Outlook can
    check its data file after a forced close, so the first start may take longer. Nothing is deleted
    or reset (profile, data files and add-ins stay unchanged). The new Outlook (olk.exe) is not
    affected. Does not restart Windows.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = Outlook restarted or not running; exit 1 = Outlook could not be closed.

.NOTES
    Name    : SelfX_Outlook_Reboot.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.2    2026-11-22  fubu2k               Initial version (own session, classic Outlook only)
    2.8.0    2026-11-23  fubu2k               Program path from the closed process or from App Paths; nothing is closed when it is unknown
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

$session = (Get-Process -Id $PID).SessionId
$outlook = @(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
if (-not $outlook.Count) {
	Write-SelfXLog 'Outlook is not running; nothing to restart.'
	exit 0
}
# Capture the executable path before termination removes its process metadata.
$outlookPath = $outlook | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path
if (-not $outlookPath) {
	# No search through the program path: the path comes from the machine-wide App Paths registration (administrators only).
	$appPath = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE' -ErrorAction SilentlyContinue).'(default)'
	if ($appPath -and (Test-Path -LiteralPath $appPath.Trim('"') -PathType Leaf)) { $outlookPath = $appPath.Trim('"') }
}
if (-not $outlookPath) { throw 'The program path of Outlook could not be determined; Outlook was not closed.' }
Write-SelfXLog "Closing $($outlook.Count) Outlook process(es) ($outlookPath)."
$outlook | Stop-Process -Force -ErrorAction Stop
for ($i = 0; $i -lt 30 -and (Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }); $i++) { Start-Sleep -Seconds 1 }
if (Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }) {
	throw 'Outlook is still running after 30 seconds; it was not restarted.'
}
Start-Process -FilePath $outlookPath
Write-SelfXLog 'Outlook started again.'
exit 0
