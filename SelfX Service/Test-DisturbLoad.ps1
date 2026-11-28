<#
.SYNOPSIS
    Tests the check of SelfXDisturb.dll before it is loaded (hint before disruptive actions).

.DESCRIPTION
    Dot-sources Sources\SelfXDisturb.ps1 and runs it against a temporary "install folder" with a stand-in file (plain bytes, no
    real DLL), a hash list like the one the package build writes and, where Windows allows it, junctions. Nothing is
    installed and nothing on this computer is changed.
    Checked: the unchanged folder is accepted and the DLL stays open (no writing while the check holds it); a changed, missing,
    additional or unlisted file, a sub folder, a link (folder, entry), a missing, broken, oversized or unknown list, an invalid
    hash and a list without SelfXDisturb.dll are refused and leave no handle open; Import-SelfXDisturb refuses before it loads
    anything; Get-SelfXNotificationState returns 0 (no hint) when the check fails; the script loads the library only through
    Import-SelfXDisturb and compiles nothing on the device.
    PowerShell 7 (the library needs SHA256.HashData): pwsh -NoProfile -File .\Test-DisturbLoad.ps1

.NOTES
    Name    : Test-DisturbLoad.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-28  fubu2k               Initial version (check of SelfXDisturb.dll before it is loaded).
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
. (Join-Path $sources 'SelfXDisturb.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXDisturbTest_' + [guid]::NewGuid().ToString('N'))
$install = Join-Path $root 'install'
$disturb = Join-Path $install 'Disturb'
$dll = Join-Path $disturb 'SelfXDisturb.dll'

function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Close-Handle { if ($Script:SelfXDisturbHandle) { $Script:SelfXDisturbHandle.Dispose(); $Script:SelfXDisturbHandle = $null } }
function Write-List([hashtable]$Files, [int]$Version = 1) {
	$json = [ordered]@{ ManifestVersion = $Version; ToolVersion = '9.9.9'; Files = $Files } | ConvertTo-Json -Depth 4
	[IO.File]::WriteAllText((Join-Path $install 'SelfX.Code.json'), $json)
}
function New-Install {
	Close-Handle
	if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
	New-Item -ItemType Directory -Path $disturb -Force | Out-Null
	[IO.File]::WriteAllBytes($dll, [byte[]](1, 2, 3, 4))
	[IO.File]::WriteAllText((Join-Path $install 'Tool_Config.xml'), '<GUI_Config/>')
	Write-List @{ 'Tool_Config.xml' = (Get-Hash (Join-Path $install 'Tool_Config.xml')); 'Disturb/SelfXDisturb.dll' = (Get-Hash $dll) }
}
function Assert-Refused([string]$Pattern, [string]$Message) {
	Assert-Throws { Test-SelfXDisturbFiles -InstallFolder $install } $Pattern $Message
	Assert-Equal ($null -eq $Script:SelfXDisturbHandle) $true "${Message}: no handle stays open"
}
function Test-CanWrite([string]$Path) {
	try { $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite); $stream.Dispose(); return $true } catch { return $false }
}

try {
	# --- accepted ---
	New-Install
	Test-SelfXDisturbFiles -InstallFolder $install
	Assert-Equal ($null -ne $Script:SelfXDisturbHandle) $true 'accepted: the DLL is kept open'
	if ($IsWindows) {
		Assert-Equal (Test-CanWrite $dll) $false 'accepted: SelfXDisturb.dll cannot be written while the handle is open'
		Assert-Throws { Remove-Item -LiteralPath $dll -Force } '.' 'accepted: SelfXDisturb.dll cannot be deleted or replaced while the handle is open'
	}
	Test-SelfXDisturbFiles -InstallFolder $install
	Assert-Equal ($null -ne $Script:SelfXDisturbHandle) $true 'accepted: a second check replaces the handle'
	Close-Handle
	Assert-Equal (Test-CanWrite $dll) $true 'accepted: after closing the handle the file can be written again (test setup works)'

	# --- changed, missing, additional ---
	New-Install; [IO.File]::WriteAllBytes($dll, [byte[]](1, 2, 3, 9))
	Assert-Refused 'SelfXDisturb.dll does not match' 'a changed SelfXDisturb.dll is refused'
	New-Install; Remove-Item -LiteralPath $dll
	Assert-Refused 'SelfXDisturb.dll is missing' 'a missing SelfXDisturb.dll is refused'
	New-Install; [IO.File]::WriteAllBytes((Join-Path $disturb 'Extra.dll'), [byte[]](1))
	Assert-Refused 'Extra.dll is not expected' 'an additional DLL is refused'
	New-Install; New-Item -ItemType Directory -Path (Join-Path $disturb 'sub') | Out-Null
	Assert-Refused 'is a folder' 'a sub folder in Disturb is refused'
	New-Install; Remove-Item -LiteralPath $disturb -Recurse -Force
	Assert-Refused 'folder Disturb is missing' 'a missing folder Disturb is refused'

	# --- the list ---
	New-Install; Remove-Item -LiteralPath (Join-Path $install 'SelfX.Code.json')
	Assert-Refused 'SelfX.Code.json is missing' 'a missing list is refused'
	New-Install; [IO.File]::WriteAllText((Join-Path $install 'SelfX.Code.json'), '{ not json')
	Assert-Refused 'not valid JSON' 'a broken list is refused'
	New-Install; Write-List @{ 'Disturb/SelfXDisturb.dll' = (Get-Hash $dll) } 2
	Assert-Refused 'unknown format' 'an unknown list format is refused'
	New-Install; Write-List @{ 'Tool_Config.xml' = (Get-Hash (Join-Path $install 'Tool_Config.xml')) }
	Assert-Refused 'SelfXDisturb.dll is not listed' 'a list without SelfXDisturb.dll is refused'
	New-Install; Write-List @{ 'Disturb/SelfXDisturb.dll' = 'ABC' }
	Assert-Refused 'invalid hash' 'an invalid hash in the list is refused'
	New-Install; [IO.File]::WriteAllText((Join-Path $install 'SelfX.Code.json'), ('{"ManifestVersion":1,"Files":{"x":"' + ('A' * 1100000) + '"}}'))
	Assert-Refused 'too large' 'an oversized list is refused'
	# The hash of the WinRT library must not be accepted for the disturb library.
	New-Install; Write-List @{ 'WinRT/SelfXDisturb.dll' = (Get-Hash $dll) }
	Assert-Refused 'SelfXDisturb.dll is not listed' 'an entry outside Disturb is not used'

	# --- links (needs Windows; skipped where junctions cannot be created) ---
	$linkTarget = Join-Path $root 'target'
	New-Install; New-Item -ItemType Directory -Path $linkTarget | Out-Null
	Copy-Item -LiteralPath $dll -Destination $linkTarget
	$junctionOk = [bool]$IsWindows
	if ($junctionOk) { try { Remove-Item -LiteralPath $disturb -Recurse -Force; New-Item -ItemType Junction -Path $disturb -Target $linkTarget | Out-Null } catch { $junctionOk = $false } }
	if ($junctionOk) {
		Assert-Refused 'folder Disturb is a link' 'a junction instead of the folder Disturb is refused'
		New-Install; New-Item -ItemType Directory -Path $linkTarget | Out-Null
		New-Item -ItemType Junction -Path (Join-Path $disturb 'jl') -Target $linkTarget | Out-Null
		Assert-Refused 'is a link' 'a junction inside Disturb is refused'
	}

	# --- Import-SelfXDisturb: nothing is loaded when the check fails; with a valid check it gets to the loader ---
	New-Install; [IO.File]::WriteAllBytes($dll, [byte[]](9, 9, 9, 9))
	Assert-Throws { Import-SelfXDisturb -InstallFolder $install } 'does not match' 'Import-SelfXDisturb: a changed DLL is refused before the loader'
	Assert-Equal @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { try { $_.Location -and $_.Location.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } catch { $false } }).Count 0 'Import-SelfXDisturb: no assembly of the test folder was loaded'
	New-Install
	Assert-Throws { Import-SelfXDisturb -InstallFolder $install } 'load|format|assembly' 'Import-SelfXDisturb: a checked file reaches the loader (stand-in bytes are no assembly)'
	Close-Handle

	# --- the state function: a failed check gives 0 (no hint), never an error ---
	New-Install; [IO.File]::WriteAllBytes($dll, [byte[]](9, 9, 9, 9))
	Assert-Equal (Get-SelfXNotificationState -InstallFolder $install) 0 'Get-SelfXNotificationState: a changed DLL gives 0'
	Close-Handle
	New-Install; Remove-Item -LiteralPath $dll
	Assert-Equal (Get-SelfXNotificationState -InstallFolder $install) 0 'Get-SelfXNotificationState: a missing DLL gives 0'
	New-Install; Remove-Item -LiteralPath (Join-Path $install 'SelfX.Code.json')
	Assert-Equal (Get-SelfXNotificationState -InstallFolder $install) 0 'Get-SelfXNotificationState: a missing list gives 0'
	Assert-Equal (Get-SelfXNotificationState -InstallFolder (Join-Path $root 'does-not-exist')) 0 'Get-SelfXNotificationState: a missing install folder gives 0'
	Close-Handle

	# --- the script ---
	$script = (Get-Content -LiteralPath (Join-Path $sources 'SelfXDisturb.ps1') -Raw) -replace '(?s)<#.*?#>', ''
	Assert-Equal ($script -match 'Import-SelfXDisturb -InstallFolder') $true 'the state function loads the library through Import-SelfXDisturb'
	Assert-Equal ($script -match 'Add-Type|csc\.exe|dotnet\s+build|Assembly\]::Load\(|LoadFile') $false 'nothing is compiled on the device and no assembly is loaded from bytes'
	Assert-Equal ($script -match 'Start-Process|Invoke-Expression|Set-ItemProperty|New-ItemProperty|reg\.exe|sc\.exe') $false 'the script starts no process and changes no registry value'
	Assert-Equal ($script -match '\$args|\$env:') $false 'the script uses no argument and no environment variable of the caller'
}
finally {
	Close-Handle
	if (Test-Path -LiteralPath $root) {
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
