<#
.SYNOPSIS
    Tests the path resolver of SelfX (Sources\SelfXPaths.ps1): folders App and Config, configuration files, images, own scripts
    and own language files.

.DESCRIPTION
    Dot-sources SelfXPaths.ps1, Localization.ps1 and HealthStatus.ps1 (functions only; the health checks themselves are not run, the
    start of a health script is replaced by a mock) and works in a temporary folder with the layout of an installation
    (<root>\App and <root>\Config). Nothing is installed, no process is started.
    Checked:
      - the configuration folder is Config next to App, and the code folder itself in the flat layout of the repository;
      - Get-SelfXConfigPath accepts only the names that SelfX.Config.json may hold and refuses path traversal, rooted, UNC, drive
        and stream paths, '.' and '..' segments, sub folders of Scripts_to_run and files of the project (fail closed); its rule is
        the placement rule of the package tools;
      - Get-SelfXImagePath: Branding\... in Config, default images in App, rooted values unchanged, traversal gives nothing;
      - Resolve-SelfXScriptPath: the script of the project wins; an own script in Config only with its entry and its current SHA256
        in SelfX.Config.json; changed, unlisted, linked and badly named scripts, a missing or broken list are refused; the flat
        layout never looks into another folder;
      - own language files in Config\Languages are offered, but cannot replace a bundled language;
      - own health scripts in Config\HealthChecks run only when they are listed (HealthStatus.ps1);
      - no script of the window, the status icon, the health collector or the log helper builds a path of a settings file itself.
    PowerShell 7 (Test-Compat51.ps1 checks that SelfXPaths.ps1 also parses in Windows PowerShell 5.1):
    pwsh.exe -NoProfile -File .\Test-ConfigPath.ps1

.NOTES
    Name    : Test-ConfigPath.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version.
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
	$script:checks++
	try { & $Action | Out-Null; $script:errors.Add("$Message (no error)") }
	catch { if ($_.Exception.Message -notmatch $Pattern) { $script:errors.Add("$Message (wrong error: $($_.Exception.Message))") } }
}

$sources = Join-Path $PSScriptRoot 'Sources'
. (Join-Path $sources 'SelfXPaths.ps1')
. (Join-Path $sources 'Localization.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\SelfXPackage.Common.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXConfigPathTest_' + [guid]::NewGuid().ToString('N'))
$app = Join-Path $root 'App'
$config = Join-Path $root 'Config'
function Write-ConfigList {
	# SelfX.Config.json of the configuration folder from the files that are there now.
	$files = [ordered]@{}
	foreach ($file in @(Get-ChildItem -LiteralPath $config -Recurse -File | Where-Object { $_.Name -ne 'SelfX.Config.json' })) {
		$files[$file.FullName.Substring($config.Length + 1).Replace('\', '/')] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
	}
	[IO.File]::WriteAllText((Join-Path $config 'SelfX.Config.json'), ([ordered]@{ ManifestVersion = 1; ConfigRevision = '2026-11-27T10:00:00Z'; Files = $files } | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
}

try {
	foreach ($folder in 'App\Scripts_to_run', 'App\HealthChecks', 'App\Languages', 'Config\Scripts_to_run', 'Config\HealthChecks', 'Config\Branding', 'Config\Languages') {
		New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force | Out-Null
	}
	Set-Content -LiteralPath (Join-Path $app 'Scripts_to_run\SelfX_Project.ps1') -Value 'exit 0'
	Set-Content -LiteralPath (Join-Path $app 'HealthChecks\Check-Compliance.ps1') -Value 'exit 0'
	Set-Content -LiteralPath (Join-Path $config 'Tool_Config.xml') -Value '<GUI_Config />'
	Set-Content -LiteralPath (Join-Path $config 'Branding\logo.png') -Value 'logo'
	Set-Content -LiteralPath (Join-Path $config 'Scripts_to_run\Own_Action.ps1') -Value 'exit 0'
	Set-Content -LiteralPath (Join-Path $config 'HealthChecks\Own-Check.ps1') -Value 'exit 0'
	Write-ConfigList

	# --- The configuration folder ---
	Assert-Equal (Get-SelfXConfigRoot -CodeRoot $app) $config 'root: Config next to App'
	Assert-Equal (Get-SelfXConfigRoot -CodeRoot ($app.ToLowerInvariant() + '\')) ([IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $app.ToLowerInvariant()) 'Config'))) 'root: the name App is compared without case, a trailing \ is ignored'
	Assert-Equal (Get-SelfXConfigRoot -CodeRoot $sources) ([IO.Path]::GetFullPath($sources)) 'root: the flat layout of the repository uses the code folder'
	Assert-Equal (Get-SelfXConfigRoot -CodeRoot (Join-Path $app 'Scripts_to_run')) ([IO.Path]::GetFullPath((Join-Path $app 'Scripts_to_run'))) 'root: only a folder named App has a folder Config next to it'
	Assert-Equal (Test-SelfXSplitLayout -CodeRoot $app) $true 'root: App/Config is the split layout'
	Assert-Equal (Test-SelfXSplitLayout -CodeRoot $sources) $false 'root: Sources is the flat layout'
	Assert-Equal (Get-SelfXCodeRoot) ([IO.Path]::GetFullPath($sources)) 'root: without a parameter the folder of SelfXPaths.ps1 is the code folder'
	$env:SELFX_CONFIG = 'C:\Evil'
	Assert-Equal (Get-SelfXConfigRoot -CodeRoot $app) $config 'root: an environment variable does not change the folder'
	Remove-Item Env:\SELFX_CONFIG

	# --- Configuration files: allowed names only, always below Config ---
	foreach ($name in 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'Ticket_Config.xml', 'Network_Test_Config.xml', 'Branding\logo.png', 'Branding/a/b.png', 'Scripts_to_run\Own_Action.ps1', 'HealthChecks\Own-Check.ps1', 'Languages\it.xml', 'Languages\de-CH.xml') {
		Assert-Equal (Get-SelfXConfigPath -Name $name -CodeRoot $app) ([IO.Path]::GetFullPath((Join-Path $config $name.Replace('/', '\')))) "config path: $name is in Config"
	}
	Assert-Equal (Get-SelfXConfigPath -Name 'Tool_Config.xml' -CodeRoot $sources) ([IO.Path]::GetFullPath((Join-Path $sources 'Tool_Config.xml'))) 'config path: flat layout'
	$badNames = @('..\Tool_Config.xml', '..\..\Windows\win.ini', 'Branding\..\..\App\Self_X.ps1', 'Branding\..', 'Branding\.\x.png', '.\Tool_Config.xml',
		'C:\Windows\win.ini', 'C:Tool_Config.xml', '\\server\share\Tool_Config.xml', '\Tool_Config.xml', '/Tool_Config.xml', 'Tool_Config.xml:stream',
		'Self_X.ps1', 'SelfXService.exe', 'Uninstall.ps1', 'Scripts_to_run\sub\Own.ps1', 'Scripts_to_run\Own.exe', 'Languages\x.ps1', 'Languages\toolong-language-name.xml',
		'tool_config.xml ', 'Branding\', 'Branding', '', ' ', 'Tool_Config.xml|x', 'Branding\<x>.png', "Branding\x`n.png", 'Branding\*.png')
	foreach ($bad in $badNames) {
		Assert-Throws { Get-SelfXConfigPath -Name $bad -CodeRoot $app } 'is not a configuration file|outside the configuration folder|Cannot bind|empty' "config path: '$($bad -replace '\s', '_')' is refused"
	}
	# The rule equals the placement rule of the configuration list of the package tools (for names with '/').
	foreach ($name in @($script:SelfXCodeFileNames) + $script:SelfXConfigFileNames + @('Branding/x.png', 'Branding/', 'Scripts_to_run/Own.ps1', 'Scripts_to_run/Own.exe', 'Scripts_to_run/a/b.ps1', 'HealthChecks/Own-Check.ps1', 'Languages/it.xml', 'Languages/it-CH.xml', 'Languages/x.ps1', 'WinRT/A.dll', 'Evil.ps1', '../x', 'a/../b')) {
		Assert-Equal (Test-SelfXConfigFileName -Name $name) (Test-SelfXListPlacement -Name $name -List 'Config') "config path: '$name' follows the placement rule of SelfX.Config.json"
	}

	# --- Images named in Tool_Config.xml ---
	Assert-Equal (Get-SelfXImagePath -Value 'Branding\logo.png' -CodeRoot $app) ([IO.Path]::GetFullPath((Join-Path $config 'Branding\logo.png'))) 'image: Branding\... is in Config'
	Assert-Equal (Get-SelfXImagePath -Value 'Branding/logo.png' -CodeRoot $app) ([IO.Path]::GetFullPath((Join-Path $config 'Branding\logo.png'))) 'image: Branding/... is in Config'
	Assert-Equal (Get-SelfXImagePath -Value ' Repair.ico ' -CodeRoot $app) ([IO.Path]::GetFullPath((Join-Path $app 'Repair.ico'))) 'image: a default image is in App'
	Assert-Equal (Get-SelfXImagePath -Value 'C:\Images\logo.png' -CodeRoot $app) 'C:\Images\logo.png' 'image: a rooted value is used as it is (Tool_Config.xml is protected)'
	Assert-Equal (Get-SelfXImagePath -Value 'Branding\logo.png' -CodeRoot $sources) ([IO.Path]::GetFullPath((Join-Path $sources 'Branding\logo.png'))) 'image: flat layout'
	foreach ($bad in '', ' ', '..\logo.png', 'Branding\..\..\logo.png', 'Sub\..\..\logo.png', '.\logo.png', 'Branding\', 'logo.png:x') {
		Assert-Equal ($null -eq (Get-SelfXImagePath -Value $bad -CodeRoot $app)) $true "image: '$bad' gives nothing"
	}

	# --- Scripts: project first, own scripts only when listed ---
	Assert-Equal (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName 'SelfX_Project.ps1' -CodeRoot $app) (Join-Path $app 'Scripts_to_run\SelfX_Project.ps1') 'script: a script of the project is taken from App'
	Assert-Equal (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName 'Own_Action.ps1' -CodeRoot $app) ([IO.Path]::GetFullPath((Join-Path $config 'Scripts_to_run\Own_Action.ps1'))) 'script: a listed own script is taken from Config'
	Assert-Equal (Resolve-SelfXScriptPath -Folder 'HealthChecks' -FileName 'Own-Check.ps1' -CodeRoot $app) ([IO.Path]::GetFullPath((Join-Path $config 'HealthChecks\Own-Check.ps1'))) 'script: a listed own health script is taken from Config'
	Copy-Item -LiteralPath (Join-Path $config 'Scripts_to_run\Own_Action.ps1') -Destination (Join-Path $config 'Scripts_to_run\SelfX_Project.ps1')
	Write-ConfigList
	Assert-Equal (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName 'SelfX_Project.ps1' -CodeRoot $app) (Join-Path $app 'Scripts_to_run\SelfX_Project.ps1') 'script: an own script cannot replace a script of the project'
	Remove-Item -LiteralPath (Join-Path $config 'Scripts_to_run\SelfX_Project.ps1')
	Write-ConfigList
	Add-Content -LiteralPath (Join-Path $config 'Scripts_to_run\Own_Action.ps1') -Value 'calc.exe'
	Assert-Equal ($null -eq (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName 'Own_Action.ps1' -CodeRoot $app)) $true 'script: a changed own script is refused (SHA256)'
	Write-ConfigList
	Set-Content -LiteralPath (Join-Path $config 'Scripts_to_run\Unlisted.ps1') -Value 'calc.exe'
	Assert-Equal ($null -eq (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName 'Unlisted.ps1' -CodeRoot $app)) $true 'script: an own script without an entry is refused'
	Assert-Equal (Test-SelfXConfigListed -Name 'Scripts_to_run\Unlisted.ps1' -CodeRoot $app) $false 'listed: an unlisted file is not listed'
	Assert-Equal (Test-SelfXConfigListed -Name 'Scripts_to_run/Own_Action.ps1' -CodeRoot $app) $true 'listed: a listed file with its SHA256 is listed'
	Assert-Equal (Test-SelfXConfigListed -Name 'scripts_to_run/own_action.ps1' -CodeRoot $app) $false 'listed: the name in the list is compared exactly'
	Remove-Item -LiteralPath (Join-Path $config 'Scripts_to_run\Unlisted.ps1')
	Assert-Throws { Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName '' -CodeRoot $app } 'empty string' 'script: an empty name is refused'
	foreach ($bad in '..\Own_Action.ps1', '..\..\App\Scripts_to_run\SelfX_Project.ps1', 'Scripts_to_run\Own_Action.ps1', 'C:\Windows\x.ps1', 'Own_Action.ps1:x', 'Own_Action', 'Own Action.ps1', ' ', '.ps1x') {
		Assert-Equal ($null -eq (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName $bad -CodeRoot $app)) $true "script: the name '$bad' is refused"
	}
	Assert-Throws { Resolve-SelfXScriptPath -Folder 'Branding' -FileName 'Own_Action.ps1' -CodeRoot $app } 'Cannot validate|does not belong to the set' 'script: only Scripts_to_run and HealthChecks'
	Assert-Equal ($null -eq (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName 'Own_Action.ps1' -CodeRoot (Join-Path $root 'Flat'))) $true 'script: the flat layout never looks into another folder'
	# The list: missing, broken, unknown format, a wrong hash text.
	$listPath = Join-Path $config 'SelfX.Config.json'
	$listText = [IO.File]::ReadAllText($listPath)
	foreach ($case in @(@('missing', $null), @('broken', '{ broken'), @('format 2', '{"ManifestVersion":2,"Files":{"Scripts_to_run/Own_Action.ps1":"00"}}'), @('no hash', '{"ManifestVersion":1,"Files":{"Scripts_to_run/Own_Action.ps1":"x"}}'))) {
		if ($null -eq $case[1]) { Remove-Item -LiteralPath $listPath } else { [IO.File]::WriteAllText($listPath, $case[1]) }
		Assert-Equal ($null -eq (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName 'Own_Action.ps1' -CodeRoot $app)) $true "script: a list that is $($case[0]) starts no own script"
	}
	[IO.File]::WriteAllText($listPath, $listText)
	Assert-Equal (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName 'Own_Action.ps1' -CodeRoot $app) ([IO.Path]::GetFullPath((Join-Path $config 'Scripts_to_run\Own_Action.ps1'))) 'script: accepted again with the list restored'
	# A junction instead of Config\Scripts_to_run: the script behind it is not started.
	$elsewhere = Join-Path $root 'Elsewhere'
	Move-Item -LiteralPath (Join-Path $config 'Scripts_to_run') -Destination $elsewhere
	New-Item -ItemType Junction -Path (Join-Path $config 'Scripts_to_run') -Target $elsewhere | Out-Null
	Assert-Equal ($null -eq (Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName 'Own_Action.ps1' -CodeRoot $app)) $true 'script: an own script behind a junction is refused'
	(Get-Item -LiteralPath (Join-Path $config 'Scripts_to_run')).Delete()
	Move-Item -LiteralPath $elsewhere -Destination (Join-Path $config 'Scripts_to_run')

	# --- Own health scripts (HealthStatus.ps1): only listed scripts run; the start of the script is a mock ---
	. (Join-Path $sources 'HealthStatus.ps1')
	$script:started = New-Object System.Collections.Generic.List[string]
	function Invoke-SelfXHealthScript { param([string]$Path, [int]$TimeoutSeconds) $script:started.Add($Path); return [pscustomobject]@{ ExitCode = 0; Output = 'fine' } }
	[xml]$check = '<Check Name="Own check" Script="Own-Check.ps1"/>'
	$result = Get-SelfXCustomHealth -Check $check.DocumentElement -Root $app
	Assert-Equal $result.Status 'OK' 'health: a listed own health script runs'
	Assert-Equal ($script:started -contains ([IO.Path]::GetFullPath((Join-Path $config 'HealthChecks\Own-Check.ps1')))) $true 'health: the own health script is started from Config'
	[xml]$project = '<Check Name="Compliance" Script="Check-Compliance.ps1"/>'
	Assert-Equal (Get-SelfXCustomHealth -Check $project.DocumentElement -Root $app).Status 'OK' 'health: the health script of the project runs from App'
	Set-Content -LiteralPath (Join-Path $config 'HealthChecks\Unlisted-Check.ps1') -Value 'exit 0'
	$script:started.Clear()
	[xml]$unlisted = '<Check Name="Unlisted" Script="Unlisted-Check.ps1"/>'
	$result = Get-SelfXCustomHealth -Check $unlisted.DocumentElement -Root $app
	Assert-Equal "$($result.Status)/$($script:started.Count)" 'Error/0' 'health: an unlisted own health script does not run'
	Assert-Equal ($result.Detail -match 'not listed in SelfX.Config.json') $true 'health: the reason names the list'
	Add-Content -LiteralPath (Join-Path $config 'HealthChecks\Own-Check.ps1') -Value 'calc.exe'
	$result = Get-SelfXCustomHealth -Check $check.DocumentElement -Root $app
	Assert-Equal "$($result.Status)/$($script:started.Count)" 'Error/0' 'health: a changed own health script does not run'

	# --- Language files: own files are offered, bundled ones win ---
	foreach ($culture in 'de', 'en') { Copy-Item -LiteralPath (Join-Path $sources "Languages\$culture.xml") -Destination (Join-Path $app 'Languages') }
	[IO.File]::WriteAllText((Join-Path $config 'Languages\eo.xml'), '<?xml version="1.0" encoding="utf-8"?><SelfX_Language Culture="eo" NativeName="Esperanto"><Texts /></SelfX_Language>')
	[IO.File]::WriteAllText((Join-Path $config 'Languages\de.xml'), '<?xml version="1.0" encoding="utf-8"?><SelfX_Language Culture="de" NativeName="Replaced"><Texts /></SelfX_Language>')
	$folders = Get-SelfXLanguageFolders -CodeRoot $app
	Assert-Equal (@($folders) -join '|') ((Join-Path $app 'Languages') + '|' + (Join-Path $config 'Languages')) 'languages: App first, then Config'
	Assert-Equal @(Get-SelfXLanguageFolders -CodeRoot $sources).Count 1 'languages: one folder in the flat layout'
	$list = @(Get-SelfXLanguageList -LanguageFolder $folders)
	Assert-Equal (($list | ForEach-Object { $_.Culture }) -contains 'eo') $true 'languages: an own language is offered'
	Assert-Equal (@($list | Where-Object { $_.Culture -eq 'de' }).Count) 1 'languages: a culture is offered once'
	Assert-Equal (@($list | Where-Object { $_.Culture -eq 'de' })[0].Name -ne 'Replaced') $true 'languages: an own file cannot replace a bundled language'
	Assert-Equal (Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de').File (Join-Path $app 'Languages\de.xml') 'languages: the bundled file is loaded for a bundled culture'
	Assert-Equal (Initialize-SelfXLanguage -LanguageFolder $folders -Language 'eo').File (Join-Path $config 'Languages\eo.xml') 'languages: the own file is loaded for an own culture'
	Assert-Equal (Resolve-SelfXLanguageSetting -ConfigLanguage 'Auto' -UserLanguage 'eo' -LanguageFolder $folders) 'eo' 'languages: the user may choose an own language'
	Assert-Equal (Resolve-SelfXLanguageSetting -ConfigLanguage 'Auto' -UserLanguage '..\eo' -LanguageFolder $folders) 'Auto' 'languages: a path in the user value is ignored'
	Assert-Equal (Get-SelfXLanguageFileCulture -LanguageFolder $folders -Language 'eo') 'eo' 'languages: the culture of an own file is found'
	Assert-Equal (Get-SelfXLanguageFileCulture -LanguageFolder @((Join-Path $root 'Missing')) -Language 'fr') 'de' 'languages: without files German is the base language'

	# --- No script builds the path of a settings file itself ---
	$direct = '(Join-Path\s+\$[A-Za-z_:]+\s+''(Tool_Config|Issues_List|Health_Config|Ticket_Config|Network_Test_Config)\.xml'')|("\$[A-Za-z_:]+\\(Tool_Config|Issues_List|Health_Config|Ticket_Config|Network_Test_Config)\.xml")'
	foreach ($file in 'Self_X.ps1', 'SelfX_Tray.ps1', 'HealthStatus.ps1', 'SelfXLog.ps1', 'Branding.ps1', 'Localization.ps1', 'Scripts_to_run\SelfX_Device_CollectLogs.ps1') {
		$text = [IO.File]::ReadAllText((Join-Path $sources $file))
		Assert-Equal ([regex]::Matches($text, $direct).Count) 0 "static: $file resolves settings files only through SelfXPaths.ps1"
	}
	$gui = [IO.File]::ReadAllText((Join-Path $sources 'Self_X.ps1'))
	Assert-Equal $gui.Contains("Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName `$Script_Name -CodeRoot `$Current_Folder") $true 'static: user actions are resolved by Resolve-SelfXScriptPath'
	Assert-Equal $gui.Contains('. "$Current_Folder\SelfXPaths.ps1"') $true 'static: the window loads SelfXPaths.ps1'
	$tray = [IO.File]::ReadAllText((Join-Path $sources 'SelfX_Tray.ps1'))
	Assert-Equal ($tray.IndexOf("SelfXPaths.ps1") -lt $tray.IndexOf('[System.Xml.XmlReader]::Create($Global:Tray_Config_File')) $true 'static: the status icon loads SelfXPaths.ps1 before it reads Tool_Config.xml'
}
finally {
	Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | ForEach-Object { try { [IO.Directory]::Delete($_.FullName) } catch {} }
	Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
