<#
.SYNOPSIS
    Tests the package wizard (New-SelfXPackage.ps1, Wizard\SelfXWizard.ps1) without building a package.

.DESCRIPTION
    Isolated: works in a temporary folder, changes no repository file, sends nothing, needs no .NET SDK and no
    IntuneWinAppUtil.exe. Checks the language files, the validation of every kind of answer (including injection
    attempts), the patching of Tool_Config.xml and Ticket_Config.xml, the generated Intune scripts and the
    instructions, and the failure of invalid answer files. Works in Windows PowerShell 5.1 and PowerShell 7.

.NOTES
    Name    : Test-SelfXPackageWizard.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 1.0.0
    Exit code: 0 = all tests passed, 1 = at least one failed
#>
$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$WizardFolder = Join-Path $ScriptFolder 'Wizard'
. (Join-Path $WizardFolder 'SelfXWizard.ps1')
. (Join-Path $RepositoryRoot 'SelfX Service\Sources\TicketMail.ps1')
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
        $output = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptFolder 'New-SelfXPackage.ps1') -AnswerFile $file -OutputFolder $Folder -ConfigureOnly -Language de 2>&1
        return [pscustomobject]@{ Exit = $LASTEXITCODE; Output = ($output | Out-String) }
    }
    $out = Join-Path $work 'out'
    $run = Invoke-Wizard -Answers $answers -Folder $out
    Assert ($run.Exit -eq 0) ("wizard run exits with 0" + $(if ($run.Exit -ne 0) { ': ' + $run.Output }))
    $hashAfter = @((Get-FileHash $toolConfig).Hash, (Get-FileHash $ticketConfig).Hash)
    Assert (($hashBefore -join ',') -eq ($hashAfter -join ',')) 'repository files are unchanged'

    $cfg = New-Object Xml.XmlDocument; $cfg.XmlResolver = $null; $cfg.Load((Join-Path $out 'package\Sources\Tool_Config.xml'))
    $g = $cfg.GUI_Config
    Assert ($g.Tool_Language -eq 'Auto' -and $g.Support_Mail -eq 'it-support@contoso.example') 'Tool_Config: language and support mail'
    Assert ($g.Ticket_Enabled -eq 'True' -and $g.Ticket_Mail -eq 'servicedesk@contoso.example') 'Tool_Config: ticket on, default recipient'
    Assert ($g.Copilot_Enabled -eq 'True' -and $g.Copilot_Audience -eq 'User' -and $g.Copilot_Clear_Clipboard -eq 'True') 'Tool_Config: Copilot'
    Assert ($g.Wiki_Enabled -eq 'True' -and $g.Wiki_Url -eq 'https://wiki.contoso.example/start' -and $g.Wiki_Name -eq 'Contoso <Wiki>') 'Tool_Config: wiki button'
    Assert ($g.Shortcut_Desktop -eq 'False' -and $g.Shortcut_StartMenu -eq 'True') 'Tool_Config: shortcuts'
    Assert ($g.Brand_Accent_Color -eq '#E20074' -and $g.Brand_Logo -eq 'Branding\logo.png') 'Tool_Config: branding'
    Assert ((Test-Path (Join-Path $out 'package\Sources\Branding\logo.png')) -and -not (Test-Path (Join-Path $out 'package\Sources\Branding\company_logo.png'))) 'logo copied, placeholder removed'
    Assert ($g.Service_FileCheck -eq 'Enforce' -and $g.Service_Privileges -eq 'Restricted') 'secure defaults stay without expert mode'
    Assert (-not (Test-Path (Join-Path $out 'package\Service\Projects')) -and @(Get-ChildItem (Join-Path $out 'package') -Recurse -Filter 'Test-*.ps1').Count -eq 0) 'copy has no project files and no tests'

    $ticket = Read-SelfXTicketConfig -Path (Join-Path $out 'package\Sources\Ticket_Config.xml')
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
    $saved = Get-Content -LiteralPath (Join-Path $out 'selfx-answers.json') -Raw | ConvertFrom-Json
    Assert (@($saved.Units).Count -eq 2 -and $saved.OrgName -eq 'Contoso <&> Test') 'answers are saved'
    # Re-run with the saved file itself (round trip).
    $roundTrip = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptFolder 'New-SelfXPackage.ps1') -AnswerFile (Join-Path $out 'selfx-answers.json') -OutputFolder (Join-Path $work 'round') -ConfigureOnly 2>&1
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
    $cfgEvil = New-Object Xml.XmlDocument; $cfgEvil.XmlResolver = $null; $cfgEvil.Load((Join-Path $work 'evil2\package\Sources\Tool_Config.xml'))
    Assert ($cfgEvil.GUI_Config.Tool_Name -eq 'Self</Tool_Name><Evil/>X' -and $null -eq $cfgEvil.SelectSingleNode('//Evil')) 'Tool_Name with XML is stored as text'
    $ticketEvil = Read-SelfXTicketConfig -Path (Join-Path $work 'evil2\package\Sources\Ticket_Config.xml')
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
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failed) { Write-Host "$($script:Failed) test(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All wizard tests passed.' -ForegroundColor Green
exit 0
