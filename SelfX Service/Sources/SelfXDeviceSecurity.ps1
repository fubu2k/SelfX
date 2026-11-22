<#
.SYNOPSIS
    Reads device security state (Secure Boot, BitLocker, TPM) without the SecureBoot, BitLocker and TrustedPlatformModule modules.

.DESCRIPTION
    Dot-sourced by HealthStatus.ps1 and HealthChecks\Check-Compliance.ps1. Confirm-SecureBootUEFI runs in PowerShell 7 only through the Windows
    PowerShell 5.1 compatibility layer and needs administrator rights. The value UEFISecureBootEnabled in
    HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State is what Windows itself publishes (checked on Windows 11 build 26300: 1 = on,
    readable without administrator rights, same result as Confirm-SecureBootUEFI run as administrator).
    BitLocker: CIM Win32_EncryptableVolume (root\CIMV2\Security\MicrosoftVolumeEncryption), TPM: CIM Win32_Tpm
    (root\CIMV2\Security\MicrosoftTpm). Both were readable without administrator rights on Windows 11 build 26300 and gave the same
    values as Get-BitLockerVolume and Get-Tpm. The service runs them as SYSTEM.

.NOTES
    Name    : SelfXDeviceSecurity.ps1
    Package : SelfX Service
    Context : User and System, dot-sourced
    Version : 2.6.10

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version: Secure Boot from the registry; BitLocker and TPM through CIM
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

# BitLocker volumes (one object per Win32_EncryptableVolume): MountPoint, VolumeType (OperatingSystem, FixedData, Removable),
# ProtectionStatus (On, Off, Unknown) and VolumeStatus (as Get-BitLockerVolume). Throws when the class cannot be read.
function Get-SelfXBitLockerVolumes {
	$types = @{ 0 = 'OperatingSystem'; 1 = 'FixedData'; 2 = 'Removable' }
	$protection = @{ 0 = 'Off'; 1 = 'On'; 2 = 'Unknown' }
	$conversion = @{ 0 = 'FullyDecrypted'; 1 = 'FullyEncrypted'; 2 = 'EncryptionInProgress'; 3 = 'DecryptionInProgress'; 4 = 'EncryptionPaused'; 5 = 'DecryptionPaused' }
	foreach ($volume in @(Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -ErrorAction Stop)) {
		[pscustomobject]@{
			MountPoint       = "$($volume.DriveLetter)"
			VolumeType       = if ($null -ne $volume.VolumeType -and $types.ContainsKey([int]$volume.VolumeType)) { $types[[int]$volume.VolumeType] } else { 'Unknown' }
			ProtectionStatus = if ($null -ne $volume.ProtectionStatus -and $protection.ContainsKey([int]$volume.ProtectionStatus)) { $protection[[int]$volume.ProtectionStatus] } else { $null }
			VolumeStatus     = if ($null -ne $volume.ConversionStatus -and $conversion.ContainsKey([int]$volume.ConversionStatus)) { $conversion[[int]$volume.ConversionStatus] } else { $null }
		}
	}
}

# TPM: TpmPresent (a Win32_Tpm instance exists) and TpmReady (enabled, activated and owned). Throws when the class cannot be read.
function Get-SelfXTpmStatus {
	$tpm = @(Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop) | Select-Object -First 1
	if ($null -eq $tpm) { return [pscustomobject]@{ TpmPresent = $false; TpmReady = $false } }
	[pscustomobject]@{
		TpmPresent = $true
		TpmReady   = [bool]($tpm.IsEnabled_InitialValue -and $tpm.IsActivated_InitialValue -and $tpm.IsOwned_InitialValue)
	}
}
