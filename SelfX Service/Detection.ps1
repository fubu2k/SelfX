<#
.SYNOPSIS
    Detect the expected locally installed SelfX Service package version.

.DESCRIPTION
    Read-only Intune/SCCM detection for ProgramFiles\SelfX. Requires SelfXService.exe, SelfX.exe,
    Tool_Config.xml, a registered SelfXService, an exact Tool_Version match of 3.0.1 and the file list of the
    package: SelfX.Files.json in the install folder must have the digest that tools\New-SelfXIntuneWin.ps1 writes
    into $ExpectedFilesHash of the Detection.ps1 it creates (build\SelfX-Service-<version>.Detection.ps1; upload that
    file to Intune). So an update with changed files is found even when Tool_Version did not change.
    The copy in the repository still has the placeholder: it checks the version only and logs that.
    Does not start the service, contact the pipe, verify that it is running or execute
    remediation scripts. Writes an installed message and exits 0 when checks pass; exits
    1 for a missing prerequisite or version mismatch. XML read/parse errors are not caught.
    Logs the result to ProgramData\SelfX\Logs\Detection_<date>.log when that folder exists.

.NOTES
    Name    : Detection.ps1
    Package : SelfX Service
    Context : Detection
    Version : 3.0.1

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.8.0    2026-11-22  fubu2k               Detect version 2.8.0 (PowerShell 7, Windows 11 25H2)
    2.8.1    2026-11-23  fubu2k               Security (M2): also compares the digest of the file list SelfX.Files.json with the value
                                              embedded by the packaging tool (changed files are detected without a version change)
    3.0.0    2026-11-23  fubu2k               Detect version 3.0.0 (release)
    3.0.1    2026-11-24  fubu2k               Detect version 3.0.1
#>

$ExpectedVersion = '3.0.1'
# Digest of the file list of the package. tools\New-SelfXIntuneWin.ps1 replaces the placeholder in the Detection.ps1 it writes
# to the build folder; the repository copy keeps it (version check only).
$ExpectedFilesHash = '__SELFX_FILES_HASH__'
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
# The same function is in tools\New-SelfXIntuneWin.ps1 (Test-Detection.ps1 checks that both give the same value).
function Get-SelfXFilesDigest {
	param([Parameter(Mandatory = $true)][hashtable]$Files)
	$names = [string[]]@($Files.Keys)
	[Array]::Sort($names, [StringComparer]::Ordinal)
	$text = [string]::Join("`n", @($names | ForEach-Object { '{0}={1}' -f $_, "$($Files[$_])".ToUpperInvariant() }))
	$sha = [Security.Cryptography.SHA256]::Create()
	try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))) -replace '-', '') }
	finally { $sha.Dispose() }
}

# Returns $null when the installed file list has the expected digest, otherwise the reason.
function Test-SelfXFilesList {
	param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ExpectedHash)
	If(-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'SelfX.Files.json missing' }
	Try
	{
		$list = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
		If(-not $list -or "$($list.ManifestVersion)" -ne '1' -or -not $list.Files) { return 'SelfX.Files.json has an unknown format' }
		$files = @{}
		ForEach($property in @($list.Files.PSObject.Properties)) { $files[$property.Name] = "$($property.Value)" }
		If($files.Count -eq 0) { return 'SelfX.Files.json lists no files' }
		If((Get-SelfXFilesDigest -Files $files) -ne $ExpectedHash.ToUpperInvariant()) { return 'file list differs from the package' }
	}
	Catch { return 'SelfX.Files.json cannot be read' }
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

# The file list of the package: changed files without a new Tool_Version are an update too.
If($ExpectedFilesHash -match '^[0-9A-Fa-f]{64}\z')
{
	$FilesProblem = Test-SelfXFilesList -Path (Join-Path $InstallFolder 'SelfX.Files.json') -ExpectedHash $ExpectedFilesHash
	If($FilesProblem) { Exit-Detection 1 "not detected ($FilesProblem)" }
}
ElseIf($ExpectedFilesHash -eq '__SELFX_FILES_HASH__') { Write-DetectionLog 'No file list digest embedded (script not created by New-SelfXIntuneWin.ps1): version check only.' }
Else { Exit-Detection 1 'not detected (invalid file list digest in this script)' }

Exit-Detection 0 'detected'
