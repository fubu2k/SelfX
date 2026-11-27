<#
.SYNOPSIS
    Functions for the publisher mode of the AppLocker and App Control (WDAC) tools: signer state of files, one AppLocker publisher
    rule per rule collection, and the checks of the generated policies.

.DESCRIPTION
    Dot-sourced by New-SelfXAppLockerRules.ps1, New-SelfXWdacPolicy.ps1 and by the tests. The file only defines functions; it
    changes nothing when it is dot-sourced and calls no AppLocker or ConfigCI cmdlet, so the logic can be tested on any computer.

      Get-SelfXFileSignerState                Reads the Authenticode signature of a file (Get-AuthenticodeSignature) and returns the state
                                              Signed (status Valid), Unsigned (status NotSigned) or Invalid (any other status).
      ConvertTo-SelfXSignerState              The same decision for a signature object (used by the function above and by the tests).
      Get-SelfXSignerSetProblem               Checks the states of a set of files: no invalid signature, optionally no unsigned file,
                                              one signer only (unless several are allowed). Returns the reason or $null.
      Get-SelfXSignedPackageProblem           Checks that the entry script of a package (Install.ps1) is signed: only then the package counts as
                                              signed. Libraries of other publishers in Bin alone (for example from Microsoft) do not make it so.
      Get-SelfXPublisherNameProblem           Checks a publisher name before it becomes a rule: not empty, no wildcard, no control character.
      New-SelfXAppLockerPublisherPolicyXml    One publisher rule (Allow, SID S-1-1-0, no version range) for each of the rule collections
                                              Exe, Dll and Script.
      Get-SelfXAppLockerPublisherPolicyProblem  Checks an AppLocker policy text against the structure above. Returns the problems (callers wrap the call in @(...)).
      Get-SelfXWdacPublisherPolicyProblem     Checks a WDAC supplemental policy created with the level Publisher. Returns the problems (callers wrap the call in @(...)).
      Get-SelfXWdacSignerName                 The publisher names (CertPublisher) of the signer rules of a WDAC policy, for the output.

    Every check stops (fail closed) or returns a problem when something is not as expected; none of them returns "fine" after an error.
    XML is read without DTD and without an external resolver. No account is addressed by name: the rules use the well-known SID S-1-1-0
    ("Everyone"), whose name is localized.

    Limit: an AppLocker publisher rule and a WDAC publisher rule trust the signer, not a version or a file. Anyone who can sign with a
    certificate of this publisher gets a file allowed. Keep the signing certificate protected (docs\Installation.md, "Set up once instead
    of per version").

.NOTES
    Name    : SelfXPublisherRules.ps1
    Package : tools
    Context : Build machine / administrator PC (not installed, not shipped)
    Version : 1.0.0
    Works in Windows PowerShell 5.1 and PowerShell 7.

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-27  fubu2k               Initial version: publisher rules for AppLocker and App Control (step 9)
#>

# The well-known SID of "Everyone" (the name is localized: "Jeder" on German Windows).
$script:SelfXEveryoneSid = 'S-1-1-0'

# The AppLocker rule collections that get a publisher rule.
$script:SelfXAppLockerCollections = @('Exe', 'Dll', 'Script')

# Files that carry a signature the tools look at (programs, libraries, scripts).
$script:SelfXSignedFileExtensions = @('.exe', '.dll', '.ps1', '.psm1', '.psd1')

$script:SelfXWdacNamespace = 'urn:schemas-microsoft-com:sipolicy'

function ConvertTo-SelfXXmlDocument {
    # Reads XML text without DTD and without an external resolver (no entity expansion, no network access).
    param([Parameter(Mandatory)][string]$Text)
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader($Text)), $settings)
    try {
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
        return $document
    }
    finally { $reader.Close() }
}

function ConvertTo-SelfXSignerState {
    # Decides from a signature object (status, signer certificate) what the signature of a file is worth.
    #   Unsigned : the file has no signature (status NotSigned).
    #   Signed   : the signature is valid (status Valid) and names a signer certificate.
    #   Invalid  : every other status (not trusted, changed file, unknown error, ...). Such a file is neither trusted nor allowed by hash.
    param(
        [Parameter(Mandatory)][string]$Name,
        $Signature
    )
    $status = $(if ($null -eq $Signature) { 'UnknownError' } else { [string]$Signature.Status })
    $thumbprint = ''
    if ($status -eq 'Valid') {
        $certificate = $Signature.SignerCertificate
        if ($null -eq $certificate -or [string]::IsNullOrEmpty([string]$certificate.Thumbprint)) { $status = 'UnknownError' }
        else { $thumbprint = ([string]$certificate.Thumbprint).ToUpperInvariant() }
    }
    $state = 'Invalid'
    if ($status -eq 'Valid') { $state = 'Signed' }
    elseif ($status -eq 'NotSigned') { $state = 'Unsigned' }
    return [pscustomobject]@{ Name = $Name; State = $state; Status = $status; Thumbprint = $thumbprint }
}

function Get-SelfXFileSignerState {
    # The state of the signature of one file. Only the file name (not the path) is kept in the result.
    param([Parameter(Mandatory)][string]$Path)
    $name = Split-Path -Leaf $Path
    $signature = $null
    try { $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop }
    catch { $signature = $null }
    return (ConvertTo-SelfXSignerState -Name $name -Signature $signature)
}

function Get-SelfXSignerSetProblem {
    # Checks the signer states of a set of files; returns the reason (a short text) or $null when the set is fine.
    #   - A file with an invalid signature is always a problem (the signature must not be left out or hashed around).
    #   - RequireSigned: a file without signature is a problem too.
    #   - More than one signer is a problem unless AllowMultipleSigners is set (a package is signed with one certificate).
    #   - No file at all, or no signed file at all, is a problem: a publisher rule needs a signer.
    param(
        $State,
        [switch]$RequireSigned,
        [switch]$AllowMultipleSigners
    )
    $list = @($State)
    if ($list.Count -eq 0) { return 'No file to check.' }
    $invalid = @($list | Where-Object { $_.State -eq 'Invalid' })
    if ($invalid.Count -gt 0) {
        $first = $invalid[0]
        return ("The signature of {0} is not valid (status {1}); {2} file(s) are affected. Sign the files again or use the mode Hash." -f $first.Name, $first.Status, $invalid.Count)
    }
    $unsigned = @($list | Where-Object { $_.State -eq 'Unsigned' })
    if ($RequireSigned -and $unsigned.Count -gt 0) {
        return ("{0} file(s) are not signed (first: {1}). The publisher mode needs signed files; sign them or use the mode Hash." -f $unsigned.Count, $unsigned[0].Name)
    }
    $signed = @($list | Where-Object { $_.State -eq 'Signed' })
    if ($signed.Count -eq 0) { return 'No file is signed. The publisher mode needs at least one signed file; use the mode Hash for an unsigned package.' }
    $signers = @($signed | ForEach-Object { $_.Thumbprint } | Sort-Object -Unique)
    if ($signers.Count -gt 1 -and -not $AllowMultipleSigners) {
        return ("The files are signed by {0} different certificates. A package is signed by one certificate; check the files or allow several signers on purpose." -f $signers.Count)
    }
    return $null
}

function Get-SelfXSignedPackageProblem {
    # A package counts as signed when its entry script is signed (Install.ps1 is the file that Intune starts, and the mode signature
    # of Install.ps1 requires it). A package whose only signed files are libraries of other publishers (for example Microsoft.Windows.SDK.NET.dll)
    # is an unsigned package: a publisher rule for such a library would trust the other publisher, not the company.
    param(
        $State,
        [string]$EntryScript = 'Install.ps1'
    )
    $entry = @(@($State) | Where-Object { $_.Name -eq $EntryScript })
    if ($entry.Count -eq 0) { return "$EntryScript was not found in the package." }
    if (@($entry | Where-Object { $_.State -ne 'Signed' }).Count -gt 0) { return "$EntryScript is not signed, so the package does not count as signed. Sign the package or use the mode Hash." }
    return $null
}

function Get-SelfXPublisherNameProblem {
    # Why a publisher name cannot become a rule; $null when it can. The name is the subject text that AppLocker reads from the signature
    # (for example "O=CONTOSO, L=BERLIN, C=DE"). A wildcard would allow every publisher.
    param([string]$PublisherName)
    if ([string]::IsNullOrWhiteSpace($PublisherName)) { return 'The publisher name is empty.' }
    if ($PublisherName.Length -gt 1000) { return 'The publisher name is longer than 1000 characters.' }
    if ($PublisherName -match '[\x00-\x1F\x7F]') { return 'The publisher name contains a control character.' }
    if ($PublisherName -ne $PublisherName.Trim()) { return 'The publisher name starts or ends with a space.' }
    if ($PublisherName.Contains('*')) { return 'The publisher name contains a wildcard.' }
    if (-not $PublisherName.Contains('=')) { return 'The publisher name is not a certificate subject (attribute=value).' }
    return $null
}

function Get-SelfXRuleId {
    # A fixed GUID for a rule: the same publisher and collection give the same ID in every build, so a new policy replaces the old
    # rule instead of being added next to it.
    param([Parameter(Mandatory)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) } finally { $sha.Dispose() }
    $bytes = New-Object byte[] 16
    [Array]::Copy($hash, 0, $bytes, 0, 16)
    return (New-Object System.Guid(, $bytes)).ToString()
}

function New-SelfXAppLockerPublisherPolicyXml {
    # An AppLocker policy with one publisher rule (Allow, SID S-1-1-0) for each of the collections Exe, Dll and Script.
    # The rule has no product, no file name and no version range ("*"): it stays the same for every version of SelfX.
    # The XML is built with the DOM, so no text of the parameters can become markup.
    param(
        [Parameter(Mandatory)][string]$PublisherName,
        [Parameter(Mandatory)][string]$RuleNamePrefix
    )
    $problem = Get-SelfXPublisherNameProblem -PublisherName $PublisherName
    if ($problem) { throw $problem }
    if ([string]::IsNullOrWhiteSpace($RuleNamePrefix) -or $RuleNamePrefix.Length -gt 100 -or $RuleNamePrefix -match '[\x00-\x1F\x7F]') {
        throw 'The rule name prefix must have 1 to 100 characters and no control character.'
    }
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $policy = $document.CreateElement('AppLockerPolicy')
    $policy.SetAttribute('Version', '1')
    [void]$document.AppendChild($policy)
    foreach ($collectionType in $script:SelfXAppLockerCollections) {
        $collection = $document.CreateElement('RuleCollection')
        $collection.SetAttribute('Type', $collectionType)
        $collection.SetAttribute('EnforcementMode', 'NotConfigured')
        $rule = $document.CreateElement('FilePublisherRule')
        $rule.SetAttribute('Id', (Get-SelfXRuleId -Text "SelfX publisher rule|$collectionType|$PublisherName"))
        $rule.SetAttribute('Name', "$RuleNamePrefix publisher rule ($collectionType)")
        $rule.SetAttribute('Description', "Allows $collectionType files signed by this publisher, every version.")
        $rule.SetAttribute('UserOrGroupSid', $script:SelfXEveryoneSid)
        $rule.SetAttribute('Action', 'Allow')
        $conditions = $document.CreateElement('Conditions')
        $condition = $document.CreateElement('FilePublisherCondition')
        $condition.SetAttribute('PublisherName', $PublisherName)
        $condition.SetAttribute('ProductName', '*')
        $condition.SetAttribute('BinaryName', '*')
        $range = $document.CreateElement('BinaryVersionRange')
        $range.SetAttribute('LowSection', '*')
        $range.SetAttribute('HighSection', '*')
        [void]$condition.AppendChild($range)
        [void]$conditions.AppendChild($condition)
        [void]$rule.AppendChild($conditions)
        [void]$collection.AppendChild($rule)
        [void]$policy.AppendChild($collection)
    }
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.OmitXmlDeclaration = $true
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $writer = New-Object System.IO.StringWriter
    $xmlWriter = [System.Xml.XmlWriter]::Create($writer, $settings)
    try { $document.Save($xmlWriter) } finally { $xmlWriter.Close() }
    return $writer.ToString()
}

function Get-SelfXAppLockerPublisherPolicyProblem {
    # Checks an AppLocker policy text against what publisher mode must produce. Returns the problems (an empty list when it is fine).
    param([Parameter(Mandatory)][string]$PolicyXml)
    $problems = New-Object System.Collections.Generic.List[string]
    $document = $null
    try { $document = ConvertTo-SelfXXmlDocument -Text $PolicyXml }
    catch { return 'The policy is not well-formed XML (or contains a DTD).' }
    if ($document.DocumentElement.LocalName -ne 'AppLockerPolicy') { return 'The root element is not AppLockerPolicy.' }
    $collections = @($document.SelectNodes('/AppLockerPolicy/RuleCollection'))
    $types = @($collections | ForEach-Object { $_.GetAttribute('Type') })
    foreach ($expected in $script:SelfXAppLockerCollections) {
        if (@($types | Where-Object { $_ -eq $expected }).Count -ne 1) { $problems.Add("The rule collection $expected is missing or appears more than once.") }
    }
    if ($collections.Count -ne $script:SelfXAppLockerCollections.Count) { $problems.Add("The policy has $($collections.Count) rule collections instead of $($script:SelfXAppLockerCollections.Count).") }
    $publishers = New-Object System.Collections.Generic.List[string]
    foreach ($collection in $collections) {
        $type = $collection.GetAttribute('Type')
        $children = @($collection.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
        $rules = @($children | Where-Object { $_.LocalName -eq 'FilePublisherRule' })
        if ($rules.Count -ne 1 -or $children.Count -ne 1) { $problems.Add("The collection $type must hold exactly one publisher rule and nothing else (found $($children.Count) rule(s)).") }
        foreach ($rule in $rules) {
            if ($rule.GetAttribute('UserOrGroupSid') -ne $script:SelfXEveryoneSid) { $problems.Add("The rule of $type does not apply to the SID $($script:SelfXEveryoneSid).") }
            if ($rule.GetAttribute('Action') -ne 'Allow') { $problems.Add("The rule of $type is not an Allow rule.") }
            $conditionNodes = @($rule.SelectNodes('Conditions/FilePublisherCondition'))
            if ($conditionNodes.Count -ne 1) { $problems.Add("The rule of $type must have exactly one publisher condition."); continue }
            $condition = $conditionNodes[0]
            if ($condition.GetAttribute('ProductName') -ne '*' -or $condition.GetAttribute('BinaryName') -ne '*') { $problems.Add("The rule of $type is bound to a product or file name.") }
            $ranges = @($condition.SelectNodes('BinaryVersionRange'))
            if ($ranges.Count -ne 1 -or $ranges[0].GetAttribute('LowSection') -ne '*' -or $ranges[0].GetAttribute('HighSection') -ne '*') { $problems.Add("The rule of $type is bound to a version.") }
            $nameProblem = Get-SelfXPublisherNameProblem -PublisherName $condition.GetAttribute('PublisherName')
            if ($nameProblem) { $problems.Add("The rule of ${type}: $nameProblem") }
            $publishers.Add($condition.GetAttribute('PublisherName'))
        }
    }
    if (@($publishers | Sort-Object -Unique).Count -gt 1) { $problems.Add('The rules name different publishers.') }
    if ($document.SelectNodes('//FileHashRule').Count -gt 0) { $problems.Add('The policy contains hash rules.') }
    if ($document.SelectNodes('//FilePathRule').Count -gt 0) { $problems.Add('The policy contains path rules.') }
    return $problems.ToArray()
}

function Get-SelfXWdacPublisherPolicyProblem {
    # Checks a WDAC supplemental policy that New-CIPolicy created with -Level Publisher -Fallback Hash. Returns the problems.
    #   ExpectHashRules  : $true when unsigned files were scanned (then hash rules must exist), $false when every file is signed
    #                      (then no hash rule may exist: a hash rule next to a signer rule would again pin one version).
    #   SignedFileName   : names of the signed files. A hash rule named after one of them is a problem (best effort: New-CIPolicy
    #                      names a hash rule after the file in its FriendlyName).
    param(
        [Parameter(Mandatory)][string]$PolicyXml,
        [Parameter(Mandatory)][bool]$ExpectHashRules,
        [string[]]$SignedFileName = @()
    )
    $problems = New-Object System.Collections.Generic.List[string]
    $document = $null
    try { $document = ConvertTo-SelfXXmlDocument -Text $PolicyXml }
    catch { return 'The policy is not well-formed XML (or contains a DTD).' }
    $namespaces = New-Object System.Xml.XmlNamespaceManager($document.NameTable)
    $namespaces.AddNamespace('ci', $script:SelfXWdacNamespace)
    $signers = @($document.SelectNodes('/ci:SiPolicy/ci:Signers/ci:Signer', $namespaces))
    if ($signers.Count -eq 0) { $problems.Add('The policy has no signer rule.') }
    $allowedIds = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($node in @($document.SelectNodes('//ci:AllowedSigners/ci:AllowedSigner', $namespaces))) { [void]$allowedIds.Add($node.GetAttribute('SignerId')) }
    foreach ($signer in $signers) {
        $id = $signer.GetAttribute('ID')
        if ($signer.SelectNodes('ci:CertRoot', $namespaces).Count -ne 1) { $problems.Add("The signer $id has no certification authority (CertRoot).") }
        $publisher = $signer.SelectSingleNode('ci:CertPublisher', $namespaces)
        if ($null -eq $publisher -or [string]::IsNullOrWhiteSpace($publisher.GetAttribute('Value'))) { $problems.Add("The signer $id has no publisher (CertPublisher): it would allow every file of the authority.") }
        if ($signer.SelectNodes('ci:FileAttribRef', $namespaces).Count -gt 0) { $problems.Add("The signer $id is bound to a file attribute (version or file name).") }
        if (-not $allowedIds.Contains($id)) { $problems.Add("The signer $id is not allowed in any signing scenario.") }
    }
    if ($document.SelectNodes('//ci:DeniedSigners', $namespaces).Count -gt 0) { $problems.Add('The policy has denied signers.') }
    $hashRules = @($document.SelectNodes('/ci:SiPolicy/ci:FileRules/ci:Allow[@Hash]', $namespaces))
    if ($ExpectHashRules -and $hashRules.Count -eq 0) { $problems.Add('Unsigned files were scanned but the policy has no hash rule for them.') }
    if (-not $ExpectHashRules -and $hashRules.Count -gt 0) { $problems.Add("Every file is signed but the policy has $($hashRules.Count) hash rule(s).") }
    foreach ($name in @($SignedFileName)) {
        if ([string]::IsNullOrEmpty($name)) { continue }
        foreach ($rule in $hashRules) {
            $friendly = $rule.GetAttribute('FriendlyName')
            if ($friendly -and $friendly.StartsWith($name + ' ', [StringComparison]::OrdinalIgnoreCase)) { $problems.Add("The signed file $name also has a hash rule."); break }
        }
    }
    $otherRules = @($document.SelectNodes('/ci:SiPolicy/ci:FileRules/*[not(self::ci:Allow[@Hash])]', $namespaces))
    if ($otherRules.Count -gt 0) { $problems.Add("The policy has $($otherRules.Count) file rule(s) that are not plain hash rules.") }
    return $problems.ToArray()
}

function Get-SelfXWdacSignerName {
    # The publisher names of the signer rules of a WDAC policy (for the output; the administrator sees whom the policy trusts).
    param([Parameter(Mandatory)][string]$PolicyXml)
    $document = ConvertTo-SelfXXmlDocument -Text $PolicyXml
    $namespaces = New-Object System.Xml.XmlNamespaceManager($document.NameTable)
    $namespaces.AddNamespace('ci', $script:SelfXWdacNamespace)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($node in @($document.SelectNodes('/ci:SiPolicy/ci:Signers/ci:Signer/ci:CertPublisher', $namespaces))) { $names.Add($node.GetAttribute('Value')) }
    return @($names.ToArray() | Sort-Object -Unique)
}
