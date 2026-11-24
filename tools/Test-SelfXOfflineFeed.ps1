<#
.SYNOPSIS
    Tests the offline NuGet feed check (SelfXOfflineFeed.Common.ps1) and the offline settings of the repository.

.DESCRIPTION
    Isolated: works in a temporary folder with invented packages, changes no repository file, needs no .NET SDK and no
    internet. Checks that a correct feed is accepted and that a missing manifest, an unusable manifest, a missing, changed or
    additional package, an unusual file name and a wrong hash are refused. Checks that NuGet.config allows only the
    offline feed, that the audit is switched off for the offline build and that the build script names no internet source.
    When the real folder offline-feed already holds a manifest, it is checked too. Works in Windows PowerShell 5.1 and PowerShell 7.

.NOTES
    Name    : Test-SelfXOfflineFeed.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 1.0.0
    Exit code: 0 = all tests passed, 1 = at least one failed
#>
$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
. (Join-Path $ScriptFolder 'SelfXOfflineFeed.Common.ps1')

$script:Failed = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  PASS $Name" } else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}
function Assert-Throws {
    param([scriptblock]$Code, [string]$Name, [string]$Pattern = '')
    $message = $null
    try { & $Code | Out-Null } catch { $message = $_.Exception.Message }
    Assert (($null -ne $message) -and ($Pattern -eq '' -or $message -match $Pattern)) $Name
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-FeedTest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # A feed with two invented packages and a correct manifest.
    function New-Feed {
        param([string]$Name)
        $folder = Join-Path $work $Name
        New-Item -ItemType Directory -Path $folder | Out-Null
        $packages = [ordered]@{}
        foreach ($file in 'alpha.1.0.0.nupkg', 'beta.runtime.win-x64.10.0.15.nupkg') {
            [IO.File]::WriteAllBytes((Join-Path $folder $file), [Text.Encoding]::UTF8.GetBytes("package $file"))
            $packages[$file] = Get-SelfXNupkgHash -Path (Join-Path $folder $file)
        }
        Save-Manifest -Folder $folder -Packages $packages
        return $folder
    }
    function Save-Manifest {
        param([string]$Folder, $Packages)
        $manifest = [ordered]@{ ManifestVersion = 1; SdkVersion = '10.0.100'; Packages = $Packages }
        [IO.File]::WriteAllText((Join-Path $Folder 'SelfX.OfflineFeed.json'), ($manifest | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    }
    function Read-Packages {
        param([string]$Folder)
        $data = Get-Content -LiteralPath (Join-Path $Folder 'SelfX.OfflineFeed.json') -Raw | ConvertFrom-Json
        $table = [ordered]@{}
        foreach ($property in $data.Packages.PSObject.Properties) { $table[$property.Name] = $property.Value }
        return $table
    }

    Write-Host 'Hash'
    $bytes = [Text.Encoding]::UTF8.GetBytes('SelfX')
    $file = Join-Path $work 'hash.bin'
    [IO.File]::WriteAllBytes($file, $bytes)
    $reference = [Convert]::ToBase64String(([Security.Cryptography.SHA512]::Create()).ComputeHash($bytes))
    Assert ((Get-SelfXNupkgHash -Path $file) -ceq $reference) 'SHA512 of the file as Base64'
    Assert ((Get-SelfXNupkgHash -Path $file) -match '^[A-Za-z0-9+/]{86}==$') 'hash has 88 characters'

    Write-Host 'Correct feed'
    $feed = New-Feed 'ok'
    $manifest = Test-SelfXOfflineFeed -FeedFolder $feed
    Assert ($manifest.ManifestVersion -eq 1) 'a correct feed is accepted and the manifest is returned'
    Set-Content -LiteralPath (Join-Path $feed 'README.md') -Value 'text'
    Assert ($null -ne (Test-SelfXOfflineFeed -FeedFolder $feed)) 'README.md in the folder is allowed'

    Write-Host 'Refused feeds'
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder (Join-Path $work 'nothing') } 'folder missing' 'does not exist'
    $feed = New-Feed 'no-manifest'; Remove-Item -LiteralPath (Join-Path $feed 'SelfX.OfflineFeed.json')
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'manifest missing' 'SelfX.OfflineFeed.json is missing'
    $feed = New-Feed 'bad-json'; [IO.File]::WriteAllText((Join-Path $feed 'SelfX.OfflineFeed.json'), '{ not json')
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'manifest is not JSON' 'not valid JSON'
    $feed = New-Feed 'version'; [IO.File]::WriteAllText((Join-Path $feed 'SelfX.OfflineFeed.json'), '{"ManifestVersion":2,"Packages":{"a.1.nupkg":"x"}}')
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'unknown manifest version' 'unknown format'
    $feed = New-Feed 'empty'; Save-Manifest -Folder $feed -Packages ([ordered]@{ 'x' = 'y' }); [IO.File]::WriteAllText((Join-Path $feed 'SelfX.OfflineFeed.json'), '{"ManifestVersion":1,"Packages":{}}')
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'manifest lists no package' 'lists no package'
    $feed = New-Feed 'missing'; Remove-Item -LiteralPath (Join-Path $feed 'alpha.1.0.0.nupkg')
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'listed package is missing' 'missing in the offline feed'
    $feed = New-Feed 'changed'; [IO.File]::AppendAllText((Join-Path $feed 'alpha.1.0.0.nupkg'), 'x')
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'package changed after export' 'does not match its SHA512'
    $feed = New-Feed 'extra'; [IO.File]::WriteAllText((Join-Path $feed 'gamma.1.0.0.nupkg'), 'x')
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'additional package is refused' 'not listed'
    $feed = New-Feed 'extra-case'; [IO.File]::WriteAllText((Join-Path $feed 'extra.dll'), 'x')
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'additional file of another type is refused' 'not listed'
    $feed = New-Feed 'sub'; New-Item -ItemType Directory -Path (Join-Path $feed 'sub') | Out-Null; [IO.File]::WriteAllText((Join-Path $feed 'sub\alpha.1.0.0.nupkg'), 'x')
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'package in a subfolder is refused' 'not listed'
    $feed = New-Feed 'hash'; $packages = Read-Packages $feed; $packages['alpha.1.0.0.nupkg'] = 'AAAA'; Save-Manifest -Folder $feed -Packages $packages
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'invalid hash text' 'invalid SHA512'
    $feed = New-Feed 'hash-wrong'; $packages = Read-Packages $feed; $packages['alpha.1.0.0.nupkg'] = $packages['beta.runtime.win-x64.10.0.15.nupkg']; Save-Manifest -Folder $feed -Packages $packages
    Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } 'hash of another package' 'does not match its SHA512'
    foreach ($badName in '..\evil.nupkg', '../evil.nupkg', 'C:\evil.nupkg', 'sub\alpha.1.0.0.nupkg', 'evil.dll', '.hidden.nupkg', 'a b.nupkg') {
        $feed = New-Feed ('name-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $packages = Read-Packages $feed; $packages[$badName] = $packages['alpha.1.0.0.nupkg']; Save-Manifest -Folder $feed -Packages $packages
        Assert-Throws { Test-SelfXOfflineFeed -FeedFolder $feed } "unusual file name '$badName' in the manifest" 'unsupported name'
    }

    Write-Host 'Offline settings of the repository'
    $config = New-Object System.Xml.XmlDocument
    $config.XmlResolver = $null
    $config.Load((Join-Path $RepositoryRoot 'NuGet.config'))
    $keys = @($config.SelectNodes('/configuration/packageSources/add') | ForEach-Object { $_.GetAttribute('key') })
    Assert ($config.SelectNodes('/configuration/packageSources/clear').Count -eq 1) 'NuGet.config clears all other sources'
    Assert (($keys.Count -eq 1) -and ($keys[0] -eq 'SelfXOffline')) 'NuGet.config has the one source SelfXOffline'
    $value = $config.SelectSingleNode('/configuration/packageSources/add').GetAttribute('value')
    Assert ($value -eq 'offline-feed') 'the source is the relative folder offline-feed'
    Assert ($config.OuterXml -notmatch 'https?://') 'NuGet.config names no internet address'
    $props = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'SelfX Service\Service\Projects\Directory.Build.props') -Raw
    Assert ($props -match '<NuGetAudit>false</NuGetAudit>') 'NuGetAudit is off for the offline build'
    Assert ($props -match '<DisableTransitiveFrameworkReferenceDownloads>true</DisableTransitiveFrameworkReferenceDownloads>') 'runtime packs of unused frameworks are not requested'
    foreach ($project in Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'SelfX Service\Service\Projects') -Recurse -Filter '*.csproj') {
        $text = Get-Content -LiteralPath $project.FullName -Raw
        Assert ($text -notmatch '<NuGetAudit>\s*true') "$($project.Name): no NuGetAudit=true that overrides the offline setting"
    }
    $build = Get-Content -LiteralPath (Join-Path $ScriptFolder 'Build-SelfXBinaries.ps1') -Raw
    Assert ($build -notmatch 'api\.nuget\.org|https://www\.nuget\.org') 'Build-SelfXBinaries.ps1 names no package source on the internet'
    Assert ($build -match 'Test-SelfXOfflineFeed') 'Build-SelfXBinaries.ps1 checks the feed before the build'
    $gitignore = Get-Content -LiteralPath (Join-Path $RepositoryRoot '.gitignore') -Raw
    Assert ($gitignore -notmatch '(?m)^/?offline-feed') 'the feed is not excluded from Git'

    $realManifest = Join-Path $RepositoryRoot 'offline-feed\SelfX.OfflineFeed.json'
    if (Test-Path -LiteralPath $realManifest) {
        Write-Host 'The feed of the repository'
        Assert ($null -ne (Test-SelfXOfflineFeed -FeedFolder (Join-Path $RepositoryRoot 'offline-feed'))) 'offline-feed matches SelfX.OfflineFeed.json'
        $feedData = Get-Content -LiteralPath $realManifest -Raw | ConvertFrom-Json
        $feedNames = @{}
        foreach ($property in $feedData.Packages.PSObject.Properties) { $feedNames[$property.Name.ToLowerInvariant()] = $true }
        foreach ($lock in Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'SelfX Service\Service\Projects') -Recurse -Filter 'packages.lock.json') {
            $data = Get-Content -LiteralPath $lock.FullName -Raw | ConvertFrom-Json
            foreach ($framework in $data.dependencies.PSObject.Properties) {
                foreach ($package in $framework.Value.PSObject.Properties) {
                    if (-not $package.Value.contentHash) { continue }
                    $name = ('{0}.{1}.nupkg' -f $package.Name, $package.Value.resolved).ToLowerInvariant()
                    Assert $feedNames.ContainsKey($name) "$name of $($lock.Directory.Name)\packages.lock.json is in the feed"
                }
            }
        }
    }
    else { Write-Host '  SKIP the folder offline-feed holds no manifest yet (run tools\Export-SelfXOfflineFeed.ps1 online)' }
}
finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

if ($script:Failed -gt 0) { Write-Host "$script:Failed test(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed.'
exit 0
