<#
.SYNOPSIS
    Detect the expected locally installed SelfX Service package version.

.DESCRIPTION
    Read-only Intune/SCCM detection for ProgramFiles\SelfX. Requires SelfXService.exe, SelfX.exe,
    Tool_Config.xml, a registered SelfXService, an exact Tool_Version match of 3.0.2 and the two file lists of the
    package: SelfX.Code.json and SelfX.Config.json in the install folder must have the digests that
    tools\New-SelfXIntuneWin.ps1 writes into $ExpectedCodeHash and $ExpectedConfigHash of the Detection.ps1 it creates
    (build\SelfX-Service-<version>.Detection.ps1; upload that file to Intune). So an update with changed files is found even
    when Tool_Version did not change, and a changed logo changes only the second digest.
    The copy in the repository still has the placeholders: it checks the version only and logs that.
    Does not start the service, contact the pipe, verify that it is running or execute
    remediation scripts. Writes an installed message and exits 0 when checks pass; exits
    1 for a missing prerequisite or version mismatch. XML read/parse errors are not caught.
    Logs the result to ProgramData\SelfX\Logs\Detection_<date>.log when that folder exists.

.NOTES
    Name    : Detection.ps1
    Package : SelfX Service
    Context : Detection
    Version : 3.0.3

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
#>

$ExpectedVersion = '3.0.2'
# Digests of the two file lists of the package. tools\New-SelfXIntuneWin.ps1 replaces the placeholders in the Detection.ps1 it
# writes to the build folder; the repository copy keeps them (version check only).
$ExpectedCodeHash = '__SELFX_CODE_HASH__'
$ExpectedConfigHash = '__SELFX_CONFIG_HASH__'
$InstallFolder = Join-Path $env:ProgramFiles 'SelfX'
$ToolConfigFile = Join-Path $InstallFolder 'Tool_Config.xml'
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

function Exit-Detection {
	param([int]$Code, [string]$Reason)
	Write-DetectionLog ("SelfX {0}: {1}" -f $ExpectedVersion, $Reason)
	if ($Code -eq 0) { Write-Output "SelfX $ExpectedVersion is installed" }
	exit $Code
}

If(-not (Test-Path -LiteralPath (Join-Path $InstallFolder 'SelfXService.exe'))) { Exit-Detection 1 'not detected (SelfXService.exe missing)' }
If(-not (Test-Path -LiteralPath (Join-Path $InstallFolder 'SelfX.exe'))) { Exit-Detection 1 'not detected (SelfX.exe missing)' }
If(-not (Test-Path -LiteralPath $ToolConfigFile)) { Exit-Detection 1 'not detected (Tool_Config.xml missing)' }
# Registration is sufficient here; detection does not require the service to be running.
If(-not (Get-Service -Name 'SelfXService' -ErrorAction SilentlyContinue)) { Exit-Detection 1 'not detected (service SelfXService not registered)' }

# Compare the package catalog version, not the service protocol version.
$InstalledVersion = ([xml](Get-Content -LiteralPath $ToolConfigFile -Raw)).GUI_Config.Tool_Version
If("$InstalledVersion".Trim() -ne $ExpectedVersion) { Exit-Detection 1 "not detected (installed version $("$InstalledVersion".Trim()))" }

# The two file lists of the package: changed files without a new Tool_Version are an update too.
$ListChecks = @(
	@{ File = 'SelfX.Code.json'; Expected = $ExpectedCodeHash; Placeholder = '__SELFX_CODE_HASH__' },
	@{ File = 'SelfX.Config.json'; Expected = $ExpectedConfigHash; Placeholder = '__SELFX_CONFIG_HASH__' }
)
ForEach($Check in $ListChecks)
{
	If($Check.Expected -match '^[0-9A-Fa-f]{64}\z')
	{
		$FilesProblem = Test-SelfXFilesList -Path (Join-Path $InstallFolder $Check.File) -ExpectedHash $Check.Expected
		If($FilesProblem) { Exit-Detection 1 "not detected ($FilesProblem)" }
	}
	ElseIf($Check.Expected -eq $Check.Placeholder) { Write-DetectionLog "No digest of $($Check.File) embedded (script not created by New-SelfXIntuneWin.ps1): version check only." }
	Else { Exit-Detection 1 "not detected (invalid digest of $($Check.File) in this script)" }
}

Exit-Detection 0 'detected'
