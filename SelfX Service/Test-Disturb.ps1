<#
.SYNOPSIS
    Tests the hint before disruptive actions (SelfXDisturb.ps1, Disruptive in Issues_List.xml, Disturb_Warning in Tool_Config.xml).

.DESCRIPTION
    Checks without a window and without a service:
      - Get-SelfXDisturbKind for every state of SHQueryUserNotificationState (1 to 7), 0 (cannot be read) and values outside the range;
      - Get-SelfXDisturbWarning for every combination of setting, marking and state, an empty text, a state provider that fails
        and one that returns nothing (the hint is only added when everything says yes);
      - Get-SelfXNotificationState on this device: only a number from 0 to 7, nothing is changed (the API only reads);
      - the delivered catalogue: the actions of the six disruptive scripts are marked on every entry, no other action is, and
        Get-SelfXLocalizedActions passes the field on;
      - the delivered Tool_Config.xml has Disturb_Warning = True and every language file has Disturb_Warning_Text;
      - static checks of the code: Self_X.ps1 reads the setting and uses the hint in the confirmation of an action and of the
        restart; SelfXDisturb.ps1 does not touch the registry (no ConsentStore), no process, no service, no pipe, no file and no log.
    Nothing is started, written or changed. Run in PowerShell 7: pwsh -NoProfile -ExecutionPolicy Bypass -File .\Test-Disturb.ps1

.NOTES
    Name    : Test-Disturb.ps1
    Package : SelfX Service
    Context : Packaging test (not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-28  fubu2k               Initial version.
#>
$ErrorActionPreference = 'Stop'
$sources = Join-Path $PSScriptRoot 'Sources'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]

function Assert-True {
	param([bool]$Condition, [string]$Message)
	$script:checks++
	if (-not $Condition) { $script:errors.Add($Message) }
}
function Assert-Equal {
	param($Actual, $Expected, [string]$Message)
	$script:checks++
	if ("$Actual" -cne "$Expected") { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}

. (Join-Path $sources 'SelfXDisturb.ps1')
$disturbText = [IO.File]::ReadAllText((Join-Path $sources 'SelfXDisturb.ps1'))
$selfXText = [IO.File]::ReadAllText((Join-Path $sources 'Self_X.ps1'))

# --- Kind of the disturbance (pure) ------------------------------------------------------------------
$kinds = @(@(0, 'None'), @(1, 'None'), @(2, 'FullScreen'), @(3, 'FullScreen'), @(4, 'Presentation'), @(5, 'None'), @(6, 'QuietTime'), @(7, 'None'), @(8, 'None'), @(99, 'None'), @(-1, 'None'))
foreach ($pair in $kinds) { Assert-Equal (Get-SelfXDisturbKind -State $pair[0]) $pair[1] "Kind of state $($pair[0])" }

# --- Warning text: only when setting, marking, text and state all say yes ------------------------------------
$text = 'HINT'
foreach ($enabled in $true, $false) {
	foreach ($disruptive in $true, $false) {
		foreach ($state in 0..8) {
			$expected = if ($enabled -and $disruptive -and (Get-SelfXDisturbKind -State $state) -ne 'None') { $text } else { '' }
			$provider = [scriptblock]::Create("$state")
			Assert-Equal (Get-SelfXDisturbWarning -Enabled $enabled -Disruptive $disruptive -Text $text -StateProvider $provider) $expected "Warning with Enabled=$enabled Disruptive=$disruptive State=$state"
		}
	}
}
Assert-Equal (Get-SelfXDisturbWarning -Enabled $true -Disruptive $true -Text '' -StateProvider { 4 }) '' 'No hint without a text (empty)'
Assert-Equal (Get-SelfXDisturbWarning -Enabled $true -Disruptive $true -Text '   ' -StateProvider { 4 }) '' 'No hint without a text (blank)'
Assert-Equal (Get-SelfXDisturbWarning -Enabled $true -Disruptive $true -Text $text -StateProvider { throw 'state failed' }) '' 'A failing state provider gives no hint and no error'
Assert-Equal (Get-SelfXDisturbWarning -Enabled $true -Disruptive $true -Text $text -StateProvider { $null }) '' 'A provider without a value gives no hint'
Assert-Equal (Get-SelfXDisturbWarning -Enabled $true -Disruptive $true -Text $text -StateProvider { 'abc' }) '' 'A provider with a non-number gives no hint'
# The state is read only when everything else says yes (setting off or action not marked: nothing is asked).
$script:asked = 0
[void](Get-SelfXDisturbWarning -Enabled $false -Disruptive $true -Text $text -StateProvider { $script:asked++; 4 })
[void](Get-SelfXDisturbWarning -Enabled $true -Disruptive $false -Text $text -StateProvider { $script:asked++; 4 })
Assert-Equal $script:asked 0 'The state is not read when the setting is off or the action is not marked'

# --- The real call on this device (read only) ------------------------------------------------------------
if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
	$real = Get-SelfXNotificationState
	Assert-True ($real -is [int] -and $real -ge 0 -and $real -le 7) "Get-SelfXNotificationState returns a number from 0 to 7 (got '$real')"
}

# --- Delivered catalogue and settings ---------------------------------------------------------------------
$expectedScripts = @('SelfX_Device_AirePlaneMode.ps1', 'SelfX_Excel_Reboot.ps1', 'SelfX_Outlook_Reboot.ps1', 'SelfX_Outlook_TeamsAddIn.ps1', 'SelfX_Teams_ResetCache.ps1', 'SelfX_Word_Reboot.ps1')
$catalog = [xml][IO.File]::ReadAllText((Join-Path $sources 'Issues_List.xml'))
$marked = @($catalog.SelectNodes('//Action[Disruptive]'))
Assert-True ($marked.Count -gt 0) 'The delivered catalogue marks actions Disruptive'
foreach ($action in @($catalog.SelectNodes('//Action'))) {
	$scriptName = "$($action.Script)".Trim()
	$isMarked = @($action.SelectNodes('Disruptive')).Count -eq 1
	Assert-Equal $isMarked ($scriptName -in $expectedScripts) "Action $($action.GetAttribute('Id')) ($scriptName): marked Disruptive only when its script is one of the six"
}
foreach ($scriptName in $expectedScripts) { Assert-True (@($marked | Where-Object { "$($_.Script)".Trim() -ceq $scriptName }).Count -gt 0) "The script $scriptName is used by a marked action" }
Assert-True (@($marked | Where-Object { "$($_.Context)".Trim() -eq 'Link' }).Count -eq 0) 'No link action is marked'
Assert-Equal "$($catalog.Actions.XML_Version)".Trim() '2.4.14' 'XML_Version of the catalogue'

. (Join-Path $sources 'Localization.ps1')
[void](Initialize-SelfXLanguage -LanguageFolder (Join-Path $sources 'Languages') -Language 'en')
$rows = @(Get-SelfXLocalizedActions -Catalog $catalog -Section 'Quick_Solution') + @(Get-SelfXLocalizedActions -Catalog $catalog -Section 'Detailed_Solution')
Assert-Equal (@($rows | Where-Object { $_.Id -eq 'Q_Teams' })[0].Disruptive) 'True' 'Get-SelfXLocalizedActions passes Disruptive on (Q_Teams)'
Assert-Equal (@($rows | Where-Object { $_.Id -eq 'Q_Network_Restart' })[0].Disruptive) 'True' 'Get-SelfXLocalizedActions passes Disruptive on (Q_Network_Restart)'
Assert-Equal (@($rows | Where-Object { $_.Id -eq 'Q_Store' })[0].Disruptive) '' 'An unmarked action has an empty Disruptive (Q_Store)'
Assert-Equal @($rows | Where-Object { $_.Disruptive -eq 'True' }).Count $marked.Count 'Every marked action arrives as a row'

$toolConfig = [xml][IO.File]::ReadAllText((Join-Path $sources 'Tool_Config.xml'))
Assert-Equal "$($toolConfig.GUI_Config.Disturb_Warning)".Trim() 'True' 'The delivered Tool_Config.xml has Disturb_Warning = True'
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $sources 'Languages') -Filter '*.xml') {
	$language = [xml][IO.File]::ReadAllText($file.FullName)
	$value = "$($language.SelfX_Language.UI.Disturb_Warning_Text)".Trim()
	Assert-True ($value.Length -gt 10 -and $value.Length -lt 200) "$($file.Name) has Disturb_Warning_Text"
	Assert-True ($value -notmatch '[<>{}&]') "$($file.Name) Disturb_Warning_Text has no markup or placeholder"
}

# --- Static checks of the code ---------------------------------------------------------------------------
Assert-True ($selfXText -match '\. "\$Current_Folder\\SelfXDisturb\.ps1"') 'Self_X.ps1 loads SelfXDisturb.ps1'
Assert-True ($selfXText -match '\$Global:SelfX_DisturbWarning = \(Get-SelfXText "Disturb_Warning" "True"\) -ne ''False''') 'Self_X.ps1 reads Disturb_Warning (default on, only False switches off)'
Assert-Equal ([regex]::Matches($selfXText, 'Get-SelfXDisturbWarning -Enabled \$Global:SelfX_DisturbWarning')).Count 2 'Self_X.ps1 uses the hint in two places (action and restart)'
Assert-True ($selfXText -match "-Disruptive \(\(\[string\]\`$rowObj\.Disruptive\)\.Trim\(\) -eq 'True'\)") 'The action confirmation uses the Disruptive field of the row'
Assert-True ($selfXText -match "Write-SelfXLog `"Action '\`$\(\`$rowObj\.Id\)': disturbance hint added") 'The log names the action Id only'
$noComments = [regex]::Replace($disturbText, '(?s)^<#.*?#>', '')
$noComments = ($noComments -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
foreach ($forbidden in 'ConsentStore', 'CapabilityAccessManager', 'HKCU', 'HKLM', 'Get-ItemProperty', 'Get-Process', 'Start-Process', 'Write-SelfXLog', 'Out-File', 'Set-Content', 'Add-Content', 'NamedPipe', 'Invoke-SelfXServiceRequest', 'Get-CimInstance', 'quser', 'WTSEnumerateSessions') {
	Assert-True (-not $noComments.Contains($forbidden)) "SelfXDisturb.ps1 does not use $forbidden"
}
Assert-True ($disturbText -cmatch 'SHQueryUserNotificationState' -and $disturbText -cmatch 'shell32\.dll') 'SelfXDisturb.ps1 calls SHQueryUserNotificationState of shell32.dll'
Assert-True (-not ($disturbText -cmatch '[^\x00-\x7F]')) 'SelfXDisturb.ps1 is plain ASCII (no byte order mark needed)'
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($disturbText, [ref]$null, [ref]$parseErrors)
Assert-Equal @($parseErrors).Count 0 'SelfXDisturb.ps1 parses'
# The file is a code file of the package (class Code) and is listed once.
$common = [IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\SelfXPackage.Common.ps1'))
Assert-Equal ([regex]::Matches($common, "'SelfXDisturb\.ps1'")).Count 1 'SelfXPackage.Common.ps1 lists SelfXDisturb.ps1 once as a code file'

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "FAILED: $($script:errors.Count) of $script:checks checks."
	exit 1
}
Write-Output "PASS: $script:checks checks. Nothing was started, written or changed."
exit 0
