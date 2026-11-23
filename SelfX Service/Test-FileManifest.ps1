<#
.SYNOPSIS
    Tests SelfX.Files.json: the hash list of all installed files (security review finding N4).

.DESCRIPTION
    Takes New-SelfXFileManifest out of tools\New-SelfXIntuneWin.ps1 and Test-SelfXFileManifest out of Install.ps1 (the
    scripts themselves are never run) and runs them against a copy of the real Sources folder in a temporary folder.
    Checked: the generator lists every file and the check accepts the result; a changed file, an extra file (also in
    Scripts_to_run), a missing file, a changed Uninstall.ps1, a broken JSON, an unknown format and names with a path
    traversal are refused; a package without the file is reported as not checked. Nothing is installed.
    Windows PowerShell 5.1 or PowerShell 7: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-FileManifest.ps1

.NOTES
    Name    : Test-FileManifest.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 2.8.3
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.1    2026-11-23  fubu2k               Initial version (security review finding N4).
    2.8.2    2026-11-23  fubu2k               Also the DLLs of Bin\WinRT (WinRT load check).
    2.8.3    2026-11-23  fubu2k               Also SelfXService.exe and SelfX.exe from Bin, the check of the installed folder after copying
                                              (Test-SelfXInstalledFiles) and the .exe entry of the service file check.
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
. ([scriptblock]::Create((Get-FunctionText (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\New-SelfXIntuneWin.ps1') 'New-SelfXFileManifest')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $PSScriptRoot 'Install.ps1') 'Test-SelfXFileManifest')))
. ([scriptblock]::Create((Get-FunctionText (Join-Path $PSScriptRoot 'Install.ps1') 'Test-SelfXInstalledFiles')))

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXFileManifestTest_' + [guid]::NewGuid().ToString('N'))
$pristine = Join-Path $root 'pristine'
$package = Join-Path $root 'package'
function Reset-Package {
	if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Recurse -Force }
	Copy-Item -LiteralPath $pristine -Destination $package -Recurse
}
# What Install.ps1 does: Sources\* and Uninstall.ps1 and SelfX.Files.json to the root, the programs from Bin to the root,
# the DLLs from Bin\WinRT to WinRT.
$installed = Join-Path $root 'installed'
function New-InstalledCopy {
	if (Test-Path -LiteralPath $installed) { Remove-Item -LiteralPath $installed -Recurse -Force }
	New-Item -ItemType Directory -Path $installed -Force | Out-Null
	Copy-Item -Path (Join-Path $pristine 'Sources\*') -Destination $installed -Recurse
	foreach ($name in 'Uninstall.ps1', 'SelfX.Files.json') { Copy-Item -LiteralPath (Join-Path $pristine $name) -Destination $installed }
	foreach ($name in 'SelfXService.exe', 'SelfX.exe') { Copy-Item -LiteralPath (Join-Path $pristine "Bin\$name") -Destination $installed }
	Copy-Item -LiteralPath (Join-Path $pristine 'Bin\WinRT') -Destination (Join-Path $installed 'WinRT') -Recurse
}
try {
	New-Item -ItemType Directory -Path $pristine -Force | Out-Null
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Destination (Join-Path $pristine 'Sources') -Recurse
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $pristine
	# Stand-ins for the DLLs of Bin\WinRT (the real ones are built on the build machine); only their bytes matter here.
	New-Item -ItemType Directory -Path (Join-Path $pristine 'Bin\WinRT') -Force | Out-Null
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\WinRT\SelfXWinRT.dll'), [byte[]](1, 2, 3, 4))
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\WinRT\Microsoft.Windows.SDK.NET.dll'), [byte[]](5, 6, 7, 8))
	# Stand-ins for the two programs of Bin (service and starter).
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\SelfXService.exe'), [byte[]](9, 10, 11, 12))
	[IO.File]::WriteAllBytes((Join-Path $pristine 'Bin\SelfX.exe'), [byte[]](13, 14, 15, 16))
	$expectedCount = @(Get-ChildItem -LiteralPath $pristine -Recurse -File).Count

	# The generator lists every installed file and the check accepts the result.
	$count = New-SelfXFileManifest -Stage $pristine -Version '9.9.9'
	Assert-Equal $count $expectedCount 'generator: every file of Sources, Uninstall.ps1, Bin\WinRT and the two programs is listed'
	$manifest = Get-Content -LiteralPath (Join-Path $pristine 'SelfX.Files.json') -Raw | ConvertFrom-Json
	Assert-Equal $manifest.ManifestVersion 1 'manifest: format 1'
	Assert-Equal $manifest.ToolVersion '9.9.9' 'manifest: version'
	foreach ($name in 'Uninstall.ps1', 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'Self_X.ps1', 'Scripts_to_run/SelfX_Device_SyncTime.ps1') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "manifest lists $name"
	}
	Assert-Equal ($null -eq $manifest.Files.'SelfX.Files.json') $true 'manifest does not list itself'
	foreach ($name in 'WinRT/SelfXWinRT.dll', 'WinRT/Microsoft.Windows.SDK.NET.dll') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "manifest lists $name"
	}
	foreach ($name in 'SelfXService.exe', 'SelfX.exe') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "manifest lists $name"
		Assert-Equal $manifest.Files.$name (Get-FileHash -LiteralPath (Join-Path $pristine "Bin\$name") -Algorithm SHA256).Hash "manifest: SHA256 of $name"
	}
	Assert-Equal $manifest.Files.'WinRT/SelfXWinRT.dll' (Get-FileHash -LiteralPath (Join-Path $pristine 'Bin\WinRT\SelfXWinRT.dll') -Algorithm SHA256).Hash 'manifest: SHA256 of the WinRT library'
	# SelfX.Files.json is in the package folder, not in Sources: it must not count as an extra file.
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $pristine) ($count) 'check: the unchanged package is accepted'

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
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'SelfX.Files.json') -Value '{ not json'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'not valid JSON' 'check: broken JSON is refused'
	Reset-Package; Set-Content -LiteralPath (Join-Path $package 'SelfX.Files.json') -Value '{"ManifestVersion":2,"Files":{"Uninstall.ps1":"00"}}'
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'unknown format' 'check: an unknown format is refused'
	foreach ($bad in '../Install.ps1', 'a/../../b.ps1', 'C:/Windows/x.ps1', '/etc/x', 'a//b.ps1', '.hidden/..') {
		Reset-Package
		$json = [ordered]@{ ManifestVersion = 1; Files = [ordered]@{ $bad = 'AA' } } | ConvertTo-Json
		Set-Content -LiteralPath (Join-Path $package 'SelfX.Files.json') -Value $json
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'unsupported name' "check: the name '$bad' is refused"
	}
	Reset-Package; $manifest = Get-Content -LiteralPath (Join-Path $package 'SelfX.Files.json') -Raw | ConvertFrom-Json
	$files = [ordered]@{}; foreach ($property in $manifest.Files.PSObject.Properties) { if ($property.Name -ne 'Uninstall.ps1') { $files[$property.Name] = $property.Value } }
	Set-Content -LiteralPath (Join-Path $package 'SelfX.Files.json') -Value ([ordered]@{ ManifestVersion = 1; Files = $files } | ConvertTo-Json)
	Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } 'Uninstall.ps1 is not listed' 'check: a list without Uninstall.ps1 is refused'
	foreach ($program in 'SelfXService.exe', 'SelfX.exe') {
		Reset-Package; $manifest = Get-Content -LiteralPath (Join-Path $package 'SelfX.Files.json') -Raw | ConvertFrom-Json
		$files = [ordered]@{}; foreach ($property in $manifest.Files.PSObject.Properties) { if ($property.Name -ne $program) { $files[$property.Name] = $property.Value } }
		Set-Content -LiteralPath (Join-Path $package 'SelfX.Files.json') -Value ([ordered]@{ ManifestVersion = 1; Files = $files } | ConvertTo-Json)
		Assert-Throws { Test-SelfXFileManifest -PackageFolder $package } "$([regex]::Escape($program)) is not listed" "check: a list without $program is refused"
	}
	Reset-Package; Remove-Item -LiteralPath (Join-Path $package 'SelfX.Files.json')
	Assert-Equal ($null -eq (Test-SelfXFileManifest -PackageFolder $package)) $true 'check: a package without the list is reported as not checked'

	# The generator refuses a package without one of the programs.
	foreach ($program in 'SelfXService.exe', 'SelfX.exe') {
		Reset-Package; Remove-Item -LiteralPath (Join-Path $package "Bin\$program")
		Assert-Throws { New-SelfXFileManifest -Stage $package -Version '9.9.9' } "Bin\\$([regex]::Escape($program)) is missing" "generator: a package without $program is refused"
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
	New-InstalledCopy; Remove-Item -LiteralPath (Join-Path $installed 'SelfX.Files.json')
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'SelfX.Files.json is missing' 'installed: a missing list is refused'
	New-InstalledCopy; Set-Content -LiteralPath (Join-Path $installed 'SelfX.Files.json') -Value '{ not json'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'not valid JSON' 'installed: a broken list is refused'
	New-InstalledCopy; Set-Content -LiteralPath (Join-Path $installed 'SelfX.Files.json') -Value '{"ManifestVersion":2,"Files":{"Uninstall.ps1":"00"}}'
	Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'unknown format' 'installed: an unknown list format is refused'
	foreach ($bad in '../Install.ps1', 'a/../../b.ps1', 'C:/Windows/x.ps1', 'a//b.ps1') {
		New-InstalledCopy
		Set-Content -LiteralPath (Join-Path $installed 'SelfX.Files.json') -Value ([ordered]@{ ManifestVersion = 1; Files = [ordered]@{ $bad = 'AA' } } | ConvertTo-Json)
		Assert-Throws { Test-SelfXInstalledFiles -InstallFolder $installed } 'unsupported name' "installed: the name '$bad' is refused"
	}

	# The service file check covers .exe (an unlisted program in the install folder is refused).
	$serviceSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Service\SelfXService.cs') -Raw
	Assert-Equal ($serviceSource -match 'CheckedExtensions\s*=\s*\{[^}]*"\.exe"[^}]*\}') $true 'service: the file check covers .exe'
}
finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } }

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
