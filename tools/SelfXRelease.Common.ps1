<#
.SYNOPSIS
    Shared functions of the release build: release notes from the changelog, the payload archive, the checksum file and their checks.

.DESCRIPTION
    Dot-sourced by tools\New-SelfXIntuneWin.ps1 (payload archive), by .github\workflows\release.yml (notes, checksums, checks) and by
    tools\Test-SelfXRelease.ps1. The file only defines functions; it changes nothing when it is dot-sourced.

    Release files (Get-SelfXReleaseFileNames), all in one folder, named after the version of Version.txt:
      SelfX-Service-<version>.intunewin          the Intune package with the default configuration
      SelfX-Service-<version>.Detection.ps1      its detection script (with the digests)
      SelfX-Service-<version>-payload.zip        programs, code and default configuration of the package plus the package tools
      SelfX-Service-<version>.sbom.cdx.json      bill of materials
      SHA256SUMS.txt                             SHA-256 of all other files

    The payload archive (New-SelfXPayloadArchive) is the package folder exactly as it is packed into the .intunewin (Install.ps1,
    Uninstall.ps1, Detection.ps1, Bin\, App\ with SelfX.Code.json, Config\ with SelfX.Config.json and the default configuration,
    Service\*.cs) plus tools\ (the package assistant and the scripts it calls), LICENSE.md, NOTICE.md and NOTICE.en.md. The set of
    tool files is a fixed list in this file; a new file of the assistant has to be added here, the test fails until it is. The archive
    is reproducible: entries in ordinal order of their names, a fixed time stamp, names with '/'. A link, a name outside the allowed
    characters or two entries with the same name stops the build (fail closed).

    The release notes (New-SelfXReleaseNotes) are the section of the version in CHANGELOG.en.md plus the fixed block "Files and how to
    verify". A changelog without that section is an error (Get-SelfXChangelogSection), so a release without notes cannot be created.

    The checksum file (New-SelfXChecksumFile, Get-SelfXChecksumProblems) has one line "<sha256 in lower case>  <file name>" per file in
    UTF-8 without BOM and LF; lines that start with '#' are comments. The check lists every difference: a changed, a missing or an
    additional file, a line in the wrong format, a name twice.

.NOTES
    Name    : SelfXRelease.Common.ps1
    Package : tools
    Context : Build machine / CI (any user; not installed, not shipped)
    Version : 3.1.2
    Works in Windows PowerShell 5.1 and PowerShell 7.

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version: release notes from CHANGELOG.en.md, payload archive, checksum file
    3.1.1    2026-11-27  fubu2k               tools\Start-SelfXPackageWizard.cmd (window of the package wizard) in the payload archive
    3.1.2    2026-11-28  fubu2k               tools\Intune (detection script of Intune Remediations, sample data collection rule) in the payload archive
#>

# A release version: <major>.<minor>.<patch> (the release workflow checks the tag against Version.txt with the same rule).
$script:SelfXReleaseVersionPattern = '^[0-9]+\.[0-9]+\.[0-9]+\z'
# A file name in the release folder.
$script:SelfXReleaseNamePattern = '^[A-Za-z0-9][A-Za-z0-9._-]*\z'
# A name in the payload archive: plain relative names with '/', never '.' or '..' as a segment (same rule as the lists of the package).
$script:SelfXPayloadNamePattern = '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*\z'
# Fixed time stamp of all entries (the earliest time a zip file can store), so the same contents give the same archive.
$script:SelfXPayloadTime = New-Object System.DateTimeOffset(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
# Longest text of a GitHub release description is 125000 characters.
$script:SelfXReleaseNotesLimit = 120000

# The scripts of the package assistant and the tools it calls (taken from the repository, not from the package folder).
$script:SelfXPayloadToolFiles = @(
    'tools/Get-SelfXAsrEvents.ps1', 'tools/New-SelfXAppLockerRules.ps1', 'tools/New-SelfXIntuneWin.ps1', 'tools/New-SelfXPackage.ps1',
    'tools/New-SelfXWdacPolicy.ps1', 'tools/SelfXPackage.Common.ps1', 'tools/SelfXPublisherRules.ps1', 'tools/SelfXRelease.Common.ps1',
    'tools/SelfXSigning.ps1', 'tools/Start-SelfXPackageWizard.cmd'
)
# Every file below these folders of the repository is part of the payload.
$script:SelfXPayloadToolFolders = @('tools/Wizard', 'tools/Intune')
# Files of the repository root.
$script:SelfXPayloadRootFiles = @('LICENSE.md', 'NOTICE.md', 'NOTICE.en.md')
# Files that must be in the payload besides the tool files and the root files.
$script:SelfXPayloadRequired = @(
    'Install.ps1', 'Uninstall.ps1', 'Detection.ps1', 'Bin/SelfX.Binaries.json', 'Bin/SelfXService.exe', 'Bin/SelfX.exe',
    'App/SelfX.Code.json', 'Config/SelfX.Config.json', 'Config/Tool_Config.xml', 'Config/Issues_List.xml',
    'tools/Wizard/SelfXWizard.ps1', 'tools/Wizard/Wizard.de.xml', 'tools/Wizard/Wizard.en.xml',
    'tools/Intune/Detect-SelfXHealth.ps1', 'tools/Intune/SelfX-Inventory-DCR.json'
)
# The names at the top of the archive: the package folder as it is packed, tools and the files of the root.
$script:SelfXPayloadTopLevel = @(
    'Install.ps1', 'Uninstall.ps1', 'Detection.ps1', 'README.md', 'README.en.md', 'Bin', 'App', 'Config', 'Service', 'tools',
    'LICENSE.md', 'NOTICE.md', 'NOTICE.en.md'
)

function Get-SelfXReleaseFileNames {
    # The five files of a release (all in one folder). Throws for a version that is not <major>.<minor>.<patch>.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Version)
    if ($Version -notmatch $script:SelfXReleaseVersionPattern) { throw "Invalid version '$Version' (expected <major>.<minor>.<patch>)." }
    return [ordered]@{
        Package   = "SelfX-Service-$Version.intunewin"
        Detection = "SelfX-Service-$Version.Detection.ps1"
        Payload   = "SelfX-Service-$Version-payload.zip"
        Sbom      = "SelfX-Service-$Version.sbom.cdx.json"
        Checksums = 'SHA256SUMS.txt'
    }
}

# ------------------------------------------------------------------------------------------------ release notes

function Get-SelfXChangelogSection {
    # The text of the section "## <version> ..." of the changelog (without the heading, without blank lines at the start and the end),
    # up to the next heading of level 2. A heading counts only outside of code fences. Throws when the section is missing, exists twice
    # or is empty (a release without notes is not created). "## Unreleased" is no version.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Version
    )
    if ($Version -notmatch $script:SelfXReleaseVersionPattern) { throw "Invalid version '$Version' (expected <major>.<minor>.<patch>)." }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "The changelog is missing: $Path" }
    $name = Split-Path -Leaf $Path
    $lines = @([IO.File]::ReadAllText($Path) -split '\r?\n')
    $versionHeading = '^##[ \t]+' + [regex]::Escape($Version) + '(?:[ \t].*)?$'
    $headings = New-Object System.Collections.Generic.List[int]
    $matching = New-Object System.Collections.Generic.List[int]
    $fence = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^[ \t]*(```|~~~)') { $fence = -not $fence; continue }
        if ($fence) { continue }
        if ($lines[$i] -match '^##[ \t]') {
            $headings.Add($i)
            if ($lines[$i] -match $versionHeading) { $matching.Add($i) }
        }
    }
    if ($matching.Count -eq 0) { throw "$name has no section '## $Version'. Add the notes of the release (rename '## Unreleased' to the version) before the tag is set." }
    if ($matching.Count -gt 1) { throw "$name has more than one section '## $Version'." }
    $start = $matching[0]
    $end = $lines.Count
    foreach ($index in $headings) { if ($index -gt $start) { $end = $index; break } }
    $body = New-Object System.Collections.Generic.List[string]
    for ($i = $start + 1; $i -lt $end; $i++) { $body.Add($lines[$i].TrimEnd()) }
    while ($body.Count -gt 0 -and $body[0].Trim().Length -eq 0) { $body.RemoveAt(0) }
    while ($body.Count -gt 0 -and $body[$body.Count - 1].Trim().Length -eq 0) { $body.RemoveAt($body.Count - 1) }
    if ($body.Count -eq 0) { throw "The section '## $Version' of $name is empty." }
    return ($body -join "`n")
}

function New-SelfXReleaseNotes {
    # The description of the release: the section of the version from the changelog and the fixed block "Files and how to verify".
    # Attested = $true adds the line for the verification of the build provenance of the payload archive.
    param(
        [Parameter(Mandatory = $true)][string]$ChangelogPath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Version,
        [Parameter(Mandatory = $true)][string]$Repository,
        [bool]$Attested = $true
    )
    if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z') { throw "Invalid repository name '$Repository' (expected <owner>/<name>)." }
    $section = Get-SelfXChangelogSection -Path $ChangelogPath -Version $Version
    $names = Get-SelfXReleaseFileNames -Version $Version
    $block = @'
## Files and how to verify

| File | What it is |
| --- | --- |
| `{PACKAGE}` | Intune Win32 app (`.intunewin`) with the default configuration, for tests. |
| `{DETECTION}` | Detection script for that package. Upload this file to Intune, not the copy in the repository. |
| `{PAYLOAD}` | Programs, code and default configuration of the package plus the package tools (`tools\Wizard` and the scripts of the assistant), to configure and package SelfX for your own company. |
| `{SBOM}` | Software bill of materials (CycloneDX 1.5). |
| `{CHECKSUMS}` | SHA-256 of all other files in this list. |

Check the files before you use them. Download all files into one folder and run this in PowerShell in that folder:

```powershell
Get-Content -LiteralPath .\SHA256SUMS.txt | ForEach-Object {
    if ($_ -match '^([0-9a-f]{64})  (\S+)$') {
        $hash = (Get-FileHash -LiteralPath $Matches[2] -Algorithm SHA256).Hash.ToLowerInvariant()
        '{0}  {1}' -f $(if ($hash -eq $Matches[1]) { 'OK    ' } else { 'FAILED' }), $Matches[2]
    }
}
```

Every line must start with `OK`. A line with `FAILED` or an error means the file was changed or is incomplete: do not use it.
{ATTESTATION}
The release workflow published this release only after all tests of the CI had passed for the tagged commit and the files had been checked against `SHA256SUMS.txt`.
'@
    $attestation = ''
    if ($Attested) {
        $attestation = "`nBuild provenance of the payload archive (needs the GitHub CLI):`n`n``````powershell`ngh attestation verify .\{PAYLOAD} --repo {REPOSITORY}`n```````n"
    }
    $block = $block.Replace('{ATTESTATION}', $attestation)
    $block = $block.Replace('{PACKAGE}', $names.Package).Replace('{DETECTION}', $names.Detection).Replace('{PAYLOAD}', $names.Payload)
    $block = $block.Replace('{SBOM}', $names.Sbom).Replace('{CHECKSUMS}', $names.Checksums).Replace('{REPOSITORY}', $Repository)
    $notes = $section + "`n`n" + ($block -replace '\r?\n', "`n").TrimEnd() + "`n"
    if ($notes.Length -gt $script:SelfXReleaseNotesLimit) { throw "The release notes have $($notes.Length) characters; GitHub allows at most 125000." }
    return $notes
}

# ------------------------------------------------------------------------------------------------ payload archive

function Get-SelfXPayloadEntries {
    # The entries of the payload archive: name (relative, '/') -> path of the file. Package folder (Stage), then the tool files and
    # the files of the root from the repository. Throws for a link, a name outside the allowed characters, a name twice and a missing
    # required file (fail closed). The result is sorted by name (ordinal).
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )
    $map = @{}
    $add = {
        param([string]$Name, [string]$Path)
        if ($Name -notmatch $script:SelfXPayloadNamePattern -or $Name -match '(^|/)\.\.?(/|$)') { throw "The name '$Name' is not allowed in the payload archive." }
        if ($map.ContainsKey($Name.ToLowerInvariant())) { throw "The name '$Name' is in the payload archive twice." }
        $map[$Name.ToLowerInvariant()] = [pscustomobject]@{ Name = $Name; Path = $Path }
    }
    $walk = {
        param([string]$Root, [string]$Prefix)
        $rootFull = (Get-Item -LiteralPath $Root -Force).FullName.TrimEnd('\', '/')
        foreach ($item in @(Get-ChildItem -LiteralPath $rootFull -Recurse -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "A link is not allowed in the payload: $($item.FullName.Substring($rootFull.Length + 1))" }
            if ($item.PSIsContainer) { continue }
            $relative = $item.FullName.Substring($rootFull.Length + 1).Replace('\', '/')
            & $add ($Prefix + $relative) $item.FullName
        }
    }
    if (-not (Test-Path -LiteralPath $Stage -PathType Container)) { throw "The package folder is missing: $Stage" }
    & $walk $Stage ''
    foreach ($entry in @($map.Values)) {
        $top = $entry.Name.Split('/')[0]
        if ($top -notin $script:SelfXPayloadTopLevel) { throw "The package folder has '$top' at the top, which is not part of the payload layout. Add it to SelfXPayloadTopLevel in tools\SelfXRelease.Common.ps1 if it belongs there." }
        if ($top -eq 'tools' -or $entry.Name -in $script:SelfXPayloadRootFiles) { throw "The package folder must not contain '$($entry.Name)' (the payload adds it from the repository)." }
    }
    foreach ($relative in @($script:SelfXPayloadToolFiles) + @($script:SelfXPayloadRootFiles)) {
        $path = [IO.Path]::Combine($RepositoryRoot, $relative.Replace('/', [string][IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "The file '$relative' of the repository is missing." }
        if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "A link is not allowed in the payload: $relative" }
        & $add $relative $path
    }
    foreach ($folder in $script:SelfXPayloadToolFolders) {
        $path = [IO.Path]::Combine($RepositoryRoot, $folder.Replace('/', [string][IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "The folder '$folder' of the repository is missing." }
        & $walk $path ($folder + '/')
    }
    $missing = @($script:SelfXPayloadRequired | Where-Object { -not $map.ContainsKey($_.ToLowerInvariant()) })
    if ($missing.Count -gt 0) { throw "The payload misses required files: $($missing -join ', ')." }
    $names = @($map.Values | ForEach-Object { $_.Name })
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return @($names | ForEach-Object { $map[$_.ToLowerInvariant()] })
}

function New-SelfXPayloadArchive {
    # Writes the payload archive Target (replaces an existing file). The file is written next to Target and renamed at the end, so
    # an error leaves no incomplete archive.
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Target
    )
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $entries = @(Get-SelfXPayloadEntries -Stage $Stage -RepositoryRoot $RepositoryRoot)
    $targetFull = [IO.Path]::GetFullPath($Target)
    $folder = Split-Path -Parent $targetFull
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw "The folder of the payload archive is missing: $folder" }
    $temp = $targetFull + '.tmp'
    try {
        $stream = [IO.File]::Open($temp, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($entry in $entries) {
                $zipEntry = $zip.CreateEntry($entry.Name, [IO.Compression.CompressionLevel]::Optimal)
                $zipEntry.LastWriteTime = $script:SelfXPayloadTime
                $out = $zipEntry.Open()
                try {
                    $in = [IO.File]::OpenRead($entry.Path)
                    try { $in.CopyTo($out) } finally { $in.Dispose() }
                } finally { $out.Dispose() }
            }
        } finally { $zip.Dispose() }
        Move-Item -LiteralPath $temp -Destination $targetFull -Force
    } catch {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw
    }
    return $entries.Count
}

function Get-SelfXPayloadArchiveProblems {
    # Checks a payload archive and returns the list of problems (empty = fine): unreadable file, a name outside the allowed
    # characters, a name twice, a folder entry, a name at the top that is not part of the layout, a missing required file, a file
    # in tools\ that is not on the list of the assistant.
    param([Parameter(Mandatory = $true)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $problems = New-Object System.Collections.Generic.List[string]
    try { $zip = [IO.Compression.ZipFile]::OpenRead($Path) }
    catch { return @("The payload archive cannot be read: $($_.Exception.Message)") }
    try {
        $seen = @{}
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if ($name.EndsWith('/')) { $problems.Add("Folder entry '$name'."); continue }
            if ($name -notmatch $script:SelfXPayloadNamePattern -or $name -match '(^|/)\.\.?(/|$)') { $problems.Add("Name not allowed: '$name'."); continue }
            if ($seen.ContainsKey($name.ToLowerInvariant())) { $problems.Add("Name twice: '$name'."); continue }
            $seen[$name.ToLowerInvariant()] = $true
            $top = $name.Split('/')[0]
            if ($top -notin $script:SelfXPayloadTopLevel) { $problems.Add("Not part of the layout: '$name'."); continue }
            if ($top -eq 'tools' -and $name -notin $script:SelfXPayloadToolFiles) {
                $inFolder = $false
                foreach ($folder in $script:SelfXPayloadToolFolders) { if ($name.StartsWith($folder + '/')) { $inFolder = $true } }
                if (-not $inFolder) { $problems.Add("Not on the list of the assistant: '$name'.") }
            }
        }
        $required = @($script:SelfXPayloadRequired) + @($script:SelfXPayloadToolFiles) + @($script:SelfXPayloadRootFiles)
        foreach ($name in $required) { if (-not $seen.ContainsKey($name.ToLowerInvariant())) { $problems.Add("Missing: '$name'.") } }
    } finally { $zip.Dispose() }
    return $problems.ToArray()
}

# ------------------------------------------------------------------------------------------------ checksum file

function New-SelfXChecksumFile {
    # Writes SHA256SUMS.txt into Folder: one line "<sha256>  <name>" for every file of the folder (sorted by name, ordinal), then the
    # comment lines. Throws for a subfolder, a link, a name outside the allowed characters and an empty folder (fail closed).
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [string[]]$Comment = @()
    )
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw "The folder is missing: $Folder" }
    $root = (Get-Item -LiteralPath $Folder -Force).FullName
    $files = @{}
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "A link is not allowed in the release folder: $($item.Name)" }
        if ($item.PSIsContainer) { throw "A folder is not allowed in the release folder: $($item.Name)" }
        if ($item.Name -eq 'SHA256SUMS.txt') { continue }
        if ($item.Name -notmatch $script:SelfXReleaseNamePattern) { throw "The file name '$($item.Name)' is not allowed in the release folder." }
        $files[$item.Name] = $item.FullName
    }
    if ($files.Count -eq 0) { throw "The release folder has no files: $Folder" }
    $names = @($files.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($name in $names) {
        $lines.Add(('{0}  {1}' -f (Get-FileHash -LiteralPath $files[$name] -Algorithm SHA256).Hash.ToLowerInvariant(), $name))
    }
    foreach ($text in $Comment) {
        if ($text -match '[\x00-\x1F\x7F]') { throw 'A comment of the checksum file must be one line without control characters.' }
        $lines.Add('# ' + $text)
    }
    [IO.File]::WriteAllText((Join-Path $root 'SHA256SUMS.txt'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return $names.Count
}

function Get-SelfXChecksumProblems {
    # Checks the files of Folder against Folder\SHA256SUMS.txt and returns the list of problems (empty = fine): the list is missing,
    # a line has the wrong format, a name is twice in the list or SHA256SUMS.txt lists itself, a listed file is missing or has another
    # hash, a file is not listed, a subfolder or a link exists. With ExpectedFiles the files of the folder (without SHA256SUMS.txt
    # and with it) must be exactly these.
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [string[]]$ExpectedFiles
    )
    $problems = New-Object System.Collections.Generic.List[string]
    $listPath = Join-Path $Folder 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) { return @('SHA256SUMS.txt is missing.') }
    $listed = @{}
    foreach ($line in @([IO.File]::ReadAllText($listPath) -split '\r?\n')) {
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
        if ($line -cmatch '^([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)\z') {
            $hash = $Matches[1]
            $name = $Matches[2]
        } else { $problems.Add("Line in the wrong format: '$line'."); continue }
        if ($name -eq 'SHA256SUMS.txt') { $problems.Add('SHA256SUMS.txt lists itself.'); continue }
        if ($listed.ContainsKey($name)) { $problems.Add("Listed twice: '$name'."); continue }
        $listed[$name] = $hash
    }
    if ($listed.Count -eq 0) { $problems.Add('SHA256SUMS.txt lists no file.') }
    $present = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(Get-ChildItem -LiteralPath $Folder -Force)) {
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $problems.Add("Folder or link in the release folder: '$($item.Name)'."); continue }
        $present.Add($item.Name)
    }
    foreach ($name in $listed.Keys) {
        $path = Join-Path $Folder $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $problems.Add("Listed but missing: '$name'."); continue }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $listed[$name]) { $problems.Add("Hash does not match: '$name'.") }
    }
    foreach ($name in $present) {
        if ($name -ne 'SHA256SUMS.txt' -and -not $listed.ContainsKey($name)) { $problems.Add("Not listed in SHA256SUMS.txt: '$name'.") }
    }
    if ($PSBoundParameters.ContainsKey('ExpectedFiles')) {
        foreach ($name in $ExpectedFiles) { if ($name -notin $present) { $problems.Add("Expected file is missing: '$name'.") } }
        foreach ($name in $present) { if ($name -notin $ExpectedFiles) { $problems.Add("Unexpected file: '$name'.") } }
    }
    return $problems.ToArray()
}
