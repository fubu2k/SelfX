<#
.SYNOPSIS
    Shared functions of the SelfX package tools: file classes, the two file lists and the digest of a list.

.DESCRIPTION
    Dot-sourced by tools\New-SelfXIntuneWin.ps1 and by the tests. The file only defines functions; it changes nothing
    when it is dot-sourced.

    Every file that Install.ps1 installs belongs to exactly one class (docs\Architecture.md):
      Code    The programs, the libraries and the scripts, language files and images of the project. They are the same for
              every company and are listed in SelfX.Code.json.
      Config  The settings files (Tool_Config.xml, Issues_List.xml, Health_Config.xml, Ticket_Config.xml,
              Network_Test_Config.xml), everything below Branding, and own scripts and language files of the company in
              Scripts_to_run, HealthChecks and Languages. They are listed in SelfX.Config.json.
    Get-SelfXFileClass is the one place of this rule. A file that no rule knows is an error (fail closed). Install.ps1 and
    SelfXService.cs cannot load this file (it is not part of the package); they apply the placement rule
    Test-SelfXListPlacement in their own copy, and the tests check that all copies give the same answers.

    SelfX.Code.json and SelfX.Config.json have the format of the former SelfX.Files.json: ManifestVersion 1 and Files (relative
    name with '/' -> SHA256). SelfX.Code.json also has ToolVersion; it has no build time, so the same package contents always
    give the same bytes. SelfX.Config.json also has ConfigRevision (UTC time of the packaging run).

    The version is a property of the code: it comes from the file 'SelfX Service\Version.txt' of the repository (one line, read by
    Get-SelfXVersionFromFile) and is written only into SelfX.Code.json. Tool_Config.xml does not carry it any more, so a change of
    the version changes no configuration file and a change of the configuration does not change the version.

.NOTES
    Name    : SelfXPackage.Common.ps1
    Package : tools
    Context : Build machine (administrator of the package; not installed, not shipped)
    Version : 1.1.0
    Works in Windows PowerShell 5.1 and PowerShell 7.

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-27  fubu2k               Initial version: file classes, SelfX.Code.json, SelfX.Config.json, digest and Detection.ps1 writer
    1.1.0    2026-11-27  fubu2k               The version comes from Version.txt (Get-SelfXVersionFromFile) and is written only into SelfX.Code.json;
                                              SelfX.Config.json has ConfigRevision (UTC time of the run) instead of BuiltUtc
#>

# Names (relative to the installation folder, '/' as separator) of the settings files.
$script:SelfXConfigFileNames = @('Health_Config.xml', 'Issues_List.xml', 'Network_Test_Config.xml', 'Ticket_Config.xml', 'Tool_Config.xml')

# Names of all files of the project that are installed and are code (the programs come from Bin, the rest from Sources).
# WinRT/<name>.dll is code too (the set of DLLs is the output of the build) and is matched by a pattern below.
# A new file of the project has to be added here; the tests fail until it is.
$script:SelfXCodeFileNames = @(
    'Audio/SelfXAudio.dll', 'Branding.ps1', 'CopilotClipboard.ps1', 'CopilotFacts.ps1', 'CopilotPrompt.ps1',
    'HealthChecks/Check-Compliance.ps1', 'HealthStatus.ps1', 'Languages/ar.xml', 'Languages/bn.xml',
    'Languages/de.xml', 'Languages/en.xml', 'Languages/es.xml', 'Languages/fa.xml', 'Languages/fr.xml',
    'Languages/hi.xml', 'Languages/id.xml', 'Languages/it.xml', 'Languages/ja.xml', 'Languages/ko.xml',
    'Languages/nl.xml', 'Languages/pl.xml', 'Languages/pt.xml', 'Languages/ru.xml', 'Languages/sw.xml',
    'Languages/th.xml', 'Languages/tr.xml', 'Languages/uk.xml', 'Languages/ur.xml', 'Languages/vi.xml',
    'Languages/zh-Hans.xml', 'Languages/zh-Hant.xml', 'Localization.ps1', 'Repair.ico',
    'Scripts_to_run/Collect-DeviceLogs.ps1', 'Scripts_to_run/SelfX_Apps_RetryInstall.ps1',
    'Scripts_to_run/SelfX_Audio_Restore.ps1', 'Scripts_to_run/SelfX_Browser_ClearChromeCache.ps1',
    'Scripts_to_run/SelfX_Browser_ClearEdgeCache.ps1', 'Scripts_to_run/SelfX_Browser_ClearFirefoxCache.ps1',
    'Scripts_to_run/SelfX_Citrix_RestartWorkspace.ps1', 'Scripts_to_run/SelfX_Defender_QuickScan.ps1',
    'Scripts_to_run/SelfX_Defender_UpdateSignature.ps1', 'Scripts_to_run/SelfX_Device_AirePlaneMode.ps1',
    'Scripts_to_run/SelfX_Device_BringWindowsBack.ps1', 'Scripts_to_run/SelfX_Device_ClearCache.ps1',
    'Scripts_to_run/SelfX_Device_CollectLogs.ps1', 'Scripts_to_run/SelfX_Device_DeviceSlow.ps1',
    'Scripts_to_run/SelfX_Device_GpUpdate.ps1', 'Scripts_to_run/SelfX_Device_Restart.ps1',
    'Scripts_to_run/SelfX_Device_SyncTime.ps1', 'Scripts_to_run/SelfX_Excel_NewInstance.ps1',
    'Scripts_to_run/SelfX_Excel_Reboot.ps1', 'Scripts_to_run/SelfX_Intune_RestartService.ps1',
    'Scripts_to_run/SelfX_Office_ResetLicence.ps1', 'Scripts_to_run/SelfX_OneDrive_CHKDSK.ps1',
    'Scripts_to_run/SelfX_OneDrive_Reboot.ps1', 'Scripts_to_run/SelfX_OneDrive_Reset.ps1',
    'Scripts_to_run/SelfX_OneDrive_Run.ps1', 'Scripts_to_run/SelfX_Outlook_CleanAutoComplete.ps1',
    'Scripts_to_run/SelfX_Outlook_Reboot.ps1', 'Scripts_to_run/SelfX_Outlook_TeamsAddIn.ps1',
    'Scripts_to_run/SelfX_Poste_WSReset.ps1', 'Scripts_to_run/SelfX_Teams_Reboot.ps1',
    'Scripts_to_run/SelfX_Teams_ResetCache.ps1', 'Scripts_to_run/SelfX_Updates_Install.ps1',
    'Scripts_to_run/SelfX_Word_Reboot.ps1', 'SelfX.exe', 'SelfXAudio.ps1', 'SelfXDefender.ps1',
    'SelfXDeviceSecurity.ps1', 'SelfXLog.ps1', 'SelfXNetwork.ps1', 'SelfXOffice.ps1', 'SelfXService.exe',
    'SelfXServiceClient.ps1', 'SelfXWinRT.ps1', 'SelfXWindows.ps1', 'SelfX_Tray.ps1', 'Self_X.ps1',
    'SupportLinks.ps1', 'SupportReport.ps1', 'SystemInfo.ps1', 'TicketMail.ps1', 'TicketSend.ps1', 'Uninstall.ps1',
    'icon_systray.ico', 'logo.png'
)

# One file name of a list: plain relative names, never '.' or '..' as a segment.
$script:SelfXListedNamePattern = '^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*$'

function Test-SelfXListedName {
    param([string]$Name)
    return ($Name -match $script:SelfXListedNamePattern -and $Name -notmatch '(^|/)\.\.?(/|$)')
}

# A version: letters, digits, '.' and '-', at most 30 characters. It becomes part of file names, a registry value and log lines.
# Install.ps1, Detection.ps1 and Self_X.ps1 have a copy of the same pattern (Test-FileManifest.ps1 checks that they agree).
$script:SelfXVersionPattern = '^[0-9A-Za-z.\-]{1,30}\z'

function Test-SelfXVersionText {
    param([string]$Text)
    return ($Text -match $script:SelfXVersionPattern)
}

function Get-SelfXVersionFromFile {
    # Reads the version of the code from Version.txt (the only source): exactly one non-empty line. A missing file, an empty
    # file, more than one line and a version with other characters than Test-SelfXVersionText allows are errors (fail closed).
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "The version file is missing: $Path" }
    $lines = @(([IO.File]::ReadAllText($Path) -split '\r?\n') | Where-Object { $_.Trim().Length -gt 0 })
    if ($lines.Count -ne 1) { throw "The version file '$(Split-Path -Leaf $Path)' must contain exactly one line with the version." }
    $version = $lines[0].Trim()
    if (-not (Test-SelfXVersionText $version)) { throw "Invalid version '$version' in '$(Split-Path -Leaf $Path)'." }
    return $version
}

function Test-SelfXConfigName {
    # True for a name that may be in SelfX.Config.json: a settings file, a file below Branding, an own script in
    # Scripts_to_run or HealthChecks, an own language file in Languages.
    param([string]$Name)
    if ($script:SelfXConfigFileNames -contains $Name) { return $true }
    if ($Name -match '^Branding/.+') { return $true }
    if ($Name -match '^(Scripts_to_run|HealthChecks)/[A-Za-z0-9._-]+\.ps1$') { return $true }
    if ($Name -match '^Languages/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml$') { return $true }
    return $false
}

function Test-SelfXListPlacement {
    # The placement rule of Install.ps1 and the service: may this name be in this list? Code may be anything that is not a
    # settings file or below Branding; Config only what Test-SelfXConfigName accepts (so no program, library, Uninstall.ps1,
    # root script or image can be put into the list of the company).
    param([string]$Name, [ValidateSet('Code', 'Config')][string]$List)
    if (-not (Test-SelfXListedName $Name)) { return $false }
    $isConfigFile = ($script:SelfXConfigFileNames -contains $Name) -or ($Name -match '^Branding/.+')
    if ($List -eq 'Code') { return (-not $isConfigFile) }
    return (Test-SelfXConfigName $Name)
}

function Get-SelfXFileClass {
    # Returns 'Code' or 'Config' for a file name relative to the installation folder, or throws for a file that no rule knows.
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Test-SelfXListedName $Name)) { throw "Unsupported file name in the package: $Name" }
    $comparer = [StringComparer]::OrdinalIgnoreCase
    foreach ($known in $script:SelfXConfigFileNames) { if ($comparer.Equals($known, $Name)) { return 'Config' } }
    if ($Name -match '^Branding/.+') { return 'Config' }
    foreach ($known in $script:SelfXCodeFileNames) { if ($comparer.Equals($known, $Name)) { return 'Code' } }
    if ($Name -match '^WinRT/[A-Za-z0-9._-]+\.dll$') { return 'Code' }
    # Not a file of the project: an own script or language file of the company.
    if (Test-SelfXConfigName $Name) { return 'Config' }
    throw "The file '$Name' belongs to no file class (see docs\Architecture.md)."
}

function Get-SelfXPackageEntries {
    # Every file that Install.ps1 installs, with its name in the installation folder, its path in the package and its class:
    # everything below Sources, Uninstall.ps1, the DLLs of Bin\WinRT (WinRT/<name>), Bin\Audio (Audio/<name>) and the two
    # programs SelfXService.exe and SelfX.exe from Bin. Sorted by name (ordinal). Throws for a name that is not allowed,
    # a duplicate, a missing program and a file that has no class.
    param([Parameter(Mandatory = $true)][string]$Stage)
    $sources = Join-Path $Stage 'Sources'
    if (-not (Test-Path -LiteralPath $sources -PathType Container)) { throw 'The folder Sources is missing in the package.' }
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($item in (@(Get-ChildItem -LiteralPath $sources -Recurse -File -Force) + @(Get-Item -LiteralPath (Join-Path $Stage 'Uninstall.ps1') -Force))) {
        $relative = if ($item.FullName.StartsWith($sources + '\', [StringComparison]::OrdinalIgnoreCase)) { $item.FullName.Substring($sources.Length + 1) } else { $item.Name }
        $entries.Add([pscustomobject]@{ Path = $item.FullName; Name = $relative.Replace('\', '/') })
    }
    # The WinRT libraries come from Bin (built by tools\Build-SelfXBinaries.ps1) and are installed into the folder WinRT.
    $winRT = Join-Path $Stage 'Bin\WinRT'
    if (Test-Path -LiteralPath $winRT -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $winRT -Recurse -File -Force)) {
            if ($item.DirectoryName -ne (Get-Item -LiteralPath $winRT).FullName) { throw "Unexpected sub folder in Bin\WinRT: $($item.DirectoryName)" }
            $entries.Add([pscustomobject]@{ Path = $item.FullName; Name = 'WinRT/' + $item.Name })
        }
    }
    # The audio library comes from Bin too and is installed into the folder Audio.
    $audio = Join-Path $Stage 'Bin\Audio'
    if (Test-Path -LiteralPath $audio -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $audio -Recurse -File -Force)) {
            if ($item.DirectoryName -ne (Get-Item -LiteralPath $audio).FullName) { throw "Unexpected sub folder in Bin\Audio: $($item.DirectoryName)" }
            $entries.Add([pscustomobject]@{ Path = $item.FullName; Name = 'Audio/' + $item.Name })
        }
    }
    # The two programs (service and starter) come from Bin and are installed next to the scripts; a missing one is an error.
    foreach ($program in 'SelfXService.exe', 'SelfX.exe') {
        $programPath = Join-Path $Stage "Bin\$program"
        if (-not (Test-Path -LiteralPath $programPath -PathType Leaf)) { throw "Bin\$program is missing in the package." }
        $entries.Add([pscustomobject]@{ Path = $programPath; Name = $program })
    }
    $names = [string[]]@($entries | ForEach-Object { $_.Name })
    $order = [string[]]@($names)
    [Array]::Sort($order, [StringComparer]::Ordinal)
    $byName = @{}
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($name in $order) {
        if (-not (Test-SelfXListedName $name)) { throw "Unsupported file name in the package: $name" }
        if ($byName.ContainsKey($name.ToLowerInvariant())) { throw "Duplicate file name in the package: $name" }
        $byName[$name.ToLowerInvariant()] = $true
        $entry = $entries | Where-Object { $_.Name -ceq $name } | Select-Object -First 1
        $result.Add([pscustomobject]@{ Name = $name; Path = $entry.Path; Class = (Get-SelfXFileClass -Name $name) })
    }
    return $result.ToArray()
}

function Get-SelfXClassHashes {
    param([Parameter(Mandatory = $true)][string]$Stage, [Parameter(Mandatory = $true)][ValidateSet('Code', 'Config')][string]$Class)
    $files = [ordered]@{}
    foreach ($entry in @(Get-SelfXPackageEntries -Stage $Stage | Where-Object { $_.Class -eq $Class })) {
        $files[$entry.Name] = (Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash
    }
    return $files
}

function New-SelfXCodeManifest {
    # Writes SelfX.Code.json into the staged package: the SHA256 of every file of the class Code. Same contents give the same
    # bytes (no build time). Returns the number of files.
    param([Parameter(Mandatory = $true)][string]$Stage, [Parameter(Mandatory = $true)][string]$Version)
    if (-not (Test-SelfXVersionText $Version)) { throw "Invalid version '$Version'." }
    $files = Get-SelfXClassHashes -Stage $Stage -Class Code
    $manifest = [ordered]@{
        ManifestVersion = 1
        ToolVersion     = $Version
        Files           = $files
    }
    [IO.File]::WriteAllText((Join-Path $Stage 'SelfX.Code.json'), ($manifest | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    return $files.Count
}

function New-SelfXConfigManifest {
    # Writes SelfX.Config.json into the staged package: the SHA256 of every file of the class Config and ConfigRevision, the UTC
    # time of this packaging run (yyyy-MM-ddTHH:mm:ssZ; the caller may pass it, otherwise it is now). The revision is not part of the
    # digest that Detection.ps1 compares. Returns the number of files.
    param([Parameter(Mandatory = $true)][string]$Stage, [string]$ConfigRevision)
    if (-not $ConfigRevision) { $ConfigRevision = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
    if ($ConfigRevision -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z') { throw "Invalid ConfigRevision '$ConfigRevision' (expected yyyy-MM-ddTHH:mm:ssZ, UTC)." }
    $files = Get-SelfXClassHashes -Stage $Stage -Class Config
    $manifest = [ordered]@{
        ManifestVersion = 1
        ConfigRevision  = $ConfigRevision
        Files           = $files
    }
    [IO.File]::WriteAllText((Join-Path $Stage 'SelfX.Config.json'), ($manifest | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    return $files.Count
}

# Digest of a file list: SHA256 over the lines "<name>=<SHA256>", sorted by name (ordinal), joined by LF, UTF-8.
# Detection.ps1 has the same function (Test-Detection.ps1 checks that both give the same value for the same list).
function Get-SelfXFilesDigest {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Files)
    $names = [string[]]@($Files.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $text = [string]::Join("`n", @($names | ForEach-Object { '{0}={1}' -f $_, "$($Files[$_])".ToUpperInvariant() }))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))) -replace '-', '') }
    finally { $sha.Dispose() }
}

function Get-SelfXListDigest {
    # Digest of SelfX.Code.json or SelfX.Config.json of the staged package, read back from the file (exactly what Install.ps1 installs).
    param([Parameter(Mandatory = $true)][string]$Stage, [Parameter(Mandatory = $true)][ValidateSet('SelfX.Code.json', 'SelfX.Config.json')][string]$ListName)
    $list = Get-Content -LiteralPath (Join-Path $Stage $ListName) -Raw | ConvertFrom-Json
    $files = [ordered]@{}
    foreach ($property in @($list.Files.PSObject.Properties)) { $files[$property.Name] = "$($property.Value)" }
    if ($files.Count -eq 0) { throw "$ListName lists no files." }
    return (Get-SelfXFilesDigest -Files $files)
}

# Writes the Detection.ps1 for Intune: the copy of the package with the digests of SelfX.Code.json and SelfX.Config.json instead of
# the two placeholders. The detection script is uploaded to Intune separately from the .intunewin, so it must come from the same
# build. Returns an object with the properties Code and Config (the two digests).
function New-SelfXDetectionScript {
    param([Parameter(Mandatory = $true)][string]$Stage, [Parameter(Mandatory = $true)][string]$Target)
    $codeDigest = Get-SelfXListDigest -Stage $Stage -ListName 'SelfX.Code.json'
    $configDigest = Get-SelfXListDigest -Stage $Stage -ListName 'SelfX.Config.json'
    $path = Join-Path $Stage 'Detection.ps1'
    $bytes = [IO.File]::ReadAllBytes($path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [IO.File]::ReadAllText($path)
    $replacements = @(
        @{ Variable = 'ExpectedCodeHash'; Placeholder = '__SELFX_CODE_HASH__'; Value = $codeDigest },
        @{ Variable = 'ExpectedConfigHash'; Placeholder = '__SELFX_CONFIG_HASH__'; Value = $configDigest }
    )
    foreach ($replacement in $replacements) {
        $pattern = "(\`$$($replacement.Variable)\s*=\s*')$($replacement.Placeholder)(')"
        if (@([regex]::Matches($text, $pattern)).Count -ne 1) { throw "Detection.ps1 must contain the placeholder for `$$($replacement.Variable) exactly once." }
        $text = [regex]::Replace($text, $pattern, ('${1}' + $replacement.Value + '${2}'))
    }
    [IO.File]::WriteAllText($Target, $text, (New-Object System.Text.UTF8Encoding($hasBom)))
    return [pscustomobject]@{ Code = $codeDigest; Config = $configDigest }
}
