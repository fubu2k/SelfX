<#
.SYNOPSIS
    Detect the expected locally installed SelfX Service package version.

.DESCRIPTION
    Read-only Intune/SCCM detection for ProgramFiles\SelfX. Requires App\SelfXService.exe, App\SelfX.exe,
    Config\Tool_Config.xml, a registered SelfXService, an exact match of the code version 3.1.0 and the two file lists of the
    package. The code version is ToolVersion in App\SelfX.Code.json (the version is a property of the code;
    Tool_Config.xml is not read for it). App\SelfX.Code.json and Config\SelfX.Config.json must have the digests that
    tools\New-SelfXIntuneWin.ps1 writes into $ExpectedCodeHash and $ExpectedConfigHash of the Detection.ps1 it creates
    (build\SelfX-Service-<version>.Detection.ps1; upload that file to Intune). The three checks are independent: a new code
    version, changed code files without a new version, and a changed configuration (for example a logo) each fail with their own reason,
    and a changed logo changes only the configuration digest.
    $PackageKind says which package this script belongs to (tools\New-SelfXIntuneWin.ps1 and the assistant write it): Full (default:
    all three checks), FullWithoutConfig (the full package of a setup with a separate configuration package: version and code digest,
    the configuration digest is not compared, so that the full package is not installed again when the configuration package has
    changed the configuration) and ConfigOnly (the configuration package: only the configuration digest; it needs a digest, a
    placeholder is a problem).
    The copy in the repository still has the placeholders: it checks the version only and logs that.
    An installation in the layout of an older version (all files directly in ProgramFiles\SelfX) is not detected, so Intune
    installs the update.
    The trust anchor that Install.ps1 writes must exist: HKLM\SOFTWARE\SelfX\Trust (64-bit view) with the value Mode = Hash or
    Signature. The mode itself is not a problem (both are valid and it is only written to the log); a missing key or another
    value is "not detected", so an installation of a version without the anchor is installed again.
    Does not start the service, contact the pipe, verify that it is running or execute
    remediation scripts. Writes an installed message and exits 0 when checks pass; for a missing prerequisite or a version
    mismatch it writes nothing and exits 0 as well (no output = not installed for Intune and for Configuration Manager; Configuration
    Manager would read an exit code other than 0 as "unknown" and not install). XML read/parse errors are not caught (an error).
    Logs the result to ProgramData\SelfX\Logs\Detection_<date>.log when that folder exists.

.NOTES
    Name    : Detection.ps1
    Package : SelfX Service
    Context : Detection
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.8.0    2026-11-22  fubu2k               Detect version 2.8.0 (PowerShell 7, Windows 11 25H2)
    2.8.1    2026-11-23  fubu2k               Security (M2): also compares the digest of the file list SelfX.Files.json with the value
                                              embedded by the packaging tool (changed files are detected without a version change)
    3.0.0    2026-11-23  fubu2k               Detect version 3.0.0 (release)
    3.0.1    2026-11-24  fubu2k               Detect version 3.0.1
    3.0.2    2026-11-24  fubu2k               Detect version 3.0.2
    3.0.3    2026-11-27  fubu2k               Two digests (SelfX.Code.json and SelfX.Config.json) instead of the digest of SelfX.Files.json
    3.0.4    2026-11-27  fubu2k               The installed version is read from ToolVersion of SelfX.Code.json, no longer from Tool_Version of Tool_Config.xml;
                                              the check is the function Test-SelfXInstalledPackage (version, code digest, configuration digest)
    3.1.0    2026-11-27  fubu2k               Detect version 3.1.0 in the layout App\ and Config\ (programs and SelfX.Code.json in App, Tool_Config.xml
                                              and SelfX.Config.json in Config); the old layout is not detected
    3.1.0    2026-11-27  fubu2k               The trust anchor HKLM\SOFTWARE\SelfX\Trust must exist with Mode = Hash or Signature (function
                                              Test-SelfXTrustAnchor); the mode is logged, not judged
    3.1.0    2026-11-27  fubu2k               $PackageKind: Full (as before), FullWithoutConfig (configuration digest not compared) and ConfigOnly (only the
                                              configuration digest) for the two Intune packages of a setup with a configuration package
    3.1.0    2026-11-28  fubu2k               "Not detected" ends with exit code 0 and no output (was 1), so the script also works as the detection
                                              method of Configuration Manager (Windows Server); for Intune the result is the same
#>

$ExpectedVersion = '3.1.0'
# Digests of the two file lists of the package. tools\New-SelfXIntuneWin.ps1 replaces the placeholders in the Detection.ps1 it
# writes to the build folder; the repository copy keeps them (version check only).
$ExpectedCodeHash = '__SELFX_CODE_HASH__'
$ExpectedConfigHash = '__SELFX_CONFIG_HASH__'
# Full | FullWithoutConfig | ConfigOnly (see the description); the packaging tools replace the value for the configuration package and for
# the full package of a setup with a separate configuration package.
$PackageKind = 'Full'
$InstallFolder = Join-Path $env:ProgramFiles 'SelfX'
# Code in App, configuration in Config (Install.ps1).
$AppFolder = Join-Path $InstallFolder 'App'
$ToolConfigFile = Join-Path $InstallFolder 'Config\Tool_Config.xml'
$LogFolder = Join-Path $env:ProgramData 'SelfX\Logs'

# Detection runs standalone (without the package files): small own logger, only when SelfX was installed
# (the Logs folder exists and is protected by Install.ps1). Never creates folders, never fails detection.
function Write-DetectionLog {
	param([string]$Message)
	try {
		if (-not (Test-Path -LiteralPath $LogFolder -PathType Container)) { return }
		$path = Join-Path $LogFolder ('Detection_{0:yyyy-MM-dd}.log' -f [datetime]::Now)
		$line = '{0} | {1,-7} | {2,6} | {3}' -f [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff'), 'Info', $PID, $Message
		[IO.File]::AppendAllText($path, $line + "`r`n", [Text.Encoding]::UTF8)
	} catch { }
}

# Digest of the file list: SHA256 over the lines "<name>=<SHA256>", sorted by name (ordinal), joined by LF, UTF-8.
# The same function is in tools\SelfXPackage.Common.ps1 (Test-Detection.ps1 checks that both give the same value).
function Get-SelfXFilesDigest {
	param([Parameter(Mandatory = $true)][hashtable]$Files)
	$names = [string[]]@($Files.Keys)
	[Array]::Sort($names, [StringComparer]::Ordinal)
	$text = [string]::Join("`n", @($names | ForEach-Object { '{0}={1}' -f $_, "$($Files[$_])".ToUpperInvariant() }))
	$sha = [Security.Cryptography.SHA256]::Create()
	try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))) -replace '-', '') }
	finally { $sha.Dispose() }
}

# Version of the installed code: ToolVersion of SelfX.Code.json (a version file of the project, never the configuration). Returns $null when
# the list is missing, too large, not valid JSON or has no version of 1 to 30 letters, digits, '.' or '-'.
function Get-SelfXInstalledVersion {
	param([Parameter(Mandatory = $true)][string]$Path)
	Try
	{
		$item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
		If($item.PSIsContainer -or $item.Length -gt 1048576) { return $null }
		$list = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
		If(-not $list) { return $null }
		$version = "$($list.ToolVersion)".Trim()
		If($version -notmatch '^[0-9A-Za-z.\-]{1,30}\z') { return $null }
		return $version
	}
	Catch { return $null }
}

# Returns $null when the installed file list (SelfX.Code.json or SelfX.Config.json) has the expected digest, otherwise the reason.
function Test-SelfXFilesList {
	param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ExpectedHash)
	$name = Split-Path -Leaf $Path
	If(-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "$name missing" }
	Try
	{
		$list = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
		If(-not $list -or "$($list.ManifestVersion)" -ne '1' -or -not $list.Files) { return "$name has an unknown format" }
		$files = @{}
		ForEach($property in @($list.Files.PSObject.Properties)) { $files[$property.Name] = "$($property.Value)" }
		If($files.Count -eq 0) { return "$name lists no files" }
		If((Get-SelfXFilesDigest -Files $files) -ne $ExpectedHash.ToUpperInvariant()) { return "$name differs from the package" }
	}
	Catch { return "$name cannot be read" }
	return $null
}

# Checks the installed package against what this script expects and returns an object with Reason (the first problem, $null when all
# checks pass) and Notes (messages for the log). The three checks are independent of each other:
#   1. the code version: ToolVersion of SelfX.Code.json must equal ExpectedVersion (Tool_Config.xml is not read for it),
#   2. the code files: SelfX.Code.json must have the digest ExpectedCodeHash,
#   3. the configuration files: SelfX.Config.json must have the digest ExpectedConfigHash.
# A digest that is still the placeholder (a copy of the repository) is not checked; a digest that is neither a placeholder nor 64 hex
# characters is a problem.
function Test-SelfXInstalledPackage {
	param(
		[Parameter(Mandatory = $true)][string]$InstallFolder,
		[Parameter(Mandatory = $true)][string]$ExpectedVersion,
		[Parameter(Mandatory = $true)][string]$ExpectedCodeHash,
		[Parameter(Mandatory = $true)][string]$ExpectedConfigHash,
		[string]$Kind = 'Full'
	)
	$notes = New-Object System.Collections.Generic.List[string]
	If(@('Full', 'FullWithoutConfig', 'ConfigOnly') -cnotcontains $Kind) { return [pscustomobject]@{ Reason = 'invalid package kind in this script'; Notes = $notes.ToArray() } }
	# Compare the package catalog version, not the service protocol version. The configuration package does not check the code.
	If($Kind -ne 'ConfigOnly')
	{
		$installedVersion = Get-SelfXInstalledVersion -Path (Join-Path $InstallFolder 'App\SelfX.Code.json')
		If($null -eq $installedVersion) { return [pscustomobject]@{ Reason = 'no code version in SelfX.Code.json'; Notes = $notes.ToArray() } }
		If($installedVersion -ne $ExpectedVersion) { return [pscustomobject]@{ Reason = "installed version $installedVersion"; Notes = $notes.ToArray() } }
	}
	# The two file lists of the package: changed files without a new version are an update too.
	$checks = @(
		@{ File = 'SelfX.Code.json'; Folder = 'App'; Expected = $ExpectedCodeHash; Placeholder = '__SELFX_CODE_HASH__' },
		@{ File = 'SelfX.Config.json'; Folder = 'Config'; Expected = $ExpectedConfigHash; Placeholder = '__SELFX_CONFIG_HASH__' }
	)
	ForEach($check in $checks)
	{
		If(($Kind -eq 'ConfigOnly') -and ($check.File -eq 'SelfX.Code.json')) { continue }
		If(($Kind -eq 'FullWithoutConfig') -and ($check.File -eq 'SelfX.Config.json')) { $notes.Add('The configuration is delivered by a separate package: SelfX.Config.json is not compared here.'); continue }
		If(($Kind -eq 'ConfigOnly') -and ($check.Expected -ceq $check.Placeholder)) { return [pscustomobject]@{ Reason = 'no digest of SelfX.Config.json in this script (it is not a script of the assistant)'; Notes = $notes.ToArray() } }
		If($check.Expected -match '^[0-9A-Fa-f]{64}\z')
		{
			$problem = Test-SelfXFilesList -Path (Join-Path (Join-Path $InstallFolder $check.Folder) $check.File) -ExpectedHash $check.Expected
			If($problem) { return [pscustomobject]@{ Reason = $problem; Notes = $notes.ToArray() } }
		}
		ElseIf($check.Expected -ceq $check.Placeholder) { $notes.Add("No digest of $($check.File) embedded (script not created by New-SelfXIntuneWin.ps1): version check only.") }
		Else { return [pscustomobject]@{ Reason = "invalid digest of $($check.File) in this script"; Notes = $notes.ToArray() } }
	}
	return [pscustomobject]@{ Reason = $null; Notes = $notes.ToArray() }
}

# The trust anchor of Install.ps1: the key must exist and Mode must be the text Hash or Signature. Returns an object with Reason ($null
# when the anchor is there) and Mode. Which of the two modes is set is not a problem. Read from the 64-bit view of the registry, also
# when the script runs in a 32-bit process. Hive and SubKey are parameters for the tests only.
function Test-SelfXTrustAnchor {
	param(
		[ValidateSet('LocalMachine', 'CurrentUser')][string]$Hive = 'LocalMachine',
		[string]$SubKey = 'SOFTWARE\SelfX\Trust'
	)
	Try
	{
		$mode = $null
		$base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]$Hive, [Microsoft.Win32.RegistryView]::Registry64)
		Try
		{
			$key = $base.OpenSubKey($SubKey, $false)
			If($null -eq $key) { return [pscustomobject]@{ Reason = 'trust anchor missing'; Mode = $null } }
			Try { $mode = $key.GetValue('Mode', $null) } Finally { $key.Dispose() }
		}
		Finally { $base.Dispose() }
		If(($mode -is [string]) -and (($mode -ceq 'Hash') -or ($mode -ceq 'Signature'))) { return [pscustomobject]@{ Reason = $null; Mode = $mode } }
		return [pscustomobject]@{ Reason = 'trust anchor has no valid mode'; Mode = $null }
	}
	Catch { return [pscustomobject]@{ Reason = 'trust anchor cannot be read'; Mode = $null } }
}

function Exit-Detection {
	param([int]$Code, [string]$Reason)
	Write-DetectionLog ("SelfX {0}: {1}" -f $ExpectedVersion, $Reason)
	if ($Code -eq 0) { Write-Output $(if ($PackageKind -eq 'ConfigOnly') { 'The SelfX configuration is installed' } else { "SelfX $ExpectedVersion is installed" }) }
	# Not detected ($Code 1) is no error: no output and exit code 0. Intune and Configuration Manager both read that as "not installed";
	# Configuration Manager reads any other exit code as "unknown" and would not install SelfX.
	exit 0
}

If(-not (Test-Path -LiteralPath (Join-Path $AppFolder 'SelfXService.exe'))) { Exit-Detection 1 'not detected (App\SelfXService.exe missing)' }
If(-not (Test-Path -LiteralPath (Join-Path $AppFolder 'SelfX.exe'))) { Exit-Detection 1 'not detected (App\SelfX.exe missing)' }
If(-not (Test-Path -LiteralPath $ToolConfigFile)) { Exit-Detection 1 'not detected (Config\Tool_Config.xml missing)' }
# Registration is sufficient here; detection does not require the service to be running.
If(-not (Get-Service -Name 'SelfXService' -ErrorAction SilentlyContinue)) { Exit-Detection 1 'not detected (service SelfXService not registered)' }

# The installed package: code version, code files, configuration files (each with its own reason).
$Result = Test-SelfXInstalledPackage -InstallFolder $InstallFolder -ExpectedVersion $ExpectedVersion -ExpectedCodeHash $ExpectedCodeHash -ExpectedConfigHash $ExpectedConfigHash -Kind $PackageKind
ForEach($Note in @($Result.Notes)) { Write-DetectionLog $Note }
If($Result.Reason) { Exit-Detection 1 "not detected ($($Result.Reason))" }

# The trust anchor must exist; the mode (Hash or Signature) is only logged.
$Anchor = Test-SelfXTrustAnchor
If($Anchor.Reason) { Exit-Detection 1 "not detected ($($Anchor.Reason))" }
Write-DetectionLog "Trust mode: $($Anchor.Mode)."

Exit-Detection 0 'detected'
