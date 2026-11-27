<#
.SYNOPSIS
    Creates an optional App Control for Business (WDAC) supplemental policy for SelfX Service: hash rules (default) or signer rules.

.DESCRIPTION
    Nothing in the SelfX package depends on this script: WDAC support is optional. The script reads the package folder
    "SelfX Service" (Install.ps1, Detection.ps1, Uninstall.ps1, Sources and Bin, as packaged by New-SelfXIntuneWin.ps1)
    and lets New-CIPolicy create hash rules for every program, library and script. The result is a supplemental
    policy for a base policy of your organization, so the unsigned SelfX files (decision 2026-11-22: allow them by
    hash, no certificate) and the scripts keep running in FullLanguage mode when the base policy enforces script rules.

    By default the policy has a fixed policy ID, so a new version replaces the old one instead of being added next to it. The mode
    (audit or enforced) is the mode of the BASE policy: a supplemental policy does not set it. Roll out in audit mode
    first (see docs\Installation.md, "App Control for Business (WDAC)").

    The hash rules change with every release (every changed script has a new hash). Run this script again for every
    package that you deploy and deploy the new supplemental policy together with it. SelfX.Code.json and SelfX.Config.json (see
    docs\Installation.md) are created by the package build and do not replace this step.

    The scan of the whole package takes a few minutes.

    Level Hash (default): hash rules for every file, as described above.

    Level Publisher: for a signed package (docs\Installation.md, "Set up once instead of per version"). The policy gets a signer rule
    (certification authority and publisher name of the signing certificate, no version) instead of the hash rules, so it stays the
    same for every version of SelfX that is signed with the same certificate. A file without signature gets a hash rule instead (fallback
    Hash). Before the scan the script reads the signature of every program, library and script: a file with an invalid signature (for
    example changed after signing, or a certificate that is not trusted on this PC) stops the script, as do files of different signers
    (unless -AllowMultipleSigners is set) and a package whose Install.ps1 is not signed (use the level Hash for it; signed libraries of
    other publishers alone do not make a package signed). After the scan the policy is
    checked: it has signer rules without a file attribute, no hash rule when every file is signed, and the publishers it trusts are listed
    in the output. The policy ID stays fixed. The level Publisher trusts the signer: keep the signing certificate protected.

    Requirement: Windows PowerShell 5.1 on an administrator PC with the ConfigCI module (Windows 11 or Windows Server);
    the base policy must allow supplemental policies (rule option 17, "Allow Supplemental Policies"). Needs no
    administrator rights beyond reading the package folder; changes nothing on the PC.

.PARAMETER BasePolicyId
    PolicyID (GUID) of the base policy that the supplemental policy expands.

.PARAMETER PolicyId
    PolicyID (GUID) of the supplemental policy. Default: a fixed ID, so a new version replaces the old policy. Use another
    ID per version when devices with the old and the new SelfX version must run side by side during a rollout.

.PARAMETER Level
    Hash (default) or Publisher (see above).

.PARAMETER AllowMultipleSigners
    Only with the level Publisher: allows files that are signed by more than one certificate (for example while two certificates are in
    use). Every signer of the package gets a signer rule.

.PARAMETER PackageFolder
    Default: "SelfX Service" of the repository (with the folder Bin built by Build-SelfXBinaries.ps1).

.PARAMETER OutputFolder
    Default: build\wdac of the repository (not committed).

.NOTES
    Name    : New-SelfXWdacPolicy.ps1
    Package : tools
    Context : Administrator PC (not installed, no device is changed)
    Version : 1.1.0
    Exit code: 0 = policy created, an exception otherwise

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-23  fubu2k               Initial version.
    1.0.1    2026-11-27  fubu2k               The policy version comes from Version.txt (no longer from Tool_Config.xml)
    1.1.0    2026-11-27  fubu2k               New -Level Publisher: signer rule of the signing certificate, hash fallback for unsigned files
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$BasePolicyId,
    [guid]$PolicyId = '1377A178-96F8-49DD-B277-80F0F10BB383',
    [ValidateSet('Hash', 'Publisher')][string]$Level = 'Hash',
    [switch]$AllowMultipleSigners,
    [string]$PackageFolder,
    [string]$OutputFolder
)

$ErrorActionPreference = 'Stop'

# ID of the supplemental policy. The default is the same for every SelfX version, so an update replaces the previous
# policy. For a staged rollout give each version its own ID: both policies are then active side by side until you
# remove the old one.
$SupplementalPolicyId = $PolicyId.ToString('B').ToUpperInvariant()
$AllowedSupplementalOption = 'Enabled:Unsigned System Integrity Policy'

$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
# Get-SelfXVersionFromFile (the version is read from Version.txt); the file only defines functions.
. (Join-Path $ScriptFolder 'SelfXPackage.Common.ps1')
# Functions of the level Publisher (signature state of the files, check of the signer rules); only definitions.
. (Join-Path $ScriptFolder 'SelfXPublisherRules.ps1')
if ($AllowMultipleSigners -and $Level -ne 'Publisher') { throw '-AllowMultipleSigners is only valid with -Level Publisher.' }
if (-not $PackageFolder) { $PackageFolder = Join-Path $RepositoryRoot 'SelfX Service' }
if (-not $OutputFolder) { $OutputFolder = Join-Path $RepositoryRoot 'build\wdac' }

foreach ($cmdlet in 'New-CIPolicy', 'Set-CIPolicyIdInfo', 'Set-CIPolicyVersion', 'ConvertFrom-CIPolicy') {
    if (-not (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue)) {
        throw "The cmdlet $cmdlet is missing (module ConfigCI). Run the script in Windows PowerShell 5.1 (powershell.exe) on Windows 11 or Windows Server."
    }
}

$versionPath = Join-Path $PackageFolder 'Version.txt'
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) { throw "Version.txt not found in '$PackageFolder'." }
$toolVersion = Get-SelfXVersionFromFile -Path $versionPath
if ($toolVersion -notmatch '^(\d{1,4})\.(\d{1,4})\.(\d{1,4})$') { throw "Unexpected version '$toolVersion' in Version.txt." }
$policyVersion = "$toolVersion.0"

$bin = Join-Path $PackageFolder 'Bin'
if (-not (Test-Path -LiteralPath (Join-Path $bin 'SelfX.Binaries.json') -PathType Leaf)) { throw "The folder Bin with SelfX.Binaries.json is missing in '$PackageFolder'. Run tools\Build-SelfXBinaries.ps1 first." }

# Staging copy of exactly what the package contains, so the scan sees the same files as the device.
$stage = Join-Path ([IO.Path]::GetTempPath()) ('SelfXWdac_' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    foreach ($name in 'Install.ps1', 'Detection.ps1', 'Uninstall.ps1') {
        Copy-Item -LiteralPath (Join-Path $PackageFolder $name) -Destination $stage
    }
    Copy-Item -LiteralPath (Join-Path $PackageFolder 'Sources') -Destination (Join-Path $stage 'Sources') -Recurse
    Copy-Item -LiteralPath $bin -Destination (Join-Path $stage 'Bin') -Recurse

    # Level Publisher: look at the signatures of the staged files before the scan (fail closed, nothing is written yet).
    $signedFileNames = @()
    $unsignedCount = 0
    if ($Level -eq 'Publisher') {
        $states = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $script:SelfXSignedFileExtensions -contains $_.Extension.ToLowerInvariant() } | ForEach-Object { Get-SelfXFileSignerState -Path $_.FullName })
        $problem = Get-SelfXSignerSetProblem -State $states -AllowMultipleSigners:$AllowMultipleSigners
        if (-not $problem) { $problem = Get-SelfXSignedPackageProblem -State $states }
        if ($problem) { throw $problem }
        $signedFileNames = @($states | Where-Object { $_.State -eq 'Signed' } | ForEach-Object { $_.Name })
        $unsignedCount = @($states | Where-Object { $_.State -eq 'Unsigned' }).Count
    }

    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    $xmlPath = Join-Path $OutputFolder ("SelfX-$toolVersion-Supplemental.xml")
    $binaryPath = Join-Path $OutputFolder ("$SupplementalPolicyId.cip")
    $warningsPath = Join-Path $OutputFolder ("SelfX-$toolVersion-Supplemental-Warnings.txt")
    foreach ($old in $xmlPath, $binaryPath) { if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force } }

    # Hash rules for every file (scripts are included: -NoScript is not set). Warnings of the scan go to a file.
    # Level Publisher: signer rules for the signed files, hash rules only for the files without signature.
    if ($Level -eq 'Publisher') { New-CIPolicy -FilePath $xmlPath -ScanPath $stage -Level Publisher -Fallback Hash -UserPEs -MultiplePolicyFormat 3> $warningsPath }
    else { New-CIPolicy -FilePath $xmlPath -ScanPath $stage -Level Hash -UserPEs -MultiplePolicyFormat 3> $warningsPath }
    Set-CIPolicyIdInfo -FilePath $xmlPath -PolicyName "SelfX $toolVersion" -SupplementsBasePolicyID $BasePolicyId
    Set-CIPolicyVersion -FilePath $xmlPath -Version $policyVersion

    # Fixed policy ID, so that the next version replaces this one.
    $document = New-Object Xml.XmlDocument
    $document.XmlResolver = $null
    $document.Load($xmlPath)
    $namespaces = New-Object Xml.XmlNamespaceManager($document.NameTable)
    $namespaces.AddNamespace('ci', 'urn:schemas-microsoft-com:sipolicy')
    $document.SelectSingleNode('/ci:SiPolicy/ci:PolicyID', $namespaces).InnerText = $SupplementalPolicyId
    # New-CIPolicy adds rule options of a base policy (for example "Enabled:Audit Mode"). A supplemental policy may only
    # set a few of them (option 6, "Unsigned System Integrity Policy", is the default one): the mode and the other
    # options come from the base policy.
    $rules = $document.SelectSingleNode('/ci:SiPolicy/ci:Rules', $namespaces)
    if ($rules) {
        foreach ($rule in @($rules.SelectNodes('ci:Rule', $namespaces))) {
            if ($rule.SelectSingleNode('ci:Option', $namespaces).InnerText -ne $AllowedSupplementalOption) { [void]$rules.RemoveChild($rule) }
        }
    }
    $document.Save($xmlPath)

    # Checks of the result: a supplemental policy, for the given base policy, with hash rules only, no mode option.
    $check = New-Object Xml.XmlDocument
    $check.XmlResolver = $null
    $check.Load($xmlPath)
    $policyType = $check.SelectSingleNode('/ci:SiPolicy/@PolicyType', $namespaces)
    if ((-not $policyType) -or $policyType.Value -ne 'Supplemental Policy') { throw "The policy is not a supplemental policy (PolicyType '$(if ($policyType) { $policyType.Value })')." }
    if ($check.SelectSingleNode('/ci:SiPolicy/ci:BasePolicyID', $namespaces).InnerText.ToUpperInvariant() -ne $BasePolicyId.ToString('B').ToUpperInvariant()) { throw 'BasePolicyID does not match the given base policy.' }
    $hashRules = @($check.SelectNodes('/ci:SiPolicy/ci:FileRules/ci:Allow[@Hash]', $namespaces))
    $otherRules = @($check.SelectNodes('/ci:SiPolicy/ci:FileRules/*[not(self::ci:Allow[@Hash])]', $namespaces))
    $signerNames = @()
    if ($Level -eq 'Publisher') {
        # Signer rules without file attribute, hash rules only for files without signature (see Get-SelfXWdacPublisherPolicyProblem).
        $policyProblems = @(Get-SelfXWdacPublisherPolicyProblem -PolicyXml (Get-Content -LiteralPath $xmlPath -Raw) -ExpectHashRules ($unsignedCount -gt 0) -SignedFileName $signedFileNames)
        if ($policyProblems.Count -gt 0) { throw "The publisher policy is not as expected: $($policyProblems -join ' ')" }
        $signerNames = @(Get-SelfXWdacSignerName -PolicyXml (Get-Content -LiteralPath $xmlPath -Raw))
    }
    else {
        if ($hashRules.Count -eq 0) { throw 'The policy has no hash rules.' }
        if ($otherRules.Count -gt 0) { Write-Warning "The policy has $($otherRules.Count) rule(s) that are not plain hash rules. Check '$xmlPath' before you deploy it." }
    }
    foreach ($option in @($check.SelectNodes('/ci:SiPolicy/ci:Rules/ci:Rule/ci:Option', $namespaces))) {
        if ($option.InnerText -ne $AllowedSupplementalOption) { throw "The supplemental policy must not set the rule option '$($option.InnerText)' (the base policy decides, for example the audit mode)." }
    }

    ConvertFrom-CIPolicy -XmlFilePath $xmlPath -BinaryFilePath $binaryPath | Out-Null
    if ($Level -eq 'Publisher') {
        Write-Output "Supplemental policy for base policy $($BasePolicyId.ToString('B')), SelfX $toolVersion, level Publisher: $(@($signerNames).Count) signer(s), $($hashRules.Count) hash rule(s) for $unsignedCount unsigned file(s)."
        Write-Output 'The policy trusts these publishers (check that this is your signing certificate and nobody else):'
        foreach ($signerName in $signerNames) { Write-Output "  $signerName" }
    }
    else { Write-Output "Supplemental policy for base policy $($BasePolicyId.ToString('B')), SelfX $toolVersion, $($hashRules.Count) hash rules:" }
    Write-Output "  $xmlPath"
    Write-Output "  $binaryPath"
    Write-Output "Scan warnings: $warningsPath"
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
