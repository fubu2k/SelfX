<#
.SYNOPSIS
    Tests the release build: release notes from the changelog, payload archive, checksum file and the structure of the release workflow.

.DESCRIPTION
    Isolated: everything is written below the system temp folder and removed again; nothing is installed, downloaded or sent. Checks:
      - static: tools\SelfXRelease.Common.ps1 and this test parse, are plain ASCII and use no syntax of PowerShell 7 only;
      - release notes: the section of a version is taken from CHANGELOG.en.md (heading with or without date, subheadings and code
        fences kept, no other version matched by prefix, CRLF), a missing, a doubled and an empty section, "Unreleased", an invalid
        version and a missing file are errors; the fixed block "Files and how to verify" is there once, names the five files, and the
        verification command in it works (positive and negative);
      - checksum file: format, order, comments, and the check finds a changed, a missing, an additional file, a line in the wrong format,
        a name twice, a list that lists itself, a subfolder, a link and a file set that is not the expected one;
      - payload archive: layout, content, reproducible bytes, every file of the assistant, and negative cases (missing required file,
        a name outside the layout, a forbidden character, a link, a missing folder, an existing archive stays when the run fails,
        manipulated archives: extra entry, folder entry, entry with '..', name twice, missing file, not a zip);
      - every script that the assistant dot-sources is part of the payload;
      - release.yml: only a tag starts it, actions are pinned to a commit, the CI workflow is a prerequisite of the publishing job, the
        token that can write releases appears once and only in the last step, no secret is used, the notes come before the build, the
        draft switch and the attestation switch exist; service-ci.yml can be called and runs this test;
      - docs: both installation guides describe the payload archive, the automatic publishing and the two repository variables.
    Works in Windows PowerShell 5.1 and PowerShell 7.

.NOTES
    Name    : Test-SelfXRelease.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 3.1.1
    Exit code: 0 = all tests passed, 1 = at least one failed

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version
    3.1.1    2026-11-27  fubu2k               A script of the assistant may dot-source a code file of the package (App of the payload: the
                                              window SelfXWizardGui.ps1 loads Branding.ps1); eleven Windows PowerShell 5.1 tests
#>
$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$Common = Join-Path $ScriptFolder 'SelfXRelease.Common.ps1'
$onWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
$separator = [string][IO.Path]::DirectorySeparatorChar
$utf8 = New-Object System.Text.UTF8Encoding($false)

$script:Failed = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  PASS $Name" } else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}
function Test-Throws {
    param([scriptblock]$Script, [string]$Pattern = '.')
    try { & $Script | Out-Null; return $false } catch { return ([string]$_.Exception.Message -match $Pattern) }
}
function Write-TestFile {
    param([string]$Root, [string]$Relative, [string]$Text)
    $path = Join-Path $Root $Relative.Replace('/', $separator)
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $Text, $utf8)
}
function New-TestLink {
    # A junction (Windows) or a symbolic link; $false when the account may not create one.
    param([string]$Path, [string]$Target)
    try {
        if ($onWindows) { New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null } else { New-Item -ItemType SymbolicLink -Path $Path -Target $Target | Out-Null }
        return $true
    } catch { return $false }
}
function New-TestStage {
    # A package folder with the required files of the payload (content is irrelevant).
    param([string]$Root)
    $files = [ordered]@{
        'Install.ps1' = '# install'; 'Uninstall.ps1' = '# uninstall'; 'Detection.ps1' = '# detection'; 'README.md' = 'readme'
        'Bin/SelfX.Binaries.json' = '{}'; 'Bin/SelfXService.exe' = 'MZ1'; 'Bin/SelfX.exe' = 'MZ2'; 'Bin/WinRT/SelfXWinRT.dll' = 'MZ3'
        'App/SelfX.Code.json' = '{}'; 'App/Self_X.ps1' = '# window'; 'Config/SelfX.Config.json' = '{}'; 'Config/Tool_Config.xml' = '<a/>'
        'Config/Issues_List.xml' = '<a/>'; 'Config/Branding/logo.png' = 'png'; 'Service/SelfXService.cs' = '// service'
    }
    foreach ($name in $files.Keys) { Write-TestFile -Root $Root -Relative $name -Text $files[$name] }
}
function New-TestZip {
    # A zip file with the given entry names (content 'x'); the entries are created without checks.
    param([string]$Path, [string[]]$Names)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $zip = New-Object System.IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($name in $Names) {
            $entry = $zip.CreateEntry($name)
            if (-not $name.EndsWith('/')) {
                $out = $entry.Open()
                try { $bytes = [Text.Encoding]::ASCII.GetBytes('x'); $out.Write($bytes, 0, $bytes.Length) } finally { $out.Dispose() }
            }
        }
    } finally { $zip.Dispose() }
}
function Get-ZipNames {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try { return @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
}
function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-ReleaseTest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {

# ---------------------------------------------------------------- static checks
Write-Host 'Static checks'
foreach ($file in @($Common, $MyInvocation.MyCommand.Path)) {
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
    $leaf = Split-Path -Leaf $file
    Assert (@($parseErrors).Count -eq 0) "$leaf parses without errors"
    $text = [IO.File]::ReadAllText($file)
    $ps7 = @($ast.FindAll({ param($node) $node.GetType().Name -in 'TernaryExpressionAst', 'PipelineChainAst', 'NullConditionalMemberAccessAst' }, $true))
    Assert ($ps7.Count -eq 0) "$leaf uses no syntax of PowerShell 7 only"
    Assert ($text -notmatch '[^\x00-\x7F]') "$leaf is plain ASCII"
}
$commonText = [IO.File]::ReadAllText($Common)
Assert ($commonText -notmatch '(?m)\?\?=?|\?\.|ForEach-Object\s+-Parallel|-AsHash' + 'table') 'the release functions use no operator or parameter of PowerShell 7 only'
Assert ($commonText -notmatch '(?i)\b(Invoke-Expression|iex|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Invoke-Command)\b') 'the release functions start no process and download nothing'

. $Common

# ---------------------------------------------------------------- file names
Write-Host 'Release file names'
$names = Get-SelfXReleaseFileNames -Version '3.1.0'
Assert (($names.Values -join '|') -eq 'SelfX-Service-3.1.0.intunewin|SelfX-Service-3.1.0.Detection.ps1|SelfX-Service-3.1.0-payload.zip|SelfX-Service-3.1.0.sbom.cdx.json|SHA256SUMS.txt') 'the five files are named after the version'
foreach ($bad in '', '3.1', 'v3.1.0', '3.1.0-rc1', '3.1.0 ', '3.1.0; x', '..\3.1.0', '3.1.0.0') {
    Assert (Test-Throws { Get-SelfXReleaseFileNames -Version $bad } 'Invalid version') "version '$bad' is refused"
}

# ---------------------------------------------------------------- changelog section
Write-Host 'Section of the changelog'
$changelog = @'
# Changelog

Intro of the file.

## Unreleased (SelfX Service)

- unreleased item

## 3.1.0 - 2026-12-01 (SelfX Service)

Intro line of 3.1.0.

### Added

- Item A
- Item B

```text
## not a heading
```

### Fixed

- Item C

## 3.0.20 - 2026-11-30

- twenty

## 3.0.2 - 2026-11-24 (SelfX Service)

- two

## 3.0.1

- one

## Based on upstream 2.6.9

- base
'@
$changelogPath = Join-Path $work 'CHANGELOG.en.md'
[IO.File]::WriteAllText($changelogPath, $changelog, $utf8)
$section = Get-SelfXChangelogSection -Path $changelogPath -Version '3.1.0'
Assert ($section.StartsWith('Intro line of 3.1.0.') -and $section.EndsWith('- Item C')) 'the section starts after its heading and ends before the next heading of level 2'
Assert ($section -match '### Added' -and $section -match '### Fixed') 'subheadings of level 3 stay in the section'
Assert ($section -match '(?m)^## not a heading$') 'a line inside a code fence is no heading'
Assert ($section -notmatch 'unreleased item|twenty') 'nothing of the neighbouring sections'
Assert ((Get-SelfXChangelogSection -Path $changelogPath -Version '3.0.2') -eq '- two') '3.0.2 is not confused with 3.0.20'
Assert ((Get-SelfXChangelogSection -Path $changelogPath -Version '3.0.20') -eq '- twenty') '3.0.20 is found'
Assert ((Get-SelfXChangelogSection -Path $changelogPath -Version '3.0.1') -eq '- one') 'a heading without a date is found'
Assert ($section -notmatch "`r") 'the section has LF line ends'
$crlfPath = Join-Path $work 'CHANGELOG-crlf.md'
[IO.File]::WriteAllText($crlfPath, ($changelog -replace "`r?`n", "`r`n"), $utf8)
Assert ((Get-SelfXChangelogSection -Path $crlfPath -Version '3.1.0') -eq $section) 'a changelog with CRLF gives the same section'
Assert (Test-Throws { Get-SelfXChangelogSection -Path $changelogPath -Version '9.9.9' } "has no section '## 9.9.9'") 'a version without a section is an error'
Assert (Test-Throws { Get-SelfXChangelogSection -Path $changelogPath -Version '3.0' } 'Invalid version') 'a version with two numbers is refused'
Assert (Test-Throws { Get-SelfXChangelogSection -Path $changelogPath -Version 'Unreleased' } 'Invalid version') 'Unreleased is no version'
$onlyUnreleased = Join-Path $work 'CHANGELOG-unreleased.md'
[IO.File]::WriteAllText($onlyUnreleased, "# Changelog`n`n## Unreleased (SelfX Service)`n`n- item`n", $utf8)
Assert (Test-Throws { Get-SelfXChangelogSection -Path $onlyUnreleased -Version '3.1.0' } "has no section '## 3.1.0'") 'a changelog that only has "Unreleased" gives an error for the version'
$doubled = Join-Path $work 'CHANGELOG-double.md'
[IO.File]::WriteAllText($doubled, "## 3.1.0 - a`n`n- one`n`n## 3.1.0 - b`n`n- two`n", $utf8)
Assert (Test-Throws { Get-SelfXChangelogSection -Path $doubled -Version '3.1.0' } 'more than one section') 'a section that exists twice is an error'
$empty = Join-Path $work 'CHANGELOG-empty.md'
[IO.File]::WriteAllText($empty, "## 3.1.0 - a`n`n`n## 3.0.2`n`n- one`n", $utf8)
Assert (Test-Throws { Get-SelfXChangelogSection -Path $empty -Version '3.1.0' } 'is empty') 'an empty section is an error'
Assert (Test-Throws { Get-SelfXChangelogSection -Path (Join-Path $work 'nothing.md') -Version '3.1.0' } 'changelog is missing') 'a missing changelog is an error'
$real = Join-Path $RepositoryRoot 'CHANGELOG.en.md'
$realSection = Get-SelfXChangelogSection -Path $real -Version '3.0.2'
Assert ($realSection.Length -gt 20 -and $realSection -notmatch '(?m)^## ') 'the real CHANGELOG.en.md gives the section of 3.0.2'

# ---------------------------------------------------------------- release notes
Write-Host 'Release notes'
$notes = New-SelfXReleaseNotes -ChangelogPath $changelogPath -Version '3.1.0' -Repository 'owner/SelfX' -Attested $true
Assert ($notes.StartsWith($section)) 'the notes start with the section of the version'
Assert ([regex]::Matches($notes, '(?m)^## Files and how to verify$').Count -eq 1) 'the block "Files and how to verify" is there once'
foreach ($file in $names.Values) { Assert ($notes.Contains('`' + $file + '`')) "the notes name $file" }
Assert ($notes -match 'gh attestation verify \.\\SelfX-Service-3\.1\.0-payload\.zip --repo owner/SelfX') 'with attestation the notes show the verification of the provenance'
$notesPlain = New-SelfXReleaseNotes -ChangelogPath $changelogPath -Version '3.1.0' -Repository 'owner/SelfX' -Attested $false
Assert ($notesPlain -notmatch 'gh attestation') 'without attestation the notes do not mention it'
Assert ($notes -notmatch "`r" -and $notes.EndsWith("`n") -and -not $notes.EndsWith("`n`n")) 'the notes have LF line ends and one final line end'
Assert ($notes -notmatch '\{[A-Z]+\}') 'no placeholder is left in the notes'
foreach ($badRepo in 'owner', 'owner/name/extra', 'owner/na me', '/name', 'owner/') {
    Assert (Test-Throws { New-SelfXReleaseNotes -ChangelogPath $changelogPath -Version '3.1.0' -Repository $badRepo } 'Invalid repository') "repository '$badRepo' is refused"
}
Assert (Test-Throws { New-SelfXReleaseNotes -ChangelogPath $changelogPath -Version '9.9.9' -Repository 'owner/SelfX' } "has no section") 'no section: no notes'
$huge = Join-Path $work 'CHANGELOG-huge.md'
[IO.File]::WriteAllText($huge, "## 3.1.0`n`n" + (('x' * 99) + "`n") * 1300, $utf8)
Assert (Test-Throws { New-SelfXReleaseNotes -ChangelogPath $huge -Version '3.1.0' -Repository 'owner/SelfX' } 'at most 125000') 'notes that are too long for GitHub are an error'

# The verification command of the notes works against a real release folder.
$verifyFolder = Join-Path $work 'verify'
New-Item -ItemType Directory -Path $verifyFolder | Out-Null
foreach ($file in @($names.Package, $names.Detection, $names.Payload, $names.Sbom)) { Write-TestFile -Root $verifyFolder -Relative $file -Text "content of $file" }
$null = New-SelfXChecksumFile -Folder $verifyFolder -Comment @('Build tool: example')
$snippet = [regex]::Match($notes, '(?s)```powershell\r?\n(.*?)\r?\n```').Groups[1].Value
Assert ($snippet -match 'Get-FileHash' -and $snippet -notmatch 'gh attestation') 'the first code block of the notes is the hash command'
if ($onWindows) {
Push-Location -LiteralPath $verifyFolder
try {
    $result = @(& ([scriptblock]::Create($snippet)) 2>&1 | ForEach-Object { "$_" })
    Assert (@($result | Where-Object { $_ -match '^OK  ' }).Count -eq 4 -and @($result | Where-Object { $_ -match 'FAILED' }).Count -eq 0) 'the command of the notes shows OK for the four files'
    Write-TestFile -Root $verifyFolder -Relative $names.Payload -Text 'changed'
    $result = @(& ([scriptblock]::Create($snippet)) 2>&1 | ForEach-Object { "$_" })
    Assert (@($result | Where-Object { $_ -match '^FAILED ' -and $_ -match 'payload\.zip' }).Count -eq 1 -and @($result | Where-Object { $_ -match '^OK  ' }).Count -eq 3) 'the command of the notes shows FAILED for a changed file'
} finally { Pop-Location }
} else { Write-Host '  SKIP the command of the notes is for Windows PowerShell' }

# ---------------------------------------------------------------- checksum file
Write-Host 'Checksum file'
$sumFolder = Join-Path $work 'sums'
New-Item -ItemType Directory -Path $sumFolder | Out-Null
Write-TestFile -Root $sumFolder -Relative 'b.txt' -Text 'abc'
Write-TestFile -Root $sumFolder -Relative 'a.txt' -Text 'hello'
Write-TestFile -Root $sumFolder -Relative 'C.txt' -Text 'third'
$count = New-SelfXChecksumFile -Folder $sumFolder -Comment @('Build tool: example', 'second comment')
Assert ($count -eq 3) 'the list has one line per file'
$sumBytes = [IO.File]::ReadAllBytes((Join-Path $sumFolder 'SHA256SUMS.txt'))
Assert (-not ($sumBytes.Length -ge 3 -and $sumBytes[0] -eq 0xEF -and $sumBytes[1] -eq 0xBB)) 'UTF-8 without BOM'
$sumText = [IO.File]::ReadAllText((Join-Path $sumFolder 'SHA256SUMS.txt'))
Assert ($sumText -notmatch "`r" -and $sumText.EndsWith("`n")) 'LF line ends and a final line end'
$sumLines = @($sumText.TrimEnd("`n") -split "`n")
Assert ($sumLines[0] -match '^[0-9a-f]{64}  C\.txt$' -and $sumLines[1] -match '^[0-9a-f]{64}  a\.txt$' -and $sumLines[2] -match '^[0-9a-f]{64}  b\.txt$') 'the order is ordinal (C.txt, a.txt, b.txt)'
Assert ($sumText -match '(?m)^ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  b\.txt$') 'the hash is the SHA-256 in lower case with two spaces'
Assert ($sumLines[3] -eq '# Build tool: example' -and $sumLines[4] -eq '# second comment') 'comments come last and start with #'
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder).Count -eq 0) 'a correct folder has no problems'
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder -ExpectedFiles @('a.txt', 'b.txt', 'C.txt', 'SHA256SUMS.txt')).Count -eq 0) 'the expected file set is accepted'
$null = New-SelfXChecksumFile -Folder $sumFolder
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder).Count -eq 0) 'the list can be written again (it does not list itself)'
Write-TestFile -Root $sumFolder -Relative 'a.txt' -Text 'changed'
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder | Where-Object { $_ -match "Hash does not match: 'a.txt'" }).Count -eq 1) 'a changed file is found'
Write-TestFile -Root $sumFolder -Relative 'a.txt' -Text 'hello'
Remove-Item -LiteralPath (Join-Path $sumFolder 'b.txt')
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder | Where-Object { $_ -match "Listed but missing: 'b.txt'" }).Count -eq 1) 'a missing file is found'
Write-TestFile -Root $sumFolder -Relative 'b.txt' -Text 'abc'
Write-TestFile -Root $sumFolder -Relative 'extra.txt' -Text 'x'
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder | Where-Object { $_ -match "Not listed in SHA256SUMS.txt: 'extra.txt'" }).Count -eq 1) 'an additional file is found'
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder -ExpectedFiles @('a.txt', 'b.txt', 'C.txt', 'extra.txt', 'SHA256SUMS.txt') | Where-Object { $_ -match 'Not listed' }).Count -eq 1) 'listing is also checked when the file is expected'
Remove-Item -LiteralPath (Join-Path $sumFolder 'extra.txt')
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder -ExpectedFiles @('a.txt', 'b.txt', 'SHA256SUMS.txt') | Where-Object { $_ -match "Unexpected file: 'C.txt'" }).Count -eq 1) 'a file that is not expected is found'
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder -ExpectedFiles @('a.txt', 'b.txt', 'C.txt', 'd.txt', 'SHA256SUMS.txt') | Where-Object { $_ -match "Expected file is missing: 'd.txt'" }).Count -eq 1) 'an expected file that is missing is found'
$good = [IO.File]::ReadAllText((Join-Path $sumFolder 'SHA256SUMS.txt'))
$hashA = Get-Sha256 (Join-Path $sumFolder 'a.txt')
foreach ($case in @(
    @{ Name = 'upper case hash'; Line = ($hashA.ToUpperInvariant() + '  a.txt') },
    @{ Name = 'one space'; Line = ($hashA + ' a.txt') },
    @{ Name = 'a path with a folder'; Line = ($hashA + '  sub/a.txt') },
    @{ Name = 'a path that leaves the folder'; Line = ($hashA + '  ../a.txt') },
    @{ Name = 'a short hash'; Line = ('abc  a.txt') },
    @{ Name = 'the binary marker of sha256sum'; Line = ($hashA + ' *a.txt') }
)) {
    [IO.File]::WriteAllText((Join-Path $sumFolder 'SHA256SUMS.txt'), $good + $case.Line + "`n", $utf8)
    Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder | Where-Object { $_ -match 'wrong format' }).Count -eq 1) "a line with $($case.Name) is refused"
}
[IO.File]::WriteAllText((Join-Path $sumFolder 'SHA256SUMS.txt'), $good + $hashA + "  a.txt`n", $utf8)
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder | Where-Object { $_ -match "Listed twice: 'a.txt'" }).Count -eq 1) 'a name twice is found'
[IO.File]::WriteAllText((Join-Path $sumFolder 'SHA256SUMS.txt'), $good + (Get-Sha256 (Join-Path $sumFolder 'SHA256SUMS.txt')) + "  SHA256SUMS.txt`n", $utf8)
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder | Where-Object { $_ -match 'lists itself' }).Count -eq 1) 'a list that lists itself is found'
[IO.File]::WriteAllText((Join-Path $sumFolder 'SHA256SUMS.txt'), "# only a comment`n", $utf8)
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder | Where-Object { $_ -match 'lists no file' }).Count -eq 1) 'a list without files is found'
Remove-Item -LiteralPath (Join-Path $sumFolder 'SHA256SUMS.txt')
Assert (@(Get-SelfXChecksumProblems -Folder $sumFolder) -contains 'SHA256SUMS.txt is missing.') 'a missing list is found'
New-Item -ItemType Directory -Path (Join-Path $sumFolder 'sub') | Out-Null
Assert (Test-Throws { New-SelfXChecksumFile -Folder $sumFolder } 'folder is not allowed') 'a subfolder stops the list'
Remove-Item -LiteralPath (Join-Path $sumFolder 'sub')
Write-TestFile -Root $sumFolder -Relative 'with space.txt' -Text 'x'
Assert (Test-Throws { New-SelfXChecksumFile -Folder $sumFolder } 'not allowed in the release folder') 'a file name with a space stops the list'
Remove-Item -LiteralPath (Join-Path $sumFolder 'with space.txt')
Assert (Test-Throws { New-SelfXChecksumFile -Folder $sumFolder -Comment @("two`nlines") } 'one line') 'a comment with a line break is refused'
$emptyFolder = Join-Path $work 'empty'
New-Item -ItemType Directory -Path $emptyFolder | Out-Null
Assert (Test-Throws { New-SelfXChecksumFile -Folder $emptyFolder } 'no files') 'an empty folder stops the list'
Assert (Test-Throws { New-SelfXChecksumFile -Folder (Join-Path $work 'nothing') } 'folder is missing') 'a missing folder stops the list'
$linkTarget = Join-Path $work 'link-target'
New-Item -ItemType Directory -Path $linkTarget | Out-Null
if (New-TestLink -Path (Join-Path $sumFolder 'link') -Target $linkTarget) {
    Assert (Test-Throws { New-SelfXChecksumFile -Folder $sumFolder } 'not allowed in the release folder') 'a link in the release folder stops the list'
    [IO.Directory]::Delete((Join-Path $sumFolder 'link'))
} else { Write-Host '  SKIP links cannot be created here' }

# ---------------------------------------------------------------- payload archive
Write-Host 'Payload archive'
$stage = Join-Path $work 'stage'
New-TestStage -Root $stage
$archive = Join-Path $work 'payload.zip'
$entryCount = New-SelfXPayloadArchive -Stage $stage -RepositoryRoot $RepositoryRoot -Target $archive
$zipNames = Get-ZipNames -Path $archive
Assert ($entryCount -eq $zipNames.Count) 'the function returns the number of entries'
Assert (@(Get-SelfXPayloadArchiveProblems -Path $archive).Count -eq 0) 'the archive passes its own check'
$sorted = @($zipNames); [Array]::Sort($sorted, [StringComparer]::Ordinal)
Assert (($sorted -join '|') -eq ($zipNames -join '|')) 'the entries are in ordinal order'
Assert (@($zipNames | Where-Object { $_.Contains('\') -or $_.StartsWith('/') -or $_.EndsWith('/') -or $_ -match '\.\.' }).Count -eq 0) "the names use '/', are relative and have no folder entries"
foreach ($name in 'Install.ps1', 'Uninstall.ps1', 'Detection.ps1', 'Bin/SelfXService.exe', 'Bin/WinRT/SelfXWinRT.dll', 'App/SelfX.Code.json', 'Config/SelfX.Config.json', 'Config/Branding/logo.png', 'Service/SelfXService.cs', 'LICENSE.md', 'NOTICE.md', 'NOTICE.en.md', 'tools/Wizard/SelfXWizard.ps1', 'tools/Wizard/Wizard.de.xml', 'tools/Wizard/Wizard.en.xml') {
    Assert ($name -in $zipNames) "the archive has $name"
}
$missingTools = @($script:SelfXPayloadToolFiles | Where-Object { $_ -notin $zipNames })
Assert ($missingTools.Count -eq 0) 'the archive has every file of the assistant on the list'
Assert (@($zipNames | Where-Object { $_ -match '(^|/)(Test-|Build-SelfXBinaries|Export-SelfXOfflineFeed|Measure-SelfX|SelfXTestCertificate|New-SelfXSbom)' }).Count -eq 0) 'no test, build-only or measuring script is in the archive'
Assert (@($zipNames | Where-Object { $_ -match '^(Sources|Sources/)|IntuneWinAppUtil' }).Count -eq 0) 'no Sources folder and no packaging tool'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    $badTime = @($zip.Entries | Where-Object { -not ($_.LastWriteTime.Year -eq 1980 -and $_.LastWriteTime.Month -eq 1 -and $_.LastWriteTime.Day -eq 1 -and $_.LastWriteTime.Hour -eq 0) })
    Assert ($badTime.Count -eq 0) 'all entries have the fixed time stamp'
    $same = $true
    foreach ($pair in @(@('Bin/SelfXService.exe', (Join-Path $stage ('Bin' + $separator + 'SelfXService.exe'))), @('LICENSE.md', (Join-Path $RepositoryRoot 'LICENSE.md')), @('tools/Wizard/Wizard.en.xml', (Join-Path $RepositoryRoot ('tools' + $separator + 'Wizard' + $separator + 'Wizard.en.xml'))))) {
        $entry = $zip.GetEntry($pair[0])
        $memory = New-Object System.IO.MemoryStream
        $in = $entry.Open()
        try { $in.CopyTo($memory) } finally { $in.Dispose() }
        $sha = [Security.Cryptography.SHA256]::Create()
        $entryHash = (($sha.ComputeHash($memory.ToArray()) | ForEach-Object { $_.ToString('x2') }) -join '')
        if ($entryHash -ne (Get-Sha256 $pair[1])) { $same = $false }
    }
    Assert $same 'the content of entries from the package folder and from the repository is unchanged'
} finally { $zip.Dispose() }
$archive2 = Join-Path $work 'payload2.zip'
$null = New-SelfXPayloadArchive -Stage $stage -RepositoryRoot $RepositoryRoot -Target $archive2
Assert ((Get-Sha256 $archive) -eq (Get-Sha256 $archive2)) 'the same contents give the same archive (reproducible)'
Assert (-not (Test-Path -LiteralPath ($archive + '.tmp'))) 'no temporary file is left'

# Negative cases of the build
$stageMissing = Join-Path $work 'stage-missing'
New-TestStage -Root $stageMissing
Remove-Item -LiteralPath (Join-Path $stageMissing 'Install.ps1')
Assert (Test-Throws { New-SelfXPayloadArchive -Stage $stageMissing -RepositoryRoot $RepositoryRoot -Target (Join-Path $work 'x1.zip') } 'misses required files: Install.ps1') 'a missing required file stops the build'
$stageTools = Join-Path $work 'stage-tools'
New-TestStage -Root $stageTools
Write-TestFile -Root $stageTools -Relative 'tools/New-SelfXPackage.ps1' -Text '# own copy'
Assert (Test-Throws { New-SelfXPayloadArchive -Stage $stageTools -RepositoryRoot $RepositoryRoot -Target (Join-Path $work 'x2.zip') } "must not contain|not part of the payload layout") 'a package folder with its own tools folder stops the build'
$stageSources = Join-Path $work 'stage-sources'
New-TestStage -Root $stageSources
Write-TestFile -Root $stageSources -Relative 'Sources/Self_X.ps1' -Text '# not sorted'
Assert (Test-Throws { New-SelfXPayloadArchive -Stage $stageSources -RepositoryRoot $RepositoryRoot -Target (Join-Path $work 'x3.zip') } "'Sources' at the top") 'a name at the top that is not part of the layout stops the build'
$stageLicense = Join-Path $work 'stage-license'
New-TestStage -Root $stageLicense
Write-TestFile -Root $stageLicense -Relative 'LICENSE.md' -Text 'own license'
Assert (Test-Throws { New-SelfXPayloadArchive -Stage $stageLicense -RepositoryRoot $RepositoryRoot -Target (Join-Path $work 'x4.zip') } 'must not contain') 'a license file in the package folder stops the build (no second copy)'
foreach ($badName in 'App/a+b.txt', 'App/a;b.txt', 'App/a$b.txt', 'App/-x/.hidden y/ a.txt') {
    $stageBad = Join-Path $work ('stage-bad-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-TestStage -Root $stageBad
    $created = $true
    try { Write-TestFile -Root $stageBad -Relative $badName -Text 'x' } catch { $created = $false }
    if ($created) { Assert (Test-Throws { New-SelfXPayloadArchive -Stage $stageBad -RepositoryRoot $RepositoryRoot -Target (Join-Path $work 'x5.zip') } 'is not allowed in the payload archive') "the name '$badName' stops the build" }
}
$stageUnicode = Join-Path $work 'stage-unicode'
New-TestStage -Root $stageUnicode
Write-TestFile -Root $stageUnicode -Relative ('App/caf' + [char]0x00E9 + '.txt') -Text 'x'
Assert (Test-Throws { New-SelfXPayloadArchive -Stage $stageUnicode -RepositoryRoot $RepositoryRoot -Target (Join-Path $work 'x6.zip') } 'is not allowed in the payload archive') 'a name with a character outside ASCII stops the build'
$stageLink = Join-Path $work 'stage-link'
New-TestStage -Root $stageLink
if (New-TestLink -Path (Join-Path $stageLink 'App/linked') -Target $linkTarget) {
    Assert (Test-Throws { New-SelfXPayloadArchive -Stage $stageLink -RepositoryRoot $RepositoryRoot -Target (Join-Path $work 'x7.zip') } 'link is not allowed') 'a link in the package folder stops the build'
    [IO.Directory]::Delete((Join-Path $stageLink 'App/linked'))
} else { Write-Host '  SKIP links cannot be created here' }
Assert (Test-Throws { New-SelfXPayloadArchive -Stage (Join-Path $work 'no-stage') -RepositoryRoot $RepositoryRoot -Target (Join-Path $work 'x8.zip') } 'package folder is missing') 'a missing package folder stops the build'
Assert (Test-Throws { New-SelfXPayloadArchive -Stage $stage -RepositoryRoot $RepositoryRoot -Target (Join-Path $work 'no-folder/x9.zip') } 'folder of the payload archive is missing') 'a missing target folder stops the build'
$emptyRoot = Join-Path $work 'empty-root'
New-Item -ItemType Directory -Path $emptyRoot | Out-Null
Assert (Test-Throws { New-SelfXPayloadArchive -Stage $stage -RepositoryRoot $emptyRoot -Target (Join-Path $work 'x10.zip') } 'of the repository is missing') 'a repository without the tool files stops the build'
$existing = Join-Path $work 'existing.zip'
[IO.File]::WriteAllText($existing, 'OLD', $utf8)
try { New-SelfXPayloadArchive -Stage $stageMissing -RepositoryRoot $RepositoryRoot -Target $existing | Out-Null } catch { }
Assert ([IO.File]::ReadAllText($existing) -eq 'OLD' -and -not (Test-Path -LiteralPath ($existing + '.tmp'))) 'a failed run leaves an existing archive unchanged and no temporary file'
$null = New-SelfXPayloadArchive -Stage $stage -RepositoryRoot $RepositoryRoot -Target $existing
Assert ((Get-Sha256 $existing) -eq (Get-Sha256 $archive)) 'a successful run replaces an existing archive'

# Manipulated archives
Write-Host 'Checks of an archive'
$goodNames = @($zipNames)
$mutations = @(
    @{ Name = 'an entry outside the layout'; Names = $goodNames + 'evil/x.txt'; Pattern = "Not part of the layout: 'evil/x.txt'" },
    @{ Name = 'an extra file in tools'; Names = $goodNames + 'tools/Extra.ps1'; Pattern = "Not on the list of the assistant: 'tools/Extra.ps1'" },
    @{ Name = 'a folder entry'; Names = $goodNames + 'App/'; Pattern = 'Folder entry' },
    @{ Name = 'an entry with ..'; Names = $goodNames + 'App/../x.txt'; Pattern = 'Name not allowed' },
    @{ Name = 'an entry with a backslash'; Names = $goodNames + 'App\x.txt'; Pattern = 'Name not allowed' },
    @{ Name = 'an absolute name'; Names = $goodNames + '/App/x.txt'; Pattern = 'Name not allowed' },
    @{ Name = 'a name twice (other case)'; Names = $goodNames + 'app/SELFX.CODE.JSON'; Pattern = 'Name twice' },
    @{ Name = 'a missing required file'; Names = @($goodNames | Where-Object { $_ -ne 'Install.ps1' }); Pattern = "Missing: 'Install.ps1'" },
    @{ Name = 'a missing file of the assistant'; Names = @($goodNames | Where-Object { $_ -ne 'tools/New-SelfXPackage.ps1' }); Pattern = "Missing: 'tools/New-SelfXPackage.ps1'" },
    @{ Name = 'a missing notice'; Names = @($goodNames | Where-Object { $_ -ne 'NOTICE.en.md' }); Pattern = "Missing: 'NOTICE.en.md'" }
)
foreach ($mutation in $mutations) {
    $path = Join-Path $work ('mut-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.zip')
    New-TestZip -Path $path -Names $mutation.Names
    Assert (@(Get-SelfXPayloadArchiveProblems -Path $path | Where-Object { $_ -match [regex]::Escape($mutation.Pattern) -or $_ -match $mutation.Pattern }).Count -ge 1) "the check finds $($mutation.Name)"
}
$notZip = Join-Path $work 'not-a.zip'
[IO.File]::WriteAllText($notZip, 'this is not a zip file', $utf8)
Assert (@(Get-SelfXPayloadArchiveProblems -Path $notZip | Where-Object { $_ -match 'cannot be read' }).Count -eq 1) 'a file that is not a zip is reported'
Assert (@(Get-SelfXPayloadArchiveProblems -Path (Join-Path $work 'nothing.zip') | Where-Object { $_ -match 'cannot be read' }).Count -eq 1) 'a missing archive is reported'

# Every script that the assistant dot-sources is in the payload.
Write-Host 'Scripts of the assistant'
$payloadScripts = New-Object System.Collections.Generic.List[string]
foreach ($relative in $script:SelfXPayloadToolFiles) { if ($relative.EndsWith('.ps1')) { $payloadScripts.Add($relative) } }
foreach ($folder in $script:SelfXPayloadToolFolders) {
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot $folder.Replace('/', $separator)) -Recurse -File -Filter '*.ps1')) { $payloadScripts.Add($folder + '/' + $file.Name) }
}
$inPayload = @($script:SelfXPayloadToolFiles) + @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'tools/Wizard') -Recurse -File | ForEach-Object { 'tools/Wizard/' + $_.Name })
$unresolved = New-Object System.Collections.Generic.List[string]
. (Join-Path $ScriptFolder 'SelfXPackage.Common.ps1')
$packageCodeFiles = @($script:SelfXCodeFileNames)
foreach ($relative in $payloadScripts) {
    $text = [IO.File]::ReadAllText((Join-Path $RepositoryRoot $relative.Replace('/', $separator)))
    foreach ($match in [regex]::Matches($text, "(?m)^\s*\.\s+\(Join-Path\s+.*'([A-Za-z0-9._-]+\.ps1)'\)\s*$")) {
        $needed = $match.Groups[1].Value
        # A code file of the package (App of the payload, for example Branding.ps1 for the window of the assistant) is part of the payload too.
        if (('tools/' + $needed) -notin $inPayload -and ('tools/Wizard/' + $needed) -notin $inPayload -and $needed -notin $packageCodeFiles) { $unresolved.Add("$relative -> $needed") }
    }
}
Assert ($unresolved.Count -eq 0) ('every script that the assistant dot-sources is part of the payload' + $(if ($unresolved.Count) { ': ' + ($unresolved -join ', ') }))
Assert (@($script:SelfXPayloadToolFiles | Where-Object { $_ -match 'Test-' }).Count -eq 0) 'no test script is on the list of the assistant'

# ---------------------------------------------------------------- packaging script
Write-Host 'tools\New-SelfXIntuneWin.ps1'
$packText = [IO.File]::ReadAllText((Join-Path $ScriptFolder 'New-SelfXIntuneWin.ps1'))
$packAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $ScriptFolder 'New-SelfXIntuneWin.ps1'), [ref]$null, [ref]$null)
$packParams = @($packAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
Assert ($packParams -contains 'PayloadFile') 'the packaging script has the parameter -PayloadFile'
Assert ($packText -match "if \(\`$name -eq 'Service' -and \`$PayloadFile\)\s*\{[^}]*New-SelfXPayloadArchive -Stage \`$stage") 'the archive is written from the staged package folder and only when -PayloadFile is given'
Assert ($packText.IndexOf('$payloadEntries = New-SelfXPayloadArchive') -gt 0 -and $packText.IndexOf('$payloadEntries = New-SelfXPayloadArchive') -lt $packText.IndexOf('$created = New-PackageFile -Stage')) 'the archive is written before the package is packed'

# ---------------------------------------------------------------- workflows
Write-Host '.github\workflows\release.yml'
$release = [IO.File]::ReadAllText((Join-Path $RepositoryRoot '.github/workflows/release.yml'))
Assert ($release -match "(?m)^on:\s*\r?\n  push:\s*\r?\n    tags:\s*\r?\n      - 'v\[0-9\]\+\.\[0-9\]\+\.\[0-9\]\+'\s*\r?\n") 'only a version tag starts the workflow'
Assert ($release -notmatch '(?m)^\s*(workflow_dispatch|pull_request|pull_request_target|schedule|workflow_run|workflow_call|branches|issue_comment):') 'no other trigger'
$uses = @([regex]::Matches($release, '(?m)^\s*(?:-\s+)?uses:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
Assert ($uses.Count -ge 6) "the workflow uses actions ($($uses.Count) uses lines)"
$unpinned = @($uses | Where-Object { $_ -ne './.github/workflows/service-ci.yml' -and $_ -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$' })
Assert ($unpinned.Count -eq 0) ('every action is pinned to a full commit SHA' + $(if ($unpinned.Count) { ': ' + ($unpinned -join ', ') }))
Assert (@([regex]::Matches($release, '(?m)^\s*(?:-\s+)?uses:\s*[^\s@]+@[0-9a-f]{40}\s+# v[0-9]+\.[0-9]+\.[0-9]+\s*$')).Count -eq ($uses.Count - 1)) 'every pinned action names its version in a comment'
Assert ($release -notmatch 'secrets\.') 'no secret is used'
$ciUse = $release.IndexOf('uses: ./.github/workflows/service-ci.yml')
Assert ($ciUse -gt $release.IndexOf('  ci:') -and $ciUse -lt $release.IndexOf('  build:')) 'the job ci calls the CI workflow of the same commit'
Assert ($release -match 'needs: \[ci, build, attest\]') 'the publishing job needs ci, build and attest'
Assert ($release -match "needs\.ci\.result == 'success'" -and $release -match "needs\.build\.result == 'success'" -and $release -match "needs\.attest\.result == 'skipped'") 'the publishing job runs only when ci and build passed (attest passed or was switched off)'
Assert ([regex]::Matches($release, 'GH_TOKEN:').Count -eq 1 -and [regex]::Matches($release, 'github\.token').Count -eq 1) 'the token appears once'
$lastStep = [regex]::Matches($release, '(?m)^      - (name|uses):') | Select-Object -Last 1
Assert ($release.IndexOf('GH_TOKEN:') -gt $lastStep.Index -and $release.IndexOf('GH_TOKEN:') -gt $release.IndexOf('  publish:')) 'the token is in the last step of the last job'
Assert ([regex]::Matches($release, 'contents: write').Count -eq 1 -and $release.IndexOf('contents: write') -gt $release.IndexOf('  publish:')) 'only the publishing job can write contents'
Assert ([regex]::Matches($release, 'id-token: write').Count -eq 1 -and [regex]::Matches($release, 'attestations: write').Count -eq 1 -and $release.IndexOf('id-token: write') -gt $release.IndexOf('  attest:') -and $release.IndexOf('id-token: write') -lt $release.IndexOf('  publish:')) 'only the attestation job gets the rights for the attestation'
Assert ($release -match '(?m)^permissions:\s*\r?\n  contents: read\s*\r?\n') 'the default of the token is read-only'
Assert ($release -match "RELEASE_DRAFT: \`$\{\{ vars\.RELEASE_DRAFT \}\}" -and $release -match '--draft=false' -and $release -match 'gh release create "\$tag" release/\* --draft --verify-tag') 'RELEASE_DRAFT switches between draft and published release; the release is created as a draft first'
Assert ($release -match "vars\.RELEASE_ATTEST != 'false'" -and $release -match 'subject-path: release/SelfX-Service-\*-payload\.zip') 'RELEASE_ATTEST=false turns the attestation of the payload archive off'
Assert ($release.IndexOf('Release notes from CHANGELOG.en.md') -lt $release.IndexOf('Build the programs')) 'the release notes are made (and a missing section stops the run) before anything is built'
Assert ($release -match 'New-SelfXReleaseNotes' -and $release -match 'Get-SelfXChecksumProblems' -and $release -match 'Get-SelfXPayloadArchiveProblems' -and $release -match '-PayloadFile') 'the workflow uses the tested functions'
Assert ($release -match 'sha256sum --check --strict' -and $release -match 'gh release view "\$tag"') 'the files are checked against SHA256SUMS.txt before the upload and an existing release is never touched'
Assert ($release -match 'SelfX Service/Version\.txt') 'the tag is compared with Version.txt'
Assert ($release.IndexOf('trap cleanup EXIT') -gt $release.IndexOf('gh release view "$tag"')) 'the draft is removed on failure only after the check for an existing release'

Write-Host '.github\workflows\service-ci.yml'
$ci = [IO.File]::ReadAllText((Join-Path $RepositoryRoot '.github/workflows/service-ci.yml'))
Assert ($ci -match '(?m)^  workflow_call:\s*$') 'the CI workflow can be called by the release workflow'
Assert ([regex]::Matches($ci, 'Test-SelfXRelease\.ps1').Count -eq 2) 'this test runs in Windows PowerShell 5.1 and in PowerShell 7'
Assert ($ci -match "Count -ne 11") 'the count of the Windows PowerShell 5.1 tests is 11'

# ---------------------------------------------------------------- docs
Write-Host 'Docs'
foreach ($doc in @(@('docs/Installation.md', 'English'), @('docs/de/Installation.md', 'German'))) {
    $text = [IO.File]::ReadAllText((Join-Path $RepositoryRoot $doc[0].Replace('/', $separator)))
    Assert ($text -match 'payload\.zip' -and $text -match 'RELEASE_DRAFT' -and $text -match 'RELEASE_ATTEST' -and $text -match 'CHANGELOG\.en\.md' -and $text -match 'SHA256SUMS\.txt') "$($doc[0]) ($($doc[1])) describes the payload archive, the automatic publishing, both repository variables and the notes"
}
foreach ($log in @('CHANGELOG.en.md', 'CHANGELOG.md')) {
    $text = [IO.File]::ReadAllText((Join-Path $RepositoryRoot $log))
    Assert ($text -match 'SelfXRelease\.Common\.ps1' -and $text -match 'payload\.zip') "$log lists the release build"
}

} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed -gt 0) { Write-Host "FAILED: $script:Failed test(s)." -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed.'
exit 0
