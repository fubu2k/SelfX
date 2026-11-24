<#
.SYNOPSIS
    Guided configuration: asks questions (with a recommendation for each), writes the answers into a copy of the
    package, builds the Intune package and writes the Intune scripts and short instructions.

.DESCRIPTION
    For administrators on the build machine. The files in the repository are not changed: the wizard works on a copy
    in the output folder. Result in the output folder:

      package\                                  the configured package folder (input of the packaging)
      SelfX-Service-<version>.intunewin         the package for Intune (not with -ConfigureOnly)
      SelfX-Service-<version>.Detection.ps1     the detection script for Intune (not with -ConfigureOnly)
      Set-SelfXSupportUnit-*.ps1                Intune platform scripts for the ticket routing (one per unit/group tag/device class)
      SelfX-Intune-Guide.<language>.txt         short instructions for Intune in the language of the wizard
      selfx-answers.json                        your answers (contains mailbox addresses: do not commit)

    Languages of the wizard: tools\Wizard\Wizard.<culture>.xml (de, en). Missing texts come from English.
    Non-interactive: -AnswerFile selfx-answers.json uses the saved answers (and the defaults for missing ones).

.PARAMETER Language
    Language of the wizard (de, en ...). Default: the wizard asks first (in English; English is the default, other languages are a numbered list).

.PARAMETER AnswerFile
    JSON file with answers (see selfx-answers.json of an earlier run). No questions are asked.

.PARAMETER OutputFolder
    Default: build\SelfX-Guided in the repository.

.PARAMETER ToolPath
    IntuneWinAppUtil.exe (Win32 Content Prep Tool). Checked for the Microsoft signature by New-SelfXIntuneWin.ps1.

.PARAMETER BuildBinaries
    Build the programs (tools\Build-SelfXBinaries.ps1) when the folder Bin is missing. Without the switch the wizard asks.

.PARAMETER ConfigureOnly
    Write the configured package folder, the scripts and the instructions only. No programs are built, nothing is packaged.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXPackage.ps1

.EXAMPLE
    .\tools\New-SelfXPackage.ps1 -AnswerFile .\build\SelfX-Guided\selfx-answers.json -ToolPath C:\Tools\IntuneWinAppUtil.exe

.NOTES
    Name    : New-SelfXPackage.ps1
    Package : tools
    Context : Build machine (administrator of the package; not installed)
    Version : 1.0.0
    Exit code: 0 = done, 1 = error or aborted
    Works in Windows PowerShell 5.1 and PowerShell 7. The wizard asks for no password and no secret and sends nothing.

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-24  fubu2k               Initial version: guided configuration (de, en)
#>
[CmdletBinding()]
param(
    [string]$Language,
    [string]$AnswerFile,
    [string]$OutputFolder,
    [string]$ToolPath,
    [switch]$BuildBinaries,
    [switch]$ConfigureOnly
)

$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$PackageSource = Join-Path $RepositoryRoot 'SelfX Service'
$WizardFolder = Join-Path $ScriptFolder 'Wizard'
. (Join-Path $WizardFolder 'SelfXWizard.ps1')

try {
    $interactive = -not $AnswerFile
    $script:WizardInteractive = $interactive

    # ---- language of the wizard
    $languages = @(Get-WizardLanguages -Folder $WizardFolder)
    if (-not $Language) {
        # The first question is always in English: English is the default, the other languages are a numbered list.
        $Language = 'en'
        if ($interactive) {
            $ordered = @($languages | Sort-Object @{ Expression = { $_.Culture -ne 'en' } }, Culture)
            while ($true) {
                Write-Host 'Select the language of this wizard:' -ForegroundColor White
                for ($i = 0; $i -lt $ordered.Count; $i++) { Write-Host ("  {0}) {1} ({2})" -f ($i + 1), $ordered[$i].Name, $ordered[$i].Culture) }
                $typed = (Read-Host 'Number or language code [1 = English]').Trim()
                if ($typed -eq '') { $Language = 'en'; break }
                $number = 0
                if ([int]::TryParse($typed, [ref]$number) -and $number -ge 1 -and $number -le $ordered.Count) { $Language = $ordered[$number - 1].Culture; break }
                $match = @($ordered | Where-Object { $_.Culture -ieq $typed })
                if ($match.Count -eq 1) { $Language = $match[0].Culture; break }
                Write-Host 'This choice is not valid.' -ForegroundColor Yellow
            }
        }
    }
    Initialize-WizardTexts -Folder $WizardFolder -Culture $Language
    $guideLanguage = if ($languages.Culture -contains $Language) { $Language } elseif ($Language.Contains('-') -and $languages.Culture -contains $Language.Split('-')[0]) { $Language.Split('-')[0] } else { 'en' }

    if ($interactive) {
        Write-Host ''
        Write-Host (Get-WText 'title') -ForegroundColor Green
        Write-Host (Get-WText 'intro')
    }

    # ---- answers
    $source = $null
    if ($AnswerFile) {
        if (-not (Test-Path -LiteralPath $AnswerFile -PathType Leaf)) { throw "Answer file not found: $AnswerFile" }
        $json = Get-Content -LiteralPath $AnswerFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $source = @{}
        foreach ($property in $json.PSObject.Properties) { $source[$property.Name] = $property.Value }
        $known = @((Get-WizardQuestions) | ForEach-Object { $_.Id }) + @('Units', 'WizardLanguage')
        foreach ($key in $source.Keys) { if ($known -notcontains $key) { throw "Unknown answer '$key' in the answer file." } }
    }
    $answers = Read-WizardAnswers -Source $source

    if ($interactive) {
        Write-Host ''
        Write-Host (Get-WText 'summary.header') -ForegroundColor Green
        Get-WizardSummary -A $answers | ForEach-Object { Write-Host $_ }
        $go = Get-WizardAnswer -Question @{ Id = 'summary'; Kind = 'bool'; Default = $true } -Answers $answers -Source @{}
        if (-not $go) { Write-Host (Get-WText 'aborted'); exit 1 }
    }

    # ---- build settings (machine specific, not part of the saved answers)
    if (-not $OutputFolder) {
        $OutputFolder = Join-Path $RepositoryRoot 'build\SelfX-Guided'
        if ($interactive) {
            Write-Host ''; Write-Host (Get-WText 'section.build') -ForegroundColor Green
            $OutputFolder = Get-WizardAnswer -Question @{ Id = 'Output'; Kind = 'text'; Max = 260; Default = $OutputFolder } -Answers $answers -Source @{}
        }
    }
    if (-not $ConfigureOnly -and -not $ToolPath) {
        $ToolPath = Join-Path $ScriptFolder 'IntuneWinAppUtil.exe'
        if ($interactive) { $ToolPath = Get-WizardAnswer -Question @{ Id = 'Tool'; Kind = 'text'; Max = 260; Default = $ToolPath } -Answers $answers -Source @{} }
    }
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    $OutputFolder = (Resolve-Path -LiteralPath $OutputFolder).Path
    $hostExe = (Get-Process -Id $PID).Path

    # ---- programs
    $bin = Join-Path $PackageSource 'Bin'
    if (-not $ConfigureOnly -and -not (Test-Path -LiteralPath (Join-Path $bin 'SelfX.Binaries.json') -PathType Leaf)) {
        $build = [bool]$BuildBinaries
        if (-not $build -and $interactive) { $build = Get-WizardAnswer -Question @{ Id = 'BuildBinaries'; Kind = 'bool'; Default = $true } -Answers $answers -Source @{} }
        if (-not $build) { throw 'The folder Bin is missing. Run tools\Build-SelfXBinaries.ps1 first or use -BuildBinaries.' }
        Write-Host (Get-WText 'step.bin') -ForegroundColor Cyan
        & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptFolder 'Build-SelfXBinaries.ps1')
        if ($LASTEXITCODE -ne 0) { throw "Build-SelfXBinaries.ps1 failed (exit code $LASTEXITCODE)." }
    }

    # ---- configured copy of the package
    Write-Host (Get-WText 'step.config') -ForegroundColor Cyan
    $packageCopy = Join-Path $OutputFolder 'package'
    if (Test-Path -LiteralPath $packageCopy) { Remove-Item -LiteralPath $packageCopy -Recurse -Force }
    New-Item -ItemType Directory -Path $packageCopy -Force | Out-Null
    Copy-Item -Path (Join-Path $PackageSource '*') -Destination $packageCopy -Recurse -Force
    $projects = Join-Path $packageCopy 'Service\Projects'
    if (Test-Path -LiteralPath $projects) { Remove-Item -LiteralPath $projects -Recurse -Force }
    Get-ChildItem -LiteralPath $packageCopy -Recurse -File -Filter 'Test-*.ps1' | Remove-Item -Force
    Set-WizardPackageConfiguration -PackageFolder $packageCopy -Answers $answers
    $version = (Select-Xml -Path (Join-Path $packageCopy 'Sources\Tool_Config.xml') -XPath '/GUI_Config/Tool_Version').Node.InnerText.Trim()

    # ---- Intune package
    $packageName = "SelfX-Service-$version.intunewin"
    $detectionName = "SelfX-Service-$version.Detection.ps1"
    if (-not $ConfigureOnly) {
        Write-Host (Get-WText 'step.pack') -ForegroundColor Cyan
        & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptFolder 'New-SelfXIntuneWin.ps1') -SourceFolder $packageCopy -OutputFolder $OutputFolder -ToolPath $ToolPath
        if ($LASTEXITCODE -ne 0) { throw "New-SelfXIntuneWin.ps1 failed (exit code $LASTEXITCODE)." }
    }

    # ---- scripts and instructions
    Write-Host (Get-WText 'step.guide') -ForegroundColor Cyan
    $scriptFiles = New-Object System.Collections.Generic.List[string]
    $safe = { param($s) ("$s" -replace '[^A-Za-z0-9._-]', '_') }
    foreach ($unit in @($answers.Units)) {
        $tags = @($unit.GroupTags); $classes = @($unit.Categories)
        $combos = New-Object System.Collections.Generic.List[object]
        if ($tags.Count -and $classes.Count) { foreach ($t in $tags) { foreach ($c in $classes) { $combos.Add(@($t, $c)) } } }
        elseif ($tags.Count) { foreach ($t in $tags) { $combos.Add(@($t, '')) } }
        elseif ($classes.Count) { foreach ($c in $classes) { $combos.Add(@('', $c)) } }
        # Units that are matched by OU only need no script: the rules of Ticket_Config.xml route them.
        if ($combos.Count -gt 50) { throw "The unit '$($unit.Id)' needs more than 50 scripts. Reduce the group tags or device classes." }
        foreach ($combo in $combos) {
            $name = 'Set-SelfXSupportUnit-' + (& $safe $unit.Id)
            if ($combo[0]) { $name += '-' + (& $safe $combo[0]) }
            if ($combo[1]) { $name += '-' + (& $safe $combo[1]) }
            $path = Join-Path $OutputFolder ($name + '.ps1')
            [IO.File]::WriteAllText($path, (New-SelfXSupportUnitScript -Unit $unit -GroupTag $combo[0] -Category $combo[1]), (New-Object System.Text.UTF8Encoding($false)))
            $scriptFiles.Add($name + '.ps1')
        }
    }
    $answersFile = Join-Path $OutputFolder 'selfx-answers.json'
    $saved = [ordered]@{ WizardLanguage = $Language }
    foreach ($key in ($answers.Keys | Where-Object { $_ -ne 'Units' } | Sort-Object)) { $saved[$key] = $answers[$key] }
    $saved['Units'] = @($answers.Units | ForEach-Object { [ordered]@{ UnitId = $_.Id; UnitMail = $_.Mail; UnitCc = $_.Cc; UnitGroupTags = @($_.GroupTags); UnitOUs = @($_.OUs); UnitCategories = @($_.Categories) } })
    [IO.File]::WriteAllText($answersFile, ($saved | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    $guide = New-SelfXIntuneGuide -Answers $answers -Version $version -PackageFile $packageName -DetectionFile $detectionName -ScriptFiles $scriptFiles.ToArray() -AnswersFile 'selfx-answers.json'
    $guidePath = Join-Path $OutputFolder "SelfX-Intune-Guide.$guideLanguage.txt"
    [IO.File]::WriteAllText($guidePath, $guide, (New-Object System.Text.UTF8Encoding($true)))

    Write-Host ''
    Write-Host (Get-WText $(if ($ConfigureOnly) { 'done.config' } else { 'done' }) @($OutputFolder)) -ForegroundColor Green
    Write-Host ''
    Write-Host $guide
    exit 0
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
