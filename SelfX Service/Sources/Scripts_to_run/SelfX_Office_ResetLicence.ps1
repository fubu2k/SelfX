<#
.SYNOPSIS
    Reset the Office license tokens of the signed-in user (Office asks for the sign-in again).

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Closes the Office apps of the user's own session (first by asking
    them to close, after 10 seconds by ending them), waits up to 30 seconds and then removes only the contents of the
    license token folders of the user (SelfXOffice.ps1, Get-SelfXOfficeLicenseFolder):
      %LOCALAPPDATA%\Microsoft\Office\Licenses
      %LOCALAPPDATA%\Microsoft\Office\<version>\Licensing   (every version folder that exists, e.g. 16.0)
    The folders are independent of the Office version, the bitness (32 or 64 bit) and the installation type.
    Nothing else is changed: no registry value (identity and sign-in data stay), no document, no Office setting,
    no program file. Office creates new tokens and asks the user to sign in at the next start.
    Teams is not closed. Only processes of the own Windows session are closed (multi-user devices).
    Links (junctions, symbolic links) are never followed: when a folder or an item inside is a link, it is skipped and
    logged, so nothing outside the license folders can be deleted. When an Office app does not close, nothing is
    deleted. Does not start the Office apps again and does not restart Windows.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = done (also when no license token folder exists); exit 1 = an Office app did not close or an item could
    not be removed.

.NOTES
    Name    : SelfX_Office_ResetLicence.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.4

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.8.4    2026-11-23  fubu2k               Token folders independent of the Office version (Licenses and every <version>\Licensing),
                                              only the contents are removed, links are not followed, own session only,
                                              graceful close with timeout, Teams not closed, logging and exit code
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

$officeHelper = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXOffice.ps1'
if (-not (Test-Path -LiteralPath $officeHelper -PathType Leaf)) { throw 'SelfXOffice.ps1 is missing in the installation folder.' }
. $officeHelper

# Office apps that use the license tokens (Teams is not one of them).
$officeProcesses = @('WINWORD', 'EXCEL', 'POWERPNT', 'OUTLOOK', 'MSACCESS', 'ONENOTE', 'MSPUB', 'VISIO', 'WINPROJ', 'LYNC')

function Test-PlainItem {
	# $true when the item exists and is not a link (junction, symbolic link).
	param([string]$Path)
	$item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
	return [bool]($item -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))
}

function Test-FolderChainPlain {
	# $true when no part of the path from LOCALAPPDATA down to the folder is a link.
	param([string]$Folder)
	$current = $Folder
	$base = "$env:LOCALAPPDATA".TrimEnd('\')
	while ($current -and $current.Length -gt $base.Length) {
		if (-not (Test-PlainItem -Path $current)) { return $false }
		$current = Split-Path -Parent $current
	}
	return $true
}

# Close the Office apps of the own session first so that the tokens are not in use.
$running = @(Get-SelfXOwnSessionProcess -Name $officeProcesses)
if ($running.Count) {
	Write-SelfXLog "Closing $($running.Count) Office process(es): $(($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', ')."
	if (-not (Close-SelfXOwnSessionProcess -Name $officeProcesses)) { throw 'An Office app is still running after 40 seconds; the license tokens were not removed.' }
} else {
	Write-SelfXLog 'No Office app is running.'
}

$folders = @(Get-SelfXOfficeLicenseFolder)
if (-not $folders.Count) {
	Write-SelfXLog 'No license token folder found, nothing to remove.'
	exit 0
}

$failed = 0
$removed = 0
foreach ($folder in $folders) {
	$label = $folder.Substring("$env:LOCALAPPDATA".TrimEnd('\').Length + 1)
	if (-not (Test-FolderChainPlain -Folder $folder)) {
		$failed++
		Write-SelfXLog "Skipped $label : the folder or one of its parent folders is a link, not a normal folder." Warning
		continue
	}
	foreach ($entry in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue)) {
		# A link inside is never followed or deleted; a folder that contains a link somewhere is skipped as a whole.
		$hasLink = [bool]($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)
		if (-not $hasLink -and $entry.PSIsContainer) {
			$hasLink = [bool](Get-ChildItem -LiteralPath $entry.FullName -Force -Recurse -Attributes ReparsePoint -ErrorAction SilentlyContinue | Select-Object -First 1)
		}
		if ($hasLink) {
			$failed++
			Write-SelfXLog "Skipped $label\$($entry.Name) : it is or contains a link." Warning
			continue
		}
		try {
			Remove-Item -LiteralPath $entry.FullName -Force -Recurse -ErrorAction Stop
			$removed++
		} catch {
			$failed++
			Write-SelfXLog "Could not remove $label\$($entry.Name) : $($_.Exception.Message)" Warning
		}
	}
	Write-SelfXLog "Processed $label."
}
Write-SelfXLog "Finished: $removed item(s) removed, $failed item(s) not removed."
if ($failed) { exit 1 }
exit 0
