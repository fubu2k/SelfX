<#
.SYNOPSIS
    Shared functions for the offline NuGet feed (offline-feed): hash of a package and check of the feed against its manifest.

.DESCRIPTION
    Dot-sourced by Build-SelfXBinaries.ps1, Export-SelfXOfflineFeed.ps1 and Test-SelfXOfflineFeed.ps1. Defines functions only;
    it changes nothing and loads nothing from the internet.

.NOTES
    Name    : SelfXOfflineFeed.Common.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 1.0.0
#>

# SHA512 of a file as Base64 (the format of the file .nupkg.sha512). Not identical to "contentHash" in packages.lock.json: NuGet
# computes that one without the repository signature of nuget.org.
function Get-SelfXNupkgHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA512]::Create()
        try { return [Convert]::ToBase64String($algorithm.ComputeHash($stream)) }
        finally { $algorithm.Dispose() }
    }
    finally { $stream.Dispose() }
}

# Checks the feed folder against SelfX.OfflineFeed.json. Throws with a clear text at the first problem; returns the
# manifest object when everything is in order. Fail securely: a missing manifest, a missing, changed or additional
# package, an unusual file name or a path outside the folder is an error and never a reason to look elsewhere.
function Test-SelfXOfflineFeed {
    param([Parameter(Mandatory = $true)][string]$FeedFolder)
    $hint = 'Run tools\Export-SelfXOfflineFeed.ps1 on a computer with internet access and copy the folder offline-feed to the build machine.'
    if (-not (Test-Path -LiteralPath $FeedFolder -PathType Container)) { throw "The offline feed folder '$FeedFolder' does not exist. $hint" }
    $manifestPath = Join-Path $FeedFolder 'SelfX.OfflineFeed.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "offline-feed\SelfX.OfflineFeed.json is missing. $hint" }
    if ((Get-Item -LiteralPath $manifestPath).Length -gt 1MB) { throw 'offline-feed\SelfX.OfflineFeed.json is unexpectedly large.' }
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "offline-feed\SelfX.OfflineFeed.json is not valid JSON: $($_.Exception.Message)" }
    if (-not $manifest -or "$($manifest.ManifestVersion)" -ne '1' -or -not $manifest.Packages) { throw 'offline-feed\SelfX.OfflineFeed.json has an unknown format.' }

    $feedFull = [IO.Path]::GetFullPath($FeedFolder).TrimEnd('\', '/')
    $listed = @{}
    $entries = @($manifest.Packages.PSObject.Properties)
    if ($entries.Count -eq 0) { throw 'offline-feed\SelfX.OfflineFeed.json lists no package.' }
    foreach ($entry in $entries) {
        $file = "$($entry.Name)"
        $hash = "$($entry.Value)"
        # Only plain file names of NuGet packages: no folder, no drive, no relative part.
        if ($file -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.nupkg$') { throw "offline-feed\SelfX.OfflineFeed.json lists an unsupported name '$file'." }
        if ($hash -notmatch '^[A-Za-z0-9+/]{86}==$') { throw "offline-feed\SelfX.OfflineFeed.json lists an invalid SHA512 for '$file'." }
        $path = [IO.Path]::GetFullPath((Join-Path $FeedFolder $file))
        if ([IO.Path]::GetDirectoryName($path) -ne $feedFull) { throw "'$file' is outside the offline feed folder." }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$file is listed in SelfX.OfflineFeed.json but missing in the offline feed. $hint" }
        if ((Get-SelfXNupkgHash -Path $path) -cne $hash) { throw "$file does not match its SHA512 in SelfX.OfflineFeed.json. $hint" }
        $listed[$file.ToLowerInvariant()] = $true
    }
    foreach ($package in Get-ChildItem -LiteralPath $FeedFolder -Recurse -File -Force) {
        if ($package.Name -eq 'SelfX.OfflineFeed.json' -or $package.Name -eq 'README.md') { continue }
        $relative = $package.FullName.Substring($feedFull.Length + 1)
        if ($relative -ne $package.Name -or -not $listed.ContainsKey($package.Name.ToLowerInvariant())) { throw "$relative is in the offline feed but not listed in SelfX.OfflineFeed.json." }
    }
    return $manifest
}
