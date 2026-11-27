<#
.SYNOPSIS
    Experiment for the signature check of the service: runs tools\SelfXTrustProbe.cs (WinVerifyTrust for embedded signatures and
    for one given catalog) against known cases and measures the time.

.DESCRIPTION
    Compiles tools\SelfXTrustProbe.cs in memory (Add-Type) and checks:
      - Windows: a program with an embedded signature of Microsoft (pwsh.exe) and a file of Windows that is signed by a catalog
        (found with CryptCATAdminEnumCatalogFromHash). These are positive cases with a trusted signer on every device.
      - Test signer: a self-signed test certificate (Cert:\CurrentUser\My, valid for two days) signs test scripts and a catalog
        (New-FileCatalog, version 2) of a folder with XML and JSON files in a temporary folder. With administrator rights the
        certificate is added to Cert:\LocalMachine\Root for the time of the test, so the expected result is Ok; without, the
        expected result is UntrustedRoot (the signature and the hash fit, only the root is unknown) and every changed file must
        still give its own result.
      - Negative cases: changed script, unsigned script, changed XML, a file that is not in the catalog, a changed catalog (must
        never give Ok; which code Windows reports depends on where the member lookup fails), an unsigned catalog, a missing
        catalog, another catalog.
      - What decides in WINTRUST_CATALOG_INFO: the member tag or the calculated hash (tag "hash", no tag, wrong tag), and both
        actions (generic verify, driver verify).
      - Time per check, with and without the network request for revocation (cache only).
    At the end the certificates and the folder are removed. Nothing of SelfX is changed. The output ends with tables in Markdown
    for the pull request. Exit code 0 = every case as expected, 1 = a difference.

    PowerShell 7: pwsh -NoProfile -ExecutionPolicy Bypass -File .\Measure-SelfXTrustCheck.ps1

.NOTES
    Name    : Measure-SelfXTrustCheck.ps1
    Package : tools
    Context : Test device (signed-in user; not installed, not shipped)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version
#>
[CmdletBinding()]
param(
    # Number of repetitions for the time per check.
    [ValidateRange(1, 500)][int]$Repeat = 30
)
$ErrorActionPreference = 'Stop'
If($PSVersionTable.PSVersion.Major -lt 7) { throw 'Run this script in PowerShell 7 (pwsh).' }
Add-Type -Path (Join-Path $PSScriptRoot 'SelfXTrustProbe.cs') -ErrorAction Stop

$rows = New-Object System.Collections.Generic.List[object]
$failed = 0
function Add-Case([string]$Case, [string]$Expected, $Result) {
    $ok = ("$($Result.Reason)" -eq $Expected)
    If(-not $ok) { $script:failed++ }
    $rows.Add([pscustomobject]@{ Case = $Case; Expected = $Expected; Result = "$($Result.Reason)"; Code = ('0x{0:X8}' -f $Result.Code); Signer = $(If($Result.Thumbprint) { $Result.Thumbprint.Substring(0, 8) + '...' } Else { '-' }); Ok = $(If($ok) { 'yes' } Else { 'NO' }) })
}
function Invoke-Embedded([string]$Path, [bool]$CacheOnly = $true) {
    $pinned = [SelfXProbe.TrustProbe]::OpenPinned($Path)
    Try { return [SelfXProbe.TrustProbe]::VerifyEmbedded($Path, $pinned, $CacheOnly) } Finally { $pinned.Dispose() }
}
function Invoke-Member([string]$Catalog, [string]$Path, [string]$Tag = 'hash', [bool]$Driver = $false, [bool]$CacheOnly = $true) {
    $pinned = [SelfXProbe.TrustProbe]::OpenPinned($Path)
    Try { return [SelfXProbe.TrustProbe]::VerifyCatalogMember($Catalog, $Path, $pinned, $CacheOnly, $Tag, $Driver) } Finally { $pinned.Dispose() }
}
function Invoke-ByList([string]$Catalog, [string]$Path) {
    If(-not (Test-Path -LiteralPath $Catalog -PathType Leaf)) { return [pscustomobject]@{ Reason = 'CatalogMissing'; Code = -1; Thumbprint = '' } }
    $pinnedCatalog = [SelfXProbe.TrustProbe]::OpenPinned($Catalog)
    $pinned = [SelfXProbe.TrustProbe]::OpenPinned($Path)
    Try { return [SelfXProbe.TrustProbe]::VerifyCatalogByList($Catalog, $pinnedCatalog, $pinned, $true) } Finally { $pinned.Dispose(); $pinnedCatalog.Dispose() }
}
function Measure-Check([scriptblock]$Action) {
    $null = & $Action
    $watch = [Diagnostics.Stopwatch]::StartNew()
    For($i = 0; $i -lt $Repeat; $i++) { $null = & $Action }
    return [math]::Round($watch.Elapsed.TotalMilliseconds / $Repeat, 2)
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$trusted = $(If($isAdmin) { 'Ok' } Else { 'UntrustedRoot' })
Write-Output "Windows $([Environment]::OSVersion.Version), PowerShell $($PSVersionTable.PSVersion), administrator rights: $isAdmin (test signer expected: $trusted)."

# --- Windows: trusted signer on every device ---
$pwsh = (Get-Process -Id $PID).Path
$reference = Get-AuthenticodeSignature -LiteralPath $pwsh
$result = Invoke-Embedded $pwsh
Add-Case 'Windows: pwsh.exe, embedded signature' 'Ok' $result
$rows.Add([pscustomobject]@{ Case = 'Windows: signer of pwsh.exe equals Get-AuthenticodeSignature'; Expected = 'yes'; Result = $(If($result.Thumbprint -eq $reference.SignerCertificate.Thumbprint) { 'yes' } Else { 'no' }); Code = '-'; Signer = '-'; Ok = $(If($result.Thumbprint -eq $reference.SignerCertificate.Thumbprint) { 'yes' } Else { $failed++; 'NO' }) })
$systemFile = $null; $systemCatalog = $null
ForEach($candidate in 'notepad.exe', 'cmd.exe', 'whoami.exe', 'find.exe', 'sort.exe') {
    $path = Join-Path $env:SystemRoot "System32\$candidate"
    If(-not (Test-Path -LiteralPath $path)) { continue }
    $pinned = [SelfXProbe.TrustProbe]::OpenPinned($path)
    Try { $found = [SelfXProbe.TrustProbe]::FindSystemCatalog($pinned) } Finally { $pinned.Dispose() }
    If($found) { $systemFile = $path; $systemCatalog = $found; break }
}
If($systemCatalog) {
    Write-Output "Windows catalog case: $systemFile in $(Split-Path -Leaf $systemCatalog)."
    Add-Case 'Windows: file of System32 against its catalog' 'Ok' (Invoke-Member $systemCatalog $systemFile)
    Add-Case 'Windows: the same, way 2 (signature of the catalog + member list)' 'Ok' (Invoke-ByList $systemCatalog $systemFile)
    Add-Case 'Windows: pwsh.exe against that catalog (not a member)' 'NoSignature' (Invoke-Member $systemCatalog $pwsh)
    $other = Get-ChildItem -LiteralPath (Split-Path -Parent $systemCatalog) -Filter '*.cat' | Where-Object { $_.FullName -ne $systemCatalog } | Select-Object -First 1
    If($other) { Add-Case 'Windows: file of System32 against another catalog of Windows' 'NoSignature' (Invoke-Member $other.FullName $systemFile) }
}
Else { Write-Output 'No file of System32 with a catalog found; the Windows catalog cases are skipped.' }

# --- Test signer ---
$work = Join-Path ([IO.Path]::GetTempPath()) ('SelfXTrustProbe_' + [guid]::NewGuid().ToString('N'))
$folder = Join-Path $work 'Config'
New-Item -ItemType Directory -Path $folder, (Join-Path $folder 'Branding') -Force | Out-Null
$certificates = New-Object System.Collections.Generic.List[string]
$roots = New-Object System.Collections.Generic.List[string]
function New-TestSigner([string]$Name) {
    $created = New-SelfSignedCertificate -Subject "CN=SelfX Trust Probe $Name $([guid]::NewGuid().ToString('N'))" -CertStoreLocation 'Cert:\CurrentUser\My' -Type CodeSigningCert -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyUsage DigitalSignature -NotAfter (Get-Date).AddDays(2)
    $certificates.Add($created.Thumbprint)
    return (Get-Item -LiteralPath "Cert:\CurrentUser\My\$($created.Thumbprint)")
}
$timings = New-Object System.Collections.Generic.List[object]
Try
{
    $signer = New-TestSigner 'A'
    If($isAdmin) {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        Try { $store.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($signer.RawData)) } Finally { $store.Close() }
        $roots.Add($signer.Thumbprint)
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $script = Join-Path $work 'Signed.ps1'
    [IO.File]::WriteAllText($script, "Write-Output 'SelfX trust probe'`r`n", $utf8)
    $null = Set-AuthenticodeSignature -LiteralPath $script -Certificate $signer -HashAlgorithm SHA256 -IncludeChain NotRoot
    $result = Invoke-Embedded $script
    Add-Case 'Test signer: signed script' $trusted $result
    $rows.Add([pscustomobject]@{ Case = 'Test signer: thumbprint read from the state data'; Expected = 'yes'; Result = $(If($result.Thumbprint -eq $signer.Thumbprint) { 'yes' } Else { 'no' }); Code = '-'; Signer = '-'; Ok = $(If($result.Thumbprint -eq $signer.Thumbprint) { 'yes' } Else { $failed++; 'NO' }) })
    $changed = Join-Path $work 'Changed.ps1'
    [IO.File]::WriteAllText($changed, "Write-Output 'changed'`r`n" + [IO.File]::ReadAllText($script), $utf8)
    Add-Case 'Test signer: script changed before the signature block' 'BadDigest' (Invoke-Embedded $changed)
    $appended = Join-Path $work 'Appended.ps1'
    [IO.File]::WriteAllText($appended, [IO.File]::ReadAllText($script) + "# text after the signature block`r`n", $utf8)
    Add-Case 'Test signer: text added after the signature block' 'NoSignature' (Invoke-Embedded $appended)
    $unsigned = Join-Path $work 'Unsigned.ps1'
    [IO.File]::WriteAllText($unsigned, "Write-Output 'unsigned'`r`n", $utf8)
    Add-Case 'Unsigned script' 'NoSignature' (Invoke-Embedded $unsigned)

    $catalogXml = Join-Path $folder 'Issues_List.xml'
    $healthXml = Join-Path $folder 'Health_Config.xml'
    $list = Join-Path $folder 'SelfX.Config.json'
    [IO.File]::WriteAllText($catalogXml, '<Issues><Action><Script>SelfX_Test.ps1</Script><Context>System</Context></Action></Issues>', $utf8)
    [IO.File]::WriteAllText($healthXml, '<HealthConfig><Background Enabled="true" /></HealthConfig>', $utf8)
    [IO.File]::WriteAllText($list, '{ "ManifestVersion": 1, "Files": {} }', $utf8)
    [IO.File]::WriteAllText((Join-Path $folder 'Branding\logo.png'), 'png', $utf8)
    $catalog = Join-Path $work 'SelfX.Config.cat'
    $null = New-FileCatalog -Path $folder -CatalogFilePath $catalog -CatalogVersion 2
    $unsignedCatalog = Join-Path $work 'Unsigned.cat'
    Copy-Item -LiteralPath $catalog -Destination $unsignedCatalog
    $null = Set-AuthenticodeSignature -LiteralPath $catalog -Certificate $signer -HashAlgorithm SHA256 -IncludeChain NotRoot
    $tags = [SelfXProbe.TrustProbe]::CatalogTags($catalog, 10)
    $pinned = [SelfXProbe.TrustProbe]::OpenPinned($catalogXml)
    Try { $catalogHash = [BitConverter]::ToString([SelfXProbe.TrustProbe]::CatalogHash($pinned)).Replace('-', '') } Finally { $pinned.Dispose() }
    $flatHash = (Get-FileHash -LiteralPath $catalogXml -Algorithm SHA256).Hash
    Write-Output "Catalog of New-FileCatalog: $($tags.Count) members; the tag is the SHA256 as text: $($tags -contains $catalogHash); the catalog hash of an XML file equals its plain SHA256: $($catalogHash -eq $flatHash)."

    Add-Case 'Catalog: XML is a member (tag = hash)' $trusted (Invoke-Member $catalog $catalogXml)
    Add-Case 'Catalog: JSON list is a member (tag = hash)' $trusted (Invoke-Member $catalog $list)
    Add-Case 'Catalog: XML is a member, way 2' $trusted (Invoke-ByList $catalog $catalogXml)
    $result = Invoke-Member $catalog $healthXml
    $rows.Add([pscustomobject]@{ Case = 'Catalog: signer of the catalog read from the state data'; Expected = 'yes'; Result = $(If($result.Thumbprint -eq $signer.Thumbprint) { 'yes' } Else { 'no' }); Code = '-'; Signer = '-'; Ok = $(If($result.Thumbprint -eq $signer.Thumbprint) { 'yes' } Else { $failed++; 'NO' }) })
    # What decides: tag or hash?
    $noTag = Invoke-Member $catalog $catalogXml 'none'
    $wrongTag = Invoke-Member $catalog $catalogXml 'wrong'
    $driver = Invoke-Member $catalog $catalogXml 'hash' $true
    Write-Output "Member without a tag: $noTag. Member with a wrong tag: $wrongTag. Driver action instead of generic verify: $driver."
    # Negative cases.
    $changedXml = Join-Path $work 'Issues_List.xml'
    [IO.File]::WriteAllText($changedXml, [IO.File]::ReadAllText($catalogXml) + '<!-- changed -->', $utf8)
    Add-Case 'Catalog: changed XML' 'NoSignature' (Invoke-Member $catalog $changedXml)
    Add-Case 'Catalog: changed XML, way 2' 'NotInCatalog' (Invoke-ByList $catalog $changedXml)
    Add-Case 'Catalog: file that is not in the catalog' 'NoSignature' (Invoke-Member $catalog $unsigned)
    Add-Case 'Catalog: unsigned catalog' 'NoSignature' (Invoke-Member $unsignedCatalog $catalogXml)
    Add-Case 'Catalog: unsigned catalog, way 2' 'NoSignature' (Invoke-ByList $unsignedCatalog $catalogXml)
    Add-Case 'Catalog: missing catalog' 'Other' (Invoke-Member (Join-Path $work 'Missing.cat') $catalogXml)
    # A catalog whose content was changed after it was signed: one byte of the hash of a member.
    $brokenCatalog = Join-Path $work 'Broken.cat'
    $bytes = [IO.File]::ReadAllBytes($catalog)
    $needle = [byte[]]::new(32)
    For($i = 0; $i -lt 32; $i++) { $needle[$i] = [Convert]::ToByte($catalogHash.Substring($i * 2, 2), 16) }
    $position = -1
    For($i = 0; $i -le $bytes.Length - 32 -and $position -lt 0; $i++) {
        $match = $true
        For($j = 0; $j -lt 32; $j++) { If($bytes[$i + $j] -ne $needle[$j]) { $match = $false; break } }
        If($match) { $position = $i }
    }
    If($position -ge 0) {
        # The hash of another file is put in place of the hash of the member (binary form); the tag text stays.
        $otherHash = (Get-FileHash -LiteralPath $changedXml -Algorithm SHA256).Hash
        For($i = 0; $i -lt 32; $i++) { $bytes[$position + $i] = [Convert]::ToByte($otherHash.Substring($i * 2, 2), 16) }
        [IO.File]::WriteAllBytes($brokenCatalog, $bytes)
        $result = Invoke-Member $brokenCatalog $changedXml
        Write-Output "Changed catalog (hash of a member replaced by the hash of the changed XML, tag unchanged), changed XML against it: $result."
        $rows.Add([pscustomobject]@{ Case = 'Catalog: catalog changed after signing does not make a changed XML valid'; Expected = 'not Ok'; Result = "$($result.Reason)"; Code = ('0x{0:X8}' -f $result.Code); Signer = '-'; Ok = $(If($result.Reason -notin 'Ok', $trusted) { 'yes' } Else { $failed++; 'NO' }) })
        $result = Invoke-Member $brokenCatalog $healthXml
        $rows.Add([pscustomobject]@{ Case = 'Catalog: catalog changed after signing, unchanged other member'; Expected = 'not Ok'; Result = "$($result.Reason)"; Code = ('0x{0:X8}' -f $result.Code); Signer = '-'; Ok = $(If($result.Reason -notin 'Ok', $trusted) { 'yes' } Else { $failed++; 'NO' }) })
    }
    Else { Write-Output 'The binary hash of the member was not found in the catalog file; the case "changed catalog" is skipped.' }
    # A second signer: his catalog of the same folder is a valid catalog of another signer (the caller compares the thumbprint).
    $signerB = New-TestSigner 'B'
    $catalogB = Join-Path $work 'Other.cat'
    Copy-Item -LiteralPath $unsignedCatalog -Destination $catalogB
    $null = Set-AuthenticodeSignature -LiteralPath $catalogB -Certificate $signerB -HashAlgorithm SHA256 -IncludeChain NotRoot
    $result = Invoke-Member $catalogB $catalogXml
    $rows.Add([pscustomobject]@{ Case = 'Catalog of another signer: the thumbprint read is the one of the other signer'; Expected = 'yes'; Result = $(If($result.Thumbprint -eq $signerB.Thumbprint) { 'yes' } Else { 'no' }); Code = ('0x{0:X8}' -f $result.Code); Signer = '-'; Ok = $(If($result.Thumbprint -eq $signerB.Thumbprint) { 'yes' } Else { $failed++; 'NO' }) })

    # --- Time per check ---
    $timings.Add([pscustomobject]@{ Check = 'Embedded, small script (test signer), cache only'; Ms = (Measure-Check { Invoke-Embedded $script $true }) })
    $timings.Add([pscustomobject]@{ Check = 'Embedded, small script (test signer), network allowed'; Ms = (Measure-Check { Invoke-Embedded $script $false }) })
    $timings.Add([pscustomobject]@{ Check = "Embedded, pwsh.exe ($([math]::Round((Get-Item -LiteralPath $pwsh).Length / 1KB)) KB), cache only"; Ms = (Measure-Check { Invoke-Embedded $pwsh $true }) })
    $timings.Add([pscustomobject]@{ Check = 'Catalog member, small XML (test signer), cache only'; Ms = (Measure-Check { Invoke-Member $catalog $catalogXml 'hash' $false $true }) })
    $timings.Add([pscustomobject]@{ Check = 'Catalog member, small XML (test signer), network allowed'; Ms = (Measure-Check { Invoke-Member $catalog $catalogXml 'hash' $false $false }) })
    $timings.Add([pscustomobject]@{ Check = 'Catalog member, way 2 (signature of the catalog + member list)'; Ms = (Measure-Check { Invoke-ByList $catalog $catalogXml }) })
    $timings.Add([pscustomobject]@{ Check = 'SHA256 of the small script (Get-FileHash, for comparison)'; Ms = (Measure-Check { Get-FileHash -LiteralPath $script -Algorithm SHA256 }) })
}
Finally
{
    ForEach($thumbprint in $roots) { Remove-Item -LiteralPath "Cert:\LocalMachine\Root\$thumbprint" -Force -ErrorAction SilentlyContinue }
    ForEach($thumbprint in $certificates) { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint" -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ''
Write-Output '| Case | Expected | Result | Code | Signer | As expected |'
Write-Output '|---|---|---|---|---|---|'
ForEach($row in $rows) { Write-Output "| $($row.Case) | $($row.Expected) | $($row.Result) | $($row.Code) | $($row.Signer) | $($row.Ok) |" }
Write-Output ''
Write-Output "| Check ($Repeat repetitions) | Milliseconds per check |"
Write-Output '|---|---|'
ForEach($row in $timings) { Write-Output "| $($row.Check) | $($row.Ms) |" }
Write-Output ''
If($failed -gt 0) { Write-Output "$failed case(s) differ from the expectation."; exit 1 }
Write-Output 'Every case is as expected.'
exit 0
