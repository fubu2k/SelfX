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
. (Join-Path $PSScriptRoot 'Sources\SupportReport.ps1')
. (Join-Path $PSScriptRoot 'Sources\TicketSend.ps1')
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


# --- device information block ---------------------------------------------------------------------
$withInfo = New-SelfXTicket -DeviceName 'PC-1' -UserText 'Problem' -DeviceInfoText "[System]`r`nName : PC-1`r`n/close" -Timestamp $time
Assert-Equal ($withInfo.Body -match 'Device information:\r\n```\n\[System\]\nName : PC-1\n /close\n```$') $true 'ticket: device information comes last in a fenced block, quick action neutralised'
Assert-Equal ($withInfo.Body.IndexOf('Description of the user:') -lt $withInfo.Body.IndexOf('Device information:')) $true 'ticket: description comes before the device information'
$noInfo = New-SelfXTicket -DeviceName 'PC-1' -Timestamp $time
Assert-Equal ($noInfo.Body -match 'Device information') $false 'ticket: no device information, no block'
$cutLink = ConvertTo-SelfXTicketMailto -To 'a@example.com' -Subject 'S' -Body $withInfo.Body
Assert-Equal ($cutLink.Length -le 1800) $true 'mailto: link with device information stays within the limit'
Assert-Equal (Test-SelfXTicketAddress 'service-desk@example.com') $true 'address: valid address accepted'
Assert-Equal (Test-SelfXTicketAddress $null) $false 'address: null rejected'

# --- opening the mail (TicketSend.ps1, mail program and Explorer replaced by stubs) ------------
$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXTicketTest-' + [guid]::NewGuid().ToString('N'))
$script:outlookCalls = @(); $script:started = @(); $script:outlookFails = $false
function New-SelfXOutlookMail { param($To, $Subject, $Body, $Attachment) if ($script:outlookFails) { throw 'no COM' }; $script:outlookCalls += [pscustomobject]@{ To = $To; Subject = $Subject; Body = $Body; Attachment = $Attachment } }
function Start-Process { param($FilePath, $ArgumentList) $script:started += [pscustomobject]@{ FilePath = $FilePath; Args = "$ArgumentList" } }
try {
	$result = Send-SelfXTicket -To 'service-desk@example.com' -Ticket $withInfo -DeviceInfoText 'Name : PC-1' -DeviceName 'PC-1' -Destination $temp
	Assert-Equal $result.Status 'Outlook' 'send: classic Outlook is used first'
	Assert-Equal $script:outlookCalls.Count 1 'send: one Outlook mail'
	Assert-Equal $script:outlookCalls[0].To 'service-desk@example.com' 'send: recipient from the parameter'
	Assert-Equal $script:outlookCalls[0].Body $withInfo.Body 'send: complete body is used with Outlook (no cut)'
	Assert-Equal (Test-Path -LiteralPath $result.Path -PathType Leaf) $true 'send: device information file exists'
	Assert-Equal ((Split-Path -Leaf $result.Path) -match '^TicketInfo-PC-1-\d{8}-\d{6}\.txt$') $true 'send: fixed file name'
	Assert-Equal ([IO.File]::ReadAllText($result.Path)) 'Name : PC-1' 'send: file contains the device information'
	Assert-Equal $script:started.Count 0 'send: no other program is started when Outlook works'

	$script:outlookFails = $true; $script:started = @()
	$result = Send-SelfXTicket -To 'service-desk@example.com' -Ticket $withInfo -DeviceInfoText 'Name : PC-1' -DeviceName 'PC-1' -Destination $temp
	Assert-Equal $result.Status 'Manual' 'send: without classic Outlook the default mail app is used'
	Assert-Equal $script:started.Count 2 'send: mailto link and Explorer'
	Assert-Equal ($script:started[0].FilePath -like 'mailto:service-desk@example.com?subject=*') $true 'send: mailto link with the configured address'
	Assert-Equal ($script:started[1].FilePath -like '*\explorer.exe') $true 'send: Explorer selects the file'
	Assert-Equal ($script:started[1].Args -like '/select,"*TicketInfo-PC-1-*.txt"') $true 'send: Explorer shows the device information file'
	Assert-Equal @(Get-ChildItem -LiteralPath $temp -Filter 'TicketInfo-*').Count 1 'send: older device information files are removed'

	$script:started = @(); $script:outlookCalls = @()
	foreach ($badTo in 'a@b.de,c@d.de', 'a@b.de?bcc=x@y.de', 'nobody') {
		$result = Send-SelfXTicket -To $badTo -Ticket $withInfo -DeviceInfoText 'x' -Destination $temp
		Assert-Equal $result.Status 'Error' "send: address '$badTo' is rejected"
	}
	Assert-Equal ($script:started.Count + $script:outlookCalls.Count) 0 'send: nothing is opened for a rejected address'
	$result = Send-SelfXTicket -To 'a@example.com' -Ticket $withInfo -DeviceInfoText 'x' -DeviceName "PC`r`n..\x" -Destination $temp
	Assert-Equal ((Split-Path -Leaf $result.Path) -match '^TicketInfo-device-\d{8}-\d{6}\.txt$') $true 'send: invalid device name cannot reach the file name'
} finally {
	Remove-Item function:New-SelfXOutlookMail, function:Start-Process -ErrorAction SilentlyContinue
	if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

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
