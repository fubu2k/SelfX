<#
.SYNOPSIS
    Tests that the uninstall deletes the data folders without following junctions.

.DESCRIPTION
    Takes the function Remove-SelfXTree out of Uninstall.ps1 (the script itself is never run: it would uninstall
    SelfX) and runs it in a temporary folder. A user can create a junction in a folder that SYSTEM deletes;
    the junction must be removed, the folder it points to must stay untouched. Remove-SelfXEventLog is run with replaced
    registration commands (nothing is removed on the device). Static checks: Uninstall.ps1 handles the
    layout App/Config and the old layout (everything directly in the install folder).
    Files are created only in a temporary folder. Windows PowerShell 5.1:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Uninstall.ps1

.NOTES
    Name    : Test-Uninstall.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version.
    3.1.0    2026-11-27  fubu2k               Both layouts: Tool_Config.xml in Config and in the install folder, delete helper in App, pattern of the
                                              open windows for App and the old layout, Tool_Config.xml without DTD.
    3.1.0    2026-11-28  fubu2k               Event log SelfX: log and source removed, a source in the Application log (older version) too, failure reported.
    3.1.0    2026-11-28  fubu2k               Uninstall.ps1 starts sc.exe and icacls.exe with their full path (static check).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}

# Load only the function, never the rest of Uninstall.ps1.
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Uninstall.ps1'), [ref]$tokens, [ref]$parseErrors)
Assert-Equal @($parseErrors).Count 0 'Uninstall.ps1 parses'
$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Remove-SelfXTree' }, $true)
Assert-Equal ($null -ne $definition) $true 'Uninstall.ps1 defines Remove-SelfXTree'
if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
. ([scriptblock]::Create($definition.Extent.Text))

# Event log SelfX (Remove-SelfXEventLog): the registration commands are replaced by functions of this test.
$removeDefinition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Remove-SelfXEventLog' }, $true)
Assert-Equal ($null -ne $removeDefinition) $true 'Uninstall.ps1 defines Remove-SelfXEventLog'
if ($removeDefinition) {
	. ([scriptblock]::Create($removeDefinition.Extent.Text))
	$script:sourceLog = ''; $script:logExists = $false; $script:calls = New-Object System.Collections.Generic.List[string]; $script:failRemove = $false
	function Get-SelfXEventSourceLog { param([string]$Source) return $script:sourceLog }
	function Test-SelfXEventLogExists { param([string]$LogName) return $script:logExists }
	function Remove-EventLog { [CmdletBinding()] param([string]$LogName, [string]$Source) $script:calls.Add("Remove $LogName|$Source"); if ($script:failRemove) { throw 'access denied' } }
	foreach ($case in @(
		@('SelfX', $true, $false, 'Remove SelfX|', 'log SelfX removed', 'the log SelfX with its source is removed'),
		@('Application', $true, $false, 'Remove |SelfXService;Remove SelfX|', "removed from 'Application'", 'a source of an older version in the Application log is removed too'),
		@('Application', $false, $false, 'Remove |SelfXService', "removed from 'Application'", 'an installation of an older version without the log SelfX'),
		@('', $false, $false, '', 'No event log SelfX to remove.', 'nothing to remove'),
		@('SelfX', $true, $true, 'Remove SelfX|', 'could not be removed completely', 'a failure is reported, not thrown'))) {
		$script:sourceLog = $case[0]; $script:logExists = $case[1]; $script:failRemove = $case[2]; $script:calls.Clear()
		$line = "$(Remove-SelfXEventLog)"
		Assert-Equal ($script:calls -join ';') $case[3] "Event log: $($case[5]) (calls)"
		Assert-Equal ($line.Contains($case[4])) $true "Event log: $($case[5]) ('$line')"
	}
	Remove-Item -Path Function:\Remove-EventLog, Function:\Get-SelfXEventSourceLog, Function:\Test-SelfXEventLogExists
}
$uninstallSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Uninstall.ps1'))
Assert-Equal ($uninstallSource.IndexOf('Write-Output (Remove-SelfXEventLog)') -gt $uninstallSource.IndexOf("& (Join-Path ([Environment]::SystemDirectory) 'sc.exe') delete `$ServiceName")) $true 'Event log: removed after the service is stopped and deleted'
# SYSTEM starts the tools of Windows by their full path, never through a search of PATH.
Assert-Equal ([regex]::IsMatch($uninstallSource, '(?m)^[^#\r\n]*&\s*(sc|icacls)\.exe\b')) $false 'Uninstall.ps1 starts sc.exe and icacls.exe with their full path'

# Both layouts (3.1.0): App\ and Config\ and, for an installation of an older version, everything directly in the install folder.
$uninstallText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Uninstall.ps1'))
Assert-Equal $uninstallText.Contains("'Config\Tool_Config.xml'") $true 'Both layouts: Tool_Config.xml is looked for in Config'
Assert-Equal $uninstallText.Contains("(Join-Path `$InstallFolder 'Tool_Config.xml')") $true 'Both layouts: Tool_Config.xml of the old layout is looked for too'
Assert-Equal $uninstallText.Contains("'App\SelfXService.exe'") $true 'Both layouts: the delete helper is looked for in App'
Assert-Equal ($uninstallText -match '\[xml\]\(Get-Content') $false 'Tool_Config.xml is not read with [xml] (DTD processing is prohibited explicitly)'
Assert-Equal $uninstallText.Contains('DtdProcessing]::Prohibit') $true 'Tool_Config.xml is read without DTD'
$patternAssignment = $ast.Find({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$SelfXPattern' }, $true)
Assert-Equal ($null -ne $patternAssignment) $true 'Uninstall.ps1 builds the pattern of the open SelfX windows'
if ($patternAssignment) {
	$InstallFolder = 'C:\Program Files\SelfX'
	$pattern = & ([scriptblock]::Create($patternAssignment.Right.Extent.Text))
	foreach ($case in @(
		@('pwsh.exe -File "C:\Program Files\SelfX\Self_X.ps1"', $true),
		@('pwsh.exe -File "C:\Program Files\SelfX\SelfX_Tray.ps1"', $true),
		@('pwsh.exe -File "C:\Program Files\SelfX\App\Self_X.ps1"', $true),
		@('pwsh.exe -File "C:\Program Files\SelfX\App\SelfX_Tray.ps1"', $true),
		@('pwsh.exe -File "C:\Program Files\SelfX\Config\Self_X.ps1"', $false),
		@('pwsh.exe -File "C:\Other\Self_X.ps1"', $false))) {
		Assert-Equal ($case[0] -match $pattern) $case[1] "Window pattern: $($case[0])"
	}
}
# The uninstallation removes the whole install folder (both layouts) in one step.
Assert-Equal $uninstallText.Contains('Remove-Item -LiteralPath $InstallFolder -Recurse -Force') $true 'Both layouts: the whole install folder is removed'

$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXUninstallTests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
	# A folder that must never be touched: it stands for a place outside ProgramData\SelfX.
	$outside = Join-Path $temp 'Outside'
	[void][IO.Directory]::CreateDirectory((Join-Path $outside 'Sub'))
	[IO.File]::WriteAllText((Join-Path $outside 'secret.log'), 'must survive')
	[IO.File]::WriteAllText((Join-Path $outside 'Sub\deep.txt'), 'must survive too')

	# Data folder like ProgramData\SelfX with a user folder that contains a junction to the outside folder.
	$data = Join-Path $temp 'SelfX'
	$userFolder = Join-Path $data 'Logs\Users\S-1-5-21-1-2-3-1001'
	[void][IO.Directory]::CreateDirectory($userFolder)
	[IO.File]::WriteAllText((Join-Path $data 'Logs\SelfXService.log'), 'machine log')
	[IO.File]::WriteAllText((Join-Path $userFolder 'SelfX_2026-11-22.log'), 'user log')
	(Get-Item -LiteralPath (Join-Path $userFolder 'SelfX_2026-11-22.log')).IsReadOnly = $true
	New-Item -ItemType Junction -Path (Join-Path $userFolder 'Link') -Value $outside | Out-Null
	Assert-Equal (Test-Path -LiteralPath (Join-Path $userFolder 'Link\secret.log')) $true 'Setup: the junction reaches the outside file'

	Remove-SelfXTree -Path $data
	Assert-Equal (Test-Path -LiteralPath $data) $false 'The data folder is deleted, also with a read-only file'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $outside 'secret.log')) $true 'The target of the junction is untouched (file)'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $outside 'Sub\deep.txt')) $true 'The target of the junction is untouched (subfolder)'
	Assert-Equal ([IO.File]::ReadAllText((Join-Path $outside 'secret.log'))) 'must survive' 'The content of the target is unchanged'

	# The folder itself is a junction (for example Reports replaced by a link): only the link is removed.
	$linkRoot = Join-Path $temp 'Reports'
	New-Item -ItemType Junction -Path $linkRoot -Value $outside | Out-Null
	Remove-SelfXTree -Path $linkRoot
	Assert-Equal (Test-Path -LiteralPath $linkRoot) $false 'A junction as the folder itself is removed'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $outside 'secret.log')) $true 'Its target is untouched'

	# Missing folder: no error.
	Remove-SelfXTree -Path (Join-Path $temp 'DoesNotExist')
	Assert-Equal $true $true 'A missing folder is no error'
} finally {
	Get-ChildItem -LiteralPath $temp -Force -ErrorAction SilentlyContinue | ForEach-Object {
		if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { try { [IO.Directory]::Delete($_.FullName) } catch {} }
	}
	Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "FAILED: $($script:errors.Count) of $script:checks checks."
	exit 1
}
Write-Output "PASS: $script:checks checks. Junctions are removed, never followed."
exit 0
