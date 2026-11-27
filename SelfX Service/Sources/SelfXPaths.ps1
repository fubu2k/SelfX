<#
.SYNOPSIS
    Resolves the paths of the configuration files, images and scripts of SelfX (code folder App, configuration folder Config).

.DESCRIPTION
    Dot-sourced by Self_X.ps1, SelfX_Tray.ps1, HealthStatus.ps1, SelfXLog.ps1 and SelfX_Device_CollectLogs.ps1. Windows PowerShell 5.1
    and PowerShell 7. Pure path functions: nothing is changed on the device.

    Layout of an installation (%ProgramFiles%\SelfX):
      App\     the code: programs, libraries, scripts of the project, bundled language files, default images, SelfX.Code.json
      Config\  the configuration: Tool_Config.xml, Issues_List.xml, Health_Config.xml, Ticket_Config.xml, Network_Test_Config.xml,
               Branding\, own scripts (Scripts_to_run, HealthChecks), own language files (Languages) and text overrides (Texts) of the
               company, SelfX.Config.json
    The configuration folder is the folder Config next to the code folder when the code folder is named App. Otherwise (the folder
    Sources of the repository, a flat test folder) the configuration is in the code folder itself. No environment variable, registry
    value or other input that a user can set takes part in this decision: both folders are protected by Install.ps1 (users can only
    read and execute).

    Rules:
      - Get-SelfXConfigPath accepts only relative names that are allowed in SelfX.Config.json (same placement rule as Install.ps1,
        tools\SelfXPackage.Common.ps1 and the service); a rooted path, a UNC path, a drive, '.', '..' or any other character
        throws. The result always lies below the configuration folder.
      - Get-SelfXImagePath: a value that starts with Branding\ is a configuration file (Config\Branding); another relative value is
        a default image of the code (App); a rooted value is used as it is (as before; Tool_Config.xml can only be changed by
        administrators). A relative value that leaves its folder gives $null.
      - Resolve-SelfXScriptPath: a script of the project (App\Scripts_to_run or App\HealthChecks) wins. An own script of the
        company (Config\Scripts_to_run or Config\HealthChecks) is used only when it is listed in Config\SelfX.Config.json with the
        SHA256 that the file has now, and when neither the file nor its folder is a link. This check does not depend on
        Service_FileCheck (Audit), so an unlisted or changed own script is never started.

.NOTES
    Name    : SelfXPaths.ps1
    Package : SelfX Service
    Context : User and System, dot-sourced
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version: one resolver for the folders App and Config
    3.1.0    2026-11-27  fubu2k               Text overrides: Texts/<culture>.xml is a configuration file; Get-SelfXTextOverrideFolder
#>

# The settings files of SelfX (same list as Install.ps1, tools\SelfXPackage.Common.ps1 and SelfXService.cs).
$Script:SelfXConfigFileNames = @('Health_Config.xml', 'Issues_List.xml', 'Network_Test_Config.xml', 'Ticket_Config.xml', 'Tool_Config.xml')

function Get-SelfXCodeRoot {
	# The code folder: the folder of this file (App on a device, Sources in the repository), or the given folder.
	param([string]$CodeRoot = '')
	If([string]::IsNullOrWhiteSpace($CodeRoot)) { $CodeRoot = $Script:SelfXPathsRoot }
	If([string]::IsNullOrWhiteSpace($CodeRoot)) { throw 'The code folder of SelfX is not known.' }
	Return [IO.Path]::GetFullPath($CodeRoot).TrimEnd('\')
}

function Get-SelfXConfigRoot {
	# The configuration folder: <parent>\Config when the code folder is named App, otherwise the code folder itself.
	param([string]$CodeRoot = '')
	$Code = Get-SelfXCodeRoot -CodeRoot $CodeRoot
	If([IO.Path]::GetFileName($Code) -ieq 'App')
	{
		$Parent = [IO.Path]::GetDirectoryName($Code)
		If([string]::IsNullOrEmpty($Parent)) { throw 'The folder App has no parent folder.' }
		Return (Join-Path $Parent 'Config')
	}
	Return $Code
}

function Test-SelfXSplitLayout {
	# True when code and configuration are in two folders (App and Config).
	param([string]$CodeRoot = '')
	Return ((Get-SelfXConfigRoot -CodeRoot $CodeRoot) -ne (Get-SelfXCodeRoot -CodeRoot $CodeRoot))
}

function Test-SelfXConfigFileName {
	# May this relative name be used below the configuration folder? Same rule as the configuration list (SelfX.Config.json):
	# a settings file, a file below Branding, an own script in Scripts_to_run or HealthChecks, an own language file or a text override.
	param([string]$Name)
	If([string]::IsNullOrEmpty($Name)) { return $false }
	$Relative = $Name.Replace('\', '/')
	If($Relative -notmatch '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*\z' -or $Relative -match '(^|/)\.\.?(/|$)') { return $false }
	If($Script:SelfXConfigFileNames -contains $Relative) { return $true }
	If($Relative -match '^Branding/.+') { return $true }
	If($Relative -match '^(Scripts_to_run|HealthChecks)/[A-Za-z0-9._-]+\.ps1\z') { return $true }
	If($Relative -match '^Languages/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml\z') { return $true }
	If($Relative -match '^Texts/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml\z') { return $true }
	Return $false
}

function Get-SelfXConfigPath {
	# Full path of a configuration file, for example Get-SelfXConfigPath Tool_Config.xml or Get-SelfXConfigPath Branding\logo.png.
	# Throws for a name that is not allowed (fail closed); the file need not exist.
	param(
		[Parameter(Mandatory = $true)][string]$Name,
		[string]$CodeRoot = ''
	)
	If(-not (Test-SelfXConfigFileName -Name $Name)) { throw "'$Name' is not a configuration file of SelfX." }
	$Root = Get-SelfXConfigRoot -CodeRoot $CodeRoot
	$Full = [IO.Path]::GetFullPath((Join-Path $Root $Name.Replace('/', '\')))
	If(-not $Full.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "'$Name' is outside the configuration folder." }
	Return $Full
}

function Get-SelfXImagePath {
	# Path of an image named in Tool_Config.xml (Brand_Logo, Brand_Icon, About_Logo). Branding\... = configuration folder,
	# another relative value = code folder (default images), a rooted value is used as it is. $null for an empty value or a
	# relative value that is not allowed.
	param(
		[string]$Value,
		[string]$CodeRoot = ''
	)
	$Text = "$Value".Trim()
	If($Text -eq '') { return $null }
	If([IO.Path]::IsPathRooted($Text)) { return $Text }
	If($Text -match '^Branding[\\/]')
	{
		Try { return (Get-SelfXConfigPath -Name $Text -CodeRoot $CodeRoot) } Catch { return $null }
	}
	$Relative = $Text.Replace('\', '/')
	If($Relative -notmatch '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*\z' -or $Relative -match '(^|/)\.\.?(/|$)') { return $null }
	$Root = Get-SelfXCodeRoot -CodeRoot $CodeRoot
	$Full = [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/', '\')))
	If(-not $Full.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $null }
	Return $Full
}

function Get-SelfXLanguageFolders {
	# Folders with language files: the bundled files of the code first, then own files of the company (only in the layout App/Config).
	param([string]$CodeRoot = '')
	$Folders = @(Join-Path (Get-SelfXCodeRoot -CodeRoot $CodeRoot) 'Languages')
	If(Test-SelfXSplitLayout -CodeRoot $CodeRoot) { $Folders += (Join-Path (Get-SelfXConfigRoot -CodeRoot $CodeRoot) 'Languages') }
	Return ,([string[]]$Folders)
}

function Get-SelfXTextOverrideFolder {
	# Folder with the optional text overrides of the company (Texts\<culture>.xml): Config\Texts. The folder need not exist. The files
	# are read by Initialize-SelfXLanguage (Localization.ps1), which accepts only culture names as file names.
	param([string]$CodeRoot = '')
	Return (Join-Path (Get-SelfXConfigRoot -CodeRoot $CodeRoot) 'Texts')
}

function Test-SelfXConfigListed {
	# True when the configuration file is listed in SelfX.Config.json of the configuration folder with the SHA256 it has now. False
	# for a missing, broken or unknown list, a missing entry, a different hash and a link at the file or at a folder below the
	# configuration folder (fail closed).
	param(
		[Parameter(Mandatory = $true)][string]$Name,
		[string]$CodeRoot = ''
	)
	Try
	{
		$Path = Get-SelfXConfigPath -Name $Name -CodeRoot $CodeRoot
		$Root = Get-SelfXConfigRoot -CodeRoot $CodeRoot
		$ListPath = Join-Path $Root 'SelfX.Config.json'
		If(-not (Test-Path -LiteralPath $ListPath -PathType Leaf) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
		$Item = Get-Item -LiteralPath $Path -Force
		While($Item -and ($Item.FullName.TrimEnd('\').Length -ge $Root.Length))
		{
			If($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
			$Item = $(If($Item -is [IO.FileInfo]) { $Item.Directory } Else { $Item.Parent })
		}
		If((Get-Item -LiteralPath $ListPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
		$List = Get-Content -LiteralPath $ListPath -Raw | ConvertFrom-Json
		If(-not $List -or "$($List.ManifestVersion)" -ne '1' -or -not $List.Files) { return $false }
		$Key = $Name.Replace('\', '/')
		$Expected = $null
		ForEach($Property in @($List.Files.PSObject.Properties)) { If($Property.Name -ceq $Key) { $Expected = "$($Property.Value)" } }
		If($Expected -notmatch '^[0-9A-Fa-f]{64}\z') { return $false }
		Return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Expected.ToUpperInvariant())
	}
	Catch { return $false }
}

function Resolve-SelfXScriptPath {
	# Full path of a script named in the catalog or in Health_Config.xml, or $null when it may not be started.
	# Folder is Scripts_to_run or HealthChecks; FileName is a plain file name. The script of the project (code folder) wins; an own
	# script of the company (configuration folder) only counts when Test-SelfXConfigListed accepts it.
	param(
		[Parameter(Mandatory = $true)][ValidateSet('Scripts_to_run', 'HealthChecks')][string]$Folder,
		[Parameter(Mandatory = $true)][string]$FileName,
		[string]$CodeRoot = ''
	)
	If($FileName -notmatch '^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,90}\.ps1\z' -or $FileName.Contains('..')) { return $null }
	$Code = Get-SelfXCodeRoot -CodeRoot $CodeRoot
	$CodePath = Join-Path (Join-Path $Code $Folder) $FileName
	If(Test-Path -LiteralPath $CodePath -PathType Leaf) { return $CodePath }
	If(-not (Test-SelfXSplitLayout -CodeRoot $CodeRoot)) { return $null }
	$Name = "$Folder/$FileName"
	If(Test-SelfXConfigListed -Name $Name -CodeRoot $CodeRoot) { return (Get-SelfXConfigPath -Name $Name -CodeRoot $CodeRoot) }
	Return $null
}

$Script:SelfXPathsRoot = $PSScriptRoot
