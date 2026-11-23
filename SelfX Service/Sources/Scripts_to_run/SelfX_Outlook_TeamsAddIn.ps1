<#
.SYNOPSIS
    Enable the Teams meeting add-in for Outlook and restart Outlook.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Sets LoadBehavior = 3 (load at startup) for
    the Teams meeting add-in (TeamsAddin.FastConnect, classic and new Teams) under
    HKCU\Software\Microsoft\Office\Outlook\Addins and adds it to the Outlook DoNotDisableAddinList,
    so Outlook does not disable it again after a slow start. Then closes classic Outlook
    (outlook.exe) of the user's session, waits up to 30 seconds and starts Outlook again.
    Outlook windows close and unsaved items may be lost. Does not install a missing add-in; the
    new Outlook (olk.exe) does not use COM add-ins, its Teams integration is not changed.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = add-in enabled (and Outlook restarted when it was running); exit 1 = error.

.NOTES
    Name    : SelfX_Outlook_TeamsAddIn.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.8.0    2026-11-23  fubu2k               Program path from the closed process or from App Paths; nothing is closed when it is unknown
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# LoadBehavior 3 requests the registered add-in to load when Outlook starts.
$addIn = 'HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect'
if (-not (Test-Path -LiteralPath $addIn)) { New-Item -Path $addIn -Force | Out-Null; Write-SelfXLog 'Add-in key created.' }
Set-ItemProperty -LiteralPath $addIn -Name 'LoadBehavior' -Value 3 -Type DWord -Force
# Outlook must not disable the add-in again (for example after a slow start).
$doNotDisable = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList'
if (-not (Test-Path -LiteralPath $doNotDisable)) { New-Item -Path $doNotDisable -Force | Out-Null }
Set-ItemProperty -LiteralPath $doNotDisable -Name 'TeamsAddin.FastConnect' -Value 1 -Type DWord -Force
Write-SelfXLog 'Teams meeting add-in: LoadBehavior = 3, DoNotDisableAddinList = 1.'

$session = (Get-Process -Id $PID).SessionId
$outlook = @(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
if (-not $outlook.Count) {
	Write-SelfXLog 'Outlook is not running; the add-in loads at the next start of Outlook.'
	exit 0
}
$outlookPath = $outlook | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path
if (-not $outlookPath) {
	# No search through the program path: the path comes from the machine-wide App Paths registration (administrators only).
	$appPath = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE' -ErrorAction SilentlyContinue).'(default)'
	if ($appPath -and (Test-Path -LiteralPath $appPath.Trim('"') -PathType Leaf)) { $outlookPath = $appPath.Trim('"') }
}
if (-not $outlookPath) { throw 'The program path of Outlook could not be determined; Outlook was not closed.' }
$outlook | Stop-Process -Force -ErrorAction Stop
# Wait for the old Outlook instance to exit so the start loads the add-in setting.
for ($i = 0; $i -lt 30 -and (Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }); $i++) { Start-Sleep -Seconds 1 }
if (Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }) {
	throw 'Outlook is still running after 30 seconds; it was not restarted.'
}
Start-Process -FilePath $outlookPath
Write-SelfXLog 'Outlook started again.'
exit 0
