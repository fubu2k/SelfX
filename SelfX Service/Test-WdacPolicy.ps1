<#
.SYNOPSIS
    Tests tools\New-SelfXWdacPolicy.ps1 (optional WDAC supplemental policy, security review finding N4, part 3).

.DESCRIPTION
    Checks that the script parses and runs it in Windows PowerShell 5.1 against a copy of the real package files and a
    dummy Bin folder. Expected: a supplemental policy for the given base policy, with the fixed policy ID, hash rules
    for the scripts, no audit-mode option and a binary .cip file. Without the ConfigCI module (for example a Windows
    edition without it) the run is skipped and reported as skipped, the parse check still counts. Nothing is deployed.
    Windows PowerShell 5.1 or PowerShell 7: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WdacPolicy.ps1

.NOTES
    Name    : Test-WdacPolicy.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 2.8.3
    Exit code: 0 = all checks passed (or skipped), 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.3    2026-11-23  fubu2k               Initial version (security review finding N4, part 3).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-True($Condition, $Message) {
	$script:checks++
	if (-not $Condition) { $script:errors.Add($Message) }
}

$repository = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $repository 'tools\New-SelfXWdacPolicy.ps1'
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($tool, [ref]$null, [ref]$parseErrors)
Assert-True (@($parseErrors).Count -eq 0) 'New-SelfXWdacPolicy.ps1 parses without errors'

$toolText = Get-Content -LiteralPath $tool -Raw
Assert-True ($toolText -match 'Level Hash') 'the policy uses hash rules'
Assert-True ($toolText -notmatch '(?m)^[^#\r\n]*-NoScript') 'scripts are included in the scan'
Assert-True ($toolText -match '1377A178-96F8-49DD-B277-80F0F10BB383') 'the policy ID is fixed'

$configCi = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[bool](Get-Module -ListAvailable -Name ConfigCI)"
if ("$configCi".Trim() -ne 'True') {
	Write-Output 'SKIPPED: the ConfigCI module is not available in Windows PowerShell 5.1 on this machine; only the parse checks ran.'
}
else {
	$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXWdacTest_' + [guid]::NewGuid().ToString('N'))
	try {
		$package = Join-Path $root 'package'
		$out = Join-Path $root 'out'
		New-Item -ItemType Directory -Path (Join-Path $package 'Bin') -Force | Out-Null
		foreach ($name in 'Install.ps1', 'Detection.ps1', 'Uninstall.ps1') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $package }
		Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Destination (Join-Path $package 'Sources') -Recurse
		Set-Content -LiteralPath (Join-Path $package 'Bin\SelfX.Binaries.json') -Value '{}'
		Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\whoami.exe') -Destination (Join-Path $package 'Bin\SelfX.exe')
		$base = [guid]::NewGuid()
		$log = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tool -BasePolicyId $base -PackageFolder $package -OutputFolder $out 2>&1)
		Assert-True ($LASTEXITCODE -eq 0) ("the script runs ($(($log | Select-Object -Last 5) -join ' | '))")
		$xmlFile = @(Get-ChildItem -LiteralPath $out -Filter 'SelfX-*-Supplemental.xml' -ErrorAction SilentlyContinue)
		Assert-True ($xmlFile.Count -eq 1) 'one supplemental policy XML is written'
		Assert-True (Test-Path -LiteralPath (Join-Path $out '{1377A178-96F8-49DD-B277-80F0F10BB383}.cip')) 'the binary policy is written under the fixed policy ID'
		if ($xmlFile.Count -eq 1) {
			$text = Get-Content -LiteralPath $xmlFile[0].FullName -Raw
			Assert-True ($text -match '1377A178-96F8-49DD-B277-80F0F10BB383') 'the XML has the fixed policy ID'
			Assert-True ($text -match [regex]::Escape($base.ToString('B')) -or $text -match [regex]::Escape($base.ToString('B').ToUpperInvariant())) 'the XML supplements the given base policy'
			Assert-True ($text -notmatch 'Enabled:Audit Mode') 'the supplemental policy sets no audit mode'
			Assert-True ([regex]::Matches($text, '<Allow ID=[^>]*Hash=').Count -ge 5) 'the XML has hash rules'
		}
	}
	finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
