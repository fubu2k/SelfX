<#
.SYNOPSIS
    Build the Intune Win32 app package (.intunewin) of SelfX Service.

.DESCRIPTION
    Wraps the product folder into one .intunewin file in the build folder of the repository:

      Product  Source folder    Setup file     Output file
      -------  ---------------  -------------  ---------------------------------
      Service  SelfX Service    Install.ps1    build\SelfX-Service-<version>.intunewin

    The Microsoft Win32 Content Prep Tool (IntuneWinAppUtil.exe) is required. Pass its path with
    -ToolPath, or place it next to this script. The script verifies that it has a valid Microsoft
    Authenticode signature. No packaging tool is kept in the repository.

    Each product folder is first copied to a temporary staging folder, so that packaging-only
    files (Test-*.ps1) are not shipped and the source folders stay unchanged. Before
    packaging, the script checks that the setup file exists, that all XML files are valid and,
    for SelfX Service, that $ExpectedVersion in Detection.ps1 matches the version in Version.txt of the
    product folder (otherwise the Intune detection would fail after installation).
    The version is a property of the code: it comes from Version.txt, is written into SelfX.Code.json (ToolVersion) and into the
    name of the file. Version.txt itself is not part of the package and Tool_Config.xml does not carry the version.
    Next to the .intunewin it writes build\SelfX-Service-<version>.Detection.ps1: Detection.ps1 with the
    digests of the two file lists (SelfX.Code.json and SelfX.Config.json) filled in. Upload that file as the detection script to
    Intune (not the repository copy): then the detection also finds an update whose files changed without a new version, and a
    changed configuration (for example a logo) without a new code version.
    SelfX.Config.json gets ConfigRevision, the UTC time of this run.
    In the staging folder the files of Sources are sorted into App\ (code) and Config\ (configuration) by their file class
    (ConvertTo-SelfXPackageLayout in tools\SelfXPackage.Common.ps1); the lists are App\SelfX.Code.json and Config\SelfX.Config.json.
    Install.ps1 installs them into %ProgramFiles%\SelfX\App and %ProgramFiles%\SelfX\Config.

    The script only reads the product folders, writes the staging folder (deleted at the end)
    and the build folder. It uploads nothing to Intune.
    Exit code 0 = all requested packages created, 1 = at least one package failed.

.PARAMETER Product
    Product to build. Only Service exists in this repository (the parameter is kept for compatibility).

.PARAMETER OutputFolder
    Target folder of the .intunewin files. Default: <repository>\build.

.PARAMETER ToolPath
    Path of the Microsoft IntuneWinAppUtil.exe. Defaults to tools\IntuneWinAppUtil.exe.

.PARAMETER PayloadFile
    Optional. Also writes the payload archive (SelfX-Service-<version>-payload.zip) to this path: the staged package folder exactly as
    it is packed into the .intunewin plus the package tools (New-SelfXPayloadArchive in tools\SelfXRelease.Common.ps1). The release
    workflow uses it; a build with -SourceFolder (the package assistant) does not.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1

.EXAMPLE
    .\tools\New-SelfXIntuneWin.ps1 -Product Service -ToolPath C:\Tools\IntuneWinAppUtil.exe

.NOTES
    Name    : New-SelfXIntuneWin.ps1
    Package : SelfX (repository tool, not installed)
    Context : Packaging, run by the administrator; no administrator rights needed
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-04  Wolfgang Baeck       Initial version
    1.6.1    2026-11-23  fubu2k               SelfX.Files.json also lists SelfXService.exe and SelfX.exe from Bin
    1.7.0    2026-11-23  fubu2k               Security (M2): also writes build\SelfX-Service-<version>.Detection.ps1 with the digest of
                                              SelfX.Files.json (changed files are detected without a version change)
    1.8.0    2026-11-24  fubu2k               New parameter -SourceFolder: build from a configured copy of the package (New-SelfXPackage.ps1)
    1.9.0    2026-11-27  fubu2k               Two file lists instead of SelfX.Files.json: SelfX.Code.json and SelfX.Config.json by file class
                                              (tools\SelfXPackage.Common.ps1); Detection.ps1 gets two digests
    1.10.0   2026-11-27  fubu2k               The version comes from Version.txt (no longer from Tool_Config.xml) and is written only into SelfX.Code.json;
                                              SelfX.Config.json gets ConfigRevision
    3.1.0    2026-11-27  fubu2k               Package layout App\ and Config\ instead of Sources\ (ConvertTo-SelfXPackageLayout)
    3.1.0    2026-11-27  fubu2k               New parameter -PayloadFile: also writes the payload archive of the release (tools\SelfXRelease.Common.ps1)
#>

[CmdletBinding()]
param(
    [ValidateSet('Service')]
    [string[]]$Product = @('Service'),
    [string]$OutputFolder,
    [string]$ToolPath,
    # Package folder to build from instead of the folder of the repository (used by New-SelfXPackage.ps1: a configured copy).
    [string]$SourceFolder,
    # Target of the payload archive of the release (optional; see .PARAMETER PayloadFile).
    [string]$PayloadFile
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 does not set $PSScriptRoot for parameter defaults, so they are resolved here.
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
# File classes, SelfX.Code.json, SelfX.Config.json and the Detection.ps1 writer (shared with the tests).
. (Join-Path $ScriptFolder 'SelfXPackage.Common.ps1')
# The payload archive of the release.
. (Join-Path $ScriptFolder 'SelfXRelease.Common.ps1')
if (-not $OutputFolder) { $OutputFolder = Join-Path $RepositoryRoot 'build' }
if (-not $ToolPath) { $ToolPath = Join-Path $ScriptFolder 'IntuneWinAppUtil.exe' }
# A relative path is relative to the current folder of PowerShell (not to the process folder of .NET).
if ($PayloadFile -and -not [IO.Path]::IsPathRooted($PayloadFile)) { $PayloadFile = Join-Path (Get-Location).ProviderPath $PayloadFile }

# Source folder, setup file and version source of every product. The version is read from Version.txt (the code carries it, not the
# configuration).
$Definitions = @{
    Service = @{ Folder = 'SelfX Service';  Setup = 'Install.ps1';  VersionFile = 'Version.txt' }
}
# Files used only to build or test a package; they are never shipped.
$ExcludedFiles = @('Test-*.ps1')

function Read-XmlFile {
    param([string]$Path)
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $document.Load($Path)
    return $document
}

function Get-ProductVersion {
    param([string]$Folder, [hashtable]$Definition)
    # Also used as part of a file name; Get-SelfXVersionFromFile allows letters, digits, '.' and '-' (30 characters at most).
    return (Get-SelfXVersionFromFile -Path (Join-Path $Folder $Definition.VersionFile))
}

function Test-StagedPackage {
    param([string]$Stage, [string]$Name, [hashtable]$Definition, [string]$Version)
    if (-not (Test-Path -LiteralPath (Join-Path $Stage $Definition.Setup) -PathType Leaf)) { throw "Setup file '$($Definition.Setup)' is missing." }
    foreach ($xml in @(Get-ChildItem -LiteralPath $Stage -Recurse -File -Filter '*.xml')) {
        try { $null = Read-XmlFile $xml.FullName }
        catch { throw "Invalid XML '$($xml.FullName.Substring($Stage.Length + 1))': $($_.Exception.Message)" }
    }
    if ($Name -eq 'Service') {
        $detection = Get-Content -LiteralPath (Join-Path $Stage 'Detection.ps1') -Raw
        if ($detection -notmatch "\`$ExpectedVersion\s*=\s*'([^']+)'") { throw 'No $ExpectedVersion found in Detection.ps1.' }
        if ($Matches[1] -ne $Version) { throw "Detection.ps1 expects version $($Matches[1]), $($Definition.VersionFile) has $Version. Set both to the same value." }
        # Prebuilt programs (F9, .NET 10): Bin is required, and it must have been built from the sources of this
        # package, otherwise Install.ps1 would refuse it on every device.
        $bin = Join-Path $Stage 'Bin'
        if (-not (Test-Path -LiteralPath (Join-Path $bin 'SelfX.Binaries.json') -PathType Leaf)) { throw 'The folder Bin with SelfX.Binaries.json is missing. Run tools\Build-SelfXBinaries.ps1 first (docs\Installation.md).' }
        $manifest = Get-Content -LiteralPath (Join-Path $bin 'SelfX.Binaries.json') -Raw | ConvertFrom-Json
        if ("$($manifest.ManifestVersion)" -ne '3') { throw 'Bin was built by an older Build-SelfXBinaries.ps1. Run tools\Build-SelfXBinaries.ps1 again.' }
        foreach ($source in @('Service/SelfXService.cs', 'Service/SelfXLauncher.cs', 'Service/SelfXSessionStarter.cs', 'Service/SelfXWinRT.cs', 'Service/SelfXAudio.cs')) {
            $hash = (Get-FileHash -LiteralPath (Join-Path $Stage ($source.Replace('/', '\'))) -Algorithm SHA256).Hash
            if ($hash -ne "$($manifest.Sources.$source)") { throw "Bin was not built from the current $source. Run tools\Build-SelfXBinaries.ps1 again." }
        }
        # Every file that the manifest lists (the three programs and the DLLs in WinRT) must exist and match.
        foreach ($file in @($manifest.Binaries.PSObject.Properties.Name) + @('SelfXService.exe', 'SelfX.exe', 'SelfXSessionStarter.dll', 'WinRT/SelfXWinRT.dll', 'Audio/SelfXAudio.dll') | Select-Object -Unique) {
            $hash = (Get-FileHash -LiteralPath (Join-Path $bin $file.Replace('/', '\')) -Algorithm SHA256).Hash
            if ($hash -ne "$($manifest.Binaries.$file)") { throw "Bin\$file does not match the manifest. Run tools\Build-SelfXBinaries.ps1 again." }
        }
        Write-Host "Service: programs from Bin (.NET SDK $($manifest.SdkVersion), checked against the manifest)."
    }
}

# Creates <OutputDir>\<setup file name>.intunewin, like IntuneWinAppUtil.exe.
function New-PackageFile {
    param([string]$Stage, [string]$SetupFile, [string]$OutputDir)
    $created = Join-Path $OutputDir ([IO.Path]::GetFileNameWithoutExtension($SetupFile) + '.intunewin')
    # -q: no prompts and overwrite.
    $toolLog = @(& $ToolPath -c $Stage -s $SetupFile -o $OutputDir -q 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $created -PathType Leaf)) {
        throw "IntuneWinAppUtil.exe failed (exit code $LASTEXITCODE): $(($toolLog | Select-Object -Last 5) -join ' / ')"
    }
    return $created
}

if (-not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) { throw "IntuneWinAppUtil.exe not found: $ToolPath" }
$signature = Get-AuthenticodeSignature -LiteralPath $ToolPath
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike 'CN=Microsoft Corporation,*') {
    throw "IntuneWinAppUtil.exe is not validly signed by Microsoft ($($signature.Status))."
}
Write-Host "Packaging with $ToolPath"
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$OutputFolder = (Resolve-Path -LiteralPath $OutputFolder).Path

$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-IntuneWin-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$results = New-Object System.Collections.Generic.List[object]
try {
    foreach ($name in $Product) {
        $definition = $Definitions[$name]
        $sourceFolder = if ($SourceFolder) { $SourceFolder } else { Join-Path $RepositoryRoot $definition.Folder }
        $stage = Join-Path $workRoot "$name\source"
        $toolOutput = Join-Path $workRoot "$name\output"
        $version = $null
        try {
            if (-not (Test-Path -LiteralPath $sourceFolder -PathType Container)) { throw "Source folder not found: $sourceFolder" }
            $version = Get-ProductVersion -Folder $sourceFolder -Definition $definition
            Write-Host "Building SelfX $name $version from '$($definition.Folder)' ..."

            New-Item -ItemType Directory -Path $stage, $toolOutput -Force | Out-Null
            Copy-Item -Path (Join-Path $sourceFolder '*') -Destination $stage -Recurse -Force
            foreach ($pattern in $ExcludedFiles) {
                Get-ChildItem -LiteralPath $stage -Recurse -File -Filter $pattern | Remove-Item -Force
            }
            # Version.txt is read above and written into SelfX.Code.json; the device gets the version from that list only.
            Remove-Item -LiteralPath (Join-Path $stage $definition.VersionFile) -Force -ErrorAction SilentlyContinue
            # The .NET project files (and build leftovers next to them) are only needed on the build machine.
            $projectsInStage = Join-Path $stage 'Service\Projects'
            if (Test-Path -LiteralPath $projectsInStage) { Remove-Item -LiteralPath $projectsInStage -Recurse -Force }
            Test-StagedPackage -Stage $stage -Name $name -Definition $definition -Version $version
            if ($name -eq 'Service') {
                # Code and configuration in two folders (App, Config), sorted by file class; a file without a class stops the build.
                $layout = ConvertTo-SelfXPackageLayout -Stage $stage
                Write-Host ('Service: {0} code files in App, {1} configuration files in Config.' -f $layout.Code, $layout.Config)
                Write-Host ('Service: SelfX.Code.json lists {0} files.' -f (New-SelfXCodeManifest -Stage $stage -Version $version))
                Write-Host ('Service: SelfX.Config.json lists {0} files.' -f (New-SelfXConfigManifest -Stage $stage))
            }

            if ($name -eq 'Service' -and $PayloadFile) {
                # The package folder as it is now is also the content of the .intunewin; the archive adds the tools of the assistant.
                $payloadEntries = New-SelfXPayloadArchive -Stage $stage -RepositoryRoot $RepositoryRoot -Target $PayloadFile
                Write-Host "Service: payload archive with $payloadEntries files: $PayloadFile"
            }

            $created = New-PackageFile -Stage $stage -SetupFile $definition.Setup -OutputDir $toolOutput

            $target = Join-Path $OutputFolder ('SelfX-{0}-{1}.intunewin' -f $name, $version)
            Move-Item -LiteralPath $created -Destination $target -Force
            if ($name -eq 'Service') {
                $detectionTarget = Join-Path $OutputFolder ('SelfX-{0}-{1}.Detection.ps1' -f $name, $version)
                $digests = New-SelfXDetectionScript -Stage $stage -Target $detectionTarget
                Write-Host "Service: $detectionTarget contains the digest of SelfX.Code.json ($($digests.Code)) and of SelfX.Config.json ($($digests.Config)). Upload this file as the detection script to Intune."
            }
            $file = Get-Item -LiteralPath $target
            $results.Add([pscustomobject]@{
                Product   = $name
                Version   = $version
                SetupFile = $definition.Setup
                Files     = @(Get-ChildItem -LiteralPath $stage -Recurse -File).Count
                SizeKB    = [math]::Round($file.Length / 1KB)
                Package   = $file.FullName
                Status    = 'OK'
            })
        } catch {
            Write-Warning "SelfX $name failed: $($_.Exception.Message)"
            $results.Add([pscustomobject]@{ Product = $name; Version = $version; SetupFile = $definition.Setup; Files = $null; SizeKB = $null; Package = $null; Status = "Failed: $($_.Exception.Message)" })
        }
    }
} finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$results | Format-Table Product, Version, SetupFile, Files, SizeKB, Status -AutoSize | Out-String -Width 200 | Write-Host
$results | Where-Object Status -eq 'OK' | ForEach-Object { Write-Host "  $($_.Package)" }
if (@($results | Where-Object Status -ne 'OK').Count) { exit 1 }
exit 0
