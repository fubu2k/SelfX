<#
.SYNOPSIS
    Window of the SelfX package wizard: the same questions as tools\New-SelfXPackage.ps1 on pages, then one click builds the Intune package.

.DESCRIPTION
    Start: tools\Start-SelfXPackageWizard.cmd (Windows PowerShell 5.1, -STA). PowerShell 7 works as well (pwsh -STA -File ...).
    Pages: language, basics, support, branding, ticket, network targets, further settings, signature, summary (with the build settings), build (progress
    list) and result (files and the instructions for Intune as steps with copy buttons).

    Signature: the certificate comes from the stores (Get-SelfXSigningCertificate lists only certificates with a private key, the key usage
    Code Signing and a valid period) or from a PFX file. The password of a PFX file is read from the password box as a SecureString only
    (PasswordBox.SecurePassword; the property Password is never read), used once to open the file and disposed; the box is emptied. It never
    reaches the state, the answers, a text, a log or the window title. The certificate lives in memory and is disposed when the window closes.

    The window only shows and collects: every value is checked with the functions of SelfXWizard.ps1 (ConvertTo-WizardValue,
    Test-WizardUnitValues, Read-WizardLogo) as soon as it is typed, the error is shown at the field. The answers are the same object the
    console builds from an answer file (Test-WizardAnswerSet), and the build is Invoke-SelfXWizardBuild in a background runspace, so the
    window stays usable and the build can be cancelled (until the result is written). Answers can be loaded from and saved to
    selfx-answers.json (Save-WizardAnswers; never a password or a key). Texts come from Wizard.<culture>.xml only.

    Look: the shared styles are read from Sources\Self_X.ps1 (the here-string $Global:SelfX_StylesXaml, parsed, not run) and the colors
    from Sources\Branding.ps1 (New-SelfXThemeColors), both from the package around this folder tools (payload: App, repository:
    "SelfX Service\Sources"). Light or dark follows Windows. A valid company color is shown at once.

    The file only defines functions when it is dot-sourced (tools\Test-SelfXWizardGui.ps1 does this); run as a script it opens the window.

.NOTES
    Name    : SelfXWizardGui.ps1
    Package : tools
    Context : Build machine (administrator of the package, own user account; not installed, not shipped to devices)
    Version : 1.9.0
    Works in Windows PowerShell 5.1 and PowerShell 7 on Windows (WPF, single-threaded apartment). Sends nothing, starts no process
    except the Windows Explorer for the result folder (on request) and what Invoke-SelfXPackageBuild starts (IntuneWinAppUtil.exe and the
    rule scripts).

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-27  fubu2k               Initial version
    1.1.0    2026-11-27  fubu2k               Page Signature: no certificate (trust mode Hash), certificate from the store (suitable ones only) or a
                                              PFX file (password box, SecureString only, emptied after opening), time stamp service (required unless
                                              switched off), additional signers for a change of the certificate, revocation list addresses with
                                              warnings; result page with the instructions as steps and copy buttons
    1.2.0    2026-11-27  fubu2k               Summary page: choice of the package (full, full with separate configuration, configuration package)
    1.3.0    2026-11-27  fubu2k               Page Network targets (between ticket and further settings): switches for the measurement, the delivered
                                              Microsoft targets and host names in the report, list of own targets (label, host, port, group, kind)
    1.4.0    2026-11-27  fubu2k               Page Basics: question EnvironmentMode (Where does SelfX run?)
    1.5.0    2026-11-28  fubu2k               Page Basics: question TerminalServerHealth (device status on a terminal server)
    1.6.0    2026-11-28  fubu2k               Page Basics: question TargetOS (Windows 11 or Windows Server) instead of EnvironmentMode; result page:
                                              title of the instructions for a server package (installation without Intune)
    1.7.0    2026-11-28  fubu2k               Page Support: question TerminalServerSupportMail (only for Windows Server)
    1.8.0    2026-11-28  fubu2k               Windows Server: no field for IntuneWinAppUtil.exe on the page Summary, no step 'pack' in the progress list,
                                              no .intunewin file on the result page
    1.9.0    2026-11-28  fubu2k               Page More settings: question DisturbWarning (hint before disruptive actions)
#>

$ErrorActionPreference = 'Stop'
$script:GuiFolder = $(if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path })
$script:GuiToolsFolder = Split-Path -Parent $script:GuiFolder
$script:GuiIsDotSourced = ($MyInvocation.InvocationName -eq '.')
# Questions, validation, texts and Invoke-SelfXWizardBuild. The file only defines functions.
. (Join-Path $script:GuiFolder 'SelfXWizard.ps1')

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# ---------------------------------------------------------------- package around tools (styles, colors, languages of SelfX)

# The folder with Self_X.ps1 and Branding.ps1: App of the unpacked payload archive or "SelfX Service\Sources" of the repository.
function Get-WizardGuiCodeFolder {
    param([Parameter(Mandatory = $true)][string]$ToolsFolder)
    $root = Split-Path -Parent $ToolsFolder
    foreach ($candidate in @((Join-Path $root 'App'), (Join-Path $root 'SelfX Service\Sources'))) {
        if ((Test-Path -LiteralPath (Join-Path $candidate 'Self_X.ps1') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $candidate 'Branding.ps1') -PathType Leaf)) { return $candidate }
    }
    throw 'Self_X.ps1 and Branding.ps1 were not found next to the folder tools (App of the payload or "SelfX Service\Sources" of the repository).'
}

# The shared styles of the SelfX window: the constant text of $Global:SelfX_StylesXaml in Self_X.ps1. The file is parsed, never run; the value
# must be a plain single-quoted string (no expression), otherwise this is an error.
function Get-WizardGuiSharedStyles {
    param([Parameter(Mandatory = $true)][string]$SelfXScript)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($SelfXScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) { throw 'Self_X.ps1 cannot be parsed; the shared styles are not available.' }
    $found = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -eq 'Global:SelfX_StylesXaml'
            }, $true))
    if ($found.Count -ne 1) { throw 'Self_X.ps1 must assign $Global:SelfX_StylesXaml exactly once.' }
    $right = $found[0].Right
    if ($right -is [System.Management.Automation.Language.CommandExpressionAst]) { $right = $right.Expression }
    if ($right -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { throw '$Global:SelfX_StylesXaml in Self_X.ps1 is not a constant text.' }
    return $right.Value
}

# Culture names of the SelfX language files (Languages\<culture>.xml) for the list of the question ToolLanguage.
function Get-WizardGuiToolCultures {
    param([Parameter(Mandatory = $true)][string]$CodeFolder)
    $folder = Join-Path $CodeFolder 'Languages'
    $names = @()
    if (Test-Path -LiteralPath $folder -PathType Container) {
        $names = @(Get-ChildItem -LiteralPath $folder -Filter '*.xml' -File | ForEach-Object { $_.BaseName } | Where-Object { $_ -match '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}$' } | Sort-Object)
    }
    return , (@('Auto') + $names)
}

$script:GuiCodeFolder = Get-WizardGuiCodeFolder -ToolsFolder $script:GuiToolsFolder
# Colors of the themes (New-SelfXThemeColors, Set-SelfXThemeResources). The file only defines functions and two tables.
. (Join-Path $script:GuiCodeFolder 'Branding.ps1')

# ---------------------------------------------------------------- pages and questions

# Page ids in order and the questions of SelfXWizard.ps1 on each page. Every question of Get-WizardQuestions is on exactly one page
# (Test-SelfXWizardGui.ps1 checks this). The page 'summary' has the build settings, which are not answers (same as the console).
$script:WizardGuiPages = @(
    [pscustomobject]@{ Id = 'language'; Questions = @('ToolLanguage', 'ShowLanguageSetting') },
    [pscustomobject]@{ Id = 'basics'; Questions = @('OrgName', 'ToolName', 'TargetOS', 'TerminalServerHealth') },
    [pscustomobject]@{ Id = 'support'; Questions = @('SupportMail', 'TerminalServerSupportMail', 'SupportPhone', 'SupportHours', 'SupportWebsite', 'SupportTeams') },
    [pscustomobject]@{ Id = 'branding'; Questions = @('LogoPath', 'AccentColor') },
    [pscustomobject]@{ Id = 'ticket'; Questions = @('TicketEnabled', 'TicketMail', 'TicketSubjectTag', 'MultiOrg', 'HybridJoin', 'UseGroupTags', 'UseDeviceClass') },
    [pscustomobject]@{ Id = 'network'; Questions = @('NetworkEnabled', 'NetworkMicrosoft', 'NetworkHostNames') },
    [pscustomobject]@{ Id = 'more'; Questions = @('CopilotEnabled', 'CopilotAudience', 'CopilotClearClipboard', 'WikiEnabled', 'WikiUrl', 'WikiName', 'TrayIcon', 'DisturbWarning', 'ShortcutDesktop', 'ShortcutStartMenu', 'Expert', 'LogRetention', 'FileCheck', 'Privileges', 'AppLockerRules', 'WdacBasePolicyId') },
    [pscustomobject]@{ Id = 'signing'; Questions = @() },
    [pscustomobject]@{ Id = 'summary'; Questions = @() },
    [pscustomobject]@{ Id = 'build'; Questions = @() },
    [pscustomobject]@{ Id = 'result'; Questions = @() }
)

# The build settings of the page summary. Payload and ConfigureOnly have texts of the window; Output and Tool use the texts of the console.
$script:WizardGuiBuildQuestions = @(
    @{ Id = 'Payload'; Kind = 'text'; Max = 260; Required = $true; Browse = 'folder' },
    @{ Id = 'Output'; Kind = 'text'; Max = 260; Required = $true; Browse = 'folder' },
    @{ Id = 'ConfigureOnly'; Kind = 'bool' },
    @{ Id = 'PackageKind'; Kind = 'choice'; Choices = @('Full', 'FullSeparateConfig', 'ConfigOnly') },
    # No tool for a package for Windows Server (it has no .intunewin file); $a are the answers so far.
    @{ Id = 'Tool'; Kind = 'text'; Max = 260; Required = $true; Browse = 'tool'; When = { param($b, $a) -not $b.ConfigureOnly -and -not ($a -and $a.TargetOS -eq 'WindowsServer') } }
)

# The fields of the page signing (time stamp service, without time stamp, additional signers); the texts are <Id>.ask and <Id>.rec.
$script:WizardGuiSigningQuestions = @(
    @{ Id = 'Timestamp'; Kind = 'text'; Max = 500 },
    @{ Id = 'NoTimestamp'; Kind = 'bool' },
    @{ Id = 'Additional'; Kind = 'text'; Max = 500 }
)

# The index of a page by its id.
function Get-WizardGuiPageIndex {
    param([Parameter(Mandatory = $true)][string]$Id)
    for ($i = 0; $i -lt $script:WizardGuiPages.Count; $i++) { if ($script:WizardGuiPages[$i].Id -eq $Id) { return $i } }
    throw "Unknown page $Id."
}

# Step ids of Invoke-SelfXPackageBuild in the order of the progress list (sign and catalog only with a certificate).
function Get-WizardGuiBuildSteps {
    param([bool]$ConfigureOnly, [bool]$Signed, [string]$PackageKind = 'Full', [bool]$ServerPackage)
    if ($ConfigureOnly) { return , @('check', 'copy', 'config', 'guide', 'finish') }
    # A package for Windows Server is not packed (no .intunewin file).
    $steps = New-Object System.Collections.Generic.List[string]
    foreach ($step in @('check', 'copy', 'config', 'sign', 'catalog', 'pack', 'detection', 'rules', 'guide', 'finish')) {
        if ($step -in @('sign', 'catalog') -and -not $Signed) { continue }
        # The configuration package has no programs and so no code catalog.
        if ($step -eq 'catalog' -and $PackageKind -eq 'ConfigOnly') { continue }
        if ($step -eq 'pack' -and $ServerPackage) { continue }
        $steps.Add($step)
    }
    return , $steps.ToArray()
}

# Text ids of the window (labels of questions use <Id>.ask and <Id>.rec). Test-SelfXWizardGui.ps1 checks that de and en have all of them.
function Get-WizardGuiTextIds {
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($id in 'title', 'rec', 'required', 'gui.back', 'gui.next', 'gui.load', 'gui.save', 'gui.browse', 'gui.wizardLanguage.ask', 'gui.wizardLanguage.rec',
        'gui.preview', 'gui.logo.none', 'gui.logo.invalid', 'gui.accent.sample', 'gui.accent.link', 'gui.units.title', 'gui.units.rec', 'gui.units.add', 'gui.units.remove',
        'gui.units.empty', 'gui.units.duplicate', 'gui.unit.title', 'gui.unit.new', 'gui.unit.invalid', 'gui.targets.title', 'gui.targets.rec', 'gui.targets.add', 'gui.targets.remove', 'gui.targets.duplicate', 'gui.targets.max', 'gui.target.title', 'gui.target.new', 'gui.target.invalid', 'gui.summary.title', 'gui.summary.build', 'Payload.ask', 'Payload.rec', 'Payload.missing',
        'ConfigureOnly.ask', 'ConfigureOnly.rec', 'PackageKind.ask', 'PackageKind.rec', 'Output.ask', 'Output.rec', 'Tool.ask', 'Tool.rec', 'gui.build.start', 'gui.build.cancel', 'gui.build.running', 'gui.build.cancelling',
        'gui.build.cancelled', 'gui.build.failed', 'gui.build.done', 'gui.state.pending', 'gui.state.running', 'gui.state.done', 'gui.state.failed', 'gui.state.cancelled',
        'gui.result.text', 'gui.result.configured', 'gui.result.files', 'gui.result.open', 'gui.result.copy', 'gui.result.copied', 'gui.result.guide', 'gui.result.guide.server', 'gui.page.errors', 'gui.answers.loaded',
        'gui.answers.saved', 'gui.answers.invalid', 'gui.answers.unreadable', 'gui.answers.filter', 'gui.logo.filter', 'gui.tool.filter', 'gui.close.build', 'gui.finish',
        'gui.sign.none', 'gui.sign.store', 'gui.sign.file', 'gui.sign.none.info', 'gui.sign.store.rec', 'gui.sign.store.empty', 'gui.sign.store.none', 'gui.sign.refresh',
        'gui.sign.file.ask', 'gui.sign.file.rec', 'gui.sign.password.ask', 'gui.sign.password.rec', 'gui.sign.open', 'gui.sign.file.failed', 'gui.sign.file.notloaded',
        'gui.sign.file.loaded', 'gui.sign.pfx.filter', 'gui.sign.details', 'gui.sign.subject', 'gui.sign.issuer', 'gui.sign.valid', 'gui.sign.thumbprint', 'gui.sign.crl',
        'gui.crl.none', 'gui.crl.nohttp', 'gui.crl.internal', 'gui.kind.timestamp', 'gui.sign.additional.invalid', 'gui.sign.configureonly', 'gui.summary.sign.none',
        'gui.summary.sign', 'gui.summary.sign.notimestamp', 'gui.copy.name', 'gui.copy.package', 'gui.copy.install', 'gui.copy.uninstall', 'gui.copy.requirement',
        'gui.copy.detection', 'gui.copy.folder', 'gui.copy.thumbprints', 'gui.copy.asr', 'gui.copy.packagefolder', 'gui.result.copied.value') {
        $ids.Add($id)
    }
    foreach ($page in $script:WizardGuiPages) { $ids.Add("gui.page.$($page.Id)"); $ids.Add("gui.page.$($page.Id).intro") }
    foreach ($kind in 'bool', 'text', 'mail', 'url', 'teams', 'guid', 'phone', 'color', 'culture', 'tag', 'unitid', 'int', 'choice', 'list') { $ids.Add("gui.kind.$kind") }
    foreach ($step in 'check', 'copy', 'config', 'sign', 'catalog', 'pack', 'detection', 'rules', 'guide', 'finish') { $ids.Add("step.$step") }
    return , $ids.ToArray()
}

# All questions the window shows, by id: the answers, the unit questions (all six) and the build settings.
function Get-WizardGuiQuestionTable {
    $table = @{}
    foreach ($question in (Get-WizardQuestions)) { $table[$question.Id] = $question }
    $everyUnit = @{ UseGroupTags = $true; HybridJoin = $true; UseDeviceClass = $true }
    foreach ($question in (Get-WizardUnitQuestions -Answers $everyUnit)) { $table[$question.Id] = $question }
    foreach ($question in (Get-WizardTargetQuestions)) { $table[$question.Id] = $question }
    foreach ($question in $script:WizardGuiBuildQuestions) { $table[$question.Id] = $question }
    foreach ($question in $script:WizardGuiSigningQuestions) { $table[$question.Id] = $question }
    return $table
}

# ---------------------------------------------------------------- state of the window (no WPF here: tested by Test-SelfXWizardGui.ps1)

# Raw = typed values by question id (a missing id means: the default, exactly as a missing answer in an answer file). Units = raw values of the
# units. Targets = raw values of the own network targets. Build = the build settings.
function New-WizardGuiState {
    param([Parameter(Mandatory = $true)][string]$ToolsFolder, [string]$Culture = 'en')
    $defaults = Get-WizardBuildDefaults -ToolsFolder $ToolsFolder
    return [pscustomobject]@{
        Culture   = $Culture
        Raw       = @{}
        Units     = (New-Object System.Collections.Generic.List[hashtable])
        Targets   = (New-Object System.Collections.Generic.List[hashtable])
        Build     = @{ Payload = $defaults.PayloadFolder; Output = $defaults.OutputFolder; Tool = $defaults.ToolPath; ConfigureOnly = $false; PackageKind = 'Full' }
        Questions = (Get-WizardGuiQuestionTable)
        ToolsFolder = $ToolsFolder
        # Signature: Mode None | Store | File. The certificates are objects in memory (never saved); no password is kept anywhere.
        Signing   = @{ Mode = 'None'; Timestamp = ''; NoTimestamp = $false; Additional = '' }
        StoreCertificate = $null
        StoreList        = @()
        PfxCertificate   = $null
    }
}

# The certificate of the chosen mode, or $null (mode None, nothing selected or opened).
function Get-WizardGuiCertificate {
    param([Parameter(Mandatory = $true)]$State)
    switch ($State.Signing.Mode) {
        'Store' { return $State.StoreCertificate }
        'File' { return $State.PfxCertificate }
    }
    return $null
}

# The additional signers as a list (comma separated text, empty entries ignored).
function Get-WizardGuiAdditionalSigners {
    param([Parameter(Mandatory = $true)]$State)
    return , @("$($State.Signing.Additional)".Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# The values of the signature for Invoke-SelfXPackageBuild: certificate, time stamp service, additional signers.
function Get-WizardGuiSigning {
    param([Parameter(Mandatory = $true)]$State)
    $certificate = Get-WizardGuiCertificate -State $State
    if ($null -eq $certificate) { return [pscustomobject]@{ Certificate = $null; TimestampServer = ''; AdditionalSigner = @() } }
    return [pscustomobject]@{
        Certificate      = $certificate
        TimestampServer  = $(if ($State.Signing.NoTimestamp) { '' } else { "$($State.Signing.Timestamp)".Trim() })
        AdditionalSigner = (Get-WizardGuiAdditionalSigners -State $State)
    }
}

# Disposes the certificates of the window (store selection and PFX file).
function Clear-WizardGuiCertificates {
    param([Parameter(Mandatory = $true)]$State, [switch]$StoreOnly)
    if ($null -ne $State.StoreCertificate) { $State.StoreCertificate = $null }
    foreach ($certificate in @($State.StoreList)) { if ($null -ne $certificate) { $certificate.Dispose() } }
    $State | Add-Member -NotePropertyName StoreList -NotePropertyValue @() -Force
    if (-not $StoreOnly -and $null -ne $State.PfxCertificate) { $State.PfxCertificate.Dispose(); $State.PfxCertificate = $null }
}

function New-WizardGuiUnit {
    return @{ UnitId = ''; UnitMail = ''; UnitCc = ''; UnitGroupTags = ''; UnitOUs = ''; UnitCategories = '' }
}

# A new own network target with the values the questions start with.
function New-WizardGuiTarget {
    return @{ TargetLabel = ''; TargetHost = ''; TargetPort = '443'; TargetGroup = 'Company'; TargetKind = 'Vpn' }
}

# The text of a failed check, in the language of the window. The message of ConvertTo-WizardValue is English, so the window shows the text of
# the kind instead (same rule, own words).
function Get-WizardGuiErrorText {
    param([Parameter(Mandatory = $true)][hashtable]$Question)
    switch ($Question.Kind) {
        'text' { return (Get-WText 'gui.kind.text' @($Question.Max)) }
        'int' { return (Get-WText 'gui.kind.int' @($Question.Min, $Question.Max)) }
        'choice' { return (Get-WText 'gui.kind.choice' @((@($Question.Choices) -join ', '))) }
        default { return (Get-WText "gui.kind.$($Question.Kind)") }
    }
}

# Checks one raw value against its question like Get-WizardAnswer does (ConvertTo-WizardValue, then Required). Returns the error text or $null.
function Test-WizardGuiValue {
    param([Parameter(Mandatory = $true)][hashtable]$Question, [AllowNull()]$Value)
    $choices = if ($Question.Choices) { [string[]]$Question.Choices } else { @() }
    $min = if ($Question.Min) { [int]$Question.Min } else { 0 }
    $max = if ($Question.Max) { [int]$Question.Max } else { 0 }
    try { $normalized = ConvertTo-WizardValue -Kind $Question.Kind -Value $Value -Choices $choices -Min $min -Max $max }
    catch { return (Get-WizardGuiErrorText -Question $Question) }
    if ($Question.Required -and ($null -eq $normalized -or "$normalized" -eq '')) { return (Get-WText 'required') }
    return $null
}

# The value the window shows for a question: the typed value, else the default (a scriptblock default is computed from the answers so far).
function Get-WizardGuiShownValue {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Id, [hashtable]$Answers = @{})
    if ($State.Raw.ContainsKey($Id)) { return $State.Raw[$Id] }
    $default = $State.Questions[$Id].Default
    if ($default -is [scriptblock]) { $default = & $default $Answers }
    return $default
}

# Goes through the questions in the order of Read-WizardAnswers: which are shown (When), which have an error, the normalized answers so far.
# Units: an error list per unit, at least one unit when units are asked (as in the console), no id twice.
function Get-WizardGuiEvaluation {
    param([Parameter(Mandatory = $true)]$State)
    $answers = @{}
    $errors = @{}
    $visible = @{}
    foreach ($question in (Get-WizardQuestions)) {
        if ($question.When -and -not (& $question.When $answers)) { $visible[$question.Id] = $false; continue }
        $visible[$question.Id] = $true
        $raw = Get-WizardGuiShownValue -State $State -Id $question.Id -Answers $answers
        $problem = Test-WizardGuiValue -Question $question -Value $raw
        if ($null -ne $problem) { $errors[$question.Id] = $problem; continue }
        $choices = if ($question.Choices) { [string[]]$question.Choices } else { @() }
        $min = if ($question.Min) { [int]$question.Min } else { 0 }
        $max = if ($question.Max) { [int]$question.Max } else { 0 }
        $answers[$question.Id] = ConvertTo-WizardValue -Kind $question.Kind -Value $raw -Choices $choices -Min $min -Max $max
    }
    $unitsShown = [bool]($answers.TicketEnabled -and $answers.MultiOrg)
    # Get-WizardUnitQuestions returns one array (return , ...): not wrapped in @() again.
    $unitQuestions = Get-WizardUnitQuestions -Answers $answers
    $unitErrors = New-Object System.Collections.Generic.List[hashtable]
    $unitsError = $null
    if ($unitsShown) {
        $ids = @{}
        foreach ($unit in $State.Units) {
            $problems = @{}
            foreach ($question in $unitQuestions) {
                $problem = Test-WizardGuiValue -Question $question -Value $unit[$question.Id]
                if ($null -ne $problem) { $problems[$question.Id] = $problem; continue }
                if ($question.Kind -eq 'list') {
                    $items = ConvertTo-WizardValue -Kind 'list' -Value $unit[$question.Id]
                    $probe = [pscustomobject]@{ GroupTags = @(); OUs = @(); Categories = @() }
                    $probe.($question.Id.Substring(4)) = @($items)
                    try { Test-WizardUnitValues -Unit $probe } catch { $problems[$question.Id] = (Get-WText 'gui.unit.invalid' @((Get-WText "$($question.Id).rec"))) }
                }
            }
            $key = "$($unit.UnitId)".Trim().ToLowerInvariant()
            if ($key -and $ids.ContainsKey($key)) { $problems['UnitId'] = (Get-WText 'gui.units.duplicate') }
            if ($key) { $ids[$key] = $true }
            $unitErrors.Add($problems)
        }
        if ($State.Units.Count -eq 0) { $unitsError = (Get-WText 'gui.units.empty') }
    }
    # Own network targets: an error list per target (field by field, then the whole target as Set-SelfXNetworkTestConfig takes it), no label
    # twice, at most NetMaxTargets (the delivered Microsoft targets in the file count too).
    $targetsShown = [bool]$answers.NetworkEnabled
    $targetErrors = New-Object System.Collections.Generic.List[hashtable]
    $targetsError = $null
    $targetQuestions = Get-WizardTargetQuestions
    if ($targetsShown) {
        $labels = @{}
        foreach ($target in $State.Targets) {
            $problems = @{}
            $isCompany = ("$($target.TargetGroup)" -ieq 'Company')
            foreach ($question in $targetQuestions) {
                if ($question.Id -eq 'TargetKind' -and -not $isCompany) { continue }
                $problem = Test-WizardGuiValue -Question $question -Value $target[$question.Id]
                if ($null -ne $problem) { $problems[$question.Id] = $problem }
            }
            if ($problems.Count -eq 0) {
                try { $null = ConvertTo-WizardValue -Kind 'netTarget' -Value ([pscustomobject]@{ Label = $target.TargetLabel; Host = $target.TargetHost; Port = $target.TargetPort; Group = $target.TargetGroup; Kind = $(if ($isCompany) { $target.TargetKind } else { '' }) }) }
                catch {
                    $field = switch -Regex ($_.Exception.Message) { '^label' { 'TargetLabel' } '^(host|an IPv4)' { 'TargetHost' } '^port' { 'TargetPort' } '^group' { 'TargetGroup' } default { 'TargetKind' } }
                    $problems[$field] = (Get-WText 'gui.target.invalid' @((Get-WText "$field.rec")))
                }
            }
            $key = "$($target.TargetLabel)".Trim().ToLowerInvariant()
            if ($key -and $labels.ContainsKey($key)) { $problems['TargetLabel'] = (Get-WText 'gui.targets.duplicate') }
            if ($key) { $labels[$key] = $true }
            $targetErrors.Add($problems)
        }
        if ($State.Targets.Count -gt $script:NetMaxOwnTargets) { $targetsError = (Get-WText 'gui.targets.max' @($script:NetMaxOwnTargets)) }
    }
    $buildErrors = @{}
    $buildVisible = @{}
    foreach ($question in $script:WizardGuiBuildQuestions) {
        if ($question.When -and -not (& $question.When $State.Build $answers)) { $buildVisible[$question.Id] = $false; continue }
        $buildVisible[$question.Id] = $true
        $problem = Test-WizardGuiValue -Question $question -Value $State.Build[$question.Id]
        if ($null -ne $problem) { $buildErrors[$question.Id] = $problem }
    }
    if (-not $buildErrors.ContainsKey('Payload') -and -not (Test-Path -LiteralPath $State.Build.Payload -PathType Container)) { $buildErrors['Payload'] = (Get-WText 'Payload.missing') }
    # Signature: a certificate for the mode, a time stamp service (or the switch without), valid additional signers.
    $signingErrors = @{}
    $signing = $State.Signing
    if ($signing.Mode -ne 'None') {
        if ($null -eq (Get-WizardGuiCertificate -State $State)) { $signingErrors[$signing.Mode] = (Get-WText $(if ($signing.Mode -eq 'Store') { 'gui.sign.store.none' } else { 'gui.sign.file.notloaded' })) }
        if (-not $signing.NoTimestamp -and -not (Test-SelfXTimestampUrl "$($signing.Timestamp)".Trim())) { $signingErrors['Timestamp'] = (Get-WText 'gui.kind.timestamp') }
        $additional = Get-WizardGuiAdditionalSigners -State $State
        $badAdditional = ($additional.Count -gt 9) -or "$($signing.Additional)".Length -gt 500 -or (@($additional | Where-Object { $_ -notmatch '^[0-9A-Fa-f]{40}\z' }).Count -gt 0)
        if ($badAdditional) { $signingErrors['Additional'] = (Get-WText 'gui.sign.additional.invalid') }
        if ($State.Build.ConfigureOnly -and -not $buildErrors.ContainsKey('ConfigureOnly')) { $buildErrors['ConfigureOnly'] = (Get-WText 'gui.sign.configureonly') }
    }
    return [pscustomobject]@{
        Answers       = $answers
        Errors        = $errors
        Visible       = $visible
        UnitsShown    = $unitsShown
        UnitQuestions = @($unitQuestions | ForEach-Object { $_.Id })
        UnitErrors    = $unitErrors
        UnitsError    = $unitsError
        TargetsShown  = $targetsShown
        TargetQuestions = @($targetQuestions | ForEach-Object { $_.Id })
        TargetErrors  = $targetErrors
        TargetsError  = $targetsError
        BuildErrors   = $buildErrors
        BuildVisible  = $buildVisible
        SigningErrors = $signingErrors
    }
}

# Errors of one page as a list of ids ('Units' for the unit list, 'Unit<n>' for a unit, build setting ids). Empty = the page may be left.
function Get-WizardGuiPageErrors {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$PageId, $Evaluation, [hashtable]$ExtraErrors = @{})
    if ($null -eq $Evaluation) { $Evaluation = Get-WizardGuiEvaluation -State $State }
    $page = @($script:WizardGuiPages | Where-Object { $_.Id -eq $PageId })[0]
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($id in $page.Questions) { if ($Evaluation.Visible[$id] -and ($Evaluation.Errors.ContainsKey($id) -or $ExtraErrors.ContainsKey($id))) { $list.Add($id) } }
    if ($PageId -eq 'ticket' -and $Evaluation.UnitsShown) {
        if ($Evaluation.UnitsError) { $list.Add('Units') }
        for ($i = 0; $i -lt $Evaluation.UnitErrors.Count; $i++) { if ($Evaluation.UnitErrors[$i].Count -gt 0) { $list.Add("Unit$i") } }
    }
    if ($PageId -eq 'network' -and $Evaluation.TargetsShown) {
        if ($Evaluation.TargetsError) { $list.Add('Targets') }
        for ($i = 0; $i -lt $Evaluation.TargetErrors.Count; $i++) { if ($Evaluation.TargetErrors[$i].Count -gt 0) { $list.Add("Target$i") } }
    }
    if ($PageId -eq 'signing') { foreach ($id in $Evaluation.SigningErrors.Keys) { $list.Add($id) } }
    if ($PageId -eq 'summary') { foreach ($id in $Evaluation.BuildErrors.Keys) { $list.Add($id) } }
    return , $list.ToArray()
}

# The answers in the shape of an answer file (selfx-answers.json): only typed values; the units with their raw values.
function Get-WizardGuiSource {
    param([Parameter(Mandatory = $true)]$State)
    $source = @{}
    foreach ($key in $State.Raw.Keys) { $source[$key] = $State.Raw[$key] }
    $source['Units'] = @($State.Units | ForEach-Object { [pscustomobject]@{ UnitId = $_.UnitId; UnitMail = $_.UnitMail; UnitCc = $_.UnitCc; UnitGroupTags = $_.UnitGroupTags; UnitOUs = $_.UnitOUs; UnitCategories = $_.UnitCategories } })
    # Own targets only with the measurement switched on (an answer file with targets and the measurement off is refused).
    $enabled = $false
    if ($State.Raw.ContainsKey('NetworkEnabled')) {
        # A value that is not yes or no is reported by the check of NetworkEnabled itself.
        try { $enabled = [bool](ConvertTo-WizardValue -Kind 'bool' -Value $State.Raw['NetworkEnabled']) } catch { $enabled = $false }
    }
    if ($enabled) {
        $source['NetworkTargets'] = @($State.Targets | ForEach-Object {
                [pscustomobject]@{ Label = $_.TargetLabel; Host = $_.TargetHost; Port = $_.TargetPort; Group = $_.TargetGroup; Kind = $(if ("$($_.TargetGroup)" -ieq 'Company') { $_.TargetKind } else { '' }) }
            })
    }
    return $source
}

# The normalized answers, exactly as the console makes them from an answer file. Throws the message of the check when an answer is not valid.
function Get-WizardGuiAnswers {
    param([Parameter(Mandatory = $true)]$State)
    return (Test-WizardAnswerSet -Answers (Get-WizardGuiSource -State $State))
}

# Loads selfx-answers.json into the state (as the console reads it: unknown answers refused). Values are kept as typed; they are checked like
# typed values. Returns the language of the file (WizardLanguage) or ''.
function Import-WizardGuiAnswers {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or $item.Length -gt 1MB) { throw 'The answer file must be a JSON file of at most 1 MB.' }
    $json = [IO.File]::ReadAllText($item.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($null -eq $json -or $json -isnot [psobject]) { throw 'The answer file is not a JSON object.' }
    $known = @((Get-WizardQuestions) | ForEach-Object { $_.Id }) + @('Units', 'NetworkTargets', 'WizardLanguage')
    foreach ($property in $json.PSObject.Properties) { if ($known -notcontains $property.Name) { throw "Unknown answer '$($property.Name)' in the answer file." } }
    $raw = @{}
    $units = New-Object System.Collections.Generic.List[hashtable]
    $targets = New-Object System.Collections.Generic.List[hashtable]
    $language = ''
    $join = { param($v) if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) { (@($v | ForEach-Object { "$_" }) -join ', ') } elseif ($null -eq $v) { '' } else { "$v" } }
    foreach ($property in $json.PSObject.Properties) {
        if ($property.Name -eq 'WizardLanguage') { $language = "$($property.Value)"; continue }
        if ($property.Name -eq 'Units') {
            foreach ($entry in @($property.Value)) {
                if ($null -eq $entry) { continue }
                $unit = New-WizardGuiUnit
                foreach ($name in @($unit.Keys)) { if ($null -ne $entry.PSObject.Properties[$name]) { $unit[$name] = & $join $entry.$name } }
                $units.Add($unit)
            }
            continue
        }
        if ($property.Name -eq 'NetworkTargets') {
            foreach ($entry in @($property.Value)) {
                if ($null -eq $entry) { continue }
                $target = New-WizardGuiTarget
                foreach ($pair in @(@('TargetLabel', 'Label'), @('TargetHost', 'Host'), @('TargetPort', 'Port'), @('TargetGroup', 'Group'), @('TargetKind', 'Kind'))) {
                    if ($null -ne $entry.PSObject.Properties[$pair[1]]) { $target[$pair[0]] = & $join $entry.($pair[1]) }
                }
                if ($target.TargetKind -eq '') { $target.TargetKind = 'None' }
                $targets.Add($target)
            }
            continue
        }
        $value = $property.Value
        if ($value -is [bool]) { $raw[$property.Name] = $value } else { $raw[$property.Name] = & $join $value }
    }
    $State.Raw = $raw
    $State.Units = $units
    $State.Targets = $targets
    return $language
}

# ---------------------------------------------------------------- window

# The XAML of the window with the shared styles of Self_X.ps1 in place of the marker. The styles text is a constant of the SelfX code.
function Get-WizardGuiXaml {
    $xaml = [IO.File]::ReadAllText((Join-Path $script:GuiFolder 'SelfXWizardGui.xaml'), [Text.Encoding]::UTF8)
    $marker = '<!--SELFX-SHARED-STYLES-->'
    if (([regex]::Matches($xaml, [regex]::Escape($marker))).Count -ne 1) { throw 'SelfXWizardGui.xaml must contain the marker of the shared styles once.' }
    $styles = Get-WizardGuiSharedStyles -SelfXScript (Join-Path $script:GuiCodeFolder 'Self_X.ps1')
    return $xaml.Replace($marker, $styles)
}

# Light or dark as the app mode of Windows (Settings > Personalization > Colors); without the value Windows uses light.
function Get-WizardGuiTheme {
    $value = $null
    try { $value = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop).AppsUseLightTheme } catch { $value = $null }
    if ("$value" -eq '0') { return 'Dark' }
    return 'Light'
}

# Colors of the window: the theme of Windows and the company color when it is valid (else the SelfX blue of the delivered configuration).
function Set-WizardGuiColors {
    param([Parameter(Mandatory = $true)]$Window, [string]$AccentColor, [string]$Theme)
    if (-not $Theme) { $Theme = Get-WizardGuiTheme }
    $accent = ConvertTo-SelfXColor $AccentColor
    if ($null -eq $accent) { $accent = ConvertTo-SelfXColor '#0072BC' }
    $colors = New-SelfXThemeColors -Theme $Theme -Accent $accent
    Set-SelfXThemeResources -Dictionary $Window.Resources -Colors $colors
}

function New-WizardGuiTextBlock {
    param([string]$Style)
    $block = New-Object System.Windows.Controls.TextBlock
    if ($Style) { $block.Style = $script:Gui.Window.FindResource($Style) }
    return $block
}

# One input row: label, recommendation, input (switch, list or text field with an optional browse button) and the error line below.
function New-WizardGuiFieldRow {
    param([Parameter(Mandatory = $true)][hashtable]$Question, [Parameter(Mandatory = $true)][string]$Scope)
    $window = $script:Gui.Window
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 18)
    $label = New-WizardGuiTextBlock 'FieldLabel'
    $hint = New-WizardGuiTextBlock 'FieldHint'
    $errorLine = New-WizardGuiTextBlock 'FieldError'
    $browse = $null
    if ($Question.Kind -eq 'bool') {
        $control = New-Object System.Windows.Controls.CheckBox
        $control.Style = $window.FindResource('Switch')
        $control.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $label.Visibility = 'Collapsed'
        $null = $row.Children.Add($control)
        $null = $row.Children.Add($hint)
        $hint.Margin = [System.Windows.Thickness]::new(50, 0, 0, 0)
    }
    else {
        $null = $row.Children.Add($label)
        $null = $row.Children.Add($hint)
        if ($Question.Kind -eq 'choice' -or $Question.Kind -eq 'culture') {
            $control = New-Object System.Windows.Controls.ComboBox
            $control.Style = $window.FindResource('FieldCombo')
            $items = if ($Question.Kind -eq 'culture') { $script:Gui.ToolCultures } else { @($Question.Choices) }
            foreach ($item in $items) { $null = $control.Items.Add([string]$item) }
            $null = $row.Children.Add($control)
        }
        else {
            $control = New-Object System.Windows.Controls.TextBox
            $control.Style = $window.FindResource('FieldBox')
            $control.MaxLength = $(if ($Question.Max) { [int]$Question.Max + 10 } else { 520 })
            if ($Question.Browse -or $Question.Id -eq 'LogoPath') {
                $dock = New-Object System.Windows.Controls.DockPanel
                $browse = New-Object System.Windows.Controls.Button
                $browse.Style = $window.FindResource('BaseButton')
                $browse.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                [System.Windows.Controls.DockPanel]::SetDock($browse, 'Right')
                $null = $dock.Children.Add($browse)
                $null = $dock.Children.Add($control)
                $null = $row.Children.Add($dock)
            }
            else { $null = $row.Children.Add($control) }
        }
    }
    $null = $row.Children.Add($errorLine)
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($control, "Field_$($Question.Id)")
    [System.Windows.Automation.AutomationProperties]::SetLabeledBy($control, $label)
    if ($Question.Required) { [System.Windows.Automation.AutomationProperties]::SetIsRequiredForForm($control, $true) }
    return [pscustomobject]@{ Id = $Question.Id; Question = $Question; Scope = $Scope; Row = $row; Label = $label; Hint = $hint; Control = $control; Error = $errorLine; Browse = $browse }
}

# Puts a value into a control without running the change handler (the handler stores typed values only).
function Set-WizardGuiControlValue {
    param($Field, $Value)
    $script:Gui.Loading = $true
    try {
        $control = $Field.Control
        if ($control -is [System.Windows.Controls.CheckBox]) { $control.IsChecked = [bool]$Value }
        elseif ($control -is [System.Windows.Controls.ComboBox]) {
            $text = "$Value"
            $match = $null
            foreach ($item in $control.Items) { if ("$item" -ieq $text) { $match = $item } }
            if ($null -eq $match -and $text) { $null = $control.Items.Add($text); $match = $text }
            $control.SelectedItem = $match
        }
        else { $control.Text = "$Value" }
    }
    finally { $script:Gui.Loading = $false }
}

function Get-WizardGuiControlValue {
    param($Field)
    $control = $Field.Control
    if ($control -is [System.Windows.Controls.CheckBox]) { return [bool]$control.IsChecked }
    if ($control -is [System.Windows.Controls.ComboBox]) { return "$($control.SelectedItem)" }
    return $control.Text
}

function Set-WizardGuiFieldError {
    param($Field, [string]$Message)
    $hasError = [bool]$Message
    $Field.Error.Text = $Message
    $Field.Error.Visibility = $(if ($hasError) { 'Visible' } else { 'Collapsed' })
    if ($Field.Control -is [System.Windows.Controls.TextBox]) { $Field.Control.Tag = $(if ($hasError) { 'Error' } else { $null }) }
    $help = $(if ($hasError) { "$Message $($Field.Hint.Text)" } else { $Field.Hint.Text })
    [System.Windows.Automation.AutomationProperties]::SetHelpText($Field.Control, $help)
}

# Logo preview: the file is checked by Read-WizardLogo (the same rule as the build) and shown from the checked bytes. Returns an error text.
function Update-WizardGuiLogo {
    $ui = $script:Gui.Ui
    $path = "$($script:Gui.State.Raw['LogoPath'])".Trim()
    # The file is read again only when the path changed.
    if ($null -ne $script:Gui.LogoChecked -and $script:Gui.LogoChecked.Path -eq $path) { return $script:Gui.LogoChecked.Error }
    $script:Gui.LogoChecked = [pscustomobject]@{ Path = $path; Error = $null }
    $ui.LogoPreview.Source = $null
    if (-not $path) { $ui.LogoPreviewText.Text = (Get-WText 'gui.logo.none'); $ui.LogoPreviewText.Visibility = 'Visible'; return $null }
    try {
        $logo = Read-WizardLogo -LogoPath $path
        $stream = New-Object System.IO.MemoryStream(, $logo.Bytes)
        $image = New-Object System.Windows.Media.Imaging.BitmapImage
        $image.BeginInit()
        $image.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $image.StreamSource = $stream
        $image.EndInit()
        $image.Freeze()
        $stream.Dispose()
        $ui.LogoPreview.Source = $image
        $ui.LogoPreviewText.Visibility = 'Collapsed'
        return $null
    }
    catch {
        $ui.LogoPreviewText.Text = (Get-WText 'gui.logo.none')
        $ui.LogoPreviewText.Visibility = 'Visible'
        $script:Gui.LogoChecked.Error = (Get-WText 'gui.logo.invalid')
        return $script:Gui.LogoChecked.Error
    }
}

# Shows the result of the checks: errors at the fields, which questions are shown, the unit list. Only typed fields show an error until
# the user tries to leave the page (then all errors of the page are shown).
function Update-WizardGuiView {
    param([switch]$ShowAll)
    $state = $script:Gui.State
    $ui = $script:Gui.Ui
    $evaluation = Get-WizardGuiEvaluation -State $state
    $script:Gui.Evaluation = $evaluation
    $script:Gui.Extra = @{}
    $logoError = Update-WizardGuiLogo
    if ($logoError) { $script:Gui.Extra['LogoPath'] = $logoError }
    foreach ($field in $script:Gui.Fields.Values) {
        if ($field.Scope -eq 'answer') {
            # A field without a typed value shows its default, which can follow other answers (the ticket recipient follows the support address).
            if (-not $state.Raw.ContainsKey($field.Id)) {
                $default = Get-WizardGuiShownValue -State $state -Id $field.Id -Answers $evaluation.Answers
                if ("$(Get-WizardGuiControlValue -Field $field)" -ne "$default") { Set-WizardGuiControlValue -Field $field -Value $default }
            }
            $shown = [bool]$evaluation.Visible[$field.Id]
            $message = $evaluation.Errors[$field.Id]
            if (-not $message) { $message = $script:Gui.Extra[$field.Id] }
            $touched = $state.Raw.ContainsKey($field.Id) -or $script:Gui.ShowAll.Contains($field.Id)
        }
        elseif ($field.Scope -eq 'build') {
            $shown = [bool]$evaluation.BuildVisible[$field.Id]
            $message = $evaluation.BuildErrors[$field.Id]
            $touched = $true
        }
        elseif ($field.Scope -eq 'signing') {
            $shown = $true
            $message = $evaluation.SigningErrors[$field.Id]
            $touched = ($field.Id -ne 'Timestamp') -or "$($state.Signing.Timestamp)" -ne '' -or $script:Gui.ShowAll.Contains('Timestamp')
            if ($field.Id -eq 'Timestamp') { $field.Control.IsEnabled = -not $state.Signing.NoTimestamp }
        }
        else { continue }
        $field.Row.Visibility = $(if ($shown) { 'Visible' } else { 'Collapsed' })
        Set-WizardGuiFieldError -Field $field -Message $(if ($touched) { $message } else { $null })
    }
    # Units
    $ui.UnitsPanel.Visibility = $(if ($evaluation.UnitsShown) { 'Visible' } else { 'Collapsed' })
    $ui.UnitsError.Text = "$($evaluation.UnitsError)"
    $ui.UnitsError.Visibility = $(if ($evaluation.UnitsError -and $script:Gui.ShowAll.Contains('Units')) { 'Visible' } else { 'Collapsed' })
    $selected = $ui.UnitList.SelectedIndex
    $script:Gui.Loading = $true
    try {
        $ui.UnitList.Items.Clear()
        for ($i = 0; $i -lt $state.Units.Count; $i++) {
            $unit = $state.Units[$i]
            $name = $(if ("$($unit.UnitId)".Trim()) { "$($unit.UnitId)".Trim() } else { Get-WText 'gui.unit.new' })
            $mark = $(if ($i -lt $evaluation.UnitErrors.Count -and $evaluation.UnitErrors[$i].Count -gt 0) { '  !' } else { '' })
            $text = "$name  -  $("$($unit.UnitMail)".Trim())$mark"
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = $text
            [System.Windows.Automation.AutomationProperties]::SetName($item, $text)
            $null = $ui.UnitList.Items.Add($item)
        }
        if ($selected -ge $state.Units.Count) { $selected = $state.Units.Count - 1 }
        $ui.UnitList.SelectedIndex = $selected
    }
    finally { $script:Gui.Loading = $false }
    $ui.RemoveUnitButton.IsEnabled = ($ui.UnitList.SelectedIndex -ge 0)
    $ui.UnitEditor.Visibility = $(if ($ui.UnitList.SelectedIndex -ge 0) { 'Visible' } else { 'Collapsed' })
    $index = $ui.UnitList.SelectedIndex
    foreach ($field in @($script:Gui.Fields.Values | Where-Object { $_.Scope -eq 'unit' })) {
        $field.Row.Visibility = $(if ($evaluation.UnitQuestions -contains $field.Id) { 'Visible' } else { 'Collapsed' })
        $message = $null
        if ($index -ge 0 -and $index -lt $evaluation.UnitErrors.Count) { $message = $evaluation.UnitErrors[$index][$field.Id] }
        $touched = $script:Gui.ShowAll.Contains("Unit$index") -or ($index -ge 0 -and "$($state.Units[$index][$field.Id])" -ne '')
        Set-WizardGuiFieldError -Field $field -Message $(if ($touched) { $message } else { $null })
    }
    # Network targets
    $ui.TargetsPanel.Visibility = $(if ($evaluation.TargetsShown) { 'Visible' } else { 'Collapsed' })
    $ui.TargetsError.Text = "$($evaluation.TargetsError)"
    $ui.TargetsError.Visibility = $(if ($evaluation.TargetsError -and $script:Gui.ShowAll.Contains('Targets')) { 'Visible' } else { 'Collapsed' })
    $selectedTarget = $ui.TargetList.SelectedIndex
    $script:Gui.Loading = $true
    try {
        $ui.TargetList.Items.Clear()
        for ($i = 0; $i -lt $state.Targets.Count; $i++) {
            $target = $state.Targets[$i]
            $name = $(if ("$($target.TargetLabel)".Trim()) { "$($target.TargetLabel)".Trim() } else { Get-WText 'gui.target.new' })
            $mark = $(if ($i -lt $evaluation.TargetErrors.Count -and $evaluation.TargetErrors[$i].Count -gt 0) { '  !' } else { '' })
            $text = "$name  -  $("$($target.TargetHost)".Trim()):$("$($target.TargetPort)".Trim())  ($("$($target.TargetGroup)"))$mark"
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = $text
            [System.Windows.Automation.AutomationProperties]::SetName($item, $text)
            $null = $ui.TargetList.Items.Add($item)
        }
        if ($selectedTarget -ge $state.Targets.Count) { $selectedTarget = $state.Targets.Count - 1 }
        $ui.TargetList.SelectedIndex = $selectedTarget
    }
    finally { $script:Gui.Loading = $false }
    $ui.RemoveTargetButton.IsEnabled = ($ui.TargetList.SelectedIndex -ge 0)
    $ui.AddTargetButton.IsEnabled = ($state.Targets.Count -lt $script:NetMaxOwnTargets)
    $ui.TargetEditor.Visibility = $(if ($ui.TargetList.SelectedIndex -ge 0) { 'Visible' } else { 'Collapsed' })
    $targetIndex = $ui.TargetList.SelectedIndex
    foreach ($field in @($script:Gui.Fields.Values | Where-Object { $_.Scope -eq 'target' })) {
        $shownGroup = $(if ($targetIndex -ge 0 -and $targetIndex -lt $state.Targets.Count) { "$($state.Targets[$targetIndex].TargetGroup)" } else { '' })
        $field.Row.Visibility = $(if ($field.Id -eq 'TargetKind' -and $shownGroup -ine 'Company') { 'Collapsed' } else { 'Visible' })
        $message = $null
        if ($targetIndex -ge 0 -and $targetIndex -lt $evaluation.TargetErrors.Count) { $message = $evaluation.TargetErrors[$targetIndex][$field.Id] }
        $touched = $script:Gui.ShowAll.Contains("Target$targetIndex") -or ($targetIndex -ge 0 -and "$($state.Targets[$targetIndex][$field.Id])" -ne '' -and $field.Id -ne 'TargetPort' -and $field.Id -ne 'TargetGroup' -and $field.Id -ne 'TargetKind') -or ($targetIndex -ge 0 -and $field.Id -in @('TargetPort', 'TargetGroup', 'TargetKind') -and $message)
        Set-WizardGuiFieldError -Field $field -Message $(if ($touched) { $message } else { $null })
    }
    # Company color shown at once when it is valid.
    $accent = $(if ($evaluation.Errors.ContainsKey('AccentColor')) { '' } else { "$($evaluation.Answers['AccentColor'])" })
    if ($accent -ne $script:Gui.AppliedAccent) { Set-WizardGuiColors -Window $script:Gui.Window -AccentColor $accent -Theme $script:Gui.Theme; $script:Gui.AppliedAccent = $accent }
    Update-WizardGuiSigningView -Evaluation $evaluation
    $ui.SaveButton.IsEnabled = ($script:Gui.Page -lt (Get-WizardGuiPageIndex 'build'))
}

# Page signing: the panel of the mode, the list of the store, the state of the PFX file and the details of the chosen certificate.
function Update-WizardGuiSigningView {
    param($Evaluation)
    $ui = $script:Gui.Ui
    $state = $script:Gui.State
    $mode = $state.Signing.Mode
    $ui.SignNoneInfo.Visibility = $(if ($mode -eq 'None') { 'Visible' } else { 'Collapsed' })
    $ui.SignStorePanel.Visibility = $(if ($mode -eq 'Store') { 'Visible' } else { 'Collapsed' })
    $ui.SignFilePanel.Visibility = $(if ($mode -eq 'File') { 'Visible' } else { 'Collapsed' })
    $ui.SignDetailsPanel.Visibility = $(if ($mode -ne 'None') { 'Visible' } else { 'Collapsed' })
    $storeError = $Evaluation.SigningErrors['Store']
    $ui.CertListError.Text = "$storeError"
    $ui.CertListError.Visibility = $(if ($storeError -and $script:Gui.ShowAll.Contains('Store')) { 'Visible' } else { 'Collapsed' })
    $fileError = $Evaluation.SigningErrors['File']
    if ($fileError -and $script:Gui.ShowAll.Contains('File') -and -not $script:Gui.PfxMessage) { $ui.PfxError.Text = "$fileError"; $ui.PfxError.Visibility = 'Visible' }
    elseif (-not $script:Gui.PfxMessage) { $ui.PfxError.Visibility = 'Collapsed' }
    $certificate = Get-WizardGuiCertificate -State $state
    $ui.CertDetailsTitle.Visibility = $(if ($null -ne $certificate) { 'Visible' } else { 'Collapsed' })
    $ui.CertCard.Visibility = $(if ($null -ne $certificate) { 'Visible' } else { 'Collapsed' })
    if ($null -eq $certificate) { return }
    if ($null -eq $script:Gui.CertInfo -or $script:Gui.CertInfo.Thumbprint -ne $certificate.Thumbprint) { $script:Gui.CertInfo = Get-WizardCertificateInfo -Certificate $certificate }
    $info = $script:Gui.CertInfo
    $ui.CertSubject.Text = (Get-WText 'gui.sign.subject' @($info.Subject))
    $ui.CertIssuer.Text = (Get-WText 'gui.sign.issuer' @($info.Issuer))
    $ui.CertValid.Text = (Get-WText 'gui.sign.valid' @($info.NotAfter.ToString('d', [Globalization.CultureInfo]::CurrentCulture)))
    $ui.CertThumbprint.Text = (Get-WText 'gui.sign.thumbprint' @($info.Thumbprint))
    $ui.CertCrl.Text = (Get-WText 'gui.sign.crl' @($(if ($info.CrlUrls.Count) { $info.CrlUrls -join ', ' } else { '-' })))
    $ui.CertCrlWarning.Text = ((@($info.Warnings) | ForEach-Object { Get-WText $_ }) -join ' ')
    $ui.CertCrlWarningBox.Visibility = $(if ($info.Warnings.Count) { 'Visible' } else { 'Collapsed' })
}

# Fills the list of suitable certificates of the stores (Get-SelfXSigningCertificate: private key, Code Signing, valid period). The objects of
# the previous list are disposed.
function Update-WizardGuiCertificateList {
    $ui = $script:Gui.Ui
    $state = $script:Gui.State
    $selected = $(if ($null -ne $state.StoreCertificate) { $state.StoreCertificate.Thumbprint } else { '' })
    Clear-WizardGuiCertificates -State $state -StoreOnly
    $list = @(Get-SelfXSigningCertificate)
    $state.StoreList = $list
    $script:Gui.Loading = $true
    try {
        $ui.CertList.Items.Clear()
        foreach ($certificate in $list) {
            $item = New-Object System.Windows.Controls.ListBoxItem
            $text = '{0}{1}{2}  |  {3}  |  {4}' -f $certificate.Subject, [Environment]::NewLine, $certificate.Issuer, $certificate.NotAfter.ToString('d', [Globalization.CultureInfo]::CurrentCulture), $certificate.Thumbprint
            $block = New-Object System.Windows.Controls.TextBlock
            $block.Text = $text
            $block.TextWrapping = 'Wrap'
            $item.Content = $block
            $item.Tag = $certificate.Thumbprint
            [System.Windows.Automation.AutomationProperties]::SetName($item, $text.Replace([Environment]::NewLine, ', '))
            $null = $ui.CertList.Items.Add($item)
            if ($certificate.Thumbprint -eq $selected) { $ui.CertList.SelectedItem = $item; $state.StoreCertificate = $certificate }
        }
    }
    finally { $script:Gui.Loading = $false }
    $ui.CertListEmpty.Visibility = $(if ($list.Count -eq 0) { 'Visible' } else { 'Collapsed' })
}

# Opens the PFX file with the password of the password box. The password is a SecureString copy of the box (never the property Password),
# disposed afterwards; the box is emptied in every case. Messages contain no password (Get-SelfXSigningCertificate guarantees that).
function Open-WizardGuiPfx {
    $ui = $script:Gui.Ui
    $state = $script:Gui.State
    $script:Gui.PfxMessage = $true
    $secure = $ui.PfxPasswordBox.SecurePassword
    try {
        if ($null -ne $state.PfxCertificate) { $state.PfxCertificate.Dispose(); $state.PfxCertificate = $null }
        $path = "$($ui.PfxPathBox.Text)".Trim()
        $state.PfxCertificate = Get-SelfXSigningCertificate -PfxPath $path -PfxPassword $secure
        $ui.PfxStatus.Text = (Get-WText 'gui.sign.file.loaded')
        $ui.PfxStatus.Visibility = 'Visible'
        $ui.PfxError.Visibility = 'Collapsed'
    }
    catch {
        $ui.PfxStatus.Visibility = 'Collapsed'
        $ui.PfxError.Text = (Get-WText 'gui.sign.file.failed' @((ConvertTo-SelfXSafeText $_.Exception.Message)))
        $ui.PfxError.Visibility = 'Visible'
    }
    finally {
        $secure.Dispose()
        $ui.PfxPasswordBox.Clear()
        $script:Gui.CertInfo = $null
    }
    Update-WizardGuiView
}

# Button text with an access key (_ before the letter). The button template of Self_X.ps1 does not read access keys from text, so the text is an
# AccessText element; the name for screen readers is the text without the underscore.
function Set-WizardGuiButtonText {
    param([Parameter(Mandatory = $true)]$Button, [Parameter(Mandatory = $true)][string]$Text)
    $access = New-Object System.Windows.Controls.AccessText
    $access.Text = $Text
    $Button.Content = $access
    [System.Windows.Automation.AutomationProperties]::SetName($Button, $Text.Replace('_', ''))
}

# Writes all texts of the current language into the window (also after a change of the language).
function Set-WizardGuiTexts {
    $ui = $script:Gui.Ui
    $window = $script:Gui.Window
    $window.Title = (Get-WText 'title')
    $ui.AppTitle.Text = (Get-WText 'title')
    Set-WizardGuiButtonText -Button $ui.BackButton -Text (Get-WText 'gui.back')
    Set-WizardGuiButtonText -Button $ui.LoadButton -Text (Get-WText 'gui.load')
    Set-WizardGuiButtonText -Button $ui.SaveButton -Text (Get-WText 'gui.save')
    $ui.WizardLanguageLabel.Text = (Get-WText 'gui.wizardLanguage.ask')
    $ui.WizardLanguageHint.Text = (Get-WText 'gui.wizardLanguage.rec')
    [System.Windows.Automation.AutomationProperties]::SetName($ui.WizardLanguageBox, $ui.WizardLanguageLabel.Text)
    [System.Windows.Automation.AutomationProperties]::SetHelpText($ui.WizardLanguageBox, $ui.WizardLanguageHint.Text)
    $ui.PreviewTitle.Text = (Get-WText 'gui.preview')
    $ui.AccentSample.Content = (Get-WText 'gui.accent.sample')
    $ui.AccentSampleLink.Text = (Get-WText 'gui.accent.link')
    $ui.UnitsTitle.Text = (Get-WText 'gui.units.title')
    $ui.UnitsHint.Text = (Get-WText 'gui.units.rec')
    Set-WizardGuiButtonText -Button $ui.AddUnitButton -Text (Get-WText 'gui.units.add')
    Set-WizardGuiButtonText -Button $ui.RemoveUnitButton -Text (Get-WText 'gui.units.remove')
    $ui.UnitEditorTitle.Text = (Get-WText 'gui.unit.title')
    $ui.TargetsTitle.Text = (Get-WText 'gui.targets.title')
    $ui.TargetsHint.Text = (Get-WText 'gui.targets.rec')
    Set-WizardGuiButtonText -Button $ui.AddTargetButton -Text (Get-WText 'gui.targets.add')
    Set-WizardGuiButtonText -Button $ui.RemoveTargetButton -Text (Get-WText 'gui.targets.remove')
    $ui.TargetEditorTitle.Text = (Get-WText 'gui.target.title')
    [System.Windows.Automation.AutomationProperties]::SetName($ui.TargetList, $ui.TargetsTitle.Text)
    [System.Windows.Automation.AutomationProperties]::SetName($ui.UnitList, $ui.UnitsTitle.Text)
    $ui.SummaryTitle.Text = (Get-WText 'gui.summary.title')
    [System.Windows.Automation.AutomationProperties]::SetName($ui.SummaryBox, $ui.SummaryTitle.Text)
    $ui.BuildSettingsTitle.Text = (Get-WText 'gui.summary.build')
    Set-WizardGuiButtonText -Button $ui.BuildButton -Text (Get-WText 'gui.build.start')
    Set-WizardGuiButtonText -Button $ui.CancelBuildButton -Text (Get-WText 'gui.build.cancel')
    $ui.ResultFilesTitle.Text = (Get-WText 'gui.result.files')
    [System.Windows.Automation.AutomationProperties]::SetName($ui.ResultFilesBox, $ui.ResultFilesTitle.Text)
    Set-WizardGuiButtonText -Button $ui.OpenFolderButton -Text (Get-WText 'gui.result.open')
    Set-WizardGuiButtonText -Button $ui.CopyGuideButton -Text (Get-WText 'gui.result.copy')
    $ui.GuideTitle.Text = (Get-WText 'gui.result.guide')
    Set-WizardGuiButtonText -Button $ui.SignNone -Text (Get-WText 'gui.sign.none')
    Set-WizardGuiButtonText -Button $ui.SignStore -Text (Get-WText 'gui.sign.store')
    Set-WizardGuiButtonText -Button $ui.SignFile -Text (Get-WText 'gui.sign.file')
    $ui.SignNoneText.Text = (Get-WText 'gui.sign.none.info')
    $ui.CertListHint.Text = (Get-WText 'gui.sign.store.rec')
    $ui.CertListEmpty.Text = (Get-WText 'gui.sign.store.empty')
    [System.Windows.Automation.AutomationProperties]::SetName($ui.CertList, (Get-WText 'gui.sign.store').Replace('_', ''))
    [System.Windows.Automation.AutomationProperties]::SetHelpText($ui.CertList, $ui.CertListHint.Text)
    Set-WizardGuiButtonText -Button $ui.RefreshCertsButton -Text (Get-WText 'gui.sign.refresh')
    $ui.PfxPathLabel.Text = (Get-WText 'gui.sign.file.ask')
    $ui.PfxPathHint.Text = (Get-WText 'gui.sign.file.rec')
    [System.Windows.Automation.AutomationProperties]::SetName($ui.PfxPathBox, $ui.PfxPathLabel.Text)
    [System.Windows.Automation.AutomationProperties]::SetHelpText($ui.PfxPathBox, $ui.PfxPathHint.Text)
    $ui.PfxBrowseButton.Content = (Get-WText 'gui.browse')
    [System.Windows.Automation.AutomationProperties]::SetName($ui.PfxBrowseButton, "$(Get-WText 'gui.browse') $($ui.PfxPathLabel.Text)")
    $ui.PfxPasswordLabel.Text = (Get-WText 'gui.sign.password.ask')
    $ui.PfxPasswordHint.Text = (Get-WText 'gui.sign.password.rec')
    [System.Windows.Automation.AutomationProperties]::SetName($ui.PfxPasswordBox, $ui.PfxPasswordLabel.Text)
    [System.Windows.Automation.AutomationProperties]::SetHelpText($ui.PfxPasswordBox, $ui.PfxPasswordHint.Text)
    Set-WizardGuiButtonText -Button $ui.PfxOpenButton -Text (Get-WText 'gui.sign.open')
    $ui.CertDetailsTitle.Text = (Get-WText 'gui.sign.details')
    $script:Gui.CertInfo = $null
    foreach ($field in $script:Gui.Fields.Values) {
        $ask = Get-WText "$($field.Id).ask"
        $field.Label.Text = $ask
        $field.Hint.Text = (Get-WText 'rec') + (Get-WText "$($field.Id).rec")
        if ($field.Control -is [System.Windows.Controls.CheckBox]) { $field.Control.Content = $ask }
        [System.Windows.Automation.AutomationProperties]::SetName($field.Control, $ask)
        [System.Windows.Automation.AutomationProperties]::SetHelpText($field.Control, $field.Hint.Text)
        if ($null -ne $field.Browse) {
            $field.Browse.Content = (Get-WText 'gui.browse')
            [System.Windows.Automation.AutomationProperties]::SetName($field.Browse, "$(Get-WText 'gui.browse') $ask")
        }
    }
    Set-WizardGuiStepList
    Set-WizardGuiPage -Index $script:Gui.Page -NoFocus
}

function Set-WizardGuiStepList {
    $ui = $script:Gui.Ui
    $ui.StepList.Children.Clear()
    for ($i = 0; $i -lt $script:WizardGuiPages.Count; $i++) {
        $page = $script:WizardGuiPages[$i]
        $current = ($i -eq $script:Gui.Page)
        $done = ($i -lt $script:Gui.Page)
        $row = New-Object System.Windows.Controls.Border
        $row.CornerRadius = [System.Windows.CornerRadius]::new(12)
        $row.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
        $row.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
        if ($current) { $row.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'SelectedBg') }
        $panel = New-Object System.Windows.Controls.StackPanel
        $panel.Orientation = 'Horizontal'
        $badge = New-Object System.Windows.Controls.Border
        $badge.Width = 24; $badge.Height = 24
        $badge.CornerRadius = [System.Windows.CornerRadius]::new(12)
        $badge.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $(if ($current -or $done) { 'Accent' } else { 'SurfaceAlt' }))
        $mark = New-Object System.Windows.Controls.TextBlock
        $mark.HorizontalAlignment = 'Center'; $mark.VerticalAlignment = 'Center'; $mark.FontSize = 11; $mark.FontWeight = 'SemiBold'
        if ($done) { $mark.FontFamily = $script:Gui.Window.FindResource('Icons'); $mark.Text = [string][char]0xE73E }
        else { $mark.Text = "$($i + 1)" }
        $mark.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($current -or $done) { 'AccentFg' } else { 'TextSecondary' }))
        $badge.Child = $mark
        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = (Get-WText "gui.page.$($page.Id)")
        $label.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
        $label.VerticalAlignment = 'Center'
        $label.TextWrapping = 'Wrap'
        $label.MaxWidth = 170
        if ($current) { $label.FontWeight = 'SemiBold' }
        $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if ($current -or $done) { 'TextPrimary' } else { 'TextSecondary' }))
        $null = $panel.Children.Add($badge)
        $null = $panel.Children.Add($label)
        $row.Child = $panel
        [System.Windows.Automation.AutomationProperties]::SetName($label, ('{0}. {1}' -f ($i + 1), $label.Text))
        $null = $ui.StepList.Children.Add($row)
    }
}

function Set-WizardGuiPage {
    param([int]$Index, [switch]$NoFocus)
    $ui = $script:Gui.Ui
    $script:Gui.Page = $Index
    $page = $script:WizardGuiPages[$Index]
    foreach ($other in $script:WizardGuiPages) { $ui["Page_$($other.Id)"].Visibility = $(if ($other.Id -eq $page.Id) { 'Visible' } else { 'Collapsed' }) }
    $ui.PageTitle.Text = (Get-WText "gui.page.$($page.Id)")
    $ui.PageIntro.Text = (Get-WText "gui.page.$($page.Id).intro")
    $ui.PageMessage.Visibility = 'Collapsed'
    $building = ($null -ne $script:Gui.Build)
    $ui.BackButton.IsEnabled = ($Index -gt 0 -and -not $building -and $page.Id -ne 'result')
    $ui.LoadButton.IsEnabled = ($Index -lt (Get-WizardGuiPageIndex 'build') -and -not $building)
    $ui.NextButton.Visibility = $(if ($page.Id -eq 'build' -and -not $script:Gui.Result) { 'Collapsed' } else { 'Visible' })
    Set-WizardGuiButtonText -Button $ui.NextButton -Text $(if ($page.Id -eq 'result') { Get-WText 'gui.finish' } else { Get-WText 'gui.next' })
    if ($page.Id -eq 'summary') {
        try {
            $lines = @(Get-WizardSummary -A (Get-WizardGuiAnswers -State $script:Gui.State))
            $certificate = Get-WizardGuiCertificate -State $script:Gui.State
            if ($null -eq $certificate) { $lines += ('  ' + (Get-WText 'gui.summary.sign.none')) }
            else {
                $signing = Get-WizardGuiSigning -State $script:Gui.State
                $lines += ('  ' + (Get-WText 'gui.summary.sign' @($certificate.Subject, $certificate.Thumbprint, $(if ($signing.TimestampServer) { $signing.TimestampServer } else { Get-WText 'gui.summary.sign.notimestamp' }))))
            }
            $ui.SummaryBox.Text = ($lines -join [Environment]::NewLine)
        }
        catch { $ui.SummaryBox.Text = $_.Exception.Message }
    }
    if ($page.Id -eq 'build') { Set-WizardGuiProgress }
    Set-WizardGuiStepList
    $ui.PageScroll.ScrollToTop()
    Update-WizardGuiView
    if (-not $NoFocus) {
        $first = $null
        if ($page.Id -eq 'language') { $first = $ui.WizardLanguageBox }
        elseif ($page.Id -eq 'build') { $first = $ui.BuildButton }
        elseif ($page.Id -eq 'result') { $first = $ui.OpenFolderButton }
        elseif ($page.Id -eq 'signing') { $first = $(if ($script:Gui.State.Signing.Mode -eq 'Store') { $ui.SignStore } elseif ($script:Gui.State.Signing.Mode -eq 'File') { $ui.SignFile } else { $ui.SignNone }) }
        else {
            $scopeIds = @($page.Questions)
            if ($page.Id -eq 'summary') { $scopeIds = @($script:WizardGuiBuildQuestions | ForEach-Object { $_.Id }) }
            foreach ($id in $scopeIds) { $field = $script:Gui.Fields[$id]; if ($null -ne $field -and $field.Row.Visibility -eq 'Visible') { $first = $field.Control; break } }
        }
        if ($null -ne $first) { $null = $first.Focus() }
    }
}

# Rows of the progress list: one per step of the build, with a symbol and the state as text for screen readers.
function Set-WizardGuiProgress {
    $ui = $script:Gui.Ui
    $ui.ProgressList.Children.Clear()
    $script:Gui.ProgressRows = @{}
    $serverPackage = ((Get-WizardGuiEvaluation -State $script:Gui.State).Answers.TargetOS -eq 'WindowsServer')
    $steps = Get-WizardGuiBuildSteps -ConfigureOnly ([bool]$script:Gui.State.Build.ConfigureOnly) -Signed ($null -ne (Get-WizardGuiCertificate -State $script:Gui.State)) -PackageKind "$($script:Gui.State.Build.PackageKind)" -ServerPackage $serverPackage
    foreach ($step in $steps) {
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'
        $row.Margin = [System.Windows.Thickness]::new(0, 5, 0, 5)
        $glyph = New-Object System.Windows.Controls.TextBlock
        $glyph.FontFamily = $script:Gui.Window.FindResource('Icons')
        $glyph.Width = 22
        $glyph.FontSize = 15
        $text = New-Object System.Windows.Controls.TextBlock
        $text.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
        $text.Text = (Get-WText "step.$step")
        $null = $row.Children.Add($glyph)
        $null = $row.Children.Add($text)
        $null = $ui.ProgressList.Children.Add($row)
        $script:Gui.ProgressRows[$step] = [pscustomobject]@{ Row = $row; Glyph = $glyph; Text = $text; State = 'pending' }
        Set-WizardGuiStepState -Step $step -StateName 'pending'
    }
}

function Set-WizardGuiStepState {
    param([string]$Step, [string]$StateName)
    $entry = $script:Gui.ProgressRows[$Step]
    if ($null -eq $entry) { return }
    $map = @{ pending = @(0xEA3A, 'TextSecondary'); running = @(0xE895, 'AccentText'); done = @(0xE73E, 'OkFg'); failed = @(0xE783, 'ErrFg'); cancelled = @(0xE711, 'TextSecondary') }
    $entry.Glyph.Text = [string][char]$map[$StateName][0]
    $entry.Glyph.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $map[$StateName][1])
    $entry.Text.FontWeight = $(if ($StateName -eq 'running') { 'SemiBold' } else { 'Normal' })
    $entry.State = $StateName
    [System.Windows.Automation.AutomationProperties]::SetName($entry.Text, ('{0}: {1}' -f (Get-WText "step.$Step"), (Get-WText "gui.state.$StateName")))
}

# ---------------------------------------------------------------- build in a background runspace

# The script of the runspace. Every value is a parameter (nothing is put together as code); progress goes into a queue that the window reads.
$script:WizardGuiBuildScript = {
    param([string]$WizardScript, [string]$Culture, [hashtable]$Source, [string]$PayloadFolder, [bool]$FromRepository, [string]$OutputFolder, [string]$ToolPath, [bool]$ConfigureOnly, [string]$PackageKind,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate, [string]$TimestampServer, [string[]]$AdditionalSigner, $Sync)
    $ErrorActionPreference = 'Stop'
    try {
        . $WizardScript
        Initialize-WizardTexts -Folder (Split-Path -Parent $WizardScript) -Culture $Culture
        $queue = $Sync.Queue
        $progress = { param($id, $text) $queue.Enqueue([string]$id) }.GetNewClosure()
        $Sync.Result = Invoke-SelfXWizardBuild -Answers $Source -PayloadFolder $PayloadFolder -FromRepository:$FromRepository -OutputFolder $OutputFolder `
            -ToolPath $ToolPath -Language $Culture -ConfigureOnly:$ConfigureOnly -PackageKind $PackageKind -Certificate $Certificate -TimestampServer $TimestampServer `
            -AdditionalSigner $AdditionalSigner -OnProgress $progress
    }
    catch { $Sync.Error = $_.Exception.Message }
}

# Starts the build. Returns the handle (PowerShell, runspace, async result, shared table Sync with Queue, Result, Error).
function Start-WizardGuiBuild {
    param([Parameter(Mandatory = $true)]$State)
    $source = Get-WizardGuiSource -State $State
    $payload = "$($State.Build.Payload)".Trim()
    $fromRepository = (Test-Path -LiteralPath (Join-Path $payload 'Version.txt') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $payload 'Sources') -PathType Container) -and
        -not (Test-Path -LiteralPath (Join-Path $payload 'App\SelfX.Code.json') -PathType Leaf)
    $signing = Get-WizardGuiSigning -State $State
    $sync = [hashtable]::Synchronized(@{ Queue = (New-Object System.Collections.Concurrent.ConcurrentQueue[string]); Result = $null; Error = $null })
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $shell = [powershell]::Create()
    $shell.Runspace = $runspace
    $null = $shell.AddScript($script:WizardGuiBuildScript.ToString()).AddParameters(@{
            WizardScript = (Join-Path $script:GuiFolder 'SelfXWizard.ps1'); Culture = $State.Culture; Source = $source; PayloadFolder = $payload
            FromRepository = [bool]$fromRepository; OutputFolder = "$($State.Build.Output)".Trim(); ToolPath = "$($State.Build.Tool)".Trim()
            ConfigureOnly = [bool]$State.Build.ConfigureOnly; PackageKind = $(if (@('Full', 'FullSeparateConfig', 'ConfigOnly') -ccontains "$($State.Build.PackageKind)") { "$($State.Build.PackageKind)" } else { 'Full' }); Certificate = $signing.Certificate; TimestampServer = $signing.TimestampServer
            AdditionalSigner = [string[]]$signing.AdditionalSigner; Sync = $sync
        })
    $handle = $shell.BeginInvoke()
    return [pscustomobject]@{ Shell = $shell; Runspace = $runspace; Handle = $handle; Sync = $sync; Steps = (New-Object System.Collections.Generic.List[string]); Cancelled = $false }
}

# Reads the queue of a running build. Returns the new step ids.
function Receive-WizardGuiBuildProgress {
    param([Parameter(Mandatory = $true)]$Build)
    $new = New-Object System.Collections.Generic.List[string]
    $id = $null
    while ($Build.Sync.Queue.TryDequeue([ref]$id)) { $Build.Steps.Add($id); $new.Add($id) }
    return , $new.ToArray()
}

function Stop-WizardGuiBuild {
    param([Parameter(Mandatory = $true)]$Build)
    $Build.Cancelled = $true
    $null = $Build.Shell.BeginStop($null, $null)
}

function Close-WizardGuiBuild {
    param([Parameter(Mandatory = $true)]$Build)
    try { if ($Build.Handle.IsCompleted) { $null = $Build.Shell.EndInvoke($Build.Handle) } }
    catch { if (-not $Build.Sync.Error -and -not $Build.Cancelled) { $Build.Sync.Error = $_.Exception.Message } }
    $Build.Shell.Dispose()
    $Build.Runspace.Dispose()
}

function Complete-WizardGuiBuild {
    $build = $script:Gui.Build
    $ui = $script:Gui.Ui
    $script:Gui.Timer.Stop()
    Close-WizardGuiBuild -Build $build
    $script:Gui.Build = $null
    $ui.CancelBuildButton.IsEnabled = $false
    $last = $(if ($build.Steps.Count) { $build.Steps[$build.Steps.Count - 1] } else { $null })
    if ($null -ne $build.Sync.Result -and -not $build.Sync.Error) {
        foreach ($step in @($script:Gui.ProgressRows.Keys)) { Set-WizardGuiStepState -Step $step -StateName 'done' }
        $script:Gui.Result = $build.Sync.Result
        $ui.BuildStatus.Text = (Get-WText 'gui.build.done')
        Show-WizardGuiResult
        return
    }
    if ($build.Cancelled) {
        if ($last) { Set-WizardGuiStepState -Step $last -StateName 'cancelled' }
        $ui.BuildStatus.Text = (Get-WText 'gui.build.cancelled')
    }
    else {
        if ($last) { Set-WizardGuiStepState -Step $last -StateName 'failed' }
        $ui.BuildStatus.Text = (Get-WText 'gui.build.failed')
        $ui.BuildError.Text = "$($build.Sync.Error)"
        $ui.BuildError.Visibility = 'Visible'
    }
    $ui.BuildButton.IsEnabled = $true
    Set-WizardGuiPage -Index $script:Gui.Page -NoFocus
    $null = $ui.BuildButton.Focus()
}

function Show-WizardGuiResult {
    $ui = $script:Gui.Ui
    $result = $script:Gui.Result
    $configured = [bool]$script:Gui.State.Build.ConfigureOnly
    $ui.ResultText.Text = (Get-WText $(if ($configured) { 'gui.result.configured' } else { 'gui.result.text' }) @($result.OutputFolder))
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($result.PackageFile, $result.DetectionFile, $result.GuideFile, 'selfx-answers.json') + @($result.RuleFiles) + @($result.ScriptFiles)) { if ($name) { $files.Add($name) } }
    $files.Add('package\')
    $ui.ResultFilesBox.Text = ($files -join [Environment]::NewLine)
    # A package for Windows Server is installed without Intune (SelfX-Server-Guide): the title of the instructions says so.
    $ui.GuideTitle.Text = (Get-WText $(if ($result.TargetOS -eq 'WindowsServer') { 'gui.result.guide.server' } else { 'gui.result.guide' }))
    Set-WizardGuiGuideSteps -Guide $result.GuideSteps
    Set-WizardGuiPage -Index (Get-WizardGuiPageIndex 'result')
}

# The instructions as cards: the lines of each step and one copy button per value (install command, detection script, thumbprints ...).
# The value to copy is the Tag of the button; the click handler copies it and names it in the status line.
function Set-WizardGuiGuideSteps {
    param($Guide)
    $ui = $script:Gui.Ui
    $window = $script:Gui.Window
    $ui.GuideSteps.Children.Clear()
    if ($null -eq $Guide) { return }
    foreach ($step in @($Guide.Steps)) {
        $card = New-Object System.Windows.Controls.Border
        $card.Style = $window.FindResource('Card')
        $card.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
        $panel = New-Object System.Windows.Controls.StackPanel
        $first = $true
        foreach ($line in @($step.Lines)) {
            $block = New-Object System.Windows.Controls.TextBlock
            $block.Text = "$line".TrimStart()
            $block.TextWrapping = 'Wrap'
            if ($first) { $block.FontWeight = 'SemiBold'; $first = $false }
            else { $block.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0); $block.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'TextSecondary') }
            $null = $panel.Children.Add($block)
        }
        if (@($step.Copies).Count) {
            $buttons = New-Object System.Windows.Controls.WrapPanel
            $buttons.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
            foreach ($copy in @($step.Copies)) {
                $button = New-Object System.Windows.Controls.Button
                $button.Style = $window.FindResource('BaseButton')
                $button.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
                $button.Content = (Get-WText $copy.Label)
                $button.Tag = [string]$copy.Value
                $button.ToolTip = [string]$copy.Value
                [System.Windows.Automation.AutomationProperties]::SetName($button, (Get-WText $copy.Label))
                [System.Windows.Automation.AutomationProperties]::SetHelpText($button, [string]$copy.Value)
                $button.Add_Click({
                        param($sender)
                        [System.Windows.Clipboard]::SetText([string]$sender.Tag)
                        $script:Gui.Ui.StatusText.Text = (Get-WText 'gui.result.copied.value' @("$([System.Windows.Automation.AutomationProperties]::GetName($sender))"))
                    })
                $null = $buttons.Children.Add($button)
            }
            $null = $panel.Children.Add($buttons)
        }
        $card.Child = $panel
        $null = $ui.GuideSteps.Children.Add($card)
    }
}

function Start-WizardGuiBuildFromWindow {
    $ui = $script:Gui.Ui
    $ui.BuildButton.IsEnabled = $false
    $ui.BuildError.Visibility = 'Collapsed'
    $ui.BuildStatus.Text = (Get-WText 'gui.build.running')
    Set-WizardGuiProgress
    $script:Gui.Result = $null
    try { $script:Gui.Build = Start-WizardGuiBuild -State $script:Gui.State }
    catch {
        $ui.BuildStatus.Text = (Get-WText 'gui.build.failed'); $ui.BuildError.Text = $_.Exception.Message; $ui.BuildError.Visibility = 'Visible'; $ui.BuildButton.IsEnabled = $true
        return
    }
    $ui.CancelBuildButton.IsEnabled = $true
    $ui.BackButton.IsEnabled = $false
    $ui.LoadButton.IsEnabled = $false
    $script:Gui.Timer.Start()
}

# Timer tick: shows new steps and the end of the build. Cancel is possible until the step 'finish' (the result replaces the output folder then).
function Update-WizardGuiBuild {
    $build = $script:Gui.Build
    if ($null -eq $build) { $script:Gui.Timer.Stop(); return }
    foreach ($id in (Receive-WizardGuiBuildProgress -Build $build)) {
        foreach ($step in @($script:Gui.ProgressRows.Keys)) { if ($script:Gui.ProgressRows[$step].State -eq 'running') { Set-WizardGuiStepState -Step $step -StateName 'done' } }
        Set-WizardGuiStepState -Step $id -StateName 'running'
        if ($id -eq 'finish') { $script:Gui.Ui.CancelBuildButton.IsEnabled = $false }
    }
    if ($build.Handle.IsCompleted) { Complete-WizardGuiBuild }
}

# ---------------------------------------------------------------- dialogs

function Select-WizardGuiFile {
    param([string]$FilterTextId, [string]$Current, [switch]$Save, [string]$FileName)
    $dialog = $(if ($Save) { New-Object Microsoft.Win32.SaveFileDialog } else { New-Object Microsoft.Win32.OpenFileDialog })
    $dialog.Filter = (Get-WText $FilterTextId)
    if ($FileName) { $dialog.FileName = $FileName }
    if ($Current -and (Test-Path -LiteralPath (Split-Path -Parent $Current) -PathType Container -ErrorAction SilentlyContinue)) { $dialog.InitialDirectory = (Split-Path -Parent $Current) }
    if ($dialog.ShowDialog($script:Gui.Window)) { return $dialog.FileName }
    return $null
}

function Select-WizardGuiFolder {
    param([string]$Current)
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.ShowNewFolderButton = $true
    if ($Current -and (Test-Path -LiteralPath $Current -PathType Container)) { $dialog.SelectedPath = $Current }
    try { if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath } }
    finally { $dialog.Dispose() }
    return $null
}

# ---------------------------------------------------------------- creation of the window

# Creates the window with all pages and fields, without showing it. Returns the context ($script:Gui). Tested by Test-SelfXWizardGui.ps1.
function New-WizardGuiWindow {
    param([string]$Culture = 'en', [string]$Theme)
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) { throw 'The window needs a single-threaded apartment: start it with -STA (tools\Start-SelfXPackageWizard.cmd).' }
    Initialize-WizardTexts -Folder $script:GuiFolder -Culture $Culture
    $reader = New-Object System.Xml.XmlTextReader((New-Object System.IO.StringReader((Get-WizardGuiXaml))))
    $reader.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $reader.XmlResolver = $null
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $reader.Close()
    if (-not $Theme) { $Theme = Get-WizardGuiTheme }
    $script:Gui = [pscustomobject]@{
        Window = $window; Ui = @{}; Fields = [ordered]@{}; State = (New-WizardGuiState -ToolsFolder $script:GuiToolsFolder -Culture $Culture); Page = 0; Loading = $false
        Evaluation = $null; Extra = @{}; ShowAll = (New-Object System.Collections.Generic.HashSet[string]); Build = $null; Result = $null; ProgressRows = @{}
        Timer = $null; Theme = $Theme; AppliedAccent = $null; LogoChecked = $null; ToolCultures = (Get-WizardGuiToolCultures -CodeFolder $script:GuiCodeFolder)
        CertInfo = $null; PfxMessage = $false
    }
    Set-WizardGuiColors -Window $window -AccentColor '' -Theme $Theme
    $script:Gui.AppliedAccent = ''
    $names = @('AppTitle', 'StepList', 'PageTitle', 'PageIntro', 'PageMessage', 'PageMessageText', 'PageScroll', 'WizardLanguageLabel', 'WizardLanguageHint', 'WizardLanguageBox',
        'PreviewTitle', 'LogoPreview', 'LogoPreviewText', 'AccentSwatch', 'AccentSample', 'AccentSampleLink', 'UnitsPanel', 'UnitsTitle', 'UnitsHint', 'UnitList', 'UnitsError',
        'AddUnitButton', 'RemoveUnitButton', 'UnitEditor', 'UnitEditorTitle', 'TargetsPanel', 'TargetsTitle', 'TargetsHint', 'TargetList', 'TargetsError', 'AddTargetButton', 'RemoveTargetButton',
        'TargetEditor', 'TargetEditorTitle', 'SummaryTitle', 'SummaryBox', 'BuildSettingsTitle', 'BuildButton', 'CancelBuildButton', 'ProgressList',
        'BuildStatus', 'BuildError', 'ResultText', 'ResultFilesTitle', 'ResultFilesBox', 'OpenFolderButton', 'CopyGuideButton', 'GuideTitle', 'GuideSteps', 'LoadButton', 'SaveButton',
        'NextButton', 'BackButton', 'StatusText', 'SignNone', 'SignStore', 'SignFile', 'SignNoneInfo', 'SignNoneText', 'SignStorePanel', 'CertListHint', 'CertList', 'CertListEmpty',
        'CertListError', 'RefreshCertsButton', 'SignFilePanel', 'PfxPathLabel', 'PfxPathHint', 'PfxBrowseButton', 'PfxPathBox', 'PfxPasswordLabel', 'PfxPasswordHint', 'PfxOpenButton',
        'PfxPasswordBox', 'PfxStatus', 'PfxError', 'SignDetailsPanel', 'CertDetailsTitle', 'CertCard', 'CertSubject', 'CertIssuer', 'CertValid', 'CertThumbprint', 'CertCrl',
        'CertCrlWarningBox', 'CertCrlWarning')
    foreach ($page in $script:WizardGuiPages) { $names += "Page_$($page.Id)" }
    foreach ($page in @('language', 'basics', 'support', 'branding', 'ticket', 'network', 'more', 'signing', 'summary', 'unit', 'target')) { $names += "Fields_$page" }
    foreach ($name in $names) {
        $element = $window.FindName($name)
        if ($null -eq $element) { throw "The window has no element $name." }
        $script:Gui.Ui[$name] = $element
    }
    $ui = $script:Gui.Ui
    foreach ($language in @(Get-WizardLanguages -Folder $script:GuiFolder | Sort-Object @{ Expression = { $_.Culture -ne 'en' } }, Culture)) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = "$($language.Name) ($($language.Culture))"
        $item.Tag = $language.Culture
        $null = $ui.WizardLanguageBox.Items.Add($item)
        if ($language.Culture -eq $Culture) { $ui.WizardLanguageBox.SelectedItem = $item }
    }
    # Fields of the pages
    $questions = $script:Gui.State.Questions
    foreach ($page in $script:WizardGuiPages) {
        foreach ($id in $page.Questions) {
            $field = New-WizardGuiFieldRow -Question $questions[$id] -Scope 'answer'
            $null = $ui["Fields_$($page.Id)"].Children.Add($field.Row)
            $script:Gui.Fields[$id] = $field
        }
    }
    foreach ($id in 'UnitId', 'UnitMail', 'UnitCc', 'UnitGroupTags', 'UnitOUs', 'UnitCategories') {
        $field = New-WizardGuiFieldRow -Question $questions[$id] -Scope 'unit'
        $null = $ui.Fields_unit.Children.Add($field.Row)
        $script:Gui.Fields[$id] = $field
    }
    foreach ($id in 'TargetLabel', 'TargetHost', 'TargetPort', 'TargetGroup', 'TargetKind') {
        $field = New-WizardGuiFieldRow -Question $questions[$id] -Scope 'target'
        $null = $ui.Fields_target.Children.Add($field.Row)
        $script:Gui.Fields[$id] = $field
    }
    foreach ($question in $script:WizardGuiBuildQuestions) {
        $field = New-WizardGuiFieldRow -Question $question -Scope 'build'
        $null = $ui.Fields_summary.Children.Add($field.Row)
        $script:Gui.Fields[$question.Id] = $field
    }
    foreach ($question in $script:WizardGuiSigningQuestions) {
        $field = New-WizardGuiFieldRow -Question $question -Scope 'signing'
        $null = $ui.Fields_signing.Children.Add($field.Row)
        $script:Gui.Fields[$question.Id] = $field
    }
    $ui.SignNone.IsChecked = $true
    Register-WizardGuiEvents
    Set-WizardGuiAllValues
    Set-WizardGuiTexts
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({ Update-WizardGuiBuild })
    $script:Gui.Timer = $timer
    return $script:Gui
}

# Puts the values of the state into all fields (start, after loading answers, after changing the selected unit).
function Set-WizardGuiAllValues {
    $state = $script:Gui.State
    $evaluation = Get-WizardGuiEvaluation -State $state
    foreach ($field in $script:Gui.Fields.Values) {
        if ($field.Scope -eq 'answer') { Set-WizardGuiControlValue -Field $field -Value (Get-WizardGuiShownValue -State $state -Id $field.Id -Answers $evaluation.Answers) }
        elseif ($field.Scope -eq 'build') { Set-WizardGuiControlValue -Field $field -Value $state.Build[$field.Id] }
        elseif ($field.Scope -eq 'signing') { Set-WizardGuiControlValue -Field $field -Value $state.Signing[$field.Id] }
    }
    Set-WizardGuiUnitValues
    Set-WizardGuiTargetValues
}

function Set-WizardGuiTargetValues {
    $index = $script:Gui.Ui.TargetList.SelectedIndex
    foreach ($field in @($script:Gui.Fields.Values | Where-Object { $_.Scope -eq 'target' })) {
        $value = $(if ($index -ge 0 -and $index -lt $script:Gui.State.Targets.Count) { $script:Gui.State.Targets[$index][$field.Id] } else { '' })
        Set-WizardGuiControlValue -Field $field -Value $value
    }
}

function Set-WizardGuiUnitValues {
    $index = $script:Gui.Ui.UnitList.SelectedIndex
    foreach ($field in @($script:Gui.Fields.Values | Where-Object { $_.Scope -eq 'unit' })) {
        $value = $(if ($index -ge 0 -and $index -lt $script:Gui.State.Units.Count) { $script:Gui.State.Units[$index][$field.Id] } else { '' })
        Set-WizardGuiControlValue -Field $field -Value $value
    }
}

# A changed field: store the typed value in the state, check again, show. Nothing else happens here.
function Invoke-WizardGuiFieldChanged {
    param($Field)
    if ($script:Gui.Loading) { return }
    $value = Get-WizardGuiControlValue -Field $Field
    $state = $script:Gui.State
    switch ($Field.Scope) {
        'answer' { $state.Raw[$Field.Id] = $value }
        'build' { $state.Build[$Field.Id] = $value }
        'signing' { $state.Signing[$Field.Id] = $value }
        'unit' {
            $index = $script:Gui.Ui.UnitList.SelectedIndex
            if ($index -lt 0) { return }
            $state.Units[$index][$Field.Id] = $value
        }
        'target' {
            $index = $script:Gui.Ui.TargetList.SelectedIndex
            if ($index -lt 0) { return }
            $state.Targets[$index][$Field.Id] = $value
        }
    }
    if ($Field.Id -eq 'ConfigureOnly' -and $script:WizardGuiPages[$script:Gui.Page].Id -eq 'summary') { Set-WizardGuiProgress }
    Update-WizardGuiView
}

function Invoke-WizardGuiBrowse {
    param($Field)
    $target = $null
    if ($Field.Id -eq 'LogoPath') { $target = Select-WizardGuiFile -FilterTextId 'gui.logo.filter' -Current $Field.Control.Text }
    elseif ($Field.Question.Browse -eq 'tool') { $target = Select-WizardGuiFile -FilterTextId 'gui.tool.filter' -Current $Field.Control.Text }
    else { $target = Select-WizardGuiFolder -Current $Field.Control.Text }
    if ($target) { $Field.Control.Text = $target; $null = $Field.Control.Focus() }
}

function Register-WizardGuiEvents {
    $ui = $script:Gui.Ui
    # The handlers find their field by the control that raised the event (no closures: they would lose the functions of this script).
    $changed = { param($sender) foreach ($field in @($script:Gui.Fields.Values)) { if ([object]::ReferenceEquals($field.Control, $sender)) { Invoke-WizardGuiFieldChanged -Field $field } } }
    $browse = { param($sender) foreach ($field in @($script:Gui.Fields.Values)) { if ([object]::ReferenceEquals($field.Browse, $sender)) { Invoke-WizardGuiBrowse -Field $field } } }
    foreach ($field in $script:Gui.Fields.Values) {
        if ($field.Control -is [System.Windows.Controls.CheckBox]) { $field.Control.Add_Checked($changed); $field.Control.Add_Unchecked($changed) }
        elseif ($field.Control -is [System.Windows.Controls.ComboBox]) { $field.Control.Add_SelectionChanged($changed) }
        else { $field.Control.Add_TextChanged($changed) }
        if ($null -ne $field.Browse) { $field.Browse.Add_Click($browse) }
    }
    $ui.WizardLanguageBox.Add_SelectionChanged({
            if ($script:Gui.Loading) { return }
            $item = $script:Gui.Ui.WizardLanguageBox.SelectedItem
            if ($null -eq $item) { return }
            $script:Gui.State.Culture = [string]$item.Tag
            Initialize-WizardTexts -Folder $script:GuiFolder -Culture $script:Gui.State.Culture
            $script:Gui.LogoChecked = $null
            Set-WizardGuiTexts
        })
    $ui.UnitList.Add_SelectionChanged({
            if ($script:Gui.Loading) { return }
            Set-WizardGuiUnitValues
            Update-WizardGuiView
        })
    $ui.AddUnitButton.Add_Click({
            $script:Gui.State.Units.Add((New-WizardGuiUnit))
            Update-WizardGuiView
            $script:Gui.Ui.UnitList.SelectedIndex = $script:Gui.State.Units.Count - 1
            $null = $script:Gui.Fields['UnitId'].Control.Focus()
        })
    $ui.RemoveUnitButton.Add_Click({
            $index = $script:Gui.Ui.UnitList.SelectedIndex
            if ($index -lt 0) { return }
            $script:Gui.State.Units.RemoveAt($index)
            Update-WizardGuiView
            Set-WizardGuiUnitValues
            Update-WizardGuiView
        })
    $ui.TargetList.Add_SelectionChanged({
            if ($script:Gui.Loading) { return }
            Set-WizardGuiTargetValues
            Update-WizardGuiView
        })
    $ui.AddTargetButton.Add_Click({
            if ($script:Gui.State.Targets.Count -ge $script:NetMaxOwnTargets) { return }
            $script:Gui.State.Targets.Add((New-WizardGuiTarget))
            Update-WizardGuiView
            $script:Gui.Ui.TargetList.SelectedIndex = $script:Gui.State.Targets.Count - 1
            $null = $script:Gui.Fields['TargetLabel'].Control.Focus()
        })
    $ui.RemoveTargetButton.Add_Click({
            $index = $script:Gui.Ui.TargetList.SelectedIndex
            if ($index -lt 0) { return }
            $script:Gui.State.Targets.RemoveAt($index)
            Update-WizardGuiView
            Set-WizardGuiTargetValues
            Update-WizardGuiView
        })
    $ui.NextButton.Add_Click({ Invoke-WizardGuiNext })
    $ui.BackButton.Add_Click({ if ($script:Gui.Page -gt 0) { Set-WizardGuiPage -Index ($script:Gui.Page - 1) } })
    $ui.BuildButton.Add_Click({ Start-WizardGuiBuildFromWindow })
    $ui.CancelBuildButton.Add_Click({
            if ($null -eq $script:Gui.Build) { return }
            $script:Gui.Ui.CancelBuildButton.IsEnabled = $false
            $script:Gui.Ui.BuildStatus.Text = (Get-WText 'gui.build.cancelling')
            Stop-WizardGuiBuild -Build $script:Gui.Build
        })
    $ui.OpenFolderButton.Add_Click({
            $folder = "$($script:Gui.Result.OutputFolder)"
            if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) {
                Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList @(('"{0}"' -f $folder))
            }
        })
    $ui.CopyGuideButton.Add_Click({
            [System.Windows.Clipboard]::SetText("$($script:Gui.Result.GuideText)")
            $script:Gui.Ui.StatusText.Text = (Get-WText 'gui.result.copied')
        })
    # Page signing: mode, list of the stores, PFX file. Enter in the password box opens the file (not the next page).
    $mode = {
        param($sender)
        $script:Gui.State.Signing.Mode = $(if ([object]::ReferenceEquals($sender, $script:Gui.Ui.SignStore)) { 'Store' } elseif ([object]::ReferenceEquals($sender, $script:Gui.Ui.SignFile)) { 'File' } else { 'None' })
        if ($script:Gui.State.Signing.Mode -eq 'Store' -and $script:Gui.Ui.CertList.Items.Count -eq 0) { Update-WizardGuiCertificateList }
        $script:Gui.CertInfo = $null
        Update-WizardGuiView
    }
    $ui.SignNone.Add_Checked($mode); $ui.SignStore.Add_Checked($mode); $ui.SignFile.Add_Checked($mode)
    $ui.RefreshCertsButton.Add_Click({ Update-WizardGuiCertificateList; $script:Gui.CertInfo = $null; Update-WizardGuiView })
    $ui.CertList.Add_SelectionChanged({
            if ($script:Gui.Loading) { return }
            $item = $script:Gui.Ui.CertList.SelectedItem
            $script:Gui.State.StoreCertificate = $null
            if ($null -ne $item) { foreach ($certificate in @($script:Gui.State.StoreList)) { if ($certificate.Thumbprint -eq $item.Tag) { $script:Gui.State.StoreCertificate = $certificate } } }
            $script:Gui.CertInfo = $null
            Update-WizardGuiView
        })
    $ui.PfxBrowseButton.Add_Click({
            $target = Select-WizardGuiFile -FilterTextId 'gui.sign.pfx.filter' -Current $script:Gui.Ui.PfxPathBox.Text
            if ($target) { $script:Gui.Ui.PfxPathBox.Text = $target; $null = $script:Gui.Ui.PfxPasswordBox.Focus() }
        })
    $ui.PfxOpenButton.Add_Click({ Open-WizardGuiPfx })
    $ui.PfxPasswordBox.Add_KeyDown({
            param($sender, $keys)
            if ($keys.Key -eq [System.Windows.Input.Key]::Return) { $keys.Handled = $true; Open-WizardGuiPfx }
        })
    $ui.PfxPathBox.Add_TextChanged({ $script:Gui.PfxMessage = $false })
    $ui.LoadButton.Add_Click({ Invoke-WizardGuiLoad })
    $ui.SaveButton.Add_Click({ Invoke-WizardGuiSave })
    $script:Gui.Window.Add_Closing({
            param($sender, $closing)
            if ($null -ne $script:Gui.Build) {
                $answer = [System.Windows.MessageBox]::Show($script:Gui.Window, (Get-WText 'gui.close.build'), (Get-WText 'title'), 'YesNo', 'Warning')
                if ($answer -ne 'Yes') { $closing.Cancel = $true; return }
                Stop-WizardGuiBuild -Build $script:Gui.Build
            }
            $script:Gui.Ui.PfxPasswordBox.Clear()
        })
}

function Invoke-WizardGuiNext {
    $ui = $script:Gui.Ui
    $page = $script:WizardGuiPages[$script:Gui.Page]
    if ($page.Id -eq 'result') { $script:Gui.Window.Close(); return }
    if ($page.Id -eq 'build') { if ($script:Gui.Result) { Set-WizardGuiPage -Index (Get-WizardGuiPageIndex 'result') }; return }
    $evaluation = Get-WizardGuiEvaluation -State $script:Gui.State
    $null = Update-WizardGuiLogo
    $extra = @{}; if ($script:Gui.Extra.ContainsKey('LogoPath')) { $extra['LogoPath'] = $script:Gui.Extra['LogoPath'] }
    $errors = Get-WizardGuiPageErrors -State $script:Gui.State -PageId $page.Id -Evaluation $evaluation -ExtraErrors $extra
    if ($errors.Count -gt 0) {
        foreach ($id in $errors) { $null = $script:Gui.ShowAll.Add($id) }
        foreach ($id in $page.Questions) { $null = $script:Gui.ShowAll.Add($id) }
        if ($errors -match '^Unit\d+$') { $first = [int](($errors -match '^Unit\d+$')[0].Substring(4)); $ui.UnitList.SelectedIndex = $first }
        if ($errors -match '^Target\d+$') { $first = [int](($errors -match '^Target\d+$')[0].Substring(6)); $ui.TargetList.SelectedIndex = $first }
        Update-WizardGuiView
        $ui.PageMessageText.Text = (Get-WText 'gui.page.errors')
        $ui.PageMessage.Visibility = 'Visible'
        foreach ($id in $errors) {
            $field = $script:Gui.Fields[$id]
            if ($null -eq $field -and $id -match '^Target\d+$') { $field = @($script:Gui.Fields.Values | Where-Object { $_.Scope -eq 'target' -and $_.Error.Visibility -eq 'Visible' })[0] }
            if ($null -eq $field -and $id -match '^Unit\d+$') { $field = @($script:Gui.Fields.Values | Where-Object { $_.Scope -eq 'unit' -and $_.Error.Visibility -eq 'Visible' })[0] }
            if ($null -ne $field) { $null = $field.Control.Focus(); break }
            if ($id -eq 'Units') { $null = $ui.AddUnitButton.Focus(); break }
            if ($id -eq 'Targets') { $null = $ui.AddTargetButton.Focus(); break }
            if ($id -eq 'Store') { $null = $ui.CertList.Focus(); break }
            if ($id -eq 'File') { $null = $ui.PfxPathBox.Focus(); break }
        }
        return
    }
    if ($page.Id -eq 'summary') {
        try { $null = Get-WizardGuiAnswers -State $script:Gui.State }
        catch { $ui.PageMessageText.Text = $_.Exception.Message; $ui.PageMessage.Visibility = 'Visible'; return }
    }
    Set-WizardGuiPage -Index ($script:Gui.Page + 1)
}

function Invoke-WizardGuiLoad {
    $path = Select-WizardGuiFile -FilterTextId 'gui.answers.filter' -Current "$($script:Gui.State.Build.Output)\selfx-answers.json"
    if (-not $path) { return }
    try { $language = Import-WizardGuiAnswers -State $script:Gui.State -Path $path }
    catch { $script:Gui.Ui.StatusText.Text = (Get-WText 'gui.answers.unreadable' @($_.Exception.Message)); return }
    $script:Gui.ShowAll.Clear()
    foreach ($key in $script:Gui.State.Raw.Keys) { $null = $script:Gui.ShowAll.Add($key) }
    $script:Gui.Ui.UnitList.SelectedIndex = -1
    $script:Gui.Ui.TargetList.SelectedIndex = -1
    Set-WizardGuiAllValues
    Update-WizardGuiView
    $available = @(Get-WizardLanguages -Folder $script:GuiFolder | ForEach-Object { $_.Culture })
    if ($language -and $available -contains $language -and $language -ne $script:Gui.State.Culture) {
        foreach ($item in $script:Gui.Ui.WizardLanguageBox.Items) { if ($item.Tag -eq $language) { $script:Gui.Ui.WizardLanguageBox.SelectedItem = $item } }
    }
    $script:Gui.Ui.StatusText.Text = (Get-WText 'gui.answers.loaded' @((Split-Path -Leaf $path)))
}

function Invoke-WizardGuiSave {
    try { $answers = Get-WizardGuiAnswers -State $script:Gui.State }
    catch { $script:Gui.Ui.StatusText.Text = (Get-WText 'gui.answers.invalid'); return }
    $path = Select-WizardGuiFile -FilterTextId 'gui.answers.filter' -Current "$($script:Gui.State.Build.Output)\selfx-answers.json" -Save -FileName 'selfx-answers.json'
    if (-not $path) { return }
    Save-WizardAnswers -Path $path -Answers $answers -Language $script:Gui.State.Culture
    $script:Gui.Ui.StatusText.Text = (Get-WText 'gui.answers.saved' @((Split-Path -Leaf $path)))
}

function Show-SelfXWizardGui {
    param([string]$Culture)
    if (-not $Culture) {
        $Culture = 'en'
        $ui = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if (@(Get-WizardLanguages -Folder $script:GuiFolder | ForEach-Object { $_.Culture }) -contains $ui) { $Culture = $ui }
    }
    $context = New-WizardGuiWindow -Culture $Culture
    Set-WizardGuiPage -Index 0
    try { $null = $context.Window.ShowDialog() }
    finally {
        if ($null -ne $context.Build) { Close-WizardGuiBuild -Build $context.Build }
        # The certificates (and the key of an opened PFX file, which lives only in memory) are released.
        Clear-WizardGuiCertificates -State $context.State
    }
}

if (-not $script:GuiIsDotSourced) {
    try { Show-SelfXWizardGui; exit 0 }
    catch {
        $message = "SelfX package wizard: $($_.Exception.Message)"
        try { $null = [System.Windows.MessageBox]::Show($message, 'SelfX', 'OK', 'Error') } catch { Write-Host $message -ForegroundColor Red }
        exit 1
    }
}
