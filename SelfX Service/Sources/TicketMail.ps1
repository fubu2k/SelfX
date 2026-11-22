<#
.SYNOPSIS
    Ticket model for "open a ticket from SelfX" (building blocks only, no user interface yet).

.DESCRIPTION
    Pure functions without side effects: they read nothing from the device and send nothing.
    They turn a few validated fields and one free text of the user into a standardised e-mail
    (subject, body, mailto link) for a ticket system that creates tickets from e-mail
    (for example GitLab Service Desk).

    Security rules:
      - The recipient address comes only from the package configuration, never from the user.
        ConvertTo-SelfXTicketMailto accepts exactly one plain address and rejects everything else.
      - Every field is cleaned: control characters and line breaks are removed from single-line
        fields (no header or line injection), lengths are limited, the computer name must look
        like a NetBIOS name.
      - The free text of the user is put into a fenced block, so a ticket system does not
        interpret Markdown or quick actions (lines starting with /) written by the user.
      - Field labels in the body are fixed English words, so tickets can be filtered and
        automated; they are not translated.

    Routing: Ticket_Config.xml lists any number of support units (mail address, optional Cc) and rules
    that map the group tag, the OU or the device category of the device to a unit (Read-SelfXTicketConfig,
    Resolve-SelfXTicketUnit). Names and patterns are not fixed in the code. The file is read by the
    GUI from the install folder (administrators only can change it).
    Not part of this file: user interface (Self_X.ps1), opening the mail and reading the device values (TicketSend.ps1). Sending is done by TicketSend.ps1.

.NOTES
    Name    : TicketMail.ps1
    Package : SelfX Service
    Context : GUI helper (signed-in user), functions only
    Version : 2.8.6

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.4    2026-11-22  fubu2k               Initial version: ticket model and mailto link (no user interface yet)
    2.8.5    2026-11-22  fubu2k               Device information block, Test-SelfXTicketAddress
    2.8.6    2026-11-22  fubu2k               Routing to support units from Ticket_Config.xml (rules for group tag, OU, category), Cc, group tag field
#>

function ConvertTo-SelfXTicketField {
    # Single-line field: no control characters or line breaks, one space between words, limited length.
    param($Value, [int]$MaxLength = 100)
    if ($null -eq $Value) { return '' }
    $text = [regex]::Replace("$Value", '[\x00-\x1F\x7F]+', ' ')
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength).TrimEnd() }
    return $text
}

function ConvertTo-SelfXTicketFreeText {
    # Free text of the user as a fenced block. The fence is longer than any run of backticks in the text,
    # so the text cannot close the block. A line that starts with / gets a leading space (quick actions).
    param($Text, [int]$MaxLength = 3000)
    if ($null -eq $Text) { return '' }
    $clean = ("$Text" -replace "`r`n?", "`n")
    $clean = [regex]::Replace($clean, '[\x00-\x08\x0B-\x1F\x7F]', '')
    if ($clean.Length -gt $MaxLength) { $clean = $clean.Substring(0, $MaxLength) }
    $clean = $clean.Trim()
    if (-not $clean) { return '' }
    $longestRun = 0
    foreach ($match in [regex]::Matches($clean, '`+')) { if ($match.Length -gt $longestRun) { $longestRun = $match.Length } }
    $fence = '`' * [Math]::Max(3, $longestRun + 1)
    $lines = foreach ($line in ($clean -split "`n")) {
        if ($line -match '^\s*/') { ' ' + $line } else { $line }
    }
    return ($fence + "`n" + ($lines -join "`n") + "`n" + $fence)
}

function New-SelfXTicket {
    <#
    .SYNOPSIS
        Builds the ticket: Subject (one line) and Body (fixed fields, then the free text).
        Tag is the subject marker from the configuration (letters, digits . _ -, up to 20, otherwise SelfX).
        KindText is the short type shown in the subject (language of the user), Timestamp is UTC.
    #>
    param(
        [string]$Tag = 'SelfX',
        [string]$KindText = 'Incident',
        [string]$Category,
        [string]$Unit,
        [string]$GroupTag,
        [string]$DeviceName,
        [string]$WindowsBuild,
        [string]$SelfXVersion,
        [string]$ActionId,
        [string]$ActionResult,
        [string]$DeviceStatus,
        [string]$UserText,
        [string]$DeviceInfoText,
        [datetime]$Timestamp = [datetime]::UtcNow
    )
    if ($Tag -notmatch '^[A-Za-z0-9._-]{1,20}\z') { $Tag = 'SelfX' }
    $computer = if ($DeviceName -match '^[A-Za-z0-9-]{1,63}\z') { $DeviceName } else { 'unknown' }
    $kind = ConvertTo-SelfXTicketField $KindText 30
    if (-not $kind) { $kind = 'Incident' }
    $categoryText = ConvertTo-SelfXTicketField $Category 40
    $subject = "[$Tag][$kind] "
    if ($categoryText) { $subject += "$categoryText - " }
    $subject += $computer

    $fields = [ordered]@{
        'Time (UTC)'      = $Timestamp.ToUniversalTime().ToString('yyyy-MM-dd HH:mm')
        'Computer'        = $computer
        'Support unit'    = ConvertTo-SelfXTicketField $Unit 40
        'Group tag'       = ConvertTo-SelfXTicketField $GroupTag 64
        'Device category' = $categoryText
        'Windows build'   = ConvertTo-SelfXTicketField $WindowsBuild 30
        'SelfX version'   = ConvertTo-SelfXTicketField $SelfXVersion 20
        'Action'          = ConvertTo-SelfXTicketField $ActionId 60
        'Action result'   = ConvertTo-SelfXTicketField $ActionResult 60
        'Device status'   = ConvertTo-SelfXTicketField $DeviceStatus 200
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($name in $fields.Keys) {
        if ($fields[$name]) { $lines.Add("${name}: $($fields[$name])") }
    }
    $freeText = ConvertTo-SelfXTicketFreeText $UserText
    if ($freeText) {
        $lines.Add('')
        $lines.Add('Description of the user:')
        $lines.Add($freeText)
    }
    # Device information (all rows of System information and Device status) comes last, so a cut mailto link loses it first.
    $deviceBlock = ConvertTo-SelfXTicketFreeText $DeviceInfoText 20000
    if ($deviceBlock) {
        $lines.Add('')
        $lines.Add('Device information:')
        $lines.Add($deviceBlock)
    }
    return [pscustomobject]@{
        Subject = $subject
        Body    = ($lines -join "`r`n")
    }
}

function Test-SelfXTicketAddress {
    # One plain e-mail address (no list, no display name, no mailto parameters).
    param($Address)
    return ("$Address" -match '^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,}\z')
}

function ConvertTo-SelfXTicketMailto {
    # mailto link for the default mail app. The address must be one plain address (from the configuration).
    # Too long a link is not opened by some mail apps: then the body is cut and says so.
    param(
        [Parameter(Mandatory = $true)][string]$To,
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string]$Body,
        [int]$MaxLength = 1800,
        [string]$Cc = ''
    )
    if (-not (Test-SelfXTicketAddress $To)) { throw 'Invalid recipient address.' }
    if ($Cc -and -not (Test-SelfXTicketAddress $Cc)) { throw 'Invalid Cc address.' }
    $subjectPart = [uri]::EscapeDataString($Subject)
    $ccPart = if ($Cc) { "&cc=$Cc" } else { '' }
    $build = { param($text) 'mailto:{0}?subject={1}{2}&body={3}' -f $To, $subjectPart, $ccPart, [uri]::EscapeDataString($text) }
    $link = & $build $Body
    $text = $Body
    while ($link.Length -gt $MaxLength -and $text.Length -gt 50) {
        $text = $text.Substring(0, [int]($text.Length * 0.8)).TrimEnd()
        $link = & $build ($text + "`r`n[...]")
    }
    return $link
}

function ConvertTo-SelfXTicketDeviceValue {
    # Value read from the device (group tag, category, OU) for the routing: invalid values become empty.
    param($Value, [ValidateSet('GroupTag', 'Category', 'OU')][string]$Kind)
    $text = "$Value".Trim()
    $pattern = if ($Kind -eq 'OU') { '^[^\x00-\x1F\x7F]{1,400}\z' } else { '^[A-Za-z0-9._ -]{1,64}\z' }
    if ($text -match $pattern) { return $text }
    return ''
}

function Read-SelfXTicketConfig {
    <#
    .SYNOPSIS
        Reads Ticket_Config.xml: Units (Id, Mail, optional Cc) and Rules (Source GroupTag, OU or Category;
        Match = exact value, or Regex; Unit = fixed unit, or the named group "unit" of the Regex).
        Any number of units and rules (limits MaxUnits and MaxRules). Entries that are not valid are skipped and
        named in Errors; a file that cannot be read gives an empty configuration (the default recipient is used).
    #>
    param([Parameter(Mandatory = $true)][string]$Path, [int]$MaxUnits = 500, [int]$MaxRules = 2000)
    $errors = New-Object System.Collections.Generic.List[string]
    $units = @{}
    $rules = New-Object System.Collections.Generic.List[object]
    $result = [pscustomobject]@{ Units = $units; Rules = $rules; Errors = $errors }
    $doc = New-Object Xml.XmlDocument
    $doc.XmlResolver = $null
    $reader = $null
    try {
        $settings = New-Object Xml.XmlReaderSettings
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create($Path, $settings)
        $doc.Load($reader)
    } catch {
        $errors.Add("The file cannot be read: $($_.Exception.Message)")
        return $result
    } finally {
        if ($reader) { $reader.Dispose() }
    }

    $count = 0
    foreach ($node in @($doc.SelectNodes('/Ticket_Config/Units/Unit'))) {
        $count++
        if ($count -gt $MaxUnits) { $errors.Add("More than $MaxUnits units: the rest is ignored."); break }
        $id = $node.GetAttribute('Id').Trim()
        $mail = $node.GetAttribute('Mail').Trim()
        $cc = $node.GetAttribute('Cc').Trim()
        if ($id -notmatch '^[A-Za-z0-9._-]{1,40}\z') { $errors.Add("Unit $count has no valid Id (letters, digits . _ -, up to 40)."); continue }
        if ($units.ContainsKey($id)) { $errors.Add("Unit '$id' is listed twice: the first entry is used."); continue }
        if (-not (Test-SelfXTicketAddress $mail)) { $errors.Add("Unit '$id' has no valid Mail address: skipped."); continue }
        if ($cc -and -not (Test-SelfXTicketAddress $cc)) { $errors.Add("Unit '$id' has no valid Cc address: skipped."); continue }
        $units[$id] = [pscustomobject]@{ Id = $id; Mail = $mail; Cc = $cc }
    }

    $count = 0
    foreach ($node in @($doc.SelectNodes('/Ticket_Config/Rules/Rule'))) {
        $count++
        if ($count -gt $MaxRules) { $errors.Add("More than $MaxRules rules: the rest is ignored."); break }
        $source = $node.GetAttribute('Source').Trim()
        $match = $node.GetAttribute('Match')
        $pattern = $node.GetAttribute('Regex')
        $unit = $node.GetAttribute('Unit').Trim()
        $sourceName = @('GroupTag', 'OU', 'Category') | Where-Object { $_ -eq $source } | Select-Object -First 1
        if (-not $sourceName) { $errors.Add("Rule ${count}: Source must be GroupTag, OU or Category: skipped."); continue }
        if ((-not $match -and -not $pattern) -or ($match -and $pattern)) { $errors.Add("Rule ${count}: use exactly one of Match and Regex: skipped."); continue }
        $regex = $null
        if ($pattern) {
            if ($pattern.Length -gt 300) { $errors.Add("Rule ${count}: Regex is longer than 300 characters: skipped."); continue }
            try {
                $regex = New-Object Text.RegularExpressions.Regex($pattern, ([Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'), [timespan]::FromMilliseconds(200))
            } catch { $errors.Add("Rule ${count}: Regex is not valid: skipped."); continue }
            if (-not $unit -and $regex.GroupNumberFromName('unit') -lt 0) { $errors.Add("Rule ${count}: needs Unit or a named group 'unit' in the Regex: skipped."); continue }
        } elseif (-not $unit) { $errors.Add("Rule ${count}: needs a Unit: skipped."); continue }
        if ($unit -and -not $units.ContainsKey($unit)) { $errors.Add("Rule ${count}: unit '$unit' is not listed: skipped."); continue }
        $rules.Add([pscustomobject]@{ Index = $count; Source = $sourceName; Match = $match; Regex = $regex; Unit = $unit })
    }
    return $result
}

function Resolve-SelfXTicketUnit {
    # First matching rule wins (order of the file). Returns Unit, Mail, Cc and Source, or $null (default recipient).
    param([Parameter(Mandatory = $true)]$Config, [string]$GroupTag, [string]$Category, [string]$OU)
    $values = @{
        GroupTag = ConvertTo-SelfXTicketDeviceValue $GroupTag 'GroupTag'
        Category = ConvertTo-SelfXTicketDeviceValue $Category 'Category'
        OU       = ConvertTo-SelfXTicketDeviceValue $OU 'OU'
    }
    foreach ($rule in $Config.Rules) {
        $value = $values[$rule.Source]
        if (-not $value) { continue }
        $unitId = ''
        if ($rule.Regex) {
            try { $found = $rule.Regex.Match($value) } catch { continue }
            if (-not $found.Success) { continue }
            $unitId = if ($rule.Unit) { $rule.Unit } else { $found.Groups['unit'].Value }
        } else {
            if ($value -ne $rule.Match) { continue }
            $unitId = $rule.Unit
        }
        if ($unitId -and $Config.Units.ContainsKey($unitId)) {
            $unit = $Config.Units[$unitId]
            return [pscustomobject]@{ Unit = $unit.Id; Mail = $unit.Mail; Cc = $unit.Cc; Source = "Rule $($rule.Index) ($($rule.Source))" }
        }
    }
    return $null
}
