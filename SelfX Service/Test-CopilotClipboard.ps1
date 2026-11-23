<#
.SYNOPSIS
    Tests the clipboard helper of the Copilot Chat hand-over (Sources\CopilotClipboard.ps1) and its use in the window.

.DESCRIPTION
    Builds data objects in memory and reads static checks of Self_X.ps1. The test never touches the real clipboard.

.NOTES
    Name    : Test-CopilotClipboard.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.16

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.16   2026-11-23  fubu2k               Initial version
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

# --- Data object (needs the WPF assemblies, Windows only) ------------------------------------------------------
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
	[Console]::Out.WriteLine('Test-CopilotClipboard: data object checks skipped (not Windows).')
}
else {
	Add-Type -AssemblyName PresentationCore, WindowsBase
	. $helperPath
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
	$empty = New-SelfXClipboardDataObject -Text ''
	Assert-Equal ($empty -is [System.Windows.DataObject]) $true 'data object: empty text is accepted'
}

# --- Static checks -----------------------------------------------------------------------------------------------
foreach ($pattern in @('Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Invoke-Expression', 'Set-Content', 'Out-File', 'Add-Content', 'Add-Type', 'Write-SelfXLog "[^"]*\$Text')) {
	Assert-Equal ($helperCode -match $pattern) $false "CopilotClipboard.ps1 does not use $pattern"
}
Assert-Equal ($ui -match '\. "\$Current_Folder\\CopilotClipboard\.ps1"') $true 'window: the helper is loaded'
$start = $ui.IndexOf('Function Show-SelfXCopilotDialog')
$end = $ui.IndexOf('Function Show-SelfXHelpDialog')
Assert-Equal (($start -ge 0) -and ($end -gt $start)) $true 'window: Copilot dialog found'
if (($start -ge 0) -and ($end -gt $start)) {
	$dialog = $ui.Substring($start, $end - $start)
	Assert-Equal ($dialog -match 'Set-SelfXClipboardPrivate -Text \$Text') $true 'window: the text is copied with Set-SelfXClipboardPrivate'
	Assert-Equal ($dialog -match 'Clipboard\]::SetText') $false 'window: the Copilot dialog does not copy plain text to the clipboard directly'
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { [Console]::Error.WriteLine($_) }
	[Console]::Out.WriteLine("Test-CopilotClipboard: $($script:errors.Count) of $($script:checks) checks failed.")
	exit 1
}
[Console]::Out.WriteLine("Test-CopilotClipboard: all $($script:checks) checks passed.")
