<#
.SYNOPSIS
    Ask Windows to apply the group policies again (gpupdate /force) on a domain or hybrid joined device.

.DESCRIPTION
    Runs non-interactively in the context of the signed-in user (no administrator rights, no SELFX service). Checks that
    the device is joined to a domain (Win32_ComputerSystem.PartOfDomain; hybrid Entra joined devices are domain joined
    too). On other devices (for example Entra ID joined only, workgroup) nothing is started and the exit code is 3.
    Then runs "gpupdate.exe /force" from System32 with fixed arguments and waits for it (at most 5 minutes; a longer
    run is ended and counts as an error). The switches /logoff and /boot are never used, so Windows is neither
    restarted nor is the user signed out; a policy that needs a restart or a new sign-in takes effect after the next
    one. The input of gpupdate is an empty file, so a question of the program ("sign out now?") is never answered with
    yes. Nothing from the caller is used. Does not change the policies, the registry or any file itself.
    Logs to the user log of SelfX (SelfXLog.ps1).
    Exit 0 = gpupdate finished successfully; exit 1 = gpupdate failed, did not finish in time or could not be started;
    exit 3 = the device is not joined to a domain (nothing was done).

.NOTES
    Name    : SelfX_Device_GpUpdate.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.16

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard, gpupdate with echo y)
    2.8.16   2026-11-23  fubu2k               Only domain / hybrid devices, no echo y, empty input, waits with a time limit and exit code, never /boot or /logoff
#>

# Logging (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; Write-Output "Group policy update failed: $($_.Exception.Message)"; exit 1 }

$computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
if (-not $computer.PartOfDomain) {
	Write-SelfXLog 'The device is not joined to a domain; nothing was done.' Warning
	Write-Output 'This device is not joined to a domain; group policies are not used.'
	exit 3
}

# Fixed program and fixed arguments. The input is an empty file: gpupdate can never receive "y".
$gpupdate = Join-Path $env:SystemRoot 'System32\gpupdate.exe'
$emptyInput = [IO.Path]::GetTempFileName()
try {
	Write-SelfXLog 'gpupdate /force started.'
	$process = Start-Process -FilePath $gpupdate -ArgumentList '/force' -RedirectStandardInput $emptyInput -PassThru -WindowStyle Hidden -ErrorAction Stop
	if (-not $process.WaitForExit(300000)) {
		try { $process.Kill() } catch { Write-SelfXLog "gpupdate could not be ended: $($_.Exception.Message)" Warning }
		Write-SelfXLog 'gpupdate did not finish within 5 minutes and was ended.' Error
		Write-Output 'The group policy update did not finish in time.'
		exit 1
	}
	Write-SelfXLog "gpupdate /force finished with exit code $($process.ExitCode)."
	if ($process.ExitCode -ne 0) {
		Write-Output "Group policy update failed (exit code $($process.ExitCode))."
		exit 1
	}
	Write-Output 'Group policies updated.'
	exit 0
} finally {
	Remove-Item -LiteralPath $emptyInput -Force -ErrorAction SilentlyContinue
}
