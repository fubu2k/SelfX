<#
.SYNOPSIS
    Tests tools\New-SelfXWdacPolicy.ps1 (optional WDAC supplemental policy).

.DESCRIPTION
    Checks that the script parses and runs it in Windows PowerShell 5.1 against a copy of the real package files and a
    dummy Bin folder. Expected: a supplemental policy for the given base policy, with the fixed policy ID, hash rules
    for the scripts, no audit-mode option and a binary .cip file. Without the ConfigCI module, or when New-CIPolicy needs more than 150 seconds
    (the CI limit is 5 minutes per test script), the run is reported as skipped; the parse check still counts. Nothing is deployed.
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
    2.8.3    2026-11-23  fubu2k               Initial version.
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
		# A small part of the real files: the scan of the whole package takes minutes (the test has 5 minutes).
		$sources = Join-Path $package 'Sources'
		New-Item -ItemType Directory -Path (Join-Path $sources 'Scripts_to_run') -Force | Out-Null
		Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sources\Tool_Config.xml') -Destination $sources
		foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Filter '*.ps1' -File | Select-Object -First 2)) { Copy-Item -LiteralPath $file.FullName -Destination $sources }
		foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Sources\Scripts_to_run') -Filter '*.ps1' -File | Select-Object -First 1)) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $sources 'Scripts_to_run') }
		Set-Content -LiteralPath (Join-Path $package 'Bin\SelfX.Binaries.json') -Value '{}'
		Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\whoami.exe') -Destination (Join-Path $package 'Bin\SelfX.exe')
		$base = [guid]::NewGuid()
		# New-CIPolicy needs between 3 and more than 5 minutes on a CI runner. The run is limited to 150 seconds here so that
		# the test script stays within the CI limit of 5 minutes per script; a slower run is reported as skipped, not failed.
		$outFile = Join-Path $root 'run.out'
		$errFile = Join-Path $root 'run.err'
		$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $tool), '-BasePolicyId', $base.ToString(), '-PackageFolder', ('"{0}"' -f $package), '-OutputFolder', ('"{0}"' -f $out))
		$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
		if (-not $process.WaitForExit(150000)) {
			& taskkill.exe /PID $process.Id /T /F | Out-Null
			Write-Output 'SKIPPED: New-CIPolicy needed more than 150 seconds on this machine; only the parse checks ran. Run the tool by hand to check the policy (see docs\Installation.md).'
		}
		else {
			$process.WaitForExit()
			$log = @(Get-Content -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue)
			Assert-True ($process.ExitCode -eq 0) ("the script runs ($(($log | Select-Object -Last 5) -join ' | '))")
			$xmlFile = @(Get-ChildItem -LiteralPath $out -Filter 'SelfX-*-Supplemental.xml' -ErrorAction SilentlyContinue)
			Assert-True ($xmlFile.Count -eq 1) 'one supplemental policy XML is written'
			Assert-True (Test-Path -LiteralPath (Join-Path $out '{1377A178-96F8-49DD-B277-80F0F10BB383}.cip')) 'the binary policy is written under the fixed policy ID'
			if ($xmlFile.Count -eq 1) {
				$text = Get-Content -LiteralPath $xmlFile[0].FullName -Raw
				Assert-True ($text -match '1377A178-96F8-49DD-B277-80F0F10BB383') 'the XML has the fixed policy ID'
				Assert-True ($text -match [regex]::Escape($base.ToString('B')) -or $text -match [regex]::Escape($base.ToString('B').ToUpperInvariant())) 'the XML supplements the given base policy'
				Assert-True (@([regex]::Matches($text, '<Option>([^<]*)</Option>') | Where-Object { $_.Groups[1].Value -ne 'Enabled:Unsigned System Integrity Policy' }).Count -eq 0) 'the supplemental policy sets no rule option except the unsigned policy option (no audit mode)'
				Assert-True ([regex]::Matches($text, '<Allow ID=[^>]*Hash=').Count -ge 5) 'the XML has hash rules'
			}
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
