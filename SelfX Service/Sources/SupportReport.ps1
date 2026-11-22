<#
.SYNOPSIS
    Open a new e-mail to the support with the device logs report attached (GUI helper).

.DESCRIPTION
    Loaded by the SelfX GUI in the signed-in user session; defining these functions alone
    performs no action. After the System action SelfX_Device_CollectLogs.ps1 (catalog
    Post_Action MailReport) has written the report to ProgramData\SelfX\Reports\<SID of the
    user>, Send-SelfXSupportReport:
      1. takes the newest DeviceLogs-* file of the current user (only that user can read it),
      2. copies it to %LOCALAPPDATA%\SelfX\Reports (older copies there are deleted),
      3. adds the user's own SelfX logs (ProgramData\SelfX\Logs\Users\<own SID>, last DeviceLogs_Days
         days) to the copy with the rights of the user (2.6.10). They are not read by the System
         action: the folder is user-writable, so a read as SYSTEM could be redirected to protected
         files. Only the own SID folder is used, never the logs of another user. A problem here never
         stops the e-mail,
      4. opens a new e-mail with the copy attached:
         - classic Outlook through COM (recipient, subject and text filled in), else
         - outlook.exe /a <file> (Outlook fills in nothing, the user adds the recipient), else
         - the default mail app through mailto: and an Explorer window with the file selected,
           so the user can attach the file (for example new Outlook, which has no COM interface).
    The e-mail is only displayed, never sent: the user describes the issue and sends it.
    Nothing runs elevated and nothing is sent automatically.

.NOTES
    Name    : SupportReport.ps1
    Package : SelfX Service
    Context : GUI helper (signed-in user)
    Version : 2.6.10

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.4.0    2026-11-02  Wolfgang Baeck       Initial version: device logs report by e-mail
    2.6.10   2026-11-22  fubu2k               The own user logs are added here with the rights of the user (were read by
                                              the System action, which a user-writable folder could redirect)
#>

function Get-SelfXReportFolder {
    # Report folder of the current user, written by the System action and readable only by this user.
    param([string]$Root = (Join-Path $env:ProgramData 'SelfX\Reports'))
    return (Join-Path $Root ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
}

function Get-SelfXLatestReport {
    param([Parameter(Mandatory = $true)][string]$Folder)
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return $null }
    return (Get-ChildItem -LiteralPath $Folder -File -Filter 'DeviceLogs-*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.zip', '.txt' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Copy-SelfXReport {
    # A copy in the user profile stays available after the next run replaces the System copy.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Destination = (Join-Path $env:LOCALAPPDATA 'SelfX\Reports')
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Destination -File -Filter 'DeviceLogs-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $target = Join-Path $Destination (Split-Path -Leaf $Path)
    Copy-Item -LiteralPath $Path -Destination $target -Force
    return $target
}

function ConvertTo-SelfXLogDays {
    # DeviceLogs_Days of Tool_Config.xml: 1-60, otherwise 7 (same rule as the System action).
    param($Value)
    $days = 0
    if ([int]::TryParse("$Value", [ref]$days) -and $days -ge 1 -and $days -le 60) { return $days }
    return 7
}

function Get-SelfXUserLogFiles {
    # The own logs of the signed-in user: Logs\Users\<own SID>, files *.log of the last Days days.
    # Runs with the rights of the user, so it can only list what this user can read anyway. Nothing of
    # another user is returned: only the folder of the own SID is used. A junction as folder, links and
    # files that another account owns (for example planted in a folder that account created in advance)
    # are skipped, as in SelfXLog.ps1 (Get-SelfXUserLogFolder).
    param(
        [string]$UsersRoot = (Join-Path $env:ProgramData 'SelfX\Logs\Users'),
        [string]$Sid = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),
        [int]$Days = 7
    )
    $files = New-Object System.Collections.Generic.List[object]
    $folder = Join-Path $UsersRoot $Sid
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return $files }
    if ((Get-Item -LiteralPath $folder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $files }
    $limit = (Get-Date).AddDays(-$Days)
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($file.Name -notlike '*.log' -or $file.LastWriteTime -lt $limit) { continue }
        $owner = $null
        # Fails closed: when the owner cannot be read, the file is skipped. .NET 10 (PowerShell 7) has the
        # FileSystemAclExtensions only.
        try {
            $sections = [Security.AccessControl.AccessControlSections]::Owner
            $acl = [IO.FileSystemAclExtensions]::GetAccessControl($file, $sections)
            $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        } catch { }
        if ($owner -ne $Sid) { continue }
        $files.Add([pscustomobject]@{ Path = $file.FullName; Entry = "SelfX-Logs\User\$($file.Name)" })
    }
    return $files
}

function Read-SelfXUserLogText {
    # Reads a log file that may still be written (shared read), at most the last MaxBytes bytes, as text.
    param([string]$Path, [long]$MaxBytes = 2MB)
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $start = [Math]::Max(0, $stream.Length - $MaxBytes)
        [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
        $buffer = [byte[]]::new($stream.Length - $start)
        $read = 0
        while ($read -lt $buffer.Length) { $n = $stream.Read($buffer, $read, $buffer.Length - $read); if ($n -le 0) { break }; $read += $n }
        $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $read).TrimStart([char]0xFEFF)
        if ($start -gt 0) { $text = "[... only the last $([Math]::Round($MaxBytes / 1MB)) MB of this file ...]`r`n" + $text }
        return $text
    } finally { $stream.Dispose() }
}

function Add-SelfXUserLogsToReport {
    # Adds the own user logs to the user's COPY of the report: as files in SelfX-Logs\User in a .zip, as a
    # last section in a .txt. At most the last 2 MB of each file and 30 MB in total. Returns the number of
    # logs added. The copy is in the profile of the user, so nothing here crosses a privilege boundary.
    param(
        [Parameter(Mandatory = $true)][string]$Report,
        [string]$UsersRoot = (Join-Path $env:ProgramData 'SelfX\Logs\Users'),
        [string]$Sid = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),
        [int]$Days = 7
    )
    $logs = @(Get-SelfXUserLogFiles -UsersRoot $UsersRoot -Sid $Sid -Days $Days)
    if (-not $logs.Count) { return 0 }
    $added = 0
    $total = 0L
    $totalLimit = 30MB
    if ($Report -like '*.zip') {
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::Open($Report, [IO.Compression.ZipArchiveMode]::Update)
        try {
            foreach ($log in $logs) {
                if ($total -ge $totalLimit) { break }
                try {
                    $bytes = [Text.Encoding]::UTF8.GetBytes((Read-SelfXUserLogText -Path $log.Path))
                    $entry = $archive.CreateEntry($log.Entry, [IO.Compression.CompressionLevel]::Optimal)
                    $stream = $entry.Open()
                    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
                    $total += $bytes.Length
                    $added++
                } catch { }
            }
        } finally { $archive.Dispose() }
    } else {
        $section = [Text.StringBuilder]::new()
        [void]$section.AppendLine().AppendLine('=' * 100).AppendLine('SelfX logs of the user (ProgramData\SelfX\Logs\Users\<SID>)').AppendLine('=' * 100)
        foreach ($log in $logs) {
            if ($total -ge $totalLimit) { [void]$section.AppendLine('[limit of 30 MB reached, further user logs not added]'); break }
            try {
                $text = Read-SelfXUserLogText -Path $log.Path
                [void]$section.AppendLine().AppendLine("----- $($log.Entry) -----").AppendLine($text)
                $total += $text.Length
                $added++
            } catch { [void]$section.AppendLine("----- $($log.Entry): not readable ($($_.Exception.Message)) -----") }
        }
        [IO.File]::AppendAllText($Report, $section.ToString(), [Text.UTF8Encoding]::new($false))
    }
    return $added
}

function Test-SelfXClassicOutlook {
    # New Outlook registers no COM ProgID; only classic Outlook can be automated.
    return [bool][type]::GetTypeFromProgID('Outlook.Application')
}

function New-SelfXOutlookMail {
    # Classic Outlook only; new Outlook has no COM interface and fails here.
    param([string]$To, [string]$Subject, [string]$Body, [string]$Attachment)
    if (-not (Test-SelfXClassicOutlook)) { throw 'Classic Outlook is not installed.' }
    $outlook = $null
    $mail = $null
    try {
        $outlook = New-Object -ComObject Outlook.Application
        $mail = $outlook.CreateItem(0)
        if ($To) { $mail.To = $To }
        $mail.Subject = $Subject
        $mail.Body = $Body
        $null = $mail.Attachments.Add($Attachment)
        # Not modal: the SelfX window stays usable while the e-mail is open.
        $mail.Display($false)
    } finally {
        foreach ($comObject in @($mail, $outlook)) {
            if ($comObject -and [Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
                $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($comObject)
            }
        }
    }
}

function Get-SelfXOutlookPath {
    foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE') {
        $path = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).'(default)'
        if ($path -and (Test-Path -LiteralPath $path.Trim('"') -PathType Leaf)) { return $path.Trim('"') }
    }
    return $null
}

function Start-SelfXOutlookCommandLine {
    param([string]$Attachment)
    $outlookExe = Get-SelfXOutlookPath
    if (-not $outlookExe) { throw 'outlook.exe was not found.' }
    Start-Process -FilePath $outlookExe -ArgumentList '/a', "`"$Attachment`""
}

function Start-SelfXManualMail {
    # Default mail app with recipient, subject and text, plus the file selected in Explorer.
    param([string]$To, [string]$Subject, [string]$Body, [string]$Attachment)
    try {
        # The address keeps its @ readable; some mail apps do not decode %40 in the recipient.
        $mailto = 'mailto:{0}?subject={1}&body={2}' -f ([uri]::EscapeDataString("$To") -replace '%40', '@'),
            [uri]::EscapeDataString("$Subject"), [uri]::EscapeDataString("$Body")
        Start-Process -FilePath $mailto
    } catch { }
    Start-Process -FilePath ([IO.Path]::Combine($env:SystemRoot, 'explorer.exe')) -ArgumentList "/select,`"$Attachment`""
}

function Send-SelfXSupportReport {
    <#
    .SYNOPSIS
        Opens a new e-mail with the latest report attached. Returns Status (Outlook,
        OutlookCommandLine, Manual, NotFound or Error), Path (attached copy), Message and
        UserLogs (number of own user logs added to the copy).
        Days is DeviceLogs_Days of Tool_Config.xml (1-60, otherwise 7). UsersRoot is only for tests.
    #>
    param(
        [string]$To,
        [string]$Subject,
        [string]$Body,
        [string]$ReportFolder = (Get-SelfXReportFolder),
        [string]$Destination = (Join-Path $env:LOCALAPPDATA 'SelfX\Reports'),
        $Days = 7,
        [string]$UsersRoot = (Join-Path $env:ProgramData 'SelfX\Logs\Users')
    )
    $report = Get-SelfXLatestReport -Folder $ReportFolder
    if (-not $report) { return [pscustomobject]@{ Status = 'NotFound'; Path = $null; Message = $ReportFolder; UserLogs = 0 } }
    try {
        $copy = Copy-SelfXReport -Path $report.FullName -Destination $Destination
    } catch {
        return [pscustomobject]@{ Status = 'Error'; Path = $report.FullName; Message = $_.Exception.Message; UserLogs = 0 }
    }

    # The own user logs are added to the copy with the rights of the user. A problem never stops the e-mail.
    $userLogs = 0
    try { $userLogs = Add-SelfXUserLogsToReport -Report $copy -UsersRoot $UsersRoot -Days (ConvertTo-SelfXLogDays $Days) } catch { $userLogs = 0 }

    $errors = @()
    try {
        New-SelfXOutlookMail -To $To -Subject $Subject -Body $Body -Attachment $copy
        return [pscustomobject]@{ Status = 'Outlook'; Path = $copy; Message = ''; UserLogs = $userLogs }
    } catch { $errors += "Outlook: $($_.Exception.Message)" }
    try {
        Start-SelfXOutlookCommandLine -Attachment $copy
        return [pscustomobject]@{ Status = 'OutlookCommandLine'; Path = $copy; Message = ($errors -join ' / '); UserLogs = $userLogs }
    } catch { $errors += "outlook.exe: $($_.Exception.Message)" }
    try {
        Start-SelfXManualMail -To $To -Subject $Subject -Body $Body -Attachment $copy
        return [pscustomobject]@{ Status = 'Manual'; Path = $copy; Message = ($errors -join ' / '); UserLogs = $userLogs }
    } catch {
        $errors += "Explorer: $($_.Exception.Message)"
        return [pscustomobject]@{ Status = 'Error'; Path = $copy; Message = ($errors -join ' / '); UserLogs = $userLogs }
    }
}
