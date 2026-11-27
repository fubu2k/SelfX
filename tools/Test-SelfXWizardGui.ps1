<#
.SYNOPSIS
    Tests the window of the package wizard (tools\Wizard\SelfXWizardGui.ps1) without showing it.

.DESCRIPTION
    Isolated: works in a temporary folder, changes no repository file, sends nothing, needs no .NET SDK and no IntuneWinAppUtil.exe (the
    builds use -ConfigureOnly on a fake payload). The window is created but never shown. Checks:
      - texts: every text id of the window and every question of every page exists in de and en with the same placeholders;
      - pages: every question of the console is on exactly one page;
      - look: the shared styles come from Self_X.ps1 (parsed, not run), negative cases for a changed Self_X.ps1;
      - the XAML loads in this edition (Windows PowerShell 5.1 or PowerShell 7) in light and dark, every page opens, every input has a name
        for screen readers and no text is missing;
      - checks at the field: wrong e-mail address, required value, wrong logo, units (empty, twice, wrong group tag), next page blocked;
      - answers: the answers of the window are identical to the answers of the console with the same input (selfx-answers.json, Tool_Config.xml
        and Ticket_Config.xml of a build with -ConfigureOnly, the window's build running in the background runspace);
      - answer files: load, unknown answer, too large, not JSON; cancel of a running build leaves no half-finished output;
      - signature: an expired certificate is not offered, a valid test certificate is; the PFX password (a test value) appears nowhere: not
        in a text of the window, its title, a help text, the state, the answers or an error; the box is emptied; time stamp and additional
        signers are checked; the instructions as steps with copy values. Test certificates are created in Cert:\CurrentUser\My and
        removed at the end (no trusted root is added; a signed build is tested by Test-SelfXPackageWizard.ps1).
    Works in Windows PowerShell 5.1 and PowerShell 7 on Windows. Restarts itself with -STA when the thread is not single-threaded (WPF).

.NOTES
    Name    : Test-SelfXWizardGui.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 1.1.0
    History : 1.0.0 (2026-11-27, fubu2k) Initial version
              1.1.0 (2026-11-27, fubu2k) Page Signature (store list without expired certificates, PFX file, password never in a text, the
                                         state, the answers or the window title; time stamp; additional signers), instructions as steps
              1.2.0 (2026-11-27, fubu2k) choice of the package kind (configuration package)
    Exit code: 0 = all tests passed, 1 = at least one failed
#>
$ErrorActionPreference = 'Stop'
$hostExe = (Get-Process -Id $PID).Path
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    & $hostExe -NoProfile -STA -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit $LASTEXITCODE
}
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$WizardFolder = Join-Path $ScriptFolder 'Wizard'
. (Join-Path $WizardFolder 'SelfXWizardGui.ps1')
. (Join-Path $ScriptFolder 'SelfXTestCertificate.ps1')

$script:Failed = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  PASS $Name" } else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}
function Assert-Throws {
    param([scriptblock]$Code, [string]$Name)
    $threw = $false
    try { & $Code | Out-Null } catch { $threw = $true }
    Assert $threw $Name
}

function New-FakePayload {
    # A payload as the release archive has it (App and Config, Bin with dummy programs and SelfX.Binaries.json), made from the repository.
    param([string]$Folder)
    $repo = Join-Path $Folder 'repo'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Copy-Item -Path (Join-Path $RepositoryRoot 'SelfX Service\*') -Destination $repo -Recurse -Force
    $bin = Join-Path $repo 'Bin'
    $programs = [ordered]@{ 'SelfXService.exe' = 'Service/SelfXService.cs'; 'SelfX.exe' = 'Service/SelfXLauncher.cs'; 'SelfXSessionStarter.dll' = 'Service/SelfXSessionStarter.cs'; 'WinRT/SelfXWinRT.dll' = 'Service/SelfXWinRT.cs'; 'Audio/SelfXAudio.dll' = 'Service/SelfXAudio.cs' }
    $sources = [ordered]@{}; $binaries = [ordered]@{}
    foreach ($name in $programs.Keys) {
        $path = Join-Path $bin $name.Replace('/', '\')
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllText($path, "binary $name")
        $binaries[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $sources[$programs[$name]] = (Get-FileHash -LiteralPath (Join-Path $repo $programs[$name].Replace('/', '\')) -Algorithm SHA256).Hash
    }
    $manifest = [ordered]@{ ManifestVersion = 3; ToolVersion = 'test'; BuiltUtc = ''; Sources = $sources; Binaries = $binaries }
    [IO.File]::WriteAllText((Join-Path $bin 'SelfX.Binaries.json'), ($manifest | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    $payload = Join-Path $Folder 'payload'
    $null = New-SelfXPayloadFromRepository -SourceFolder $repo -Target $payload
    Remove-Item -LiteralPath $repo -Recurse -Force
    return $payload
}

function Set-Field {
    # Types a value into a field of the window as a user does: the change handler of the window stores it.
    param([string]$Id, $Value)
    $field = $script:Gui.Fields[$Id]
    $control = $field.Control
    if ($control -is [System.Windows.Controls.CheckBox]) { $control.IsChecked = [bool]$Value }
    elseif ($control -is [System.Windows.Controls.ComboBox]) { $control.SelectedItem = @($control.Items | Where-Object { "$_" -ieq "$Value" })[0] }
    else { $control.Text = "$Value" }
}

function Wait-GuiBuild {
    param($Build, [int]$Seconds = 180)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while (-not $Build.Handle.IsCompleted -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
    $null = Receive-WizardGuiBuildProgress -Build $Build
    Close-WizardGuiBuild -Build $Build
}

function Get-AllWindowText {
    # Every text the window holds: texts of text blocks, boxes, access texts, string contents and tool tips, names and help texts for screen
    # readers, and the window title.
    param($Root)
    $texts = New-Object System.Collections.Generic.List[string]
    $texts.Add([string]$script:Gui.Window.Title)
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue($Root)
    while ($queue.Count) {
        $node = $queue.Dequeue()
        if ($node -is [System.Windows.DependencyObject]) {
            $texts.Add([string][System.Windows.Automation.AutomationProperties]::GetName($node))
            $texts.Add([string][System.Windows.Automation.AutomationProperties]::GetHelpText($node))
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($node)) { $queue.Enqueue($child) }
        }
        if ($node -is [string]) { $texts.Add($node) }
        if ($node -is [System.Windows.Controls.TextBlock]) { $texts.Add($node.Text) }
        if ($node -is [System.Windows.Controls.TextBox]) { $texts.Add($node.Text) }
        if ($node -is [System.Windows.Controls.AccessText]) { $texts.Add($node.Text) }
        if ($node -is [System.Windows.FrameworkElement] -and $node.ToolTip -is [string]) { $texts.Add($node.ToolTip) }
    }
    return ($texts -join "`n")
}

function Click {
    param($Button)
    $Button.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-WizardGuiTest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$repoDigest = @((Get-FileHash (Join-Path $RepositoryRoot 'SelfX Service\Sources\Tool_Config.xml')).Hash, (Get-FileHash (Join-Path $RepositoryRoot 'SelfX Service\Sources\Ticket_Config.xml')).Hash) -join ','
try {
    # ---------------------------------------------------------- texts and pages
    Write-Host 'Texts and pages'
    $en = Read-WizardTextFile -Path (Join-Path $WizardFolder 'Wizard.en.xml')
    $de = Read-WizardTextFile -Path (Join-Path $WizardFolder 'Wizard.de.xml')
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($id in (Get-WizardGuiTextIds)) { $ids.Add($id) }
    $questions = Get-WizardGuiQuestionTable
    foreach ($id in $questions.Keys) { $ids.Add("$id.ask"); $ids.Add("$id.rec") }
    foreach ($table in @(@('en', $en), @('de', $de))) {
        $missing = @($ids | Where-Object { -not $table[1].ContainsKey($_) -or -not $table[1][$_] })
        Assert ($missing.Count -eq 0) ("$($table[0]): every text id of the window exists" + $(if ($missing) { ': ' + ($missing -join ', ') }))
    }
    $placeholder = @($ids | Where-Object { $en.ContainsKey($_) -and $de.ContainsKey($_) -and ((([regex]::Matches($en[$_], '\{\d+\}') | ForEach-Object Value | Sort-Object) -join ',') -ne (([regex]::Matches($de[$_], '\{\d+\}') | ForEach-Object Value | Sort-Object) -join ',')) })
    Assert ($placeholder.Count -eq 0) 'de and en have the same placeholders in the texts of the window'
    foreach ($page in $script:WizardGuiPages) {
        $pageIds = @("gui.page.$($page.Id)", "gui.page.$($page.Id).intro") + @($page.Questions | ForEach-Object { "$_.ask"; "$_.rec" })
        $gap = @($pageIds | Where-Object { -not $en.ContainsKey($_) -or -not $de.ContainsKey($_) })
        Assert ($gap.Count -eq 0) "page $($page.Id) has all its texts in de and en"
    }
    $onPages = @($script:WizardGuiPages | ForEach-Object { $_.Questions } | ForEach-Object { $_ })
    $consoleIds = @((Get-WizardQuestions) | ForEach-Object { $_.Id })
    Assert (@($consoleIds | Where-Object { @($onPages -eq $_).Count -ne 1 }).Count -eq 0) 'every question of the console is on exactly one page'
    Assert (@($onPages | Where-Object { $consoleIds -notcontains $_ }).Count -eq 0) 'the pages name only questions of the console'
    Assert (((Get-WizardGuiBuildSteps -ConfigureOnly $false) -join ',') -eq 'check,copy,config,pack,detection,rules,guide,finish') 'progress list has the steps of Invoke-SelfXPackageBuild'
    Assert (((Get-WizardGuiBuildSteps -ConfigureOnly $false -Signed $true -PackageKind ConfigOnly) -join ',') -eq 'check,copy,config,sign,pack,detection,rules,guide,finish') 'progress list of the signed configuration package has no code catalog step'
    Assert (((Get-WizardGuiBuildSteps -ConfigureOnly $false -Signed $true -PackageKind Full) -join ',') -eq 'check,copy,config,sign,catalog,pack,detection,rules,guide,finish') 'progress list of the signed full package keeps the catalog step'
    $kindQuestion = @($script:WizardGuiBuildQuestions | Where-Object { $_.Id -eq 'PackageKind' })
    Assert ($kindQuestion.Count -eq 1 -and ($kindQuestion[0].Choices -join ',') -eq 'Full,FullSeparateConfig,ConfigOnly') 'the summary page asks for the package kind with the three kinds'

    # ---------------------------------------------------------- shared styles
    Write-Host 'Shared styles'
    $selfx = Join-Path $RepositoryRoot 'SelfX Service\Sources\Self_X.ps1'
    $styles = Get-WizardGuiSharedStyles -SelfXScript $selfx
    foreach ($key in 'Card', 'BaseButton', 'PrimaryButton', 'Switch', 'SubText', 'PageTitle', 'Glyph') { Assert ($styles -match "x:Key=`"$key`"") "Self_X.ps1 provides the style $key" }
    $xaml = [IO.File]::ReadAllText((Join-Path $WizardFolder 'SelfXWizardGui.xaml'))
    Assert ($xaml -notmatch 'x:Key="(Card|BaseButton|PrimaryButton|Switch|SubText|PageTitle|Glyph)"') 'the window does not copy the styles of Self_X.ps1'
    Assert ($xaml -notmatch '#[0-9A-Fa-f]{6}') 'the window XAML has no fixed color (all colors come from Branding.ps1)'
    $fake = Join-Path $work 'fake-selfx.ps1'
    [IO.File]::WriteAllText($fake, "`$x = 1`n`$Global:SelfX_StylesXaml = `"<Style x:Key='A'/> `$x`"`n")
    Assert-Throws { Get-WizardGuiSharedStyles -SelfXScript $fake } 'styles that are an expression (not a constant text) are refused'
    [IO.File]::WriteAllText($fake, "`$Global:SelfX_StylesXaml = 'a'`n`$Global:SelfX_StylesXaml = 'b'`n")
    Assert-Throws { Get-WizardGuiSharedStyles -SelfXScript $fake } 'two assignments of the styles are refused'
    [IO.File]::WriteAllText($fake, "`$Other = 'a'`n")
    Assert-Throws { Get-WizardGuiSharedStyles -SelfXScript $fake } 'a Self_X.ps1 without styles is refused'
    [IO.File]::WriteAllText($fake, "`$Global:SelfX_StylesXaml = @'`n<x/>`n")
    Assert-Throws { Get-WizardGuiSharedStyles -SelfXScript $fake } 'a Self_X.ps1 that cannot be parsed is refused'
    $marker = Join-Path $work 'marker.ps1'
    [IO.File]::WriteAllText($marker, "'not run'")
    [IO.File]::WriteAllText($fake, "`$Global:SelfX_StylesXaml = '<Style/>'`n& '$marker' > '$(Join-Path $work 'ran.txt')'`n")
    $null = Get-WizardGuiSharedStyles -SelfXScript $fake
    Assert (-not (Test-Path -LiteralPath (Join-Path $work 'ran.txt'))) 'Self_X.ps1 is parsed, never run'
    Assert ((Get-WizardGuiCodeFolder -ToolsFolder $ScriptFolder) -like '*SelfX Service\Sources') 'code folder of the repository found'
    Assert-Throws { Get-WizardGuiCodeFolder -ToolsFolder (Join-Path $work 'tools') } 'no code folder next to tools is an error'

    # ---------------------------------------------------------- the window
    foreach ($culture in 'en', 'de') {
        foreach ($theme in 'Light', 'Dark') {
            Write-Host "Window ($culture, $theme, PowerShell $($PSVersionTable.PSVersion.Major))"
            $context = New-WizardGuiWindow -Culture $culture -Theme $theme
            Assert ($null -ne $context.Window -and $context.Window.Title -eq (Get-WText 'title')) 'XAML loads, title from the language file'
            Assert ($context.Window.Resources['Accent'] -is [System.Windows.Media.SolidColorBrush] -and $context.Window.Resources['WindowBg'].Color.ToString() -eq $(if ($theme -eq 'Dark') { '#FF1C1C1E' } else { '#FFF2F2F4' })) 'colors of the theme come from Branding.ps1'
            for ($i = 0; $i -lt $script:WizardGuiPages.Count; $i++) {
                $opened = $true
                try { Set-WizardGuiPage -Index $i -NoFocus } catch { $opened = $false; Write-Host "    $($_.Exception.Message)" }
                Assert ($opened -and $context.Ui["Page_$($script:WizardGuiPages[$i].Id)"].Visibility -eq 'Visible' -and $context.Ui.PageTitle.Text -notmatch '^\[') "page $($script:WizardGuiPages[$i].Id) opens with its title"
            }
            $unnamed = @($context.Fields.Values | Where-Object { -not [System.Windows.Automation.AutomationProperties]::GetName($_.Control) -or [System.Windows.Automation.AutomationProperties]::GetName($_.Control) -match '^\[' })
            Assert ($unnamed.Count -eq 0) 'every input has a name for screen readers'
            $noHelp = @($context.Fields.Values | Where-Object { -not [System.Windows.Automation.AutomationProperties]::GetHelpText($_.Control) })
            Assert ($noHelp.Count -eq 0) 'every input has the recommendation as help text'
            $buttons = @('BackButton', 'NextButton', 'LoadButton', 'SaveButton', 'AddUnitButton', 'RemoveUnitButton', 'BuildButton', 'CancelBuildButton', 'OpenFolderButton', 'CopyGuideButton',
                'SignNone', 'SignStore', 'SignFile', 'RefreshCertsButton', 'PfxBrowseButton', 'PfxOpenButton', 'CertList', 'PfxPathBox', 'PfxPasswordBox')
            Assert (@($buttons | Where-Object { -not [System.Windows.Automation.AutomationProperties]::GetName($context.Ui[$_]) }).Count -eq 0) 'every button has a name for screen readers'
            Assert ($context.Ui.NextButton.Content -is [System.Windows.Controls.AccessText] -and $context.Ui.NextButton.Content.Text.Contains('_')) 'buttons have an access key'
            $missingText = @($context.Fields.Values | Where-Object { $_.Label.Text -match '^\[' -or $_.Hint.Text -match '\[' })
            Assert ($missingText.Count -eq 0) 'no field shows a missing text'
            $context.Window.Close()
        }
    }

    # ---------------------------------------------------------- checks at the field
    Write-Host 'Checks at the field'
    $context = New-WizardGuiWindow -Culture 'de' -Theme 'Light'
    Set-WizardGuiPage -Index 1 -NoFocus
    Click $context.Ui.NextButton
    Assert ($context.Page -eq 1 -and $context.Ui.PageMessage.Visibility -eq 'Visible') 'required organisation name missing: the next page is blocked'
    Assert ($context.Fields['OrgName'].Error.Text -eq (Get-WText 'required') -and $context.Fields['OrgName'].Error.Visibility -eq 'Visible') 'the error is shown at the field'
    Set-Field 'OrgName' 'Contoso'
    Assert ($context.Fields['OrgName'].Error.Visibility -eq 'Collapsed') 'a valid value removes the error at once'
    Click $context.Ui.NextButton
    Assert ($context.Page -eq 2) 'with valid values the next page opens'
    Set-Field 'SupportMail' 'a@b'
    Assert ($context.Fields['SupportMail'].Error.Text -eq (Get-WText 'gui.kind.mail') -and $context.Fields['SupportMail'].Control.Tag -eq 'Error') 'a wrong e-mail address is shown at the field in the language of the window'
    Assert ([System.Windows.Automation.AutomationProperties]::GetHelpText($context.Fields['SupportMail'].Control) -like "$(Get-WText 'gui.kind.mail')*") 'the error is the help text for screen readers'
    Set-Field 'SupportMail' "a@example.com`nBcc: x@example.com"
    Assert ($context.Fields['SupportMail'].Error.Visibility -eq 'Visible') 'a header injection in the e-mail address is refused'
    Set-Field 'SupportMail' 'support@contoso.example'
    Assert ($context.Fields['SupportMail'].Error.Visibility -eq 'Collapsed') 'a valid e-mail address is accepted'
    Set-Field 'SupportWebsite' 'javascript:alert(1)'
    Assert ($context.Fields['SupportWebsite'].Error.Visibility -eq 'Visible') 'a script address is refused'
    Set-Field 'SupportWebsite' ''
    Set-WizardGuiPage -Index 3 -NoFocus
    $badLogo = Join-Path $work 'fake.png'
    [IO.File]::WriteAllText($badLogo, 'not an image')
    Set-Field 'LogoPath' $badLogo
    Assert ($context.Fields['LogoPath'].Error.Text -eq (Get-WText 'gui.logo.invalid') -and $null -eq $context.Ui.LogoPreview.Source) 'a file that is no image is refused at the field, no preview'
    Click $context.Ui.NextButton
    Assert ($context.Page -eq 3) 'a wrong logo blocks the next page'
    $png = Join-Path $work 'logo.png'
    $bitmap = [System.Windows.Media.Imaging.BitmapSource]::Create(2, 2, 96, 96, [System.Windows.Media.PixelFormats]::Bgra32, $null, [byte[]](0..15 | ForEach-Object { 200 }), 8)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create($png); $encoder.Save($stream); $stream.Dispose()
    Set-Field 'LogoPath' $png
    Assert ($context.Fields['LogoPath'].Error.Visibility -eq 'Collapsed' -and $null -ne $context.Ui.LogoPreview.Source) 'a valid logo is shown in the preview'
    Set-Field 'AccentColor' '#E20074'
    Assert ($context.Window.Resources['Accent'].Color.ToString() -eq '#FFE20074') 'a valid company color is shown at once'
    Set-Field 'AccentColor' 'red'
    Assert ($context.Fields['AccentColor'].Error.Visibility -eq 'Visible' -and $context.Window.Resources['Accent'].Color.ToString() -eq '#FF0072BC') 'a wrong color is refused, the window keeps the SelfX blue'
    Set-Field 'AccentColor' ''
    Set-WizardGuiPage -Index 4 -NoFocus
    Assert ($context.Fields['TicketMail'].Row.Visibility -eq 'Collapsed') 'ticket questions are hidden while the ticket function is off'
    Set-Field 'TicketEnabled' $true
    Assert ($context.Fields['TicketMail'].Row.Visibility -eq 'Visible' -and $context.Fields['TicketMail'].Control.Text -eq 'support@contoso.example') 'the ticket recipient shows the support address as default'
    Set-Field 'MultiOrg' $true
    Assert ($context.Ui.UnitsPanel.Visibility -eq 'Visible') 'the list of organisations appears for several organisations'
    Click $context.Ui.NextButton
    Assert ($context.Page -eq 4 -and $context.Ui.UnitsError.Visibility -eq 'Visible') 'without an organisation the next page is blocked'
    Click $context.Ui.AddUnitButton
    Set-Field 'UnitId' 'IT-Berlin'; Set-Field 'UnitMail' 'it-berlin@contoso.example'; Set-Field 'UnitGroupTags' 'DE;BER'
    Assert ($context.Fields['UnitGroupTags'].Error.Visibility -eq 'Visible') 'a group tag with ; is refused at the field'
    Set-Field 'UnitGroupTags' 'DE-IT1-BER'
    Click $context.Ui.AddUnitButton
    Set-Field 'UnitId' 'it-berlin'; Set-Field 'UnitMail' 'other@contoso.example'
    Assert ($context.Fields['UnitId'].Error.Text -eq (Get-WText 'gui.units.duplicate')) 'the same unit name twice is refused'
    Set-Field 'UnitId' '..\x'
    Assert ($context.Fields['UnitId'].Error.Visibility -eq 'Visible') 'a unit name with path characters is refused'
    Click $context.Ui.RemoveUnitButton
    Assert ($context.State.Units.Count -eq 1) 'a unit can be removed'
    Click $context.Ui.NextButton
    Assert ($context.Page -eq 5) 'with one valid organisation the next page opens'
    $context.Window.Close()

    # ---------------------------------------------------------- signature
    Write-Host 'Signature'
    $unique = [guid]::NewGuid().ToString('N').Substring(0, 10)
    $valid = New-SelfXTestCertificate -Name 'Gui'
    $expired = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=SelfX Gui Expired $unique" -CertStoreLocation 'Cert:\CurrentUser\My' `
        -NotBefore (Get-Date).AddDays(-30) -NotAfter (Get-Date).AddDays(-1) -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyExportPolicy Exportable -KeyUsage DigitalSignature
    $testSecret = 'SxPw-' + [guid]::NewGuid().ToString('N')
    $secure = New-Object System.Security.SecureString
    foreach ($character in $testSecret.ToCharArray()) { $secure.AppendChar($character) }
    $pfx = Join-Path $work 'test-signing.pfx'
    [IO.File]::WriteAllBytes($pfx, $valid.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $secure))
    $secure.Dispose()
    try {
        $context = New-WizardGuiWindow -Culture 'de' -Theme 'Light'
        $signingPage = Get-WizardGuiPageIndex 'signing'
        Assert ($signingPage -eq 6 -and (Get-WizardGuiPageIndex 'summary') -eq 7 -and (Get-WizardGuiPageIndex 'result') -eq 9) 'the page Signature comes after the further settings and before the summary'
        Set-WizardGuiPage -Index $signingPage -NoFocus
        Assert ($context.Ui.SignNone.IsChecked -and (Get-WizardGuiPageErrors -State $context.State -PageId 'signing').Count -eq 0 -and $context.Ui.SignNoneInfo.Visibility -eq 'Visible') 'default: no certificate, the consequences are explained, nothing is required'
        Assert ($null -eq (Get-WizardGuiSigning -State $context.State).Certificate) 'without a certificate nothing is signed'
        $context.Ui.SignStore.IsChecked = $true
        $tags = @($context.Ui.CertList.Items | ForEach-Object { $_.Tag })
        Assert ($tags -contains $valid.Thumbprint) 'a valid code signing certificate of the store is offered'
        Assert ($tags -notcontains $expired.Thumbprint) 'an expired certificate is not offered (not selectable)'
        Click $context.Ui.NextButton
        Assert ($context.Page -eq $signingPage -and $context.Ui.CertListError.Visibility -eq 'Visible') 'store without a selection: the next page is blocked, the error is shown at the list'
        $context.Ui.CertList.SelectedItem = @($context.Ui.CertList.Items | Where-Object { $_.Tag -eq $valid.Thumbprint })[0]
        Assert ($context.State.StoreCertificate.Thumbprint -eq $valid.Thumbprint -and $context.Ui.CertThumbprint.Text -match $valid.Thumbprint) 'the selected certificate is shown with its thumbprint'
        Assert ($context.Ui.CertCrlWarningBox.Visibility -eq 'Visible' -and $context.Ui.CertCrlWarning.Text -match [regex]::Escape((Get-WText 'gui.crl.none'))) 'a certificate without revocation list is warned about'
        Click $context.Ui.NextButton
        Assert ($context.Page -eq $signingPage -and $context.Fields['Timestamp'].Error.Text -eq (Get-WText 'gui.kind.timestamp')) 'without a time stamp service the next page is blocked'
        foreach ($badUrl in 'file://server/ts', 'https://user:pw@ts.example.com', 'ftp://ts.example.com', 'http://ts .example.com') {
            Set-Field 'Timestamp' $badUrl
            Assert ($context.Fields['Timestamp'].Error.Visibility -eq 'Visible') "time stamp service '$badUrl' is refused"
        }
        Set-Field 'Timestamp' 'http://timestamp.example.com'
        Assert ($context.Fields['Timestamp'].Error.Visibility -eq 'Collapsed') 'an http time stamp service is accepted'
        foreach ($badSigner in 'abc', ('AB' * 20 + ';calc'), (@(1..10 | ForEach-Object { 'AB' * 20 }) -join ',')) {
            Set-Field 'Additional' $badSigner
            Assert ($context.Fields['Additional'].Error.Visibility -eq 'Visible') 'an additional signer that is not a thumbprint (or more than 9) is refused'
        }
        Set-Field 'Additional' (('ab' * 20) + ', ' + ('CD' * 20))
        $signing = Get-WizardGuiSigning -State $context.State
        Assert ($signing.Certificate.Thumbprint -eq $valid.Thumbprint -and $signing.TimestampServer -eq 'http://timestamp.example.com' -and @($signing.AdditionalSigner).Count -eq 2) 'the build gets the certificate, the time stamp service and the additional signers'
        Set-Field 'Timestamp' ''
        Set-Field 'NoTimestamp' $true
        Assert ((Get-WizardGuiPageErrors -State $context.State -PageId 'signing').Count -eq 0 -and -not $context.Fields['Timestamp'].Control.IsEnabled) 'signing without a time stamp must be switched on explicitly'
        Set-Field 'NoTimestamp' $false
        Set-Field 'Timestamp' 'http://timestamp.example.com'
        $context.State.Raw['OrgName'] = 'Contoso'
        Click $context.Ui.NextButton
        Assert ($context.Page -eq (Get-WizardGuiPageIndex 'summary') -and $context.Ui.SummaryBox.Text -match $valid.Thumbprint) 'with a certificate and a time stamp the summary names the certificate'
        Set-Field 'ConfigureOnly' $true
        Assert ($context.Fields['ConfigureOnly'].Error.Text -eq (Get-WText 'gui.sign.configureonly')) 'only configure and sign at the same time is refused at the field'
        Set-Field 'ConfigureOnly' $false
        Set-WizardGuiProgress
        Assert ((@($context.ProgressRows.Keys) -contains 'sign') -and (@($context.ProgressRows.Keys) -contains 'catalog')) 'the progress list shows signing and the catalog'
        # The certificate reaches the background build: with a missing IntuneWinAppUtil.exe the build stops after the check of the certificate.
        $context.State.Build.Payload = Join-Path $work 'no-payload'
        New-Item -ItemType Directory -Path $context.State.Build.Payload -Force | Out-Null
        $context.State.Build.Tool = Join-Path $work 'missing\IntuneWinAppUtil.exe'
        $context.State.Build.Output = Join-Path $work 'signed-out'
        $build = Start-WizardGuiBuild -State $context.State
        Wait-GuiBuild -Build $build -Seconds 60
        Assert ("$($build.Sync.Error)" -match 'IntuneWinAppUtil' -and -not (Test-Path -LiteralPath $context.State.Build.Output)) 'the background build receives the signing values and stops before anything is written'
        $context.Window.Close()

        # PFX file: wrong password, right password. The password is a test value; it must not appear anywhere.
        $context = New-WizardGuiWindow -Culture 'de' -Theme 'Light'
        Set-WizardGuiPage -Index $signingPage -NoFocus
        $context.Ui.SignFile.IsChecked = $true
        $context.Ui.PfxPathBox.Text = $pfx
        $context.Ui.PfxPasswordBox.Password = 'wrong-' + $testSecret
        Click $context.Ui.PfxOpenButton
        Assert ($null -eq $context.State.PfxCertificate -and $context.Ui.PfxError.Visibility -eq 'Visible' -and $context.Ui.PfxPasswordBox.SecurePassword.Length -eq 0) 'a wrong password is refused; the box is emptied'
        $wrongText = Get-AllWindowText -Root $context.Window
        Assert ($wrongText -notmatch [regex]::Escape($testSecret)) 'the password is not in any text after a wrong password (error, help texts, title)'
        $context.Ui.PfxPasswordBox.Password = $testSecret
        $keySource = New-Object System.Windows.Interop.HwndSource(0, 0, 0, 0, 0, 'SelfXTestKeys', [IntPtr]::Zero)
        try {
            $enter = New-Object System.Windows.Input.KeyEventArgs([System.Windows.Input.Keyboard]::PrimaryDevice, $keySource, 0, [System.Windows.Input.Key]::Return)
            $enter.RoutedEvent = [System.Windows.Input.Keyboard]::KeyDownEvent
            $context.Ui.PfxPasswordBox.RaiseEvent($enter)
        }
        finally { $keySource.Dispose() }
        Assert ($null -ne $context.State.PfxCertificate -and $context.State.PfxCertificate.Thumbprint -eq $valid.Thumbprint -and $context.State.PfxCertificate.HasPrivateKey) 'Enter in the password box opens the PFX file (with the private key)'
        Assert ($context.Ui.PfxPasswordBox.SecurePassword.Length -eq 0 -and $context.Ui.PfxStatus.Visibility -eq 'Visible') 'after opening the password box is empty'
        $context.State.Raw['OrgName'] = 'Contoso'
        Set-Field 'Timestamp' 'http://timestamp.example.com'
        Set-WizardGuiPage -Index (Get-WizardGuiPageIndex 'summary') -NoFocus
        $allText = Get-AllWindowText -Root $context.Window
        $stateText = (@($context.State.Raw, $context.State.Signing, $context.State.Build) | ConvertTo-Json -Depth 4)
        $answerPath = Join-Path $work 'signed-answers.json'
        Save-WizardAnswers -Path $answerPath -Answers (Get-WizardGuiAnswers -State $context.State) -Language 'de'
        $answerText = [IO.File]::ReadAllText($answerPath)
        Assert ($allText -notmatch [regex]::Escape($testSecret)) 'the password is in no text of the window, no help text and not in the window title'
        Assert ($stateText -notmatch [regex]::Escape($testSecret) -and $answerText -notmatch [regex]::Escape($testSecret)) 'the password is not in the state and not in the answer file'
        Assert ($answerText -notmatch '(?i)pfx|password|kennwort|thumbprint|' + $valid.Thumbprint) 'the answer file has no certificate data'
        $context.Window.Close()
        Clear-WizardGuiCertificates -State $context.State
        Assert ($null -eq $context.State.PfxCertificate) 'the certificates are released when the window closes'

        # Details of a certificate and the revocation list addresses.
        $info = Get-WizardCertificateInfo -Certificate $valid
        Assert ($info.Thumbprint -eq $valid.Thumbprint -and @($info.Warnings) -contains 'gui.crl.none') 'certificate details: no revocation list is a warning'
        foreach ($hostName in 'ca01', 'pki.contoso.local', '10.1.2.3', '192.168.0.10', 'pki.corp', '') { Assert (Test-WizardInternalHost $hostName) "'$hostName' counts as internal" }
        foreach ($hostName in 'crl.contoso.example', 'pki.example.com') { Assert (-not (Test-WizardInternalHost $hostName)) "'$hostName' counts as public" }
    }
    finally {
        Remove-SelfXTestCertificate -Thumbprint $valid.Thumbprint
        Remove-SelfXTestCertificate -Thumbprint $expired.Thumbprint
    }

    # ---------------------------------------------------------- instructions as steps
    Write-Host 'Instructions as steps'
    Initialize-WizardTexts -Folder $WizardFolder -Culture 'en'
    $signers = @(('AB' * 20), ('cd' * 20))
    $guideArgs = @{ Answers = @{ OrgName = 'Contoso'; Units = @() }; Version = '3.1.0'; PackageFile = 'p.intunewin'; DetectionFile = 'd.ps1'; TrustedSigner = $signers; RuleFiles = @('SelfX.AppLocker.xml') }
    $guide = Get-SelfXIntuneGuideSteps @guideArgs -OutputFolder 'C:\Out'
    $text = New-SelfXIntuneGuide @guideArgs
    $joined = (@($guide.Header) + @('') + @($guide.Steps | ForEach-Object { @($_.Lines) + @('') }) + @($guide.Footer)) -join "`r`n"
    Assert ($text -eq ($joined + "`r`n")) 'the text file of the instructions is the lines of the steps'
    $install = @($guide.Steps | ForEach-Object { $_.Copies } | Where-Object { $_.Label -eq 'gui.copy.install' })[0].Value
    Assert ($install -match ('-TrustedSigner ' + ('AB' * 20) + ',' + ('CD' * 20) + '$')) 'copy value: install command with both signers, comma without a space'
    Assert (@($guide.Steps | ForEach-Object { $_.Copies } | Where-Object { $_.Label -eq 'gui.copy.detection' })[0].Value -eq 'C:\Out\d.ps1') 'copy value: full path of the detection script'
    Assert ((@($guide.Steps | ForEach-Object { $_.Id }) -join ',') -eq 'app,program,requirements,detection,dependency,assignment,trust,certchange,rules,asr,test') 'steps in the mode Signature: trust and change of the certificate before the rules'
    Assert ($text -match '4006' -and $text -match '4007' -and $text -match 'Install\.log' -and $text -match '60 minutes') 'instructions: events 4006/4007, refused signature without Install.log, 60 minutes'
    Assert-Throws { Get-SelfXIntuneGuideSteps -Answers @{ OrgName = 'C'; Units = @() } -Version '1' -TrustedSigner @(1..11 | ForEach-Object { '{0:X40}' -f $_ }) } 'more than 10 signers are refused'
    $hashGuide = Get-SelfXIntuneGuideSteps -Answers @{ OrgName = 'C'; Units = @() } -Version '1' -PackageFile 'p' -DetectionFile 'd'
    Assert (@($hashGuide.Steps | Where-Object { $_.Id -in 'trust', 'certchange' }).Count -eq 0) 'mode Hash: no trust and no certificate steps'

    # ---------------------------------------------------------- answers of the window = answers of the console
    Write-Host 'Answers of the window and the console'
    $payload = New-FakePayload -Folder (Join-Path $work 'fake')
    $inputValues = [ordered]@{
        ToolLanguage = 'de'; ShowLanguageSetting = $false; OrgName = 'Contoso <&> Test'; ToolName = 'SelfX'
        SupportMail = 'it-support@contoso.example'; SupportPhone = '+49 30 1234'; SupportHours = 'Mo.-Fr. 08:00-17:00'
        SupportWebsite = 'https://support.contoso.example'; SupportTeams = 'team@contoso.example'; LogoPath = $png; AccentColor = '#e20074'
        TicketEnabled = $true; TicketMail = 'servicedesk@contoso.example'; TicketSubjectTag = 'SelfX'; MultiOrg = $true
        HybridJoin = $true; UseGroupTags = $true; UseDeviceClass = $true
        CopilotEnabled = $true; CopilotAudience = 'Admin'; CopilotClearClipboard = $false
        WikiEnabled = $true; WikiUrl = 'https://wiki.contoso.example/start'; WikiName = 'Contoso <Wiki>'
        TrayIcon = $true; ShortcutDesktop = $false; ShortcutStartMenu = $true; Expert = $true; LogRetention = '30'; FileCheck = 'Audit'; Privileges = 'Restricted'
        AppLockerRules = $false; WdacBasePolicyId = ''
    }
    $units = @(
        [ordered]@{ UnitId = 'IT-Berlin'; UnitMail = 'it-berlin@contoso.example'; UnitCc = ''; UnitGroupTags = 'DE-IT1-BER, DE-IT2-BER'; UnitOUs = 'OU=Berlin'; UnitCategories = '' },
        [ordered]@{ UnitId = 'IT-Mobile'; UnitMail = 'it-mobile@contoso.example'; UnitCc = 'service@contoso.example'; UnitGroupTags = ''; UnitOUs = ''; UnitCategories = 'Tablet' }
    )
    $cases = @(
        @{ Name = 'all answers'; Input = $inputValues; Units = $units },
        @{ Name = 'only the required answer (defaults)'; Input = [ordered]@{ OrgName = 'Contoso' }; Units = @() }
    )
    for ($caseIndex = 0; $caseIndex -lt $cases.Count; $caseIndex++) {
        $case = $cases[$caseIndex]
        $context = New-WizardGuiWindow -Culture 'de' -Theme 'Light'
        foreach ($key in $case.Input.Keys) { Set-Field $key $case.Input[$key] }
        foreach ($unit in $case.Units) {
            Click $context.Ui.AddUnitButton
            foreach ($key in $unit.Keys) { Set-Field $key $unit[$key] }
        }
        $context.State.Build.Payload = $payload
        $context.State.Build.ConfigureOnly = $true
        $context.State.Build.Output = Join-Path $work ("gui-" + $caseIndex)
        $evaluation = Get-WizardGuiEvaluation -State $context.State
        Assert ($evaluation.Errors.Count -eq 0 -and @($evaluation.UnitErrors | Where-Object { $_.Count }).Count -eq 0 -and $evaluation.BuildErrors.Count -eq 0) "$($case.Name): the window reports no error"
        $guiAnswers = Get-WizardGuiAnswers -State $context.State

        # Console: the same input as an answer file (lists as arrays, as a saved file has them).
        $file = [ordered]@{ WizardLanguage = 'de' }
        foreach ($key in $case.Input.Keys) { $file[$key] = $case.Input[$key] }
        $file['Units'] = @($case.Units | ForEach-Object { [ordered]@{ UnitId = $_.UnitId; UnitMail = $_.UnitMail; UnitCc = $_.UnitCc; UnitGroupTags = @($_.UnitGroupTags.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }); UnitOUs = @($_.UnitOUs.Split(',') | Where-Object { $_ }); UnitCategories = @($_.UnitCategories.Split(',') | Where-Object { $_ }) } })
        $answerFile = Join-Path $work ("answers-" + $caseIndex + '.json')
        [IO.File]::WriteAllText($answerFile, ($file | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
        $source = @{}; foreach ($property in (Get-Content -LiteralPath $answerFile -Raw | ConvertFrom-Json).PSObject.Properties) { $source[$property.Name] = $property.Value }
        $script:WizardInteractive = $false
        $consoleAnswers = Read-WizardAnswers -Source $source
        $guiSaved = Join-Path $work 'gui.json'; $consoleSaved = Join-Path $work 'console.json'
        Save-WizardAnswers -Path $guiSaved -Answers $guiAnswers -Language 'de'
        Save-WizardAnswers -Path $consoleSaved -Answers $consoleAnswers -Language 'de'
        Assert ((Get-FileHash $guiSaved).Hash -eq (Get-FileHash $consoleSaved).Hash) "$($case.Name): the answer object of the window is identical to the console"

        # Same input, two builds with -ConfigureOnly: the console script and the background runspace of the window.
        $consoleOut = Join-Path $work ("console-" + $caseIndex)
        $output = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptFolder 'New-SelfXPackage.ps1') -AnswerFile $answerFile -OutputFolder $consoleOut -PayloadFolder $payload -ConfigureOnly -Language de 2>&1
        Assert ($LASTEXITCODE -eq 0) ("$($case.Name): console build exits with 0" + $(if ($LASTEXITCODE -ne 0) { ': ' + ($output | Out-String) }))
        $build = Start-WizardGuiBuild -State $context.State
        Wait-GuiBuild -Build $build
        Assert ($null -ne $build.Sync.Result -and -not $build.Sync.Error) ("$($case.Name): build of the window in the background runspace succeeded" + $(if ($build.Sync.Error) { ': ' + $build.Sync.Error }))
        Assert ((@($build.Steps) -join ',') -eq 'check,copy,config,guide,finish') "$($case.Name): the window received every step of the progress"
        foreach ($name in 'selfx-answers.json', 'package\Config\Tool_Config.xml', 'package\Config\Ticket_Config.xml', 'SelfX-Intune-Guide.de.txt') {
            $a = Join-Path $consoleOut $name; $b = Join-Path $context.State.Build.Output $name
            Assert ((Test-Path -LiteralPath $a) -and (Test-Path -LiteralPath $b) -and (Get-FileHash $a).Hash -eq (Get-FileHash $b).Hash) "$($case.Name): $name of the window is identical to the console"
        }
        if ($case.Units.Count) {
            $guide = Get-Content -LiteralPath (Join-Path $context.State.Build.Output 'SelfX-Intune-Guide.de.txt') -Raw
            $scripts = @($build.Sync.Result.ScriptFiles)
            Assert ($scripts.Count -eq 3 -and @($scripts | Where-Object { $guide -match ('(?m)^   - ' + [regex]::Escape($_) + '\r?$') }).Count -eq 3) "$($case.Name): each platform script is its own entry of the result and its own line of the instructions"
        }
        $saved = Get-Content -LiteralPath (Join-Path $context.State.Build.Output 'selfx-answers.json') -Raw
        Assert ($saved -notmatch '(?i)password|pfx|secret|privatekey|thumbprint') "$($case.Name): selfx-answers.json of the window has no password, key or certificate"
        $context.Window.Close()
    }

    # ---------------------------------------------------------- answer files
    Write-Host 'Answer files'
    $state = New-WizardGuiState -ToolsFolder $ScriptFolder
    $language = Import-WizardGuiAnswers -State $state -Path (Join-Path $work 'answers-0.json')
    Assert ($language -eq 'de' -and $state.Raw['OrgName'] -eq 'Contoso <&> Test' -and $state.Units.Count -eq 2 -and $state.Units[0].UnitGroupTags -eq 'DE-IT1-BER, DE-IT2-BER') 'an answer file is loaded with its units and language'
    Assert ((Get-FileHash $guiSaved).Hash -ne '' -and @((Get-WizardGuiEvaluation -State $state).Errors.Keys).Count -eq 0) 'the loaded answers are valid'
    $bad = Join-Path $work 'bad.json'
    [IO.File]::WriteAllText($bad, '{ "OrgName": "x", "PfxPassword": "secret" }')
    Assert-Throws { Import-WizardGuiAnswers -State $state -Path $bad } 'an unknown answer (for example a password) is refused'
    [IO.File]::WriteAllText($bad, 'this is not json')
    Assert-Throws { Import-WizardGuiAnswers -State $state -Path $bad } 'a file that is not JSON is refused'
    [IO.File]::WriteAllText($bad, ('{ "OrgName": "' + ('x' * 1100000) + '" }'))
    Assert-Throws { Import-WizardGuiAnswers -State $state -Path $bad } 'an answer file over 1 MB is refused'
    $state.Raw['SupportMail'] = 'not a mail'
    Assert-Throws { Get-WizardGuiAnswers -State $state } 'answers with an error are not given to the build'

    # ---------------------------------------------------------- cancel
    Write-Host 'Cancel'
    $cancelOut = Join-Path $work 'cancelled\out'
    $state = New-WizardGuiState -ToolsFolder $ScriptFolder
    $state.Raw['OrgName'] = 'Contoso'
    $state.Build.Payload = $payload; $state.Build.ConfigureOnly = $true; $state.Build.Output = $cancelOut
    $build = Start-WizardGuiBuild -State $state
    Stop-WizardGuiBuild -Build $build
    Wait-GuiBuild -Build $build
    $leftovers = @(Get-ChildItem -LiteralPath (Join-Path $work 'cancelled') -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.selfx-*' })
    $complete = (Test-Path -LiteralPath (Join-Path $cancelOut 'selfx-answers.json'))
    Assert ($build.Cancelled -and $leftovers.Count -eq 0) 'a cancelled build leaves no work folder'
    Assert ((-not (Test-Path -LiteralPath $cancelOut)) -or $complete) 'a cancelled build leaves no half-finished output folder'

    $after = @((Get-FileHash (Join-Path $RepositoryRoot 'SelfX Service\Sources\Tool_Config.xml')).Hash, (Get-FileHash (Join-Path $RepositoryRoot 'SelfX Service\Sources\Ticket_Config.xml')).Hash) -join ','
    Assert ($after -eq $repoDigest) 'repository files are unchanged'

    # ---------------------------------------------------------- static checks of the window script
    Write-Host 'Static checks'
    $guiText = [IO.File]::ReadAllText((Join-Path $WizardFolder 'SelfXWizardGui.ps1'))
    Assert ($guiText -notmatch '(?i)Invoke-Expression|\biex\b|Add-Type\s+-TypeDefinition') 'no Invoke-Expression and no compiled source text'
    Assert ($guiText -notmatch '(?i)ConvertTo-WizardValue\s+-Kind\s+''(mail|url)''.*-replace') 'the window does not change the checks'
    $addScript = @([regex]::Matches($guiText, '\.AddScript\((.+?)\)\.AddParameters\('))
    Assert ($addScript.Count -eq 1 -and $addScript[0].Groups[1].Value -eq '$script:WizardGuiBuildScript.ToString()' -and ([regex]::Matches($guiText, 'AddScript\(')).Count -eq 1) 'the runspace runs only the constant build script (values are parameters)'
    Assert ($guiText -cnotmatch '\.Password\b' -and $guiText -match '\.SecurePassword') 'the window reads the password box only as SecureString (never the property Password)'
    Assert ($guiText -notmatch '(?i)ConvertFrom-SecureString|PtrToString|SecureStringToBSTR|SecureStringToGlobalAlloc|NetworkCredential') 'the window never turns the password into text'
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $WizardFolder 'SelfXWizardGui.ps1'), [ref]$tokens, [ref]$errors)
    Assert (@($errors).Count -eq 0) 'SelfXWizardGui.ps1 parses'
    Assert ([IO.File]::ReadAllText((Join-Path $ScriptFolder 'Start-SelfXPackageWizard.cmd')) -match '%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe" -NoProfile -STA ') 'the start file runs Windows PowerShell by its full path with -NoProfile -STA'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed -gt 0) { Write-Host "$($script:Failed) test(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed.' -ForegroundColor Green
exit 0
