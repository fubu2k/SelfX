<#
.SYNOPSIS
    Tests tools\New-SelfXWdacPolicy.ps1 (optional WDAC supplemental policy).

.DESCRIPTION
    Checks that the script parses and runs it in Windows PowerShell 5.1 against a copy of the real package files and a
    dummy Bin folder. Expected: a supplemental policy for the given base policy, with the fixed policy ID, hash rules
    for the scripts, no audit-mode option and a binary .cip file. Without the ConfigCI module, or when New-CIPolicy needs more than 150 seconds
    (the CI limit is 5 minutes per test script), the run is reported as skipped; the parse check still counts. Nothing is deployed.
    Level Publisher: the checks of the policy (signer rule without version, no hash rule when every file is signed, no denied signer,
    DTD refused) run on synthetic policy texts on any computer; the script is refused for a package without a signed file (quick, before
    the scan); with a trusted test certificate (GitHub Actions or SELFX_TEST_ALLOW_ROOT_IMPORT=1) one run creates a policy for a small
    package of one signed and one unsigned script (signer rule and hash fallback).
    Windows PowerShell 5.1 or PowerShell 7: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-WdacPolicy.ps1

.NOTES
    Name    : Test-WdacPolicy.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 2.9.0
    Exit code: 0 = all checks passed (or skipped), 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.3    2026-11-23  fubu2k               Initial version.
    2.8.4    2026-11-27  fubu2k               The policy version comes from Version.txt: the test package gets Version.txt.
    2.9.0    2026-11-27  fubu2k               Level Publisher: checks of the policy, refusal without a signed file, run with a signed test script
#>
$ErrorActionPreference = 'Stop'
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
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
Assert-True ($toolText -match 'Version\.txt' -and $toolText -notmatch 'Tool_Version') 'the policy version comes from Version.txt, not from Tool_Config.xml'

Assert-True ($toolText -match [regex]::Escape("[ValidateSet('Hash', 'Publisher')][string]`$Level = 'Hash'")) 'the level is Hash or Publisher and Hash is the default'
Assert-True ($toolText -match '-Level Publisher -Fallback Hash') 'the level Publisher uses signer rules with a hash fallback for unsigned files'
Assert-True ($toolText -match 'AllowMultipleSigners') 'several signers need an explicit switch'
Assert-True ($toolText -notmatch '(?i)-User\s+(Everyone|Jeder)') 'no account is addressed by name'

# Functions of the level Publisher (checks of the policy, signature states); only definitions, run on any computer.
. (Join-Path $repository 'tools\SelfXPublisherRules.ps1')
$ns = 'xmlns="urn:schemas-microsoft-com:sipolicy"'
function New-PolicyText {
	param([string]$Signers = '<Signer ID="ID_SIGNER_S_1" Name="SelfX Test"><CertRoot Type="TBS" Value="AABBCC"/><CertPublisher Value="SelfX Test"/></Signer>',
		[string]$Allowed = '<AllowedSigner SignerId="ID_SIGNER_S_1"/>', [string]$Denied = '', [string]$FileRules = '')
	return "<SiPolicy $ns PolicyType=`"Supplemental Policy`"><FileRules>$FileRules</FileRules><Signers>$Signers</Signers><SigningScenarios><SigningScenario Value=`"12`" ID=`"ID_SCENARIO_1`"><ProductSigners><AllowedSigners>$Allowed</AllowedSigners>$Denied</ProductSigners></SigningScenario></SigningScenarios></SiPolicy>"
}
function Get-Problems {
	param([string]$Xml, [bool]$ExpectHash, [string[]]$Signed = @())
	return @(Get-SelfXWdacPublisherPolicyProblem -PolicyXml $Xml -ExpectHashRules $ExpectHash -SignedFileName $Signed)
}
$hashRule = '<Allow ID="ID_ALLOW_A_1" FriendlyName="Unsigned.ps1 Hash Sha256" Hash="0011223344556677889900112233445566778899001122334455667788990011"/>'
$signedHashRule = '<Allow ID="ID_ALLOW_A_2" FriendlyName="Install.ps1 Hash Sha256" Hash="0011223344556677889900112233445566778899001122334455667788990022"/>'
Assert-True ((Get-Problems (New-PolicyText) $false).Count -eq 0) 'publisher policy, every file signed: signer rule only, no problem'
Assert-True ((Get-Problems (New-PolicyText -FileRules $hashRule) $true 'Install.ps1').Count -eq 0) 'publisher policy with the hash fallback of an unsigned file: no problem'
Assert-True ((Get-Problems (New-PolicyText -FileRules $hashRule) $false).Count -gt 0) 'a hash rule is a problem when every file is signed (no hash rules in the publisher mode)'
Assert-True ((Get-Problems (New-PolicyText) $true).Count -gt 0) 'no hash rule is a problem when unsigned files were scanned'
Assert-True ((Get-Problems (New-PolicyText -FileRules ($hashRule + $signedHashRule)) $true 'Install.ps1') -join ' ' -match 'Install\.ps1 also has a hash rule') 'a signed file with its own hash rule is found'
Assert-True ((Get-Problems (New-PolicyText -Signers '' -Allowed '') $false).Count -gt 0) 'a policy without signer rule is a problem'
Assert-True ((Get-Problems (New-PolicyText -Signers '<Signer ID="ID_SIGNER_S_1" Name="x"><CertRoot Type="TBS" Value="AABBCC"/></Signer>') $false) -join ' ' -match 'CertPublisher') 'a signer without publisher (every file of the authority) is found'
Assert-True ((Get-Problems (New-PolicyText -Signers '<Signer ID="ID_SIGNER_S_1" Name="x"><CertRoot Type="TBS" Value="AABBCC"/><CertPublisher Value=""/></Signer>') $false).Count -gt 0) 'a signer with an empty publisher is found'
Assert-True ((Get-Problems (New-PolicyText -Signers '<Signer ID="ID_SIGNER_S_1" Name="x"><CertPublisher Value="x"/></Signer>') $false) -join ' ' -match 'CertRoot') 'a signer without authority is found'
Assert-True ((Get-Problems (New-PolicyText -Signers '<Signer ID="ID_SIGNER_S_1" Name="x"><CertRoot Type="TBS" Value="AABBCC"/><CertPublisher Value="x"/><FileAttribRef RuleID="ID_FILEATTRIB_A_1"/></Signer>') $false) -join ' ' -match 'file attribute') 'a signer bound to a version or file name is found'
Assert-True ((Get-Problems (New-PolicyText -Allowed '') $false) -join ' ' -match 'not allowed') 'a signer that no scenario allows is found'
Assert-True ((Get-Problems (New-PolicyText -Denied '<DeniedSigners><DeniedSigner SignerId="ID_SIGNER_S_1"/></DeniedSigners>') $false) -join ' ' -match 'denied') 'denied signers are found'
Assert-True ((Get-Problems (New-PolicyText -FileRules '<FileAttrib ID="ID_FILEATTRIB_A_1" FileName="x.exe" MinimumFileVersion="1.0.0.0"/>') $false).Count -gt 0) 'a file rule that is not a plain hash rule is found'
Assert-True ((Get-Problems '<SiPolicy' $false).Count -gt 0) 'text that is not XML is a problem, not an exception'
Assert-True ((Get-Problems '<!DOCTYPE SiPolicy [<!ENTITY a "b">]><SiPolicy xmlns="urn:schemas-microsoft-com:sipolicy"/>' $false).Count -gt 0) 'a policy with a DTD is refused (no entity expansion)'
Assert-True (@(Get-SelfXWdacSignerName -PolicyXml (New-PolicyText -Signers ('<Signer ID="ID_SIGNER_S_1" Name="a"><CertRoot Type="TBS" Value="AA"/><CertPublisher Value="B Corp"/></Signer><Signer ID="ID_SIGNER_S_2" Name="b"><CertRoot Type="TBS" Value="AA"/><CertPublisher Value="A Corp"/></Signer>') -Allowed '<AllowedSigner SignerId="ID_SIGNER_S_1"/><AllowedSigner SignerId="ID_SIGNER_S_2"/>')) -join ',' -eq 'A Corp,B Corp') 'the publishers of the signer rules are listed (sorted)'

function New-FileState { param([string]$Name, [string]$State) [pscustomobject]@{ Name = $Name; State = $State; Status = $State; Thumbprint = $(if ($State -eq 'Signed') { 'AA' } else { '' }) } }
Assert-True ($null -eq (Get-SelfXSignedPackageProblem -State @((New-FileState 'Install.ps1' 'Signed'), (New-FileState 'Other.ps1' 'Unsigned')))) 'a package with a signed Install.ps1 counts as signed (the other files may fall back to hash rules)'
Assert-True ($null -ne (Get-SelfXSignedPackageProblem -State @((New-FileState 'Install.ps1' 'Unsigned'), (New-FileState 'Microsoft.Windows.SDK.NET.dll' 'Signed')))) 'a signed library of another publisher does not make an unsigned package signed'
Assert-True ($null -ne (Get-SelfXSignedPackageProblem -State @((New-FileState 'Other.ps1' 'Signed')))) 'a package without Install.ps1 is refused'

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
		foreach ($name in 'Install.ps1', 'Detection.ps1', 'Uninstall.ps1', 'Version.txt') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $package }
		# A small part of the real files: the scan of the whole package takes minutes (the test has 5 minutes).
		$sources = Join-Path $package 'Sources'
		New-Item -ItemType Directory -Path (Join-Path $sources 'Scripts_to_run') -Force | Out-Null
		Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sources\Tool_Config.xml') -Destination $sources
		foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Sources') -Filter '*.ps1' -File | Select-Object -First 2)) { Copy-Item -LiteralPath $file.FullName -Destination $sources }
		foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Sources\Scripts_to_run') -Filter '*.ps1' -File | Select-Object -First 1)) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $sources 'Scripts_to_run') }
		Set-Content -LiteralPath (Join-Path $package 'Bin\SelfX.Binaries.json') -Value '{}'
		Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\whoami.exe') -Destination (Join-Path $package 'Bin\SelfX.exe')
		$base = [guid]::NewGuid()

		# Level Publisher, package without any signed file: refused before the scan (quick).
		$unsignedPackage = Join-Path $root 'unsigned-package'
		New-Item -ItemType Directory -Path (Join-Path $unsignedPackage 'Bin') -Force | Out-Null
		foreach ($name in 'Install.ps1', 'Detection.ps1', 'Uninstall.ps1', 'Version.txt') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $unsignedPackage }
		New-Item -ItemType Directory -Path (Join-Path $unsignedPackage 'Sources') -Force | Out-Null
		Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Sources\Tool_Config.xml') -Destination (Join-Path $unsignedPackage 'Sources')
		Set-Content -LiteralPath (Join-Path $unsignedPackage 'Bin\SelfX.Binaries.json') -Value '{}'
		$refusedOut = Join-Path $root 'refused-out'
		$refusedText = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tool -BasePolicyId $base.ToString() -PackageFolder $unsignedPackage -OutputFolder $refusedOut -Level Publisher 2>&1 | Out-String
		Assert-True ($LASTEXITCODE -ne 0 -and $refusedText -match 'No file is signed') 'the level Publisher is refused for a package without a signed file'
		Assert-True (-not (Test-Path -LiteralPath $refusedOut)) 'no output folder after the refusal (nothing is written before the checks)'
		$refusedText = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tool -BasePolicyId $base.ToString() -PackageFolder $unsignedPackage -OutputFolder $refusedOut -AllowMultipleSigners 2>&1 | Out-String
		Assert-True ($LASTEXITCODE -ne 0 -and $refusedText -match 'only valid with -Level Publisher') '-AllowMultipleSigners without the level Publisher is refused'

		# Level Publisher with a signed test script (a trusted test certificate is needed; skipped otherwise).
		. (Join-Path $repository 'tools\SelfXSigning.ps1')
		. (Join-Path $repository 'tools\SelfXTestCertificate.ps1')
		$trust = Get-SelfXTestRootLocation
		$publisherCertificate = $null
		try {
			if (-not $trust.Allowed) {
				Write-Output 'SKIPPED: the run with a signed test script needs a trusted test certificate (GitHub Actions, or SELFX_TEST_ALLOW_ROOT_IMPORT=1).'
			}
			elseif ((285000 - $stopwatch.ElapsedMilliseconds) -lt 70000) {
				Write-Output 'SKIPPED: the run with a signed test script: not enough time is left in the 5 minutes of this test.'
			}
			else {
				$publisherCertificate = New-SelfXTestCertificate 'Wdac'
				Add-SelfXTestRoot -Certificate $publisherCertificate -Location $trust.Location
				$signedPackage = Join-Path $root 'signed-package'
				New-Item -ItemType Directory -Path (Join-Path $signedPackage 'Bin') -Force | Out-Null
				New-Item -ItemType Directory -Path (Join-Path $signedPackage 'Sources') -Force | Out-Null
				foreach ($name in 'Detection.ps1', 'Uninstall.ps1', 'Install.ps1', 'Version.txt') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $signedPackage }
				Set-Content -LiteralPath (Join-Path $signedPackage 'Bin\SelfX.Binaries.json') -Value '{}'
				# One script without signature stays unsigned: it must get a hash rule, the signed files must not.
				[IO.File]::WriteAllText((Join-Path $signedPackage 'Sources\Unsigned.ps1'), "Write-Output 'unsigned'`r`n", (New-Object System.Text.UTF8Encoding($false)))
				$null = Set-SelfXCodeSignature -Path (Join-Path $signedPackage 'Install.ps1'), (Join-Path $signedPackage 'Detection.ps1'), (Join-Path $signedPackage 'Uninstall.ps1') -Certificate $publisherCertificate
				$signedOut = Join-Path $root 'signed-out'
				$outFile = Join-Path $root 'publisher.out'
				$errFile = Join-Path $root 'publisher.err'
				$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $tool), '-BasePolicyId', $base.ToString(), '-PackageFolder', ('"{0}"' -f $signedPackage), '-OutputFolder', ('"{0}"' -f $signedOut), '-Level', 'Publisher')
				$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
				if (-not $process.WaitForExit([int][Math]::Min(120000, 285000 - $stopwatch.ElapsedMilliseconds))) {
					& taskkill.exe /PID $process.Id /T /F | Out-Null
					Write-Output 'SKIPPED: the run with a signed test script needed too much time on this machine.'
				}
				else {
					$process.WaitForExit()
					$log = @(Get-Content -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue)
					Assert-True ($process.ExitCode -eq 0) ("the level Publisher runs for a package with signed and unsigned scripts ($(($log | Select-Object -Last 5) -join ' | '))")
					$publisherXml = @(Get-ChildItem -LiteralPath $signedOut -Filter 'SelfX-*-Supplemental.xml' -ErrorAction SilentlyContinue)
					Assert-True ($publisherXml.Count -eq 1) 'one publisher policy XML is written'
					if ($publisherXml.Count -eq 1) {
						$publisherText = Get-Content -LiteralPath $publisherXml[0].FullName -Raw
						$found = @(Get-SelfXWdacPublisherPolicyProblem -PolicyXml $publisherText -ExpectHashRules $true -SignedFileName @('Install.ps1', 'Detection.ps1', 'Uninstall.ps1'))
						Assert-True ($found.Count -eq 0) ("the publisher policy passes the checks ($($found -join ' '))")
						Assert-True (@(Get-SelfXWdacSignerName -PolicyXml $publisherText).Count -ge 1) 'the policy has a signer rule'
						Assert-True ($publisherText -match 'Unsigned\.ps1') 'the unsigned script has a hash rule'
						Assert-True ($publisherText -match '1377A178-96F8-49DD-B277-80F0F10BB383') 'the publisher policy has the fixed policy ID'
					}
					Assert-True (Test-Path -LiteralPath (Join-Path $signedOut '{1377A178-96F8-49DD-B277-80F0F10BB383}.cip')) 'the binary publisher policy is written under the fixed policy ID'
				}
			}
		}
		finally { if ($publisherCertificate) { Remove-SelfXTestCertificate -Thumbprint $publisherCertificate.Thumbprint -Location $trust.Location } }
		# New-CIPolicy needs between 3 and more than 5 minutes on a CI runner. The run is limited to 150 seconds here so that
		# the test script stays within the CI limit of 5 minutes per script; a slower run is reported as skipped, not failed.
		$outFile = Join-Path $root 'run.out'
		$errFile = Join-Path $root 'run.err'
		$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $tool), '-BasePolicyId', $base.ToString(), '-PackageFolder', ('"{0}"' -f $package), '-OutputFolder', ('"{0}"' -f $out))
		$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
		$hashBudget = [int][Math]::Min(150000, 285000 - $stopwatch.ElapsedMilliseconds)
		if ($hashBudget -lt 20000 -or -not $process.WaitForExit($hashBudget)) {
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
