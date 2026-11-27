<#
.SYNOPSIS
    Tests the limits of the service pipe with the real service code (deadlines and connection limits).

.DESCRIPTION
    Compiles Service\SelfXService.cs in memory and starts only its pipe listener in this process, under a test
    pipe name of its own ("SelfX.Test.<guid>"). Nothing is installed, no service is registered, no action and no
    health check is run (the background checks start after 120 seconds; the test stops the listener before).
    Checked:
      - PING answers PONG.
      - A5: the per-user limit (8 open connections) applies before any data is read: a 9th connection of the
        same user is closed without an answer while 8 silent connections are open.
      - A4: silent connections are closed by the service after the read deadline (5 s), and PING answers again.
      - A4: a client that sends slowly cannot extend the deadline (one deadline for the whole request).
      - An oversized request without a line end is cut and rejected, not answered with PONG.
      - N3: when another process already owns the pipe name, the service does not join it (FirstPipeInstance), logs
        the problem and serves as soon as the name is free.
      - Trust mode: the service reads the anchor (tested in a key of the current user) only when it is valid and no
        normal account owns or may change it; files stay pinned (not writable, not replaceable) while they are checked;
        embedded signatures and the signed catalogs SelfX.Code.cat and SelfX.Config.cat are checked with test certificates
        (wrong signer, changed XML, missing catalog, unsigned or changed script, unsigned library); the cache of positive
        results. The cases that need a signature accepted by Windows run with administrator rights in CI or with
        SELFX_TEST_ALLOW_ROOT_IMPORT=1 (two test certificates become trusted roots until the end of the test).
    Runs as a normal user, needs no administrator rights. Duration about 30 seconds. Windows PowerShell 5.1:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-ServicePipe.ps1

.NOTES
    Name    : Test-ServicePipe.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.11   2026-11-22  fubu2k               Initial version.
    2.8.5    2026-11-23  fubu2k               The file list check covers .exe: changed and unlisted programs are refused.
    2.8.20   2026-11-23  fubu2k               N1: configuration and catalog are checked first, a cut-off is noted. N2: every file type in the install
                                              folder must be listed. N3: rights check of PowerShell 7 for all identities and parent folders.
    2.8.21   2026-11-23  fubu2k               N5 (pass 2): unexpected exceptions in a request are answered with a fixed text. N6: the job object ends a
                                              child process and its descendants; nothing is added after it has ended.
    2.9.0    2026-11-27  fubu2k               Two lists (SelfX.Code.json, SelfX.Config.json): placement, both lists, one list missing, left-over SelfX.Files.json.
    3.1.0    2026-11-27  fubu2k               Layout App/Config: configuration folder, fixed names of the settings files, file check of App, Config and the
                                              install folder above them, scripts of the company only with their entry in SelfX.Config.json.
    3.1.0    2026-11-27  fubu2k               Text overrides: Texts/<culture>.xml in the configuration list, nothing below Texts in the code list.
    3.1.0    2026-11-27  fubu2k               Trust mode: the anchor (missing, invalid, unsafe rights), pinned files, signatures and signed catalogs with
                                              test certificates (wrong signer, changed XML, missing catalog, unsigned script and library), the cache.
    3.1.0    2026-11-27  fubu2k               Environment_Mode: RUN in both modes through ProcessRequest of a test instance (Hide, not classified,
                                              different values per script, remediation, administrator, invalid or missing value, unreadable
                                              Tool_Config.xml), the check of other sessions in both modes, session host detection; nothing is started.
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-True($Condition, $Message) {
	$script:checks++
	if (-not $Condition) { $script:errors.Add($Message) }
}

# Makes the service type available: loads the program built from the real project file (same compiler settings and
# packages as the release build). Runs in PowerShell 7 and needs the .NET SDK 10.
function Add-SelfXServiceType {
	param([string]$Path)
	$project = Join-Path (Split-Path -Parent $Path) 'Projects\SelfXService\SelfXService.csproj'
	$output = Join-Path ([IO.Path]::GetTempPath()) ('SelfXServiceBuild_' + [guid]::NewGuid().ToString('N'))
	# global.json in the repository root selects the SDK.
	Push-Location (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Path)))
	try { $log = @(& dotnet build $project -c Release -o $output --nologo -v q 2>&1); $code = $LASTEXITCODE } finally { Pop-Location }
	if ($code -ne 0) { throw ("dotnet build of the service failed:`n" + (($log | Select-Object -Last 15) -join "`n")) }
	# The folder of the build: the trust tests sign a copy of the built library.
	$script:serviceBuildFolder = $output
	[void][Reflection.Assembly]::LoadFrom((Join-Path $output 'SelfXService.dll'))
}

$source = Join-Path $PSScriptRoot 'Service\SelfXService.cs'
Add-SelfXServiceType -Path $source

# --- PowerShell 7 must not be replaceable by normal users: the service checks the rights before every start ---
# The test calls the check behind IsPowerShellProtected with a stop folder (so the rights of %TEMP% and the user profile
# do not count) and with its own account added to the trusted identities (so that it runs without administrator rights).
$protectionMethod = [SelfX.SelfXService].GetMethod('IsPathChainProtected', [Reflection.BindingFlags]'NonPublic,Static')
Assert-True ($null -ne $protectionMethod) 'The service has the rights check for PowerShell 7'
Assert-True ($null -ne [SelfX.SelfXService].GetMethod('IsPowerShellProtected', [Reflection.BindingFlags]'NonPublic,Static')) 'The service still has IsPowerShellProtected (used before every start)'
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$defaultTrusted = [string[]]@('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
$testTrusted = [string[]]($defaultTrusted + $currentSid)
$tempFolder = [IO.Path]::GetTempPath().TrimEnd('\')
function Test-ProtectionResult([string]$Path, [string[]]$Trusted = $testTrusted) {
	$arguments = [object[]]@($Path, $tempFolder, $Trusted, $null)
	return [bool]$protectionMethod.Invoke($null, $arguments)
}
$fakeFolder = Join-Path ([IO.Path]::GetTempPath()) ('SelfXPwshTest_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fakeFolder -Force | Out-Null
$fakeExe = Join-Path $fakeFolder 'pwsh.exe'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination $fakeExe
& icacls.exe $fakeFolder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "*$($currentSid):(OI)(CI)F" | Out-Null
Assert-True (Test-ProtectionResult $fakeExe) 'Folder for administrators only: protected'
# N3: every identity outside SYSTEM, Administrators and TrustedInstaller counts as normal users.
Assert-True (-not (Test-ProtectionResult $fakeExe $defaultTrusted)) 'N3: an account outside the trusted identities with full control is refused'
& icacls.exe $fakeFolder /grant '*S-1-5-32-545:(OI)(CI)M' | Out-Null
Assert-True (-not (Test-ProtectionResult $fakeExe)) 'Users can modify the folder: not protected (nothing is started)'
& icacls.exe $fakeFolder /remove:g '*S-1-5-32-545' | Out-Null
& icacls.exe $fakeFolder /grant '*S-1-1-0:(OI)(CI)W' | Out-Null
Assert-True (-not (Test-ProtectionResult $fakeExe)) 'Everyone can write: not protected'
& icacls.exe $fakeFolder /remove:g '*S-1-1-0' | Out-Null
& icacls.exe $fakeFolder /grant '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
Assert-True (Test-ProtectionResult $fakeExe) 'Users can read and run: protected'
# CREATOR OWNER rules that only apply to child items (inherit only, as in Program Files) say nothing about the folder itself.
& icacls.exe $fakeFolder /grant '*S-1-3-0:(OI)(CI)(IO)F' | Out-Null
Assert-True (Test-ProtectionResult $fakeExe) 'N3: CREATOR OWNER rule for child items only (inherit only): protected'
& icacls.exe $fakeFolder /remove:g '*S-1-3-0' | Out-Null
Assert-True (-not (Test-ProtectionResult (Join-Path $fakeFolder 'missing.exe'))) 'Rights cannot be read: not protected (fail closed)'
# N3: the folders above pwsh.exe count too: a normal user who may delete items in a parent folder could replace the folder below it.
$fakeParent = Join-Path ([IO.Path]::GetTempPath()) ('SelfXPwshParent_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fakeParent -Force | Out-Null
& icacls.exe $fakeParent /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "*$($currentSid):(OI)(CI)F" | Out-Null
$fakeInner = Join-Path $fakeParent 'Inner'
New-Item -ItemType Directory -Path $fakeInner -Force | Out-Null
$fakeInnerExe = Join-Path $fakeInner 'pwsh.exe'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination $fakeInnerExe
Assert-True (Test-ProtectionResult $fakeInnerExe) 'N3: parent folder for administrators only: protected'
& icacls.exe $fakeParent /grant '*S-1-5-32-545:(DC)' | Out-Null
Assert-True (-not (Test-ProtectionResult $fakeInnerExe)) 'N3: Users may delete items in the parent folder: not protected'
& icacls.exe $fakeParent /remove:g '*S-1-5-32-545' | Out-Null
& icacls.exe $fakeParent /grant '*S-1-5-32-545:(RX)' '*S-1-5-11:(AD)' | Out-Null
Assert-True (Test-ProtectionResult $fakeInnerExe) 'N3: Users may only read and create folders in the parent folder: protected'
Remove-Item -LiteralPath $fakeFolder, $fakeParent -Recurse -Force -ErrorAction SilentlyContinue

# --- N4: the service checks the installed files against SelfX.Code.json and SelfX.Config.json before every start ---
$verifyMethod = [SelfX.SelfXService].GetMethod('VerifyInstalledFiles', [Reflection.BindingFlags]'NonPublic,Static')
Assert-True ($null -ne $verifyMethod) 'N4: the service has the file list check'
if ($verifyMethod) {
	function Test-FileList([string]$Root) {
		$arguments = [object[]]@($Root, $null)
		$ok = [bool]$verifyMethod.Invoke($null, $arguments)
		return [pscustomobject]@{ Ok = $ok; Problems = @($arguments[1]) -join '; ' }
	}
	# Same placement as the package build: settings files and Branding go to SelfX.Config.json, everything else to SelfX.Code.json.
	function Get-ListOf([string]$Relative) {
		if ($Relative -in 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'Ticket_Config.xml', 'Network_Test_Config.xml' -or $Relative -like 'Branding/*' -or $Relative -like 'Texts/*' -or $Relative -like 'Scripts_to_run/Own_*') { return 'SelfX.Config.json' }
		return 'SelfX.Code.json'
	}
	function Write-ListFile([string]$Root, [string]$ListName, $Files) {
		$json = [ordered]@{ ManifestVersion = 1; ToolVersion = '9.9.9'; Files = $Files } | ConvertTo-Json -Depth 4
		[IO.File]::WriteAllText((Join-Path $Root $ListName), $json, (New-Object Text.UTF8Encoding($false)))
	}
	function New-FileList([string]$Root, [hashtable]$Overrides = @{}, [string]$OverrideList = 'SelfX.Code.json') {
		$lists = @{ 'SelfX.Code.json' = [ordered]@{}; 'SelfX.Config.json' = [ordered]@{} }
		foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.xml', '.exe', '.png' -and $_.Name -notin 'SelfX.Code.json', 'SelfX.Config.json' }) {
			$relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
			$lists[(Get-ListOf $relative)][$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
		}
		foreach ($key in $Overrides.Keys) { $lists[$OverrideList][$key] = $Overrides[$key] }
		foreach ($listName in $lists.Keys) { Write-ListFile $Root $listName $lists[$listName] }
	}
	$fileRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfXFilesTest_' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path (Join-Path $fileRoot 'Scripts_to_run') -Force | Out-Null
	Set-Content -LiteralPath (Join-Path $fileRoot 'HealthStatus.ps1') -Value 'Write-Output 1'
	Set-Content -LiteralPath (Join-Path $fileRoot 'Scripts_to_run\SelfX_Test.ps1') -Value 'Write-Output 2'
	Set-Content -LiteralPath (Join-Path $fileRoot 'Issues_List.xml') -Value '<Issues />'
	Set-Content -LiteralPath (Join-Path $fileRoot 'SelfXService.exe') -Value 'binary of the service'
	New-Item -ItemType Directory -Path (Join-Path $fileRoot 'Branding') -Force | Out-Null
	Set-Content -LiteralPath (Join-Path $fileRoot 'Branding\company_logo.png') -Value 'logo of the company'
	New-FileList $fileRoot
	$result = Test-FileList $fileRoot
	Assert-True $result.Ok "N4: unchanged files are accepted ($($result.Problems))"
	# The programs are part of the list: a changed program and an unlisted program are refused.
	Set-Content -LiteralPath (Join-Path $fileRoot 'SelfXService.exe') -Value 'another binary'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'changed: SelfXService.exe') "N4: a changed program is refused ($($result.Problems))"
	New-FileList $fileRoot
	Assert-True (Test-FileList $fileRoot).Ok 'N4: the changed program is accepted again after the list is rewritten'
	Set-Content -LiteralPath (Join-Path $fileRoot 'Extra.exe') -Value 'planted'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'not listed: Extra.exe') "N4: an unlisted program is refused ($($result.Problems))"
	Remove-Item -LiteralPath (Join-Path $fileRoot 'Extra.exe')
	Add-Content -LiteralPath (Join-Path $fileRoot 'Scripts_to_run\SelfX_Test.ps1') -Value 'Write-Output 3'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'changed: Scripts_to_run/SelfX_Test.ps1') "N4: a changed script is refused ($($result.Problems))"
	New-FileList $fileRoot
	Set-Content -LiteralPath (Join-Path $fileRoot 'Scripts_to_run\SelfX_New.ps1') -Value 'Write-Output 4'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'not listed: Scripts_to_run/SelfX_New.ps1') "N4: an unlisted script is refused ($($result.Problems))"
	Remove-Item -LiteralPath (Join-Path $fileRoot 'Scripts_to_run\SelfX_New.ps1')
	Set-Content -LiteralPath (Join-Path $fileRoot 'Extra.xml') -Value '<X />'
	Assert-True (-not (Test-FileList $fileRoot).Ok) 'N4: an unlisted XML file is refused'
	Remove-Item -LiteralPath (Join-Path $fileRoot 'Extra.xml')
	Set-Content -LiteralPath (Join-Path $fileRoot 'Issues_List.xml') -Value '<Issues><Action /></Issues>'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'changed: Issues_List.xml') 'N4: a changed catalog is refused'
	New-FileList $fileRoot
	Remove-Item -LiteralPath (Join-Path $fileRoot 'HealthStatus.ps1')
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'missing: HealthStatus.ps1') 'N4: a missing file is refused'
	Set-Content -LiteralPath (Join-Path $fileRoot 'HealthStatus.ps1') -Value 'Write-Output 1'
	New-FileList $fileRoot @{ '../Outside.ps1' = ('A' * 64) }
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: SelfX.Code.json invalid entry') 'N4: a name with a path traversal is refused'
	New-FileList $fileRoot @{ 'Issues_List.xml' = 'not-a-hash' } 'SelfX.Config.json'
	Assert-True ((Test-FileList $fileRoot).Problems -match 'file list: SelfX.Config.json invalid entry') 'N4: an invalid hash is refused'
	New-FileList $fileRoot
	# A changed logo of the company is reported (it is checked like every other file).
	Add-Content -LiteralPath (Join-Path $fileRoot 'Branding\company_logo.png') -Value 'x'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'changed: Branding/company_logo.png') 'N4: a changed logo is refused'
	New-FileList $fileRoot
	# Placement: a file in both lists, a settings file in the code list and a program or script of the project in the configuration list are refused.
	New-FileList $fileRoot @{ 'HealthStatus.ps1' = ('A' * 64) } 'SelfX.Config.json'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: SelfX.Config.json invalid entry') 'N4: a file in both lists or a project script in the configuration list is refused'
	New-FileList $fileRoot @{ 'Tool_Config.xml' = ('A' * 64) } 'SelfX.Code.json'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: SelfX.Code.json invalid entry') 'N4: a settings file in the code list is refused'
	New-FileList $fileRoot @{ 'SelfXService.exe' = ('A' * 64) } 'SelfX.Config.json'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: SelfX.Config.json invalid entry') 'N4: a program in the configuration list is refused'
	New-FileList $fileRoot @{ 'Scripts_to_run/SelfX_Test.ps1' = ((Get-FileHash -LiteralPath (Join-Path $fileRoot 'Scripts_to_run\SelfX_Test.ps1') -Algorithm SHA256).Hash) } 'SelfX.Config.json'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: SelfX.Config.json invalid entry') 'N4: a file that is already in the code list is refused in the configuration list too (listed twice)'
	# An own script of the company in the configuration list is accepted.
	Set-Content -LiteralPath (Join-Path $fileRoot 'Scripts_to_run\Own_Action.ps1') -Value 'Write-Output 5'
	New-FileList $fileRoot
	$result = Test-FileList $fileRoot
	Assert-True $result.Ok "N4: an own script in the configuration list is accepted ($($result.Problems))"
	Remove-Item -LiteralPath (Join-Path $fileRoot 'Scripts_to_run\Own_Action.ps1')
	# A text override of the company (Texts/<culture>.xml) belongs in the configuration list; nothing below Texts may be in the code list.
	New-Item -ItemType Directory -Path (Join-Path $fileRoot 'Texts') -Force | Out-Null
	Set-Content -LiteralPath (Join-Path $fileRoot 'Texts\de.xml') -Value '<SelfX_Language Culture="de" />'
	New-FileList $fileRoot
	$result = Test-FileList $fileRoot
	Assert-True $result.Ok "text overrides: Texts/de.xml in the configuration list is accepted ($($result.Problems))"
	Add-Content -LiteralPath (Join-Path $fileRoot 'Texts\de.xml') -Value ' '
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'changed: Texts/de.xml') 'text overrides: a changed Texts/de.xml is refused'
	New-FileList $fileRoot
	New-FileList $fileRoot @{ 'Texts/de-AT.xml' = ('A' * 64) } 'SelfX.Code.json'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: SelfX.Code.json invalid entry') 'text overrides: a file below Texts in the code list is refused'
	New-FileList $fileRoot @{ 'Texts/x.ps1' = ('A' * 64) } 'SelfX.Config.json'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: SelfX.Config.json invalid entry') 'text overrides: a script below Texts in the configuration list is refused'
	New-FileList $fileRoot @{ 'Texts/sub/de.xml' = ('A' * 64) } 'SelfX.Config.json'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: SelfX.Config.json invalid entry') 'text overrides: a sub folder below Texts in the configuration list is refused'
	Remove-Item -LiteralPath (Join-Path $fileRoot 'Texts') -Recurse -Force
	New-FileList $fileRoot
	# The old SelfX.Files.json of an earlier version is not a list any more: left in the folder it is an unlisted file.
	Set-Content -LiteralPath (Join-Path $fileRoot 'SelfX.Files.json') -Value '{"ManifestVersion":1,"Files":{}}'
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'not listed: SelfX.Files.json') 'N4: a left-over SelfX.Files.json is refused'
	Remove-Item -LiteralPath (Join-Path $fileRoot 'SelfX.Files.json')
	foreach ($listName in 'SelfX.Code.json', 'SelfX.Config.json') {
		New-FileList $fileRoot
		Set-Content -LiteralPath (Join-Path $fileRoot $listName) -Value '{ broken'
		$result = Test-FileList $fileRoot
		Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: |check failed') "N4: a broken $listName is refused (fail closed)"
		Set-Content -LiteralPath (Join-Path $fileRoot $listName) -Value '{"ManifestVersion":2,"Files":{"a.ps1":"%s"}}'.Replace('%s', ('A' * 64))
		Assert-True ((Test-FileList $fileRoot).Problems -match "$([regex]::Escape($listName)) unsupported format") "N4: an unknown format of $listName is refused"
		Remove-Item -LiteralPath (Join-Path $fileRoot $listName)
		$result = Test-FileList $fileRoot
		Assert-True ((-not $result.Ok) -and $result.Problems -match "file list: $([regex]::Escape($listName)) missing") "N4: a missing $listName is refused (fail closed)"
	}
	# A junction in the way is refused: the files behind it are not the files of the package.
	New-FileList $fileRoot
	$elsewhere = Join-Path ([IO.Path]::GetTempPath()) ('SelfXFilesElsewhere_' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
	Copy-Item -LiteralPath (Join-Path $fileRoot 'Scripts_to_run\SelfX_Test.ps1') -Destination $elsewhere
	Remove-Item -LiteralPath (Join-Path $fileRoot 'Scripts_to_run') -Recurse -Force
	New-Item -ItemType Junction -Path (Join-Path $fileRoot 'Scripts_to_run') -Target $elsewhere | Out-Null
	$result = Test-FileList $fileRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'link: ') "N4: a junction is refused ($($result.Problems))"
	(Get-Item -LiteralPath (Join-Path $fileRoot 'Scripts_to_run')).Delete()
	Remove-Item -LiteralPath $elsewhere, $fileRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# --- N1/N2: Tool_Config.xml and the catalog are checked first; every file type in the install folder must be listed ---
if ($verifyMethod) {
	$checkRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfXFilesTest2_' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path (Join-Path $checkRoot 'Scripts_to_run') -Force | Out-Null
	function Write-CheckList([string]$Root) {
		$lists = @{ 'SelfX.Code.json' = [ordered]@{}; 'SelfX.Config.json' = [ordered]@{} }
		foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Name -notin 'SelfX.Code.json', 'SelfX.Config.json' }) {
			$relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
			$lists[(Get-ListOf $relative)][$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
		}
		foreach ($listName in $lists.Keys) { Write-ListFile $Root $listName $lists[$listName] }
	}
	function Test-CheckList([string]$Root) {
		$arguments = [object[]]@($Root, $null)
		$ok = [bool]$verifyMethod.Invoke($null, $arguments)
		return [pscustomobject]@{ Ok = $ok; Problems = @($arguments[1]) }
	}
	Set-Content -LiteralPath (Join-Path $checkRoot 'Tool_Config.xml') -Value '<GUI_Config />'
	Set-Content -LiteralPath (Join-Path $checkRoot 'Issues_List.xml') -Value '<Issues />'
	Set-Content -LiteralPath (Join-Path $checkRoot 'Logo.png') -Value 'image'
	Write-CheckList $checkRoot
	$result = Test-CheckList $checkRoot
	Assert-True $result.Ok "N2: a list of all files (also images) is accepted ($($result.Problems -join '; '))"
	# N2: any file type next to the checked ones is reported, also in a sub folder and in the folder of the libraries.
	foreach ($name in 'Extra.config', 'Extra.json', 'Extra.cmd', 'Extra.bat', 'Extra.vbs', 'Extra.psc1', 'Extra.dll.config', 'Extra.exe.manifest', 'Scripts_to_run\Extra.json') {
		Set-Content -LiteralPath (Join-Path $checkRoot $name) -Value 'planted'
		$result = Test-CheckList $checkRoot
		$expected = 'not listed: ' + $name.Replace('\', '/')
		Assert-True ((-not $result.Ok) -and ($result.Problems -contains $expected)) "N2: an unlisted file '$name' is refused ($($result.Problems -join '; '))"
		Remove-Item -LiteralPath (Join-Path $checkRoot $name)
	}
	Assert-True (Test-CheckList $checkRoot).Ok 'N2: accepted again after the planted files are removed (the list itself is not reported)'
	# N1: Tool_Config.xml and the catalog come first although 25 other files are wrong, and the cut-off is noted.
	foreach ($index in 1..25) { Set-Content -LiteralPath (Join-Path $checkRoot ('A{0:D2}.ps1' -f $index)) -Value 'Write-Output 1' }
	Write-CheckList $checkRoot
	foreach ($index in 1..25) { Add-Content -LiteralPath (Join-Path $checkRoot ('A{0:D2}.ps1' -f $index)) -Value 'Write-Output 2' }
	Add-Content -LiteralPath (Join-Path $checkRoot 'Tool_Config.xml') -Value '<!-- changed -->'
	Add-Content -LiteralPath (Join-Path $checkRoot 'Issues_List.xml') -Value '<!-- changed -->'
	$result = Test-CheckList $checkRoot
	Assert-True ((-not $result.Ok) -and ((@($result.Problems[0..1]) | Sort-Object) -join '|') -eq 'changed: Issues_List.xml|changed: Tool_Config.xml') "N1: Tool_Config.xml and Issues_List.xml are reported first ($($result.Problems[0..2] -join '; '))"
	Assert-True ($result.Problems.Count -eq 21 -and $result.Problems[20] -eq 'check stopped: more problems may exist') "N1: the cut-off at 20 problems is noted as the last entry ($($result.Problems.Count) entries)"
	# Exactly 20 problems and nothing more: no cut-off entry.
	foreach ($index in 1..25) { Remove-Item -LiteralPath (Join-Path $checkRoot ('A{0:D2}.ps1' -f $index)) }
	Write-CheckList $checkRoot
	foreach ($index in 1..18) { Set-Content -LiteralPath (Join-Path $checkRoot ('A{0:D2}.ps1' -f $index)) -Value 'x' }
	Write-CheckList $checkRoot
	foreach ($index in 1..18) { Add-Content -LiteralPath (Join-Path $checkRoot ('A{0:D2}.ps1' -f $index)) -Value 'y' }
	Add-Content -LiteralPath (Join-Path $checkRoot 'Tool_Config.xml') -Value '<!-- changed again -->'
	Add-Content -LiteralPath (Join-Path $checkRoot 'Issues_List.xml') -Value '<!-- changed again -->'
	$result = Test-CheckList $checkRoot
	Assert-True ((-not $result.Ok) -and $result.Problems.Count -eq 20 -and ($result.Problems -notcontains 'check stopped: more problems may exist')) "N1: 20 problems (the changed Tool_Config.xml, Issues_List.xml and 18 files) are complete, no cut-off entry ($($result.Problems.Count) entries)"
	Remove-Item -LiteralPath $checkRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 3.1.0: layout App/Config. The configuration folder, the only path of a settings file, the scripts of the company and the file check
# of both folders and of the install folder above them ---
$flags = [Reflection.BindingFlags]'NonPublic,Static'
$configRootMethod = [SelfX.SelfXService].GetMethod('GetConfigRoot', $flags)
$configFileMethod = [SelfX.SelfXService].GetMethod('GetConfigFilePath', $flags, $null, [type[]]@([string], [string]), $null)
$layoutMethod = [SelfX.SelfXService].GetMethod('VerifyInstalledLayout', $flags)
$resolveMethod = [SelfX.SelfXService].GetMethod('ResolveScriptPath', $flags)
Assert-True ($null -ne $configRootMethod) 'Layout: the service has GetConfigRoot'
Assert-True ($null -ne $configFileMethod) 'Layout: the service has GetConfigFilePath'
Assert-True ($null -ne $layoutMethod) 'Layout: the service has VerifyInstalledLayout'
Assert-True ($null -ne $resolveMethod) 'Layout: the service has ResolveScriptPath'
$serviceText = [IO.File]::ReadAllText($source)
Assert-True ($serviceText -notmatch 'Path\.Combine\(installRoot, "(Tool_Config|Issues_List|Health_Config|Ticket_Config|Network_Test_Config)\.xml"\)') 'Layout: no settings file is built from the code folder any more'
Assert-True ($serviceText.Contains('ResolveScriptPath(installRoot, configRoot, "Scripts_to_run", scriptName)')) 'Layout: RUN resolves the script through ResolveScriptPath'
if ($configRootMethod -and $configFileMethod -and $layoutMethod -and $resolveMethod) {
	foreach ($case in @(@('C:\Program Files\SelfX\App', 'C:\Program Files\SelfX\Config'), @('C:\Program Files\SelfX\app\', 'C:\Program Files\SelfX\Config'), @('C:\Repo\SelfX Service\Sources', 'C:\Repo\SelfX Service\Sources'), @('C:\Program Files\SelfX\App\Sub', 'C:\Program Files\SelfX\App\Sub'), @('C:\Program Files\SelfX', 'C:\Program Files\SelfX'))) {
		Assert-True ($configRootMethod.Invoke($null, [object[]]@($case[0])) -eq $case[1]) "Layout: the configuration folder of '$($case[0])' is '$($case[1])'"
	}
	Assert-True ($configFileMethod.Invoke($null, [object[]]@('C:\X\Config', 'Tool_Config.xml')) -eq 'C:\X\Config\Tool_Config.xml') 'Layout: GetConfigFilePath gives the settings file in the configuration folder'
	foreach ($bad in '..\Tool_Config.xml', 'Branding\logo.png', 'C:\Windows\Tool_Config.xml', 'tool_config.xml', 'Tool_Config.xml ', 'Scripts_to_run\Own.ps1', '') {
		$threw = $false
		try { [void]$configFileMethod.Invoke($null, [object[]]@('C:\X\Config', $bad)) } catch { $threw = $true }
		Assert-True $threw "Layout: GetConfigFilePath refuses '$bad' (only the fixed names of the settings files)"
	}

	function Write-LayoutLists([string]$Root) {
		# Lists of the layout: App against SelfX.Code.json, Config against SelfX.Config.json (names relative to the folder).
		foreach ($part in @(@{ Folder = 'App'; List = 'SelfX.Code.json' }, @{ Folder = 'Config'; List = 'SelfX.Config.json' })) {
			$folder = Join-Path $Root $part.Folder
			$files = [ordered]@{}
			foreach ($file in @(Get-ChildItem -LiteralPath $folder -Recurse -File | Where-Object { $_.Name -ne $part.List })) {
				$files[$file.FullName.Substring($folder.Length + 1).Replace('\', '/')] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
			}
			$json = [ordered]@{ ManifestVersion = 1; Files = $files } | ConvertTo-Json -Depth 4
			[IO.File]::WriteAllText((Join-Path $folder $part.List), $json, (New-Object Text.UTF8Encoding($false)))
		}
	}
	function Test-Layout([string]$Root) {
		$arguments = [object[]]@([string](Join-Path $Root 'App'), [string](Join-Path $Root 'Config'), $null)
		$ok = [bool]$layoutMethod.Invoke($null, $arguments)
		return [pscustomobject]@{ Ok = $ok; Problems = @($arguments[2]) -join '; ' }
	}
	function Resolve-Script([string]$Root, [string]$Folder, [string]$Name, [switch]$Flat) {
		$config = if ($Flat) { Join-Path $Root 'App' } else { Join-Path $Root 'Config' }
		return $resolveMethod.Invoke($null, [object[]]@([string](Join-Path $Root 'App'), [string]$config, [string]$Folder, [string]$Name))
	}
	$layoutRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfXLayoutTest_' + [guid]::NewGuid().ToString('N'))
	foreach ($folder in 'App\Scripts_to_run', 'App\HealthChecks', 'Config\Scripts_to_run', 'Config\Branding') { New-Item -ItemType Directory -Path (Join-Path $layoutRoot $folder) -Force | Out-Null }
	Set-Content -LiteralPath (Join-Path $layoutRoot 'App\HealthStatus.ps1') -Value 'Write-Output 1'
	Set-Content -LiteralPath (Join-Path $layoutRoot 'App\SelfXService.exe') -Value 'binary of the service'
	Set-Content -LiteralPath (Join-Path $layoutRoot 'App\Scripts_to_run\SelfX_Test.ps1') -Value 'Write-Output 2'
	Set-Content -LiteralPath (Join-Path $layoutRoot 'App\HealthChecks\Check-Compliance.ps1') -Value 'exit 0'
	Set-Content -LiteralPath (Join-Path $layoutRoot 'Config\Tool_Config.xml') -Value '<GUI_Config />'
	Set-Content -LiteralPath (Join-Path $layoutRoot 'Config\Issues_List.xml') -Value '<Issues />'
	Set-Content -LiteralPath (Join-Path $layoutRoot 'Config\Branding\company_logo.png') -Value 'logo'
	Set-Content -LiteralPath (Join-Path $layoutRoot 'Config\Scripts_to_run\Own_Action.ps1') -Value 'Write-Output 3'
	Write-LayoutLists $layoutRoot
	$result = Test-Layout $layoutRoot
	Assert-True $result.Ok "Layout: App and Config that match their lists are accepted ($($result.Problems))"
	# Install folder above App and Config: a file or a non-empty folder of an older layout is refused, an empty folder is allowed.
	Set-Content -LiteralPath (Join-Path $layoutRoot 'Tool_Config.xml') -Value '<GUI_Config />'
	$result = Test-Layout $layoutRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'not listed: \.\./Tool_Config\.xml') "Layout: a file of the old layout next to App and Config is refused ($($result.Problems))"
	Remove-Item -LiteralPath (Join-Path $layoutRoot 'Tool_Config.xml')
	New-Item -ItemType Directory -Path (Join-Path $layoutRoot 'Scripts_to_run') -Force | Out-Null
	Assert-True (Test-Layout $layoutRoot).Ok 'Layout: an empty folder of the old layout (still in use) is allowed'
	Set-Content -LiteralPath (Join-Path $layoutRoot 'Scripts_to_run\SelfX_Device_Restart.ps1') -Value 'old'
	$result = Test-Layout $layoutRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'not listed: \.\./Scripts_to_run/SelfX_Device_Restart\.ps1') "Layout: a file in a folder of the old layout is refused ($($result.Problems))"
	Remove-Item -LiteralPath (Join-Path $layoutRoot 'Scripts_to_run') -Recurse -Force
	# A file in the wrong folder: every folder is checked against its own list only.
	Copy-Item -LiteralPath (Join-Path $layoutRoot 'Config\Tool_Config.xml') -Destination (Join-Path $layoutRoot 'App\Tool_Config.xml')
	$result = Test-Layout $layoutRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match '(^|; )not listed: Tool_Config\.xml') "Layout: a settings file in App is refused although Config lists it ($($result.Problems))"
	Remove-Item -LiteralPath (Join-Path $layoutRoot 'App\Tool_Config.xml')
	Copy-Item -LiteralPath (Join-Path $layoutRoot 'App\Scripts_to_run\SelfX_Test.ps1') -Destination (Join-Path $layoutRoot 'Config\Scripts_to_run\SelfX_Test.ps1')
	$result = Test-Layout $layoutRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'not listed: Config/Scripts_to_run/SelfX_Test\.ps1') "Layout: a project script in Config is refused although App lists it ($($result.Problems))"
	Remove-Item -LiteralPath (Join-Path $layoutRoot 'Config\Scripts_to_run\SelfX_Test.ps1')
	Set-Content -LiteralPath (Join-Path $layoutRoot 'Config\Scripts_to_run\Planted.ps1') -Value 'calc.exe'
	$result = Test-Layout $layoutRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'not listed: Config/Scripts_to_run/Planted\.ps1') "Layout: an unlisted own script in Config is refused ($($result.Problems))"
	Remove-Item -LiteralPath (Join-Path $layoutRoot 'Config\Scripts_to_run\Planted.ps1')
	Add-Content -LiteralPath (Join-Path $layoutRoot 'Config\Issues_List.xml') -Value '<!-- changed -->'
	$result = Test-Layout $layoutRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'changed: Issues_List\.xml') "Layout: a changed catalog in Config is refused ($($result.Problems))"
	Write-LayoutLists $layoutRoot
	# The list of the other folder in a folder: SelfX.Config.json in App is an unlisted file, a missing SelfX.Config.json in Config is refused.
	Move-Item -LiteralPath (Join-Path $layoutRoot 'Config\SelfX.Config.json') -Destination (Join-Path $layoutRoot 'App\SelfX.Config.json')
	$result = Test-Layout $layoutRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'file list: SelfX\.Config\.json missing') "Layout: SelfX.Config.json in App instead of Config is refused ($($result.Problems))"
	Move-Item -LiteralPath (Join-Path $layoutRoot 'App\SelfX.Config.json') -Destination (Join-Path $layoutRoot 'Config\SelfX.Config.json')
	# A missing folder Config or a link instead of it is refused (fail closed).
	Rename-Item -LiteralPath (Join-Path $layoutRoot 'Config') -NewName 'Config.moved'
	$result = Test-Layout $layoutRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'missing: Config') "Layout: a missing folder Config is refused ($($result.Problems))"
	New-Item -ItemType Junction -Path (Join-Path $layoutRoot 'Config') -Target (Join-Path $layoutRoot 'Config.moved') | Out-Null
	$result = Test-Layout $layoutRoot
	Assert-True ((-not $result.Ok) -and $result.Problems -match 'link: Config') "Layout: a junction instead of the folder Config is refused ($($result.Problems))"
	(Get-Item -LiteralPath (Join-Path $layoutRoot 'Config')).Delete()
	Rename-Item -LiteralPath (Join-Path $layoutRoot 'Config.moved') -NewName 'Config'
	Assert-True (Test-Layout $layoutRoot).Ok 'Layout: accepted again'

	# Scripts: the script of the project wins, an own script of the company only with its entry and current SHA256 in SelfX.Config.json.
	$appScript = Join-Path $layoutRoot 'App\Scripts_to_run\SelfX_Test.ps1'
	$ownScript = Join-Path $layoutRoot 'Config\Scripts_to_run\Own_Action.ps1'
	Assert-True ((Resolve-Script $layoutRoot 'Scripts_to_run' 'SelfX_Test.ps1') -eq $appScript) 'Scripts: a script of the project is started from App'
	Assert-True ((Resolve-Script $layoutRoot 'Scripts_to_run' 'Own_Action.ps1') -eq $ownScript) 'Scripts: a listed own script is started from Config'
	Assert-True ((Resolve-Script $layoutRoot 'HealthChecks' 'Check-Compliance.ps1') -eq (Join-Path $layoutRoot 'App\HealthChecks\Check-Compliance.ps1')) 'Scripts: a health script of the project is found in App'
	Copy-Item -LiteralPath $appScript -Destination (Join-Path $layoutRoot 'Config\Scripts_to_run\SelfX_Test.ps1')
	Assert-True ((Resolve-Script $layoutRoot 'Scripts_to_run' 'SelfX_Test.ps1') -eq $appScript) 'Scripts: a script of the same name in Config cannot replace the script of the project'
	Remove-Item -LiteralPath (Join-Path $layoutRoot 'Config\Scripts_to_run\SelfX_Test.ps1')
	Add-Content -LiteralPath $ownScript -Value 'Write-Output 4'
	Assert-True ($null -eq (Resolve-Script $layoutRoot 'Scripts_to_run' 'Own_Action.ps1')) 'Scripts: a changed own script is not started (also with Service_FileCheck=Audit)'
	Write-LayoutLists $layoutRoot
	Set-Content -LiteralPath (Join-Path $layoutRoot 'Config\Scripts_to_run\Unlisted.ps1') -Value 'calc.exe'
	Assert-True ($null -eq (Resolve-Script $layoutRoot 'Scripts_to_run' 'Unlisted.ps1')) 'Scripts: an own script without an entry in SelfX.Config.json is not started'
	Remove-Item -LiteralPath (Join-Path $layoutRoot 'Config\Scripts_to_run\Unlisted.ps1')
	foreach ($bad in '..\SelfX_Test.ps1', '..\..\App\Scripts_to_run\SelfX_Test.ps1', 'Scripts_to_run\Own_Action.ps1', 'C:\Windows\x.ps1', 'Own_Action.ps1:x', 'Own_Action', '') {
		Assert-True ($null -eq (Resolve-Script $layoutRoot 'Scripts_to_run' $bad)) "Scripts: the name '$bad' is refused"
	}
	Assert-True ($null -eq (Resolve-Script $layoutRoot 'Branding' 'Own_Action.ps1')) 'Scripts: only the folders Scripts_to_run and HealthChecks are used'
	Assert-True ($null -eq (Resolve-Script $layoutRoot 'Scripts_to_run' 'Own_Action.ps1' -Flat)) 'Scripts: in the flat layout no script is taken from another folder'
	Rename-Item -LiteralPath (Join-Path $layoutRoot 'Config\SelfX.Config.json') -NewName 'SelfX.Config.json.moved'
	Assert-True ($null -eq (Resolve-Script $layoutRoot 'Scripts_to_run' 'Own_Action.ps1')) 'Scripts: without SelfX.Config.json no own script is started'
	Rename-Item -LiteralPath (Join-Path $layoutRoot 'Config\SelfX.Config.json.moved') -NewName 'SelfX.Config.json'
	Set-Content -LiteralPath (Join-Path $layoutRoot 'Config\SelfX.Config.json') -Value '{ broken'
	Assert-True ($null -eq (Resolve-Script $layoutRoot 'Scripts_to_run' 'Own_Action.ps1')) 'Scripts: a broken SelfX.Config.json starts no own script'
	Write-LayoutLists $layoutRoot
	$elsewhere = Join-Path ([IO.Path]::GetTempPath()) ('SelfXLayoutElsewhere_' + [guid]::NewGuid().ToString('N'))
	Move-Item -LiteralPath (Join-Path $layoutRoot 'Config\Scripts_to_run') -Destination $elsewhere
	New-Item -ItemType Junction -Path (Join-Path $layoutRoot 'Config\Scripts_to_run') -Target $elsewhere | Out-Null
	Assert-True ($null -eq (Resolve-Script $layoutRoot 'Scripts_to_run' 'Own_Action.ps1')) 'Scripts: an own script behind a junction is not started'
	(Get-Item -LiteralPath (Join-Path $layoutRoot 'Config\Scripts_to_run')).Delete()
	Remove-Item -LiteralPath $layoutRoot, $elsewhere -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Trust mode: the anchor HKLM\SOFTWARE\SelfX\Trust, signatures through pinned handles, the signed catalogs, the cache ---
# The anchor is tested in a key of the current user. The signatures are made with self-signed test certificates
# (Cert:\CurrentUser\My, removed at the end). Windows accepts them only when they are trusted roots: with administrator rights in
# CI, or with SELFX_TEST_ALLOW_ROOT_IMPORT=1, they are added to the trusted roots for the time of the test (same rule as
# Test-InstallBinaries.ps1). Without that, the cases that need an accepted signature are skipped and the others expect the
# result UntrustedRoot where the signature itself fits.
$anchorMethod = [SelfX.SelfXService].GetMethod('ReadTrustAnchor', $flags)
$signedMethod = [SelfX.SelfXService].GetMethod('VerifySignedLayout', $flags)
$pinnedType = [SelfX.SelfXService].GetNestedType('PinnedFiles', [Reflection.BindingFlags]'NonPublic')
$cacheType = [SelfX.SelfXService].GetNestedType('SignatureCache', [Reflection.BindingFlags]'NonPublic')
$trustType = [SelfX.SelfXService].Assembly.GetType('SelfX.SelfXTrust')
Assert-True ($null -ne $anchorMethod) 'Trust: the service has ReadTrustAnchor'
Assert-True ($null -ne $signedMethod) 'Trust: the service has VerifySignedLayout'
Assert-True (($null -ne $pinnedType) -and ($null -ne $cacheType) -and ($null -ne $trustType)) 'Trust: the service has PinnedFiles, SignatureCache and SelfXTrust'
Assert-True ($serviceText.Contains('ReadTrustAnchor(RegistryHive.LocalMachine, TrustKeyPath, TrustAnchorWriterSids, out anchorProblem)')) 'Trust: the service reads the anchor from HKLM with the fixed key and the fixed identities'
Assert-True ($serviceText.Contains('const string TrustKeyPath = @"SOFTWARE\SelfX\Trust";')) 'Trust: the key is SOFTWARE\SelfX\Trust'
Assert-True ($serviceText.Contains('static readonly string[] TrustAnchorWriterSids = { "S-1-5-18", "S-1-5-32-544" };')) 'Trust: only SYSTEM and Administrators may own or change the anchor (by SID)'
Assert-True ($serviceText.Contains('if (!CheckInstalledFiles(scriptName, scriptPath, out pinned))')) 'Trust: every start goes through the check with the anchor'
Assert-True ($serviceText.Contains('if (pinned != null) pinned.Dispose();')) 'Trust: the pinned files are released after the script has ended'
Assert-True ($serviceText -match 'WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT \| WTD_CACHE_ONLY_URL_RETRIEVAL') 'Trust: revocation is checked from the cache only (no network request)'
Assert-True (($serviceText -split 'data\.dwUIChoice = WTD_UI_NONE;').Count -eq 2) 'Trust: WinVerifyTrust never shows a window'
Assert-True ($serviceText -notmatch '(?i)"BUILTIN\\|"NT AUTHORITY|Administratoren') 'Trust: the service names accounts by SID only'

if ($anchorMethod -and $signedMethod -and $pinnedType -and $cacheType -and $trustType) {
	# 1. The anchor.
	$anchorRoot = 'Software\SelfXServiceTest_' + [guid]::NewGuid().ToString('N')
	$anchorKey = "$anchorRoot\Trust"
	$anchorWriters = [string[]]@('S-1-5-18', 'S-1-5-32-544', $currentSid)
	$hkcu = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
	function Read-Anchor([string[]]$Writers = $anchorWriters) {
		$arguments = [object[]]@([Microsoft.Win32.RegistryHive]::CurrentUser, [string]$anchorKey, $Writers, $null)
		$anchor = $anchorMethod.Invoke($null, $arguments)
		$mode = $null; $signers = @()
		if ($null -ne $anchor) {
			$mode = if ($anchor.GetType().GetField('Signature').GetValue($anchor)) { 'Signature' } else { 'Hash' }
			$signers = @($anchor.GetType().GetField('Signers').GetValue($anchor))
		}
		return [pscustomobject]@{ Mode = $mode; Signers = ($signers -join ','); Problem = [string]$arguments[3] }
	}
	function Set-AnchorRights([string[]]$ReadSids = @('S-1-5-32-545'), [hashtable]$Extra = @{}) {
		# Rights like Set-SelfXTrustAnchor of Install.ps1, plus full control for the current user (the test must remove the key again).
		$security = New-Object System.Security.AccessControl.RegistrySecurity
		$security.SetAccessRuleProtection($true, $false)
		foreach ($sid in 'S-1-5-18', 'S-1-5-32-544', $currentSid) {
			$security.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule((New-Object System.Security.Principal.SecurityIdentifier($sid)), [System.Security.AccessControl.RegistryRights]::FullControl, 'ContainerInherit', 'None', 'Allow')))
		}
		foreach ($sid in $ReadSids) {
			$security.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule((New-Object System.Security.Principal.SecurityIdentifier($sid)), [System.Security.AccessControl.RegistryRights]::ReadKey, 'ContainerInherit', 'None', 'Allow')))
		}
		foreach ($sid in $Extra.Keys) {
			$security.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule((New-Object System.Security.Principal.SecurityIdentifier($sid)), [System.Security.AccessControl.RegistryRights]$Extra[$sid], 'ContainerInherit', 'None', 'Allow')))
		}
		$key = $hkcu.OpenSubKey($anchorKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]'ChangePermissions, ReadKey')
		try { $key.SetAccessControl($security) } finally { $key.Dispose() }
	}
	function Set-AnchorValues([scriptblock]$Action) {
		$key = $hkcu.CreateSubKey($anchorKey)
		try { foreach ($name in @($key.GetValueNames())) { $key.DeleteValue($name, $false) }; & $Action $key } finally { $key.Dispose() }
	}
	$thumbA = 'A1' * 20
	$thumbB = 'b2' * 20
	try {
		$read = Read-Anchor
		Assert-True (($null -eq $read.Mode) -and ($read.Problem -eq 'the key is missing')) "Anchor: a missing key is a problem, nothing starts ($($read.Problem))"
		Set-AnchorValues { param($key) $key.SetValue('Mode', 'Hash', 'String') }
		Set-AnchorRights
		$read = Read-Anchor
		Assert-True (($read.Mode -eq 'Hash') -and (-not $read.Problem)) "Anchor: Mode = Hash is read ($($read.Problem))"
		Set-AnchorValues { param($key) $key.SetValue('Mode', 'Signature', 'String'); $key.SetValue('Signers', [string[]]@($thumbA, $thumbB), 'MultiString') }
		$read = Read-Anchor
		Assert-True (($read.Mode -eq 'Signature') -and ($read.Signers -eq "$thumbA,$($thumbB.ToUpperInvariant())")) "Anchor: Mode = Signature with two signers is read, thumbprints in upper case ($($read.Signers) $($read.Problem))"
		$invalid = [ordered]@{
			'Mode in another case'                     = { param($key) $key.SetValue('Mode', 'hash', 'String') }
			'Mode with another text'                   = { param($key) $key.SetValue('Mode', 'None', 'String') }
			'Mode as a number'                         = { param($key) $key.SetValue('Mode', 1, 'DWord') }
			'Mode as an expandable text'               = { param($key) $key.SetValue('Mode', 'Hash', 'ExpandString') }
			'no Mode'                                  = { param($key) $key.SetValue('Signers', [string[]]@($thumbA), 'MultiString') }
			'Signature without Signers'                = { param($key) $key.SetValue('Mode', 'Signature', 'String') }
			'Signature with Signers as one text'       = { param($key) $key.SetValue('Mode', 'Signature', 'String'); $key.SetValue('Signers', $thumbA, 'String') }
			'Signature with an empty list'             = { param($key) $key.SetValue('Mode', 'Signature', 'String'); $key.SetValue('Signers', [string[]]@(), 'MultiString') }
			'Signature with a short thumbprint'        = { param($key) $key.SetValue('Mode', 'Signature', 'String'); $key.SetValue('Signers', [string[]]@($thumbA, 'A1B2'), 'MultiString') }
			'Signature with a thumbprint and a space'  = { param($key) $key.SetValue('Mode', 'Signature', 'String'); $key.SetValue('Signers', [string[]]@("$thumbA "), 'MultiString') }
			'Signature with 11 signers'                = { param($key) $key.SetValue('Mode', 'Signature', 'String'); $key.SetValue('Signers', [string[]]@(0..10 | ForEach-Object { '{0:X2}' -f $_ * 20 }), 'MultiString') }
		}
		foreach ($case in $invalid.Keys) {
			Set-AnchorValues $invalid[$case]
			$read = Read-Anchor
			Assert-True (($null -eq $read.Mode) -and $read.Problem) "Anchor: $case is refused ($($read.Problem))"
		}
		Set-AnchorValues { param($key) $key.SetValue('Mode', 'Hash', 'String'); $key.SetValue('Signers', 'left over', 'String') }
		Assert-True ((Read-Anchor).Mode -eq 'Hash') 'Anchor: in the mode Hash a left-over value Signers does not matter'
		# Unsafe anchors: who owns the key and who may change it.
		$read = Read-Anchor -Writers ([string[]]@('S-1-5-18', 'S-1-5-32-544'))
		Assert-True (($null -eq $read.Mode) -and ($read.Problem -match 'owned by|can be changed by')) "Anchor: a key that a normal account owns or may change is refused ($($read.Problem))"
		foreach ($unsafe in @(@('S-1-5-32-545', 'SetValue'), @('S-1-5-11', 'FullControl'), @('S-1-1-0', 'CreateSubKey'), @('S-1-5-32-545', 'Delete'), @('S-1-5-4', 'ChangePermissions'), @('S-1-5-32-545', 'TakeOwnership'), @('S-1-5-32-545', 'CreateLink'))) {
			Set-AnchorRights -Extra @{ $unsafe[0] = $unsafe[1] }
			$read = Read-Anchor
			Assert-True (($null -eq $read.Mode) -and ($read.Problem -eq "the key can be changed by $($unsafe[0])")) "Anchor: $($unsafe[0]) with $($unsafe[1]) makes the anchor unsafe, nothing starts ($($read.Problem))"
		}
		Set-AnchorRights -ReadSids @('S-1-5-32-545', 'S-1-5-11', 'S-1-1-0')
		Assert-True ((Read-Anchor).Mode -eq 'Hash') 'Anchor: read rights for users do not make the anchor unsafe'
	}
	finally {
		try { $hkcu.DeleteSubKeyTree($anchorRoot, $false) } catch { }
		$hkcu.Dispose()
	}

	# 2. Signatures and catalogs.
	$isAdminTest = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	$canTrust = (($env:GITHUB_ACTIONS -eq 'true') -and $isAdminTest) -or ($env:SELFX_TEST_ALLOW_ROOT_IMPORT -eq '1')
	$rootLocation = $(if ($isAdminTest) { 'LocalMachine' } else { 'CurrentUser' })
	$accepted = $(if ($canTrust) { 'Ok' } else { 'UntrustedRoot' })
	if (-not $canTrust) {
		Write-Output 'Trust: the test certificates are not trusted roots here, so the cases that need an accepted signature are skipped (set SELFX_TEST_ALLOW_ROOT_IMPORT=1 to add two test certificates to the trusted roots until the end of the test: Cert:\LocalMachine\Root with administrator rights, otherwise Cert:\CurrentUser\Root with a question of Windows; CI runs them).'
	}
	$signedRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfXSignedTest_' + [guid]::NewGuid().ToString('N'))
	$signedApp = Join-Path $signedRoot 'App'
	$signedConfig = Join-Path $signedRoot 'Config'
	$testCertificates = New-Object System.Collections.Generic.List[string]
	$testRoots = New-Object System.Collections.Generic.List[string]
	$utf8 = New-Object System.Text.UTF8Encoding($false)
	function New-TestSigner([string]$Name) {
		$created = New-SelfSignedCertificate -Subject "CN=SelfX Service Test $Name $([guid]::NewGuid().ToString('N'))" -CertStoreLocation 'Cert:\CurrentUser\My' -Type CodeSigningCert -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyUsage DigitalSignature -NotAfter (Get-Date).AddDays(2)
		$testCertificates.Add($created.Thumbprint)
		if ($canTrust) {
			$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', $rootLocation)
			$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
			try { $store.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($created.RawData)) } finally { $store.Close() }
			$testRoots.Add($created.Thumbprint)
		}
		return (Get-Item -LiteralPath "Cert:\CurrentUser\My\$($created.Thumbprint)")
	}
	function Set-TestSignature([string[]]$Path, $Certificate) {
		foreach ($file in $Path) { $null = Set-AuthenticodeSignature -LiteralPath $file -Certificate $Certificate -HashAlgorithm SHA256 -IncludeChain NotRoot }
	}
	function Write-SignedLists($Certificate, $CatalogCertificate = $Certificate) {
		# The two lists (as Write-LayoutLists) and, next to each, its signed catalog. On a device SelfX.Code.cat is the catalog of the
		# package; here it is a catalog of the folder App. The service looks the list up by its hash, so the names do not matter.
		foreach ($part in @(@{ Folder = $signedApp; List = 'SelfX.Code.json'; Catalog = 'SelfX.Code.cat' }, @{ Folder = $signedConfig; List = 'SelfX.Config.json'; Catalog = 'SelfX.Config.cat' })) {
			$catalog = Join-Path $part.Folder $part.Catalog
			if (Test-Path -LiteralPath $catalog) { Remove-Item -LiteralPath $catalog -Force }
			$files = [ordered]@{}
			foreach ($file in @(Get-ChildItem -LiteralPath $part.Folder -Recurse -File | Where-Object { $_.Name -ne $part.List } | Sort-Object FullName)) {
				$files[$file.FullName.Substring($part.Folder.Length + 1).Replace('\', '/')] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
			}
			[IO.File]::WriteAllText((Join-Path $part.Folder $part.List), ([ordered]@{ ManifestVersion = 1; Files = $files } | ConvertTo-Json -Depth 4), $utf8)
			$temporary = Join-Path $signedRoot $part.Catalog
			$null = New-FileCatalog -Path $part.Folder -CatalogFilePath $temporary -CatalogVersion 2
			if ($CatalogCertificate) { Set-TestSignature $temporary $CatalogCertificate }
			Move-Item -LiteralPath $temporary -Destination $catalog -Force
		}
	}
	function New-SignedLayout($Certificate) {
		if (Test-Path -LiteralPath $signedRoot) { Remove-Item -LiteralPath $signedRoot -Recurse -Force }
		foreach ($folder in 'App\Scripts_to_run', 'App\WinRT', 'App\Languages', 'Config\Scripts_to_run', 'Config\Branding') { New-Item -ItemType Directory -Path (Join-Path $signedRoot $folder) -Force | Out-Null }
		$scripts = @('App\HealthStatus.ps1', 'App\SelfXPaths.ps1', 'App\Scripts_to_run\SelfX_Test.ps1', 'Config\Scripts_to_run\Own_Action.ps1') | ForEach-Object { Join-Path $signedRoot $_ }
		foreach ($file in $scripts) { [IO.File]::WriteAllText($file, "Write-Output '$(Split-Path -Leaf $file)'`r`n", $utf8) }
		# A real library: the service built for this test.
		$library = Join-Path $signedApp 'WinRT\SelfXTest.dll'
		Copy-Item -LiteralPath (Join-Path $script:serviceBuildFolder 'SelfXService.dll') -Destination $library
		[IO.File]::WriteAllText((Join-Path $signedApp 'SelfXService.exe'), 'binary of the service', $utf8)
		[IO.File]::WriteAllText((Join-Path $signedApp 'Languages\de.xml'), '<Language />', $utf8)
		[IO.File]::WriteAllText((Join-Path $signedConfig 'Tool_Config.xml'), '<GUI_Config><Service_FileCheck>Enforce</Service_FileCheck></GUI_Config>', $utf8)
		[IO.File]::WriteAllText((Join-Path $signedConfig 'Issues_List.xml'), '<Issues><Action><Script>SelfX_Test.ps1</Script><Context>System</Context></Action></Issues>', $utf8)
		[IO.File]::WriteAllText((Join-Path $signedConfig 'Health_Config.xml'), '<HealthConfig><Background Enabled="true" /></HealthConfig>', $utf8)
		[IO.File]::WriteAllText((Join-Path $signedConfig 'Branding\company_logo.png'), 'logo', $utf8)
		Set-TestSignature ($scripts + $library) $Certificate
		Write-SignedLists $Certificate
	}
	function New-Pins { return [Activator]::CreateInstance($pinnedType, $true) }
	function Test-SignedLayout([string[]]$Signers, $Cache = $null, $Pins = $null) {
		$own = ($null -eq $Pins)
		if ($own) { $Pins = New-Pins }
		try {
			if ($null -ne $Cache) { $Cache = $Cache.PSObject.BaseObject }
			$Pins = $Pins.PSObject.BaseObject
			$arguments = [object[]]@([string]$signedApp, [string]$signedConfig, $Signers, $Cache, $Pins, $null, $null)
			$ok = [bool]$signedMethod.Invoke($null, $arguments)
			return [pscustomobject]@{ Ok = $ok; Files = (@($arguments[5]) -join '; '); Signatures = (@($arguments[6]) -join '; '); Pinned = [int]$pinnedType.GetProperty('Count').GetValue($Pins) }
		}
		finally { if ($own) { ([IDisposable]$Pins).Dispose() } }
	}
	function Test-Embedded([string]$Path) {
		$stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
		try {
			$verdict = $trustType.GetMethod('VerifyEmbedded', $flags).Invoke($null, [object[]]@([string]$Path, $stream))
			return [pscustomobject]@{ Reason = [string]$verdict.GetType().GetField('Reason').GetValue($verdict); Thumbprint = [string]$verdict.GetType().GetField('Thumbprint').GetValue($verdict) }
		}
		finally { $stream.Dispose() }
	}
	function Test-Member([string]$Catalog, [string]$Path) {
		$stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
		try {
			$verdict = $trustType.GetMethod('VerifyCatalogMember', $flags).Invoke($null, [object[]]@([string]$Catalog, [string]$Path, $stream))
			return [pscustomobject]@{ Reason = [string]$verdict.GetType().GetField('Reason').GetValue($verdict); Thumbprint = [string]$verdict.GetType().GetField('Thumbprint').GetValue($verdict) }
		}
		finally { $stream.Dispose() }
	}
	try {
		$certA = New-TestSigner 'A'
		$certB = New-TestSigner 'B'
		$signersA = [string[]]@($certA.Thumbprint)
		$signersB = [string[]]@($certB.Thumbprint)
		New-SignedLayout $certA
		$script = Join-Path $signedApp 'Scripts_to_run\SelfX_Test.ps1'
		$ownScript = Join-Path $signedConfig 'Scripts_to_run\Own_Action.ps1'
		$library = Join-Path $signedApp 'WinRT\SelfXTest.dll'
		$catalogXml = Join-Path $signedConfig 'Issues_List.xml'
		$configCatalog = Join-Path $signedConfig 'SelfX.Config.cat'
		$codeCatalog = Join-Path $signedApp 'SelfX.Code.cat'
		$listedCount = @(Get-ChildItem -LiteralPath $signedRoot -Recurse -File).Count

		# 2a. The calls of Windows, file by file (these cases need no trusted root).
		$result = Test-Embedded $script
		Assert-True (($result.Reason -eq $accepted) -and ($result.Thumbprint -eq $certA.Thumbprint)) "Signature: a signed script gives $accepted and the thumbprint of its signer ($($result.Reason))"
		$result = Test-Embedded $library
		Assert-True (($result.Reason -eq $accepted) -and ($result.Thumbprint -eq $certA.Thumbprint)) "Signature: a signed library gives $accepted and the thumbprint of its signer ($($result.Reason))"
		$probe = Join-Path $signedRoot 'Probe.ps1'
		[IO.File]::WriteAllText($probe, "Write-Output 'changed'`r`n" + [IO.File]::ReadAllText($script), $utf8)
		Assert-True ((Test-Embedded $probe).Reason -eq 'BadDigest') 'Signature: a script changed before the signature block gives BadDigest'
		[IO.File]::WriteAllText($probe, [IO.File]::ReadAllText($script) + "# added`r`n", $utf8)
		Assert-True ((Test-Embedded $probe).Reason -eq 'NoSignature') 'Signature: a script with text after the signature block gives NoSignature'
		[IO.File]::WriteAllText($probe, "Write-Output 'unsigned'`r`n", $utf8)
		Assert-True ((Test-Embedded $probe).Reason -eq 'NoSignature') 'Signature: an unsigned script gives NoSignature'
		$result = Test-Member $configCatalog $catalogXml
		Assert-True (($result.Reason -eq $accepted) -and ($result.Thumbprint -eq $certA.Thumbprint)) "Catalog: the catalog XML is a member of SelfX.Config.cat, signer of the catalog read ($($result.Reason))"
		Assert-True ((Test-Member $configCatalog (Join-Path $signedConfig 'SelfX.Config.json')).Reason -eq $accepted) 'Catalog: SelfX.Config.json is a member of SelfX.Config.cat'
		Assert-True ((Test-Member $codeCatalog (Join-Path $signedApp 'SelfX.Code.json')).Reason -eq $accepted) 'Catalog: SelfX.Code.json is a member of SelfX.Code.cat'
		Assert-True ((Test-Member $codeCatalog $catalogXml).Reason -eq 'NoSignature') 'Catalog: a file of Config is not a member of SelfX.Code.cat'
		[IO.File]::WriteAllText($probe, [IO.File]::ReadAllText($catalogXml) + '<!-- changed -->', $utf8)
		Assert-True ((Test-Member $configCatalog $probe).Reason -eq 'NoSignature') 'Catalog: a changed XML is not a member'
		Assert-True ((Test-Member (Join-Path $signedRoot 'Missing.cat') $catalogXml).Reason -notin 'Ok', 'UntrustedRoot') 'Catalog: a missing catalog never gives a positive result'
		Remove-Item -LiteralPath $probe -Force

		# 2b. Pinned files: what was checked cannot be changed or replaced until it is released.
		$pins = New-Pins
		try {
			$entry = $pinnedType.GetMethod('Open').Invoke($pins, [object[]]@([string]$script))
			Assert-True ($entry.GetType().GetField('Hash').GetValue($entry) -eq (Get-FileHash -LiteralPath $script -Algorithm SHA256).Hash) 'Pinned: the SHA256 is the one of the file behind the handle'
			Assert-True ([IO.File]::ReadAllText($script).Length -gt 0) 'Pinned: other processes can still read the file (PowerShell reads the script)'
			foreach ($attempt in @(
					@{ Name = 'written'; Action = { [IO.File]::AppendAllText($script, '# x') } },
					@{ Name = 'replaced'; Action = { [IO.File]::WriteAllText($script, 'Write-Output 0') } },
					@{ Name = 'deleted'; Action = { [IO.File]::Delete($script) } },
					@{ Name = 'renamed'; Action = { [IO.File]::Move($script, "$script.moved") } },
					@{ Name = 'replaced by another file'; Action = { [IO.File]::Copy($ownScript, $script, $true) } })) {
				$refused = $false
				try { & $attempt.Action } catch { $refused = $true }
				Assert-True $refused "Pinned: the file cannot be $($attempt.Name) while it is pinned"
			}
			$refused = $false
			try { [IO.Directory]::Move((Join-Path $signedApp 'Scripts_to_run'), (Join-Path $signedApp 'Scripts_moved')) } catch { $refused = $true }
			Assert-True $refused 'Pinned: the folder of a pinned file cannot be renamed'
		}
		finally { ([IDisposable]$pins).Dispose() }
		[IO.File]::AppendAllText($script, '')
		Assert-True (Test-Path -LiteralPath $script -PathType Leaf) 'Pinned: after the release the file can be opened for writing again'

		# 2c. Without an accepted signature nothing passes: the lists are refused first.
		if (-not $canTrust) {
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'SelfX\.Code\.json against SelfX\.Code\.cat \(UntrustedRoot\)') -and ($result.Signatures -match 'SelfX\.Config\.json against SelfX\.Config\.cat \(UntrustedRoot\)')) "Signature mode: a signer that Windows does not trust is refused, also when he is in the list ($($result.Signatures))"
		}
		# Cases that do not depend on the trust of the root.
		Remove-Item -LiteralPath $configCatalog -Force
		$result = Test-SignedLayout $signersA
		Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'signature: SelfX\.Config\.cat \(missing\)')) "Signature mode: a missing SelfX.Config.cat is refused ($($result.Signatures))"
		New-SignedLayout $certA
		Remove-Item -LiteralPath $codeCatalog -Force
		$result = Test-SignedLayout $signersA
		Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'signature: SelfX\.Code\.cat \(missing\)')) "Signature mode: a missing SelfX.Code.cat is refused ($($result.Signatures))"
		New-SignedLayout $certA
		Add-Content -LiteralPath (Join-Path $signedConfig 'SelfX.Config.json') -Value ' '
		$result = Test-SignedLayout $signersA
		Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'SelfX\.Config\.json against SelfX\.Config\.cat \(NotInCatalogOrCatalogUnsigned\)')) "Signature mode: a changed SelfX.Config.json is refused ($($result.Signatures))"
		New-SignedLayout $certA
		Write-SignedLists $certA $null
		$result = Test-SignedLayout $signersA
		Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'against SelfX\.Code\.cat \(NotInCatalogOrCatalogUnsigned\)')) "Signature mode: unsigned catalogs are refused ($($result.Signatures))"
		$result = Test-SignedLayout ([string[]]@())
		Assert-True ((-not $result.Ok) -and ($result.Signatures -eq 'signature: no allowed signer')) 'Signature mode: an empty list of signers never means "everything is allowed"'
		# Mode Hash: a catalog in the install folder is a file that is not listed.
		New-SignedLayout $certA
		$arguments = [object[]]@([string]$signedApp, [string]$signedConfig, $null)
		$ok = [bool]$layoutMethod.Invoke($null, $arguments)
		Assert-True ((-not $ok) -and ((@($arguments[2]) -join '; ') -match 'not listed: SelfX\.Code\.cat') -and ((@($arguments[2]) -join '; ') -match 'not listed: Config/SelfX\.Config\.cat')) 'Mode Hash: the file check refuses a catalog like every unlisted file'

		if ($canTrust) {
			# 2d. The whole check with accepted signatures.
			New-SignedLayout $certA
			$result = Test-SignedLayout $signersA
			Assert-True ($result.Ok -and (-not $result.Files) -and (-not $result.Signatures)) "Signature mode: a completely signed installation is accepted ($($result.Files) $($result.Signatures))"
			Assert-True ($result.Pinned -eq $listedCount) "Signature mode: every list, catalog and listed file is pinned ($($result.Pinned) of $listedCount)"
			$pins = New-Pins
			try {
				$null = Test-SignedLayout $signersA $null $pins
				$checked = $pinnedType.GetMethod('IsSignatureChecked')
				Assert-True ([bool]$checked.Invoke($pins, [object[]]@([string]$script))) 'Signature mode: the script of the project counts as checked'
				Assert-True ([bool]$checked.Invoke($pins, [object[]]@([string]$ownScript))) 'Signature mode: the own script of the company counts as checked'
				Assert-True ([bool]$checked.Invoke($pins, [object[]]@([string]$library))) 'Signature mode: the library counts as checked'
				Assert-True (-not [bool]$checked.Invoke($pins, [object[]]@([string](Join-Path $signedApp 'SelfXService.exe')))) 'Signature mode: a file without a signature check does not count as checked (it could not be started)'
				Assert-True (-not [bool]$checked.Invoke($pins, [object[]]@([string](Join-Path $signedApp 'Scripts_to_run\Other.ps1')))) 'Signature mode: a script that is not in the lists does not count as checked'
				$refused = $false
				try { [IO.File]::AppendAllText($catalogXml, '<!-- x -->') } catch { $refused = $true }
				Assert-True $refused 'Signature mode: the catalog XML cannot be changed while the check holds it'
			}
			finally { ([IDisposable]$pins).Dispose() }
			Assert-True (Test-SignedLayout ([string[]]@($certB.Thumbprint, $certA.Thumbprint.ToLowerInvariant()))).Ok 'Signature mode: the signer is one of several allowed signers (any case)'
			# Wrong signer: validly signed, but not by a signer of the anchor.
			$result = Test-SignedLayout $signersB
			Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'SelfX\.Code\.json against SelfX\.Code\.cat \(SignerNotAllowed\)')) "Signature mode: a valid signature of a signer that is not in the anchor is refused ($($result.Signatures))"
			# Catalogs of another signer than the files.
			Write-SignedLists $certA $certB
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'against SelfX\.Config\.cat \(SignerNotAllowed\)')) "Signature mode: catalogs signed by another signer are refused ($($result.Signatures))"
			$result = Test-SignedLayout ([string[]]@($certA.Thumbprint, $certB.Thumbprint))
			Assert-True $result.Ok 'Signature mode: files of one allowed signer and catalogs of another allowed signer are accepted'
			# One script of another signer, lists and catalogs correct.
			New-SignedLayout $certA
			Set-TestSignature $script $certB
			Write-SignedLists $certA
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Signatures -eq 'signature: Scripts_to_run/SelfX_Test.ps1 (SignerNotAllowed)')) "Signature mode: one script of a signer that is not allowed is refused ($($result.Signatures))"
			# Changed XML: the list no longer fits (file problem) and the XML is not in the catalog (signature problem).
			New-SignedLayout $certA
			[IO.File]::WriteAllText($catalogXml, '<Issues><Action><Script>Planted.ps1</Script><Context>System</Context></Action></Issues>', $utf8)
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Files -match 'changed: Issues_List\.xml') -and ($result.Signatures -match 'Issues_List\.xml against SelfX\.Config\.cat \(NotInCatalogOrCatalogUnsigned\)')) "Signature mode: a changed catalog XML is refused as a signature problem (not open to Audit) ($($result.Files) | $($result.Signatures))"
			# Changed XML with the list rewritten to fit: the list is no longer the signed one.
			$list = Join-Path $signedConfig 'SelfX.Config.json'
			$json = Get-Content -LiteralPath $list -Raw | ConvertFrom-Json
			$json.Files.'Issues_List.xml' = (Get-FileHash -LiteralPath $catalogXml -Algorithm SHA256).Hash
			[IO.File]::WriteAllText($list, ($json | ConvertTo-Json -Depth 4), $utf8)
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'SelfX\.Config\.json against SelfX\.Config\.cat \(NotInCatalogOrCatalogUnsigned\)')) "Signature mode: a changed XML with a rewritten list is refused ($($result.Signatures))"
			# Changed Health_Config.xml.
			New-SignedLayout $certA
			Add-Content -LiteralPath (Join-Path $signedConfig 'Health_Config.xml') -Value '<!-- changed -->'
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'Health_Config\.xml against SelfX\.Config\.cat')) "Signature mode: a changed Health_Config.xml is refused ($($result.Signatures))"
			# Unsigned script, unsigned own script, unsigned library, changed script: lists and catalogs fit, the embedded signature decides.
			New-SignedLayout $certA
			[IO.File]::WriteAllText($script, "Write-Output 'unsigned'`r`n", $utf8)
			Write-SignedLists $certA
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and (-not $result.Files) -and ($result.Signatures -eq 'signature: Scripts_to_run/SelfX_Test.ps1 (NoSignature)')) "Signature mode: an unsigned script is refused although the lists and catalogs fit ($($result.Signatures))"
			New-SignedLayout $certA
			[IO.File]::WriteAllText($ownScript, "Write-Output 'unsigned'`r`n", $utf8)
			Write-SignedLists $certA
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Signatures -eq 'signature: Config/Scripts_to_run/Own_Action.ps1 (NoSignature)')) "Signature mode: an unsigned own script of the company is refused ($($result.Signatures))"
			New-SignedLayout $certA
			Copy-Item -LiteralPath (Join-Path $script:serviceBuildFolder 'SelfXService.dll') -Destination $library -Force
			Write-SignedLists $certA
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Signatures -eq 'signature: WinRT/SelfXTest.dll (NoSignature)')) "Signature mode: an unsigned library is refused ($($result.Signatures))"
			New-SignedLayout $certA
			[IO.File]::WriteAllText($script, "Write-Output 'changed'`r`n" + [IO.File]::ReadAllText($script), $utf8)
			Write-SignedLists $certA
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Signatures -eq 'signature: Scripts_to_run/SelfX_Test.ps1 (BadDigest)')) "Signature mode: a script changed after signing is refused ($($result.Signatures))"
			# A file that is not listed is a problem of the file check only (Service_FileCheck decides, as in the mode Hash).
			New-SignedLayout $certA
			[IO.File]::WriteAllText((Join-Path $signedApp 'Extra.txt'), 'x', $utf8)
			$result = Test-SignedLayout $signersA
			Assert-True ((-not $result.Ok) -and ($result.Files -eq 'not listed: Extra.txt') -and (-not $result.Signatures)) "Signature mode: an unlisted file is a problem of the file check, not of the signatures ($($result.Files) | $($result.Signatures))"

			# 2e. The cache: a second check of unchanged files asks Windows nothing; any change of a file is checked again.
			New-SignedLayout $certA
			$cache = [Activator]::CreateInstance($cacheType, $true)
			function Get-CacheCount([string]$Name) { return [int]$cacheType.GetField($Name).GetValue($cache) }
			$watch = [Diagnostics.Stopwatch]::StartNew()
			$result = Test-SignedLayout $signersA $cache
			$cold = $watch.Elapsed.TotalMilliseconds
			$asked = Get-CacheCount 'Misses'
			Assert-True ($result.Ok -and ($asked -eq 10) -and ((Get-CacheCount 'Hits') -eq 0)) "Cache: the first check asks Windows for every signature (2 lists, 5 signed files, 3 settings files; counted $asked)"
			$watch.Restart()
			$result = Test-SignedLayout $signersA $cache
			$warm = $watch.Elapsed.TotalMilliseconds
			Assert-True ($result.Ok -and ((Get-CacheCount 'Misses') -eq $asked) -and ((Get-CacheCount 'Hits') -eq $asked)) "Cache: the second check of unchanged files uses the stored results only (hits $(Get-CacheCount 'Hits'), checks $(Get-CacheCount 'Misses'); $($result.Files) $($result.Signatures))"
			Write-Output ("Trust: signature check of the small test installation: first run {0:N1} ms, second run (cache) {1:N1} ms." -f $cold, $warm)
			$result = Test-SignedLayout $signersB $cache
			Assert-True ((-not $result.Ok) -and ($result.Signatures -match 'SignerNotAllowed')) 'Cache: a stored result does not replace the list of signers of the anchor'
			$before = Get-CacheCount 'Misses'
			(Get-Item -LiteralPath $script).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-5)
			$result = Test-SignedLayout $signersA $cache
			Assert-True ($result.Ok -and ((Get-CacheCount 'Misses') -eq ($before + 1))) 'Cache: a file with another write time is checked again'
			[IO.File]::WriteAllText($script, "Write-Output 'unsigned'`r`n", $utf8)
			Write-SignedLists $certA
			$result = Test-SignedLayout $signersA $cache
			Assert-True ((-not $result.Ok) -and ($result.Signatures -eq 'signature: Scripts_to_run/SelfX_Test.ps1 (NoSignature)')) "Cache: a replaced script is checked again and refused ($($result.Signatures))"
			$result = Test-SignedLayout $signersA $cache
			Assert-True (-not $result.Ok) 'Cache: a negative result is never stored'

			# 2f. Measurement with the scripts, language files and settings of the project (the two programs are not built here; their
			#     SHA256 is calculated once per start in both modes).
			if (Test-Path -LiteralPath $signedRoot) { Remove-Item -LiteralPath $signedRoot -Recurse -Force }
			New-Item -ItemType Directory -Path $signedApp, $signedConfig -Force | Out-Null
			Copy-Item -Path (Join-Path $PSScriptRoot 'Sources\*') -Destination $signedApp -Recurse
			foreach ($name in 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'Ticket_Config.xml', 'Network_Test_Config.xml', 'Branding') { Move-Item -LiteralPath (Join-Path $signedApp $name) -Destination $signedConfig }
			$projectScripts = @(Get-ChildItem -LiteralPath $signedApp -Recurse -File -Filter '*.ps1' | ForEach-Object { $_.FullName })
			Set-TestSignature $projectScripts $certA
			Write-SignedLists $certA
			$projectFiles = @(Get-ChildItem -LiteralPath $signedRoot -Recurse -File).Count
			$cache = [Activator]::CreateInstance($cacheType, $true)
			$watch = [Diagnostics.Stopwatch]::StartNew()
			$result = Test-SignedLayout $signersA $cache
			$cold = $watch.Elapsed.TotalMilliseconds
			Assert-True $result.Ok "Measurement: the signed scripts of the project are accepted ($($result.Files) $($result.Signatures))"
			$warmRuns = 5
			$watch.Restart()
			for ($i = 0; $i -lt $warmRuns; $i++) { $result = Test-SignedLayout $signersA $cache }
			$warm = $watch.Elapsed.TotalMilliseconds / $warmRuns
			Assert-True ($result.Ok -and ((Get-CacheCount 'Misses') -eq ($projectScripts.Count + 2 + 5))) "Measurement: only the first run asks Windows ($(Get-CacheCount 'Misses') checks for $($projectScripts.Count) scripts, 2 lists and 5 settings files)"
			Remove-Item -LiteralPath (Join-Path $signedApp 'SelfX.Code.cat'), (Join-Path $signedConfig 'SelfX.Config.cat') -Force
			$arguments = [object[]]@([string]$signedApp, [string]$signedConfig, $null)
			$watch.Restart()
			for ($i = 0; $i -lt $warmRuns; $i++) { $hashOk = [bool]$layoutMethod.Invoke($null, $arguments) }
			$hashMode = $watch.Elapsed.TotalMilliseconds / $warmRuns
			Assert-True $hashOk 'Measurement: the same files pass the file check of the mode Hash'
			Write-Output ("Trust: measurement with {0} files of the project ({1} signed scripts): mode Hash {2:N0} ms per start; mode Signature {3:N0} ms for the first start and {4:N0} ms for each later start within 60 minutes (cache)." -f $projectFiles, $projectScripts.Count, $hashMode, $cold, $warm)
		}
	}
	finally {
		foreach ($thumbprint in $testRoots) { Remove-Item -LiteralPath "Cert:\$rootLocation\Root\$thumbprint" -Force -ErrorAction SilentlyContinue }
		foreach ($thumbprint in $testCertificates) { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint" -Force -ErrorAction SilentlyContinue }
		Remove-Item -LiteralPath $signedRoot -Recurse -Force -ErrorAction SilentlyContinue
	}
}

$pipeName = 'SelfX.Test.' + [guid]::NewGuid().ToString('N')
$dataRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfXPipeTest_' + [guid]::NewGuid().ToString('N'))
$logDirectory = Join-Path $dataRoot 'Logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

function New-TestClient {
	# Asynchronous client handle, so that the test can wait with a timeout.
	$client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut,
		[System.IO.Pipes.PipeOptions]::Asynchronous, [System.Security.Principal.TokenImpersonationLevel]::Identification)
	$client.Connect(3000)
	return $client
}

function Send-TestBytes($Client, [string]$Text) {
	$data = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Text)
	$Client.Write($data, 0, $data.Length)
	$Client.Flush()
}

function Read-TestAnswer($Client, [int]$TimeoutMs) {
	# Returns the answer line, '' when the service closed the connection without an answer, $null on a timeout.
	$buffer = New-Object byte[] 1024
	$text = New-Object System.Text.StringBuilder
	$watch = [Diagnostics.Stopwatch]::StartNew()
	while ($true) {
		$remaining = $TimeoutMs - [int]$watch.ElapsedMilliseconds
		if ($remaining -le 0) { return $null }
		try {
			$pending = $Client.BeginRead($buffer, 0, $buffer.Length, $null, $null)
			if (-not $pending.AsyncWaitHandle.WaitOne($remaining)) { return $null }
			$count = $Client.EndRead($pending)
		}
		catch { return $text.ToString().Trim() }
		if ($count -le 0) { return $text.ToString().Trim() }
		[void]$text.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $count))
		if ($text.ToString().Contains("`n")) { return $text.ToString().Trim() }
	}
}

function Invoke-TestRequest([string]$Request, [int]$TimeoutMs = 5000) {
	$client = $null
	try {
		$client = New-TestClient
		Send-TestBytes $client ($Request + "`n")
		return Read-TestAnswer $client $TimeoutMs
	}
	catch { return '' }
	finally { if ($client) { $client.Dispose() } }
}

# --- N5: the OtherSessions check needs no SeTcbPrivilege (no WTSQueryUserToken); it fails closed on bad input ---
$sourceText = [IO.File]::ReadAllText($source)
Assert-True ($sourceText -notmatch 'static\s+extern\s+bool\s+WTSQueryUserToken') 'N5: the service does not import WTSQueryUserToken (no SeTcbPrivilege needed)'
$countMethod = [SelfX.SelfXService].GetMethod('CountOtherUserSessions', [Reflection.BindingFlags]'NonPublic,Static')
Assert-True ($null -ne $countMethod) 'N5: the service has the session check'
if ($countMethod) {
	Assert-True ($countMethod.Invoke($null, @($null, [long]1)) -eq -1) 'N5: no caller SID fails closed'
	Assert-True ($countMethod.Invoke($null, @('S-1-5-21-1-2-3-1001', [long]-1)) -eq -1) 'N5: unknown caller session fails closed'
	Assert-True ($countMethod.Invoke($null, @('S-1-5-21-1-2-3-1001', [long]99999)) -eq -1) 'N5: a session without a user fails closed'
	$own = [long][Diagnostics.Process]::GetCurrentProcess().SessionId
	$result = $countMethod.Invoke($null, @('S-1-5-21-1-2-3-1001', $own))
	Assert-True ($result -ge -1) "N5: the check for the own session returns a number (got $result)"
}

# --- Environment_Mode (Tool_Config.xml): TerminalServer refuses actions that are not classified Show, for every caller -----------
# A test instance gets its code, configuration and catalogue folders set to a test folder; ProcessRequest is called directly. Every
# case ends before a script could start: a refusal, "Script not found" (the script file does not exist: the request passed the
# TerminalServer check) or "OtherSessions" (unknown caller session, fail closed).
$sourceText = [IO.File]::ReadAllText($source)
$instanceFlags = [Reflection.BindingFlags]'NonPublic,Instance'
$staticFlags = [Reflection.BindingFlags]'NonPublic,Static'
$modeMethod = [SelfX.SelfXService].GetMethod('IsTerminalServerMode', $staticFlags)
$productMethod = [SelfX.SelfXService].GetMethod('IsSessionHostProduct', $staticFlags)
$hostMethod = [SelfX.SelfXService].GetMethod('IsSessionHost', $staticFlags)
Assert-True ($null -ne $modeMethod -and $null -ne $productMethod -and $null -ne $hostMethod) 'Environment_Mode: the service has the mode and session host checks'
foreach ($case in @(@('TerminalServer', $true, $true), @(' terminalserver ', $true, $true), @('Client', $false, $true), @('', $false, $true), @($null, $false, $true), @('Foo', $false, $false), @('TerminalServer2', $false, $false))) {
	$arguments = [object[]]@($case[0], $null)
	$result = $modeMethod.Invoke($null, $arguments)
	Assert-True (($result -eq $case[1]) -and ($arguments[1] -eq $case[2])) "Environment_Mode '$($case[0])' = $(if ($case[1]) { 'TerminalServer' } else { 'Client' }), valid $($case[2]) (got $result, $($arguments[1]))"
}
# wProductType 1 = workstation, 2 = domain controller, 3 = server (Windows Enterprise multi-session reports 3); suite 0x10 = terminal
# services, 0x100 = single user (not set in application server mode).
foreach ($case in @(@(1, 0x0110, $false), @(1, 0x0010, $true), @(3, 0x0110, $true), @(3, 0x0010, $true), @(2, 0x0000, $true), @(1, 0x0000, $false))) {
	$result = $productMethod.Invoke($null, [object[]]@([byte]$case[0], [uint16]$case[1]))
	Assert-True ($result -eq $case[2]) "Session host: product type $($case[0]), suite 0x$('{0:X4}' -f $case[1]) = $($case[2])"
}
$hostNow = $hostMethod.Invoke($null, @())
Assert-True ($hostNow -is [bool]) "Session host: the version data of this Windows can be read (got '$hostNow')"
Assert-True ($sourceText.IndexOf('return "ERROR TerminalServer"') -gt 0 -and $sourceText.IndexOf('return "ERROR TerminalServer"') -lt $sourceText.IndexOf('ResolveScriptPath(installRoot, configRoot, "Scripts_to_run", scriptName)')) 'Environment_Mode: the refusal comes before the script is resolved or started'
Assert-True ($sourceText.Contains('if (blockOtherSessions && !callerIsAdmin)') -and $sourceText -notmatch 'blockOtherSessions\s*&&\s*[^;]*TerminalServer') 'Environment_Mode: the check of other sessions does not depend on the mode'
Assert-True ($sourceText -match 'EventTerminalServerRefused\s*=\s*4008' -and $sourceText -match 'EventSessionHostClient\s*=\s*4009') 'Environment_Mode: events 4008 and 4009 are defined'

$envRoot = Join-Path $dataRoot 'EnvironmentMode'
$envApp = Join-Path $envRoot 'App'
$envConfig = Join-Path $envRoot 'Config'
New-Item -ItemType Directory -Path (Join-Path $envApp 'Scripts_to_run'), $envConfig -Force | Out-Null
Set-Content -LiteralPath (Join-Path $envApp 'Scripts_to_run\Ts_Block.ps1') -Value 'exit 0'
Set-Content -LiteralPath (Join-Path $envConfig 'Issues_List.xml') -Value @'
<Actions><Quick_Solution>
<Action Id="S_Hide"><Script>Ts_Hide.ps1</Script><Context>System</Context><TerminalServer>Hide</TerminalServer></Action>
<Action Id="S_Show"><Script>Ts_Show.ps1</Script><Context>System</Context><TerminalServer>Show</TerminalServer></Action>
<Action Id="S_None"><Script>Ts_None.ps1</Script><Context>System</Context></Action>
<Action Id="S_Lower"><Script>Ts_Lower.ps1</Script><Context>System</Context><TerminalServer>show</TerminalServer></Action>
<Action Id="S_Two"><Script>Ts_Two.ps1</Script><Context>System</Context><TerminalServer>Show</TerminalServer><TerminalServer>Hide</TerminalServer></Action>
<Action Id="S_Mixed1"><Script>Ts_Mixed.ps1</Script><Context>System</Context><TerminalServer>Show</TerminalServer></Action>
<Action Id="S_Mixed2"><Script>Ts_Mixed.ps1</Script><Context>System</Context><TerminalServer>Hide</TerminalServer></Action>
<Action Id="S_Block"><Script>Ts_Block.ps1</Script><Context>System</Context><OtherSessions>Block</OtherSessions><TerminalServer>Show</TerminalServer></Action>
<Action Id="U_User"><Script>Ts_User.ps1</Script><Context>User</Context><TerminalServer>Show</TerminalServer></Action>
</Quick_Solution></Actions>
'@
Set-Content -LiteralPath (Join-Path $envConfig 'Health_Config.xml') -Value @'
<HealthConfig><Remediations>
<Remediation Id="Disk" Script="Ts_RemHide.ps1" TerminalServer="Hide" />
<Remediation Id="Updates" Script="Ts_RemShow.ps1" TerminalServer="Show" />
<Remediation Id="Defender" Script="Ts_RemNone.ps1" />
</Remediations></HealthConfig>
'@
$envService = New-Object SelfX.SelfXService(('SelfX.EnvTest.' + [guid]::NewGuid().ToString('N')), $logDirectory)
[SelfX.SelfXService].GetField('installRoot', $instanceFlags).SetValue($envService, $envApp)
[SelfX.SelfXService].GetField('configRoot', $instanceFlags).SetValue($envService, $envConfig)
[SelfX.SelfXService].GetField('catalogPath', $instanceFlags).SetValue($envService, (Join-Path $envConfig 'Issues_List.xml'))
$processMethod = [SelfX.SelfXService].GetMethod('ProcessRequest', $instanceFlags)
function Invoke-EnvRequest([string]$Script, [bool]$Admin = $false, [long]$Session = -1) {
	return [string]$processMethod.Invoke($envService, [object[]]@("RUN $Script", 'TEST\user', 'S-1-5-21-1-2-3-1001', $Admin, $Session))
}
function Set-EnvMode([string]$Text) { Set-Content -LiteralPath (Join-Path $envConfig 'Tool_Config.xml') -Value $Text }

Set-EnvMode '<GUI_Config><Environment_Mode>TerminalServer</Environment_Mode></GUI_Config>'
foreach ($case in @(
	@('Ts_Hide.ps1', $false, 'ERROR TerminalServer', 'an action classified Hide is refused'),
	@('Ts_Hide.ps1', $true, 'ERROR TerminalServer', 'an action classified Hide is refused for an elevated administrator too'),
	@('Ts_None.ps1', $false, 'ERROR TerminalServer', 'an action without classification is refused (fail closed)'),
	@('Ts_Lower.ps1', $false, 'ERROR TerminalServer', 'a classification other than exactly Show is refused'),
	@('Ts_Two.ps1', $false, 'ERROR TerminalServer', 'two TerminalServer elements (Show, Hide) are refused'),
	@('Ts_Mixed.ps1', $false, 'ERROR TerminalServer', 'a script with Show and Hide entries is refused'),
	@('Ts_RemHide.ps1', $false, 'ERROR TerminalServer', 'a remediation classified Hide is refused'),
	@('Ts_RemNone.ps1', $true, 'ERROR TerminalServer', 'a remediation without classification is refused, also for an administrator'),
	@('Ts_Show.ps1', $false, 'ERROR Script not found', 'an action classified Show passes the check'),
	@('Ts_RemShow.ps1', $false, 'ERROR Script not found', 'a remediation classified Show passes the check'),
	@('Ts_User.ps1', $false, 'ERROR Action is not allowed', 'a User action is still not a System action'),
	@('Unknown.ps1', $false, 'ERROR Action is not allowed', 'an unknown script is still refused by the whitelist'),
	@('Ts_Block.ps1', $false, 'ERROR OtherSessions', 'the check of other sessions still applies (unknown session = fail closed)'))) {
	$answer = Invoke-EnvRequest $case[0] $case[1]
	Assert-True ($answer -ceq $case[2]) "Environment_Mode TerminalServer: $($case[3]) ($($case[0]): '$answer')"
}
foreach ($mode in @(@('<GUI_Config><Environment_Mode>Client</Environment_Mode></GUI_Config>', 'Client'), @('<GUI_Config><Environment_Mode>Foo</Environment_Mode></GUI_Config>', 'an invalid value (= Client)'), @('<GUI_Config />', 'a missing element (= Client)'))) {
	Set-EnvMode $mode[0]
	foreach ($case in @(@('Ts_Hide.ps1', 'ERROR Script not found'), @('Ts_None.ps1', 'ERROR Script not found'), @('Ts_RemHide.ps1', 'ERROR Script not found'), @('Ts_Block.ps1', 'ERROR OtherSessions'), @('Ts_User.ps1', 'ERROR Action is not allowed'))) {
		$answer = Invoke-EnvRequest $case[0]
		Assert-True ($answer -ceq $case[1]) "Environment_Mode $($mode[1]): $($case[0]) gives '$($case[1])' (got '$answer')"
	}
}
Set-EnvMode '<GUI_Config><Environment_Mode>Client'
Assert-True ((Invoke-EnvRequest 'Ts_Hide.ps1') -ceq 'ERROR TerminalServer') 'Environment_Mode: an unreadable Tool_Config.xml counts as TerminalServer (fail closed)'
Assert-True ((Invoke-EnvRequest 'Ts_Show.ps1') -ceq 'ERROR Script not found') 'Environment_Mode: with an unreadable Tool_Config.xml an action classified Show still passes the check'
Remove-Item -LiteralPath (Join-Path $envConfig 'Tool_Config.xml')
Assert-True ((Invoke-EnvRequest 'Ts_Hide.ps1') -ceq 'ERROR TerminalServer') 'Environment_Mode: a missing Tool_Config.xml counts as TerminalServer (fail closed)'
$envLog = Join-Path $logDirectory 'SelfXService.log'
Assert-True ((Test-Path -LiteralPath $envLog) -and ([IO.File]::ReadAllText($envLog) -match 'not available in Environment_Mode TerminalServer')) 'Environment_Mode: a refusal is logged'

# Report housekeeping: only old DeviceLogs-* files in SID-named folders are deleted, empty SID folders are removed.
$reportRoot = Join-Path $dataRoot 'Reports'
$sidOld = Join-Path $reportRoot 'S-1-5-21-1-2-3-1001'
$sidNew = Join-Path $reportRoot 'S-1-5-21-1-2-3-1002'
$other = Join-Path $reportRoot 'NotASid'
New-Item -ItemType Directory -Path $sidOld, $sidNew, $other -Force | Out-Null
$old = (Get-Date).AddDays(-8)
$oldReport = Join-Path $sidOld 'DeviceLogs-PC-20260101-000000.txt'
$oldZip = Join-Path $sidOld 'DeviceLogs-PC-20260101-000000.zip'
$oldOther = Join-Path $sidOld 'Notes.txt'
$newReport = Join-Path $sidNew 'DeviceLogs-PC-20260102-000000.txt'
$otherOld = Join-Path $other 'DeviceLogs-PC-20260101-000000.txt'
foreach ($file in $oldReport, $oldZip, $oldOther, $newReport, $otherOld) { Set-Content -LiteralPath $file -Value 'x' }
foreach ($file in $oldReport, $oldZip, $oldOther, $otherOld) { (Get-Item -LiteralPath $file).LastWriteTime = $old }
$reportService = New-Object SelfX.SelfXService(('SelfX.ReportTest.' + [guid]::NewGuid().ToString('N')), $logDirectory)
$deleted = $reportService.CleanupReports()
Assert-True ($deleted -eq 2) "Reports: two old report files are deleted (got $deleted)"
Assert-True (-not (Test-Path -LiteralPath $oldReport)) 'Reports: the old .txt report is deleted'
Assert-True (-not (Test-Path -LiteralPath $oldZip)) 'Reports: the old .zip report is deleted'
Assert-True (Test-Path -LiteralPath $oldOther) 'Reports: a file that is no report stays'
Assert-True (Test-Path -LiteralPath $sidOld) 'Reports: a folder with a remaining file stays'
Assert-True (Test-Path -LiteralPath $newReport) 'Reports: a recent report stays'
Assert-True (Test-Path -LiteralPath $otherOld) 'Reports: a folder that is no SID folder is not touched'
Remove-Item -LiteralPath $oldOther -Force
[void]$reportService.CleanupReports()
Assert-True (-not (Test-Path -LiteralPath $sidOld)) 'Reports: an empty SID folder is removed'
Assert-True (Test-Path -LiteralPath $sidNew) 'Reports: the folder with a recent report stays'

# --- N5 (pass 2): an unexpected exception while a request is processed gets the fixed answer, not a timeout ---
Assert-True ($sourceText -match 'response = "ERROR Internal error";') 'N5: the service answers an unexpected exception with the fixed text ERROR Internal error'
Assert-True ($sourceText -notmatch 'ERROR Internal error"\s*\+') 'N5: the fixed answer carries no exception details'

# --- N6: the job object ends the child process and its descendants (KILL_ON_JOB_CLOSE) ---
$jobType = [SelfX.SelfXService].GetNestedType('ChildJob', [Reflection.BindingFlags]'NonPublic,Public')
Assert-True ($null -ne $jobType) 'N6: the service has the job object class ChildJob'
if ($null -ne $jobType) {
	$job = $jobType.GetMethod('Create', [Reflection.BindingFlags]'Public,Static').Invoke($null, @())
	Assert-True ($null -ne $job) 'N6: the job object can be created'
	if ($null -ne $job) {
		$pwshPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
		$pidFile = Join-Path ([IO.Path]::GetTempPath()) ('SelfXJobTest_' + [guid]::NewGuid().ToString('N') + '.txt')
		# The child waits one second (it is in the job by then), starts a grandchild and writes its ID.
		$childScript = "Start-Sleep -Seconds 1; `$p = Start-Process -FilePath ping.exe -ArgumentList '-n','120','127.0.0.1' -WindowStyle Hidden -PassThru; Set-Content -LiteralPath '$pidFile' -Value `$p.Id; Start-Sleep -Seconds 120"
		$startInfo = New-Object Diagnostics.ProcessStartInfo($pwshPath, "-NoLogo -NoProfile -NonInteractive -Command `"$childScript`"")
		$startInfo.UseShellExecute = $false
		$startInfo.CreateNoWindow = $true
		$child = [Diagnostics.Process]::Start($startInfo)
		$grandchildId = 0
		try {
			$added = $jobType.GetMethod('Add').Invoke($job, @($child))
			Assert-True ($added -eq $true) 'N6: a started process is added to the job'
			for ($i = 0; $i -lt 40 -and -not (Test-Path -LiteralPath $pidFile); $i++) { Start-Sleep -Milliseconds 500 }
			if (Test-Path -LiteralPath $pidFile) { $grandchildId = [int](Get-Content -LiteralPath $pidFile -Raw).Trim() }
			Assert-True ($grandchildId -gt 0) 'N6: the test child started a grandchild process'
			$jobType.GetMethod('Terminate').Invoke($job, @()) | Out-Null
			Assert-True ($child.WaitForExit(5000)) 'N6: Terminate ends the child process'
			if ($grandchildId -gt 0) {
				Start-Sleep -Milliseconds 500
				Assert-True ($null -eq (Get-Process -Id $grandchildId -ErrorAction SilentlyContinue)) 'N6: Terminate also ends the grandchild process'
			}
			# After the end nothing is added any more (the caller then ends such a process itself).
			$late = [Diagnostics.Process]::Start((New-Object Diagnostics.ProcessStartInfo($pwshPath, '-NoLogo -NoProfile -Command Start-Sleep -Seconds 30')))
			try { Assert-True ($jobType.GetMethod('Add').Invoke($job, @($late)) -eq $false) 'N6: a process is not added after the job ended' }
			finally { try { $late.Kill() } catch { } }
			$jobType.GetMethod('Terminate').Invoke($job, @()) | Out-Null
			Assert-True $true 'N6: Terminate can be called twice'
		}
		finally {
			try { if (-not $child.HasExited) { $child.Kill() } } catch { }
			if ($grandchildId -gt 0) { Stop-Process -Id $grandchildId -Force -ErrorAction SilentlyContinue }
			Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
		}
	}
}

$service = New-Object SelfX.SelfXService($pipeName, $logDirectory)
$silent = New-Object System.Collections.Generic.List[object]
try {
	# 0. N3: another process already owns the pipe name. The service must not join it (FirstPipeInstance): it logs the
	#    problem, keeps retrying, and serves as soon as the name is free.
	$squatter = New-Object System.IO.Pipes.NamedPipeServerStream($pipeName, [IO.Pipes.PipeDirection]::InOut, 254, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::Asynchronous)
	try {
		$service.StartListening()
		Start-Sleep -Milliseconds 2500
		$logPath = Join-Path $logDirectory 'SelfXService.log'
		$logText = if (Test-Path -LiteralPath $logPath) { [IO.File]::ReadAllText($logPath) } else { '' }
		Assert-True ($logText -match 'already in use by another process') 'N3: the service logs that the pipe name is already in use'
	}
	finally { $squatter.Dispose() }
	Start-Sleep -Milliseconds 2500
	Assert-True ((Invoke-TestRequest 'PING') -like 'PONG *') 'N3: the service answers as soon as the pipe name is free'
	$logText = [IO.File]::ReadAllText($logPath)
	Assert-True ($logText -match 'is free now') 'N3: the service logs that the pipe name is free'

	# 1. Basic answer.
	Assert-True ((Invoke-TestRequest 'PING') -like 'PONG *') 'PING answers PONG'

	# 2. A5: 8 silent connections of this user, the 9th is refused before anything is read.
	for ($i = 0; $i -lt 8; $i++) { $silent.Add((New-TestClient)) }
	Start-Sleep -Milliseconds 300
	$refused = Invoke-TestRequest 'PING' 2000
	Assert-True ($refused -notlike 'PONG*') "A 9th connection of the same user is refused while 8 are open (answer: '$refused')"

	# 3. A4: the service closes the silent connections after the read deadline (5 s plus grace).
	$closed = 0
	foreach ($client in $silent) {
		if ((Read-TestAnswer $client 9000) -ne $null) { $closed++ }
	}
	Assert-True ($closed -eq 8) "The service closes silent connections after the deadline ($closed of 8 closed)"
	foreach ($client in $silent) { $client.Dispose() }
	$silent.Clear()
	Start-Sleep -Milliseconds 300
	$watch = [Diagnostics.Stopwatch]::StartNew()
	$answer = Invoke-TestRequest 'PING' 2000
	Assert-True (($answer -like 'PONG *') -and $watch.ElapsedMilliseconds -lt 2000) "PING answers within 2 s after the silent connections ended (answer: '$answer')"

	# 4. A4: sending slowly does not extend the deadline (line end after 5.5 s).
	$slow = New-TestClient
	try {
		Send-TestBytes $slow 'PI'
		Start-Sleep -Milliseconds 2500
		Send-TestBytes $slow 'N'
		Start-Sleep -Milliseconds 3000
		try { Send-TestBytes $slow "G`n" } catch { }
		$slowAnswer = Read-TestAnswer $slow 4000
	}
	finally { $slow.Dispose() }
	Assert-True ($slowAnswer -notlike 'PONG*') "A request sent slowly over more than 5 s is not answered (answer: '$slowAnswer')"

	# 5. An oversized request without a line end is cut at 512 bytes and rejected.
	$big = New-TestClient
	try {
		Send-TestBytes $big ('PING' + ('A' * 2000))
		$bigAnswer = Read-TestAnswer $big 8000
	}
	finally { $big.Dispose() }
	Assert-True (($bigAnswer -ne $null) -and ($bigAnswer -notlike 'PONG*')) "An oversized request is rejected (answer: '$bigAnswer')"

	# 6. The service still works.
	Assert-True ((Invoke-TestRequest 'PING') -like 'PONG *') 'PING answers PONG at the end'
}
finally {
	foreach ($client in $silent) { try { $client.Dispose() } catch { } }
	try { $service.StopListening() } catch { }
	Remove-Item -LiteralPath $dataRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
