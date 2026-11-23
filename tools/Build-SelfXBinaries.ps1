<#
.SYNOPSIS
    Builds the programs of SelfX Service once on a build machine with .NET 10 and writes a SHA256 manifest and
    AppLocker hash rules.

.DESCRIPTION
    The devices do not compile anything. This script builds the three programs from the sources of the package
    with the .NET SDK 10 (dotnet publish, self-contained: no .NET runtime is needed on the devices):

      SelfX Service\Bin\SelfXService.exe          service (Service\SelfXService.cs)
      SelfX Service\Bin\SelfX.exe                 starter without console window (Service\SelfXLauncher.cs)
      SelfX Service\Bin\SelfXSessionStarter.dll   used by Install.ps1 only (Service\SelfXSessionStarter.cs)
      SelfX Service\Bin\SelfX.Binaries.json       manifest: SHA256 of the three sources and the three files

    The project files are in SelfX Service\Service\Projects. The only NuGet package is pinned by a lock file
    (packages.lock.json) and restored in locked mode. The build is reproducible: the same sources and the same
    SDK give the same files. The files are not signed (decision 2026-11-22: allow them by hash, no certificate).
    When the AppLocker cmdlets are available, the script also writes build\SelfX.AppLocker.xml with hash rules
    for the three files (AppLocker uses its own Authenticode SHA256, not the file SHA256 of the manifest). The
    rules are not part of the package; merge them into the AppLocker policy before the package is deployed.
    Install.ps1 requires the Bin folder and checks it (see docs\Installation.md).

    Requirement on the build machine: .NET SDK 10 (command dotnet, https://dotnet.microsoft.com/download),
    internet access to nuget.org for the restore. Run in Windows PowerShell 5.1 or PowerShell 7:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1

.PARAMETER OutputFolder
    Default: "SelfX Service\Bin" of the repository. The folder is not committed (.gitignore).

.NOTES
    Name    : Build-SelfXBinaries.ps1
    Package : tools
    Context : Build machine (administrator of the package; not installed)
    Version : 2.8.18
    Exit code: 0 = built, an exception otherwise

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.11   2026-11-22  fubu2k               Initial version.
    2.8.18   2026-11-23  fubu2k               Also builds Bin\Audio\SelfXAudio.dll (Service\SelfXAudio.cs)
#>

[CmdletBinding()]
param(
    [string]$OutputFolder
)

$ErrorActionPreference = 'Stop'

$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$PackageFolder = Join-Path $RepositoryRoot 'SelfX Service'
$ProjectsFolder = Join-Path $PackageFolder 'Service\Projects'
if (-not $OutputFolder) { $OutputFolder = Join-Path $PackageFolder 'Bin' }

# Source file, project and the file that is taken over into Bin.
$Programs = [ordered]@{
    'Service/SelfXService.cs'        = @{ Project = 'SelfXService';        Output = 'SelfXService.exe' }
    'Service/SelfXLauncher.cs'       = @{ Project = 'SelfXLauncher';       Output = 'SelfX.exe' }
    'Service/SelfXSessionStarter.cs' = @{ Project = 'SelfXSessionStarter'; Output = 'SelfXSessionStarter.dll' }
    # Library for PowerShell 7 (WinRT projection). All its DLLs go into Bin\WinRT and are listed one by one in the manifest.
    'Service/SelfXWinRT.cs'          = @{ Project = 'SelfXWinRT';          Folder = 'WinRT'; Output = 'SelfXWinRT.dll' }
    # Library for PowerShell 7 (Core Audio, action "No sound"). No dependencies: Bin\Audio holds only SelfXAudio.dll.
    'Service/SelfXAudio.cs'          = @{ Project = 'SelfXAudio';          Folder = 'Audio'; Output = 'SelfXAudio.dll' }
}

# The .NET SDK 10 is required: another major version would build other files than the ones that were tested.
$dotnet = Get-Command -Name dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) { throw 'The command dotnet was not found. Install the .NET SDK 10 (https://dotnet.microsoft.com/download) and open a new PowerShell window.' }
# global.json in the repository root selects the SDK 10 even when a newer SDK is installed too, so the command
# runs in the repository root.
Push-Location -LiteralPath $RepositoryRoot
try { $sdkVersion = ((& $dotnet.Source --version 2>&1) | Select-Object -First 1).ToString().Trim(); $sdkExit = $LASTEXITCODE }
finally { Pop-Location }
if ($sdkExit -ne 0 -or $sdkVersion -notmatch '^10\.') { throw "The .NET SDK 10 is required, found '$sdkVersion'. Install the .NET SDK 10 (https://dotnet.microsoft.com/download/dotnet/10.0)." }

# No telemetry and no welcome text on the build machine.
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'

# A fresh output folder, so no file of an older build survives.
if (Test-Path -LiteralPath $OutputFolder) { Remove-Item -LiteralPath $OutputFolder -Recurse -Force }
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$publishRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-Build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $publishRoot | Out-Null
$manifestSources = [ordered]@{}
$manifestBinaries = [ordered]@{}
Push-Location -LiteralPath $RepositoryRoot
try {
    foreach ($relative in $Programs.Keys) {
        $definition = $Programs[$relative]
        $project = Join-Path $ProjectsFolder ("{0}\{0}.csproj" -f $definition.Project)
        $publishFolder = Join-Path $publishRoot $definition.Project
        & $dotnet.Source publish $project -c Release -o $publishFolder --nologo -v minimal
        if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed for $($definition.Project) (exit code $LASTEXITCODE)." }
        $built = Join-Path $publishFolder $definition.Output
        if (-not (Test-Path -LiteralPath $built -PathType Leaf)) { throw "dotnet publish did not create $($definition.Output)." }
        $sourcePath = Join-Path $PackageFolder $relative.Replace('/', '\')
        $manifestSources[$relative] = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        if ($definition.Folder) {
            # The library and the Windows SDK projection DLLs it needs, each with its own SHA256.
            $targetFolder = Join-Path $OutputFolder $definition.Folder
            New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
            foreach ($dll in Get-ChildItem -LiteralPath $publishFolder -Filter '*.dll' -File | Sort-Object Name) {
                Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $targetFolder $dll.Name) -Force
                $manifestBinaries["$($definition.Folder)/$($dll.Name)"] = (Get-FileHash -LiteralPath (Join-Path $targetFolder $dll.Name) -Algorithm SHA256).Hash
            }
            continue
        }
        $outputPath = Join-Path $OutputFolder $definition.Output
        Copy-Item -LiteralPath $built -Destination $outputPath -Force
        $manifestBinaries[$definition.Output] = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
    }
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $publishRoot -Recurse -Force -ErrorAction SilentlyContinue
    # dotnet leaves obj and bin next to the project files; they are not needed and must not end up in a package.
    Get-ChildItem -LiteralPath $ProjectsFolder -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($name in 'obj', 'bin') { Remove-Item -LiteralPath (Join-Path $_.FullName $name) -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

$toolConfig = Join-Path $PackageFolder 'Sources\Tool_Config.xml'
$document = New-Object System.Xml.XmlDocument
$document.XmlResolver = $null
$document.Load($toolConfig)
$manifest = [ordered]@{
    ManifestVersion = 3
    SdkVersion      = $sdkVersion
    ToolVersion     = $document.SelectSingleNode('/GUI_Config/Tool_Version').InnerText.Trim()
    BuiltUtc        = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Sources         = $manifestSources
    Binaries        = $manifestBinaries
}
$manifestPath = Join-Path $OutputFolder 'SelfX.Binaries.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

Write-Output "Built with .NET SDK $sdkVersion in $OutputFolder (not signed):"
foreach ($name in $manifestBinaries.Keys) { Write-Output ('  {0}  {1}' -f $manifestBinaries[$name], $name) }

# AppLocker hash rules for exactly these files (Everyone; exe rules for the two programs, a DLL rule for the library).
if (@(Get-Command -Name Get-AppLockerFileInformation, New-AppLockerPolicy -ErrorAction SilentlyContinue).Count -eq 2) {
    $buildFolder = Join-Path $RepositoryRoot 'build'
    New-Item -ItemType Directory -Path $buildFolder -Force | Out-Null
    $policyPath = Join-Path $buildFolder 'SelfX.AppLocker.xml'
    $paths = @($manifestBinaries.Keys | ForEach-Object { Join-Path $OutputFolder $_.Replace('/', '\') })
    # The rules are a convenience: a problem here must not fail the build (PowerShell 7 reaches the AppLocker
    # cmdlets only through a compatibility layer; use Windows PowerShell 5.1 for the rules in that case).
    try {
        $policy = Get-AppLockerFileInformation -Path $paths |
            New-AppLockerPolicy -RuleType Hash -User Everyone -RuleNamePrefix ("SelfX " + $manifest.ToolVersion) -Xml
        [IO.File]::WriteAllText($policyPath, $policy, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output "AppLocker hash rules: $policyPath (merge into your policy; replace the rules of the previous build)."
    }
    catch {
        Write-Warning "The AppLocker hash rules could not be created: $($_.Exception.Message) Run the script in Windows PowerShell 5.1 (powershell.exe) or create the rules from the files in Bin."
    }
}
else {
    Write-Warning 'AppLocker cmdlets not available: no build\SelfX.AppLocker.xml. Create the hash rules from the files in Bin on a machine with the AppLocker module.'
}
Write-Output 'Package the folder with tools\New-SelfXIntuneWin.ps1; Install.ps1 then installs these files instead of compiling.'
