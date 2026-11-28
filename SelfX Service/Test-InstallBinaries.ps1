<#
.SYNOPSIS
    Tests the check of the prebuilt programs (.NET 10) of Install.ps1.

.DESCRIPTION
    Takes the function Test-SelfXPrebuiltBinaries out of Install.ps1 (the script itself is never run: it would
    install SelfX) and runs it against a fake package in a temporary folder. Nothing is built or installed.
    Checked: a complete, matching Bin is accepted; a missing Bin folder, a missing file, a changed file, a changed
    source, a broken or missing manifest, an unknown manifest format and the manifest format of the old
    on-device compiler (version 1) are refused. The copy step (Clear-SelfXInstallFolder, Copy-SelfXPayload, Test-SelfXInstalledFiles)
    is run against a package in the layout App/Config and an install folder in the old layout (update 3.0.2 -> 3.1.0).
    Trust mode Signature: the functions for -TrustedSigner, the mode and the downgrade check, the signatures and the two signed
    catalogs of the package and the trust anchor are taken out of Install.ps1. Part 1 replaces Get-AuthenticodeSignature and
    Test-FileCatalog by functions of this test; the anchor is written to a test key below HKCU\Software (removed at the end).
    Part 2 signs a small package with self-signed test certificates of the current user and needs two of them as trusted roots
    (Cert:\LocalMachine\Root with administrator rights, otherwise Cert:\CurrentUser\Root, where Windows asks for confirmation): it
    runs in CI or with SELFX_TEST_ALLOW_ROOT_IMPORT=1 and removes the certificates at the end.
    Windows PowerShell 5.1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-InstallBinaries.ps1

.NOTES
    Name    : Test-InstallBinaries.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.11   2026-11-22  fubu2k               Initial version.
    2.8.18   2026-11-23  fubu2k               Audio library (Audio/SelfXAudio.dll) in the fake package and its refusal cases.
    2.8.21   2026-11-23  fubu2k               N4: the check returns the verified hashes (Install.ps1 loads SelfXSessionStarter.dll from checked bytes).
    3.1.0    2026-11-27  fubu2k               Layout App/Config: update from the old layout (3.0.2) and from the new layout, mixed state, empty left-over
                                              folder, locked file, package in the old layout, paths of service, starter, shortcut and uninstall entry.
    3.1.0    2026-11-27  fubu2k               Trust mode Signature: list of -TrustedSigner, mode and downgrade, signatures and both catalogs of the package
                                              (replaced cmdlets and, with a trusted test root, real certificates), copy step, trust anchor in a test key.
    3.1.0    2026-11-27  fubu2k               Trust mode Signature: both catalogs are installed next to their lists and compared after the copy; no
                                              catalog in the mode Hash
    3.1.0    2026-11-28  fubu2k               Windows check: Windows 11 25H2 and Windows Server 2022/2025 with Desktop Experience are accepted; Server Core,
                                              a domain controller, Windows Enterprise multi-session and unreadable values are refused
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
foreach ($name in 'Test-SelfXPrebuiltBinaries', 'Test-SelfXPowerShell7', 'Get-SelfXWindowsInfo', 'Test-SelfXWindowsSupport', 'Invoke-SelfXSafeDelete', 'Initialize-SelfXDataFolder', 'Get-SelfXServicePrivileges', 'Set-SelfXServicePrivileges') {
	$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }.GetNewClosure(), $true)
	Assert-Equal ($null -ne $definition) $true "Install.ps1 defines $name"
	if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
	. ([scriptblock]::Create($definition.Extent.Text))
}

# Privileges of the service: a fixed list; the strong LocalSystem privileges must not be in it.
$privileges = @(Get-SelfXServicePrivileges)
Assert-Equal ($privileges.Count -ge 5) $true 'N5: the privilege list is not empty'
Assert-Equal (@($privileges | Where-Object { $_ -notmatch '^Se[A-Za-z]+Privilege$' }).Count) 0 'N5: all entries are privilege names'
Assert-Equal (@($privileges | Select-Object -Unique).Count) $privileges.Count 'N5: no duplicate privilege'
foreach ($required in 'SeChangeNotifyPrivilege', 'SeImpersonatePrivilege', 'SeCreateGlobalPrivilege') { Assert-Equal ($privileges -contains $required) $true "N5: $required is kept (the service needs it)" }
foreach ($forbidden in 'SeTcbPrivilege', 'SeDebugPrivilege', 'SeCreateTokenPrivilege', 'SeLoadDriverPrivilege', 'SeSecurityPrivilege', 'SeAuditPrivilege', 'SeSystemEnvironmentPrivilege', 'SeCreatePermanentPrivilege', 'SeLockMemoryPrivilege') {
	Assert-Equal ($privileges -contains $forbidden) $false "N5: $forbidden is removed from the service"
}
Assert-Equal ("$(Set-SelfXServicePrivileges -Name 'SelfXTestNoSuchService' -Mode 'Default')" -like 'Default*') $true 'N5: Service_Privileges = Default leaves the privileges unchanged (no sc.exe call)'

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXInstallBinariesTest_' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $root 'package'
$bin = Join-Path $package 'Bin'
$files = [ordered]@{
	'SelfXService.exe'        = 'Service/SelfXService.cs'
	'SelfX.exe'               = 'Service/SelfXLauncher.cs'
	'SelfXSessionStarter.dll' = 'Service/SelfXSessionStarter.cs'
	'WinRT/SelfXWinRT.dll'    = 'Service/SelfXWinRT.cs'
	'Audio/SelfXAudio.dll'    = 'Service/SelfXAudio.cs'
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
	try { $null = Test-SelfXPrebuiltBinaries -BinFolder $bin -PackageFolder $package; return 'accepted' }
	catch { return 'refused: ' + $_.Exception.Message }
}

try {
	Reset-Package
	Assert-Equal (Test-Accepted) 'accepted' 'Complete, matching Bin is accepted'

	# N4: the check returns the verified hashes; Install.ps1 compares the bytes of SelfXSessionStarter.dll with this value before loading them.
	Reset-Package
	$verified = Test-SelfXPrebuiltBinaries -BinFolder $bin -PackageFolder $package
	Assert-Equal $verified['SelfXSessionStarter.dll'] (Get-FileHash -LiteralPath (Join-Path $bin 'SelfXSessionStarter.dll') -Algorithm SHA256).Hash 'N4: the check returns the verified SHA256 of SelfXSessionStarter.dll'
	Assert-Equal $verified.Count 5 'N4: the check returns one hash per checked file'

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

	# --- Audio library: expected like the programs, nothing else may be listed below Audio ---
	Reset-Package
	Remove-Item -LiteralPath (Join-Path $bin 'Audio\SelfXAudio.dll')
	Assert-Equal ((Test-Accepted) -like 'refused*Audio/SelfXAudio.dll is missing*') $true 'A missing audio library is refused'
	Reset-Package
	[IO.File]::WriteAllText((Join-Path $bin 'Audio\SelfXAudio.dll'), 'replaced')
	Assert-Equal ((Test-Accepted) -like 'refused*Audio/SelfXAudio.dll does not match*') $true 'A changed audio library is refused'
	Reset-Package
	[IO.File]::WriteAllText((Join-Path $package 'Service\SelfXAudio.cs'), '// changed source')
	Assert-Equal ((Test-Accepted) -like 'refused*not built from*SelfXAudio.cs*') $true 'An audio library built from other sources is refused'
	Reset-Package
	$extraAudio = Join-Path $bin 'Audio\Other.dll'
	[IO.File]::WriteAllText($extraAudio, 'other')
	$manifestPath = Join-Path $bin 'SelfX.Binaries.json'
	$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
	$manifest.Binaries | Add-Member -NotePropertyName 'Audio/Other.dll' -NotePropertyValue (Get-FileHash -LiteralPath $extraAudio -Algorithm SHA256).Hash
	[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4))
	Assert-Equal ((Test-Accepted) -like 'refused*unexpected file*Audio/Other.dll*') $true 'An additional file listed below Audio is refused'

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
		# The test folder lies below %TEMP%: the folders above are not judged (StopBefore) and the current user counts as trusted.
		try { $check = Test-SelfXPowerShell7 -Executable $Path -MinimumVersion $Minimum -StopBefore $root -TrustedSids @('S-1-5-18', 'S-1-5-32-544', $currentUser); if ($check.Ready) { return 'accepted' } else { return 'not ready: ' + $check.Reason } }
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
	# Not only Users: Everyone (S-1-1-0), Authenticated Users (S-1-5-11) and any other identity that may write are refused.
	foreach ($group in @('S-1-1-0', 'S-1-5-11', 'S-1-5-4', 'S-1-5-32-547')) {
		& icacls.exe $ps7Folder /grant "*$($group):(OI)(CI)W" | Out-Null
		Assert-Equal ((Test-PowerShell7Result $fakeExe '1.0.0') -like 'refused*can be changed by normal users*') $true "Write for $group on the folder is refused"
		& icacls.exe $ps7Folder /remove:g "*$group" | Out-Null
	}
	# pwsh.exe itself: Modify for Everyone only on the file.
	& icacls.exe $fakeExe /grant '*S-1-1-0:M' | Out-Null
	Assert-Equal ((Test-PowerShell7Result $fakeExe '1.0.0') -like 'refused*can be changed by normal users*') $true 'Everyone may change pwsh.exe: refused'
	& icacls.exe $fakeExe /remove:g '*S-1-1-0' | Out-Null
	# The folder above (Program Files\PowerShell): whoever may delete or take over it can replace the folder below. The folder
	# 'ps7' lies in $root; $root itself is the checked "parent" here (StopBefore = the folder above it).
	& icacls.exe $root /grant '*S-1-1-0:(DC)' | Out-Null
	$parentCheck = try { $null = Test-SelfXPowerShell7 -Executable $fakeExe -MinimumVersion '1.0.0' -StopBefore (Split-Path -Parent $root) -TrustedSids @('S-1-5-18', 'S-1-5-32-544', $currentUser); 'accepted' } catch { 'refused: ' + $_.Exception.Message }
	Assert-Equal ($parentCheck -like 'refused*can be changed by normal users*') $true 'Everyone may delete subfolders of the folder above: refused'
	& icacls.exe $root /remove:g '*S-1-1-0' | Out-Null
	Assert-Equal (Test-PowerShell7Result $fakeExe '1.0.0') 'accepted' 'After removing the extra rights the folder is accepted again'

	# Windows 11 25H2 (build 26200) and Windows Server 2022 or 2025 with Desktop Experience (build 20348) are the minimum; everything else
	# stops the installation (hard abort): older builds, Server Core, a domain controller, Windows Enterprise multi-session, unreadable values.
	function Test-WindowsSupportResult {
		param([int]$Build, [string]$ProductType, [string]$InstallationType = '', [string]$EditionId = '', [int]$ServerGuiShell = 0)
		$info = [pscustomobject]@{ Build = $Build; ProductType = $ProductType; InstallationType = $InstallationType; EditionId = $EditionId; ServerGuiShell = $ServerGuiShell }
		try { $result = Test-SelfXWindowsSupport -Info $info; return "accepted $($result.Kind) $($result.Build)" } catch { return 'refused: ' + $_.Exception.Message }
	}
	Assert-Equal (Test-WindowsSupportResult 26200 'WinNT' 'Client' 'Enterprise') 'accepted Client 26200' 'Windows 11 25H2 (build 26200) is accepted'
	Assert-Equal (Test-WindowsSupportResult 26300 'WinNT' 'Client' 'Professional') 'accepted Client 26300' 'A newer Windows 11 build is accepted'
	Assert-Equal ((Test-WindowsSupportResult 26199 'WinNT' 'Client' 'Enterprise') -like 'refused*Windows build 26199 is not supported*') $true 'Build 26199 is refused'
	Assert-Equal ((Test-WindowsSupportResult 26100 'WinNT' 'Client' 'Enterprise') -like 'refused*25H2*') $true 'Windows 11 24H2 (build 26100) is refused'
	Assert-Equal ((Test-WindowsSupportResult 19045 'WinNT' 'Client' 'Enterprise') -like 'refused*') $true 'Windows 10 is refused'
	Assert-Equal (Test-WindowsSupportResult 20348 'ServerNT' 'Server' 'ServerDatacenter' 1) 'accepted Server 20348' 'Windows Server 2022 with Desktop Experience is accepted'
	Assert-Equal (Test-WindowsSupportResult 26100 'ServerNT' 'Server' 'ServerStandard' 1) 'accepted Server 26100' 'Windows Server 2025 with Desktop Experience is accepted'
	Assert-Equal ((Test-WindowsSupportResult 17763 'ServerNT' 'Server' 'ServerStandard' 1) -like 'refused*Windows Server build 17763 is not supported*') $true 'Windows Server 2019 is refused'
	Assert-Equal ((Test-WindowsSupportResult 20348 'ServerNT' 'Server Core' 'ServerDatacenter' 0) -like 'refused*Server Core*') $true 'Windows Server Core is refused'
	Assert-Equal ((Test-WindowsSupportResult 26100 'ServerNT' 'Server' 'ServerStandard' 0) -like 'refused*Server Core*') $true 'A server without the desktop (no ServerGuiShell) is refused'
	Assert-Equal ((Test-WindowsSupportResult 26200 'ServerNT' 'Client' 'ServerRdsh') -like 'refused*multi-session*') $true 'Windows Enterprise multi-session (product type of a server) is refused'
	Assert-Equal ((Test-WindowsSupportResult 26200 'WinNT' 'Client' 'ServerRdsh') -like 'refused*multi-session*') $true 'Windows Enterprise multi-session is refused for any product type'
	Assert-Equal ((Test-WindowsSupportResult 26200 'ServerNT' 'Client' 'Enterprise') -like 'refused*installation type*') $true 'A server product type with another installation type is refused'
	Assert-Equal ((Test-WindowsSupportResult 20348 'LanmanNT' 'Server' 'ServerDatacenter' 1) -like 'refused*domain controller*') $true 'A domain controller is refused'
	Assert-Equal ((Test-WindowsSupportResult 26200 '' 'Client' 'Enterprise') -like 'refused*product type of Windows cannot be read*') $true 'A product type that cannot be read is refused'
	Assert-Equal ((Test-WindowsSupportResult 26200 'Other' 'Client' 'Enterprise') -like "refused*product type 'Other'*") $true 'An unknown product type is refused'
	Assert-Equal ((Test-WindowsSupportResult 0 'WinNT' 'Client' 'Enterprise') -like 'refused*build number cannot be read*') $true 'A build that cannot be read is refused'
	Assert-Equal (Test-WindowsSupportResult 26200 'winnt' 'Client' 'Enterprise') 'accepted Client 26200' 'The product type is compared without case'
	# The facts of this computer are read from the registry (the result is not judged: the CI runs on Windows Server).
	$readInfo = Get-SelfXWindowsInfo
	Assert-Equal ($readInfo.Build -is [int] -and $readInfo.Build -gt 0 -and @('WinNT', 'ServerNT', 'LanmanNT') -contains $readInfo.ProductType) $true "The build number and the product type of this computer are read from the registry ($($readInfo.ProductType) $($readInfo.Build))"
	$installText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Install.ps1'))
	Assert-Equal ($installText.IndexOf('$SelfXWindows = Test-SelfXWindowsSupport') -ge 0 -and $installText.IndexOf('$SelfXWindows = Test-SelfXWindowsSupport') -lt $installText.IndexOf('New-Item -ItemType Directory -Path $LogFolder')) $true 'The check of Windows runs before the installer changes anything'

# Initialize-SelfXDataFolder: links and foreign-owned entries in ProgramData\SelfX are removed, owner and
# rights are set again. Needs administrator rights (icacls /setowner); without them these checks are skipped.
$isAdminTest = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# The delete helper is SelfXService.exe of the build (Bin of the package, or SELFX_TEST_SAFEDELETE_EXE).
$safeExe = $env:SELFX_TEST_SAFEDELETE_EXE
if (-not $safeExe) { $safeExe = Join-Path $PSScriptRoot 'Bin\SelfXService.exe' }
if (-not $isAdminTest) { Write-Output 'Skipped: Initialize-SelfXDataFolder checks need administrator rights.' }
elseif (-not (Test-Path -LiteralPath $safeExe -PathType Leaf)) {
	if ($env:SELFX_REQUIRE_BIN -eq '1') { $script:errors.Add("The delete helper '$safeExe' is missing.") }
	else { Write-Output "Skipped: Initialize-SelfXDataFolder checks need the delete helper ($safeExe; build with tools\Build-SelfXBinaries.ps1)." }
}
else {
	$missingHelper = try { Invoke-SelfXSafeDelete -Exe (Join-Path $root 'missing.exe') -Arguments @('/removetree:C:\x\y'); 'no error' } catch { "$($_.Exception.Message)" }
	Assert-Equal ($missingHelper -match 'is missing') $true 'Invoke-SelfXSafeDelete: a missing helper is an error (fail closed)'
	$dataTest = Join-Path $root 'DataTests'
	function New-TestJunction($Link, $Target) { $null = & cmd.exe /c mklink /J "`"$Link`"" "`"$Target`"" 2>&1; if ($LASTEXITCODE -ne 0) { throw "mklink failed for '$Link'." } }
	function Get-TestOwner($Path) { (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value }

	# 1. A folder that does not exist is created; owner = Administrators, only SYSTEM and Administrators have explicit rights.
	$data1 = Join-Path $dataTest 'new\SelfX'
	New-Item -ItemType Directory -Path (Split-Path -Parent $data1) -Force | Out-Null
	Initialize-SelfXDataFolder -Path $data1 -SafeDeleteExe $safeExe
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
	Initialize-SelfXDataFolder -Path $data2 -SafeDeleteExe $safeExe
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
	Initialize-SelfXDataFolder -Path $data3 -SafeDeleteExe $safeExe
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
	Initialize-SelfXDataFolder -Path $data3 -SafeDeleteExe $safeExe -TrustedOwnerSids @('S-1-5-99-1')
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Cache')) $false "foreign-owned folder (owner $ownerFile): deleted"
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Reports')) $false 'foreign-owned folder with content: deleted'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data3 'Logs')) $false 'foreign-owned Logs folder: deleted'
	Assert-Equal (Test-Path -LiteralPath $data3 -PathType Container) $true 'data folder itself is kept (owner and rights are set again)'
	Assert-Equal (Get-TestOwner $data3) 'S-1-5-32-544' 'data folder after cleaning: owner is Administrators'
}
	# --- Layout App/Config (3.1.0): update from an installation in the old layout, update in the new layout, no mixed state ---
	# The functions of the copy step are taken out of Install.ps1; the package is built like tools\New-SelfXIntuneWin.ps1 does it.
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\SelfXPackage.Common.ps1')
	foreach ($name in 'Test-SelfXListPlacement', 'Read-SelfXFileList', 'Test-SelfXFileManifest', 'Get-SelfXPackageToolVersion', 'Test-SelfXInstalledFiles', 'Clear-SelfXInstallFolder', 'Copy-SelfXPayload') {
		$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }.GetNewClosure(), $true)
		Assert-Equal ($null -ne $definition) $true "Install.ps1 defines $name"
		if ($definition) { . ([scriptblock]::Create($definition.Extent.Text)) }
	}
	$layoutRoot = Join-Path $root 'layout'
	$layoutPackage = Join-Path $layoutRoot 'package'
	$layoutBin = Join-Path $layoutPackage 'Bin'
	New-Item -ItemType Directory -Path (Join-Path $layoutBin 'WinRT'), (Join-Path $layoutBin 'Audio') -Force | Out-Null
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Destination (Join-Path $layoutPackage 'Sources') -Recurse
	Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $layoutPackage
	foreach ($name in 'SelfXService.exe', 'SelfX.exe', 'WinRT\SelfXWinRT.dll', 'Audio\SelfXAudio.dll', 'SelfXSessionStarter.dll') { [IO.File]::WriteAllText((Join-Path $layoutBin $name), "binary $name") }
	[IO.File]::WriteAllText((Join-Path $layoutBin 'SelfX.Binaries.json'), '{ "ManifestVersion": 3, "Sources": {}, "Binaries": { "WinRT/SelfXWinRT.dll": "00", "Audio/SelfXAudio.dll": "00" } }')
	$sorted = ConvertTo-SelfXPackageLayout -Stage $layoutPackage
	[void](New-SelfXCodeManifest -Stage $layoutPackage -Version '3.1.0')
	[void](New-SelfXConfigManifest -Stage $layoutPackage)
	$packageCount = Test-SelfXFileManifest -PackageFolder $layoutPackage
	Assert-Equal ($packageCount -eq ($sorted.Code + $sorted.Config + 5)) $true "layout: the package lists the sorted files, Uninstall.ps1 and the four files of Bin ($packageCount)"
	Assert-Equal (Get-SelfXPackageToolVersion -PackageFolder $layoutPackage) '3.1.0' 'layout: the version comes from App\SelfX.Code.json'

	$device = Join-Path $layoutRoot 'SelfX'
	function New-OldLayout {
		# An installation of version 3.0.2: everything directly in the install folder.
		if (Test-Path -LiteralPath $device) { Remove-Item -LiteralPath $device -Recurse -Force }
		foreach ($folder in 'Scripts_to_run', 'HealthChecks', 'Branding', 'Languages', 'WinRT', 'Audio') { New-Item -ItemType Directory -Path (Join-Path $device $folder) -Force | Out-Null }
		foreach ($name in 'SelfXService.exe', 'SelfX.exe', 'Self_X.ps1', 'SelfX_Tray.ps1', 'Uninstall.ps1', 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'SelfX.Code.json', 'SelfX.Config.json', 'SelfX.Files.json',
			'Scripts_to_run\SelfX_Device_Restart.ps1', 'Scripts_to_run\Own_Old.ps1', 'HealthChecks\Check-Compliance.ps1', 'Branding\company_logo.png', 'Languages\de.xml', 'WinRT\SelfXWinRT.dll', 'Audio\SelfXAudio.dll') {
			[IO.File]::WriteAllText((Join-Path $device $name), "old $name")
		}
	}
	function Get-TopEntries { return ((@(Get-ChildItem -LiteralPath $device -Force | ForEach-Object { $_.Name }) | Sort-Object) -join ',') }

	# Update 3.0.2 -> 3.1.0: the old layout is removed completely, the new one is complete and checked.
	New-OldLayout
	Clear-SelfXInstallFolder -InstallFolder $device -Attempts 1 -DelaySeconds 0
	Assert-Equal @(Get-ChildItem -LiteralPath $device -Recurse -Force).Count 0 'old layout: the install folder is empty after the cleanup'
	Copy-SelfXPayload -PackageFolder $layoutPackage -InstallFolder $device
	Assert-Equal (Get-TopEntries) 'App,Config' 'old layout -> new: the install folder holds only App and Config'
	try { $installedCount = Test-SelfXInstalledFiles -InstallFolder $device } catch { $installedCount = "refused: $($_.Exception.Message)" }
	Assert-Equal $installedCount $packageCount 'old layout -> new: the installed folders match both lists'
	foreach ($name in 'App\SelfXService.exe', 'App\SelfX.exe', 'App\Uninstall.ps1', 'App\SelfX.Code.json', 'App\SelfXPaths.ps1', 'App\WinRT\SelfXWinRT.dll', 'App\Audio\SelfXAudio.dll', 'App\Scripts_to_run\SelfX_Device_Restart.ps1', 'Config\Tool_Config.xml', 'Config\Issues_List.xml', 'Config\SelfX.Config.json', 'Config\Branding\company_logo.png') {
		Assert-Equal (Test-Path -LiteralPath (Join-Path $device $name) -PathType Leaf) $true "old layout -> new: $name is installed"
	}
	foreach ($name in 'App\Tool_Config.xml', 'Config\Self_X.ps1', 'Config\SelfX.Code.json', 'App\SelfX.Config.json', 'App\SelfX.Files.json', 'App\Scripts_to_run\Own_Old.ps1', 'Config\Scripts_to_run\Own_Old.ps1') {
		Assert-Equal (Test-Path -LiteralPath (Join-Path $device $name)) $false "old layout -> new: $name does not exist"
	}
	# Update 3.1.0 -> 3.1.0 (new layout over new layout).
	Clear-SelfXInstallFolder -InstallFolder $device -Attempts 1 -DelaySeconds 0
	Copy-SelfXPayload -PackageFolder $layoutPackage -InstallFolder $device
	try { $installedCount = Test-SelfXInstalledFiles -InstallFolder $device } catch { $installedCount = "refused: $($_.Exception.Message)" }
	Assert-Equal $installedCount $packageCount 'new layout -> new: the installed folders match both lists'
	# Mixed state: a copy over an old layout without the cleanup is refused after the copy (fail closed).
	New-OldLayout
	Copy-SelfXPayload -PackageFolder $layoutPackage -InstallFolder $device
	try { Test-SelfXInstalledFiles -InstallFolder $device | Out-Null; $mixed = 'accepted' } catch { $mixed = $_.Exception.Message }
	Assert-Equal ($mixed -match 'left over from an older installation') $true "mixed state: files of the old layout next to App and Config are refused ($mixed)"
	# An empty folder of the old layout that is still in use (working directory) is allowed.
	Clear-SelfXInstallFolder -InstallFolder $device -Attempts 1 -DelaySeconds 0
	New-Item -ItemType Directory -Path (Join-Path $device 'Scripts_to_run') -Force | Out-Null
	Copy-SelfXPayload -PackageFolder $layoutPackage -InstallFolder $device
	try { $installedCount = Test-SelfXInstalledFiles -InstallFolder $device } catch { $installedCount = "refused: $($_.Exception.Message)" }
	Assert-Equal $installedCount $packageCount 'empty folder of the old layout: accepted'
	# A locked file of the old layout stops the installation before the copy.
	New-OldLayout
	$lock = [IO.File]::Open((Join-Path $device 'Scripts_to_run\SelfX_Device_Restart.ps1'), 'Open', 'Read', 'None')
	try {
		try { Clear-SelfXInstallFolder -InstallFolder $device -Attempts 1 -DelaySeconds 0; $locked = 'accepted' } catch { $locked = $_.Exception.Message }
		Assert-Equal ($locked -match 'are in use and cannot be replaced') $true "locked file: the cleanup stops ($locked)"
	} finally { $lock.Dispose() }
	# A package in the old layout (Sources, lists at the top) is refused before anything is changed.
	$oldPackage = Join-Path $layoutRoot 'oldpackage'
	New-Item -ItemType Directory -Path (Join-Path $oldPackage 'Sources') -Force | Out-Null
	[IO.File]::WriteAllText((Join-Path $oldPackage 'SelfX.Code.json'), '{"ManifestVersion":1,"ToolVersion":"3.0.2","Files":{"Uninstall.ps1":"00"}}')
	try { Test-SelfXFileManifest -PackageFolder $oldPackage | Out-Null; $old = 'accepted' } catch { $old = $_.Exception.Message }
	Assert-Equal ($old -match 'old layout') $true "old package layout: refused ($old)"
	# The main part of Install.ps1 uses the layout: service, starter, shortcut, uninstall entry and status icon point into App.
	$installText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Install.ps1'))
	foreach ($expected in @('$ServiceExe = Join-Path $AppFolder ''SelfXService.exe''', '$LauncherExe = Join-Path $AppFolder ''SelfX.exe''', '$Shortcut.WorkingDirectory = $AppFolder', '$AppFolder\Uninstall.ps1', 'Clear-SelfXInstallFolder -InstallFolder $InstallFolder', 'Copy-SelfXPayload -PackageFolder $PackageFolder -InstallFolder $InstallFolder', '$InstalledFiles = Test-SelfXInstalledFiles -InstallFolder $InstallFolder')) {
		Assert-Equal $installText.Contains($expected) $true "Install.ps1 contains: $expected"
	}
	Assert-Equal ($installText -match '\[xml\]\(Get-Content') $false 'Install.ps1 reads no XML with [xml] (DTD processing is prohibited explicitly)'
	Assert-Equal ($installText.Contains('''\\(App\\)?SelfX_Tray\.ps1''')) $true 'Install.ps1 closes status icons of both layouts'
	$trayPattern = [regex]::Escape('C:\Program Files\SelfX') + '\\(App\\)?SelfX_Tray\.ps1'
	Assert-Equal ('pwsh.exe -File "C:\Program Files\SelfX\SelfX_Tray.ps1"' -match $trayPattern) $true 'tray pattern: old layout'
	Assert-Equal ('pwsh.exe -File "C:\Program Files\SelfX\App\SelfX_Tray.ps1"' -match $trayPattern) $true 'tray pattern: new layout'
	Assert-Equal ('pwsh.exe -File "C:\Program Files\SelfX\Config\SelfX_Tray.ps1"' -match $trayPattern) $false 'tray pattern: not below Config'

	# --- Trust mode Signature: -TrustedSigner, signatures of the package, signed catalogs, trust anchor, downgrade ---
	# Part 1 replaces Get-AuthenticodeSignature and Test-FileCatalog by functions of this test (a function is found before a cmdlet),
	# so every status can be produced without a certificate. Part 2 (further down) uses real test certificates.
	foreach ($name in 'ConvertTo-SelfXTrustedSignerList', 'Get-SelfXTrustAnchor', 'Resolve-SelfXTrustMode', 'Test-SelfXFileSignature', 'Test-SelfXPackageCatalog', 'Test-SelfXPackageSignatures', 'Test-SelfXInstalledLists', 'Set-SelfXTrustAnchor', 'Test-SelfXTrustAnchorState') {
		$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }.GetNewClosure(), $true)
		Assert-Equal ($null -ne $definition) $true "Install.ps1 defines $name"
		if ($definition) { . ([scriptblock]::Create($definition.Extent.Text)) }
	}
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\SelfXSigning.ps1')
	function Get-Refusal([scriptblock]$Action) { try { $null = & $Action; return 'accepted' } catch { return "$($_.Exception.Message)" } }
	$signerA = 'A' * 40
	$signerB = 'B' * 40
	$signerC = '0123456789abcdef0123456789abcdef01234567'

	# 1. The list of -TrustedSigner.
	Assert-Equal ((ConvertTo-SelfXTrustedSignerList -TrustedSigner $signerC) -join '|') $signerC.ToUpperInvariant() 'signers: one thumbprint, returned in upper case'
	Assert-Equal ((ConvertTo-SelfXTrustedSignerList -TrustedSigner "$signerA,$signerC") -join '|') "$signerA|$($signerC.ToUpperInvariant())" 'signers: "A,B" as one string (powershell.exe -File) gives two entries'
	Assert-Equal ((ConvertTo-SelfXTrustedSignerList -TrustedSigner @($signerA, $signerB)) -join '|') "$signerA|$signerB" 'signers: an array gives two entries'
	Assert-Equal ((ConvertTo-SelfXTrustedSignerList -TrustedSigner " $signerA , $signerB ") -join '|') "$signerA|$signerB" 'signers: spaces around an entry are ignored'
	Assert-Equal @(ConvertTo-SelfXTrustedSignerList -TrustedSigner @($signerA, $signerA.ToLowerInvariant(), "$signerA,$signerA")).Count 1 'signers: duplicates are removed (any case)'
	$badLists = [ordered]@{
		'empty string'               = @('')
		'empty list'                 = @()
		'39 characters'              = @('A' * 39)
		'41 characters'              = @('A' * 41)
		'not hexadecimal'            = @('G' * 40)
		'trailing comma'             = @("$signerA,")
		'space inside a thumbprint'  = @(('A' * 20) + ' ' + ('A' * 20))
		'two thumbprints with space' = @("$signerA $signerB")
		'SHA256 thumbprint'          = @('A' * 64)
		'one bad entry of two'       = @($signerA, 'xyz')
		'eleven entries'             = @(0..10 | ForEach-Object { '{0:X40}' -f $_ })
	}
	foreach ($case in $badLists.Keys) {
		$list = $badLists[$case]
		$answer = Get-Refusal { ConvertTo-SelfXTrustedSignerList -TrustedSigner $list }
		Assert-Equal ($answer -match '^-TrustedSigner') $true "signers: $case stops ($answer)"
	}
	Assert-Equal @(ConvertTo-SelfXTrustedSignerList -TrustedSigner @(0..9 | ForEach-Object { '{0:X40}' -f $_ })).Count 10 'signers: ten entries are allowed'

	# 2. The mode of the installation and the protection against a downgrade.
	foreach ($installed in '', 'Hash', 'Signature', 'Invalid') {
		Assert-Equal (Resolve-SelfXTrustMode -InstalledMode $installed -SignatureRequested $true -AllowHashMode $false) 'Signature' "mode: -TrustedSigner gives Signature (device: '$installed')"
		Assert-Equal ((Get-Refusal { Resolve-SelfXTrustMode -InstalledMode $installed -SignatureRequested $true -AllowHashMode $true }) -match 'cannot be used together') $true "mode: -TrustedSigner with -AllowHashMode stops (device: '$installed')"
	}
	Assert-Equal (Resolve-SelfXTrustMode -InstalledMode '' -SignatureRequested $false -AllowHashMode $false) 'Hash' 'mode: no anchor and no -TrustedSigner gives Hash (as before)'
	Assert-Equal (Resolve-SelfXTrustMode -InstalledMode 'Hash' -SignatureRequested $false -AllowHashMode $false) 'Hash' 'mode: Hash stays Hash'
	Assert-Equal (Resolve-SelfXTrustMode -InstalledMode '' -SignatureRequested $false -AllowHashMode $true) 'Hash' 'mode: -AllowHashMode without an anchor is harmless'
	foreach ($installed in 'Signature', 'Invalid', 'hash') {
		$answer = Get-Refusal { Resolve-SelfXTrustMode -InstalledMode $installed -SignatureRequested $false -AllowHashMode $false }
		Assert-Equal ($answer -match '-AllowHashMode' -and $answer -match 'Nothing was changed') $true "downgrade: device '$installed', no -TrustedSigner, no -AllowHashMode stops ($answer)"
		Assert-Equal (Resolve-SelfXTrustMode -InstalledMode $installed -SignatureRequested $false -AllowHashMode $true) 'Hash' "downgrade: device '$installed' with -AllowHashMode gives Hash"
	}

	# 3. Replacements for the two cmdlets. A "signature" is an entry in a table (status, thumbprint, hash of the file when it was
	#    "signed"); a "catalog" is a JSON file with the relative names and SHA256 of the files of its folder.
	$script:fakeSignatures = @{}
	$script:fakeSignatureError = ''
	$script:fakeCatalogError = $false
	function Get-FakeKey([string]$Path) { return (Get-Item -LiteralPath $Path -Force).FullName.ToLowerInvariant() }
	function Set-FakeSignature([string]$Path, [string]$Thumbprint, [string]$Status = 'Valid') {
		$script:fakeSignatures[(Get-FakeKey $Path)] = @{ Status = $Status; Thumbprint = $Thumbprint; Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
	}
	function Get-AuthenticodeSignature {
		param([string]$LiteralPath, $ErrorAction)
		if ($script:fakeSignatureError -and ($LiteralPath -like $script:fakeSignatureError)) { throw 'simulated error of Get-AuthenticodeSignature' }
		$entry = $script:fakeSignatures[(Get-FakeKey $LiteralPath)]
		if (-not $entry) { return [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
		$status = $entry.Status
		# A file changed after it was signed has the status HashMismatch, like a real signature.
		if (($status -eq 'Valid') -and ($entry.Hash -ne (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash)) { $status = 'HashMismatch' }
		$certificate = $null
		if ($entry.Thumbprint) { $certificate = [pscustomobject]@{ Thumbprint = $entry.Thumbprint } }
		return [pscustomobject]@{ Status = $status; SignerCertificate = $certificate }
	}
	function Test-FileCatalog {
		param([string]$Path, [string]$CatalogFilePath, [switch]$Detailed, [string[]]$FilesToSkip, $ErrorAction)
		if ($script:fakeCatalogError) { throw 'simulated error of Test-FileCatalog' }
		$catalog = Get-Content -LiteralPath $CatalogFilePath -Raw | ConvertFrom-Json
		$catalogItems = New-Object 'System.Collections.Generic.Dictionary[string,string]'
		foreach ($property in @($catalog.Files.PSObject.Properties)) { $catalogItems[$property.Name] = "$($property.Value)" }
		$pathItems = New-Object 'System.Collections.Generic.Dictionary[string,string]'
		$folder = (Get-Item -LiteralPath $Path -Force).FullName.TrimEnd('\')
		foreach ($file in @(Get-ChildItem -LiteralPath $folder -Recurse -File -Force)) {
			$relative = $file.FullName.Substring($folder.Length + 1)
			if ($FilesToSkip -contains $relative) { continue }
			$pathItems[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
		}
		return [pscustomobject]@{ Status = 'Valid'; HashAlgorithm = "$($catalog.HashAlgorithm)"; CatalogItems = $catalogItems; PathItems = $pathItems }
	}
	function New-FakeCatalog([string]$Folder, [string]$CatalogPath, [string]$Thumbprint, [string[]]$Skip = @(), [string]$HashName = 'SHA256', [switch]$Empty) {
		$rootFolder = (Get-Item -LiteralPath $Folder -Force).FullName.TrimEnd('\')
		$entries = [ordered]@{}
		if (-not $Empty) {
			foreach ($file in @(Get-ChildItem -LiteralPath $rootFolder -Recurse -File -Force | Sort-Object FullName)) {
				$relative = $file.FullName.Substring($rootFolder.Length + 1)
				if ($file.FullName -ieq $CatalogPath) { continue }
				if (@($Skip | Where-Object { $relative.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { continue }
				$entries[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
			}
		}
		[IO.File]::WriteAllText($CatalogPath, (([ordered]@{ HashAlgorithm = $HashName; Files = $entries }) | ConvertTo-Json -Depth 4))
		if ($Thumbprint) { Set-FakeSignature $CatalogPath $Thumbprint }
	}
	$signedPackage = Join-Path $root 'signed\package'
	$configCatalog = Join-Path $signedPackage 'Config\SelfX.Config.cat'
	$codeCatalog = Join-Path $signedPackage 'SelfX.Code.cat'
	function New-SignedPackage([string]$Signer = $signerA, [switch]$Full) {
		# A small package with the names the cases below use (default) or, with -Full, the package of the layout tests with all scripts
		# of the project; plus Install.ps1, Detection.ps1 and a source file. Every program and script is "signed" by Signer, also the
		# catalog of Config and the catalog of everything else. The small package keeps the many cases fast.
		$script:fakeSignatures = @{}
		$script:fakeSignatureError = ''
		$script:fakeCatalogError = $false
		if (Test-Path -LiteralPath $signedPackage) { Remove-Item -LiteralPath $signedPackage -Recurse -Force }
		New-Item -ItemType Directory -Path (Split-Path -Parent $signedPackage) -Force | Out-Null
		if ($Full) { Copy-Item -LiteralPath $layoutPackage -Destination $signedPackage -Recurse }
		else {
			foreach ($name in 'Uninstall.ps1', 'App\Self_X.ps1', 'App\SelfX_Tray.ps1', 'App\Localization.ps1', 'App\Scripts_to_run\SelfX_Device_Restart.ps1', 'App\SelfX.Code.json', 'App\Languages\de.xml', 'App\Languages\fr.xml', 'App\logo.png',
				'Bin\SelfXService.exe', 'Bin\SelfX.exe', 'Bin\SelfXSessionStarter.dll', 'Bin\WinRT\SelfXWinRT.dll', 'Bin\Audio\SelfXAudio.dll', 'Bin\SelfX.Binaries.json', 'Config\Tool_Config.xml', 'Config\Health_Config.xml', 'Config\SelfX.Config.json') {
				$path = Join-Path $signedPackage $name
				New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
				[IO.File]::WriteAllText($path, "content of $name")
			}
		}
		New-Item -ItemType Directory -Path (Join-Path $signedPackage 'Service') -Force | Out-Null
		[IO.File]::WriteAllText((Join-Path $signedPackage 'Install.ps1'), "# installer`r`n")
		[IO.File]::WriteAllText((Join-Path $signedPackage 'Detection.ps1'), "# detection`r`n")
		[IO.File]::WriteAllText((Join-Path $signedPackage 'Service\SelfXService.cs'), '// source')
		foreach ($file in @(Get-ChildItem -LiteralPath $signedPackage -Recurse -File -Force | Where-Object { $_.Extension -in '.exe', '.dll', '.ps1' })) { Set-FakeSignature $file.FullName $Signer }
		New-FakeCatalog (Join-Path $signedPackage 'Config') $configCatalog $Signer
		New-FakeCatalog $signedPackage $codeCatalog $Signer -Skip @('Config')
	}
	function Test-Signed([string[]]$Allowed = @($signerA)) { return (Get-Refusal { Test-SelfXPackageSignatures -PackageFolder $signedPackage -AllowedThumbprint $Allowed }) }

	# 4. A completely signed package is accepted (the package with all scripts of the project).
	New-SignedPackage -Full
	$signableCount = @(Get-ChildItem -LiteralPath $signedPackage -Recurse -File -Force | Where-Object { $_.Extension -in '.exe', '.dll', '.ps1' }).Count
	$verified = Test-SelfXPackageSignatures -PackageFolder $signedPackage -AllowedThumbprint $signerA
	Assert-Equal $verified.Files $signableCount "signature: every program and script of the package was checked ($signableCount)"
	Assert-Equal ($signableCount -gt 60) $true 'signature: the test package holds the scripts of the project'
	Assert-Equal $verified.CodeListHash (Get-FileHash -LiteralPath (Join-Path $signedPackage 'App\SelfX.Code.json') -Algorithm SHA256).Hash 'signature: the SHA256 of the checked SelfX.Code.json is returned'
	Assert-Equal $verified.ConfigListHash (Get-FileHash -LiteralPath (Join-Path $signedPackage 'Config\SelfX.Config.json') -Algorithm SHA256).Hash 'signature: the SHA256 of the checked SelfX.Config.json is returned'
	Assert-Equal (Test-Signed @($signerB, $signerA.ToLowerInvariant())) 'accepted' 'signature: the signer is one of several allowed signers (any case)'
	Assert-Equal ((Get-Refusal { Test-SelfXPackageSignatures -PackageFolder $signedPackage -AllowedThumbprint @('') }) -ne 'accepted') $true 'signature: an empty entry in the list of signers never means "everything is allowed"'
	Assert-Equal ((Get-Refusal { Test-SelfXPackageSignatures -PackageFolder $signedPackage -AllowedThumbprint @('xyz') }) -match '^-TrustedSigner') $true 'signature: an invalid list of signers stops the check'

	# 5. Negative cases of the signatures (the cases of the signing library: not signed, changed, wrong signer, not trusted).
	New-SignedPackage
	$slimCount = @(Get-ChildItem -LiteralPath $signedPackage -Recurse -File -Force | Where-Object { $_.Extension -in '.exe', '.dll', '.ps1' }).Count
	Assert-Equal $slimCount 12 'the small test package has 12 programs and scripts'
	Assert-Equal (Test-Signed) 'accepted' 'the small signed test package is accepted'
	$answer = Test-Signed @($signerB)
	Assert-Equal ($answer -match 'SignerNotAllowed' -and $answer -match "$slimCount of $slimCount" -and $answer -match 'Nothing was changed') $true "wrong signer: valid signatures of a signer that is not allowed are refused ($answer)"
	Assert-Equal ($answer -match ' and \d+ more') $true 'many problems: the message names ten files and the number of the rest'
	New-SignedPackage
	$script:fakeSignatures.Remove((Get-FakeKey (Join-Path $signedPackage 'App\Self_X.ps1')))
	$answer = Test-Signed
	Assert-Equal ($answer -match 'App\\Self_X\.ps1 \(NotSigned\)' -and $answer -match '^Trust mode Signature: 1 of ') $true "not signed: one unsigned script stops ($answer)"
	New-SignedPackage
	Add-Content -LiteralPath (Join-Path $signedPackage 'App\Scripts_to_run\SelfX_Device_Restart.ps1') -Value '# changed after signing'
	$answer = Test-Signed
	Assert-Equal ($answer -match 'SelfX_Device_Restart\.ps1 \(HashMismatch\)') $true "changed file: a script changed after signing stops ($answer)"
	foreach ($status in 'NotTrusted', 'UnknownError', 'Incompatible') {
		New-SignedPackage
		Set-FakeSignature (Join-Path $signedPackage 'Bin\SelfXService.exe') $signerA $status
		$answer = Test-Signed
		Assert-Equal ($answer -match 'Bin\\SelfXService\.exe \(NotTrusted\)') $true "status $status (untrusted root, expired without time stamp): the program is refused ($answer)"
	}
	New-SignedPackage
	Set-FakeSignature (Join-Path $signedPackage 'Bin\SelfXService.exe') $signerA 'NotSupportedFileFormat'
	Assert-Equal ((Test-Signed) -match 'SelfXService\.exe \(NotSupported\)') $true 'status NotSupportedFileFormat is refused'
	New-SignedPackage
	Set-FakeSignature (Join-Path $signedPackage 'Bin\WinRT\SelfXWinRT.dll') $signerB
	$answer = Test-Signed
	Assert-Equal ($answer -match 'Bin\\WinRT\\SelfXWinRT\.dll \(SignerNotAllowed\)') $true "library of another publisher: a valid signature of another signer is refused ($answer)"
	New-SignedPackage
	$script:fakeSignatures.Remove((Get-FakeKey (Join-Path $signedPackage 'Install.ps1')))
	Assert-Equal ((Test-Signed) -match 'Install\.ps1 \(NotSigned\)') $true 'Install.ps1 itself must be signed'
	New-SignedPackage
	$script:fakeSignatures.Remove((Get-FakeKey (Join-Path $signedPackage 'Bin\SelfXSessionStarter.dll')))
	Assert-Equal ((Test-Signed) -match 'SelfXSessionStarter\.dll \(NotSigned\)') $true 'a library that is loaded but not installed must be signed'
	New-SignedPackage
	$script:fakeSignatureError = '*\Uninstall.ps1'
	Assert-Equal ((Test-Signed) -match 'Uninstall\.ps1 \(Error\)') $true 'an error of the signature check is a refusal (fail closed)'
	New-SignedPackage
	Set-FakeSignature (Join-Path $signedPackage 'Uninstall.ps1') '' 'Valid'
	Assert-Equal ((Test-Signed) -match 'Uninstall\.ps1 \(Error\)') $true 'status Valid without a signer certificate is refused'
	New-SignedPackage
	[IO.File]::WriteAllText((Join-Path $signedPackage 'App\Scripts_to_run\Added.psm1'), '# module')
	Assert-Equal ((Test-Signed) -match 'Added\.psm1 \(NotSigned\)') $true 'a module file (.psm1) must be signed too'

	# 6. Negative cases of the catalog of the configuration.
	New-SignedPackage
	Remove-Item -LiteralPath $configCatalog -Force
	$answer = Test-Signed
	Assert-Equal ($answer -match 'Config\\SelfX\.Config\.cat is not a valid signed catalog.*FileMissing') $true "configuration catalog missing: refused ($answer)"
	New-SignedPackage
	Set-FakeSignature $configCatalog $signerB
	Assert-Equal ((Test-Signed) -match 'SelfX\.Config\.cat.*CatalogSignature:SignerNotAllowed') $true 'configuration catalog of another signer: refused'
	New-SignedPackage
	$script:fakeSignatures.Remove((Get-FakeKey $configCatalog))
	Assert-Equal ((Test-Signed) -match 'SelfX\.Config\.cat.*CatalogSignature:NotSigned') $true 'unsigned configuration catalog: refused'
	New-SignedPackage
	Add-Content -LiteralPath $configCatalog -Value ' '
	Assert-Equal ((Test-Signed) -match 'SelfX\.Config\.cat.*CatalogSignature:HashMismatch') $true 'configuration catalog changed after signing: refused'
	New-SignedPackage
	Add-Content -LiteralPath (Join-Path $signedPackage 'Config\Tool_Config.xml') -Value '<!-- changed -->'
	$answer = Test-Signed
	Assert-Equal ($answer -match 'SelfX\.Config\.cat.*FilesDiffer \(changed: tool_config\.xml\)') $true "changed XML: a configuration file changed after the catalog was signed stops ($answer)"
	New-SignedPackage
	New-Item -ItemType Directory -Path (Join-Path $signedPackage 'Config\Branding') -Force | Out-Null
	[IO.File]::WriteAllText((Join-Path $signedPackage 'Config\Branding\added.png'), 'png')
	$answer = Test-Signed
	Assert-Equal ($answer -match 'SelfX\.Config\.cat.*not in the catalog: branding\\added\.png') $true "added file: a file in Config that the catalog does not list stops ($answer)"
	New-SignedPackage
	Remove-Item -LiteralPath (Join-Path $signedPackage 'Config\Health_Config.xml') -Force
	Assert-Equal ((Test-Signed) -match 'SelfX\.Config\.cat.*missing: health_config\.xml') $true 'missing file: a configuration file of the catalog that is not in the package stops'
	New-SignedPackage
	New-FakeCatalog (Join-Path $signedPackage 'Config') $configCatalog $signerA -HashName 'SHA1'
	Assert-Equal ((Test-Signed) -match 'SelfX\.Config\.cat.*HashAlgorithm') $true 'a catalog that does not use SHA256 is refused'
	New-SignedPackage
	New-FakeCatalog (Join-Path $signedPackage 'Config') $configCatalog $signerA -Empty
	Assert-Equal ((Test-Signed) -match 'SelfX\.Config\.cat.*NoDetails') $true 'an empty catalog is refused'
	New-SignedPackage
	$script:fakeCatalogError = $true
	Assert-Equal ((Test-Signed) -match 'SelfX\.Config\.cat.*: Error\.') $true 'an error of the catalog check is a refusal (fail closed)'

	# 7. Negative cases of the catalog of the code: everything outside Config, also files that cannot carry a signature.
	New-SignedPackage
	Remove-Item -LiteralPath $codeCatalog -Force
	$answer = Test-Signed
	Assert-Equal ($answer -match '^Trust mode Signature: SelfX\.Code\.cat is not a valid signed catalog.*FileMissing') $true "code catalog missing: refused ($answer)"
	New-SignedPackage
	Set-FakeSignature $codeCatalog $signerB
	Assert-Equal ((Test-Signed) -match 'SelfX\.Code\.cat.*CatalogSignature:SignerNotAllowed') $true 'code catalog of another signer: refused'
	foreach ($name in 'App\SelfX.Code.json', 'App\Languages\de.xml', 'App\logo.png', 'Bin\SelfX.Binaries.json', 'Service\SelfXService.cs') {
		New-SignedPackage
		Add-Content -LiteralPath (Join-Path $signedPackage $name) -Value ' '
		$answer = Test-Signed
		Assert-Equal ($answer -match ('SelfX\.Code\.cat.*FilesDiffer \(changed: ' + [regex]::Escape($name.ToLowerInvariant()) + '\)')) $true "code catalog: a changed $name stops ($answer)"
	}
	New-SignedPackage
	[IO.File]::WriteAllText((Join-Path $signedPackage 'readme.txt'), 'added')
	Assert-Equal ((Test-Signed) -match 'SelfX\.Code\.cat.*not in the catalog: readme\.txt') $true 'code catalog: an added file at the top of the package stops'
	New-SignedPackage
	Remove-Item -LiteralPath (Join-Path $signedPackage 'App\Languages\fr.xml') -Force
	Assert-Equal ((Test-Signed) -match 'SelfX\.Code\.cat.*missing: app\\languages\\fr\.xml') $true 'code catalog: a missing language file stops'
	New-SignedPackage
	New-FakeCatalog $signedPackage $codeCatalog $signerA
	Assert-Equal ((Test-Signed) -match 'SelfX\.Code\.cat.*missing: config\\') $true 'code catalog: a catalog that also lists the files of Config is refused (the two catalogs are separate)'
	New-SignedPackage
	Remove-Item -LiteralPath (Join-Path $signedPackage 'App\SelfX.Code.json') -Force
	New-FakeCatalog $signedPackage $codeCatalog $signerA -Skip @('Config')
	Assert-Equal ((Test-Signed) -match 'SelfX\.Code\.json is missing') $true 'a signed package without SelfX.Code.json is refused'

	# 8. A link in the package.
	New-SignedPackage
	$linkTarget = Join-Path $root 'signed\target'
	New-Item -ItemType Directory -Path $linkTarget -Force | Out-Null
	$link = Join-Path $signedPackage 'App\Linked'
	$null = & cmd.exe /c mklink /J "`"$link`"" "`"$linkTarget`"" 2>&1
	if ($LASTEXITCODE -eq 0) {
		try { Assert-Equal ((Test-Signed) -match 'contains a link \(App\\Linked\)') $true 'a junction in the package stops the check' }
		finally { $null = & cmd.exe /c rmdir "`"$link`"" 2>&1 }
	}
	else { Write-Output 'Skipped: the junction for the link test could not be created.' }

	# 9. The same answers as Test-SelfXSignature of tools\SelfXSigning.ps1 (two copies of one rule).
	New-SignedPackage
	$probe = Join-Path $signedPackage 'Uninstall.ps1'
	$probes = @(
		@{ Status = 'Valid'; Thumbprint = $signerA }, @{ Status = 'Valid'; Thumbprint = $signerB }, @{ Status = 'Valid'; Thumbprint = '' },
		@{ Status = 'NotSigned'; Thumbprint = '' }, @{ Status = 'HashMismatch'; Thumbprint = $signerA }, @{ Status = 'NotSupportedFileFormat'; Thumbprint = '' },
		@{ Status = 'NotTrusted'; Thumbprint = $signerA }, @{ Status = 'UnknownError'; Thumbprint = $signerA }, @{ Status = 'Incompatible'; Thumbprint = $signerA }
	)
	foreach ($case in $probes) {
		Set-FakeSignature $probe $case.Thumbprint $case.Status
		$fromLibrary = (Test-SelfXSignature -Path $probe -AllowedThumbprint $signerA).Reason
		Assert-Equal (Test-SelfXFileSignature -Path $probe -AllowedThumbprint @($signerA)) $fromLibrary "same answer as the signing library: status $($case.Status), signer '$($case.Thumbprint)' ($fromLibrary)"
	}
	$missingProbe = Join-Path $signedPackage 'NoSuchFile.ps1'
	Assert-Equal (Test-SelfXFileSignature -Path $missingProbe -AllowedThumbprint @($signerA)) (Test-SelfXSignature -Path $missingProbe -AllowedThumbprint $signerA).Reason 'same answer as the signing library: missing file'

	# 10. The lists and the copy step with a signed package: the catalog of Config is accepted only in the mode Signature; both
	#     catalogs are installed next to their lists (the service reads them); the installed lists and catalogs are the checked ones.
	#     In the mode Hash no catalog is installed.
	New-SignedPackage -Full
	$verified = Test-SelfXPackageSignatures -PackageFolder $signedPackage -AllowedThumbprint $signerA
	Assert-Equal (Get-Refusal { Test-SelfXFileManifest -PackageFolder $signedPackage -SignedPackage }) 'accepted' 'mode Signature: the lists accept Config\SelfX.Config.cat'
	Assert-Equal (Test-SelfXFileManifest -PackageFolder $signedPackage -SignedPackage) $packageCount 'mode Signature: the catalog is not counted as a file of the lists'
	$answer = Get-Refusal { Test-SelfXFileManifest -PackageFolder $signedPackage }
	Assert-Equal ($answer -match 'package is signed' -and $answer -match '-TrustedSigner') $true "mode Hash: a signed package without -TrustedSigner is refused with a hint ($answer)"
	Assert-Equal (Get-Refusal { Test-SelfXFileManifest -PackageFolder $signedPackage -SignedPackage:$false }) $answer 'mode Hash: -SignedPackage:$false is the same as no switch'
	if (Test-Path -LiteralPath $device) { Remove-Item -LiteralPath $device -Recurse -Force }
	Clear-SelfXInstallFolder -InstallFolder $device -Attempts 1 -DelaySeconds 0
	Copy-SelfXPayload -PackageFolder $signedPackage -InstallFolder $device
	Assert-Equal @(Get-ChildItem -LiteralPath $device -Recurse -File -Force -Filter '*.cat').Count 0 'mode Hash: the copy step installs no catalog'
	if (Test-Path -LiteralPath $device) { Remove-Item -LiteralPath $device -Recurse -Force }
	Clear-SelfXInstallFolder -InstallFolder $device -Attempts 1 -DelaySeconds 0
	Copy-SelfXPayload -PackageFolder $signedPackage -InstallFolder $device -SignedPackage
	Assert-Equal (Get-TopEntries) 'App,Config' 'signed package: the install folder holds only App and Config'
	Assert-Equal ((@(Get-ChildItem -LiteralPath $device -Recurse -File -Force -Filter '*.cat' | ForEach-Object { $_.FullName.Substring($device.Length + 1) }) | Sort-Object) -join ',') 'App\SelfX.Code.cat,Config\SelfX.Config.cat' 'signed package: both catalogs are installed next to their lists, nowhere else'
	Assert-Equal (Get-FileHash -LiteralPath (Join-Path $device 'App\SelfX.Code.cat') -Algorithm SHA256).Hash $verified.CodeCatalogHash 'signed package: the installed code catalog is the checked one'
	Assert-Equal (Get-FileHash -LiteralPath (Join-Path $device 'Config\SelfX.Config.cat') -Algorithm SHA256).Hash $verified.ConfigCatalogHash 'signed package: the installed configuration catalog is the checked one'
	try { $installedCount = Test-SelfXInstalledFiles -InstallFolder $device -SignedPackage } catch { $installedCount = "refused: $($_.Exception.Message)" }
	Assert-Equal $installedCount $packageCount 'signed package: the installed folders match both lists (the catalogs are not counted)'
	Assert-Equal ((Get-Refusal { Test-SelfXInstalledFiles -InstallFolder $device }) -match 'SelfX\.Code\.cat is not listed') $true 'mode Hash: an installed catalog is refused like every unlisted file'
	Assert-Equal (Get-Refusal { Test-SelfXInstalledLists -InstallFolder $device -Verified $verified }) 'accepted' 'signed package: the installed lists and catalogs are the checked ones'
	Add-Content -LiteralPath (Join-Path $device 'App\SelfX.Code.cat') -Value ' '
	Assert-Equal ((Get-Refusal { Test-SelfXInstalledLists -InstallFolder $device -Verified $verified }) -match 'App\\SelfX\.Code\.cat.*changed between check and copy') $true 'a code catalog changed between check and copy is found'
	Copy-Item -LiteralPath (Join-Path $signedPackage 'SelfX.Code.cat') -Destination (Join-Path $device 'App\SelfX.Code.cat') -Force
	Remove-Item -LiteralPath (Join-Path $device 'Config\SelfX.Config.cat') -Force
	Assert-Equal ((Get-Refusal { Test-SelfXInstalledFiles -InstallFolder $device -SignedPackage }) -match 'Config\\SelfX\.Config\.cat is missing') $true 'signed package: a missing installed catalog is refused'
	Copy-Item -LiteralPath (Join-Path $signedPackage 'Config\SelfX.Config.cat') -Destination (Join-Path $device 'Config\SelfX.Config.cat') -Force
	Add-Content -LiteralPath (Join-Path $device 'App\SelfX.Code.json') -Value ' '
	Assert-Equal ((Get-Refusal { Test-SelfXInstalledLists -InstallFolder $device -Verified $verified }) -match 'App\\SelfX\.Code\.json.*changed between check and copy') $true 'a code list changed between check and copy is found'
	Copy-Item -LiteralPath (Join-Path $signedPackage 'App\SelfX.Code.json') -Destination (Join-Path $device 'App\SelfX.Code.json') -Force
	Add-Content -LiteralPath (Join-Path $device 'Config\SelfX.Config.json') -Value ' '
	Assert-Equal ((Get-Refusal { Test-SelfXInstalledLists -InstallFolder $device -Verified $verified }) -match 'Config\\SelfX\.Config\.json.*changed between check and copy') $true 'a configuration list changed between check and copy is found'
	Assert-Equal ((Get-Refusal { Test-SelfXInstalledLists -InstallFolder $device -Verified ([pscustomobject]@{ CodeListHash = ''; ConfigListHash = '' }) }) -match 'checked SHA256.*is missing') $true 'installed lists without checked hashes are refused'
	Copy-Item -LiteralPath (Join-Path $signedPackage 'Config\SelfX.Config.json') -Destination (Join-Path $device 'Config\SelfX.Config.json') -Force
	Assert-Equal ((Get-Refusal { Test-SelfXInstalledLists -InstallFolder $device -Verified ([pscustomobject]@{ CodeListHash = $verified.CodeListHash; ConfigListHash = $verified.ConfigListHash }) }) -match 'checked SHA256 of App\\SelfX\.Code\.cat is missing') $true 'installed catalogs without checked hashes are refused'

	# 11. The trust anchor, in a test key of the current user (Install.ps1 uses HKLM\SOFTWARE\SelfX\Trust). The current user gets full
	#     control here so that the test can run without administrator rights and can remove the key again.
	$trustTestRoot = 'Software\SelfXInstallTest_' + [guid]::NewGuid().ToString('N')
	$trustKey = $trustTestRoot + '\Trust'
	$me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
	$place = @{ Hive = 'CurrentUser'; SubKey = $trustKey }
	$write = @{ Hive = 'CurrentUser'; SubKey = $trustKey; OwnerSid = $me; FullControlSids = @('S-1-5-18', 'S-1-5-32-544', $me) }
	$trusted = @('S-1-5-18', 'S-1-5-32-544', $me)
	Assert-Equal ($null -eq (Get-SelfXTrustAnchor @place)) $true 'anchor: no key gives no anchor'
	Set-SelfXTrustAnchor -Mode Signature -Signers @($signerC, $signerA) @write
	$anchor = Get-SelfXTrustAnchor @place
	Assert-Equal $anchor.Mode 'Signature' 'anchor: the mode Signature is written'
	Assert-Equal (@($anchor.Signers) -join '|') "$($signerC.ToUpperInvariant())|$signerA" 'anchor: the signers are written in upper case, in the given order'
	$rawKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($trustKey, $false)
	try {
		Assert-Equal $rawKey.GetValueKind('Mode') 'String' 'anchor: Mode is REG_SZ'
		Assert-Equal $rawKey.GetValueKind('Signers') 'MultiString' 'anchor: Signers is REG_MULTI_SZ'
		$acl = $rawKey.GetAccessControl([Security.AccessControl.AccessControlSections]'Access, Owner')
		Assert-Equal $acl.AreAccessRulesProtected $true 'anchor: the rights are not inherited'
		Assert-Equal $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value $me 'anchor: the owner is set (Install.ps1: Administrators, S-1-5-32-544)'
		$rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
		Assert-Equal ((@($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)) -join ',') ((@('S-1-5-18', 'S-1-5-32-544', 'S-1-5-32-545', $me) | Sort-Object -Unique) -join ',') 'anchor: rules only for SYSTEM, Administrators, Users (and the test user), all by SID'
		$userRule = @($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-32-545' })
		Assert-Equal $userRule.Count 1 'anchor: one rule for Users'
		Assert-Equal ([int]$userRule[0].RegistryRights) ([int][Security.AccessControl.RegistryRights]::ReadKey) 'anchor: Users can only read'
		foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') { Assert-Equal ([int](@($rules | Where-Object { $_.IdentityReference.Value -eq $sid })[0].RegistryRights)) ([int][Security.AccessControl.RegistryRights]::FullControl) "anchor: full control for $sid" }
	} finally { $rawKey.Dispose() }
	Assert-Equal ($null -eq (Test-SelfXTrustAnchorState -Mode Signature -Signers @($signerC.ToUpperInvariant(), $signerA) -TrustedSids $trusted @place)) $true 'anchor: the state check accepts what was written'
	Assert-Equal ((Test-SelfXTrustAnchorState -Mode Signature -Signers @($signerC.ToUpperInvariant(), $signerA) @place) -match "can be changed by $me") $true 'anchor: an identity other than SYSTEM and Administrators with write rights is found'
	Assert-Equal (Test-SelfXTrustAnchorState -Mode Hash -TrustedSids $trusted @place) 'the mode is Signature' 'anchor: another mode than expected is found'
	Assert-Equal (Test-SelfXTrustAnchorState -Mode Signature -Signers @($signerA) -TrustedSids $trusted @place) 'the signers differ' 'anchor: other signers than expected are found'
	# Downgrade with the anchor of the registry: Signature -> Hash only with the switch.
	$answer = Get-Refusal { Resolve-SelfXTrustMode -InstalledMode (Get-SelfXTrustAnchor @place).Mode -SignatureRequested $false -AllowHashMode $false }
	Assert-Equal ($answer -match '-AllowHashMode') $true 'downgrade: an update without -TrustedSigner on a device with the anchor Signature stops'
	Assert-Equal (Get-SelfXTrustAnchor @place).Mode 'Signature' 'downgrade: the refused update leaves the anchor unchanged'
	Assert-Equal (Resolve-SelfXTrustMode -InstalledMode (Get-SelfXTrustAnchor @place).Mode -SignatureRequested $false -AllowHashMode $true) 'Hash' 'downgrade: with -AllowHashMode the mode is Hash'
	# A renewal: a second signer is added, the mode stays.
	Set-SelfXTrustAnchor -Mode Signature -Signers @("$signerA,$signerB") @write
	Assert-Equal (@((Get-SelfXTrustAnchor @place).Signers) -join '|') "$signerA|$signerB" 'anchor: a new list of signers replaces the old one'
	Assert-Equal ((Get-Refusal { Set-SelfXTrustAnchor -Mode Signature -Signers @('xyz') @write }) -match '^-TrustedSigner') $true 'anchor: the mode Signature is not written with an invalid list'
	Assert-Equal ((Get-Refusal { Set-SelfXTrustAnchor -Mode Signature @write }) -match '^-TrustedSigner') $true 'anchor: the mode Signature is not written without signers'
	Assert-Equal (@((Get-SelfXTrustAnchor @place).Signers) -join '|') "$signerA|$signerB" 'anchor: a refused write leaves the anchor unchanged'
	# Mode Hash: Signers is removed, also every other value and sub key.
	$rawKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($trustKey, $true)
	try { $rawKey.SetValue('Other', 'x'); $rawKey.CreateSubKey('Sub').Dispose() } finally { $rawKey.Dispose() }
	Set-SelfXTrustAnchor -Mode Hash -Signers @($signerA) @write
	$anchor = Get-SelfXTrustAnchor @place
	Assert-Equal $anchor.Mode 'Hash' 'anchor: the mode Hash is written'
	Assert-Equal @($anchor.Signers).Count 0 'anchor: the mode Hash has no signers'
	$rawKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($trustKey, $true)
	try {
		Assert-Equal ((@($rawKey.GetValueNames()) | Sort-Object) -join ',') 'Mode' 'anchor: only the value Mode is left in the mode Hash'
		Assert-Equal @($rawKey.GetSubKeyNames()).Count 0 'anchor: a sub key is removed'
		# Content that Install.ps1 does not write counts as Invalid (and is treated like Signature by the downgrade check).
		$rawKey.SetValue('Mode', 'hash', [Microsoft.Win32.RegistryValueKind]::String)
		Assert-Equal (Get-SelfXTrustAnchor @place).Mode 'Invalid' 'anchor: another text than Hash or Signature is Invalid'
		$rawKey.SetValue('Mode', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
		Assert-Equal (Get-SelfXTrustAnchor @place).Mode 'Invalid' 'anchor: a number as Mode is Invalid'
		$rawKey.DeleteValue('Mode')
		Assert-Equal (Get-SelfXTrustAnchor @place).Mode 'Invalid' 'anchor: a key without Mode is Invalid'
		$rawKey.SetValue('Mode', 'Signature', [Microsoft.Win32.RegistryValueKind]::String)
		$rawKey.SetValue('Signers', $signerA, [Microsoft.Win32.RegistryValueKind]::String)
		Assert-Equal (Get-SelfXTrustAnchor @place).Mode 'Invalid' 'anchor: Signers of another type than REG_MULTI_SZ is Invalid'
	} finally { $rawKey.Dispose() }
	Assert-Equal ((Get-Refusal { Resolve-SelfXTrustMode -InstalledMode (Get-SelfXTrustAnchor @place).Mode -SignatureRequested $false -AllowHashMode $false }) -match '-AllowHashMode') $true 'downgrade: an anchor that cannot be understood counts as Signature (fail closed)'

	# 12. The main part of Install.ps1: order of the steps and the parameters.
	$parameters = @{}
	foreach ($parameter in $ast.ParamBlock.Parameters) { $parameters[$parameter.Name.VariablePath.UserPath] = $parameter.StaticType.Name }
	Assert-Equal $parameters['TrustedSigner'] 'String[]' 'Install.ps1 has the parameter -TrustedSigner (string[])'
	Assert-Equal $parameters['AllowHashMode'] 'SwitchParameter' 'Install.ps1 has the switch -AllowHashMode'
	Assert-Equal $installText.Contains('[CmdletBinding(PositionalBinding = $false)]') $true 'Install.ps1 binds parameters by name only'
	$order = @(
		'$TrustMode = Resolve-SelfXTrustMode',
		'$VerifiedSignatures = Test-SelfXPackageSignatures -PackageFolder $PackageFolder',
		'Initialize-SelfXDataFolder -Path $DataFolder',
		'Start-Transcript',
		'Stop-Service -Name $ServiceName',
		'Clear-SelfXInstallFolder -InstallFolder $InstallFolder',
		'Copy-SelfXPayload -PackageFolder $PackageFolder -InstallFolder $InstallFolder -SignedPackage:($TrustMode -eq ''Signature'')',
		'$InstalledFiles = Test-SelfXInstalledFiles -InstallFolder $InstallFolder -SignedPackage:($TrustMode -eq ''Signature'')',
		'Test-SelfXInstalledLists -InstallFolder $InstallFolder -Verified $VerifiedSignatures',
		'Set-SelfXTrustAnchor -Mode $TrustMode -Signers $AllowedSigners',
		'New-Service -Name $ServiceName'
	)
	# The mode -ConfigOnly has its own branch before the full installation (Test-InstallConfigOnly.ps1 checks it): the order is that of the full flow.
	$fullFlowText = $installText.Substring($installText.IndexOf('exit $ConfigOnlyExit', [StringComparison]::Ordinal))
	$position = -1
	foreach ($step in $order) {
		$found = $fullFlowText.IndexOf($step, [StringComparison]::Ordinal)
		Assert-Equal ($found -gt $position) $true "Install.ps1: '$step' comes after the step before it (mode and signatures before any change, anchor before the service)"
		if ($found -gt $position) { $position = $found }
	}
	Assert-Equal $installText.Contains('$SignatureRequested = $PSBoundParameters.ContainsKey(''TrustedSigner'')') $true 'Install.ps1: a given but empty -TrustedSigner is not the mode Hash'
	Assert-Equal $installText.Contains('Test-SelfXFileManifest -PackageFolder $PackageFolder -SignedPackage:($TrustMode -eq ''Signature'')') $true 'Install.ps1: the lists are checked in both modes'
	Assert-Equal ($installText -match '(?i)BUILTIN\\|NT AUTHORITY|Administratoren|''Everyone''|''Jeder''') $false 'Install.ps1 names accounts by SID only'

	# 13. Part 2: real signatures and real catalogs (test certificates of the current user). This part shows that the names of
	#     Test-FileCatalog, the hash algorithm and the status values are the ones the functions expect.
	Remove-Item -LiteralPath Function:\Get-AuthenticodeSignature, Function:\Test-FileCatalog
	# The test certificates must be trusted roots. With administrator rights they are added to Cert:\LocalMachine\Root (Windows asks
	# nothing there); without, to Cert:\CurrentUser\Root, where Windows shows a question that somebody has to answer. So the part runs
	# in CI only with administrator rights (a question would wait for ever) and elsewhere only when it is asked for.
	$rootLocation = $(if ($isAdminTest) { 'LocalMachine' } else { 'CurrentUser' })
	$canTrust = (($env:GITHUB_ACTIONS -eq 'true') -and $isAdminTest) -or ($env:SELFX_TEST_ALLOW_ROOT_IMPORT -eq '1')
	if (-not $canTrust) {
		Write-Output 'Skipped: real signatures and catalogs need a trusted test root; set SELFX_TEST_ALLOW_ROOT_IMPORT=1 (adds two test certificates to the trusted roots until the end of the test: Cert:\LocalMachine\Root with administrator rights, otherwise Cert:\CurrentUser\Root with a question of Windows) or run in CI.'
	}
	else {
		$testCertificates = New-Object System.Collections.Generic.List[string]
		$testRoots = New-Object System.Collections.Generic.List[string]
		function New-TestSigner([string]$Name) {
			$created = New-SelfSignedCertificate -Subject "CN=SelfX Install Test $Name $([guid]::NewGuid().ToString('N'))" -CertStoreLocation 'Cert:\CurrentUser\My' -Type CodeSigningCert -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyUsage DigitalSignature
			$testCertificates.Add($created.Thumbprint)
			return (Get-Item -LiteralPath "Cert:\CurrentUser\My\$($created.Thumbprint)")
		}
		function Add-TestRoot($Certificate) {
			$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', $rootLocation)
			$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
			try { $store.Add((New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, $Certificate.RawData))) } finally { $store.Close() }
			$testRoots.Add($Certificate.Thumbprint)
		}
		try {
			$certA = New-TestSigner 'A'
			$certB = New-TestSigner 'B'
			# A third certificate that is never added to the trusted roots.
			$certC = New-TestSigner 'C'
			Add-TestRoot $certA
			Add-TestRoot $certB
			$real = Join-Path $root 'real\package'
			$realCatalogs = Join-Path $root 'real\catalogs'
			function New-RealPackage($Certificate) {
				foreach ($folder in $real, $realCatalogs) { if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force } }
				New-Item -ItemType Directory -Path (Join-Path $real 'App\Languages'), (Join-Path $real 'App\Scripts_to_run'), (Join-Path $real 'Bin'), (Join-Path $real 'Service'), $realCatalogs -Force | Out-Null
				$scripts = @('Install.ps1', 'Uninstall.ps1', 'App\Self_X.ps1', 'App\Scripts_to_run\SelfX_Device_Restart.ps1') | ForEach-Object { Join-Path $real $_ }
				foreach ($scriptFile in $scripts) { [IO.File]::WriteAllText($scriptFile, "Write-Output 'SelfX install test'`r`n", (New-Object System.Text.UTF8Encoding($false))) }
				[IO.File]::WriteAllText((Join-Path $real 'App\SelfX.Code.json'), '{ "ManifestVersion": 1, "ToolVersion": "3.1.0", "Files": {} }')
				[IO.File]::WriteAllText((Join-Path $real 'App\Languages\de.xml'), '<Language />')
				[IO.File]::WriteAllText((Join-Path $real 'Bin\SelfX.Binaries.json'), '{}')
				[IO.File]::WriteAllText((Join-Path $real 'Service\SelfXService.cs'), '// source')
				$null = Set-SelfXCodeSignature -Path $scripts -Certificate $Certificate
				# The catalog of the code is written before the folder Config exists, so it lists everything outside Config.
				$null = New-SelfXSignedCatalog -Path $real -CatalogFilePath (Join-Path $realCatalogs 'SelfX.Code.cat') -Certificate $Certificate
				New-Item -ItemType Directory -Path (Join-Path $real 'Config\Branding') -Force | Out-Null
				[IO.File]::WriteAllText((Join-Path $real 'Config\Tool_Config.xml'), '<GUI_Config />')
				[IO.File]::WriteAllText((Join-Path $real 'Config\Branding\logo.png'), 'png')
				[IO.File]::WriteAllText((Join-Path $real 'Config\SelfX.Config.json'), '{ "ManifestVersion": 1, "Files": {} }')
				$null = New-SelfXSignedCatalog -Path (Join-Path $real 'Config') -CatalogFilePath (Join-Path $realCatalogs 'SelfX.Config.cat') -Certificate $Certificate
				Move-Item -LiteralPath (Join-Path $realCatalogs 'SelfX.Config.cat') -Destination (Join-Path $real 'Config\SelfX.Config.cat')
				Move-Item -LiteralPath (Join-Path $realCatalogs 'SelfX.Code.cat') -Destination (Join-Path $real 'SelfX.Code.cat')
			}
			function Test-Real([string[]]$Allowed) { return (Get-Refusal { Test-SelfXPackageSignatures -PackageFolder $real -AllowedThumbprint $Allowed }) }
			New-RealPackage $certA
			$watch = [Diagnostics.Stopwatch]::StartNew()
			$answer = Test-Real @($certA.Thumbprint)
			$watch.Stop()
			Assert-Equal $answer 'accepted' 'real signatures: a signed package with both catalogs is accepted'
			Write-Output "Real signatures: the check of the small test package took $($watch.ElapsedMilliseconds) ms."
			Assert-Equal (Test-SelfXSignedCatalog -CatalogFilePath (Join-Path $real 'Config\SelfX.Config.cat') -Path (Join-Path $real 'Config') -AllowedThumbprint $certA.Thumbprint).Reason 'Ok' 'real signatures: the signing library accepts the same configuration catalog'
			Assert-Equal ((Test-Real @($certB.Thumbprint)) -match 'SignerNotAllowed') $true 'real signatures: another allowed signer than the one that signed is refused'
			Add-Content -LiteralPath (Join-Path $real 'App\Self_X.ps1') -Value '# added after the signature block'
			$answer = Test-Real @($certA.Thumbprint)
			Assert-Equal ($answer -ne 'accepted') $true "real signatures: a script with text added after the signature block is refused ($answer)"
			Write-Output "Real signatures: text added after the signature block is refused with: $answer"
			New-RealPackage $certA
			$changedScript = Join-Path $real 'App\Self_X.ps1'
			[IO.File]::WriteAllText($changedScript, "Write-Output 'changed'`r`n" + [IO.File]::ReadAllText($changedScript), (New-Object System.Text.UTF8Encoding($false)))
			$answer = Test-Real @($certA.Thumbprint)
			Assert-Equal ($answer -match 'App\\Self_X\.ps1 \(HashMismatch\)') $true "real signatures: a script changed before the signature block is refused ($answer)"
			New-RealPackage $certA
			[IO.File]::WriteAllText((Join-Path $real 'App\Scripts_to_run\Added.ps1'), "Write-Output 'unsigned'`r`n")
			Assert-Equal ((Test-Real @($certA.Thumbprint)) -match 'Added\.ps1 \(NotSigned\)') $true 'real signatures: an added unsigned script is refused'
			New-RealPackage $certA
			Add-Content -LiteralPath (Join-Path $real 'Config\Tool_Config.xml') -Value '<!-- changed -->'
			$answer = Test-Real @($certA.Thumbprint)
			Assert-Equal ($answer -match 'SelfX\.Config\.cat.*FilesDiffer \(changed: tool_config\.xml\)') $true "real catalog: a changed XML is refused ($answer)"
			New-RealPackage $certA
			[IO.File]::WriteAllText((Join-Path $real 'Config\Branding\added.png'), 'png')
			$answer = Test-Real @($certA.Thumbprint)
			Assert-Equal ($answer -match 'SelfX\.Config\.cat.*not in the catalog: branding\\added\.png') $true "real catalog: an added file in Config is refused ($answer)"
			New-RealPackage $certA
			Add-Content -LiteralPath (Join-Path $real 'App\Languages\de.xml') -Value '<!-- changed -->'
			$answer = Test-Real @($certA.Thumbprint)
			Assert-Equal ($answer -match 'SelfX\.Code\.cat.*FilesDiffer \(changed: app\\languages\\de\.xml\)') $true "real catalog: a changed language file is refused ($answer)"
			New-RealPackage $certA
			Add-Content -LiteralPath (Join-Path $real 'App\SelfX.Code.json') -Value ' '
			Assert-Equal ((Test-Real @($certA.Thumbprint)) -match 'SelfX\.Code\.cat.*changed: app\\selfx\.code\.json') $true 'real catalog: a changed SelfX.Code.json is refused'
			New-RealPackage $certA
			$bytes = [IO.File]::ReadAllBytes((Join-Path $real 'SelfX.Code.cat'))
			$bytes[[int]($bytes.Length / 2)] = $bytes[[int]($bytes.Length / 2)] -bxor 0xFF
			[IO.File]::WriteAllBytes((Join-Path $real 'SelfX.Code.cat'), $bytes)
			Assert-Equal ((Test-Real @($certA.Thumbprint)) -match 'SelfX\.Code\.cat is not a valid signed catalog.*(CatalogSignature|Error)') $true 'real catalog: a damaged catalog is refused'
			New-RealPackage $certB
			Assert-Equal ((Test-Real @($certA.Thumbprint)) -match 'SignerNotAllowed') $true 'real signatures: a package signed by another trusted certificate is refused'
			Assert-Equal (Test-Real @($certA.Thumbprint, $certB.Thumbprint)) 'accepted' 'real signatures: the same package is accepted when its signer is in the list'
			# A script signed by a certificate whose root the device does not trust: the status is not Valid, also when the thumbprint is allowed.
			New-RealPackage $certA
			$null = Set-AuthenticodeSignature -LiteralPath (Join-Path $real 'App\Self_X.ps1') -Certificate $certC -HashAlgorithm SHA256
			$answer = Test-Real @($certA.Thumbprint, $certC.Thumbprint)
			Assert-Equal ($answer -match 'App\\Self_X\.ps1 \(NotTrusted\)') $true "real signatures: a signer whose root the device does not trust is refused ($answer)"
		}
		finally {
			foreach ($thumbprint in $testRoots) {
				$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', $rootLocation)
				$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
				try { foreach ($entry in @($store.Certificates | Where-Object { $_.Thumbprint -eq $thumbprint })) { $store.Remove($entry) } } finally { $store.Close() }
			}
			foreach ($thumbprint in $testCertificates) { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint" -DeleteKey -Force -ErrorAction SilentlyContinue }
			Assert-Equal @(Get-ChildItem "Cert:\$rootLocation\Root" | Where-Object { $testRoots -contains $_.Thumbprint }).Count 0 'no test certificate is left in the trusted roots'
			Assert-Equal @(Get-ChildItem Cert:\CurrentUser\My | Where-Object { $testCertificates -contains $_.Thumbprint }).Count 0 'no test certificate is left in Cert:\CurrentUser\My'
		}
	}
}
finally {
	if ($trustTestRoot) { try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($trustTestRoot, $false) } catch { Write-Output "The test key HKCU\$trustTestRoot could not be removed: $($_.Exception.Message)" } }
	Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
