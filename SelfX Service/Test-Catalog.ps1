<#
.SYNOPSIS
    Static consistency checks of the action catalogue, Health_Config.xml and the scripts that run as SYSTEM.

.DESCRIPTION
    The SelfX service runs a script as SYSTEM when its plain file name is listed with Context=System in
    Sources\Issues_List.xml (or as a remediation in Sources\Health_Config.xml). Every signed-in user can send
    that request through the named pipe. This test keeps that whitelist safe for every release:

      - every action has a unique Id, a Context of exactly User, System or Link; User and System actions have a plain
        script file name (letters, digits, _ - . only, no path, no "..", ends with .ps1) that exists in Scripts_to_run;
        Link actions have no script and name a Tool_Config.xml key Link_<Name> with a valid https address;
      - no script is listed with both contexts (the service accepts a script when ANY entry says System);
      - every remediation of Health_Config.xml points to an existing plain file name, is not listed as a
        user action, and has a TimeoutSeconds between 1 and 7200 when it is set;
      - every script that can run as SYSTEM declares "Context : System" in its header, has no mandatory
        parameter in its script-level param block (the service starts it without parameters) and parses;
      - user scripts do not declare "Context : System" in their header;
      - every action (element TerminalServer) and every remediation (attribute TerminalServer) is classified Show or Hide,
        the same on every entry of a script (Environment_Mode TerminalServer); negative examples prove the rule.
      - the optional element Disruptive of an action is exactly True, only on an action with a script, and the same on every entry
        of a script (hint before disruptive actions); negative examples prove the rule.

    Nothing is executed and nothing is changed: the files are only read and parsed.
    Run in Windows PowerShell 5.1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Catalog.ps1

.PARAMETER SourcesFolder
    Folder with Issues_List.xml, Health_Config.xml and Scripts_to_run. Default: Sources next to this script.

.NOTES
    Name    : Test-Catalog.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version.
    3.1.0    2026-11-27  fubu2k               Remediation UserScript: plain file name, exists, declares 'Context : User', is not a SYSTEM
                                              script of the catalogue or of another remediation and has no mandatory parameter.
    3.1.0    2026-11-27  fubu2k               Required classification TerminalServer (Show or Hide) on every action and remediation, the same
                                              for every entry of a script, with negative examples
    3.1.0    2026-11-28  fubu2k               Optional element Disruptive: exactly True, only with a script, the same for every entry of a script (negative examples)
    3.1.0    2026-11-28  fubu2k               Classification of Office licence reset, OneDrive reset and group policy update (Show) and of No sound (Hide) checked by name;
                                              what a terminal server offers is decided by Test-SelfXShownInEnvironment (the rule of the window)
#>
param(
	[string]$SourcesFolder = (Join-Path $PSScriptRoot 'Sources')
)

$ErrorActionPreference = 'Stop'
$scripts = Join-Path $SourcesFolder 'Scripts_to_run'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]

function Assert-True {
	param([bool]$Condition, [string]$Message)
	$script:checks++
	if (-not $Condition) { $script:errors.Add($Message) }
}

# Same rule as the service (ScriptNamePattern in SelfXService.cs): a plain file name only.
function Test-PlainScriptName {
	param([string]$Name)
	return ($Name -imatch '^[A-Za-z0-9_\-\.]{1,100}\.ps1\z') -and -not $Name.Contains('..')
}

function Get-ScriptInfo {
	param([string]$Name)
	$path = Join-Path $scripts $Name
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
	$text = [IO.File]::ReadAllText($path)
	$tokens = $null
	$parseErrors = $null
	$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
	$mandatory = @()
	if ($ast.ParamBlock) {
		foreach ($parameter in $ast.ParamBlock.Parameters) {
			foreach ($attribute in $parameter.Attributes) {
				if ($attribute -is [Management.Automation.Language.AttributeAst] -and $attribute.TypeName.Name -eq 'Parameter') {
					foreach ($argument in $attribute.NamedArguments) {
						if ($argument.ArgumentName -eq 'Mandatory' -and ($argument.ExpressionOmitted -or "$($argument.Argument.Extent.Text)" -notmatch '^\$false$')) { $mandatory += $parameter.Name.VariablePath.UserPath }
					}
				}
			}
		}
	}
	$header = if ($text.Contains('#>')) { $text.Substring(0, $text.IndexOf('#>')) } else { '' }
	$context = ''
	if ($header -match '(?m)^\s*Context\s*:\s*(\w+)') { $context = $Matches[1] }
	return [pscustomobject]@{ Name = $Name; ParseErrors = @($parseErrors).Count; MandatoryParameters = $mandatory; HeaderContext = $context }
}

$catalogPath = Join-Path $SourcesFolder 'Issues_List.xml'
$healthPath = Join-Path $SourcesFolder 'Health_Config.xml'
Assert-True (Test-Path -LiteralPath $catalogPath) "Issues_List.xml exists ($catalogPath)"
Assert-True (Test-Path -LiteralPath $healthPath) "Health_Config.xml exists ($healthPath)"
if ($script:errors.Count) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }

$catalog = [xml][IO.File]::ReadAllText($catalogPath)
$toolConfigPath = Join-Path $SourcesFolder 'Tool_Config.xml'
Assert-True (Test-Path -LiteralPath $toolConfigPath) "Tool_Config.xml exists ($toolConfigPath)"
$toolConfig = [xml][IO.File]::ReadAllText($toolConfigPath)
. (Join-Path $SourcesFolder 'SupportLinks.ps1')   # pure functions: Resolve-SelfXCatalogLink
$health = [xml][IO.File]::ReadAllText($healthPath)

# --- Catalogue ------------------------------------------------------------------------------------
$contexts = @{}       # script name (lower case) -> list of contexts
$seenIds = @{}
foreach ($action in @($catalog.SelectNodes('//Action'))) {
	$id = $action.GetAttribute('Id')
	$scriptName = "$($action.Script)".Trim()
	$context = "$($action.Context)".Trim()
	Assert-True ($id -ne '') 'Every action has an Id'
	Assert-True ("$($action.Requires)".Trim() -in '', 'DomainJoined') "Action $id has no Requires or Requires=DomainJoined (found '$($action.Requires)')"
	Assert-True (-not $seenIds.ContainsKey($id)) "Action Id is unique: $id"
	$seenIds[$id] = $true
	Assert-True ($context -ceq 'User' -or $context -ceq 'System' -or $context -ceq 'Link') "Action $id has Context User, System or Link (found '$context')"
	if ($context -ceq 'Link') {
		# A link action opens an https address from Tool_Config.xml in the browser of the user: no script, no service, no OtherSessions.
		$linkKey = "$($action.Link)".Trim()
		Assert-True ($scriptName -eq '') "Link action $id has no Script (found '$scriptName')"
		Assert-True ("$($action.OtherSessions)".Trim() -eq '' -and "$($action.Post_Action)".Trim() -eq '' -and "$($action.TimeoutSeconds)".Trim() -eq '') "Link action $id has no OtherSessions, Post_Action or TimeoutSeconds"
		Assert-True ($linkKey -cmatch '^Link_[A-Za-z0-9]{1,40}$') "Link action ${id}: Link is a Tool_Config.xml key of the form Link_<Name> (found '$linkKey')"
		$linkValue = "$($toolConfig.GUI_Config.$linkKey)".Trim()
		$linkResult = Resolve-SelfXCatalogLink -Key $linkKey -Value $linkValue
		Assert-True ($linkResult.State -ceq 'Ok') "Link action ${id}: Tool_Config.xml has a valid https address for $linkKey (state $($linkResult.State))"
		continue
	}
	Assert-True ("$($action.Link)".Trim() -eq '') "Action $id has no Link (only Context Link uses it)"
	Assert-True (Test-PlainScriptName $scriptName) "Action $id uses a plain script file name (found '$scriptName')"
	Assert-True (Test-Path -LiteralPath (Join-Path $scripts $scriptName) -PathType Leaf) "Action ${id}: script exists in Scripts_to_run ($scriptName)"
	$key = $scriptName.ToLowerInvariant()
	if (-not $contexts.ContainsKey($key)) { $contexts[$key] = New-Object System.Collections.Generic.List[string] }
	$contexts[$key].Add($context)
}
foreach ($key in $contexts.Keys) {
	Assert-True (@($contexts[$key] | Sort-Object -Unique).Count -eq 1) "$key is not listed with both contexts (the service accepts a script when any entry says System)"
}

# OtherSessions is optional, may only be Block, needs Context System and must be the same on every entry of a script
# (the service blocks when any System entry of the script says Block).
$sessionsByScript = @{}
foreach ($action in @($catalog.SelectNodes('//Action'))) {
	$sessions = "$($action.OtherSessions)".Trim()
	if ($sessions) {
		Assert-True ($sessions -ceq 'Block' -and "$($action.Context)".Trim() -ceq 'System') "Action $($action.Id) uses OtherSessions=Block only with Context System (found '$sessions')"
	}
	if ("$($action.Context)".Trim() -ceq 'System') {
		$scriptKey = "$($action.Script)".Trim().ToLowerInvariant()
		if (-not $sessionsByScript.ContainsKey($scriptKey)) { $sessionsByScript[$scriptKey] = New-Object System.Collections.Generic.List[string] }
		$sessionsByScript[$scriptKey].Add($sessions)
	}
}
foreach ($scriptKey in $sessionsByScript.Keys) {
	Assert-True (@($sessionsByScript[$scriptKey] | Sort-Object -Unique).Count -eq 1) "All System entries of $scriptKey have the same OtherSessions setting"
}
foreach ($remediation in @($health.SelectNodes('//Remediation[@OtherSessions]'))) {
	Assert-True ($remediation.GetAttribute('OtherSessions') -ceq 'Block') "Remediation $($remediation.GetAttribute('Script')) OtherSessions is Block (found '$($remediation.GetAttribute('OtherSessions'))')"
}

# TerminalServer (Environment_Mode TerminalServer) is required on every action (one element) and every remediation (attribute): exactly
# Show or Hide, and the same on every entry of a script, also between the catalogue and Health_Config.xml. The service hides a System
# script when any of its entries is not Show; the window decides per entry, so different values would show what the service refuses.
function Get-TerminalServerProblems {
	param([xml]$Catalog, [xml]$Health)
	$problems = New-Object System.Collections.Generic.List[string]
	$byScript = @{}
	foreach ($action in @($Catalog.SelectNodes('//Action'))) {
		$nodes = @($action.SelectNodes('TerminalServer'))
		$value = if ($nodes.Count -eq 1) { "$($nodes[0].InnerText)".Trim() } else { '' }
		if ($nodes.Count -ne 1 -or $value -cnotin @('Show', 'Hide')) {
			$problems.Add("Action $($action.GetAttribute('Id')) has exactly one TerminalServer of Show or Hide (found $($nodes.Count) element(s), '$value')")
			continue
		}
		$scriptKey = "$($action.Script)".Trim().ToLowerInvariant()
		if (-not $scriptKey) { continue }
		if (-not $byScript.ContainsKey($scriptKey)) { $byScript[$scriptKey] = New-Object System.Collections.Generic.List[string] }
		$byScript[$scriptKey].Add($value)
	}
	foreach ($remediation in @($Health.SelectNodes('//Remediation'))) {
		$value = $remediation.GetAttribute('TerminalServer')
		if (-not $remediation.HasAttribute('TerminalServer') -or $value -cnotin @('Show', 'Hide')) {
			$problems.Add("Remediation $($remediation.GetAttribute('Id')) $($remediation.GetAttribute('Script')) has TerminalServer Show or Hide (found '$value')")
			continue
		}
		$scriptKey = "$($remediation.GetAttribute('Script'))".Trim().ToLowerInvariant()
		if (-not $byScript.ContainsKey($scriptKey)) { $byScript[$scriptKey] = New-Object System.Collections.Generic.List[string] }
		$byScript[$scriptKey].Add($value)
	}
	foreach ($scriptKey in $byScript.Keys) {
		$values = @($byScript[$scriptKey] | Sort-Object -Unique)
		if ($values.Count -ne 1) { $problems.Add("All entries of $scriptKey have the same TerminalServer value (found $($values -join ', '))") }
	}
	return $problems.ToArray()
}
$terminalServerProblems = @(Get-TerminalServerProblems $catalog $health)
Assert-True ($terminalServerProblems.Count -eq 0) ("Every action and remediation is classified TerminalServer Show or Hide, the same for every entry of a script" + $(if ($terminalServerProblems.Count) { ': ' + ($terminalServerProblems -join '; ') }))

# Negative examples: the rule must find each mistake.
# The delivered classification of four actions that depend on the terminal server decision: Office licence reset, OneDrive reset and
# group policy update are offered on a terminal server (Show); No sound is not (Hide). All four run as the user, so the window decides
# what is offered (Test-SelfXShownInEnvironment, the rule of SelfXEnvironment.ps1); the service is not involved.
. (Join-Path $SourcesFolder 'SelfXEnvironment.ps1')
$expectedClassification = [ordered]@{
	'SelfX_Office_ResetLicence.ps1' = 'Show'
	'SelfX_OneDrive_Reset.ps1'      = 'Show'
	'SelfX_Device_GpUpdate.ps1'     = 'Show'
	'SelfX_Audio_Restore.ps1'       = 'Hide'
}
foreach ($scriptName in $expectedClassification.Keys) {
	$entries = @($catalog.SelectNodes('//Action') | Where-Object { "$($_.Script)".Trim() -ceq $scriptName })
	Assert-True ($entries.Count -gt 0) "$scriptName is used by an action of the catalogue"
	foreach ($entry in $entries) {
		$classification = "$($entry.SelectSingleNode('TerminalServer').InnerText)".Trim()
		Assert-True ($classification -ceq $expectedClassification[$scriptName]) "$($entry.GetAttribute('Id')) ($scriptName) is classified $($expectedClassification[$scriptName]) (found '$classification')"
		Assert-True ("$($entry.Context)".Trim() -ceq 'User') "$($entry.GetAttribute('Id')) ($scriptName) runs as the user (the service is not involved)"
		$offeredOnServer = [bool](Test-SelfXShownInEnvironment 'TerminalServer' $classification)
		Assert-True ($offeredOnServer -eq ($expectedClassification[$scriptName] -ceq 'Show')) "$($entry.GetAttribute('Id')): offered on a terminal server = $($expectedClassification[$scriptName] -ceq 'Show')"
		Assert-True ([bool](Test-SelfXShownInEnvironment 'Client' $classification)) "$($entry.GetAttribute('Id')): always offered on Windows 11"
	}
}

function New-TerminalServerExample([string]$Actions, [string]$Remediations = '') {
	return [pscustomobject]@{
		Catalog = [xml]"<Actions><Quick_Solution>$Actions</Quick_Solution></Actions>"
		Health  = [xml]"<HealthConfig><Remediations>$Remediations</Remediations></HealthConfig>"
	}
}
$goodAction = '<Action Id="A"><Script>A.ps1</Script><Context>User</Context><TerminalServer>Show</TerminalServer></Action>'
$goodRemediation = '<Remediation Id="Disk" Script="B.ps1" TerminalServer="Hide" />'
$examples = [ordered]@{
	'a valid example'                          = @((New-TerminalServerExample ($goodAction + '<Action Id="L"><Link>Link_X</Link><Context>Link</Context><TerminalServer>Show</TerminalServer></Action>') $goodRemediation), 0)
	'an action without TerminalServer'         = @((New-TerminalServerExample '<Action Id="A"><Script>A.ps1</Script><Context>User</Context></Action>'), 1)
	'an empty TerminalServer'                  = @((New-TerminalServerExample '<Action Id="A"><Script>A.ps1</Script><Context>User</Context><TerminalServer> </TerminalServer></Action>'), 1)
	'show in lower case'                       = @((New-TerminalServerExample '<Action Id="A"><Script>A.ps1</Script><Context>User</Context><TerminalServer>show</TerminalServer></Action>'), 1)
	'two TerminalServer elements'              = @((New-TerminalServerExample '<Action Id="A"><Script>A.ps1</Script><Context>User</Context><TerminalServer>Show</TerminalServer><TerminalServer>Hide</TerminalServer></Action>'), 1)
	'Show and Hide for one script'             = @((New-TerminalServerExample ($goodAction + '<Action Id="A2"><Script>a.ps1</Script><Context>User</Context><TerminalServer>Hide</TerminalServer></Action>')), 1)
	'a remediation without the attribute'      = @((New-TerminalServerExample $goodAction '<Remediation Id="Disk" Script="B.ps1" />'), 1)
	'a remediation with another value'         = @((New-TerminalServerExample $goodAction '<Remediation Id="Disk" Script="B.ps1" TerminalServer="Maybe" />'), 1)
	'catalogue and remediation disagree'       = @((New-TerminalServerExample $goodAction '<Remediation Id="Disk" Script="A.ps1" TerminalServer="Hide" />'), 1)
}
foreach ($name in $examples.Keys) {
	$example = $examples[$name][0]
	$found = @(Get-TerminalServerProblems $example.Catalog $example.Health)
	Assert-True ($found.Count -eq $examples[$name][1]) "TerminalServer rule: $name gives $($examples[$name][1]) problem(s) (found $($found.Count): $($found -join '; '))"
}

# Disruptive (hint before disruptive actions) is optional. When it is there it is exactly True (never False, never empty, one element),
# belongs to an action with a script and is the same on every entry of that script: the window decides per entry, so different
# values would warn for one entry of a script and not for another.
function Get-DisruptiveProblems {
	param([xml]$Catalog)
	$problems = New-Object System.Collections.Generic.List[string]
	$byScript = @{}
	foreach ($action in @($Catalog.SelectNodes('//Action'))) {
		$nodes = @($action.SelectNodes('Disruptive'))
		$value = if ($nodes.Count -eq 1) { "$($nodes[0].InnerText)" } else { '' }
		$scriptKey = "$($action.Script)".Trim().ToLowerInvariant()
		if ($nodes.Count -gt 1 -or ($nodes.Count -eq 1 -and $value -cne 'True')) {
			$problems.Add("Action $($action.GetAttribute('Id')) has at most one Disruptive and it is exactly True (found $($nodes.Count) element(s), '$value')")
			continue
		}
		if ($nodes.Count -eq 1 -and -not $scriptKey) {
			$problems.Add("Action $($action.GetAttribute('Id')) is Disruptive but has no script")
			continue
		}
		if (-not $scriptKey) { continue }
		if (-not $byScript.ContainsKey($scriptKey)) { $byScript[$scriptKey] = New-Object System.Collections.Generic.List[string] }
		$byScript[$scriptKey].Add($(if ($nodes.Count -eq 1) { 'True' } else { '' }))
	}
	foreach ($scriptKey in $byScript.Keys) {
		if (@($byScript[$scriptKey] | Sort-Object -Unique).Count -ne 1) { $problems.Add("All entries of $scriptKey have the same Disruptive value") }
	}
	return $problems.ToArray()
}
$disruptiveProblems = @(Get-DisruptiveProblems $catalog)
Assert-True ($disruptiveProblems.Count -eq 0) ("Disruptive is True or absent, the same for every entry of a script" + $(if ($disruptiveProblems.Count) { ": $($disruptiveProblems -join '; ')" } else { '' }))
Assert-True (@($catalog.SelectNodes('//Action[Disruptive]')).Count -gt 0) 'The delivered catalogue marks at least one action Disruptive'
Assert-True (@($health.SelectNodes('//Remediation[@Disruptive]')).Count -eq 0) 'Remediations of Health_Config.xml have no Disruptive attribute (the restart repair has the hint without it)'
$disruptiveExamples = [ordered]@{
	'a valid example'                       = @('<Action Id="A"><Script>A.ps1</Script><Disruptive>True</Disruptive></Action><Action Id="A2"><Script>a.ps1</Script><Disruptive>True</Disruptive></Action><Action Id="B"><Script>B.ps1</Script></Action>', 0)
	'False'                                 = @('<Action Id="A"><Script>A.ps1</Script><Disruptive>False</Disruptive></Action>', 1)
	'lower case'                            = @('<Action Id="A"><Script>A.ps1</Script><Disruptive>true</Disruptive></Action>', 1)
	'empty'                                 = @('<Action Id="A"><Script>A.ps1</Script><Disruptive></Disruptive></Action>', 1)
	'two elements'                          = @('<Action Id="A"><Script>A.ps1</Script><Disruptive>True</Disruptive><Disruptive>True</Disruptive></Action>', 1)
	'True on one entry of a script only'    = @('<Action Id="A"><Script>A.ps1</Script><Disruptive>True</Disruptive></Action><Action Id="A2"><Script>a.ps1</Script></Action>', 1)
	'a link action'                         = @('<Action Id="L"><Link>Link_X</Link><Context>Link</Context><Disruptive>True</Disruptive></Action>', 1)
}
foreach ($name in $disruptiveExamples.Keys) {
	$found = @(Get-DisruptiveProblems ([xml]"<Actions><Quick_Solution>$($disruptiveExamples[$name][0])</Quick_Solution></Actions>"))
	Assert-True ($found.Count -eq $disruptiveExamples[$name][1]) "Disruptive rule: $name gives $($disruptiveExamples[$name][1]) problem(s) (found $($found.Count): $($found -join '; '))"
}

# --- Remediations of Health_Config.xml -------------------------------------------------------------
$remediationScripts = New-Object System.Collections.Generic.List[string]
foreach ($remediation in @($health.SelectNodes('//Remediation'))) {
	$scriptName = $remediation.GetAttribute('Script')
	Assert-True (Test-PlainScriptName $scriptName) "Remediation $($remediation.GetAttribute('Id')) uses a plain script file name (found '$scriptName')"
	Assert-True (Test-Path -LiteralPath (Join-Path $scripts $scriptName) -PathType Leaf) "Remediation script exists: $scriptName"
	Assert-True (-not ($contexts.ContainsKey($scriptName.ToLowerInvariant()) -and $contexts[$scriptName.ToLowerInvariant()] -contains 'User')) "Remediation $scriptName is not also listed as a user action"
	if ($remediation.HasAttribute('TimeoutSeconds')) {
		$seconds = 0
		$valid = [int]::TryParse($remediation.GetAttribute('TimeoutSeconds'), [ref]$seconds) -and $seconds -ge 1 -and $seconds -le 7200
		Assert-True $valid "Remediation $scriptName TimeoutSeconds is a number from 1 to 7200 (found '$($remediation.GetAttribute('TimeoutSeconds'))')"
	}
	$remediationScripts.Add($scriptName)
}

# --- Scripts that can run as SYSTEM ----------------------------------------------------------------
$systemScripts = @($contexts.Keys | Where-Object { $contexts[$_] -contains 'System' }) + @($remediationScripts | ForEach-Object { $_.ToLowerInvariant() })
foreach ($name in ($systemScripts | Sort-Object -Unique)) {
	$file = Get-ChildItem -LiteralPath $scripts -Filter '*.ps1' | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
	if (-not $file) { continue }   # reported above
	$info = Get-ScriptInfo $file.Name
	Assert-True ($info.ParseErrors -eq 0) "$($file.Name) parses"
	Assert-True ($info.HeaderContext -ceq 'System') "$($file.Name) declares 'Context : System' in its header (found '$($info.HeaderContext)')"
	Assert-True ($info.MandatoryParameters.Count -eq 0) "$($file.Name) has no mandatory script parameter, the service starts it without parameters (found: $($info.MandatoryParameters -join ', '))"
}

# --- Parts of the user of two-part repairs (Health_Config.xml UserScript) ----------------------------
# SelfX starts them with the rights of the user; one script has one context, so a UserScript is never a SYSTEM script.
foreach ($remediation in @($health.SelectNodes('//Remediation[@UserScript]'))) {
	$userName = $remediation.GetAttribute('UserScript')
	Assert-True (Test-PlainScriptName $userName) "Remediation $($remediation.GetAttribute('Id')) UserScript is a plain script file name (found '$userName')"
	Assert-True ($systemScripts -notcontains $userName.ToLowerInvariant()) "UserScript $userName is not a SYSTEM script (catalogue or remediation)"
	$file = Get-ChildItem -LiteralPath $scripts -Filter '*.ps1' | Where-Object { $_.Name -ieq $userName } | Select-Object -First 1
	Assert-True ([bool]$file) "UserScript exists: $userName"
	if (-not $file) { continue }
	$info = Get-ScriptInfo $file.Name
	Assert-True ($info.HeaderContext -ceq 'User') "UserScript $($file.Name) declares 'Context : User' in its header (found '$($info.HeaderContext)')"
	Assert-True ($info.MandatoryParameters.Count -eq 0) "UserScript $($file.Name) has no mandatory parameter (found: $($info.MandatoryParameters -join ', '))"
}

# --- User scripts ----------------------------------------------------------------------------------
foreach ($key in $contexts.Keys) {
	if ($contexts[$key] -notcontains 'User' -or $systemScripts -contains $key) { continue }
	$file = Get-ChildItem -LiteralPath $scripts -Filter '*.ps1' | Where-Object { $_.Name -ieq $key } | Select-Object -First 1
	if (-not $file) { continue }
	$info = Get-ScriptInfo $file.Name
	Assert-True ($info.HeaderContext -cne 'System') "User script $($file.Name) does not declare 'Context : System'"
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "FAILED: $($script:errors.Count) of $script:checks checks."
	exit 1
}
Write-Output "PASS: $script:checks checks. Catalogue, Health_Config.xml and the SYSTEM scripts are consistent; nothing was executed."
exit 0
