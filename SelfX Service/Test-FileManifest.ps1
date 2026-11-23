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
    Version : 2.8.1
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.1    2026-11-23  fubu2k               Initial version (security review finding N4).
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

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXFileManifestTest_' + [guid]::NewGuid().ToString('N'))
$pristine = Join-Path $root 'pristine'
$package = Join-Path $root 'package'
function Reset-Package {
	if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Recurse -Force }
	Copy-Item -LiteralPath $pristine -Destination $package -Recurse
}
try {
	New-Item -ItemType Directory -Path $pristine -Force | Out-Null
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Destination (Join-Path $pristine 'Sources') -Recurse
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $pristine
	$expectedCount = @(Get-ChildItem -LiteralPath $pristine -Recurse -File).Count

	# The generator lists every installed file and the check accepts the result.
	$count = New-SelfXFileManifest -Stage $pristine -Version '9.9.9'
	Assert-Equal $count $expectedCount 'generator: every file of Sources and Uninstall.ps1 is listed'
	$manifest = Get-Content -LiteralPath (Join-Path $pristine 'SelfX.Files.json') -Raw | ConvertFrom-Json
	Assert-Equal $manifest.ManifestVersion 1 'manifest: format 1'
	Assert-Equal $manifest.ToolVersion '9.9.9' 'manifest: version'
	foreach ($name in 'Uninstall.ps1', 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'Self_X.ps1', 'Scripts_to_run/SelfX_Device_SyncTime.ps1') {
		Assert-Equal ($null -ne $manifest.Files.$name) $true "manifest lists $name"
	}
	Assert-Equal ($null -eq $manifest.Files.'SelfX.Files.json') $true 'manifest does not list itself'
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
	Reset-Package; Remove-Item -LiteralPath (Join-Path $package 'SelfX.Files.json')
	Assert-Equal ($null -eq (Test-SelfXFileManifest -PackageFolder $package)) $true 'check: a package without the list is reported as not checked'
}
finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } }

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
