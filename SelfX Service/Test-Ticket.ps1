<#
.SYNOPSIS
    Tests the ticket model (Sources\TicketMail.ps1): cleaning of fields, free text block, subject, mailto.

.DESCRIPTION
    Pure functions, nothing is read from or changed on the device.

.NOTES
    Name    : Test-Ticket.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.6

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.4    2026-11-22  fubu2k               Initial version
    2.8.6    2026-11-22  fubu2k               Routing (Ticket_Config.xml), Cc, device values
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
function New-SelfXOutlookMail { param($To, $Subject, $Body, $Attachment, $Cc) if ($script:outlookFails) { throw 'no COM' }; $script:outlookCalls += [pscustomobject]@{ To = $To; Cc = $Cc; Subject = $Subject; Body = $Body; Attachment = $Attachment } }
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


# --- routing: Ticket_Config.xml -------------------------------------------------------------------
$cfgTemp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXTicketCfg-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $cfgTemp -Force | Out-Null
function Write-TestConfig($Name, $Xml) { $path = Join-Path $cfgTemp $Name; [IO.File]::WriteAllText($path, $Xml); return $path }
try {
	$shipped = Read-SelfXTicketConfig -Path (Join-Path $PSScriptRoot 'Sources\Ticket_Config.xml')
	Assert-Equal @($shipped.Errors).Count 0 'config: the shipped file is valid'
	Assert-Equal @($shipped.Rules).Count 0 'config: the shipped file has no active rules (default recipient)'

	$xml = @"
<Ticket_Config>
  <Units>
    <Unit Id="IT1" Mail="it1@example.com" Cc="" />
    <Unit Id="IT2" Mail="it2@example.com" Cc="service@example.com" />
    <Unit Id="IT3" Mail="it3@example.com" />
    <Unit Id="IT1" Mail="double@example.com" />
    <Unit Id="BAD1" Mail="a@b.de,c@d.de" />
    <Unit Id="BAD2" Mail="ok@example.com" Cc="x y@example.com" />
    <Unit Id="bad id" Mail="ok@example.com" />
  </Units>
  <Rules>
    <Rule Source="GroupTag" Match="de-it1-ber" Unit="IT1" />
    <Rule Source="GroupTag" Regex="^[A-Z]{2}-(?'unit'IT[0-9]+)-[A-Z]{3}`$" />
    <Rule Source="OU" Regex="OU=IT2," Unit="IT2" />
    <Rule Source="Category" Match="Category-A" Unit="IT3" />
    <Rule Source="Floor" Match="x" Unit="IT1" />
    <Rule Source="GroupTag" Unit="IT1" />
    <Rule Source="GroupTag" Match="a" Regex="b" Unit="IT1" />
    <Rule Source="GroupTag" Regex="(" Unit="IT1" />
    <Rule Source="GroupTag" Regex="^x`$" />
    <Rule Source="GroupTag" Match="z" Unit="NOPE" />
    <Rule Source="GroupTag" Match="late" Unit="IT3" />
  </Rules>
</Ticket_Config>
"@
	$config = Read-SelfXTicketConfig -Path (Write-TestConfig 'a.xml' $xml)
	Assert-Equal @($config.Units.Keys).Count 3 'config: three valid units (duplicate, bad address, bad Cc and bad Id are skipped)'
	Assert-Equal $config.Units['IT1'].Mail 'it1@example.com' 'config: the first entry of a duplicate unit is used'
	Assert-Equal $config.Units['IT2'].Cc 'service@example.com' 'config: Cc is read'
	Assert-Equal @($config.Rules).Count 5 'config: five valid rules (the others are skipped)'
	Assert-Equal @($config.Errors).Count 10 'config: every skipped entry is named in the errors'
	Assert-Equal ($config.Errors -join '|' -match 'a@b.de') $false 'config: errors do not repeat the invalid addresses'

	# --- resolving: first match wins, any number of rules
	$r = Resolve-SelfXTicketUnit -Config $config -GroupTag 'DE-IT1-BER'
	Assert-Equal $r.Unit 'IT1' 'resolve: exact match ignores case'
	Assert-Equal $r.Source 'Rule 1 (GroupTag)' 'resolve: source names the rule'
	$r = Resolve-SelfXTicketUnit -Config $config -GroupTag 'FR-IT2-PAR'
	Assert-Equal $r.Unit 'IT2' 'resolve: unit from the named group of the Regex'
	Assert-Equal $r.Mail 'it2@example.com' 'resolve: mail of the unit'
	Assert-Equal $r.Cc 'service@example.com' 'resolve: Cc of the unit'
	$r = Resolve-SelfXTicketUnit -Config $config -GroupTag 'FR-IT9-PAR'
	Assert-Equal $null $r 'resolve: group names an unknown unit, no other rule matches: default'
	$r = Resolve-SelfXTicketUnit -Config $config -OU 'OU=IT2,OU=Clients,DC=example,DC=com'
	Assert-Equal $r.Unit 'IT2' 'resolve: OU rule'
	$r = Resolve-SelfXTicketUnit -Config $config -Category 'Category-A'
	Assert-Equal $r.Unit 'IT3' 'resolve: category rule'
	$r = Resolve-SelfXTicketUnit -Config $config -GroupTag 'DE-IT1-BER' -Category 'Category-A'
	Assert-Equal $r.Unit 'IT1' 'resolve: the earlier rule wins'
	$r = Resolve-SelfXTicketUnit -Config $config -GroupTag 'late'
	Assert-Equal $r.Unit 'IT3' 'resolve: a rule behind skipped rules still works'
	Assert-Equal $null (Resolve-SelfXTicketUnit -Config $config) 'resolve: no values, no unit'
	Assert-Equal $null (Resolve-SelfXTicketUnit -Config $config -GroupTag "DE-IT1-BER`r`nBcc: x") 'resolve: a value with control characters is not used'
	Assert-Equal $null (Resolve-SelfXTicketUnit -Config $config -GroupTag ('A' * 65)) 'resolve: a value longer than 64 characters is not used'

	# --- any number of units and rules
	$many = New-Object System.Text.StringBuilder
	[void]$many.Append('<Ticket_Config><Units>')
	foreach ($i in 1..300) { [void]$many.Append("<Unit Id=`"U$i`" Mail=`"u$i@example.com`" />") }
	[void]$many.Append('</Units><Rules>')
	foreach ($i in 1..300) { [void]$many.Append("<Rule Source=`"GroupTag`" Match=`"TAG-$i`" Unit=`"U$i`" />") }
	[void]$many.Append('</Rules></Ticket_Config>')
	$big = Read-SelfXTicketConfig -Path (Write-TestConfig 'big.xml' $many.ToString())
	Assert-Equal @($big.Errors).Count 0 'config: 300 units and 300 rules are read without errors'
	Assert-Equal (Resolve-SelfXTicketUnit -Config $big -GroupTag 'TAG-299').Mail 'u299@example.com' 'resolve: rule 299 of 300'
	$limited = Read-SelfXTicketConfig -Path (Write-TestConfig 'big2.xml' $many.ToString()) -MaxUnits 10 -MaxRules 10
	Assert-Equal @($limited.Units.Keys).Count 10 'config: the unit limit is applied'
	Assert-Equal @($limited.Rules).Count 10 'config: the rule limit is applied'

	# --- files that cannot be used give an empty configuration
	$missing = Read-SelfXTicketConfig -Path (Join-Path $cfgTemp 'missing.xml')
	Assert-Equal (@($missing.Rules).Count + @($missing.Units.Keys).Count) 0 'config: missing file gives an empty configuration'
	Assert-Equal @($missing.Errors).Count 1 'config: missing file is named in the errors'
	$broken = Read-SelfXTicketConfig -Path (Write-TestConfig 'broken.xml' '<Ticket_Config><Units>')
	Assert-Equal @($broken.Errors).Count 1 'config: invalid XML is named in the errors'
	$dtd = Read-SelfXTicketConfig -Path (Write-TestConfig 'dtd.xml' '<!DOCTYPE x [<!ENTITY e "boom">]><Ticket_Config><Units><Unit Id="A" Mail="a@example.com"/></Units></Ticket_Config>')
	Assert-Equal @($dtd.Units.Keys).Count 0 'config: a DTD is refused'
	Assert-Equal $null (Resolve-SelfXTicketUnit -Config $broken -GroupTag 'x') 'resolve: empty configuration gives the default'

	# --- a regex that needs too long is stopped
	$slow = Read-SelfXTicketConfig -Path (Write-TestConfig 'slow.xml' '<Ticket_Config><Units><Unit Id="A" Mail="a@example.com"/></Units><Rules><Rule Source="GroupTag" Regex="^(a+)+$" Unit="A"/></Rules></Ticket_Config>')
	$watch = [Diagnostics.Stopwatch]::StartNew()
	$null = Resolve-SelfXTicketUnit -Config $slow -GroupTag (('a' * 40) + '-')
	Assert-Equal ($watch.ElapsedMilliseconds -lt 5000) $true 'resolve: a catastrophic Regex is stopped by the timeout'
} finally {
	Remove-Item -LiteralPath $cfgTemp -Recurse -Force -ErrorAction SilentlyContinue
}

# --- device values (registry replaced by a stub) ----------------------------------------------------
$script:regValues = @{}
function Get-ItemProperty { param($LiteralPath, $ErrorAction) if ($script:regValues.ContainsKey($LiteralPath)) { return [pscustomobject]$script:regValues[$LiteralPath] } }
try {
	$script:regValues['HKLM:\SOFTWARE\SelfX\Support'] = @{ GroupTag = 'DE-IT1-BER'; Category = 'Category-A' }
	$script:regValues['HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine'] = @{ 'Distinguished-Name' = 'CN=PC-1,OU=IT2,OU=Clients,DC=example,DC=com' }
	$dev = Get-SelfXTicketDeviceValues
	Assert-Equal $dev.GroupTag 'DE-IT1-BER' 'device values: group tag'
	Assert-Equal $dev.Category 'Category-A' 'device values: category'
	Assert-Equal $dev.OU 'OU=IT2,OU=Clients,DC=example,DC=com' 'device values: OU without the computer name'
	$script:regValues['HKLM:\SOFTWARE\SelfX\Support'] = @{ GroupTag = "x`r`ny"; Category = ('c' * 80) }
	$dev = Get-SelfXTicketDeviceValues
	Assert-Equal ($dev.GroupTag + $dev.Category) '' 'device values: invalid values become empty'
	$script:regValues = @{}
	$dev = Get-SelfXTicketDeviceValues
	Assert-Equal ($dev.GroupTag + $dev.Category + $dev.OU) '' 'device values: no keys, no values'

	$cfg2 = [pscustomobject]@{
		Units = @{ IT1 = [pscustomobject]@{ Id = 'IT1'; Mail = 'it1@example.com'; Cc = 'cc@example.com' } }
		Rules = @([pscustomobject]@{ Index = 1; Source = 'GroupTag'; Match = 'DE-IT1-BER'; Regex = $null; Unit = 'IT1' })
	}
	$t = Get-SelfXTicketTarget -DefaultMail 'default@example.com' -Config $cfg2 -DeviceValues ([pscustomobject]@{ GroupTag = 'DE-IT1-BER'; Category = 'Category-A'; OU = '' })
	Assert-Equal "$($t.To)|$($t.Cc)|$($t.Unit)|$($t.GroupTag)|$($t.Category)" 'it1@example.com|cc@example.com|IT1|DE-IT1-BER|Category-A' 'target: unit of the rule, tag and category'
	$t = Get-SelfXTicketTarget -DefaultMail 'default@example.com' -Config $cfg2 -DeviceValues ([pscustomobject]@{ GroupTag = 'OTHER'; Category = ''; OU = '' })
	Assert-Equal "$($t.To)|$($t.Cc)|$($t.Unit)|$($t.Source)" 'default@example.com|||Default' 'target: no match gives the default recipient'
	$t = Get-SelfXTicketTarget -DefaultMail 'default@example.com' -DeviceValues ([pscustomobject]@{ GroupTag = 'DE-IT1-BER'; Category = ''; OU = '' })
	Assert-Equal $t.To 'default@example.com' 'target: no configuration gives the default recipient'
} finally {
	Remove-Item function:Get-ItemProperty -ErrorAction SilentlyContinue
}

# --- Cc in the mail ---------------------------------------------------------------------------------
$ccLink = ConvertTo-SelfXTicketMailto -To 'a@example.com' -Cc 'cc@example.com' -Subject 'S' -Body 'B'
Assert-Equal $ccLink 'mailto:a@example.com?subject=S&cc=cc@example.com&body=B' 'mailto: Cc is added'
foreach ($badCc in 'a@b.de,c@d.de', 'a@b.de?bcc=x@y.de', 'no-at') {
	$threw = $false
	try { $null = ConvertTo-SelfXTicketMailto -To 'a@example.com' -Cc $badCc -Subject 'S' -Body 'B' } catch { $threw = $true }
	Assert-Equal $threw $true "mailto: Cc '$badCc' is rejected"
}
$withGroup = New-SelfXTicket -DeviceName 'PC-1' -Unit 'IT1' -GroupTag 'DE-IT1-BER' -Category 'Category-A' -Timestamp $time
Assert-Equal ($withGroup.Body -match '(?m)^Group tag: DE-IT1-BER\r?$') $true 'ticket: group tag field'
Assert-Equal ($withGroup.Body -match '(?m)^Support unit: IT1\r?$') $true 'ticket: support unit field'
$ccTemp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXTicketCc-' + [guid]::NewGuid().ToString('N'))
$script:outlookCalls = @(); $script:started = @(); $script:outlookFails = $false
function New-SelfXOutlookMail { param($To, $Subject, $Body, $Attachment, $Cc) if ($script:outlookFails) { throw 'no COM' }; $script:outlookCalls += [pscustomobject]@{ To = $To; Cc = $Cc } }
function Start-Process { param($FilePath, $ArgumentList) $script:started += [pscustomobject]@{ FilePath = $FilePath } }
try {
	$result = Send-SelfXTicket -To 'it1@example.com' -Cc 'cc@example.com' -Ticket $withGroup -DeviceInfoText 'x' -DeviceName 'PC-1' -Destination $ccTemp
	Assert-Equal $result.Status 'Outlook' 'send: Outlook with Cc'
	Assert-Equal $script:outlookCalls[0].Cc 'cc@example.com' 'send: Cc is passed to Outlook'
	$script:outlookFails = $true
	$result = Send-SelfXTicket -To 'it1@example.com' -Cc 'cc@example.com' -Ticket $withGroup -DeviceInfoText 'x' -DeviceName 'PC-1' -Destination $ccTemp
	Assert-Equal ($script:started[0].FilePath -like '*&cc=cc@example.com&body=*') $true 'send: Cc is in the mailto link'
	$script:started = @()
	$result = Send-SelfXTicket -To 'it1@example.com' -Cc 'a@b.de,c@d.de' -Ticket $withGroup -DeviceInfoText 'x' -Destination $ccTemp
	Assert-Equal $result.Status 'Error' 'send: invalid Cc is rejected'
	Assert-Equal $script:started.Count 0 'send: nothing is opened for an invalid Cc'
} finally {
	Remove-Item function:New-SelfXOutlookMail, function:Start-Process -ErrorAction SilentlyContinue
	if (Test-Path -LiteralPath $ccTemp) { Remove-Item -LiteralPath $ccTemp -Recurse -Force -ErrorAction SilentlyContinue }
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
