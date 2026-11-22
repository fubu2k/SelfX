<#
.SYNOPSIS
    Tests that the log collector creates its report file safely (finding N2 of the code review).

.DESCRIPTION
    Takes the function Open-SelfXReportWriter out of Sources\Scripts_to_run\Collect-DeviceLogs.ps1 (the collector itself is
    never run) and runs it in a temporary folder. A user can create a file with the predictable name of the report in
    C:\Windows\Temp in advance; such a file (link, foreign owner) must be removed and replaced, the target of a link must
    stay untouched, and an existing file of a trusted owner is overwritten. The default report is readable only by SYSTEM
    and administrators. Files are created only in a temporary folder. Runs in PowerShell 7 and Windows PowerShell 5.1:
    pwsh -NoProfile -File .\Test-CollectorOutput.ps1

.NOTES
    Name    : Test-CollectorOutput.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 2.8.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.0    2026-11-22  fubu2k               Initial version (security review finding N2).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}

if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { Write-Output 'Skipped: Windows only.'; exit 0 }

# Load only the one function, never the rest of the collector.
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Sources\Scripts_to_run\Collect-DeviceLogs.ps1'), [ref]$tokens, [ref]$parseErrors)
Assert-Equal @($parseErrors).Count 0 'Collect-DeviceLogs.ps1 parses'
$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Open-SelfXReportWriter' }, $true)
Assert-Equal ($null -ne $definition) $true 'Collect-DeviceLogs.ps1 defines Open-SelfXReportWriter'
if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
. ([scriptblock]::Create($definition.Extent.Text))

$me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXCollectorOutputTest_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
function Write-Report($Path, $Trusted, [switch]$Protect) {
	$writer = Open-SelfXReportWriter -Path $Path -TrustedOwnerSids $Trusted -Protect:$Protect
	$writer.WriteLine('new report')
	$writer.Dispose()
}
function Read-Text($Path) { [IO.File]::ReadAllText($Path).Trim() }

try {
	# 1. A new file is created.
	$file1 = Join-Path $root 'new.log'
	Write-Report $file1 @($me)
	Assert-Equal (Read-Text $file1) 'new report' 'new report file is written'

	# 2. An existing file of a trusted owner is overwritten (not appended).
	$file2 = Join-Path $root 'trusted.log'
	Set-Content -LiteralPath $file2 -Value ('old content ' * 50)
	Write-Report $file2 @($me)
	Assert-Equal (Read-Text $file2) 'new report' 'existing file of a trusted owner is overwritten'

	# 3. An existing file whose owner is not in the list (created in advance by a user) is removed and replaced.
	$file3 = Join-Path $root 'foreign.log'
	Set-Content -LiteralPath $file3 -Value 'planted'
	$id3 = (Get-Item -LiteralPath $file3).CreationTimeUtc
	Start-Sleep -Milliseconds 50
	Write-Report $file3 @('S-1-5-18-no-match')
	Assert-Equal (Read-Text $file3) 'new report' 'file of an untrusted owner is replaced'
	Assert-Equal ((Get-Item -LiteralPath $file3).CreationTimeUtc -gt $id3) $true 'file of an untrusted owner is a new file (not the planted one)'

	# 4. A symbolic link at the report path: the link is removed, the target is not written.
	$target4 = Join-Path $root 'target4.txt'
	Set-Content -LiteralPath $target4 -Value 'target stays'
	$link4 = Join-Path $root 'link.log'
	$linked = $false
	try { New-Item -ItemType SymbolicLink -Path $link4 -Value $target4 | Out-Null; $linked = $true } catch { Write-Output "Skipped: symbolic link cannot be created here ($($_.Exception.Message))." }
	if ($linked) {
		Write-Report $link4 @($me)
		Assert-Equal (Read-Text $target4) 'target stays' 'link: the target is not written'
		Assert-Equal (Read-Text $link4) 'new report' 'link: the report is a regular file'
		Assert-Equal (([IO.File]::GetAttributes($link4) -band [IO.FileAttributes]::ReparsePoint) -eq 0) $true 'link: the report is not a link any more'
	}

	# 5. A hard link at the report path: the name is removed, the other name and its content stay.
	$target5 = Join-Path $root 'target5.txt'
	Set-Content -LiteralPath $target5 -Value 'hard target stays'
	$hard5 = Join-Path $root 'hard.log'
	$null = & cmd.exe /c mklink /H "`"$hard5`"" "`"$target5`"" 2>&1
	if ($LASTEXITCODE -eq 0) {
		Write-Report $hard5 @($me)
		Assert-Equal (Read-Text $target5) 'hard target stays' 'hard link: the other name is not written'
		Assert-Equal (Read-Text $hard5) 'new report' 'hard link: the report is a new file'
	}

	# 6. A folder at the report path is refused.
	$dir6 = Join-Path $root 'folder.log'
	New-Item -ItemType Directory -Path $dir6 | Out-Null
	$threw = $false
	try { Write-Report $dir6 @($me) } catch { $threw = $true }
	Assert-Equal $threw $true 'a folder at the report path is refused'

	# 7. Default reports (-Protect): only SYSTEM and administrators have explicit rights, no inherited rights. (needs administrator rights)
	if ($isAdmin) {
		$file7 = Join-Path $root 'protected.log'
		Write-Report $file7 @($me) -Protect
		Assert-Equal (Read-Text $file7) 'new report' 'protected report is written'
		$rules = @((Get-Acl -LiteralPath $file7).Access)
		Assert-Equal (@($rules | Where-Object { $_.IsInherited }).Count) 0 'protected report: no inherited rights'
		Assert-Equal (@($rules | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } | Sort-Object -Unique) -join ',') 'S-1-5-18,S-1-5-32-544' 'protected report: only SYSTEM and administrators'
	}

	# 8. The collector uses the function and passes -Protect only for the default location.
	$text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sources\Scripts_to_run\Collect-DeviceLogs.ps1'))
	Assert-Equal ($text.Contains('Open-SelfXReportWriter -Path $outFile -TrustedOwnerSids $trustedOwners -Protect:$defaultOutput')) $true 'collector opens the report with Open-SelfXReportWriter'
	Assert-Equal ($text.Contains('New-Object System.IO.StreamWriter($outFile')) $false 'collector no longer opens the report with a plain StreamWriter'
}
finally {
	if ($isAdmin) { & icacls.exe $root /grant "*S-1-5-32-544:(OI)(CI)F" /T /C 2>&1 | Out-Null }
	Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
