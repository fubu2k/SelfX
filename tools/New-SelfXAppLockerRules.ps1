<#
.SYNOPSIS
    Writes AppLocker rules (Allow, everyone) for the given program files to an XML file: hash rules (default) or publisher rules.

.DESCRIPTION
    Called by Build-SelfXBinaries.ps1. Needs the AppLocker cmdlets, which exist in Windows PowerShell 5.1 only
    (PowerShell 7 reaches them through a compatibility layer that cannot pass a list of paths). Build-SelfXBinaries.ps1
    therefore starts this script in powershell.exe when it runs in PowerShell 7.
    The rules apply to the well-known SID S-1-1-0 ("Everyone"). The name "Everyone" is not used: it is localized
    ("Jeder" on German Windows) and cannot be resolved there.
    AppLocker uses its own Authenticode SHA256 of a file, not the file SHA256 of SelfX.Binaries.json. The file is checked to
    hold one hash rule for every program; anything else is an error.

    Mode Hash (default): one hash rule for every file. The rules change with every build; replace them for every new version.

    Mode Publisher: for a signed package (docs\Installation.md, "Set up once instead of per version"). The files in PathList must all
    be signed (status Valid) by the same certificate; give at least one program, one library and one script of the package. The
    script writes ONE publisher rule for each rule collection (Exe, Dll, Script) with the publisher name that AppLocker reads from the
    signature: no product, no file name, no version range. The rules have fixed IDs, so a new build gives the same rules and they
    need not be replaced for a new version. Hash rules are not written. A file without signature, an invalid signature or files
    of different signers are errors (use the mode Hash for an unsigned package). The publisher name is taken from the file, never from
    a parameter.

.PARAMETER PathList
    The program files, separated by the character | (a character that no Windows path contains). A string because
    powershell.exe -File cannot pass an array. In the mode Publisher: signed files, from which the publisher is read.

.PARAMETER OutputFile
    The XML file to write (UTF-8 without BOM). Replaced when it exists.

.PARAMETER RuleNamePrefix
    Start of the name of every rule, for example "SelfX 3.0.1". In the mode Publisher use a name without a version, for example
    "SelfX", because the rules are the same for every version.

.PARAMETER Mode
    Hash (default) or Publisher.

.NOTES
    Name    : New-SelfXAppLockerRules.ps1
    Package : tools
    Context : Build machine (any user; the cmdlets need no administrator rights)
    Version : 1.1.0
    Exit code: 0 = written, 1 = error (the message is written to the output)

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-24  fubu2k               Initial version: SID instead of the name Everyone, runs in Windows PowerShell
    1.1.0    2026-11-27  fubu2k               New -Mode Publisher: one publisher rule per rule collection (Exe, Dll, Script) from the signature, no version
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PathList,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [Parameter(Mandatory = $true)][string]$RuleNamePrefix,
    [ValidateSet('Hash', 'Publisher')][string]$Mode = 'Hash'
)
$ErrorActionPreference = 'Stop'
try {
    # Functions of the publisher mode (only definitions; calls no AppLocker cmdlet).
    . (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'SelfXPublisherRules.ps1')
    if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run this script in Windows PowerShell 5.1 (powershell.exe): the AppLocker cmdlets do not accept a list of paths in PowerShell 7.' }
    if (@(Get-Command -Name Get-AppLockerFileInformation, New-AppLockerPolicy -ErrorAction SilentlyContinue).Count -ne 2) { throw 'The AppLocker cmdlets are not available on this computer.' }
    $paths = @($PathList.Split('|') | Where-Object { $_ })
    if ($paths.Count -eq 0) { throw 'No program file given.' }
    foreach ($path in $paths) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "File not found: $path" } }
    if ($Mode -eq 'Publisher') {
        if (-not (Get-Command -Name Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) { throw 'The cmdlet Get-AuthenticodeSignature is missing (module Microsoft.PowerShell.Security). Run the script in Windows PowerShell 5.1 (powershell.exe).' }
        # The signature of every file must be valid, all files must have the same signer, and AppLocker must name a publisher.
        $problem = Get-SelfXSignerSetProblem -State @($paths | ForEach-Object { Get-SelfXFileSignerState -Path $_ }) -RequireSigned
        if ($problem) { throw $problem }
        $publisherNames = New-Object System.Collections.Generic.List[string]
        foreach ($path in $paths) {
            $information = @(Get-AppLockerFileInformation -Path $path)
            $publisher = $(if ($information.Count -eq 1) { $information[0].Publisher } else { $null })
            $name = $(if ($null -ne $publisher) { [string]$publisher.PublisherName } else { '' })
            if ([string]::IsNullOrEmpty($name)) { throw "AppLocker reads no publisher from $(Split-Path -Leaf $path) although the signature is valid." }
            if (-not $publisherNames.Contains($name)) { $publisherNames.Add($name) }
        }
        if ($publisherNames.Count -ne 1) { throw "AppLocker reads $($publisherNames.Count) different publishers from the files; the rules need exactly one." }
        $policy = New-SelfXAppLockerPublisherPolicyXml -PublisherName $publisherNames[0] -RuleNamePrefix $RuleNamePrefix
        $problems = @(Get-SelfXAppLockerPublisherPolicyProblem -PolicyXml $policy)
        if ($problems.Count -gt 0) { throw "The publisher rules are not as expected: $($problems[0])" }
        [IO.File]::WriteAllText($OutputFile, $policy, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output "$($script:SelfXAppLockerCollections.Count) publisher rules written (one for each of Exe, Dll and Script; publisher: $($publisherNames[0]))."
        exit 0
    }
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
