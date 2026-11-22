<#
.SYNOPSIS
    Synchronize the system clock with the configured time source (Windows Time service).

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service". Checks that the Windows Time service (W32Time) exists and is not disabled,
    starts it when it is stopped and runs "w32tm.exe /resync /force" with fixed arguments from
    System32. The time source and the time service configuration are not changed (no /config),
    and no time or time zone is set by hand. A wrong clock is a common reason for sign-in and
    certificate errors; after the synchronization the user can try again. Does not restart Windows.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Exit 0 = synchronization done; exit 1 = Windows Time service missing, disabled or not
    startable, or the synchronization failed (for example no time source reachable).

.NOTES
    Name    : SelfX_Device_SyncTime.ps1
    Package : SelfX Service
    Context : System
    Version : 2.8.2

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.2    2026-11-22  fubu2k               Initial version (fixed arguments, configuration unchanged)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# The service is normally started on demand (trigger start); a stopped service is started, a disabled one is not changed.
$service = Get-Service -Name W32Time -ErrorAction Stop
Write-SelfXLog "W32Time before the synchronization: $($service.Status) (start type $($service.StartType))."
if ("$($service.StartType)" -eq 'Disabled') {
	Write-SelfXLog 'The Windows Time service is disabled; the configuration is not changed.' Error
	Write-Output 'The Windows Time service is disabled.'
	exit 1
}
if ("$($service.Status)" -ne 'Running') {
	Start-Service -Name W32Time -ErrorAction Stop
	Write-SelfXLog 'W32Time started.'
}

# Fixed program and fixed arguments; nothing from the caller is used.
$w32tm = Join-Path $env:SystemRoot 'System32\w32tm.exe'
$process = Start-Process -FilePath $w32tm -ArgumentList '/resync', '/force' -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
Write-SelfXLog "w32tm /resync /force finished with exit code $($process.ExitCode)."
if ($process.ExitCode -ne 0) {
	Write-Output "Time synchronization failed (exit code $($process.ExitCode))."
	exit 1
}
Write-Output 'Time synchronized.'
exit 0
