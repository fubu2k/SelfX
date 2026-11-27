<#
.SYNOPSIS
    Functions of the SelfX package wizard (tools\New-SelfXPackage.ps1): texts, validation, patching of the settings
    files, generation of the ticket configuration, the Intune scripts and the instructions.

.NOTES
    Name    : SelfXWizard.ps1
    Package : tools
    Context : Build machine (administrator of the package; not installed, not shipped)
    Version : 3.1.3
    Works in Windows PowerShell 5.1 and PowerShell 7. The file only defines functions; it changes nothing when it is
    dot-sourced. Test-SelfXPackageWizard.ps1 tests it.

    Invoke-SelfXPackageBuild does everything of a package build in one run, without a question: it checks the payload, copies it,
    writes the settings and the logo, signs (optional), writes the file lists and catalogs, packs, writes the detection script, the
    AppLocker / App Control files, the scripts for Intune and the instructions. Progress goes to a callback (step id, text), an error
    is an exception with a plain text. The result appears in the output folder in one piece: an abort leaves no half-finished folder.
    The answers (the content of selfx-answers.json) never contain a password or a key; the certificate is a parameter of the function.

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Package layout App\Config, ASR step in the instructions
    3.1.1    2026-11-27  fubu2k               Invoke-SelfXPackageBuild (one-step build on the unpacked payload archive), logo check by file header,
                                              answers AppLockerRules and WdacBasePolicyId, -TrustedSigner in the instructions
    3.1.2    2026-11-27  fubu2k               Get-WizardBuildDefaults and Invoke-SelfXWizardBuild: default paths and the build of the repository
                                              package, shared by New-SelfXPackage.ps1 and the window SelfXWizardGui.ps1; Read-WizardLogo (the
                                              check of Copy-WizardLogo, also used by the logo preview of the window); several platform scripts
                                              are listed one per line in the instructions and in the result (they were joined into one line)
    3.1.3    2026-11-27  fubu2k               Instructions as steps with values to copy (Get-SelfXIntuneGuideSteps); trust mode Signature: events
                                              4006/4007, refused signature without Install.log, change of the certificate; -AdditionalSigner;
                                              Get-WizardCertificateInfo (certificate and revocation list addresses for the window)
    3.1.4    2026-11-27  fubu2k               -PackageKind (Full, FullSeparateConfig, ConfigOnly): the configuration package (Install.ps1, Detection.ps1, Config; MinCodeVersion;
                                              SelfX-Config-<version> names), the detection kind of the full package of a setup with a configuration
                                              package, and the instructions for both (Supersedence explained)
#>

$script:WizardFolder = $(if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path })
$script:WizardToolsFolder = Split-Path -Parent $script:WizardFolder
# File classes, file lists, payload and packaging functions; the signing library. Both only define functions.
. (Join-Path $script:WizardToolsFolder 'SelfXPackage.Common.ps1')
. (Join-Path $script:WizardToolsFolder 'SelfXSigning.ps1')

$script:WizardTexts = @{}
$script:WizardAnswerFile = $null
$script:WizardInteractive = $true

# The files of SelfX that the guide names for a per-rule exclusion of the Defender ASR rule for executable files (installed below
# %ProgramFiles%\SelfX\App). Exactly these four, no folder and no wildcard; docs\Installation.md lists the same files.
$script:SelfXAsrExclusionFiles = @(
    'C:\Program Files\SelfX\App\SelfXService.exe',
    'C:\Program Files\SelfX\App\SelfX.exe',
    'C:\Program Files\SelfX\App\WinRT\SelfXWinRT.dll',
    'C:\Program Files\SelfX\App\Audio\SelfXAudio.dll'
)

# ---------------------------------------------------------------- texts

function Get-WizardLanguages {
    param([string]$Folder)
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder -Filter 'Wizard.*.xml' -File)) {
        $doc = New-Object System.Xml.XmlDocument
        $doc.XmlResolver = $null
        $doc.Load($file.FullName)
        [pscustomobject]@{ Culture = $doc.DocumentElement.GetAttribute('Culture'); Name = $doc.DocumentElement.GetAttribute('Name'); Path = $file.FullName }
    }
}

function Read-WizardTextFile {
    param([string]$Path)
    $table = @{}
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    $doc.Load($Path)
    foreach ($node in @($doc.SelectNodes('/Wizard_Language/T'))) {
        $id = $node.GetAttribute('Id')
        if ($id) { $table[$id] = $node.InnerText }
    }
    return $table
}

# English is the base; the language file overrides it. Unknown cultures fall back to the neutral culture, then to English.
function Initialize-WizardTexts {
    param([string]$Folder, [string]$Culture = 'en')
    $texts = Read-WizardTextFile -Path (Join-Path $Folder 'Wizard.en.xml')
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Culture -match '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}$') {
        $candidates.Add($Culture)
        if ($Culture.Contains('-')) { $candidates.Add($Culture.Split('-')[0]) }
    }
    foreach ($name in $candidates) {
        $path = Join-Path $Folder "Wizard.$name.xml"
        if ($name -ne 'en' -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            foreach ($pair in (Read-WizardTextFile -Path $path).GetEnumerator()) { if ($pair.Value) { $texts[$pair.Key] = $pair.Value } }
            break
        }
    }
    $script:WizardTexts = $texts
}

function Get-WText {
    param([Parameter(Mandatory = $true)][string]$Id, [object[]]$Arguments = @())
    $text = $script:WizardTexts[$Id]
    if ($null -eq $text) { return "[$Id]" }
    if ($Arguments.Count -gt 0) { return ($text -f $Arguments) }
    return $text
}

# ---------------------------------------------------------------- validation

$script:WizardMaxLogoBytes = 2MB
$script:MailPattern = '^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,}\z'
$script:TagPattern = '^[A-Za-z0-9._ -]{1,64}\z'

function Test-WizardText {
    param([string]$Value, [int]$MaxLength)
    return ($Value.Length -le $MaxLength -and $Value -notmatch '[\x00-\x1F\x7F]')
}

# Returns the normalized value or throws a message that names the problem (without the value).
function ConvertTo-WizardValue {
    param([Parameter(Mandatory = $true)][string]$Kind, [AllowNull()][object]$Value, [string[]]$Choices = @(), [int]$Min = 0, [int]$Max = 0)
    $text = if ($null -eq $Value) { '' } else { ("$Value").Trim() }
    switch ($Kind) {
        'bool' {
            if ($Value -is [bool]) { return $Value }
            if ($text -match '^(j|ja|y|yes|true|1)$') { return $true }
            if ($text -match '^(n|nein|no|false|0)$') { return $false }
            throw 'yes or no'
        }
        'text' { if (-not (Test-WizardText $text $Max)) { throw "text up to $Max characters without control characters" }; return $text }
        'mail' {
            if ($text -eq '') { return '' }
            if ($text -notmatch $script:MailPattern) { throw 'one plain e-mail address' }
            return $text
        }
        'url' {
            if ($text -eq '') { return '' }
            $uri = $null
            if ($text.Length -gt 490 -or $text -notmatch '^https://[^\s<>"'']+\z' -or -not [Uri]::TryCreate($text, [UriKind]::Absolute, [ref]$uri) -or $uri.UserInfo) { throw 'an https:// address without user name' }
            return $text
        }
        'teams' {
            if ($text -eq '') { return '' }
            if ($text -match $script:MailPattern) { return $text }
            return (ConvertTo-WizardValue -Kind 'url' -Value $text)
        }
        'guid' {
            if ($text -eq '') { return '' }
            $guid = [guid]::Empty
            if (-not [guid]::TryParse($text, [ref]$guid) -or $guid -eq [guid]::Empty) { throw 'a GUID such as 12345678-1234-1234-1234-123456789abc' }
            return $guid.ToString('D')
        }
        'phone' { if ($text -ne '' -and $text -notmatch '^[0-9+()./ -]{3,30}\z') { throw 'digits and + ( ) . / - only'}; return $text }
        'color' { if ($text -ne '' -and $text -notmatch '^#[0-9A-Fa-f]{6}\z') { throw '#RRGGBB' }; return $text.ToUpperInvariant() }
        'culture' { if ($text -notmatch '^(Auto|[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2})\z') { throw 'a culture such as de, en, fr-CH or Auto' }; return $text }
        'tag' { if ($text -notmatch '^[A-Za-z0-9._-]{1,20}\z') { throw 'letters, digits . _ - up to 20 characters' }; return $text }
        'unitid' { if ($text -notmatch '^[A-Za-z0-9._-]{1,40}\z') { throw 'letters, digits . _ - up to 40 characters' }; return $text }
        'int' {
            $number = 0
            if (-not [int]::TryParse($text, [ref]$number) -or $number -lt $Min -or $number -gt $Max) { throw "a whole number from $Min to $Max" }
            return $number
        }
        'choice' {
            foreach ($choice in $Choices) { if ($choice -ieq $text) { return $choice } }
            throw ('one of: ' + ($Choices -join ', '))
        }
        'list' {
            # Comma separated list (or an array from an answer file) of group tags, OU names or device classes.
            $items = if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { @($Value | ForEach-Object { "$_".Trim() }) } else { @($text.Split(',') | ForEach-Object { $_.Trim() }) }
            $items = @($items | Where-Object { $_ })
            if ($items.Count -gt 100) { throw 'at most 100 entries' }
            foreach ($item in $items) { if (-not (Test-WizardText $item 150)) { throw 'entries up to 150 characters without control characters' } }
            return , $items
        }
    }
    throw "unknown kind $Kind"
}

function Test-WizardUnitValues {
    param([Parameter(Mandatory = $true)]$Unit)
    foreach ($tag in @($Unit.GroupTags)) { if ($tag -notmatch $script:TagPattern) { throw 'group tag: letters, digits, space . _ - up to 64 characters' } }
    foreach ($category in @($Unit.Categories)) { if ($category -notmatch $script:TagPattern) { throw 'device class: letters, digits, space . _ - up to 64 characters' } }
    foreach ($ou in @($Unit.OUs)) { if ($ou.Length -gt 250) { throw 'OU name: up to 250 characters' } }
}

# ---------------------------------------------------------------- settings files

# Replaces the text of the element <Name> in an XML text without touching comments and layout. The element must exist once.
function Set-XmlElementText {
    param([Parameter(Mandatory = $true)][string]$Xml, [Parameter(Mandatory = $true)][string]$Name, [AllowEmptyString()][string]$Value)
    $escaped = [System.Security.SecurityElement]::Escape($Value)
    $quoted = [regex]::Escape($Name)
    $found = [regex]::Matches($Xml, "<$quoted>[^<]*</$quoted>|<$quoted\s*/>")
    if ($found.Count -ne 1) { throw "The element $Name must exist exactly once (found $($found.Count))." }
    return $Xml.Substring(0, $found[0].Index) + "<$Name>$escaped</$Name>" + $Xml.Substring($found[0].Index + $found[0].Length)
}

function Read-WizardFileText {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    return [pscustomobject]@{ Text = [IO.File]::ReadAllText($Path); Bom = $bom }
}

function Write-WizardFileText {
    param([string]$Path, [string]$Text, [bool]$Bom)
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($Bom)))
}

function Set-SelfXToolConfigValues {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Values)
    $file = Read-WizardFileText -Path $Path
    $text = $file.Text
    foreach ($name in $Values.Keys) {
        $value = $Values[$name]
        if ($value -is [bool]) { $value = if ($value) { 'True' } else { 'False' } }
        $text = Set-XmlElementText -Xml $text -Name $name -Value "$value"
    }
    $check = New-Object System.Xml.XmlDocument
    $check.XmlResolver = $null
    $check.LoadXml($text)
    Write-WizardFileText -Path $Path -Text $text -Bom $file.Bom
}

# Rules: group tags first, then OUs, then device classes (the first match wins in SelfX).
function Get-SelfXTicketRuleList {
    param([object[]]$Units)
    $rules = New-Object System.Collections.Generic.List[object]
    foreach ($unit in $Units) { foreach ($tag in @($unit.GroupTags)) { $rules.Add([pscustomobject]@{ Source = 'GroupTag'; Attribute = 'Match'; Value = $tag; Unit = $unit.Id }) } }
    foreach ($unit in $Units) { foreach ($ou in @($unit.OUs)) { $rules.Add([pscustomobject]@{ Source = 'OU'; Attribute = 'Regex'; Value = [regex]::Escape($ou); Unit = $unit.Id }) } }
    foreach ($unit in $Units) { foreach ($category in @($unit.Categories)) { $rules.Add([pscustomobject]@{ Source = 'Category'; Attribute = 'Match'; Value = $category; Unit = $unit.Id }) } }
    return , $rules.ToArray()
}

function Set-SelfXTicketConfig {
    param([Parameter(Mandatory = $true)][string]$Path, [object[]]$Units = @())
    $file = Read-WizardFileText -Path $Path
    $esc = { param($s) [System.Security.SecurityElement]::Escape($s) }
    $unitLines = foreach ($unit in $Units) { "`t`t<Unit Id=`"$(& $esc $unit.Id)`" Mail=`"$(& $esc $unit.Mail)`" Cc=`"$(& $esc $unit.Cc)`" />" }
    $ruleLines = foreach ($rule in (Get-SelfXTicketRuleList -Units $Units)) { "`t`t<Rule Source=`"$($rule.Source)`" $($rule.Attribute)=`"$(& $esc $rule.Value)`" Unit=`"$(& $esc $rule.Unit)`" />" }
    $newline = if ($file.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $text = $file.Text
    foreach ($part in @(@('Units', $unitLines), @('Rules', $ruleLines))) {
        $pattern = "(?s)<$($part[0])>.*?</$($part[0])>"
        $found = [regex]::Matches($text, $pattern)
        # The first block in the comment header is an example; the real element is the last one.
        if ($found.Count -lt 1) { throw "The element $($part[0]) is missing in Ticket_Config.xml." }
        $last = $found[$found.Count - 1]
        $body = if (@($part[1]).Count) { $newline + (@($part[1]) -join $newline) + $newline + "`t" } else { $newline + "`t" }
        $replacement = "<$($part[0])>$body</$($part[0])>"
        $text = $text.Substring(0, $last.Index) + $replacement + $text.Substring($last.Index + $last.Length)
    }
    $check = New-Object System.Xml.XmlDocument
    $check.XmlResolver = $null
    $check.LoadXml($text)
    Write-WizardFileText -Path $Path -Text $text -Bom $file.Bom
}

# ---------------------------------------------------------------- Intune scripts and instructions

# Same script as in docs\Installation.md (Ticket-Zuordnung per Intune), with the values of one unit.
function New-SelfXSupportUnitScript {
    param([Parameter(Mandatory = $true)]$Unit, [string]$GroupTag = '', [string]$Category = '')
    $q = { param($s) "$s".Replace("'", "''") }
    $header = Get-WText 'guide.script.header' @($Unit.Id)
    $lines = @(
        "# $header",
        "# Intune platform script: run as SYSTEM (not as the signed-in user), 64-bit. Shared (functional) mailboxes only.",
        "`$GroupTag   = '$(& $q $GroupTag)'",
        "`$Category   = '$(& $q $Category)'",
        "`$TicketMail = '$(& $q $Unit.Mail)'",
        "`$TicketCc   = '$(& $q $Unit.Cc)'",
        "# An empty value removes the registry value. All four values are always set.",
        '',
        "`$ErrorActionPreference = 'Stop'",
        "`$key = 'HKLM:\SOFTWARE\SelfX\Support'",
        "`$tag = '^[A-Za-z0-9._ -]{1,64}\z'",
        "`$mail = '^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,}\z'",
        "`$values = [ordered]@{ GroupTag = @(`$GroupTag, `$tag); Category = @(`$Category, `$tag); TicketMail = @(`$TicketMail, `$mail); TicketCc = @(`$TicketCc, `$mail) }",
        'foreach ($name in $values.Keys) {',
        '    $value = ("$($values[$name][0])").Trim()',
        '    if ($value -and $value -notmatch $values[$name][1]) { Write-Output "$name has an invalid value."; exit 1 }',
        '}',
        'foreach ($name in $values.Keys) {',
        '    $value = ("$($values[$name][0])").Trim()',
        '    if ($value) {',
        '        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }',
        '        New-ItemProperty -LiteralPath $key -Name $name -Value $value -PropertyType String -Force | Out-Null',
        '    } elseif (Test-Path -LiteralPath $key) {',
        '        Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue',
        '    }',
        '}',
        "Write-Output 'SelfX support values set.'",
        'exit 0'
    )
    return ($lines -join "`r`n") + "`r`n"
}

# The requirement script of the guide (step 3) as its own value, so that the window can copy it.
$script:SelfXRequirementScript = "[int](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber)"

# The instructions for Intune as steps: every step has its lines and the values that the window offers to copy (install command, detection
# script, thumbprints ...). New-SelfXIntuneGuide joins the lines into the text file; both show the same text. OutputFolder (optional) makes
# the copy values of files full paths. TrustedSigner: the thumbprints of -TrustedSigner (trust mode Signature), at most 10 as Install.ps1 allows.
function Get-SelfXIntuneGuideSteps {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Answers,
        [Parameter(Mandatory = $true)][string]$Version,
        [AllowEmptyString()][string]$PackageFile = '',
        [AllowEmptyString()][string]$DetectionFile = '',
        [string[]]$ScriptFiles = @(),
        [string]$AnswersFile = '',
        [string[]]$TrustedSigner = @(),
        [string[]]$RuleFiles = @(),
        [string]$OutputFolder = '',
        [ValidateSet('Full', 'FullSeparateConfig', 'ConfigOnly')][string]$PackageKind = 'Full'
    )
    $ps = '%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File'
    # Trust mode Signature: the install command names the signers (SHA1 thumbprints, 40 hex characters, separated by commas without a space).
    $signers = @($TrustedSigner | Where-Object { $_ } | ForEach-Object { "$_".ToUpperInvariant() } | Select-Object -Unique)
    foreach ($signer in $signers) { if ($signer -notmatch '^[0-9A-F]{40}\z') { throw 'A thumbprint for -TrustedSigner is not valid.' } }
    if ($signers.Count -gt 10) { throw 'At most 10 thumbprints are allowed for -TrustedSigner.' }
    $installArguments = $(if ($signers.Count) { ' -TrustedSigner ' + ($signers -join ',') } else { '' })
    $installCommand = "$ps .\Install.ps1$installArguments"
    $uninstallCommand = "$ps .\Uninstall.ps1"
    $inOutput = { param([string]$name) if ($OutputFolder -and $name) { Join-Path $OutputFolder $name } else { $name } }
    $org = $Answers.OrgName
    $steps = New-Object System.Collections.Generic.List[object]
    $add = {
        param([string]$Id, [string[]]$Lines, [object[]]$Copies = @())
        $steps.Add([pscustomobject]@{ Id = $Id; Lines = @($Lines); Copies = @($Copies | Where-Object { $null -ne $_ -and $_.Value }) })
    }
    $copy = { param([string]$Label, [string]$Value) [pscustomobject]@{ Label = $Label; Value = $Value } }

    if ($PackageKind -eq 'ConfigOnly') {
        # The configuration package: Install.ps1 -ConfigOnly needs no trust parameters (the mode is the one of the device); the uninstall
        # command is a command that does nothing (Intune needs one); the full package removes SelfX.
        $configInstall = "$ps .\Install.ps1 -ConfigOnly"
        $noUninstall = '%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command exit 0'
        & $add 'app' @((Get-WText 'guide.c1' @($PackageFile, "SelfX Configuration - $org", $org))) @((& $copy 'gui.copy.name' "SelfX Configuration - $org"), (& $copy 'gui.copy.package' (& $inOutput $PackageFile)))
        & $add 'program' @((Get-WText 'guide.c2' @($configInstall)), (Get-WText 'guide.c2b' @($noUninstall)), (Get-WText 'guide.s2c')) @((& $copy 'gui.copy.install' $configInstall), (& $copy 'gui.copy.uninstall' $noUninstall))
        & $add 'requirements' @((Get-WText 'guide.c3')) @((& $copy 'gui.copy.requirement' $script:SelfXRequirementScript))
        & $add 'detection' @((Get-WText 'guide.c4' @($DetectionFile))) @((& $copy 'gui.copy.detection' (& $inOutput $DetectionFile)))
        & $add 'dependency' @((Get-WText 'guide.c5' @($Version)))
        & $add 'assignment' @((Get-WText 'guide.c6'))
        & $add 'supersedence' @((Get-WText 'guide.c7'), (Get-WText 'guide.c7a'), (Get-WText 'guide.c7b'))
        & $add 'test' @((Get-WText 'guide.c8'))
        $configFooter = @()
        if ($AnswersFile) { $configFooter = @((Get-WText 'guide.answers' @($AnswersFile))) }
        return [pscustomobject]@{
            Header = @((Get-WText 'guide.title' @($org, $Version)), ('=' * 72), (Get-WText 'guide.c.intro'))
            Steps  = $steps.ToArray()
            Footer = $configFooter
        }
    }

    & $add 'app' @((Get-WText 'guide.s1' @($PackageFile, "SelfX Service - $org", $org))) @((& $copy 'gui.copy.name' "SelfX Service - $org"), (& $copy 'gui.copy.package' (& $inOutput $PackageFile)))
    & $add 'program' @((Get-WText 'guide.s2' @($installCommand)), (Get-WText 'guide.s2b' @($uninstallCommand)), (Get-WText 'guide.s2c')) @((& $copy 'gui.copy.install' $installCommand), (& $copy 'gui.copy.uninstall' $uninstallCommand))
    & $add 'requirements' @((Get-WText 'guide.s3')) @((& $copy 'gui.copy.requirement' $script:SelfXRequirementScript))
    & $add 'detection' @((Get-WText 'guide.s4' @($DetectionFile))) @((& $copy 'gui.copy.detection' (& $inOutput $DetectionFile)))
    & $add 'dependency' @((Get-WText 'guide.s5'))
    & $add 'assignment' @((Get-WText 'guide.s6'))
    if ($ScriptFiles.Count -gt 0) {
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add((Get-WText 'guide.s7'))
        foreach ($unit in @($Answers.Units)) {
            $tags = if (@($unit.GroupTags).Count) { (@($unit.GroupTags) -join ', ') } else { '-' }
            $classes = if (@($unit.Categories).Count) { (@($unit.Categories) -join ', ') } else { '-' }
            $lines.Add((Get-WText 'guide.s7item' @($unit.Id, $tags, $classes)))
        }
        foreach ($file in $ScriptFiles) { $lines.Add("   - $file") }
        $lines.Add((Get-WText 'guide.s7tag'))
        & $add 'routing' $lines.ToArray() @((& $copy 'gui.copy.folder' $OutputFolder))
    }
    $step = if ($ScriptFiles.Count -gt 0) { 8 } else { 7 }
    if ($signers.Count) {
        & $add 'trust' @((Get-WText 'guide.trust' @($step)), (Get-WText 'guide.trust2'), (Get-WText 'guide.trust3'), (Get-WText 'guide.trust4')) @((& $copy 'gui.copy.thumbprints' ($signers -join ',')))
        $step++
        & $add 'certchange' @((Get-WText 'guide.certchange' @($step)), (Get-WText 'guide.certchange1'), (Get-WText 'guide.certchange2'), (Get-WText 'guide.certchange3'))
        $step++
    }
    if ($RuleFiles.Count -gt 0) {
        $lines = @((Get-WText $(if ($signers.Count) { 'guide.rules.signed' } else { 'guide.rules' }) @($step))) + @($RuleFiles | ForEach-Object { "   - $_" })
        & $add 'rules' $lines @((& $copy 'gui.copy.folder' $OutputFolder))
        $step++
    }
    $lines = @((Get-WText 'guide.asr' @($step)), (Get-WText 'guide.asr1'), (Get-WText 'guide.asr2')) + @($script:SelfXAsrExclusionFiles | ForEach-Object { "   - $_" }) + @((Get-WText 'guide.asr3'))
    & $add 'asr' $lines @((& $copy 'gui.copy.asr' ($script:SelfXAsrExclusionFiles -join "`r`n")))
    & $add 'test' @((Get-WText 'guide.s8' @($step + 1)))
    if ($PackageKind -eq 'FullSeparateConfig') { & $add 'separate' @((Get-WText 'guide.sep' @($step + 2)), (Get-WText 'guide.sep1')) }
    $footer = @()
    if ($AnswersFile) { $footer = @((Get-WText 'guide.update' @($AnswersFile)), (Get-WText 'guide.answers' @($AnswersFile))) }
    return [pscustomobject]@{
        Header = @((Get-WText 'guide.title' @($org, $Version)), ('=' * 72), (Get-WText 'guide.intro'))
        Steps  = $steps.ToArray()
        Footer = $footer
    }
}

# The instructions for Intune as text (the file SelfX-Intune-Guide.<language>.txt): the lines of Get-SelfXIntuneGuideSteps, one empty line
# after the header and after every step.
function New-SelfXIntuneGuide {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Answers,
        [Parameter(Mandatory = $true)][string]$Version,
        [AllowEmptyString()][string]$PackageFile = '',
        [AllowEmptyString()][string]$DetectionFile = '',
        [string[]]$ScriptFiles = @(),
        [string]$AnswersFile = '',
        [string[]]$TrustedSigner = @(),
        [string[]]$RuleFiles = @(),
        [ValidateSet('Full', 'FullSeparateConfig', 'ConfigOnly')][string]$PackageKind = 'Full'
    )
    $guide = Get-SelfXIntuneGuideSteps @PSBoundParameters
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $guide.Header) { $lines.Add($line) }
    $lines.Add('')
    foreach ($step in $guide.Steps) { foreach ($line in $step.Lines) { $lines.Add($line) }; $lines.Add('') }
    foreach ($line in $guide.Footer) { $lines.Add($line) }
    return ($lines -join "`r`n") + "`r`n"
}

# ---------------------------------------------------------------- questions

# Every question: Id (also the key in the answer file), Kind, Default (value or scriptblock of the answers so far),
# When (scriptblock: ask only if true), Required, Choices, Min, Max. Texts: <Id>.ask and <Id>.rec in the language file.
function Get-WizardQuestions {
    $q = New-Object System.Collections.Generic.List[hashtable]
    $add = { param([hashtable]$d) $q.Add($d) }
    & $add @{ Section = 'basics'; Id = 'ToolLanguage'; Kind = 'culture'; Default = 'Auto' }
    & $add @{ Id = 'ShowLanguageSetting'; Kind = 'bool'; Default = $true }
    & $add @{ Id = 'OrgName'; Kind = 'text'; Max = 60; Required = $true; Default = '' }
    & $add @{ Id = 'ToolName'; Kind = 'text'; Max = 40; Required = $true; Default = 'SelfX' }
    & $add @{ Section = 'support'; Id = 'SupportMail'; Kind = 'mail'; Default = '' }
    & $add @{ Id = 'SupportPhone'; Kind = 'phone'; Default = '' }
    & $add @{ Id = 'SupportHours'; Kind = 'text'; Max = 60; Default = '' }
    & $add @{ Id = 'SupportWebsite'; Kind = 'url'; Default = '' }
    & $add @{ Id = 'SupportTeams'; Kind = 'teams'; Default = '' }
    & $add @{ Section = 'branding'; Id = 'LogoPath'; Kind = 'text'; Max = 260; Default = '' }
    & $add @{ Id = 'AccentColor'; Kind = 'color'; Default = '' }
    & $add @{ Section = 'ticket'; Id = 'TicketEnabled'; Kind = 'bool'; Default = $false }
    & $add @{ Id = 'TicketMail'; Kind = 'mail'; Required = $true; When = { param($a) $a.TicketEnabled }; Default = { param($a) $a.SupportMail } }
    & $add @{ Id = 'TicketSubjectTag'; Kind = 'tag'; When = { param($a) $a.TicketEnabled }; Default = 'SelfX' }
    & $add @{ Id = 'MultiOrg'; Kind = 'bool'; When = { param($a) $a.TicketEnabled }; Default = $false }
    & $add @{ Id = 'HybridJoin'; Kind = 'bool'; When = { param($a) $a.TicketEnabled -and $a.MultiOrg }; Default = $false }
    & $add @{ Id = 'UseGroupTags'; Kind = 'bool'; When = { param($a) $a.TicketEnabled -and $a.MultiOrg }; Default = $true }
    & $add @{ Id = 'UseDeviceClass'; Kind = 'bool'; When = { param($a) $a.TicketEnabled -and $a.MultiOrg }; Default = $false }
    # The units are asked in a loop (see Read-WizardUnits).
    & $add @{ Section = 'copilot'; Id = 'CopilotEnabled'; Kind = 'bool'; Default = $false }
    & $add @{ Id = 'CopilotAudience'; Kind = 'choice'; Choices = @('User', 'Admin'); When = { param($a) $a.CopilotEnabled }; Default = 'User' }
    & $add @{ Id = 'CopilotClearClipboard'; Kind = 'bool'; When = { param($a) $a.CopilotEnabled }; Default = $true }
    & $add @{ Id = 'WikiEnabled'; Kind = 'bool'; Default = $false }
    & $add @{ Id = 'WikiUrl'; Kind = 'url'; Required = $true; When = { param($a) $a.WikiEnabled }; Default = '' }
    & $add @{ Id = 'WikiName'; Kind = 'text'; Max = 40; When = { param($a) $a.WikiEnabled }; Default = '' }
    & $add @{ Section = 'behavior'; Id = 'TrayIcon'; Kind = 'bool'; Default = $true }
    & $add @{ Id = 'ShortcutDesktop'; Kind = 'bool'; Default = $true }
    & $add @{ Id = 'ShortcutStartMenu'; Kind = 'bool'; Default = $true }
    & $add @{ Id = 'Expert'; Kind = 'bool'; Default = $false }
    & $add @{ Id = 'LogRetention'; Kind = 'int'; Min = 1; Max = 3650; When = { param($a) $a.Expert }; Default = 90 }
    & $add @{ Id = 'FileCheck'; Kind = 'choice'; Choices = @('Enforce', 'Audit'); When = { param($a) $a.Expert }; Default = 'Enforce' }
    & $add @{ Id = 'Privileges'; Kind = 'choice'; Choices = @('Restricted', 'Default'); When = { param($a) $a.Expert }; Default = 'Restricted' }
    & $add @{ Section = 'rules'; Id = 'AppLockerRules'; Kind = 'bool'; Default = $true }
    & $add @{ Id = 'WdacBasePolicyId'; Kind = 'guid'; Default = '' }
    return , $q.ToArray()
}

function Get-WizardUnitQuestions {
    param([hashtable]$Answers)
    $q = New-Object System.Collections.Generic.List[hashtable]
    $q.Add(@{ Id = 'UnitId'; Kind = 'unitid'; Required = $true; Default = '' })
    $q.Add(@{ Id = 'UnitMail'; Kind = 'mail'; Required = $true; Default = '' })
    $q.Add(@{ Id = 'UnitCc'; Kind = 'mail'; Default = '' })
    if ($Answers.UseGroupTags) { $q.Add(@{ Id = 'UnitGroupTags'; Kind = 'list'; Default = '' }) }
    if ($Answers.HybridJoin) { $q.Add(@{ Id = 'UnitOUs'; Kind = 'list'; Default = '' }) }
    if ($Answers.UseDeviceClass) { $q.Add(@{ Id = 'UnitCategories'; Kind = 'list'; Default = '' }) }
    return , $q.ToArray()
}

function Format-WizardValue {
    param($Value)
    if ($Value -is [bool]) { return $(if ($Value) { (Get-WText 'yes') } else { (Get-WText 'no') }) }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { return (@($Value) -join ', ') }
    return "$Value"
}

# Asks one question (interactive) or takes the value from the answer file. Returns the normalized value.
function Get-WizardAnswer {
    param([Parameter(Mandatory = $true)][hashtable]$Question, [hashtable]$Answers, [hashtable]$Source)
    $default = $Question.Default
    if ($default -is [scriptblock]) { $default = & $default $Answers }
    $choices = if ($Question.Choices) { [string[]]$Question.Choices } else { @() }
    $min = if ($Question.Min) { [int]$Question.Min } else { 0 }
    $max = if ($Question.Max) { [int]$Question.Max } else { 0 }
    if (-not $script:WizardInteractive) {
        if ($Source -and $Source.ContainsKey($Question.Id)) { $raw = $Source[$Question.Id] }
        else { $raw = $default }
        try { $value = ConvertTo-WizardValue -Kind $Question.Kind -Value $raw -Choices $choices -Min $min -Max $max }
        catch { throw "Answer '$($Question.Id)' is not valid: $($_.Exception.Message)" }
        if ($Question.Required -and ($null -eq $value -or "$value" -eq '')) { throw "Answer '$($Question.Id)' is required." }
        return , $value
    }
    Write-Host ''
    Write-Host (Get-WText "$($Question.Id).ask") -ForegroundColor White
    Write-Host ((Get-WText 'rec') + (Get-WText "$($Question.Id).rec")) -ForegroundColor DarkCyan
    if ($Question.Kind -eq 'bool') { Write-Host (Get-WText 'yesno') -ForegroundColor DarkGray }
    if ($choices.Count) { Write-Host ($choices -join ' / ') -ForegroundColor DarkGray }
    while ($true) {
        $shown = Format-WizardValue $default
        $answer = Read-Host $(if ($shown -ne '') { "[$shown]" } else { '[ ]' })
        $raw = if ($answer.Trim() -eq '') { $default } else { $answer }
        try {
            $value = ConvertTo-WizardValue -Kind $Question.Kind -Value $raw -Choices $choices -Min $min -Max $max
            if ($Question.Required -and ($null -eq $value -or "$value" -eq '')) { Write-Host (Get-WText 'required') -ForegroundColor Yellow; continue }
            return , $value
        } catch { Write-Host (Get-WText 'invalid' @($_.Exception.Message)) -ForegroundColor Yellow }
    }
}

# Units: a loop of "unit" questions. In an answer file the units are the array "Units".
function Read-WizardUnits {
    param([hashtable]$Answers, [hashtable]$Source)
    $units = New-Object System.Collections.Generic.List[object]
    if (-not $script:WizardInteractive) {
        foreach ($entry in @($Source.Units)) {
            if ($null -eq $entry) { continue }
            $table = @{}
            foreach ($property in $entry.PSObject.Properties) { $table[$property.Name] = $property.Value }
            $unit = @{}
            foreach ($question in (Get-WizardUnitQuestions -Answers $Answers)) { $unit[$question.Id] = (Get-WizardAnswer -Question $question -Answers $unit -Source $table) }
            $units.Add((New-WizardUnit $unit))
        }
    } else {
        $index = 1
        do {
            Write-Host ''
            Write-Host (Get-WText 'Unit.header' @($index)) -ForegroundColor Cyan
            $unit = @{}
            foreach ($question in (Get-WizardUnitQuestions -Answers $Answers)) {
                while ($true) {
                    $unit[$question.Id] = (Get-WizardAnswer -Question $question -Answers $unit -Source @{})
                    $candidate = New-WizardUnit $unit
                    try { Test-WizardUnitValues -Unit $candidate; break } catch { Write-Host (Get-WText 'invalid' @($_.Exception.Message)) -ForegroundColor Yellow }
                }
            }
            $units.Add((New-WizardUnit $unit))
            $index++
            $more = Get-WizardAnswer -Question @{ Id = 'UnitMore'; Kind = 'bool'; Default = ($index -le 1) } -Answers $Answers -Source @{}
        } while ($more)
    }
    $ids = @{}
    foreach ($unit in $units) {
        Test-WizardUnitValues -Unit $unit
        if ($ids.ContainsKey($unit.Id.ToLowerInvariant())) { throw "The unit '$($unit.Id)' is defined twice." }
        $ids[$unit.Id.ToLowerInvariant()] = $true
    }
    return , $units.ToArray()
}

function New-WizardUnit {
    param([hashtable]$Values)
    return [pscustomobject]@{
        Id         = [string]$Values.UnitId
        Mail       = [string]$Values.UnitMail
        Cc         = [string]$Values.UnitCc
        GroupTags  = @($Values.UnitGroupTags | Where-Object { $_ })
        OUs        = @($Values.UnitOUs | Where-Object { $_ })
        Categories = @($Values.UnitCategories | Where-Object { $_ })
    }
}

# Collects all answers. Source = hashtable from an answer file (non-interactive) or $null (interactive).
function Read-WizardAnswers {
    param([hashtable]$Source, [scriptblock]$SectionStart)
    $answers = @{}
    $section = $null
    foreach ($question in (Get-WizardQuestions)) {
        if ($question.Section -and $script:WizardInteractive) { Write-Host ''; Write-Host (Get-WText "section.$($question.Section)") -ForegroundColor Green }
        if ($question.When -and -not (& $question.When $answers)) { continue }
        $answers[$question.Id] = Get-WizardAnswer -Question $question -Answers $answers -Source $Source
        # The units follow the last ticket question.
        if ($question.Id -eq 'UseDeviceClass') { $answers.Units = Read-WizardUnits -Answers $answers -Source $Source }
    }
    if ($answers.TicketEnabled -and -not $answers.MultiOrg) { $answers.Units = @() }
    if (-not $answers.ContainsKey('Units')) { $answers.Units = @() }
    return $answers
}

# Settings of Tool_Config.xml that follow from the answers.
function Get-WizardToolConfigValues {
    param([hashtable]$A)
    $values = [ordered]@{
        Tool_Language               = $A.ToolLanguage
        Show_Language_Setting       = $A.ShowLanguageSetting
        Tool_Name                   = $A.ToolName
        Shortcut_Name               = $A.ToolName
        Shortcut_Desktop            = $A.ShortcutDesktop
        Shortcut_StartMenu          = $A.ShortcutStartMenu
        Show_Tray_Icon              = $A.TrayIcon
        Support_Mail                = $A.SupportMail
        Support_Phone_number        = $A.SupportPhone
        Support_Hours               = $A.SupportHours
        Support_Website             = $A.SupportWebsite
        Support_Teams               = $A.SupportTeams
        Ticket_Enabled              = [bool]$A.TicketEnabled
        Copilot_Enabled             = [bool]$A.CopilotEnabled
    }
    if ($A.TicketEnabled) { $values['Ticket_Mail'] = $A.TicketMail; $values['Ticket_Subject_Tag'] = $A.TicketSubjectTag }
    if ($A.CopilotEnabled) { $values['Copilot_Audience'] = $A.CopilotAudience; $values['Copilot_Clear_Clipboard'] = [bool]$A.CopilotClearClipboard }
    $values['Wiki_Enabled'] = [bool]$A.WikiEnabled
    if ($A.WikiEnabled) { $values['Wiki_Url'] = $A.WikiUrl; $values['Wiki_Name'] = $A.WikiName }
    if ($A.AccentColor) {
        $values['Brand_Accent_Color'] = $A.AccentColor
        $values['Brand_TitleBar_Color'] = $A.AccentColor
        $values['Brand_Run_Button_Color'] = ''
        $values['Brand_Info_Button_Color'] = ''
    }
    if ($A.Expert) {
        $values['Log_Retention_Days'] = $A.LogRetention
        $values['Service_FileCheck'] = $A.FileCheck
        $values['Service_Privileges'] = $A.Privileges
    }
    return $values
}

# Kind of an image by its first bytes (never by the extension alone): png, jpg or ico; $null for anything else.
function Get-WizardImageKind {
    param([byte[]]$Bytes)
    if ($Bytes.Length -ge 8 -and $Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47 -and $Bytes[4] -eq 0x0D -and $Bytes[5] -eq 0x0A -and $Bytes[6] -eq 0x1A -and $Bytes[7] -eq 0x0A) { return 'png' }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) { return 'jpg' }
    if ($Bytes.Length -ge 6 -and $Bytes[0] -eq 0 -and $Bytes[1] -eq 0 -and $Bytes[2] -eq 1 -and $Bytes[3] -eq 0 -and ($Bytes[4] -ne 0 -or $Bytes[5] -ne 0)) { return 'ico' }
    return $null
}

# Reads and checks a logo file once: a normal file of at most 2 MB, extension png, jpg, jpeg or ico, and the first bytes are a png, jpg or ico
# image of the same kind. Returns the bytes and the kind; throws a plain message otherwise. Used by Copy-WizardLogo and by the preview of the
# window (SelfXWizardGui.ps1), so both apply the same rules.
function Read-WizardLogo {
    param([Parameter(Mandatory = $true)][string]$LogoPath)
    $item = Get-Item -LiteralPath $LogoPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'The logo must be a normal file.' }
    if ($item.Extension -notmatch '^\.(png|jpg|jpeg|ico)$') { throw 'The logo must be png, jpg or ico.' }
    if ($item.Length -gt $script:WizardMaxLogoBytes) { throw 'The logo is larger than 2 MB.' }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -gt $script:WizardMaxLogoBytes) { throw 'The logo is larger than 2 MB.' }
    $kind = Get-WizardImageKind -Bytes $bytes
    if ($null -eq $kind) { throw 'The logo is not a png, jpg or ico image (the file header does not match).' }
    $extensionKind = $item.Extension.TrimStart('.').ToLowerInvariant().Replace('jpeg', 'jpg')
    if ($extensionKind -ne $kind) { throw "The logo has the extension $($item.Extension) but is a $kind image." }
    return [pscustomobject]@{ Bytes = $bytes; Kind = $kind }
}

# Copies the logo into <configuration folder>\Branding and returns the relative path for Brand_Logo (relative to the configuration
# folder: Branding\<name>, resolved by SelfXPaths.ps1 on the device). The file is read and checked once by Read-WizardLogo. The copy gets
# the name logo.<kind> from the checked bytes.
function Copy-WizardLogo {
    param([string]$LogoPath, [string]$SourcesFolder)
    $logo = Read-WizardLogo -LogoPath $LogoPath
    $folder = Join-Path $SourcesFolder 'Branding'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    foreach ($old in @(Get-ChildItem -LiteralPath $folder -File -Force)) { Remove-Item -LiteralPath $old.FullName -Force }
    $name = "logo.$($logo.Kind)"
    [IO.File]::WriteAllBytes((Join-Path $folder $name), $logo.Bytes)
    return "Branding\$name"
}

# The folder of the configuration files in a copy of the package: Config (package layout App/Config) or Sources (layout of the
# repository, sorted into App and Config by New-SelfXIntuneWin.ps1).
function Get-WizardConfigFolder {
    param([Parameter(Mandatory = $true)][string]$PackageFolder)
    $config = Join-Path $PackageFolder 'Config'
    if (Test-Path -LiteralPath $config -PathType Container) { return $config }
    $sources = Join-Path $PackageFolder 'Sources'
    if (Test-Path -LiteralPath $sources -PathType Container) { return $sources }
    throw 'The package has neither a folder Config nor a folder Sources.'
}

# Writes the answers into a copy of the package folder (Tool_Config.xml, Ticket_Config.xml, logo in Config or Sources).
function Set-WizardPackageConfiguration {
    param([Parameter(Mandatory = $true)][string]$PackageFolder, [Parameter(Mandatory = $true)][hashtable]$Answers)
    $sources = Get-WizardConfigFolder -PackageFolder $PackageFolder
    $values = Get-WizardToolConfigValues -A $Answers
    if ($Answers.LogoPath) { $values['Brand_Logo'] = Copy-WizardLogo -LogoPath $Answers.LogoPath -SourcesFolder $sources }
    else {
        $values['Brand_Logo'] = ''
        $placeholder = Join-Path $sources 'Branding\company_logo.png'
        if (Test-Path -LiteralPath $placeholder -PathType Leaf) { Remove-Item -LiteralPath $placeholder -Force }
    }
    Set-SelfXToolConfigValues -Path (Join-Path $sources 'Tool_Config.xml') -Values $values
    Set-SelfXTicketConfig -Path (Join-Path $sources 'Ticket_Config.xml') -Units @($Answers.Units)
}

function Get-WizardSummary {
    param([hashtable]$A)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($A.Keys | Where-Object { $_ -ne 'Units' } | Sort-Object)) { $lines.Add(('  {0,-22} {1}' -f $key, (Format-WizardValue $A[$key]))) }
    foreach ($unit in @($A.Units)) {
        $lines.Add(('  Unit {0}: {1} (Cc {2}); GroupTags: {3}; OUs: {4}; Classes: {5}' -f $unit.Id, $unit.Mail, $unit.Cc, (@($unit.GroupTags) -join ', '), (@($unit.OUs) -join ', '), (@($unit.Categories) -join ', ')))
    }
    return $lines.ToArray()
}

# ---------------------------------------------------------------- one-step package build

# Answers (hashtable of Read-WizardAnswers, or an object with the same properties) -> the Source of Read-WizardAnswers (the shape of
# selfx-answers.json). Units may have the properties Id/Mail/... (New-WizardUnit) or UnitId/UnitMail/... (answer file).
function ConvertTo-WizardAnswerSource {
    param([Parameter(Mandatory = $true)]$Answers)
    $source = @{}
    if ($Answers -is [System.Collections.IDictionary]) { foreach ($key in $Answers.Keys) { $source["$key"] = $Answers[$key] } }
    elseif ($Answers -is [psobject]) { foreach ($property in $Answers.PSObject.Properties) { $source[$property.Name] = $property.Value } }
    else { throw 'The answers must be a hashtable or an object.' }
    $get = { param($o, [string[]]$names) foreach ($n in $names) { if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] } } elseif ($null -ne $o.PSObject.Properties[$n]) { return $o.$n } } return $null }
    $units = New-Object System.Collections.Generic.List[object]
    foreach ($unit in @($source['Units'])) {
        if ($null -eq $unit) { continue }
        $units.Add([pscustomobject]@{
                UnitId         = (& $get $unit @('UnitId', 'Id'))
                UnitMail       = (& $get $unit @('UnitMail', 'Mail'))
                UnitCc         = (& $get $unit @('UnitCc', 'Cc'))
                UnitGroupTags  = (& $get $unit @('UnitGroupTags', 'GroupTags'))
                UnitOUs        = (& $get $unit @('UnitOUs', 'OUs'))
                UnitCategories = (& $get $unit @('UnitCategories', 'Categories'))
            })
    }
    $source['Units'] = $units.ToArray()
    return $source
}

# Checks all answers again like an answer file (every value normalized, unknown answers refused) and returns the normalized answers.
# There is no place for a password or a key: such a name is an unknown answer and stops the build.
function Test-WizardAnswerSet {
    param([Parameter(Mandatory = $true)]$Answers)
    $source = ConvertTo-WizardAnswerSource -Answers $Answers
    $known = @((Get-WizardQuestions) | ForEach-Object { $_.Id }) + @('Units', 'WizardLanguage')
    foreach ($key in $source.Keys) { if ($known -notcontains $key) { throw "Unknown answer '$key'. The answers contain no password and no key." } }
    $previous = $script:WizardInteractive
    $script:WizardInteractive = $false
    try { return (Read-WizardAnswers -Source $source) }
    finally { $script:WizardInteractive = $previous }
}

# Writes the answers (without any secret) as selfx-answers.json.
function Save-WizardAnswers {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][hashtable]$Answers, [string]$Language = 'en')
    $saved = [ordered]@{ WizardLanguage = $Language }
    foreach ($key in ($Answers.Keys | Where-Object { $_ -ne 'Units' } | Sort-Object)) { $saved[$key] = $Answers[$key] }
    $saved['Units'] = @($Answers.Units | ForEach-Object { [ordered]@{ UnitId = $_.Id; UnitMail = $_.Mail; UnitCc = $_.Cc; UnitGroupTags = @($_.GroupTags); UnitOUs = @($_.OUs); UnitCategories = @($_.Categories) } })
    [IO.File]::WriteAllText($Path, ($saved | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
}

# Writes the Intune platform scripts of the ticket routing into Folder and returns their file names.
function Write-SelfXSupportUnitScripts {
    param([Parameter(Mandatory = $true)][hashtable]$Answers, [Parameter(Mandatory = $true)][string]$Folder)
    $scriptFiles = New-Object System.Collections.Generic.List[string]
    $safe = { param($s) ("$s" -replace '[^A-Za-z0-9._-]', '_') }
    foreach ($unit in @($Answers.Units)) {
        $tags = @($unit.GroupTags); $classes = @($unit.Categories)
        $combos = New-Object System.Collections.Generic.List[object]
        if ($tags.Count -and $classes.Count) { foreach ($t in $tags) { foreach ($c in $classes) { $combos.Add(@($t, $c)) } } }
        elseif ($tags.Count) { foreach ($t in $tags) { $combos.Add(@($t, '')) } }
        elseif ($classes.Count) { foreach ($c in $classes) { $combos.Add(@('', $c)) } }
        # Units that are matched by OU only need no script: the rules of Ticket_Config.xml route them.
        if ($combos.Count -gt 50) { throw "The unit '$($unit.Id)' needs more than 50 scripts. Reduce the group tags or device classes." }
        foreach ($combo in $combos) {
            $name = 'Set-SelfXSupportUnit-' + (& $safe $unit.Id)
            if ($combo[0]) { $name += '-' + (& $safe $combo[0]) }
            if ($combo[1]) { $name += '-' + (& $safe $combo[1]) }
            [IO.File]::WriteAllText((Join-Path $Folder ($name + '.ps1')), (New-SelfXSupportUnitScript -Unit $unit -GroupTag $combo[0] -Category $combo[1]), (New-Object System.Text.UTF8Encoding($false)))
            $scriptFiles.Add($name + '.ps1')
        }
    }
    return , $scriptFiles.ToArray()
}

# Runs one of the rule scripts (New-SelfXAppLockerRules.ps1, New-SelfXWdacPolicy.ps1) in Windows PowerShell 5.1 (AppLocker and ConfigCI exist
# only there) as a child process. Every value is its own argument (no command line is built from text). Throws with the end of the output
# when the script fails. Tests replace this function.
function Invoke-SelfXRuleScript {
    param([Parameter(Mandatory = $true)][string]$Script, [Parameter(Mandatory = $true)][string[]]$Arguments)
    $windowsPowerShell = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) { throw 'Windows PowerShell 5.1 was not found (needed for the AppLocker and App Control rules).' }
    $output = @(& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw "$(Split-Path -Leaf $Script) failed (exit code $LASTEXITCODE): $((@($output | Select-Object -Last 4)) -join ' / ')" }
}

# After signing the programs in Bin the hashes in Bin\SelfX.Binaries.json must be the signed ones (Install.ps1 compares them).
function Update-SelfXBinariesManifest {
    param([Parameter(Mandatory = $true)][string]$Package)
    $path = Join-Path $Package 'Bin\SelfX.Binaries.json'
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $binaries = [ordered]@{}
    foreach ($property in @($manifest.Binaries.PSObject.Properties)) {
        $file = Join-Path (Join-Path $Package 'Bin') $property.Name.Replace('/', '\')
        $binaries[$property.Name] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    $result = [ordered]@{}
    foreach ($property in @($manifest.PSObject.Properties)) {
        if ($property.Name -eq 'Binaries') { $result['Binaries'] = $binaries }
        elseif ($property.Name -eq 'Sources') { $sources = [ordered]@{}; foreach ($source in @($property.Value.PSObject.Properties)) { $sources[$source.Name] = $source.Value }; $result['Sources'] = $sources }
        else { $result[$property.Name] = $property.Value }
    }
    [IO.File]::WriteAllText($path, ($result | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
}

function Test-WizardOutputFolder {
    # The output folder is new, empty or the result of an earlier run (it then has selfx-answers.json or a folder package); anything else
    # is not touched. It must not be inside the payload and must not contain it.
    param([Parameter(Mandatory = $true)][string]$OutputFolder, [Parameter(Mandatory = $true)][string]$PayloadFolder)
    $out = [IO.Path]::GetFullPath($OutputFolder).TrimEnd('\', '/')
    $payload = [IO.Path]::GetFullPath($PayloadFolder).TrimEnd('\', '/')
    if ([IO.Path]::GetPathRoot($out + '\') -eq ($out + '\')) { throw 'The output folder must not be the root of a drive.' }
    if ($out -ieq $payload -or $out.StartsWith($payload + '\', [StringComparison]::OrdinalIgnoreCase) -or $payload.StartsWith($out + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The output folder and the payload folder must not contain each other.'
    }
    if (Test-Path -LiteralPath $out) {
        $item = Get-Item -LiteralPath $out -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'The output path is not a normal folder.' }
        $entries = @(Get-ChildItem -LiteralPath $out -Force)
        if ($entries.Count -gt 0 -and -not (@($entries | Where-Object { $_.Name -ieq 'selfx-answers.json' -or ($_.Name -ieq 'package' -and $_.PSIsContainer) }).Count)) {
            throw 'The output folder is not empty and holds no earlier SelfX result. Use an empty folder.'
        }
    }
    return $out
}

function Invoke-SelfXPackageBuild {
    <#
    .SYNOPSIS
        Builds the configured Intune package in one run, without a question.

    .DESCRIPTION
        Order: check the answers, the tool and the certificate; copy the package part of the unpacked payload; check the copy against
        App\SelfX.Code.json; write the settings and the logo; trust mode Signature (with -Certificate): sign every program and script,
        rewrite Bin\SelfX.Binaries.json and App\SelfX.Code.json, write SelfX.Code.cat from the package without Config; then
        Config\SelfX.Config.json (and in the mode Signature Config\SelfX.Config.cat); pack with IntuneWinAppUtil.exe (Microsoft signature
        checked); write Detection.ps1 with the digests (signed in the mode Signature); AppLocker and App Control files for the mode;
        platform scripts, instructions and selfx-answers.json.

        -PackageKind: Full (default), FullSeparateConfig (the full package for a setup with a separate configuration package: its
        detection script does not compare the configuration) or ConfigOnly (the configuration package: Install.ps1, Detection.ps1 and
        Config; Install.ps1 -ConfigOnly; no programs, no AppLocker or App Control files; the file list names MinCodeVersion).

        Everything is built in a work folder next to the output folder. Only when every step worked, the result replaces the output
        folder; an error leaves no half-finished output (an earlier result stays as it was). Errors are exceptions with a plain text.
        The caller disposes -Certificate; the function never reads, stores or logs a password.

        Progress: -OnProgress is called as & $OnProgress <step id> <text>. Step ids: check, copy, config, sign, catalog, pack,
        detection, rules, guide, finish.

        -AdditionalSigner: SHA1 thumbprints of further signers that the devices shall accept besides the certificate (change of the
        certificate: the new one is announced before the first package signed with it). They only go into -TrustedSigner of the install
        command; nothing is signed with them. At most 9 (Install.ps1 accepts 10 thumbprints). Needs -Certificate.

    .OUTPUTS
        An object with OutputFolder, Version, Mode (Hash or Signature), PackageFile, DetectionFile, RuleFiles, ScriptFiles, GuideFile, GuideText,
        TrustedSigner (the thumbprints of the install command) and GuideSteps (Get-SelfXIntuneGuideSteps: the same instructions as steps with
        the values to copy).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Answers,
        [Parameter(Mandatory = $true)][string]$PayloadFolder,
        [Parameter(Mandatory = $true)][string]$OutputFolder,
        [string]$ToolPath,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$TimestampServer,
        [string[]]$AdditionalSigner = @(),
        [scriptblock]$OnProgress,
        [string]$Language = 'en',
        [switch]$ConfigureOnly,
        [ValidateSet('Full', 'FullSeparateConfig', 'ConfigOnly')][string]$PackageKind = 'Full'
    )
    $configPackage = ($PackageKind -eq 'ConfigOnly')
    $progress = { param([string]$id) if ($null -ne $OnProgress) { & $OnProgress $id (Get-WText "step.$id") } }
    $signed = ($null -ne $Certificate)
    $additional = @($AdditionalSigner | Where-Object { "$_".Trim() })

    # ---- input, before anything is written
    & $progress 'check'
    $a = Test-WizardAnswerSet -Answers $Answers
    if ($ConfigureOnly -and $signed) { throw 'A package that is only configured is not signed: do not combine -ConfigureOnly with a certificate.' }
    if ($TimestampServer -and -not $signed) { throw 'A time stamp server needs a certificate.' }
    if (-not $ConfigureOnly) { Assert-SelfXIntuneWinTool -ToolPath $ToolPath }
    if ($signed) {
        $problem = Get-SelfXSigningCertificateProblem $Certificate
        if ($null -ne $problem) { throw "The certificate cannot be used for code signing: $problem." }
        if ($TimestampServer -and -not (Test-SelfXTimestampUrl $TimestampServer)) { throw 'The time stamp server must be an absolute http or https address without user information.' }
    }
    # The signers of the install command: the certificate first, then the additional ones (normalized, duplicates removed, at most 10).
    if ($additional.Count -and -not $signed) { throw 'Additional signers need a certificate (trust mode Signature).' }
    $trustedSigners = @()
    if ($signed) {
        # ConvertTo-SelfXThumbprintList returns one array (return , ...): not wrapped in @() again.
        $trustedSigners = [string[]](ConvertTo-SelfXThumbprintList -Thumbprint (@($Certificate.Thumbprint) + $additional))
        if ($trustedSigners.Count -gt 10) { throw 'At most 9 additional signers are allowed (Install.ps1 accepts 10 thumbprints).' }
    }
    $final = Test-WizardOutputFolder -OutputFolder $OutputFolder -PayloadFolder $PayloadFolder
    $parent = Split-Path -Parent $final
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    $work = Join-Path $parent ('.selfx-build-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
    $out = Join-Path $work 'out'
    $tmp = Join-Path $work 'tmp'
    $backup = $null
    try {
        New-Item -ItemType Directory -Path $out, $tmp -Force | Out-Null
        $package = Join-Path $out 'package'

        # ---- copy and check
        & $progress 'copy'
        Copy-SelfXPayloadPackage -PayloadFolder $PayloadFolder -Target $package
        $payload = Test-SelfXPayloadFolder -Package $package
        $version = $payload.Version

        # ---- settings and logo
        & $progress 'config'
        Set-WizardPackageConfiguration -PackageFolder $package -Answers $a
        if ($configPackage) { Convert-SelfXPackageToConfigOnly -Stage $package }

        # The detection script is made from the unsigned file with the lists of the finished package (a signature block is not copied).
        $detectStage = Join-Path $tmp 'detect'
        New-Item -ItemType Directory -Path (Join-Path $detectStage 'App'), (Join-Path $detectStage 'Config') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $package 'Detection.ps1') -Destination (Join-Path $detectStage 'Detection.ps1')

        if ($signed) {
            & $progress 'sign'
            $types = @('.exe', '.dll', '.ps1', '.psm1', '.psd1')
            $files = @(Get-ChildItem -LiteralPath $package -Recurse -File -Force | Where-Object { $types -contains $_.Extension.ToLowerInvariant() } | ForEach-Object { $_.FullName })
            $signArguments = @{ Path = $files; Certificate = $Certificate }
            if ($TimestampServer) { $signArguments.TimestampServer = $TimestampServer }
            $null = Set-SelfXCodeSignature @signArguments
            if (-not $configPackage) {
                Update-SelfXBinariesManifest -Package $package
                $null = New-SelfXCodeManifest -Stage $package -Version $version

                # SelfX.Code.cat covers everything outside Config: Config is set aside while the catalog is made, and the catalog must lie outside
                # the folder it covers until it is moved in.
                & $progress 'catalog'
                $held = Join-Path $tmp 'config-held'
                Move-Item -LiteralPath (Join-Path $package 'Config') -Destination $held
                try {
                    $catalogArguments = @{ Path = $package; CatalogFilePath = (Join-Path $tmp 'SelfX.Code.cat'); Certificate = $Certificate }
                    if ($TimestampServer) { $catalogArguments.TimestampServer = $TimestampServer }
                    $null = New-SelfXSignedCatalog @catalogArguments
                }
                finally { Move-Item -LiteralPath $held -Destination (Join-Path $package 'Config') }
                Move-Item -LiteralPath (Join-Path $tmp 'SelfX.Code.cat') -Destination (Join-Path $package 'SelfX.Code.cat')
            }
        }

        # The configuration package names the code version it is made for (the version of the payload).
        if ($configPackage) { $null = New-SelfXConfigManifest -Stage $package -MinCodeVersion $version }
        else { $null = New-SelfXConfigManifest -Stage $package }
        if ($signed) {
            $configCatalogArguments = @{ Path = (Join-Path $package 'Config'); CatalogFilePath = (Join-Path $tmp 'SelfX.Config.cat'); Certificate = $Certificate }
            if ($TimestampServer) { $configCatalogArguments.TimestampServer = $TimestampServer }
            $null = New-SelfXSignedCatalog @configCatalogArguments
            Move-Item -LiteralPath (Join-Path $tmp 'SelfX.Config.cat') -Destination (Join-Path $package 'Config\SelfX.Config.cat')
        }

        # The names are also named in the instructions of a package that is only configured.
        $namePrefix = $(if ($configPackage) { 'SelfX-Config' } else { 'SelfX-Service' })
        $packageName = "$namePrefix-$version.intunewin"
        $detectionName = "$namePrefix-$version.Detection.ps1"
        $packageFile = $null
        $detectionFile = $null
        $ruleFiles = New-Object System.Collections.Generic.List[string]
        if (-not $ConfigureOnly) {
            # ---- pack
            & $progress 'pack'
            $packageFile = $packageName
            $toolOutput = Join-Path $tmp 'tool'
            New-Item -ItemType Directory -Path $toolOutput -Force | Out-Null
            New-SelfXIntuneWinFile -ToolPath $ToolPath -Stage $package -SetupFile 'Install.ps1' -OutputDir $toolOutput -Target (Join-Path $out $packageFile)

            # ---- detection script with the digests
            & $progress 'detection'
            $detectionFile = $detectionName
            if (-not $configPackage) { Copy-Item -LiteralPath (Get-SelfXListPath -Stage $package -ListName 'SelfX.Code.json') -Destination (Get-SelfXListPath -Stage $detectStage -ListName 'SelfX.Code.json') }
            Copy-Item -LiteralPath (Get-SelfXListPath -Stage $package -ListName 'SelfX.Config.json') -Destination (Get-SelfXListPath -Stage $detectStage -ListName 'SelfX.Config.json')
            $detectionKind = $(if ($configPackage) { 'ConfigOnly' } elseif ($PackageKind -eq 'FullSeparateConfig') { 'FullWithoutConfig' } else { 'Full' })
            $null = New-SelfXDetectionScript -Stage $detectStage -Target (Join-Path $out $detectionFile) -Kind $detectionKind
            if ($signed) {
                $detectSign = @{ Path = @((Join-Path $out $detectionFile)); Certificate = $Certificate }
                if ($TimestampServer) { $detectSign.TimestampServer = $TimestampServer }
                $null = Set-SelfXCodeSignature @detectSign
            }

            # ---- AppLocker and App Control files for the mode
            & $progress 'rules'
            $mode = $(if ($signed) { 'Publisher' } else { 'Hash' })
            if ($a.AppLockerRules -and -not $configPackage) {
                $programs = @(((Get-Content -LiteralPath (Join-Path $package 'Bin\SelfX.Binaries.json') -Raw | ConvertFrom-Json).Binaries.PSObject.Properties) | ForEach-Object { Join-Path $package ('Bin\' + $_.Name.Replace('/', '\')) })
                if ($signed) { $programs += (Join-Path $package 'Install.ps1') }
                if ($programs | Where-Object { $_ -match '\|' }) { throw 'A file name contains the character |.' }
                Invoke-SelfXRuleScript -Script (Join-Path $script:WizardToolsFolder 'New-SelfXAppLockerRules.ps1') -Arguments @(
                    '-PathList', ($programs -join '|'), '-OutputFile', (Join-Path $out 'SelfX.AppLocker.xml'), '-RuleNamePrefix', $(if ($signed) { 'SelfX' } else { "SelfX $version" }), '-Mode', $mode)
                $ruleFiles.Add('SelfX.AppLocker.xml')
            }
            if ($a.WdacBasePolicyId -and -not $configPackage) {
                Invoke-SelfXRuleScript -Script (Join-Path $script:WizardToolsFolder 'New-SelfXWdacPolicy.ps1') -Arguments @(
                    '-BasePolicyId', $a.WdacBasePolicyId, '-Level', $mode, '-PackageFolder', $package, '-DetectionFile', (Join-Path $out $detectionFile), '-OutputFolder', (Join-Path $out 'AppControl'))
                $ruleFiles.Add('AppControl\')
            }
        }

        # ---- platform scripts, answers, instructions
        & $progress 'guide'
        # The function returns one array (return , ...); @() around it would nest it and join the names into one line of the instructions.
        $scriptFiles = [string[]](Write-SelfXSupportUnitScripts -Answers $a -Folder $out)
        Save-WizardAnswers -Path (Join-Path $out 'selfx-answers.json') -Answers $a -Language $Language
        $available = @(Get-WizardLanguages -Folder $script:WizardFolder | ForEach-Object { $_.Culture })
        $guideLanguage = $(if ($available -contains $Language) { $Language } elseif ($Language.Contains('-') -and $available -contains $Language.Split('-')[0]) { $Language.Split('-')[0] } else { 'en' })
        $guideArguments = @{ Answers = $a; Version = $version; PackageFile = $packageName; DetectionFile = $detectionName; ScriptFiles = $scriptFiles
            AnswersFile = 'selfx-answers.json'; TrustedSigner = $trustedSigners; RuleFiles = @($ruleFiles); PackageKind = $PackageKind }
        $guideText = New-SelfXIntuneGuide @guideArguments
        $guideSteps = Get-SelfXIntuneGuideSteps @guideArguments -OutputFolder $final
        $guideFile = "SelfX-Intune-Guide.$guideLanguage.txt"
        [IO.File]::WriteAllText((Join-Path $out $guideFile), $guideText, (New-Object System.Text.UTF8Encoding($true)))

        # ---- the result replaces the output folder in one move
        & $progress 'finish'
        if (Test-Path -LiteralPath $final) {
            $backup = Join-Path $parent ('.selfx-old-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
            Move-Item -LiteralPath $final -Destination $backup
        }
        try { Move-Item -LiteralPath $out -Destination $final }
        catch {
            if ($null -ne $backup -and (Test-Path -LiteralPath $backup)) { Move-Item -LiteralPath $backup -Destination $final; $backup = $null }
            throw
        }
        return [pscustomobject]@{
            OutputFolder  = $final
            Version       = $version
            Mode          = $(if ($signed) { 'Signature' } else { 'Hash' })
            PackageKind   = $PackageKind
            PackageFile   = $packageFile
            DetectionFile = $detectionFile
            RuleFiles     = @($ruleFiles)
            ScriptFiles   = $scriptFiles
            GuideFile     = $guideFile
            GuideText     = $guideText
            TrustedSigner = $trustedSigners
            GuideSteps    = $guideSteps
        }
    }
    finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
        if ($null -ne $backup -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------- certificate details for the window

# Host names that only exist inside a company network: no dot, a reserved private suffix, localhost or a private IPv4 address.
function Test-WizardInternalHost {
    param([string]$HostName)
    $name = "$HostName".Trim().TrimEnd('.').ToLowerInvariant()
    if (-not $name -or $name -eq 'localhost' -or -not $name.Contains('.')) { return $true }
    if ($name -match '\.(local|lan|internal|intranet|intra|corp|home|home\.arpa|localdomain)$') { return $true }
    if ($name -match '^(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|127\.\d+\.\d+\.\d+|169\.254\.\d+\.\d+)$') { return $true }
    return $false
}

# What the window shows of a signing certificate: subject, issuer, end of validity, thumbprint and the addresses of the revocation lists
# (CRL distribution points) of the certificate and its chain, with warnings: no address at all, no http address (devices outside the
# network cannot reach an ldap or file address), only internal names. The chain is built without a revocation check and, where .NET
# allows it, without downloads; nothing is sent to the addresses. Text ids of the warnings: wizard texts gui.crl.none, gui.crl.nohttp,
# gui.crl.internal.
function Get-WizardCertificateInfo {
    param([Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
    $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::AllowUnknownCertificateAuthority
    $chain.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds(2)
    $downloads = $chain.ChainPolicy.GetType().GetProperty('DisableCertificateDownloads')
    if ($null -ne $downloads) { $downloads.SetValue($chain.ChainPolicy, $true) }
    $certificates = New-Object System.Collections.Generic.List[System.Security.Cryptography.X509Certificates.X509Certificate2]
    try {
        $null = $chain.Build($Certificate)
        foreach ($element in $chain.ChainElements) { $certificates.Add($element.Certificate) }
    }
    catch { $certificates.Clear() }
    finally { $chain.Reset() }
    if ($certificates.Count -eq 0) { $certificates.Add($Certificate) }
    $urls = New-Object System.Collections.Generic.List[string]
    foreach ($certificate in $certificates) {
        foreach ($extension in $certificate.Extensions) {
            if ($extension.Oid.Value -ne '2.5.29.31') { continue }
            foreach ($match in [regex]::Matches($extension.Format($false), '(?i)\b(?:https?|ldap|file|ftp)://[^\s,;]+')) {
                $url = ($match.Value -replace '[\x00-\x1F\x7F]', '')
                if ($url.Length -gt 300) { $url = $url.Substring(0, 300) }
                if (-not $urls.Contains($url)) { $urls.Add($url) }
            }
        }
    }
    $warnings = New-Object System.Collections.Generic.List[string]
    $http = @($urls | Where-Object { $_ -match '(?i)^https?://' })
    if ($urls.Count -eq 0) { $warnings.Add('gui.crl.none') }
    elseif ($http.Count -eq 0) { $warnings.Add('gui.crl.nohttp') }
    if ($urls.Count -gt 0) {
        $public = @($urls | Where-Object {
                $uri = $null
                [Uri]::TryCreate($_, [UriKind]::Absolute, [ref]$uri) -and -not (Test-WizardInternalHost $uri.Host)
            })
        if ($public.Count -eq 0) { $warnings.Add('gui.crl.internal') }
    }
    return [pscustomobject]@{
        Subject    = $Certificate.Subject
        Issuer     = $Certificate.Issuer
        NotAfter   = $Certificate.NotAfter
        Thumbprint = $Certificate.Thumbprint
        CrlUrls    = $urls.ToArray()
        Warnings   = $warnings.ToArray()
    }
}

# ---------------------------------------------------------------- shared by the console and the window

# Default build settings, the same for New-SelfXPackage.ps1 and SelfXWizardGui.ps1. ToolsFolder is the folder tools (of the repository or of
# the unpacked payload archive). Without PayloadFolder the package comes from the payload around tools (it has App\SelfX.Code.json) or from
# the package folder "SelfX Service" of the repository (FromRepository: it is brought into the payload layout before the build).
function Get-WizardBuildDefaults {
    param([Parameter(Mandatory = $true)][string]$ToolsFolder, [string]$PayloadFolder)
    $root = Split-Path -Parent $ToolsFolder
    $source = $root
    $fromRepository = -not (Test-Path -LiteralPath (Join-Path $root 'App\SelfX.Code.json') -PathType Leaf)
    if ($fromRepository) { $source = Join-Path $root 'SelfX Service' }
    if ($PayloadFolder) { $source = $PayloadFolder; $fromRepository = $false }
    return [pscustomobject]@{
        PayloadFolder  = $source
        FromRepository = $fromRepository
        OutputFolder   = $(if ($fromRepository) { Join-Path $root 'build\SelfX-Guided' } else { Join-Path (Split-Path -Parent $root) 'SelfX-Guided' })
        ToolPath       = (Join-Path $ToolsFolder 'IntuneWinAppUtil.exe')
    }
}

# Builds the package from a payload folder or (FromRepository) from the package folder of the repository with a built folder Bin: the
# repository package is copied into the payload layout in a temporary folder first, which is removed afterwards. Everything else is
# Invoke-SelfXPackageBuild; the parameters are passed on unchanged.
function Invoke-SelfXWizardBuild {
    param(
        [Parameter(Mandatory = $true)]$Answers,
        [Parameter(Mandatory = $true)][string]$PayloadFolder,
        [switch]$FromRepository,
        [Parameter(Mandatory = $true)][string]$OutputFolder,
        [string]$ToolPath,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$TimestampServer,
        [string[]]$AdditionalSigner = @(),
        [scriptblock]$OnProgress,
        [string]$Language = 'en',
        [switch]$ConfigureOnly,
        [ValidateSet('Full', 'FullSeparateConfig', 'ConfigOnly')][string]$PackageKind = 'Full'
    )
    $temporaryPayload = $null
    try {
        $source = $PayloadFolder
        if ($FromRepository) {
            $temporaryPayload = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-Payload-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $null = New-SelfXPayloadFromRepository -SourceFolder $PayloadFolder -Target $temporaryPayload
            $source = $temporaryPayload
        }
        return (Invoke-SelfXPackageBuild -Answers $Answers -PayloadFolder $source -OutputFolder $OutputFolder -ToolPath $ToolPath -Certificate $Certificate `
                -TimestampServer $TimestampServer -AdditionalSigner $AdditionalSigner -OnProgress $OnProgress -Language $Language -ConfigureOnly:$ConfigureOnly -PackageKind $PackageKind)
    }
    finally {
        if ($temporaryPayload -and (Test-Path -LiteralPath $temporaryPayload)) { Remove-Item -LiteralPath $temporaryPayload -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
