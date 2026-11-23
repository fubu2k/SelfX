<#
.SYNOPSIS
    Tests the check of the WinRT libraries before they are loaded (security review finding N4).

.DESCRIPTION
    Dot-sources Sources\SelfXWinRT.ps1 and runs it against a temporary "install folder" with stand-in files (plain bytes, no
    real DLLs), a hash list like the one the package build writes and, where Windows allows it, junctions. Nothing is
    installed and nothing on this computer is changed.
    Checked: the unchanged folder is accepted and every DLL stays open (no writing while the check holds it); a changed, missing,
    unlisted or additional DLL, a sub folder, a link (folder, entry), a missing, broken, oversized or unknown list, an invalid
    hash and a list without SelfXWinRT.dll are refused and leave no handle open; Import-SelfXWinRT refuses before it loads
    anything; the callers (HealthStatus.ps1, SelfX_Updates_Install.ps1) use Import-SelfXWinRT and nothing else loads a DLL
    from WinRT; the service checks .dll files against the list too.
    PowerShell 7 (the library needs SHA256.HashData): pwsh -NoProfile -File .\Test-WinRTLoad.ps1

.NOTES
    Name    : Test-WinRTLoad.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI; not installed)
    Version : 2.8.14
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.14   2026-11-23  fubu2k               Initial version (security review finding N4, WinRT load check).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
	$script:checks++
	try { & $Action | Out-Null; $script:errors.Add("$Message (no error)") }
	catch { if ($_.Exception.Message -notmatch $Pattern) { $script:errors.Add("$Message (wrong error: $($_.Exception.Message))") } }
}

$sources = Join-Path $PSScriptRoot 'Sources'
. (Join-Path $sources 'SelfXWinRT.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXWinRTTest_' + [guid]::NewGuid().ToString('N'))
$install = Join-Path $root 'install'
$winRT = Join-Path $install 'WinRT'
$mainDll = Join-Path $winRT 'SelfXWinRT.dll'
$depDll = Join-Path $winRT 'Microsoft.Windows.SDK.NET.dll'

function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Close-Handles { foreach ($stream in @($Script:SelfXWinRTHandles)) { $stream.Dispose() }; $Script:SelfXWinRTHandles.Clear() }
function Write-List([hashtable]$Files, [int]$Version = 1) {
	$json = [ordered]@{ ManifestVersion = $Version; ToolVersion = '9.9.9'; Files = $Files } | ConvertTo-Json -Depth 4
	[IO.File]::WriteAllText((Join-Path $install 'SelfX.Files.json'), $json)
}
function New-Install {
	Close-Handles
	if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
	New-Item -ItemType Directory -Path $winRT -Force | Out-Null
	[IO.File]::WriteAllBytes($mainDll, [byte[]](1, 2, 3, 4))
	[IO.File]::WriteAllBytes($depDll, [byte[]](5, 6, 7, 8))
	[IO.File]::WriteAllText((Join-Path $install 'Tool_Config.xml'), '<GUI_Config/>')
	Write-List @{
		'Tool_Config.xml'                      = (Get-Hash (Join-Path $install 'Tool_Config.xml'))
		'WinRT/SelfXWinRT.dll'                 = (Get-Hash $mainDll)
		'WinRT/Microsoft.Windows.SDK.NET.dll'  = (Get-Hash $depDll)
	}
}
# Refused: the message matches and no handle stays open (the file can be written right away).
function Assert-Refused([string]$Pattern, [string]$Message) {
	Assert-Throws { Test-SelfXWinRTFiles -InstallFolder $install } $Pattern $Message
	Assert-Equal $Script:SelfXWinRTHandles.Count 0 "${Message}: no handle stays open"
}
function Test-CanWrite([string]$Path) {
	try { $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite); $stream.Dispose(); return $true } catch { return $false }
}

try {
	# --- accepted ---
	New-Install
	Test-SelfXWinRTFiles -InstallFolder $install
	Assert-Equal $Script:SelfXWinRTHandles.Count 2 'accepted: both DLLs are kept open'
	# The sharing mode is enforced by Windows only (on Linux a second open or a delete is not refused).
	if ($IsWindows) {
		Assert-Equal (Test-CanWrite $mainDll) $false 'accepted: SelfXWinRT.dll cannot be written while the handle is open'
		Assert-Equal (Test-CanWrite $depDll) $false 'accepted: the dependency cannot be written while the handle is open'
		Assert-Throws { Remove-Item -LiteralPath $mainDll -Force } '.' 'accepted: SelfXWinRT.dll cannot be deleted or replaced while the handle is open'
	}
	Test-SelfXWinRTFiles -InstallFolder $install
	Assert-Equal $Script:SelfXWinRTHandles.Count 2 'accepted: a second check replaces the handles (no growth)'
	Close-Handles
	Assert-Equal (Test-CanWrite $mainDll) $true 'accepted: after closing the handles the file can be written again (test setup works)'

	# --- entries of the list that are not WinRT DLLs are ignored, the case of the DLL file name does not matter ---
	New-Install
	Test-SelfXWinRTFiles -InstallFolder $install
	Assert-Equal $Script:SelfXWinRTHandles.Count 2 'accepted: other entries of the list (Tool_Config.xml) are not WinRT DLLs'
	Close-Handles

	# --- changed, missing, additional ---
	New-Install; [IO.File]::WriteAllBytes($mainDll, [byte[]](1, 2, 3, 9))
	Assert-Refused 'SelfXWinRT.dll does not match' 'a changed SelfXWinRT.dll is refused'
	Assert-Equal (Test-CanWrite $depDll) $true 'a changed SelfXWinRT.dll: the other DLL is not left open either'
	New-Install; [IO.File]::WriteAllBytes($depDll, [byte[]](5, 6, 7, 9))
	Assert-Refused 'Microsoft.Windows.SDK.NET.dll does not match' 'a changed dependency is refused'
	Assert-Equal (Test-CanWrite $mainDll) $true 'a changed dependency: SelfXWinRT.dll is not left open either'
	New-Install; Remove-Item -LiteralPath $depDll
	Assert-Refused 'microsoft.windows.sdk.net.dll is missing' 'a missing DLL is refused'
	New-Install; Remove-Item -LiteralPath $mainDll
	Assert-Refused 'selfxwinrt.dll is missing' 'a missing SelfXWinRT.dll is refused'
	New-Install; [IO.File]::WriteAllBytes((Join-Path $winRT 'Extra.dll'), [byte[]](1))
	Assert-Refused 'Extra.dll is not listed' 'an additional DLL is refused'
	New-Install; [IO.File]::WriteAllBytes((Join-Path $winRT 'Extra.DLL'), [byte[]](1))
	Assert-Refused 'not listed' 'an additional DLL with upper case extension is refused'
	New-Install; New-Item -ItemType Directory -Path (Join-Path $winRT 'sub') | Out-Null
	Assert-Refused 'is a folder' 'a sub folder in WinRT is refused'
	New-Install; Remove-Item -LiteralPath $winRT -Recurse -Force
	Assert-Refused 'folder WinRT is missing' 'a missing folder WinRT is refused'

	# --- the list ---
	New-Install; Remove-Item -LiteralPath (Join-Path $install 'SelfX.Files.json')
	Assert-Refused 'SelfX.Files.json is missing' 'a missing list is refused'
	New-Install; [IO.File]::WriteAllText((Join-Path $install 'SelfX.Files.json'), '{ not json')
	Assert-Refused 'not valid JSON' 'a broken list is refused'
	New-Install; Write-List @{ 'WinRT/SelfXWinRT.dll' = (Get-Hash $mainDll) } 2
	Assert-Refused 'unknown format' 'an unknown list format is refused'
	New-Install; Write-List @{ 'WinRT/Microsoft.Windows.SDK.NET.dll' = (Get-Hash $depDll) }
	Assert-Refused 'SelfXWinRT.dll is not listed' 'a list without SelfXWinRT.dll is refused'
	New-Install; Write-List @{ 'WinRT/SelfXWinRT.dll' = 'ABC'; 'WinRT/Microsoft.Windows.SDK.NET.dll' = (Get-Hash $depDll) }
	Assert-Refused 'invalid hash' 'an invalid hash in the list is refused'
	New-Install; [IO.File]::WriteAllText((Join-Path $install 'SelfX.Files.json'), ('{"ManifestVersion":1,"Files":{"x":"' + ('A' * 1100000) + '"}}'))
	Assert-Refused 'too large' 'an oversized list is refused'
	New-Install; Write-List @{ 'WinRT/SelfXWinRT.dll' = (Get-Hash $mainDll); 'WinRT/Microsoft.Windows.SDK.NET.dll' = (Get-Hash $depDll); 'WinRT/../evil.dll' = (Get-Hash $depDll) }
	Test-SelfXWinRTFiles -InstallFolder $install
	Assert-Equal $Script:SelfXWinRTHandles.Count 2 'a list entry with a path outside WinRT is ignored (never used as a file name)'
	Close-Handles

	# --- links (needs Windows; skipped where junctions cannot be created) ---
	$linkTarget = Join-Path $root 'target'
	New-Install; New-Item -ItemType Directory -Path $linkTarget | Out-Null
	Copy-Item -LiteralPath $mainDll, $depDll -Destination $linkTarget
	$junctionOk = [bool]$IsWindows
	if ($junctionOk) { try { Remove-Item -LiteralPath $winRT -Recurse -Force; New-Item -ItemType Junction -Path $winRT -Target $linkTarget | Out-Null } catch { $junctionOk = $false } }
	if ($junctionOk) {
		Assert-Refused 'folder WinRT is a link' 'a junction instead of the folder WinRT is refused'
		New-Install; New-Item -ItemType Directory -Path $linkTarget | Out-Null
		New-Item -ItemType Junction -Path (Join-Path $winRT 'jl') -Target $linkTarget | Out-Null
		Assert-Refused 'is a link' 'a junction inside WinRT is refused'
		New-Install; Copy-Item -LiteralPath (Join-Path $install 'SelfX.Files.json') -Destination (Join-Path $root 'list.json')
		Remove-Item -LiteralPath (Join-Path $install 'SelfX.Files.json')
		$symlinkOk = $true
		try { New-Item -ItemType SymbolicLink -Path (Join-Path $install 'SelfX.Files.json') -Target (Join-Path $root 'list.json') | Out-Null } catch { $symlinkOk = $false }
		if ($symlinkOk) { Assert-Refused 'SelfX.Files.json is a link' 'a symbolic link as list is refused' }
	}

	# --- Import-SelfXWinRT: nothing is loaded when the check fails; with a valid check it gets to the loader ---
	New-Install; [IO.File]::WriteAllBytes($mainDll, [byte[]](9, 9, 9, 9))
	Assert-Throws { Import-SelfXWinRT -InstallFolder $install } 'does not match' 'Import-SelfXWinRT: a changed DLL is refused before the loader'
	Assert-Equal @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { try { $_.Location -and $_.Location.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } catch { $false } }).Count 0 'Import-SelfXWinRT: no assembly of the test folder was loaded'
	New-Install
	Assert-Throws { Import-SelfXWinRT -InstallFolder $install } 'load|format|assembly' 'Import-SelfXWinRT: a checked file reaches the loader (stand-in bytes are no assembly)'
	Close-Handles

	# --- the callers and the service ---
	$loaders = @(Get-ChildItem -LiteralPath $sources -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -ne 'SelfXWinRT.ps1' -and (Select-String -LiteralPath $_.FullName -Pattern 'Assembly\]::(LoadFrom|LoadFile|Load)\b' -Quiet) })
	Assert-Equal ($loaders.Name -join ', ') '' 'no other script loads an assembly (only SelfXWinRT.ps1)'
	foreach ($caller in 'HealthStatus.ps1', 'Scripts_to_run\SelfX_Updates_Install.ps1') {
		$text = Get-Content -LiteralPath (Join-Path $sources $caller) -Raw
		Assert-Equal ($text -match 'Import-SelfXWinRT -InstallFolder') $true "$caller loads the library through Import-SelfXWinRT"
		Assert-Equal ($text -match 'SelfXWinRT\.dll''') $false "$caller does not build the DLL path itself"
	}
	$service = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Service\SelfXService.cs') -Raw
	Assert-Equal ($service -match 'CheckedExtensions = \{[^}]*"\.dll"') $true 'the service checks .dll files against SelfX.Files.json'
}
finally {
	Close-Handles
	if (Test-Path -LiteralPath $root) {
		# Junctions are removed by name first so that nothing outside the test folder is touched.
		foreach ($link in @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })) {
			try { if ($link.PSIsContainer) { [IO.Directory]::Delete($link.FullName) } else { [IO.File]::Delete($link.FullName) } } catch { }
		}
		Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
	}
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
