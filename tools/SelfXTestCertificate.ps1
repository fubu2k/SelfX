<#
.SYNOPSIS
    Test helper: creates short-lived self-signed code signing certificates and makes them trusted for the time of a test.

.DESCRIPTION
    Dot-sourced by the tests of the publisher rules (Test-SelfXAppLockerRules.ps1, Test-WdacPolicy.ps1). The file only defines
    functions. Windows only. Never used by a tool or by the package.

      Get-SelfXTestRootLocation     Says whether the test may add certificates to the trusted roots, and where. Allowed only on GitHub
                                    Actions with administrator rights (Cert:\LocalMachine\Root, where Windows asks nothing) or when the
                                    variable SELFX_TEST_ALLOW_ROOT_IMPORT is 1 (then Cert:\LocalMachine\Root with administrator rights,
                                    otherwise Cert:\CurrentUser\Root, where Windows shows a question).
      New-SelfXTestCertificate      Creates a self-signed code signing certificate in Cert:\CurrentUser\My (subject with O=, so that
                                    AppLocker has a publisher name) and returns the live certificate object.
      Add-SelfXTestRoot             Adds the certificate to the trusted roots of the given location.
      Remove-SelfXTestCertificate   Removes the certificate (and its private key) from Cert:\CurrentUser\My and from the trusted roots.
                                    Safe to call when it is already gone.

    The tests call Remove-SelfXTestCertificate in a finally block for every certificate they created.

.NOTES
    Name    : SelfXTestCertificate.ps1
    Package : tools
    Context : Test machine / CI (not installed, not shipped)
    Version : 1.0.0
    Works in Windows PowerShell 5.1 and PowerShell 7 (Windows).

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-27  fubu2k               Initial version (tests of the publisher rules, step 9)
#>

function Get-SelfXTestRootLocation {
    $isAdmin = $false
    try {
        $principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $principal.IsInRole([System.Security.Principal.SecurityIdentifier]'S-1-5-32-544')
    }
    catch { $isAdmin = $false }
    $allowed = (($env:GITHUB_ACTIONS -eq 'true') -and $isAdmin) -or ($env:SELFX_TEST_ALLOW_ROOT_IMPORT -eq '1')
    return [pscustomobject]@{ Allowed = $allowed; Location = $(if ($isAdmin) { 'LocalMachine' } else { 'CurrentUser' }) }
}

function New-SelfXTestCertificate {
    param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{1,10}$')][string]$Name)
    $unique = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $created = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=SelfX Rules Test $Name $unique, O=SelfX Rules Test $Name $unique, C=DE" `
        -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyExportPolicy Exportable -KeyUsage DigitalSignature
    # A live certificate object from the store (the cmdlet may return a copy when PowerShell 7 runs it through Windows PowerShell).
    return (Get-Item -LiteralPath "Cert:\CurrentUser\My\$($created.Thumbprint)")
}

function Add-SelfXTestRoot {
    param(
        [Parameter(Mandatory)]$Certificate,
        [Parameter(Mandatory)][ValidateSet('LocalMachine', 'CurrentUser')][string]$Location
    )
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', $Location)
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    try { $store.Add((New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, $Certificate.RawData))) }
    finally { $store.Close() }
}

function Remove-SelfXTestCertificate {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{40}$')][string]$Thumbprint,
        [ValidateSet('LocalMachine', 'CurrentUser')][string]$Location = 'CurrentUser'
    )
    foreach ($place in @($Location, 'CurrentUser') | Select-Object -Unique) {
        $path = "Cert:\$place\Root\$Thumbprint"
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
    $own = "Cert:\CurrentUser\My\$Thumbprint"
    if (Test-Path -LiteralPath $own) { Remove-Item -LiteralPath $own -DeleteKey -Force -ErrorAction SilentlyContinue }
}
