<#
.SYNOPSIS
    Builds the programs of SelfX Service once on a build machine and writes a SHA256 manifest and AppLocker hash
    rules (security review finding F9).

.DESCRIPTION
    Without prebuilt programs, Install.ps1 compiles SelfXService.exe and SelfX.exe on every device. Each device then
    has files with a different hash, the files are unsigned, and the compiler runs as SYSTEM on the device.
    This script compiles the same sources with the same compiler once:

      SelfX Service\Bin\SelfXService.exe          service (Service\SelfXService.cs)
      SelfX Service\Bin\SelfX.exe                 starter without console window (Service\SelfXLauncher.cs)
      SelfX Service\Bin\SelfXSessionStarter.dll   used by Install.ps1 only (Service\SelfXSessionStarter.cs)
      SelfX Service\Bin\SelfX.Binaries.json       manifest: SHA256 of the three sources and the three files

    The files are not signed (decision 2026-11-22: allow them by hash, no certificate). When the AppLocker
    cmdlets are available, the script also writes build\SelfX.AppLocker.xml with hash rules for the three files
    (AppLocker uses its own Authenticode SHA256, not the file SHA256 of the manifest). The rules are not part of
    the package; merge them into the AppLocker policy before the package is deployed.
    Install.ps1 uses the Bin folder when it is part of the package and checks it (see docs\Installation.md).
    Run on the build machine in Windows PowerShell 5.1 (the .NET Framework compiler of the devices):
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1

.PARAMETER OutputFolder
    Default: "SelfX Service\Bin" of the repository. The folder is not committed (.gitignore).

.NOTES
    Name    : Build-SelfXBinaries.ps1
    Package : tools
    Context : Build machine (administrator of the package; not installed)
    Version : 2.6.11
    Exit code: 0 = built, an exception otherwise

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.11   2026-11-22  fubu2k               Initial version (security review finding F9).
#>

[CmdletBinding()]
param(
    [string]$OutputFolder
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Core') { throw 'Run in Windows PowerShell 5.1 (powershell.exe): the devices compile with the .NET Framework compiler.' }

$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$PackageFolder = Join-Path $RepositoryRoot 'SelfX Service'
if (-not $OutputFolder) { $OutputFolder = Join-Path $PackageFolder 'Bin' }

$Sources = [ordered]@{
    'Service\SelfXService.cs'        = @{ Output = 'SelfXService.exe';        Type = 'ConsoleApplication'; References = @('System.ServiceProcess', 'System.Xml') }
    'Service\SelfXLauncher.cs'       = @{ Output = 'SelfX.exe';               Type = 'WindowsApplication'; References = @() }
    'Service\SelfXSessionStarter.cs' = @{ Output = 'SelfXSessionStarter.dll'; Type = 'Library';            References = @() }
}

# A fresh output folder, so no file of an older build survives.
if (Test-Path -LiteralPath $OutputFolder) { Remove-Item -LiteralPath $OutputFolder -Recurse -Force }
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

# The compiler writes temporary files to TEMP; use a folder of this build only.
$buildTemp = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-Build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildTemp | Out-Null
$savedTemp = $env:TEMP
$savedTmp = $env:TMP
$manifestSources = [ordered]@{}
$manifestBinaries = [ordered]@{}
try {
    $env:TEMP = $buildTemp
    $env:TMP = $buildTemp
    foreach ($relative in $Sources.Keys) {
        $definition = $Sources[$relative]
        $sourcePath = Join-Path $PackageFolder $relative
        $outputPath = Join-Path $OutputFolder $definition.Output
        $arguments = @{
            TypeDefinition = (Get-Content -LiteralPath $sourcePath -Raw)
            OutputAssembly = $outputPath
            OutputType     = $definition.Type
        }
        if ($definition.References.Count -gt 0) { $arguments.ReferencedAssemblies = $definition.References }
        Add-Type @arguments
        if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "Compiling $relative failed." }
        $manifestSources[$relative.Replace('\', '/')] = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $manifestBinaries[$definition.Output] = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
    }
}
finally {
    $env:TEMP = $savedTemp
    $env:TMP = $savedTmp
    Remove-Item -LiteralPath $buildTemp -Recurse -Force -ErrorAction SilentlyContinue
}

$toolConfig = Join-Path $PackageFolder 'Sources\Tool_Config.xml'
$document = New-Object System.Xml.XmlDocument
$document.XmlResolver = $null
$document.Load($toolConfig)
$manifest = [ordered]@{
    ManifestVersion = 1
    ToolVersion     = $document.SelectSingleNode('/GUI_Config/Tool_Version').InnerText.Trim()
    BuiltUtc        = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Sources         = $manifestSources
    Binaries        = $manifestBinaries
}
$manifestPath = Join-Path $OutputFolder 'SelfX.Binaries.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

Write-Output "Built in $OutputFolder (not signed):"
foreach ($name in $manifestBinaries.Keys) { Write-Output ('  {0}  {1}' -f $manifestBinaries[$name], $name) }

# AppLocker hash rules for exactly these files (Everyone; exe rules for the two programs, a DLL rule for the library).
if (@(Get-Command -Name Get-AppLockerFileInformation, New-AppLockerPolicy -ErrorAction SilentlyContinue).Count -eq 2) {
    $buildFolder = Join-Path $RepositoryRoot 'build'
    New-Item -ItemType Directory -Path $buildFolder -Force | Out-Null
    $policyPath = Join-Path $buildFolder 'SelfX.AppLocker.xml'
    $paths = @($manifestBinaries.Keys | ForEach-Object { Join-Path $OutputFolder $_ })
    $policy = Get-AppLockerFileInformation -Path $paths |
        New-AppLockerPolicy -RuleType Hash -User Everyone -RuleNamePrefix ("SelfX " + $manifest.ToolVersion) -Xml
    [IO.File]::WriteAllText($policyPath, $policy, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output "AppLocker hash rules: $policyPath (merge into your policy; replace the rules of the previous build)."
}
else {
    Write-Warning 'AppLocker cmdlets not available: no build\SelfX.AppLocker.xml. Create the hash rules from the files in Bin on a machine with the AppLocker module.'
}
Write-Output 'Package the folder with tools\New-SelfXIntuneWin.ps1; Install.ps1 then installs these files instead of compiling.'
