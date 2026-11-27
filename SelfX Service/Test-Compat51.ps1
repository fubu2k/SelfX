<#
.SYNOPSIS
    Tests that the scripts which Intune and Autopilot start in Windows PowerShell 5.1 still parse there.

.DESCRIPTION
    Install.ps1, Uninstall.ps1, Detection.ps1 and Sources\Scripts_to_run\Collect-DeviceLogs.ps1 must run in Windows PowerShell 5.1
    (and Collect-DeviceLogs.ps1 also in PowerShell 7). Everything else is PowerShell 7 only. This test runs in Windows PowerShell 5.1
    in CI. It uses the parser of the running edition, so a PowerShell 7 only syntax (ternary operator, pipeline chain operators,
    null-coalescing, ForEach-Object -Parallel) in one of these scripts is found. Sources\SelfXPaths.ps1 (the resolver of the folders
    App and Config) is checked too, because it is written for both editions. It changes nothing on the device.

.NOTES
    Name    : Test-Compat51.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version
    3.1.0    2026-11-27  fubu2k               Also Sources\SelfXPaths.ps1
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ($Actual -ne $Expected) { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}

$package = $PSScriptRoot
$files = @('Install.ps1', 'Uninstall.ps1', 'Detection.ps1', 'Sources\Scripts_to_run\Collect-DeviceLogs.ps1', 'Sources\SelfXPaths.ps1')
Write-Output "Parser of PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
foreach ($file in $files) {
	$path = Join-Path $package $file
	Assert-Equal (Test-Path -LiteralPath $path -PathType Leaf) $true "$file exists"
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
	$tokens = $null; $parseErrors = $null
	$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
	Assert-Equal @($parseErrors).Count 0 "$file parses without errors in this PowerShell"
	foreach ($parseError in @($parseErrors)) { $script:errors.Add("$file line $($parseError.Extent.StartLineNumber): $($parseError.Message)") }
	# Syntax that only exists in PowerShell 7 is rejected by the 5.1 parser; in PowerShell 7 these checks find it by AST.
	$ps7Syntax = @($ast.FindAll({ param($node) $node.GetType().Name -in 'TernaryExpressionAst', 'PipelineChainAst' }, $true))
	Assert-Equal $ps7Syntax.Count 0 "$file has no ternary operator and no pipeline chain operators (&& ||)"
	$text = [IO.File]::ReadAllText($path)
	Assert-Equal ($text -match '(?m)\?\?=?|ForEach-Object\s+-Parallel') $false "$file has no ?? / ??= and no ForEach-Object -Parallel"
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "FAILED: $($script:errors.Count) of $script:checks checks."
	exit 1
}
Write-Output "PASS: $script:checks checks. The scripts of Intune and Autopilot and SelfXPaths.ps1 stay compatible with Windows PowerShell 5.1."
exit 0
