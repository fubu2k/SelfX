<#
.SYNOPSIS
    Tests the check of the prebuilt programs (.NET 10) of Install.ps1 (finding F9).

.DESCRIPTION
    Takes the function Test-SelfXPrebuiltBinaries out of Install.ps1 (the script itself is never run: it would
    install SelfX) and runs it against a fake package in a temporary folder. Nothing is built or installed.
    Checked: a complete, matching Bin is accepted; a missing Bin folder, a missing file, a changed file, a changed
    source, a broken or missing manifest, an unknown manifest format and the manifest format of the old
    on-device compiler (version 1) are refused.
    Windows PowerShell 5.1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-InstallBinaries.ps1

.NOTES
    Name    : Test-InstallBinaries.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 2.7.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.11   2026-11-22  fubu2k               Initial version (security review finding F9).
    2.7.0    2026-11-22  fubu2k               .NET 10: manifest format 2, Bin is required; the test of the compiler TEMP was removed.
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}

# Load only the one function, never the rest of Install.ps1.
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install.ps1'), [ref]$tokens, [ref]$parseErrors)
Assert-Equal @($parseErrors).Count 0 'Install.ps1 parses'
foreach ($name in 'Test-SelfXPrebuiltBinaries', 'Test-SelfXPowerShell7') {
	$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }.GetNewClosure(), $true)
	Assert-Equal ($null -ne $definition) $true "Install.ps1 defines $name"
	if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
	. ([scriptblock]::Create($definition.Extent.Text))
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXInstallBinariesTest_' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $root 'package'
$bin = Join-Path $package 'Bin'
$files = [ordered]@{
	'SelfXService.exe'        = 'Service/SelfXService.cs'
	'SelfX.exe'               = 'Service/SelfXLauncher.cs'
	'SelfXSessionStarter.dll' = 'Service/SelfXSessionStarter.cs'
	'WinRT/SelfXWinRT.dll'    = 'Service/SelfXWinRT.cs'
}

function Reset-Package {
	# A complete, consistent fake package: sources, programs and manifest.
	if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Recurse -Force }
	New-Item -ItemType Directory -Path (Join-Path $package 'Service'), $bin -Force | Out-Null
	$sources = [ordered]@{}
	$binaries = [ordered]@{}
	foreach ($name in $files.Keys) {
		$sourcePath = Join-Path $package ($files[$name].Replace('/', '\'))
		[IO.File]::WriteAllText($sourcePath, "// source of $name")
		$binaryPath = Join-Path $bin $name.Replace('/', '\')
		New-Item -ItemType Directory -Path (Split-Path -Parent $binaryPath) -Force | Out-Null
		[IO.File]::WriteAllText($binaryPath, "binary $name")
		$sources[$files[$name]] = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
		$binaries[$name] = (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash
	}
	$manifest = [ordered]@{ ManifestVersion = 3; ToolVersion = 'test'; BuiltUtc = ''; Sources = $sources; Binaries = $binaries }
	[IO.File]::WriteAllText((Join-Path $bin 'SelfX.Binaries.json'), ($manifest | ConvertTo-Json -Depth 4))
}

function Test-Accepted {
	try { Test-SelfXPrebuiltBinaries -BinFolder $bin -PackageFolder $package; return 'accepted' }
	catch { return 'refused: ' + $_.Exception.Message }
}

try {
	Reset-Package
	Assert-Equal (Test-Accepted) 'accepted' 'Complete, matching Bin is accepted'

	Reset-Package
	Remove-Item -LiteralPath (Join-Path $bin 'SelfX.exe')
	Assert-Equal ((Test-Accepted) -like 'refused*') $true 'Missing program is refused'

	Reset-Package
	Remove-Item -LiteralPath (Join-Path $bin 'SelfX.Binaries.json')
	Assert-Equal ((Test-Accepted) -like 'refused*') $true 'Missing manifest is refused'

	Reset-Package
	[IO.File]::WriteAllText((Join-Path $bin 'SelfX.Binaries.json'), '{ not json')
	Assert-Equal ((Test-Accepted) -like 'refused*') $true 'Broken manifest is refused'

	Reset-Package
	[IO.File]::WriteAllText((Join-Path $bin 'SelfXService.exe'), 'replaced')
	Assert-Equal ((Test-Accepted) -like 'refused*SHA256*') $true 'Changed program is refused'

	Reset-Package
	[IO.File]::WriteAllText((Join-Path $package 'Service\SelfXService.cs'), '// changed source')
	Assert-Equal ((Test-Accepted) -like 'refused*not built from*') $true 'Program built from other sources is refused'

	Reset-Package
	[IO.File]::WriteAllText((Join-Path $bin 'SelfX.Binaries.json'), '{ "ManifestVersion": 4, "Sources": {}, "Binaries": {} }')
	Assert-Equal ((Test-Accepted) -like 'refused*unknown format*') $true 'Unknown manifest format is refused'

	Reset-Package
	$manifestPath = Join-Path $bin 'SelfX.Binaries.json'
	$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
	$manifest.ManifestVersion = 1
	[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4))
	Assert-Equal ((Test-Accepted) -like 'refused*unknown format*') $true 'Manifest of the old on-device build (version 1) is refused'
	$manifest.ManifestVersion = 2
	[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4))
	Assert-Equal ((Test-Accepted) -like 'refused*unknown format*') $true 'Manifest without the WinRT library (version 2) is refused'

	# --- WinRT library: its DLLs are checked one by one, nothing else may be listed ---
	Reset-Package
	$extra = Join-Path $bin 'WinRT\Projection.dll'
	[IO.File]::WriteAllText($extra, 'projection')
	$manifestPath = Join-Path $bin 'SelfX.Binaries.json'
	$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
	$manifest.Binaries | Add-Member -NotePropertyName 'WinRT/Projection.dll' -NotePropertyValue (Get-FileHash -LiteralPath $extra -Algorithm SHA256).Hash
	[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4))
	Assert-Equal (Test-Accepted) 'accepted' 'An additional DLL in WinRT is accepted when it matches the manifest'
	[IO.File]::WriteAllText($extra, 'changed projection')
	Assert-Equal ((Test-Accepted) -like 'refused*Projection.dll does not match*') $true 'A changed DLL in WinRT is refused'
	Remove-Item -LiteralPath $extra -Force
	Assert-Equal ((Test-Accepted) -like 'refused*Projection.dll is missing*') $true 'A missing DLL in WinRT is refused'
	$manifest.Binaries | Add-Member -NotePropertyName '..\..\evil.dll' -NotePropertyValue 'AA' -Force
	$manifest.Binaries.PSObject.Properties.Remove('WinRT/Projection.dll')
	[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4))
	Assert-Equal ((Test-Accepted) -like 'refused*unexpected file*') $true 'A manifest entry outside WinRT is refused'

	Reset-Package
	Remove-Item -LiteralPath $bin -Recurse -Force
	Assert-Equal ((Test-Accepted) -like 'refused*folder Bin is missing*') $true 'Missing Bin folder is refused'

	Reset-Package
	$manifestPath = Join-Path $bin 'SelfX.Binaries.json'
	$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
	$manifest.Binaries.'SelfX.exe' = ''
	[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4))
	Assert-Equal ((Test-Accepted) -like 'refused*SHA256*') $true 'Empty hash in the manifest is refused'
	# --- PowerShell 7 prerequisite (fixed path, minimum version, folder not writable by normal users) ---
	$ps7Folder = Join-Path $root 'ps7'
	New-Item -ItemType Directory -Path $ps7Folder -Force | Out-Null
	$fakeExe = Join-Path $ps7Folder 'pwsh.exe'
	# cmd.exe is a signed system program with a known version: a stand-in for a version check.
	Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination $fakeExe
	$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
	# Only SYSTEM, administrators and the current user: the same as an installation below Program Files.
	& icacls.exe $ps7Folder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "*$($currentUser):(OI)(CI)F" | Out-Null
	function Test-PowerShell7Result {
		param([string]$Path, [string]$Minimum = '7.6.0')
		# accepted = ready; not ready = missing or too old (the installation goes on with a warning); refused = unsafe rights (stops).
		try { $check = Test-SelfXPowerShell7 -Executable $Path -MinimumVersion $Minimum; if ($check.Ready) { return 'accepted' } else { return 'not ready: ' + $check.Reason } }
		catch { return 'refused: ' + $_.Exception.Message }
	}
	Assert-Equal (Test-PowerShell7Result $fakeExe '1.0.0') 'accepted' 'PowerShell 7 check accepts a protected folder with a new enough version'
	Assert-Equal ((Test-PowerShell7Result (Join-Path $ps7Folder 'missing.exe')) -like 'not ready*was not found*') $true 'Missing pwsh.exe: not ready, installation goes on (Autopilot)'
	Assert-Equal ((Test-PowerShell7Result $fakeExe '99.0.0') -like 'not ready*version 99.0.0 or newer is required*') $true 'Too old version: not ready, installation goes on (Autopilot)'
	& icacls.exe $ps7Folder /grant '*S-1-5-32-545:(OI)(CI)M' | Out-Null
	Assert-Equal ((Test-PowerShell7Result $fakeExe '1.0.0') -like 'refused*can be changed by normal users*') $true 'Folder that Users can change is refused'
	& icacls.exe $ps7Folder /remove:g '*S-1-5-32-545' | Out-Null
	& icacls.exe $ps7Folder /grant '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
	Assert-Equal (Test-PowerShell7Result $fakeExe '1.0.0') 'accepted' 'Users may read and run the folder'

}
finally {
	Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
