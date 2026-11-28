<#
.SYNOPSIS
    Install SelfX files, the local Windows service, and machine-wide shortcuts.

.DESCRIPTION
    Runs in elevated 64-bit Windows PowerShell 5.1, normally as SYSTEM via Intune/SCCM.
    Requires Windows 11 25H2 (build 26200) or newer, or Windows Server 2022 or 2025 with Desktop Experience (build 20348 or newer;
    there SelfX works as on a terminal server). On older builds, on Server Core, on a domain controller and on Windows Enterprise
    multi-session it stops before anything is changed.
    Stops and deletes an existing SelfXService, deletes the entire content of InstallFolder
    (default ProgramFiles\SelfX; the folder itself is kept because an open SelfX window or
    status icon may use it as working directory, locked files are retried for 20 seconds),
    copies App (code) and Config (configuration) of the package into InstallFolder\App and InstallFolder\Config, puts
    Uninstall.ps1 into App, and installs the service SelfXService.exe and the console-less
    starter SelfX.exe (SelfXLauncher.cs) used by the shortcuts and the status icon. Both are .NET 10
    programs (self-contained: no .NET runtime is needed on the device) that are built centrally by
    tools\Build-SelfXBinaries.ps1 into the folder Bin of the package (installed into App). Before anything on the device is
    changed, Install.ps1 checks them: the manifest Bin\SelfX.Binaries.json must list the SHA256 of the
    sources in the package and of each file. A missing Bin folder or any failed check stops the
    installation with the old installation still in place (nothing is compiled on the device any more).
    Trust mode (docs\Architecture.md): without -TrustedSigner the mode is Hash, as before (the files need no signature;
    AppLocker/WDAC allow them with hash rules). With -TrustedSigner <thumbprint>[,<thumbprint>] the mode is Signature:
    every .exe, .dll, .ps1, .psm1 and .psd1 of the package must have an Authenticode signature with the status Valid of one of
    the given signers (SHA1 thumbprints, 40 hexadecimal characters), Config\SelfX.Config.cat must be signed by one of them and
    match the folder Config, and SelfX.Code.cat (top of the package) must be signed by one of them and match everything else in
    the package (App, Bin, Service, the scripts at the top; so SelfX.Code.json, the language files and the images are covered
    too). SelfX.Code.json and SelfX.Config.json are checked in both modes. Any difference stops the installation before
    anything on the device is changed. The two catalogs are installed next to the lists (App\SelfX.Code.cat,
    Config\SelfX.Config.cat): the service checks the lists against them before every start. The revocation check
    is the one of Windows (Get-AuthenticodeSignature): a revocation list that cannot be reached does not make a signature
    invalid. After the files are installed, the anchor is written to HKLM\SOFTWARE\SelfX\Trust: Mode (Hash or Signature) and
    Signers (REG_MULTI_SZ, only in the mode Signature); SYSTEM (S-1-5-18) and Administrators (S-1-5-32-544) have full control,
    users (S-1-5-32-545) can read. A device whose anchor says Signature is installed in the mode Hash only with the explicit
    switch -AllowHashMode (protection against a downgrade); -AllowHashMode together with -TrustedSigner is an error.
    Parameters are bound by name only.
    Mode -ConfigOnly (package of the assistant that holds only Install.ps1 and Config): replaces the folder Config of an existing
    installation and nothing else; the service, the programs, the shortcuts and the trust anchor are not touched and nothing is
    restarted (the service reads its settings anew at every use; an open SelfX window keeps its texts until it is closed). The
    trust mode is the one of the anchor on the device: -TrustedSigner and -AllowHashMode are errors. Mode Signature: Install.ps1
    and every script of the package must be signed by a signer of the anchor, Config\SelfX.Config.cat must be signed by one of
    them and match Config; mode Hash: no catalog. Config\SelfX.Config.json must list exactly the files of Config and must have
    MinCodeVersion; the installed code (ToolVersion of App\SelfX.Code.json) must not be older. Settings that are applied only at
    installation (shortcuts, status icon entry, icon, service privileges) must not differ from the installed Tool_Config.xml: such
    a change needs the full package. The new folder is built next to the install folder (InstallFolder.ConfigStage), checked
    there, and exchanged by two renames (the old one becomes InstallFolder.ConfigOld); an error at any step puts the old folder
    back. A script of an action that is running keeps the folder locked: the exchange is retried for 20 seconds, then it stops
    and the old configuration stays. No change before all checks have passed. Exits 0 or 1 as the full installation does.
    Registers and starts an automatic LOCAL SYSTEM service with recovery restart actions.
    Restricts installed files against user modification and ProgramData\SelfX logs and the
    status cache to SYSTEM/administrators. Creates ProgramData\SelfX\Logs\Users, in which users
    may only create their own log folder (CREATOR OWNER) and cannot list or read other folders
    (logs of the SelfX window, the status icon and the user actions, SelfXLog.ps1). Creates configured public desktop/Start Menu shortcuts and the
    HKLM Apps & Features entry, using Brand_Icon when a valid .ico exists. When Show_Tray_Icon
    is True in Tool_Config.xml, the HKLM Run entry "SelfXTray" starts the status icon
    (SelfX_Tray.ps1) at every sign-in for all users; otherwise the entry is removed. Running
    status icons are closed before the files are replaced. When the installer runs as SYSTEM,
    the new status icon is then started right away in every active user session with the
    (not elevated) rights of the signed-in user (SelfXSessionStarter.dll from Bin, loaded from the package);
    in other contexts it appears at the next sign-in. A failed start is logged and does not
    fail the installation. Open SelfX windows are not closed. Reinstallation
    removes local customizations in InstallFolder and interrupts service actions. No Windows
    restart is requested. Exits 0 on success or 1 for caught installation failures; initial
    privilege, edition and bitness checks throw before the installation try block.

.NOTES
    Name    : Install.ps1
    Package : SelfX Service
    Context : Installer (SYSTEM via Intune/SCCM)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.8.3    2026-11-23  fubu2k               SelfX.Files.json also lists SelfXService.exe and SelfX.exe; after copying, the installed
                                              folder is checked against the list again
    2.8.4    2026-11-23  fubu2k               Security (M1): the data folder is cleaned by the delete helper of SelfXService.exe (handle-based, no
                                              time window between link check and delete); the Bin check runs before the data folder is prepared
    2.8.5    2026-11-23  fubu2k               Security (N4): SelfXSessionStarter.dll is read once, compared with the hash verified at the start and
                                              loaded from these bytes (no time between check and load in the Intune staging folder)
    2.8.6    2026-11-24  fubu2k               Security: the PowerShell 7 rights check is the same as the service's (SID based, only SYSTEM,
                                              Administrators and TrustedInstaller, folders above pwsh.exe included, unreadable rights refuse)
    2.9.0    2026-11-27  fubu2k               Two file lists instead of SelfX.Files.json: SelfX.Code.json (programs, libraries, scripts, language
                                              files, images of the project) and SelfX.Config.json (settings, Branding, own scripts and language
                                              files); every file in exactly one list, a file in the wrong list is refused
    2.9.1    2026-11-27  fubu2k               The version is read from ToolVersion of SelfX.Code.json (the version is a property of the code), no
                                              longer from Tool_Version of Tool_Config.xml (an old element there is ignored); a package without
                                              SelfX.Code.json has no version and is refused before anything is changed
    3.1.0    2026-11-27  fubu2k               Code and configuration in two folders: the package has App\ and Config\, the device gets
                                              InstallFolder\App (programs, libraries, scripts, Uninstall.ps1, SelfX.Code.json) and InstallFolder\Config
                                              (settings, Branding, own scripts and language files, SelfX.Config.json), rights unchanged; an
                                              installation in the old layout is removed completely before the copy, and afterwards the install
                                              folder may hold nothing but App and Config; a package in the old layout (Sources) is refused
    3.1.0    2026-11-27  fubu2k               Text overrides: Texts/<culture>.xml is accepted in SelfX.Config.json (placement rule); nothing below Texts
                                              may be in SelfX.Code.json
    3.1.0    2026-11-27  fubu2k               Security: trust mode Signature with -TrustedSigner (every .exe, .dll and script of the package signed by
                                              an allowed signer, signed catalogs Config\SelfX.Config.cat and SelfX.Code.cat, checked before anything
                                              is changed); trust anchor HKLM\SOFTWARE\SelfX\Trust (Mode, Signers) in both modes; -AllowHashMode for
                                              the change from Signature to Hash; parameters are bound by name only
    3.1.0    2026-11-27  fubu2k               Trust mode Signature: the signed catalogs are installed (SelfX.Code.cat into App, Config\SelfX.Config.cat
                                              into Config) and compared with the checked catalogs after the copy; the service reads them
    3.1.0    2026-11-27  fubu2k               Mode -ConfigOnly: a package with only Install.ps1 and Config replaces the folder Config of an existing
                                              installation (checks like the full installation, MinCodeVersion, no change of install-time settings,
                                              exchange by rename with rollback); service, programs and trust anchor stay untouched
    3.1.0    2026-11-28  fubu2k               Windows Server 2022 and 2025 with Desktop Experience (build 20348 or newer) are supported next to
                                              Windows 11 25H2; Server Core, domain controllers and Windows Enterprise multi-session stop the
                                              installation before anything is changed (Test-SelfXWindowsSupport)
    3.1.0    2026-11-28  fubu2k               New library Disturb\SelfXDisturb.dll (state of the notification area): expected, checked and installed like
                                              Audio\SelfXAudio.dll
#>

# Parameters are bound by name only: a thumbprint that is separated by a space instead of a comma must not become the install folder.
[CmdletBinding(PositionalBinding = $false)]
param(
	[string]$InstallFolder = (Join-Path $env:ProgramFiles 'SelfX'),
	# Trust mode Signature: SHA1 thumbprints (40 hexadecimal characters) of the allowed signers, separated by commas.
	[string[]]$TrustedSigner = @(),
	# Allows the mode Hash on a device whose trust anchor says Signature.
	[switch]$AllowHashMode,
	# Configuration package: replaces only the folder Config of an existing installation (see the description).
	[switch]$ConfigOnly
)

$ErrorActionPreference = 'Stop'
$ServiceName = 'SelfXService'
$ServiceDisplayName = 'SelfX Service'
$PackageFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
# Package: App (code) and Config (configuration); device: InstallFolder\App and InstallFolder\Config.
$ConfigSource = Join-Path $PackageFolder 'Config'
$BinFolder = Join-Path $PackageFolder 'Bin'
$AppFolder = Join-Path $InstallFolder 'App'
$ConfigFolder = Join-Path $InstallFolder 'Config'
$DataFolder = Join-Path $env:ProgramData 'SelfX'
$LogFolder = Join-Path $DataFolder 'Logs'
$UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SelfX'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Get-SelfXWindowsInfo {
	# Facts of the running Windows from the registry (not from [Environment]::OSVersion, which an application manifest can falsify).
	# A value that cannot be read stays empty (0 for the build); Test-SelfXWindowsSupport then stops the installation.
	$CurrentVersion = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
	$Info = [ordered]@{ Build = 0; ProductType = ''; InstallationType = ''; EditionId = ''; ServerGuiShell = 0 }
	Try { $Info.Build = [int](Get-ItemProperty -LiteralPath $CurrentVersion -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber } Catch { $Info.Build = 0 }
	Try { $Info.ProductType = [string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -Name ProductType -ErrorAction Stop).ProductType } Catch { $Info.ProductType = '' }
	Try { $Info.InstallationType = [string](Get-ItemProperty -LiteralPath $CurrentVersion -Name InstallationType -ErrorAction Stop).InstallationType } Catch { $Info.InstallationType = '' }
	Try { $Info.EditionId = [string](Get-ItemProperty -LiteralPath $CurrentVersion -Name EditionID -ErrorAction Stop).EditionID } Catch { $Info.EditionId = '' }
	# Windows Server with Desktop Experience has ServerLevels\ServerGuiShell = 1; Server Core does not (Microsoft Learn, "Detecting Minimal
	# Server Interface and Server Core").
	Try { $Info.ServerGuiShell = [int](Get-ItemProperty -LiteralPath (Join-Path $CurrentVersion 'Server\ServerLevels') -Name ServerGuiShell -ErrorAction Stop).ServerGuiShell } Catch { $Info.ServerGuiShell = 0 }
	return [pscustomobject]$Info
}

function Test-SelfXWindowsSupport {
	# SelfX Service runs on Windows 11 25H2 (build 26200) or newer and on Windows Server 2022 or 2025 with Desktop Experience
	# (build 20348 or newer). Everything else stops the installation before anything is changed (hard abort):
	#  - Windows Enterprise multi-session (EditionID ServerRdsh; it reports the product type of a server),
	#  - Server Core (no desktop: the window and the status icon cannot run),
	#  - a domain controller (ProductType LanmanNT), an unknown product type, values that cannot be read.
	# Returns Kind ('Client' or 'Server') and Build. The mode of SelfX follows the product type: Client on Windows 11, TerminalServer on
	# Windows Server (SelfXEnvironment.ps1, SelfXService.cs).
	param(
		$Info = $null,
		[int]$MinimumClientBuild = 26200,
		[int]$MinimumServerBuild = 20348
	)
	If($null -eq $Info) { $Info = Get-SelfXWindowsInfo }
	$Need = "SelfX Service needs Windows 11 25H2 (build $MinimumClientBuild) or newer, or Windows Server 2022 or 2025 with Desktop Experience (build $MinimumServerBuild or newer)."
	$Build = [int]$Info.Build
	$ProductType = "$($Info.ProductType)".Trim()
	$InstallationType = "$($Info.InstallationType)".Trim()
	$EditionId = "$($Info.EditionId)".Trim()
	If($Build -le 0) { throw "The Windows build number cannot be read. $Need" }
	If($EditionId -ieq 'ServerRdsh') { throw "Windows Enterprise multi-session is not supported. $Need" }
	If($ProductType -ieq 'WinNT')
	{
		If($Build -lt $MinimumClientBuild) { throw "Windows build $Build is not supported. $Need" }
		return [pscustomobject]@{ Kind = 'Client'; Build = $Build }
	}
	If($ProductType -ieq 'ServerNT')
	{
		If($InstallationType -ieq 'Server Core' -or ($InstallationType -ieq 'Server' -and [int]$Info.ServerGuiShell -ne 1)) { throw "Windows Server Core is not supported: SelfX needs the desktop (Desktop Experience). $Need" }
		If($InstallationType -ine 'Server') { throw "This kind of Windows (installation type '$InstallationType') is not supported. $Need" }
		If($Build -lt $MinimumServerBuild) { throw "Windows Server build $Build is not supported. $Need" }
		return [pscustomobject]@{ Kind = 'Server'; Build = $Build }
	}
	If($ProductType -ieq 'LanmanNT') { throw "A domain controller is not supported. $Need" }
	If(-not $ProductType) { throw "The product type of Windows cannot be read. $Need" }
	throw "The product type '$ProductType' is not supported. $Need"
}

function Test-SelfXPowerShell7 {
	# Checks the PowerShell 7 that the service, the window and the status icon start (fixed machine-wide path, no PATH
	# search). Returns an object with Ready, Version and Reason.
	#  - pwsh.exe missing or older than the minimum (7.6 is based on .NET 10, the LTS release): Ready = $false with a
	#    reason, and the installation goes on. Autopilot installs apps in any order and must never fail because of this;
	#    until PowerShell 7 is there the service starts no script and says so.
	#  - neither the folder nor pwsh.exe may be changeable by normal users (the service runs it as SYSTEM): THROWS, the
	#    installation stops before anything is changed. The service checks this again before every start.
	#    (The Store version lives in a user-specific folder and is not usable for the service.)
	param(
		[string]$Executable = (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
		[version]$MinimumVersion = '7.6.0',
		# Tests only: the first folder above the file that is no longer checked, and the SIDs that count as trusted.
		[string]$StopBefore = '',
		[string[]]$TrustedSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
	)
	If(-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return [pscustomobject]@{ Ready = $false; Version = $null; Reason = "PowerShell 7 was not found at '$Executable'. Install PowerShell $MinimumVersion or newer (MSI, machine-wide); SelfX works as soon as it is there (docs\Installation.md)." } }
	$Info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Executable)
	$Found = [version]('{0}.{1}.{2}' -f $Info.FileMajorPart, $Info.FileMinorPart, $Info.FileBuildPart)
	If($Found -lt $MinimumVersion) { return [pscustomobject]@{ Ready = $false; Version = $Found; Reason = "PowerShell $Found was found at '$Executable'; version $MinimumVersion or newer is required." } }
	# Same rule as the service before every start (SelfXService.cs, IsPathChainProtected): only SYSTEM, Administrators and
	# TrustedInstaller may change pwsh.exe, its folder or (as far as removing or taking over the folder) the folders above it.
	# Every other identity counts as a normal user (Everyone, Users, Authenticated Users, a domain group, a single account).
	# The rules are read as SIDs, so an unknown or orphaned SID cannot slip through; when the rights cannot be read: refused.
	$Direct = [Security.AccessControl.FileSystemRights]'WriteData, AppendData, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
	$Above = [Security.AccessControl.FileSystemRights]'DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
	$Checks = @(@((Split-Path -Parent $Executable), $Direct), @($Executable, $Direct))
	$Limit = $(If($StopBefore) { [IO.Path]::GetFullPath($StopBefore).TrimEnd('\') } Else { $null })
	$Parent = Split-Path -Parent (Split-Path -Parent $Executable)
	While($Parent)
	{
		If($Limit -and ($Parent.TrimEnd('\') -ieq $Limit)) { break }
		$Checks += ,@($Parent, $Above)
		$Parent = Split-Path -Parent $Parent
	}
	ForEach($Check in $Checks)
	{
		$Item = $Check[0]; $Dangerous = $Check[1]
		Try { $Rules = (Get-Acl -LiteralPath $Item -ErrorAction Stop).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) }
		Catch { throw "The rights of '$Item' could not be read ($($_.Exception.GetType().Name)). PowerShell 7 is not used." }
		ForEach($Rule in $Rules)
		{
			If($Rule.AccessControlType -ne 'Allow') { continue }
			# A rule that only applies to child items (for example CREATOR OWNER in Program Files) says nothing about this item.
			If($Rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
			If(-not ($Rule.FileSystemRights -band $Dangerous)) { continue }
			If($TrustedSids -contains $Rule.IdentityReference.Value) { continue }
			throw "'$Item' can be changed by normal users ($($Rule.IdentityReference.Value)). PowerShell 7 must be installed machine-wide in a folder that only administrators can change."
		}
	}
	return [pscustomobject]@{ Ready = $true; Version = $Found; Reason = '' }
}

function Test-SelfXPrebuiltBinaries {
	# Checks the prebuilt programs of the package (F9). Throws with a reason when any check fails; the caller
	# stops the installation then (fail closed, nothing is compiled instead).
	#  - all three files and the manifest SelfX.Binaries.json exist;
	#  - the manifest lists the SHA256 of the three sources in this package (the files were built from them)
	#    and of the three files (complete, unchanged copy).
	# The files are not signed (decision 2026-11-22: allow them by hash, no certificate).
	# Returns a hashtable <file name in Bin> -> SHA256 that was verified here. A caller that loads one of the files later
	# compares the bytes it really loads with this value (no second look at the staging folder: N4).
	param(
		[Parameter(Mandatory = $true)][string]$BinFolder,
		[Parameter(Mandatory = $true)][string]$PackageFolder
	)
	$Expected = [ordered]@{
		'SelfXService.exe'        = 'Service/SelfXService.cs'
		'SelfX.exe'               = 'Service/SelfXLauncher.cs'
		'SelfXSessionStarter.dll' = 'Service/SelfXSessionStarter.cs'
		'WinRT/SelfXWinRT.dll'    = 'Service/SelfXWinRT.cs'
		'Audio/SelfXAudio.dll'    = 'Service/SelfXAudio.cs'
		'Disturb/SelfXDisturb.dll' = 'Service/SelfXDisturb.cs'
	}
	$Verified = @{}
	$ManifestPath = Join-Path $BinFolder 'SelfX.Binaries.json'
	If(-not (Test-Path -LiteralPath $BinFolder -PathType Container)) { throw 'The folder Bin is missing in the package. Run tools\Build-SelfXBinaries.ps1 and build the package again (docs\Installation.md).' }
	If(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'Bin\SelfX.Binaries.json is missing.' }
	Try { $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json }
	Catch { throw "Bin\SelfX.Binaries.json is not valid JSON: $($_.Exception.Message)" }
	If(-not $Manifest -or "$($Manifest.ManifestVersion)" -ne '3' -or -not $Manifest.Sources -or -not $Manifest.Binaries) { throw 'Bin\SelfX.Binaries.json has an unknown format.' }
	ForEach($Name in $Expected.Keys)
	{
		$Source = $Expected[$Name]
		$SourcePath = Join-Path $PackageFolder ($Source.Replace('/', '\'))
		If(-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "Source $Source is missing in the package." }
		If((Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash -ne "$($Manifest.Sources.$Source)") { throw "Bin\$Name was not built from the $Source of this package (rebuild with tools\Build-SelfXBinaries.ps1)." }
		$File = Join-Path $BinFolder $Name.Replace('/', '\')
		If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Bin\$Name is missing." }
		$FileHash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
		If($FileHash -ne "$($Manifest.Binaries.$Name)") { throw "Bin\$Name does not match its SHA256 in the manifest." }
		$Verified[$Name] = $FileHash
	}
	# The DLLs of the Windows SDK projection in WinRT: only plain file names, each one present and unchanged.
	ForEach($Name in @($Manifest.Binaries.PSObject.Properties.Name))
	{
		If($Expected.Contains($Name)) { continue }
		If($Name -notmatch '^WinRT/[A-Za-z0-9._-]+\.dll$') { throw "Bin\SelfX.Binaries.json lists an unexpected file '$Name'." }
		$File = Join-Path $BinFolder $Name.Replace('/', '\')
		If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Bin\$Name is missing." }
		$FileHash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
		If($FileHash -ne "$($Manifest.Binaries.$Name)") { throw "Bin\$Name does not match its SHA256 in the manifest." }
		$Verified[$Name] = $FileHash
	}
	Return $Verified
}

function Test-SelfXListPlacement {
	# Placement rule: may this name be in this list? Same rule as Test-SelfXListPlacement in tools\SelfXPackage.Common.ps1 and
	# in the service (Test-ServicePipe.ps1 and Test-FileManifest.ps1 check that all copies answer alike). SelfX.Code.json
	# may hold any file that is not a settings file or below Branding; SelfX.Config.json only settings files, files below
	# Branding, own scripts in Scripts_to_run or HealthChecks, own language files and text overrides (Texts/<culture>.xml), so no program, library, Uninstall.ps1,
	# script of the project or image can be moved into the list that the company writes.
	param([string]$Name, [string]$List)
	If($Name -notmatch '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*$' -or $Name -match '(^|/)\.\.?(/|$)') { return $false }
	$ConfigFiles = @('Health_Config.xml', 'Issues_List.xml', 'Network_Test_Config.xml', 'Ticket_Config.xml', 'Tool_Config.xml')
	$IsConfigFile = ($ConfigFiles -contains $Name) -or ($Name -match '^Branding/.+')
	# Nothing below Texts may be in the code list; the configuration list accepts only Texts/<culture>.xml (below).
	If($List -eq 'Code') { return (-not ($IsConfigFile -or ($Name -match '^Texts/.+'))) }
	If($IsConfigFile) { return $true }
	If($Name -match '^(Scripts_to_run|HealthChecks)/[A-Za-z0-9._-]+\.ps1$') { return $true }
	If($Name -match '^Languages/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml$') { return $true }
	If($Name -match '^Texts/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml$') { return $true }
	Return $false
}

function Read-SelfXFileList {
	# Reads SelfX.Code.json or SelfX.Config.json and returns its entries (Name, Hash). Throws when the file is not valid JSON, has an
	# unknown format, lists a name that is not allowed or lists a name in the wrong list (Test-SelfXListPlacement).
	# $Where is the place for the messages ('the package' or 'the installation folder').
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[Parameter(Mandatory = $true)][ValidateSet('SelfX.Code.json', 'SelfX.Config.json')][string]$ListName,
		[Parameter(Mandatory = $true)][string]$Where
	)
	$List = If($ListName -eq 'SelfX.Code.json') { 'Code' } Else { 'Config' }
	Try { $Manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
	Catch { throw "$ListName in $Where is not valid JSON: $($_.Exception.Message)" }
	If(-not $Manifest -or "$($Manifest.ManifestVersion)" -ne '1' -or -not $Manifest.Files) { throw "$ListName in $Where has an unknown format." }
	$Entries = New-Object System.Collections.Generic.List[object]
	ForEach($Property in @($Manifest.Files.PSObject.Properties))
	{
		$Relative = "$($Property.Name)"
		If($Relative -notmatch '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*$' -or $Relative -match '(^|/)\.\.?(/|$)') { throw "$ListName lists an unsupported name '$Relative'." }
		If(-not (Test-SelfXListPlacement -Name $Relative -List $List))
		{
			$Reason = If($List -eq 'Code') { 'it is a configuration file' } Else { 'it is not a configuration file or an own script or language file' }
			throw "$Relative must not be listed in $ListName ($Reason)."
		}
		$Entries.Add([pscustomobject]@{ Name = $Relative; Hash = "$($Property.Value)" })
	}
	Return $Entries.ToArray()
}

function Test-SelfXFileManifest {
	# Checks the package against App\SelfX.Code.json and Config\SelfX.Config.json. Code names are relative to the code folder:
	# Uninstall.ps1 (top of the package), the programs SelfXService.exe and SelfX.exe and the DLLs WinRT/<name>, Audio/<name> and Disturb/<name>
	# (from Bin), everything else from App. Configuration names are relative to Config. Every file below App and Config, every DLL
	# of Bin\WinRT, Bin\Audio and Bin\Disturb, Uninstall.ps1 and both programs must be listed in exactly one of the two lists and unchanged,
	# and nothing may be in App or Config that is not listed. Returns the number of checked files, or $null when the package has
	# neither list (the caller refuses it: no version). A package in the old layout (folder Sources), a mismatch, a missing list
	# or a file in both lists throws before anything is installed.
	# Config\SelfX.Config.cat (the signed catalog of the folder Config) is in no list: with -SignedPackage (trust mode Signature, the
	# catalog was checked by Test-SelfXPackageSignatures) it is skipped, without the switch it is refused like every unlisted file.
	param([Parameter(Mandatory = $true)][string]$PackageFolder, [switch]$SignedPackage)
	$AppSource = Join-Path $PackageFolder 'App'
	$ConfigSource = Join-Path $PackageFolder 'Config'
	If(Test-Path -LiteralPath (Join-Path $PackageFolder 'Sources')) { throw 'The package has the old layout (folder Sources). Build it again with tools\New-SelfXIntuneWin.ps1 (folders App and Config).' }
	$CodePath = Join-Path $AppSource 'SelfX.Code.json'
	$ConfigPath = Join-Path $ConfigSource 'SelfX.Config.json'
	$HasCode = Test-Path -LiteralPath $CodePath -PathType Leaf
	$HasConfig = Test-Path -LiteralPath $ConfigPath -PathType Leaf
	If(-not $HasCode -and -not $HasConfig) { return $null }
	If(-not $HasCode) { throw 'App\SelfX.Code.json is missing in the package (Config\SelfX.Config.json is present).' }
	If(-not $HasConfig) { throw 'Config\SelfX.Config.json is missing in the package (App\SelfX.Code.json is present).' }
	$ProgramNames = @('SelfXService.exe', 'SelfX.exe')
	$Listed = @{}
	ForEach($List in @(@{ Name = 'SelfX.Code.json'; Path = $CodePath }, @{ Name = 'SelfX.Config.json'; Path = $ConfigPath }))
	{
		$ListName = $List.Name
		ForEach($Entry in @(Read-SelfXFileList -Path $List.Path -ListName $ListName -Where 'the package'))
		{
			$Relative = $Entry.Name
			If($Listed.ContainsKey($Relative.ToLowerInvariant()))
			{
				If($Listed[$Relative.ToLowerInvariant()] -eq $ListName) { throw "$Relative is listed twice in $ListName." }
				throw "$Relative is listed in both SelfX.Code.json and SelfX.Config.json."
			}
			If($ListName -eq 'SelfX.Config.json') { $File = Join-Path $ConfigSource $Relative.Replace('/', '\') }
			ElseIf($Relative -eq 'Uninstall.ps1') { $File = Join-Path $PackageFolder 'Uninstall.ps1' }
			ElseIf(($Relative -like 'WinRT/*') -or ($Relative -like 'Audio/*') -or ($Relative -like 'Disturb/*') -or ($ProgramNames -contains $Relative)) { $File = Join-Path (Join-Path $PackageFolder 'Bin') $Relative.Replace('/', '\') }
			Else { $File = Join-Path $AppSource $Relative.Replace('/', '\') }
			If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "$Relative is listed in $ListName but missing in the package." }
			If((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Entry.Hash) { throw "$Relative does not match its SHA256 in $ListName." }
			$Listed[$Relative.ToLowerInvariant()] = $ListName
		}
	}
	# Every file of App, Config and of the libraries in Bin\WinRT, Bin\Audio and Bin\Disturb must be listed in the list of its folder.
	$Folders = @(
		@{ Path = $AppSource; Prefix = ''; List = 'SelfX.Code.json' },
		@{ Path = $ConfigSource; Prefix = ''; List = 'SelfX.Config.json' },
		@{ Path = (Join-Path (Join-Path $PackageFolder 'Bin') 'WinRT'); Prefix = 'WinRT/'; List = 'SelfX.Code.json' },
		@{ Path = (Join-Path (Join-Path $PackageFolder 'Bin') 'Audio'); Prefix = 'Audio/'; List = 'SelfX.Code.json' },
		@{ Path = (Join-Path (Join-Path $PackageFolder 'Bin') 'Disturb'); Prefix = 'Disturb/'; List = 'SelfX.Code.json' }
	)
	ForEach($Folder in $Folders)
	{
		If(-not (Test-Path -LiteralPath $Folder.Path -PathType Container)) { continue }
		$Root = (Get-Item -LiteralPath $Folder.Path -Force).FullName.TrimEnd('\')
		ForEach($Item in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force))
		{
			$Relative = $Folder.Prefix + $Item.FullName.Substring($Root.Length + 1).Replace('\', '/')
			If(($Folder.Prefix -eq '') -and ($Relative -ceq $Folder.List)) { continue }
			If(($Folder.List -eq 'SelfX.Config.json') -and ($Relative -ieq 'SelfX.Config.cat'))
			{
				If($SignedPackage) { continue }
				throw 'The package is signed (Config\SelfX.Config.cat is present) but -TrustedSigner was not given. Install it with -TrustedSigner <thumbprint of the signer> (docs\Installation.md).'
			}
			If($Listed[$Relative.ToLowerInvariant()] -ne $Folder.List) { throw "$Relative is in the package but not listed in $($Folder.List)." }
		}
	}
	If($Listed['uninstall.ps1'] -ne 'SelfX.Code.json') { throw 'Uninstall.ps1 is not listed in SelfX.Code.json.' }
	ForEach($Program in $ProgramNames) { If($Listed[$Program.ToLowerInvariant()] -ne 'SelfX.Code.json') { throw "$Program is not listed in SelfX.Code.json." } }
	Return $Listed.Count
}

function Get-SelfXPackageToolVersion {
	# The version of the package: ToolVersion of App\SelfX.Code.json (the only source; Tool_Config.xml is not read for it). It is written
	# into the registry and the log, so it must be 1 to 30 letters, digits, '.' or '-'. A missing list, a missing or invalid version
	# throws (fail closed).
	param([Parameter(Mandatory = $true)][string]$PackageFolder)
	$ListPath = Join-Path (Join-Path $PackageFolder 'App') 'SelfX.Code.json'
	If(-not (Test-Path -LiteralPath $ListPath -PathType Leaf)) { throw 'App\SelfX.Code.json is missing in the package: the package has no version.' }
	Try { $List = Get-Content -LiteralPath $ListPath -Raw | ConvertFrom-Json }
	Catch { throw 'SelfX.Code.json is not valid JSON.' }
	$Version = If($List) { "$($List.ToolVersion)".Trim() } Else { '' }
	If($Version -notmatch '^[0-9A-Za-z.\-]{1,30}\z') { throw 'SelfX.Code.json has no valid ToolVersion.' }
	Return $Version
}

function Test-SelfXInstalledFiles {
	# After copying: compares the installed folders with the lists copied into them. App\SelfX.Code.json lists the code folder App
	# (scripts, WinRT, Audio and Disturb libraries, SelfXService.exe, SelfX.exe, Uninstall.ps1; names relative to App), Config\SelfX.Config.json
	# the configuration folder Config (names relative to Config). This closes the gap between the check of the package and the copy:
	# every listed file must exist with the listed SHA256, in exactly one of the two lists; no file in App or Config may be unlisted;
	# no link may be in the way; and the install folder itself may hold nothing but App and Config (no mixed state with an older
	# layout; an empty folder that a running process still uses as working folder is allowed). Throws at the first difference.
	# Returns the number of checked files.
	# With -SignedPackage (trust mode Signature) the signed catalog next to each list (App\SelfX.Code.cat, Config\SelfX.Config.cat)
	# must exist and is not counted as an unlisted file; without the switch a catalog is refused like every unlisted file.
	param([Parameter(Mandatory = $true)][string]$InstallFolder, [switch]$SignedPackage)
	$Root = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	$Count = 0
	$Listed = @{}
	ForEach($List in @(@{ Name = 'SelfX.Code.json'; Folder = 'App'; Catalog = 'SelfX.Code.cat' }, @{ Name = 'SelfX.Config.json'; Folder = 'Config'; Catalog = 'SelfX.Config.cat' }))
	{
		$ListName = $List.Name
		$FolderRoot = Join-Path $Root $List.Folder
		$FolderItem = Get-Item -LiteralPath $FolderRoot -Force -ErrorAction SilentlyContinue
		If(-not $FolderItem -or -not $FolderItem.PSIsContainer) { throw "The folder $($List.Folder) is missing in the installation folder." }
		If($FolderItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "The folder $($List.Folder) in the installation folder is a link." }
		$ManifestPath = Join-Path $FolderRoot $ListName
		If(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "$($List.Folder)\$ListName is missing in the installation folder." }
		If($SignedPackage -and -not (Test-Path -LiteralPath (Join-Path $FolderRoot $List.Catalog) -PathType Leaf)) { throw "$($List.Folder)\$($List.Catalog) is missing in the installation folder." }
		ForEach($Entry in @(Read-SelfXFileList -Path $ManifestPath -ListName $ListName -Where 'the installation folder'))
		{
			$Relative = $Entry.Name
			If($Listed.ContainsKey($Relative.ToLowerInvariant()))
			{
				If($Listed[$Relative.ToLowerInvariant()] -eq $ListName) { throw "$Relative is listed twice in $ListName." }
				throw "$Relative is listed in both SelfX.Code.json and SelfX.Config.json."
			}
			$File = [IO.Path]::GetFullPath((Join-Path $FolderRoot $Relative.Replace('/', '\')))
			If(-not $File.StartsWith($FolderRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "$Relative points outside the folder $($List.Folder)." }
			If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "$Relative is missing in the folder $($List.Folder)." }
			If((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Entry.Hash) { throw "$Relative in the folder $($List.Folder) does not match its SHA256 in $ListName." }
			$Listed[$Relative.ToLowerInvariant()] = $ListName
			$Count++
		}
		ForEach($Item in @(Get-ChildItem -LiteralPath $FolderRoot -Recurse -Force))
		{
			$Relative = $Item.FullName.Substring($FolderRoot.Length + 1).Replace('\', '/')
			If($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "$($List.Folder)/$Relative is a link." }
			If($Item.PSIsContainer -or ($Relative -ceq $ListName)) { continue }
			If($SignedPackage -and ($Relative -ieq $List.Catalog)) { continue }
			If($Listed[$Relative.ToLowerInvariant()] -ne $ListName) { throw "$($List.Folder)/$Relative is not listed in $ListName." }
		}
	}
	# The install folder itself: only App and Config. Anything else is left over from an older layout (mixed state).
	ForEach($Item in @(Get-ChildItem -LiteralPath $Root -Force))
	{
		If(($Item.Name -ieq 'App') -or ($Item.Name -ieq 'Config')) { continue }
		If($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "$($Item.Name) in the installation folder is a link." }
		If(-not $Item.PSIsContainer) { throw "$($Item.Name) in the installation folder is left over from an older installation." }
		$Left = @(Get-ChildItem -LiteralPath $Item.FullName -Recurse -Force | Where-Object { (-not $_.PSIsContainer) -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
		If($Left.Count -gt 0) { throw "The folder $($Item.Name) in the installation folder is left over from an older installation and is not empty." }
	}
	Return $Count
}

function Resolve-SelfXInstalledImage {
	# Path of an image named in Tool_Config.xml (Brand_Icon): Branding\... in Config, another relative value in App (default images),
	# a rooted value as it is; $null for a relative value that leaves its folder. Same rule as Get-SelfXImagePath in SelfXPaths.ps1.
	param([string]$Value, [Parameter(Mandatory = $true)][string]$AppFolder, [Parameter(Mandatory = $true)][string]$ConfigFolder)
	$Text = "$Value".Trim()
	If($Text -eq '') { return $null }
	If([IO.Path]::IsPathRooted($Text)) { return $Text }
	$Relative = $Text.Replace('\', '/')
	If($Relative -notmatch '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*\z' -or $Relative -match '(^|/)\.\.?(/|$)') { return $null }
	$Base = $(If($Relative -match '^Branding/.+') { $ConfigFolder } Else { $AppFolder })
	$Base = [IO.Path]::GetFullPath($Base).TrimEnd('\')
	$Full = [IO.Path]::GetFullPath((Join-Path $Base $Relative.Replace('/', '\')))
	If(-not $Full.StartsWith($Base + '\', [StringComparison]::OrdinalIgnoreCase)) { return $null }
	Return $Full
}

function Clear-SelfXInstallFolder {
	# Deletes the whole content of the install folder, so that no old script survives an update. This also removes an installation
	# in the old layout (scripts, configuration and programs directly in the install folder) completely; Test-SelfXInstalledFiles
	# refuses any file that is left next to App and Config afterwards (no mixed state). The folder itself is kept: Windows refuses
	# to delete a folder that is the working directory of a running process (e.g. an open SelfX window or status icon of an older
	# version), which made the update fail with exit code 1. Remaining empty folders do not matter, only files do; locked files are
	# retried (Attempts x DelaySeconds), then the installation stops.
	param(
		[Parameter(Mandatory = $true)][string]$InstallFolder,
		[int]$Attempts = 10,
		[int]$DelaySeconds = 2
	)
	New-Item -ItemType Directory -Path $InstallFolder -Force | Out-Null
	For($Attempt = 1; $Attempt -le $Attempts; $Attempt++)
	{
		ForEach($Item in @(Get-ChildItem -LiteralPath $InstallFolder -Force)) { Remove-Item -LiteralPath $Item.FullName -Recurse -Force -ErrorAction SilentlyContinue }
		If(@(Get-ChildItem -LiteralPath $InstallFolder -Recurse -Force -File).Count -eq 0) { break }
		Start-Sleep -Seconds $DelaySeconds
	}
	$Locked = @(Get-ChildItem -LiteralPath $InstallFolder -Recurse -Force -File | Select-Object -ExpandProperty FullName)
	If($Locked.Count -gt 0) { throw "Files in '$InstallFolder' are in use and cannot be replaced: $($Locked -join ', ')" }
}

function Copy-SelfXPayload {
	# Copies the checked package into the emptied install folder: App\* (code, SelfX.Code.json), Uninstall.ps1, SelfXService.exe,
	# SelfX.exe, Bin\WinRT\*.dll (as listed in Bin\SelfX.Binaries.json), Bin\Audio\SelfXAudio.dll and Bin\Disturb\SelfXDisturb.dll into InstallFolder\App, and
	# Config\* (configuration, SelfX.Config.json) into InstallFolder\Config. Nothing is copied to the install folder itself.
	# With -SignedPackage (trust mode Signature) the two signed catalogs are installed next to their lists: SelfX.Code.cat from
	# the top of the package into App, Config\SelfX.Config.cat into Config. The service checks the lists against them.
	param(
		[Parameter(Mandatory = $true)][string]$PackageFolder,
		[Parameter(Mandatory = $true)][string]$InstallFolder,
		[switch]$SignedPackage
	)
	$Bin = Join-Path $PackageFolder 'Bin'
	$App = Join-Path $InstallFolder 'App'
	$Config = Join-Path $InstallFolder 'Config'
	# A folder of the old layout that is still in use (working directory) may remain empty; App and Config are created fresh.
	New-Item -ItemType Directory -Path $App, $Config -Force | Out-Null
	Copy-Item -Path (Join-Path (Join-Path $PackageFolder 'App') '*') -Destination $App -Recurse -Force
	Copy-Item -Path (Join-Path (Join-Path $PackageFolder 'Config') '*') -Destination $Config -Recurse -Force
	# Trust mode Signature: both catalogs are installed. Trust mode Hash: no catalog is installed (the file check of the service
	# then accepts only the files of the two lists).
	$ConfigCatalog = Join-Path $Config 'SelfX.Config.cat'
	If($SignedPackage) { Copy-Item -LiteralPath (Join-Path $PackageFolder 'SelfX.Code.cat') -Destination (Join-Path $App 'SelfX.Code.cat') -Force }
	ElseIf(Test-Path -LiteralPath $ConfigCatalog -PathType Leaf) { Remove-Item -LiteralPath $ConfigCatalog -Force }
	Copy-Item -LiteralPath (Join-Path $PackageFolder 'Uninstall.ps1') -Destination $App -Force
	ForEach($Program in @('SelfXService.exe', 'SelfX.exe')) { Copy-Item -LiteralPath (Join-Path $Bin $Program) -Destination (Join-Path $App $Program) -Force }
	# Library for PowerShell 7 (Windows Update orchestrator).
	$WinRT = Join-Path $App 'WinRT'
	New-Item -ItemType Directory -Path $WinRT -Force | Out-Null
	ForEach($Name in @((Get-Content -LiteralPath (Join-Path $Bin 'SelfX.Binaries.json') -Raw | ConvertFrom-Json).Binaries.PSObject.Properties.Name | Where-Object { $_ -like 'WinRT/*' }))
	{
		Copy-Item -LiteralPath (Join-Path $Bin $Name.Replace('/', '\')) -Destination $WinRT -Force
	}
	# Library for PowerShell 7 (Core Audio, action "No sound").
	$Audio = Join-Path $App 'Audio'
	New-Item -ItemType Directory -Path $Audio -Force | Out-Null
	Copy-Item -LiteralPath (Join-Path (Join-Path $Bin 'Audio') 'SelfXAudio.dll') -Destination $Audio -Force
	# Library for PowerShell 7 (state of the notification area, hint before disruptive actions).
	$Disturb = Join-Path $App 'Disturb'
	New-Item -ItemType Directory -Path $Disturb -Force | Out-Null
	Copy-Item -LiteralPath (Join-Path (Join-Path $Bin 'Disturb') 'SelfXDisturb.dll') -Destination $Disturb -Force
}

function ConvertTo-SelfXTrustedSignerList {
	# The list of allowed signers of -TrustedSigner: SHA1 thumbprints of exactly 40 hexadecimal characters. With powershell.exe -File
	# the value "A,B" arrives as one string, so every entry is also split at commas. Returns the thumbprints in upper case without
	# duplicates. An empty list, an empty entry, any other character (also a space inside a thumbprint) or more than Maximum entries
	# throws: the list never means "everything is allowed". The text is not repeated in the message (it may be long or contain
	# control characters).
	param([string[]]$TrustedSigner, [int]$Maximum = 10)
	$List = New-Object System.Collections.Generic.List[string]
	ForEach($Item in @($TrustedSigner))
	{
		ForEach($Part in @("$Item" -split ','))
		{
			$Value = $Part.Trim()
			If($Value -notmatch '^[0-9A-Fa-f]{40}\z') { throw '-TrustedSigner: every entry must be a SHA1 thumbprint of exactly 40 hexadecimal characters (several entries are separated by commas). Nothing was changed.' }
			$Value = $Value.ToUpperInvariant()
			If(-not $List.Contains($Value)) { $List.Add($Value) }
		}
	}
	If($List.Count -eq 0) { throw '-TrustedSigner is empty: at least one SHA1 thumbprint (40 hexadecimal characters) is required. Nothing was changed.' }
	If($List.Count -gt $Maximum) { throw "-TrustedSigner: at most $Maximum thumbprints are allowed. Nothing was changed." }
	Return $List.ToArray()
}

function Get-SelfXTrustAnchor {
	# Reads the trust anchor (64-bit view of the registry). Returns $null when the key does not exist, otherwise an object with Mode
	# ('Hash', 'Signature' or 'Invalid' for any other content) and Signers. A key that cannot be read throws (the caller stops:
	# fail closed). Hive and SubKey are parameters for the tests only.
	param(
		[ValidateSet('LocalMachine', 'CurrentUser')][string]$Hive = 'LocalMachine',
		[string]$SubKey = 'SOFTWARE\SelfX\Trust'
	)
	$Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]$Hive, [Microsoft.Win32.RegistryView]::Registry64)
	Try
	{
		$Key = $Base.OpenSubKey($SubKey, $false)
		If($null -eq $Key) { return $null }
		Try
		{
			$Mode = 'Invalid'
			If($Key.GetValueKind('Mode') -eq [Microsoft.Win32.RegistryValueKind]::String)
			{
				$Text = "$($Key.GetValue('Mode'))"
				If(($Text -ceq 'Hash') -or ($Text -ceq 'Signature')) { $Mode = $Text }
			}
			$Signers = @()
			If(@($Key.GetValueNames()) -contains 'Signers')
			{
				If($Key.GetValueKind('Signers') -eq [Microsoft.Win32.RegistryValueKind]::MultiString) { $Signers = @($Key.GetValue('Signers') | ForEach-Object { "$_" }) }
				Else { $Mode = 'Invalid' }
			}
			Return [pscustomobject]@{ Mode = $Mode; Signers = $Signers }
		}
		Catch [System.IO.IOException] { Return [pscustomobject]@{ Mode = 'Invalid'; Signers = @() } }
		Finally { $Key.Dispose() }
	}
	Finally { $Base.Dispose() }
}

function Resolve-SelfXTrustMode {
	# Decides the trust mode of this installation and refuses a downgrade. InstalledMode is the mode of the anchor on the device
	# ($null = no anchor, 'Hash', 'Signature' or 'Invalid'). Returns 'Signature' or 'Hash'.
	#  - -TrustedSigner given: Signature (from every state). -AllowHashMode together with it is a contradiction: throws.
	#  - no -TrustedSigner: Hash, when the device has no anchor or the anchor says Hash. When the anchor says Signature (or cannot
	#    be understood: treated like Signature, fail closed) the installation stops, unless -AllowHashMode is given.
	param([string]$InstalledMode, [bool]$SignatureRequested, [bool]$AllowHashMode)
	If($SignatureRequested)
	{
		If($AllowHashMode) { throw '-TrustedSigner and -AllowHashMode cannot be used together. Nothing was changed.' }
		Return 'Signature'
	}
	If((-not $InstalledMode) -or ($InstalledMode -ceq 'Hash')) { return 'Hash' }
	If(-not $AllowHashMode)
	{
		throw 'This device is in the trust mode Signature (HKLM\SOFTWARE\SelfX\Trust), but -TrustedSigner was not given. Install with -TrustedSigner <thumbprint>, or allow the change to the mode Hash with the switch -AllowHashMode. Nothing was changed.'
	}
	Return 'Hash'
}

function Test-SelfXFileSignature {
	# Authenticode signature of one file: the status must be Valid AND the signer must be one of the allowed thumbprints ("any valid
	# signature" is not enough). Returns the reason: Ok, FileMissing, NotSigned, HashMismatch, NotSupported, NotTrusted (every other
	# status, for example a root that the device does not trust or a certificate that expired without a time stamp),
	# SignerNotAllowed, Error. Same rule and same reasons as Test-SelfXSignature in tools\SelfXSigning.ps1 (that file is not part of
	# the package; Test-InstallBinaries.ps1 checks that both answer alike). The revocation check is the one of Windows: a
	# revocation list that cannot be reached does not change the status.
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[Parameter(Mandatory = $true)][string[]]$AllowedThumbprint
	)
	If(-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'FileMissing' }
	Try { $Signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop }
	Catch { return 'Error' }
	If($null -eq $Signature) { return 'Error' }
	$Status = [string]$Signature.Status
	If($Status -eq 'Valid')
	{
		$Thumbprint = ''
		If($null -ne $Signature.SignerCertificate) { $Thumbprint = "$($Signature.SignerCertificate.Thumbprint)".ToUpperInvariant() }
		If($Thumbprint -notmatch '^[0-9A-F]{40}\z') { return 'Error' }
		If($AllowedThumbprint -notcontains $Thumbprint) { return 'SignerNotAllowed' }
		Return 'Ok'
	}
	If($Status -eq 'NotSigned') { return 'NotSigned' }
	If($Status -eq 'HashMismatch') { return 'HashMismatch' }
	If($Status -eq 'NotSupportedFileFormat') { return 'NotSupported' }
	Return 'NotTrusted'
}

function Test-SelfXPackageCatalog {
	# A signed catalog of the package: the catalog is signed by an allowed signer (Test-SelfXFileSignature), uses SHA256, and the
	# folder matches it exactly. The catalog lies at the top of the folder it covers and is not counted itself. Files below the
	# folders of SkipFolder (relative to Folder) are not part of this catalog. The lists of Test-FileCatalog -Detailed are compared
	# here, so the reason names the files. Returns 'Ok' or the reason: FileMissing, CatalogSignature:<reason>, HashAlgorithm,
	# NoDetails, FilesDiffer (...), Error. Anything unexpected, also an exception, is a reason and never 'Ok' (fail closed).
	param(
		[Parameter(Mandatory = $true)][string]$CatalogPath,
		[Parameter(Mandatory = $true)][string]$Folder,
		[Parameter(Mandatory = $true)][string[]]$AllowedThumbprint,
		[string[]]$SkipFolder = @()
	)
	Try
	{
		$Root = [IO.Path]::GetFullPath($Folder).TrimEnd('\')
		$Catalog = [IO.Path]::GetFullPath($CatalogPath)
		If(-not (Test-Path -LiteralPath $Root -PathType Container) -or -not (Test-Path -LiteralPath $Catalog -PathType Leaf)) { return 'FileMissing' }
		If((Split-Path -Parent $Catalog).TrimEnd('\') -ine $Root) { return 'Error' }
		$Reason = Test-SelfXFileSignature -Path $Catalog -AllowedThumbprint $AllowedThumbprint
		If($Reason -ne 'Ok') { return "CatalogSignature:$Reason" }
		$CatalogKey = (Split-Path -Leaf $Catalog).ToLowerInvariant()
		$Information = Test-FileCatalog -Path $Root -CatalogFilePath $Catalog -Detailed -FilesToSkip @(Split-Path -Leaf $Catalog) -ErrorAction Stop
		If($null -eq $Information -or $null -eq $Information.CatalogItems -or $null -eq $Information.PathItems) { return 'NoDetails' }
		If("$($Information.HashAlgorithm)" -notmatch 'SHA256') { return 'HashAlgorithm' }
		$InCatalog = @{}
		ForEach($Key in @($Information.CatalogItems.Keys)) { $InCatalog[([string]$Key).Replace('/', '\').ToLowerInvariant()] = [string]$Information.CatalogItems[$Key] }
		$InFolder = @{}
		ForEach($Key in @($Information.PathItems.Keys)) { $InFolder[([string]$Key).Replace('/', '\').ToLowerInvariant()] = [string]$Information.PathItems[$Key] }
		$InCatalog.Remove($CatalogKey)
		$InFolder.Remove($CatalogKey)
		ForEach($Skip in @($SkipFolder))
		{
			$Prefix = "$Skip".Trim('\').ToLowerInvariant() + '\'
			ForEach($Key in @($InFolder.Keys)) { If($Key.StartsWith($Prefix, [StringComparison]::Ordinal)) { $InFolder.Remove($Key) } }
		}
		If($InCatalog.Count -eq 0) { return 'NoDetails' }
		$Changed = New-Object System.Collections.Generic.List[string]
		$Missing = New-Object System.Collections.Generic.List[string]
		$Extra = New-Object System.Collections.Generic.List[string]
		ForEach($Key in $InCatalog.Keys)
		{
			If(-not $InFolder.ContainsKey($Key)) { $Missing.Add($Key) }
			ElseIf($InFolder[$Key] -ne $InCatalog[$Key]) { $Changed.Add($Key) }
		}
		ForEach($Key in $InFolder.Keys) { If(-not $InCatalog.ContainsKey($Key)) { $Extra.Add($Key) } }
		If(($Changed.Count + $Missing.Count + $Extra.Count) -eq 0) { return 'Ok' }
		$Parts = @()
		ForEach($Group in @(@{ Name = 'changed'; Items = $Changed }, @{ Name = 'missing'; Items = $Missing }, @{ Name = 'not in the catalog'; Items = $Extra }))
		{
			If($Group.Items.Count -eq 0) { continue }
			$Names = @($Group.Items | Sort-Object | Select-Object -First 5)
			$More = $(If($Group.Items.Count -gt 5) { " and $($Group.Items.Count - 5) more" } Else { '' })
			$Parts += "$($Group.Name): $($Names -join ', ')$More"
		}
		Return "FilesDiffer ($($Parts -join '; '))"
	}
	Catch { return 'Error' }
}

function Test-SelfXPackageSignatures {
	# Trust mode Signature: checks the whole package before anything on the device is changed. Throws at the first failed part.
	#  1. No link (junction, symbolic link) in the package.
	#  2. Every .exe, .dll, .ps1, .psm1 and .psd1 of the package (Install.ps1 and the libraries of other publishers in Bin included)
	#     has a signature with the status Valid of an allowed signer.
	#  3. Config\SelfX.Config.cat is signed by an allowed signer and matches the folder Config.
	#  4. SelfX.Code.cat at the top of the package is signed by an allowed signer and matches everything else in the package (all
	#     files outside Config: App with SelfX.Code.json, the language files and the images, Bin with SelfX.Binaries.json, the
	#     sources in Service, the scripts at the top). So no file of the package is without a signature of an allowed signer.
	# Returns an object with Files (number of files of step 2) and the SHA256 of the two lists and of the two catalogs as they were
	# checked (CodeListHash, ConfigListHash, CodeCatalogHash, ConfigCatalogHash); Install.ps1 compares the installed lists and
	# catalogs with them after the copy.
	param(
		[Parameter(Mandatory = $true)][string]$PackageFolder,
		[Parameter(Mandatory = $true)][string[]]$AllowedThumbprint
	)
	$Allowed = @(ConvertTo-SelfXTrustedSignerList -TrustedSigner $AllowedThumbprint)
	$Root = (Get-Item -LiteralPath $PackageFolder -Force).FullName.TrimEnd('\')
	$Items = @(Get-ChildItem -LiteralPath $Root -Recurse -Force)
	ForEach($Item in $Items)
	{
		If($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Trust mode Signature: the package contains a link ($($Item.FullName.Substring($Root.Length + 1))). Nothing was changed." }
	}
	$SignedTypes = @('.exe', '.dll', '.ps1', '.psm1', '.psd1')
	$Count = 0
	$Problems = New-Object System.Collections.Generic.List[string]
	ForEach($Item in $Items)
	{
		If($Item.PSIsContainer -or ($SignedTypes -notcontains $Item.Extension.ToLowerInvariant())) { continue }
		$Count++
		$Reason = Test-SelfXFileSignature -Path $Item.FullName -AllowedThumbprint $Allowed
		If($Reason -ne 'Ok') { $Problems.Add("$($Item.FullName.Substring($Root.Length + 1)) ($Reason)") }
	}
	If($Count -eq 0) { throw 'Trust mode Signature: the package contains no program or script. Nothing was changed.' }
	If($Problems.Count -gt 0)
	{
		$Shown = @($Problems | Select-Object -First 10) -join ', '
		$More = $(If($Problems.Count -gt 10) { " and $($Problems.Count - 10) more" } Else { '' })
		throw "Trust mode Signature: $($Problems.Count) of $Count programs and scripts of the package have no valid signature of an allowed signer: $Shown$More. Nothing was changed."
	}
	$ConfigSource = Join-Path $Root 'Config'
	$Result = Test-SelfXPackageCatalog -CatalogPath (Join-Path $ConfigSource 'SelfX.Config.cat') -Folder $ConfigSource -AllowedThumbprint $Allowed
	If($Result -ne 'Ok') { throw "Trust mode Signature: Config\SelfX.Config.cat is not a valid signed catalog of the folder Config: $Result. Nothing was changed." }
	$Result = Test-SelfXPackageCatalog -CatalogPath (Join-Path $Root 'SelfX.Code.cat') -Folder $Root -AllowedThumbprint $Allowed -SkipFolder @('Config')
	If($Result -ne 'Ok') { throw "Trust mode Signature: SelfX.Code.cat is not a valid signed catalog of the package (all files outside Config): $Result. Nothing was changed." }
	$CodeList = Join-Path (Join-Path $Root 'App') 'SelfX.Code.json'
	$ConfigList = Join-Path $ConfigSource 'SelfX.Config.json'
	ForEach($List in @($CodeList, $ConfigList))
	{
		If(-not (Test-Path -LiteralPath $List -PathType Leaf)) { throw "Trust mode Signature: $(Split-Path -Leaf $List) is missing in the package. Nothing was changed." }
	}
	Return [pscustomobject]@{
		Files          = $Count
		CodeListHash      = (Get-FileHash -LiteralPath $CodeList -Algorithm SHA256).Hash
		ConfigListHash    = (Get-FileHash -LiteralPath $ConfigList -Algorithm SHA256).Hash
		CodeCatalogHash   = (Get-FileHash -LiteralPath (Join-Path $Root 'SelfX.Code.cat') -Algorithm SHA256).Hash
		ConfigCatalogHash = (Get-FileHash -LiteralPath (Join-Path $ConfigSource 'SelfX.Config.cat') -Algorithm SHA256).Hash
	}
}

function Test-SelfXInstalledLists {
	# Trust mode Signature, after the copy: the installed lists are byte for byte the lists that the signed catalogs covered when
	# the package was checked, and the installed catalogs are byte for byte the checked catalogs (no second look at the package; a
	# list or catalog changed between check and copy is found here). Together with Test-SelfXInstalledFiles this binds every
	# installed file to the signed package. Throws on a difference.
	param(
		[Parameter(Mandatory = $true)][string]$InstallFolder,
		[Parameter(Mandatory = $true)]$Verified
	)
	$Lists = @(
		@{ Path = (Join-Path (Join-Path $InstallFolder 'App') 'SelfX.Code.json'); Hash = "$($Verified.CodeListHash)"; Name = 'App\SelfX.Code.json' },
		@{ Path = (Join-Path (Join-Path $InstallFolder 'Config') 'SelfX.Config.json'); Hash = "$($Verified.ConfigListHash)"; Name = 'Config\SelfX.Config.json' },
		@{ Path = (Join-Path (Join-Path $InstallFolder 'App') 'SelfX.Code.cat'); Hash = "$($Verified.CodeCatalogHash)"; Name = 'App\SelfX.Code.cat' },
		@{ Path = (Join-Path (Join-Path $InstallFolder 'Config') 'SelfX.Config.cat'); Hash = "$($Verified.ConfigCatalogHash)"; Name = 'Config\SelfX.Config.cat' }
	)
	ForEach($List in $Lists)
	{
		If($List.Hash -notmatch '^[0-9A-Fa-f]{64}\z') { throw "The checked SHA256 of $($List.Name) is missing." }
		If(-not (Test-Path -LiteralPath $List.Path -PathType Leaf)) { throw "$($List.Name) is missing in the installation folder." }
		If((Get-FileHash -LiteralPath $List.Path -Algorithm SHA256).Hash -ne $List.Hash) { throw "$($List.Name) in the installation folder is not the file that was checked in the signed package (changed between check and copy)." }
	}
}

function Set-SelfXTrustAnchor {
	# Writes the trust anchor: Mode (REG_SZ, 'Hash' or 'Signature') and, in the mode Signature, Signers (REG_MULTI_SZ, the allowed
	# thumbprints); in the mode Hash the value Signers is removed. Every other value and sub key is removed. Owner Administrators
	# (S-1-5-32-544); rights not inherited: SYSTEM (S-1-5-18) and Administrators full control, users (S-1-5-32-545) read. All
	# accounts by SID. Afterwards the anchor is read back and its rights are checked (Test-SelfXTrustAnchorState); a difference
	# throws. Hive, SubKey, OwnerSid and FullControlSids are parameters for the tests only.
	param(
		[Parameter(Mandatory = $true)][ValidateSet('Hash', 'Signature')][string]$Mode,
		[string[]]$Signers = @(),
		[ValidateSet('LocalMachine', 'CurrentUser')][string]$Hive = 'LocalMachine',
		[string]$SubKey = 'SOFTWARE\SelfX\Trust',
		[string]$OwnerSid = 'S-1-5-32-544',
		[string[]]$FullControlSids = @('S-1-5-18', 'S-1-5-32-544')
	)
	If($Mode -eq 'Signature') { $Signers = @(ConvertTo-SelfXTrustedSignerList -TrustedSigner $Signers) } Else { $Signers = @() }
	$Security = New-Object System.Security.AccessControl.RegistrySecurity
	$Security.SetAccessRuleProtection($true, $false)
	$Security.SetOwner((New-Object System.Security.Principal.SecurityIdentifier($OwnerSid)))
	$Inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
	$Propagate = [System.Security.AccessControl.PropagationFlags]::None
	$Allow = [System.Security.AccessControl.AccessControlType]::Allow
	ForEach($Sid in $FullControlSids)
	{
		$Security.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule((New-Object System.Security.Principal.SecurityIdentifier($Sid)), [System.Security.AccessControl.RegistryRights]::FullControl, $Inherit, $Propagate, $Allow)))
	}
	$Security.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule((New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')), [System.Security.AccessControl.RegistryRights]::ReadKey, $Inherit, $Propagate, $Allow)))
	$Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]$Hive, [Microsoft.Win32.RegistryView]::Registry64)
	Try
	{
		$Key = $Base.CreateSubKey($SubKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree)
		If($null -eq $Key) { throw 'The trust anchor could not be created.' }
		Try
		{
			$Key.SetAccessControl($Security)
			ForEach($Child in @($Key.GetSubKeyNames())) { $Key.DeleteSubKeyTree($Child, $false) }
			ForEach($Name in @($Key.GetValueNames())) { If(($Name -ne 'Mode') -and ($Name -ne 'Signers')) { $Key.DeleteValue($Name, $false) } }
			$Key.SetValue('Mode', $Mode, [Microsoft.Win32.RegistryValueKind]::String)
			If($Mode -eq 'Signature') { $Key.SetValue('Signers', [string[]]$Signers, [Microsoft.Win32.RegistryValueKind]::MultiString) }
			Else { $Key.DeleteValue('Signers', $false) }
			$Key.Flush()
		}
		Finally { $Key.Dispose() }
	}
	Finally { $Base.Dispose() }
	$Problem = Test-SelfXTrustAnchorState -Mode $Mode -Signers $Signers -Hive $Hive -SubKey $SubKey -TrustedSids $FullControlSids
	If($Problem) { throw "The trust anchor was written but is not as expected: $Problem." }
}

function Test-SelfXTrustAnchorState {
	# Reads the trust anchor back: the mode and the signers are the expected ones, the rights are not inherited and no identity
	# other than TrustedSids (SYSTEM, Administrators) may change the key (set a value, create a sub key or a link, delete, change
	# rights, take ownership). Rules are read as SIDs. Returns $null or the problem.
	param(
		[Parameter(Mandatory = $true)][string]$Mode,
		[string[]]$Signers = @(),
		[ValidateSet('LocalMachine', 'CurrentUser')][string]$Hive = 'LocalMachine',
		[string]$SubKey = 'SOFTWARE\SelfX\Trust',
		[string[]]$TrustedSids = @('S-1-5-18', 'S-1-5-32-544')
	)
	$Anchor = Get-SelfXTrustAnchor -Hive $Hive -SubKey $SubKey
	If($null -eq $Anchor) { return 'the key is missing' }
	If($Anchor.Mode -cne $Mode) { return "the mode is $($Anchor.Mode)" }
	If((@($Anchor.Signers) -join ',') -cne (@($Signers) -join ',')) { return 'the signers differ' }
	$Write = [System.Security.AccessControl.RegistryRights]'SetValue, CreateSubKey, CreateLink, Delete, ChangePermissions, TakeOwnership'
	$Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]$Hive, [Microsoft.Win32.RegistryView]::Registry64)
	Try
	{
		$Key = $Base.OpenSubKey($SubKey, $false)
		If($null -eq $Key) { return 'the key is missing' }
		Try
		{
			$Acl = $Key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
			If(-not $Acl.AreAccessRulesProtected) { return 'the rights are inherited' }
			ForEach($Rule in $Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
			{
				If($Rule.AccessControlType -ne 'Allow') { continue }
				If(-not ($Rule.RegistryRights -band $Write)) { continue }
				If($TrustedSids -contains $Rule.IdentityReference.Value) { continue }
				Return "the key can be changed by $($Rule.IdentityReference.Value)"
			}
		}
		Finally { $Key.Dispose() }
	}
	Finally { $Base.Dispose() }
	Return $null
}

# ------------------------------------------------------------------------------------------------ mode -ConfigOnly
# A package of the assistant with only Install.ps1 and Config replaces the folder Config of an existing installation. The functions
# below are called by Invoke-SelfXConfigOnly (Test-InstallConfigOnly.ps1 takes them out of this file and runs them in a temporary folder).

function ConvertTo-SelfXCodeVersion {
	# A version for the comparison of -ConfigOnly: two to four numbers separated by dots (3.1.0). Anything else (letters, a suffix, a
	# sign, a number with more than five digits) gives $null, so an unclear version is never "new enough" (fail closed).
	param([string]$Text)
	If("$Text" -notmatch '^[0-9]{1,5}(\.[0-9]{1,5}){1,3}\z') { return $null }
	Try { Return [version]"$Text" } Catch { Return $null }
}

function Get-SelfXConfigMinCodeVersion {
	# MinCodeVersion of Config\SelfX.Config.json: the oldest code version that the configuration of the package is made for. A missing
	# or invalid value throws: the package is then no configuration package.
	param([Parameter(Mandatory = $true)][string]$Path)
	Try { $List = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
	Catch { throw 'Config\SelfX.Config.json is not valid JSON.' }
	$Text = If($List) { "$($List.MinCodeVersion)".Trim() } Else { '' }
	If($null -eq (ConvertTo-SelfXCodeVersion -Text $Text)) { throw 'Config\SelfX.Config.json has no valid MinCodeVersion: this is not a configuration package (build it with the assistant, option configuration package).' }
	Return $Text
}

function Test-SelfXConfigPackageLayout {
	# The package of -ConfigOnly holds Install.ps1 and the folder Config and nothing else, and no link anywhere. A full package (App,
	# Bin, Service, Uninstall.ps1) is refused: it would silently leave the code of the device unchanged. Throws; nothing is changed.
	param([Parameter(Mandatory = $true)][string]$PackageFolder)
	$Root = (Get-Item -LiteralPath $PackageFolder -Force).FullName.TrimEnd('\')
	ForEach($Item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force))
	{
		If($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "-ConfigOnly: the package contains a link ($($Item.FullName.Substring($Root.Length + 1))). Nothing was changed." }
	}
	ForEach($Item in @(Get-ChildItem -LiteralPath $Root -Force))
	{
		If(($Item.Name -ieq 'Install.ps1') -and -not $Item.PSIsContainer) { continue }
		If(($Item.Name -ieq 'Config') -and $Item.PSIsContainer) { continue }
		If(@('App', 'Bin', 'Service', 'Uninstall.ps1') -contains $Item.Name) { throw "-ConfigOnly: the package holds '$($Item.Name)': it is a full package. Install it without -ConfigOnly. Nothing was changed." }
		throw "-ConfigOnly: the package holds the unexpected entry '$($Item.Name)' (only Install.ps1 and Config are allowed). Nothing was changed."
	}
	If(-not (Test-Path -LiteralPath (Join-Path $Root 'Config') -PathType Container)) { throw '-ConfigOnly: the folder Config is missing in the package. Nothing was changed.' }
}

function Test-SelfXConfigFolder {
	# One folder of configuration against its list Config\SelfX.Config.json (the list is inside the folder): every listed name is allowed
	# in this list (placement rule), exists with the listed SHA256, is listed once; nothing in the folder is unlisted; no link; Tool_Config.xml
	# is listed. With -SignedPackage the catalog SelfX.Config.cat may be in the folder and is not counted (its signature is checked by
	# Test-SelfXConfigPackageSignatures); without the switch it is an unlisted file. Where names the place in the messages. Throws at
	# the first difference. Returns the number of listed files.
	param(
		[Parameter(Mandatory = $true)][string]$Folder,
		[Parameter(Mandatory = $true)][string]$Where,
		[switch]$SignedPackage
	)
	$Root = [IO.Path]::GetFullPath($Folder).TrimEnd('\')
	$FolderItem = Get-Item -LiteralPath $Root -Force -ErrorAction SilentlyContinue
	If(-not $FolderItem -or -not $FolderItem.PSIsContainer) { throw "The folder Config is missing in $Where." }
	If($FolderItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "The folder Config in $Where is a link." }
	$ListPath = Join-Path $Root 'SelfX.Config.json'
	If(-not (Test-Path -LiteralPath $ListPath -PathType Leaf)) { throw "Config\SelfX.Config.json is missing in $Where." }
	If($SignedPackage -and -not (Test-Path -LiteralPath (Join-Path $Root 'SelfX.Config.cat') -PathType Leaf)) { throw "Config\SelfX.Config.cat is missing in $Where." }
	$Listed = @{}
	$Count = 0
	ForEach($Entry in @(Read-SelfXFileList -Path $ListPath -ListName 'SelfX.Config.json' -Where $Where))
	{
		$Key = $Entry.Name.ToLowerInvariant()
		If($Listed.ContainsKey($Key)) { throw "$($Entry.Name) is listed twice in SelfX.Config.json." }
		$File = [IO.Path]::GetFullPath((Join-Path $Root $Entry.Name.Replace('/', '\')))
		If(-not $File.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "$($Entry.Name) points outside the folder Config." }
		If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "$($Entry.Name) is listed in SelfX.Config.json but missing in $Where." }
		If((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Entry.Hash) { throw "$($Entry.Name) does not match its SHA256 in SelfX.Config.json ($Where)." }
		$Listed[$Key] = $true
		$Count++
	}
	ForEach($Child in @(Get-ChildItem -LiteralPath $Root -Recurse -Force))
	{
		$Relative = $Child.FullName.Substring($Root.Length + 1).Replace('\', '/')
		If($Child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Config/$Relative in $Where is a link." }
		If($Child.PSIsContainer -or ($Relative -ceq 'SelfX.Config.json')) { continue }
		If($Relative -ieq 'SelfX.Config.cat')
		{
			If($SignedPackage) { continue }
			throw "Config\SelfX.Config.cat is present in $Where but the trust mode of the device is Hash: a signed package needs a device in the mode Signature."
		}
		If(-not $Listed.ContainsKey($Relative.ToLowerInvariant())) { throw "Config/$Relative in $Where is not listed in SelfX.Config.json." }
	}
	If(-not $Listed.ContainsKey('tool_config.xml')) { throw "Tool_Config.xml is not listed in SelfX.Config.json ($Where)." }
	Return $Count
}

function Test-SelfXConfigPackageSignatures {
	# Trust mode Signature of -ConfigOnly: Install.ps1 and every script of the package carry a signature with the status Valid of an
	# allowed signer (the signers of the anchor on the device, never a list from the package or the command line), and
	# Config\SelfX.Config.cat is signed by one of them and matches the folder Config. Throws at the first failed part. Returns the number
	# of checked files and the SHA256 of the list and of the catalog as they were checked (the copy is compared with them).
	param(
		[Parameter(Mandatory = $true)][string]$PackageFolder,
		[Parameter(Mandatory = $true)][string[]]$AllowedThumbprint
	)
	$Allowed = @(ConvertTo-SelfXTrustedSignerList -TrustedSigner $AllowedThumbprint)
	$Root = (Get-Item -LiteralPath $PackageFolder -Force).FullName.TrimEnd('\')
	$Items = @(Get-ChildItem -LiteralPath $Root -Recurse -Force)
	ForEach($Item in $Items)
	{
		If($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Trust mode Signature: the package contains a link ($($Item.FullName.Substring($Root.Length + 1))). Nothing was changed." }
	}
	$SignedTypes = @('.exe', '.dll', '.ps1', '.psm1', '.psd1')
	$Count = 0
	$Problems = New-Object System.Collections.Generic.List[string]
	ForEach($Item in $Items)
	{
		If($Item.PSIsContainer -or ($SignedTypes -notcontains $Item.Extension.ToLowerInvariant())) { continue }
		$Count++
		$Reason = Test-SelfXFileSignature -Path $Item.FullName -AllowedThumbprint $Allowed
		If($Reason -ne 'Ok') { $Problems.Add("$($Item.FullName.Substring($Root.Length + 1)) ($Reason)") }
	}
	If($Count -eq 0) { throw 'Trust mode Signature: the package contains no script. Nothing was changed.' }
	If($Problems.Count -gt 0)
	{
		$Shown = @($Problems | Select-Object -First 10) -join ', '
		$More = $(If($Problems.Count -gt 10) { " and $($Problems.Count - 10) more" } Else { '' })
		throw "Trust mode Signature: $($Problems.Count) of $Count scripts of the package have no valid signature of a signer of this device: $Shown$More. Nothing was changed."
	}
	$ConfigSource = Join-Path $Root 'Config'
	$Result = Test-SelfXPackageCatalog -CatalogPath (Join-Path $ConfigSource 'SelfX.Config.cat') -Folder $ConfigSource -AllowedThumbprint $Allowed
	If($Result -ne 'Ok') { throw "Trust mode Signature: Config\SelfX.Config.cat is not a valid signed catalog of the folder Config: $Result. Nothing was changed." }
	Return [pscustomobject]@{
		Files             = $Count
		ConfigListHash    = (Get-FileHash -LiteralPath (Join-Path $ConfigSource 'SelfX.Config.json') -Algorithm SHA256).Hash
		ConfigCatalogHash = (Get-FileHash -LiteralPath (Join-Path $ConfigSource 'SelfX.Config.cat') -Algorithm SHA256).Hash
	}
}

function Test-SelfXConfigListsMatch {
	# Trust mode Signature: the list and the catalog in this copy of Config are byte for byte the ones that were checked in the package
	# (a change between the check and the copy is found). Throws on a difference.
	param([Parameter(Mandatory = $true)][string]$Folder, [Parameter(Mandatory = $true)]$Verified, [Parameter(Mandatory = $true)][string]$Where)
	ForEach($Item in @(@{ Name = 'SelfX.Config.json'; Hash = "$($Verified.ConfigListHash)" }, @{ Name = 'SelfX.Config.cat'; Hash = "$($Verified.ConfigCatalogHash)" }))
	{
		If($Item.Hash -notmatch '^[0-9A-Fa-f]{64}\z') { throw "The checked SHA256 of $($Item.Name) is missing." }
		$Path = Join-Path $Folder $Item.Name
		If(-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Config\$($Item.Name) is missing in $Where." }
		If((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Item.Hash) { throw "Config\$($Item.Name) in $Where is not the file that was checked in the signed package (changed between check and copy)." }
	}
}

function Read-SelfXXmlFile {
	# Reads an XML file without DTD and without external resources (a DTD or an external entity is an error: fail closed).
	param([Parameter(Mandatory = $true)][string]$Path)
	$Document = New-Object System.Xml.XmlDocument
	$Document.XmlResolver = $null
	$Settings = New-Object System.Xml.XmlReaderSettings
	$Settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
	$Settings.XmlResolver = $null
	$Reader = [System.Xml.XmlReader]::Create($Path, $Settings)
	Try { $Document.Load($Reader) } Finally { $Reader.Dispose() }
	Return $Document
}

function Get-SelfXInstallTimeSettings {
	# The settings of Tool_Config.xml that only Install.ps1 applies (shortcuts, the status icon entry, the icon of the shortcuts, the
	# privileges of the service), as the values Install.ps1 works with (a missing or invalid value gives the same result as in
	# Install.ps1). Returns an ordered table. Throws when the file has no element GUI_Config.
	param([Parameter(Mandatory = $true)][System.Xml.XmlDocument]$ToolConfig)
	$Gui = $ToolConfig.GUI_Config
	If($null -eq $Gui) { throw 'Tool_Config.xml has no element GUI_Config.' }
	$Privileges = "$($Gui.Service_Privileges)".Trim()
	If($Privileges -notin @('Restricted', 'Default')) { $Privileges = 'Restricted' }
	Return [ordered]@{
		Shortcut_Name      = "$($Gui.Shortcut_Name)".Trim()
		Shortcut_Desktop   = [bool]("$($Gui.Shortcut_Desktop)" -eq 'True')
		Shortcut_StartMenu = [bool]("$($Gui.Shortcut_StartMenu)" -eq 'True')
		Brand_Icon         = "$($Gui.Brand_Icon)".Trim()
		Show_Tray_Icon     = [bool]("$($Gui.Show_Tray_Icon)".Trim() -ne 'False')
		Service_Privileges = $Privileges
	}
}

function Compare-SelfXInstallTimeSettings {
	# Names of the install-time settings that differ between the installed Tool_Config.xml and the one of the package (empty = equal).
	param([Parameter(Mandatory = $true)][string]$InstalledFile, [Parameter(Mandatory = $true)][string]$PackageFile)
	$Installed = Get-SelfXInstallTimeSettings -ToolConfig (Read-SelfXXmlFile -Path $InstalledFile)
	$Package = Get-SelfXInstallTimeSettings -ToolConfig (Read-SelfXXmlFile -Path $PackageFile)
	$Different = New-Object System.Collections.Generic.List[string]
	ForEach($Name in @($Installed.Keys)) { If("$($Installed[$Name])" -cne "$($Package[$Name])") { $Different.Add($Name) } }
	Return $Different.ToArray()
}

function Get-SelfXInstalledDeleteHelper {
	# The delete helper for the work folders: SelfXService.exe of the installation, used only when its SHA256 is the one in the installed
	# App\SelfX.Code.json (otherwise nothing is deleted by it: fail closed). Returns the path.
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$Exe = Join-Path $InstallFolder 'App\SelfXService.exe'
	$ListPath = Join-Path $InstallFolder 'App\SelfX.Code.json'
	If(-not (Test-Path -LiteralPath $Exe -PathType Leaf) -or -not (Test-Path -LiteralPath $ListPath -PathType Leaf)) { throw 'The installation is incomplete (App\SelfXService.exe or App\SelfX.Code.json is missing). Install the full package first. Nothing was changed.' }
	$Entry = @(Read-SelfXFileList -Path $ListPath -ListName 'SelfX.Code.json' -Where 'the installation folder' | Where-Object { $_.Name -ceq 'SelfXService.exe' })
	If($Entry.Count -ne 1) { throw 'App\SelfX.Code.json does not list SelfXService.exe. Nothing was changed.' }
	If((Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash -ne $Entry[0].Hash) { throw 'App\SelfXService.exe does not match App\SelfX.Code.json: it is not used to delete folders. Install the full package again. Nothing was changed.' }
	Return $Exe
}

function Set-SelfXConfigFolderRights {
	# Rights of a folder that becomes Config: the same as Install.ps1 gives the install folder (SYSTEM and administrators full control,
	# users read and execute, not inherited), by SID.
	param([Parameter(Mandatory = $true)][string]$Path)
	& icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
	If($LASTEXITCODE -ne 0) { throw "icacls failed for '$Path' (exit code $LASTEXITCODE)." }
}

function Reset-SelfXConfigFolderRights {
	# After the folder has been moved into the install folder: its rights are the inherited ones again, exactly as after a full
	# installation (Config inherits from the install folder).
	param([Parameter(Mandatory = $true)][string]$Path)
	& icacls.exe $Path /reset /T /C /Q | Out-Null
	If($LASTEXITCODE -ne 0) { throw "icacls /reset failed for '$Path' (exit code $LASTEXITCODE)." }
}

function Move-SelfXFolderWithRetry {
	# Renames a folder. A folder that holds a file which is open (a script of a running action) cannot be renamed: the rename is tried
	# again (Attempts x DelaySeconds), then it throws and nothing has moved.
	param(
		[Parameter(Mandatory = $true)][string]$From,
		[Parameter(Mandatory = $true)][string]$To,
		[int]$Attempts = 10,
		[int]$DelaySeconds = 2
	)
	For($Attempt = 1; $Attempt -le $Attempts; $Attempt++)
	{
		Try { [IO.Directory]::Move($From, $To); return }
		Catch
		{
			If($Attempt -ge $Attempts) { throw "The folder '$From' is in use and cannot be exchanged (a SelfX action may be running): $($_.Exception.Message)" }
			Start-Sleep -Seconds $DelaySeconds
		}
	}
}

function Restore-SelfXInterruptedConfig {
	# A run that stopped between the two renames leaves no Config and the old one in InstallFolder.ConfigOld: it is put back (the
	# installation works again) before anything else is looked at.
	param([Parameter(Mandatory = $true)][string]$InstallFolder, [int]$Attempts = 10, [int]$DelaySeconds = 2)
	$Root = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	$Config = Join-Path $Root 'Config'
	$Old = $Root + '.ConfigOld'
	If(-not (Test-Path -LiteralPath $Config) -and (Test-Path -LiteralPath $Old))
	{
		Move-SelfXFolderWithRetry -From $Old -To $Config -Attempts $Attempts -DelaySeconds $DelaySeconds
		Write-Host 'The configuration of an interrupted update was put back.'
	}
}

function Install-SelfXConfigFolder {
	# Exchanges the folder Config of the installation for the one of the package, with these steps (each before the next):
	#  1. The work folders next to the install folder are cleaned: InstallFolder.ConfigStage, InstallFolder.ConfigOld (left over from an
	#     interrupted run; when Config is missing and ConfigOld exists, ConfigOld is put back first).
	#  2. The package folder is copied into InstallFolder.ConfigStage (rights as Install.ps1 gives them) and checked there against its
	#     list (and in the mode Signature against the checked list and catalog). A difference stops here; Config is untouched.
	#  3. Config is renamed to ConfigOld, ConfigStage to Config (two renames, the only moment without a complete Config), rights are reset
	#     to the inherited ones, and Config is checked again. Any error puts ConfigOld back as Config.
	#  4. ConfigOld is deleted (link-safe, by the helper of the installation).
	# The work folders are next to the install folder, not in it: the service refuses to start a script when the install folder holds
	# more than App and Config. Returns the number of files of the new Config.
	param(
		[Parameter(Mandatory = $true)][string]$PackageFolder,
		[Parameter(Mandatory = $true)][string]$InstallFolder,
		[Parameter(Mandatory = $true)][string]$SafeDeleteExe,
		[switch]$SignedPackage,
		$Verified,
		[int]$Attempts = 10,
		[int]$DelaySeconds = 2
	)
	$Root = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	$Config = Join-Path $Root 'Config'
	$Stage = $Root + '.ConfigStage'
	$Old = $Root + '.ConfigOld'
	# 1. left over from an interrupted run
	Restore-SelfXInterruptedConfig -InstallFolder $Root -Attempts $Attempts -DelaySeconds $DelaySeconds
	$ConfigItem = Get-Item -LiteralPath $Config -Force -ErrorAction SilentlyContinue
	If(-not $ConfigItem -or -not $ConfigItem.PSIsContainer -or ($ConfigItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'The folder Config of the installation is missing or a link. Install the full package. Nothing was changed.' }
	ForEach($Left in @($Stage, $Old))
	{
		If(Test-Path -LiteralPath $Left) { Invoke-SelfXSafeDelete -Exe $SafeDeleteExe -Arguments @("/removetree:$Left") }
		If(Test-Path -LiteralPath $Left) { throw "The work folder '$Left' could not be removed. Nothing was changed." }
	}
	$Succeeded = $false
	Try
	{
		# 2. copy and check next to the install folder
		New-Item -ItemType Directory -Path $Stage | Out-Null
		Set-SelfXConfigFolderRights -Path $Stage
		Copy-Item -Path (Join-Path (Join-Path $PackageFolder 'Config') '*') -Destination $Stage -Recurse -Force
		$Count = Test-SelfXConfigFolder -Folder $Stage -Where 'the copy of the package' -SignedPackage:$SignedPackage
		If($SignedPackage) { Test-SelfXConfigListsMatch -Folder $Stage -Verified $Verified -Where 'the copy of the package' }
		# 3. exchange
		Move-SelfXFolderWithRetry -From $Config -To $Old -Attempts $Attempts -DelaySeconds $DelaySeconds
		Try
		{
			[IO.Directory]::Move($Stage, $Config)
			Reset-SelfXConfigFolderRights -Path $Config
			$null = Test-SelfXConfigFolder -Folder $Config -Where 'the installation folder' -SignedPackage:$SignedPackage
			If($SignedPackage) { Test-SelfXConfigListsMatch -Folder $Config -Verified $Verified -Where 'the installation folder' }
		}
		Catch
		{
			$Failure = $_
			# The old folder goes back; a new Config that is already in place is moved out of the way first.
			Try
			{
				If(Test-Path -LiteralPath $Config) { [IO.Directory]::Move($Config, $Stage + '.Failed') }
				[IO.Directory]::Move($Old, $Config)
			}
			Catch { throw "The new configuration was refused ($($Failure.Exception.Message)) and the old one could not be put back ($($_.Exception.Message)). The old configuration is in '$Old'; run the package again to put it back." }
			throw $Failure
		}
		$Succeeded = $true
		Return $Count
	}
	Finally
	{
		ForEach($Leftover in @($Stage, ($Stage + '.Failed')))
		{
			If(Test-Path -LiteralPath $Leftover) { Try { Invoke-SelfXSafeDelete -Exe $SafeDeleteExe -Arguments @("/removetree:$Leftover") } Catch { Write-Warning "The work folder '$Leftover' could not be removed: $($_.Exception.Message)" } }
		}
		If($Succeeded -and (Test-Path -LiteralPath $Old)) { Try { Invoke-SelfXSafeDelete -Exe $SafeDeleteExe -Arguments @("/removetree:$Old") } Catch { Write-Warning "The work folder '$Old' could not be removed: $($_.Exception.Message)" } }
	}
}

function Invoke-SelfXConfigOnly {
	# The whole mode -ConfigOnly after the anchor was read. Anchor: the object of Get-SelfXTrustAnchor (Mode Hash or Signature and
	# Signers), already checked for safe rights by the caller. All checks come before the first change:
	#  - the package is Install.ps1 + Config; mode Signature: the signatures (signers of the anchor); mode Hash: no catalog;
	#  - Config\SelfX.Config.json lists exactly the files of Config;
	#  - MinCodeVersion is not newer than the installed code (App\SelfX.Code.json);
	#  - the install-time settings of Tool_Config.xml are the installed ones.
	# Then Install-SelfXConfigFolder. Throws with a plain text; returns an object with Version, MinCodeVersion, Files and Mode.
	param(
		[Parameter(Mandatory = $true)][string]$PackageFolder,
		[Parameter(Mandatory = $true)][string]$InstallFolder,
		$Anchor,
		[int]$Attempts = 10,
		[int]$DelaySeconds = 2
	)
	If($null -eq $Anchor) { throw '-ConfigOnly needs an installed SelfX with a trust anchor (HKLM\SOFTWARE\SelfX\Trust). Install the full package first. Nothing was changed.' }
	Restore-SelfXInterruptedConfig -InstallFolder $InstallFolder -Attempts $Attempts -DelaySeconds $DelaySeconds
	$SignedPackage = ($Anchor.Mode -ceq 'Signature')
	If(-not $SignedPackage -and ($Anchor.Mode -cne 'Hash')) { throw 'The trust anchor of the device has no valid mode. Install the full package again. Nothing was changed.' }
	Test-SelfXConfigPackageLayout -PackageFolder $PackageFolder
	$Verified = $null
	If($SignedPackage)
	{
		$Allowed = @(ConvertTo-SelfXTrustedSignerList -TrustedSigner @($Anchor.Signers))
		$Verified = Test-SelfXConfigPackageSignatures -PackageFolder $PackageFolder -AllowedThumbprint $Allowed
		Write-Host "Trust mode Signature: $($Verified.Files) scripts are signed by a signer of this device; Config\SelfX.Config.cat is signed and matches the package. Signers of the device: $($Allowed -join ', ')."
	}
	Else { Write-Host 'Trust mode Hash (the mode of this device).' }
	$PackageConfig = Join-Path $PackageFolder 'Config'
	$Checked = Test-SelfXConfigFolder -Folder $PackageConfig -Where 'the package' -SignedPackage:$SignedPackage
	Write-Host "Package files checked against Config\SelfX.Config.json ($Checked files)."
	$Minimum = Get-SelfXConfigMinCodeVersion -Path (Join-Path $PackageConfig 'SelfX.Config.json')
	$Installed = Get-SelfXPackageToolVersion -PackageFolder $InstallFolder
	$InstalledVersion = ConvertTo-SelfXCodeVersion -Text $Installed
	If($null -eq $InstalledVersion) { throw "The installed code version '$Installed' cannot be compared. Install the full package. Nothing was changed." }
	If($InstalledVersion -lt (ConvertTo-SelfXCodeVersion -Text $Minimum)) { throw "This configuration needs code version $Minimum or newer; installed is $Installed. Install the full package first. Nothing was changed." }
	$InstalledToolConfig = Join-Path $InstallFolder 'Config\Tool_Config.xml'
	If(-not (Test-Path -LiteralPath $InstalledToolConfig -PathType Leaf)) { throw 'The installation has no Config\Tool_Config.xml. Install the full package. Nothing was changed.' }
	$Different = @(Compare-SelfXInstallTimeSettings -InstalledFile $InstalledToolConfig -PackageFile (Join-Path $PackageConfig 'Tool_Config.xml'))
	If($Different.Count -gt 0) { throw "These settings are applied only by the full package, and the package changes them: $($Different -join ', '). Build and install the full package, or keep them as they are. Nothing was changed." }
	$Helper = Get-SelfXInstalledDeleteHelper -InstallFolder $InstallFolder
	Write-Host "Installed code version $Installed, the configuration needs $Minimum or newer."
	$Files = Install-SelfXConfigFolder -PackageFolder $PackageFolder -InstallFolder $InstallFolder -SafeDeleteExe $Helper -SignedPackage:$SignedPackage -Verified $Verified -Attempts $Attempts -DelaySeconds $DelaySeconds
	Return [pscustomobject]@{ Version = $Installed; MinCodeVersion = $Minimum; Files = $Files; Mode = $(If($SignedPackage) { 'Signature' } Else { 'Hash' }) }
}

function Get-SelfXServicePrivileges {
	# Privileges the service (LocalSystem) keeps. Everything else of the LocalSystem token is removed, so the
	# service and every script it starts cannot use SeTcb, SeDebug, SeCreateToken, SeLoadDriver, SeSecurity and the like.
	# Needed: ChangeNotify (every process), Impersonate (pipe client), CreateGlobal (global objects), Shutdown (restart
	# action), Systemtime (time sync), Backup/Restore/TakeOwnership (file repairs), ManageVolume (disk check).
	return @(
		'SeChangeNotifyPrivilege', 'SeImpersonatePrivilege', 'SeCreateGlobalPrivilege', 'SeShutdownPrivilege',
		'SeSystemtimePrivilege', 'SeBackupPrivilege', 'SeRestorePrivilege', 'SeTakeOwnershipPrivilege', 'SeManageVolumePrivilege'
	)
}

function Set-SelfXServicePrivileges {
	# Sets the required privileges of the service and checks the result. A failure is a warning only: the installation
	# (Autopilot) must not fail because of this setting; the service then keeps the default LocalSystem privileges.
	param([string]$Name, [string]$Mode)
	if ($Mode -eq 'Default') { return 'Default (all LocalSystem privileges; Service_Privileges = Default).' }
	$wanted = @(Get-SelfXServicePrivileges)
	$output = @(& sc.exe privs $Name ($wanted -join '/') 2>&1)
	if ($LASTEXITCODE -ne 0) { Write-Warning "sc.exe privs failed (exit code $LASTEXITCODE): the service keeps the default privileges. $($output -join ' ')"; return 'Default (setting failed).' }
	$actual = @([regex]::Matches((@(& sc.exe qprivs $Name 2>&1) -join ' '), 'Se\w+Privilege') | ForEach-Object { $_.Value } | Sort-Object -Unique)
	$missing = @($wanted | Where-Object { $actual -notcontains $_ })
	$extra = @($actual | Where-Object { $wanted -notcontains $_ })
	if ($missing.Count -or $extra.Count) { Write-Warning "The privileges of the service differ from the list (missing: $($missing -join ', '); extra: $($extra -join ', '))." }
	return "Restricted to: $($actual -join ', ')."
}

function Invoke-SelfXSafeDelete {
	# Runs the delete helper of SelfXService.exe (/removetree: or /cleandata:, class SafeTree). The helper opens every entry
	# once without following links and deletes through that handle, so a folder that a user replaces by a junction between
	# check and delete is never followed (no time window as with Get-Item + Remove-Item). Fail closed: anything but the
	# exit code 0 together with the marker line is an error; there is no fallback to a delete by path.
	param(
		[Parameter(Mandatory = $true)][string]$Exe,
		[Parameter(Mandatory = $true)][string[]]$Arguments
	)
	If(-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "The delete helper '$Exe' is missing." }
	$output = @(& $Exe @Arguments 2>&1 | ForEach-Object { "$_" })
	$exitCode = $LASTEXITCODE
	If(($exitCode -ne 0) -or (@($output | Where-Object { $_ -eq 'SELFX-SAFEDELETE-OK' }).Count -ne 1))
	{
		throw "The delete helper failed (exit code $exitCode): $($output -join ' | ')"
	}
}

function Initialize-SelfXDataFolder {
	# Prepares ProgramData\SelfX before anything is written there as SYSTEM. A user can create this folder
	# (or a link in it) before the installation; the service later writes, rotates and deletes files in it as SYSTEM.
	# Steps: a link at the folder itself or below it is removed (the link, never its target); entries that are not owned by
	# SYSTEM, administrators or TrustedInstaller are deleted (link-safe); owner and rights of the folder are set again.
	# Logs\Users is the area of the users (their own folders are owned by them by design): it is neither entered nor changed.
	# Deleting is done by the helper in SelfXService.exe (SafeDeleteExe, from the checked package): it works through handles,
	# so a user cannot redirect the delete with a junction between check and delete.
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[Parameter(Mandatory = $true)][string]$SafeDeleteExe,
		[string[]]$TrustedOwnerSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'),
		[string]$UserArea = 'Logs\Users'
	)
	$root = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
	If($root -and (($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not $root.PSIsContainer))
	{
		# A link or a file instead of the folder: remove it (a link itself, never its target).
		Invoke-SelfXSafeDelete -Exe $SafeDeleteExe -Arguments @("/removetree:$Path")
		$root = $null
	}
	If(-not $root) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
	Invoke-SelfXSafeDelete -Exe $SafeDeleteExe -Arguments @("/cleandata:$Path", "/trusted:$($TrustedOwnerSids -join ';')", "/skip:$UserArea")

	# Owner first, then rights from scratch: explicit entries that a former owner added are removed by /reset.
	& icacls.exe $Path /setowner '*S-1-5-32-544' | Out-Null
	If($LASTEXITCODE -ne 0) { throw "icacls /setowner failed for '$Path' (exit code $LASTEXITCODE)." }
	& icacls.exe $Path /reset | Out-Null
	If($LASTEXITCODE -ne 0) { throw "icacls /reset failed for '$Path' (exit code $LASTEXITCODE)." }
	& icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
	If($LASTEXITCODE -ne 0) { throw "icacls failed for '$Path' (exit code $LASTEXITCODE)." }
}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
If(-not $IsAdmin) { throw 'Install.ps1 must run with administrator rights.' }
If($PSVersionTable.PSEdition -eq 'Core') { throw 'Install.ps1 must run in Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.' }
$SelfXWindows = Test-SelfXWindowsSupport
If([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Run Install.ps1 in a 64-bit PowerShell (use %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe from 32-bit agents).' }

# Mode -ConfigOnly: only the folder Config of an existing installation is replaced (Invoke-SelfXConfigOnly). The trust mode is the one
# of the anchor on the device: the anchor must exist and must not be changeable by users (Test-SelfXTrustAnchorState); the signers of the
# command line cannot widen it. The service, the programs, the shortcuts and the anchor are not touched; nothing is restarted.
If($ConfigOnly)
{
	$ConfigOnlyExit = 1
	$ConfigOnlyTranscript = $false
	Try
	{
		If($PSBoundParameters.ContainsKey('TrustedSigner') -or $AllowHashMode) { throw '-ConfigOnly cannot be combined with -TrustedSigner or -AllowHashMode: the trust anchor of the device is not changed. Nothing was changed.' }
		If(-not (Test-Path -LiteralPath $LogFolder -PathType Container)) { throw 'SelfX is not installed on this device (no folder ProgramData\SelfX\Logs). Install the full package first. Nothing was changed.' }
		Start-Transcript -Path (Join-Path $LogFolder 'Install.log') -Append | Out-Null
		$ConfigOnlyTranscript = $true
		Write-Output "Configuration update (-ConfigOnly) for '$InstallFolder'."
		$ConfigOnlyAnchor = Get-SelfXTrustAnchor
		If($null -eq $ConfigOnlyAnchor) { throw 'The trust anchor HKLM\SOFTWARE\SelfX\Trust is missing: the installed version is too old or SelfX is not installed. Install the full package first. Nothing was changed.' }
		If($ConfigOnlyAnchor.Mode -ceq 'Invalid') { throw 'The trust anchor HKLM\SOFTWARE\SelfX\Trust cannot be understood. Install the full package again. Nothing was changed.' }
		$AnchorProblem = Test-SelfXTrustAnchorState -Mode $ConfigOnlyAnchor.Mode -Signers @($ConfigOnlyAnchor.Signers)
		If($AnchorProblem) { throw "The trust anchor HKLM\SOFTWARE\SelfX\Trust is not safe ($AnchorProblem). Install the full package again. Nothing was changed." }
		$ConfigOnlyResult = Invoke-SelfXConfigOnly -PackageFolder $PackageFolder -InstallFolder $InstallFolder -Anchor $ConfigOnlyAnchor
		Write-Output "SelfX configuration installed ($($ConfigOnlyResult.Files) files, trust mode $($ConfigOnlyResult.Mode), code version $($ConfigOnlyResult.Version) unchanged). The service and the programs were not restarted; an open SelfX window shows the new settings after it is closed and opened again."
		$ConfigOnlyExit = 0
	}
	Catch { Write-Output "Configuration update failed: $($_.Exception.Message)" }
	Finally { If($ConfigOnlyTranscript) { Stop-Transcript | Out-Null } }
	exit $ConfigOnlyExit
}

# Trust mode: Signature with -TrustedSigner, otherwise Hash. The list of signers comes from the command line (Intune), never from
# the package. An invalid list, a contradiction and a downgrade (the anchor on the device says Signature, -TrustedSigner is missing
# and -AllowHashMode was not given) stop here, before anything is changed.
$SignatureRequested = $PSBoundParameters.ContainsKey('TrustedSigner')
$AllowedSigners = @()
If($SignatureRequested) { $AllowedSigners = @(ConvertTo-SelfXTrustedSignerList -TrustedSigner $TrustedSigner) }
$InstalledAnchor = Get-SelfXTrustAnchor
$InstalledMode = $(If($null -eq $InstalledAnchor) { '' } Else { $InstalledAnchor.Mode })
$TrustMode = Resolve-SelfXTrustMode -InstalledMode $InstalledMode -SignatureRequested $SignatureRequested -AllowHashMode ([bool]$AllowHashMode)
# Mode Signature: every program and script and both signed catalogs of the package, before anything on the device is changed
# (also before the data folder is prepared). A failure throws; nothing is written, also no log.
$VerifiedSignatures = $null
If($TrustMode -eq 'Signature') { $VerifiedSignatures = Test-SelfXPackageSignatures -PackageFolder $PackageFolder -AllowedThumbprint $AllowedSigners }

# Logs may contain script output; only SYSTEM and administrators can read them. The folder is cleaned of links and
# foreign-owned entries first, then owner and rights are set.
# The package is checked before anything on the device is changed; the delete helper is the checked SelfXService.exe of the package.
$VerifiedBinaryHashes = Test-SelfXPrebuiltBinaries -BinFolder $BinFolder -PackageFolder $PackageFolder
Initialize-SelfXDataFolder -Path $DataFolder -SafeDeleteExe (Join-Path $BinFolder 'SelfXService.exe')
New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
# The SelfX window, the status icon and the user actions log as the user into Logs\Users\<SID> (SelfXLog.ps1).
# Users may only create their own folder (CREATOR OWNER = full control on it); they cannot list the Users
# folder or read the folders of other users.
$UserLogFolder = Join-Path $LogFolder 'Users'
New-Item -ItemType Directory -Path $UserLogFolder -Force | Out-Null
& icacls.exe $UserLogFolder /setowner '*S-1-5-32-544' | Out-Null
& icacls.exe $UserLogFolder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(AD,X,RA)' '*S-1-3-0:(OI)(CI)(IO)F' | Out-Null
Start-Transcript -Path (Join-Path $LogFolder 'Install.log') -Append | Out-Null
If($SelfXWindows.Kind -eq 'Server') { Write-Output "Windows Server build $($SelfXWindows.Build): SelfX works as on a terminal server (mode TerminalServer)." }
Else { Write-Output "Windows 11 build $($SelfXWindows.Build): SelfX works in the mode Client." }

Try
{
	# Tool_Config.xml is a configuration file: the version is not read from it (an old Tool_Version element is ignored).
	# Read without DTD (fail closed for a DTD or an external entity).
	$ToolConfigFile = Join-Path $ConfigSource 'Tool_Config.xml'
	If(-not (Test-Path -LiteralPath $ToolConfigFile -PathType Leaf)) { throw 'Config\Tool_Config.xml is missing in the package (old package layout or broken package). The existing installation was not changed.' }
	$ToolConfig = New-Object System.Xml.XmlDocument
	$ToolConfig.XmlResolver = $null
	$ToolConfigSettings = New-Object System.Xml.XmlReaderSettings
	$ToolConfigSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
	$ToolConfigSettings.XmlResolver = $null
	$ToolConfigReader = [System.Xml.XmlReader]::Create($ToolConfigFile, $ToolConfigSettings)
	Try { $ToolConfig.Load($ToolConfigReader) } Finally { $ToolConfigReader.Dispose() }
	$ShortcutName = $ToolConfig.GUI_Config.Shortcut_Name.Trim()

	# The programs of the package are checked first: when they are missing or do not match, the existing
	# installation stays untouched and still works.
	Write-Output 'Programs in Bin checked against the manifest (before the data folder was prepared).'
	If($TrustMode -eq 'Signature') { Write-Output "Trust mode Signature: $($VerifiedSignatures.Files) programs and scripts are signed by an allowed signer; Config\SelfX.Config.cat and SelfX.Code.cat are signed and match the package (checked before the data folder was prepared). Allowed signers: $($AllowedSigners -join ', ')." }
	ElseIf($InstalledMode -and ($InstalledMode -cne 'Hash')) { Write-Output "Trust mode Hash: the device was in the mode $InstalledMode; the change was allowed with -AllowHashMode." }
	Else { Write-Output 'Trust mode Hash (no -TrustedSigner).' }
	$CheckedFiles = Test-SelfXFileManifest -PackageFolder $PackageFolder -SignedPackage:($TrustMode -eq 'Signature')
	If($null -eq $CheckedFiles) { throw 'SelfX.Code.json and SelfX.Config.json are missing in the package: it has no version and its files cannot be checked. Build the package with tools\New-SelfXIntuneWin.ps1. The existing installation was not changed.' }
	Write-Output "Package files checked against SelfX.Code.json and SelfX.Config.json ($CheckedFiles files)."
	# The version of the code, from the checked list.
	$ToolVersion = Get-SelfXPackageToolVersion -PackageFolder $PackageFolder
	Write-Output "Installing SelfX $ToolVersion to '$InstallFolder'."
	$PowerShell7 = Test-SelfXPowerShell7
	If($PowerShell7.Ready) { Write-Output "PowerShell $($PowerShell7.Version) found (machine-wide)." }
	Else { Write-Warning "$($PowerShell7.Reason) The installation continues." }

	# Remove a previous service so its files can be replaced
	$ExistingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
	If($ExistingService)
	{
		If($ExistingService.Status -ne 'Stopped') { Stop-Service -Name $ServiceName -Force }
		& sc.exe delete $ServiceName | Out-Null
		For($i = 0; ($i -lt 30) -and (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
	}

	# Close running status icons of all users; the new version is started again at the end.
	# Old layout (SelfX_Tray.ps1 directly in the install folder) and new layout (App\SelfX_Tray.ps1).
	$TrayPattern = [regex]::Escape($InstallFolder.TrimEnd('\')) + '\\(App\\)?SelfX_Tray\.ps1'
	$TrayProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
		Where-Object { ($_.ProcessId -ne $PID) -and ("$($_.CommandLine)" -match $TrayPattern) })
	ForEach($Process in $TrayProcesses)
	{
		Stop-Process -Id $Process.ProcessId -Force -ErrorAction SilentlyContinue
		Write-Output "Closed status icon process $($Process.ProcessId)."
	}

	# Replace the complete payload so old scripts cannot survive a package upgrade (also an installation in the old layout).
	Clear-SelfXInstallFolder -InstallFolder $InstallFolder
	# Code into App, configuration into Config; the programs and libraries from Bin that were checked at the start (.NET 10, self-contained).
	Copy-SelfXPayload -PackageFolder $PackageFolder -InstallFolder $InstallFolder -SignedPackage:($TrustMode -eq 'Signature')
	Write-Output 'Installed App (code, SelfXService.exe, SelfX.exe, WinRT, audio and disturb libraries from Bin) and Config (configuration).'
	# Users may read and run SelfX but must not change scripts that the service runs as SYSTEM (App and Config inherit the rights).
	& icacls.exe $InstallFolder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
	If($LASTEXITCODE -ne 0) { throw "icacls failed for '$InstallFolder' (exit code $LASTEXITCODE)." }
	# Service host and the starter without console window (shortcuts and status icon).
	$ServiceExe = Join-Path $AppFolder 'SelfXService.exe'
	$LauncherExe = Join-Path $AppFolder 'SelfX.exe'
	If(-not (Test-Path -LiteralPath $ServiceExe)) { throw 'SelfXService.exe is missing after the installation step.' }
	If(-not (Test-Path -LiteralPath $LauncherExe)) { throw 'SelfX.exe is missing after the installation step.' }
	# The installed folders must equal the checked package (scripts, configuration, WinRT libraries, both programs), and nothing of
	# an older layout may be left next to App and Config.
	$InstalledFiles = Test-SelfXInstalledFiles -InstallFolder $InstallFolder -SignedPackage:($TrustMode -eq 'Signature')
	Write-Output "Installed files checked against App\SelfX.Code.json and Config\SelfX.Config.json ($InstalledFiles files)."
	# Mode Signature: the installed lists are the ones that the signed catalogs covered.
	If($TrustMode -eq 'Signature')
	{
		Test-SelfXInstalledLists -InstallFolder $InstallFolder -Verified $VerifiedSignatures
		Write-Output 'Installed lists and catalogs (App\SelfX.Code.cat, Config\SelfX.Config.cat) are the ones of the signed package.'
	}
	# The trust anchor, before the service is registered and started (the service reads it).
	Set-SelfXTrustAnchor -Mode $TrustMode -Signers $AllowedSigners
	Write-Output "Trust anchor written: HKLM\SOFTWARE\SelfX\Trust, Mode = $TrustMode."

	New-Service -Name $ServiceName -DisplayName $ServiceDisplayName -BinaryPathName "`"$ServiceExe`"" -StartupType Automatic | Out-Null
	& sc.exe description $ServiceName 'Runs the SelfX actions that need administrator rights. Only scripts listed with Context System in the local SelfX catalog are accepted.' | Out-Null
	& sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/300000 | Out-Null
	# Privileges of the service: Restricted (default) or Default (all LocalSystem privileges).
	$PrivilegeMode = "$($ToolConfig.GUI_Config.Service_Privileges)".Trim()
	If($PrivilegeMode -notin @('Restricted', 'Default'))
	{
		If($PrivilegeMode) { Write-Warning "Service_Privileges '$PrivilegeMode' is not valid (Restricted or Default); using Restricted." }
		$PrivilegeMode = 'Restricted'
	}
	Write-Output ("Service privileges: " + (Set-SelfXServicePrivileges -Name $ServiceName -Mode $PrivilegeMode))
	Start-Service -Name $ServiceName

	# Shortcuts for all users: SelfX.exe starts Self_X.ps1 without a console window
	$ShortcutArguments = ''
	$ShortcutTargets = @()
	If($ToolConfig.GUI_Config.Shortcut_Desktop -eq 'True') { $ShortcutTargets += Join-Path $env:PUBLIC 'Desktop' }
	If($ToolConfig.GUI_Config.Shortcut_StartMenu -eq 'True') { $ShortcutTargets += Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs' }
	# Retain the fallback icon unless the configured branding is an existing ICO file.
	$ShortcutIcon = Join-Path $AppFolder 'Repair.ico'
	# Branding\... in Config, a default icon in App, a rooted value as it is (same rule as SelfXPaths.ps1).
	$BrandIcon = Resolve-SelfXInstalledImage -Value "$($ToolConfig.GUI_Config.Brand_Icon)" -AppFolder $AppFolder -ConfigFolder $ConfigFolder
	If($BrandIcon -and ($BrandIcon -like '*.ico') -and (Test-Path -LiteralPath $BrandIcon -PathType Leaf)) { $ShortcutIcon = $BrandIcon }
	$Shell = New-Object -ComObject WScript.Shell
	ForEach($Folder in $ShortcutTargets)
	{
		$Shortcut = $Shell.CreateShortcut((Join-Path $Folder "$ShortcutName.lnk"))
		$Shortcut.TargetPath = $LauncherExe
		$Shortcut.Arguments = $ShortcutArguments
		$Shortcut.WorkingDirectory = $AppFolder
		$Shortcut.IconLocation = $ShortcutIcon
		$Shortcut.Save()
	}

	# Entry in Apps & Features
	New-Item -Path $UninstallKey -Force | Out-Null
	Set-ItemProperty -Path $UninstallKey -Name DisplayName -Value 'SelfX'
	Set-ItemProperty -Path $UninstallKey -Name DisplayVersion -Value $ToolVersion
	Set-ItemProperty -Path $UninstallKey -Name Publisher -Value 'SelfX'
	Set-ItemProperty -Path $UninstallKey -Name InstallLocation -Value $InstallFolder
	Set-ItemProperty -Path $UninstallKey -Name DisplayIcon -Value $ShortcutIcon
	Set-ItemProperty -Path $UninstallKey -Name UninstallString -Value "`"$PowerShellExe`" -NoProfile -ExecutionPolicy Bypass -File `"$AppFolder\Uninstall.ps1`""
	Set-ItemProperty -Path $UninstallKey -Name NoModify -Value 1 -Type DWord
	Set-ItemProperty -Path $UninstallKey -Name NoRepair -Value 1 -Type DWord

	# Status icon for every user at sign-in (each user can hide it in SelfX > Settings).
	$RunKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
	If("$($ToolConfig.GUI_Config.Show_Tray_Icon)".Trim() -ne 'False')
	{
		Set-ItemProperty -Path $RunKey -Name 'SelfXTray' -Value "`"$LauncherExe`" /tray"
		# Show the icon now in the sessions of the signed-in users, not only after the next sign-in.
		Try
		{
			If(-not ('SelfXInstall.SessionStarter' -as [type]))
			{
				# The library was checked at the start; it is loaded from the package and not installed. The package folder
				# (Intune staging) is not protected against changes during the installation, so the file is read once, the
				# bytes are compared with the hash verified at the start, and exactly these bytes are loaded (N4: no time
				# between check and load; no second look at the file or at the manifest).
				$StarterBytes = [IO.File]::ReadAllBytes((Join-Path $BinFolder 'SelfXSessionStarter.dll'))
				$Sha256 = [Security.Cryptography.SHA256]::Create()
				Try { $StarterHash = [BitConverter]::ToString($Sha256.ComputeHash($StarterBytes)).Replace('-', '') } Finally { $Sha256.Dispose() }
				If($StarterHash -ne "$($VerifiedBinaryHashes['SelfXSessionStarter.dll'])") { throw 'SelfXSessionStarter.dll changed after the check; it was not loaded.' }
				[void][Reflection.Assembly]::Load($StarterBytes)
			}
			ForEach($Line in [SelfXInstall.SessionStarter]::StartInActiveSessions($LauncherExe, '/tray', $env:SystemRoot)) { Write-Output "Status icon: $Line" }
		}
		Catch
		{
			Write-Output "Status icon not started (starts at the next sign-in): $($_.Exception.Message)"
		}
	}
	Else
	{
		Remove-ItemProperty -Path $RunKey -Name 'SelfXTray' -ErrorAction SilentlyContinue
	}

	Write-Output "SelfX $ToolVersion installed. Service '$ServiceName' status: $((Get-Service -Name $ServiceName).Status)."
	$ExitCode = 0
}
Catch
{
	Write-Output "Installation failed: $($_.Exception.Message)"
	$ExitCode = 1
}
Finally
{
	Stop-Transcript | Out-Null
}
exit $ExitCode
