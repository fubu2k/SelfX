<#
.SYNOPSIS
    Tests the file list check of Detection.ps1 and the Detection.ps1 that tools\New-SelfXIntuneWin.ps1 writes.

.DESCRIPTION
    Detection.ps1 compares the digests of the installed SelfX.Code.json and SelfX.Config.json with digests that the packaging
    tool embeds, so an update with changed files is found even when the version did not change (finding M2). The code version is
    ToolVersion of the installed SelfX.Code.json; Tool_Config.xml is not read for it. The test takes the functions out of
    Detection.ps1 (the script is not run), loads tools\SelfXPackage.Common.ps1 (functions only) and checks that both compute the same
    digest, that a changed, missing or damaged list is reported, that the tool fills both placeholders exactly once, that a changed
    logo changes only the configuration digest, and that the detection recognizes a new code version, changed code files and a
    changed configuration separately (each with its own reason).
    Files are created only in a temporary folder; no administrator rights are needed.
    Windows PowerShell 5.1 or PowerShell 7: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Detection.ps1

.NOTES
    Name    : Test-Detection.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator before building the package; not installed)
    Version : 2.9.1
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.1    2026-11-23  fubu2k               Initial version (M2).
    2.9.0    2026-11-27  fubu2k               Two lists and two digests; a changed logo changes only the configuration digest.
    2.9.1    2026-11-27  fubu2k               The version comes from SelfX.Code.json: tests of Get-SelfXInstalledVersion and Test-SelfXInstalledPackage (code
                                              version, code files and configuration detected separately; an old Tool_Version in Tool_Config.xml is ignored).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}

function Import-DetectionFunction([string]$Script, [string[]]$Names) {
	$ast = [Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
	foreach ($name in $Names) {
		$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }.GetNewClosure(), $true)
		Assert-Equal ($null -ne $definition) $true "$(Split-Path -Leaf $Script) defines $name"
		if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
		# Defined in the global scope as Det_<name>; calls of the imported functions inside (for example Get-SelfXFilesDigest) point to
		# the Detection.ps1 versions, not to the ones of tools\SelfXPackage.Common.ps1.
		$text = $definition.Extent.Text
		foreach ($other in $Names) { $text = $text -replace "(?<![\w-])$([regex]::Escape($other))(?![\w-])", "Det_$other" }
		$text = $text -replace '^function\s+Det_', 'function global:Det_'
		. ([scriptblock]::Create($text))
	}
}
$detectionScript = Join-Path $PSScriptRoot 'Detection.ps1'
$commonScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\SelfXPackage.Common.ps1'

Import-DetectionFunction $detectionScript @('Get-SelfXFilesDigest', 'Test-SelfXFilesList', 'Get-SelfXInstalledVersion', 'Test-SelfXInstalledPackage')
. $commonScript
$files = [ordered]@{ 'Self_X.ps1' = 'aa11'; 'Languages/de.xml' = 'bb22'; 'Uninstall.ps1' = 'cc33'; 'SelfXService.exe' = 'dd44' }
$plain = @{}; foreach ($key in $files.Keys) { $plain[$key] = $files[$key] }

$digestDetection = Det_Get-SelfXFilesDigest -Files $plain
$digestTool = Get-SelfXFilesDigest -Files $files
Assert-Equal ($digestDetection -match '^[0-9A-F]{64}$') $true 'digest: 64 upper-case hex characters'
Assert-Equal $digestTool $digestDetection 'digest: tool and Detection.ps1 compute the same value'
$reordered = [ordered]@{ 'SelfXService.exe' = 'DD44'; 'Uninstall.ps1' = 'cc33'; 'Languages/de.xml' = 'bb22'; 'Self_X.ps1' = 'AA11' }
Assert-Equal (Get-SelfXFilesDigest -Files $reordered) $digestTool 'digest: independent of order and letter case of the hashes'
$changed = [ordered]@{} ; foreach ($key in $files.Keys) { $changed[$key] = $files[$key] }; $changed['Self_X.ps1'] = 'aa12'
Assert-Equal ((Get-SelfXFilesDigest -Files $changed) -ne $digestTool) $true 'digest: one changed file hash changes the digest'
$renamed = [ordered]@{ 'Self_Y.ps1' = 'aa11'; 'Languages/de.xml' = 'bb22'; 'Uninstall.ps1' = 'cc33'; 'SelfXService.exe' = 'dd44' }
Assert-Equal ((Get-SelfXFilesDigest -Files $renamed) -ne $digestTool) $true 'digest: a renamed file changes the digest'

$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXDetectionTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
	function Write-List($Path, $Files, $Version = 1) {
		# The code list has ToolVersion, the configuration list has ConfigRevision (neither is part of the digest).
		$list = [ordered]@{ ManifestVersion = $Version; ToolVersion = '3.0.0'; ConfigRevision = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'); Files = $Files }
		[IO.File]::WriteAllText($Path, ($list | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
	}
	$list = Join-Path $temp 'SelfX.Code.json'
	Write-List $list $files
	Assert-Equal ($null -eq (Det_Test-SelfXFilesList -Path $list -ExpectedHash $digestTool)) $true 'list: the installed list with the expected digest is accepted (ToolVersion and ConfigRevision are not part of the digest)'
	Assert-Equal ($null -eq (Det_Test-SelfXFilesList -Path $list -ExpectedHash $digestTool.ToLowerInvariant())) $true 'list: the expected digest may be lower case'
	Write-List $list $changed
	Assert-Equal (Det_Test-SelfXFilesList -Path $list -ExpectedHash $digestTool) 'SelfX.Code.json differs from the package' 'list: a changed file hash is reported'
	Assert-Equal (Det_Test-SelfXFilesList -Path (Join-Path $temp 'SelfX.Config.json') -ExpectedHash $digestTool) 'SelfX.Config.json missing' 'list: a missing file is reported with its name'
	[IO.File]::WriteAllText($list, '{ not json')
	Assert-Equal (Det_Test-SelfXFilesList -Path $list -ExpectedHash $digestTool) 'SelfX.Code.json cannot be read' 'list: damaged JSON is reported'
	Write-List $list $files 2
	Assert-Equal (Det_Test-SelfXFilesList -Path $list -ExpectedHash $digestTool) 'SelfX.Code.json has an unknown format' 'list: an unknown manifest version is reported'
	Write-List $list ([ordered]@{})
	Assert-Equal ("$(Det_Test-SelfXFilesList -Path $list -ExpectedHash $digestTool)" -ne '') $true 'list: an empty list is reported'

	# The tool writes the Detection.ps1 with the digests of the staged lists.
	$stage = Join-Path $temp 'Stage'
	[void][IO.Directory]::CreateDirectory($stage)
	Copy-Item -LiteralPath $detectionScript -Destination (Join-Path $stage 'Detection.ps1')
	$codeFiles = [ordered]@{ 'Self_X.ps1' = 'aa11'; 'Uninstall.ps1' = 'cc33' }
	$configFiles = [ordered]@{ 'Tool_Config.xml' = 'bb22'; 'Branding/logo.png' = 'ee55' }
	Write-List (Join-Path $stage 'SelfX.Code.json') $codeFiles
	Write-List (Join-Path $stage 'SelfX.Config.json') $configFiles
	$expectedCode = Get-SelfXFilesDigest -Files $codeFiles
	$expectedConfig = Get-SelfXFilesDigest -Files $configFiles
	$target = Join-Path $temp 'out\Detection.ps1'
	[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
	$written = New-SelfXDetectionScript -Stage $stage -Target $target
	Assert-Equal $written.Code $expectedCode 'tool: the digest of the staged code list is returned'
	Assert-Equal $written.Config $expectedConfig 'tool: the digest of the staged configuration list is returned'
	Assert-Equal ($expectedCode -ne $expectedConfig) $true 'tool: the two digests differ'
	$text = [IO.File]::ReadAllText($target)
	Assert-Equal ($text -match "\`$ExpectedCodeHash = '$expectedCode'") $true 'tool: the code digest replaces its placeholder in Detection.ps1'
	Assert-Equal ($text -match "\`$ExpectedConfigHash = '$expectedConfig'") $true 'tool: the configuration digest replaces its placeholder in Detection.ps1'
	Assert-Equal ([regex]::Matches($text, '__SELFX_CODE_HASH__').Count) 1 'tool: only the comparison with the code placeholder is left'
	Assert-Equal ([regex]::Matches($text, '__SELFX_CONFIG_HASH__').Count) 1 'tool: only the comparison with the configuration placeholder is left'
	$parseErrors = $null
	[void][Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$parseErrors)
	Assert-Equal @($parseErrors).Count 0 'tool: the written Detection.ps1 parses'

	# A changed logo changes only the configuration digest.
	$configLogo = [ordered]@{ 'Tool_Config.xml' = 'bb22'; 'Branding/logo.png' = 'ee56' }
	Write-List (Join-Path $stage 'SelfX.Config.json') $configLogo
	$logo = New-SelfXDetectionScript -Stage $stage -Target (Join-Path $temp 'out\Logo.ps1')
	Assert-Equal $logo.Code $expectedCode 'logo changed: the code digest stays'
	Assert-Equal ($logo.Config -ne $expectedConfig) $true 'logo changed: the configuration digest changes'

	# A Detection.ps1 with a missing or doubled placeholder is refused (a digest would not be embedded).
	$zeros = '0' * 64
	$cases = @(
		@{ Name = 'without the code placeholder'; Text = "`$ExpectedCodeHash = '$zeros'`n`$ExpectedConfigHash = '__SELFX_CONFIG_HASH__'" },
		@{ Name = 'without the configuration placeholder'; Text = "`$ExpectedCodeHash = '__SELFX_CODE_HASH__'`n`$ExpectedConfigHash = '$zeros'" },
		@{ Name = 'with the code placeholder twice'; Text = "`$ExpectedCodeHash = '__SELFX_CODE_HASH__'`n`$ExpectedCodeHash = '__SELFX_CODE_HASH__'`n`$ExpectedConfigHash = '__SELFX_CONFIG_HASH__'" }
	)
	foreach ($case in $cases) {
		Set-Content -LiteralPath (Join-Path $stage 'Detection.ps1') -Value $case.Text
		$threw = $false
		try { [void](New-SelfXDetectionScript -Stage $stage -Target (Join-Path $temp 'out\Bad.ps1')) } catch { $threw = $true }
		Assert-Equal $threw $true "tool: a Detection.ps1 $($case.Name) is refused"
	}
	# A staged package without one of the lists is refused.
	Copy-Item -LiteralPath $detectionScript -Destination (Join-Path $stage 'Detection.ps1') -Force
	Remove-Item -LiteralPath (Join-Path $stage 'SelfX.Config.json')
	$threw = $false
	try { [void](New-SelfXDetectionScript -Stage $stage -Target (Join-Path $temp 'out\Bad.ps1')) } catch { $threw = $true }
	Assert-Equal $threw $true 'tool: a package without SelfX.Config.json is refused'

	# The installed package: the code version, the code files and the configuration are detected separately.
	$codeInstalled = [ordered]@{ 'Self_X.ps1' = 'aa11'; 'Uninstall.ps1' = 'cc33'; 'SelfXService.exe' = 'dd44' }
	$configInstalled = [ordered]@{ 'Tool_Config.xml' = 'bb22'; 'Branding/logo.png' = 'ee55' }
	$digestCode = Get-SelfXFilesDigest -Files $codeInstalled
	$digestConfig = Get-SelfXFilesDigest -Files $configInstalled
	function New-InstalledFolder([string]$ToolVersion, $CodeFiles, $ConfigFiles, [string]$LegacyToolConfigVersion) {
		$dir = Join-Path $temp ('inst-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
		[void][IO.Directory]::CreateDirectory($dir)
		$codeList = [ordered]@{ ManifestVersion = 1; ToolVersion = $ToolVersion; Files = $CodeFiles }
		[IO.File]::WriteAllText((Join-Path $dir 'SelfX.Code.json'), ($codeList | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
		if ($ConfigFiles) { Write-List (Join-Path $dir 'SelfX.Config.json') $ConfigFiles }
		if ($LegacyToolConfigVersion) { [IO.File]::WriteAllText((Join-Path $dir 'Tool_Config.xml'), "<GUI_Config><Tool_Version>$LegacyToolConfigVersion</Tool_Version></GUI_Config>") }
		return $dir
	}
	function Test-Installed([string]$Dir, [string]$ExpectedVersion = '3.0.2', [string]$CodeDigest = $digestCode, [string]$ConfigDigest = $digestConfig) {
		return (Det_Test-SelfXInstalledPackage -InstallFolder $Dir -ExpectedVersion $ExpectedVersion -ExpectedCodeHash $CodeDigest -ExpectedConfigHash $ConfigDigest)
	}
	$installedOk = New-InstalledFolder '3.0.2' $codeInstalled $configInstalled
	Assert-Equal $null (Test-Installed $installedOk).Reason 'installed: the expected version and both digests are accepted'
	# 1. A new code version (same files, same configuration): only the version is reported.
	$installedNewVersion = New-InstalledFolder '3.0.3' $codeInstalled $configInstalled
	Assert-Equal (Test-Installed $installedNewVersion).Reason 'installed version 3.0.3' 'installed: a different code version is reported as version'
	Assert-Equal (Test-Installed $installedOk -ExpectedVersion '3.0.3').Reason 'installed version 3.0.2' 'installed: an update to a new code version is detected (expected 3.0.3, installed 3.0.2)'
	Assert-Equal $null (Det_Test-SelfXFilesList -Path (Join-Path $installedNewVersion 'SelfX.Config.json') -ExpectedHash $digestConfig) 'installed: a different code version does not touch the configuration list'
	Assert-Equal $null (Det_Test-SelfXFilesList -Path (Join-Path $installedNewVersion 'SelfX.Code.json') -ExpectedHash $digestCode) 'installed: the code digest does not contain the version'
	# 2. Changed code files with the same version: reported as code files.
	$codeChanged = [ordered]@{ 'Self_X.ps1' = 'aa12'; 'Uninstall.ps1' = 'cc33'; 'SelfXService.exe' = 'dd44' }
	Assert-Equal (Test-Installed (New-InstalledFolder '3.0.2' $codeChanged $configInstalled)).Reason 'SelfX.Code.json differs from the package' 'installed: changed code files without a new version are detected'
	# 3. A changed configuration (logo) with the same code version and code files: reported as configuration, the version stays.
	$configLogo = [ordered]@{ 'Tool_Config.xml' = 'bb22'; 'Branding/logo.png' = 'ee56' }
	$digestConfigLogo = Get-SelfXFilesDigest -Files $configLogo
	Assert-Equal (Test-Installed $installedOk -ConfigDigest $digestConfigLogo).Reason 'SelfX.Config.json differs from the package' 'installed: a changed configuration is detected without a new code version'
	Assert-Equal (Det_Get-SelfXInstalledVersion -Path (Join-Path $installedOk 'SelfX.Code.json')) '3.0.2' 'installed: a changed configuration does not change the code version'
	Assert-Equal $null (Test-Installed (New-InstalledFolder '3.0.2' $codeInstalled $configLogo) -ConfigDigest $digestConfigLogo).Reason 'installed: the package with the new configuration is accepted'
	# 4. Tool_Config.xml is not evaluated for the version (an old Tool_Version element is ignored in both directions).
	Assert-Equal $null (Test-Installed (New-InstalledFolder '3.0.2' $codeInstalled $configInstalled '9.9.9')).Reason 'installed: an old Tool_Version in Tool_Config.xml does not matter'
	Assert-Equal (Test-Installed (New-InstalledFolder '3.0.3' $codeInstalled $configInstalled '3.0.2')).Reason 'installed version 3.0.3' 'installed: Tool_Config.xml cannot make an old code version look current'
	# 5. Negative cases: a missing, damaged or manipulated code list never counts as installed.
	$negative = Join-Path $temp 'negative'
	[void][IO.Directory]::CreateDirectory($negative)
	$negativeList = Join-Path $negative 'SelfX.Code.json'
	Assert-Equal ($null -eq (Det_Get-SelfXInstalledVersion -Path $negativeList)) $true 'version: a missing list gives no version'
	Assert-Equal (Test-Installed $negative).Reason 'no code version in SelfX.Code.json' 'installed: a missing code list is reported'
	[IO.File]::WriteAllText($negativeList, '{ not json')
	Assert-Equal ($null -eq (Det_Get-SelfXInstalledVersion -Path $negativeList)) $true 'version: damaged JSON gives no version'
	[IO.File]::WriteAllText($negativeList, '"3.0.2"')
	Assert-Equal ($null -eq (Det_Get-SelfXInstalledVersion -Path $negativeList)) $true 'version: JSON that is a string gives no version'
	[IO.File]::WriteAllText($negativeList, '{"ManifestVersion":1,"Files":{"a":"b"}}')
	Assert-Equal ($null -eq (Det_Get-SelfXInstalledVersion -Path $negativeList)) $true 'version: a list without ToolVersion gives no version'
	foreach ($bad in '', ' ', '..\evil', 'a b', '3.0.2;calc', ('1' * 31), '3.0.2/../x', "3.0.2`r`n3.0.3") {
		[IO.File]::WriteAllText($negativeList, (([ordered]@{ ManifestVersion = 1; ToolVersion = $bad; Files = @{ a = 'b' } }) | ConvertTo-Json))
		Assert-Equal ($null -eq (Det_Get-SelfXInstalledVersion -Path $negativeList)) $true "version: the value '$($bad -replace '\s', '_')' is refused"
	}
	[IO.File]::WriteAllText($negativeList, '{"ManifestVersion":1,"ToolVersion":["3.0.2","3.0.3"],"Files":{"a":"b"}}')
	Assert-Equal ($null -eq (Det_Get-SelfXInstalledVersion -Path $negativeList)) $true 'version: a list of versions is refused'
	[IO.File]::WriteAllText($negativeList, '{"ManifestVersion":1,"ToolVersion":" 3.0.2 ","Files":{"a":"b"}}')
	Assert-Equal (Det_Get-SelfXInstalledVersion -Path $negativeList) '3.0.2' 'version: spaces around the version are removed'
	[IO.File]::WriteAllText($negativeList, ('{"ManifestVersion":1,"ToolVersion":"3.0.2","Files":{"x":"' + ('A' * 1100000) + '"}}'))
	Assert-Equal ($null -eq (Det_Get-SelfXInstalledVersion -Path $negativeList)) $true 'version: a list larger than 1 MB is refused'
	Remove-Item -LiteralPath $negativeList -Force
	[void][IO.Directory]::CreateDirectory($negativeList)
	Assert-Equal ($null -eq (Det_Get-SelfXInstalledVersion -Path $negativeList)) $true 'version: a folder instead of the list gives no version'
	Assert-Equal (Test-Installed (New-InstalledFolder '3.0.2' $codeInstalled $null)).Reason 'SelfX.Config.json missing' 'installed: a missing configuration list is reported'
	# 6. Digests in the script: a placeholder is not checked (and noted), a damaged value is refused, the version is checked first.
	$placeholders = Test-Installed $installedOk -CodeDigest '__SELFX_CODE_HASH__' -ConfigDigest '__SELFX_CONFIG_HASH__'
	Assert-Equal $null $placeholders.Reason 'installed: the repository copy (placeholders) checks the version only'
	Assert-Equal @($placeholders.Notes).Count 2 'installed: both placeholders are noted for the log'
	Assert-Equal (Test-Installed $installedNewVersion -CodeDigest '__SELFX_CODE_HASH__' -ConfigDigest '__SELFX_CONFIG_HASH__').Reason 'installed version 3.0.3' 'installed: the repository copy still checks the version'
	Assert-Equal (Test-Installed $installedOk -CodeDigest 'xyz').Reason 'invalid digest of SelfX.Code.json in this script' 'installed: a damaged code digest in the script is refused'
	Assert-Equal (Test-Installed $installedOk -ConfigDigest ('0' * 63)).Reason 'invalid digest of SelfX.Config.json in this script' 'installed: a damaged configuration digest in the script is refused'
	Assert-Equal (Test-Installed $installedOk -CodeDigest '__SELFX_CONFIG_HASH__').Reason 'invalid digest of SelfX.Code.json in this script' 'installed: the placeholder of the other list is refused'

	# The repository copy contains each placeholder exactly once as assignment and keeps working as version check.
	$repoText = [IO.File]::ReadAllText($detectionScript)
	Assert-Equal ([regex]::Matches($repoText, "\`$ExpectedCodeHash\s*=\s*'__SELFX_CODE_HASH__'").Count) 1 'Detection.ps1: one code placeholder assignment'
	Assert-Equal ([regex]::Matches($repoText, "\`$ExpectedConfigHash\s*=\s*'__SELFX_CONFIG_HASH__'").Count) 1 'Detection.ps1: one configuration placeholder assignment'
	Assert-Equal ($repoText -match 'GUI_Config\.Tool_Version|Tool_Config\.xml\s*-Raw') $false 'Detection.ps1: the version is not read from Tool_Config.xml'
	Assert-Equal ($repoText.Contains("'^[0-9A-Za-z.\-]{1,30}\z'")) $true 'Detection.ps1: the version pattern is the one of the package tools'
} finally {
	Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "FAILED: $($script:errors.Count) of $script:checks checks."
	exit 1
}
Write-Output "PASS: $script:checks checks. The file list digests of the detection match the packaging tool."
exit 0
