<#
.SYNOPSIS
    Tests Install.ps1 -ConfigOnly: the configuration package replaces only the folder Config of an existing installation.

.DESCRIPTION
    Takes the functions of the mode -ConfigOnly out of Install.ps1 (the script itself is never run) and runs them in a temporary folder with a
    fake installation and fake packages. Commands that change the system are replaced: icacls (rights), the delete helper
    (Invoke-SelfXSafeDelete deletes inside the temporary folder only). Positive tests: the folder Config is exchanged, the new files are
    there, the work folders are gone, a leftover of an interrupted run is cleaned or put back. Negative tests: a full package, an unknown
    entry, a link, a missing or invalid MinCodeVersion, a code version that is too old, a changed list or file, an unlisted file, a
    catalog in the mode Hash, a package without signature in the mode Signature, a missing trust anchor, changed install-time settings,
    a folder that is in use, a failure after the exchange (the old Config comes back). Static checks of the main flow of Install.ps1.
    Files are created only in a temporary folder. Windows PowerShell 5.1:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-InstallConfigOnly.ps1

.NOTES
    Name    : Test-InstallConfigOnly.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version (Install.ps1 -ConfigOnly).
    3.1.0    2026-11-28  fubu2k               Signature check of -ConfigOnly: Detection.ps1 at the top is not checked, a Detection.ps1 below Config is
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}

# Load only the functions, never the rest of Install.ps1.
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install.ps1'), [ref]$tokens, [ref]$parseErrors)
Assert-Equal @($parseErrors).Count 0 'Install.ps1 parses'
$names = 'Test-SelfXListPlacement', 'Read-SelfXFileList', 'Get-SelfXPackageToolVersion', 'ConvertTo-SelfXTrustedSignerList', 'Test-SelfXFileSignature', 'Test-SelfXPackageCatalog',
	'ConvertTo-SelfXCodeVersion', 'Get-SelfXConfigMinCodeVersion', 'Test-SelfXConfigPackageLayout', 'Test-SelfXConfigFolder', 'Test-SelfXUnsignedPackageFile', 'Test-SelfXConfigPackageSignatures',
	'Test-SelfXConfigListsMatch', 'Read-SelfXXmlFile', 'Get-SelfXInstallTimeSettings', 'Compare-SelfXInstallTimeSettings', 'Get-SelfXInstalledDeleteHelper',
	'Move-SelfXFolderWithRetry', 'Restore-SelfXInterruptedConfig', 'Install-SelfXConfigFolder', 'Invoke-SelfXConfigOnly'
foreach ($name in $names) {
	$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }.GetNewClosure(), $true)
	Assert-Equal ($null -ne $definition) $true "Install.ps1 defines $name"
	if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
	. ([scriptblock]::Create($definition.Extent.Text))
}
# Nothing of the system is changed: the rights and the delete helper are replaced by functions that work inside the temporary folder.
function Set-SelfXConfigFolderRights { param([string]$Path) }
function Reset-SelfXConfigFolderRights { param([string]$Path) If($script:FailReset) { throw 'reset of the rights failed (test)' } }
function Invoke-SelfXSafeDelete {
	param([string]$Exe, [string[]]$Arguments)
	$Target = ($Arguments[0] -replace '^/removetree:', '')
	If($Target -notlike "$script:Root*") { throw "test: delete outside the temporary folder: $Target" }
	If(Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
}
$script:FailReset = $false

$script:Root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXConfigOnlyTest_' + [guid]::NewGuid().ToString('N'))
$install = Join-Path $script:Root 'ProgramFiles\SelfX'
$package = Join-Path $script:Root 'package'

function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Write-Json([string]$Path, $Object) { [IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 5)) }
function New-ToolConfig([string]$Name = 'SelfX Support', [string]$Desktop = 'False', [string]$Privileges = 'Restricted') {
	return "<?xml version=`"1.0`" encoding=`"utf-8`"?><GUI_Config><Shortcut_Name>$Name</Shortcut_Name><Shortcut_Desktop>$Desktop</Shortcut_Desktop><Shortcut_StartMenu>True</Shortcut_StartMenu><Show_Tray_Icon>True</Show_Tray_Icon><Service_Privileges>$Privileges</Service_Privileges></GUI_Config>"
}
function Write-ConfigFolder([string]$Folder, [hashtable]$Content, [string]$MinCode = '3.1.0', [switch]$WithCatalog) {
	if (Test-Path -LiteralPath $Folder) { Remove-Item -LiteralPath $Folder -Recurse -Force }
	New-Item -ItemType Directory -Path $Folder -Force | Out-Null
	$files = [ordered]@{}
	foreach ($name in ($Content.Keys | Sort-Object)) {
		$path = Join-Path $Folder $name.Replace('/', '\')
		New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
		[IO.File]::WriteAllText($path, [string]$Content[$name])
		$files[$name] = Get-Sha $path
	}
	$list = [ordered]@{ ManifestVersion = 1; ConfigRevision = '2026-11-27T10:00:00Z' }
	if ($MinCode) { $list['MinCodeVersion'] = $MinCode }
	$list['Files'] = $files
	Write-Json (Join-Path $Folder 'SelfX.Config.json') $list
	if ($WithCatalog) { [IO.File]::WriteAllText((Join-Path $Folder 'SelfX.Config.cat'), 'catalog') }
}
function Reset-Fixture([string]$InstalledVersion = '3.1.0') {
	if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
	New-Item -ItemType Directory -Path (Join-Path $install 'App') -Force | Out-Null
	[IO.File]::WriteAllText((Join-Path $install 'App\SelfXService.exe'), 'fake service')
	Write-Json (Join-Path $install 'App\SelfX.Code.json') ([ordered]@{ ManifestVersion = 1; ToolVersion = $InstalledVersion; Files = [ordered]@{ 'SelfXService.exe' = (Get-Sha (Join-Path $install 'App\SelfXService.exe')) } })
	Write-ConfigFolder (Join-Path $install 'Config') @{ 'Tool_Config.xml' = (New-ToolConfig); 'Issues_List.xml' = '<Issues version="old" />'; 'Branding/old.png' = 'old logo' }
	New-Item -ItemType Directory -Path $package -Force | Out-Null
	[IO.File]::WriteAllText((Join-Path $package 'Install.ps1'), '# package script')
	Write-ConfigFolder (Join-Path $package 'Config') @{ 'Tool_Config.xml' = (New-ToolConfig); 'Issues_List.xml' = '<Issues version="new" />'; 'Branding/new.png' = 'new logo' }
}
$hashAnchor = [pscustomobject]@{ Mode = 'Hash'; Signers = @() }
function Invoke-Config($Anchor = $hashAnchor) {
	try { $null = Invoke-SelfXConfigOnly -PackageFolder $package -InstallFolder $install -Anchor $Anchor -Attempts 2 -DelaySeconds 0 6>$null; return 'accepted' }
	catch { return 'refused: ' + $_.Exception.Message }
}
function Get-InstalledText([string]$Name) { [IO.File]::ReadAllText((Join-Path $install ('Config\' + $Name))) }
function Test-NothingChanged([string]$Message) {
	Assert-Equal (Get-InstalledText 'Issues_List.xml') '<Issues version="old" />' "${Message}: Config is unchanged"
	Assert-Equal (Test-Path -LiteralPath ($install + '.ConfigStage')) $false "${Message}: no stage folder is left"
	Assert-Equal (Test-Path -LiteralPath ($install + '.ConfigOld')) $false "${Message}: no old folder is left"
}

try {
	# ---- the version rule
	foreach ($case in @(@('3.1.0', $true), @('3.1', $true), @('10.20.30.40', $true), @('3', $false), @('3.1.0-beta', $false), @(' 3.1.0', $false), @('3.1.0.1.2', $false), @('3.x', $false), @('', $false), @('300000.1', $false))) {
		Assert-Equal ($null -ne (ConvertTo-SelfXCodeVersion -Text $case[0])) $case[1] "Version text '$($case[0])'"
	}
	Assert-Equal ((ConvertTo-SelfXCodeVersion -Text '3.10.0') -gt (ConvertTo-SelfXCodeVersion -Text '3.9.9')) $true 'Versions are compared as numbers (3.10.0 is newer than 3.9.9)'

	# ---- positive: Hash mode
	Reset-Fixture
	Assert-Equal (Invoke-Config) 'accepted' 'Hash mode: a matching configuration package is accepted'
	Assert-Equal (Get-InstalledText 'Issues_List.xml') '<Issues version="new" />' 'Hash mode: the new Issues_List.xml is installed'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $install 'Config\Branding\new.png')) $true 'Hash mode: the new logo is installed'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $install 'Config\Branding\old.png')) $false 'Hash mode: a file of the old configuration that is not in the package is gone'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $install 'App\SelfXService.exe')) $true 'Hash mode: App is untouched'
	Assert-Equal (Test-Path -LiteralPath ($install + '.ConfigStage')) $false 'Hash mode: the stage folder is removed'
	Assert-Equal (Test-Path -LiteralPath ($install + '.ConfigOld')) $false 'Hash mode: the old folder is removed'
	Assert-Equal (@(Get-ChildItem -LiteralPath $install -Force | ForEach-Object { $_.Name } | Sort-Object) -join ',') 'App,Config' 'Hash mode: the install folder holds App and Config only'
	Assert-Equal (Invoke-Config) 'accepted' 'Hash mode: the same package can be installed again'

	# ---- MinCodeVersion
	Reset-Fixture '3.1.0'
	Write-ConfigFolder (Join-Path $package 'Config') @{ 'Tool_Config.xml' = (New-ToolConfig); 'Issues_List.xml' = '<Issues version="new" />' } -MinCode '3.2.0'
	Assert-Equal (Invoke-Config) 'refused: This configuration needs code version 3.2.0 or newer; installed is 3.1.0. Install the full package first. Nothing was changed.' 'Code too old: refused'
	Test-NothingChanged 'Code too old'
	Reset-Fixture '3.2.0'
	Write-ConfigFolder (Join-Path $package 'Config') @{ 'Tool_Config.xml' = (New-ToolConfig); 'Issues_List.xml' = '<Issues version="new" />' } -MinCode '3.1.0'
	Assert-Equal (Invoke-Config) 'accepted' 'Newer code than needed: accepted'
	Reset-Fixture
	Write-ConfigFolder (Join-Path $package 'Config') @{ 'Tool_Config.xml' = (New-ToolConfig) } -MinCode ''
	Assert-Equal ((Invoke-Config) -like 'refused: Config\SelfX.Config.json has no valid MinCodeVersion*') $true 'No MinCodeVersion (a list of a full package): refused'
	Test-NothingChanged 'No MinCodeVersion'
	Reset-Fixture
	Write-ConfigFolder (Join-Path $package 'Config') @{ 'Tool_Config.xml' = (New-ToolConfig) } -MinCode '3.1.0-beta'
	Assert-Equal ((Invoke-Config) -like 'refused: Config\SelfX.Config.json has no valid MinCodeVersion*') $true 'MinCodeVersion with a suffix: refused'
	Reset-Fixture '3.1.0-beta'
	Assert-Equal ((Invoke-Config) -like 'refused: The installed code version*cannot be compared*') $true 'Installed version that cannot be compared: refused (fail closed)'

	# ---- the package layout
	Reset-Fixture
	New-Item -ItemType Directory -Path (Join-Path $package 'App') | Out-Null
	Assert-Equal ((Invoke-Config) -like "refused: -ConfigOnly: the package holds 'App': it is a full package*") $true 'Full package (App): refused'
	Test-NothingChanged 'Full package'
	Reset-Fixture
	[IO.File]::WriteAllText((Join-Path $package 'Uninstall.ps1'), '# x')
	Assert-Equal ((Invoke-Config) -like "refused: -ConfigOnly: the package holds 'Uninstall.ps1'*") $true 'Full package (Uninstall.ps1): refused'
	Reset-Fixture
	[IO.File]::WriteAllText((Join-Path $package 'extra.txt'), 'x')
	Assert-Equal ((Invoke-Config) -like "refused: -ConfigOnly: the package holds the unexpected entry 'extra.txt'*") $true 'Unknown entry at the top: refused'
	Reset-Fixture
	Remove-Item -LiteralPath (Join-Path $package 'Config') -Recurse -Force
	Assert-Equal ((Invoke-Config) -like 'refused: -ConfigOnly: the folder Config is missing*') $true 'No Config folder: refused'
	Reset-Fixture
	$outside = Join-Path $script:Root 'outside'
	New-Item -ItemType Directory -Path $outside | Out-Null
	[IO.File]::WriteAllText((Join-Path $outside 'secret.txt'), 'must stay')
	& cmd.exe /c mklink /J ('"' + (Join-Path $package 'Config\Branding\link') + '"') ('"' + $outside + '"') | Out-Null
	Assert-Equal ((Invoke-Config) -like 'refused: -ConfigOnly: the package contains a link*') $true 'A junction in the package: refused'
	Test-NothingChanged 'Junction'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $outside 'secret.txt')) $true 'Junction: the folder it points to is untouched'

	# ---- the list against the files
	Reset-Fixture
	[IO.File]::WriteAllText((Join-Path $package 'Config\Issues_List.xml'), '<Issues version="manipulated" />')
	Assert-Equal ((Invoke-Config) -like 'refused: Issues_List.xml does not match its SHA256*') $true 'Changed file (hash differs): refused'
	Test-NothingChanged 'Changed file'
	Reset-Fixture
	[IO.File]::WriteAllText((Join-Path $package 'Config\unlisted.xml'), '<x />')
	Assert-Equal ((Invoke-Config) -like 'refused: Config/unlisted.xml in the package is not listed*') $true 'Unlisted file: refused'
	Reset-Fixture
	Remove-Item -LiteralPath (Join-Path $package 'Config\Branding\new.png')
	Assert-Equal ((Invoke-Config) -like 'refused: Branding/new.png is listed in SelfX.Config.json but missing*') $true 'Listed file missing: refused'
	Reset-Fixture
	Remove-Item -LiteralPath (Join-Path $package 'Config\SelfX.Config.json')
	Assert-Equal ((Invoke-Config) -like 'refused: Config\SelfX.Config.json is missing*') $true 'List missing: refused'
	Reset-Fixture
	Write-ConfigFolder (Join-Path $package 'Config') @{ 'Issues_List.xml' = '<x />' }
	Assert-Equal ((Invoke-Config) -like 'refused: Tool_Config.xml is not listed*') $true 'No Tool_Config.xml: refused'
	Reset-Fixture
	$list = Get-Content -LiteralPath (Join-Path $package 'Config\SelfX.Config.json') -Raw | ConvertFrom-Json
	$list.Files | Add-Member -NotePropertyName 'SelfXService.exe' -NotePropertyValue ('A' * 64)
	Write-Json (Join-Path $package 'Config\SelfX.Config.json') $list
	Assert-Equal ((Invoke-Config) -like 'refused: SelfXService.exe must not be listed in SelfX.Config.json*') $true 'A program in the configuration list: refused'
	Reset-Fixture
	[IO.File]::WriteAllText((Join-Path $package 'Config\SelfX.Config.json'), '{ not json')
	Assert-Equal ((Invoke-Config) -like 'refused: Config\SelfX.Config.json is not valid JSON*' -or (Invoke-Config) -like 'refused: SelfX.Config.json in the package is not valid JSON*') $true 'Invalid JSON: refused'

	# ---- trust modes
	Reset-Fixture
	Write-ConfigFolder (Join-Path $package 'Config') @{ 'Tool_Config.xml' = (New-ToolConfig); 'Issues_List.xml' = '<Issues version="new" />' } -WithCatalog
	Assert-Equal ((Invoke-Config) -like 'refused: Config\SelfX.Config.cat is present in the package but the trust mode of the device is Hash*') $true 'Signed package on a device in the mode Hash: refused'
	Test-NothingChanged 'Catalog in mode Hash'
	Reset-Fixture
	$signatureAnchor = [pscustomobject]@{ Mode = 'Signature'; Signers = @('A' * 40) }
	Assert-Equal ((Invoke-Config $signatureAnchor) -like 'refused: Trust mode Signature: * of * scripts of the package have no valid signature*') $true 'Unsigned package on a device in the mode Signature: refused'
	Test-NothingChanged 'Unsigned package in mode Signature'
	# Detection.ps1 at the top needs no embedded signature (it is neither run nor installed): only Install.ps1 is counted and named.
	[IO.File]::WriteAllText((Join-Path $package 'Detection.ps1'), '# detection')
	try { $null = Test-SelfXConfigPackageSignatures -PackageFolder $package -AllowedThumbprint @('A' * 40); $answer = 'accepted' } catch { $answer = "refused: $($_.Exception.Message)" }
	Assert-Equal ($answer -like 'refused: Trust mode Signature: 1 of 1 scripts*Install.ps1 (NotSigned)*' -and $answer -notlike '*Detection.ps1*') $true "Signature check of -ConfigOnly: Detection.ps1 at the top is not checked, Install.ps1 is ($answer)"
	New-Item -ItemType Directory -Path (Join-Path $package 'Config\Sub') -Force | Out-Null
	[IO.File]::WriteAllText((Join-Path $package 'Config\Sub\Detection.ps1'), '# not at the top')
	try { $null = Test-SelfXConfigPackageSignatures -PackageFolder $package -AllowedThumbprint @('A' * 40); $answer = 'accepted' } catch { $answer = "refused: $($_.Exception.Message)" }
	Assert-Equal ($answer -like 'refused: Trust mode Signature: 2 of 2 scripts*Config\Sub\Detection.ps1 (NotSigned)*') $true "Signature check of -ConfigOnly: a Detection.ps1 below Config is checked ($answer)"
	Assert-Equal ((Invoke-Config ([pscustomobject]@{ Mode = 'Signature'; Signers = @() })) -like 'refused: -TrustedSigner is empty*') $true 'Mode Signature with an empty signer list: refused (never "allow all")'
	Assert-Equal ((Invoke-Config $null) -like 'refused: -ConfigOnly needs an installed SelfX with a trust anchor*') $true 'No trust anchor: refused'
	Assert-Equal ((Invoke-Config ([pscustomobject]@{ Mode = 'Other'; Signers = @() })) -like 'refused: The trust anchor of the device has no valid mode*') $true 'Unknown mode in the anchor: refused'

	# ---- settings that only the full package applies
	foreach ($case in @(
		@{ Name = 'Shortcut_Name'; Config = (New-ToolConfig -Name 'Other name') },
		@{ Name = 'Shortcut_Desktop'; Config = (New-ToolConfig -Desktop 'True') },
		@{ Name = 'Service_Privileges'; Config = (New-ToolConfig -Privileges 'Default') })) {
		Reset-Fixture
		Write-ConfigFolder (Join-Path $package 'Config') @{ 'Tool_Config.xml' = $case.Config; 'Issues_List.xml' = '<Issues version="new" />' }
		$result = Invoke-Config
		Assert-Equal ($result -like "refused: These settings are applied only by the full package*$($case.Name)*") $true "Changed $($case.Name): refused"
		Test-NothingChanged "Changed $($case.Name)"
	}
	Reset-Fixture
	Write-ConfigFolder (Join-Path $package 'Config') @{ 'Tool_Config.xml' = ((New-ToolConfig) -replace '<GUI_Config>', '<GUI_Config><Support_Mail>help@example.com</Support_Mail>'); 'Issues_List.xml' = '<Issues version="new" />' }
	Assert-Equal (Invoke-Config) 'accepted' 'A changed setting that the service reads at run time (support mail): accepted'
	Reset-Fixture
	$dtd = '<?xml version="1.0"?><!DOCTYPE GUI_Config [<!ENTITY x "y">]><GUI_Config><Shortcut_Name>&x;</Shortcut_Name></GUI_Config>'
	Write-ConfigFolder (Join-Path $package 'Config') @{ 'Tool_Config.xml' = $dtd; 'Issues_List.xml' = '<Issues version="new" />' }
	Assert-Equal ((Invoke-Config) -like 'refused:*') $true 'Tool_Config.xml with a DTD: refused'
	Test-NothingChanged 'DTD'

	# ---- the installation
	Reset-Fixture
	Remove-Item -LiteralPath (Join-Path $install 'App\SelfXService.exe')
	Assert-Equal ((Invoke-Config) -like 'refused: The installation is incomplete*') $true 'No service program in the installation: refused'
	Reset-Fixture
	[IO.File]::WriteAllText((Join-Path $install 'App\SelfXService.exe'), 'changed program')
	Assert-Equal ((Invoke-Config) -like 'refused: App\SelfXService.exe does not match App\SelfX.Code.json*') $true 'Delete helper that does not match its list: not used, refused'
	Test-NothingChanged 'Changed delete helper'
	Reset-Fixture
	Remove-Item -LiteralPath (Join-Path $install 'Config') -Recurse -Force
	Assert-Equal ((Invoke-Config) -like 'refused: The installation has no Config\Tool_Config.xml*') $true 'No installed configuration: refused'

	# ---- work folders of an interrupted run
	Reset-Fixture
	New-Item -ItemType Directory -Path ($install + '.ConfigStage\old') -Force | Out-Null
	[IO.File]::WriteAllText(($install + '.ConfigStage\old\x.txt'), 'x')
	New-Item -ItemType Directory -Path ($install + '.ConfigOld') -Force | Out-Null
	Assert-Equal (Invoke-Config) 'accepted' 'Leftover stage and old folders (Config exists): cleaned, accepted'
	Assert-Equal ((Test-Path -LiteralPath ($install + '.ConfigStage')) -or (Test-Path -LiteralPath ($install + '.ConfigOld'))) $false 'Leftover folders are gone'
	Reset-Fixture
	Move-Item -LiteralPath (Join-Path $install 'Config') -Destination ($install + '.ConfigOld')
	Assert-Equal (Invoke-Config) 'accepted' 'Config missing, old folder present (run stopped between the renames): put back and updated'
	Assert-Equal (Get-InstalledText 'Issues_List.xml') '<Issues version="new" />' 'After the recovery the new configuration is installed'
	Reset-Fixture
	Move-Item -LiteralPath (Join-Path $install 'Config') -Destination ($install + '.ConfigOld')
	Remove-Item -LiteralPath (Join-Path $package 'Config\SelfX.Config.json')
	$null = Invoke-Config
	Assert-Equal (Test-Path -LiteralPath (Join-Path $install 'Config\Tool_Config.xml')) $true 'Config missing and the new package refused: the old configuration is back in place first'

	# ---- a folder that is in use, a failure after the exchange
	Reset-Fixture
	$lock = [IO.File]::Open((Join-Path $install 'Config\Issues_List.xml'), 'Open', 'Read', 'None')
	try { $result = Invoke-Config } finally { $lock.Dispose() }
	Assert-Equal ($result -like 'refused: The folder*is in use and cannot be exchanged*') $true 'A script of Config is open: the exchange is refused after the retries'
	Test-NothingChanged 'Folder in use'
	Reset-Fixture
	$script:FailReset = $true
	try { $result = Invoke-Config } finally { $script:FailReset = $false }
	Assert-Equal ($result -like 'refused: reset of the rights failed*') $true 'Failure after the exchange: reported'
	Test-NothingChanged 'Failure after the exchange'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $install 'Config\Branding\old.png')) $true 'Failure after the exchange: the old configuration is back'

	# ---- main flow of Install.ps1 (static)
	$installText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Install.ps1'))
	Assert-Equal $installText.Contains('[switch]$ConfigOnly') $true 'Install.ps1 has the switch -ConfigOnly'
	Assert-Equal $installText.Contains("-ConfigOnly cannot be combined with -TrustedSigner or -AllowHashMode") $true '-ConfigOnly refuses -TrustedSigner and -AllowHashMode (the anchor is not changed)'
	$branchStart = $installText.IndexOf('If($ConfigOnly)')
	$branch = $installText.Substring($branchStart, $installText.IndexOf('exit $ConfigOnlyExit') - $branchStart)
	Assert-Equal ($branch -match 'Set-SelfXTrustAnchor|Start-Service|Stop-Service|Restart-Service|New-Service|sc\.exe|Stop-Process') $false 'The -ConfigOnly branch does not touch the service, the anchor or processes'
	Assert-Equal $branch.Contains('Test-SelfXTrustAnchorState') $true 'The -ConfigOnly branch checks the trust anchor for safe rights'
	Assert-Equal ($installText.IndexOf('If($ConfigOnly)') -lt $installText.IndexOf('$TrustMode = Resolve-SelfXTrustMode')) $true 'The -ConfigOnly branch comes before the trust mode of the full installation'
	$uninstallText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Uninstall.ps1'))
	Assert-Equal ($uninstallText.Contains('.ConfigStage') -and $uninstallText.Contains('.ConfigOld')) $true 'Uninstall.ps1 removes the work folders of an interrupted -ConfigOnly'
}
finally {
	if (Test-Path -LiteralPath $script:Root) { Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
