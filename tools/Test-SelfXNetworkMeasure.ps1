<#
.SYNOPSIS
    Checks Network_Test_Config.xml and optionally runs the network measurements of SelfX once on this computer.

.DESCRIPTION
    For administrators, before the package is distributed. Reads Network_Test_Config.xml (default: the one in
    SelfX Service\Sources), prints the settings, the targets and the entries that are not valid. With -Run the
    measurements are made (default gateway, name lookup, TCP connection time) and the result lines are printed
    as they appear in the System information of SelfX. Without -Run nothing is measured.
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
    Version : 2.8.8

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.8    2026-11-22  fubu2k               Initial version
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
Write-Output ("Enabled: {0}, gateway: {1}, samples: {2}, timeout: {3} ms, targets: {4}" -f $config.Enabled, $config.Gateway, $config.Samples, $config.TimeoutMs, @($config.Targets).Count)
foreach ($target in @($config.Targets)) {
    $port = $(if ($target.Port) { ":$($target.Port)" } else { '' })
    Write-Output ("  {0}: {1}{2}" -f $target.Label, $target.Host, $port)
}
if (-not $Run) { return }
$config.Enabled = $true
$gateways = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' | ForEach-Object { $_.DefaultIPGateway } | Where-Object { $_ })
foreach ($item in @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -Gateways $gateways)) {
    $mark = $(if ($item.Status) { " [$($item.Status)]" } else { '' })
    Write-Output ("{0,-34}: {1}{2}" -f $item.Property, $item.Value, $mark)
}
