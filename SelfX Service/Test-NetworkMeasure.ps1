<#
.SYNOPSIS
    Tests the optional network measurements (Sources\SystemInfo.ps1): validation, Network_Test_Config.xml, statistics,
    measurements against the loopback address, texts and status.

.DESCRIPTION
    Measurements only use this computer (loopback listener, localhost) and a name that cannot be resolved.
    Nothing is read from the device other than that, nothing is changed.

.NOTES
    Name    : Test-NetworkMeasure.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.8    2026-11-22  fubu2k               Initial version
    3.1.0    2026-11-27  fubu2k               Connection check: Group and Kind, 12 targets, group rows, verdict table, HostNames, Microsoft switch, order, time limit
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ($Actual -ne $Expected) { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}
. (Join-Path $PSScriptRoot 'Sources\SystemInfo.ps1')

# --- host names -----------------------------------------------------------------------------------
foreach ($valid in 'intranet', 'intranet.example.org', 'a-b.example.org', 'host1.sub.example.org', '10.1.2.3', 'localhost') {
	Assert-Equal (Test-SelfXNetworkHostName $valid) $true "host name: '$valid' is valid"
}
$longLabel = ('a' * 64) + '.example.org'
$longName = ((('a' * 60) + '.') * 5) + 'org'
foreach ($invalid in $null, '', 'a b', 'a_b.example.org', 'http://example.org', 'example.org/path', 'example.org:443', '-a.example.org', 'a-.example.org', 'a..example.org', '.example.org', 'example.org.', 'a@b', "a`nb", $longLabel, $longName, '[::1]', '::1') {
	Assert-Equal (Test-SelfXNetworkHostName $invalid) $false "host name: '$invalid' is rejected"
}
Assert-Equal (Test-SelfXIPv4Literal '10.1.2.3') $true 'IPv4: dotted address'
Assert-Equal (Test-SelfXIPv4Literal '300.1.2.3') $false 'IPv4: 300 is not an address'
Assert-Equal (Test-SelfXIPv4Literal '1234') $false 'IPv4: a plain number is not an address'
Assert-Equal (Test-SelfXIPv4Literal 'example.org') $false 'IPv4: a name is not an address'

# --- statistics -----------------------------------------------------------------------------------
$stats = Get-SelfXLatencyStats @(10, 20, $null, 30)
Assert-Equal $stats.Sent 4 'stats: four samples'
Assert-Equal $stats.Lost 1 'stats: one lost'
Assert-Equal $stats.Min 10 'stats: minimum'
Assert-Equal $stats.Avg 20 'stats: average'
Assert-Equal $stats.Max 30 'stats: maximum'
$allLost = Get-SelfXLatencyStats @($null, $null)
Assert-Equal $allLost.Lost 2 'stats: all lost'
Assert-Equal ($null -eq $allLost.Avg) $true 'stats: no average when all are lost'
$none = Get-SelfXLatencyStats @()
Assert-Equal $none.Sent 0 'stats: no samples'
$rounded = Get-SelfXLatencyStats @(1.4, 2.6)
Assert-Equal $rounded.Avg 2 'stats: average is rounded to whole milliseconds'

# --- texts and status -----------------------------------------------------------------------------
$good = ConvertTo-SelfXLatencyInfo ([pscustomobject]@{ Stats = (Get-SelfXLatencyStats @(10, 20, 30)); Skipped = $false })
Assert-Equal $good.Value '20 ms (min 10, max 30, 0 of 3 lost)' 'text: result'
Assert-Equal $good.Status '' 'status: no loss gives no status'
$partial = ConvertTo-SelfXLatencyInfo ([pscustomobject]@{ Stats = (Get-SelfXLatencyStats @(10, $null, 30)); Skipped = $false })
Assert-Equal $partial.Status 'Pending' 'status: partial loss is a warning'
$failed = ConvertTo-SelfXLatencyInfo ([pscustomobject]@{ Stats = (Get-SelfXLatencyStats @($null, $null, $null)); Skipped = $false })
Assert-Equal $failed.Value 'not reachable (3 of 3 failed)' 'text: all lost'
Assert-Equal $failed.Status 'Error' 'status: all lost is an error'
$skipped = ConvertTo-SelfXLatencyInfo ([pscustomobject]@{ Stats = (Get-SelfXLatencyStats @()); Skipped = $true })
Assert-Equal $skipped.Value 'not measured (time limit reached)' 'text: time limit'

# --- Network_Test_Config.xml ------------------------------------------------------------------------
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('SelfXNetworkTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($sandbox)
function Write-TestConfig([string]$Name, [string]$Xml) {
	$path = Join-Path $sandbox $Name
	[IO.File]::WriteAllText($path, $Xml, (New-Object Text.UTF8Encoding($false)))
	return $path
}
try {
	$shipped = Read-SelfXNetworkTestConfig -Path (Join-Path $PSScriptRoot 'Sources\Network_Test_Config.xml')
	Assert-Equal $shipped.Enabled $false 'shipped file: measurements are off'
	Assert-Equal @($shipped.Targets).Count 4 'shipped file: four Microsoft endpoints'
	Assert-Equal @($shipped.Targets | Where-Object { $_.Group -ne 'Microsoft' -or $_.Port -ne 443 }).Count 0 'shipped file: all in group Microsoft, TCP 443'
	Assert-Equal $shipped.Microsoft $true 'shipped file: Microsoft group is on'
	Assert-Equal $shipped.HostNames $true 'shipped file: host names are shown'
	Assert-Equal $shipped.Gateway $true 'shipped file: gateway is measured'
	Assert-Equal @($shipped.Errors).Count 0 'shipped file: no errors'
	Assert-Equal $shipped.Samples 3 'shipped file: three samples'
	Assert-Equal $shipped.TimeoutMs 2000 'shipped file: 2000 ms'

	$path = Write-TestConfig 'ok.xml' '<Network_Test_Config><Settings Enabled="True" Gateway="False" Samples="2" TimeoutMs="1500"/><Targets><Target Label="Intranet" Host="intranet.example.org" Port="443"/><Target Label="DNS only" Host="www.example.org"/><Target Label="Direct" Host="10.1.2.3" Port="80"/></Targets></Network_Test_Config>'
	$config = Read-SelfXNetworkTestConfig -Path $path
	Assert-Equal $config.Enabled $true 'config: enabled'
	Assert-Equal $config.Gateway $false 'config: gateway off'
	Assert-Equal $config.Samples 2 'config: samples'
	Assert-Equal $config.TimeoutMs 1500 'config: timeout'
	Assert-Equal @($config.Targets).Count 3 'config: three targets'
	Assert-Equal $config.Targets[0].Host 'intranet.example.org' 'config: host'
	Assert-Equal $config.Targets[0].Port 443 'config: port'
	Assert-Equal $config.Targets[1].Port 0 'config: no port means 0'
	Assert-Equal @($config.Errors).Count 0 'config: no errors'

	$path = Write-TestConfig 'lower.xml' '<Network_Test_Config><Settings Enabled="true"/></Network_Test_Config>'
	Assert-Equal (Read-SelfXNetworkTestConfig -Path $path).Enabled $true 'config: True in any letter case switches it on'
	$path = Write-TestConfig 'other.xml' '<Network_Test_Config><Settings Enabled="1"/></Network_Test_Config>'
	Assert-Equal (Read-SelfXNetworkTestConfig -Path $path).Enabled $false 'config: only True switches it on'
	$path = Write-TestConfig 'default-gateway.xml' '<Network_Test_Config><Settings Enabled="True"/></Network_Test_Config>'
	Assert-Equal (Read-SelfXNetworkTestConfig -Path $path).Gateway $true 'config: gateway is measured by default'

	$bad = '<Network_Test_Config><Settings Enabled="True" Samples="9" TimeoutMs="10"/><Targets>' +
		'<Target Label="" Host="a.example.org"/>' +
		'<Target Label="Bad host" Host="http://a.example.org"/>' +
		'<Target Label="Bad port" Host="a.example.org" Port="70000"/>' +
		'<Target Label="Twice" Host="a.example.org" Port="80"/>' +
		'<Target Label="Twice" Host="b.example.org" Port="80"/>' +
		'</Targets></Network_Test_Config>'
	$config = Read-SelfXNetworkTestConfig -Path (Write-TestConfig 'bad.xml' $bad)
	Assert-Equal $config.Samples 3 'config: invalid samples fall back to 3'
	Assert-Equal $config.TimeoutMs 2000 'config: invalid timeout falls back to 2000'
	Assert-Equal @($config.Targets).Count 1 'config: only the valid target is kept'
	Assert-Equal $config.Targets[0].Host 'a.example.org' 'config: the first of two equal labels is kept'
	Assert-Equal @($config.Errors).Count 6 'config: every invalid entry is named'
	$bad = '<Network_Test_Config><Settings Enabled="True"/><Targets><Target Label="Port text" Host="a.example.org" Port="https"/><Target Label="Bad;label" Host="a.example.org"/><Target Label="Fine" Host="a.example.org" Port="443"/></Targets></Network_Test_Config>'
	$config = Read-SelfXNetworkTestConfig -Path (Write-TestConfig 'bad2.xml' $bad)
	Assert-Equal @($config.Targets).Count 1 'config: a port that is not a number and a label with a semicolon are skipped'
	Assert-Equal @($config.Errors).Count 2 'config: both are named'

	$many = '<Network_Test_Config><Settings Enabled="True"/><Targets>' + ((1..14 | ForEach-Object { "<Target Label=`"T$_`" Host=`"h$_.example.org`"/>" }) -join '') + '</Targets></Network_Test_Config>'
	$config = Read-SelfXNetworkTestConfig -Path (Write-TestConfig 'many.xml' $many)
	Assert-Equal @($config.Targets).Count 12 'config: at most twelve targets'
	Assert-Equal @($config.Errors).Count 1 'config: the limit is reported'

	$grp = '<Network_Test_Config><Settings Enabled="True" Microsoft="False" HostNames="False"/><Targets>' +
		'<Target Label="A" Host="a.example.org" Port="443" Group="Company" Kind="Vpn"/>' +
		'<Target Label="B" Host="b.example.org" Port="443" Group="Company" Kind="Intranet"/>' +
		'<Target Label="C" Host="c.example.org" Port="443" Group="Microsoft"/>' +
		'<Target Label="D" Host="d.example.org" Port="443"/>' +
		'<Target Label="E" Host="e.example.org" Port="443" Group="company"/>' +
		'<Target Label="F" Host="f.example.org" Port="443" Group="Mars"/>' +
		'<Target Label="G" Host="g.example.org" Port="443" Group="Internet" Kind="Vpn"/>' +
		'<Target Label="H" Host="h.example.org" Port="443" Group="Company" Kind="Cable"/>' +
		'<Target Label="I" Host="i.example.org" Port="443" Kind="Vpn"/>' +
		'</Targets></Network_Test_Config>'
	$config = Read-SelfXNetworkTestConfig -Path (Write-TestConfig 'groups.xml' $grp)
	Assert-Equal $config.Microsoft $false 'config: Microsoft=False'
	Assert-Equal $config.HostNames $false 'config: HostNames=False'
	Assert-Equal (@($config.Targets | ForEach-Object { $_.Label }) -join ',') 'A,B,C,D' 'config: only valid groups and kinds are kept (names are case sensitive)'
	Assert-Equal $config.Targets[0].Group 'Company' 'config: group'
	Assert-Equal $config.Targets[0].Kind 'Vpn' 'config: kind Vpn'
	Assert-Equal $config.Targets[1].Kind 'Intranet' 'config: kind Intranet'
	Assert-Equal $config.Targets[3].Group '' 'config: a target without Group stays without Group'
	Assert-Equal @($config.Errors).Count 5 'config: wrong group, wrong case, Kind with another group, wrong kind and Kind without group are named'
	$dtd = '<!DOCTYPE x [<!ENTITY e "y">]><Network_Test_Config><Settings Enabled="True"/></Network_Test_Config>'
	$config = Read-SelfXNetworkTestConfig -Path (Write-TestConfig 'dtd.xml' $dtd)
	Assert-Equal $config.Enabled $false 'config: a DTD is refused, measurements stay off'
	Assert-Equal @($config.Errors).Count 1 'config: the DTD is reported'
	$config = Read-SelfXNetworkTestConfig -Path (Join-Path $sandbox 'missing.xml')
	Assert-Equal $config.Enabled $false 'config: missing file means off'
	$config = Read-SelfXNetworkTestConfig -Path (Write-TestConfig 'broken.xml' '<Network_Test_Config><Settings')
	Assert-Equal $config.Enabled $false 'config: broken XML means off'
	$config = Read-SelfXNetworkTestConfig -Path (Write-TestConfig 'nosettings.xml' '<Network_Test_Config/>')
	Assert-Equal $config.Enabled $false 'config: no Settings element means off'
}
finally { Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue }

# --- verdict (pure function) and group state ------------------------------------------------------------
Assert-Equal (Get-SelfXGroupState -Reached 0 -Failed 0) 'None' 'group state: nothing measured'
Assert-Equal (Get-SelfXGroupState -Reached 3 -Failed 0) 'Ok' 'group state: all reached'
Assert-Equal (Get-SelfXGroupState -Reached 1 -Failed 2) 'Partial' 'group state: some reached'
Assert-Equal (Get-SelfXGroupState -Reached 0 -Failed 2) 'Fail' 'group state: none reached'
$cases = @(
	# Local, Internet, Microsoft, Company, VpnExpected, expected
	@('Ok', 'Ok', 'Ok', 'Ok', $true, 'AllOk'),
	@('None', 'Ok', 'None', 'None', $true, 'AllOk'),
	@('None', 'None', 'None', 'None', $true, 'NoData'),
	@('Fail', 'Fail', 'Ok', 'Ok', $true, 'LocalDown'),
	@('Fail', 'None', 'None', 'None', $true, 'LocalDown'),
	@('Fail', 'Fail', 'Fail', 'Fail', $true, 'LocalDown'),
	@('Ok', 'Fail', 'Ok', 'Ok', $true, 'InternetDown'),
	@('None', 'Fail', 'None', 'Fail', $true, 'InternetDown'),
	@('Ok', 'Fail', 'Fail', 'Fail', $true, 'InternetDown'),
	@('Fail', 'Ok', 'Ok', 'Ok', $true, 'Partial'),
	@('Fail', 'Partial', 'Ok', 'Ok', $true, 'Partial'),
	@('Ok', 'Ok', 'Fail', 'Ok', $true, 'MicrosoftDown'),
	@('Ok', 'Ok', 'Fail', 'Fail', $true, 'MicrosoftDown'),
	@('Ok', 'Partial', 'Fail', 'Ok', $true, 'MicrosoftDown'),
	@('Ok', 'Ok', 'Ok', 'Fail', $true, 'CompanyVpn'),
	@('Ok', 'Ok', 'Ok', 'Fail', $false, 'CompanyIntranet'),
	@('None', 'Ok', 'None', 'Fail', $true, 'CompanyVpn'),
	@('Ok', 'Ok', 'None', 'Fail', $false, 'CompanyIntranet'),
	@('Ok', 'None', 'Ok', 'Fail', $true, 'Partial'),
	@('Ok', 'Ok', 'Partial', 'Ok', $true, 'Partial'),
	@('Ok', 'Ok', 'Ok', 'Partial', $true, 'Partial'),
	@('Ok', 'Partial', 'Ok', 'Ok', $true, 'Partial'),
	@('Partial', 'Ok', 'Ok', 'Ok', $true, 'Partial')
)
foreach ($case in $cases) {
	$verdict = Get-SelfXConnectionVerdict -Local $case[0] -Internet $case[1] -Microsoft $case[2] -Company $case[3] -CompanyVpnExpected $case[4]
	Assert-Equal $verdict $case[5] ("verdict: Local={0} Internet={1} Microsoft={2} Company={3} Vpn={4}" -f $case[0], $case[1], $case[2], $case[3], $case[4])
}
# all 256 combinations (with both values of the VPN flag): known Id, and rules that must hold for every one of them
$known = @('LocalDown', 'InternetDown', 'MicrosoftDown', 'CompanyVpn', 'CompanyIntranet', 'Partial', 'AllOk', 'NoData')
$states = @('Ok', 'Partial', 'Fail', 'None')
$combinations = 0
foreach ($l in $states) { foreach ($i in $states) { foreach ($m in $states) { foreach ($c in $states) { foreach ($vpn in $true, $false) {
	$combinations++
	$v = Get-SelfXConnectionVerdict -Local $l -Internet $i -Microsoft $m -Company $c -CompanyVpnExpected $vpn
	$label = "$l/$i/$m/$c/$vpn -> $v"
	if ($known -notcontains $v) { Assert-Equal $v 'a known Id' "verdict combination: $label" }
	$anyBad = (@($l, $i, $m, $c) -contains 'Fail') -or (@($l, $i, $m, $c) -contains 'Partial')
	if ($v -eq 'AllOk' -and $anyBad) { Assert-Equal $v 'not AllOk' "verdict combination: AllOk with a failure: $label" }
	if ($v -eq 'NoData' -and (@($l, $i, $m, $c) | Where-Object { $_ -ne 'None' })) { Assert-Equal $v 'not NoData' "verdict combination: NoData with a measurement: $label" }
	if ($i -eq 'Fail' -and $l -ne 'Fail' -and $v -ne 'InternetDown') { Assert-Equal $v 'InternetDown' "verdict combination: internet down is reported: $label" }
	if ($v -eq 'LocalDown' -and ($l -ne 'Fail' -or $i -eq 'Ok' -or $i -eq 'Partial')) { Assert-Equal $v 'not LocalDown' "verdict combination: LocalDown needs a failing gateway and no working internet: $label" }
	if ($v -in 'CompanyVpn', 'CompanyIntranet' -and ($c -ne 'Fail' -or $i -notin 'Ok', 'Partial')) { Assert-Equal $v 'not Company' "verdict combination: company verdict needs a working internet: $label" }
	if ($v -eq 'CompanyVpn' -and -not $vpn) { Assert-Equal $v 'CompanyIntranet' "verdict combination: Intranet flag: $label" }
} } } } }
Assert-Equal $combinations 512 'verdict: 256 state combinations with both VPN flags'
Assert-Equal (Get-SelfXVerdictStatus 'AllOk') 'OK' 'verdict status: all reachable'
Assert-Equal (Get-SelfXVerdictStatus 'Partial') 'Pending' 'verdict status: partial'
Assert-Equal (Get-SelfXVerdictStatus 'NoData') '' 'verdict status: nothing measured'
foreach ($errorId in 'LocalDown', 'InternetDown', 'MicrosoftDown', 'CompanyVpn', 'CompanyIntranet') { Assert-Equal (Get-SelfXVerdictStatus $errorId) 'Error' "verdict status: $errorId" }
Assert-Equal (Get-SelfXCheckStatus 'Ok') 'OK' 'check status: ok'
Assert-Equal (Get-SelfXCheckStatus 'Partial') 'Pending' 'check status: partial'
Assert-Equal (Get-SelfXCheckStatus 'Fail') 'Error' 'check status: fail'
Assert-Equal (Get-SelfXCheckStatus 'None') '' 'check status: none'
$rejected = $false
try { [void](Get-SelfXConnectionVerdict -Internet 'Maybe') } catch { $rejected = $true }
Assert-Equal $rejected $true 'verdict: an unknown state is refused'
foreach ($key in 'Check_Local', 'Check_Internet', 'Check_Microsoft', 'Check_Company', 'Check_Result', 'Check_State_Ok', 'Check_State_Partial', 'Check_State_Fail', 'Check_State_None') {
	Assert-Equal ($Script:SelfXInfoDefaultText.ContainsKey($key)) $true "texts: English default for $key"
}
foreach ($id in $known) { Assert-Equal ($Script:SelfXInfoDefaultText.ContainsKey("Verdict_$id")) $true "texts: English default for Verdict_$id" }

# --- measurements against this computer ---------------------------------------------------------------
$listener = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
try {
	$tcp = Measure-SelfXTcpLatency -Address '127.0.0.1' -Port $port -Samples 3 -TimeoutMs 2000
	Assert-Equal $tcp.Stats.Sent 3 'tcp: three samples'
	Assert-Equal $tcp.Stats.Lost 0 'tcp: an open port is reached every time'
	Assert-Equal $tcp.Skipped $false 'tcp: not skipped'
	$expired = Measure-SelfXTcpLatency -Address '127.0.0.1' -Port $port -Samples 3 -TimeoutMs 2000 -Deadline ([datetime]::UtcNow.AddSeconds(-1))
	Assert-Equal $expired.Stats.Sent 0 'tcp: nothing is measured after the deadline'
	Assert-Equal $expired.Skipped $true 'tcp: skipped after the deadline'

	$dns = Measure-SelfXDnsLatency -HostName 'localhost' -Samples 2 -TimeoutMs 3000
	Assert-Equal $dns.Stats.Sent 2 'dns: two samples'
	Assert-Equal $dns.Stats.Lost 0 'dns: localhost resolves'
	Assert-Equal ($dns.Address -in @('127.0.0.1', '::1')) $true 'dns: address of localhost'
	$noName = Measure-SelfXDnsLatency -HostName 'selfx-no-such-host.invalid' -Samples 1 -TimeoutMs 3000
	Assert-Equal $noName.Stats.Lost 1 'dns: a name that does not exist counts as lost'
	Assert-Equal ($null -eq $noName.Address) $true 'dns: no address for it'

	$ping = Measure-SelfXPingLatency -Address '127.0.0.1' -Samples 2 -TimeoutMs 1000
	Assert-Equal $ping.Stats.Sent 2 'ping: two samples (the result depends on the firewall)'

	# items. The first rows are the four group rows and the result; the detail rows are the measurements.
	$isDetail = { $_.Property -like 'Latency:*' -or $_.Property -like 'DNS lookup:*' -or $_.Property -like 'Connection:*' }
	$off = @(@(Get-SelfXNetworkMeasureItems -Category 'Network' -Config ([pscustomobject]@{ Enabled = $false; Gateway = $true; Samples = 1; TimeoutMs = 1000; Targets = @() }) -Gateways @('127.0.0.1')) | Where-Object $isDetail)
	Assert-Equal $off.Count 0 'items: nothing when switched off'
	Assert-Equal @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $null).Count 0 'items: nothing without a configuration'

	$target = [pscustomobject]@{ Label = 'Local'; Host = 'localhost'; Port = $port }
	$config = [pscustomobject]@{ Enabled = $true; Gateway = $true; Samples = 1; TimeoutMs = 2000; Targets = @($target) }
	$items = @(@(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -Gateways @('fe80::1', '127.0.0.1')) | Where-Object $isDetail)
	Assert-Equal $items.Count 3 'items: gateway, name lookup and connection'
	Assert-Equal $items[0].Property 'Latency: default gateway' 'items: gateway label'
	Assert-Equal $items[1].Property 'DNS lookup: Local' 'items: DNS label'
	Assert-Equal $items[2].Property 'Connection: Local' 'items: connection label'
	Assert-Equal $items[1].Category 'Network' 'items: category'
	Assert-Equal $items[2].Value.StartsWith("localhost:${port}: ") $true 'items: host and port are shown'
	Assert-Equal $items[2].Status '' 'items: a working connection has no status'

	$noGateway = @(@(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -Gateways @()) | Where-Object $isDetail)
	Assert-Equal $noGateway.Count 2 'items: without a gateway address the gateway line is missing'
	$config.Gateway = $false
	$noGateway = @(@(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -Gateways @('127.0.0.1')) | Where-Object $isDetail)
	Assert-Equal $noGateway.Count 2 'items: gateway switched off'

	$literal = [pscustomobject]@{ Enabled = $true; Gateway = $false; Samples = 1; TimeoutMs = 2000; Targets = @([pscustomobject]@{ Label = 'Direct'; Host = '127.0.0.1'; Port = $port }) }
	$items = @(@(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $literal) | Where-Object $isDetail)
	Assert-Equal $items.Count 1 'items: no name lookup for an IPv4 address'
	$noPort = [pscustomobject]@{ Enabled = $true; Gateway = $false; Samples = 1; TimeoutMs = 2000; Targets = @([pscustomobject]@{ Label = 'Name'; Host = 'localhost'; Port = 0 }) }
	$items = @(@(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $noPort) | Where-Object $isDetail)
	Assert-Equal $items.Count 1 'items: without a port only the name lookup'
	Assert-Equal $items[0].Property 'DNS lookup: Name' 'items: name lookup only'
	$unknown = [pscustomobject]@{ Enabled = $true; Gateway = $false; Samples = 1; TimeoutMs = 2000; Targets = @([pscustomobject]@{ Label = 'Gone'; Host = 'selfx-no-such-host.invalid'; Port = 443 }) }
	$items = @(@(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $unknown) | Where-Object $isDetail)
	Assert-Equal $items.Count 2 'items: unknown name gives two lines'
	Assert-Equal $items[0].Status 'Error' 'items: unknown name is an error'
	Assert-Equal $items[1].Status 'Error' 'items: no connection without an address'
	$late = @(@(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -DeadlineSeconds -5) | Where-Object $isDetail)
	Assert-Equal @($late | Where-Object { $_.Value -like '*: not measured (time limit reached)' }).Count 2 'items: time limit shows not measured'

	# group rows, verdict, order, host names, Microsoft switch
	$closedListener = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
	$closedListener.Start()
	$closedPort = ([Net.IPEndPoint]$closedListener.LocalEndpoint).Port
	$closedListener.Stop()
	function New-TestConfig($Targets, [bool]$HostNames = $true, [bool]$Microsoft = $true) {
		[pscustomobject]@{ Enabled = $true; Gateway = $false; Microsoft = $Microsoft; HostNames = $HostNames; Samples = 1; TimeoutMs = 2000; Targets = @($Targets) }
	}
	function New-TestTarget($Label, $HostName, $PortNumber, $Group = '', $Kind = '') { [pscustomobject]@{ Label = $Label; Host = $HostName; Port = $PortNumber; Group = $Group; Kind = $Kind } }
	$companyOk = New-TestTarget 'Company ok' '127.0.0.1' $port 'Company' 'Vpn'
	$companyDown = New-TestTarget 'Company down' '127.0.0.1' $closedPort 'Company' 'Vpn'
	$companyDownIntranet = New-TestTarget 'Share down' '127.0.0.1' $closedPort 'Company' 'Intranet'
	$msOk = New-TestTarget 'Ms ok' '127.0.0.1' $port 'Microsoft'
	$msDown = New-TestTarget 'Ms down' '127.0.0.1' $closedPort 'Microsoft'

	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyOk, $msOk)) -InternetTestReachable $true)
	Assert-Equal $all.Count 7 'check: four group rows, the result and two detail rows'
	Assert-Equal $all[0].Property 'Local network (Wi-Fi, router)' 'check: local row'
	Assert-Equal $all[0].Value 'not measured' 'check: local row without a measurement'
	Assert-Equal $all[0].Status '' 'check: not measured has no status'
	Assert-Equal $all[1].Property 'Internet' 'check: internet row'
	Assert-Equal $all[1].Value 'reachable (1 of 1)' 'check: the internet test counts as one target'
	Assert-Equal $all[1].Status 'OK' 'check: internet row is ok'
	Assert-Equal $all[2].Value 'reachable (1 of 1)' 'check: Microsoft row'
	Assert-Equal $all[3].Value 'reachable (1 of 1)' 'check: company row'
	Assert-Equal $all[4].Property 'Connection result' 'check: result row'
	Assert-Equal $all[4].Value 'Everything can be reached.' 'check: everything reachable'
	Assert-Equal $all[4].Status 'OK' 'check: the result is ok'

	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyDown)) -InternetTestReachable $true)
	Assert-Equal $all[3].Value 'not reachable (0 of 1)' 'check: company row when the port is closed'
	Assert-Equal $all[3].Status 'Error' 'check: company row is an error'
	Assert-Equal $all[4].Value 'The internet works, but the company network cannot be reached: check the VPN.' 'check: VPN hint'
	Assert-Equal $all[4].Status 'Error' 'check: the VPN result is an error'
	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyDownIntranet)) -InternetTestReachable $true)
	Assert-Equal $all[4].Value 'The internet works, but the company network cannot be reached: check the network connection at your location.' 'check: Kind Intranet gives the location hint'
	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyDownIntranet, $companyDown)) -InternetTestReachable $true)
	Assert-Equal $all[4].Value 'The internet works, but the company network cannot be reached: check the VPN.' 'check: one failing VPN target is enough for the VPN hint'
	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyOk, $companyDown)) -InternetTestReachable $true)
	Assert-Equal $all[3].Value 'partly reachable (1 of 2)' 'check: partly reachable'
	Assert-Equal $all[3].Status 'Pending' 'check: partly reachable is a warning'
	Assert-Equal $all[4].Value 'Most connections work, but some targets cannot be reached.' 'check: partial result'
	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($msDown)) -InternetTestReachable $true)
	Assert-Equal $all[4].Value 'The internet works, but the Microsoft services for the management of this device cannot be reached.' 'check: Microsoft result'
	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyDown, $msDown)) -InternetTestReachable $false)
	Assert-Equal $all[4].Value 'The internet cannot be reached.' 'check: no internet'
	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @()) -InternetTestReachable $null)
	Assert-Equal $all[4].Value 'Nothing could be measured.' 'check: nothing measured'
	Assert-Equal $all[4].Status '' 'check: nothing measured has no status'
	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @((New-TestTarget 'Free' '127.0.0.1' $closedPort))) -InternetTestReachable $true)
	Assert-Equal $all[4].Value 'Everything can be reached.' 'check: a target without Group does not count for the result'
	Assert-Equal @($all | Where-Object $isDetail).Count 1 'check: a target without Group is still measured'

	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyDown, $msDown) -Microsoft $false) -InternetTestReachable $true)
	Assert-Equal $all.Count 5 'Microsoft switched off: no Microsoft row and no Microsoft measurement (three group rows, the result, one detail row)'
	Assert-Equal @($all | Where-Object { $_.Property -like '*Ms down*' }).Count 0 'Microsoft switched off: no detail row for a Microsoft target'

	$all = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyOk, $msOk)) -InternetTestReachable $true)
	$detailRows = @($all | Where-Object $isDetail)
	Assert-Equal $detailRows[0].Property 'Connection: Ms ok' 'order: Microsoft is measured before Company even if the file lists it later'
	$hidden = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyOk) -HostNames $false) -InternetTestReachable $true)
	$hiddenDetail = @($hidden | Where-Object $isDetail)
	Assert-Equal ($hiddenDetail[0].Value -like '*127.0.0.1*') $false 'HostNames=False: no host name in the row'
	Assert-Equal ($hiddenDetail[0].Value -like '*ms*') $true 'HostNames=False: the result is still shown'
	$shown = @(@(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig @($companyOk)) -InternetTestReachable $true) | Where-Object $isDetail)
	Assert-Equal ($shown[0].Value -like "127.0.0.1:${port}: *") $true 'HostNames=True: host name and port in the row'
	$many = @(1..12 | ForEach-Object { New-TestTarget "T$_" '127.0.0.1' $closedPort 'Company' })
	$sw = [Diagnostics.Stopwatch]::StartNew()
	$timed = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config (New-TestConfig $many) -InternetTestReachable $true -DeadlineSeconds 15)
	$sw.Stop()
	Assert-Equal ($sw.Elapsed.TotalSeconds -lt 20) $true 'time limit: twelve targets finish within the limit'
	Assert-Equal (@($timed | Where-Object $isDetail).Count) 12 'time limit: twelve detail rows'
}
finally { $listener.Stop() }

# --- the collector takes the configuration path; the file has no write or download calls -----------------
$cmd = Get-Command Get-SelfXSystemInfo
Assert-Equal $cmd.Parameters.ContainsKey('NetworkTestConfigPath') $true 'Get-SelfXSystemInfo has NetworkTestConfigPath'
$text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sources\SystemInfo.ps1'))
foreach ($pattern in 'Start-Process', 'Invoke-Expression', '\biex\b', 'Set-ItemProperty', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Add-Type') {
	Assert-Equal ($text -match $pattern) $false "SystemInfo.ps1 does not use $pattern"
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
