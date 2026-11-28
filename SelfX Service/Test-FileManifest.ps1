<#
.SYNOPSIS
    Tests SelfX.Code.json and SelfX.Config.json: the two hash lists of all installed files.

.DESCRIPTION
    Loads tools\SelfXPackage.Common.ps1 (functions only) and takes Test-SelfXFileManifest, Test-SelfXInstalledFiles,
    Read-SelfXFileList and Test-SelfXListPlacement out of Install.ps1 (the script itself is never run) and runs them against
    a copy of the real Sources folder in a temporary folder, sorted into the package layout App\ and Config\
    (ConvertTo-SelfXPackageLayout) as tools\New-SelfXIntuneWin.ps1 does.
    Checked: every file of the repository has a class and the name list of the project equals the repository; the generator
    lists every file in exactly one list and the check accepts the result; a changed logo of the company changes only
    SelfX.Config.json (SelfX.Code.json stays byte-identical); a changed file, an extra file (also in Scripts_to_run), a missing
    file, a changed Uninstall.ps1, a file in both lists, a settings file in the code list, a program in the configuration list,
    a broken JSON, an unknown format and names with a path traversal are refused; a package without the lists is reported as
    not checked. The version is a property of the code: the test checks that a new version changes no configuration file, that a
    changed configuration changes neither the version nor a code file, that an old Tool_Version element is ignored, that Version.txt,
    ConfigRevision and the version in the package are validated (fail closed), and that no script, tool or workflow reads Tool_Version.
    Nothing is installed.
    Windows PowerShell 5.1 or PowerShell 7: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-FileManifest.ps1

.NOTES
    Name    : Test-FileManifest.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.1    2026-11-23  fubu2k               Initial version.
    2.8.19   2026-11-23  fubu2k               Also SelfXService.exe and SelfX.exe, the check of the installed folder after copying
                                              and the .exe entry of the service file check.
    2.9.0    2026-11-27  fubu2k               Two lists (SelfX.Code.json, SelfX.Config.json) by file class; logo test, placement and
                                              class tests, negative tests for a file in both lists, in none and in the wrong list.
    2.9.1    2026-11-27  fubu2k               Version in the code list: version and configuration are independent, Version.txt, ConfigRevision, Install.ps1 reads the
                                              version from SelfX.Code.json, no reader of Tool_Version is left.
    3.1.0    2026-11-27  fubu2k               Text overrides: class and placement of Texts/<culture>.xml, same pattern in the service.
    3.1.0    2026-11-27  fubu2k               Layout App\ and Config\ in the package and on the device: sorting by file class, lists in App and Config,
                                              a package in the old layout, a configuration file in App and a code file in Config are refused, the
                                              installed folder may hold nothing but App and Config (left-over files and non-empty folders refused,
                                              empty folders allowed), unlisted files in Config are refused, the icon rule of Install.ps1 equals
                                              Get-SelfXImagePath.
    3.1.0    2026-11-28  fubu2k               Library Disturb/SelfXDisturb.dll (Bin\Disturb): code list, check, extra, changed and missing file.
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
	$script:checks++
	try { & $Action | Out-Null; $script:errors.Add("$Message (no error)") }
	catch { if ($_.Exception.Message -notmatch $Pattern) { $script:errors.Add("$Message (wrong error: $($_.Exception.Message))") } }
}

# Load only the two functions, never the rest of the scripts.
function Get-FunctionText($Path, $Name) {
	$parseErrors = $null
	$ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
	Assert-Equal @($parseErrors).Count 0 "$([IO.Path]::GetFileName($Path)) parses"
	$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }.GetNewClosure(), $true)
	Assert-Equal ($null -ne $definition) $true "$([IO.Path]::GetFileName($Path)) defines $Name"
	if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
	return $definition.Extent.Text
}
# Dot-sourced here (script scope), not inside a function, so the functions stay visible.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\SelfXPackage.Common.ps1')
# The placement rule of the generator keeps its own name; Install.ps1 has a copy of the same rule under the same name.
${function:Common_Test-SelfXListPlacement} = ${function:Test-SelfXListPlacement}
foreach ($name in 'Test-SelfXListPlacement', 'Read-SelfXFileList', 'Test-SelfXFileManifest', 'Get-SelfXPackageToolVersion', 'Test-SelfXInstalledFiles', 'Resolve-SelfXInstalledImage') {
	. ([scriptblock]::Create((Get-FunctionText (Join-Path $PSScriptRoot 'Install.ps1') $name)))
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXFileManifestTest_' + [guid]::NewGuid().ToString('N'))
$pristine = Join-Path $root 'pristine'
$package = Join-Path $root 'package'
function Reset-Package {
	if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Recurse -Force }
	Copy-Item -LiteralPath $pristine -Destination $package -Recurse
}
# Path of a list in a package or an installed folder: App\SelfX.Code.json or Config\SelfX.Config.json.
function Get-ListPath([string]$Root, [string]$ListName) {
	if ($ListName -eq 'SelfX.Code.json') { return (Join-Path $Root 'App\SelfX.Code.json') }
	return (Join-Path $Root 'Config\SelfX.Config.json')
}
# Writes a list file of the package (or of the installed folder) from a name -> hash table.
function Set-List([string]$Path, $Files, $Version = 1) {
	Set-Content -LiteralPath $Path -Value ([ordered]@{ ManifestVersion = $Version; Files = $Files } | ConvertTo-Json)
}
# ConfigRevision as written in the file (PowerShell 7 turns an ISO 8601 string into a DateTime in ConvertFrom-Json, so the text is read).
function Get-ConfigRevisionText([string]$Path) {
	return [regex]::Match([IO.File]::ReadAllText($Path), '"ConfigRevision"\s*:\s*"([^"]*)"').Groups[1].Value
}
function Get-ListFiles([string]$Path) {
	$list = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
	$files = [ordered]@{}; foreach ($property in $list.Files.PSObject.Properties) { $files[$property.Name] = $property.Value }
	return $files
}
# What Install.ps1 does: App\* (with SelfX.Code.json), Uninstall.ps1, the programs from Bin, the DLLs from Bin\WinRT, Bin\Audio and Bin\Disturb into
# App, and Config\* (with SelfX.Config.json) into Config.
$installed = Join-Path $root 'installed'
function New-InstalledCopy {
	if (Test-Path -LiteralPath $installed) { Remove-Item -LiteralPath $installed -Recurse -Force }
	$app = Join-Path $installed 'App'
	$config = Join-Path $installed 'Config'
	New-Item -ItemType Directory -Path $app, $config -Force | Out-Null
	Copy-Item -Path (Join-Path $pristine 'App\*') -Destination $app -Recurse
	Copy-Item -Path (Join-Path $pristine 'Config\*') -Destination $config -Recurse
	Copy-Item -LiteralPath (Join-Path $pristine 'Uninstall.ps1') -Destination $app
	foreach ($name in 'SelfXService.exe', 'SelfX.exe') { Copy-Item -LiteralPath (Join-Path $pristine "Bin\$name") -Destination $app }
	Copy-Item -LiteralPath (Join-Path $pristine 'Bin\WinRT') -Destination (Join-Path $app 'WinRT') -Recurse
	Copy-Item -LiteralPath (Join-Path $pristine 'Bin\Audio') -Destination (Join-Path $app 'Audio') -Recurse
	Copy-Item -LiteralPath (Join-Path $pristine 'Bin\Disturb') -Destination (Join-Path $app 'Disturb') -Recurse
}
try {
	New-Item -ItemType Directory -Path $pristine -Force | Out-Null
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Destination (Join-Path $pristine 'Sources') -Recurse
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $pristine
	# Stand-ins for the DLLs of Bin\WinRT (the real ones are built on the build machine); only their bytes matter here.
	New-Item -ItemType Directory -Path (Join-Path $pristine 'Bin\WinRT') -Force | Out-Null
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\WinRT\SelfXWinRT.dll'), [byte[]](1, 2, 3, 4))
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\WinRT\Microsoft.Windows.SDK.NET.dll'), [byte[]](5, 6, 7, 8))
	# Stand-in for Bin\Audio\SelfXAudio.dll (audio library of the action "No sound").
	New-Item -ItemType Directory -Path (Join-Path $pristine 'Bin\Audio') -Force | Out-Null
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\Audio\SelfXAudio.dll'), [byte[]](9, 10, 11, 12))
	# Stand-in for Bin\Disturb\SelfXDisturb.dll (library of the hint before disruptive actions).
	New-Item -ItemType Directory -Path (Join-Path $pristine 'Bin\Disturb') -Force | Out-Null
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\Disturb\SelfXDisturb.dll'), [byte[]](13, 14, 15, 16))
	# Stand-ins for the two programs of Bin (service and starter).
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\SelfXService.exe'), [byte[]](17, 18, 19, 20))
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\SelfX.exe'), [byte[]](21, 22, 23, 24))
	$expectedCount = @(Get-ChildItem -LiteralPath $pristine -Recurse -File).Count
	# The package layout of tools\New-SelfXIntuneWin.ps1: code files into App, configuration files into Config, Sources removed.
	$layout = ConvertTo-SelfXPackageLayout -Stage $pristine
	Assert-Equal (Test-Path -LiteralPath (Join-Path $pristine 'Sources')) $false 'layout: Sources is removed'
	Assert-Equal ($layout.Code + $layout.Config) ($expectedCount - 6) 'layout: every file of Sources is sorted (Uninstall.ps1 and the 5 files of Bin stay)'
	foreach ($name in 'Self_X.ps1', 'SelfXPaths.ps1', 'Scripts_to_run\SelfX_Device_SyncTime.ps1', 'HealthChecks\Check-Compliance.ps1', 'Languages\de.xml', 'Repair.ico', 'logo.png') {
		Assert-Equal (Test-Path -LiteralPath (Join-Path $pristine "App\$name") -PathType Leaf) $true "layout: $name is in App"
		Assert-Equal (Test-Path -LiteralPath (Join-Path $pristine "Config\$name")) $false "layout: $name is not in Config"
	}
	foreach ($name in 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'Ticket_Config.xml', 'Network_Test_Config.xml', 'Branding\company_logo.png') {
		Assert-Equal (Test-Path -LiteralPath (Join-Path $pristine "Config\$name") -PathType Leaf) $true "layout: $name is in Config"
		Assert-Equal (Test-Path -LiteralPath (Join-Path $pristine "App\$name")) $false "layout: $name is not in App"
	}
	Assert-Throws { ConvertTo-SelfXPackageLayout -Stage $pristine } 'Sources is missing' 'layout: a package that is already sorted is not sorted again'
	# A file without a class stops the sorting before anything is moved (fail closed).
	$unsorted = Join-Path $root 'unsorted'
	New-Item -ItemType Directory -Path (Join-Path $unsorted 'Sources') -Force | Out-Null
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sources\Self_X.ps1') -Destination (Join-Path $unsorted 'Sources')
	Set-Content -LiteralPath (Join-Path $unsorted 'Sources\Unknown.dll') -Value 'x'
	Assert-Throws { ConvertTo-SelfXPackageLayout -Stage $unsorted } 'belongs to no file class' 'layout: a file without a class stops the sorting'
	Assert-Equal ((Test-Path -LiteralPath (Join-Path $unsorted 'App')) -or (Test-Path -LiteralPath (Join-Path $unsorted 'Config'))) $false 'layout: nothing is moved when a file has no class'
	# The generator refuses the old layout (Sources still there).
	Assert-Throws { New-SelfXCodeManifest -Stage $unsorted -Version '9.9.9' } 'still has the folder Sources' 'generator: the old layout (Sources) is refused'
	Remove-Item -LiteralPath $unsorted -Recurse -Force

	# Every file of the repository has a class, and the name list of the project equals the files of the repository.
	$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Recurse -File | ForEach-Object { $_.FullName.Substring((Join-Path $PSScriptRoot 'Sources').Length + 1).Replace('\', '/') })
	foreach ($name in $sourceFiles) {
		$class = Get-SelfXFileClass -Name $name
		$expectedClass = if (($script:SelfXConfigFileNames -contains $name) -or $name -like 'Branding/*') { 'Config' } else { 'Code' }
		Assert-Equal $class $expectedClass "class: $name"
		if ($expectedClass -eq 'Code') { Assert-Equal ($script:SelfXCodeFileNames -ccontains $name) $true "name list of the project contains $name" }
	}
	$fromSources = @($script:SelfXCodeFileNames | Where-Object { $_ -notin 'Uninstall.ps1', 'SelfXService.exe', 'SelfX.exe', 'Audio/SelfXAudio.dll', 'Disturb/SelfXDisturb.dll' })
	foreach ($name in $fromSources) { Assert-Equal ($sourceFiles -ccontains $name) $true "name list of the project: $name exists in Sources" }
	Assert-Equal @($script:SelfXCodeFileNames | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1).Count 0 'name list of the project has no duplicates'
	foreach ($case in @(@('Branding/company_logo.png', 'Config'), @('Branding/a/b.xml', 'Config'), @('Tool_Config.xml', 'Config'), @('WinRT/Some.Library.dll', 'Code'), @('Scripts_to_run/Own_Action.ps1', 'Config'), @('HealthChecks/Own-Check.ps1', 'Config'), @('Languages/de-AT.xml', 'Config'), @('Texts/de.xml', 'Config'), @('Texts/zh-Hans.xml', 'Config'))) {
		Assert-Equal (Get-SelfXFileClass -Name $case[0]) $case[1] "class: $($case[0])"
	}
	foreach ($bad in 'Extra.dll', 'Evil.ps1', 'Sources/Self_X.ps1', 'Scripts_to_run/sub/Own.ps1', 'Languages/xx_yy.xml', 'Texts/x.ps1', 'Texts/sub/de.xml', 'Texts/de.xml.txt', 'Texts/xx_yy.xml', 'Texts/', 'Bin/SelfX.exe', '../Install.ps1', 'a//b.ps1', 'Branding/../Self_X.ps1') {
		Assert-Throws { Get-SelfXFileClass -Name $bad } 'belongs to no file class|Unsupported file name' "class: '$bad' is refused (fail closed)"
	}
	# The placement rules of the generator and of Install.ps1 give the same answer for every name.
	$placementNames = @($script:SelfXCodeFileNames) + $script:SelfXConfigFileNames + @('Branding/x.png', 'Branding/', 'Scripts_to_run/Own.ps1', 'Scripts_to_run/Own.exe', 'Scripts_to_run/a/b.ps1', 'HealthChecks/Own-Check.ps1', 'Languages/it.xml', 'Languages/it-CH.xml', 'Languages/x.ps1', 'Texts/de.xml', 'Texts/de-CH.xml', 'Texts/x.ps1', 'Texts/sub/de.xml', 'Texts/xx_yy.xml', 'Texts/', 'WinRT/A.dll', 'Evil.ps1', '../x', 'a/../b', 'C:/x')
	foreach ($name in $placementNames) {
		foreach ($list in 'Code', 'Config') {
			Assert-Equal (Test-SelfXListPlacement -Name $name -List $list) (Common_Test-SelfXListPlacement -Name $name -List $list) "placement of '$name' in $list is the same in Install.ps1 and the generator"
		}
	}
	Assert-Equal (Test-SelfXListPlacement -Name 'SelfXService.exe' -List 'Config') $false 'placement: a program must not be in the configuration list'
	Assert-Equal (Test-SelfXListPlacement -Name 'Tool_Config.xml' -List 'Code') $false 'placement: a settings file must not be in the code list'
	Assert-Equal (Test-SelfXListPlacement -Name 'Texts/de.xml' -List 'Config') $true 'placement: a text override belongs in the configuration list'
	Assert-Equal (Test-SelfXListPlacement -Name 'Texts/de.xml' -List 'Code') $false 'placement: a text override must not be in the code list'
	Assert-Equal (Test-SelfXListPlacement -Name 'Texts/x.ps1' -List 'Code') $false 'placement: nothing below Texts may be in the code list'
	Assert-Equal (Test-SelfXListPlacement -Name 'Texts/x.ps1' -List 'Config') $false 'placement: only <culture>.xml may be below Texts in the configuration list'
	# The service has the same rule: the names of the settings files and the two patterns are the same text.
	$serviceText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Service\SelfXService.cs') -Raw
	$serviceNames = [regex]::Match($serviceText, 'ConfigFileNames = \{([^}]*)\}').Groups[1].Value
	Assert-Equal (([regex]::Matches($serviceNames, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object) -join ',') (($script:SelfXConfigFileNames | Sort-Object) -join ',') 'service: the settings files are the same as in the generator'
	Assert-Equal $serviceText.Contains('^(Scripts_to_run|HealthChecks)/[A-Za-z0-9._-]+\.ps1\z') $true 'service: same pattern for own scripts'
	Assert-Equal $serviceText.Contains('^Languages/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml\z') $true 'service: same pattern for own language files'
	Assert-Equal $serviceText.Contains('^Texts/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml\z') $true 'service: same pattern for text overrides'
	Assert-Equal $serviceText.Contains('name.StartsWith("Texts/", StringComparison.Ordinal)') $true 'service: nothing below Texts is allowed in the code list'

	# The generator lists every installed file in exactly one list and the check accepts the result.
	$codeCount = New-SelfXCodeManifest -Stage $pristine -Version '9.9.9'
	$configCount = New-SelfXConfigManifest -Stage $pristine
	$count = $codeCount + $configCount
	Assert-Equal $count $expectedCount 'generator: every file of Sources, Uninstall.ps1, Bin\WinRT, Bin\Audio, Bin\Disturb and the two programs is listed in one of the two lists'
	$manifest = Get-Content -LiteralPath (Get-ListPath $pristine 'SelfX.Code.json') -Raw | ConvertFrom-Json
	$configManifest = Get-Content -LiteralPath (Get-ListPath $pristine 'SelfX.Config.json') -Raw | ConvertFrom-Json
	Assert-Equal $manifest.ManifestVersion 1 'code list: format 1'
	Assert-Equal $configManifest.ManifestVersion 1 'configuration list: format 1'
	Assert-Equal $manifest.ToolVersion '9.9.9' 'code list: version'
	Assert-Equal ($null -eq $manifest.BuiltUtc) $true 'code list: no build time (same contents give the same bytes)'
	Assert-Equal ($null -eq $manifest.ConfigRevision) $true 'code list: no configuration revision'
	Assert-Equal ($null -eq $configManifest.ToolVersion) $true 'configuration list: no version (the version is a property of the code)'
	Assert-Equal ($null -eq $configManifest.BuiltUtc) $true 'configuration list: no BuiltUtc any more'
	Assert-Equal ((Get-ConfigRevisionText (Get-ListPath $pristine 'SelfX.Config.json')) -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') $true 'configuration list: ConfigRevision is a UTC time (yyyy-MM-ddTHH:mm:ssZ)'
	foreach ($name in 'Uninstall.ps1', 'Self_X.ps1', 'Scripts_to_run/SelfX_Device_SyncTime.ps1', 'Languages/de.xml', 'logo.png', 'HealthChecks/Check-Compliance.ps1') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "code list contains $name"
		Assert-Equal ($null -eq $configManifest.Files.$name) $true "configuration list does not contain $name"
	}
	foreach ($name in 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'Ticket_Config.xml', 'Network_Test_Config.xml', 'Branding/company_logo.png') {
		Assert-Equal ($null -ne $configManifest.Files.$name) $true "configuration list contains $name"
		Assert-Equal ($null -eq $manifest.Files.$name) $true "code list does not contain $name"
	}
	foreach ($listName in 'SelfX.Code.json', 'SelfX.Config.json') { Assert-Equal ($null -eq $manifest.Files.$listName -and $null -eq $configManifest.Files.$listName) $true "no list contains $listName" }
	foreach ($name in 'WinRT/SelfXWinRT.dll', 'WinRT/Microsoft.Windows.SDK.NET.dll', 'Audio/SelfXAudio.dll', 'Disturb/SelfXDisturb.dll') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "code list contains $name"
	}
	foreach ($name in 'SelfXService.exe', 'SelfX.exe') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "code list contains $name"
		Assert-Equal $manifest.Files.$name (Get-FileHash -LiteralPath (Join-Path $pristine "Bin\$name") -Algorithm SHA256).Hash "code list: SHA256 of $name"
	}
	Assert-Equal $manifest.Files.'WinRT/SelfXWinRT.dll' (Get-FileHash -LiteralPath (Join-Path $pristine 'Bin\WinRT\SelfXWinRT.dll') -Algorithm SHA256).Hash 'code list: SHA256 of the WinRT library'
	Assert-Equal $manifest.Files.'Audio/SelfXAudio.dll' (Get-FileHash -LiteralPath (Join-Path $pristine 'Bin\Audio\SelfXAudio.dll') -Algorithm SHA256).Hash 'code list: SHA256 of the audio library'
	Assert-Equal $manifest.Files.'Disturb/SelfXDisturb.dll' (Get-FileHash -LiteralPath (Join-Path $pristine 'Bin\Disturb\SelfXDisturb.dll') -Algorithm SHA256).Hash 'code list: SHA256 of the disturb library'
	# The lists are in App and Config: they must not count as extra files.
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $pristine) ($count) 'check: the unchanged package is accepted'

	# A changed logo of the company changes only SelfX.Config.json and the configuration digest; SelfX.Code.json stays byte-identical.
	$logoStage = Join-Path $root 'logo'
	Copy-Item -LiteralPath $pristine -Destination $logoStage -Recurse
	Remove-Item -LiteralPath (Get-ListPath $logoStage 'SelfX.Code.json'), (Get-ListPath $logoStage 'SelfX.Config.json')
	[IO.File]::WriteAllBytes((Join-Path $logoStage 'Config\Branding\company_logo.png'), [byte[]](1, 1, 1, 1, 1))
	[void](New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9'); [void](New-SelfXConfigManifest -Stage $logoStage)
	$codeBefore = [IO.File]::ReadAllBytes((Get-ListPath $logoStage 'SelfX.Code.json'))
	$configBefore = [IO.File]::ReadAllBytes((Get-ListPath $logoStage 'SelfX.Config.json'))
	$codeDigestBefore = Get-SelfXListDigest -Stage $logoStage -ListName 'SelfX.Code.json'
	$configDigestBefore = Get-SelfXListDigest -Stage $logoStage -ListName 'SelfX.Config.json'
	[IO.File]::WriteAllBytes((Join-Path $logoStage 'Config\Branding\company_logo.png'), [byte[]](2, 2, 2, 2, 2))
	Start-Sleep -Seconds 1
	[void](New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9'); [void](New-SelfXConfigManifest -Stage $logoStage)
	Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Get-ListPath $logoStage 'SelfX.Code.json'))) -ceq [Convert]::ToBase64String($codeBefore)) $true 'logo changed: SelfX.Code.json is byte-identical'
	Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Get-ListPath $logoStage 'SelfX.Config.json'))) -ceq [Convert]::ToBase64String($configBefore)) $false 'logo changed: SelfX.Config.json changes'
	Assert-Equal (Get-SelfXListDigest -Stage $logoStage -ListName 'SelfX.Code.json') $codeDigestBefore 'logo changed: the code digest stays'
	Assert-Equal ((Get-SelfXListDigest -Stage $logoStage -ListName 'SelfX.Config.json') -ne $configDigestBefore) $true 'logo changed: the configuration digest changes'
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $logoStage) $count 'logo changed: the new package is accepted'
	# The same package built twice gives the same code list (no build time in it).
	Start-Sleep -Seconds 1
	[void](New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9')
	Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Get-ListPath $logoStage 'SelfX.Code.json'))) -ceq [Convert]::ToBase64String($codeBefore)) $true 'rebuilt: SelfX.Code.json is byte-identical'

	# The version is a property of the code: changing the version changes no configuration file, changing the configuration does not
	# change the version.
	$versionStage = Join-Path $root 'version'
	function New-VersionStage([string]$Version, [string]$LegacyVersionElement) {
		if (Test-Path -LiteralPath $versionStage) { Remove-Item -LiteralPath $versionStage -Recurse -Force }
		Copy-Item -LiteralPath $pristine -Destination $versionStage -Recurse
		Remove-Item -LiteralPath (Get-ListPath $versionStage 'SelfX.Code.json'), (Get-ListPath $versionStage 'SelfX.Config.json')
		if ($LegacyVersionElement) {
			# A Tool_Config.xml of a company that still has the old element: tolerated, but never evaluated.
			$configFile = Join-Path $versionStage 'Config\Tool_Config.xml'
			$text = [IO.File]::ReadAllText($configFile)
			[IO.File]::WriteAllText($configFile, $text.Replace('<GUI_Config>', "<GUI_Config><Tool_Version>$LegacyVersionElement</Tool_Version>"), (New-Object System.Text.UTF8Encoding($true)))
		}
		[void](New-SelfXCodeManifest -Stage $versionStage -Version $Version)
		[void](New-SelfXConfigManifest -Stage $versionStage -ConfigRevision '2026-11-27T10:00:00Z')
		return @{
			CodeBytes   = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Get-ListPath $versionStage 'SelfX.Code.json')))
			ConfigBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Get-ListPath $versionStage 'SelfX.Config.json')))
			CodeFiles   = (Get-ListFiles (Get-ListPath $versionStage 'SelfX.Code.json'))
			ConfigFiles = (Get-ListFiles (Get-ListPath $versionStage 'SelfX.Config.json'))
			CodeDigest  = (Get-SelfXListDigest -Stage $versionStage -ListName 'SelfX.Code.json')
			ConfigDigest = (Get-SelfXListDigest -Stage $versionStage -ListName 'SelfX.Config.json')
			Version     = (Get-Content -LiteralPath (Get-ListPath $versionStage 'SelfX.Code.json') -Raw | ConvertFrom-Json).ToolVersion
		}
	}
	$versionA = New-VersionStage '3.0.2'
	$versionB = New-VersionStage '3.0.3'
	Assert-Equal $versionA.Version '3.0.2' 'version: the code list carries the version of the run'
	Assert-Equal $versionB.Version '3.0.3' 'version: a new version is written into the code list'
	Assert-Equal ($versionA.CodeBytes -ceq $versionB.CodeBytes) $false 'version: a new version changes SelfX.Code.json'
	Assert-Equal ($versionA.ConfigBytes -ceq $versionB.ConfigBytes) $true 'version: a new version does not change SelfX.Config.json (same bytes)'
	Assert-Equal $versionB.ConfigDigest $versionA.ConfigDigest 'version: a new version does not change the configuration digest'
	Assert-Equal (($versionA.ConfigFiles.Keys | ForEach-Object { "$_=$($versionA.ConfigFiles[$_])" }) -join ';') (($versionB.ConfigFiles.Keys | ForEach-Object { "$_=$($versionB.ConfigFiles[$_])" }) -join ';') 'version: a new version changes no configuration file (all hashes the same)'
	Assert-Equal (($versionA.CodeFiles.Keys | ForEach-Object { "$_=$($versionA.CodeFiles[$_])" }) -join ';') (($versionB.CodeFiles.Keys | ForEach-Object { "$_=$($versionB.CodeFiles[$_])" }) -join ';') 'version: a new version changes no file of the code either (the version is in no file of the package)'
	Assert-Equal $versionB.CodeDigest $versionA.CodeDigest 'version: the code digest does not contain the version (only changed files change it)'
	# The configuration changes (logo, a setting, a new own script): the version and the code files stay.
	New-VersionStage '3.0.2' | Out-Null
	[IO.File]::WriteAllBytes((Join-Path $versionStage 'Config\Branding\company_logo.png'), [byte[]](4, 4, 4, 4))
	Add-Content -LiteralPath (Join-Path $versionStage 'Config\Ticket_Config.xml') -Value '<!-- changed -->'
	[void](New-SelfXConfigManifest -Stage $versionStage -ConfigRevision '2026-11-27T11:00:00Z')
	$configChanged = @{
		CodeBytes    = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Get-ListPath $versionStage 'SelfX.Code.json')))
		ConfigDigest = (Get-SelfXListDigest -Stage $versionStage -ListName 'SelfX.Config.json')
		Revision     = (Get-ConfigRevisionText (Get-ListPath $versionStage 'SelfX.Config.json'))
	}
	Assert-Equal ($configChanged.CodeBytes -ceq $versionA.CodeBytes) $true 'configuration changed: SelfX.Code.json is byte-identical (version and code files stay)'
	Assert-Equal ($configChanged.ConfigDigest -ne $versionA.ConfigDigest) $true 'configuration changed: the configuration digest changes'
	Assert-Equal $configChanged.Revision '2026-11-27T11:00:00Z' 'configuration changed: ConfigRevision is the time that the run was given'
	# The ConfigRevision alone is not part of the digest: the same configuration at another time has the same digest.
	[void](New-SelfXConfigManifest -Stage $versionStage -ConfigRevision '2030-01-01T00:00:00Z')
	Assert-Equal (Get-SelfXListDigest -Stage $versionStage -ListName 'SelfX.Config.json') $configChanged.ConfigDigest 'configuration changed: another ConfigRevision with the same files gives the same digest'
	# An old Tool_Version element in Tool_Config.xml is tolerated and never evaluated: the version is the one of the run, and the code list
	# does not depend on it.
	$legacyA = New-VersionStage '3.0.2' '1.1.1'
	$legacyB = New-VersionStage '3.0.2' '2.2.2'
	Assert-Equal $legacyA.Version '3.0.2' 'legacy Tool_Version: the code list has the version of the run, not the one of Tool_Config.xml'
	Assert-Equal ($legacyA.CodeBytes -ceq $versionA.CodeBytes) $true 'legacy Tool_Version: SelfX.Code.json is the same as without the element'
	Assert-Equal ($legacyA.CodeBytes -ceq $legacyB.CodeBytes) $true 'legacy Tool_Version: another value in Tool_Config.xml does not change SelfX.Code.json'
	Assert-Equal ($legacyA.ConfigDigest -ne $legacyB.ConfigDigest) $true 'legacy Tool_Version: the element is only a changed configuration file (the configuration digest)'
	# The generators refuse a version or revision that is not allowed (fail closed).
	foreach ($bad in '', ' ', '3.0.2 beta', '..\x', '3.0.2;calc', ('1' * 31), "3.0.2`n3.0.3") {
		Assert-Throws { New-SelfXCodeManifest -Stage $versionStage -Version $bad } 'Invalid version|Cannot bind' "generator: the version '$($bad -replace '\s', '_')' is refused"
	}
	foreach ($bad in 'now', '2026-11-27', '2026-11-27 10:00:00', '2026-11-27T10:00:00+01:00', "2026-11-27T10:00:00Z`n", '2026-11-27T10:00:00Z;x') {
		Assert-Throws { New-SelfXConfigManifest -Stage $versionStage -ConfigRevision $bad } 'Invalid ConfigRevision' "generator: the ConfigRevision '$($bad -replace '\s', '_')' is refused"
	}
	[void](New-SelfXConfigManifest -Stage $versionStage)
	$defaultRevision = Get-ConfigRevisionText (Get-ListPath $versionStage 'SelfX.Config.json')
	Assert-Equal ($defaultRevision -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') $true 'ConfigRevision: without a value it is written in the format yyyy-MM-ddTHH:mm:ssZ'
	$revisionTime = [DateTime]::ParseExact($defaultRevision, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
	Assert-Equal ([Math]::Abs(([DateTime]::UtcNow - $revisionTime).TotalMinutes) -lt 5) $true 'ConfigRevision: without a value it is the current UTC time'
	Remove-Item -LiteralPath $versionStage -Recurse -Force

	# Version.txt: one line, only the allowed characters.
	$versionFiles = Join-Path $root 'versionfiles'
	New-Item -ItemType Directory -Path $versionFiles -Force | Out-Null
	$versionFile = Join-Path $versionFiles 'Version.txt'
	foreach ($case in @(@("3.0.2`n", '3.0.2'), @("3.0.2`r`n", '3.0.2'), @('3.0.2', '3.0.2'), @("  3.0.2  `n`n", '3.0.2'), @("`n3.0.2-rc.1`n", '3.0.2-rc.1'))) {
		[IO.File]::WriteAllText($versionFile, $case[0])
		Assert-Equal (Get-SelfXVersionFromFile -Path $versionFile) $case[1] "Version.txt: '$($case[0] -replace '\s', '_')' gives $($case[1])"
	}
	[IO.File]::WriteAllText($versionFile, "3.0.2`n", (New-Object System.Text.UTF8Encoding($true)))
	Assert-Equal (Get-SelfXVersionFromFile -Path $versionFile) '3.0.2' 'Version.txt: a byte order mark is accepted'
	foreach ($bad in '', "`n", '   ', "3.0.2`n3.0.3", "3.0.2`n# comment", '3.0.2 beta', '..\evil', '3.0.2/../x', '$(calc)', ('1' * 31), '3,0,2') {
		[IO.File]::WriteAllText($versionFile, $bad)
		Assert-Throws { Get-SelfXVersionFromFile -Path $versionFile } 'exactly one line|Invalid version' "Version.txt: '$($bad -replace '\s', '_')' is refused"
	}
	Assert-Throws { Get-SelfXVersionFromFile -Path (Join-Path $versionFiles 'missing.txt') } 'version file is missing' 'Version.txt: a missing file is refused'
	Assert-Throws { Get-SelfXVersionFromFile -Path $versionFiles } 'version file is missing' 'Version.txt: a folder is refused'
	Remove-Item -LiteralPath $versionFiles -Recurse -Force

	# Install.ps1 reads the version from the code list of the package (Get-SelfXPackageToolVersion).
	Reset-Package
	Assert-Equal (Get-SelfXPackageToolVersion -PackageFolder $package) '9.9.9' 'install: the version of the package is ToolVersion of SelfX.Code.json'
	Reset-Package; Remove-Item -LiteralPath (Get-ListPath $package 'SelfX.Code.json')
	Assert-Throws { Get-SelfXPackageToolVersion -PackageFolder $package } 'has no version' 'install: a package without SelfX.Code.json has no version (refused)'
	Reset-Package; Set-Content -LiteralPath (Get-ListPath $package 'SelfX.Code.json') -Value '{ not json'
	Assert-Throws { Get-SelfXPackageToolVersion -PackageFolder $package } 'not valid JSON' 'install: a broken SelfX.Code.json is refused'
	Reset-Package; Set-Content -LiteralPath (Get-ListPath $package 'SelfX.Code.json') -Value '"9.9.9"'
	Assert-Throws { Get-SelfXPackageToolVersion -PackageFolder $package } 'no valid ToolVersion' 'install: a list that is only a string is refused'
	foreach ($bad in $null, '', ' ', '9.9.9 x', '..\evil', '9.9.9"; calc; "', ('1' * 31), "9.9.9`n9.9.10") {
		Reset-Package
		[IO.File]::WriteAllText((Get-ListPath $package 'SelfX.Code.json'), (([ordered]@{ ManifestVersion = 1; ToolVersion = $bad; Files = @{ 'Uninstall.ps1' = 'AA' } }) | ConvertTo-Json))
		Assert-Throws { Get-SelfXPackageToolVersion -PackageFolder $package } 'no valid ToolVersion' "install: the ToolVersion '$("$bad" -replace '\s', '_')' is refused"
	}
	Reset-Package; Set-Content -LiteralPath (Get-ListPath $package 'SelfX.Code.json') -Value '{"ManifestVersion":1,"Files":{"Uninstall.ps1":"AA"}}'
	Assert-Throws { Get-SelfXPackageToolVersion -PackageFolder $package } 'no valid ToolVersion' 'install: a list without ToolVersion is refused'
	Reset-Package; $codeListOnly = Get-Content -LiteralPath (Get-ListPath $package 'SelfX.Config.json') -Raw
	Assert-Equal ($codeListOnly -match 'ToolVersion') $false 'install: the configuration list has no version that could be taken instead'

	# An own script of the company is Code for nobody: it goes into SelfX.Config.json and the check accepts it.
	New-Item -ItemType Directory -Path (Join-Path $logoStage 'Config\Scripts_to_run') -Force | Out-Null
	[IO.File]::WriteAllText((Join-Path $logoStage 'Config\Scripts_to_run\Own_Action.ps1'), 'Write-Output 1')
	[void](New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9'); [void](New-SelfXConfigManifest -Stage $logoStage)
	Assert-Equal ($null -ne (Get-ListFiles (Get-ListPath $logoStage 'SelfX.Config.json'))['Scripts_to_run/Own_Action.ps1']) $true 'own script: listed in SelfX.Config.json'
	Assert-Equal ($null -eq (Get-ListFiles (Get-ListPath $logoStage 'SelfX.Code.json'))['Scripts_to_run/Own_Action.ps1']) $true 'own script: not in SelfX.Code.json'
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $logoStage) ($count + 1) 'own script: the package is accepted'
	# A file that no rule knows stops the generator (fail closed).
	[IO.File]::WriteAllText((Join-Path $logoStage 'App\Unknown.dll'), 'x')
	Assert-Throws { New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9' } 'belongs to no file class' 'generator: an unknown file stops the build'
	Assert-Throws { New-SelfXConfigManifest -Stage $logoStage } 'belongs to no file class' 'generator: an unknown file stops the build (configuration list)'
	Remove-Item -LiteralPath (Join-Path $logoStage 'App\Unknown.dll')
	# A file in the wrong folder of the package stops the generator: an own script in App, a settings file in App, a project file in Config.
	Move-Item -LiteralPath (Join-Path $logoStage 'Config\Scripts_to_run\Own_Action.ps1') -Destination (Join-Path $logoStage 'App\Scripts_to_run\Own_Action.ps1')
	Assert-Throws { New-SelfXConfigManifest -Stage $logoStage } 'Own_Action.ps1 is in the folder App but belongs to the class Config' 'generator: an own script in App is refused'
	Remove-Item -LiteralPath (Join-Path $logoStage 'App\Scripts_to_run\Own_Action.ps1')
	Copy-Item -LiteralPath (Join-Path $logoStage 'App\SelfXPaths.ps1') -Destination (Join-Path $logoStage 'Config\SelfXPaths.ps1')
	Assert-Throws { New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9' } 'Duplicate file name|SelfXPaths.ps1 is in the folder Config but belongs to the class Code' 'generator: a project file in Config is refused'
	Remove-Item -LiteralPath $logoStage -Recurse -Force

	Reset-Package
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $package) $count 'check: a copy of the package is accepted'

	# Tampering is refused before anything is installed.
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'App\Scripts_to_run\SelfX_Device_SyncTime.ps1') -Value '# changed'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'does not match its SHA256' 'check: a changed script is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'App\Scripts_to_run\Evil.ps1') -Value 'calc.exe'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'not listed' 'check: an extra script in Scripts_to_run is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'App\Extra.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'not listed' 'check: an extra file in App is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'Config\Extra.xml') -Value '<x />'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Extra.xml is in the package but not listed in SelfX.Config.json' 'check: an extra file in Config is refused'
	# A file in the wrong folder of the package: a settings file in App, a project script in Config.
	Reset-Package; Copy-Item -LiteralPath (Join-Path $package 'Config\Tool_Config.xml') -Destination (Join-Path $package 'App\Tool_Config.xml')
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Tool_Config.xml is in the package but not listed in SelfX.Code.json' 'check: a settings file in App is refused'
	Reset-Package; Copy-Item -LiteralPath (Join-Path $package 'App\Self_X.ps1') -Destination (Join-Path $package 'Config\Self_X.ps1')
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Self_X.ps1 is in the package but not listed in SelfX.Config.json' 'check: a project script in Config is refused'
	# A package in the old layout (folder Sources) is refused.
	Reset-Package; New-Item -ItemType Directory -Path (Join-Path $package 'Sources') -Force | Out-Null
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'old layout' 'check: a package with the folder Sources is refused'
	Reset-Package; Remove-Item -LiteralPath (Join-Path $package 'Config\Issues_List.xml')
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'missing in the package' 'check: a missing file is refused'
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'Bin\WinRT\SelfXWinRT.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'WinRT/SelfXWinRT.dll does not match its SHA256' 'check: a changed WinRT library is refused'
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'Bin\Audio\SelfXAudio.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Audio/SelfXAudio.dll does not match its SHA256' 'check: a changed audio library is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'Bin\Audio\Extra.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Audio/Extra.dll is in the package but not listed' 'check: an extra audio file is refused'
	Reset-Package; Remove-Item -LiteralPath (Join-Path $package 'Bin\Audio\SelfXAudio.dll')
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'missing in the package' 'check: a missing audio library is refused'
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'Bin\Disturb\SelfXDisturb.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Disturb/SelfXDisturb.dll does not match its SHA256' 'check: a changed disturb library is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'Bin\Disturb\Extra.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Disturb/Extra.dll is in the package but not listed' 'check: an extra disturb file is refused'
	Reset-Package; Remove-Item -LiteralPath (Join-Path $package 'Bin\Disturb\SelfXDisturb.dll')
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'missing in the package' 'check: a missing disturb library is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'Bin\WinRT\Extra.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'WinRT/Extra.dll is in the package but not listed' 'check: an extra WinRT library is refused'
	Reset-Package; Remove-Item -LiteralPath (Join-Path $package 'Bin\WinRT\Microsoft.Windows.SDK.NET.dll')
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'missing in the package' 'check: a missing WinRT library is refused'
	foreach ($program in 'SelfXService.exe', 'SelfX.exe') {
		Reset-Package; [IO.File]::WriteAllBytes((Join-Path $package "Bin\$program"), [byte[]](99, 99))
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } "$([regex]::Escape($program)) does not match its SHA256" "check: a changed $program is refused"
		Reset-Package; Remove-Item -LiteralPath (Join-Path $package "Bin\$program")
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'missing in the package' "check: a missing $program is refused"
	}
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'Uninstall.ps1') -Value '# changed'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'does not match its SHA256' 'check: a changed Uninstall.ps1 is refused'
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'Config\Health_Config.xml') -Value '<!-- changed -->'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'does not match its SHA256' 'check: a changed catalog configuration is refused'

	# A broken or unexpected list is refused, a missing list is reported.
	foreach ($listName in 'SelfX.Code.json', 'SelfX.Config.json') {
		Reset-Package; Set-Content -LiteralPath (Get-ListPath $package $listName) -Value '{ not json'
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'not valid JSON' "check: broken JSON in $listName is refused"
		Reset-Package; Set-Content -LiteralPath (Get-ListPath $package $listName) -Value '{"ManifestVersion":2,"Files":{"Uninstall.ps1":"00"}}'
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'unknown format' "check: an unknown format in $listName is refused"
		foreach ($bad in '../Install.ps1', 'a/../../b.ps1', 'C:/Windows/x.ps1', '/etc/x', 'a//b.ps1', '.hidden/..') {
			Reset-Package
			Set-List (Get-ListPath $package $listName) ([ordered]@{ $bad = 'AA' })
			Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'unsupported name' "check: the name '$bad' in $listName is refused"
		}
		Reset-Package; Remove-Item -LiteralPath (Get-ListPath $package $listName)
		$other = if ($listName -eq 'SelfX.Code.json') { 'SelfX.Config.json' } else { 'SelfX.Code.json' }
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } "$([regex]::Escape($listName)) is missing in the package" "check: a package with only $other is refused"
	}
	# A list without Uninstall.ps1 or without one of the programs is refused.
	foreach ($missing in 'Uninstall.ps1', 'SelfXService.exe', 'SelfX.exe') {
		Reset-Package; $files = Get-ListFiles (Get-ListPath $package 'SelfX.Code.json'); $files.Remove($missing)
		Set-List (Get-ListPath $package 'SelfX.Code.json') $files
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } "$([regex]::Escape($missing)) is not listed" "check: a code list without $missing is refused"
	}
	# A file in both lists, a file in none, and a file in the wrong list are refused.
	Reset-Package; $codeFiles = Get-ListFiles (Get-ListPath $package 'SelfX.Code.json'); $configFiles = Get-ListFiles (Get-ListPath $package 'SelfX.Config.json')
	$configFiles['Scripts_to_run/SelfX_Device_SyncTime.ps1'] = $codeFiles['Scripts_to_run/SelfX_Device_SyncTime.ps1']
	Set-List (Get-ListPath $package 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'listed in both SelfX.Code.json and SelfX.Config.json' 'check: a file in both lists is refused'
	Reset-Package; $codeFiles = Get-ListFiles (Get-ListPath $package 'SelfX.Code.json'); $codeFiles.Remove('Self_X.ps1')
	Set-List (Get-ListPath $package 'SelfX.Code.json') $codeFiles
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Self_X.ps1 is in the package but not listed' 'check: a file in no list is refused'
	Reset-Package; $codeFiles = Get-ListFiles (Get-ListPath $package 'SelfX.Code.json'); $configFiles = Get-ListFiles (Get-ListPath $package 'SelfX.Config.json')
	$codeFiles['Tool_Config.xml'] = $configFiles['Tool_Config.xml']; $configFiles.Remove('Tool_Config.xml')
	Set-List (Get-ListPath $package 'SelfX.Code.json') $codeFiles; Set-List (Get-ListPath $package 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Tool_Config.xml must not be listed in SelfX.Code.json' 'check: a settings file in the code list is refused'
	Reset-Package; $codeFiles = Get-ListFiles (Get-ListPath $package 'SelfX.Code.json'); $configFiles = Get-ListFiles (Get-ListPath $package 'SelfX.Config.json')
	$configFiles['Branding/company_logo.png'] = $configFiles['Branding/company_logo.png']; $codeFiles['Branding/company_logo.png'] = $configFiles['Branding/company_logo.png']; $configFiles.Remove('Branding/company_logo.png')
	Set-List (Get-ListPath $package 'SelfX.Code.json') $codeFiles; Set-List (Get-ListPath $package 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Branding/company_logo.png must not be listed in SelfX.Code.json' 'check: a file of Branding in the code list is refused'
	foreach ($moved in 'SelfXService.exe', 'Uninstall.ps1', 'Self_X.ps1', 'logo.png', 'WinRT/SelfXWinRT.dll', 'Languages/de.xml/../x') {
		Reset-Package; $codeFiles = Get-ListFiles (Get-ListPath $package 'SelfX.Code.json'); $configFiles = Get-ListFiles (Get-ListPath $package 'SelfX.Config.json')
		if ($codeFiles.Contains($moved)) { $configFiles[$moved] = $codeFiles[$moved]; $codeFiles.Remove($moved) } else { $configFiles[$moved] = 'AA' }
		Set-List (Get-ListPath $package 'SelfX.Code.json') $codeFiles; Set-List (Get-ListPath $package 'SelfX.Config.json') $configFiles
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'must not be listed in SelfX.Config.json|unsupported name' "check: '$moved' in the configuration list is refused"
	}
	Reset-Package; $files = Get-ListFiles (Get-ListPath $package 'SelfX.Code.json'); $files['Extra.dll'] = 'AA'
	Set-List (Get-ListPath $package 'SelfX.Code.json') $files
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Extra.dll is listed in SelfX.Code.json but missing in the package' 'check: a listed file that is not in the package is refused'
	Reset-Package; Remove-Item -LiteralPath (Get-ListPath $package 'SelfX.Code.json'), (Get-ListPath $package 'SelfX.Config.json')
	Assert-Equal ($null -eq (Test-SelfXFileManifest -PackageFolder $package)) $true 'check: a package without the lists is reported as not checked'

	# The generator refuses a package without one of the programs.
	foreach ($program in 'SelfXService.exe', 'SelfX.exe') {
		Reset-Package; Remove-Item -LiteralPath (Join-Path $package "Bin\$program")
		Assert-Throws { New-SelfXCodeManifest -Stage $package -Version '9.9.9' } "Bin\\$([regex]::Escape($program)) is missing" "generator: a package without $program is refused"
	}

	# The installed folder after copying: the same list, the files at their installed places.
	New-InstalledCopy
	Assert-Equal (Test-SelfXInstalledFiles -InstallFolder $installed) $count 'installed: the unchanged installation is accepted'
	foreach ($program in 'SelfXService.exe', 'SelfX.exe') {
		New-InstalledCopy; [IO.File]::WriteAllBytes((Join-Path $installed "App\$program"), [byte[]](99, 99))
		Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } "$([regex]::Escape($program)) in the folder App does not match" "installed: a changed $program is refused"
		New-InstalledCopy; Remove-Item -LiteralPath (Join-Path $installed "App\$program")
		Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } "$([regex]::Escape($program)) is missing in the folder App" "installed: a missing $program is refused"
	}
	New-InstalledCopy; Add-Content -LiteralPath (Join-Path $installed 'App\Scripts_to_run\SelfX_Device_SyncTime.ps1') -Value '# changed'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'does not match its SHA256' 'installed: a changed script is refused'
	New-InstalledCopy; Add-Content -LiteralPath (Join-Path $installed 'App\WinRT\SelfXWinRT.dll') -Value 'x'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'WinRT/SelfXWinRT.dll in the folder App does not match' 'installed: a changed WinRT library is refused'
	New-InstalledCopy; Remove-Item -LiteralPath (Join-Path $installed 'Config\Issues_List.xml')
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'Issues_List.xml is missing in the folder Config' 'installed: a missing configuration file is refused'
	# Unlisted files in App and Config are refused (also a settings file copied into App).
	New-InstalledCopy; New-Item -ItemType Directory -Path (Join-Path $installed 'Config\Scripts_to_run') -Force | Out-Null
	Set-Content -LiteralPath (Join-Path $installed 'Config\Scripts_to_run\Planted.ps1') -Value 'calc.exe'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'Config/Scripts_to_run/Planted.ps1 is not listed in SelfX.Config.json' 'installed: an unlisted own script in Config is refused'
	New-InstalledCopy; Copy-Item -LiteralPath (Join-Path $installed 'Config\Tool_Config.xml') -Destination (Join-Path $installed 'App\Tool_Config.xml')
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'App/Tool_Config.xml is not listed in SelfX.Code.json' 'installed: a settings file in App is refused'
	# Migration: nothing of an older layout may be left next to App and Config.
	New-InstalledCopy; Set-Content -LiteralPath (Join-Path $installed 'Tool_Config.xml') -Value '<GUI_Config />'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'Tool_Config.xml in the installation folder is left over' 'installed: a file of the old layout next to App and Config is refused'
	New-InstalledCopy; New-Item -ItemType Directory -Path (Join-Path $installed 'Scripts_to_run') | Out-Null; Set-Content -LiteralPath (Join-Path $installed 'Scripts_to_run\SelfX_Device_Restart.ps1') -Value 'old'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'Scripts_to_run in the installation folder is left over from an older installation and is not empty' 'installed: a non-empty folder of the old layout is refused'
	New-InstalledCopy; New-Item -ItemType Directory -Path (Join-Path $installed 'Scripts_to_run\Empty') -Force | Out-Null
	Assert-Equal (Test-SelfXInstalledFiles -InstallFolder $installed) $count 'installed: an empty folder of the old layout (still in use) is allowed'
	New-InstalledCopy; Remove-Item -LiteralPath (Join-Path $installed 'Config') -Recurse -Force
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'The folder Config is missing' 'installed: a missing folder Config is refused'
	New-InstalledCopy; Remove-Item -LiteralPath (Get-ListPath $installed 'SelfX.Config.json')
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'SelfX.Config.json is missing' 'installed: a missing list is refused'
	New-InstalledCopy; Remove-Item -LiteralPath (Get-ListPath $installed 'SelfX.Code.json')
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'SelfX.Code.json is missing' 'installed: a missing code list is refused'
	foreach ($listName in 'SelfX.Code.json', 'SelfX.Config.json') {
		New-InstalledCopy; Set-Content -LiteralPath (Get-ListPath $installed $listName) -Value '{ not json'
		Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'not valid JSON' "installed: a broken $listName is refused"
		New-InstalledCopy; Set-Content -LiteralPath (Get-ListPath $installed $listName) -Value '{"ManifestVersion":2,"Files":{"Uninstall.ps1":"00"}}'
		Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'unknown format' "installed: an unknown format of $listName is refused"
		foreach ($bad in '../Install.ps1', 'a/../../b.ps1', 'C:/Windows/x.ps1', 'a//b.ps1') {
			New-InstalledCopy
			Set-List (Get-ListPath $installed $listName) ([ordered]@{ $bad = 'AA' })
			Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'unsupported name' "installed: the name '$bad' in $listName is refused"
		}
	}
	New-InstalledCopy; $configFiles = Get-ListFiles (Get-ListPath $installed 'SelfX.Config.json'); $codeFiles = Get-ListFiles (Get-ListPath $installed 'SelfX.Code.json')
	$configFiles['Self_X.ps1'] = $codeFiles['Self_X.ps1']
	Set-List (Get-ListPath $installed 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'Self_X.ps1 must not be listed in SelfX.Config.json' 'installed: a project script in the configuration list is refused'
	New-InstalledCopy; $configFiles = Get-ListFiles (Get-ListPath $installed 'SelfX.Config.json'); $codeFiles = Get-ListFiles (Get-ListPath $installed 'SelfX.Code.json')
	$configFiles['Scripts_to_run/SelfX_Device_SyncTime.ps1'] = $codeFiles['Scripts_to_run/SelfX_Device_SyncTime.ps1']
	Set-List (Get-ListPath $installed 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'listed in both SelfX.Code.json and SelfX.Config.json' 'installed: a file in both lists is refused'
	New-InstalledCopy; Add-Content -LiteralPath (Join-Path $installed 'Config\Branding\company_logo.png') -Value 'x'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'Branding/company_logo.png in the folder Config does not match its SHA256 in SelfX.Config.json' 'installed: a changed logo is reported against SelfX.Config.json'

	# The icon rule of Install.ps1 (shortcuts) equals Get-SelfXImagePath of SelfXPaths.ps1 (window, status icon).
	. (Join-Path $PSScriptRoot 'Sources\SelfXPaths.ps1')
	$appFolder = Join-Path $installed 'App'
	$configFolder = Join-Path $installed 'Config'
	foreach ($value in 'Repair.ico', 'Branding\logo.ico', 'Branding/logo.ico', 'Languages\x.ico', '..\x.ico', 'Branding\..\..\x.ico', 'C:\Images\x.ico', '', ' ') {
		Assert-Equal "$(Resolve-SelfXInstalledImage -Value $value -AppFolder $appFolder -ConfigFolder $configFolder)" "$(Get-SelfXImagePath -Value $value -CodeRoot $appFolder)" "icon rule: '$value' resolves the same in Install.ps1 and SelfXPaths.ps1"
	}
	Assert-Equal (Resolve-SelfXInstalledImage -Value 'Branding\logo.ico' -AppFolder $appFolder -ConfigFolder $configFolder) ([IO.Path]::GetFullPath((Join-Path $configFolder 'Branding\logo.ico'))) 'icon rule: Branding\... is in Config'
	Assert-Equal (Resolve-SelfXInstalledImage -Value 'Repair.ico' -AppFolder $appFolder -ConfigFolder $configFolder) ([IO.Path]::GetFullPath((Join-Path $appFolder 'Repair.ico'))) 'icon rule: a default icon is in App'
	Assert-Equal ($null -eq (Resolve-SelfXInstalledImage -Value '..\x.ico' -AppFolder $appFolder -ConfigFolder $configFolder)) $true 'icon rule: a value that leaves its folder gives nothing'

	# The service file check covers every file type (an unlisted .exe, .dll, .json or .config in the install folder is refused):
	# there is no list of checked extensions any more (behaviour tested in Test-ServicePipe.ps1).
	$serviceSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Service\SelfXService.cs') -Raw
	Assert-Equal ($serviceSource -match 'CheckedExtensions') $false 'service: the file check has no extension filter'
	Assert-Equal ($serviceSource -match '"not listed: "') $true 'service: the file check reports unlisted files'

	# Readers of the version: nothing evaluates Tool_Version any more. The file Version.txt is the source, SelfX.Code.json carries it.
	$repository = Split-Path -Parent $PSScriptRoot
	$versionTextPath = Join-Path $PSScriptRoot 'Version.txt'
	Assert-Equal (Test-Path -LiteralPath $versionTextPath -PathType Leaf) $true 'readers: SelfX Service\Version.txt exists'
	$repositoryVersion = Get-SelfXVersionFromFile -Path $versionTextPath
	Assert-Equal ($repositoryVersion -match '^[0-9]+\.[0-9]+\.[0-9]+$') $true 'readers: Version.txt is <major>.<minor>.<patch> (the tag of a release is v<version>)'
	$detectionText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Detection.ps1'))
	Assert-Equal ($detectionText -match "\`$ExpectedVersion\s*=\s*'([^']+)'") $true 'readers: Detection.ps1 has $ExpectedVersion'
	Assert-Equal $Matches[1] $repositoryVersion 'readers: $ExpectedVersion in Detection.ps1 equals Version.txt (the packaging tool refuses a difference)'
	$toolConfigText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sources\Tool_Config.xml'))
	Assert-Equal ($toolConfigText -match '<Tool_Version[\s>]') $false 'readers: Tool_Config.xml of the repository has no Tool_Version element'
	$readerPattern = 'GUI_Config\.Tool_Version|/GUI_Config/Tool_Version|\.Tool_Version\b'
	$scanned = New-Object System.Collections.Generic.List[object]
	foreach ($folder in $PSScriptRoot, (Join-Path $repository 'tools'), (Join-Path $repository '.github')) {
		foreach ($file in @(Get-ChildItem -LiteralPath $folder -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.yml', '.cs' })) {
			# Not the programs and build leftovers, and not the two tests that name the old element on purpose.
			if ($file.FullName -match '[\\/](obj|bin|Bin)[\\/]' -or $file.Name -in 'Test-FileManifest.ps1', 'Test-Detection.ps1') { continue }
			$scanned.Add($file)
		}
	}
	Assert-Equal ($scanned.Count -gt 20) $true 'readers: the scan covers the scripts, the tools and the workflows'
	foreach ($file in $scanned) {
		$hits = @(Select-String -LiteralPath $file.FullName -Pattern $readerPattern)
		Assert-Equal $hits.Count 0 "readers: $($file.FullName.Substring($repository.Length + 1)) does not read Tool_Version"
	}
	# The texts of the wizard name Version.txt for an update, not the old element.
	foreach ($wizardText in @(Get-ChildItem -LiteralPath (Join-Path $repository 'tools\Wizard') -Filter '*.xml' -File)) {
		Assert-Equal ([IO.File]::ReadAllText($wizardText.FullName).Contains('Tool_Version')) $false "readers: $($wizardText.Name) does not name Tool_Version"
	}
	$releaseText = [IO.File]::ReadAllText((Join-Path $repository '.github\workflows\release.yml'))
	Assert-Equal ($releaseText.Contains('SelfX Service/Version.txt')) $true 'readers: release.yml compares the tag with Version.txt'
	Assert-Equal ($releaseText.Contains('Tool_Config.xml')) $false 'readers: release.yml does not read Tool_Config.xml'
	# The pattern of a version is the same text in Install.ps1, Detection.ps1, Self_X.ps1 and the package tools.
	$versionPattern = [regex]::Escape('^[0-9A-Za-z.\-]{1,30}\z')
	foreach ($copy in @(@('Install.ps1', 'Install.ps1'), @('Detection.ps1', 'Detection.ps1'), @('Self_X.ps1', 'Sources\Self_X.ps1'), @('SelfXPackage.Common.ps1', '..\tools\SelfXPackage.Common.ps1'))) {
		Assert-Equal ([IO.File]::ReadAllText((Join-Path $PSScriptRoot $copy[1])) -match $versionPattern) $true "readers: $($copy[0]) has the version pattern"
	}
}
finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } }

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
