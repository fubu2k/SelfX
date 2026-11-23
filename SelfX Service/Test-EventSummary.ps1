<#
.SYNOPSIS
    Tests the event log summary of the log collector (counts per provider and event id, no message text).

.DESCRIPTION
    Takes the function Get-EventCountSummary out of Sources\Scripts_to_run\Collect-DeviceLogs.ps1 (the collector itself is
    never run) and runs it with a simulated Get-WinEvent. Checks the counting per provider, event id and level, the
    order, the limit of the lines, the cleaning of provider names, that no message text reaches the report, the case
    without events and the note when the number of events is capped. Nothing is read from the device and no file is
    written. Runs in PowerShell 7 and Windows PowerShell 5.1:
    pwsh -NoProfile -File .\Test-EventSummary.ps1

.NOTES
    Name    : Test-EventSummary.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 2.8.17
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.17   2026-11-23  fubu2k               Initial version (event log summary in the device logs report).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}

$collector = Join-Path $PSScriptRoot 'Sources\Scripts_to_run\Collect-DeviceLogs.ps1'
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { $collector = Join-Path $PSScriptRoot 'Sources/Scripts_to_run/Collect-DeviceLogs.ps1' }
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($collector, [ref]$tokens, [ref]$parseErrors)
Assert-Equal @($parseErrors).Count 0 'Collect-DeviceLogs.ps1 parses'
$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-EventCountSummary' }, $true)
Assert-Equal ($null -ne $definition) $true 'Collect-DeviceLogs.ps1 defines Get-EventCountSummary'
if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
. ([scriptblock]::Create($definition.Extent.Text))

# Simulated Get-WinEvent: records the filter and returns the prepared events (with a message that must never be shown).
$script:filter = $null
$script:fakeEvents = @()
function Get-WinEvent {
	param($FilterHashtable, $MaxEvents, $ErrorAction)
	$script:filter = $FilterHashtable
	return @($script:fakeEvents | Select-Object -First $MaxEvents)
}
function New-FakeEvent($Provider, $Id, $Level, [datetime]$Time) {
	[pscustomobject]@{ ProviderName = $Provider; Id = $Id; Level = $Level; TimeCreated = $Time; Message = 'SECRET-MESSAGE C:\Users\alice\file.docx alice@contoso.com' }
}
$base = [datetime]'2026-11-20 08:00:00'

# 1. Counting, order and format
$script:fakeEvents = @(
	(New-FakeEvent 'Disk' 7 2 $base.AddHours(1)), (New-FakeEvent 'Disk' 7 2 $base.AddHours(5)), (New-FakeEvent 'Disk' 7 2 $base.AddHours(3)),
	(New-FakeEvent 'Schannel' 36887 2 $base.AddHours(2)),
	(New-FakeEvent 'Disk' 7 3 $base.AddHours(4)),
	(New-FakeEvent 'Microsoft-Windows-DNS-Client' 1014 3 $base.AddHours(6)), (New-FakeEvent 'Microsoft-Windows-DNS-Client' 1014 3 $base.AddHours(7))
)
$out = @(Get-EventCountSummary -LogName 'System' -Days 3)
Assert-Equal $out[0] '--- System (levels 1,2,3, counted per provider and event id, no messages; 7 events, last 3 days)' 'header line'
Assert-Equal $out.Count 5 'one line per provider, event id and level plus the header'
Assert-Equal $out[1] '        3x  id=7 lvl=Error Disk  (first 2026-11-20 09:00, last 2026-11-20 13:00)' 'most frequent first, first and last time'
Assert-Equal ($out[2] -like '        2x  id=1014 lvl=Warning Microsoft-Windows-DNS-Client*') $true 'second group'
Assert-Equal ($out[3] -like '        1x  id=36887 lvl=Error Schannel*' -or $out[4] -like '        1x  id=36887 lvl=Error Schannel*') $true 'single event is listed'
Assert-Equal ($out[4] -like '        1x  id=7 lvl=Warning Disk*' -or $out[3] -like '        1x  id=7 lvl=Warning Disk*') $true 'the level is part of the group'

# 2. Filter: log, levels and time window
Assert-Equal $script:filter['LogName'] 'System' 'filter: log name'
Assert-Equal ($script:filter['Level'] -join ',') '1,2,3' 'filter: critical, error and warning'
Assert-Equal ((Get-Date) - $script:filter['StartTime'] -gt [timespan]::FromDays(2.9) -and (Get-Date) - $script:filter['StartTime'] -lt [timespan]::FromDays(3.1)) $true 'filter: time window of the days'

# 3. No message text, no user data
Assert-Equal (($out -join "`n") -match 'SECRET|alice|contoso|C:\\') $false 'no message text in the summary'

# 4. Limit of the lines and provider names
$script:fakeEvents = @(1..30 | ForEach-Object { New-FakeEvent "Provider$_" $_ 2 $base })
Assert-Equal @(Get-EventCountSummary -LogName 'Application' -Top 15).Count 16 'at most Top lines plus the header'
$script:fakeEvents = @((New-FakeEvent ("Evil`r`nInjected <b>line</b> " + ('x' * 200)) 1 2 $base))
$line = @(Get-EventCountSummary -LogName 'Application')[1]
Assert-Equal ($line -match "[\r\n<>]") $false 'provider name: no line break, no markup characters'
Assert-Equal ($line.Length -lt 200) $true 'provider name: shortened'
Assert-Equal @(Get-EventCountSummary -LogName 'Application').Count 2 'provider name with a line break stays one line'

# 5. No events and capped number of events
$script:fakeEvents = @()
$out = @(Get-EventCountSummary -LogName 'Application' -Days 7)
Assert-Equal "$($out[0])|$($out[1])" '--- Application (levels 1,2,3, counted per provider and event id, no messages; 0 events, last 7 days)|    (none)' 'no events'
$script:fakeEvents = @(1..10 | ForEach-Object { New-FakeEvent 'Disk' 7 2 $base })
$out = @(Get-EventCountSummary -LogName 'System' -MaxEvents 10)
Assert-Equal ($out[0] -like '*; only the newest 10 events counted)') $true 'capped: note in the header'
Assert-Equal ($out[1] -like '       10x  id=7 lvl=Error Disk*') $true 'capped: count of the events read'

# 6. The collector uses it in section 8 and does not print messages in the summary calls
$text = [IO.File]::ReadAllText($collector)
Assert-Equal ($text -match "(?s)Add-Section ""8\. Event logs.*?Get-EventCountSummary -LogName \`$summaryLog -Days \`$Days") $true 'section 8 calls the summary for its logs'
Assert-Equal ($text -match 'Get-EventCountSummary[^\r\n]*-MessageLike') $false 'the summary never filters or prints messages'

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $script:checks checks failed."
	exit 1
}
Write-Output "PASS: $script:checks checks. The event log summary counts per provider and event id and never shows message text."
exit 0
