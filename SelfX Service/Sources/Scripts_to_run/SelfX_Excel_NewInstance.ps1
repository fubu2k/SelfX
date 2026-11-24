<#
.SYNOPSIS
    Start a second, independent Excel instance (to compare two workbooks side by side, for example on two screens).

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Excel normally opens every workbook in the same Excel window
    (one instance). This action starts a new, independent Excel instance with the switch /x, so that a second
    workbook can be opened in its own window and moved to another screen.
    Nothing is closed, ended or changed: Excel windows and workbooks that are already open are not touched, no
    setting and no file is changed.
    The program path is independent of the Office version, the bitness (32 or 64 bit) and the installation type and is
    checked (SelfXOffice.ps1, Get-SelfXOfficeAppPath): below Program Files, no link, never searched in PATH or in the
    current directory. The only argument is the fixed switch /x; no path, file name or text from the user is passed.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = Excel was started; exit 1 = classic Excel was not found or could not be started.

.NOTES
    Name    : SelfX_Excel_NewInstance.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.23

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.23   2026-11-24  fubu2k               Initial version
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

# A running Excel of the own session is used as the first source of the path (it is checked like every other source).
$running = @(Get-SelfXOwnSessionProcess -Name 'EXCEL')
$processPath = $running | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path
$path = Get-SelfXOfficeAppPath -Application Excel -ProcessPath $processPath
if (-not $path) { throw 'Classic Excel was not found on this device (or its path is not below Program Files); no new Excel window was started.' }

Write-SelfXLog "Starting a new Excel instance ($($running.Count) Excel process(es) of this session already running)."
Start-Process -FilePath $path -ArgumentList '/x'
Write-SelfXLog 'New Excel instance started.'
exit 0
