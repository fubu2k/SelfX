<#
.SYNOPSIS
    Detect the expected locally installed SelfX Service package version.

.DESCRIPTION
    Read-only Intune/SCCM detection for ProgramFiles\SelfX. Requires SelfXService.exe, SelfX.exe,
    Tool_Config.xml, a registered SelfXService and an exact Tool_Version match of 2.8.0.
    Does not start the service, contact the pipe, verify that it is running or execute
    remediation scripts. Writes an installed message and exits 0 when checks pass; exits
    1 for a missing prerequisite or version mismatch. XML read/parse errors are not caught.
    Logs the result to ProgramData\SelfX\Logs\Detection_<date>.log when that folder exists.

.NOTES
    Name    : Detection.ps1
    Package : SelfX Service
    Context : Detection
    Version : 2.8.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.8.0    2026-11-22  fubu2k               Detect version 2.8.0 (PowerShell 7, Windows 11 25H2)
#>

$ExpectedVersion = '2.8.0'
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

Exit-Detection 0 'detected'
