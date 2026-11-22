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

    Not part of this file: user interface (Self_X.ps1), opening the mail (TicketSend.ps1), assignment to the support unit
    (concept in the project document "Ticket aus SelfX"). Sending is done by TicketSend.ps1.

.NOTES
    Name    : TicketMail.ps1
    Package : SelfX Service
    Context : GUI helper (signed-in user), functions only
    Version : 2.8.5

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.4    2026-11-22  fubu2k               Initial version: ticket model and mailto link (no user interface yet)
    2.8.5    2026-11-22  fubu2k               Device information block, Test-SelfXTicketAddress
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
        [int]$MaxLength = 1800
    )
    if (-not (Test-SelfXTicketAddress $To)) { throw 'Invalid recipient address.' }
    $subjectPart = [uri]::EscapeDataString($Subject)
    $build = { param($text) 'mailto:{0}?subject={1}&body={2}' -f $To, $subjectPart, [uri]::EscapeDataString($text) }
    $link = & $build $Body
    $text = $Body
    while ($link.Length -gt $MaxLength -and $text.Length -gt 50) {
        $text = $text.Substring(0, [int]($text.Length * 0.8)).TrimEnd()
        $link = & $build ($text + "`r`n[...]")
    }
    return $link
}
