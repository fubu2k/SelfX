<#
.SYNOPSIS
    Restart the network adapters that connect the device, to refresh connectivity.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service". Restarts the physical network adapters that are present and not Disabled,
    without confirmation. In a virtual machine (Hyper-V, VMware) the network adapters are no
    physical adapters; then the adapters that carry a default route are restarted instead
    (never Hyper-V host switches, VPN or Bluetooth adapters). Does not toggle the Windows
    airplane-mode setting. Active network traffic and remote connections are interrupted for
    a few seconds; deliberately disabled adapters remain untouched.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Exit 0 = all selected adapters restarted; exit 1 = no adapter found or a restart failed.

.NOTES
    Name    : SelfX_Device_AirePlaneMode.ps1
    Package : SelfX Service
    Context : System
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1) and exit code
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# Selects the adapters to restart from the objects of Get-SelfXNetAdapters (SelfXNetwork.ps1) and the interface indexes with a default route.
function Select-SelfXRestartAdapters {
	param([object[]]$Adapters = @(), [int[]]$GatewayIndexes = @())
	$enabled = @($Adapters | Where-Object { $_ -and "$($_.Status)" -notin @('Disabled', 'Not Present') })
	# Physical adapters (hardware, not virtual); preserve adapters the user or administrator disabled.
	$physical = @($enabled | Where-Object { ($_.HardwareInterface -eq $true -or $_.ConnectorPresent -eq $true) -and $_.Virtual -ne $true })
	if ($physical.Count) { return $physical }
	# Virtual machine: its network adapters are virtual. Restart those that connect the device.
	return @($enabled | Where-Object {
		($GatewayIndexes -contains [int]$_.ifIndex) -and
		"$($_.InterfaceDescription)" -notmatch 'Hyper-V Virtual Ethernet Adapter|VPN|AnyConnect|GlobalProtect|Fortinet|WireGuard|Pulse|Zscaler|PANGP|TAP-Windows|Bluetooth'
	})
}

# Dot-sourcing (tests) only defines the function.
if ($MyInvocation.InvocationName -ne '.') {
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXNetwork.ps1')
	$gateways = @()
	try { $gateways = @(Get-SelfXDefaultRouteInterfaceIndexes) } catch { Write-SelfXLog "Default routes not readable: $($_.Exception.Message)" Warning }
	$adapters = @(Select-SelfXRestartAdapters -Adapters @(Get-SelfXNetAdapters) -GatewayIndexes $gateways)
	if (-not $adapters.Count) {
		Write-SelfXLog 'No network adapter to restart was found.' Warning
		Write-Output 'No network adapter to restart was found.'
		exit 1
	}
	$failed = 0
	foreach ($adapter in $adapters) {
		try {
			Restart-SelfXNetAdapter -Adapter $adapter
			Write-SelfXLog "Restarted '$($adapter.Name)' ($($adapter.InterfaceDescription))."
		} catch {
			$failed++
			Write-SelfXLog "Could not restart '$($adapter.Name)': $($_.Exception.Message)" Error
		}
	}
	Write-Output "$($adapters.Count - $failed) of $($adapters.Count) network adapter(s) restarted."
	Write-SelfXLog "Finished: $($adapters.Count - $failed) of $($adapters.Count) adapter(s) restarted."
	if ($failed) { exit 1 }
	exit 0
}
