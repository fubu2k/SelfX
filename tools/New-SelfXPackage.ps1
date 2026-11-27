<#
.SYNOPSIS
    Guided configuration: asks questions (with a recommendation for each), then builds the Intune package in one run (Invoke-SelfXPackageBuild)
    and writes the Intune scripts and short instructions.

.DESCRIPTION
    For administrators on the build machine. It works on the unpacked payload archive of a release (SelfX-Service-<version>-payload.zip, no
    .NET SDK needed; this script is in its folder tools) or, in the repository, on the package folder "SelfX Service" with the folder Bin
    (-BuildBinaries builds it). The payload and the repository are not changed: everything is built in a work folder and replaces the output
    folder only when all steps worked. Result in the output folder:

      package\                                  the configured package folder (input of the packaging)
      SelfX-Service-<version>.intunewin         the package for Intune (not with -ConfigureOnly)
      SelfX-Service-<version>.Detection.ps1     the detection script for Intune (not with -ConfigureOnly; signed in the trust mode Signature)
      SelfX.AppLocker.xml, AppControl\          AppLocker rules and App Control (WDAC) supplemental policy for the mode (optional)
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
    Default: build\SelfX-Guided in the repository (payload: the folder SelfX-Guided next to the payload folder).

.PARAMETER ToolPath
    IntuneWinAppUtil.exe (Win32 Content Prep Tool). Checked for the Microsoft signature by New-SelfXIntuneWin.ps1.

.PARAMETER BuildBinaries
    Only in the repository: build the programs (tools\Build-SelfXBinaries.ps1) when the folder Bin is missing. Without the switch the
    wizard asks. The payload archive contains the programs.

.PARAMETER PayloadFolder
    A folder in the layout of the unpacked payload archive (Install.ps1, App, Config, Bin ...). Default: the folder above tools when it is an
    unpacked payload archive, otherwise the package folder "SelfX Service" of the repository.

.PARAMETER CertificateThumbprint
    Trust mode Signature: SHA1 thumbprint (40 hexadecimal characters) of a code signing certificate with private key in the certificate
    store of the user or of the computer. The package, the catalogs and the detection script are signed with it (docs\Installation.md).

.PARAMETER PfxPath
    Trust mode Signature: a PFX file instead of the store. The password is asked for (hidden); it is never a parameter, never written to
    a file, a log or selfx-answers.json.

.PARAMETER TimestampServer
    Time stamp service (http or https address) for the signatures. Recommended, so the signatures stay valid after the certificate expires.

.PARAMETER AdditionalSigner
    Trust mode Signature, change of the certificate: SHA1 thumbprints (40 hexadecimal characters) of further signers that the devices
    shall accept. They go into -TrustedSigner of the install command in the instructions; nothing is signed with them. At most 9.

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
    Version : 1.2.0
    Exit code: 0 = done, 1 = error or aborted
    Works in Windows PowerShell 5.1 and PowerShell 7. The wizard sends nothing; only -PfxPath makes it ask for the password of the PFX file (hidden, not stored).

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-24  fubu2k               Initial version: guided configuration (de, en)
    1.0.1    2026-11-27  fubu2k               The version in the file names comes from Version.txt (no longer from Tool_Config.xml)
    1.1.0    2026-11-27  fubu2k               Only asks and calls Invoke-SelfXPackageBuild (one run, no half-finished output); works on the unpacked payload
                                              archive; -CertificateThumbprint, -PfxPath, -TimestampServer for the trust mode Signature
    1.1.1    2026-11-27  fubu2k               Default paths and the build of the repository package through Get-WizardBuildDefaults and
                                              Invoke-SelfXWizardBuild (shared with the window tools\Wizard\SelfXWizardGui.ps1); same behavior
    1.2.0    2026-11-27  fubu2k               -AdditionalSigner (further thumbprints for -TrustedSigner, change of the certificate)
#>
[CmdletBinding()]
param(
    [string]$Language,
    [string]$AnswerFile,
    [string]$OutputFolder,
    [string]$ToolPath,
    [switch]$BuildBinaries,
    [switch]$ConfigureOnly,
    [string]$PayloadFolder,
    [string]$CertificateThumbprint,
    [string]$PfxPath,
    [string]$TimestampServer,
    [string[]]$AdditionalSigner = @()
)

$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$WizardFolder = Join-Path $ScriptFolder 'Wizard'
# The functions of the assistant (texts, questions, Invoke-SelfXPackageBuild); the files only define functions.
. (Join-Path $WizardFolder 'SelfXWizard.ps1')

$certificate = $null
try {
    $interactive = -not $AnswerFile
    $script:WizardInteractive = $interactive
    if ($CertificateThumbprint -and $PfxPath) { throw 'Use either -CertificateThumbprint or -PfxPath, not both.' }
    if ($TimestampServer -and -not ($CertificateThumbprint -or $PfxPath)) { throw '-TimestampServer needs -CertificateThumbprint or -PfxPath.' }
    if ($ConfigureOnly -and ($CertificateThumbprint -or $PfxPath)) { throw '-ConfigureOnly does not sign: do not combine it with a certificate.' }
    if (@($AdditionalSigner | Where-Object { $_ }).Count -and -not ($CertificateThumbprint -or $PfxPath)) { throw '-AdditionalSigner needs -CertificateThumbprint or -PfxPath.' }

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

    # ---- where the package comes from: -PayloadFolder, the unpacked payload archive (this script is in its folder tools) or the repository
    $defaults = Get-WizardBuildDefaults -ToolsFolder $ScriptFolder -PayloadFolder $PayloadFolder
    $packageSource = $defaults.PayloadFolder
    $fromRepository = $defaults.FromRepository

    # ---- build settings (machine specific, not part of the saved answers)
    if (-not $OutputFolder) {
        $OutputFolder = $defaults.OutputFolder
        if ($interactive) {
            Write-Host ''; Write-Host (Get-WText 'section.build') -ForegroundColor Green
            $OutputFolder = Get-WizardAnswer -Question @{ Id = 'Output'; Kind = 'text'; Max = 260; Default = $OutputFolder } -Answers $answers -Source @{}
        }
    }
    if (-not $ConfigureOnly -and -not $ToolPath) {
        $ToolPath = $defaults.ToolPath
        if ($interactive) { $ToolPath = Get-WizardAnswer -Question @{ Id = 'Tool'; Kind = 'text'; Max = 260; Default = $ToolPath } -Answers $answers -Source @{} }
    }

    # ---- certificate (trust mode Signature)
    if ($CertificateThumbprint) {
        $certificate = @(Get-SelfXSigningCertificate -Thumbprint $CertificateThumbprint) | Select-Object -First 1
        if ($null -eq $certificate) { throw 'No suitable code signing certificate with this thumbprint was found in the certificate stores (private key, code signing, valid).' }
    }
    elseif ($PfxPath) {
        $password = Read-Host -Prompt (Get-WText 'pfx.password') -AsSecureString
        $certificate = Get-SelfXSigningCertificate -PfxPath $PfxPath -PfxPassword $password
        $password.Dispose()
        $password = $null
    }

    # ---- programs (repository only: the payload archive contains them)
    if ($fromRepository -and -not $ConfigureOnly -and -not (Test-Path -LiteralPath (Join-Path $packageSource 'Bin\SelfX.Binaries.json') -PathType Leaf)) {
        $build = [bool]$BuildBinaries
        if (-not $build -and $interactive) { $build = Get-WizardAnswer -Question @{ Id = 'BuildBinaries'; Kind = 'bool'; Default = $true } -Answers $answers -Source @{} }
        if (-not $build) { throw 'The folder Bin is missing. Run tools\Build-SelfXBinaries.ps1 first or use -BuildBinaries.' }
        Write-Host (Get-WText 'step.bin') -ForegroundColor Cyan
        & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptFolder 'Build-SelfXBinaries.ps1')
        if ($LASTEXITCODE -ne 0) { throw "Build-SelfXBinaries.ps1 failed (exit code $LASTEXITCODE)." }
    }

    # ---- build (the package folder of the repository is brought into the layout of the payload in a temporary folder first)
    $result = Invoke-SelfXWizardBuild -Answers $answers -PayloadFolder $packageSource -FromRepository:$fromRepository -OutputFolder $OutputFolder -ToolPath $ToolPath `
        -Certificate $certificate -TimestampServer $TimestampServer -AdditionalSigner $AdditionalSigner -Language $Language -ConfigureOnly:$ConfigureOnly `
        -OnProgress { param($id, $text) Write-Host $text -ForegroundColor Cyan }

    Write-Host ''
    Write-Host (Get-WText $(if ($ConfigureOnly) { 'done.config' } else { 'done' }) @($result.OutputFolder)) -ForegroundColor Green
    Write-Host ''
    Write-Host $result.GuideText
    exit 0
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($null -ne $certificate) { $certificate.Dispose() }
}
