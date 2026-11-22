<#
.SYNOPSIS
    Tests the collection of the facts for Copilot Chat (Sources\CopilotFacts.ps1), the configuration keys and the
    hand-over in the window (static checks of Self_X.ps1).

.DESCRIPTION
    Reads only local values (registry, drives, files of the package) and changes nothing. All names, addresses and
    identifiers in this test are invented examples.

.NOTES
    Name    : Test-CopilotFacts.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.12

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.10   2026-11-22  fubu2k               Initial version
    2.8.11   2026-11-22  fubu2k               Company apps row without app names, network facts, note text
    2.8.12   2026-11-22  fubu2k               Prompt texts in the language files (en, de), same text as the built-in fallback
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ($Actual -ne $Expected) { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}
$sources = Join-Path $PSScriptRoot 'Sources'
. (Join-Path $sources 'CopilotPrompt.ps1')
. (Join-Path $sources 'CopilotFacts.ps1')

# --- Status rows from the health items of the window ---------------------------------------------------------
$items = @(
	[pscustomobject]@{ Category = 'Health'; Property = 'Defender'; Value = 'OK - Signatures current'; Status = 'OK'; HealthId = 'Defender'; HealthName = ''; Detail = 'Signatures current' },
	[pscustomobject]@{ Category = 'Health'; Property = 'Disk'; Value = 'Error - 96 % used'; Status = 'Error'; HealthId = 'Disk'; HealthName = 'C:'; Detail = '96 % used' },
	[pscustomobject]@{ Category = 'Health'; Property = 'Sync'; Value = 'Error - contact to mail.fabrikam.example failed'; Status = 'error'; HealthId = 'IntuneSync'; HealthName = ''; Detail = 'contact to mail.fabrikam.example failed' },
	[pscustomobject]@{ Category = 'Health'; Property = 'Odd'; Value = 'x'; Status = 'Strange'; HealthId = 'Odd'; HealthName = ''; Detail = 'x' },
	[pscustomobject]@{ Category = 'Health'; Property = 'Bad id'; Value = 'x'; Status = 'OK'; HealthId = 'bad id; rm'; HealthName = ''; Detail = 'x' },
	[pscustomobject]@{ Category = 'Device'; Property = 'Computer name'; Value = 'PC-ANNA-01'; Status = '' },
	[pscustomobject]@{ Category = 'User'; Property = 'User name'; Value = 'anna.beispiel'; Status = ''; HealthId = ''; HealthName = ''; Detail = '' }
)
$rows = @(ConvertTo-SelfXCopilotStatusRows -HealthItems $items)
Assert-Equal $rows.Count 4 'status rows: items without a valid check id are skipped (information items, bad id, empty id)'
Assert-Equal $rows[0].Name 'Defender' 'status rows: name is the technical id'
Assert-Equal $rows[1].Name 'Disk (C:)' 'status rows: name with the check name'
Assert-Equal ($rows[2].State -ceq 'Error') $true 'status rows: state is normalised (error -> Error)'
Assert-Equal $rows[3].State 'Unknown' 'status rows: an unknown state becomes Unknown'
Assert-Equal @(ConvertTo-SelfXCopilotStatusRows -HealthItems @()).Count 0 'status rows: empty input'
Assert-Equal @(ConvertTo-SelfXCopilotStatusRows -HealthItems @($null)).Count 0 'status rows: null item'
$many = @(1..60 | ForEach-Object { [pscustomobject]@{ Status = 'OK'; HealthId = "Check$_"; HealthName = ''; Detail = '' } })
Assert-Equal @(ConvertTo-SelfXCopilotStatusRows -HealthItems $many).Count 40 'status rows: at most 40 rows'

# --- Company apps without app names ----------------------------------------------------------------------------
$appItems = @([pscustomobject]@{ Category = 'Health'; Property = 'Apps'; Value = 'x'; Status = 'Error'; HealthId = 'Applications'; HealthName = ''; Detail = '1 of 3 app(s) could not be installed: Contoso Teams Plugin (error 0x87D1041C).' })
$withNames = @(ConvertTo-SelfXCopilotStatusRows -HealthItems $appItems -IncludeAppNames $true)
$withoutNames = @(ConvertTo-SelfXCopilotStatusRows -HealthItems $appItems -IncludeAppNames $false)
Assert-Equal ($withNames[0].Detail -like '*Contoso Teams Plugin*') $true 'apps row: details with app names by default'
Assert-Equal $withoutNames.Count 1 'apps row: the row stays without app names'
Assert-Equal $withoutNames[0].State 'Error' 'apps row: the state stays without app names'
Assert-Equal $withoutNames[0].Detail '' 'apps row: no details (app names) with Copilot_Include_AppNames = False'
$otherItems = @([pscustomobject]@{ Status = 'Error'; HealthId = 'Disk'; HealthName = 'C:'; Detail = '96 % used' })
$otherRows = @(ConvertTo-SelfXCopilotStatusRows -HealthItems $otherItems -IncludeAppNames $false)
Assert-Equal $otherRows[0].Detail '96 % used' 'apps row: other rows keep their details'
$noNames = Get-SelfXCopilotFacts -HealthItems $appItems -IncludeAppNames $false
$noNamesPrompt = New-SelfXCopilotPrompt -Facts $noNames -Audience User -Language 'en' -IncludeAppNames $false
Assert-Equal ($noNamesPrompt -match 'Contoso|Teams Plugin') $false 'apps row: no app name in the prompt with Copilot_Include_AppNames = False'
Assert-Equal ($noNamesPrompt -like '*- Applications: Error*') $true 'apps row: the row itself is in the prompt'

# --- Network facts -----------------------------------------------------------------------------------------------
$net = ConvertTo-SelfXCopilotNetworkFacts -Connections ([pscustomobject]@{ Lan = $true; WiFi = $false; Wwan = $false }) -Vpn $true -ProxySettings ([pscustomobject]@{ ProxyEnable = 1; ProxyServer = 'proxy.fabrikam.example:8080'; AutoConfigURL = '' })
Assert-Equal (($net.Connection -join ',') -ceq 'LAN,VPN') $true 'network: LAN and VPN'
Assert-Equal ($net.Proxy -ceq 'Manual') $true 'network: manual proxy'
$net2 = ConvertTo-SelfXCopilotNetworkFacts -Connections ([pscustomobject]@{ Lan = $false; WiFi = $true; Wwan = $true }) -Vpn $false -ProxySettings ([pscustomobject]@{ ProxyEnable = 0; ProxyServer = 'x:1'; AutoConfigURL = 'https://pac.fabrikam.example/proxy.pac' })
Assert-Equal (($net2.Connection -join ',') -ceq 'Wi-Fi,Mobile') $true 'network: Wi-Fi and mobile'
Assert-Equal ($net2.Proxy -ceq 'Script') $true 'network: proxy script'
$net3 = ConvertTo-SelfXCopilotNetworkFacts -Connections ([pscustomobject]@{ Lan = $false; WiFi = $false; Wwan = $false }) -Vpn $false -ProxySettings ([pscustomobject]@{ ProxyEnable = 0; ProxyServer = ''; AutoConfigURL = '' })
Assert-Equal ($net3.ContainsKey('Connection')) $false 'network: no connection kinds when nothing is connected'
Assert-Equal ($net3.Proxy -ceq 'None') $true 'network: no proxy'
$net4 = ConvertTo-SelfXCopilotNetworkFacts -Connections $null -Vpn $false -ProxySettings $null
Assert-Equal ($net4.ContainsKey('Proxy')) $false 'network: unreadable proxy settings are left out'
$netPrompt = New-SelfXCopilotPrompt -Facts $net -Audience User -Language 'en'
Assert-Equal ($netPrompt -like '*Network: LAN + VPN, proxy manual*') $true 'network: line in the prompt'
Assert-Equal ($netPrompt -match 'fabrikam|8080') $false 'network: no proxy address in the prompt'

# --- Facts ---------------------------------------------------------------------------------------------------
$facts = Get-SelfXCopilotFacts -HealthItems $items -SelfXVersion '2.8.10' -Language 'de'
$allowed = @('WindowsEdition', 'WindowsVersion', 'WindowsBuild', 'SelfXVersion', 'Language', 'UptimeDays', 'Disks', 'Status', 'Connection', 'Proxy')
$unknown = @($facts.Keys | Where-Object { $_ -notin $allowed })
Assert-Equal $unknown.Count 0 'facts: only keys of the positive list'
Assert-Equal $facts.SelfXVersion '2.8.10' 'facts: SelfX version'
Assert-Equal $facts.Language 'de' 'facts: language'
Assert-Equal @($facts.Status).Count 4 'facts: status rows'
foreach ($disk in @($facts.Disks)) {
	Assert-Equal ("$($disk.Drive)" -match '^[A-Z]:$') $true "facts: drive '$($disk.Drive)' is a drive letter only"
	Assert-Equal (($disk.UsedPercent -ge 0) -and ($disk.UsedPercent -le 100)) $true 'facts: percent used between 0 and 100'
}
if ($facts.ContainsKey('UptimeDays')) { Assert-Equal ($facts.UptimeDays -ge 0) $true 'facts: uptime is not negative' }

# --- Facts to prompt (end to end) -----------------------------------------------------------------------------
$context = @{ ComputerName = 'PC-ANNA-01'; UserName = 'anna.beispiel'; DomainName = @('CONTOSO', 'contoso.example') }
$prompt = New-SelfXCopilotPrompt -Facts $facts -Description 'Teams hakt, mein Laptop PC-ANNA-01 ist langsam. anna.beispiel@contoso.example' -Context $context -Audience User -Language 'de'
Assert-Equal ($prompt -match 'fabrikam') $false 'prompt: host name of a status detail is replaced'
Assert-Equal ($prompt -match 'anna|PC-ANNA') $false 'prompt: user and device names are replaced'
Assert-Equal ($prompt -like '*- Defender: OK*') $true 'prompt: status row is present'
Assert-Equal ($prompt -like '*- IntuneSync: Error*') $true 'prompt: error status row is present'
Assert-Equal ($prompt.Length -le 6000) $true 'prompt: length limit'

# --- Configuration -------------------------------------------------------------------------------------------
[xml]$config = [IO.File]::ReadAllText((Join-Path $sources 'Tool_Config.xml'))
Assert-Equal "$($config.GUI_Config.Copilot_Enabled)" 'False' 'config: Copilot_Enabled is off by default'
Assert-Equal "$($config.GUI_Config.Copilot_Url)" 'https://m365.cloud.microsoft/chat' 'config: default address'
Assert-Equal (Test-SelfXCopilotUrl "$($config.GUI_Config.Copilot_Url)") $true 'config: default address passes the address check'
Assert-Equal "$($config.GUI_Config.Copilot_Audience)" 'User' 'config: audience User by default'
Assert-Equal "$($config.GUI_Config.Copilot_Include_AppNames)" 'True' 'config: app names are included by default'

# --- Texts in all language files -----------------------------------------------------------------------------
$keys = @('Copilot_Row_Label', 'Copilot_Row_Text', 'Copilot_Button', 'Copilot_Window_Title', 'Copilot_Intro_Text', 'Copilot_Description_Label', 'Copilot_Preview_Label', 'Copilot_Preview_Button', 'Copilot_Target_Text', 'Copilot_Open_Button', 'Copilot_Opened_Text', 'Copilot_Error_Text', 'Copilot_Warning_Text')
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $sources 'Languages') -Filter '*.xml') {
	[xml]$lang = [IO.File]::ReadAllText($file.FullName)
	foreach ($key in $keys) {
		$node = $lang.SelectSingleNode("//UI/$key")
		Assert-Equal (($null -ne $node) -and (-not [string]::IsNullOrWhiteSpace($node.InnerText))) $true "language $($file.BaseName): text $key exists"
		if ($key -in @('Copilot_Target_Text', 'Copilot_Error_Text') -and $node) { Assert-Equal ($node.InnerText -match '\{0\}') $true "language $($file.BaseName): $key keeps the placeholder {0}" }
	}
}

$ui = [IO.File]::ReadAllText((Join-Path $sources 'Self_X.ps1'))

# --- Prompt texts in the language files ------------------------------------------------------------------------
# The built-in text is the fallback; the language file is shown and used first. Both must say the same.
function ConvertTo-PromptNormal([string]$Text) { return ((($Text -split '\r?\n' | ForEach-Object { $_.Trim() }) -join "`n").Trim()) }
foreach ($pair in @(@('en', 'en'), @('de', 'de'))) {
	[xml]$promptLang = [IO.File]::ReadAllText((Join-Path $sources "Languages\$($pair[0]).xml"))
	foreach ($audience in @('User', 'Admin')) {
		$node = $promptLang.SelectSingleNode("//UI/Copilot_Prompt_$audience")
		Assert-Equal ($null -ne $node) $true "language $($pair[0]): Copilot_Prompt_$audience exists"
		if ($null -eq $node) { continue }
		$fileText = ConvertTo-PromptNormal $node.InnerText
		Assert-Equal ([regex]::Matches($fileText, '\{DATA\}').Count) 1 "language $($pair[0]): Copilot_Prompt_$audience contains {DATA} once"
		Assert-Equal ($fileText -like '*BEGIN DATA*END DATA*') $true "language $($pair[0]): Copilot_Prompt_$audience names the data block markers"
		Assert-Equal ($fileText.Length -le 3000) $true "language $($pair[0]): Copilot_Prompt_$audience has at most 3000 characters"
		if ($pair[0] -ceq 'en') { Assert-Equal ($fileText -like '*Answer in the language of the problem description*') $true "language $($pair[0]): Copilot_Prompt_$audience asks for the answer language" }
		Assert-Equal ($fileText -ceq (ConvertTo-PromptNormal (Get-SelfXCopilotTemplate -Audience $audience -Language $pair[1]))) $true "language $($pair[0]): Copilot_Prompt_$audience equals the built-in fallback text"
	}
}
Assert-Equal ($ui -match 'Get-SelfXString \$\(If\(\$Copilot_Audience -eq ''Admin''\) \{ ''Copilot_Prompt_Admin'' \} Else \{ ''Copilot_Prompt_User'' \}\)') $true 'window: the prompt text comes from the language file by audience'
Assert-Equal ($ui -match 'New-SelfXCopilotPrompt [^\r\n]*-Template \$Template') $true 'window: the text is passed to the prompt builder'

# --- Static checks: nothing is sent, only the configured address is opened -------------------------------------
$factsCode = [IO.File]::ReadAllText((Join-Path $sources 'CopilotFacts.ps1'))
foreach ($pattern in @('Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Invoke-Expression', 'Set-Content', 'Out-File', 'Add-Content', 'Set-Clipboard', 'New-Object System.Net')) {
	Assert-Equal ($factsCode -match [regex]::Escape($pattern)) $false "CopilotFacts.ps1 does not use $pattern"
}
$start = $ui.IndexOf('Function Show-SelfXCopilotDialog')
$end = $ui.IndexOf('Function Show-SelfXHelpDialog')
Assert-Equal (($start -ge 0) -and ($end -gt $start)) $true 'window: Copilot dialog found'
if (($start -ge 0) -and ($end -gt $start)) {
	$dialog = $ui.Substring($start, $end - $start)
	$starts = [regex]::Matches($dialog, 'Start-Process\s+(\S+)')
	Assert-Equal $starts.Count 1 'window: the Copilot dialog starts exactly one process'
	Assert-Equal $starts[0].Groups[1].Value '$Copilot_Url' 'window: it opens only the address from the configuration'
	Assert-Equal ($dialog -match 'Test-SelfXCopilotUrl \$Copilot_Url\)') $true 'window: the address is checked again before it is opened'
	foreach ($pattern in @('Invoke-WebRequest', 'Invoke-RestMethod', 'Invoke-Expression', 'Send-MailMessage', 'Write-SelfXLog "[^"]*\$Text')) {
		Assert-Equal ($dialog -match $pattern) $false "window: the Copilot dialog does not use $pattern (no text in the log)"
	}
}
Assert-Equal ($ui -match 'Get-SelfXCopilotFacts [^\r\n]*-IncludeAppNames \$Copilot_AppNames') $true 'window: the setting Copilot_Include_AppNames is passed to the facts'
Assert-Equal ($ui -match "FindName\('CopilotWarning'\)\.Text = Get-SelfXString 'Copilot_Warning_Text'") $true 'window: the note for the user is shown'
Assert-Equal ($ui -match '\$Copilot_Available = \(\(Get-SelfXText "Copilot_Enabled" "False"\) -eq ''True''\) -and \(Test-SelfXCopilotUrl \$Copilot_Url\)') $true 'window: the button needs Copilot_Enabled and a valid address'

if ($script:errors.Count) {
	foreach ($e in $script:errors) { [Console]::Out.WriteLine("FAIL: $e") }
	[Console]::Out.WriteLine("Test-CopilotFacts: $($script:errors.Count) of $($script:checks) checks failed.")
	exit 1
}
[Console]::Out.WriteLine("Test-CopilotFacts: all $($script:checks) checks passed.")
