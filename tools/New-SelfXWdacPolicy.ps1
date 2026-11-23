<#
.SYNOPSIS
    Creates an optional App Control for Business (WDAC) supplemental policy with hash rules for SelfX Service
    (security review finding N4, part 3).

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
    package that you deploy and deploy the new supplemental policy together with it. SelfX.Files.json (see
    docs\Installation.md) is created by the package build and does not replace this step.

    The scan of the whole package takes a few minutes.

    Requirement: Windows PowerShell 5.1 on an administrator PC with the ConfigCI module (Windows 11 or Windows Server);
    the base policy must allow supplemental policies (rule option 17, "Allow Supplemental Policies"). Needs no
    administrator rights beyond reading the package folder; changes nothing on the PC.

.PARAMETER BasePolicyId
    PolicyID (GUID) of the base policy that the supplemental policy expands.

.PARAMETER PolicyId
    PolicyID (GUID) of the supplemental policy. Default: a fixed ID, so a new version replaces the old policy. Use another
    ID per version when devices with the old and the new SelfX version must run side by side during a rollout.

.PARAMETER PackageFolder
    Default: "SelfX Service" of the repository (with the folder Bin built by Build-SelfXBinaries.ps1).

.PARAMETER OutputFolder
    Default: build\wdac of the repository (not committed).

.NOTES
    Name    : New-SelfXWdacPolicy.ps1
    Package : tools
    Context : Administrator PC (not installed, no device is changed)
    Version : 1.0.0
    Exit code: 0 = policy created, an exception otherwise

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-23  fubu2k               Initial version (security review finding N4, part 3).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$BasePolicyId,
    [guid]$PolicyId = '1377A178-96F8-49DD-B277-80F0F10BB383',
    [string]$PackageFolder,
    [string]$OutputFolder
)

$ErrorActionPreference = 'Stop'

# ID of the supplemental policy. The default is the same for every SelfX version, so an update replaces the previous
# policy. For a staged rollout give each version its own ID: both policies are then active side by side until you
# remove the old one.
$SupplementalPolicyId = $PolicyId.ToString('B').ToUpperInvariant()
$AllowedSupplementalOption = 'Enabled:Unsigned System Integrity Policy'

$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $PackageFolder) { $PackageFolder = Join-Path $RepositoryRoot 'SelfX Service' }
if (-not $OutputFolder) { $OutputFolder = Join-Path $RepositoryRoot 'build\wdac' }

foreach ($cmdlet in 'New-CIPolicy', 'Set-CIPolicyIdInfo', 'Set-CIPolicyVersion', 'ConvertFrom-CIPolicy') {
    if (-not (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue)) {
        throw "The cmdlet $cmdlet is missing (module ConfigCI). Run the script in Windows PowerShell 5.1 (powershell.exe) on Windows 11 or Windows Server."
    }
}

$settings = New-Object Xml.XmlReaderSettings
$settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
$settings.XmlResolver = $null
$configPath = Join-Path $PackageFolder 'Sources\Tool_Config.xml'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Tool_Config.xml not found in '$PackageFolder\Sources'." }
$reader = [Xml.XmlReader]::Create($configPath, $settings)
try { $config = New-Object Xml.XmlDocument; $config.XmlResolver = $null; $config.Load($reader) } finally { $reader.Dispose() }
$toolVersion = $config.SelectSingleNode('/GUI_Config/Tool_Version').InnerText.Trim()
if ($toolVersion -notmatch '^(\d{1,4})\.(\d{1,4})\.(\d{1,4})$') { throw "Unexpected version '$toolVersion' in Tool_Config.xml." }
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

    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    $xmlPath = Join-Path $OutputFolder ("SelfX-$toolVersion-Supplemental.xml")
    $binaryPath = Join-Path $OutputFolder ("$SupplementalPolicyId.cip")
    $warningsPath = Join-Path $OutputFolder ("SelfX-$toolVersion-Supplemental-Warnings.txt")
    foreach ($old in $xmlPath, $binaryPath) { if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force } }

    # Hash rules for every file (scripts are included: -NoScript is not set). Warnings of the scan go to a file.
    New-CIPolicy -FilePath $xmlPath -ScanPath $stage -Level Hash -UserPEs -MultiplePolicyFormat 3> $warningsPath
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
    if ($hashRules.Count -eq 0) { throw 'The policy has no hash rules.' }
    if ($otherRules.Count -gt 0) { Write-Warning "The policy has $($otherRules.Count) rule(s) that are not plain hash rules. Check '$xmlPath' before you deploy it." }
    foreach ($option in @($check.SelectNodes('/ci:SiPolicy/ci:Rules/ci:Rule/ci:Option', $namespaces))) {
        if ($option.InnerText -ne $AllowedSupplementalOption) { throw "The supplemental policy must not set the rule option '$($option.InnerText)' (the base policy decides, for example the audit mode)." }
    }

    ConvertFrom-CIPolicy -XmlFilePath $xmlPath -BinaryFilePath $binaryPath | Out-Null
    Write-Output "Supplemental policy for base policy $($BasePolicyId.ToString('B')), SelfX $toolVersion, $($hashRules.Count) hash rules:"
    Write-Output "  $xmlPath"
    Write-Output "  $binaryPath"
    Write-Output "Scan warnings: $warningsPath"
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
