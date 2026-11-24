<#
.SYNOPSIS
    Tests the decision functions of the window helper (Sources\SelfXWindows.ps1): which windows are lost and where they go.

.DESCRIPTION
    Pure calculations with rectangles; no window is read or moved and no screen is needed. Checked:
      - Test-SelfXWindowLost: windows on a screen, on a second screen, across two screens, on a screen that is gone (left, right,
        below, above), with only a small part of the title bar visible, one screen only, zero size;
      - Get-SelfXWindowTarget: position on the work area (also with a taskbar at the top or the left), offset per window and
        wrap after 8, windows larger than the work area are made smaller, small work area, no result outside the work area.
    The UI Automation part (Get-SelfXTopLevelWindow, Move-SelfXWindow) needs a desktop and is tested by hand (docs: device tests).

.NOTES
    Name    : Test-WindowHelper.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.24

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.24   2026-11-24  fubu2k               Initial version.
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ("$Actual" -cne "$Expected") { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}

. (Join-Path $PSScriptRoot 'Sources\SelfXWindows.ps1')
function Format-Rect($r) { "$($r.Left),$($r.Top),$($r.Width),$($r.Height)" }

$one = @(New-SelfXRect 0 0 1920 1080)
$two = @((New-SelfXRect 0 0 1920 1080), (New-SelfXRect 1920 0 1920 1080))
$left = @((New-SelfXRect -1920 0 1920 1080), (New-SelfXRect 0 0 1920 1080))

# Lost or not
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 100 100 800 600) $one) $false 'On the screen: not lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 2000 100 800 600) $two) $false 'On the second screen: not lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 1500 100 1000 600) $two) $false 'Across two screens: not lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 2000 100 800 600) $one) $true 'Second screen gone (right): lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect -1800 100 800 600) $one) $true 'Second screen gone (left): lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect -1800 100 800 600) $left) $false 'Screen on the left still there: not lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 100 1200 800 600) $one) $true 'Below the screen: lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 100 -700 800 600) $one) $true 'Above the screen: lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 100 -20 800 600) $one) $false 'Title bar partly above the screen but reachable: not lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 1870 100 800 600) $one) $true 'Only 50 pixels of the title bar visible: lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 1870 100 800 600) $two) $false 'Same window with a second screen next to it: not lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 1800 100 800 600) $one) $false '120 pixels of the title bar visible: not lost'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 100 100 0 0) $one) $false 'No size: not judged'
Assert-Equal (Test-SelfXWindowLost (New-SelfXRect 5000 5000 50 20) $one) $true 'Small window far away: lost'

# Target
$work = New-SelfXRect 0 0 1920 1040
Assert-Equal (Format-Rect (Get-SelfXWindowTarget (New-SelfXRect 5000 100 800 600) $work 0)) '40,40,800,600' 'Target: first window'
Assert-Equal (Format-Rect (Get-SelfXWindowTarget (New-SelfXRect 5000 100 800 600) $work 1)) '70,70,800,600' 'Target: second window with offset'
Assert-Equal (Format-Rect (Get-SelfXWindowTarget (New-SelfXRect 5000 100 800 600) $work 8)) '40,40,800,600' 'Target: offset starts again after 8 windows'
Assert-Equal (Format-Rect (Get-SelfXWindowTarget (New-SelfXRect 0 0 3000 2000) $work 0)) '40,40,1840,960' 'Target: window larger than the screen is made smaller'
Assert-Equal (Format-Rect (Get-SelfXWindowTarget (New-SelfXRect 5000 100 800 600) (New-SelfXRect 0 40 1920 1000) 0)) '40,80,800,600' 'Target: taskbar at the top'
Assert-Equal (Format-Rect (Get-SelfXWindowTarget (New-SelfXRect 5000 100 800 600) (New-SelfXRect 60 0 1860 1080) 0)) '100,40,800,600' 'Target: taskbar at the left'
$tiny = New-SelfXRect 0 0 640 480
$target = Get-SelfXWindowTarget (New-SelfXRect 5000 100 1000 900) $tiny 7
Assert-Equal ($target.Left -ge 0 -and $target.Top -ge 0 -and ($target.Left + $target.Width) -le 640 -and ($target.Top + $target.Height) -le 480) $true 'Target: small screen and large offset stay inside the work area'
foreach ($i in 0..20) {
	$t = Get-SelfXWindowTarget (New-SelfXRect 5000 100 1500 800) $work $i
	Assert-Equal ($t.Left -ge 0 -and $t.Top -ge 0 -and ($t.Left + $t.Width) -le 1920 -and ($t.Top + $t.Height) -le 1040) $true "Target: window $i inside the work area"
}
# A moved window is never lost again.
foreach ($i in 0..9) {
	$t = Get-SelfXWindowTarget (New-SelfXRect 5000 100 800 600) $work $i
	Assert-Equal (Test-SelfXWindowLost $t $one) $false "Target: window $i is reachable after the move"
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
