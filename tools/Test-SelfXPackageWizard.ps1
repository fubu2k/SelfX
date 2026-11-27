<#
.SYNOPSIS
    Tests the package wizard (New-SelfXPackage.ps1, Wizard\SelfXWizard.ps1) without building a package.

.DESCRIPTION
    Isolated: works in a temporary folder, changes no repository file, sends nothing, needs no .NET SDK and no
    IntuneWinAppUtil.exe. Checks the language files, the validation of every kind of answer (including injection
    attempts), the patching of Tool_Config.xml and Ticket_Config.xml, the generated Intune scripts and the
    instructions, and the failure of invalid answer files. Invoke-SelfXPackageBuild runs on a fake payload (dummy programs) with a
    dummy for IntuneWinAppUtil.exe and without the AppLocker and ConfigCI cmdlets (the rule scripts are replaced by a recorder): a complete
    run, the files of the result, an abort in the middle (no half-finished output), a second run (SelfX.Code.json unchanged), a changed
    payload, the logo check and answers with a secret. A run in the trust mode Signature (real signatures) needs a trusted test root
    (GitHub Actions with administrator rights, or SELFX_TEST_ALLOW_ROOT_IMPORT=1) and is skipped otherwise.
    Works in Windows PowerShell 5.1 and PowerShell 7.

.NOTES
    Name    : Test-SelfXPackageWizard.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 1.1.0
    History : 1.1.0 (2026-11-27, fubu2k) tests of Invoke-SelfXPackageBuild; the console tests use a fake payload (layout App/Config)
    Exit code: 0 = all tests passed, 1 = at least one failed
#>
$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$WizardFolder = Join-Path $ScriptFolder 'Wizard'
. (Join-Path $WizardFolder 'SelfXWizard.ps1')
. (Join-Path $RepositoryRoot 'SelfX Service\Sources\TicketMail.ps1')
. (Join-Path $ScriptFolder 'SelfXTestCertificate.ps1')
$hostExe = (Get-Process -Id $PID).Path

$script:Failed = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  PASS $Name" } else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}
function Assert-Throws {
    param([scriptblock]$Code, [string]$Name)
    $threw = $false
    try { & $Code | Out-Null } catch { $threw = $true }
    Assert $threw $Name
}

function New-FakePayload {
    # A payload as the release archive has it (App and Config, Bin with dummy programs and SelfX.Binaries.json, tools and licence texts),
    # made from the repository package folder. Real = copy real PE files for the programs (needed to sign them).
    param([string]$Folder, [switch]$RealPrograms)
    $repo = Join-Path $Folder 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Copy-Item -Path (Join-Path $RepositoryRoot 'SelfX Service\*') -Destination $repo -Recurse -Force
    $bin = Join-Path $repo 'Bin'
    $programs = [ordered]@{ 'SelfXService.exe' = 'Service/SelfXService.cs'; 'SelfX.exe' = 'Service/SelfXLauncher.cs'; 'SelfXSessionStarter.dll' = 'Service/SelfXSessionStarter.cs'; 'WinRT/SelfXWinRT.dll' = 'Service/SelfXWinRT.cs'; 'Audio/SelfXAudio.dll' = 'Service/SelfXAudio.cs' }
    $sources = [ordered]@{}; $binaries = [ordered]@{}
    foreach ($name in $programs.Keys) {
        $path = Join-Path $bin $name.Replace('/', '\')
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        if ($RealPrograms) { Copy-Item -LiteralPath $(if ($name -like '*.exe') { Join-Path $env:SystemRoot 'System32\whoami.exe' } else { Join-Path $env:SystemRoot 'System32\version.dll' }) -Destination $path }
        else { [IO.File]::WriteAllText($path, "binary $name") }
        $binaries[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $sources[$programs[$name]] = (Get-FileHash -LiteralPath (Join-Path $repo $programs[$name].Replace('/', '\')) -Algorithm SHA256).Hash
    }
    $manifest = [ordered]@{ ManifestVersion = 3; ToolVersion = 'test'; BuiltUtc = ''; Sources = $sources; Binaries = $binaries }
    [IO.File]::WriteAllText((Join-Path $bin 'SelfX.Binaries.json'), ($manifest | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    $payload = Join-Path $Folder 'payload'
    $version = Get-SelfXVersionFromFile -Path (Join-Path $repo 'Version.txt')
    $null = New-SelfXPayloadFromRepository -SourceFolder $repo -Target $payload
    New-Item -ItemType Directory -Path (Join-Path $payload 'tools') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $payload 'tools\note.txt'), 'tools')
    [IO.File]::WriteAllText((Join-Path $payload 'LICENSE.md'), 'licence')
    Remove-Item -LiteralPath $repo -Recurse -Force
    return $payload
}

function Get-TreeDigest {
    param([string]$Folder)
    $root = (Get-Item -LiteralPath $Folder).FullName.TrimEnd('\')
    $lines = foreach ($file in @(Get-ChildItem -LiteralPath $Folder -Recurse -File -Force | Sort-Object FullName)) { '{0}={1}' -f $file.FullName.Substring($root.Length), (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    return ($lines -join ';')
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-WizardTest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # ---------------------------------------------------------- language files
    Write-Host 'Language files'
    $en = Read-WizardTextFile -Path (Join-Path $WizardFolder 'Wizard.en.xml')
    $questionIds = @((Get-WizardQuestions) | ForEach-Object { $_.Id }) + @('UnitId', 'UnitMail', 'UnitCc', 'UnitGroupTags', 'UnitOUs', 'UnitCategories', 'UnitMore', 'Tool', 'BuildBinaries', 'Output', 'summary')
    $missing = @($questionIds | Where-Object { -not $en.ContainsKey("$_.ask") -or -not $en.ContainsKey("$_.rec") })
    Assert ($missing.Count -eq 0) ("English has .ask and .rec for every question" + $(if ($missing) { ': ' + ($missing -join ',') }))
    foreach ($language in @(Get-WizardLanguages -Folder $WizardFolder)) {
        $table = Read-WizardTextFile -Path $language.Path
        $unknown = @($table.Keys | Where-Object { -not $en.ContainsKey($_) })
        Assert ($unknown.Count -eq 0) "$($language.Culture): only known Ids"
        $bad = @($table.Keys | Where-Object { $en.ContainsKey($_) -and (([regex]::Matches($table[$_], '\{\d+\}') | ForEach-Object Value | Sort-Object) -join ',') -ne (([regex]::Matches($en[$_], '\{\d+\}') | ForEach-Object Value | Sort-Object) -join ',') })
        Assert ($bad.Count -eq 0) "$($language.Culture): same placeholders as English" 
        if ($language.Culture -ne 'en') { Assert ($table.Count -eq $en.Count) "$($language.Culture): complete ($($table.Count) of $($en.Count) texts)" }
    }
    Initialize-WizardTexts -Folder $WizardFolder -Culture 'xx-YY'
    Assert ((Get-WText 'yes') -eq 'y') 'unknown culture falls back to English'
    Initialize-WizardTexts -Folder $WizardFolder -Culture 'de-CH'
    Assert ((Get-WText 'yes') -eq 'j') 'de-CH uses de'

    # ---------------------------------------------------------- validation
    Write-Host 'Validation'
    Assert ((ConvertTo-WizardValue -Kind 'bool' -Value 'ja') -eq $true) 'bool ja'
    Assert ((ConvertTo-WizardValue -Kind 'bool' -Value 'n') -eq $false) 'bool n'
    Assert-Throws { ConvertTo-WizardValue -Kind 'bool' -Value 'vielleicht' } 'bool rejects other text'
    Assert ((ConvertTo-WizardValue -Kind 'mail' -Value 'it@example.com') -eq 'it@example.com') 'mail ok'
    foreach ($badMail in 'a@b', "a@example.com`nBcc: x@example.com", 'a@example.com;b@example.com', 'Name <a@example.com>', 'a b@example.com') {
        Assert-Throws { ConvertTo-WizardValue -Kind 'mail' -Value $badMail } "mail rejects '$($badMail -replace "`n", '\n')'"
    }
    Assert-Throws { ConvertTo-WizardValue -Kind 'url' -Value 'http://example.com' } 'url rejects http'
    Assert-Throws { ConvertTo-WizardValue -Kind 'url' -Value 'https://user:pw@example.com' } 'url rejects user info'
    Assert-Throws { ConvertTo-WizardValue -Kind 'url' -Value 'javascript:alert(1)' } 'url rejects javascript'
    Assert ((ConvertTo-WizardValue -Kind 'url' -Value 'https://support.example.com/x') -eq 'https://support.example.com/x') 'url https ok'
    Assert ((ConvertTo-WizardValue -Kind 'teams' -Value 'team@example.com') -eq 'team@example.com') 'teams accepts mail'
    Assert-Throws { ConvertTo-WizardValue -Kind 'color' -Value 'red' } 'color rejects names'
    Assert ((ConvertTo-WizardValue -Kind 'color' -Value '#e20074') -eq '#E20074') 'color normalized'
    Assert-Throws { ConvertTo-WizardValue -Kind 'tag' -Value 'a b' } 'subject tag rejects space'
    Assert-Throws { ConvertTo-WizardValue -Kind 'unitid' -Value '..\x' } 'unit id rejects path characters'
    Assert-Throws { ConvertTo-WizardValue -Kind 'int' -Value '0' -Min 1 -Max 3650 } 'int below minimum'
    Assert-Throws { ConvertTo-WizardValue -Kind 'int' -Value '99999' -Min 1 -Max 3650 } 'int above maximum'
    Assert-Throws { ConvertTo-WizardValue -Kind 'choice' -Value 'Everything' -Choices @('Enforce', 'Audit') } 'choice rejects unknown'
    Assert ((ConvertTo-WizardValue -Kind 'choice' -Value 'audit' -Choices @('Enforce', 'Audit')) -eq 'Audit') 'choice case insensitive'
    Assert-Throws { ConvertTo-WizardValue -Kind 'text' -Value "a`r`nb" -Max 40 } 'text rejects line breaks'
    Assert ((ConvertTo-WizardValue -Kind 'list' -Value 'A, B ,,C').Count -eq 3) 'list splits at commas'
    Assert-Throws { Test-WizardUnitValues -Unit ([pscustomobject]@{ GroupTags = @('x;y'); Categories = @(); OUs = @() }) } 'group tag rejects ;'

    # ---------------------------------------------------------- XML patching
    Write-Host 'XML patching'
    $xml = "<?xml version=`"1.0`"?>`n<!-- <Name>comment</Name> not here -->`n<R><A>1</A><B></B><C />`n</R>"
    $xmlComment = "<?xml version=`"1.0`"?>`n<!-- keep me -->`n<R><A>1</A><B></B><C />`n</R>"
    $patched = Set-XmlElementText -Xml (Set-XmlElementText -Xml (Set-XmlElementText -Xml $xmlComment -Name 'A' -Value 'x') -Name 'B' -Value 'y') -Name 'C' -Value 'z'
    Assert ($patched -match '<!-- keep me -->' -and $patched -match '<A>x</A><B>y</B><C>z</C>') 'values replaced, comment and layout kept'
    $evil = Set-XmlElementText -Xml $xmlComment -Name 'A' -Value '</A><Evil attr="1"/>&'
    $doc = New-Object Xml.XmlDocument; $doc.LoadXml($evil)
    Assert ($doc.R.A -eq '</A><Evil attr="1"/>&' -and $null -eq $doc.SelectSingleNode('//Evil')) 'XML special characters are escaped (no injection)'
    Assert-Throws { Set-XmlElementText -Xml $xmlComment -Name 'Missing' -Value 'x' } 'missing element is an error'
    Assert-Throws { Set-XmlElementText -Xml '<R><A>1</A><A>2</A></R>' -Name 'A' -Value 'x' } 'duplicate element is an error'

    # ---------------------------------------------------------- end to end (configure only)
    Write-Host 'Wizard run (-ConfigureOnly)'
    $toolConfig = Join-Path $RepositoryRoot 'SelfX Service\Sources\Tool_Config.xml'
    $ticketConfig = Join-Path $RepositoryRoot 'SelfX Service\Sources\Ticket_Config.xml'
    $hashBefore = @((Get-FileHash $toolConfig).Hash, (Get-FileHash $ticketConfig).Hash)
    $fakePayload = New-FakePayload -Folder (Join-Path $work 'fake')
    $logo = Join-Path $work 'logo.png'
    [IO.File]::WriteAllBytes($logo, [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
    $answers = [ordered]@{
        WizardLanguage = 'de'; ToolLanguage = 'Auto'; ShowLanguageSetting = $true; OrgName = 'Contoso <&> Test'; ToolName = 'SelfX'
        SupportMail = 'it-support@contoso.example'; SupportPhone = '+49 30 1234'; SupportHours = 'Mo.-Fr. 08:00-17:00'
        SupportWebsite = 'https://support.contoso.example'; SupportTeams = ''; LogoPath = $logo; AccentColor = '#e20074'
        TicketEnabled = $true; TicketMail = 'servicedesk@contoso.example'; TicketSubjectTag = 'SelfX'; MultiOrg = $true
        HybridJoin = $true; UseGroupTags = $true; UseDeviceClass = $true
        Units = @(
            [ordered]@{ UnitId = 'IT-Berlin'; UnitMail = 'it-berlin@contoso.example'; UnitCc = ''; UnitGroupTags = @('DE-IT1-BER'); UnitOUs = @('OU=Berlin'); UnitCategories = @() },
            [ordered]@{ UnitId = 'IT-Mobile'; UnitMail = 'it-mobile@contoso.example'; UnitCc = 'service@contoso.example'; UnitGroupTags = @(); UnitOUs = @(); UnitCategories = @('Tablet') }
        )
        CopilotEnabled = $true; CopilotAudience = 'User'; CopilotClearClipboard = $true
        WikiEnabled = $true; WikiUrl = 'https://wiki.contoso.example/start'; WikiName = 'Contoso <Wiki>'
        TrayIcon = $true; ShortcutDesktop = $false; ShortcutStartMenu = $true; Expert = $false
    }
    function Invoke-Wizard {
        param([hashtable]$Answers, [string]$Folder, [switch]$AsJson)
        $file = Join-Path $work ([guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($file, ($Answers | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
        $output = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptFolder 'New-SelfXPackage.ps1') -AnswerFile $file -OutputFolder $Folder -PayloadFolder $fakePayload -ConfigureOnly -Language de 2>&1
        return [pscustomobject]@{ Exit = $LASTEXITCODE; Output = ($output | Out-String) }
    }
    $out = Join-Path $work 'out'
    $run = Invoke-Wizard -Answers $answers -Folder $out
    Assert ($run.Exit -eq 0) ("wizard run exits with 0" + $(if ($run.Exit -ne 0) { ': ' + $run.Output }))
    $hashAfter = @((Get-FileHash $toolConfig).Hash, (Get-FileHash $ticketConfig).Hash)
    Assert (($hashBefore -join ',') -eq ($hashAfter -join ',')) 'repository files are unchanged'

    $cfg = New-Object Xml.XmlDocument; $cfg.XmlResolver = $null; $cfg.Load((Join-Path $out 'package\Config\Tool_Config.xml'))
    $g = $cfg.GUI_Config
    Assert ($g.Tool_Language -eq 'Auto' -and $g.Support_Mail -eq 'it-support@contoso.example') 'Tool_Config: language and support mail'
    Assert ($g.Ticket_Enabled -eq 'True' -and $g.Ticket_Mail -eq 'servicedesk@contoso.example') 'Tool_Config: ticket on, default recipient'
    Assert ($g.Copilot_Enabled -eq 'True' -and $g.Copilot_Audience -eq 'User' -and $g.Copilot_Clear_Clipboard -eq 'True') 'Tool_Config: Copilot'
    Assert ($g.Wiki_Enabled -eq 'True' -and $g.Wiki_Url -eq 'https://wiki.contoso.example/start' -and $g.Wiki_Name -eq 'Contoso <Wiki>') 'Tool_Config: wiki button'
    Assert ($g.Shortcut_Desktop -eq 'False' -and $g.Shortcut_StartMenu -eq 'True') 'Tool_Config: shortcuts'
    Assert ($g.Brand_Accent_Color -eq '#E20074' -and $g.Brand_Logo -eq 'Branding\logo.png') 'Tool_Config: branding'
    Assert ((Test-Path (Join-Path $out 'package\Config\Branding\logo.png')) -and -not (Test-Path (Join-Path $out 'package\Config\Branding\company_logo.png'))) 'logo copied, placeholder removed'
    Assert ($g.Service_FileCheck -eq 'Enforce' -and $g.Service_Privileges -eq 'Restricted') 'secure defaults stay without expert mode'
    Assert (-not (Test-Path (Join-Path $out 'package\Service\Projects')) -and @(Get-ChildItem (Join-Path $out 'package') -Recurse -Filter 'Test-*.ps1').Count -eq 0) 'copy has no project files and no tests'

    $ticket = Read-SelfXTicketConfig -Path (Join-Path $out 'package\Config\Ticket_Config.xml')
    Assert ($ticket.Errors.Count -eq 0 -and @($ticket.Units.Keys).Count -eq 2 -and @($ticket.Rules).Count -eq 3) 'Ticket_Config: no errors, 2 units, 3 rules'
    $r1 = Resolve-SelfXTicketUnit -Config $ticket -GroupTag 'DE-IT1-BER' -Category '' -OU ''
    $r2 = Resolve-SelfXTicketUnit -Config $ticket -GroupTag '' -Category '' -OU 'OU=Berlin,DC=contoso,DC=example'
    $r3 = Resolve-SelfXTicketUnit -Config $ticket -GroupTag '' -Category 'Tablet' -OU ''
    $r4 = Resolve-SelfXTicketUnit -Config $ticket -GroupTag 'XX' -Category 'Notebook' -OU ''
    Assert ($r1.Mail -eq 'it-berlin@contoso.example' -and $r2.Mail -eq 'it-berlin@contoso.example') 'routing by group tag and OU'
    Assert ($r3.Mail -eq 'it-mobile@contoso.example' -and $r3.Cc -eq 'service@contoso.example') 'routing by device class with Cc'
    Assert ($null -eq $r4) 'no rule: default recipient'

    $scripts = @(Get-ChildItem -LiteralPath $out -Filter 'Set-SelfXSupportUnit-*.ps1')
    Assert ($scripts.Count -eq 2) 'one Intune script per unit with group tag or device class (OU-only needs none)'
    foreach ($script in $scripts) {
        $errors = $null; [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$errors)
        Assert (@($errors).Count -eq 0) "$($script.Name) parses"
    }
    $berlin = Get-Content -LiteralPath (Join-Path $out 'Set-SelfXSupportUnit-IT-Berlin-DE-IT1-BER.ps1') -Raw
    Assert ($berlin -match "\`$GroupTag\s+= 'DE-IT1-BER'" -and $berlin -match "\`$TicketMail = 'it-berlin@contoso.example'") 'script carries group tag and mailbox'
    $guide = Get-Content -LiteralPath (Join-Path $out 'SelfX-Intune-Guide.de.txt') -Raw -Encoding UTF8
    Assert ($guide -match 'Contoso <&> Test' -and $guide -match 'Installationsbefehl' -and $guide -match 'Plattformskript' -and $guide -match 'Detection\.ps1') 'German guide mentions app, commands, detection and scripts'
    Assert ($guide -match 'Get-SelfXAsrEvents\.ps1' -and $guide -match '01443614-cd74-433a-b99e-2ecdc07bfc25' -and $guide -match 'ASR Only Per Rule Exclusions') 'German guide has the step about the Defender ASR rule'
    $asrFiles = @([regex]::Matches($guide, '(?m)^   - (C:\\Program Files\\SelfX\\[^\r\n]+)\r?$') | ForEach-Object { $_.Groups[1].Value })
    Assert ($asrFiles.Count -eq 4 -and @($asrFiles | Where-Object { $_ -notmatch '^C:\\Program Files\\SelfX\\App\\([A-Za-z]+\\)?[A-Za-z]+\.(exe|dll)$' }).Count -eq 0) 'guide names exactly four program files below SelfX\App for the exclusion (no folder, no wildcard)'
    Assert ($guide -match '(?m)^8\. Defender' -and $guide -match '(?m)^9\. Auf einem Pilotger' -and $guide -match '(?m)^7\. Ticket-Zuordnung') 'ASR step comes after the ticket step and before the test step (numbers 8 and 9 with scripts)'
    Initialize-WizardTexts -Folder $WizardFolder -Culture 'en'
    $enGuide = New-SelfXIntuneGuide -Answers @{ OrgName = 'Contoso'; Units = @() } -Version '3.1.0' -PackageFile 'p.intunewin' -DetectionFile 'd.ps1'
    Assert ($enGuide -match '(?m)^7\. Defender attack surface reduction' -and $enGuide -match '(?m)^8\. Test on a pilot device' -and $enGuide -match 'no guarantee') 'English guide without scripts: ASR step 7, test step 8, no promise that signing helps'
    Assert ($enGuide -notmatch '(?m)^   - .*(\*|SelfX\\?$)') 'English guide: no wildcard and no folder entry in the exclusion list'
    Initialize-WizardTexts -Folder $WizardFolder -Culture 'de-CH'
    $saved = Get-Content -LiteralPath (Join-Path $out 'selfx-answers.json') -Raw | ConvertFrom-Json
    Assert (@($saved.Units).Count -eq 2 -and $saved.OrgName -eq 'Contoso <&> Test') 'answers are saved'
    # Re-run with the saved file itself (round trip).
    $roundTrip = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptFolder 'New-SelfXPackage.ps1') -AnswerFile (Join-Path $out 'selfx-answers.json') -OutputFolder (Join-Path $work 'round') -PayloadFolder $fakePayload -ConfigureOnly 2>&1
    Assert ($LASTEXITCODE -eq 0) ('saved answers can be used again' + $(if ($LASTEXITCODE) { ': ' + ($roundTrip | Out-String) }))

    $minimal = [ordered]@{} ; foreach ($key in $answers.Keys) { $minimal[$key] = $answers[$key] }
    $minimal.UseDeviceClass = $false
    $minimal.Units = @([ordered]@{ UnitId = 'IT1'; UnitMail = 'it1@contoso.example'; UnitGroupTags = @('DE-IT1-BER') })
    Assert ((Invoke-Wizard -Answers $minimal -Folder (Join-Path $work 'minimal')).Exit -eq 0) 'unit without OU and device class keys is accepted'

    # ---------------------------------------------------------- injection in text answers
    $evilAnswers = [ordered]@{} ; foreach ($key in $answers.Keys) { $evilAnswers[$key] = $answers[$key] }
    $evilAnswers.ToolName = 'Self</Tool_Name><Evil/>X'
    $evilAnswers.Units = @([ordered]@{ UnitId = 'IT1'; UnitMail = 'it1@contoso.example'; UnitCc = ''; UnitGroupTags = @("T'; Remove-Item C:\ -Recurse; '"); UnitOUs = @(); UnitCategories = @() })
    $run = Invoke-Wizard -Answers $evilAnswers -Folder (Join-Path $work 'evil')
    Assert ($run.Exit -eq 1) 'group tag with a quote is refused'
    $evilAnswers.Units = @([ordered]@{ UnitId = 'IT1'; UnitMail = 'it1@contoso.example'; UnitCc = ''; UnitGroupTags = @(); UnitOUs = @('OU=A"/><Rule Source="OU" Regex=".*" Unit="IT1'); UnitCategories = @() })
    $run = Invoke-Wizard -Answers $evilAnswers -Folder (Join-Path $work 'evil2')
    Assert ($run.Exit -eq 0) 'XML characters in OU name are accepted as text'
    $cfgEvil = New-Object Xml.XmlDocument; $cfgEvil.XmlResolver = $null; $cfgEvil.Load((Join-Path $work 'evil2\package\Config\Tool_Config.xml'))
    Assert ($cfgEvil.GUI_Config.Tool_Name -eq 'Self</Tool_Name><Evil/>X' -and $null -eq $cfgEvil.SelectSingleNode('//Evil')) 'Tool_Name with XML is stored as text'
    $ticketEvil = Read-SelfXTicketConfig -Path (Join-Path $work 'evil2\package\Config\Ticket_Config.xml')
    Assert (@($ticketEvil.Rules).Count -eq 1) 'OU with XML characters stays one rule'

    # ---------------------------------------------------------- invalid answer files
    Write-Host 'Invalid answer files'
    $bad = [ordered]@{} ; foreach ($key in $answers.Keys) { $bad[$key] = $answers[$key] }
    $bad.SupportMail = "a@example.com`nBcc: x@example.com"
    Assert ((Invoke-Wizard -Answers $bad -Folder (Join-Path $work 'bad1')).Exit -eq 1) 'invalid mail address fails'
    $bad = [ordered]@{} ; foreach ($key in $answers.Keys) { $bad[$key] = $answers[$key] }
    $bad.Unknown = 'x'
    Assert ((Invoke-Wizard -Answers $bad -Folder (Join-Path $work 'bad2')).Exit -eq 1) 'unknown answer fails (typo protection)'
    $bad = [ordered]@{} ; foreach ($key in $answers.Keys) { $bad[$key] = $answers[$key] }
    $bad.OrgName = ''
    Assert ((Invoke-Wizard -Answers $bad -Folder (Join-Path $work 'bad3')).Exit -eq 1) 'missing organisation name fails'
    $bad = [ordered]@{} ; foreach ($key in $answers.Keys) { $bad[$key] = $answers[$key] }
    $bad.Units = @($answers.Units[0], $answers.Units[0])
    Assert ((Invoke-Wizard -Answers $bad -Folder (Join-Path $work 'bad4')).Exit -eq 1) 'duplicate unit fails'
    $bad = [ordered]@{} ; foreach ($key in $answers.Keys) { $bad[$key] = $answers[$key] }
    $bad.LogoPath = (Join-Path $work 'logo.exe'); [IO.File]::WriteAllText($bad.LogoPath, 'x')
    Assert ((Invoke-Wizard -Answers $bad -Folder (Join-Path $work 'bad5')).Exit -eq 1) 'logo with another extension fails'
    $bad = [ordered]@{} ; foreach ($key in $answers.Keys) { $bad[$key] = $answers[$key] }
    $bad.Expert = $true; $bad.FileCheck = 'Off'
    Assert ((Invoke-Wizard -Answers $bad -Folder (Join-Path $work 'bad6')).Exit -eq 1) 'invalid file check mode fails'

    # ---------------------------------------------------------- logo check (file header)
    Write-Host 'Logo check'
    $pngBytes = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0)
    $jpgBytes = [byte[]](0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10)
    $icoBytes = [byte[]](0, 0, 1, 0, 1, 0, 16, 16)
    $logoTarget = Join-Path $work 'logo-target'
    New-Item -ItemType Directory -Path $logoTarget | Out-Null
    foreach ($case in @(@('a.png', $pngBytes, 'logo.png'), @('b.jpg', $jpgBytes, 'logo.jpg'), @('c.jpeg', $jpgBytes, 'logo.jpg'), @('d.ico', $icoBytes, 'logo.ico'))) {
        $file = Join-Path $work $case[0]; [IO.File]::WriteAllBytes($file, [byte[]]$case[1])
        Assert ((Copy-WizardLogo -LogoPath $file -SourcesFolder $logoTarget) -eq ('Branding\' + $case[2])) "logo $($case[0]) is accepted as $($case[2])"
    }
    Assert (@(Get-ChildItem (Join-Path $logoTarget 'Branding')).Count -eq 1) 'an earlier logo is replaced, not added'
    $fake = Join-Path $work 'fake.png'; [IO.File]::WriteAllText($fake, 'this is not an image')
    Assert-Throws { Copy-WizardLogo -LogoPath $fake -SourcesFolder $logoTarget } 'a text file named .png is refused (file header)'
    $wrongKind = Join-Path $work 'wrong.jpg'; [IO.File]::WriteAllBytes($wrongKind, $pngBytes)
    Assert-Throws { Copy-WizardLogo -LogoPath $wrongKind -SourcesFolder $logoTarget } 'a png named .jpg is refused'
    $gif = Join-Path $work 'x.gif'; [IO.File]::WriteAllBytes($gif, [byte[]](0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0))
    Assert-Throws { Copy-WizardLogo -LogoPath $gif -SourcesFolder $logoTarget } 'a gif is refused (only png, jpg, ico)'
    $big = Join-Path $work 'big.png'; [IO.File]::WriteAllBytes($big, ([byte[]]$pngBytes + (New-Object byte[] (2MB + 1))))
    Assert-Throws { Copy-WizardLogo -LogoPath $big -SourcesFolder $logoTarget } 'a logo over 2 MB is refused'
    Assert-Throws { Copy-WizardLogo -LogoPath $work -SourcesFolder $logoTarget } 'a folder is refused as logo'
    Assert-Throws { Copy-WizardLogo -LogoPath (Join-Path $work 'missing.png') -SourcesFolder $logoTarget } 'a missing logo is refused'

    # ---------------------------------------------------------- Invoke-SelfXPackageBuild
    Write-Host 'Invoke-SelfXPackageBuild (dummy IntuneWinAppUtil, rule scripts recorded)'
    $payloadRoot = Join-Path $work 'build-test'
    $payload = New-FakePayload -Folder $payloadRoot
    $payloadBefore = Get-TreeDigest -Folder $payload

    # Dummy for IntuneWinAppUtil.exe: a batch file that writes <output folder>\Install.intunewin (arguments: -c <stage> -s Install.ps1 -o <out> -q).
    $dummyTool = Join-Path $work 'IntuneWinAppUtil.cmd'
    [IO.File]::WriteAllText($dummyTool, "@echo off`r`necho packed from %~2> `"%~6\Install.intunewin`"`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
    $failingTool = Join-Path $work 'IntuneWinAppUtilFail.cmd'
    [IO.File]::WriteAllText($failingTool, "@echo off`r`necho tool error 1>&2`r`nexit /b 3`r`n", [Text.Encoding]::ASCII)
    $unsignedTool = Join-Path $work 'IntuneWinAppUtil.exe'
    [IO.File]::WriteAllText($unsignedTool, 'not a program')

    # The real signature check of the tool (before it is replaced by a stub for the dummy).
    $realToolCheck = ${function:Assert-SelfXIntuneWinTool}
    Assert-Throws { & $realToolCheck -ToolPath $unsignedTool } 'IntuneWinAppUtil.exe without a Microsoft signature is refused'
    Assert-Throws { & $realToolCheck -ToolPath (Join-Path $work 'nothing.exe') } 'a missing IntuneWinAppUtil.exe is refused'
    function Assert-SelfXIntuneWinTool { param([string]$ToolPath) if (-not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) { throw "IntuneWinAppUtil.exe not found: $ToolPath" } }

    # The rule scripts need AppLocker and ConfigCI (Windows PowerShell 5.1 with the modules): here the call is recorded and a file written.
    $script:RuleCalls = New-Object System.Collections.Generic.List[object]
    $script:RuleFail = $false
    function Invoke-SelfXRuleScript {
        param([string]$Script, [string[]]$Arguments)
        if ($script:RuleFail) { throw 'rule script failed (test)' }
        $script:RuleCalls.Add([pscustomobject]@{ Script = (Split-Path -Leaf $Script); Arguments = $Arguments })
        $index = [array]::IndexOf($Arguments, '-OutputFile'); if ($index -ge 0) { [IO.File]::WriteAllText($Arguments[$index + 1], '<AppLockerPolicy />') }
        $index = [array]::IndexOf($Arguments, '-OutputFolder'); if ($index -ge 0) { New-Item -ItemType Directory -Path $Arguments[$index + 1] -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $Arguments[$index + 1] 'policy.xml'), '<SiPolicy />') }
    }

    $buildAnswers = [ordered]@{} ; foreach ($key in $answers.Keys) { if ($key -ne 'WizardLanguage') { $buildAnswers[$key] = $answers[$key] } }
    $buildAnswers.LogoPath = $logo
    $finalOut = Join-Path $work 'result\out'
    Initialize-WizardTexts -Folder $WizardFolder -Culture 'en'
    $steps = New-Object System.Collections.Generic.List[string]
    $result = Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $finalOut -ToolPath $dummyTool -Language 'en' -OnProgress { param($id, $text) $steps.Add("$id|$text") }
    $version = $result.Version
    Assert ($result.Mode -eq 'Hash' -and $result.PackageFile -eq "SelfX-Service-$version.intunewin") 'result: mode Hash, package file name from the version'
    foreach ($name in $result.PackageFile, $result.DetectionFile, 'selfx-answers.json', 'SelfX-Intune-Guide.en.txt', 'SelfX.AppLocker.xml') {
        Assert (Test-Path -LiteralPath (Join-Path $finalOut $name) -PathType Leaf) "result has $name"
    }
    Assert (Test-Path -LiteralPath (Join-Path $finalOut 'package\Install.ps1')) 'result has the configured package folder'
    Assert (-not (Test-Path -LiteralPath (Join-Path $finalOut 'AppControl'))) 'no App Control files without a base policy ID'
    Assert (@($steps | ForEach-Object { $_.Split('|')[0] }) -join ',' -eq 'check,copy,config,pack,detection,rules,guide,finish') 'progress steps in order (Hash mode: no signing steps)'
    Assert (@($steps | Where-Object { $_ -match '\[' }).Count -eq 0) 'every step has a text'
    Assert ((Get-TreeDigest -Folder $payload) -eq $payloadBefore) 'the payload folder is unchanged'
    Assert (@(Get-ChildItem -LiteralPath (Split-Path -Parent $finalOut) -Force | Where-Object { $_.Name -like '.selfx-*' }).Count -eq 0) 'no work folder is left'
    Assert (-not (Test-Path -LiteralPath (Join-Path $finalOut 'package\tools')) -and -not (Test-Path -LiteralPath (Join-Path $finalOut 'package\LICENSE.md'))) 'tools and licence texts are not part of the package'
    Assert ((Get-FileHash (Join-Path $finalOut 'package\App\SelfX.Code.json')).Hash -eq (Get-FileHash (Join-Path $payload 'App\SelfX.Code.json')).Hash) 'Hash mode: SelfX.Code.json is the one of the payload'
    $configList = Get-Content -LiteralPath (Join-Path $finalOut 'package\Config\SelfX.Config.json') -Raw | ConvertFrom-Json
    Assert ($null -ne $configList.Files.PSObject.Properties['Tool_Config.xml'] -and $null -ne $configList.Files.PSObject.Properties['Branding/logo.png']) 'SelfX.Config.json lists the configuration and the logo'
    $detection = Get-Content -LiteralPath (Join-Path $finalOut $result.DetectionFile) -Raw
    $expectedCode = Get-SelfXListDigest -Stage (Join-Path $finalOut 'package') -ListName 'SelfX.Code.json'
    $expectedConfig = Get-SelfXListDigest -Stage (Join-Path $finalOut 'package') -ListName 'SelfX.Config.json'
    Assert ($detection -match "ExpectedCodeHash = '$expectedCode'" -and $detection -match "ExpectedConfigHash = '$expectedConfig'" -and $detection -notmatch 'ExpectedCodeHash = ''__' -and $detection -notmatch 'ExpectedConfigHash = ''__') 'detection script has both digests instead of the placeholders'
    $errors = $null; [void][Management.Automation.Language.Parser]::ParseInput($detection, [ref]$null, [ref]$errors)
    Assert (@($errors).Count -eq 0) 'detection script parses'
    Assert ((Get-Content -LiteralPath (Join-Path $finalOut 'package\Detection.ps1') -Raw) -match "= '__SELFX_CODE_HASH__'") 'the Detection.ps1 in the package keeps the placeholders'
    Assert ((Get-Content -LiteralPath (Join-Path $finalOut $result.PackageFile) -Raw) -match 'packed from') 'the dummy tool was called with the package folder'
    $applocker = @($script:RuleCalls | Where-Object { $_.Script -eq 'New-SelfXAppLockerRules.ps1' })
    Assert ($applocker.Count -eq 1 -and $applocker[0].Arguments[$applocker[0].Arguments.IndexOf('-Mode') + 1] -eq 'Hash') 'AppLocker rules requested in the mode Hash'
    $pathList = $applocker[0].Arguments[$applocker[0].Arguments.IndexOf('-PathList') + 1]
    Assert ($pathList -match 'SelfXService\.exe' -and $pathList -match 'SelfXAudio\.dll' -and $pathList -notmatch 'Install\.ps1') 'AppLocker hash rules for the programs of Bin only'
    $guideText = Get-Content -LiteralPath (Join-Path $finalOut 'SelfX-Intune-Guide.en.txt') -Raw
    Assert ($guideText -match 'SelfX\.AppLocker\.xml' -and $guideText -match 'hash rules' -and $guideText -notmatch '-TrustedSigner') 'guide names the rule file and has no -TrustedSigner in the mode Hash'
    $answersJson = Get-Content -LiteralPath (Join-Path $finalOut 'selfx-answers.json') -Raw
    Assert ($answersJson -notmatch '(?i)password|pfx|secret|privatekey|thumbprint') 'selfx-answers.json has no password, key or certificate'
    $savedKeys = @((ConvertFrom-Json $answersJson).PSObject.Properties.Name)
    $allowedKeys = @((Get-WizardQuestions) | ForEach-Object { $_.Id }) + @('Units', 'WizardLanguage')
    Assert (@($savedKeys | Where-Object { $allowedKeys -notcontains $_ }).Count -eq 0) 'selfx-answers.json has only known answers'

    # Second run, same input, same output folder: SelfX.Code.json unchanged, the earlier result is replaced.
    $codeHashFirst = (Get-FileHash (Join-Path $finalOut 'package\App\SelfX.Code.json')).Hash
    $script:RuleCalls.Clear()
    $second = Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $finalOut -ToolPath $dummyTool -Language 'en'
    Assert ((Get-FileHash (Join-Path $finalOut 'package\App\SelfX.Code.json')).Hash -eq $codeHashFirst) 'second run with the same input: SelfX.Code.json is unchanged'
    Assert ($second.Version -eq $version -and (Test-Path -LiteralPath (Join-Path $finalOut $second.PackageFile))) 'second run replaced the output folder with a complete result'
    Assert (@(Get-ChildItem -LiteralPath (Split-Path -Parent $finalOut) -Force | Where-Object { $_.Name -like '.selfx-*' }).Count -eq 0) 'no old or work folder is left after the second run'

    # App Control only with a base policy ID.
    $withWdac = [ordered]@{} ; foreach ($key in $buildAnswers.Keys) { $withWdac[$key] = $buildAnswers[$key] }
    $withWdac.WdacBasePolicyId = '{12345678-1234-1234-1234-123456789ABC}'; $withWdac.AppLockerRules = $false
    $script:RuleCalls.Clear()
    $wdacOut = Join-Path $work 'result\wdac'
    $wdacResult = Invoke-SelfXPackageBuild -Answers $withWdac -PayloadFolder $payload -OutputFolder $wdacOut -ToolPath $dummyTool
    $wdac = @($script:RuleCalls | Where-Object { $_.Script -eq 'New-SelfXWdacPolicy.ps1' })
    Assert ($wdac.Count -eq 1 -and $script:RuleCalls.Count -eq 1) 'with a base policy ID and without AppLocker rules only the App Control script runs'
    Assert ($wdac[0].Arguments[$wdac[0].Arguments.IndexOf('-BasePolicyId') + 1] -eq '12345678-1234-1234-1234-123456789abc' -and $wdac[0].Arguments[$wdac[0].Arguments.IndexOf('-Level') + 1] -eq 'Hash') 'base policy ID is normalized, level Hash'
    Assert ((Test-Path -LiteralPath (Join-Path $wdacOut 'AppControl\policy.xml')) -and -not (Test-Path -LiteralPath (Join-Path $wdacOut 'SelfX.AppLocker.xml'))) 'App Control result in the output folder, no AppLocker file'
    $detectionArgument = $wdac[0].Arguments[$wdac[0].Arguments.IndexOf('-DetectionFile') + 1]
    Assert ($detectionArgument -like "$($work)*" -and $detectionArgument -like '*Detection.ps1') 'App Control scans the generated detection script'

    # ---- abort in the middle: no half-finished output, an earlier result stays
    $guideBefore = (Get-FileHash (Join-Path $finalOut 'SelfX-Intune-Guide.en.txt')).Hash
    $treeBefore = Get-TreeDigest -Folder $finalOut
    $newOut = Join-Path $work 'result\never'
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $newOut -ToolPath $failingTool } 'a failing IntuneWinAppUtil stops the run'
    Assert (-not (Test-Path -LiteralPath $newOut)) 'abort in the packing step: no output folder'
    $script:RuleFail = $true
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $newOut -ToolPath $dummyTool } 'a failing rule script stops the run (after packing)'
    Assert (-not (Test-Path -LiteralPath $newOut)) 'abort after packing: no output folder'
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $finalOut -ToolPath $dummyTool } 'a failing rule script stops a rerun'
    $script:RuleFail = $false
    Assert ((Get-TreeDigest -Folder $finalOut) -eq $treeBefore -and (Get-FileHash (Join-Path $finalOut 'SelfX-Intune-Guide.en.txt')).Hash -eq $guideBefore) 'abort of a rerun leaves the earlier result untouched'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $work 'result') -Force | Where-Object { $_.Name -like '.selfx-*' }).Count -eq 0) 'no work folder is left after the aborts'
    $badLogo = [ordered]@{} ; foreach ($key in $buildAnswers.Keys) { $badLogo[$key] = $buildAnswers[$key] }
    $badLogo.LogoPath = $fake
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $badLogo -PayloadFolder $payload -OutputFolder $newOut -ToolPath $dummyTool } 'a logo that is no image stops the run'
    Assert (-not (Test-Path -LiteralPath $newOut)) 'abort in the settings step: no output folder'

    # ---- input is checked before anything is written
    $withSecret = [ordered]@{} ; foreach ($key in $buildAnswers.Keys) { $withSecret[$key] = $buildAnswers[$key] }
    $withSecret.PfxPassword = 'x'
    $thrown = $null; try { Invoke-SelfXPackageBuild -Answers $withSecret -PayloadFolder $payload -OutputFolder $newOut -ToolPath $dummyTool } catch { $thrown = $_.Exception.Message }
    Assert ($thrown -like "Unknown answer 'PfxPassword'*" -and $thrown -notmatch 'x$') 'an answer with a password is refused as unknown (and not repeated)'
    $badMail = [ordered]@{} ; foreach ($key in $buildAnswers.Keys) { $badMail[$key] = $buildAnswers[$key] }
    $badMail.SupportMail = "a@example.com`nBcc: x@example.com"
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $badMail -PayloadFolder $payload -OutputFolder $newOut -ToolPath $dummyTool } 'an invalid answer stops the run'
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $newOut -ToolPath (Join-Path $work 'nothing.exe') } 'a missing tool stops the run'
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $newOut -ToolPath $dummyTool -TimestampServer 'https://timestamp.example' } 'a time stamp server without certificate is refused'
    $foreign = Join-Path $work 'result\foreign'
    New-Item -ItemType Directory -Path $foreign | Out-Null; [IO.File]::WriteAllText((Join-Path $foreign 'important.txt'), 'keep me')
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $foreign -ToolPath $dummyTool } 'a folder with foreign content is not used as output'
    Assert ((Get-Content -LiteralPath (Join-Path $foreign 'important.txt') -Raw) -eq 'keep me') 'the foreign content is untouched'
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder (Join-Path $payload 'out') -ToolPath $dummyTool } 'an output folder inside the payload is refused'
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder (Join-Path $payload 'App') -OutputFolder $newOut -ToolPath $dummyTool } 'a payload folder that is only a part is refused'

    # ---- changed or unexpected payload
    $changed = New-FakePayload -Folder (Join-Path $work 'changed')
    $appFile = @(Get-ChildItem (Join-Path $changed 'App') -Filter '*.ps1' | Select-Object -First 1)[0]
    Add-Content -LiteralPath $appFile.FullName -Value '# changed'
    $thrown = $null; try { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $changed -OutputFolder $newOut -ToolPath $dummyTool } catch { $thrown = $_.Exception.Message }
    Assert ($thrown -match 'does not match App\\SelfX\.Code\.json' -and $thrown -match [regex]::Escape($appFile.Name)) 'a changed code file is refused with its name'
    Assert (-not (Test-Path -LiteralPath $newOut)) 'a changed payload leaves no output'
    $extra = New-FakePayload -Folder (Join-Path $work 'extra')
    [IO.File]::WriteAllText((Join-Path $extra 'App\Extra.ps1'), 'Write-Host x')
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $extra -OutputFolder $newOut -ToolPath $dummyTool } 'an added code file is refused'
    $top = New-FakePayload -Folder (Join-Path $work 'top')
    [IO.File]::WriteAllText((Join-Path $top 'evil.ps1'), 'Write-Host x')
    $thrown = $null; try { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $top -OutputFolder $newOut -ToolPath $dummyTool } catch { $thrown = $_.Exception.Message }
    Assert ($thrown -match 'not part of SelfX') 'an unknown entry at the top of the payload is refused'
    $binChanged = New-FakePayload -Folder (Join-Path $work 'binchanged')
    [IO.File]::WriteAllText((Join-Path $binChanged 'Bin\SelfXService.exe'), 'replaced')
    $thrown = $null; try { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $binChanged -OutputFolder $newOut -ToolPath $dummyTool } catch { $thrown = $_.Exception.Message }
    Assert ($thrown -match 'SelfXService\.exe') 'a changed program in Bin is refused'
    $sourceChanged = New-FakePayload -Folder (Join-Path $work 'srcchanged')
    Add-Content -LiteralPath (Join-Path $sourceChanged 'Service\SelfXService.cs') -Value '// changed'
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $sourceChanged -OutputFolder $newOut -ToolPath $dummyTool } 'a changed source is refused'
    $oldLayout = New-FakePayload -Folder (Join-Path $work 'old')
    New-Item -ItemType Directory -Path (Join-Path $oldLayout 'Sources') | Out-Null
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $oldLayout -OutputFolder $newOut -ToolPath $dummyTool } 'the old layout (Sources) is refused'
    $signedAlready = New-FakePayload -Folder (Join-Path $work 'signed')
    [IO.File]::WriteAllText((Join-Path $signedAlready 'SelfX.Code.cat'), 'x')
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $signedAlready -OutputFolder $newOut -ToolPath $dummyTool } 'an already signed payload is refused'
    $noPlaceholder = New-FakePayload -Folder (Join-Path $work 'noph')
    $detectionPath = Join-Path $noPlaceholder 'Detection.ps1'
    [IO.File]::WriteAllText($detectionPath, ([IO.File]::ReadAllText($detectionPath).Replace("= '__SELFX_CODE_HASH__'", "= 'ABC'")))
    Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $noPlaceholder -OutputFolder $newOut -ToolPath $dummyTool } 'a Detection.ps1 without the placeholder is refused'
    Assert (-not (Test-Path -LiteralPath $newOut)) 'none of the refused payloads left an output folder'

    # ---- ConfigureOnly
    $configOnly = Join-Path $work 'result\configonly'
    $co = Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $configOnly -ConfigureOnly
    Assert ($null -eq $co.PackageFile -and (Test-Path (Join-Path $configOnly 'package\Config\SelfX.Config.json')) -and @(Get-ChildItem $configOnly -Filter '*.intunewin').Count -eq 0) '-ConfigureOnly: package folder only, no .intunewin, no tool needed'

    # ---- the guide with a signer
    Initialize-WizardTexts -Folder $WizardFolder -Culture 'en'
    $thumb = ('AB' * 20)
    $signedGuide = New-SelfXIntuneGuide -Answers @{ OrgName = 'Contoso'; Units = @() } -Version '3.1.0' -PackageFile 'p.intunewin' -DetectionFile 'd.ps1' -TrustedSigner @($thumb.ToLower()) -RuleFiles @('SelfX.AppLocker.xml', 'AppControl\')
    Assert ($signedGuide -match "Install\.ps1 -TrustedSigner $thumb" -and $signedGuide -match 'stay the same for every version' -and $signedGuide -match '-AllowHashMode') 'guide: -TrustedSigner with the thumbprint, publisher rules, way back'
    Assert-Throws { New-SelfXIntuneGuide -Answers @{ OrgName = 'C'; Units = @() } -Version '3.1.0' -PackageFile 'p' -DetectionFile 'd' -TrustedSigner @('1234; calc') } 'guide refuses a thumbprint that is not 40 hex characters'

    # ---------------------------------------------------------- trust mode Signature (real signatures; trusted test root needed)
    Write-Host 'Trust mode Signature'
    $root = Get-SelfXTestRootLocation
    if (-not $root.Allowed) {
        Write-Host '  SKIP no trusted test root allowed (GitHub Actions with administrator rights or SELFX_TEST_ALLOW_ROOT_IMPORT=1)'
    }
    else {
        $testCertificate = $null
        try {
            $testCertificate = New-SelfXTestCertificate -Name 'Wiz'
            Add-SelfXTestRoot -Certificate $testCertificate -Location $root.Location
            $realPayload = New-FakePayload -Folder (Join-Path $work 'real') -RealPrograms
            $signedOut = Join-Path $work 'result\signed'
            $steps.Clear()
            $script:RuleCalls.Clear()
            $signedResult = Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $realPayload -OutputFolder $signedOut -ToolPath $dummyTool -Certificate $testCertificate -OnProgress { param($id, $text) $steps.Add($id) }
            Assert ($signedResult.Mode -eq 'Signature' -and (@($steps) -join ',') -eq 'check,copy,config,sign,catalog,pack,detection,rules,guide,finish') 'signed run: mode Signature, steps in order'
            $signedPackage = Join-Path $signedOut 'package'
            $bad = @(Get-ChildItem $signedPackage -Recurse -File | Where-Object { '.exe', '.dll', '.ps1' -contains $_.Extension } | Where-Object { $s = Get-AuthenticodeSignature -LiteralPath $_.FullName; $s.Status -ne 'Valid' -or $s.SignerCertificate.Thumbprint -ne $testCertificate.Thumbprint })
            Assert ($bad.Count -eq 0) 'every program and script of the package has a valid signature of the certificate'
            $allowed = @($testCertificate.Thumbprint)
            Assert ((Test-SelfXSignedCatalog -Path (Join-Path $signedPackage 'Config') -CatalogFilePath (Join-Path $signedPackage 'Config\SelfX.Config.cat') -AllowedThumbprint $allowed).IsValid) 'Config\SelfX.Config.cat is valid and covers the folder Config'
            $codeCatalog = Get-Content -LiteralPath (Join-Path $signedPackage 'SelfX.Code.cat') -Raw -Encoding Byte
            Assert ($null -ne $codeCatalog -and (Get-AuthenticodeSignature -LiteralPath (Join-Path $signedPackage 'SelfX.Code.cat')).Status -eq 'Valid') 'SelfX.Code.cat is signed'
            $binaries = Get-Content -LiteralPath (Join-Path $signedPackage 'Bin\SelfX.Binaries.json') -Raw | ConvertFrom-Json
            Assert ($binaries.Binaries.'SelfXService.exe' -eq (Get-FileHash (Join-Path $signedPackage 'Bin\SelfXService.exe')).Hash) 'SelfX.Binaries.json has the hashes of the signed programs'
            $codeList = Get-Content -LiteralPath (Join-Path $signedPackage 'App\SelfX.Code.json') -Raw | ConvertFrom-Json
            Assert ($codeList.Files.'SelfXService.exe' -eq (Get-FileHash (Join-Path $signedPackage 'Bin\SelfXService.exe')).Hash) 'SelfX.Code.json lists the signed programs'
            $signedDetection = Get-AuthenticodeSignature -LiteralPath (Join-Path $signedOut $signedResult.DetectionFile)
            Assert ($signedDetection.Status -eq 'Valid' -and (Get-Content -LiteralPath (Join-Path $signedOut $signedResult.DetectionFile) -Raw) -match 'ExpectedCodeHash = ''[0-9A-F]{64}''') 'the detection script for Intune is signed and has the digests'
            Assert ((@($script:RuleCalls | ForEach-Object { $_.Arguments[$_.Arguments.IndexOf('-Mode') + 1] }) -join ',') -eq 'Publisher') 'AppLocker rules in the mode Publisher'
            Assert ((Get-Content -LiteralPath (Join-Path $signedOut 'SelfX-Intune-Guide.en.txt') -Raw) -match "-TrustedSigner $($testCertificate.Thumbprint)") 'the guide has the install command with -TrustedSigner'
            Assert ((Get-Content -LiteralPath (Join-Path $signedOut 'selfx-answers.json') -Raw) -notmatch $testCertificate.Thumbprint) 'selfx-answers.json does not name the certificate'
            Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $realPayload -OutputFolder (Join-Path $work 'result\cfgsign') -Certificate $testCertificate -ConfigureOnly } '-ConfigureOnly with a certificate is refused'
        }
        finally {
            if ($null -ne $testCertificate) { Remove-SelfXTestCertificate -Thumbprint $testCertificate.Thumbprint -Location $root.Location }
        }
    }

    # ---------------------------------------------------------- order of the signing steps (signing replaced by a recorder; runs everywhere)
    Write-Host 'Signing order (signing and catalogs replaced by a recorder)'
    $stubCertificate = $null
    try {
        $stubCertificate = New-SelfXTestCertificate -Name 'Ord'
        $script:SignedFiles = New-Object System.Collections.Generic.List[string]
        $script:CatalogCalls = New-Object System.Collections.Generic.List[object]
        function Set-SelfXCodeSignature {
            param([string[]]$Path, $Certificate, [string]$TimestampServer)
            $script:StampSeen = $TimestampServer
            foreach ($file in $Path) {
                $script:SignedFiles.Add($file)
                if ($file -like '*.ps1') { [IO.File]::AppendAllText($file, "`r`n# SIG # Begin signature block`r`n") } else { [IO.File]::AppendAllText($file, 'S') }
            }
        }
        function New-SelfXSignedCatalog {
            param([string]$Path, [string]$CatalogFilePath, $Certificate, [string]$TimestampServer)
            $names = @(Get-ChildItem -LiteralPath $Path -Recurse -File | ForEach-Object { $_.FullName.Substring($Path.TrimEnd('\').Length + 1) })
            $script:CatalogCalls.Add([pscustomobject]@{ Folder = (Split-Path -Leaf $Path); Names = $names; ConfigPresent = (Test-Path -LiteralPath (Join-Path $Path 'Config')); File = $CatalogFilePath; OutsideFolder = (-not $CatalogFilePath.StartsWith($Path.TrimEnd('\') + '\')) })
            [IO.File]::WriteAllText($CatalogFilePath, ($names -join "`n"))
        }
        $script:RuleCalls.Clear()
        $order = Join-Path $work 'result\order'
        $steps.Clear()
        $orderResult = Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $order -ToolPath $dummyTool -Certificate $stubCertificate -TimestampServer 'https://timestamp.example/ts' -OnProgress { param($id, $text) $steps.Add($id) }
        Assert ($orderResult.Mode -eq 'Signature' -and (@($steps) -join ',') -eq 'check,copy,config,sign,catalog,pack,detection,rules,guide,finish') 'signature mode: steps in order'
        $pkg = Join-Path $order 'package'
        Assert ($script:StampSeen -eq 'https://timestamp.example/ts') 'the time stamp server is passed on'
        $signedNames = @($script:SignedFiles | ForEach-Object { $_.Substring($_.IndexOf('\package\') + 9) -replace '^.*\\', '' })
        Assert (($signedNames -contains 'Install.ps1') -and ($signedNames -contains 'Detection.ps1') -and ($signedNames -contains 'Uninstall.ps1') -and ($signedNames -contains 'SelfXService.exe') -and ($signedNames -contains 'SelfXWinRT.dll') -and ($signedNames -contains 'SelfXAudio.dll')) 'every program, library and script of the package is signed'
        Assert (@($script:SignedFiles | Where-Object { $_ -match '\.(xml|json|png|cs|cat)$' }).Count -eq 0) 'no data file is signed (they are covered by the catalogs)'
        Assert (@($script:SignedFiles | Where-Object { $_ -like '*Detection.ps1' }).Count -eq 2) 'the Detection.ps1 of the package and the generated detection script are signed'
        $codeCatalog = @($script:CatalogCalls | Where-Object { $_.Folder -eq 'package' })
        $configCatalog = @($script:CatalogCalls | Where-Object { $_.Folder -eq 'Config' })
        Assert ($codeCatalog.Count -eq 1 -and $configCatalog.Count -eq 1 -and $script:CatalogCalls[0].Folder -eq 'package') 'one catalog of the package, then one of the folder Config'
        Assert ((-not $codeCatalog[0].ConfigPresent) -and @($codeCatalog[0].Names | Where-Object { $_ -like 'Config\*' }).Count -eq 0) 'SelfX.Code.cat is made without the folder Config'
        Assert ($codeCatalog[0].Names -contains 'App\SelfX.Code.json' -and $codeCatalog[0].Names -contains 'Bin\SelfX.Binaries.json' -and $codeCatalog[0].Names -contains 'Install.ps1' -and ($codeCatalog[0].Names | Where-Object { $_ -like 'Service\*.cs' })) 'SelfX.Code.cat covers the lists, the scripts and the sources'
        Assert ($codeCatalog[0].OutsideFolder -and $configCatalog[0].OutsideFolder) 'both catalogs are made outside the folder they cover'
        Assert ($configCatalog[0].Names -contains 'SelfX.Config.json' -and $configCatalog[0].Names -contains 'Tool_Config.xml' -and $configCatalog[0].Names -contains 'Branding\logo.png') 'SelfX.Config.cat covers SelfX.Config.json and the configuration'
        Assert ((Test-Path -LiteralPath (Join-Path $pkg 'SelfX.Code.cat')) -and (Test-Path -LiteralPath (Join-Path $pkg 'Config\SelfX.Config.cat')) -and (Test-Path -LiteralPath (Join-Path $pkg 'Config\Tool_Config.xml'))) 'the catalogs are in the package, Config is back in place'
        $binaries = Get-Content -LiteralPath (Join-Path $pkg 'Bin\SelfX.Binaries.json') -Raw | ConvertFrom-Json
        $codeList = Get-Content -LiteralPath (Join-Path $pkg 'App\SelfX.Code.json') -Raw | ConvertFrom-Json
        $hashOk = $true
        foreach ($property in $binaries.Binaries.PSObject.Properties) { if ($property.Value -ne (Get-FileHash -LiteralPath (Join-Path $pkg ('Bin\' + $property.Name.Replace('/', '\'))) -Algorithm SHA256).Hash) { $hashOk = $false } }
        Assert $hashOk 'SelfX.Binaries.json has the hashes of the signed programs'
        Assert ($codeList.Files.'SelfXService.exe' -eq (Get-FileHash -LiteralPath (Join-Path $pkg 'Bin\SelfXService.exe') -Algorithm SHA256).Hash -and $codeList.Files.'Uninstall.ps1' -eq (Get-FileHash -LiteralPath (Join-Path $pkg 'Uninstall.ps1') -Algorithm SHA256).Hash) 'SelfX.Code.json lists the signed files'
        Assert ($codeList.Files.'SelfXService.exe' -ne (Get-Content -LiteralPath (Join-Path $payload 'App\SelfX.Code.json') -Raw | ConvertFrom-Json).Files.'SelfXService.exe') 'SelfX.Code.json differs from the payload (new hashes)'
        $orderDetection = Get-Content -LiteralPath (Join-Path $order $orderResult.DetectionFile) -Raw
        Assert ($orderDetection -match 'ExpectedCodeHash = ''[0-9A-F]{64}''' -and ($orderDetection -split '# SIG # Begin signature block').Count -eq 2) 'the detection script has one signature block and the digests of the finished package'
        Assert ($orderDetection -match ("ExpectedCodeHash = '" + (Get-SelfXListDigest -Stage $pkg -ListName 'SelfX.Code.json') + "'")) 'the digest in the detection script is the one of the final SelfX.Code.json'
        $publisherCall = @($script:RuleCalls | Where-Object { $_.Script -eq 'New-SelfXAppLockerRules.ps1' })
        Assert ($publisherCall.Count -eq 1 -and $publisherCall[0].Arguments[$publisherCall[0].Arguments.IndexOf('-Mode') + 1] -eq 'Publisher' -and $publisherCall[0].Arguments[$publisherCall[0].Arguments.IndexOf('-PathList') + 1] -match 'Install\.ps1') 'AppLocker: mode Publisher with a program, a library and a script'
        Assert ($publisherCall[0].Arguments[$publisherCall[0].Arguments.IndexOf('-RuleNamePrefix') + 1] -eq 'SelfX') 'AppLocker: rule name without a version'
        $orderGuide = Get-Content -LiteralPath (Join-Path $order 'SelfX-Intune-Guide.en.txt') -Raw
        Assert ($orderGuide -match "Install\.ps1 -TrustedSigner $($stubCertificate.Thumbprint)") 'the guide has the install command with the thumbprint'
        Assert ((Get-Content -LiteralPath (Join-Path $order 'selfx-answers.json') -Raw) -notmatch $stubCertificate.Thumbprint) 'selfx-answers.json does not name the certificate'
        # Aborts in the signing steps leave nothing.
        $abortOut = Join-Path $work 'result\abort-sign'
        function New-SelfXSignedCatalog { param([string]$Path, [string]$CatalogFilePath, $Certificate, [string]$TimestampServer) throw 'catalog failed (test)' }
        Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $abortOut -ToolPath $dummyTool -Certificate $stubCertificate } 'a failing catalog stops the run'
        Assert (-not (Test-Path -LiteralPath $abortOut) -and @(Get-ChildItem -LiteralPath (Join-Path $work 'result') -Force | Where-Object { $_.Name -like '.selfx-*' }).Count -eq 0) 'abort while signing: no output and no work folder'
        Assert ((Get-TreeDigest -Folder $payload) -eq $payloadBefore) 'the payload is still unchanged after the signing runs'
        Assert-Throws { Invoke-SelfXPackageBuild -Answers $buildAnswers -PayloadFolder $payload -OutputFolder $abortOut -ToolPath $dummyTool -Certificate $stubCertificate -TimestampServer 'ftp://timestamp.example' } 'a time stamp server that is no http or https address is refused'
    }
    finally {
        if ($null -ne $stubCertificate) { Remove-SelfXTestCertificate -Thumbprint $stubCertificate.Thumbprint }
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failed) { Write-Host "$($script:Failed) test(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All wizard tests passed.' -ForegroundColor Green
exit 0
