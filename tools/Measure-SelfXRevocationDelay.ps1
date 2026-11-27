<#
.SYNOPSIS
    Measures how long Get-AuthenticodeSignature takes when the revocation list of the signing certificate cannot be reached.

.DESCRIPTION
    Install.ps1 checks the signatures of the package with Get-AuthenticodeSignature (trust mode Signature). The certificate of the
    signer names the address of its revocation list (CRL distribution point); Windows asks there. This script shows what happens
    on this device when the address cannot be reached: the status of the signature and the time per file.

    It creates a test root and three test signers in Cert:\CurrentUser\My (valid for two days), adds the test root to
    Cert:\CurrentUser\Root (Windows asks for confirmation), signs a number of small test scripts in a temporary folder and checks
    them in a new Windows PowerShell 5.1 process, as Install.ps1 does. At the end the certificates, the trusted root and the folder
    are removed again. Nothing of SelfX is changed. No administrator rights are needed.

      Signer "none"     no revocation list address in the certificate (comparison value)
      Signer "dns"      address with a host name that does not exist (http://crl.selfx-test.invalid/...)
      Signer "timeout"  address that does not answer (http://192.0.2.1/..., a reserved test network)

    Run it twice: once with the network connected and once without any network (cable removed, Wi-Fi off). The output ends with a
    table in Markdown for the pull request. Install.ps1 runs as SYSTEM; the setting "Check for publisher's certificate revocation"
    is stored per account, so the script also prints the value of this account and of the SYSTEM account (.DEFAULT).

    Windows PowerShell 5.1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Measure-SelfXRevocationDelay.ps1

.NOTES
    Name    : Measure-SelfXRevocationDelay.ps1
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
    # Number of signed test scripts per signer.
    [ValidateRange(2, 200)][int]$FileCount = 20
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This script needs Windows.' }

function Get-CdpExtensionHex {
    # The extension "CRL Distribution Points" (2.5.29.31) with one http address, DER encoded, as hexadecimal text.
    param([Parameter(Mandatory = $true)][string]$Url)
    $bytes = [Text.Encoding]::ASCII.GetBytes($Url)
    $length = $bytes.Length
    if ($length -lt 1 -or $length -gt 110) { throw 'The address must have 1 to 110 characters.' }
    $der = [byte[]](0x30, ($length + 8), 0x30, ($length + 6), 0xA0, ($length + 4), 0xA0, ($length + 2), 0x86, $length) + $bytes
    return (-join ($der | ForEach-Object { $_.ToString('X2') }))
}

function Get-RevocationSetting {
    # The value State of the trust provider "Software Publishing" (0x23C00 = check revocation, an offline server is accepted).
    param([Parameter(Mandatory = $true)][string]$Root)
    try {
        $value = (Get-ItemProperty -LiteralPath "$Root\Software\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing" -Name State -ErrorAction Stop).State
        return ('0x{0:X}' -f $value)
    } catch { return 'not set (Windows default)' }
}

$id = [guid]::NewGuid().ToString('N').Substring(0, 8)
$work = Join-Path ([IO.Path]::GetTempPath()) "SelfXRevocationTest_$id"
$created = New-Object System.Collections.Generic.List[string]
$rootThumbprint = $null
$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$signers = [ordered]@{
    'none'    = ''
    'dns'     = 'http://crl.selfx-test.invalid/selfx-test.crl'
    'timeout' = 'http://192.0.2.1/selfx-test.crl'
}
$rows = New-Object System.Collections.Generic.List[object]

try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $online = [Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
    Write-Host "Device: Windows build $([Environment]::OSVersion.Version.Build), PowerShell $($PSVersionTable.PSVersion), network available: $online"
    Write-Host "Revocation setting (State): this account $(Get-RevocationSetting 'HKCU:'), SYSTEM account $(Get-RevocationSetting 'Registry::HKEY_USERS\.DEFAULT')"

    Write-Host 'Creating the test certificates (Cert:\CurrentUser\My) ...'
    $root = New-SelfSignedCertificate -Type Custom -Subject "CN=SelfX Revocation Test Root $id" -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyUsage CertSign, CRLSign -KeyExportPolicy NonExportable `
        -TextExtension @('2.5.29.19={critical}{text}ca=1&pathlength=0') -NotAfter ([DateTime]::Now.AddDays(2))
    $created.Add($root.Thumbprint)
    $certificates = @{}
    foreach ($name in $signers.Keys) {
        $arguments = @{
            Type              = 'CodeSigningCert'
            Subject           = "CN=SelfX Revocation Test Signer $name $id"
            CertStoreLocation = 'Cert:\CurrentUser\My'
            Signer            = $root
            KeyAlgorithm      = 'RSA'
            KeyLength         = 2048
            HashAlgorithm     = 'SHA256'
            KeyUsage          = 'DigitalSignature'
            KeyExportPolicy   = 'NonExportable'
            NotAfter          = [DateTime]::Now.AddDays(1)
        }
        if ($signers[$name]) { $arguments.TextExtension = @("2.5.29.31={hex}$(Get-CdpExtensionHex $signers[$name])") }
        $certificate = New-SelfSignedCertificate @arguments
        $created.Add($certificate.Thumbprint)
        $hasAddress = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.31' }).Count -eq 1
        if ([bool]$signers[$name] -ne $hasAddress) { throw "The test certificate '$name' was not created as expected (revocation list address)." }
        $certificates[$name] = $certificate
    }

    Write-Host 'Adding the test root to Cert:\CurrentUser\Root (confirm the question of Windows) ...'
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    try { $store.Add((New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, $root.RawData))) } finally { $store.Close() }
    $rootThumbprint = $root.Thumbprint

    # The check runs in a new process, like Install.ps1 (nothing that this process has loaded is reused).
    $checkScript = Join-Path $work 'check.ps1'
    [IO.File]::WriteAllText($checkScript, @'
param([string]$Folder)
foreach ($file in @(Get-ChildItem -LiteralPath $Folder -Filter '*.ps1' | Sort-Object Name)) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    $watch.Stop()
    '{0};{1};{2}' -f $file.Name, $watch.ElapsedMilliseconds, $signature.Status
}
'@)

    foreach ($name in $signers.Keys) {
        $folder = Join-Path $work $name
        New-Item -ItemType Directory -Path $folder | Out-Null
        $signWatch = [Diagnostics.Stopwatch]::StartNew()
        for ($index = 1; $index -le $FileCount; $index++) {
            $file = Join-Path $folder ('Test{0:D3}.ps1' -f $index)
            [IO.File]::WriteAllText($file, "Write-Output 'SelfX revocation test $index'`r`n", (New-Object System.Text.UTF8Encoding($false)))
            $null = Set-AuthenticodeSignature -LiteralPath $file -Certificate $certificates[$name] -HashAlgorithm SHA256 -IncludeChain NotRoot
        }
        $signWatch.Stop()
        Write-Host "Signer '$name': $FileCount files signed in $($signWatch.ElapsedMilliseconds) ms; checking in a new process ..."
        $totalWatch = [Diagnostics.Stopwatch]::StartNew()
        $lines = @(& $powershellExe -NoProfile -ExecutionPolicy Bypass -File $checkScript -Folder $folder)
        $totalWatch.Stop()
        $times = New-Object System.Collections.Generic.List[int]
        $statuses = @{}
        foreach ($line in $lines) {
            $parts = "$line".Split(';')
            if ($parts.Count -ne 3) { continue }
            $times.Add([int]$parts[1])
            $statuses[$parts[2]] = 1 + [int]$statuses[$parts[2]]
        }
        if ($times.Count -ne $FileCount) { throw "The check of the signer '$name' returned $($times.Count) results instead of $FileCount." }
        $rest = @($times | Select-Object -Skip 1)
        $rows.Add([pscustomobject]@{
                Signer  = $name
                Address = $(if ($signers[$name]) { $signers[$name] } else { '(none)' })
                Status  = (@($statuses.Keys | Sort-Object | ForEach-Object { "$_ x$($statuses[$_])" }) -join ', ')
                First   = $times[0]
                RestMax = ($rest | Measure-Object -Maximum).Maximum
                RestSum = ($rest | Measure-Object -Sum).Sum
                Total   = $totalWatch.ElapsedMilliseconds
            })
    }

    Write-Host ''
    Write-Host 'Result for the pull request (Markdown):'
    Write-Host ''
    Write-Output "Device: Windows build $([Environment]::OSVersion.Version.Build), Windows PowerShell $($PSVersionTable.PSVersion), network available: $online, files per signer: $FileCount"
    Write-Output "Revocation setting (State): account of the test $(Get-RevocationSetting 'HKCU:'), SYSTEM account $(Get-RevocationSetting 'Registry::HKEY_USERS\.DEFAULT')"
    Write-Output ''
    Write-Output '| Signer | Revocation list address | Status | First file (ms) | Slowest other file (ms) | All other files (ms) | Whole process (ms) |'
    Write-Output '|---|---|---|---|---|---|---|'
    foreach ($row in $rows) { Write-Output "| $($row.Signer) | $($row.Address) | $($row.Status) | $($row.First) | $($row.RestMax) | $($row.RestSum) | $($row.Total) |" }
}
finally {
    Write-Host ''
    Write-Host 'Cleanup ...'
    if ($rootThumbprint) {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        try { foreach ($entry in @($store.Certificates | Where-Object { $_.Thumbprint -eq $rootThumbprint })) { $store.Remove($entry) } } finally { $store.Close() }
    }
    foreach ($thumbprint in $created) { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint" -DeleteKey -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    $leftRoot = @(Get-ChildItem Cert:\CurrentUser\Root | Where-Object { $_.Thumbprint -eq $rootThumbprint }).Count
    $leftMy = @(Get-ChildItem Cert:\CurrentUser\My | Where-Object { $created -contains $_.Thumbprint }).Count
    if ($leftRoot -or $leftMy) { Write-Warning "Test certificates are left: $leftRoot in Cert:\CurrentUser\Root, $leftMy in Cert:\CurrentUser\My (subject 'SelfX Revocation Test ... $id'). Remove them by hand." }
    else { Write-Host 'The test certificates and the test folder were removed.' }
}
