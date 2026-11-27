<#
.SYNOPSIS
    Functions to sign the files of a SelfX package with Authenticode and to check the signatures: certificate lookup, signing
    of files, signed catalog of a folder, check of a signature and of a catalog.

.DESCRIPTION
    Dot-sourced by the package tools (later: the wizard) and by the tests. The file only defines functions; it changes nothing
    when it is dot-sourced. It is the library for the trust mode "signature" (docs\Architecture.md).

      Get-SelfXSigningCertificate   Finds a certificate for code signing: in the stores Cert:\CurrentUser\My and
                                    Cert:\LocalMachine\My, or in a PFX file. Only certificates with a private key, the key usage
                                    "Code Signing" and a valid period are returned.
      Set-SelfXCodeSignature        Signs files (SHA256, chain without the root, optional time stamp server) and checks the result
                                    of every file.
      New-SelfXSignedCatalog        Writes a file catalog (version 2, SHA256) of a folder and signs it. For files that cannot carry
                                    an embedded signature (XML, PNG).
      Test-SelfXSignature           A signature counts when its status is Valid AND the thumbprint of the signer is in the list of
                                    allowed signers. Returns the result with the reason.
      Test-SelfXSignedCatalog       Checks the signature of the catalog (as above) and that the folder matches the catalog.

    Every function stops (fail closed) or returns IsValid = $false when something is not as expected; none of them returns "valid" after
    an error.

    Password of a PFX file: it is a SecureString from the first to the last line. It is never converted to a plain string, never
    written to a log, the output, an answer file or an error message (error texts of this file never contain it, and the text of the
    exception of the operating system is not passed on). The PFX file is not imported into a certificate store: the certificate is
    opened in memory (X509KeyStorageFlags.UserKeySet, key not persisted), so Windows removes the temporary key container when the
    object is disposed. The caller disposes the certificate (the .Dispose() method) after the last signature.

    Limits (see also docs\Architecture.md):
      - Test-SelfXSignature checks the file at the given path. It does not protect against a change between the check and the use.
      - Get-AuthenticodeSignature asks for revocation information when the network is available. The behaviour without a network is
        part of the check of Install.ps1 (step 7).
      - Scripts (.ps1, .psm1, .psd1) with characters outside ASCII must start with a byte order mark. Windows PowerShell 5.1 reads
        a file without BOM in the ANSI code page, PowerShell 7 as UTF-8; the signature of such a file would be valid in only one of
        them. Set-SelfXCodeSignature refuses the file.
      - The kind of time stamp (RFC 3161 with SHA256 or the older Authenticode time stamp) depends on the PowerShell edition that
        signs; it is not tested which edition writes which kind.

.NOTES
    Name    : SelfXSigning.ps1
    Package : tools
    Context : Build machine (administrator of the package; not installed, not shipped)
    Version : 3.1.0
    Works in Windows PowerShell 5.1 and PowerShell 7.

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version: Get-SelfXSigningCertificate, Set-SelfXCodeSignature, New-SelfXSignedCatalog,
                                              Test-SelfXSignature, Test-SelfXSignedCatalog
#>

# OID of the key usage "Code Signing".
$script:SelfXCodeSigningEku = '1.3.6.1.5.5.7.3.3'

# Files that Set-SelfXCodeSignature signs. Everything else (XML, PNG, JSON, ...) cannot carry an embedded signature and belongs in a catalog.
$script:SelfXSignableExtensions = @('.exe', '.dll', '.ps1', '.psm1', '.psd1', '.cat')

# Scripts whose bytes are checked for the byte order mark before they are signed.
$script:SelfXScriptExtensions = @('.ps1', '.psm1', '.psd1')

# A PFX file larger than this is not a signing certificate.
$script:SelfXMaxPfxBytes = 1048576

function ConvertTo-SelfXThumbprint {
    # Normalizes a SHA1 thumbprint: 40 hexadecimal characters, upper case. Anything else is an error. The text is not repeated in
    # the message (it can be long or contain control characters).
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw 'A thumbprint is empty.' }
    $value = $Text.Trim()
    if ($value -notmatch '^[0-9A-Fa-f]{40}\z') { throw 'A thumbprint must consist of exactly 40 hexadecimal characters.' }
    return $value.ToUpperInvariant()
}

function ConvertTo-SelfXThumbprintList {
    # A list of allowed signers: at least one entry, every entry valid, duplicates removed. An empty list is an error (nothing is
    # allowed), never "everything is allowed".
    param([string[]]$Thumbprint)
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Thumbprint)) {
        $normalized = ConvertTo-SelfXThumbprint $item
        if (-not $list.Contains($normalized)) { $list.Add($normalized) }
    }
    if ($list.Count -eq 0) { throw 'The list of allowed signers is empty.' }
    return , @($list.ToArray())
}

function Get-SelfXSigningCertificateProblem {
    # Why a certificate cannot be used for code signing; $null when it can. Short fixed texts, no data of the certificate.
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    if ($null -eq $Certificate) { return 'no certificate' }
    if (-not $Certificate.HasPrivateKey) { return 'no private key' }
    $usage = $null
    $keyUsage = $null
    foreach ($extension in $Certificate.Extensions) {
        if ($extension -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) { $usage = $extension }
        if ($extension -is [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]) { $keyUsage = $extension }
    }
    if ($null -eq $usage) { return 'no key usage "Code Signing"' }
    $hasCodeSigning = $false
    foreach ($oid in $usage.EnhancedKeyUsages) { if ($oid.Value -eq $script:SelfXCodeSigningEku) { $hasCodeSigning = $true } }
    if (-not $hasCodeSigning) { return 'no key usage "Code Signing"' }
    if ($null -ne $keyUsage -and (($keyUsage.KeyUsages -band [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature) -eq 0)) {
        return 'key usage without "Digital Signature"'
    }
    $now = [DateTime]::Now
    if ($now -lt $Certificate.NotBefore) { return 'not yet valid' }
    if ($now -gt $Certificate.NotAfter) { return 'expired' }
    return $null
}

function ConvertTo-SelfXSafeText {
    # Text of an exception for a message: control characters removed, at most 200 characters (log injection, long output).
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $clean = ($Text -replace '[\x00-\x1F\x7F]+', ' ').Trim()
    if ($clean.Length -gt 200) { $clean = $clean.Substring(0, 200) }
    return $clean
}

function Test-SelfXTimestampUrl {
    # A time stamp server is an absolute http or https address without user information, without spaces and control characters.
    # No file:, ftp:, UNC or other scheme.
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    if ($Url -match '[\x00-\x20\x7F]') { return $false }
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') { return $false }
    if ([string]::IsNullOrEmpty($uri.Host)) { return $false }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo)) { return $false }
    return $true
}

function Test-SelfXScriptEncoding {
    # True when the script has only ASCII bytes or starts with a byte order mark (UTF-8 or UTF-16).
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return $true }
    if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) { return $true }
    foreach ($byte in $bytes) { if ($byte -gt 127) { return $false } }
    return $true
}

function Test-SelfXReparsePoint {
    # True when the file or folder is a link (symbolic link, junction).
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-SelfXSigningCertificate {
    <#
    .SYNOPSIS
        Finds certificates for code signing, in the certificate stores of the user and of the computer or in a PFX file.

    .DESCRIPTION
        Store (default): returns every certificate of Cert:\CurrentUser\My and Cert:\LocalMachine\My that has a private key, the key
        usage "Code Signing" and a valid period (the one with the latest end first). -Thumbprint selects one certificate (40
        hexadecimal characters). No suitable certificate: nothing is returned.

        PFX: opens the file with the password (SecureString, mandatory: a PFX file without a password is refused) and returns the
        certificate when it is suitable; otherwise the function stops. The file is not imported into a store. The caller disposes
        the returned certificate after use (.Dispose()). The messages never contain the password or the text of the exception of
        the operating system.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Store')]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [Parameter(ParameterSetName = 'Store')][string]$Thumbprint,
        [Parameter(ParameterSetName = 'Store')][ValidateSet('CurrentUser', 'LocalMachine')][string[]]$StoreLocation = @('CurrentUser', 'LocalMachine'),
        [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][string]$PfxPath,
        [Parameter(Mandatory = $true, ParameterSetName = 'Pfx')][System.Security.SecureString]$PfxPassword
    )

    if ($PSCmdlet.ParameterSetName -eq 'Pfx') {
        $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($PfxPath)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'The PFX file does not exist.' }
        if (Test-SelfXReparsePoint $full) { throw 'The PFX file is a link; links are refused.' }
        if ((Get-Item -LiteralPath $full -Force).Length -gt $script:SelfXMaxPfxBytes) { throw 'The file is too large for a PFX file with a signing certificate.' }
        $certificate = $null
        try {
            # The key is not persisted and the file is not imported into a store: the key lives as long as the object.
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $full, $PfxPassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet)
        } catch {
            throw 'The PFX file could not be opened (wrong password or not a valid PFX file).'
        }
        $problem = Get-SelfXSigningCertificateProblem $certificate
        if ($null -ne $problem) {
            $certificate.Dispose()
            throw "The certificate in the PFX file cannot be used for code signing: $problem."
        }
        return $certificate
    }

    $wanted = $null
    if ($PSBoundParameters.ContainsKey('Thumbprint')) { $wanted = ConvertTo-SelfXThumbprint $Thumbprint }
    $found = New-Object System.Collections.Generic.List[System.Security.Cryptography.X509Certificates.X509Certificate2]
    foreach ($location in $StoreLocation) {
        $store = $null
        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', $location)
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
            foreach ($certificate in $store.Certificates) {
                if ($null -ne $wanted -and $certificate.Thumbprint -ne $wanted) { continue }
                if ($null -eq (Get-SelfXSigningCertificateProblem $certificate)) { $found.Add($certificate) }
            }
        } catch {
            # A store that does not exist or cannot be read has no certificate for us.
            Write-Verbose "The store $location\My could not be read: $($_.Exception.GetType().Name)"
        } finally {
            if ($null -ne $store) { $store.Close() }
        }
    }
    foreach ($certificate in @($found.ToArray() | Sort-Object -Property NotAfter -Descending)) { $certificate }
}

function Set-SelfXCodeSignature {
    <#
    .SYNOPSIS
        Signs files with Authenticode (SHA256, certificate chain without the root, optional time stamp) and checks every file.

    .DESCRIPTION
        All input is checked before the first file is signed: certificate, time stamp address (http or https only), every path (a file,
        no link, an extension that can carry a signature, scripts with a byte order mark when they have non-ASCII characters). When
        something is wrong nothing is signed. After signing, every file is read back: the status must be Valid, the signer must be
        the given certificate and, with -TimestampServer, a time stamp must be present. When a file fails the function stops after
        the last file with a message that lists the files and the reasons; a time stamp server that cannot be reached is a failure,
        not a signature without a time stamp.

        Returns one object per file: Path, Status, Thumbprint, TimeStamped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Path,
        [Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$TimestampServer
    )

    $problem = Get-SelfXSigningCertificateProblem $Certificate
    if ($null -ne $problem) { throw "The certificate cannot be used for code signing: $problem." }
    if ($PSBoundParameters.ContainsKey('TimestampServer') -and -not (Test-SelfXTimestampUrl $TimestampServer)) {
        throw 'The time stamp server must be an absolute http or https address without user information.'
    }
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Path)) {
        if ([string]::IsNullOrWhiteSpace($item)) { throw 'A path is empty.' }
        $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($item)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "The file does not exist: $item" }
        if (Test-SelfXReparsePoint $full) { throw "The file is a link; links are not signed: $item" }
        $extension = [IO.Path]::GetExtension($full).ToLowerInvariant()
        if ($script:SelfXSignableExtensions -notcontains $extension) {
            throw "A file of the type '$extension' cannot carry a signature (use a signed catalog): $item"
        }
        if ($script:SelfXScriptExtensions -contains $extension -and -not (Test-SelfXScriptEncoding $full)) {
            throw "The script has non-ASCII characters but no byte order mark; save it as UTF-8 with BOM before signing: $item"
        }
        if (-not $files.Contains($full)) { $files.Add($full) }
    }
    if ($files.Count -eq 0) { throw 'There is no file to sign.' }

    $results = New-Object System.Collections.Generic.List[object]
    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        $reason = $null
        $signature = $null
        try {
            $arguments = @{
                LiteralPath   = $file
                Certificate   = $Certificate
                HashAlgorithm = 'SHA256'
                IncludeChain  = 'NotRoot'
                ErrorAction   = 'Stop'
            }
            if ($PSBoundParameters.ContainsKey('TimestampServer')) { $arguments.TimestampServer = $TimestampServer }
            $null = Set-AuthenticodeSignature @arguments
            $signature = Get-AuthenticodeSignature -LiteralPath $file -ErrorAction Stop
            if ([string]$signature.Status -ne 'Valid') {
                $reason = "status $($signature.Status)"
            } elseif ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $Certificate.Thumbprint) {
                $reason = 'signed by another certificate'
            } elseif ($PSBoundParameters.ContainsKey('TimestampServer') -and $null -eq $signature.TimeStamperCertificate) {
                $reason = 'no time stamp in the signature'
            }
        } catch {
            $reason = "signing failed: $(ConvertTo-SelfXSafeText $_.Exception.Message)"
        }
        if ($null -ne $reason) {
            $failures.Add("$([IO.Path]::GetFileName($file)): $reason")
            continue
        }
        $results.Add([pscustomobject]@{
                Path        = $file
                Status      = [string]$signature.Status
                Thumbprint  = $signature.SignerCertificate.Thumbprint
                TimeStamped = ($null -ne $signature.TimeStamperCertificate)
            })
    }
    if ($failures.Count -gt 0) {
        throw "$($failures.Count) of $($files.Count) file(s) could not be signed: $($failures -join '; ')"
    }
    return $results.ToArray()
}

function New-SelfXSignedCatalog {
    <#
    .SYNOPSIS
        Writes a file catalog (version 2, SHA256) of a folder and signs it.

    .DESCRIPTION
        The catalog file must be outside the folder (the caller copies it into the folder afterwards; Test-SelfXSignedCatalog accepts
        a catalog inside the folder). The folder must contain at least one file and no link (symbolic link or junction). An existing
        catalog file is replaced only with -Force. When signing fails the unsigned catalog is deleted: no unsigned catalog is left.

        Returns CatalogFilePath, FileCount, Thumbprint, TimeStamped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$CatalogFilePath,
        [Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$TimestampServer,
        [switch]$Force
    )

    $problem = Get-SelfXSigningCertificateProblem $Certificate
    if ($null -ne $problem) { throw "The certificate cannot be used for code signing: $problem." }
    if ($PSBoundParameters.ContainsKey('TimestampServer') -and -not (Test-SelfXTimestampUrl $TimestampServer)) {
        throw 'The time stamp server must be an absolute http or https address without user information.'
    }
    $folder = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path).TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw 'The folder does not exist.' }
    if (Test-SelfXReparsePoint $folder) { throw 'The folder is a link; links are refused.' }
    $catalog = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($CatalogFilePath)
    if ([IO.Path]::GetExtension($catalog).ToLowerInvariant() -ne '.cat') { throw 'The catalog file must have the extension .cat.' }
    $catalogFolder = Split-Path -Parent $catalog
    if (-not (Test-Path -LiteralPath $catalogFolder -PathType Container)) { throw 'The folder of the catalog file does not exist.' }
    if ($catalog.StartsWith($folder + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The catalog file must be outside the folder that it covers.'
    }
    if ((Test-Path -LiteralPath $catalog) -and -not $Force) { throw 'The catalog file exists already (use -Force to replace it).' }

    $entries = @(Get-ChildItem -LiteralPath $folder -Recurse -Force -ErrorAction Stop)
    foreach ($entry in $entries) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "The folder contains a link; links are refused: $($entry.Name)" }
    }
    $fileCount = @($entries | Where-Object { -not $_.PSIsContainer }).Count
    if ($fileCount -eq 0) { throw 'The folder contains no file.' }

    if (Test-Path -LiteralPath $catalog -PathType Leaf) { Remove-Item -LiteralPath $catalog -Force -ErrorAction Stop }
    try {
        $null = New-FileCatalog -Path $folder -CatalogFilePath $catalog -CatalogVersion 2 -ErrorAction Stop
        $signArguments = @{ Path = $catalog; Certificate = $Certificate }
        if ($PSBoundParameters.ContainsKey('TimestampServer')) { $signArguments.TimestampServer = $TimestampServer }
        $signed = @(Set-SelfXCodeSignature @signArguments)
    } catch {
        if (Test-Path -LiteralPath $catalog -PathType Leaf) { Remove-Item -LiteralPath $catalog -Force -ErrorAction SilentlyContinue }
        throw
    }
    return [pscustomobject]@{
        CatalogFilePath = $catalog
        FileCount       = $fileCount
        Thumbprint      = $signed[0].Thumbprint
        TimeStamped     = $signed[0].TimeStamped
    }
}

function Test-SelfXSignature {
    <#
    .SYNOPSIS
        Checks the Authenticode signature of a file: status Valid AND the signer is in the list of allowed signers.

    .DESCRIPTION
        "Any valid signature" is not enough. An empty list or a thumbprint that is not 40 hexadecimal characters stops the function
        (it never means "everything is allowed"). The function does not stop for a bad file: it returns IsValid = $false.

        Returns Path, IsValid, Reason, Status, Thumbprint. Reason is one of: Ok, FileMissing, NotSigned, HashMismatch, NotSupported,
        NotTrusted (status NotTrusted, UnknownError or another status that is not Valid, for example a certificate that expired
        without a time stamp or a root that the computer does not trust), SignerNotAllowed, Error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedThumbprint
    )

    $allowed = ConvertTo-SelfXThumbprintList $AllowedThumbprint
    $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    $result = [pscustomobject]@{ Path = $full; IsValid = $false; Reason = 'Error'; Status = ''; Thumbprint = '' }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $result.Reason = 'FileMissing'; return $result }
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop
    } catch {
        $result.Reason = 'Error'
        return $result
    }
    $result.Status = [string]$signature.Status
    if ($null -ne $signature.SignerCertificate) { $result.Thumbprint = $signature.SignerCertificate.Thumbprint }
    switch ($result.Status) {
        'Valid' {
            if ([string]::IsNullOrEmpty($result.Thumbprint)) { $result.Reason = 'Error' }
            elseif ($allowed -notcontains $result.Thumbprint.ToUpperInvariant()) { $result.Reason = 'SignerNotAllowed' }
            else { $result.IsValid = $true; $result.Reason = 'Ok' }
        }
        'NotSigned' { $result.Reason = 'NotSigned' }
        'HashMismatch' { $result.Reason = 'HashMismatch' }
        'NotSupportedFileFormat' { $result.Reason = 'NotSupported' }
        default { $result.Reason = 'NotTrusted' }
    }
    return $result
}

function Test-SelfXSignedCatalog {
    <#
    .SYNOPSIS
        Checks that a catalog is signed by an allowed signer and that the folder matches it exactly.

    .DESCRIPTION
        First the signature of the catalog (Test-SelfXSignature, same rules). Then Test-FileCatalog -Detailed; the lists of the
        catalog and of the folder are compared by the function itself, so that the result names the files: ChangedFiles (hash
        differs), MissingFiles (in the catalog, not in the folder), ExtraFiles (in the folder, not in the catalog). The catalog may
        lie inside the folder; it is not counted as a file of the folder then. Anything unexpected, also an exception, gives
        IsValid = $false (fail closed).

        Returns CatalogFilePath, IsValid, Reason, Thumbprint, ChangedFiles, MissingFiles, ExtraFiles. Reason: Ok, FileMissing,
        CatalogSignature:<reason of Test-SelfXSignature>, FilesDiffer, CatalogStatus, NoDetails, Error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CatalogFilePath,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedThumbprint
    )

    $allowed = ConvertTo-SelfXThumbprintList $AllowedThumbprint
    $catalog = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($CatalogFilePath)
    $folder = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path).TrimEnd('\', '/')
    $result = [pscustomobject]@{
        CatalogFilePath = $catalog; IsValid = $false; Reason = 'Error'; Thumbprint = ''
        ChangedFiles = @(); MissingFiles = @(); ExtraFiles = @()
    }
    if (-not (Test-Path -LiteralPath $catalog -PathType Leaf) -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        $result.Reason = 'FileMissing'
        return $result
    }
    try {
        $signature = Test-SelfXSignature -Path $catalog -AllowedThumbprint $allowed
        $result.Thumbprint = $signature.Thumbprint
        if (-not $signature.IsValid) { $result.Reason = "CatalogSignature:$($signature.Reason)"; return $result }

        $inside = $catalog.StartsWith($folder + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
        $catalogKey = $null
        $checkArguments = @{ Path = $folder; CatalogFilePath = $catalog; Detailed = $true; ErrorAction = 'Stop' }
        if ($inside) {
            $catalogKey = $catalog.Substring($folder.Length + 1)
            $checkArguments.FilesToSkip = @($catalogKey)
        }
        $information = Test-FileCatalog @checkArguments
        if ($null -eq $information -or $null -eq $information.CatalogItems -or $null -eq $information.PathItems) { $result.Reason = 'NoDetails'; return $result }

        $inCatalog = @{}
        foreach ($key in $information.CatalogItems.Keys) { $inCatalog[([string]$key).ToLowerInvariant()] = [string]$information.CatalogItems[$key] }
        $inFolder = @{}
        foreach ($key in $information.PathItems.Keys) { $inFolder[([string]$key).ToLowerInvariant()] = [string]$information.PathItems[$key] }
        if ($null -ne $catalogKey) { $null = $inCatalog.Remove($catalogKey.ToLowerInvariant()); $null = $inFolder.Remove($catalogKey.ToLowerInvariant()) }

        $changed = New-Object System.Collections.Generic.List[string]
        $missing = New-Object System.Collections.Generic.List[string]
        $extra = New-Object System.Collections.Generic.List[string]
        foreach ($key in $inCatalog.Keys) {
            if (-not $inFolder.ContainsKey($key)) { $missing.Add($key) }
            elseif ($inFolder[$key] -ne $inCatalog[$key]) { $changed.Add($key) }
        }
        foreach ($key in $inFolder.Keys) { if (-not $inCatalog.ContainsKey($key)) { $extra.Add($key) } }
        $result.ChangedFiles = @($changed | Sort-Object)
        $result.MissingFiles = @($missing | Sort-Object)
        $result.ExtraFiles = @($extra | Sort-Object)
        if ($changed.Count -gt 0 -or $missing.Count -gt 0 -or $extra.Count -gt 0) { $result.Reason = 'FilesDiffer'; return $result }
        # Without the catalog inside the folder the status of Test-FileCatalog must also say Valid; with it, Test-FileCatalog
        # may count the catalog itself, so only the comparison above decides.
        if (-not $inside -and [string]$information.Status -ne 'Valid') { $result.Reason = 'CatalogStatus'; return $result }
        if ($inCatalog.Count -eq 0) { $result.Reason = 'NoDetails'; return $result }
        $result.IsValid = $true
        $result.Reason = 'Ok'
        return $result
    } catch {
        $result.Reason = 'Error'
        return $result
    }
}
