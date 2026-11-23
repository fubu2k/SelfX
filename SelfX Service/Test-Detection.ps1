<#
.SYNOPSIS
    Tests the file list check of Detection.ps1 and the Detection.ps1 that tools\New-SelfXIntuneWin.ps1 writes.

.DESCRIPTION
    Detection.ps1 compares the digest of the installed SelfX.Files.json with a digest that the packaging tool embeds, so an
    update with changed files is found even when Tool_Version did not change (finding M2). The test takes the functions out of
    Detection.ps1 and tools\New-SelfXIntuneWin.ps1 (neither script is run) and checks that both compute the same digest, that a
    changed, missing or damaged list is reported, and that the tool fills the placeholder exactly once.
    Files are created only in a temporary folder; no administrator rights are needed.
    Windows PowerShell 5.1 or PowerShell 7: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Detection.ps1

.NOTES
    Name    : Test-Detection.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator before building the package; not installed)
    Version : 2.8.1
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.1    2026-11-23  fubu2k               Initial version (M2).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}

function Import-Function([string]$Script, [string[]]$Names) {
	$ast = [Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
	foreach ($name in $Names) {
		$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }.GetNewClosure(), $true)
		Assert-Equal ($null -ne $definition) $true "$(Split-Path -Leaf $Script) defines $name"
		if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
		# Defined in the global scope under a prefix, so Detection.ps1 and the tool can both have a Get-SelfXFilesDigest.
		$text = $definition.Extent.Text -replace "^function\s+$([regex]::Escape($name))", ('function global:' + $(if ($name -eq 'Get-SelfXFilesDigest') { $Prefix } else { '' }) + $name)
		. ([scriptblock]::Create($text))
	}
}
$detectionScript = Join-Path $PSScriptRoot 'Detection.ps1'
$toolScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\New-SelfXIntuneWin.ps1'

$Prefix = 'Det_'
Import-Function $detectionScript @('Get-SelfXFilesDigest', 'Test-SelfXFilesList')
$Prefix = 'Tool_'
Import-Function $toolScript @('Get-SelfXFilesDigest', 'New-SelfXDetectionScript')
# Test-SelfXFilesList of Detection.ps1 calls Get-SelfXFilesDigest: make that name resolve to the Detection.ps1 version.
function global:Get-SelfXFilesDigest { param($Files) $copy = @{}; foreach ($key in $Files.Keys) { $copy[$key] = $Files[$key] }; Det_Get-SelfXFilesDigest -Files $copy }
# New-SelfXDetectionScript of the tool passes an ordered dictionary; the wrapper hands it on as a hashtable.
$files = [ordered]@{ 'Self_X.ps1' = 'aa11'; 'Languages/de.xml' = 'bb22'; 'Uninstall.ps1' = 'cc33'; 'SelfXService.exe' = 'dd44' }
$plain = @{}; foreach ($key in $files.Keys) { $plain[$key] = $files[$key] }

$digestDetection = Det_Get-SelfXFilesDigest -Files $plain
$digestTool = Tool_Get-SelfXFilesDigest -Files $files
Assert-Equal ($digestDetection -match '^[0-9A-F]{64}$') $true 'digest: 64 upper-case hex characters'
Assert-Equal $digestTool $digestDetection 'digest: tool and Detection.ps1 compute the same value'
$reordered = [ordered]@{ 'SelfXService.exe' = 'DD44'; 'Uninstall.ps1' = 'cc33'; 'Languages/de.xml' = 'bb22'; 'Self_X.ps1' = 'AA11' }
Assert-Equal (Tool_Get-SelfXFilesDigest -Files $reordered) $digestTool 'digest: independent of order and letter case of the hashes'
$changed = [ordered]@{} ; foreach ($key in $files.Keys) { $changed[$key] = $files[$key] }; $changed['Self_X.ps1'] = 'aa12'
Assert-Equal ((Tool_Get-SelfXFilesDigest -Files $changed) -ne $digestTool) $true 'digest: one changed file hash changes the digest'
$renamed = [ordered]@{ 'Self_Y.ps1' = 'aa11'; 'Languages/de.xml' = 'bb22'; 'Uninstall.ps1' = 'cc33'; 'SelfXService.exe' = 'dd44' }
Assert-Equal ((Tool_Get-SelfXFilesDigest -Files $renamed) -ne $digestTool) $true 'digest: a renamed file changes the digest'

$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXDetectionTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
	function Write-List($Path, $Files, $Version = 1) {
		$list = [ordered]@{ ManifestVersion = $Version; ToolVersion = '2.8.0'; BuiltUtc = [DateTime]::UtcNow.ToString('o'); Files = $Files }
		[IO.File]::WriteAllText($Path, ($list | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
	}
	$list = Join-Path $temp 'SelfX.Files.json'
	Write-List $list $files
	Assert-Equal ($null -eq (Test-SelfXFilesList -Path $list -ExpectedHash $digestTool)) $true 'list: the installed list with the expected digest is accepted (BuiltUtc is not part of the digest)'
	Assert-Equal ($null -eq (Test-SelfXFilesList -Path $list -ExpectedHash $digestTool.ToLowerInvariant())) $true 'list: the expected digest may be lower case'
	Write-List $list $changed
	Assert-Equal (Test-SelfXFilesList -Path $list -ExpectedHash $digestTool) 'file list differs from the package' 'list: a changed file hash is reported'
	Assert-Equal (Test-SelfXFilesList -Path (Join-Path $temp 'missing.json') -ExpectedHash $digestTool) 'SelfX.Files.json missing' 'list: a missing file is reported'
	[IO.File]::WriteAllText($list, '{ not json')
	Assert-Equal (Test-SelfXFilesList -Path $list -ExpectedHash $digestTool) 'SelfX.Files.json cannot be read' 'list: damaged JSON is reported'
	Write-List $list $files 2
	Assert-Equal (Test-SelfXFilesList -Path $list -ExpectedHash $digestTool) 'SelfX.Files.json has an unknown format' 'list: an unknown manifest version is reported'
	Write-List $list ([ordered]@{})
	Assert-Equal ("$(Test-SelfXFilesList -Path $list -ExpectedHash $digestTool)" -ne '') $true 'list: an empty list is reported'

	# The tool writes the Detection.ps1 with the digest of the staged list.
	$stage = Join-Path $temp 'Stage'
	[void][IO.Directory]::CreateDirectory($stage)
	Copy-Item -LiteralPath $detectionScript -Destination (Join-Path $stage 'Detection.ps1')
	Write-List (Join-Path $stage 'SelfX.Files.json') $files
	$target = Join-Path $temp 'out\Detection.ps1'
	[void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
	$written = New-SelfXDetectionScript -Stage $stage -Target $target
	Assert-Equal $written $digestTool 'tool: the digest of the staged list is returned'
	$text = [IO.File]::ReadAllText($target)
	Assert-Equal ($text -match "\`$ExpectedFilesHash = '$digestTool'") $true 'tool: the digest replaces the placeholder in Detection.ps1'
	Assert-Equal ([regex]::Matches($text, '__SELFX_FILES_HASH__').Count) 1 'tool: only the comparison with the placeholder is left'
	$parseErrors = $null
	[void][Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$parseErrors)
	Assert-Equal @($parseErrors).Count 0 'tool: the written Detection.ps1 parses'
	# A Detection.ps1 without the placeholder is refused (the digest would not be embedded).
	$noPlaceholder = '$ExpectedFilesHash = ''' + ('0' * 64) + ''''
	Set-Content -LiteralPath (Join-Path $stage 'Detection.ps1') -Value $noPlaceholder
	$threw = $false
	try { [void](New-SelfXDetectionScript -Stage $stage -Target (Join-Path $temp 'out\Bad.ps1')) } catch { $threw = $true }
	Assert-Equal $threw $true 'tool: a Detection.ps1 without the placeholder is refused'

	# The repository copy contains the placeholder exactly once as assignment and keeps working as version check.
	$repoText = [IO.File]::ReadAllText($detectionScript)
	Assert-Equal ([regex]::Matches($repoText, "\`$ExpectedFilesHash\s*=\s*'__SELFX_FILES_HASH__'").Count) 1 'Detection.ps1: one placeholder assignment'
} finally {
	Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "FAILED: $($script:errors.Count) of $script:checks checks."
	exit 1
}
Write-Output "PASS: $script:checks checks. The file list digest of the detection matches the packaging tool."
exit 0
