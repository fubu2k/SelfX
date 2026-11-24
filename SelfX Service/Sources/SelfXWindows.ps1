<#
.SYNOPSIS
    Helper functions for the action "A program window is outside the screen": decide which windows are lost and where they go.

.DESCRIPTION
    Dot-sourced by SelfX_Device_BringWindowsBack.ps1 (user context). Nothing is read from or changed on the device when
    the file is loaded.

    The decision functions are pure (rectangles in, rectangle out) so that they can be tested without a screen:
      Test-SelfXWindowLost   $true when the title bar of the window cannot be reached on any screen: less than
                             MinWidth x MinHeight pixels of the title strip (top 30 pixels) lie on a screen, or the
                             whole window has less than MinWidth x 40 pixels on screens.
      Get-SelfXWindowTarget  new position and size on the work area of the primary screen. A window that is larger
                             than the work area is made smaller; several windows are placed with an offset so that
                             they do not cover each other completely.
    Rectangles are objects with Left, Top, Width and Height (integers, pixels of the same coordinate system).

    Get-SelfXTopLevelWindow reads the top-level windows of the own Windows session through Microsoft UI Automation
    (no code is compiled, no native call is made). Taskbar, desktop and other shell windows, windows without a title,
    minimized and maximized windows are not returned (Windows places maximized windows on an existing screen itself).
    Move-SelfXWindow moves and, if needed, resizes one window with the window pattern of UI Automation. Programs that
    run with higher rights than the user cannot be moved; the function returns $false for them.
    Nothing is closed, ended or saved, and window titles are never returned to the caller for logging.

.NOTES
    Name    : SelfXWindows.ps1
    Package : SelfX Service
    Context : Dot-sourced by scripts in Scripts_to_run (user context); also loaded by tests
    Version : 2.8.24

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.24   2026-11-24  fubu2k               Initial version.
#>

function New-SelfXRect {
	param([int]$Left, [int]$Top, [int]$Width, [int]$Height)
	[pscustomobject]@{ Left = $Left; Top = $Top; Width = $Width; Height = $Height }
}

function Get-SelfXRectOverlap {
	# Width and height of the overlap of two rectangles (0 when they do not touch).
	param([Parameter(Mandatory = $true)]$A, [Parameter(Mandatory = $true)]$B)
	$width = [Math]::Min($A.Left + $A.Width, $B.Left + $B.Width) - [Math]::Max($A.Left, $B.Left)
	$height = [Math]::Min($A.Top + $A.Height, $B.Top + $B.Height) - [Math]::Max($A.Top, $B.Top)
	[pscustomobject]@{ Width = [Math]::Max(0, $width); Height = [Math]::Max(0, $height) }
}

function Test-SelfXWindowLost {
	# $true when the user cannot reach the title bar of the window on any of the screens.
	param(
		[Parameter(Mandatory = $true)]$Rect,
		[Parameter(Mandatory = $true)][object[]]$Screens,
		[int]$MinWidth = 100,
		[int]$TitleHeight = 30,
		[int]$MinTitleVisible = 10
	)
	if ($Rect.Width -le 0 -or $Rect.Height -le 0) { return $false }   # no usable size: not judged
	$strip = New-SelfXRect -Left $Rect.Left -Top $Rect.Top -Width $Rect.Width -Height ([Math]::Min($TitleHeight, $Rect.Height))
	foreach ($screen in $Screens) {
		$title = Get-SelfXRectOverlap -A $strip -B $screen
		if ($title.Width -ge $MinWidth -and $title.Height -ge $MinTitleVisible) { return $false }
	}
	return $true
}

function Get-SelfXWindowTarget {
	# New rectangle on the work area of the primary screen. Index (0, 1, 2 ...) shifts the window by 30 pixels per step
	# (back to the start after 8 steps) so that several moved windows stay distinguishable.
	param(
		[Parameter(Mandatory = $true)]$Rect,
		[Parameter(Mandatory = $true)]$WorkArea,
		[int]$Index = 0
	)
	$margin = 40
	$offset = 30 * ($Index % 8)
	# Keep the size; only a window that is larger than the work area (minus the margins) is made smaller.
	$width = [Math]::Min($Rect.Width, $WorkArea.Width - 2 * $margin)
	$height = [Math]::Min($Rect.Height, $WorkArea.Height - 2 * $margin)
	$width = [Math]::Max($width, [Math]::Min(200, $WorkArea.Width))
	$height = [Math]::Max($height, [Math]::Min(150, $WorkArea.Height))
	$left = $WorkArea.Left + $margin + $offset
	$top = $WorkArea.Top + $margin + $offset
	# Stay inside the work area also with the offset.
	if ($left + $width -gt $WorkArea.Left + $WorkArea.Width) { $left = $WorkArea.Left + $WorkArea.Width - $width }
	if ($top + $height -gt $WorkArea.Top + $WorkArea.Height) { $top = $WorkArea.Top + $WorkArea.Height - $height }
	New-SelfXRect -Left ([Math]::Max($WorkArea.Left, $left)) -Top ([Math]::Max($WorkArea.Top, $top)) -Width $width -Height $height
}

# Shell windows that are not program windows (taskbar of every screen, desktop, notification overflow).
$Script:SelfXShellWindowClasses = @('Shell_TrayWnd', 'Shell_SecondaryTrayWnd', 'Progman', 'WorkerW', 'NotifyIconOverflowWindow',
	'TopLevelWindowForOverflowXamlIsland', 'XamlExplorerHostIslandWindow', 'Windows.UI.Core.CoreWindow')

function Get-SelfXTopLevelWindow {
	# Top-level program windows of the own session: objects with Element (UI Automation), ProcessId and Rect (pixels).
	# Minimized and maximized windows, windows without a title and shell windows are left out.
	Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
	$root = [System.Windows.Automation.AutomationElement]::RootElement
	$children = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
	foreach ($element in $children) {
		try {
			$current = $element.Current
			if ($current.ControlType -ne [System.Windows.Automation.ControlType]::Window) { continue }
			if ($Script:SelfXShellWindowClasses -contains $current.ClassName) { continue }
			if ([string]::IsNullOrWhiteSpace($current.Name)) { continue }
			$pattern = $null
			if (-not $element.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$pattern)) { continue }
			$state = $pattern.Current.WindowVisualState
			if ($state -ne [System.Windows.Automation.WindowVisualState]::Normal) { continue }
			$box = $current.BoundingRectangle
			if ($box.IsEmpty -or [double]::IsInfinity($box.Width)) { continue }
			[pscustomobject]@{
				Element   = $element
				ProcessId = $current.ProcessId
				Rect      = New-SelfXRect -Left ([int]$box.Left) -Top ([int]$box.Top) -Width ([int]$box.Width) -Height ([int]$box.Height)
			}
		} catch { continue }   # the window closed while it was read
	}
}

function Move-SelfXWindow {
	# Moves (and if needed resizes) the window. Returns $true when it was moved, $false when Windows refused (for example
	# a program with higher rights than the user).
	param([Parameter(Mandatory = $true)]$Window, [Parameter(Mandatory = $true)]$Target)
	try {
		$pattern = $null
		if (-not $Window.Element.TryGetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern, [ref]$pattern)) { return $false }
		if (-not $pattern.Current.CanMove) { return $false }
		if ($pattern.Current.CanResize -and ($Target.Width -ne $Window.Rect.Width -or $Target.Height -ne $Window.Rect.Height)) {
			$pattern.Resize([double]$Target.Width, [double]$Target.Height)
		}
		$pattern.Move([double]$Target.Left, [double]$Target.Top)
		return $true
	} catch { return $false }
}
