<#
.SYNOPSIS
    Close the Citrix Workspace app of the signed-in user and start it again.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Closes the Citrix Workspace app processes of the user's own Windows
    session (first by asking them to close, after 10 seconds by ending them) and starts the app again:
      SelfService, AuthManSvr, concentr, Receiver
    Sessions that are already open (wfica32, the session windows) are NOT ended; no setting, no stored sign-in and no
    file of the app is changed or removed.
    The program is SelfService.exe of the Citrix Workspace app (installation below Program Files, 64 bit or 32 bit
    folder). Its path comes from the running process or from the two fixed locations and must pass the same check as the
    Office programs (SelfXOffice.ps1, Test-SelfXOfficeProgramPath): below Program Files, no link, no search in PATH or in
    the current directory. If no valid path is found, nothing is closed. The program is started without arguments; no
    text from the user is passed.
    Only processes of the own Windows session are touched (multi-user devices).
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = done (also when the app is not installed: nothing to do); exit 1 = the app did not close or did not start.

.NOTES
    Name    : SelfX_Citrix_RestartWorkspace.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.24

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.24   2026-11-24  fubu2k               Initial version
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# The Office helper has the program path check and the own-session process functions (no Office-specific code is used here).
$officeHelper = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXOffice.ps1'
if (-not (Test-Path -LiteralPath $officeHelper -PathType Leaf)) { throw 'SelfXOffice.ps1 is missing in the installation folder.' }
. $officeHelper

$exeName = 'SelfService.exe'
$processNames = @('SelfService', 'AuthManSvr', 'concentr', 'Receiver')
$relativePath = 'Citrix\ICA Client\SelfServicePlugin\SelfService.exe'

$running = @(Get-SelfXOwnSessionProcess -Name $processNames)
$candidates = New-Object System.Collections.Generic.List[string]
foreach ($process in $running) { if ($process.ProcessName -eq 'SelfService' -and $process.Path) { $candidates.Add("$($process.Path)") } }
foreach ($folder in (Get-SelfXTrustedProgramFolder)) { $candidates.Add((Join-Path $folder $relativePath)) }
$path = $null
foreach ($candidate in $candidates) {
	if (Test-SelfXOfficeProgramPath -Path $candidate -ExeName $exeName) { $path = [IO.Path]::GetFullPath($candidate.Trim().Trim('"')); break }
}
if (-not $path) {
	if ($running.Count) { throw 'The program path of the Citrix Workspace app could not be determined; nothing was closed.' }
	Write-SelfXLog 'The Citrix Workspace app is not installed (or not below Program Files); nothing to restart.'
	exit 0
}

if ($running.Count) {
	Write-SelfXLog "Closing $($running.Count) Citrix Workspace process(es) of this session."
	if (-not (Close-SelfXOwnSessionProcess -Name $processNames)) { throw 'The Citrix Workspace app is still running after 40 seconds; it was not started again.' }
} else {
	Write-SelfXLog 'The Citrix Workspace app is not running.'
}
Start-Process -FilePath $path
Write-SelfXLog 'Citrix Workspace app started.'
exit 0
