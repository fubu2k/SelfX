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
    The program path is independent of the Office version, the bitness and the installation type and is checked (SelfXOffice.ps1,
    Restart-SelfXOfficeApp): below Program Files, no link; if no valid path is known, nothing is closed.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = add-in enabled (and Outlook restarted when it was running); exit 1 = error.

.NOTES
    Name    : SelfX_Outlook_TeamsAddIn.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.19

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.8.0    2026-11-23  fubu2k               Program path from the closed process or from App Paths; nothing is closed when it is unknown
    2.8.19   2026-11-23  fubu2k               Restart through Restart-SelfXOfficeApp (SelfXOffice.ps1); program path is checked (Program Files, no link)
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

# The helper finds the program independent of the Office version and bitness and checks the path (SelfXOffice.ps1).
$officeHelper = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXOffice.ps1'
if (-not (Test-Path -LiteralPath $officeHelper -PathType Leaf)) { throw 'SelfXOffice.ps1 is missing in the installation folder.' }
. $officeHelper

# Outlook must be restarted so that the setting is loaded; nothing is closed if Outlook is not running.
$result = Restart-SelfXOfficeApp -Application Outlook -TimeoutSeconds 30
if (-not $result.WasRunning) {
	Write-SelfXLog 'Outlook is not running; the add-in loads at the next start of Outlook.'
	exit 0
}
Write-SelfXLog 'Outlook started again.'
exit 0
