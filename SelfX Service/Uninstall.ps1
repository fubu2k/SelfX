<#
.SYNOPSIS
    Remove the SelfX service, installed payload, shortcuts, and uninstall registration.

.DESCRIPTION
    Runs elevated, normally as SYSTEM via Intune/SCCM. Stops and deletes SelfXService,
    waits up to thirty seconds for removal, deletes configured shortcuts from the public
    desktop and machine Start Menu, and removes the HKLM Apps & Features entry. Deletes
    the entire InstallFolder (default ProgramFiles\SelfX), including local customizations. Both layouts are removed: the
    current one (InstallFolder\App and InstallFolder\Config) and the older one (all files directly in InstallFolder).
    ProgramData\SelfX logs are retained unless -RemoveLogs deletes that directory too. Folders in
    ProgramData\SelfX are deleted without following junctions or symbolic links (a link is removed,
    never the folder it points to), because users can create links in their own Logs\Users folder.
    Device logs reports (ProgramData\SelfX\Reports) and the status cache (ProgramData\SelfX\Cache)
    are always deleted (with Logs\Users on -RemoveLogs) by the helper of SelfXService.exe, which opens every entry
    without following links and deletes through that handle; without the helper nothing is deleted by path. The HKLM Run entry of the status icon is removed. Open SelfX windows
    and status icons of all signed-in users (powershell.exe or pwsh.exe running Self_X.ps1 or
    SelfX_Tray.ps1 from InstallFolder or InstallFolder\App) are closed first, because they keep the install
    folder in use. Per-user settings and caches (HKCU\Software\SelfX,
    LOCALAPPDATA\SelfX) are not removed. The Windows event log SelfX (with its entries) and the source SelfXService are removed;
    a registration of the source in the Application log (older versions) is removed too, its old entries stay there.
    Install files locked by other programs are retried for up to 90 seconds;
    an empty install folder that is still in use is left behind and
    does not count as failure. A service that is only marked for deletion (still opened by
    another program such as the Services console) does not count as failure either.
    Writes ProgramData\SelfX\Logs\Uninstall.log when the Logs folder exists.
    Service availability is interrupted; Windows is not restarted. Exits 1 for missing
    administrator rights or remaining files/service, and 0 otherwise. Several deletion
    errors are suppressed, so exit 0 does not verify every shortcut or registry removal.

.NOTES
    Name    : Uninstall.ps1
    Package : SelfX Service
    Context : Installer (SYSTEM via Intune/SCCM)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.6.10   2026-11-22  fubu2k               Security: the data folders are deleted without following junctions or symbolic
                                              links (users own subfolders of Logs\Users and can create links there); a
                                              link is removed itself, never its target
    2.6.11   2026-11-23  fubu2k               Security (M1): Reports, Cache and Logs\Users are deleted by the handle-based helper of
                                              SelfXService.exe (no time window between link check and delete)
    3.1.0    2026-11-27  fubu2k               Both layouts: Tool_Config.xml, the delete helper and the open windows are found in App and Config
                                              and, for an installation of an older version, directly in InstallFolder; Tool_Config.xml is read
                                              without DTD
    3.1.0    2026-11-27  fubu2k               Removes the trust anchor HKLM\SOFTWARE\SelfX\Trust (written by Install.ps1); HKLM\SOFTWARE\SelfX\Support
                                              is kept
    3.1.0    2026-11-27  fubu2k               Removes the work folders InstallFolder.ConfigStage, .ConfigOld and .ConfigStage.Failed that an interrupted
                                              Install.ps1 -ConfigOnly can leave next to the install folder (delete helper, no link is followed)
    3.1.0    2026-11-28  fubu2k               Removes the Windows event log SelfX and the source SelfXService (also a registration of an older version in
                                              the Application log; its old entries stay there)
#>

[CmdletBinding()]
param(
	[string]$InstallFolder = (Join-Path $env:ProgramFiles 'SelfX'),
	[switch]$RemoveLogs
)

$ServiceName = 'SelfXService'
$UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SelfX'
$DataFolder = Join-Path $env:ProgramData 'SelfX'

# Deletes a folder tree as SYSTEM without following junctions or symbolic links. Users own their subfolders of
# Logs\Users and can create links there; a recursive delete could otherwise reach files outside the tree.
# A link is removed itself (never its target); real files and folders are deleted bottom-up.
function Remove-SelfXTree
{
	param([Parameter(Mandatory = $true)][string]$Path)
	$item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
	If(-not $item) { return }
	If($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
	{
		Try { If($item.PSIsContainer) { [IO.Directory]::Delete($Path) } Else { [IO.File]::Delete($Path) } } Catch {}
		return
	}
	If($item.PSIsContainer)
	{
		Try { $children = @([IO.Directory]::EnumerateFileSystemEntries($Path)) } Catch { $children = @() }
		ForEach($child in $children) { Remove-SelfXTree -Path $child }
	}
	Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

# Deletes folders as SYSTEM with the helper of SelfXService.exe (/removetree:, class SafeTree): every entry is opened once
# without following links and deleted through that handle, so a user cannot redirect the delete with a junction between check
# and delete. Returns $true only for exit code 0 with the marker line; there is no fallback to a delete by path.
function Remove-SelfXTreeSafe
{
	param([Parameter(Mandatory = $true)][string]$Exe, [Parameter(Mandatory = $true)][string]$Path)
	If(-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { Write-Output "Not deleted (delete helper missing): $Path"; return $false }
	$output = @(& $Exe "/removetree:$Path" 2>&1 | ForEach-Object { "$_" })
	If(($LASTEXITCODE -eq 0) -and (@($output | Where-Object { $_ -eq 'SELFX-SAFEDELETE-OK' }).Count -eq 1)) { return $true }
	Write-Output "Not deleted completely: $Path ($($output -join ' | '))"
	return $false
}

# Name of the log in which an event source is registered, '' when it is not registered (same as in Install.ps1).
function Get-SelfXEventSourceLog
{
	param([Parameter(Mandatory = $true)][string]$Source)
	If(-not [Diagnostics.EventLog]::SourceExists($Source)) { return '' }
	return "$([Diagnostics.EventLog]::LogNameFromSourceName($Source, '.'))"
}

function Test-SelfXEventLogExists
{
	param([Parameter(Mandatory = $true)][string]$LogName)
	return [Diagnostics.EventLog]::Exists($LogName)
}

# Removes the Windows event log SelfX with its entries and the source SelfXService; a source that an older version registered in
# another log (Application) is removed there too (only the registration: the old entries of that log stay). Returns a line for the log.
function Remove-SelfXEventLog
{
	param([string]$LogName = 'SelfX', [string]$Source = 'SelfXService')
	$done = New-Object System.Collections.Generic.List[string]
	Try
	{
		$SourceLog = Get-SelfXEventSourceLog -Source $Source
		If($SourceLog -and ($SourceLog -ne $LogName)) { Remove-EventLog -Source $Source -ErrorAction Stop; $done.Add("source $Source removed from '$SourceLog'") }
		If(Test-SelfXEventLogExists -LogName $LogName) { Remove-EventLog -LogName $LogName -ErrorAction Stop; $done.Add("log $LogName removed") }
	}
	Catch { return "The event log $LogName could not be removed completely: $($_.Exception.Message)" }
	If(-not $done.Count) { return "No event log $LogName to remove." }
	return "Windows event log: $($done -join '; ')."
}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
If(-not $IsAdmin) { Write-Output 'Uninstall.ps1 must run with administrator rights.'; exit 1 }

# This script may run from the install folder, which is deleted below
Set-Location -LiteralPath $env:SystemRoot
[Environment]::CurrentDirectory = $env:SystemRoot

# Log next to Install.log (the folder exists after an installation and is readable only by administrators)
$Transcript = $false
If(Test-Path -LiteralPath (Join-Path $DataFolder 'Logs'))
{
	Try { Start-Transcript -Path (Join-Path $DataFolder 'Logs\Uninstall.log') -Append | Out-Null; $Transcript = $true } Catch {}
}

# Current layout (Config\Tool_Config.xml, App\SelfXService.exe) first, then the layout of older versions (directly in InstallFolder).
$ShortcutName = 'SelfX (Self fix)'
$ToolConfigFile = @((Join-Path $InstallFolder 'Config\Tool_Config.xml'), (Join-Path $InstallFolder 'Tool_Config.xml')) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
If($ToolConfigFile)
{
	Try
	{
		$ToolConfig = New-Object System.Xml.XmlDocument
		$ToolConfig.XmlResolver = $null
		$XmlSettings = New-Object System.Xml.XmlReaderSettings
		$XmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
		$XmlSettings.XmlResolver = $null
		$XmlReader = [System.Xml.XmlReader]::Create($ToolConfigFile, $XmlSettings)
		Try { $ToolConfig.Load($XmlReader) } Finally { $XmlReader.Dispose() }
		$Name = $ToolConfig.GUI_Config.Shortcut_Name
		If(-not [string]::IsNullOrWhiteSpace($Name)) { $ShortcutName = $Name.Trim() }
	}
	Catch { Write-Output "Tool_Config.xml could not be read; the default shortcut name is used." }
}

$Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
If($Service)
{
	If($Service.Status -ne 'Stopped') { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue }
	& sc.exe delete $ServiceName | Out-Null
	For($i = 0; ($i -lt 30) -and (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
}
# The event log of the service (after the service has stopped, so it writes nothing any more). A failure does not fail the uninstallation.
Write-Output (Remove-SelfXEventLog)

# Check both shared shortcut locations even if installation created only one shortcut.
ForEach($Folder in @((Join-Path $env:PUBLIC 'Desktop'), (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')))
{
	Remove-Item -LiteralPath (Join-Path $Folder "$ShortcutName.lnk") -Force -ErrorAction SilentlyContinue
}

Remove-Item -Path $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'SelfXTray' -ErrorAction SilentlyContinue
# The trust anchor of Install.ps1 (mode and allowed signers, 64-bit view). HKLM\SOFTWARE\SelfX\Support (ticket routing, set by
# Intune) is not touched. After the removal a later installation starts without an anchor (mode Hash needs no -AllowHashMode).
Try
{
	$TrustBase = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
	Try { $TrustBase.DeleteSubKeyTree('SOFTWARE\SelfX\Trust', $false) } Finally { $TrustBase.Dispose() }
}
Catch { Write-Output "The trust anchor HKLM\SOFTWARE\SelfX\Trust could not be removed: $($_.Exception.GetType().Name)" }

# Close open SelfX windows and status icons of all signed-in users: they use the install folder (working
# directory, scripts) and would otherwise make the uninstallation fail.
$SelfXPattern = [regex]::Escape($InstallFolder.TrimEnd('\')) + '\\(App\\)?(Self_X|SelfX_Tray)\.ps1'
$SelfXProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
	Where-Object { ($_.ProcessId -ne $PID) -and ("$($_.CommandLine)" -match $SelfXPattern) })
ForEach($Process in $SelfXProcesses)
{
	Stop-Process -Id $Process.ProcessId -Force -ErrorAction SilentlyContinue
	Write-Output "Closed SelfX process $($Process.ProcessId)."
}
If($SelfXProcesses.Count -gt 0) { Start-Sleep -Seconds 2 }

# Data of the users: Reports, Cache and (with -RemoveLogs) Logs\Users are deleted by the handle-based helper while it still exists in
# the install folder. Users can create links in their own folders there; the helper never follows them (M1).
$SafeDeleteExe = Join-Path $InstallFolder 'App\SelfXService.exe'
If(-not (Test-Path -LiteralPath $SafeDeleteExe -PathType Leaf)) { $SafeDeleteExe = Join-Path $InstallFolder 'SelfXService.exe' }
$DataFoldersSafe = $true
$DataFolders = @((Join-Path $DataFolder 'Reports'), (Join-Path $DataFolder 'Cache'))
If($RemoveLogs) { $DataFolders += (Join-Path $DataFolder 'Logs\Users') }
ForEach($Folder in $DataFolders)
{
	If(-not (Remove-SelfXTreeSafe -Exe $SafeDeleteExe -Path $Folder)) { $DataFoldersSafe = $false }
}
# Work folders of an interrupted configuration update (Install.ps1 -ConfigOnly) lie next to the install folder.
ForEach($Suffix in @('.ConfigStage', '.ConfigOld', '.ConfigStage.Failed'))
{
	$WorkFolder = $InstallFolder.TrimEnd('\') + $Suffix
	If(Test-Path -LiteralPath $WorkFolder) { $null = Remove-SelfXTreeSafe -Exe $SafeDeleteExe -Path $WorkFolder }
}

# Other programs (e.g. an Explorer window) can still lock the folder or single files, so removal is retried
# for up to 90 seconds.
For($Attempt = 1; ($Attempt -le 45) -and (Test-Path -LiteralPath $InstallFolder); $Attempt++)
{
	Remove-Item -LiteralPath $InstallFolder -Recurse -Force -ErrorAction SilentlyContinue
	If(Test-Path -LiteralPath $InstallFolder) { Start-Sleep -Seconds 2 }
}
$RemainingFiles = @(Get-ChildItem -LiteralPath $InstallFolder -Recurse -Force -File -ErrorAction SilentlyContinue)
If((Test-Path -LiteralPath $InstallFolder) -and ($RemainingFiles.Count -eq 0))
{
	# Only empty folders are left (still in use by another program): nothing of SelfX remains.
	Write-Output "The empty folder '$InstallFolder' is still in use and remains until the next sign-out or restart."
}

# A service that another program still has open (e.g. the Services console) is only marked for deletion. It
# can no longer start (its file is gone) and disappears when that program closes it, so this is no failure.
$ServiceLeft = $false
If(Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)
{
	& sc.exe delete $ServiceName | Out-Null
	If($LASTEXITCODE -eq 1072) { Write-Output "Service '$ServiceName' is marked for deletion and disappears when the last program closes it." }
	ElseIf(@(0, 1060) -notcontains $LASTEXITCODE) { $ServiceLeft = $true; Write-Output "Service '$ServiceName' could not be deleted (sc.exe exit code $LASTEXITCODE)." }
}

$ExitCode = 0
If(($RemainingFiles.Count -gt 0) -or $ServiceLeft)
{
	If($RemainingFiles.Count -gt 0) { Write-Output "Files in use: $(($RemainingFiles | Select-Object -ExpandProperty FullName) -join ', ')" }
	Write-Output 'SelfX could not be removed completely.'
	$ExitCode = 1
}
Else { Write-Output 'SelfX removed.' }
If($Transcript) { Stop-Transcript | Out-Null }
# What is left in ProgramData\SelfX belongs to SYSTEM and administrators only (the user folders were deleted above); the
# link-safe delete by path is enough for it. If the helper could not delete the user data, nothing is deleted by path.
If($RemoveLogs)
{
	If($DataFoldersSafe) { Remove-SelfXTree -Path $DataFolder }
	Else { Write-Output "ProgramData\SelfX was not deleted because the user data could not be removed safely." }
}
exit $ExitCode
