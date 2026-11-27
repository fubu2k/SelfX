<#
.SYNOPSIS
    Tests the check of SelfXAudio.dll before it is loaded (action "No sound").

.DESCRIPTION
    Dot-sources Sources\SelfXAudio.ps1 and runs it against a temporary "install folder" with a stand-in file (plain bytes, no
    real DLL), a hash list like the one the package build writes and, where Windows allows it, junctions. Nothing is
    installed and nothing on this computer is changed.
    Checked: the unchanged folder is accepted and the DLL stays open (no writing while the check holds it); a changed, missing,
    additional or unlisted file, a sub folder, a link (folder, entry), a missing, broken, oversized or unknown list, an invalid
    hash and a list without SelfXAudio.dll are refused and leave no handle open; Import-SelfXAudio refuses before it loads
    anything; the action script loads the library only through Import-SelfXAudio, passes a fixed minimum volume and starts no
    process, sends no keys and changes no registry value.
    PowerShell 7 (the library needs SHA256.HashData): pwsh -NoProfile -File .\Test-AudioLoad.ps1

.NOTES
    Name    : Test-AudioLoad.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI; not installed)
    Version : 2.9.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.18   2026-11-23  fubu2k               Initial version (audio library load check).
    2.9.0    2026-11-27  fubu2k               The hash comes from SelfX.Code.json.
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
. (Join-Path $sources 'SelfXAudio.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXAudioTest_' + [guid]::NewGuid().ToString('N'))
$install = Join-Path $root 'install'
$audio = Join-Path $install 'Audio'
$dll = Join-Path $audio 'SelfXAudio.dll'

function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Close-Handle { if ($Script:SelfXAudioHandle) { $Script:SelfXAudioHandle.Dispose(); $Script:SelfXAudioHandle = $null } }
function Write-List([hashtable]$Files, [int]$Version = 1) {
	$json = [ordered]@{ ManifestVersion = $Version; ToolVersion = '9.9.9'; Files = $Files } | ConvertTo-Json -Depth 4
	[IO.File]::WriteAllText((Join-Path $install 'SelfX.Code.json'), $json)
}
function New-Install {
	Close-Handle
	if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
	New-Item -ItemType Directory -Path $audio -Force | Out-Null
	[IO.File]::WriteAllBytes($dll, [byte[]](1, 2, 3, 4))
	[IO.File]::WriteAllText((Join-Path $install 'Tool_Config.xml'), '<GUI_Config/>')
	Write-List @{ 'Tool_Config.xml' = (Get-Hash (Join-Path $install 'Tool_Config.xml')); 'Audio/SelfXAudio.dll' = (Get-Hash $dll) }
}
function Assert-Refused([string]$Pattern, [string]$Message) {
	Assert-Throws { Test-SelfXAudioFiles -InstallFolder $install } $Pattern $Message
	Assert-Equal ($null -eq $Script:SelfXAudioHandle) $true "${Message}: no handle stays open"
}
function Test-CanWrite([string]$Path) {
	try { $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite); $stream.Dispose(); return $true } catch { return $false }
}

try {
	# --- accepted ---
	New-Install
	Test-SelfXAudioFiles -InstallFolder $install
	Assert-Equal ($null -ne $Script:SelfXAudioHandle) $true 'accepted: the DLL is kept open'
	if ($IsWindows) {
		Assert-Equal (Test-CanWrite $dll) $false 'accepted: SelfXAudio.dll cannot be written while the handle is open'
		Assert-Throws { Remove-Item -LiteralPath $dll -Force } '.' 'accepted: SelfXAudio.dll cannot be deleted or replaced while the handle is open'
	}
	Test-SelfXAudioFiles -InstallFolder $install
	Assert-Equal ($null -ne $Script:SelfXAudioHandle) $true 'accepted: a second check replaces the handle'
	Close-Handle
	Assert-Equal (Test-CanWrite $dll) $true 'accepted: after closing the handle the file can be written again (test setup works)'

	# --- changed, missing, additional ---
	New-Install; [IO.File]::WriteAllBytes($dll, [byte[]](1, 2, 3, 9))
	Assert-Refused 'SelfXAudio.dll does not match' 'a changed SelfXAudio.dll is refused'
	New-Install; Remove-Item -LiteralPath $dll
	Assert-Refused 'SelfXAudio.dll is missing' 'a missing SelfXAudio.dll is refused'
	New-Install; [IO.File]::WriteAllBytes((Join-Path $audio 'Extra.dll'), [byte[]](1))
	Assert-Refused 'Extra.dll is not expected' 'an additional DLL is refused'
	New-Install; New-Item -ItemType Directory -Path (Join-Path $audio 'sub') | Out-Null
	Assert-Refused 'is a folder' 'a sub folder in Audio is refused'
	New-Install; Remove-Item -LiteralPath $audio -Recurse -Force
	Assert-Refused 'folder Audio is missing' 'a missing folder Audio is refused'

	# --- the list ---
	New-Install; Remove-Item -LiteralPath (Join-Path $install 'SelfX.Code.json')
	Assert-Refused 'SelfX.Code.json is missing' 'a missing list is refused'
	New-Install; [IO.File]::WriteAllText((Join-Path $install 'SelfX.Code.json'), '{ not json')
	Assert-Refused 'not valid JSON' 'a broken list is refused'
	New-Install; Write-List @{ 'Audio/SelfXAudio.dll' = (Get-Hash $dll) } 2
	Assert-Refused 'unknown format' 'an unknown list format is refused'
	New-Install; Write-List @{ 'Tool_Config.xml' = (Get-Hash (Join-Path $install 'Tool_Config.xml')) }
	Assert-Refused 'SelfXAudio.dll is not listed' 'a list without SelfXAudio.dll is refused'
	New-Install; Write-List @{ 'Audio/SelfXAudio.dll' = 'ABC' }
	Assert-Refused 'invalid hash' 'an invalid hash in the list is refused'
	New-Install; [IO.File]::WriteAllText((Join-Path $install 'SelfX.Code.json'), ('{"ManifestVersion":1,"Files":{"x":"' + ('A' * 1100000) + '"}}'))
	Assert-Refused 'too large' 'an oversized list is refused'
	# The hash of the WinRT library must not be accepted for the audio library.
	New-Install; Write-List @{ 'WinRT/SelfXAudio.dll' = (Get-Hash $dll) }
	Assert-Refused 'SelfXAudio.dll is not listed' 'an entry outside Audio is not used'

	# --- links (needs Windows; skipped where junctions cannot be created) ---
	$linkTarget = Join-Path $root 'target'
	New-Install; New-Item -ItemType Directory -Path $linkTarget | Out-Null
	Copy-Item -LiteralPath $dll -Destination $linkTarget
	$junctionOk = [bool]$IsWindows
	if ($junctionOk) { try { Remove-Item -LiteralPath $audio -Recurse -Force; New-Item -ItemType Junction -Path $audio -Target $linkTarget | Out-Null } catch { $junctionOk = $false } }
	if ($junctionOk) {
		Assert-Refused 'folder Audio is a link' 'a junction instead of the folder Audio is refused'
		New-Install; New-Item -ItemType Directory -Path $linkTarget | Out-Null
		New-Item -ItemType Junction -Path (Join-Path $audio 'jl') -Target $linkTarget | Out-Null
		Assert-Refused 'is a link' 'a junction inside Audio is refused'
	}

	# --- Import-SelfXAudio: nothing is loaded when the check fails; with a valid check it gets to the loader ---
	New-Install; [IO.File]::WriteAllBytes($dll, [byte[]](9, 9, 9, 9))
	Assert-Throws { Import-SelfXAudio -InstallFolder $install } 'does not match' 'Import-SelfXAudio: a changed DLL is refused before the loader'
	Assert-Equal @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { try { $_.Location -and $_.Location.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } catch { $false } }).Count 0 'Import-SelfXAudio: no assembly of the test folder was loaded'
	New-Install
	Assert-Throws { Import-SelfXAudio -InstallFolder $install } 'load|format|assembly' 'Import-SelfXAudio: a checked file reaches the loader (stand-in bytes are no assembly)'
	Close-Handle

	# --- the action script ---
	$script = (Get-Content -LiteralPath (Join-Path $sources 'Scripts_to_run\SelfX_Audio_Restore.ps1') -Raw) -replace '(?s)<#.*?#>', ''
	Assert-Equal ($script -match 'Import-SelfXAudio -InstallFolder') $true 'the action loads the library through Import-SelfXAudio'
	Assert-Equal ($script -match 'Assembly\]::Load|Add-Type') $false 'the action does not load code itself'
	Assert-Equal ($script -match '\$MinimumVolumePercent = 30') $true 'the minimum volume is a fixed value in the script'
	Assert-Equal ($script -match 'Start-Process|Invoke-Expression|SendKeys|\[regex\]::Escape|Set-ItemProperty|New-ItemProperty|reg\.exe|sc\.exe') $false 'the action starts no process, sends no keys and changes no registry value'
	Assert-Equal ($script -match '\$args|\$env:') $false 'the action uses no argument and no environment variable of the caller'
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
