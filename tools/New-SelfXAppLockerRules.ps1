<#
.SYNOPSIS
    Writes AppLocker hash rules (Allow, everyone) for the given program files to an XML file.

.DESCRIPTION
    Called by Build-SelfXBinaries.ps1. Needs the AppLocker cmdlets, which exist in Windows PowerShell 5.1 only
    (PowerShell 7 reaches them through a compatibility layer that cannot pass a list of paths). Build-SelfXBinaries.ps1
    therefore starts this script in powershell.exe when it runs in PowerShell 7.
    The rules apply to the well-known SID S-1-1-0 ("Everyone"). The name "Everyone" is not used: it is localized
    ("Jeder" on German Windows) and cannot be resolved there.
    AppLocker uses its own Authenticode SHA256 of a file, not the file SHA256 of SelfX.Binaries.json. The file is checked to
    hold one hash rule for every program; anything else is an error.

.PARAMETER PathList
    The program files, separated by the character | (a character that no Windows path contains). A string because
    powershell.exe -File cannot pass an array.

.PARAMETER OutputFile
    The XML file to write (UTF-8 without BOM). Replaced when it exists.

.PARAMETER RuleNamePrefix
    Start of the name of every rule, for example "SelfX 3.0.1".

.NOTES
    Name    : New-SelfXAppLockerRules.ps1
    Package : tools
    Context : Build machine (any user; the cmdlets need no administrator rights)
    Version : 1.0.0
    Exit code: 0 = written, 1 = error (the message is written to the output)

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-24  fubu2k               Initial version: SID instead of the name Everyone, runs in Windows PowerShell
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PathList,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [Parameter(Mandatory = $true)][string]$RuleNamePrefix
)
$ErrorActionPreference = 'Stop'
try {
    if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run this script in Windows PowerShell 5.1 (powershell.exe): the AppLocker cmdlets do not accept a list of paths in PowerShell 7.' }
    if (@(Get-Command -Name Get-AppLockerFileInformation, New-AppLockerPolicy -ErrorAction SilentlyContinue).Count -ne 2) { throw 'The AppLocker cmdlets are not available on this computer.' }
    $paths = @($PathList.Split('|') | Where-Object { $_ })
    if ($paths.Count -eq 0) { throw 'No program file given.' }
    foreach ($path in $paths) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "File not found: $path" } }
    $policy = Get-AppLockerFileInformation -Path $paths | New-AppLockerPolicy -RuleType Hash -User 'S-1-1-0' -RuleNamePrefix $RuleNamePrefix -Xml
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $document.LoadXml($policy)
    $rules = @($document.SelectNodes('//FileHashRule'))
    if ($rules.Count -ne $paths.Count) { throw "Expected $($paths.Count) hash rules, AppLocker returned $($rules.Count)." }
    foreach ($rule in $rules) { if ($rule.GetAttribute('UserOrGroupSid') -ne 'S-1-1-0' -or $rule.GetAttribute('Action') -ne 'Allow') { throw 'A hash rule is not an Allow rule for S-1-1-0.' } }
    [IO.File]::WriteAllText($OutputFile, $policy, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output "$($rules.Count) hash rules written."
}
catch {
    Write-Output $_.Exception.Message
    exit 1
}
