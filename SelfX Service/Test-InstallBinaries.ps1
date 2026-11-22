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
    Version : 2.8.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.11   2026-11-22  fubu2k               Initial version (security review finding F9).
    2.7.0    2026-11-22  fubu2k               .NET 10: manifest format 2, Bin is required; the test of the compiler TEMP was removed.
    2.8.0    2026-11-22  fubu2k               Manifest format 3 (WinRT files), PowerShell 7 and Windows build checks.
    2.8.0    2026-11-22  fubu2k               Checks of Initialize-SelfXDataFolder (security review finding F12).
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
foreach ($name in 'Test-SelfXPrebuiltBinaries', 'Test-SelfXPowerShell7', 'Test-SelfXWindowsBuild', 'Initialize-SelfXDataFolder') {
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

	# Windows 11 25H2 (build 26200) is the minimum; older builds stop the installation (hard abort).
	function Test-WindowsBuildResult {
		param([int]$Build)
		try { return "accepted $(Test-SelfXWindowsBuild -Build $Build)" } catch { return 'refused: ' + $_.Exception.Message }
	}
	Assert-Equal (Test-WindowsBuildResult 26200) 'accepted 26200' 'Windows 11 25H2 (build 26200) is accepted'
	Assert-Equal (Test-WindowsBuildResult 26300) 'accepted 26300' 'A newer build is accepted'
	Assert-Equal ((Test-WindowsBuildResult 26199) -like 'refused*Windows build 26199 is not supported*') $true 'Build 26199 is refused'
	Assert-Equal ((Test-WindowsBuildResult 26100) -like 'refused*25H2*') $true 'Windows 11 24H2 (build 26100) is refused'
	Assert-Equal ((Test-WindowsBuildResult 19045) -like 'refused*') $true 'Windows 10 is refused'
	$readBuild = Test-SelfXWindowsBuild -MinimumBuild 1
	Assert-Equal ($readBuild -is [int] -and $readBuild -gt 0) $true 'The build number of this computer is read from the registry'
	$installText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Install.ps1'))
	Assert-Equal ($installText.IndexOf('$null = Test-SelfXWindowsBuild') -ge 0 -and $installText.IndexOf('$null = Test-SelfXWindowsBuild') -lt $installText.IndexOf('New-Item -ItemType Directory -Path $LogFolder')) $true 'The build check runs before the installer changes anything'

# Initialize-SelfXDataFolder (finding F12): links and foreign-owned entries in ProgramData\SelfX are removed, owner and
# rights are set again. Needs administrator rights (icacls /setowner); without them these checks are skipped.
$isAdminTest = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdminTest) { Write-Output 'Skipped: Initialize-SelfXDataFolder checks need administrator rights.' }
else {
	$dataTest = Join-Path $root 'DataTests'
	function New-TestJunction($Link, $Target) { $null = & cmd.exe /c mklink /J "`"$Link`"" "`"$Target`"" 2>&1; if ($LASTEXITCODE -ne 0) { throw "mklink failed for '$Link'." } }
	function Get-TestOwner($Path) { (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value }

	# 1. A folder that does not exist is created; owner = Administrators, only SYSTEM and Administrators have explicit rights.
	$data1 = Join-Path $dataTest 'new\SelfX'
	New-Item -ItemType Directory -Path (Split-Path -Parent $data1) -Force | Out-Null
	Initialize-SelfXDataFolder -Path $data1
	Assert-Equal (Test-Path -LiteralPath $data1 -PathType Container) $true 'data folder is created'
	Assert-Equal (Get-TestOwner $data1) 'S-1-5-32-544' 'data folder: owner is Administrators'
	$rules = @((Get-Acl -LiteralPath $data1).Access)
	Assert-Equal (@($rules | Where-Object { $_.IsInherited }).Count) 0 'data folder: no inherited rights'
	Assert-Equal (@($rules | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } | Sort-Object -Unique) -join ',') 'S-1-5-18,S-1-5-32-544' 'data folder: only SYSTEM and Administrators'

	# 2. The data folder is a junction (created in advance): the link is removed, its target stays untouched.
	$target2 = Join-Path $dataTest 'target2'
	New-Item -ItemType Directory -Path $target2 -Force | Out-Null
	Set-Content -LiteralPath (Join-Path $target2 'keep.txt') -Value 'x'
	$acl2Before = (Get-Acl -LiteralPath $target2).Sddl
	$data2 = Join-Path $dataTest 'junction\SelfX'
	New-Item -ItemType Directory -Path (Split-Path -Parent $data2) -Force | Out-Null
	New-TestJunction $data2 $target2
	Initialize-SelfXDataFolder -Path $data2
	Assert-Equal (([IO.File]::GetAttributes($data2) -band [IO.FileAttributes]::ReparsePoint) -eq 0) $true 'junction as data folder: replaced by a real folder'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $target2 'keep.txt')) $true 'junction as data folder: target content is kept'
	Assert-Equal ((Get-Acl -LiteralPath $target2).Sddl) $acl2Before 'junction as data folder: rights of the target are unchanged'

	# 3. A link below the data folder (Logs\evil) is removed, its target stays; a folder and a file that are not owned by a trusted
	#    owner are deleted; the user area Logs\Users is not entered; owned by a trusted owner: kept.
	$target3 = Join-Path $dataTest 'target3'
	New-Item -ItemType Directory -Path $target3 -Force | Out-Null
	Set-Content -LiteralPath (Join-Path $target3 'keep.txt') -Value 'x'
	$data3 = Join-Path $dataTest 'tree\SelfX'
	New-Item -ItemType Directory -Path (Join-Path $data3 'Logs\Users\S-1-5-21-1-2-3-1001'), (Join-Path $data3 'Cache'), (Join-Path $data3 'Reports\S-1-5-21-1-2-3-1001') -Force | Out-Null
	New-TestJunction (Join-Path $data3 'Logs\evil') $target3
	Set-Content -LiteralPath (Join-Path $data3 'Logs\Users\S-1-5-21-1-2-3-1001\user.log') -Value 'x'
	Set-Content -LiteralPath (Join-Path $data3 'Cache\Health.json') -Value '{}'
	Set-Content -LiteralPath (Join-Path $data3 'Reports\S-1-5-21-1-2-3-1001\r.txt') -Value 'x'
	Initialize-SelfXDataFolder -Path $data3
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Logs\evil')) $false 'link below the data folder: removed'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $target3 'keep.txt')) $true 'link below the data folder: target content is kept'
	# Files created by an elevated administrator belong to the group Administrators (trusted); otherwise this check does not apply.
	if ((Get-TestOwner (Join-Path $data3 'Cache\Health.json')) -in 'S-1-5-18', 'S-1-5-32-544') {
		Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Cache\Health.json')) $true 'trusted owner (default list): file is kept'
		Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Reports\S-1-5-21-1-2-3-1001\r.txt')) $true 'trusted owner (default list): nested file is kept'
	}
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Logs\Users\S-1-5-21-1-2-3-1001\user.log')) $true 'user area: content is kept'

	# 4. With a list that does not contain the owner of the test files, all of them count as foreign (also Logs, with the user
	#    area below it) and are deleted; the data folder itself is kept.
	$ownerFile = Get-TestOwner (Join-Path $data3 'Cache\Health.json')
	Initialize-SelfXDataFolder -Path $data3 -TrustedOwnerSids @('S-1-5-18-test-no-match')
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Cache')) $false "foreign-owned folder (owner $ownerFile): deleted"
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Reports')) $false 'foreign-owned folder with content: deleted'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Logs')) $false 'foreign-owned Logs folder: deleted'
	Assert-Equal (Test-Path -LiteralPath $data3 -PathType Container) $true 'data folder itself is kept (owner and rights are set again)'
	Assert-Equal (Get-TestOwner $data3) 'S-1-5-32-544' 'data folder after cleaning: owner is Administrators'
}
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
