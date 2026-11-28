<#
.SYNOPSIS
    Loads the WinRT libraries of SelfX (Windows Update orchestrator) only after their SHA256 was checked.

.DESCRIPTION
    Dot-sourced by HealthStatus.ps1 and SelfX_Updates_Install.ps1. PowerShell 7 loads SelfXWinRT.dll and the Windows SDK
    projection DLLs from the folder WinRT of the install folder. Install.ps1 checks them against the manifest of the package
    and the service checks the file list before it starts a SYSTEM script. This helper adds the check at the moment of
    loading (defense in depth):
      - SelfX.Code.json of the install folder lists every DLL of WinRT as "WinRT/<name>" with its SHA256 (written at package
        build). The file list, the folder WinRT and each DLL must not be a link (junction, symbolic link).
      - Every *.dll in WinRT must be listed, every listed DLL must exist and match its SHA256, and SelfXWinRT.dll must be
        listed. Anything else (changed, missing, additional, unlisted, link, missing or invalid list) = nothing is loaded.
      - Each DLL is opened for reading with the sharing mode "read only", hashed from that open handle and the handle is kept
        open as long as the process lives. While it is open nobody can write to or replace the file, so the file that was
        checked is the file that is loaded (no gap between check and load). Dependencies of SelfXWinRT.dll that the runtime
        resolves later in the same folder are covered the same way.
    The folder WinRT is only writable by administrators (ACL of the install folder). The check does not protect against an
    administrator who changes the DLL and the file list together; it detects changes by processes with write access, damaged
    installations and DLLs that were added later. Nothing is signed; see docs\Configuration.md.
    Errors throw with a short text (file name, no path); callers treat them as "orchestrator API not available".

.NOTES
    Name    : SelfXWinRT.ps1
    Package : SelfX Service
    Context : User (status checks) and System (service actions), dot-sourced, PowerShell 7
    Version : 2.9.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.14   2026-11-23  fubu2k               Initial version.
    2.9.0    2026-11-27  fubu2k               The hashes are read from SelfX.Code.json (the libraries are code), no longer from SelfX.Files.json.
    3.1.0    2026-11-28  fubu2k               Import-SelfXWinRTProjection: after the same check also loads the Windows SDK projection (WinRT.Runtime.dll,
                                              Microsoft.Windows.SDK.NET.dll), so a caller can use a WinRT type directly (UserName.ps1)
#>

# Open file handles of the checked DLLs; they stay open until the process ends (see above).
if ($null -eq $Script:SelfXWinRTHandles) { $Script:SelfXWinRTHandles = New-Object System.Collections.Generic.List[IO.FileStream] }

# Reads the SHA256 of the WinRT DLLs from SelfX.Code.json of the install folder. Returns a hashtable
# (lower case file name -> upper case SHA256). Throws when the list is missing, too large, a link or invalid.
function Get-SelfXWinRTExpectedHashes {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$listPath = Join-Path $InstallFolder 'SelfX.Code.json'
	$list = Get-Item -LiteralPath $listPath -Force -ErrorAction SilentlyContinue
	if (-not $list -or $list.PSIsContainer) { throw 'SelfX.Code.json is missing.' }
	if ($list.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'SelfX.Code.json is a link.' }
	if ($list.Length -gt 1048576) { throw 'SelfX.Code.json is too large.' }
	try { $manifest = [IO.File]::ReadAllText($listPath) | ConvertFrom-Json -ErrorAction Stop }
	catch { throw 'SelfX.Code.json is not valid JSON.' }
	if (-not $manifest -or "$($manifest.ManifestVersion)" -ne '1' -or -not $manifest.Files) { throw 'SelfX.Code.json has an unknown format.' }
	$expected = @{}
	foreach ($property in @($manifest.Files.PSObject.Properties)) {
		if ($property.Name -match '^WinRT/([A-Za-z0-9._-]+\.dll)$') { $dllName = $Matches[1].ToLowerInvariant() } else { continue }
		$hash = "$($property.Value)"
		if ($hash -notmatch '^[0-9A-Fa-f]{64}$') { throw "SelfX.Code.json has an invalid hash for $($property.Name)." }
		$expected[$dllName] = $hash.ToUpperInvariant()
	}
	if (-not $expected.ContainsKey('selfxwinrt.dll')) { throw 'SelfXWinRT.dll is not listed in SelfX.Code.json.' }
	return $expected
}

# Checks the folder WinRT of the install folder and keeps every DLL open (read sharing only) in
# $Script:SelfXWinRTHandles. Throws when anything differs; the handles opened so far are closed first.
function Test-SelfXWinRTFiles {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$expected = Get-SelfXWinRTExpectedHashes -InstallFolder $InstallFolder
	$folderPath = Join-Path $InstallFolder 'WinRT'
	$folder = Get-Item -LiteralPath $folderPath -Force -ErrorAction SilentlyContinue
	if (-not $folder -or -not $folder.PSIsContainer) { throw 'The folder WinRT is missing.' }
	if ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The folder WinRT is a link.' }

	$present = @{}
	foreach ($entry in @(Get-ChildItem -LiteralPath $folderPath -Force)) {
		if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "WinRT\$($entry.Name) is a link." }
		if ($entry.PSIsContainer) { throw "WinRT\$($entry.Name) is a folder." }
		if ($entry.Extension -ieq '.dll') {
			if (-not $expected.ContainsKey($entry.Name.ToLowerInvariant())) { throw "WinRT\$($entry.Name) is not listed in SelfX.Code.json." }
			$present[$entry.Name.ToLowerInvariant()] = $entry.FullName
		}
	}
	$opened = New-Object System.Collections.Generic.List[IO.FileStream]
	try {
		foreach ($name in $expected.Keys) {
			if (-not $present.ContainsKey($name)) { throw "WinRT\$name is missing." }
			$stream = New-Object IO.FileStream($present[$name], [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
			$opened.Add($stream)
			$actual = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($stream)).Replace('-', '')
			if ($actual -ne $expected[$name]) { throw "WinRT\$name does not match SelfX.Code.json." }
		}
	}
	catch {
		foreach ($stream in $opened) { $stream.Dispose() }
		$cause = if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }
		if ($cause -is [IO.IOException] -or $cause -is [UnauthorizedAccessException]) { throw "A WinRT file cannot be opened for the check ($($cause.GetType().Name))." }
		throw
	}
	# The new handles are in place: release the ones of an earlier check in this process.
	$previous = @($Script:SelfXWinRTHandles)
	$Script:SelfXWinRTHandles.Clear()
	foreach ($stream in $opened) { $Script:SelfXWinRTHandles.Add($stream) }
	foreach ($stream in $previous) { $stream.Dispose() }
}

# Checks the WinRT files and then loads SelfXWinRT.dll. Afterwards [SelfX.SelfXWinRT]::CreateUpdateManager is available.
# Throws (nothing is loaded) when the check fails. Called again in the same process: the files are checked again.
function Import-SelfXWinRT {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$InstallFolder = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	Test-SelfXWinRTFiles -InstallFolder $InstallFolder
	[void][Reflection.Assembly]::LoadFrom((Join-Path (Join-Path $InstallFolder 'WinRT') 'SelfXWinRT.dll'))
}

# Import-SelfXWinRT and then the two DLLs of the Windows SDK projection from the same checked folder (they stay open from the check, so the
# loaded files are the checked ones). Afterwards the WinRT types of the projection, for example [Windows.System.User], are available.
function Import-SelfXWinRTProjection {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$InstallFolder = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	Import-SelfXWinRT -InstallFolder $InstallFolder
	foreach ($name in 'WinRT.Runtime.dll', 'Microsoft.Windows.SDK.NET.dll') {
		[void][Reflection.Assembly]::LoadFrom((Join-Path (Join-Path $InstallFolder 'WinRT') $name))
	}
}
