<#
.SYNOPSIS
    Tests SelfX.Code.json and SelfX.Config.json: the two hash lists of all installed files.

.DESCRIPTION
    Loads tools\SelfXPackage.Common.ps1 (functions only) and takes Test-SelfXFileManifest, Test-SelfXInstalledFiles,
    Read-SelfXFileList and Test-SelfXListPlacement out of Install.ps1 (the script itself is never run) and runs them against
    a copy of the real Sources folder in a temporary folder.
    Checked: every file of the repository has a class and the name list of the project equals the repository; the generator
    lists every file in exactly one list and the check accepts the result; a changed logo of the company changes only
    SelfX.Config.json (SelfX.Code.json stays byte-identical); a changed file, an extra file (also in Scripts_to_run), a missing
    file, a changed Uninstall.ps1, a file in both lists, a settings file in the code list, a program in the configuration list,
    a broken JSON, an unknown format and names with a path traversal are refused; a package without the lists is reported as
    not checked. Nothing is installed.
    Windows PowerShell 5.1 or PowerShell 7: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-FileManifest.ps1

.NOTES
    Name    : Test-FileManifest.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 2.9.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.1    2026-11-23  fubu2k               Initial version.
    2.8.19   2026-11-23  fubu2k               Also SelfXService.exe and SelfX.exe, the check of the installed folder after copying
                                              and the .exe entry of the service file check.
    2.9.0    2026-11-27  fubu2k               Two lists (SelfX.Code.json, SelfX.Config.json) by file class; logo test, placement and
                                              class tests, negative tests for a file in both lists, in none and in the wrong list.
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
foreach ($name in 'Test-SelfXListPlacement', 'Read-SelfXFileList', 'Test-SelfXFileManifest', 'Test-SelfXInstalledFiles') {
	. ([scriptblock]::Create((Get-FunctionText (Join-Path $PSScriptRoot 'Install.ps1') $name)))
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXFileManifestTest_' + [guid]::NewGuid().ToString('N'))
$pristine = Join-Path $root 'pristine'
$package = Join-Path $root 'package'
function Reset-Package {
	if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Recurse -Force }
	Copy-Item -LiteralPath $pristine -Destination $package -Recurse
}
# Writes a list file of the package (or of the installed folder) from a name -> hash table.
function Set-List([string]$Path, $Files, $Version = 1) {
	Set-Content -LiteralPath $Path -Value ([ordered]@{ ManifestVersion = $Version; Files = $Files } | ConvertTo-Json)
}
function Get-ListFiles([string]$Path) {
	$list = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
	$files = [ordered]@{}; foreach ($property in $list.Files.PSObject.Properties) { $files[$property.Name] = $property.Value }
	return $files
}
# What Install.ps1 does: Sources\* and Uninstall.ps1 and the two lists to the root, the programs from Bin to the root,
# the DLLs from Bin\WinRT to WinRT and from Bin\Audio to Audio.
$installed = Join-Path $root 'installed'
function New-InstalledCopy {
	if (Test-Path -LiteralPath $installed) { Remove-Item -LiteralPath $installed -Recurse -Force }
	New-Item -ItemType Directory -Path $installed -Force | Out-Null
	Copy-Item -Path (Join-Path $pristine 'Sources\*') -Destination $installed -Recurse
	foreach ($name in 'Uninstall.ps1', 'SelfX.Code.json', 'SelfX.Config.json') { Copy-Item -LiteralPath (Join-Path $pristine $name) -Destination $installed }
	foreach ($name in 'SelfXService.exe', 'SelfX.exe') { Copy-Item -LiteralPath (Join-Path $pristine "Bin\$name") -Destination $installed }
	Copy-Item -LiteralPath (Join-Path $pristine 'Bin\WinRT') -Destination (Join-Path $installed 'WinRT') -Recurse
	Copy-Item -LiteralPath (Join-Path $pristine 'Bin\Audio') -Destination (Join-Path $installed 'Audio') -Recurse
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
	# Stand-ins for the two programs of Bin (service and starter).
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\SelfXService.exe'), [byte[]](17, 18, 19, 20))
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\SelfX.exe'), [byte[]](21, 22, 23, 24))
	$expectedCount = @(Get-ChildItem -LiteralPath $pristine -Recurse -File).Count

	# Every file of the repository has a class, and the name list of the project equals the files of the repository.
	$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Recurse -File | ForEach-Object { $_.FullName.Substring((Join-Path $PSScriptRoot 'Sources').Length + 1).Replace('\', '/') })
	foreach ($name in $sourceFiles) {
		$class = Get-SelfXFileClass -Name $name
		$expectedClass = if (($script:SelfXConfigFileNames -contains $name) -or $name -like 'Branding/*') { 'Config' } else { 'Code' }
		Assert-Equal $class $expectedClass "class: $name"
		if ($expectedClass -eq 'Code') { Assert-Equal ($script:SelfXCodeFileNames -ccontains $name) $true "name list of the project contains $name" }
	}
	$fromSources = @($script:SelfXCodeFileNames | Where-Object { $_ -notin 'Uninstall.ps1', 'SelfXService.exe', 'SelfX.exe', 'Audio/SelfXAudio.dll' })
	foreach ($name in $fromSources) { Assert-Equal ($sourceFiles -ccontains $name) $true "name list of the project: $name exists in Sources" }
	Assert-Equal @($script:SelfXCodeFileNames | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1).Count 0 'name list of the project has no duplicates'
	foreach ($case in @(@('Branding/company_logo.png', 'Config'), @('Branding/a/b.xml', 'Config'), @('Tool_Config.xml', 'Config'), @('WinRT/Some.Library.dll', 'Code'), @('Scripts_to_run/Own_Action.ps1', 'Config'), @('HealthChecks/Own-Check.ps1', 'Config'), @('Languages/de-AT.xml', 'Config'))) {
		Assert-Equal (Get-SelfXFileClass -Name $case[0]) $case[1] "class: $($case[0])"
	}
	foreach ($bad in 'Extra.dll', 'Evil.ps1', 'Sources/Self_X.ps1', 'Scripts_to_run/sub/Own.ps1', 'Languages/xx_yy.xml', 'Bin/SelfX.exe', '../Install.ps1', 'a//b.ps1', 'Branding/../Self_X.ps1') {
		Assert-Throws { Get-SelfXFileClass -Name $bad } 'belongs to no file class|Unsupported file name' "class: '$bad' is refused (fail closed)"
	}
	# The placement rules of the generator and of Install.ps1 give the same answer for every name.
	$placementNames = @($script:SelfXCodeFileNames) + $script:SelfXConfigFileNames + @('Branding/x.png', 'Branding/', 'Scripts_to_run/Own.ps1', 'Scripts_to_run/Own.exe', 'Scripts_to_run/a/b.ps1', 'HealthChecks/Own-Check.ps1', 'Languages/it.xml', 'Languages/it-CH.xml', 'Languages/x.ps1', 'WinRT/A.dll', 'Evil.ps1', '../x', 'a/../b', 'C:/x')
	foreach ($name in $placementNames) {
		foreach ($list in 'Code', 'Config') {
			Assert-Equal (Test-SelfXListPlacement -Name $name -List $list) (Common_Test-SelfXListPlacement -Name $name -List $list) "placement of '$name' in $list is the same in Install.ps1 and the generator"
		}
	}
	Assert-Equal (Test-SelfXListPlacement -Name 'SelfXService.exe' -List 'Config') $false 'placement: a program must not be in the configuration list'
	Assert-Equal (Test-SelfXListPlacement -Name 'Tool_Config.xml' -List 'Code') $false 'placement: a settings file must not be in the code list'
	# The service has the same rule: the names of the settings files and the two patterns are the same text.
	$serviceText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Service\SelfXService.cs') -Raw
	$serviceNames = [regex]::Match($serviceText, 'ConfigFileNames = \{([^}]*)\}').Groups[1].Value
	Assert-Equal (([regex]::Matches($serviceNames, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object) -join ',') (($script:SelfXConfigFileNames | Sort-Object) -join ',') 'service: the settings files are the same as in the generator'
	Assert-Equal $serviceText.Contains('^(Scripts_to_run|HealthChecks)/[A-Za-z0-9._-]+\.ps1\z') $true 'service: same pattern for own scripts'
	Assert-Equal $serviceText.Contains('^Languages/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml\z') $true 'service: same pattern for own language files'

	# The generator lists every installed file in exactly one list and the check accepts the result.
	$codeCount = New-SelfXCodeManifest -Stage $pristine -Version '9.9.9'
	$configCount = New-SelfXConfigManifest -Stage $pristine
	$count = $codeCount + $configCount
	Assert-Equal $count $expectedCount 'generator: every file of Sources, Uninstall.ps1, Bin\WinRT, Bin\Audio and the two programs is listed in one of the two lists'
	$manifest = Get-Content -LiteralPath (Join-Path $pristine 'SelfX.Code.json') -Raw | ConvertFrom-Json
	$configManifest = Get-Content -LiteralPath (Join-Path $pristine 'SelfX.Config.json') -Raw | ConvertFrom-Json
	Assert-Equal $manifest.ManifestVersion 1 'code list: format 1'
	Assert-Equal $configManifest.ManifestVersion 1 'configuration list: format 1'
	Assert-Equal $manifest.ToolVersion '9.9.9' 'code list: version'
	Assert-Equal ($null -eq $manifest.BuiltUtc) $true 'code list: no build time (same contents give the same bytes)'
	Assert-Equal ($null -ne $configManifest.BuiltUtc) $true 'configuration list: build time'
	foreach ($name in 'Uninstall.ps1', 'Self_X.ps1', 'Scripts_to_run/SelfX_Device_SyncTime.ps1', 'Languages/de.xml', 'logo.png', 'HealthChecks/Check-Compliance.ps1') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "code list contains $name"
		Assert-Equal ($null -eq $configManifest.Files.$name) $true "configuration list does not contain $name"
	}
	foreach ($name in 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'Ticket_Config.xml', 'Network_Test_Config.xml', 'Branding/company_logo.png') {
		Assert-Equal ($null -ne $configManifest.Files.$name) $true "configuration list contains $name"
		Assert-Equal ($null -eq $manifest.Files.$name) $true "code list does not contain $name"
	}
	foreach ($listName in 'SelfX.Code.json', 'SelfX.Config.json') { Assert-Equal ($null -eq $manifest.Files.$listName -and $null -eq $configManifest.Files.$listName) $true "no list contains $listName" }
	foreach ($name in 'WinRT/SelfXWinRT.dll', 'WinRT/Microsoft.Windows.SDK.NET.dll', 'Audio/SelfXAudio.dll') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "code list contains $name"
	}
	foreach ($name in 'SelfXService.exe', 'SelfX.exe') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "code list contains $name"
		Assert-Equal $manifest.Files.$name (Get-FileHash -LiteralPath (Join-Path $pristine "Bin\$name") -Algorithm SHA256).Hash "code list: SHA256 of $name"
	}
	Assert-Equal $manifest.Files.'WinRT/SelfXWinRT.dll' (Get-FileHash -LiteralPath (Join-Path $pristine 'Bin\WinRT\SelfXWinRT.dll') -Algorithm SHA256).Hash 'code list: SHA256 of the WinRT library'
	Assert-Equal $manifest.Files.'Audio/SelfXAudio.dll' (Get-FileHash -LiteralPath (Join-Path $pristine 'Bin\Audio\SelfXAudio.dll') -Algorithm SHA256).Hash 'code list: SHA256 of the audio library'
	# The lists are in the package folder, not in Sources: they must not count as extra files.
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $pristine) ($count) 'check: the unchanged package is accepted'

	# A changed logo of the company changes only SelfX.Config.json and the configuration digest; SelfX.Code.json stays byte-identical.
	$logoStage = Join-Path $root 'logo'
	Copy-Item -LiteralPath $pristine -Destination $logoStage -Recurse
	Remove-Item -LiteralPath (Join-Path $logoStage 'SelfX.Code.json'), (Join-Path $logoStage 'SelfX.Config.json')
	[IO.File]::WriteAllBytes((Join-Path $logoStage 'Sources\Branding\company_logo.png'), [byte[]](1, 1, 1, 1, 1))
	[void](New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9'); [void](New-SelfXConfigManifest -Stage $logoStage)
	$codeBefore = [IO.File]::ReadAllBytes((Join-Path $logoStage 'SelfX.Code.json'))
	$configBefore = [IO.File]::ReadAllBytes((Join-Path $logoStage 'SelfX.Config.json'))
	$codeDigestBefore = Get-SelfXListDigest -Stage $logoStage -ListName 'SelfX.Code.json'
	$configDigestBefore = Get-SelfXListDigest -Stage $logoStage -ListName 'SelfX.Config.json'
	[IO.File]::WriteAllBytes((Join-Path $logoStage 'Sources\Branding\company_logo.png'), [byte[]](2, 2, 2, 2, 2))
	Start-Sleep -Seconds 1
	[void](New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9'); [void](New-SelfXConfigManifest -Stage $logoStage)
	Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $logoStage 'SelfX.Code.json'))) -ceq [Convert]::ToBase64String($codeBefore)) $true 'logo changed: SelfX.Code.json is byte-identical'
	Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $logoStage 'SelfX.Config.json'))) -ceq [Convert]::ToBase64String($configBefore)) $false 'logo changed: SelfX.Config.json changes'
	Assert-Equal (Get-SelfXListDigest -Stage $logoStage -ListName 'SelfX.Code.json') $codeDigestBefore 'logo changed: the code digest stays'
	Assert-Equal ((Get-SelfXListDigest -Stage $logoStage -ListName 'SelfX.Config.json') -ne $configDigestBefore) $true 'logo changed: the configuration digest changes'
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $logoStage) $count 'logo changed: the new package is accepted'
	# The same package built twice gives the same code list (no build time in it).
	Start-Sleep -Seconds 1
	[void](New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9')
	Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $logoStage 'SelfX.Code.json'))) -ceq [Convert]::ToBase64String($codeBefore)) $true 'rebuilt: SelfX.Code.json is byte-identical'
	# An own script of the company is Code for nobody: it goes into SelfX.Config.json and the check accepts it.
	[IO.File]::WriteAllText((Join-Path $logoStage 'Sources\Scripts_to_run\Own_Action.ps1'), 'Write-Output 1')
	[void](New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9'); [void](New-SelfXConfigManifest -Stage $logoStage)
	Assert-Equal ($null -ne (Get-ListFiles (Join-Path $logoStage 'SelfX.Config.json'))['Scripts_to_run/Own_Action.ps1']) $true 'own script: listed in SelfX.Config.json'
	Assert-Equal ($null -eq (Get-ListFiles (Join-Path $logoStage 'SelfX.Code.json'))['Scripts_to_run/Own_Action.ps1']) $true 'own script: not in SelfX.Code.json'
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $logoStage) ($count + 1) 'own script: the package is accepted'
	# A file that no rule knows stops the generator (fail closed).
	[IO.File]::WriteAllText((Join-Path $logoStage 'Sources\Unknown.dll'), 'x')
	Assert-Throws { New-SelfXCodeManifest -Stage $logoStage -Version '9.9.9' } 'belongs to no file class' 'generator: an unknown file stops the build'
	Assert-Throws { New-SelfXConfigManifest -Stage $logoStage } 'belongs to no file class' 'generator: an unknown file stops the build (configuration list)'
	Remove-Item -LiteralPath $logoStage -Recurse -Force

	Reset-Package
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $package) $count 'check: a copy of the package is accepted'

	# Tampering is refused before anything is installed.
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'Sources\Scripts_to_run\SelfX_Device_SyncTime.ps1') -Value '# changed'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'does not match its SHA256' 'check: a changed script is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'Sources\Scripts_to_run\Evil.ps1') -Value 'calc.exe'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'not listed' 'check: an extra script in Scripts_to_run is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'Sources\Extra.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'not listed' 'check: an extra file in Sources is refused'
	Reset-Package; Remove-Item -LiteralPath (Join-Path $package 'Sources\Issues_List.xml')
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'missing in the package' 'check: a missing file is refused'
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'Bin\WinRT\SelfXWinRT.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'WinRT/SelfXWinRT.dll does not match its SHA256' 'check: a changed WinRT library is refused'
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'Bin\Audio\SelfXAudio.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Audio/SelfXAudio.dll does not match its SHA256' 'check: a changed audio library is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'Bin\Audio\Extra.dll') -Value 'x'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Audio/Extra.dll is in the package but not listed' 'check: an extra audio file is refused'
	Reset-Package; Remove-Item -LiteralPath (Join-Path $package 'Bin\Audio\SelfXAudio.dll')
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'missing in the package' 'check: a missing audio library is refused'
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
	Reset-Package; Add-Content -LiteralPath (Join-Path $package 'Sources\Health_Config.xml') -Value '<!-- changed -->'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'does not match its SHA256' 'check: a changed catalog configuration is refused'

	# A broken or unexpected list is refused, a missing list is reported.
	foreach ($listName in 'SelfX.Code.json', 'SelfX.Config.json') {
		Reset-Package; Set-Content -LiteralPath (Join-Path $package $listName) -Value '{ not json'
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'not valid JSON' "check: broken JSON in $listName is refused"
		Reset-Package; Set-Content -LiteralPath (Join-Path $package $listName) -Value '{"ManifestVersion":2,"Files":{"Uninstall.ps1":"00"}}'
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'unknown format' "check: an unknown format in $listName is refused"
		foreach ($bad in '../Install.ps1', 'a/../../b.ps1', 'C:/Windows/x.ps1', '/etc/x', 'a//b.ps1', '.hidden/..') {
			Reset-Package
			Set-List (Join-Path $package $listName) ([ordered]@{ $bad = 'AA' })
			Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'unsupported name' "check: the name '$bad' in $listName is refused"
		}
		Reset-Package; Remove-Item -LiteralPath (Join-Path $package $listName)
		$other = if ($listName -eq 'SelfX.Code.json') { 'SelfX.Config.json' } else { 'SelfX.Code.json' }
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } "$([regex]::Escape($listName)) is missing in the package" "check: a package with only $other is refused"
	}
	# A list without Uninstall.ps1 or without one of the programs is refused.
	foreach ($missing in 'Uninstall.ps1', 'SelfXService.exe', 'SelfX.exe') {
		Reset-Package; $files = Get-ListFiles (Join-Path $package 'SelfX.Code.json'); $files.Remove($missing)
		Set-List (Join-Path $package 'SelfX.Code.json') $files
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } "$([regex]::Escape($missing)) is not listed" "check: a code list without $missing is refused"
	}
	# A file in both lists, a file in none, and a file in the wrong list are refused.
	Reset-Package; $codeFiles = Get-ListFiles (Join-Path $package 'SelfX.Code.json'); $configFiles = Get-ListFiles (Join-Path $package 'SelfX.Config.json')
	$configFiles['Scripts_to_run/SelfX_Device_SyncTime.ps1'] = $codeFiles['Scripts_to_run/SelfX_Device_SyncTime.ps1']
	Set-List (Join-Path $package 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'listed in both SelfX.Code.json and SelfX.Config.json' 'check: a file in both lists is refused'
	Reset-Package; $codeFiles = Get-ListFiles (Join-Path $package 'SelfX.Code.json'); $codeFiles.Remove('Self_X.ps1')
	Set-List (Join-Path $package 'SelfX.Code.json') $codeFiles
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Self_X.ps1 is in the package but not listed' 'check: a file in no list is refused'
	Reset-Package; $codeFiles = Get-ListFiles (Join-Path $package 'SelfX.Code.json'); $configFiles = Get-ListFiles (Join-Path $package 'SelfX.Config.json')
	$codeFiles['Tool_Config.xml'] = $configFiles['Tool_Config.xml']; $configFiles.Remove('Tool_Config.xml')
	Set-List (Join-Path $package 'SelfX.Code.json') $codeFiles; Set-List (Join-Path $package 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Tool_Config.xml must not be listed in SelfX.Code.json' 'check: a settings file in the code list is refused'
	Reset-Package; $codeFiles = Get-ListFiles (Join-Path $package 'SelfX.Code.json'); $configFiles = Get-ListFiles (Join-Path $package 'SelfX.Config.json')
	$configFiles['Branding/company_logo.png'] = $configFiles['Branding/company_logo.png']; $codeFiles['Branding/company_logo.png'] = $configFiles['Branding/company_logo.png']; $configFiles.Remove('Branding/company_logo.png')
	Set-List (Join-Path $package 'SelfX.Code.json') $codeFiles; Set-List (Join-Path $package 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Branding/company_logo.png must not be listed in SelfX.Code.json' 'check: a file of Branding in the code list is refused'
	foreach ($moved in 'SelfXService.exe', 'Uninstall.ps1', 'Self_X.ps1', 'logo.png', 'WinRT/SelfXWinRT.dll', 'Languages/de.xml/../x') {
		Reset-Package; $codeFiles = Get-ListFiles (Join-Path $package 'SelfX.Code.json'); $configFiles = Get-ListFiles (Join-Path $package 'SelfX.Config.json')
		if ($codeFiles.Contains($moved)) { $configFiles[$moved] = $codeFiles[$moved]; $codeFiles.Remove($moved) } else { $configFiles[$moved] = 'AA' }
		Set-List (Join-Path $package 'SelfX.Code.json') $codeFiles; Set-List (Join-Path $package 'SelfX.Config.json') $configFiles
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'must not be listed in SelfX.Config.json|unsupported name' "check: '$moved' in the configuration list is refused"
	}
	Reset-Package; $files = Get-ListFiles (Join-Path $package 'SelfX.Code.json'); $files['Extra.dll'] = 'AA'
	Set-List (Join-Path $package 'SelfX.Code.json') $files
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Extra.dll is listed in SelfX.Code.json but missing in the package' 'check: a listed file that is not in the package is refused'
	Reset-Package; Remove-Item -LiteralPath (Join-Path $package 'SelfX.Code.json'), (Join-Path $package 'SelfX.Config.json')
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
		New-InstalledCopy; [IO.File]::WriteAllBytes((Join-Path $installed $program), [byte[]](99, 99))
		Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } "$([regex]::Escape($program)) in the installation folder does not match" "installed: a changed $program is refused"
		New-InstalledCopy; Remove-Item -LiteralPath (Join-Path $installed $program)
		Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } "$([regex]::Escape($program)) is missing in the installation folder" "installed: a missing $program is refused"
	}
	New-InstalledCopy; Add-Content -LiteralPath (Join-Path $installed 'Scripts_to_run\SelfX_Device_SyncTime.ps1') -Value '# changed'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'does not match its SHA256' 'installed: a changed script is refused'
	New-InstalledCopy; Add-Content -LiteralPath (Join-Path $installed 'WinRT\SelfXWinRT.dll') -Value 'x'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'WinRT/SelfXWinRT.dll in the installation folder does not match' 'installed: a changed WinRT library is refused'
	New-InstalledCopy; Remove-Item -LiteralPath (Join-Path $installed 'Issues_List.xml')
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'Issues_List.xml is missing in the installation folder' 'installed: a missing configuration file is refused'
	New-InstalledCopy; Remove-Item -LiteralPath (Join-Path $installed 'SelfX.Config.json')
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'SelfX.Config.json is missing' 'installed: a missing list is refused'
	New-InstalledCopy; Remove-Item -LiteralPath (Join-Path $installed 'SelfX.Code.json')
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'SelfX.Code.json is missing' 'installed: a missing code list is refused'
	foreach ($listName in 'SelfX.Code.json', 'SelfX.Config.json') {
		New-InstalledCopy; Set-Content -LiteralPath (Join-Path $installed $listName) -Value '{ not json'
		Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'not valid JSON' "installed: a broken $listName is refused"
		New-InstalledCopy; Set-Content -LiteralPath (Join-Path $installed $listName) -Value '{"ManifestVersion":2,"Files":{"Uninstall.ps1":"00"}}'
		Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'unknown format' "installed: an unknown format of $listName is refused"
		foreach ($bad in '../Install.ps1', 'a/../../b.ps1', 'C:/Windows/x.ps1', 'a//b.ps1') {
			New-InstalledCopy
			Set-List (Join-Path $installed $listName) ([ordered]@{ $bad = 'AA' })
			Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'unsupported name' "installed: the name '$bad' in $listName is refused"
		}
	}
	New-InstalledCopy; $configFiles = Get-ListFiles (Join-Path $installed 'SelfX.Config.json'); $codeFiles = Get-ListFiles (Join-Path $installed 'SelfX.Code.json')
	$configFiles['Self_X.ps1'] = $codeFiles['Self_X.ps1']
	Set-List (Join-Path $installed 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'Self_X.ps1 must not be listed in SelfX.Config.json' 'installed: a project script in the configuration list is refused'
	New-InstalledCopy; $configFiles = Get-ListFiles (Join-Path $installed 'SelfX.Config.json'); $codeFiles = Get-ListFiles (Join-Path $installed 'SelfX.Code.json')
	$configFiles['Scripts_to_run/SelfX_Device_SyncTime.ps1'] = $codeFiles['Scripts_to_run/SelfX_Device_SyncTime.ps1']
	Set-List (Join-Path $installed 'SelfX.Config.json') $configFiles
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'listed in both SelfX.Code.json and SelfX.Config.json' 'installed: a file in both lists is refused'
	New-InstalledCopy; Add-Content -LiteralPath (Join-Path $installed 'Branding\company_logo.png') -Value 'x'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'Branding/company_logo.png in the installation folder does not match its SHA256 in SelfX.Config.json' 'installed: a changed logo is reported against SelfX.Config.json'

	# The service file check covers every file type (an unlisted .exe, .dll, .json or .config in the install folder is refused):
	# there is no list of checked extensions any more (behaviour tested in Test-ServicePipe.ps1).
	$serviceSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Service\SelfXService.cs') -Raw
	Assert-Equal ($serviceSource -match 'CheckedExtensions') $false 'service: the file check has no extension filter'
	Assert-Equal ($serviceSource -match '"not listed: "') $true 'service: the file check reports unlisted files'
}
finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } }

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
