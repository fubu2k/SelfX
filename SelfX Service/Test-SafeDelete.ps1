<#
.SYNOPSIS
    Tests the handle-based delete helper of SelfXService.exe (/removetree:, /cleandata:; class SafeTree).

.DESCRIPTION
    Install.ps1 and Uninstall.ps1 delete folders as SYSTEM that users can write to (Logs\Users\<SID>). The helper opens every
    entry once without following links and deletes through that handle. This test checks in a temporary folder that
    junctions are removed and never followed (also when swapped while the helper runs), that read-only files and long paths are
    deleted, that /cleandata: keeps trusted entries and deletes foreign-owned ones, and that wrong arguments are refused.
    The helper is Bin\SelfXService.exe of the package (build it with tools\Build-SelfXBinaries.ps1) or the file named in
    SELFX_TEST_SAFEDELETE_EXE. Without it the test is skipped, unless SELFX_REQUIRE_BIN=1 (CI after the build): then it fails.
    No administrator rights are needed. Files are created only in a temporary folder.
    Windows PowerShell 5.1 or PowerShell 7: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SafeDelete.ps1

.NOTES
    Name    : Test-SafeDelete.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator before building the package; not installed)
    Version : 2.8.19
    Exit code: 0 = all checks passed (or skipped), 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.19   2026-11-23  fubu2k               Initial version (M1).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}

$exe = $env:SELFX_TEST_SAFEDELETE_EXE
if (-not $exe) { $exe = Join-Path $PSScriptRoot 'Bin\SelfXService.exe' }
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
	if ($env:SELFX_REQUIRE_BIN -eq '1') { Write-Output "FAIL: $exe is missing."; exit 1 }
	Write-Output "Skipped: $exe is missing (build it with tools\Build-SelfXBinaries.ps1)."
	exit 0
}

function Invoke-Helper([string[]]$Arguments) {
	$out = @(& $exe @Arguments 2>&1 | ForEach-Object { "$_" })
	[pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out -join "`n"); Ok = (($out -contains 'SELFX-SAFEDELETE-OK') -and $LASTEXITCODE -eq 0) }
}
function New-TestJunction($Link, $Target) { $null = & cmd.exe /c mklink /J "`"$Link`"" "`"$Target`"" 2>&1; if ($LASTEXITCODE -ne 0) { throw "mklink failed for '$Link'." } }
function Remove-TestJunction($Link) { try { [IO.Directory]::Delete($Link) } catch {} }

$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXSafeDeleteTests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
	$outside = Join-Path $temp 'Outside'
	[void][IO.Directory]::CreateDirectory((Join-Path $outside 'Sub'))
	[IO.File]::WriteAllText((Join-Path $outside 'secret.log'), 'must survive')
	[IO.File]::WriteAllText((Join-Path $outside 'Sub\deep.txt'), 'must survive too')
	function Test-OutsideIntact($Message) {
		Assert-Equal ([IO.File]::ReadAllText((Join-Path $outside 'secret.log'))) 'must survive' "$Message : outside file intact"
		Assert-Equal (Test-Path -LiteralPath (Join-Path $outside 'Sub\deep.txt')) $true "$Message : outside subfolder intact"
	}

	# 1. Tree with a junction to the outside folder, a read-only file and a long path.
	$tree = Join-Path $temp 'Tree1'
	$user = Join-Path $tree 'Logs\Users\S-1-5-21-1-2-3-1001'
	[void][IO.Directory]::CreateDirectory($user)
	[IO.File]::WriteAllText((Join-Path $user 'a.log'), 'x')
	(Get-Item -LiteralPath (Join-Path $user 'a.log')).IsReadOnly = $true
	New-TestJunction (Join-Path $user 'Link') $outside
	$long = $user
	1..14 | ForEach-Object { $long = Join-Path $long ('segment_number_' + ('x' * 20) + $_) }
	[void][IO.Directory]::CreateDirectory('\\?\' + $long)
	[IO.File]::WriteAllText('\\?\' + (Join-Path $long 'deep.log'), 'x')
	Assert-Equal ($long.Length -gt 260) $true 'Setup: the path is longer than 260 characters'
	$r = Invoke-Helper @("/removetree:$tree")
	Assert-Equal $r.Ok $true "removetree: result ok ($($r.Output))"
	Assert-Equal (Test-Path -LiteralPath $tree) $false 'removetree: tree is gone (read-only file, long path, link)'
	Test-OutsideIntact 'removetree with a junction inside'

	# 2. The folder itself is a junction: only the link is removed.
	$linkRoot = Join-Path $temp 'Reports'
	New-TestJunction $linkRoot $outside
	$r = Invoke-Helper @("/removetree:$linkRoot")
	Assert-Equal $r.Ok $true "removetree on a junction: result ok ($($r.Output))"
	Assert-Equal (Test-Path -LiteralPath $linkRoot) $false 'removetree on a junction: link is gone'
	Test-OutsideIntact 'removetree on a junction'

	# 3. A missing folder is no error.
	Assert-Equal (Invoke-Helper @("/removetree:$(Join-Path $temp 'DoesNotExist')")).Ok $true 'removetree: a missing folder is no error'

	# 4. A link in a parent folder: refused, nothing deleted in the target.
	$parentLink = Join-Path $temp 'ParentLink'
	New-TestJunction $parentLink $outside
	$r = Invoke-Helper @("/removetree:$(Join-Path $parentLink 'Sub')")
	Assert-Equal $r.Ok $false 'removetree behind a link in the path: refused'
	Remove-TestJunction $parentLink
	Test-OutsideIntact 'removetree behind a link in the path'

	# 5. Wrong arguments.
	Assert-Equal (Invoke-Helper @('/removetree:relative\path')).Code 2 'removetree: a relative path is refused (exit code 2)'
	Assert-Equal (Invoke-Helper @('/removetree:\\server\share\x')).Code 2 'removetree: a UNC path is refused (exit code 2)'
	Assert-Equal (Invoke-Helper @('/removetree:C:\')).Code 2 'removetree: a drive root is refused (exit code 2)'
	Assert-Equal (Invoke-Helper @("/cleandata:$temp", '/trusted:not-a-sid')).Code 2 'cleandata: an invalid SID is refused'
	Assert-Equal (Invoke-Helper @("/cleandata:$temp", '/trusted:S-1-5-18', '/skip:..\x')).Code 2 'cleandata: /skip: with .. is refused'

	# 6. cleandata: trusted owner kept, foreign owner deleted, links deleted, user area not entered, root kept.
	$data = Join-Path $temp 'Data'
	[void][IO.Directory]::CreateDirectory((Join-Path $data 'Logs\Users\S-1-5-21-1-2-3-1001'))
	[void][IO.Directory]::CreateDirectory((Join-Path $data 'Cache'))
	[IO.File]::WriteAllText((Join-Path $data 'Cache\Health.json'), '{}')
	[IO.File]::WriteAllText((Join-Path $data 'Logs\Users\S-1-5-21-1-2-3-1001\u.log'), 'x')
	New-TestJunction (Join-Path $data 'Logs\evil') $outside
	# Owner of the new files: the user, or the group Administrators when an elevated administrator creates them.
	$me = (Get-Acl -LiteralPath (Join-Path $data 'Cache\Health.json')).GetOwner([Security.Principal.SecurityIdentifier]).Value
	$r = Invoke-Helper @("/cleandata:$data", "/trusted:$me", '/skip:Logs\Users')
	Assert-Equal $r.Ok $true "cleandata: result ok ($($r.Output))"
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data 'Logs\evil')) $false 'cleandata: link is removed'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data 'Cache\Health.json')) $true 'cleandata: entry of a trusted owner is kept'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data 'Logs\Users\S-1-5-21-1-2-3-1001\u.log')) $true 'cleandata: the user area is not entered'
	Test-OutsideIntact 'cleandata with a junction'
	$r = Invoke-Helper @("/cleandata:$data", '/trusted:S-1-5-18', '/skip:Logs\Users')
	Assert-Equal $r.Ok $true 'cleandata: result ok (no trusted match)'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data 'Cache')) $false 'cleandata: foreign-owned folder with content is deleted'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $data 'Logs')) $false 'cleandata: foreign-owned Logs (with the user area) is deleted'
	Assert-Equal (Test-Path -LiteralPath $data -PathType Container) $true 'cleandata: the folder itself is kept'
	$r = Invoke-Helper @("/cleandata:$(Join-Path $temp 'Data')", "/trusted:$me")
	Assert-Equal $r.Ok $true 'cleandata on an empty folder'

	# 7. A user swaps folders for junctions while the helper runs: the outside folder must stay intact in every case.
	$race = Join-Path $temp 'Race'
	$count = 150
	1..$count | ForEach-Object {
		$dir = Join-Path $race "d$_"
		[void][IO.Directory]::CreateDirectory($dir)
		1..5 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $dir "f$_.txt"), 'x') }
	}
	1..30 | ForEach-Object { [IO.File]::WriteAllText((Join-Path $outside "keep$_.txt"), 'keep') }
	$attacker = Start-Job -ArgumentList $race, $outside, $count -ScriptBlock {
		param($race, $outside, $count)
		$end = (Get-Date).AddSeconds(25)
		while ((Get-Date) -lt $end) {
			1..$count | ForEach-Object {
				$dir = Join-Path $race "d$_"; $moved = $dir + '.old'
				try {
					# Folder -> junction to the outside -> folder again, over and over (the swap that a check-then-delete would miss).
					[IO.Directory]::Move($dir, $moved)
					$null = & cmd.exe /c mklink /J "`"$dir`"" "`"$outside`"" 2>&1
					[IO.Directory]::Delete($dir)
					[IO.Directory]::Move($moved, $dir)
				} catch {}
			}
		}
	}
	Start-Sleep -Milliseconds 300
	$r = Invoke-Helper @("/removetree:$race")
	Stop-Job $attacker -ErrorAction SilentlyContinue; Remove-Job $attacker -Force -ErrorAction SilentlyContinue
	$kept = @(1..30 | Where-Object { Test-Path -LiteralPath (Join-Path $outside "keep$_.txt") }).Count
	Assert-Equal $kept 30 "race: all files of the outside folder are intact (helper exit code $($r.Code))"
	Test-OutsideIntact 'race'
} finally {
	Get-ChildItem -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | ForEach-Object { Remove-TestJunction $_.FullName }
	Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "FAILED: $($script:errors.Count) of $script:checks checks."
	exit 1
}
Write-Output "PASS: $script:checks checks. Links are removed, never followed."
exit 0
