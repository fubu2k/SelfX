<#
.SYNOPSIS
    Install SelfX files, the local Windows service, and machine-wide shortcuts.

.DESCRIPTION
    Runs in elevated 64-bit Windows PowerShell 5.1, normally as SYSTEM via Intune/SCCM.
    Requires Windows 11 25H2 (build 26200) or newer; on older builds it stops before anything is changed.
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
    The files are unsigned; AppLocker/WDAC allow them with hash rules.
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
#>

[CmdletBinding()]
param(
	[string]$InstallFolder = (Join-Path $env:ProgramFiles 'SelfX')
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

function Test-SelfXWindowsBuild {
	# SelfX Service needs Windows 11 25H2 (build 26200) or newer. Older builds are not supported any more and the
	# installation stops before anything is changed (hard abort). The build number is read from the registry
	# (not from [Environment]::OSVersion, which an application manifest can falsify).
	param(
		[int]$Build = 0,
		[int]$MinimumBuild = 26200
	)
	If($Build -le 0)
	{
		Try { $Build = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber }
		Catch { throw 'The Windows build number cannot be read. SelfX Service needs Windows 11 25H2 (build 26200) or newer.' }
	}
	If($Build -lt $MinimumBuild) { throw "Windows build $Build is not supported. SelfX Service needs Windows 11 25H2 (build $MinimumBuild) or newer." }
	return $Build
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
	# Uninstall.ps1 (top of the package), the programs SelfXService.exe and SelfX.exe and the DLLs WinRT/<name> and Audio/<name>
	# (from Bin), everything else from App. Configuration names are relative to Config. Every file below App and Config, every DLL
	# of Bin\WinRT and Bin\Audio, Uninstall.ps1 and both programs must be listed in exactly one of the two lists and unchanged,
	# and nothing may be in App or Config that is not listed. Returns the number of checked files, or $null when the package has
	# neither list (the caller refuses it: no version). A package in the old layout (folder Sources), a mismatch, a missing list
	# or a file in both lists throws before anything is installed.
	param([Parameter(Mandatory = $true)][string]$PackageFolder)
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
			ElseIf(($Relative -like 'WinRT/*') -or ($Relative -like 'Audio/*') -or ($ProgramNames -contains $Relative)) { $File = Join-Path (Join-Path $PackageFolder 'Bin') $Relative.Replace('/', '\') }
			Else { $File = Join-Path $AppSource $Relative.Replace('/', '\') }
			If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "$Relative is listed in $ListName but missing in the package." }
			If((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Entry.Hash) { throw "$Relative does not match its SHA256 in $ListName." }
			$Listed[$Relative.ToLowerInvariant()] = $ListName
		}
	}
	# Every file of App, Config and of the libraries in Bin\WinRT and Bin\Audio must be listed in the list of its folder.
	$Folders = @(
		@{ Path = $AppSource; Prefix = ''; List = 'SelfX.Code.json' },
		@{ Path = $ConfigSource; Prefix = ''; List = 'SelfX.Config.json' },
		@{ Path = (Join-Path (Join-Path $PackageFolder 'Bin') 'WinRT'); Prefix = 'WinRT/'; List = 'SelfX.Code.json' },
		@{ Path = (Join-Path (Join-Path $PackageFolder 'Bin') 'Audio'); Prefix = 'Audio/'; List = 'SelfX.Code.json' }
	)
	ForEach($Folder in $Folders)
	{
		If(-not (Test-Path -LiteralPath $Folder.Path -PathType Container)) { continue }
		$Root = (Get-Item -LiteralPath $Folder.Path -Force).FullName.TrimEnd('\')
		ForEach($Item in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force))
		{
			$Relative = $Folder.Prefix + $Item.FullName.Substring($Root.Length + 1).Replace('\', '/')
			If(($Folder.Prefix -eq '') -and ($Relative -ceq $Folder.List)) { continue }
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
	# (scripts, WinRT and Audio libraries, SelfXService.exe, SelfX.exe, Uninstall.ps1; names relative to App), Config\SelfX.Config.json
	# the configuration folder Config (names relative to Config). This closes the gap between the check of the package and the copy:
	# every listed file must exist with the listed SHA256, in exactly one of the two lists; no file in App or Config may be unlisted;
	# no link may be in the way; and the install folder itself may hold nothing but App and Config (no mixed state with an older
	# layout; an empty folder that a running process still uses as working folder is allowed). Throws at the first difference.
	# Returns the number of checked files.
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$Root = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	$Count = 0
	$Listed = @{}
	ForEach($List in @(@{ Name = 'SelfX.Code.json'; Folder = 'App' }, @{ Name = 'SelfX.Config.json'; Folder = 'Config' }))
	{
		$ListName = $List.Name
		$FolderRoot = Join-Path $Root $List.Folder
		$FolderItem = Get-Item -LiteralPath $FolderRoot -Force -ErrorAction SilentlyContinue
		If(-not $FolderItem -or -not $FolderItem.PSIsContainer) { throw "The folder $($List.Folder) is missing in the installation folder." }
		If($FolderItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "The folder $($List.Folder) in the installation folder is a link." }
		$ManifestPath = Join-Path $FolderRoot $ListName
		If(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "$($List.Folder)\$ListName is missing in the installation folder." }
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
	# SelfX.exe, Bin\WinRT\*.dll (as listed in Bin\SelfX.Binaries.json) and Bin\Audio\SelfXAudio.dll into InstallFolder\App, and
	# Config\* (configuration, SelfX.Config.json) into InstallFolder\Config. Nothing is copied to the install folder itself.
	param(
		[Parameter(Mandatory = $true)][string]$PackageFolder,
		[Parameter(Mandatory = $true)][string]$InstallFolder
	)
	$Bin = Join-Path $PackageFolder 'Bin'
	$App = Join-Path $InstallFolder 'App'
	$Config = Join-Path $InstallFolder 'Config'
	# A folder of the old layout that is still in use (working directory) may remain empty; App and Config are created fresh.
	New-Item -ItemType Directory -Path $App, $Config -Force | Out-Null
	Copy-Item -Path (Join-Path (Join-Path $PackageFolder 'App') '*') -Destination $App -Recurse -Force
	Copy-Item -Path (Join-Path (Join-Path $PackageFolder 'Config') '*') -Destination $Config -Recurse -Force
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
$null = Test-SelfXWindowsBuild
If([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Run Install.ps1 in a 64-bit PowerShell (use %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe from 32-bit agents).' }

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
	$CheckedFiles = Test-SelfXFileManifest -PackageFolder $PackageFolder
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
	Copy-SelfXPayload -PackageFolder $PackageFolder -InstallFolder $InstallFolder
	Write-Output 'Installed App (code, SelfXService.exe, SelfX.exe, WinRT and audio libraries from Bin) and Config (configuration).'
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
	$InstalledFiles = Test-SelfXInstalledFiles -InstallFolder $InstallFolder
	Write-Output "Installed files checked against App\SelfX.Code.json and Config\SelfX.Config.json ($InstalledFiles files)."

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
