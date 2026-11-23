<#
.SYNOPSIS
    Install SelfX files, the local Windows service, and machine-wide shortcuts.

.DESCRIPTION
    Runs in elevated 64-bit Windows PowerShell 5.1, normally as SYSTEM via Intune/SCCM.
    Requires Windows 11 25H2 (build 26200) or newer; on older builds it stops before anything is changed.
    Stops and deletes an existing SelfXService, deletes the entire content of InstallFolder
    (default ProgramFiles\SelfX; the folder itself is kept because an open SelfX window or
    status icon may use it as working directory, locked files are retried for 20 seconds),
    copies Sources and Uninstall.ps1, and installs the service SelfXService.exe and the console-less
    starter SelfX.exe (SelfXLauncher.cs) used by the shortcuts and the status icon. Both are .NET 10
    programs (self-contained: no .NET runtime is needed on the device) that are built centrally by
    tools\Build-SelfXBinaries.ps1 into the folder Bin of the package. Before anything on the device is
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
    Version : 2.8.3

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.8.3    2026-11-23  fubu2k               SelfX.Files.json also lists SelfXService.exe and SelfX.exe; after copying, the installed
                                              folder is checked against the list again
#>

[CmdletBinding()]
param(
	[string]$InstallFolder = (Join-Path $env:ProgramFiles 'SelfX')
)

$ErrorActionPreference = 'Stop'
$ServiceName = 'SelfXService'
$ServiceDisplayName = 'SelfX Service'
$PackageFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourcesFolder = Join-Path $PackageFolder 'Sources'
$BinFolder = Join-Path $PackageFolder 'Bin'
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
		[version]$MinimumVersion = '7.6.0'
	)
	If(-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { return [pscustomobject]@{ Ready = $false; Version = $null; Reason = "PowerShell 7 was not found at '$Executable'. Install PowerShell $MinimumVersion or newer (MSI, machine-wide); SelfX works as soon as it is there (docs\Installation.md)." } }
	$Info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Executable)
	$Found = [version]('{0}.{1}.{2}' -f $Info.FileMajorPart, $Info.FileMinorPart, $Info.FileBuildPart)
	If($Found -lt $MinimumVersion) { return [pscustomobject]@{ Ready = $false; Version = $Found; Reason = "PowerShell $Found was found at '$Executable'; version $MinimumVersion or newer is required." } }
	# Everyone, Authenticated Users, Interactive and Users must not have rights to change files or permissions.
	$UserSids = @('S-1-1-0', 'S-1-5-11', 'S-1-5-4', 'S-1-5-32-545')
	$Dangerous = [Security.AccessControl.FileSystemRights]'WriteData, AppendData, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
	ForEach($Item in @((Split-Path -Parent $Executable), $Executable))
	{
		ForEach($Rule in (Get-Acl -LiteralPath $Item).Access)
		{
			If($Rule.AccessControlType -ne 'Allow') { continue }
			Try { $Sid = $Rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } Catch { continue }
			If(($UserSids -contains $Sid) -and ($Rule.FileSystemRights -band $Dangerous)) { throw "'$Item' can be changed by normal users ($($Rule.IdentityReference)). PowerShell 7 must be installed machine-wide in a folder that only administrators can change." }
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
		If((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne "$($Manifest.Binaries.$Name)") { throw "Bin\$Name does not match its SHA256 in the manifest." }
	}
	# The DLLs of the Windows SDK projection in WinRT: only plain file names, each one present and unchanged.
	ForEach($Name in @($Manifest.Binaries.PSObject.Properties.Name))
	{
		If($Expected.Contains($Name)) { continue }
		If($Name -notmatch '^WinRT/[A-Za-z0-9._-]+\.dll$') { throw "Bin\SelfX.Binaries.json lists an unexpected file '$Name'." }
		$File = Join-Path $BinFolder $Name.Replace('/', '\')
		If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Bin\$Name is missing." }
		If((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne "$($Manifest.Binaries.$Name)") { throw "Bin\$Name does not match its SHA256 in the manifest." }
	}
}

function Test-SelfXFileManifest {
	# Checks the package against SelfX.Files.json: every file below Sources, Uninstall.ps1, the DLLs of Bin\WinRT and
	# Bin\Audio (listed as WinRT/<name> and Audio/<name>) and the programs SelfXService.exe and SelfX.exe (from Bin) must be
	# listed and unchanged, and nothing may be in the package that is not listed. Returns the number of checked files, or $null
	# when the package has no such file (older package: warning only). A mismatch throws before anything is installed.
	param([Parameter(Mandatory = $true)][string]$PackageFolder)
	$ManifestPath = Join-Path $PackageFolder 'SelfX.Files.json'
	If(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return $null }
	Try { $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json }
	Catch { throw "SelfX.Files.json is not valid JSON: $($_.Exception.Message)" }
	If(-not $Manifest -or "$($Manifest.ManifestVersion)" -ne '1' -or -not $Manifest.Files) { throw 'SelfX.Files.json has an unknown format.' }
	$Sources = Join-Path $PackageFolder 'Sources'
	$ProgramNames = @('SelfXService.exe', 'SelfX.exe')
	$Listed = @{}
	ForEach($Property in @($Manifest.Files.PSObject.Properties))
	{
		$Relative = "$($Property.Name)"
		If($Relative -notmatch '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*$' -or $Relative -match '(^|/)\.\.?(/|$)') { throw "SelfX.Files.json lists an unsupported name '$Relative'." }
		$File = If($Relative -eq 'Uninstall.ps1') { Join-Path $PackageFolder 'Uninstall.ps1' } ElseIf(($Relative -like 'WinRT/*') -or ($Relative -like 'Audio/*') -or ($ProgramNames -contains $Relative)) { Join-Path (Join-Path $PackageFolder 'Bin') $Relative.Replace('/', '\') } Else { Join-Path $Sources $Relative.Replace('/', '\') }
		If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "$Relative is listed in SelfX.Files.json but missing in the package." }
		If((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne "$($Property.Value)") { throw "$Relative does not match its SHA256 in SelfX.Files.json." }
		$Listed[$Relative.ToLowerInvariant()] = $true
	}
	ForEach($Item in @(Get-ChildItem -LiteralPath $Sources -Recurse -File -Force))
	{
		$Relative = $Item.FullName.Substring($Sources.Length + 1).Replace('\', '/')
		If(-not $Listed.ContainsKey($Relative.ToLowerInvariant())) { throw "$Relative is in the package but not listed in SelfX.Files.json." }
	}
	# The WinRT libraries of the package (installed into WinRT) must all be listed too.
	$WinRTSource = Join-Path (Join-Path $PackageFolder 'Bin') 'WinRT'
	If(Test-Path -LiteralPath $WinRTSource -PathType Container)
	{
		ForEach($Item in @(Get-ChildItem -LiteralPath $WinRTSource -Recurse -File -Force))
		{
			$Relative = 'WinRT/' + $Item.FullName.Substring($WinRTSource.Length + 1).Replace('\', '/')
			If(-not $Listed.ContainsKey($Relative.ToLowerInvariant())) { throw "$Relative is in the package but not listed in SelfX.Files.json." }
		}
	}
	# The audio library of the package (installed into Audio) must be listed too.
	$AudioSource = Join-Path (Join-Path $PackageFolder 'Bin') 'Audio'
	If(Test-Path -LiteralPath $AudioSource -PathType Container)
	{
		ForEach($Item in @(Get-ChildItem -LiteralPath $AudioSource -Recurse -File -Force))
		{
			$Relative = 'Audio/' + $Item.FullName.Substring($AudioSource.Length + 1).Replace('\', '/')
			If(-not $Listed.ContainsKey($Relative.ToLowerInvariant())) { throw "$Relative is in the package but not listed in SelfX.Files.json." }
		}
	}
	If(-not $Listed.ContainsKey('uninstall.ps1')) { throw 'Uninstall.ps1 is not listed in SelfX.Files.json.' }
	ForEach($Program in $ProgramNames) { If(-not $Listed.ContainsKey($Program.ToLowerInvariant())) { throw "$Program is not listed in SelfX.Files.json." } }
	Return $Listed.Count
}

function Test-SelfXInstalledFiles {
	# After copying (finding N4 follow-up): compares the installed folder with the SelfX.Files.json copied into it. This closes
	# the gap between the check of the package and the copy: every listed file (scripts, configuration, WinRT libraries,
	# SelfXService.exe, SelfX.exe) must exist in the install folder with the listed SHA256. Throws at the first difference.
	# Returns the number of checked files.
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$Root = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	$ManifestPath = Join-Path $Root 'SelfX.Files.json'
	If(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'SelfX.Files.json is missing in the installation folder.' }
	Try { $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json }
	Catch { throw "SelfX.Files.json in the installation folder is not valid JSON: $($_.Exception.Message)" }
	If(-not $Manifest -or "$($Manifest.ManifestVersion)" -ne '1' -or -not $Manifest.Files) { throw 'SelfX.Files.json in the installation folder has an unknown format.' }
	$Count = 0
	ForEach($Property in @($Manifest.Files.PSObject.Properties))
	{
		$Relative = "$($Property.Name)"
		If($Relative -notmatch '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*$' -or $Relative -match '(^|/)\.\.?(/|$)') { throw "SelfX.Files.json lists an unsupported name '$Relative'." }
		$File = [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/', '\')))
		If(-not $File.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "$Relative points outside the installation folder." }
		If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "$Relative is missing in the installation folder." }
		If((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne "$($Property.Value)") { throw "$Relative in the installation folder does not match its SHA256 in SelfX.Files.json." }
		$Count++
	}
	Return $Count
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

function Initialize-SelfXDataFolder {
	# Prepares ProgramData\SelfX before anything is written there as SYSTEM. A user can create this folder
	# (or a link in it) before the installation; the service later writes, rotates and deletes files in it as SYSTEM.
	# Steps: a link at the folder itself or below it is removed (the link, never its target); entries that are not owned by
	# SYSTEM, administrators or TrustedInstaller are deleted (link-safe); owner and rights of the folder are set again.
	# Logs\Users is the area of the users (their own folders are owned by them by design): it is neither entered nor changed.
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[string[]]$TrustedOwnerSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'),
		[string]$UserArea = 'Logs\Users'
	)
	$skipFull = [IO.Path]::GetFullPath((Join-Path $Path $UserArea)).TrimEnd('\')

	function Remove-SelfXDataEntry {
		param([Parameter(Mandatory = $true)][string]$Entry)
		$item = Get-Item -LiteralPath $Entry -Force -ErrorAction SilentlyContinue
		If(-not $item) { return }
		If($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
		{
			If($item.PSIsContainer) { [IO.Directory]::Delete($Entry) } Else { [IO.File]::Delete($Entry) }
			return
		}
		If($item.PSIsContainer) { ForEach($child in @([IO.Directory]::EnumerateFileSystemEntries($Entry))) { Remove-SelfXDataEntry -Entry $child } }
		Remove-Item -LiteralPath $Entry -Force -ErrorAction Stop
	}

	function Clear-SelfXDataFolder {
		param([Parameter(Mandatory = $true)][string]$Folder)
		ForEach($child in @([IO.Directory]::EnumerateFileSystemEntries($Folder)))
		{
			$item = Get-Item -LiteralPath $child -Force
			If($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Remove-SelfXDataEntry -Entry $child; continue }
			$owner = (Get-Acl -LiteralPath $child).GetOwner([Security.Principal.SecurityIdentifier]).Value
			If($TrustedOwnerSids -notcontains $owner) { Remove-SelfXDataEntry -Entry $child; continue }
			If($item.PSIsContainer -and [IO.Path]::GetFullPath($child).TrimEnd('\') -ne $skipFull) { Clear-SelfXDataFolder -Folder $child }
		}
	}

	$root = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
	If($root -and ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Remove-SelfXDataEntry -Entry $Path; $root = $null }
	If($root -and -not $root.PSIsContainer) { Remove-SelfXDataEntry -Entry $Path; $root = $null }
	If(-not $root) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
	Clear-SelfXDataFolder -Folder $Path

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
Initialize-SelfXDataFolder -Path $DataFolder
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
	$ToolConfig = [xml](Get-Content -LiteralPath (Join-Path $SourcesFolder 'Tool_Config.xml') -Raw)
	$ToolVersion = $ToolConfig.GUI_Config.Tool_Version.Trim()
	$ShortcutName = $ToolConfig.GUI_Config.Shortcut_Name.Trim()
	Write-Output "Installing SelfX $ToolVersion to '$InstallFolder'."

	# The programs of the package are checked first: when they are missing or do not match, the existing
	# installation stays untouched and still works.
	Test-SelfXPrebuiltBinaries -BinFolder $BinFolder -PackageFolder $PackageFolder
	Write-Output 'Programs in Bin checked against the manifest.'
	$CheckedFiles = Test-SelfXFileManifest -PackageFolder $PackageFolder
	If($null -eq $CheckedFiles) { Write-Warning 'SelfX.Files.json is missing in the package: the files are not checked against a hash list. The installation continues.' }
	Else { Write-Output "Package files checked against SelfX.Files.json ($CheckedFiles files)." }
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
	$TrayPattern = [regex]::Escape($InstallFolder.TrimEnd('\')) + '\\SelfX_Tray\.ps1'
	$TrayProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
		Where-Object { ($_.ProcessId -ne $PID) -and ("$($_.CommandLine)" -match $TrayPattern) })
	ForEach($Process in $TrayProcesses)
	{
		Stop-Process -Id $Process.ProcessId -Force -ErrorAction SilentlyContinue
		Write-Output "Closed status icon process $($Process.ProcessId)."
	}

	# Replace the complete payload so old scripts cannot survive a package upgrade. The folder itself is
	# kept: Windows refuses to delete a folder that is the working directory of a running process (e.g. an
	# open SelfX window or status icon of an older version), which made the update fail with exit code 1.
	New-Item -ItemType Directory -Path $InstallFolder -Force | Out-Null
	For($Attempt = 1; $Attempt -le 10; $Attempt++)
	{
		ForEach($Item in @(Get-ChildItem -LiteralPath $InstallFolder -Force)) { Remove-Item -LiteralPath $Item.FullName -Recurse -Force -ErrorAction SilentlyContinue }
		# Remaining empty folders (working directory of a running process) do not matter, only files do.
		If(@(Get-ChildItem -LiteralPath $InstallFolder -Recurse -Force -File).Count -eq 0) { break }
		Start-Sleep -Seconds 2
	}
	$Locked = @(Get-ChildItem -LiteralPath $InstallFolder -Recurse -Force -File | Select-Object -ExpandProperty FullName)
	If($Locked.Count -gt 0) { throw "Files in '$InstallFolder' are in use and cannot be replaced: $($Locked -join ', ')" }
	Copy-Item -Path (Join-Path $SourcesFolder '*') -Destination $InstallFolder -Recurse -Force
	Copy-Item -LiteralPath (Join-Path $PackageFolder 'Uninstall.ps1') -Destination $InstallFolder -Force
	If($null -ne $CheckedFiles) { Copy-Item -LiteralPath (Join-Path $PackageFolder 'SelfX.Files.json') -Destination $InstallFolder -Force }
	# Users may read and run SelfX but must not change scripts that the service runs as SYSTEM.
	& icacls.exe $InstallFolder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
	If($LASTEXITCODE -ne 0) { throw "icacls failed for '$InstallFolder' (exit code $LASTEXITCODE)." }

	# Service host and the starter without console window (shortcuts and status icon): the programs from Bin
	# that were checked at the start (.NET 10, self-contained).
	$ServiceExe = Join-Path $InstallFolder 'SelfXService.exe'
	$LauncherExe = Join-Path $InstallFolder 'SelfX.exe'
	Copy-Item -LiteralPath (Join-Path $BinFolder 'SelfXService.exe') -Destination $ServiceExe -Force
	Copy-Item -LiteralPath (Join-Path $BinFolder 'SelfX.exe') -Destination $LauncherExe -Force
	Write-Output 'Installed SelfXService.exe and SelfX.exe from Bin.'
	# Library for PowerShell 7 (Windows Update orchestrator): the files checked above, into the protected install folder.
	$WinRTFolder = Join-Path $InstallFolder 'WinRT'
	New-Item -ItemType Directory -Path $WinRTFolder -Force | Out-Null
	ForEach($Name in @((Get-Content -LiteralPath (Join-Path $BinFolder 'SelfX.Binaries.json') -Raw | ConvertFrom-Json).Binaries.PSObject.Properties.Name | Where-Object { $_ -like 'WinRT/*' }))
	{
		Copy-Item -LiteralPath (Join-Path $BinFolder $Name.Replace('/', '\')) -Destination $WinRTFolder -Force
	}
	Write-Output 'Installed the WinRT library from Bin.'
	# Library for PowerShell 7 (Core Audio, action "No sound"): the file checked above, into the protected install folder.
	$AudioFolder = Join-Path $InstallFolder 'Audio'
	New-Item -ItemType Directory -Path $AudioFolder -Force | Out-Null
	Copy-Item -LiteralPath (Join-Path (Join-Path $BinFolder 'Audio') 'SelfXAudio.dll') -Destination $AudioFolder -Force
	Write-Output 'Installed the audio library from Bin.'
	If(-not (Test-Path -LiteralPath $ServiceExe)) { throw 'SelfXService.exe is missing after the installation step.' }
	If(-not (Test-Path -LiteralPath $LauncherExe)) { throw 'SelfX.exe is missing after the installation step.' }
	# The installed folder must equal the checked package (scripts, configuration, WinRT libraries, both programs).
	If($null -ne $CheckedFiles)
	{
		$InstalledFiles = Test-SelfXInstalledFiles -InstallFolder $InstallFolder
		Write-Output "Installed files checked against SelfX.Files.json ($InstalledFiles files)."
	}

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
	$ShortcutIcon = Join-Path $InstallFolder 'Repair.ico'
	$BrandIcon = "$($ToolConfig.GUI_Config.Brand_Icon)".Trim()
	If($BrandIcon -like '*.ico')
	{
		If(-not [IO.Path]::IsPathRooted($BrandIcon)) { $BrandIcon = Join-Path $InstallFolder $BrandIcon }
		If(Test-Path -LiteralPath $BrandIcon -PathType Leaf) { $ShortcutIcon = $BrandIcon }
	}
	$Shell = New-Object -ComObject WScript.Shell
	ForEach($Folder in $ShortcutTargets)
	{
		$Shortcut = $Shell.CreateShortcut((Join-Path $Folder "$ShortcutName.lnk"))
		$Shortcut.TargetPath = $LauncherExe
		$Shortcut.Arguments = $ShortcutArguments
		$Shortcut.WorkingDirectory = $InstallFolder
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
	Set-ItemProperty -Path $UninstallKey -Name UninstallString -Value "`"$PowerShellExe`" -NoProfile -ExecutionPolicy Bypass -File `"$InstallFolder\Uninstall.ps1`""
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
				# The library was checked at the start; it is loaded from the package and not installed.
				Add-Type -LiteralPath (Join-Path $BinFolder 'SelfXSessionStarter.dll')
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
