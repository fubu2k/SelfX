<#
.SYNOPSIS
    Tests tools\New-SelfXAppLockerRules.ps1 (AppLocker hash rules and publisher rules for the programs) and the functions of
    tools\SelfXPublisherRules.ps1.

.DESCRIPTION
    Isolated: works in a temporary folder, changes no repository file and no AppLocker policy of the computer. The script is
    always started in Windows PowerShell 5.1 (powershell.exe), also when this test runs in PowerShell 7, the way
    Build-SelfXBinaries.ps1 does it. Skipped (exit code 0) when the AppLocker cmdlets are not available. Checks that the rules
    apply to the SID S-1-1-0 (not to the localized name "Everyone"), that every file gets one rule, that paths with spaces
    work and that a missing file, an empty list and a wrong output folder are refused without leaving an output file.

    Part 1 runs on any computer (also PowerShell 7 on Linux): the publisher rules built from a given publisher name, the checks of a
    policy (structure, SID, no hash rule, no version) with changed copies as negative tests, and the decision about signatures with
    mocked signature objects. Part 2 needs Windows PowerShell 5.1 with the AppLocker cmdlets. Part 3 (publisher mode with real
    signatures) also needs a trusted test certificate: on GitHub Actions, or with SELFX_TEST_ALLOW_ROOT_IMPORT=1 (adds the test
    certificates to the trusted roots until the end of the test); otherwise it is skipped.

.NOTES
    Name    : Test-SelfXAppLockerRules.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 1.1.0
    Exit code: 0 = all tests passed or skipped, 1 = at least one failed

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-24  fubu2k               Initial version.
    1.1.0    2026-11-27  fubu2k               Publisher mode: functions of SelfXPublisherRules.ps1, refusals and a run with signed test files
#>
$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$rulesScript = Join-Path $ScriptFolder 'New-SelfXAppLockerRules.ps1'
$isWindowsHost = -not [string]::IsNullOrEmpty($env:SystemRoot)
$windowsPowerShell = $(if ($isWindowsHost) { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' } else { $null })
. (Join-Path $ScriptFolder 'SelfXPublisherRules.ps1')

$script:Failed = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  PASS $Name" } else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}
function Skip {
    param([string]$Name, [string]$Reason)
    Write-Host "  SKIP $Name ($Reason)"
}
function Invoke-Rules {
    param([string]$PathList, [string]$OutputFile, [string]$Mode)
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $rulesScript, '-PathList', $PathList, '-OutputFile', $OutputFile, '-RuleNamePrefix', 'SelfX test')
    if ($Mode) { $arguments += @('-Mode', $Mode) }
    # Text on stderr (for example a refused parameter value) is output here, not an error that stops the test.
    $ErrorActionPreference = 'Continue'
    $output = & $windowsPowerShell @arguments 2>&1 | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Output = $output.Trim() }
}
function New-FakeSignature {
    param([string]$Status, [string]$Thumbprint = 'AB' * 20)
    $certificate = $(if ($Thumbprint) { [pscustomobject]@{ Thumbprint = $Thumbprint } } else { $null })
    return [pscustomobject]@{ Status = $Status; SignerCertificate = $certificate }
}
function Get-PolicyProblems {
    param([string]$Xml)
    return @(Get-SelfXAppLockerPublisherPolicyProblem -PolicyXml $Xml)
}
function Test-Throws {
    param([scriptblock]$Script)
    try { & $Script | Out-Null; return $false } catch { return $true }
}

Write-Host 'Part 1: publisher name'
Assert ($null -eq (Get-SelfXPublisherNameProblem 'O=CONTOSO GMBH, L=BERLIN, C=DE')) 'a certificate subject is accepted'
Assert ($null -ne (Get-SelfXPublisherNameProblem '')) 'an empty name is refused'
Assert ($null -ne (Get-SelfXPublisherNameProblem $null)) 'no name is refused'
Assert ($null -ne (Get-SelfXPublisherNameProblem '*')) 'the wildcard alone is refused (it would allow every publisher)'
Assert ($null -ne (Get-SelfXPublisherNameProblem 'O=CONTOSO*')) 'a wildcard inside the name is refused'
Assert ($null -ne (Get-SelfXPublisherNameProblem "O=CONTOSO`r`nC=DE")) 'a control character is refused'
Assert ($null -ne (Get-SelfXPublisherNameProblem ' O=CONTOSO')) 'a leading space is refused'
Assert ($null -ne (Get-SelfXPublisherNameProblem 'CONTOSO')) 'a text that is not attribute=value is refused'
Assert ($null -ne (Get-SelfXPublisherNameProblem ('O=' + ('A' * 1000)))) 'a name longer than 1000 characters is refused'

Write-Host 'Part 1: publisher rules (built from a given name)'
$name = 'O=CONTOSO & CO <GMBH>, L=BERLIN, C=DE'
$xml = New-SelfXAppLockerPublisherPolicyXml -PublisherName $name -RuleNamePrefix 'SelfX'
$document = ConvertTo-SelfXXmlDocument -Text $xml
$collections = @($document.SelectNodes('/AppLockerPolicy/RuleCollection'))
Assert (($collections | ForEach-Object { $_.GetAttribute('Type') }) -join ',' -eq 'Exe,Dll,Script') 'one rule collection each for Exe, Dll and Script'
$rules = @($document.SelectNodes('//FilePublisherRule'))
Assert ($rules.Count -eq 3) 'one publisher rule for each collection'
Assert (@($collections | Where-Object { @($_.SelectNodes('FilePublisherRule')).Count -ne 1 }).Count -eq 0) 'exactly one rule in each collection'
Assert ($document.SelectNodes('//FileHashRule').Count -eq 0) 'no hash rule in the publisher mode'
Assert (@($rules | Where-Object { $_.GetAttribute('UserOrGroupSid') -ne 'S-1-1-0' }).Count -eq 0) 'all rules apply to the SID S-1-1-0'
Assert (@($rules | Where-Object { $_.HasAttribute('UserOrGroupName') }).Count -eq 0) 'no rule names an account (only the SID)'
Assert (@($rules | Where-Object { $_.GetAttribute('Action') -ne 'Allow' }).Count -eq 0) 'all rules are Allow rules'
$conditions = @($document.SelectNodes('//FilePublisherCondition'))
Assert (@($conditions | Where-Object { $_.GetAttribute('ProductName') -ne '*' -or $_.GetAttribute('BinaryName') -ne '*' }).Count -eq 0) 'no product and no file name in the rules'
Assert (@($document.SelectNodes('//BinaryVersionRange') | Where-Object { $_.GetAttribute('LowSection') -ne '*' -or $_.GetAttribute('HighSection') -ne '*' }).Count -eq 0) 'no version range in the rules'
Assert (@($conditions | Where-Object { $_.GetAttribute('PublisherName') -ne $name }).Count -eq 0) 'the publisher name is kept as given (special characters survive the XML escaping)'
Assert ($xml -notmatch '<!DOCTYPE' -and $xml -notmatch '<\?xml') 'no DTD and no XML declaration'
Assert (@($rules | Where-Object { $_.GetAttribute('Name') -notlike 'SelfX publisher rule*' }).Count -eq 0) 'rule names start with the prefix'
Assert ($xml -eq (New-SelfXAppLockerPublisherPolicyXml -PublisherName $name -RuleNamePrefix 'SelfX')) 'the same input gives the same rules and rule IDs (a new build replaces, does not add)'
$other = ConvertTo-SelfXXmlDocument -Text (New-SelfXAppLockerPublisherPolicyXml -PublisherName 'O=OTHER, C=DE' -RuleNamePrefix 'SelfX')
Assert (@($other.SelectNodes('//FilePublisherRule') | ForEach-Object { $_.GetAttribute('Id') }) -join ',' -ne (@($rules | ForEach-Object { $_.GetAttribute('Id') }) -join ',')) 'another publisher gives other rule IDs'
Assert ((@($rules | ForEach-Object { $_.GetAttribute('Id') } | Sort-Object -Unique)).Count -eq 3) 'the three rule IDs are different'
$parsedId = [guid]::Empty
Assert (@($rules | Where-Object { -not [guid]::TryParse($_.GetAttribute('Id'), [ref]$parsedId) }).Count -eq 0) 'the rule IDs are GUIDs'
Assert (Test-Throws { New-SelfXAppLockerPublisherPolicyXml -PublisherName '*' -RuleNamePrefix 'SelfX' }) 'a wildcard as publisher is refused'
Assert (Test-Throws { New-SelfXAppLockerPublisherPolicyXml -PublisherName '' -RuleNamePrefix 'SelfX' }) 'an empty publisher is refused'
Assert (Test-Throws { New-SelfXAppLockerPublisherPolicyXml -PublisherName $name -RuleNamePrefix '' }) 'an empty prefix is refused'
Assert (Test-Throws { New-SelfXAppLockerPublisherPolicyXml -PublisherName $name -RuleNamePrefix "a`nb" }) 'a prefix with a control character is refused'
Assert (Test-Throws { New-SelfXAppLockerPublisherPolicyXml -PublisherName $name -RuleNamePrefix ('x' * 101) }) 'a prefix longer than 100 characters is refused'

Write-Host 'Part 1: check of a publisher policy'
Assert ((Get-PolicyProblems $xml).Count -eq 0) 'the generated policy passes the check'
$badHash = $xml.Replace('</AppLockerPolicy>', '<RuleCollection Type="Msi"><FileHashRule Id="x" Name="h" Description="" UserOrGroupSid="S-1-1-0" Action="Allow"/></RuleCollection></AppLockerPolicy>')
Assert ((Get-PolicyProblems $badHash).Count -gt 0) 'a hash rule (and a fourth collection) is found'
$badSid = $xml.Replace('UserOrGroupSid="S-1-1-0"', 'UserOrGroupSid="S-1-5-32-545"')
Assert ((Get-PolicyProblems $badSid).Count -gt 0) 'a rule for another SID is found'
$badName = $xml.Replace('UserOrGroupSid="S-1-1-0"', 'UserOrGroupSid="Everyone"')
Assert ((Get-PolicyProblems $badName) -join ' ' -match 'S-1-1-0') 'the name Everyone instead of the SID is found'
$badDeny = $xml.Replace('Action="Allow"', 'Action="Deny"')
Assert ((Get-PolicyProblems $badDeny).Count -gt 0) 'a Deny rule is found'
$badProduct = $xml.Replace('ProductName="*"', 'ProductName="SELFX"')
Assert ((Get-PolicyProblems $badProduct).Count -gt 0) 'a rule bound to a product is found'
$badVersion = $xml.Replace('LowSection="*"', 'LowSection="3.0.0.0"')
Assert ((Get-PolicyProblems $badVersion).Count -gt 0) 'a rule bound to a version is found'
$badWildcard = $xml.Replace([System.Security.SecurityElement]::Escape($name), '*')
Assert ((Get-PolicyProblems $badWildcard).Count -gt 0) 'a rule for every publisher is found'
$mixed = $xml
$firstIndex = $mixed.IndexOf('L=BERLIN')
$mixed = $mixed.Remove($firstIndex, 'L=BERLIN'.Length).Insert($firstIndex, 'L=HAMBURG')
Assert ((Get-PolicyProblems $mixed) -join ' ' -match 'different publishers') 'rules of different publishers are found'
$noDll = $xml -replace '(?s)<RuleCollection Type="Dll".*?</RuleCollection>', ''
Assert ((Get-PolicyProblems $noDll).Count -gt 0) 'a missing rule collection is found'
$twoRules = $xml -replace '(<RuleCollection Type="Exe"[^>]*>)', ('$1' + '<FilePublisherRule Id="a" Name="b" Description="" UserOrGroupSid="S-1-1-0" Action="Allow"/>')
Assert ((Get-PolicyProblems $twoRules).Count -gt 0) 'a second rule in a collection is found'
Assert ((Get-PolicyProblems '<AppLockerPolicy').Count -gt 0) 'text that is not XML is a problem, not an exception'
Assert ((Get-PolicyProblems '<!DOCTYPE AppLockerPolicy [<!ENTITY a "b">]><AppLockerPolicy Version="1"/>').Count -gt 0) 'a policy with a DTD is refused (no entity expansion)'
Assert ((Get-PolicyProblems '<Other/>').Count -gt 0) 'another root element is a problem'

Write-Host 'Part 1: signature state (mocked signatures)'
$signed = ConvertTo-SelfXSignerState -Name 'a.ps1' -Signature (New-FakeSignature 'Valid' 'ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34')
Assert ($signed.State -eq 'Signed' -and $signed.Thumbprint -eq 'AB12CD34AB12CD34AB12CD34AB12CD34AB12CD34') 'status Valid is Signed (thumbprint in upper case)'
Assert ((ConvertTo-SelfXSignerState -Name 'a.ps1' -Signature (New-FakeSignature 'NotSigned')).State -eq 'Unsigned') 'status NotSigned is Unsigned'
foreach ($status in 'HashMismatch', 'NotTrusted', 'UnknownError', 'NotSupportedFileFormat', 'Incompatible') {
    Assert ((ConvertTo-SelfXSignerState -Name 'a.ps1' -Signature (New-FakeSignature $status)).State -eq 'Invalid') "status $status is Invalid (not trusted, not hashed around)"
}
Assert ((ConvertTo-SelfXSignerState -Name 'a.ps1' -Signature (New-FakeSignature 'Valid' '')).State -eq 'Invalid') 'status Valid without a signer certificate is Invalid'
Assert ((ConvertTo-SelfXSignerState -Name 'a.ps1' -Signature $null).State -eq 'Invalid') 'no signature object (file not readable) is Invalid'
function New-State { param([string]$Name, [string]$State, [string]$Thumbprint = '') [pscustomobject]@{ Name = $Name; State = $State; Status = $State; Thumbprint = $Thumbprint } }
$one = New-State 'a.exe' 'Signed' 'AA'
$two = New-State 'b.dll' 'Signed' 'AA'
$stranger = New-State 'c.dll' 'Signed' 'BB'
$unsigned = New-State 'd.ps1' 'Unsigned'
$invalid = New-State 'e.ps1' 'Invalid'
Assert ($null -eq (Get-SelfXSignerSetProblem -State @($one, $two) -RequireSigned)) 'files of one signer pass'
Assert ($null -ne (Get-SelfXSignerSetProblem -State @($one, $invalid))) 'an invalid signature is a problem'
Assert ($null -ne (Get-SelfXSignerSetProblem -State @($one, $invalid) -AllowMultipleSigners)) 'an invalid signature is a problem also when several signers are allowed'
Assert ((Get-SelfXSignerSetProblem -State @($one, $unsigned) -RequireSigned) -match 'not signed') 'an unsigned file is a problem when all must be signed'
Assert ($null -eq (Get-SelfXSignerSetProblem -State @($one, $unsigned))) 'an unsigned file is fine when the fallback is a hash rule'
Assert ($null -ne (Get-SelfXSignerSetProblem -State @($unsigned))) 'a package without any signed file is a problem'
Assert ((Get-SelfXSignerSetProblem -State @($one, $stranger)) -match 'different certificates') 'two signers are a problem'
Assert ($null -eq (Get-SelfXSignerSetProblem -State @($one, $stranger) -AllowMultipleSigners)) 'two signers pass when they are allowed on purpose'
Assert ($null -ne (Get-SelfXSignerSetProblem -State @())) 'no file at all is a problem'

Write-Host 'Part 1: scripts'
$scriptText = Get-Content -LiteralPath $rulesScript -Raw
Assert ($scriptText -match [regex]::Escape("[ValidateSet('Hash', 'Publisher')][string]`$Mode = 'Hash'")) 'the mode is Hash or Publisher and Hash is the default'
Assert ($scriptText -notmatch '-User\s+Everyone' -and $scriptText -match "-User 'S-1-1-0'") 'the hash rules use the SID, not the name Everyone'
Assert ($scriptText -match 'New-SelfXAppLockerPublisherPolicyXml' -and $scriptText -notmatch 'PublisherName\s*[:=]\s*\$PublisherName') 'the publisher is read from the files, there is no publisher parameter'
$libraryText = Get-Content -LiteralPath (Join-Path $ScriptFolder 'SelfXPublisherRules.ps1') -Raw
Assert ($libraryText -notmatch '(?i)-User\s+(Everyone|Jeder)' -and $libraryText -notmatch 'UserOrGroupName') 'the library names no account'
foreach ($file in $rulesScript, (Join-Path $ScriptFolder 'SelfXPublisherRules.ps1'), (Join-Path $ScriptFolder 'SelfXTestCertificate.ps1')) {
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$parseErrors)
    Assert (@($parseErrors).Count -eq 0) "$(Split-Path -Leaf $file) parses without errors"
    Assert (-not ([IO.File]::ReadAllBytes($file) | Where-Object { $_ -gt 127 })) "$(Split-Path -Leaf $file) is plain ASCII (the same in Windows PowerShell 5.1 and PowerShell 7)"
}

if (-not $isWindowsHost) {
    Skip 'Part 2 and 3' 'not Windows'
    if ($script:Failed -gt 0) { Write-Host "$script:Failed test(s) failed." -ForegroundColor Red; exit 1 }
    Write-Host 'All tests passed.'
    exit 0
}

Write-Host 'Build script'
$build = Get-Content -LiteralPath (Join-Path $ScriptFolder 'Build-SelfXBinaries.ps1') -Raw
Assert ($build -notmatch '-User\s+Everyone') 'Build-SelfXBinaries.ps1 does not use the localized name Everyone'
Assert ($build -match 'New-SelfXAppLockerRules\.ps1') 'Build-SelfXBinaries.ps1 uses New-SelfXAppLockerRules.ps1'

$probe = & $windowsPowerShell -NoProfile -Command "if (@(Get-Command Get-AppLockerFileInformation, New-AppLockerPolicy -ErrorAction SilentlyContinue).Count -eq 2) { 'yes' } else { 'no' }"
if ("$probe".Trim() -ne 'yes') {
    Write-Host '  SKIP the AppLocker cmdlets are not available on this computer'
    if ($script:Failed -gt 0) { exit 1 }
    exit 0
}

$createdCertificates = New-Object System.Collections.Generic.List[string]
$rootLocation = 'CurrentUser'
$work = Join-Path ([IO.Path]::GetTempPath()) ('SelfX Rules Test ' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $source = Join-Path $env:SystemRoot 'System32\whoami.exe'
    $one = Join-Path $work 'One Program.exe'
    $two = Join-Path $work 'Two.dll'
    Copy-Item -LiteralPath $source -Destination $one
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\kernel32.dll') -Destination $two
    $out = Join-Path $work 'rules.xml'

    Write-Host 'Rules'
    $result = Invoke-Rules -PathList "$one|$two" -OutputFile $out
    Assert ($result.Exit -eq 0) "two files (one path with spaces): exit code 0 ($($result.Output))"
    Assert (Test-Path -LiteralPath $out -PathType Leaf) 'output file is written'
    if (Test-Path -LiteralPath $out) {
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($out)
        $rules = @($document.SelectNodes('//FileHashRule'))
        Assert ($rules.Count -eq 2) 'one hash rule per file'
        Assert (@($rules | Where-Object { $_.GetAttribute('UserOrGroupSid') -ne 'S-1-1-0' }).Count -eq 0) 'all rules apply to the SID S-1-1-0'
        Assert (@($rules | Where-Object { $_.GetAttribute('Action') -ne 'Allow' }).Count -eq 0) 'all rules are Allow rules'
        Assert (@($rules | Where-Object { $_.GetAttribute('Name') -notlike 'SelfX test*' }).Count -eq 0) 'rule names start with the prefix'
        $bytes = [IO.File]::ReadAllBytes($out)
        Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'file is UTF-8 without BOM'
    }

    Write-Host 'Refused input'
    $bad = Join-Path $work 'bad.xml'
    $result = Invoke-Rules -PathList "$one|$(Join-Path $work 'missing.exe')" -OutputFile $bad
    Assert ($result.Exit -eq 1 -and $result.Output -match 'File not found') 'a missing file is refused with a message'
    Assert (-not (Test-Path -LiteralPath $bad)) 'no output file after an error'
    $result = Invoke-Rules -PathList '|' -OutputFile $bad
    Assert ($result.Exit -eq 1 -and $result.Output -match 'No program file') 'an empty list is refused'
    $result = Invoke-Rules -PathList $one -OutputFile (Join-Path $work 'no-folder\rules.xml')
    Assert ($result.Exit -eq 1) 'an output folder that does not exist is refused'

    Write-Host 'Part 2: publisher mode refusals (no certificate needed)'
    $unsignedScript = Join-Path $work 'Unsigned.ps1'
    [IO.File]::WriteAllText($unsignedScript, "Write-Output 'SelfX rules test'`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $refused = Join-Path $work 'refused.xml'
    $result = Invoke-Rules -PathList $unsignedScript -OutputFile $refused -Mode Publisher
    Assert ($result.Exit -eq 1 -and $result.Output -match 'not signed') 'an unsigned file is refused in the publisher mode'
    Assert (-not (Test-Path -LiteralPath $refused)) 'no output file after the refusal'
    $result = Invoke-Rules -PathList (Join-Path $work 'missing.ps1') -OutputFile $refused -Mode Publisher
    Assert ($result.Exit -eq 1 -and $result.Output -match 'File not found') 'a missing file is refused in the publisher mode'
    $result = Invoke-Rules -PathList '|' -OutputFile $refused -Mode Publisher
    Assert ($result.Exit -eq 1 -and $result.Output -match 'No program file') 'an empty list is refused in the publisher mode'
    $result = Invoke-Rules -PathList $unsignedScript -OutputFile $refused -Mode Other
    Assert ($result.Exit -ne 0 -and -not (Test-Path -LiteralPath $refused)) 'an unknown mode is refused'
    $result = Invoke-Rules -PathList "$one|$two" -OutputFile (Join-Path $work 'default.xml')
    Assert ($result.Exit -eq 0 -and (Get-Content -LiteralPath (Join-Path $work 'default.xml') -Raw) -match 'FileHashRule' -and (Get-Content -LiteralPath (Join-Path $work 'default.xml') -Raw) -notmatch 'FilePublisherRule') 'without -Mode the hash rules are written, as before'

    Write-Host 'Part 3: publisher mode with signed test files'
    . (Join-Path $ScriptFolder 'SelfXSigning.ps1')
    . (Join-Path $ScriptFolder 'SelfXTestCertificate.ps1')
    $trust = Get-SelfXTestRootLocation
    $rootLocation = $trust.Location
    if (-not $trust.Allowed) {
        Skip 'Part 3: signed test files' 'a trusted root is needed; set SELFX_TEST_ALLOW_ROOT_IMPORT=1 (adds the test certificates to the trusted roots until the end of the test) or run on GitHub Actions'
    }
    else {
        $certA = New-SelfXTestCertificate 'A'
        $createdCertificates.Add($certA.Thumbprint)
        $certB = New-SelfXTestCertificate 'B'
        $createdCertificates.Add($certB.Thumbprint)
        Add-SelfXTestRoot -Certificate $certA -Location $rootLocation
        Add-SelfXTestRoot -Certificate $certB -Location $rootLocation
        $signedOne = Join-Path $work 'Signed One.ps1'
        $signedTwo = Join-Path $work 'Signed Two.ps1'
        $signedOther = Join-Path $work 'Signed Other.ps1'
        foreach ($file in $signedOne, $signedTwo, $signedOther) { [IO.File]::WriteAllText($file, "Write-Output 'SelfX rules test'`r`n", (New-Object System.Text.UTF8Encoding($false))) }
        $null = Set-SelfXCodeSignature -Path $signedOne, $signedTwo -Certificate $certA
        $null = Set-SelfXCodeSignature -Path $signedOther -Certificate $certB
        $published = Join-Path $work 'publisher.xml'

        $result = Invoke-Rules -PathList "$signedOne|$signedTwo" -OutputFile $published -Mode Publisher
        Assert ($result.Exit -eq 0) "two signed files: exit code 0 ($($result.Output))"
        if (Test-Path -LiteralPath $published) {
            $text = Get-Content -LiteralPath $published -Raw
            Assert (@(Get-SelfXAppLockerPublisherPolicyProblem -PolicyXml $text).Count -eq 0) 'the written policy passes the structure check'
            $document = ConvertTo-SelfXXmlDocument -Text $text
            Assert (@($document.SelectNodes('//FilePublisherRule')).Count -eq 3) 'one publisher rule for each of Exe, Dll and Script'
            Assert ($document.SelectNodes('//FileHashRule').Count -eq 0) 'no hash rule in the publisher mode'
            Assert (@($document.SelectNodes('//FilePublisherRule') | Where-Object { $_.GetAttribute('UserOrGroupSid') -ne 'S-1-1-0' }).Count -eq 0) 'all rules apply to the SID S-1-1-0'
            # Read in Windows PowerShell 5.1 (PowerShell 7 reaches the AppLocker cmdlets through a compatibility layer).
            $expectedPublisher = ("$(& $windowsPowerShell -NoProfile -Command "(Get-AppLockerFileInformation -Path '$signedOne').Publisher.PublisherName")").Trim()
            Assert ($expectedPublisher -and $document.SelectSingleNode('//FilePublisherCondition').GetAttribute('PublisherName') -eq $expectedPublisher) 'the publisher name is the one that AppLocker reads from the signature'
            $bytes = [IO.File]::ReadAllBytes($published)
            Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'file is UTF-8 without BOM'
            # The same files again give the same file: a new build keeps the rule IDs.
            $again = Join-Path $work 'publisher-again.xml'
            $null = Invoke-Rules -PathList "$signedTwo|$signedOne" -OutputFile $again -Mode Publisher
            Assert ((Test-Path -LiteralPath $again) -and ((Get-Content -LiteralPath $again -Raw) -eq $text)) 'the same signer gives the same rules (any order of the files)'
        }
        else { Assert $false 'the policy file is written' }

        Remove-Item -LiteralPath $refused -Force -ErrorAction SilentlyContinue
        $result = Invoke-Rules -PathList "$signedOne|$signedOther" -OutputFile $refused -Mode Publisher
        Assert ($result.Exit -eq 1 -and $result.Output -match 'different') 'files of two different signers are refused'
        Assert (-not (Test-Path -LiteralPath $refused)) 'no output file after the refusal of two signers'
        $result = Invoke-Rules -PathList "$signedOne|$unsignedScript" -OutputFile $refused -Mode Publisher
        Assert ($result.Exit -eq 1 -and $result.Output -match 'not signed') 'one unsigned file among signed files is refused'
        $tampered = Join-Path $work 'Tampered.ps1'
        Copy-Item -LiteralPath $signedOne -Destination $tampered
        # Change a character before the signature block (text after the block is not a hash mismatch for every host).
        [IO.File]::WriteAllText($tampered, ([IO.File]::ReadAllText($tampered).Replace('SelfX rules test', 'SelfX rules TEST')), (New-Object System.Text.UTF8Encoding($false)))
        $result = Invoke-Rules -PathList "$signedOne|$tampered" -OutputFile $refused -Mode Publisher
        Assert ($result.Exit -eq 1 -and $result.Output -match 'not valid') 'a file changed after signing is refused'
        Assert (-not (Test-Path -LiteralPath $refused)) 'no output file after the refusal of a changed file'
        $result = Invoke-Rules -PathList "$signedOne|$signedTwo" -OutputFile (Join-Path $work 'no-folder\rules.xml') -Mode Publisher
        Assert ($result.Exit -eq 1) 'an output folder that does not exist is refused in the publisher mode'
    }
}
finally {
    foreach ($thumbprint in $createdCertificates) { Remove-SelfXTestCertificate -Thumbprint $thumbprint -Location $rootLocation }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed -gt 0) { Write-Host "$script:Failed test(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed.'
exit 0
