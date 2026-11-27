<#
.SYNOPSIS
    Tests tools\SelfXSigning.ps1 (certificate lookup, signing, signed catalog, check of signature and catalog).

.DESCRIPTION
    Isolated: works in a temporary folder, changes no repository file. Runs in Windows PowerShell 5.1 and in PowerShell 7.

    Part 1 runs on every system (also Linux): syntax, no PowerShell 7 only syntax, static checks of the password handling,
    thumbprints, time stamp addresses, script encoding, the rules for a suitable certificate and the PFX file (certificates are
    created in memory).

    Part 2 needs Windows. The test creates self-signed certificates with New-SelfSignedCertificate in Cert:\CurrentUser\My only
    (never in LocalMachine) and removes them (with the private key) at the end. The checks of the signature status need a trusted
    root: for them the test adds the public part of the test certificates to Cert:\CurrentUser\Root and removes it at the end.
    Windows asks for a confirmation when a root is added on an interactive desktop (certutil.exe -user is used, which the runner accepts), so this part runs only on GitHub Actions
    or when the variable SELFX_TEST_ALLOW_ROOT_IMPORT=1 is set; otherwise it is skipped (and said so).

    SELFX_TEST_SLOW=1                  also runs the tests with a certificate that expires during the test (about 3 minutes).
    SELFX_TEST_TIMESTAMP_URL=<http(s)> time stamp server for the test "expired with time stamp". A server that cannot be
                                       reached skips only that check.

    The PFX password of the tests is a random value created by the test itself (not a secret); the test checks that it appears
    in no output, no error message and no error record.

.NOTES
    Name    : Test-SelfXSigning.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 3.1.0
    Exit code: 0 = all tests passed or skipped, 1 = at least one failed

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version
#>
$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryPath = Join-Path $ScriptFolder 'SelfXSigning.ps1'

$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  PASS $Name"; $script:Passed++ } else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}
function Skip {
    param([string]$Name, [string]$Why)
    Write-Host "  SKIP $Name ($Why)" -ForegroundColor Yellow
    $script:Skipped++
}
function Assert-Throws {
    # The block must stop with an error. Returns the message (for further checks); $null when nothing was thrown.
    param([scriptblock]$Block, [string]$Name)
    $message = $null
    try { & $Block | Out-Null } catch { $message = $_.Exception.Message }
    Assert ($null -ne $message) $Name
    return $message
}

Write-Host "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

# ---------------------------------------------------------------------------------------------------------------------
Write-Host 'Library file'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($libraryPath, [ref]$tokens, [ref]$parseErrors)
Assert (@($parseErrors).Count -eq 0) 'SelfXSigning.ps1 parses without errors in this PowerShell'
$ps7Syntax = @($ast.FindAll({ param($node) $node.GetType().Name -in 'TernaryExpressionAst', 'PipelineChainAst' }, $true))
$text = [IO.File]::ReadAllText($libraryPath)
Assert ($ps7Syntax.Count -eq 0 -and $text -notmatch '(?m)\?\?=?|ForEach-Object\s+-Parallel') 'no PowerShell 7 only syntax (ternary, && ||, ??, -Parallel)'
Assert (-not ($text -match '[^\x00-\x7F]')) 'the file has only ASCII characters (signature and encoding of 5.1 and 7 agree)'
$functionNames = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
foreach ($name in 'Get-SelfXSigningCertificate', 'Set-SelfXCodeSignature', 'New-SelfXSignedCatalog', 'Test-SelfXSignature', 'Test-SelfXSignedCatalog') {
    Assert ($functionNames -contains $name) "function $name exists"
}
# The file only defines functions: nothing but function definitions and the three constants at the top level.
$topLevel = @($ast.EndBlock.Statements | Where-Object { $_ -isnot [Management.Automation.Language.FunctionDefinitionAst] })
Assert (@($topLevel | Where-Object { $_.Extent.Text -notmatch '^\$script:SelfX(CodeSigningEku|SignableExtensions|ScriptExtensions|MaxPfxBytes)\s*=' }).Count -eq 0) 'the file only defines functions and constants'
Write-Host 'Password handling (static)'
foreach ($forbidden in 'ConvertFrom-SecureString', 'SecureStringTo', 'PtrToString', 'NetworkCredential', '-AsPlainText', 'Import-PfxCertificate', 'PersistKeySet', 'Invoke-Expression', 'Write-Host', 'Out-File', 'Set-Content', 'Add-Content') {
    Assert ($text.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -lt 0) "the library does not contain '$forbidden'"
}
Assert ($text -match '\[System\.Security\.SecureString\]\$PfxPassword') 'the PFX password parameter is a SecureString'
Assert ($text -notmatch '\$PfxPassword\s*\)?\s*\.\s*(ToString|Length)' -and $text -notmatch '\[string\]\$PfxPassword') 'the PFX password is never converted to a string'

. $libraryPath

# ---------------------------------------------------------------------------------------------------------------------
Write-Host 'Thumbprints and addresses'
$goodThumb = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678'
Assert ((ConvertTo-SelfXThumbprint $goodThumb) -ceq $goodThumb.ToUpperInvariant()) 'a thumbprint is normalized to upper case'
Assert ((ConvertTo-SelfXThumbprint "  $goodThumb ") -ceq $goodThumb.ToUpperInvariant()) 'white space around a thumbprint is removed'
foreach ($bad in @('', '   ', 'abc', ($goodThumb + '0'), $goodThumb.Substring(1), ('g' * 40), ($goodThumb.Substring(0, 20) + ' ' + $goodThumb.Substring(20, 19)), ($goodThumb + "`n" + $goodThumb))) {
    $label = 'length ' + $bad.Length
    $null = Assert-Throws { ConvertTo-SelfXThumbprint $bad } "invalid thumbprint ($label) is refused"
}
$null = Assert-Throws { ConvertTo-SelfXThumbprintList @() } 'an empty list of signers is refused (it never means everything)'
$null = Assert-Throws { ConvertTo-SelfXThumbprintList @($goodThumb, 'nope') } 'one bad entry refuses the whole list'
Assert (@(ConvertTo-SelfXThumbprintList @($goodThumb, $goodThumb.ToUpperInvariant())).Count -eq 1) 'duplicates are removed from the list'

$acceptedUrls = @('http://timestamp.example.org', 'https://timestamp.example.org/tsa', 'http://127.0.0.1:8080/ts', 'HTTPS://TS.EXAMPLE.ORG/')
$refusedUrls = @('', '   ', 'ftp://ts.example.org', 'file:///C:/ts', '\\server\share\ts', 'C:\ts', 'ts.example.org', 'javascript:alert(1)',
    'http://user:secret@ts.example.org/', 'http://ts.example.org/a b', "http://ts.example.org/`r`nX-Header: 1", 'http://', 'https:///path', 'mailto:a@b.c')
foreach ($url in $acceptedUrls) { Assert (Test-SelfXTimestampUrl $url) "time stamp address accepted: $url" }
foreach ($url in $refusedUrls) { Assert (-not (Test-SelfXTimestampUrl $url)) "time stamp address refused: $(($url -replace '[\x00-\x1F]', '?'))" }

# ---------------------------------------------------------------------------------------------------------------------
Write-Host 'Script encoding'
$work = Join-Path ([IO.Path]::GetTempPath()) ('SelfXSigningTest-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
try {
    $ascii = Join-Path $work 'ascii.ps1'
    $utf8Bom = Join-Path $work 'bom.ps1'
    $utf8NoBom = Join-Path $work 'nobom.ps1'
    $utf16 = Join-Path $work 'utf16.ps1'
    [IO.File]::WriteAllText($ascii, "Write-Output 'a'`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($utf8Bom, "Write-Output 'a-umlaut: $([char]0xE4)'`r`n", (New-Object System.Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText($utf8NoBom, "Write-Output 'a-umlaut: $([char]0xE4)'`r`n", (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($utf16, "Write-Output 'a-umlaut: $([char]0xE4)'`r`n", [System.Text.Encoding]::Unicode)
    Assert (Test-SelfXScriptEncoding $ascii) 'ASCII script is accepted'
    Assert (Test-SelfXScriptEncoding $utf8Bom) 'UTF-8 script with BOM is accepted'
    Assert (Test-SelfXScriptEncoding $utf16) 'UTF-16 script with BOM is accepted'
    Assert (-not (Test-SelfXScriptEncoding $utf8NoBom)) 'UTF-8 script without BOM and with non-ASCII characters is refused'

    # -------------------------------------------------------------------------------------------------------------------
    Write-Host 'Suitable certificate (certificates in memory)'
    function New-MemoryCertificate {
        param([string[]]$Eku = @('1.3.6.1.5.5.7.3.3'), [switch]$NoEkuExtension, [switch]$NoDigitalSignature,
            [datetime]$NotBefore = ([DateTime]::Now.AddDays(-1)), [datetime]$NotAfter = ([DateTime]::Now.AddDays(1)))
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $request = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest('CN=SelfX Signing Test', $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $usage = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature
        if ($NoDigitalSignature) { $usage = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment }
        $request.CertificateExtensions.Add((New-Object System.Security.Cryptography.X509Certificates.X509KeyUsageExtension($usage, $true)))
        if (-not $NoEkuExtension) {
            $oids = New-Object System.Security.Cryptography.OidCollection
            foreach ($value in $Eku) { $null = $oids.Add((New-Object System.Security.Cryptography.Oid($value))) }
            $request.CertificateExtensions.Add((New-Object System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension($oids, $true)))
        }
        return $request.CreateSelfSigned([DateTimeOffset]$NotBefore, [DateTimeOffset]$NotAfter)
    }
    $good = New-MemoryCertificate
    Assert ($null -eq (Get-SelfXSigningCertificateProblem $good)) 'certificate with private key, Code Signing and valid period is suitable'
    $publicOnly = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, $good.RawData)
    Assert ((Get-SelfXSigningCertificateProblem $publicOnly) -eq 'no private key') 'certificate without private key is refused'
    Assert ((Get-SelfXSigningCertificateProblem (New-MemoryCertificate -Eku @('1.3.6.1.5.5.7.3.2'))) -like 'no key usage*') 'certificate for client authentication only is refused'
    Assert ((Get-SelfXSigningCertificateProblem (New-MemoryCertificate -Eku @('1.3.6.1.5.5.7.3.2', '1.3.6.1.5.5.7.3.3'))) -eq $null) 'certificate with Code Signing among other usages is suitable'
    Assert ((Get-SelfXSigningCertificateProblem (New-MemoryCertificate -NoEkuExtension)) -like 'no key usage*') 'certificate without a key usage extension is refused'
    Assert ((Get-SelfXSigningCertificateProblem (New-MemoryCertificate -NoDigitalSignature)) -like '*Digital Signature*') 'certificate without the usage Digital Signature is refused'
    Assert ((Get-SelfXSigningCertificateProblem (New-MemoryCertificate -NotBefore ([DateTime]::Now.AddDays(-10)) -NotAfter ([DateTime]::Now.AddDays(-1)))) -eq 'expired') 'expired certificate is refused'
    Assert ((Get-SelfXSigningCertificateProblem (New-MemoryCertificate -NotBefore ([DateTime]::Now.AddDays(1)) -NotAfter ([DateTime]::Now.AddDays(10)))) -eq 'not yet valid') 'certificate that is not yet valid is refused'
    Assert ((Get-SelfXSigningCertificateProblem $null) -eq 'no certificate') 'no certificate is refused'

    # -------------------------------------------------------------------------------------------------------------------
    Write-Host 'PFX file and password'
    function ConvertTo-TestSecureString {
        param([string]$Value)
        $secure = New-Object System.Security.SecureString
        foreach ($char in $Value.ToCharArray()) { $secure.AppendChar($char) }
        $secure.MakeReadOnly()
        return $secure
    }
    $password = 'Pw-' + [guid]::NewGuid().ToString('N') + '-' + [guid]::NewGuid().ToString('N')
    $securePassword = ConvertTo-TestSecureString $password
    $wrongText = 'Wrong-' + [guid]::NewGuid().ToString('N')
    $wrongPassword = ConvertTo-TestSecureString $wrongText
    $pfx = Join-Path $work 'good.pfx'
    [IO.File]::WriteAllBytes($pfx, $good.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $securePassword))
    $clientOnly = New-MemoryCertificate -Eku @('1.3.6.1.5.5.7.3.2')
    $pfxClientOnly = Join-Path $work 'client.pfx'
    [IO.File]::WriteAllBytes($pfxClientOnly, $clientOnly.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $securePassword))
    $notPfx = Join-Path $work 'not.pfx'
    [IO.File]::WriteAllText($notPfx, 'this is not a PFX file')

    $Error.Clear()
    $output = New-Object System.Collections.Generic.List[string]
    $VerbosePreference = 'Continue'
    $fromPfx = Get-SelfXSigningCertificate -PfxPath $pfx -PfxPassword $securePassword -Verbose 4>&1 5>&1 | ForEach-Object { $output.Add(($_ | Out-String)); $_ } | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509Certificate2] }
    $VerbosePreference = 'SilentlyContinue'
    Assert ($null -ne $fromPfx -and $fromPfx.Thumbprint -eq $good.Thumbprint) 'the PFX file is opened with the SecureString password'
    Assert ($fromPfx.HasPrivateKey) 'the certificate from the PFX file has its private key'
    $fromPfx.Dispose()
    $messages = New-Object System.Collections.Generic.List[string]
    $messages.Add((Assert-Throws { Get-SelfXSigningCertificate -PfxPath $pfx -PfxPassword $wrongPassword } 'a wrong PFX password stops the function'))
    $messages.Add((Assert-Throws { Get-SelfXSigningCertificate -PfxPath $notPfx -PfxPassword $securePassword } 'a file that is not a PFX file stops the function'))
    $messages.Add((Assert-Throws { Get-SelfXSigningCertificate -PfxPath $pfxClientOnly -PfxPassword $securePassword } 'a PFX file with an unsuitable certificate stops the function'))
    $messages.Add((Assert-Throws { Get-SelfXSigningCertificate -PfxPath (Join-Path $work 'missing.pfx') -PfxPassword $securePassword } 'a missing PFX file stops the function'))
    $messages.Add((Assert-Throws { Get-SelfXSigningCertificate -PfxPath $work -PfxPassword $securePassword } 'a folder instead of a PFX file stops the function'))
    $bigPfx = Join-Path $work 'big.pfx'
    [IO.File]::WriteAllBytes($bigPfx, (New-Object byte[] ($script:SelfXMaxPfxBytes + 1)))
    $messages.Add((Assert-Throws { Get-SelfXSigningCertificate -PfxPath $bigPfx -PfxPassword $securePassword } 'a PFX file above the size limit is refused'))
    $allText = ($messages -join "`n") + "`n" + ($output -join "`n") + "`n" + ($Error | Out-String) + "`n" + (($Error | ForEach-Object { $_.Exception.ToString() }) -join "`n")
    Assert ($allText.IndexOf($password, [StringComparison]::Ordinal) -lt 0) 'the PFX password appears in no output, no message and no error record'
    Assert ($allText.IndexOf($wrongText, [StringComparison]::Ordinal) -lt 0) 'a wrong password appears in no message and no error record'
    Assert ($messages[0] -notmatch 'System\.|Exception|0x[0-9A-Fa-f]{8}') 'the message for a wrong password has no text of the operating system'
    # The parameter is mandatory: a PFX file without a password cannot be requested.
    $parameter = (Get-Command Get-SelfXSigningCertificate).Parameters['PfxPassword']
    Assert ($parameter.ParameterType -eq [System.Security.SecureString]) 'PfxPassword has the type SecureString'

    # -------------------------------------------------------------------------------------------------------------------
    Write-Host 'Check of a signature: input'
    $null = Assert-Throws { Test-SelfXSignature -Path $ascii -AllowedThumbprint @() } 'Test-SelfXSignature with an empty list of signers stops'
    $null = Assert-Throws { Test-SelfXSignature -Path $ascii -AllowedThumbprint @('zzz') } 'Test-SelfXSignature with an invalid thumbprint stops'
    $missing = Test-SelfXSignature -Path (Join-Path $work 'missing.ps1') -AllowedThumbprint $goodThumb
    Assert ((-not $missing.IsValid) -and $missing.Reason -eq 'FileMissing') 'a missing file is not valid (FileMissing)'
    $null = Assert-Throws { Test-SelfXSignedCatalog -CatalogFilePath (Join-Path $work 'x.cat') -Path $work -AllowedThumbprint @() } 'Test-SelfXSignedCatalog with an empty list of signers stops'
    $noCatalog = Test-SelfXSignedCatalog -CatalogFilePath (Join-Path $work 'missing.cat') -Path $work -AllowedThumbprint $goodThumb
    Assert ((-not $noCatalog.IsValid) -and $noCatalog.Reason -eq 'FileMissing') 'a missing catalog is not valid (FileMissing)'

    # -------------------------------------------------------------------------------------------------------------------
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        Skip 'Part 2 (signing, catalog, signature status)' 'needs Windows'
    } else {
        $canTrust = ($env:GITHUB_ACTIONS -eq 'true') -or ($env:SELFX_TEST_ALLOW_ROOT_IMPORT -eq '1')
        $slow = ($env:SELFX_TEST_SLOW -eq '1')
        $timestampUrl = $env:SELFX_TEST_TIMESTAMP_URL
        $createdMy = New-Object System.Collections.Generic.List[string]
        $addedRoot = New-Object System.Collections.Generic.List[string]

        function New-StoreCertificate {
            param([string]$Name, [int]$ValidSeconds = 0, [string]$ExtraEku)
            $arguments = @{
                Subject           = "CN=SelfX Signing Test $Name $([guid]::NewGuid().ToString('N'))"
                CertStoreLocation = 'Cert:\CurrentUser\My'
                KeyAlgorithm      = 'RSA'
                KeyLength         = 2048
                HashAlgorithm     = 'SHA256'
                KeyExportPolicy   = 'Exportable'
                KeyUsage          = 'DigitalSignature'
            }
            if ($ExtraEku) { $arguments.Type = 'Custom'; $arguments.TextExtension = @("2.5.29.37={text}$ExtraEku") } else { $arguments.Type = 'CodeSigningCert' }
            if ($ValidSeconds -gt 0) { $arguments.NotAfter = [DateTime]::Now.AddSeconds($ValidSeconds) }
            $created = New-SelfSignedCertificate @arguments
            $createdMy.Add($created.Thumbprint)
            # A live certificate object from the store (the cmdlet may return a copy when PowerShell 7 runs it through Windows PowerShell).
            return (Get-Item -LiteralPath "Cert:\CurrentUser\My\$($created.Thumbprint)")
        }
        function Add-TestRoot {
            # certutil does not show the confirmation dialog of Windows (X509Store.Add waits for an answer that never comes on a runner).
            param($Certificate)
            $file = Join-Path $work ($Certificate.Thumbprint + '.cer')
            [IO.File]::WriteAllBytes($file, $Certificate.RawData)
            $null = & certutil.exe -user -addstore -f Root $file 2>&1
            if ($LASTEXITCODE -ne 0) { throw "certutil could not add the test certificate to Cert:\CurrentUser\Root (exit code $LASTEXITCODE)." }
            $addedRoot.Add($Certificate.Thumbprint)
        }
        function Write-TestScript {
            param([string]$Path)
            [IO.File]::WriteAllText($Path, "Write-Output 'SelfX signing test'`r`n", (New-Object System.Text.UTF8Encoding($false)))
        }
        function Get-SignatureStatus { param([string]$Path) return [string](Get-AuthenticodeSignature -LiteralPath $Path).Status }

        try {
            Write-Host 'Part 2: certificates in Cert:\CurrentUser\My'
            $certA = New-StoreCertificate 'A'
            $certB = New-StoreCertificate 'B'
            $thumbA = $certA.Thumbprint
            $thumbB = $certB.Thumbprint

            $byThumb = @(Get-SelfXSigningCertificate -Thumbprint $thumbA -StoreLocation CurrentUser)
            Assert ($byThumb.Count -eq 1 -and $byThumb[0].Thumbprint -eq $thumbA) 'a certificate of the user store is found by its thumbprint'
            Assert (@(Get-SelfXSigningCertificate -Thumbprint $thumbA.ToLowerInvariant() -StoreLocation CurrentUser).Count -eq 1) 'the thumbprint is compared without regard to case'
            Assert (@(Get-SelfXSigningCertificate -StoreLocation CurrentUser | Where-Object { $_.Thumbprint -eq $thumbA }).Count -eq 1) 'without a thumbprint the suitable certificates of the store are listed'
            Assert (@(Get-SelfXSigningCertificate -Thumbprint ('0' * 40)).Count -eq 0) 'an unknown thumbprint finds nothing'
            $null = Assert-Throws { Get-SelfXSigningCertificate -Thumbprint 'not a thumbprint' } 'an invalid thumbprint stops the search'
            Assert (@(Get-SelfXSigningCertificate -Thumbprint $thumbA).Count -eq 1) 'the search in both stores finds the certificate once'

            $clientCert = New-StoreCertificate 'ClientAuth' -ExtraEku '1.3.6.1.5.5.7.3.2'
            Assert (@(Get-SelfXSigningCertificate -Thumbprint $clientCert.Thumbprint -StoreLocation CurrentUser).Count -eq 0) 'a certificate without the usage Code Signing is not listed'

            $publicTemplate = New-StoreCertificate 'PublicOnly'
            $publicBytes = $publicTemplate.RawData
            $publicThumb = $publicTemplate.Thumbprint
            Remove-Item -LiteralPath "Cert:\CurrentUser\My\$publicThumb" -DeleteKey -Force
            $myStore = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', 'CurrentUser')
            $myStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            try { $myStore.Add((New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, $publicBytes))) } finally { $myStore.Close() }
            Assert (@(Get-SelfXSigningCertificate -Thumbprint $publicThumb -StoreLocation CurrentUser).Count -eq 0) 'a certificate without private key is not listed'

            Write-Host 'Part 2: PFX with a certificate of the store'
            $pfxStore = Join-Path $work 'store.pfx'
            [IO.File]::WriteAllBytes($pfxStore, $certA.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $securePassword))
            $fromStorePfx = Get-SelfXSigningCertificate -PfxPath $pfxStore -PfxPassword $securePassword
            Assert ($fromStorePfx.Thumbprint -eq $thumbA -and $fromStorePfx.HasPrivateKey) 'a PFX file with a Windows certificate is opened'
            Assert (@(Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq $thumbA }).Count -eq 1) 'opening the PFX file does not add a certificate to a store'

            Write-Host 'Part 2: refusals before anything is signed'
            $plain = Join-Path $work 'plain.ps1'; Write-TestScript $plain
            $other = Join-Path $work 'other.ps1'; Write-TestScript $other
            $xml = Join-Path $work 'data.xml'; [IO.File]::WriteAllText($xml, '<a/>')
            $umlaut = Join-Path $work 'umlaut.ps1'; [IO.File]::WriteAllText($umlaut, "Write-Output '$([char]0xE4)'`r`n", (New-Object System.Text.UTF8Encoding($false)))
            $umlautHash = (Get-FileHash -LiteralPath $umlaut -Algorithm SHA256).Hash
            $null = Assert-Throws { Set-SelfXCodeSignature -Path $plain, $xml -Certificate $certA } 'one file of a type without a signature stops the whole call'
            Assert ((Get-SignatureStatus $plain) -eq 'NotSigned') 'the other file of that call was not signed'
            $null = Assert-Throws { Set-SelfXCodeSignature -Path $plain, (Join-Path $work 'missing.ps1') -Certificate $certA } 'one missing file stops the whole call'
            Assert ((Get-SignatureStatus $plain) -eq 'NotSigned') 'the existing file of that call was not signed'
            $null = Assert-Throws { Set-SelfXCodeSignature -Path $umlaut -Certificate $certA } 'a script with non-ASCII characters and no BOM is refused'
            Assert ((Get-FileHash -LiteralPath $umlaut -Algorithm SHA256).Hash -eq $umlautHash) 'the refused script is unchanged'
            foreach ($url in 'ftp://ts.example.org', 'file:///C:/ts', 'http://user:pw@ts.example.org/', '\\server\share') {
                $null = Assert-Throws { Set-SelfXCodeSignature -Path $plain -Certificate $certA -TimestampServer $url } "time stamp address refused: $url"
            }
            $null = Assert-Throws { Set-SelfXCodeSignature -Path $plain -Certificate $certA -TimestampServer '' } 'an empty time stamp address is refused (no silent signature without time stamp)'
            Assert ((Get-SignatureStatus $plain) -eq 'NotSigned') 'no file was signed after the refused time stamp addresses'
            $null = Assert-Throws { Set-SelfXCodeSignature -Path $plain -Certificate $publicTemplate } 'a certificate without private key stops the signing'
            $null = Assert-Throws { Set-SelfXCodeSignature -Path @() -Certificate $certA } 'an empty list of files stops the signing'
            $unsigned = Test-SelfXSignature -Path $plain -AllowedThumbprint $thumbA
            Assert ((-not $unsigned.IsValid) -and $unsigned.Reason -eq 'NotSigned') 'an unsigned file is not valid (NotSigned)'

            $folder = Join-Path $work 'content'
            $null = New-Item -ItemType Directory -Path (Join-Path $folder 'sub')
            [IO.File]::WriteAllText((Join-Path $folder 'a.txt'), 'alpha')
            [IO.File]::WriteAllBytes((Join-Path $folder 'sub\b.png'), [byte[]](1..200))
            [IO.File]::WriteAllText((Join-Path $folder 'c.xml'), '<c/>')
            $catalogPath = Join-Path $work 'content.cat'
            $null = Assert-Throws { New-SelfXSignedCatalog -Path $folder -CatalogFilePath (Join-Path $folder 'in.cat') -Certificate $certA } 'a catalog file inside the folder is refused'
            $null = Assert-Throws { New-SelfXSignedCatalog -Path $folder -CatalogFilePath (Join-Path $work 'content.txt') -Certificate $certA } 'a catalog file without the extension .cat is refused'
            $emptyFolder = Join-Path $work 'empty'; $null = New-Item -ItemType Directory -Path $emptyFolder
            $null = Assert-Throws { New-SelfXSignedCatalog -Path $emptyFolder -CatalogFilePath $catalogPath -Certificate $certA } 'a folder without a file is refused'
            $null = Assert-Throws { New-SelfXSignedCatalog -Path (Join-Path $work 'missing-folder') -CatalogFilePath $catalogPath -Certificate $certA } 'a missing folder is refused'
            $null = Assert-Throws { New-SelfXSignedCatalog -Path $folder -CatalogFilePath $catalogPath -Certificate $certA -TimestampServer 'ftp://x' } 'a bad time stamp address stops the catalog'
            Assert (-not (Test-Path -LiteralPath $catalogPath)) 'no catalog file was written for the refusals'
            $linkFolder = Join-Path $work 'withlink'
            $null = New-Item -ItemType Directory -Path $linkFolder
            [IO.File]::WriteAllText((Join-Path $linkFolder 'a.txt'), 'a')
            $junction = Join-Path $linkFolder 'junction'
            $null = & cmd.exe /c mklink /J "`"$junction`"" "`"$folder`"" 2>&1
            if (Test-Path -LiteralPath $junction) {
                $null = Assert-Throws { New-SelfXSignedCatalog -Path $linkFolder -CatalogFilePath (Join-Path $work 'link.cat') -Certificate $certA } 'a folder with a junction is refused'
                Assert (-not (Test-Path -LiteralPath (Join-Path $work 'link.cat'))) 'no catalog file was written for the folder with a junction'
                & cmd.exe /c rmdir "`"$junction`"" | Out-Null
            } else { Skip 'folder with a junction is refused' 'the junction could not be created' }

            if (-not $canTrust) {
                Skip 'Part 2: signatures, catalog, expiry' 'a trusted root is needed; set SELFX_TEST_ALLOW_ROOT_IMPORT=1 (adds the test certificates to Cert:\CurrentUser\Root until the end of the test) or run on GitHub Actions'
            } else {
                Write-Host 'Part 2: trusted test roots (Cert:\CurrentUser\Root)'
                Add-TestRoot $certA
                Add-TestRoot $certB

                Write-Host 'Part 2: signing and checking files'
                $results = @(Set-SelfXCodeSignature -Path $plain, $other -Certificate $certA)
                Assert ($results.Count -eq 2 -and @($results | Where-Object { $_.Status -eq 'Valid' -and $_.Thumbprint -eq $thumbA }).Count -eq 2) 'two scripts are signed and read back: status Valid, signer is the certificate'
                Assert (-not $results[0].TimeStamped) 'without a time stamp server no time stamp is claimed'
                $good1 = Test-SelfXSignature -Path $plain -AllowedThumbprint $thumbA
                Assert ($good1.IsValid -and $good1.Reason -eq 'Ok' -and $good1.Status -eq 'Valid') 'valid: status Valid and the signer is in the list'
                Assert ((Test-SelfXSignature -Path $plain -AllowedThumbprint @($thumbB, $thumbA.ToLowerInvariant())).IsValid) 'valid: the signer is one of several allowed signers (any case)'
                $wrong = Test-SelfXSignature -Path $plain -AllowedThumbprint $thumbB
                Assert ((-not $wrong.IsValid) -and $wrong.Status -eq 'Valid' -and $wrong.Reason -eq 'SignerNotAllowed') 'wrong signer: status Valid but not in the list (SignerNotAllowed)'
                Add-Content -LiteralPath $other -Value '# changed after signing'
                $changed = Test-SelfXSignature -Path $other -AllowedThumbprint $thumbA
                Assert ((-not $changed.IsValid) -and $changed.Reason -eq 'HashMismatch') 'a file changed after signing is not valid (HashMismatch)'
                $notSupported = Test-SelfXSignature -Path $xml -AllowedThumbprint $thumbA
                Assert (-not $notSupported.IsValid) 'an XML file has no signature and is not valid'

                Write-Host 'Part 2: signing with a certificate from a PFX file (password in no output)'
                $pfxScript = Join-Path $work 'pfxsigned.ps1'; Write-TestScript $pfxScript
                $Error.Clear()
                $captured = & {
                    $VerbosePreference = 'Continue'
                    $pfxCert = Get-SelfXSigningCertificate -PfxPath $pfxStore -PfxPassword $securePassword
                    try { Set-SelfXCodeSignature -Path $pfxScript -Certificate $pfxCert } finally { $pfxCert.Dispose() }
                    try { Get-SelfXSigningCertificate -PfxPath $pfxStore -PfxPassword $wrongPassword } catch { $_ }
                } *>&1 | Out-String
                $capturedAll = $captured + "`n" + ($Error | Out-String)
                Assert ((Test-SelfXSignature -Path $pfxScript -AllowedThumbprint $thumbA).IsValid) 'a script signed with the certificate of the PFX file is valid'
                Assert ($capturedAll.IndexOf($password, [StringComparison]::Ordinal) -lt 0 -and $capturedAll.IndexOf($wrongText, [StringComparison]::Ordinal) -lt 0) 'the passwords appear in no output of signing'

                Write-Host 'Part 2: time stamp server that cannot be reached'
                $tsScript = Join-Path $work 'ts.ps1'; Write-TestScript $tsScript
                $tsMessage = Assert-Throws { Set-SelfXCodeSignature -Path $tsScript -Certificate $certA -TimestampServer 'http://127.0.0.1:9/' } 'an unreachable time stamp server is an error, not a signature without time stamp'
                Assert ($null -ne $tsMessage -and $tsMessage -match 'could not be signed') 'the message says which file could not be signed'

                Write-Host 'Part 2: signed catalog'
                $made = New-SelfXSignedCatalog -Path $folder -CatalogFilePath $catalogPath -Certificate $certA
                Assert ((Test-Path -LiteralPath $catalogPath) -and $made.FileCount -eq 3 -and $made.Thumbprint -eq $thumbA) 'the catalog of three files is written and signed'
                Assert ((Get-SignatureStatus $catalogPath) -eq 'Valid') 'the catalog has a valid signature'
                $okCatalog = Test-SelfXSignedCatalog -CatalogFilePath $catalogPath -Path $folder -AllowedThumbprint $thumbA
                Assert ($okCatalog.IsValid -and $okCatalog.Reason -eq 'Ok') 'a signed catalog and the matching folder are valid'
                $null = Assert-Throws { New-SelfXSignedCatalog -Path $folder -CatalogFilePath $catalogPath -Certificate $certA } 'an existing catalog is not replaced without -Force'
                $again = New-SelfXSignedCatalog -Path $folder -CatalogFilePath $catalogPath -Certificate $certA -Force
                Assert ($again.FileCount -eq 3 -and (Test-SelfXSignedCatalog -CatalogFilePath $catalogPath -Path $folder -AllowedThumbprint $thumbA).IsValid) 'with -Force the catalog is replaced'

                $insideCatalog = Join-Path $folder 'content.cat'
                Copy-Item -LiteralPath $catalogPath -Destination $insideCatalog
                $insideResult = Test-SelfXSignedCatalog -CatalogFilePath $insideCatalog -Path $folder -AllowedThumbprint $thumbA
                Assert ($insideResult.IsValid -and $insideResult.ExtraFiles.Count -eq 0) 'a catalog inside the folder is accepted and not counted as a file of the folder'
                Remove-Item -LiteralPath $insideCatalog -Force

                $wrongSigner = Test-SelfXSignedCatalog -CatalogFilePath $catalogPath -Path $folder -AllowedThumbprint $thumbB
                Assert ((-not $wrongSigner.IsValid) -and $wrongSigner.Reason -eq 'CatalogSignature:SignerNotAllowed') 'catalog of a signer that is not allowed is not valid'

                $a = Join-Path $folder 'a.txt'
                [IO.File]::WriteAllText($a, 'alpha changed')
                $changedFile = Test-SelfXSignedCatalog -CatalogFilePath $catalogPath -Path $folder -AllowedThumbprint $thumbA
                Assert ((-not $changedFile.IsValid) -and $changedFile.Reason -eq 'FilesDiffer' -and @($changedFile.ChangedFiles) -contains 'a.txt') 'a changed file is found by name (ChangedFiles)'
                [IO.File]::WriteAllText($a, 'alpha')
                Remove-Item -LiteralPath (Join-Path $folder 'c.xml')
                $missingFile = Test-SelfXSignedCatalog -CatalogFilePath $catalogPath -Path $folder -AllowedThumbprint $thumbA
                Assert ((-not $missingFile.IsValid) -and @($missingFile.MissingFiles) -contains 'c.xml') 'a missing file is found by name (MissingFiles)'
                [IO.File]::WriteAllText((Join-Path $folder 'c.xml'), '<c/>')
                [IO.File]::WriteAllText((Join-Path $folder 'extra.txt'), 'x')
                $extraFile = Test-SelfXSignedCatalog -CatalogFilePath $catalogPath -Path $folder -AllowedThumbprint $thumbA
                Assert ((-not $extraFile.IsValid) -and @($extraFile.ExtraFiles) -contains 'extra.txt') 'an extra file is found by name (ExtraFiles)'
                Remove-Item -LiteralPath (Join-Path $folder 'extra.txt')
                Assert ((Test-SelfXSignedCatalog -CatalogFilePath $catalogPath -Path $folder -AllowedThumbprint $thumbA).IsValid) 'after restoring the folder the catalog is valid again'

                $tampered = Join-Path $work 'tampered.cat'
                $bytes = [IO.File]::ReadAllBytes($catalogPath)
                $bytes[[int]($bytes.Length / 2)] = $bytes[[int]($bytes.Length / 2)] -bxor 0xFF
                [IO.File]::WriteAllBytes($tampered, $bytes)
                $tamperedResult = Test-SelfXSignedCatalog -CatalogFilePath $tampered -Path $folder -AllowedThumbprint $thumbA
                Assert ((-not $tamperedResult.IsValid) -and $tamperedResult.Reason -ne 'Ok') 'a changed catalog is not valid'
                $unsignedCatalog = Join-Path $work 'unsigned.cat'
                $null = New-FileCatalog -Path $folder -CatalogFilePath $unsignedCatalog -CatalogVersion 2
                $unsignedResult = Test-SelfXSignedCatalog -CatalogFilePath $unsignedCatalog -Path $folder -AllowedThumbprint $thumbA
                Assert ((-not $unsignedResult.IsValid) -and $unsignedResult.Reason -eq 'CatalogSignature:NotSigned') 'an unsigned catalog is not valid'
                $failedCatalog = Join-Path $work 'failed.cat'
                $null = Assert-Throws { New-SelfXSignedCatalog -Path $folder -CatalogFilePath $failedCatalog -Certificate $certA -TimestampServer 'http://127.0.0.1:9/' } 'a catalog whose signing fails stops the function'
                Assert (-not (Test-Path -LiteralPath $failedCatalog)) 'no unsigned catalog file is left behind when signing fails'

                if (-not $slow) {
                    Skip 'expired certificate with and without time stamp' 'set SELFX_TEST_SLOW=1 (takes about 3 minutes)'
                } else {
                    Write-Host 'Part 2: certificate that expires during the test'
                    $expiring = New-StoreCertificate 'Expiring' -ValidSeconds 180
                    $thumbE = $expiring.Thumbprint
                    Add-TestRoot $expiring
                    $noStamp = Join-Path $work 'expiry-nostamp.ps1'; Write-TestScript $noStamp
                    $withStamp = Join-Path $work 'expiry-stamp.ps1'; Write-TestScript $withStamp
                    $null = Set-SelfXCodeSignature -Path $noStamp -Certificate $expiring
                    $stampDone = $false
                    if ([string]::IsNullOrWhiteSpace($timestampUrl)) {
                        Skip 'expired certificate with time stamp' 'SELFX_TEST_TIMESTAMP_URL is not set'
                    } else {
                        try {
                            $stamped = @(Set-SelfXCodeSignature -Path $withStamp -Certificate $expiring -TimestampServer $timestampUrl)
                            Assert ($stamped[0].TimeStamped) 'the signature with a time stamp server contains a time stamp'
                            $stampDone = $true
                        } catch {
                            Skip 'expired certificate with time stamp' "the time stamp server cannot be used: $(ConvertTo-SelfXSafeText $_.Exception.Message)"
                        }
                    }
                    Assert ((Test-SelfXSignature -Path $noStamp -AllowedThumbprint $thumbE).IsValid) 'before the end of the period the signature is valid'
                    $wait = ($expiring.NotAfter - [DateTime]::Now).TotalSeconds + 3
                    if ($wait -gt 0) { Write-Host "  waiting $([int]$wait) seconds for the certificate to expire"; Start-Sleep -Seconds ([int][Math]::Ceiling($wait)) }
                    $expiredResult = Test-SelfXSignature -Path $noStamp -AllowedThumbprint $thumbE
                    Assert ((-not $expiredResult.IsValid) -and $expiredResult.Reason -eq 'NotTrusted') 'expired certificate without time stamp: the signature is not valid (NotTrusted)'
                    if ($stampDone) {
                        $stampResult = Test-SelfXSignature -Path $withStamp -AllowedThumbprint $thumbE
                        Assert ($stampResult.IsValid -and $stampResult.Reason -eq 'Ok') 'expired certificate with time stamp: the signature is still valid'
                    }
                    Assert (@(Get-SelfXSigningCertificate -Thumbprint $thumbE -StoreLocation CurrentUser).Count -eq 0) 'an expired certificate is not listed'
                    $null = Assert-Throws { Set-SelfXCodeSignature -Path $plain -Certificate $expiring } 'an expired certificate cannot sign'
                }
            }
            $fromStorePfx.Dispose()
        } finally {
            Write-Host 'Part 2: cleanup'
            foreach ($thumbprint in $addedRoot) { $null = & certutil.exe -user -delstore Root $thumbprint 2>&1 }
            foreach ($thumbprint in $createdMy) {
                $entry = "Cert:\CurrentUser\My\$thumbprint"
                if (Test-Path -LiteralPath $entry) {
                    Remove-Item -LiteralPath $entry -DeleteKey -Force -ErrorAction SilentlyContinue
                    # The certificate without private key (public part only) cannot delete a key: remove the entry itself.
                    if (Test-Path -LiteralPath $entry) { Remove-Item -LiteralPath $entry -Force -ErrorAction SilentlyContinue }
                }
            }
            $leftMy = @(Get-ChildItem Cert:\CurrentUser\My | Where-Object { $createdMy -contains $_.Thumbprint })
            $leftRoot = @(Get-ChildItem Cert:\CurrentUser\Root | Where-Object { $addedRoot -contains $_.Thumbprint })
            Assert ($leftMy.Count -eq 0) 'no test certificate is left in Cert:\CurrentUser\My'
            Assert ($leftRoot.Count -eq 0) 'no test certificate is left in Cert:\CurrentUser\Root'
        }
    }
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "Passed: $script:Passed, failed: $script:Failed, skipped: $script:Skipped"
if ($script:Failed -gt 0) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'PASS'
exit 0
