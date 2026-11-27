<#
.SYNOPSIS
    Tests tools\Get-SelfXAsrEvents.ps1 (read-only view of the Defender ASR events of the prevalence rule) and the texts about it.

.DESCRIPTION
    Isolated: the event log is replaced by synthetic events (the function Read-SelfXAsrLog of the script is replaced in the test), the
    registry and the log of the device are not read, nothing is written outside the system temp folder, nothing is sent. Checks:
      - static: the script parses, uses no syntax of PowerShell 7 only, calls only read-only commands, has no parameter that names a
        log, a computer or a file, reads XML without DTD;
      - behavior: only the one rule, Block and Audit, upper and lower case ID, other rules left out, unreadable events counted and
        reported (not hidden), XML with DTD or entity rejected, no user name in the output (also from the fields that must not be
        read), profile folders hidden, control characters removed, filter for the SelfX folder, limit and order, error handling of
        the log (no events, log missing, access denied);
      - texts: the documentation (English and German) and the texts of the wizard name the rule and exactly the four SelfX files.
    On Windows it also calls the real log once (read only) to check the call itself. Works in Windows PowerShell 5.1 and PowerShell 7.

.NOTES
    Name    : Test-SelfXAsrEvents.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 3.1.0
    Exit code: 0 = all tests passed, 1 = at least one failed

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version
#>
$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$Target = Join-Path $ScriptFolder 'Get-SelfXAsrEvents.ps1'
$hostExe = (Get-Process -Id $PID).Path
$onWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)

$script:Failed = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  PASS $Name" } else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}

$RuleId = '01443614-cd74-433a-b99e-2ecdc07bfc25'
$OtherRuleId = '3b576869-a4ec-4529-8536-b80a7769e899'
$SelfXFiles = @(
    'C:\Program Files\SelfX\App\SelfXService.exe',
    'C:\Program Files\SelfX\App\SelfX.exe',
    'C:\Program Files\SelfX\App\WinRT\SelfXWinRT.dll',
    'C:\Program Files\SelfX\App\Audio\SelfXAudio.dll'
)

# ---------------------------------------------------------------- static checks
Write-Host 'Static checks'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Target, [ref]$tokens, [ref]$parseErrors)
Assert (@($parseErrors).Count -eq 0) 'the script parses without errors'
$text = [IO.File]::ReadAllText($Target)
$ps7 = @($ast.FindAll({ param($node) $node.GetType().Name -in 'TernaryExpressionAst', 'PipelineChainAst', 'NullConditionalMemberAccessAst' }, $true))
Assert ($ps7.Count -eq 0 -and $text -notmatch '(?m)\?\?=?|\?\.|ForEach-Object\s+-Parallel|-AsHashtable') 'no syntax or parameter of PowerShell 7 only (works in Windows PowerShell 5.1)'
Assert ($text -notmatch '[^\x00-\x7F]') 'the script is plain ASCII'

# Read only: every command the script calls is on this list. A write, start or network command would be a new entry here.
$allowed = @('Get-WinEvent', 'Get-ItemProperty', 'Get-Date', 'New-Object', 'Where-Object', 'Sort-Object', 'Select-Object', 'Write-Host', 'Write-Warning', 'Write-Verbose')
$used = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
$ownFunctions = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
$extra = @($used | Where-Object { $_ -notin $allowed -and $_ -notin $ownFunctions })
Assert ($extra.Count -eq 0) ('only read-only commands are called' + $(if ($extra) { ': ' + ($extra -join ', ') }))
$types = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'New-Object' }, $true) | ForEach-Object { $_.CommandElements[1].Extent.Text.Trim("'`"") })
$badTypes = @($types | Where-Object { $_ -notin 'System.Xml.XmlReaderSettings', 'System.IO.StringReader', 'System.Xml.XmlDocument', 'System.Collections.Generic.List[string]', 'System.Collections.Generic.List[object]' })
Assert ($badTypes.Count -eq 0) ('New-Object creates only XML, reader and list objects' + $(if ($badTypes) { ': ' + ($badTypes -join ', ') }))
Assert ($text -notmatch '(?i)\b(Invoke-Expression|iex|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Add-Type|Out-File|Add-Content)\b|\b(Set|Remove|Export|Clear|Stop|Restart|New-Item)-[A-Za-z]') 'no write, start, download or compile command in the text'
Assert ($text -match 'DtdProcessing\]::Prohibit' -and $text -match '\.XmlResolver = \$null') 'event XML is read without DTD and without resolver'
$paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
Assert (($paramNames -join ',') -eq 'Days,MaxEvents,SelfXOnly') ("the parameters only limit the output (Days, MaxEvents, SelfXOnly), found: $($paramNames -join ',')")
Assert ($text -match [regex]::Escape("[guid]'$RuleId'") -and $text -match [regex]::Escape("'Microsoft-Windows-Windows Defender/Operational'")) 'rule ID and log name are the documented ones and fixed in the script'

# ---------------------------------------------------------------- load the functions (the main block does not run when dot-sourced)
. $Target

# Replaces the one function that reads the real log.
$script:FakeEvents = @()
$script:FakeError = $null
$script:LogCalls = 0
function Read-SelfXAsrLog {
    param([datetime]$StartTime, [int]$Limit)
    $script:LogCalls++
    if ($script:FakeError) { throw $script:FakeError }
    return $script:FakeEvents
}

function New-FakeEvent {
    param([int]$Id = 1121, [datetime]$Time = (Get-Date), [hashtable]$Data = @{}, [string]$RawXml)
    $xml = $RawXml
    if (-not $xml) {
        $items = ($Data.Keys | ForEach-Object { '<Data Name="{0}">{1}</Data>' -f $_, [Security.SecurityElement]::Escape([string]$Data[$_]) }) -join ''
        $xml = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><System><EventID>' + $Id + '</EventID></System><EventData>' + $items + '</EventData></Event>'
    }
    $entry = [pscustomobject]@{ Id = $Id; TimeCreated = $Time; Xml = $xml }
    return ($entry | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml } -PassThru)
}

function New-AsrData {
    param([string]$Path, [string]$Id = $RuleId, [string]$Process = 'C:\Windows\System32\svchost.exe')
    return @{
        'Product Name'       = 'Microsoft Defender Antivirus'
        'ID'                 = $Id
        'Detection Time'     = '2026-11-27T08:00:00.000Z'
        'User'               = 'CONTOSO\mmueller'
        'Path'               = $Path
        'Process Name'       = $Process
        'Target Commandline' = 'cmd /c secret-for-mmueller.cmd'
        'Parent Commandline' = 'C:\Users\mmueller\a.exe --token=abc'
        'Involved File'      = 'C:\Users\mmueller\Documents\involved.docx'
    }
}

# ---------------------------------------------------------------- behavior
Write-Host 'The one rule, Block and Audit'
$now = Get-Date
$script:FakeEvents = @(
    (New-FakeEvent -Id 1121 -Time $now.AddMinutes(-5) -Data (New-AsrData -Path $SelfXFiles[0] -Id $RuleId.ToUpperInvariant())),
    (New-FakeEvent -Id 1122 -Time $now.AddMinutes(-10) -Data (New-AsrData -Path $SelfXFiles[1] -Id $RuleId)),
    (New-FakeEvent -Id 1121 -Time $now.AddMinutes(-15) -Data (New-AsrData -Path 'C:\Tools\other.exe' -Id $OtherRuleId)),
    (New-FakeEvent -Id 1121 -Time $now.AddMinutes(-20) -Data (New-AsrData -Path 'C:\Tools\tool.exe'))
)
$r = @(Get-SelfXAsrEvent)
Assert ($r.Count -eq 3) 'three events of this rule are shown, the event of another rule is left out'
Assert ($r[0].Mode -eq 'Block' -and $r[0].File -eq $SelfXFiles[0] -and $r[0].InSelfXFolder) 'event 1121 = Block, file as in the event, upper case ID accepted'
Assert ($r[1].Mode -eq 'Audit' -and $r[1].File -eq $SelfXFiles[1]) 'event 1122 = Audit, lower case ID accepted'
Assert ($r[0].Time -gt $r[1].Time -and $r[1].Time -gt $r[2].Time) 'newest first'
Assert ($r[2].File -eq 'C:\Tools\tool.exe' -and -not $r[2].InSelfXFolder) 'a file outside the SelfX folder is shown and marked'
Assert ($r[0].StartedBy -eq 'C:\Windows\System32\svchost.exe') 'the starting process is shown'
Assert (@($r | Where-Object { $_.File -match 'other\.exe' }).Count -eq 0) 'negative: the other rule (3b576869-...) is not shown'
Assert (($r | Get-Member -MemberType NoteProperty | ForEach-Object Name | Sort-Object) -join ',' -eq 'File,InSelfXFolder,Mode,StartedBy,Time') 'the output has exactly the five documented properties'

Write-Host 'Braces in the ID, spaces, other event IDs'
$script:FakeEvents = @(
    (New-FakeEvent -Id 1121 -Data (New-AsrData -Path $SelfXFiles[2] -Id " {$($RuleId.ToUpperInvariant())} ")),
    (New-FakeEvent -Id 1129 -Data (New-AsrData -Path 'C:\x\override.exe')),
    (New-FakeEvent -Id 5007 -Data (New-AsrData -Path 'C:\x\config.exe'))
)
$r = @(Get-SelfXAsrEvent)
Assert ($r.Count -eq 1 -and $r[0].File -eq $SelfXFiles[2]) 'ID with braces and spaces is accepted; events 1129 and 5007 are never shown'

Write-Host 'Unreadable events are reported, not hidden'
$script:FakeEvents = @(
    (New-FakeEvent -Id 1121 -Data (New-AsrData -Path $SelfXFiles[0])),
    (New-FakeEvent -Id 1121 -Data @{ 'Path' = 'C:\a\no-id.exe' }),
    (New-FakeEvent -Id 1121 -Data (New-AsrData -Path 'C:\a\bad-id.exe' -Id 'not-a-guid')),
    (New-FakeEvent -Id 1122 -RawXml '<Event><EventData><Data Name="ID">'),
    (New-FakeEvent -Id 1122 -RawXml ' ')
)
$warnings = @()
$r = @(Get-SelfXAsrEvent -WarningVariable warnings -WarningAction SilentlyContinue)
Assert ($r.Count -eq 1 -and $r[0].File -eq $SelfXFiles[0]) 'the readable event is shown; events without or with an invalid ID, broken XML and empty XML are not'
Assert (@($warnings).Count -eq 1 -and "$($warnings[0])" -match '^4 event\(s\)') 'the warning counts the 4 unreadable events'
$script:FakeEvents = @()
$warnings = @()
$r = @(Get-SelfXAsrEvent -WarningVariable warnings -WarningAction SilentlyContinue)
Assert ($r.Count -eq 0 -and @($warnings).Count -eq 0) 'no events: empty result, no warning'

Write-Host 'XML with DTD or entity'
$dtd = '<?xml version="1.0"?><!DOCTYPE Event [<!ENTITY secret "expanded-text">]><Event><EventData><Data Name="ID">' + $RuleId + '</Data><Data Name="Path">&secret;</Data></EventData></Event>'
$script:FakeEvents = @((New-FakeEvent -Id 1121 -RawXml $dtd))
$warnings = @()
$r = @(Get-SelfXAsrEvent -WarningVariable warnings -WarningAction SilentlyContinue)
Assert ($r.Count -eq 0 -and @($warnings).Count -eq 1) 'negative: an event with a DOCTYPE is rejected (counted as unreadable) and no entity is expanded'
Assert ((Read-SelfXAsrEventData -Xml $dtd) -eq $null) 'Read-SelfXAsrEventData returns $null for XML with a DTD'
$external = '<?xml version="1.0"?><!DOCTYPE Event [<!ENTITY x SYSTEM "file:///etc/passwd">]><Event><EventData><Data Name="ID">&x;</Data></EventData></Event>'
Assert ((Read-SelfXAsrEventData -Xml $external) -eq $null) 'negative: an external entity is rejected'
$fields = Read-SelfXAsrEventData -Xml '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData><Data Name="ID">a</Data><Data Name="ID">b</Data><Data Name="Path">p</Data></EventData></Event>'
Assert ($fields['ID'] -eq 'a' -and $fields['path'] -eq 'p') 'the first of a repeated field counts; field names are not case sensitive'

Write-Host 'No user name in the output'
$secretNames = 'mmueller', 'anna.schmidt', 'bob'
$script:FakeEvents = @(
    (New-FakeEvent -Id 1121 -Data (New-AsrData -Path 'C:\Users\mmueller\Downloads\setup.exe' -Process 'C:\Users\MMUELL~1\AppData\Local\Temp\launcher.exe')),
    (New-FakeEvent -Id 1121 -Data (New-AsrData -Path 'D:\Profiles\anna.schmidt\Desktop\tool.exe' -Process 'D:\Profiles\anna.schmidt\x.exe')),
    (New-FakeEvent -Id 1121 -Data (New-AsrData -Path 'C:\users\BOB' -Process 'C:\Users\Public\run.exe')),
    (New-FakeEvent -Id 1121 -Data (New-AsrData -Path 'C:\Users\Default\a.exe' -Process 'C:\Users\All Users\b.exe'))
)
$r = @(Get-SelfXAsrEvent -ProfileRoot @('D:\Profiles\anna.schmidt', 'C:\Users\mmueller'))
$json = ($r | ConvertTo-Json -Depth 4) + ($r | Out-String)
$leak = @($secretNames | Where-Object { $json -match [regex]::Escape($_) })
Assert ($r.Count -eq 4 -and $leak.Count -eq 0) ('no user name (mmueller, anna.schmidt, bob) in any property or in the displayed text' + $(if ($leak) { ': ' + ($leak -join ',') }))
Assert ($json -notmatch 'CONTOSO' -and $json -notmatch 'secret-for' -and $json -notmatch 'token=abc' -and $json -notmatch 'involved\.docx') 'negative: the fields User, Target Commandline, Parent Commandline and Involved File are never shown'
$byFile = @{}; foreach ($item in $r) { $byFile[$item.File] = $item }
Assert ($byFile.ContainsKey('C:\Users\<user>\Downloads\setup.exe')) 'C:\Users\<name>\... becomes C:\Users\<user>\...'
Assert ($byFile.ContainsKey('D:\Profiles\<user>\Desktop\tool.exe')) 'a profile folder outside \Users (from the profile list) becomes <user>'
Assert ($byFile.ContainsKey('C:\users\<user>') ) 'a path that ends at the profile folder is hidden too, upper and lower case'
Assert ($byFile['C:\Users\<user>\Downloads\setup.exe'].StartedBy -eq 'C:\Users\<user>\AppData\Local\Temp\launcher.exe') 'the 8.3 short name of a profile folder in the process path is hidden'
Assert (@($r | Where-Object { $_.StartedBy -eq 'C:\Users\Public\run.exe' }).Count -eq 1 -and @($r | Where-Object { $_.File -eq 'C:\Users\Default\a.exe' -and $_.StartedBy -eq 'C:\Users\All Users\b.exe' }).Count -eq 1) 'the shared folders Public, Default and All Users stay readable'
Assert ((ConvertTo-SelfXAsrSafePath -Value '\\srv\profiles$\anna\x.exe' -ProfileRoot @('\\srv\profiles$\anna')) -eq '\\srv\profiles$\<user>\x.exe') 'a dollar sign in the path of a profile share does not break the replacement'
Assert ((ConvertTo-SelfXAsrSafePath -Value 'C:\Users\anna\x.exe' -ProfileRoot @('', 'C:', 'C:\', 'C:\Users', '\\srv\share')) -eq 'C:\Users\<user>\x.exe') 'negative: empty or too short profile roots (drive, parent folder, share) are ignored'

Write-Host 'Control characters and length'
$long = 'C:\' + ('a' * 600) + '.exe'
$script:FakeEvents = @(
    # Control characters as character references (XML 1.0 has no other way to write them) and a right-to-left override.
    (New-FakeEvent -Id 1121 -RawXml ('<Event><EventData><Data Name="ID">' + $RuleId + '</Data><Data Name="Path">C:\Temp\evil&#7;&#27;[31m' + [char]0x202E + 'exe.txt&#10;Mode=Allow</Data><Data Name="Process Name">C:\a&#1;b.exe</Data></EventData></Event>')),
    (New-FakeEvent -Id 1122 -Data (New-AsrData -Path $long))
)
$r = @(Get-SelfXAsrEvent)
Assert ($r.Count -eq 2 -and @($r | Where-Object { $_.File -match '[\x00-\x1F\x7F-\x9F\u202A-\u202E]' -or $_.StartedBy -match '[\x00-\x1F\x7F-\x9F]' }).Count -eq 0) 'control characters and direction marks are removed from file and process'
Assert (@($r | Where-Object { $_.File.Length -gt 403 }).Count -eq 0 -and @($r | Where-Object { $_.File.EndsWith('...') }).Count -eq 1) 'a long path is cut at 400 characters'
$script:FakeEvents = @((New-FakeEvent -Id 1121 -Data @{ 'ID' = $RuleId }))
$r = @(Get-SelfXAsrEvent)
Assert ($r.Count -eq 1 -and $r[0].File -eq '(not in the event)' -and $r[0].StartedBy -eq '(not in the event)' -and -not $r[0].InSelfXFolder) 'an event without Path and Process Name is shown with a clear note'

Write-Host 'Filter for the SelfX folder, limit and order'
$script:FakeEvents = @(
    (New-FakeEvent -Id 1121 -Time $now.AddMinutes(-1) -Data (New-AsrData -Path $SelfXFiles[0])),
    (New-FakeEvent -Id 1121 -Time $now.AddMinutes(-2) -Data (New-AsrData -Path 'C:\Program Files\Other\App\x.exe')),
    (New-FakeEvent -Id 1121 -Time $now.AddMinutes(-3) -Data (New-AsrData -Path 'C:\Program Files\SelfX\Config\x.exe')),
    (New-FakeEvent -Id 1121 -Time $now.AddMinutes(-4) -Data (New-AsrData -Path 'C:\Tools\SelfX\App\copy.exe')),
    (New-FakeEvent -Id 1122 -Time $now.AddMinutes(-5) -Data (New-AsrData -Path $SelfXFiles[3]))
)
$r = @(Get-SelfXAsrEvent -SelfXOnly)
Assert ($r.Count -eq 3 -and @($r | Where-Object { -not $_.InSelfXFolder }).Count -eq 0) '-SelfXOnly keeps the files below ...\SelfX\App\ only'
Assert (@($r | Where-Object { $_.File -match 'Config|Other' }).Count -eq 0) 'negative: ...\SelfX\Config\ and another program folder do not count'
$r = @(Get-SelfXAsrEvent -MaxEvents 2)
Assert ($r.Count -eq 2 -and $r[0].Time -gt $r[1].Time) '-MaxEvents limits the output to the newest events'
$script:FakeEvents = @(1..60 | ForEach-Object { New-FakeEvent -Id 1121 -Time $now.AddMinutes(-$_) -Data (New-AsrData -Path "C:\Tools\f$_.exe") })
Assert (@(Get-SelfXAsrEvent).Count -eq 60 -and @(Get-SelfXAsrEvent -MaxEvents 1000).Count -eq 60) 'all events of the rule are shown when they are fewer than the limit'

Write-Host 'Raw limit of the log read'
$script:FakeEvents = @(1..5001 | ForEach-Object { New-FakeEvent -Id 1121 -Time $now.AddSeconds(-$_) -Data @{ 'ID' = $RuleId; 'Path' = "C:\Tools\f$_.exe" } })
$warnings = @()
$r = @(Get-SelfXAsrEvent -MaxEvents 1000 -WarningVariable warnings -WarningAction SilentlyContinue)
Assert ($r.Count -eq 1000 -and @($warnings).Count -eq 1 -and "$($warnings[0])" -match 'more than 5000') 'more than 5000 events: the newest 5000 are checked and the script says so'

Write-Host 'Errors of the log'
$script:FakeEvents = @()
$script:FakeError = New-Object System.Management.Automation.ErrorRecord((New-Object System.Exception('No events were found that match the specified selection criteria.')), 'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
Assert (@(Get-SelfXAsrEvent).Count -eq 0) 'Get-WinEvent "no events found" is an empty result, not an error'
$script:FakeError = New-Object System.Management.Automation.ErrorRecord((New-Object System.UnauthorizedAccessException('Attempted to perform an unauthorized operation.')), 'System.UnauthorizedAccessException,Microsoft.PowerShell.Commands.GetWinEventCommand', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
$message = ''
try { Get-SelfXAsrEvent | Out-Null } catch { $message = $_.Exception.Message }
Assert ($message -match 'cannot be read' -and $message -match 'elevated') 'negative: access denied stops with a clear message that names the elevated window'
$script:FakeError = New-Object System.Management.Automation.ErrorRecord((New-Object System.Exception("There is not an event log on the localhost computer that matches 'Microsoft-Windows-Windows Defender/Operational'.")), 'System.Diagnostics.Eventing.Reader.EventLogNotFoundException,Microsoft.PowerShell.Commands.GetWinEventCommand', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
$message = ''
try { Get-SelfXAsrEvent | Out-Null } catch { $message = $_.Exception.Message }
Assert ($message -match 'cannot be read') 'negative: a missing log is an error, not "no events"'
$script:FakeError = $null

Write-Host 'Parameters of the script file'
function Invoke-Child {
    # Starts the script in a new process. The error output of the child must not stop this test (Windows PowerShell 5.1 turns it
    # into an error when $ErrorActionPreference is Stop).
    param([string[]]$Arguments = @())
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe -NoProfile -ExecutionPolicy Bypass -File $Target @Arguments 2>&1 | Out-String
        return [pscustomobject]@{ Exit = $LASTEXITCODE; Output = $output }
    }
    finally { $ErrorActionPreference = $previous }
}
foreach ($case in @(@('-Days', '0'), @('-Days', '3651'), @('-MaxEvents', '0'), @('-MaxEvents', '1001'), @('-LogName', 'Security'), @('-Path', 'C:\x.evtx'), @('-ComputerName', 'server'))) {
    $child = Invoke-Child -Arguments $case
    Assert ($child.Exit -ne 0) "negative: $($case -join ' ') is refused"
}
if (-not $onWindows) {
    $child = Invoke-Child
    Assert ($child.Exit -eq 1 -and $child.Output -match 'needs Windows') 'on a system other than Windows the script stops with a message'
}

# ---------------------------------------------------------------- the real call (Windows only)
if ($onWindows) {
    Write-Host 'The real log (read only)'
    Remove-Item Function:\Read-SelfXAsrLog
    . $Target
    $outcome = 'ok'
    try { $real = @(Read-SelfXAsrLog -StartTime (Get-Date).AddDays(-1) -Limit 5) }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $outcome = 'ok' }
        elseif ($_.FullyQualifiedErrorId -match 'NoMatchingLogsFound|EventLogNotFound') { $outcome = 'skip' }
        else { $outcome = "error: $($_.Exception.Message)" }
    }
    if ($outcome -eq 'skip') { Write-Host '  SKIP this device has no Defender log' } else { Assert ($outcome -eq 'ok') ("Get-WinEvent accepts the filter of the script ($outcome)") }
    $profiles = @(Get-SelfXAsrProfileRoot)
    Assert (@($profiles | Where-Object { $_ -notmatch '^[A-Za-z]:\\[^\\]+\\[^\\]+$' }).Count -eq 0) 'the profile list returns only folders two levels below a drive'
}

# ---------------------------------------------------------------- documentation and texts
Write-Host 'Documentation and texts'
$docs = @{
    'docs/Installation.md'    = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'docs/Installation.md') -Raw -Encoding UTF8
    'docs/de/Installation.md' = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'docs/de/Installation.md') -Raw -Encoding UTF8
}
foreach ($name in $docs.Keys) {
    $doc = $docs[$name]
    Assert ($doc -match [regex]::Escape($RuleId) -and $doc -match '1121' -and $doc -match '1122') "$name names the rule ID and the events 1121 and 1122"
    Assert ($doc -match 'Get-SelfXAsrEvents\.ps1') "$name names the diagnostic script"
    $missing = @($SelfXFiles | Where-Object { $doc -notmatch [regex]::Escape($_) })
    Assert ($missing.Count -eq 0) "$name lists the four SelfX files for the exclusion"
    Assert ($doc -match 'learn\.microsoft\.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference' -and $doc -match 'learn\.microsoft\.com/en-us/defender-endpoint/attack-surface-reduction-faq') "$name cites the ASR rules reference and the ASR FAQ"
    Assert ($doc -match '(?i)no guarantee|keine Zusage') "$name says that signing is no guarantee for the rule"
}
foreach ($culture in 'en', 'de') {
    $xml = New-Object System.Xml.XmlDocument
    $xml.XmlResolver = $null
    $xml.Load((Join-Path $ScriptFolder "Wizard/Wizard.$culture.xml"))
    $asr = @($xml.SelectNodes("/Wizard_Language/T[starts-with(@Id,'guide.asr')]"))
    Assert ($asr.Count -ge 4) "Wizard.$culture.xml has the guide texts about the ASR rule ($($asr.Count) texts)"
    Assert (@($asr | Where-Object { $_.InnerText -match [regex]::Escape($RuleId) }).Count -ge 1 -and @($asr | Where-Object { $_.InnerText -match 'Get-SelfXAsrEvents\.ps1' }).Count -ge 1) "Wizard.$culture.xml names the rule ID and the script"
}

if ($script:Failed -gt 0) { Write-Host "FAILED: $script:Failed test(s)." -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed.'
exit 0
