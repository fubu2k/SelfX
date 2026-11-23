<#
.SYNOPSIS
    Puts the text for Copilot Chat on the clipboard so that Windows keeps it out of the clipboard history and the
    cloud clipboard.

.DESCRIPTION
    New-SelfXClipboardDataObject builds a data object with the text and the three formats that Windows reads when it
    decides what to keep:
      - CanIncludeInClipboardHistory (DWORD 0)                 : not in the clipboard history (Win+V)
      - CanUploadToCloudClipboard (DWORD 0)                    : not synchronised to other devices
      - ExcludeClipboardContentFromMonitorProcessing (DWORD 1) : clipboard monitors that honour it skip the entry
    Set-SelfXClipboardPrivate puts that object on the clipboard. The data is copied to the clipboard (it stays there
    after SelfX has been closed). The formats are a request: they do not stop an app that reads the clipboard while
    the text is on it, and they do not empty the clipboard.

    If the object cannot be placed, the text is copied as plain text and a warning is logged, so that the hand-over
    still works. The log never contains the text.

    Optional clearing (Copilot_Clear_Clipboard): the data object also carries a marker format with a random value
    (one per copy). Start-SelfXClipboardClearTimer starts a timer in the window. When it ends, Clear-SelfXClipboardIfMarker
    empties the clipboard only if the marker of this copy is still on it. If the user has copied something else in the
    meantime, nothing is changed. Only the marker is read, never the text or any other content of the clipboard.
    The timer lives as long as the SelfX window process: when SelfX is closed earlier, the text stays on the clipboard.

.NOTES
    Name    : CopilotClipboard.ps1
    Package : SelfX Service
    Context : GUI helper (signed-in user, STA thread of the window), functions only
    Version : 2.8.17

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.16   2026-11-23  fubu2k               Initial version: text for Copilot Chat is kept out of the clipboard history and the cloud clipboard
    2.8.17   2026-11-23  fubu2k               Optional clearing of the clipboard after a time (marker format, timer, ConvertTo-SelfXClipboardClearSeconds); an empty marker is accepted and never cleared
#>

$script:SelfXClipboardPrivateFormats = @(
	@('CanIncludeInClipboardHistory', 0),
	@('CanUploadToCloudClipboard', 0),
	@('ExcludeClipboardContentFromMonitorProcessing', 1)
)
$script:SelfXClipboardMarkerFormat = 'SelfX.ClipboardMarker'
$script:SelfXClipboardTimer = $null

function New-SelfXClipboardDataObject {
	<#
	.SYNOPSIS
	    Data object with the text and the formats that keep it out of the history and the cloud clipboard.
	    Does not touch the clipboard.
	#>
	param(
		[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
		# Random value that identifies this copy (see Clear-SelfXClipboardIfMarker). Empty = no marker.
		[string]$Marker = ''
	)
	$data = New-Object System.Windows.DataObject
	$data.SetText($Text, [System.Windows.TextDataFormat]::UnicodeText)
	foreach ($pair in $script:SelfXClipboardPrivateFormats) {
		# A stream is stored as the raw bytes (no serialisation); Windows expects a DWORD.
		$bytes = [byte[]][BitConverter]::GetBytes([int]$pair[1])
		$data.SetData([string]$pair[0], (New-Object System.IO.MemoryStream -ArgumentList (, $bytes)))
	}
	if (-not [string]::IsNullOrEmpty($Marker)) {
		$markerBytes = [byte[]][Text.Encoding]::UTF8.GetBytes($Marker)
		$data.SetData($script:SelfXClipboardMarkerFormat, (New-Object System.IO.MemoryStream -ArgumentList (, $markerBytes)))
	}
	return , $data
}

function Set-SelfXClipboardPrivate {
	<#
	.SYNOPSIS
	    Copies the text to the clipboard. Returns $true if it was copied with the formats that keep it out of the
	    history and the cloud clipboard (and with the marker, if one was given), $false if only plain text could be
	    copied (no marker on the clipboard then).
	#>
	param(
		[Parameter(Mandatory = $true)][string]$Text,
		[string]$Marker = ''
	)
	try {
		[System.Windows.Clipboard]::SetDataObject((New-SelfXClipboardDataObject -Text $Text -Marker $Marker), $true)
		return $true
	}
	catch {
		if (Get-Command Write-SelfXLog -ErrorAction SilentlyContinue) {
			Write-SelfXLog "Clipboard: the entry could not be kept out of the clipboard history ($($_.Exception.GetType().Name)); the text is copied as plain text." 'Warning'
		}
		[System.Windows.Clipboard]::SetText($Text)
		return $false
	}
}

function ConvertTo-SelfXClipboardClearSeconds {
	<#
	.SYNOPSIS
	    Time after which the clipboard is emptied (Copilot_Clear_Clipboard_Seconds): a whole number from 30 to 600.
	    Anything else gives the default of 180 seconds and Valid = $false (the caller logs a warning).
	#>
	param(
		[string]$Value = ''
	)
	$default = 180
	$number = 0
	if (-not [string]::IsNullOrWhiteSpace($Value) -and $Value.Trim() -match '^[0-9]{1,4}$' -and [int]::TryParse($Value.Trim(), [ref]$number) -and $number -ge 30 -and $number -le 600) {
		return [pscustomobject]@{ Seconds = $number; Valid = $true }
	}
	return [pscustomobject]@{ Seconds = $default; Valid = $false }
}

function Get-SelfXClipboardMarker {
	<#
	.SYNOPSIS
	    The marker of the data on the clipboard, or $null if there is none. Reads only the marker format.
	#>
	$value = [System.Windows.Clipboard]::GetData($script:SelfXClipboardMarkerFormat)
	if ($value -is [System.IO.Stream]) {
		$reader = New-Object System.IO.StreamReader -ArgumentList $value, ([Text.Encoding]::UTF8)
		try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
	}
	if ($value -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($value) }
	return $null
}

function Clear-SelfXClipboardIfMarker {
	<#
	.SYNOPSIS
	    Empties the clipboard if the marker of this copy is still on it. Returns 'Cleared', 'Changed' (the user has
	    copied something else: nothing is changed) or 'Error' (the clipboard stayed locked by another program).
	    -GetMarker and -Clear can be replaced (tests); by default they use the clipboard.
	#>
	param(
		[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Marker,
		[scriptblock]$GetMarker = { Get-SelfXClipboardMarker },
		[scriptblock]$Clear = { [System.Windows.Clipboard]::Clear() },
		[int]$Retries = 5,
		[int]$DelayMilliseconds = 100
	)
	# An empty marker identifies nothing: never empty the clipboard for it.
	if ([string]::IsNullOrEmpty($Marker)) { return 'Changed' }
	for ($attempt = 1; $attempt -le $Retries; $attempt++) {
		try {
			$current = & $GetMarker
			if ($current -ne $Marker) { return 'Changed' }
			& $Clear
			return 'Cleared'
		}
		catch {
			# Another program holds the clipboard for a moment (CLIPBRD_E_CANT_OPEN): try again.
			if ($attempt -lt $Retries) { Start-Sleep -Milliseconds $DelayMilliseconds }
		}
	}
	return 'Error'
}

function Start-SelfXClipboardClearTimer {
	<#
	.SYNOPSIS
	    Starts the timer of the window that empties the clipboard after -Seconds if the marker is still on it. A
	    running timer of an earlier copy is stopped. -OnDone gets the result ('Cleared', 'Changed', 'Error').
	#>
	param(
		[Parameter(Mandatory = $true)][string]$Marker,
		[Parameter(Mandatory = $true)][int]$Seconds,
		[scriptblock]$OnDone = $null
	)
	Stop-SelfXClipboardClearTimer
	$timer = New-Object System.Windows.Threading.DispatcherTimer
	$timer.Interval = [TimeSpan]::FromSeconds($Seconds)
	$timer.Tag = @{ Marker = $Marker; OnDone = $OnDone }
	$timer.Add_Tick({
		param($Sender, $EventArgs)
		$Sender.Stop()
		$state = $Sender.Tag
		$result = Clear-SelfXClipboardIfMarker -Marker $state.Marker
		# The log names only the result, never the text.
		if (Get-Command Write-SelfXLog -ErrorAction SilentlyContinue) {
			Write-SelfXLog "Clipboard: Copilot text, result of the timer: $result" $(if ($result -eq 'Error') { 'Warning' } else { 'Info' })
		}
		if ($state.OnDone) { try { & $state.OnDone $result } catch { } }
	})
	$script:SelfXClipboardTimer = $timer
	$timer.Start()
}

function Stop-SelfXClipboardClearTimer {
	<#
	.SYNOPSIS
	    Stops the running timer, if there is one. The clipboard is not changed.
	#>
	if ($script:SelfXClipboardTimer) {
		$script:SelfXClipboardTimer.Stop()
		$script:SelfXClipboardTimer = $null
	}
}
