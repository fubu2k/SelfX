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
    for SelfX Service, that $ExpectedVersion in Detection.ps1 matches Tool_Version in
    Sources\Tool_Config.xml (otherwise the Intune detection would fail after installation).
    The version in the file name comes from Tool_Version.

    The script only reads the product folders, writes the staging folder (deleted at the end)
    and the build folder. It uploads nothing to Intune.
    Exit code 0 = all requested packages created, 1 = at least one package failed.

.PARAMETER Product
    Product to build. Only Service exists in this repository (the parameter is kept for compatibility).

.PARAMETER OutputFolder
    Target folder of the .intunewin files. Default: <repository>\build.

.PARAMETER ToolPath
    Path of the Microsoft IntuneWinAppUtil.exe. Defaults to tools\IntuneWinAppUtil.exe.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1

.EXAMPLE
    .\tools\New-SelfXIntuneWin.ps1 -Product Service -ToolPath C:\Tools\IntuneWinAppUtil.exe

.NOTES
    Name    : New-SelfXIntuneWin.ps1
    Package : SelfX (repository tool, not installed)
    Context : Packaging, run by the administrator; no administrator rights needed
    Version : 1.5.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-04  Wolfgang Baeck       Initial version
    1.1.0    2026-11-16  Wolfgang Baeck       Module SvRooij.ContentPrep.Cmdlet instead of the IntuneWinAppUtil.exe in the
                                              repository (license); the Microsoft tool is optional (-ToolPath)
    1.2.0    2026-11-20  Wolfgang Baeck       Use only the Microsoft tool; remove the module dependency and verify its signature
    1.3.0    2026-11-22  fubu2k               Only SelfX Service (SelfX Admin and SelfX Standard are no longer part of this repository)
    1.4.0    2026-11-22  fubu2k               Bin (.NET 10 programs) is required and fully checked; the .NET project files are not packaged
    1.5.0    2026-11-23  fubu2k               Writes SelfX.Files.json (SHA256 of all installed files) into the package (finding N4)
#>

[CmdletBinding()]
param(
    [ValidateSet('Service')]
    [string[]]$Product = @('Service'),
    [string]$OutputFolder,
    [string]$ToolPath
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 does not set $PSScriptRoot for parameter defaults, so they are resolved here.
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
if (-not $OutputFolder) { $OutputFolder = Join-Path $RepositoryRoot 'build' }
if (-not $ToolPath) { $ToolPath = Join-Path $ScriptFolder 'IntuneWinAppUtil.exe' }

# Source folder, setup file and version source of every product.
$Definitions = @{
    Service = @{ Folder = 'SelfX Service';  Setup = 'Install.ps1';  VersionFile = 'Sources\Tool_Config.xml'; VersionXPath = '/GUI_Config/Tool_Version' }
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
    $node = (Read-XmlFile (Join-Path $Folder $Definition.VersionFile)).SelectSingleNode($Definition.VersionXPath)
    if (-not $node -or [string]::IsNullOrWhiteSpace($node.InnerText)) { throw "No version found in $($Definition.VersionFile) ($($Definition.VersionXPath))." }
    $version = $node.InnerText.Trim()
    # The version becomes part of a file name.
    if ($version -notmatch '^[0-9A-Za-z.\-]{1,30}$') { throw "Invalid version '$version' in $($Definition.VersionFile)." }
    return $version
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
        if ($Matches[1] -ne $Version) { throw "Detection.ps1 expects version $($Matches[1]), Tool_Config.xml has $Version. Set both to the same value." }
        # Prebuilt programs (F9, .NET 10): Bin is required, and it must have been built from the sources of this
        # package, otherwise Install.ps1 would refuse it on every device.
        $bin = Join-Path $Stage 'Bin'
        if (-not (Test-Path -LiteralPath (Join-Path $bin 'SelfX.Binaries.json') -PathType Leaf)) { throw 'The folder Bin with SelfX.Binaries.json is missing. Run tools\Build-SelfXBinaries.ps1 first (docs\Installation.md).' }
        $manifest = Get-Content -LiteralPath (Join-Path $bin 'SelfX.Binaries.json') -Raw | ConvertFrom-Json
        if ("$($manifest.ManifestVersion)" -ne '3') { throw 'Bin was built by an older Build-SelfXBinaries.ps1. Run tools\Build-SelfXBinaries.ps1 again.' }
        foreach ($source in @('Service/SelfXService.cs', 'Service/SelfXLauncher.cs', 'Service/SelfXSessionStarter.cs', 'Service/SelfXWinRT.cs')) {
            $hash = (Get-FileHash -LiteralPath (Join-Path $Stage ($source.Replace('/', '\'))) -Algorithm SHA256).Hash
            if ($hash -ne "$($manifest.Sources.$source)") { throw "Bin was not built from the current $source. Run tools\Build-SelfXBinaries.ps1 again." }
        }
        # Every file that the manifest lists (the three programs and the DLLs in WinRT) must exist and match.
        foreach ($file in @($manifest.Binaries.PSObject.Properties.Name) + @('SelfXService.exe', 'SelfX.exe', 'SelfXSessionStarter.dll', 'WinRT/SelfXWinRT.dll') | Select-Object -Unique) {
            $hash = (Get-FileHash -LiteralPath (Join-Path $bin $file.Replace('/', '\')) -Algorithm SHA256).Hash
            if ($hash -ne "$($manifest.Binaries.$file)") { throw "Bin\$file does not match the manifest. Run tools\Build-SelfXBinaries.ps1 again." }
        }
        Write-Host "Service: programs from Bin (.NET SDK $($manifest.SdkVersion), checked against the manifest)."
    }
}

# Writes SelfX.Files.json into the staged package (security review finding N4): the SHA256 of every file that Install.ps1
# copies to the installation folder (everything below Sources, plus Uninstall.ps1). Install.ps1 checks the package against
# it before anything is installed and keeps the file in the installation folder; the service uses it before it starts a script.
function New-SelfXFileManifest {
    param([string]$Stage, [string]$Version)
    $sources = Join-Path $Stage 'Sources'
    if (-not (Test-Path -LiteralPath $sources -PathType Container)) { throw 'The folder Sources is missing in the package.' }
    $files = [ordered]@{}
    $items = @(Get-ChildItem -LiteralPath $sources -Recurse -File -Force) + @(Get-Item -LiteralPath (Join-Path $Stage 'Uninstall.ps1') -Force)
    foreach ($item in ($items | Sort-Object FullName)) {
        $relative = if ($item.FullName.StartsWith($sources + '\', [StringComparison]::OrdinalIgnoreCase)) { $item.FullName.Substring($sources.Length + 1) } else { $item.Name }
        $relative = $relative.Replace('\', '/')
        if ($relative -notmatch '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*$' -or $relative -match '(^|/)\.\.?(/|$)') { throw "Unsupported file name in the package: $relative" }
        $files[$relative] = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
    $manifest = [ordered]@{
        ManifestVersion = 1
        ToolVersion     = $Version
        BuiltUtc        = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        Files           = $files
    }
    $path = Join-Path $Stage 'SelfX.Files.json'
    [IO.File]::WriteAllText($path, ($manifest | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    return $files.Count
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
        $sourceFolder = Join-Path $RepositoryRoot $definition.Folder
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
            # The .NET project files (and build leftovers next to them) are only needed on the build machine.
            $projectsInStage = Join-Path $stage 'Service\Projects'
            if (Test-Path -LiteralPath $projectsInStage) { Remove-Item -LiteralPath $projectsInStage -Recurse -Force }
            Test-StagedPackage -Stage $stage -Name $name -Definition $definition -Version $version
            if ($name -eq 'Service') { Write-Host ('Service: SelfX.Files.json lists {0} files.' -f (New-SelfXFileManifest -Stage $stage -Version $version)) }

            $created = New-PackageFile -Stage $stage -SetupFile $definition.Setup -OutputDir $toolOutput

            $target = Join-Path $OutputFolder ('SelfX-{0}-{1}.intunewin' -f $name, $version)
            Move-Item -LiteralPath $created -Destination $target -Force
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
