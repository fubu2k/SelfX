<#
.SYNOPSIS
    Test of Get-SelfXRemoteHelpPath (Self_X.ps1): Remote Help counts as installed only for a plain, validly signed file.

.DESCRIPTION
    Uses temporary files; changes nothing on the device. Context: user.

.NOTES
    Name    : Test-RemoteHelp.ps1
    Package : SelfX Service (build and test only; not shipped)
    Version : 1.0.0
#>
$ErrorActionPreference = 'Stop'
$script:errors = New-Object System.Collections.Generic.List[string]
$script:checks = 0
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($Actual -ne $Expected) { $script:errors.Add("$Message (expected '$Expected', got '$Actual')") }
}
function Get-FunctionText($Path, $Name) {
	$parseErrors = $null
	$ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
	Assert-Equal @($parseErrors).Count 0 'Self_X.ps1 parses'
	$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }.GetNewClosure(), $true)
	Assert-Equal ($null -ne $definition) $true "Self_X.ps1 defines $Name"
	if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
	return $definition.Extent.Text
}
# Dot-sourced here (script scope), not inside a function, so the function stays visible.
. ([scriptblock]::Create((Get-FunctionText (Join-Path $PSScriptRoot 'Sources\Self_X.ps1') 'Get-SelfXRemoteHelpPath')))

$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXRemoteHelpTest_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
	$signed = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
	$unsigned = Join-Path $temp 'RemoteHelp.exe'
	[IO.File]::WriteAllText($unsigned, 'not a program')
	$folder = Join-Path $temp 'Folder.exe'
	New-Item -ItemType Directory -Path $folder | Out-Null

	Assert-Equal ($null -eq (Get-SelfXRemoteHelpPath -Path (Join-Path $temp 'missing.exe'))) $true 'a missing file is not Remote Help'
	Assert-Equal ($null -eq (Get-SelfXRemoteHelpPath -Path $unsigned)) $true 'an unsigned file is not Remote Help'
	Assert-Equal ($null -eq (Get-SelfXRemoteHelpPath -Path $folder)) $true 'a folder is not Remote Help'
	Assert-Equal ($null -eq (Get-SelfXRemoteHelpPath -Path $signed)) $true 'a file with another signer is not Remote Help (default signer pattern)'
	Assert-Equal ((Get-SelfXRemoteHelpPath -Path $signed -SubjectPattern '*')) $signed 'a validly signed file with a matching signer is accepted'
	Assert-Equal ($null -eq (Get-SelfXRemoteHelpPath -Path $signed -SubjectPattern 'CN=Nobody,*')) $true 'a signer that does not match is refused'
}
finally {
	Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
