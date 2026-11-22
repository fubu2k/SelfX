<#
.SYNOPSIS
    Static consistency checks of the action catalogue, Health_Config.xml and the scripts that run as SYSTEM.

.DESCRIPTION
    The SelfX service runs a script as SYSTEM when its plain file name is listed with Context=System in
    Sources\Issues_List.xml (or as a remediation in Sources\Health_Config.xml). Every signed-in user can send
    that request through the named pipe. This test keeps that whitelist safe for every release:

      - every action has a unique Id, a Context of exactly User or System and a plain script file name
        (letters, digits, _ - . only, no path, no "..", ends with .ps1) that exists in Scripts_to_run;
      - no script is listed with both contexts (the service accepts a script when ANY entry says System);
      - every remediation of Health_Config.xml points to an existing plain file name, is not listed as a
        user action, and has a TimeoutSeconds between 1 and 7200 when it is set;
      - every script that can run as SYSTEM declares "Context : System" in its header, has no mandatory
        parameter in its script-level param block (the service starts it without parameters) and parses;
      - user scripts do not declare "Context : System" in their header.

    Nothing is executed and nothing is changed: the files are only read and parsed.
    Run in Windows PowerShell 5.1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Catalog.ps1

.PARAMETER SourcesFolder
    Folder with Issues_List.xml, Health_Config.xml and Scripts_to_run. Default: Sources next to this script.

.NOTES
    Name    : Test-Catalog.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator before building the package; not installed)
    Version : 2.6.10
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version (security review finding F11).
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
$health = [xml][IO.File]::ReadAllText($healthPath)

# --- Catalogue ------------------------------------------------------------------------------------
$contexts = @{}       # script name (lower case) -> list of contexts
$seenIds = @{}
foreach ($action in @($catalog.SelectNodes('//Action'))) {
	$id = $action.GetAttribute('Id')
	$scriptName = "$($action.Script)".Trim()
	$context = "$($action.Context)".Trim()
	Assert-True ($id -ne '') 'Every action has an Id'
	Assert-True (-not $seenIds.ContainsKey($id)) "Action Id is unique: $id"
	$seenIds[$id] = $true
	Assert-True ($context -ceq 'User' -or $context -ceq 'System') "Action $id has Context User or System (found '$context')"
	Assert-True (Test-PlainScriptName $scriptName) "Action $id uses a plain script file name (found '$scriptName')"
	Assert-True (Test-Path -LiteralPath (Join-Path $scripts $scriptName) -PathType Leaf) "Action $id: script exists in Scripts_to_run ($scriptName)"
	$key = $scriptName.ToLowerInvariant()
	if (-not $contexts.ContainsKey($key)) { $contexts[$key] = New-Object System.Collections.Generic.List[string] }
	$contexts[$key].Add($context)
}
foreach ($key in $contexts.Keys) {
	Assert-True (@($contexts[$key] | Sort-Object -Unique).Count -eq 1) "$key is not listed with both contexts (the service accepts a script when any entry says System)"
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
