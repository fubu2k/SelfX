<#
.SYNOPSIS
    Functions of the SelfX package wizard (tools\New-SelfXPackage.ps1): texts, validation, patching of the settings
    files, generation of the ticket configuration, the Intune scripts and the instructions.

.NOTES
    Name    : SelfXWizard.ps1
    Package : tools
    Context : Build machine (administrator of the package; not installed, not shipped)
    Version : 3.1.0
    Works in Windows PowerShell 5.1 and PowerShell 7. The file only defines functions; it changes nothing when it is
    dot-sourced. Test-SelfXPackageWizard.ps1 tests it.
#>

$script:WizardTexts = @{}
$script:WizardAnswerFile = $null
$script:WizardInteractive = $true

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

function New-SelfXIntuneGuide {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Answers,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$PackageFile,
        [Parameter(Mandatory = $true)][string]$DetectionFile,
        [string[]]$ScriptFiles = @(),
        [string]$AnswersFile = ''
    )
    $ps = '%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File'
    $org = $Answers.OrgName
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((Get-WText 'guide.title' @($org, $Version)))
    $lines.Add(('=' * 72))
    $lines.Add((Get-WText 'guide.intro'))
    $lines.Add('')
    $lines.Add((Get-WText 'guide.s1' @($PackageFile, "SelfX Service - $org", $org)))
    $lines.Add('')
    $lines.Add((Get-WText 'guide.s2' @("$ps .\Install.ps1")))
    $lines.Add((Get-WText 'guide.s2b' @("$ps .\Uninstall.ps1")))
    $lines.Add((Get-WText 'guide.s2c'))
    $lines.Add('')
    $lines.Add((Get-WText 'guide.s3'))
    $lines.Add('')
    $lines.Add((Get-WText 'guide.s4' @($DetectionFile)))
    $lines.Add('')
    $lines.Add((Get-WText 'guide.s5'))
    $lines.Add('')
    $lines.Add((Get-WText 'guide.s6'))
    $lines.Add('')
    if ($ScriptFiles.Count -gt 0) {
        $lines.Add((Get-WText 'guide.s7'))
        foreach ($unit in @($Answers.Units)) {
            $tags = if (@($unit.GroupTags).Count) { (@($unit.GroupTags) -join ', ') } else { '-' }
            $classes = if (@($unit.Categories).Count) { (@($unit.Categories) -join ', ') } else { '-' }
            $lines.Add((Get-WText 'guide.s7item' @($unit.Id, $tags, $classes)))
        }
        foreach ($file in $ScriptFiles) { $lines.Add("   - $file") }
        $lines.Add((Get-WText 'guide.s7tag'))
        $lines.Add('')
    }
    $lines.Add((Get-WText 'guide.s8' @($(if ($ScriptFiles.Count -gt 0) { 8 } else { 7 }))))
    $lines.Add('')
    if ($AnswersFile) {
        $lines.Add((Get-WText 'guide.update' @($AnswersFile)))
        $lines.Add((Get-WText 'guide.answers' @($AnswersFile)))
    }
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

# Copies the logo into <configuration folder>\Branding and returns the relative path for Brand_Logo (relative to the configuration
# folder: Branding\<name>, resolved by SelfXPaths.ps1 on the device).
function Copy-WizardLogo {
    param([string]$LogoPath, [string]$SourcesFolder)
    $item = Get-Item -LiteralPath $LogoPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'The logo must be a normal file.' }
    if ($item.Extension -notmatch '^\.(png|jpg|jpeg|bmp|gif|ico)$') { throw 'The logo must be png, jpg, bmp, gif or ico.' }
    if ($item.Length -gt 2MB) { throw 'The logo is larger than 2 MB.' }
    $folder = Join-Path $SourcesFolder 'Branding'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    foreach ($old in @(Get-ChildItem -LiteralPath $folder -File -Force)) { Remove-Item -LiteralPath $old.FullName -Force }
    $name = 'logo' + $item.Extension.ToLowerInvariant()
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $folder $name) -Force
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
