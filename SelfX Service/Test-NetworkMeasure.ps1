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
    Version : 2.8.8

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.8    2026-11-22  fubu2k               Initial version
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
	Assert-Equal @($shipped.Targets).Count 0 'shipped file: no targets'
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

	$many = '<Network_Test_Config><Settings Enabled="True"/><Targets>' + ((1..7 | ForEach-Object { "<Target Label=`"T$_`" Host=`"h$_.example.org`"/>" }) -join '') + '</Targets></Network_Test_Config>'
	$config = Read-SelfXNetworkTestConfig -Path (Write-TestConfig 'many.xml' $many)
	Assert-Equal @($config.Targets).Count 5 'config: at most five targets'
	Assert-Equal @($config.Errors).Count 1 'config: the limit is reported'

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

	# items
	$off = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config ([pscustomobject]@{ Enabled = $false; Gateway = $true; Samples = 1; TimeoutMs = 1000; Targets = @() }) -Gateways @('127.0.0.1'))
	Assert-Equal $off.Count 0 'items: nothing when switched off'
	Assert-Equal @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $null).Count 0 'items: nothing without a configuration'

	$target = [pscustomobject]@{ Label = 'Local'; Host = 'localhost'; Port = $port }
	$config = [pscustomobject]@{ Enabled = $true; Gateway = $true; Samples = 1; TimeoutMs = 2000; Targets = @($target) }
	$items = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -Gateways @('fe80::1', '127.0.0.1'))
	Assert-Equal $items.Count 3 'items: gateway, name lookup and connection'
	Assert-Equal $items[0].Property 'Latency: default gateway' 'items: gateway label'
	Assert-Equal $items[1].Property 'DNS lookup: Local' 'items: DNS label'
	Assert-Equal $items[2].Property 'Connection: Local' 'items: connection label'
	Assert-Equal $items[1].Category 'Network' 'items: category'
	Assert-Equal $items[2].Value.StartsWith("localhost:${port}: ") $true 'items: host and port are shown'
	Assert-Equal $items[2].Status '' 'items: a working connection has no status'

	$noGateway = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -Gateways @())
	Assert-Equal $noGateway.Count 2 'items: without a gateway address the gateway line is missing'
	$config.Gateway = $false
	$noGateway = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -Gateways @('127.0.0.1'))
	Assert-Equal $noGateway.Count 2 'items: gateway switched off'

	$literal = [pscustomobject]@{ Enabled = $true; Gateway = $false; Samples = 1; TimeoutMs = 2000; Targets = @([pscustomobject]@{ Label = 'Direct'; Host = '127.0.0.1'; Port = $port }) }
	$items = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $literal)
	Assert-Equal $items.Count 1 'items: no name lookup for an IPv4 address'
	$noPort = [pscustomobject]@{ Enabled = $true; Gateway = $false; Samples = 1; TimeoutMs = 2000; Targets = @([pscustomobject]@{ Label = 'Name'; Host = 'localhost'; Port = 0 }) }
	$items = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $noPort)
	Assert-Equal $items.Count 1 'items: without a port only the name lookup'
	Assert-Equal $items[0].Property 'DNS lookup: Name' 'items: name lookup only'
	$unknown = [pscustomobject]@{ Enabled = $true; Gateway = $false; Samples = 1; TimeoutMs = 2000; Targets = @([pscustomobject]@{ Label = 'Gone'; Host = 'selfx-no-such-host.invalid'; Port = 443 }) }
	$items = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $unknown)
	Assert-Equal $items.Count 2 'items: unknown name gives two lines'
	Assert-Equal $items[0].Status 'Error' 'items: unknown name is an error'
	Assert-Equal $items[1].Status 'Error' 'items: no connection without an address'
	$late = @(Get-SelfXNetworkMeasureItems -Category 'Network' -Config $config -DeadlineSeconds -5)
	Assert-Equal @($late | Where-Object { $_.Value -like '*: not measured (time limit reached)' }).Count 2 'items: time limit shows not measured'
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
