<#
.SYNOPSIS
    Bring program windows back that lie outside the screen (for example after an external monitor was removed).

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Looks at the program windows of the own Windows session and moves
    every window whose title bar cannot be reached on any of the connected screens to the primary screen
    (SelfXWindows.ps1, Test-SelfXWindowLost). A window that is larger than the screen is made smaller. Several windows
    are placed with a small offset.
    Nothing is closed, ended, saved or changed otherwise: no document, no setting, no display configuration. Windows that
    are visible, minimized or maximized, the taskbar and the desktop are not touched. Programs that run with higher
    rights than the user cannot be moved; they are counted and skipped.
    The windows are read and moved through Microsoft UI Automation (nothing is compiled, no native call, no argument comes
    from the user). Window titles and program names are not written to the log, only the counts.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = done (also when no window was outside the screen); exit 1 = a window could not be moved.

.NOTES
    Name    : SelfX_Device_BringWindowsBack.ps1
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

$windowHelper = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXWindows.ps1'
if (-not (Test-Path -LiteralPath $windowHelper -PathType Leaf)) { throw 'SelfXWindows.ps1 is missing in the installation folder.' }
. $windowHelper

# Pixels of the screens and of the windows must use the same coordinate system (physical pixels).
Add-Type -AssemblyName System.Windows.Forms
try { [System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::PerMonitorV2) | Out-Null } catch { }

$screens = @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { New-SelfXRect -Left $_.Bounds.Left -Top $_.Bounds.Top -Width $_.Bounds.Width -Height $_.Bounds.Height })
$primary = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$workArea = New-SelfXRect -Left $primary.Left -Top $primary.Top -Width $primary.Width -Height $primary.Height
Write-SelfXLog "$($screens.Count) screen(s) found."

$windows = @(Get-SelfXTopLevelWindow)
$lost = @($windows | Where-Object { Test-SelfXWindowLost -Rect $_.Rect -Screens $screens })
Write-SelfXLog "$($windows.Count) program window(s) checked, $($lost.Count) outside the screen."
if (-not $lost.Count) { exit 0 }

$moved = 0
$failed = 0
$index = 0
foreach ($window in $lost) {
	$target = Get-SelfXWindowTarget -Rect $window.Rect -WorkArea $workArea -Index $index
	if (Move-SelfXWindow -Window $window -Target $target) { $moved++; $index++ } else { $failed++ }
}
Write-SelfXLog "Finished: $moved window(s) moved, $failed window(s) could not be moved (for example programs with higher rights)."
if ($failed) { exit 1 }
exit 0
