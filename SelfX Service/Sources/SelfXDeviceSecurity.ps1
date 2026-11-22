<#
.SYNOPSIS
    Reads device security state (Secure Boot) without the SecureBoot module.

.DESCRIPTION
    Dot-sourced by HealthChecks\Check-Compliance.ps1. Confirm-SecureBootUEFI runs in PowerShell 7 only through the Windows
    PowerShell 5.1 compatibility layer and needs administrator rights. The value UEFISecureBootEnabled in
    HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State is what Windows itself publishes (checked on Windows 11 build 26300: 1 = on,
    readable without administrator rights, same result as Confirm-SecureBootUEFI run as administrator).

.NOTES
    Name    : SelfXDeviceSecurity.ps1
    Package : SelfX Service
    Context : User and System, dot-sourced
    Version : 2.6.10

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version: Secure Boot from the registry
#>

# $true / $false. Throws [System.PlatformNotSupportedException] when the value does not exist (legacy BIOS, as Confirm-SecureBootUEFI).
function Get-SelfXSecureBootEnabled {
	param([string]$Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State')
	$item = $null
	if (Test-Path -LiteralPath $Path) { $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop }
	if ($null -eq $item -or $null -eq $item.PSObject.Properties['UEFISecureBootEnabled']) {
		throw [System.PlatformNotSupportedException]::new('Secure Boot state is not available (legacy BIOS).')
	}
	return ([int]$item.UEFISecureBootEnabled -eq 1)
}
