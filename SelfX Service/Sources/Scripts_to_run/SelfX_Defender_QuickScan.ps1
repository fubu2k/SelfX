<#
.SYNOPSIS
    Run a Microsoft Defender quick scan and report whether it found threats.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe "SelfX.Service" when the
    user confirms the action. Starts a quick scan (CIM MSFT_MpScan.Start, ScanType 1 = quick scan, as Start-MpScan
    -ScanType QuickScan) and waits until it has finished. Afterwards the detections of Defender since the start of
    the scan are read (MSFT_MpThreatDetection, MSFT_MpThreat): only the number and the names of the threats are
    logged, never file paths. SelfX does not remove, quarantine or release anything itself; what Defender does with a
    threat follows the policy of the device. Does not change Defender settings, does not update the signatures, does
    not restart Windows and does not sign out the user.
    The scan can take several minutes and slows the device down meanwhile; the service allows 40 minutes
    (TimeoutSeconds in the catalogue). Defender must be the active antivirus (another antivirus product, a stopped
    service or switched-off protection gives exit 1).
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Exit 0 = scan finished, no threats found; exit 1 = scan could not be run or failed;
    exit 2 = scan finished and Defender detected threats (details in Windows Security).

.NOTES
    Name    : SelfX_Defender_QuickScan.ps1
    Package : SelfX Service
    Context : System
    Version : 2.8.15

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin, full scan)
    2.8.15   2026-11-23  fubu2k               Quick scan through CIM (no job, no Start-MpScan), the result is read from the detections
                                              (the original always reported "no threats"), no file paths, exit codes 0 / 1 / 2
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }

$ErrorActionPreference = 'Stop'
try {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXDefender.ps1')
    $status = Get-SelfXDefenderStatus
    if (-not $status -or -not $status.AMServiceEnabled -or -not $status.AntivirusEnabled) {
        throw 'Microsoft Defender Antivirus is not active on this device (another antivirus product may be in use).'
    }
    Write-SelfXLog "Defender running mode: $($status.AMRunningMode); signature version $($status.AntivirusSignatureVersion)."

    # Detections are counted from one minute before the start (clock differences between Defender and this script).
    $since = (Get-Date).AddMinutes(-1)
    Write-SelfXLog 'Quick scan started.'
    Start-SelfXDefenderQuickScan
    Write-SelfXLog 'Quick scan finished.'

    $threats = @(Get-SelfXDefenderDetection -Since $since)
    if ($threats.Count) {
        $text = "Defender detected $($threats.Count) threat(s) during the quick scan: $(($threats | ForEach-Object { "$($_.Name) (x$($_.Count))" }) -join ', ')."
        Write-SelfXLog $text Warning
        Write-Output $text
        exit 2
    }
    Write-SelfXLog 'No threats found.'
    Write-Output 'Quick scan finished, no threats found.'
    exit 0
} catch {
    Write-SelfXLog "Defender quick scan failed: $($_.Exception.Message)" Error
    Write-Output "Defender quick scan failed: $($_.Exception.Message)"
    exit 1
}
