<#
.SYNOPSIS
    Shows which files the Defender attack surface reduction (ASR) rule "Block executable files from running unless they meet a
    prevalence, age, or trusted list criterion" blocked or would block on this device (read only).

.DESCRIPTION
    The rule (ID 01443614-cd74-433a-b99e-2ecdc07bfc25) decides with the cloud protection of Microsoft whether an executable file
    (.exe, .dll, .scr) may start. If it blocks a program of SelfX, the first step is to find out WHICH file it is. This script reads
    the events 1121 (rule fired in block mode) and 1122 (rule fired in audit mode) of the log
    Microsoft-Windows-Windows Defender/Operational and shows, for this one rule only:

      Time           local time of the event
      Mode           Block (event 1121) or Audit (event 1122)
      File           the file that was blocked, or would be blocked (field "Path" of the event)
      StartedBy      the process that wanted to start it (field "Process Name")
      InSelfXFolder  True when the path contains the program folder of SelfX (...\SelfX\App\...)

    What the script does not do: it changes nothing (no setting, no exclusion, no file, no registry value), starts no program,
    sends nothing and reads no other log. It reads the event log and, to hide user names, the list of local profile folders in the
    registry. The log and the rule are fixed in the script; the parameters only limit the output.

    No user names in the output: the fields "User", "Target Commandline", "Parent Commandline" and "Involved File" are never read or
    shown. In paths the profile folder of a user is shown as <user> (for example C:\Users\<user>\Downloads\a.exe): the folders
    of all local profiles from the profile list of Windows and every folder directly below "\Users". A path outside these folders
    (for example a network share) is shown as the event reports it: look at the output before you pass it on.

    Events of an excluded file are not recorded by Defender (Microsoft: excluded files are allowed to run and no events are written).
    After you added an exclusion, the file therefore disappears from this list.

    If the script says that the log cannot be read, run it in an elevated window. Windows PowerShell 5.1 and PowerShell 7:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-SelfXAsrEvents.ps1
      pwsh.exe       -NoProfile -ExecutionPolicy Bypass -File .\Get-SelfXAsrEvents.ps1

.PARAMETER Days
    Period in days, counted back from now (1 to 3650). Default: 30.

.PARAMETER MaxEvents
    Maximum number of events shown, the newest first (1 to 1000). Default: 100.

.PARAMETER SelfXOnly
    Shows only events whose file is in the program folder of SelfX (path contains \SelfX\App\).

.EXAMPLE
    .\Get-SelfXAsrEvents.ps1 | Format-Table -AutoSize
    All events of the rule of the last 30 days.

.EXAMPLE
    .\Get-SelfXAsrEvents.ps1 -SelfXOnly -Days 7 | Sort-Object File -Unique | Select-Object File
    The SelfX files named in the events of the last 7 days (these are the files for a per-rule exclusion).

.NOTES
    Name    : Get-SelfXAsrEvents.ps1
    Package : tools
    Context : Test or pilot device (administrator if the log cannot be read otherwise; not installed, not shipped)
    Version : 3.1.0

    The field names of the events (ID, Path, Process Name) are not described in the documentation of Microsoft; they come from the
    event XML of a real event 1121 of this rule. An event without a readable field ID is not assigned to a rule: it is not shown
    and the script says how many there were, so that a changed layout is not mistaken for "no events".

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3650)][int]$Days = 30,
    [ValidateRange(1, 1000)][int]$MaxEvents = 100,
    [switch]$SelfXOnly
)

# Fixed on purpose: no parameter names a log, a computer or a file.
$script:AsrRuleId = [guid]'01443614-cd74-433a-b99e-2ecdc07bfc25'
$script:AsrLogName = 'Microsoft-Windows-Windows Defender/Operational'
# Upper limit of the events that are read from the log (events of both IDs, all rules), protects memory and time.
$script:AsrRawLimit = 5000

function ConvertTo-SelfXAsrText {
    # Removes control characters and the characters that reverse the direction of text, and limits the length.
    param([AllowNull()][string]$Value, [int]$MaxLength = 400)
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    $text = [regex]::Replace($Value, '[\x00-\x1F\x7F-\x9F\u200B-\u200F\u202A-\u202E\u2066-\u2069]', '')
    if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength) + '...' }
    return $text.Trim()
}

function ConvertTo-SelfXAsrSafePath {
    # Replaces the profile folder of a user by <user>: first the folders of the local profiles, then every folder below \Users
    # (except the shared folders Public, Default, Default User and All Users).
    param([AllowNull()][string]$Value, [string[]]$ProfileRoot = @())
    $text = ConvertTo-SelfXAsrText -Value $Value
    foreach ($root in @($ProfileRoot)) {
        # A root must be a folder at least two levels below a drive (C:\Users\anna) or a share (\\server\share\anna): never a drive or a parent folder.
        if (-not $root -or $root -notmatch '^([A-Za-z]:\\[^\\]+\\[^\\]+|\\\\[^\\]+\\[^\\]+\\[^\\]+)') { continue }
        $cut = $root.LastIndexOf('\')
        $replacement = ($root.Substring(0, $cut) + '\<user>').Replace('$', '$$')
        $text = [regex]::Replace($text, '(?i)' + [regex]::Escape($root) + '(?=\\|$)', $replacement)
    }
    return [regex]::Replace($text, '(?i)(\\Users\\)(?!(Public|Default|Default User|All Users|<user>)(\\|$))[^\\]+', '$1<user>')
}

function Get-SelfXAsrProfileRoot {
    # Folders of the local user profiles from the profile list in the registry (read only). Profiles below the Windows folder
    # (system and service accounts) and entries that are not a folder two levels below a drive are left out.
    $roots = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($entry in @(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' -ErrorAction Stop)) {
            $path = [string]$entry.ProfileImagePath
            if ($path -match '^[A-Za-z]:\\[^\\]+\\[^\\]+$' -and $path -notmatch '(?i)^[A-Za-z]:\\Windows\\') { $roots.Add($path.TrimEnd('\')) }
        }
    }
    catch { Write-Verbose "The profile list could not be read: $($_.Exception.Message)" }
    return $roots.ToArray()
}

function Read-SelfXAsrEventData {
    # Returns the fields of the event XML (name of the Data element -> text), or $null when the text is not readable XML.
    # No DTD and no resolver: an entity or an external reference makes the event unreadable.
    param([Parameter(Mandatory = $true)][string]$Xml)
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    # A file name can hold characters that XML 1.0 does not allow; the event stays readable and ConvertTo-SelfXAsrText removes them.
    $settings.CheckCharacters = $false
    $stringReader = New-Object System.IO.StringReader($Xml)
    $reader = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($stringReader, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
    }
    catch { return $null }
    finally {
        if ($reader) { $reader.Close() }
        $stringReader.Dispose()
    }
    $fields = @{}
    foreach ($node in @($document.SelectNodes("//*[local-name()='EventData']/*[local-name()='Data']"))) {
        $name = $node.GetAttribute('Name')
        if ($name -and -not $fields.ContainsKey($name)) { $fields[$name] = $node.InnerText }
    }
    return $fields
}

function Read-SelfXAsrLog {
    # The only place that reads the event log (the tests replace this function).
    param([Parameter(Mandatory = $true)][datetime]$StartTime, [Parameter(Mandatory = $true)][int]$Limit)
    Get-WinEvent -FilterHashtable @{ LogName = $script:AsrLogName; Id = 1121, 1122; StartTime = $StartTime } -MaxEvents $Limit -ErrorAction Stop
}

function Get-SelfXAsrEvent {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 3650)][int]$Days = 30,
        [ValidateRange(1, 1000)][int]$MaxEvents = 100,
        [switch]$SelfXOnly,
        [string[]]$ProfileRoot = @()
    )
    $raw = @()
    try { $raw = @(Read-SelfXAsrLog -StartTime (Get-Date).AddDays(-$Days) -Limit ($script:AsrRawLimit + 1)) }
    catch {
        # Get-WinEvent reports "no events" as an error; every other error is shown (log missing, access denied).
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $raw = @() }
        else { throw "The log '$($script:AsrLogName)' cannot be read: $($_.Exception.Message) Run the script in an elevated window, on a device with Microsoft Defender Antivirus." }
    }
    if ($raw.Count -gt $script:AsrRawLimit) {
        Write-Warning "The log holds more than $($script:AsrRawLimit) events of the IDs 1121 and 1122 in this period; only the newest $($script:AsrRawLimit) are checked. Use a smaller value for -Days."
        $raw = @($raw | Sort-Object TimeCreated -Descending | Select-Object -First $script:AsrRawLimit)
    }

    $found = New-Object System.Collections.Generic.List[object]
    $unreadable = 0
    foreach ($entry in $raw) {
        if ($entry.Id -ne 1121 -and $entry.Id -ne 1122) { continue }
        $fields = $null
        try { $fields = Read-SelfXAsrEventData -Xml ([string]$entry.ToXml()) } catch { $fields = $null }
        $ruleId = [guid]::Empty
        if ($null -eq $fields -or -not $fields.ContainsKey('ID') -or -not [guid]::TryParse(([string]$fields['ID']).Trim(), [ref]$ruleId)) {
            $unreadable++
            continue
        }
        if ($ruleId -ne $script:AsrRuleId) { continue }

        $path = if ($fields.ContainsKey('Path')) { ConvertTo-SelfXAsrSafePath -Value $fields['Path'] -ProfileRoot $ProfileRoot } else { '' }
        $process = if ($fields.ContainsKey('Process Name')) { ConvertTo-SelfXAsrSafePath -Value $fields['Process Name'] -ProfileRoot $ProfileRoot } else { '' }
        $inSelfX = ($path -match '(?i)\\SelfX\\App\\')
        if ($SelfXOnly -and -not $inSelfX) { continue }
        $found.Add([pscustomobject][ordered]@{
                Time          = $entry.TimeCreated
                Mode          = $(if ($entry.Id -eq 1121) { 'Block' } else { 'Audit' })
                File          = $(if ($path) { $path } else { '(not in the event)' })
                StartedBy     = $(if ($process) { $process } else { '(not in the event)' })
                InSelfXFolder = $inSelfX
            })
    }
    if ($unreadable -gt 0) {
        Write-Warning "$unreadable event(s) of the IDs 1121 and 1122 could not be assigned to a rule (no readable field ID) and are not shown."
    }
    return @($found | Sort-Object Time -Descending | Select-Object -First $MaxEvents)
}

# Runs only when the file is started, not when it is dot-sourced (the tests dot-source it).
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This script needs Windows.' }
        $events = @(Get-SelfXAsrEvent -Days $Days -MaxEvents $MaxEvents -SelfXOnly:$SelfXOnly -ProfileRoot @(Get-SelfXAsrProfileRoot))
        if ($events.Count -eq 0) {
            Write-Host "No event 1121 or 1122 of the rule 01443614-cd74-433a-b99e-2ecdc07bfc25 in the last $Days day(s)$(if ($SelfXOnly) { ' for files in the SelfX program folder' })."
            Write-Host 'This also happens when the rule is off, when the file is excluded (excluded files write no events) or when nothing was blocked.'
        }
        else { $events }
    }
    catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
