<#
.SYNOPSIS
    Tests the clipboard helper of the Copilot Chat hand-over (Sources\CopilotClipboard.ps1) and its use in the window.

.DESCRIPTION
    Builds data objects in memory, runs the clearing logic with replaced clipboard access and reads static checks of
    Self_X.ps1. The test never touches the real clipboard.

.NOTES
    Name    : Test-CopilotClipboard.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.17

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.16   2026-11-23  fubu2k               Initial version
    2.8.17   2026-11-23  fubu2k               Marker, clearing logic with the retry on a locked clipboard, seconds setting, configuration, texts, wiring in the window
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ($Actual -ne $Expected) { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}
$sources = Join-Path $PSScriptRoot 'Sources'
$helperPath = Join-Path $sources 'CopilotClipboard.ps1'
$helperCode = [IO.File]::ReadAllText($helperPath)
$ui = [IO.File]::ReadAllText((Join-Path $sources 'Self_X.ps1'))

. $helperPath

# --- Time setting ------------------------------------------------------------------------------------------------
foreach ($valid in '30', '180', '600', ' 45 ') {
	$r = ConvertTo-SelfXClipboardClearSeconds $valid
	Assert-Equal $r.Valid $true "seconds: '$valid' is valid"
	Assert-Equal $r.Seconds ([int]$valid.Trim()) "seconds: '$valid' is used"
}
foreach ($invalid in '', '   ', '29', '601', '0', '-5', 'abc', '1e3', '180.5', '99999', '18 0') {
	$r = ConvertTo-SelfXClipboardClearSeconds $invalid
	Assert-Equal $r.Valid $false "seconds: '$invalid' is not valid"
	Assert-Equal $r.Seconds 180 "seconds: '$invalid' gives the default of 180"
}

# --- Clearing logic with replaced clipboard access -------------------------------------------------------------
$script:cleared = 0
$script:reads = 0
$clearOk = { $script:cleared++ }
Assert-Equal (Clear-SelfXClipboardIfMarker -Marker 'abc' -GetMarker { 'abc' } -Clear $clearOk) 'Cleared' 'clear: own marker on the clipboard -> cleared'
Assert-Equal $script:cleared 1 'clear: the clipboard was emptied once'
$script:cleared = 0
Assert-Equal (Clear-SelfXClipboardIfMarker -Marker 'abc' -GetMarker { 'other' } -Clear $clearOk) 'Changed' 'clear: other marker -> nothing changed'
Assert-Equal (Clear-SelfXClipboardIfMarker -Marker 'abc' -GetMarker { $null } -Clear $clearOk) 'Changed' 'clear: no marker (the user copied something else) -> nothing changed'
Assert-Equal (Clear-SelfXClipboardIfMarker -Marker '' -GetMarker { '' } -Clear $clearOk) 'Changed' 'clear: empty marker is never cleared'
Assert-Equal $script:cleared 0 'clear: the clipboard was not emptied in the three cases above'
$flaky = { $script:reads++; if ($script:reads -lt 3) { throw 'locked' } 'abc' }
Assert-Equal (Clear-SelfXClipboardIfMarker -Marker 'abc' -GetMarker $flaky -Clear $clearOk -Retries 5 -DelayMilliseconds 0) 'Cleared' 'clear: a locked clipboard is retried'
Assert-Equal $script:reads 3 'clear: two failed reads and one good read'
Assert-Equal (Clear-SelfXClipboardIfMarker -Marker 'abc' -GetMarker { throw 'locked' } -Clear $clearOk -Retries 3 -DelayMilliseconds 0) 'Error' 'clear: clipboard locked for all tries -> Error'
Assert-Equal (Clear-SelfXClipboardIfMarker -Marker 'abc' -GetMarker { 'abc' } -Clear { throw 'locked' } -Retries 3 -DelayMilliseconds 0) 'Error' 'clear: emptying fails for all tries -> Error'

# --- Data object (needs the WPF assemblies, Windows only) ------------------------------------------------------
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
	[Console]::Out.WriteLine('Test-CopilotClipboard: data object checks skipped (not Windows).')
}
else {
	Add-Type -AssemblyName PresentationCore, WindowsBase
	function Read-Dword($Data, $Format) {
		$stream = $Data.GetData($Format)
		$bytes = New-Object byte[] 4
		[void]$stream.Seek(0, 'Begin')
		[void]$stream.Read($bytes, 0, 4)
		return [BitConverter]::ToInt32($bytes, 0)
	}
	$text = "Invented text`r`nwith two lines and a umlaut: " + [char]0x00E4
	$data = New-SelfXClipboardDataObject -Text $text
	Assert-Equal ($data -is [System.Windows.DataObject]) $true 'data object: type'
	Assert-Equal $data.GetText([System.Windows.TextDataFormat]::UnicodeText) $text 'data object: the text is the unicode text'
	foreach ($format in 'CanIncludeInClipboardHistory', 'CanUploadToCloudClipboard', 'ExcludeClipboardContentFromMonitorProcessing') {
		Assert-Equal $data.GetDataPresent($format) $true "data object: format $format is present"
	}
	Assert-Equal (Read-Dword $data 'CanIncludeInClipboardHistory') 0 'data object: not in the clipboard history (DWORD 0)'
	Assert-Equal (Read-Dword $data 'CanUploadToCloudClipboard') 0 'data object: not in the cloud clipboard (DWORD 0)'
	Assert-Equal (Read-Dword $data 'ExcludeClipboardContentFromMonitorProcessing') 1 'data object: excluded from clipboard monitors (DWORD 1)'
	Assert-Equal $data.GetDataPresent('SelfX.ClipboardMarker') $false 'data object: no marker without -Marker'
	$marked = New-SelfXClipboardDataObject -Text $text -Marker 'f00dfeed'
	$markerStream = $marked.GetData('SelfX.ClipboardMarker')
	$markerReader = New-Object System.IO.StreamReader -ArgumentList $markerStream, ([Text.Encoding]::UTF8)
	Assert-Equal $markerReader.ReadToEnd() 'f00dfeed' 'data object: the marker is stored as UTF-8 text'
	Assert-Equal $marked.GetText([System.Windows.TextDataFormat]::UnicodeText) $text 'data object: the text is the same with a marker'
	Assert-Equal (Read-Dword $marked 'CanIncludeInClipboardHistory') 0 'data object: the marker does not change the history format'
	$empty = New-SelfXClipboardDataObject -Text ''
	Assert-Equal ($empty -is [System.Windows.DataObject]) $true 'data object: empty text is accepted'
}

# --- Static checks -----------------------------------------------------------------------------------------------
foreach ($pattern in @('GetText', 'ContainsText', 'Get-Clipboard', 'GetClipboard', 'Clipboard\]::GetDataObject')) {
	Assert-Equal ($helperCode -match $pattern) $false "CopilotClipboard.ps1 does not read the text of the clipboard ($pattern)"
}
foreach ($pattern in @('Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Invoke-Expression', 'Set-Content', 'Out-File', 'Add-Content', 'Add-Type', 'Write-SelfXLog "[^"]*\$Text')) {
	Assert-Equal ($helperCode -match $pattern) $false "CopilotClipboard.ps1 does not use $pattern"
}
Assert-Equal ($ui -match '\. "\$Current_Folder\\CopilotClipboard\.ps1"') $true 'window: the helper is loaded'
Assert-Equal ($ui -match '\$Copilot_ClearClipboard = \(Get-SelfXText "Copilot_Clear_Clipboard" "False"\) -eq ''True''') $true 'window: clearing is off by default'
Assert-Equal ($ui -match 'ConvertTo-SelfXClipboardClearSeconds \(Get-SelfXText "Copilot_Clear_Clipboard_Seconds" "180"\)') $true 'window: the seconds setting is checked, default 180'
$start = $ui.IndexOf('Function Show-SelfXCopilotDialog')
$end = $ui.IndexOf('Function Show-SelfXHelpDialog')
Assert-Equal (($start -ge 0) -and ($end -gt $start)) $true 'window: Copilot dialog found'
if (($start -ge 0) -and ($end -gt $start)) {
	$dialog = $ui.Substring($start, $end - $start)
	Assert-Equal ($dialog -match 'Set-SelfXClipboardPrivate -Text \$Text -Marker \$Marker') $true 'window: the text is copied with Set-SelfXClipboardPrivate and the marker'
	Assert-Equal ($dialog -match '\$Marker = If\(\$Copilot_ClearClipboard\) \{ \[guid\]::NewGuid\(\)\.ToString\(''N''\) \} Else \{ '''' \}') $true 'window: a random marker only when clearing is on'
	$timerCalls = [regex]::Matches($dialog, 'Start-SelfXClipboardClearTimer')
	Assert-Equal $timerCalls.Count 1 'window: the timer is started in one place'
	Assert-Equal ($dialog -match 'If\(\$Copilot_ClearClipboard\)\s*\{\s*If\(\$KeptOut\)') $true 'window: the timer is only started with clearing on and a marked copy'
	Assert-Equal ($dialog -match 'Clipboard\]::SetText') $false 'window: the Copilot dialog does not copy plain text to the clipboard directly'
}

# --- Configuration and texts -------------------------------------------------------------------------------------
$config = [xml][IO.File]::ReadAllText((Join-Path $sources 'Tool_Config.xml'))
Assert-Equal "$($config.GUI_Config.Copilot_Clear_Clipboard)" 'False' 'config: clearing is off by default'
Assert-Equal "$($config.GUI_Config.Copilot_Clear_Clipboard_Seconds)" '180' 'config: default of 180 seconds'
Assert-Equal (ConvertTo-SelfXClipboardClearSeconds "$($config.GUI_Config.Copilot_Clear_Clipboard_Seconds)").Valid $true 'config: the default passes the check'
foreach ($culture in 'en', 'de') {
	[xml]$lang = [IO.File]::ReadAllText((Join-Path (Join-Path $sources 'Languages') "$culture.xml"))
	foreach ($key in 'Copilot_Clear_Text', 'Copilot_Cleared_Text') {
		$node = $lang.SelectSingleNode("//UI/$key")
		Assert-Equal (($null -ne $node) -and (-not [string]::IsNullOrWhiteSpace($node.InnerText))) $true "language ${culture}: text $key exists"
		if ($key -eq 'Copilot_Clear_Text' -and $node) { Assert-Equal ($node.InnerText -match '\{0\}') $true "language ${culture}: $key keeps the placeholder {0}" }
	}
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { [Console]::Error.WriteLine($_) }
	[Console]::Out.WriteLine("Test-CopilotClipboard: $($script:errors.Count) of $($script:checks) checks failed.")
	exit 1
}
[Console]::Out.WriteLine("Test-CopilotClipboard: all $($script:checks) checks passed.")
