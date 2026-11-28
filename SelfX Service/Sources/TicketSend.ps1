<#
.SYNOPSIS
    Opens the ticket e-mail in the mail program of the user (GUI helper).

.DESCRIPTION
    Needs TicketMail.ps1 (ticket model) and SupportReport.ps1 (Outlook helper) in the same session.
    Loaded by the SelfX GUI in the signed-in user session; defining these functions alone performs no
    action. Send-SelfXTicket:
      1. checks the recipient and the Cc address (they come from the package configuration, never from the user),
      2. saves the device information as a text file in %LOCALAPPDATA%\SelfX\Reports (older
         TicketInfo-* files there are deleted; the file name is fixed, nothing the user typed is in it),
      3. opens a new e-mail with subject, text and the file attached:
         - classic Outlook through COM (everything filled in, file attached), else
         - the default mail app through a mailto link (new Outlook or any other program; the text is
           cut to the link limit) and an Explorer window with the file selected, so the user can
           attach it.
    The e-mail is only displayed, never sent: the user checks it and sends it. Nothing runs
    elevated and nothing is sent automatically.

.NOTES
    Name    : TicketSend.ps1
    Package : SelfX Service
    Context : GUI helper (signed-in user)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.5    2026-11-22  fubu2k               Initial version
    2.8.7    2026-11-22  fubu2k               Recipient and Cc can be set per device in the registry (TicketMail, TicketCc)
    3.1.0    2026-11-28  fubu2k               Get-SelfXSupportContact: on a terminal server TerminalServer_Support_Mail is the support e-mail and
                                              the ticket recipient; the ticket routing is not used there
#>

function Get-SelfXTicketDeviceValues {
    # Reads the values for the routing (read only): group tag and category as set by the administrator in
    # HKLM\SOFTWARE\SelfX\Support (GroupTag, Category, and the addresses TicketMail and TicketCc of the responsible unit;
    # only administrators can write there) and the OU of the computer account (Distinguished-Name of the Group Policy
    # state, hybrid devices). Invalid values become empty; an address must be exactly one plain address.
    param(
        [string]$SupportKey = 'HKLM:\SOFTWARE\SelfX\Support',
        [string]$PolicyKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine'
    )
    $support = Get-ItemProperty -LiteralPath $SupportKey -ErrorAction SilentlyContinue
    $policy = Get-ItemProperty -LiteralPath $PolicyKey -ErrorAction SilentlyContinue
    $groupTag = ''; $category = ''; $ou = ''; $mail = ''; $cc = ''
    if ($support) {
        $groupTag = ConvertTo-SelfXTicketDeviceValue $support.GroupTag 'GroupTag'
        $category = ConvertTo-SelfXTicketDeviceValue $support.Category 'Category'
        $mailValue = ("$($support.TicketMail)").Trim()
        $ccValue = ("$($support.TicketCc)").Trim()
        if (Test-SelfXTicketAddress $mailValue) { $mail = $mailValue }
        if ($mail -and (Test-SelfXTicketAddress $ccValue)) { $cc = $ccValue }
    }
    if ($policy) {
        $distinguishedName = "$($policy.'Distinguished-Name')"
        # OU part of the distinguished name (without the computer name)
        $ou = ConvertTo-SelfXTicketDeviceValue ($distinguishedName -replace '^[^,]*,', '') 'OU'
    }
    return [pscustomobject]@{ GroupTag = $groupTag; Category = $category; OU = $ou; Mail = $mail; Cc = $cc }
}

function Get-SelfXSupportContact {
    # Support addresses of the window, from the configuration only (Tool_Config.xml).
    #  - Client (Windows 11): Support_Mail; Ticket_Mail (empty = Support_Mail); the ticket routing is used (Ticket_Config.xml and the
    #    address set for the device in the registry, Get-SelfXTicketTarget).
    #  - TerminalServer (Windows Server): TerminalServer_Support_Mail is the support e-mail, the ticket recipient and the address in the
    #    help window. The ticket routing is never used there: the support unit, the group tag and the device class describe a device of
    #    one person, not a server for many. Without one plain address in TerminalServer_Support_Mail Support_Mail and Ticket_Mail stay,
    #    still without routing, and Valid is $false so that the window can log it.
    # Needs Test-SelfXTicketAddress (TicketMail.ps1).
    param(
        [string]$Mode,
        [AllowNull()][AllowEmptyString()][string]$SupportMail,
        [AllowNull()][AllowEmptyString()][string]$TicketMail,
        [AllowNull()][AllowEmptyString()][string]$TerminalServerMail
    )
    $support = "$SupportMail".Trim()
    $ticket = "$TicketMail".Trim()
    if (-not $ticket) { $ticket = $support }
    if ($Mode -cne 'TerminalServer') {
        return [pscustomobject]@{ SupportMail = $support; TicketMail = $ticket; UseRouting = $true; Source = 'Client'; Valid = $true }
    }
    $fixed = "$TerminalServerMail".Trim()
    if (Test-SelfXTicketAddress $fixed) {
        return [pscustomobject]@{ SupportMail = $fixed; TicketMail = $fixed; UseRouting = $false; Source = 'TerminalServer'; Valid = $true }
    }
    return [pscustomobject]@{ SupportMail = $support; TicketMail = $ticket; UseRouting = $false; Source = 'TerminalServerFallback'; Valid = $false }
}

function Get-SelfXTicketTarget {
    # Recipient, Cc and support unit for this device: 1. the address set for this device in the registry (TicketMail,
    # TicketCc), 2. the first matching rule of Ticket_Config.xml, 3. DefaultMail.
    param(
        [Parameter(Mandatory = $true)][string]$DefaultMail,
        $Config,
        $DeviceValues = (Get-SelfXTicketDeviceValues)
    )
    $target = [pscustomobject]@{
        To = $DefaultMail; Cc = ''; Unit = ''; GroupTag = $DeviceValues.GroupTag; Category = $DeviceValues.Category; Source = 'Default'
    }
    if ($DeviceValues.Mail) {
        $target.To = $DeviceValues.Mail; $target.Cc = $DeviceValues.Cc; $target.Source = 'Registry'
        return $target
    }
    if ($Config) {
        $resolved = Resolve-SelfXTicketUnit -Config $Config -GroupTag $DeviceValues.GroupTag -Category $DeviceValues.Category -OU $DeviceValues.OU
        if ($resolved) { $target.To = $resolved.Mail; $target.Cc = $resolved.Cc; $target.Unit = $resolved.Unit; $target.Source = $resolved.Source }
    }
    return $target
}

function Save-SelfXTicketAttachment {
    # Device information as a file for the attachment. Returns the path.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [string]$DeviceName,
        [string]$Destination = (Join-Path $env:LOCALAPPDATA 'SelfX\Reports'),
        [datetime]$Timestamp = [datetime]::Now
    )
    $name = if ($DeviceName -match '^[A-Za-z0-9-]{1,63}\z') { $DeviceName } else { 'device' }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Destination -File -Filter 'TicketInfo-*.txt' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $path = Join-Path $Destination ('TicketInfo-{0}-{1}.txt' -f $name, $Timestamp.ToString('yyyyMMdd-HHmmss'))
    [IO.File]::WriteAllText($path, $Text, (New-Object Text.UTF8Encoding($true)))
    return $path
}

function Send-SelfXTicket {
    <#
    .SYNOPSIS
        Opens the ticket e-mail. Returns Status (Outlook, Manual or Error), Path (attached file) and Message.
        Ticket is the result of New-SelfXTicket, To the address from the configuration.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$To,
        [Parameter(Mandatory = $true)]$Ticket,
        [AllowEmptyString()][string]$DeviceInfoText = '',
        [string]$DeviceName = $env:COMPUTERNAME,
        [string]$Destination = (Join-Path $env:LOCALAPPDATA 'SelfX\Reports'),
        [string]$Cc = ''
    )
    if (-not (Test-SelfXTicketAddress $To)) {
        return [pscustomobject]@{ Status = 'Error'; Path = $null; Message = 'Invalid recipient address.' }
    }
    if ($Cc -and -not (Test-SelfXTicketAddress $Cc)) {
        return [pscustomobject]@{ Status = 'Error'; Path = $null; Message = 'Invalid Cc address.' }
    }
    try {
        $file = Save-SelfXTicketAttachment -Text $DeviceInfoText -DeviceName $DeviceName -Destination $Destination
    } catch {
        return [pscustomobject]@{ Status = 'Error'; Path = $null; Message = $_.Exception.Message }
    }
    $errors = @()
    try {
        New-SelfXOutlookMail -To $To -Cc $Cc -Subject $Ticket.Subject -Body $Ticket.Body -Attachment $file
        return [pscustomobject]@{ Status = 'Outlook'; Path = $file; Message = '' }
    } catch { $errors += "Outlook: $($_.Exception.Message)" }
    try {
        $link = ConvertTo-SelfXTicketMailto -To $To -Cc $Cc -Subject $Ticket.Subject -Body $Ticket.Body
        Start-Process -FilePath $link
        Start-Process -FilePath ([IO.Path]::Combine($env:SystemRoot, 'explorer.exe')) -ArgumentList "/select,`"$file`""
        return [pscustomobject]@{ Status = 'Manual'; Path = $file; Message = ($errors -join ' / ') }
    } catch {
        $errors += "mailto: $($_.Exception.Message)"
        return [pscustomobject]@{ Status = 'Error'; Path = $file; Message = ($errors -join ' / ') }
    }
}
