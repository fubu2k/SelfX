<#
.SYNOPSIS
    Install SelfX files, the local Windows service, and machine-wide shortcuts.

.DESCRIPTION
    Runs in elevated 64-bit Windows PowerShell 5.1, normally as SYSTEM via Intune/SCCM.
    Stops and deletes an existing SelfXService, deletes the entire content of InstallFolder
    (default ProgramFiles\SelfX; the folder itself is kept because an open SelfX window or
    status icon may use it as working directory, locked files are retried for 20 seconds),
    copies Sources and Uninstall.ps1, and installs the service SelfXService.exe and the console-less
    starter SelfX.exe (SelfXLauncher.cs) used by the shortcuts and the status icon. When the package
    contains the folder Bin (built centrally by tools\Build-SelfXBinaries.ps1), these prebuilt files
    are installed after a check: the manifest Bin\SelfX.Binaries.json must list the SHA256 of the
    sources in the package and of each file. Any failed check stops the installation (nothing is
    compiled instead). The files are unsigned; AppLocker/WDAC allow them with hash rules. Without Bin both programs are compiled on the device as before, with the temporary
    files of the compiler in a folder that only SYSTEM and administrators can write.
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
    (not elevated) rights of the signed-in user (SelfXSessionStarter.cs, compiled in memory);
    in other contexts it appears at the next sign-in. A failed start is logged and does not
    fail the installation. Open SelfX windows are not closed. Reinstallation
    removes local customizations in InstallFolder and interrupts service actions. No Windows
    restart is requested. Exits 0 on success or 1 for caught installation failures; initial
    privilege, edition and bitness checks throw before the installation try block.

.NOTES
    Name    : Install.ps1
    Package : SelfX Service
    Context : Installer (SYSTEM via Intune/SCCM)
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.1.0    2026-10-28  Wolfgang Baeck       Shortcut and Apps & Features icon from Brand_Icon (branding)
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.5.0    2026-11-04  Wolfgang Baeck       Status icon at sign-in (HKLM Run "SelfXTray"); modern UI without MahApps
    2.5.2    2026-11-04  Wolfgang Baeck       Fix exit code 1 on update while SelfX or the status icon is open: the
                                              install folder is emptied instead of deleted (retries for locked files)
    2.5.3    2026-11-04  Wolfgang Baeck       Shortcuts and status icon start through SelfX.exe: no console window at start
    2.5.4    2026-11-05  Wolfgang Baeck       Health_Config: Defender Fix button only while the status is not OK
    2.5.5    2026-11-05  Wolfgang Baeck       Installs HealthChecks\Check-Compliance.ps1 (local compliance criteria for the Compliance row)
    2.5.6    2026-11-05  Wolfgang Baeck       Installs Scripts_to_run\SelfX_Updates_Install.ps1 (Fix button for pending Windows and Store updates)
    2.5.8    2026-11-05  Wolfgang Baeck       Status icon starts right after the installation in all active user sessions
    2.6.0    2026-11-06  Wolfgang Baeck       Logs\Users folder for the logs of the users (SelfXLog.ps1)
    2.6.11   2026-11-22  fubu2k               Prebuilt programs from Bin, checked against the SHA256 manifest; on-device
                                              compiling uses a protected TEMP (F9)
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
$ServiceSource = Join-Path $PackageFolder 'Service\SelfXService.cs'
$LauncherSource = Join-Path $PackageFolder 'Service\SelfXLauncher.cs'
$SessionStarterSource = Join-Path $PackageFolder 'Service\SelfXSessionStarter.cs'
$BinFolder = Join-Path $PackageFolder 'Bin'
$DataFolder = Join-Path $env:ProgramData 'SelfX'
$LogFolder = Join-Path $DataFolder 'Logs'
$UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SelfX'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Test-SelfXPrebuiltBinaries {
	# Checks the prebuilt programs of the package (F9). Throws with a reason when any check fails; the caller
	# stops the installation then (fail closed, no fallback to compiling).
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
	}
	$ManifestPath = Join-Path $BinFolder 'SelfX.Binaries.json'
	If(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'Bin\SelfX.Binaries.json is missing.' }
	Try { $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json }
	Catch { throw "Bin\SelfX.Binaries.json is not valid JSON: $($_.Exception.Message)" }
	If(-not $Manifest -or "$($Manifest.ManifestVersion)" -ne '1' -or -not $Manifest.Sources -or -not $Manifest.Binaries) { throw 'Bin\SelfX.Binaries.json has an unknown format.' }
	ForEach($Name in $Expected.Keys)
	{
		$Source = $Expected[$Name]
		$SourcePath = Join-Path $PackageFolder ($Source.Replace('/', '\'))
		If(-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "Source $Source is missing in the package." }
		If((Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash -ne "$($Manifest.Sources.$Source)") { throw "Bin\$Name was not built from the $Source of this package (rebuild with tools\Build-SelfXBinaries.ps1)." }
		$File = Join-Path $BinFolder $Name
		If(-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Bin\$Name is missing." }
		If((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne "$($Manifest.Binaries.$Name)") { throw "Bin\$Name does not match its SHA256 in the manifest." }
	}
}

function Invoke-SelfXCompile {
	# Compiles on the device when the package has no Bin folder. The compiler writes temporary files to TEMP;
	# for SYSTEM that is C:\Windows\Temp, where users can create files. A folder below the install folder is
	# used instead (its permissions were set before: SYSTEM and administrators full control, users read only;
	# users cannot create it in advance below Program Files) and removed afterwards.
	param([Parameter(Mandatory = $true)][scriptblock]$Compile, [Parameter(Mandatory = $true)][string]$ProtectedRoot)
	$CompileTemp = Join-Path $ProtectedRoot ('Build-' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $CompileTemp -Force | Out-Null
	$SavedTemp = $env:TEMP
	$SavedTmp = $env:TMP
	Try
	{
		$env:TEMP = $CompileTemp
		$env:TMP = $CompileTemp
		& $Compile
	}
	Finally
	{
		$env:TEMP = $SavedTemp
		$env:TMP = $SavedTmp
		Remove-Item -LiteralPath $CompileTemp -Recurse -Force -ErrorAction SilentlyContinue
	}
}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
If(-not $IsAdmin) { throw 'Install.ps1 must run with administrator rights.' }
If($PSVersionTable.PSEdition -eq 'Core') { throw 'Install.ps1 must run in Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.' }
If([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Run Install.ps1 in a 64-bit PowerShell (use %SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe from 32-bit agents).' }

New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
# Logs may contain script output; only SYSTEM and administrators can read them.
& icacls.exe $DataFolder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
# The SelfX window, the status icon and the user actions log as the user into Logs\Users\<SID> (SelfXLog.ps1).
# Users may only create their own folder (CREATOR OWNER = full control on it); they cannot list the Users
# folder or read the folders of other users.
$UserLogFolder = Join-Path $LogFolder 'Users'
New-Item -ItemType Directory -Path $UserLogFolder -Force | Out-Null
& icacls.exe $UserLogFolder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(AD,X,RA)' '*S-1-3-0:(OI)(CI)(IO)F' | Out-Null
Start-Transcript -Path (Join-Path $LogFolder 'Install.log') -Append | Out-Null

Try
{
	$ToolConfig = [xml](Get-Content -LiteralPath (Join-Path $SourcesFolder 'Tool_Config.xml') -Raw)
	$ToolVersion = $ToolConfig.GUI_Config.Tool_Version.Trim()
	$ShortcutName = $ToolConfig.GUI_Config.Shortcut_Name.Trim()
	Write-Output "Installing SelfX $ToolVersion to '$InstallFolder'."

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
	$TrayProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
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
	# Users may read and run SelfX but must not change scripts that the service runs as SYSTEM.
	& icacls.exe $InstallFolder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
	If($LASTEXITCODE -ne 0) { throw "icacls failed for '$InstallFolder' (exit code $LASTEXITCODE)." }

	# Service host and the starter without console window (shortcuts and status icon): prebuilt and checked
	# from Bin when the package has it (F9), otherwise compiled locally with the C# compiler of the .NET Framework.
	$ServiceExe = Join-Path $InstallFolder 'SelfXService.exe'
	$LauncherExe = Join-Path $InstallFolder 'SelfX.exe'
	$UsePrebuilt = Test-Path -LiteralPath $BinFolder -PathType Container
	If($UsePrebuilt)
	{
		Test-SelfXPrebuiltBinaries -BinFolder $BinFolder -PackageFolder $PackageFolder
		Copy-Item -LiteralPath (Join-Path $BinFolder 'SelfXService.exe') -Destination $ServiceExe -Force
		Copy-Item -LiteralPath (Join-Path $BinFolder 'SelfX.exe') -Destination $LauncherExe -Force
		Write-Output 'Installed the prebuilt programs from Bin (manifest checked).'
	}
	Else
	{
		Invoke-SelfXCompile -ProtectedRoot $InstallFolder -Compile {
			Add-Type -TypeDefinition (Get-Content -LiteralPath $ServiceSource -Raw) `
				-ReferencedAssemblies 'System.ServiceProcess', 'System.Xml' `
				-OutputAssembly $ServiceExe -OutputType ConsoleApplication
			Add-Type -TypeDefinition (Get-Content -LiteralPath $LauncherSource -Raw) `
				-OutputAssembly $LauncherExe -OutputType WindowsApplication
		}
		Write-Output 'Compiled SelfXService.exe and SelfX.exe on the device (the package has no Bin folder).'
	}
	If(-not (Test-Path -LiteralPath $ServiceExe)) { throw 'SelfXService.exe is missing after the installation step.' }
	If(-not (Test-Path -LiteralPath $LauncherExe)) { throw 'SelfX.exe is missing after the installation step.' }

	New-Service -Name $ServiceName -DisplayName $ServiceDisplayName -BinaryPathName "`"$ServiceExe`"" -StartupType Automatic | Out-Null
	& sc.exe description $ServiceName 'Runs the SelfX actions that need administrator rights. Only scripts listed with Context System in the local SelfX catalog are accepted.' | Out-Null
	& sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/300000 | Out-Null
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
				# The prebuilt library was checked above; it is loaded from the package and not installed.
				If($UsePrebuilt) { Add-Type -LiteralPath (Join-Path $BinFolder 'SelfXSessionStarter.dll') }
				Else { Invoke-SelfXCompile -ProtectedRoot $InstallFolder -Compile { Add-Type -TypeDefinition (Get-Content -LiteralPath $SessionStarterSource -Raw) } }
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
