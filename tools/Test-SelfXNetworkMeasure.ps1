<#
.SYNOPSIS
    Checks Network_Test_Config.xml and optionally runs the network measurements of SelfX once on this computer.

.DESCRIPTION
    For administrators, before the package is distributed. Reads Network_Test_Config.xml (default: the one in
    SelfX Service\Sources), prints the settings, the targets and the entries that are not valid. With -Run the
    measurements are made (default gateway, name lookup, TCP connection time) and the result lines are printed
    as they appear in the System information of SelfX, with the four traffic-light rows (Local, Internet, Microsoft,
    Company) and the one-sentence verdict. Without -Run nothing is measured.
    Runs in the context of the current user, only reads, changes nothing.

.PARAMETER ConfigPath
    Network_Test_Config.xml to check.

.PARAMETER Run
    Make the measurements. Switched-off measurements (Enabled="False") are measured too, to test targets
    before they are enabled.

.EXAMPLE
    .\Test-SelfXNetworkMeasure.ps1 -Run

.NOTES
    Name    : Test-SelfXNetworkMeasure.ps1
    Package : tools
    Context : Build machine or test device (any user)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.8    2026-11-22  fubu2k               Initial version
    3.1.0    2026-11-27  fubu2k               Prints Microsoft, HostNames, group and kind of the targets; -Run also prints the rows and the verdict
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\SelfX Service\Sources\Network_Test_Config.xml'),
    [switch]$Run
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\SelfX Service\Sources\SystemInfo.ps1')
$config = Read-SelfXNetworkTestConfig -Path $ConfigPath
Write-Output "File: $ConfigPath"
foreach ($message in $config.Errors) { Write-Warning $message }
Write-Output ("Enabled: {0}, gateway: {1}, Microsoft targets: {2}, host names in the report: {3}, samples: {4}, timeout: {5} ms, targets: {6}" -f $config.Enabled, $config.Gateway, $config.Microsoft, $config.HostNames, $config.Samples, $config.TimeoutMs, @($config.Targets).Count)
foreach ($target in @($config.Targets)) {
    $port = $(if ($target.Port) { ":$($target.Port)" } else { '' })
    $group = $(if ($target.Group) { " [$($target.Group)$(if ($target.Kind) { ', ' + $target.Kind })]" } else { '' })
    Write-Output ("  {0}: {1}{2}{3}" -f $target.Label, $target.Host, $port, $group)
}
if (-not $Run) { return }
$config.Enabled = $true
$gateways = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' | ForEach-Object { $_.DefaultIPGateway } | Where-Object { $_ })
# The Internet test of the system information counts as one Internet target (same default host and port as Get-SelfXSystemInfo).
$internetReachable = [bool](Test-SelfXTcpConnection -HostName 'www.msftconnecttest.com' -Port 80)
foreach ($item in @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -Gateways $gateways -InternetTestReachable $internetReachable)) {
    $mark = $(if ($item.Status) { " [$($item.Status)]" } else { '' })
    Write-Output ("{0,-34}: {1}{2}" -f $item.Property, $item.Value, $mark)
}
