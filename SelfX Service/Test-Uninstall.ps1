<#
.SYNOPSIS
    Tests that the uninstall deletes the data folders without following junctions (finding F10).

.DESCRIPTION
    Takes the function Remove-SelfXTree out of Uninstall.ps1 (the script itself is never run: it would uninstall
    SelfX) and runs it in a temporary folder. A user can create a junction in a folder that SYSTEM deletes;
    the junction must be removed, the folder it points to must stay untouched.
    Files are created only in a temporary folder. Windows PowerShell 5.1:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Uninstall.ps1

.NOTES
    Name    : Test-Uninstall.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator before building the package; not installed)
    Version : 2.6.10
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version (security review finding F10).
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
