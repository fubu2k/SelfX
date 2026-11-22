<#
.SYNOPSIS
    Tests the ticket model (Sources\TicketMail.ps1): cleaning of fields, free text block, subject, mailto.

.DESCRIPTION
    Pure functions, nothing is read from or changed on the device.

.NOTES
    Name    : Test-Ticket.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.4

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.4    2026-11-22  fubu2k               Initial version
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ($Actual -ne $Expected) { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}
. (Join-Path $PSScriptRoot 'Sources\TicketMail.ps1')
$time = [datetime]::new(2026, 11, 22, 14, 30, 0, [DateTimeKind]::Utc)

# --- single-line fields -----------------------------------------------------------------------
Assert-Equal (ConvertTo-SelfXTicketField $null) '' 'field: null gives empty text'
Assert-Equal (ConvertTo-SelfXTicketField "a`r`nb`tc") 'a b c' 'field: line breaks and tabs become one space'
Assert-Equal (ConvertTo-SelfXTicketField "x$([char]0)y$([char]27)z") 'x y z' 'field: control characters removed'
Assert-Equal (ConvertTo-SelfXTicketField ('a' * 300) 10) 'aaaaaaaaaa' 'field: length limited'
Assert-Equal (ConvertTo-SelfXTicketField '  two   spaces ') 'two spaces' 'field: spaces collapsed and trimmed'

# --- free text ----------------------------------------------------------------------------------
Assert-Equal (ConvertTo-SelfXTicketFreeText $null) '' 'free text: null gives empty text'
Assert-Equal (ConvertTo-SelfXTicketFreeText "  `r`n ") '' 'free text: only white space gives empty text'
$fence3 = '`' * 3
$plain = ConvertTo-SelfXTicketFreeText "Teams does not start`r`nsince Monday"
$plainExpected = $fence3 + "`nTeams does not start`nsince Monday`n" + $fence3
Assert-Equal $plain $plainExpected 'free text: fenced block with LF line breaks'
$quick = ConvertTo-SelfXTicketFreeText "/assign @boss`n/close"
Assert-Equal ($quick -match '(?m)^/') $false 'free text: no line starts with / (quick actions)'
Assert-Equal ($quick -match '(?m)^ /assign @boss$') $true 'free text: quick action line only gets a leading space'
$fenced = ConvertTo-SelfXTicketFreeText ("a`n" + $fence3 + "`n# Heading`n" + $fence3)
Assert-Equal $fenced.StartsWith('````' + "`n") $true 'free text: fence is longer than the backtick run in the text'
Assert-Equal $fenced.EndsWith("`n" + '````') $true 'free text: closing fence matches the opening fence'
$cut = ConvertTo-SelfXTicketFreeText ('x' * 5000)
Assert-Equal $cut.Length 3008 'free text: limited to 3000 characters plus the two fences'
$bell = [string][char]7
$noBell = ConvertTo-SelfXTicketFreeText ("a" + $bell + "b")
Assert-Equal $noBell.Contains($bell) $false 'free text: control characters removed'

# --- ticket -------------------------------------------------------------------------------------
$ticket = New-SelfXTicket -Tag 'SelfX' -KindText 'Stoerung' -Category 'Kategorie-A' -Unit 'IT1' -DeviceName 'PC-0815' -WindowsBuild '26300' -SelfXVersion '2.8.0' -ActionId 'Q_Outlook' -ActionResult 'Success' -DeviceStatus 'Network: ok' -UserText 'Outlook hangs' -Timestamp $time
Assert-Equal $ticket.Subject '[SelfX][Stoerung] Kategorie-A - PC-0815' 'ticket: subject follows the fixed scheme'
Assert-Equal ($ticket.Body -match '(?m)^Time \(UTC\): 2026-11-22 14:30\r?$') $true 'ticket: time is UTC'
Assert-Equal ($ticket.Body -match '(?m)^Computer: PC-0815\r?$') $true 'ticket: computer name field'
Assert-Equal ($ticket.Body -match '(?m)^Support unit: IT1\r?$') $true 'ticket: unit field'
Assert-Equal ($ticket.Body -match '(?m)^Action: Q_Outlook\r?$') $true 'ticket: action field'
Assert-Equal ($ticket.Body -match 'Description of the user:\r\n```\nOutlook hangs\n```$') $true 'ticket: free text comes last in a fenced block'
$minimal = New-SelfXTicket -DeviceName 'PC-1' -Timestamp $time
Assert-Equal $minimal.Subject '[SelfX][Incident] PC-1' 'ticket: defaults and no category'
Assert-Equal ($minimal.Body -match 'Description') $false 'ticket: no free text, no description block'
Assert-Equal ($minimal.Body -match 'Support unit') $false 'ticket: empty fields are left out'
$bad = New-SelfXTicket -Tag "X]`r`nBcc: a@b.de" -KindText "Fault`r`nBcc: a@b.de" -Category "Cat`r`nBcc: a@b.de" -DeviceName "PC`r`nBcc: a@b.de" -Timestamp $time
Assert-Equal ($bad.Subject -match "[\r\n]") $false 'ticket: no line break can get into the subject'
Assert-Equal $bad.Subject.StartsWith('[SelfX][') $true 'ticket: invalid tag falls back to SelfX'
Assert-Equal ($bad.Subject -match 'PC.*Bcc') $false 'ticket: invalid computer name is replaced'
Assert-Equal ($bad.Subject.EndsWith(' unknown')) $true 'ticket: invalid computer name shows unknown'
$field = New-SelfXTicket -DeviceName 'PC-1' -ActionResult "ok`r`nBcc: a@b.de" -Timestamp $time
Assert-Equal ($field.Body -match '(?m)^Bcc') $false 'ticket: no field can add a line to the body'

# --- mailto -------------------------------------------------------------------------------------
$link = ConvertTo-SelfXTicketMailto -To 'service-desk@example.com' -Subject '[SelfX] A b' -Body "Line 1`r`nLine 2"
Assert-Equal $link 'mailto:service-desk@example.com?subject=%5BSelfX%5D%20A%20b&body=Line%201%0D%0ALine%202' 'mailto: address readable, subject and body escaped'
foreach ($badAddress in 'a@b.de,c@d.de', 'a@b.de;c@d.de', 'a@b.de?bcc=x@y.de', 'a b@c.de', 'no-at-sign', '', 'a@b.de&cc=x@y.de', "a@b.de`n") {
	$threw = $false
	try { $null = ConvertTo-SelfXTicketMailto -To $badAddress -Subject 'S' -Body 'B' } catch { $threw = $true }
	Assert-Equal $threw $true "mailto: address '$badAddress' is rejected"
}
$long = ConvertTo-SelfXTicketMailto -To 'a@example.com' -Subject 'S' -Body ('word ' * 2000)
Assert-Equal ($long.Length -le 1800) $true 'mailto: long body is cut to the link limit'
Assert-Equal $long.EndsWith([uri]::EscapeDataString("`r`n[...]")) $true 'mailto: cut body ends with a marker'

# --- the file has no side effects ---------------------------------------------------------------
$text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sources\TicketMail.ps1'))
foreach ($pattern in 'Start-Process', 'Invoke-Expression', '\biex\b', 'Set-ItemProperty', 'New-Item', 'Out-File', 'Set-Content', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Get-ItemProperty') {
	Assert-Equal ($text -match $pattern) $false "TicketMail.ps1 does not use $pattern"
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
