<#
.SYNOPSIS
    Writes a software bill of materials (SBOM, CycloneDX 1.5 JSON) for the SelfX Service package.

.DESCRIPTION
    An SBOM lists what a package consists of, in a format that security tools can read. This script
    reads only files of the repository and of the build output; it downloads and installs nothing:

      - the programs of "SelfX Service\Bin" with their SHA-256 (from SelfX.Binaries.json, checked against the files),
      - the NuGet packages that are pinned by the lock files in SelfX Service\Service\Projects
        (name, version, SHA-512 content hash),
      - the .NET SDK version that built the programs (the .NET runtime is part of the self-contained programs).

    Run it after tools\Build-SelfXBinaries.ps1. The release workflow (.github\workflows\release.yml) runs both.

.PARAMETER OutputFile
    Target file. Default: build\SelfX-Service-<version>.sbom.cdx.json in the repository.

.PARAMETER BinFolder
    Folder with the built programs. Default: "SelfX Service\Bin".

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXSbom.ps1

.NOTES
    Name    : New-SelfXSbom.ps1
    Package : tools
    Context : Build machine (not installed, no administrator rights needed)
    Version : 1.0.0
    Exit code: 0 = written, an exception otherwise

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-23  fubu2k               Initial version.
#>

[CmdletBinding()]
param(
    [string]$OutputFile,
    [string]$BinFolder
)

$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$PackageFolder = Join-Path $RepositoryRoot 'SelfX Service'
if (-not $BinFolder) { $BinFolder = Join-Path $PackageFolder 'Bin' }

$manifestPath = Join-Path $BinFolder 'SelfX.Binaries.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Manifest not found: $manifestPath (run tools\Build-SelfXBinaries.ps1 first)." }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$version = "$($manifest.ToolVersion)"
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Unexpected version in the manifest: '$version'" }
if (-not $OutputFile) { $OutputFile = Join-Path (Join-Path $RepositoryRoot 'build') "SelfX-Service-$version.sbom.cdx.json" }

# Programs: the SHA-256 of every file must match the manifest, otherwise the SBOM would describe other files.
$components = New-Object System.Collections.Generic.List[object]
foreach ($property in $manifest.Binaries.PSObject.Properties) {
    $file = Join-Path $BinFolder ($property.Name.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Listed in the manifest but missing: $($property.Name)" }
    $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    if ($actual -ne $property.Value) { throw "SHA-256 of $($property.Name) does not match the manifest." }
    $components.Add([ordered]@{
        type      = 'file'
        'bom-ref' = "file:$($property.Name)"
        name      = $property.Name
        version   = $version
        hashes    = @([ordered]@{ alg = 'SHA-256'; content = $actual.ToLowerInvariant() })
    })
}

# NuGet packages from the lock files (direct and transitive, one entry per name and version).
function ConvertTo-HexHash {
    param([string]$Base64)
    return (([Convert]::FromBase64String($Base64) | ForEach-Object { $_.ToString('x2') }) -join '')
}
$seen = @{}
foreach ($lock in Get-ChildItem -LiteralPath (Join-Path $PackageFolder 'Service\Projects') -Recurse -Filter 'packages.lock.json') {
    $document = Get-Content -LiteralPath $lock.FullName -Raw | ConvertFrom-Json
    foreach ($framework in $document.dependencies.PSObject.Properties) {
        foreach ($package in $framework.Value.PSObject.Properties) {
            $resolved = "$($package.Value.resolved)"
            if (-not $resolved) { continue }
            $key = "$($package.Name)@$resolved"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $component = [ordered]@{
                type      = 'library'
                'bom-ref' = "pkg:nuget/$($package.Name)@$resolved"
                name      = $package.Name
                version   = $resolved
                purl      = "pkg:nuget/$($package.Name)@$resolved"
            }
            if ($package.Value.contentHash) {
                $component.hashes = @([ordered]@{ alg = 'SHA-512'; content = (ConvertTo-HexHash -Base64 "$($package.Value.contentHash)") })
            }
            $components.Add($component)
        }
    }
}

$bom = [ordered]@{
    bomFormat    = 'CycloneDX'
    specVersion  = '1.5'
    serialNumber = 'urn:uuid:' + [guid]::NewGuid().ToString()
    version      = 1
    metadata     = [ordered]@{
        timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        tools     = @([ordered]@{ vendor = 'fubu2k'; name = 'New-SelfXSbom.ps1'; version = '1.0.0' },
                      [ordered]@{ vendor = 'Microsoft'; name = '.NET SDK'; version = "$($manifest.SdkVersion)" })
        component = [ordered]@{
            type      = 'application'
            'bom-ref' = 'selfx-service'
            name      = 'SelfX Service'
            version   = $version
        }
    }
    components   = $components.ToArray()
}

$outFolder = Split-Path -Parent $OutputFile
if ($outFolder -and -not (Test-Path -LiteralPath $outFolder)) { New-Item -ItemType Directory -Path $outFolder -Force | Out-Null }
[IO.File]::WriteAllText($OutputFile, ($bom | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("SBOM written: {0} ({1} components)" -f $OutputFile, $components.Count)
