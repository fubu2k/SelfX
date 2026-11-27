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
		if ($Relative -in 'Tool_Config.xml', 'Issues_List.xml', 'Health_Config.xml', 'Ticket_Config.xml', 'Network_Test_Config.xml' -or $Relative -like 'Branding/*' -or $Relative -like 'Scripts_to_run/Own_*') { return 'SelfX.Config.json' }
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
