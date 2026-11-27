<#
.SYNOPSIS
    Loads SelfXAudio.dll (Core Audio, action "No sound") only after its SHA256 was checked.

.DESCRIPTION
    Dot-sourced by SelfX_Audio_Restore.ps1 (PowerShell 7, user context). Install.ps1 checks the library against the manifest
    of the package and installs it into the folder Audio of the install folder (writable only by administrators). This helper
    adds the check at the moment of loading, in the same way as SelfXWinRT.ps1 (defense in depth):
      - SelfX.Code.json of the install folder lists the library as "Audio/SelfXAudio.dll" with its SHA256 (written at package
        build). The file list, the folder Audio and the DLL must not be a link (junction, symbolic link).
      - Audio must contain exactly this one file. Anything else (changed, missing, additional file, folder, link, missing or
        invalid list) = nothing is loaded.
      - The DLL is opened for reading with the sharing mode "read only", hashed from that open handle and the handle is kept
        open as long as the process lives, so the file that was checked is the file that is loaded.
    Errors throw with a short text (file name, no path).

.NOTES
    Name    : SelfXAudio.ps1
    Package : SelfX Service
    Context : User, dot-sourced, PowerShell 7
    Version : 2.9.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.18   2026-11-23  fubu2k               Initial version (hash check before SelfXAudio.dll is loaded).
    2.9.0    2026-11-27  fubu2k               The hash is read from SelfX.Code.json (the library is code), no longer from SelfX.Files.json.
#>

# Open file handle of the checked DLL; it stays open until the process ends (see above).
if ($null -eq $Script:SelfXAudioHandle) { $Script:SelfXAudioHandle = $null }

# SHA256 of Audio/SelfXAudio.dll from SelfX.Code.json of the install folder. Throws when the list is missing, too large, a link,
# invalid or does not list the library.
function Get-SelfXAudioExpectedHash {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$listPath = Join-Path $InstallFolder 'SelfX.Code.json'
	$list = Get-Item -LiteralPath $listPath -Force -ErrorAction SilentlyContinue
	if (-not $list -or $list.PSIsContainer) { throw 'SelfX.Code.json is missing.' }
	if ($list.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'SelfX.Code.json is a link.' }
	if ($list.Length -gt 1048576) { throw 'SelfX.Code.json is too large.' }
	try { $manifest = [IO.File]::ReadAllText($listPath) | ConvertFrom-Json -ErrorAction Stop }
	catch { throw 'SelfX.Code.json is not valid JSON.' }
	if (-not $manifest -or "$($manifest.ManifestVersion)" -ne '1' -or -not $manifest.Files) { throw 'SelfX.Code.json has an unknown format.' }
	$property = $manifest.Files.PSObject.Properties['Audio/SelfXAudio.dll']
	if (-not $property) { throw 'SelfXAudio.dll is not listed in SelfX.Code.json.' }
	$hash = "$($property.Value)"
	if ($hash -notmatch '^[0-9A-Fa-f]{64}$') { throw 'SelfX.Code.json has an invalid hash for Audio/SelfXAudio.dll.' }
	return $hash.ToUpperInvariant()
}

# Checks the folder Audio and the DLL and keeps the DLL open (read sharing only). Throws when anything differs.
function Test-SelfXAudioFiles {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$expected = Get-SelfXAudioExpectedHash -InstallFolder $InstallFolder
	$folderPath = Join-Path $InstallFolder 'Audio'
	$folder = Get-Item -LiteralPath $folderPath -Force -ErrorAction SilentlyContinue
	if (-not $folder -or -not $folder.PSIsContainer) { throw 'The folder Audio is missing.' }
	if ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The folder Audio is a link.' }
	$entries = @(Get-ChildItem -LiteralPath $folderPath -Force)
	foreach ($entry in $entries) {
		if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Audio\$($entry.Name) is a link." }
		if ($entry.PSIsContainer) { throw "Audio\$($entry.Name) is a folder." }
		if ($entry.Name -ine 'SelfXAudio.dll') { throw "Audio\$($entry.Name) is not expected." }
	}
	if ($entries.Count -ne 1) { throw 'Audio\SelfXAudio.dll is missing.' }
	$stream = $null
	try {
		$stream = New-Object IO.FileStream($entries[0].FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
		$actual = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($stream)).Replace('-', '')
		if ($actual -ne $expected) { throw 'Audio\SelfXAudio.dll does not match SelfX.Code.json.' }
	}
	catch {
		if ($stream) { $stream.Dispose() }
		$cause = if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }
		if ($cause -is [IO.IOException] -or $cause -is [UnauthorizedAccessException]) { throw "Audio\SelfXAudio.dll cannot be opened for the check ($($cause.GetType().Name))." }
		throw
	}
	$previous = $Script:SelfXAudioHandle
	$Script:SelfXAudioHandle = $stream
	if ($previous) { $previous.Dispose() }
}

# Checks the file and then loads SelfXAudio.dll. Afterwards [SelfX.SelfXAudio]::Restore(<minimum percent>) is available.
# Throws (nothing is loaded) when the check fails.
function Import-SelfXAudio {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$InstallFolder = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	Test-SelfXAudioFiles -InstallFolder $InstallFolder
	[void][Reflection.Assembly]::LoadFrom((Join-Path (Join-Path $InstallFolder 'Audio') 'SelfXAudio.dll'))
}
