<#
.SYNOPSIS
    Shows which support unit and recipient the ticket e-mail of SelfX would use for a given group tag, OU and category.

.DESCRIPTION
    For administrators, before the package is distributed. Reads Ticket_Config.xml (default: the one in
    SelfX Service\Sources) and prints the entries that are not valid, the number of units and rules, and the
    result for the given values. Nothing is sent, nothing is changed, no registry value is read: the values
    are the parameters.

.EXAMPLE
    .\Test-SelfXTicketRouting.ps1 -GroupTag 'DE-IT1-BER' -Category 'Category-A'

.NOTES
    Name    : Test-SelfXTicketRouting.ps1
    Package : tools
    Context : Build machine (any user)
    Version : 2.8.6

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.6    2026-11-22  fubu2k               Initial version
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\SelfX Service\Sources\Ticket_Config.xml'),
    [string]$GroupTag,
    [string]$Category,
    [string]$OU
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\SelfX Service\Sources\TicketMail.ps1')
$config = Read-SelfXTicketConfig -Path $ConfigPath
Write-Output "File: $ConfigPath"
Write-Output ("Units: {0}, rules: {1}" -f @($config.Units.Keys).Count, @($config.Rules).Count)
foreach ($message in $config.Errors) { Write-Warning $message }
$result = Resolve-SelfXTicketUnit -Config $config -GroupTag $GroupTag -Category $Category -OU $OU
if ($result) {
    Write-Output "Unit: $($result.Unit)"
    Write-Output "To:   $($result.Mail)"
    Write-Output "Cc:   $($result.Cc)"
    Write-Output "By:   $($result.Source)"
} else {
    Write-Output 'No rule matches: the e-mail goes to Ticket_Mail (or Support_Mail) of Tool_Config.xml.'
}
if ($config.Errors.Count) { exit 1 }
