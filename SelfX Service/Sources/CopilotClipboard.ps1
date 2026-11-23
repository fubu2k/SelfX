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

.NOTES
    Name    : CopilotClipboard.ps1
    Package : SelfX Service
    Context : GUI helper (signed-in user, STA thread of the window), functions only
    Version : 2.8.16

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.16   2026-11-23  fubu2k               Initial version: text for Copilot Chat is kept out of the clipboard history and the cloud clipboard
#>

$script:SelfXClipboardPrivateFormats = @(
	@('CanIncludeInClipboardHistory', 0),
	@('CanUploadToCloudClipboard', 0),
	@('ExcludeClipboardContentFromMonitorProcessing', 1)
)

function New-SelfXClipboardDataObject {
	<#
	.SYNOPSIS
	    Data object with the text and the formats that keep it out of the history and the cloud clipboard.
	    Does not touch the clipboard.
	#>
	param(
		[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
	)
	$data = New-Object System.Windows.DataObject
	$data.SetText($Text, [System.Windows.TextDataFormat]::UnicodeText)
	foreach ($pair in $script:SelfXClipboardPrivateFormats) {
		# A stream is stored as the raw bytes (no serialisation); Windows expects a DWORD.
		$bytes = [byte[]][BitConverter]::GetBytes([int]$pair[1])
		$data.SetData([string]$pair[0], (New-Object System.IO.MemoryStream -ArgumentList (, $bytes)))
	}
	return , $data
}

function Set-SelfXClipboardPrivate {
	<#
	.SYNOPSIS
	    Copies the text to the clipboard. Returns $true if it was copied with the formats that keep it out of the
	    history and the cloud clipboard, $false if only plain text could be copied.
	#>
	param(
		[Parameter(Mandatory = $true)][string]$Text
	)
	try {
		[System.Windows.Clipboard]::SetDataObject((New-SelfXClipboardDataObject -Text $Text), $true)
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
