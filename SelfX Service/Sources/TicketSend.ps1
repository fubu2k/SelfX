<#
.SYNOPSIS
    Opens the ticket e-mail in the mail program of the user (GUI helper).

.DESCRIPTION
    Needs TicketMail.ps1 (ticket model) and SupportReport.ps1 (Outlook helper) in the same session.
    Loaded by the SelfX GUI in the signed-in user session; defining these functions alone performs no
    action. Send-SelfXTicket:
      1. checks the recipient (it comes from the package configuration, never from the user),
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
    Version : 2.8.5

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.5    2026-11-22  fubu2k               Initial version
#>

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
        [string]$Destination = (Join-Path $env:LOCALAPPDATA 'SelfX\Reports')
    )
    if (-not (Test-SelfXTicketAddress $To)) {
        return [pscustomobject]@{ Status = 'Error'; Path = $null; Message = 'Invalid recipient address.' }
    }
    try {
        $file = Save-SelfXTicketAttachment -Text $DeviceInfoText -DeviceName $DeviceName -Destination $Destination
    } catch {
        return [pscustomobject]@{ Status = 'Error'; Path = $null; Message = $_.Exception.Message }
    }
    $errors = @()
    try {
        New-SelfXOutlookMail -To $To -Subject $Ticket.Subject -Body $Ticket.Body -Attachment $file
        return [pscustomobject]@{ Status = 'Outlook'; Path = $file; Message = '' }
    } catch { $errors += "Outlook: $($_.Exception.Message)" }
    try {
        $link = ConvertTo-SelfXTicketMailto -To $To -Subject $Ticket.Subject -Body $Ticket.Body
        Start-Process -FilePath $link
        Start-Process -FilePath ([IO.Path]::Combine($env:SystemRoot, 'explorer.exe')) -ArgumentList "/select,`"$file`""
        return [pscustomobject]@{ Status = 'Manual'; Path = $file; Message = ($errors -join ' / ') }
    } catch {
        $errors += "mailto: $($_.Exception.Message)"
        return [pscustomobject]@{ Status = 'Error'; Path = $file; Message = ($errors -join ' / ') }
    }
}
