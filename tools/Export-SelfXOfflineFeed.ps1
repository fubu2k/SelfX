<#
.SYNOPSIS
    Fills the folder offline-feed with all NuGet packages the build needs (run ONLINE, once per SDK or package change).

.DESCRIPTION
    The build of SelfX Service (tools\Build-SelfXBinaries.ps1) works offline: NuGet.config in the repository root allows
    only the folder offline-feed as package source. This script is the only place that talks to nuget.org:

      1. restores all projects in SelfX Service\Service\Projects into an empty temporary package folder (nothing from the
         cache of the user is reused, so every package that is really needed is downloaded and therefore found),
      2. runs the NuGet vulnerability audit during that restore (NuGetAudit is switched off in Directory.Build.props for the
         offline build); a package with a known vulnerability stops the script unless -AllowVulnerabilities is given,
      3. checks that every package named in the packages.lock.json files was downloaded,
      4. copies the .nupkg files into offline-feed and writes offline-feed\SelfX.OfflineFeed.json with the SHA512 of each file,
      5. proves the result: restores all projects again from the new folder only (no internet source, empty package cache, locked
         mode). NuGet then checks the "contentHash" of the lock files itself (it is computed without the repository signature,
         so it is not the SHA512 of the .nupkg file and cannot be compared with the manifest by hand).

    Then check the result (git diff), commit the folder and copy the repository to the build machine. The packages that the
    lock files do not list (runtime pack of the .NET runtime, Windows SDK projection) are fixed only by this manifest: compare
    their hashes with an independent source the first time (see docs\Installation.md, "Offline build").

    Requirement: .NET SDK 10 and internet access to nuget.org (api.nuget.org). Windows PowerShell 5.1 or PowerShell 7:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-SelfXOfflineFeed.ps1

.PARAMETER FeedFolder
    Default: "offline-feed" of the repository. Packages and manifest in it are replaced.

.PARAMETER AllowVulnerabilities
    Continue although NuGet reports a package with a known vulnerability (NU1901 to NU1904). The warnings are still shown.

.NOTES
    Name    : Export-SelfXOfflineFeed.ps1
    Package : tools
    Context : Computer with internet access (administrator of the package; not installed)
    Version : 1.0.1
    Exit code: 0 = exported, an exception otherwise

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-24  fubu2k               Initial version (offline build).
    1.0.1    2026-11-24  fubu2k               No comparison with the lock hash by hand (NuGet computes it without the signature); offline proof restore instead
#>

[CmdletBinding()]
param(
    [string]$FeedFolder,
    [switch]$AllowVulnerabilities
)

$ErrorActionPreference = 'Stop'

$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$ProjectsFolder = Join-Path $RepositoryRoot 'SelfX Service\Service\Projects'
if (-not $FeedFolder) { $FeedFolder = Join-Path $RepositoryRoot 'offline-feed' }
. (Join-Path $ScriptFolder 'SelfXOfflineFeed.Common.ps1')

$dotnet = Get-Command -Name dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) { throw 'The command dotnet was not found. Install the .NET SDK 10 (https://dotnet.microsoft.com/download) and open a new PowerShell window.' }
Push-Location -LiteralPath $RepositoryRoot
try { $sdkVersion = ((& $dotnet.Source --version 2>&1) | Select-Object -First 1).ToString().Trim(); $sdkExit = $LASTEXITCODE }
finally { Pop-Location }
if ($sdkExit -ne 0 -or $sdkVersion -notmatch '^10\.') { throw "The .NET SDK 10 is required, found '$sdkVersion'." }
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'

$projects = @(Get-ChildItem -LiteralPath $ProjectsFolder -Directory | ForEach-Object { Join-Path $_.FullName ($_.Name + '.csproj') } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($projects.Count -eq 0) { throw "No project found in $ProjectsFolder." }

$work = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-Export-' + [guid]::NewGuid().ToString('N'))
$packages = Join-Path $work 'packages'
New-Item -ItemType Directory -Path $packages -Force | Out-Null
try {
    # Only nuget.org, only for this script. --configfile replaces every other NuGet.config (also the one of the repository).
    $onlineConfig = Join-Path $work 'NuGet.online.config'
    $configText = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
  </packageSources>
</configuration>
'@
    [IO.File]::WriteAllText($onlineConfig, $configText, (New-Object System.Text.UTF8Encoding($false)))

    $auditArguments = @('-p:NuGetAudit=true', '-p:NuGetAuditMode=all')
    if (-not $AllowVulnerabilities) { $auditArguments += '-p:WarningsAsErrors=NU1901%3BNU1902%3BNU1903%3BNU1904' }

    Push-Location -LiteralPath $RepositoryRoot
    try {
        foreach ($project in $projects) {
            Write-Output "Restore $(Split-Path -Leaf $project)"
            & $dotnet.Source restore $project --configfile $onlineConfig --packages $packages --nologo -v minimal @auditArguments
            if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed for $(Split-Path -Leaf $project) (exit code $LASTEXITCODE). A vulnerability report (NU1901 to NU1904) can be accepted with -AllowVulnerabilities after you checked it." }
        }
    }
    finally { Pop-Location }

    $downloaded = @(Get-ChildItem -LiteralPath $packages -Recurse -File -Filter '*.nupkg')
    if ($downloaded.Count -eq 0) { throw 'The restore downloaded no package.' }
    $byName = @{}
    foreach ($file in $downloaded) {
        if ($byName.ContainsKey($file.Name.ToLowerInvariant())) { throw "Two packages with the name $($file.Name)." }
        $byName[$file.Name.ToLowerInvariant()] = $file
    }

    # Every package of the lock files must be there (the hash check of the lock files is done by NuGet in the proof below).
    foreach ($lock in Get-ChildItem -LiteralPath $ProjectsFolder -Recurse -File -Filter 'packages.lock.json') {
        $lockData = Get-Content -LiteralPath $lock.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($framework in $lockData.dependencies.PSObject.Properties) {
            foreach ($package in $framework.Value.PSObject.Properties) {
                if (-not $package.Value.contentHash) { continue }
                $name = ('{0}.{1}.nupkg' -f $package.Name, $package.Value.resolved).ToLowerInvariant()
                if (-not $byName.ContainsKey($name)) { throw "$($package.Name) $($package.Value.resolved) of $($lock.Directory.Name)\packages.lock.json was not downloaded." }
            }
        }
    }

    # Replace the content of the feed (packages and manifest); README.md stays.
    New-Item -ItemType Directory -Path $FeedFolder -Force | Out-Null
    Get-ChildItem -LiteralPath $FeedFolder -File -Force | Where-Object { $_.Extension -eq '.nupkg' -or $_.Name -eq 'SelfX.OfflineFeed.json' } | Remove-Item -Force
    $manifestPackages = [ordered]@{}
    $total = 0
    foreach ($name in ($byName.Keys | Sort-Object)) {
        $file = $byName[$name]
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $FeedFolder $file.Name) -Force
        $manifestPackages[$file.Name] = Get-SelfXNupkgHash -Path (Join-Path $FeedFolder $file.Name)
        $total += $file.Length
    }
    $manifest = [ordered]@{ ManifestVersion = 1; SdkVersion = $sdkVersion; Packages = $manifestPackages }
    [IO.File]::WriteAllText((Join-Path $FeedFolder 'SelfX.OfflineFeed.json'), ($manifest | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

    # The result must pass the same check as the build.
    [void](Test-SelfXOfflineFeed -FeedFolder $FeedFolder)

    # Proof: restore every project from the new folder only. The configuration names no internet source, the package cache is empty
    # and the lock files are enforced, so a missing package or a wrong lock hash fails here and not on the build machine.
    $proofConfig = Join-Path $work 'NuGet.proof.config'
    $feedFullPath = [IO.Path]::GetFullPath($FeedFolder)
    $proofText = '<?xml version="1.0" encoding="utf-8"?><configuration><packageSources><clear /><add key="SelfXOffline" value="{0}" /></packageSources></configuration>' -f [Security.SecurityElement]::Escape($feedFullPath)
    [IO.File]::WriteAllText($proofConfig, $proofText, (New-Object System.Text.UTF8Encoding($false)))
    $proofPackages = Join-Path $work 'packages-proof'
    New-Item -ItemType Directory -Path $proofPackages -Force | Out-Null
    Push-Location -LiteralPath $RepositoryRoot
    try {
        foreach ($project in $projects) {
            Write-Output "Proof (offline restore) $(Split-Path -Leaf $project)"
            & $dotnet.Source restore $project --configfile $proofConfig --packages $proofPackages --nologo -v minimal
            if ($LASTEXITCODE -ne 0) { throw "The offline restore of $(Split-Path -Leaf $project) from the new feed failed (exit code $LASTEXITCODE)." }
        }
    }
    finally { Pop-Location }

    Write-Output ('Offline feed written: {0} ({1} packages, {2:N1} MB). SHA512 (Base64):' -f $FeedFolder, $manifestPackages.Count, ($total / 1MB))
    foreach ($name in $manifestPackages.Keys) { Write-Output ('  {0}  {1:N1} MB  {2}' -f $name, ((Get-Item -LiteralPath (Join-Path $FeedFolder $name)).Length / 1MB), $manifestPackages[$name]) }
    Write-Output 'Next: check with git diff, commit the folder offline-feed and copy the repository to the build machine (tools\Build-SelfXBinaries.ps1 works offline).'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    # dotnet leaves obj next to the project files; they are not needed.
    Get-ChildItem -LiteralPath $ProjectsFolder -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($name in 'obj', 'bin') { Remove-Item -LiteralPath (Join-Path $_.FullName $name) -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
