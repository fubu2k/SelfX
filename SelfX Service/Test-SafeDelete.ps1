<#
.SYNOPSIS
    Tests the handle-based delete helper of SelfXService.exe (/removetree:, /cleandata:; class SafeTree).

.DESCRIPTION
    Install.ps1 and Uninstall.ps1 delete folders as SYSTEM that users can write to (Logs\Users\<SID>). The helper opens every
    entry once without following links and deletes through that handle. This test checks in a temporary folder that
    junctions are removed and never followed (also when swapped while the helper runs), that read-only files and long paths are
    deleted, that /cleandata: keeps trusted entries and deletes foreign-owned ones, and that wrong arguments are refused.
    /cleanold: (free up space, SelfX_Device_FreeSpace.ps1) is tested through /cleanoldpath: in the temporary folder only; the fixed
    folders (Windows\Temp, Intune content) are never cleaned by this test, only their names are checked.
    The helper is Bin\SelfXService.exe of the package (build it with tools\Build-SelfXBinaries.ps1) or the file named in
    SELFX_TEST_SAFEDELETE_EXE. Without it the test is skipped, unless SELFX_REQUIRE_BIN=1 (CI after the build): then it fails.
    No administrator rights are needed. Files are created only in a temporary folder.
    Windows PowerShell 5.1 or PowerShell 7: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SafeDelete.ps1

.NOTES
    Name    : Test-SafeDelete.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed (or skipped), 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.19   2026-11-23  fubu2k               Initial version (M1).
    3.1.0    2026-11-27  fubu2k               /cleanold: and /cleanoldpath: (free up space): only old entries, links deleted and never followed,
                                              also while folders are swapped for junctions; fixed folder names only; wrong arguments refused.
    3.1.0    2026-11-28  fubu2k               Race 9: empty folders are turned into junctions in place (FSCTL_SET_REPARSE_POINT on the open
                                              folder, no rename) while /removetree: and /cleanold: run; the outside folder must stay intact.
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

	# 8. /cleanold: deletes only entries whose newest time (creation, write, change) is older than /minage:. Links are deleted
	#    themselves when they are old and never followed; a folder is deleted only when it is old and empty afterwards.
	#    The times are set on a handle (FILE_BASIC_INFO), the only way to set the change time; this code exists only in the test.
	if (-not ('SelfXTestFileTimes' -as [type])) {
		Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class SelfXTestFileTimes
{
    [StructLayout(LayoutKind.Sequential)]
    struct FILE_BASIC_INFO { public long CreationTime; public long LastAccessTime; public long LastWriteTime; public long ChangeTime; public uint FileAttributes; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetFileInformationByHandle(SafeFileHandle handle, int infoClass, ref FILE_BASIC_INFO info, uint size);
    public static void SetAll(string path, DateTime utc)
    {
        // FILE_WRITE_ATTRIBUTES, share read/write/delete, OPEN_EXISTING, BACKUP_SEMANTICS | OPEN_REPARSE_POINT (a link itself).
        using (SafeFileHandle handle = CreateFileW(@"\\?\" + path, 0x100, 7, IntPtr.Zero, 3, 0x02000000 | 0x00200000, IntPtr.Zero))
        {
            if (handle.IsInvalid) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            FILE_BASIC_INFO info = new FILE_BASIC_INFO();
            long time = utc.ToFileTimeUtc();
            info.CreationTime = time; info.LastAccessTime = time; info.LastWriteTime = time; info.ChangeTime = time;
            if (!SetFileInformationByHandle(handle, 0, ref info, (uint)Marshal.SizeOf(typeof(FILE_BASIC_INFO)))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@
	}
	$oldTime = [datetime]::UtcNow.AddDays(-30)
	function Set-TestOld([string[]]$Paths) { foreach ($path in $Paths) { [SelfXTestFileTimes]::SetAll($path, $oldTime) } }
	function Invoke-CleanOld([string[]]$Arguments) {
		$out = @(& $exe @Arguments 2>&1 | ForEach-Object { "$_" })
		$line = @($out | Where-Object { $_ -match '^SELFX-CLEANOLD-OK removed=\d+ kept=\d+ bytes=\d+$' }) | Select-Object -First 1
		[pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out -join "`n"); Ok = ([bool]$line -and $LASTEXITCODE -eq 0); Line = "$line" }
	}

	$aged = Join-Path $temp 'Aged'
	foreach ($folder in 'Mixed', 'OldEmpty', 'OldTree\Sub') { [void][IO.Directory]::CreateDirectory((Join-Path $aged $folder)) }
	foreach ($file in 'old.txt', 'new.txt', 'Mixed\old.txt', 'Mixed\new.txt', 'OldTree\Sub\old2.txt') { [IO.File]::WriteAllText((Join-Path $aged $file), 'x' * 100) }
	New-TestJunction (Join-Path $aged 'OldLink') $outside
	New-TestJunction (Join-Path $aged 'NewLink') $outside
	# Old content of the outside folder: it would be deleted if a link were followed.
	Set-TestOld @((Join-Path $outside 'secret.log'), (Join-Path $outside 'Sub\deep.txt'), (Join-Path $outside 'Sub'))
	# Children first: a new entry changes the times of its folder.
	Set-TestOld @((Join-Path $aged 'old.txt'), (Join-Path $aged 'Mixed\old.txt'), (Join-Path $aged 'OldTree\Sub\old2.txt'), (Join-Path $aged 'OldTree\Sub'),
		(Join-Path $aged 'OldTree'), (Join-Path $aged 'OldEmpty'), (Join-Path $aged 'OldLink'), (Join-Path $aged 'Mixed'))
	$r = Invoke-CleanOld @("/cleanoldpath:$aged", '/minage:7')
	Assert-Equal $r.Ok $true "cleanold: result ok ($($r.Output))"
	Assert-Equal $r.Line 'SELFX-CLEANOLD-OK removed=7 kept=1 bytes=300' 'cleanold: counts (3 files of 100 bytes, 3 folders, 1 link removed; the old folder with a new file kept)'
	$left = @(Get-ChildItem -LiteralPath $aged -Recurse -Force | ForEach-Object { $_.FullName.Substring($aged.Length + 1) } | Sort-Object)
	Assert-Equal ($left -join ',') 'Mixed,Mixed\new.txt,new.txt,NewLink' 'cleanold: only old entries are deleted; a folder with a new entry and a new link stay'
	Test-OutsideIntact 'cleanold with old and new junctions'
	$r = Invoke-CleanOld @("/cleanoldpath:$aged", '/minage:7')
	# Deleting Mixed\old.txt changed the times of Mixed: the folder is new now and is not touched any more.
	Assert-Equal $r.Line 'SELFX-CLEANOLD-OK removed=0 kept=0 bytes=0' 'cleanold: a second run deletes nothing more'

	# The folder itself is a junction or lies behind one: refused, nothing deleted in the target.
	$rootLink = Join-Path $temp 'CleanRootLink'
	New-TestJunction $rootLink $outside
	$r = Invoke-CleanOld @("/cleanoldpath:$rootLink", '/minage:1')
	Assert-Equal "$($r.Code)/$($r.Ok)" '1/False' 'cleanold: a folder that is a junction is refused'
	$r = Invoke-CleanOld @("/cleanoldpath:$(Join-Path $rootLink 'Sub')", '/minage:1')
	Assert-Equal "$($r.Code)/$($r.Ok)" '1/False' 'cleanold: a folder behind a junction is refused'
	Remove-TestJunction $rootLink
	Test-OutsideIntact 'cleanold on and behind a junction'
	$r = Invoke-CleanOld @("/cleanoldpath:$(Join-Path $temp 'DoesNotExist')", '/minage:7')
	Assert-Equal $r.Line 'SELFX-CLEANOLD-OK removed=0 kept=0 bytes=0' 'cleanold: a missing folder is no error'

	# Wrong arguments: unknown or differently written folder names, both modes at once, invalid ages, no path for the test mode.
	foreach ($case in @(@('/cleanold:Windows', '/minage:7'), @('/cleanold:windowstemp', '/minage:7'), @('/cleanold:..\WindowsTemp', '/minage:7'),
		@('/cleanold:C:\Windows\Temp', '/minage:7'), @('/cleanold:WindowsTemp', "/cleanoldpath:$aged", '/minage:7'),
		@('/cleanold:WindowsTemp', '/minage:0'), @('/cleanold:WindowsTemp', '/minage:366'), @('/cleanold:WindowsTemp', '/minage:abc'),
		@('/cleanold:WindowsTemp', '/minage:-1'), @('/cleanold:WindowsTemp'), @('/cleanoldpath:relative\path', '/minage:7'),
		@('/cleanoldpath:\\server\share\x', '/minage:7'), @('/cleanoldpath:C:\', '/minage:7'))) {
		Assert-Equal (Invoke-CleanOld $case).Code 2 "cleanold: refused with exit code 2 ($($case -join ' '))"
	}
	# The fixed folder names exist in the helper (checked without running it on them).
	$serviceSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Service\SelfXService.cs'))
	foreach ($key in 'WindowsTemp', 'ImeIncoming', 'ImeStaging', 'ImeCache') {
		Assert-Equal ($serviceSource -match "case `"$key`": return ") $true "cleanold: fixed folder $key is defined in the helper"
	}
	Assert-Equal ($serviceSource -match 'identity\.IsSystem\) \{ Console\.WriteLine\("SELFX-CLEANOLD-ERROR: /cleanoldpath: is refused for SYSTEM') $true 'cleanold: the test mode is refused for SYSTEM'

	# A user swaps folders for junctions while /cleanold: runs: the old files of the outside folder must stay intact.
	$oldRace = Join-Path $temp 'OldRace'
	$oldCount = 80
	$racePaths = New-Object System.Collections.Generic.List[string]
	1..$oldCount | ForEach-Object {
		$dir = Join-Path $oldRace "d$_"
		[void][IO.Directory]::CreateDirectory($dir)
		1..3 | ForEach-Object { $file = Join-Path $dir "f$_.txt"; [IO.File]::WriteAllText($file, 'x'); $racePaths.Add($file) }
		$racePaths.Add($dir)
	}
	Set-TestOld $racePaths.ToArray()
	$keepFiles = @(1..30 | ForEach-Object { Join-Path $outside "keep$_.txt" })
	foreach ($file in $keepFiles) { [IO.File]::WriteAllText($file, 'keep') }
	Set-TestOld $keepFiles
	$attacker = Start-Job -ArgumentList $oldRace, $outside, $oldCount -ScriptBlock {
		param($race, $outside, $count)
		$end = (Get-Date).AddSeconds(20)
		while ((Get-Date) -lt $end) {
			1..$count | ForEach-Object {
				$dir = Join-Path $race "d$_"; $moved = $dir + '.old'
				try {
					[IO.Directory]::Move($dir, $moved)
					$null = & cmd.exe /c mklink /J "`"$dir`"" "`"$outside`"" 2>&1
					[IO.Directory]::Delete($dir)
					[IO.Directory]::Move($moved, $dir)
				} catch {}
			}
		}
	}
	Start-Sleep -Milliseconds 300
	$r = Invoke-CleanOld @("/cleanoldpath:$oldRace", '/minage:7')
	Stop-Job $attacker -ErrorAction SilentlyContinue; Remove-Job $attacker -Force -ErrorAction SilentlyContinue
	$keptOld = @($keepFiles | Where-Object { Test-Path -LiteralPath $_ }).Count
	Assert-Equal $keptOld 30 "cleanold race: all old files of the outside folder are intact (helper exit code $($r.Code))"
	Test-OutsideIntact 'cleanold race'

	# 9. The owner of an EMPTY folder turns it into a junction in place while the helper holds it open (FSCTL_SET_REPARSE_POINT;
	#    the open handle blocks renaming, not this). Entries listed and opened through the folder would then lie in the outside
	#    folder. The helper must check every handle and neither delete nor enter such an entry. Test code only.
	if (-not ('SelfXTestReparse' -as [type])) {
		Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
public static class SelfXTestReparse
{
    const uint FSCTL_SET_REPARSE_POINT = 0x000900A4;
    const uint FSCTL_DELETE_REPARSE_POINT = 0x000900AC;
    const uint IO_REPARSE_TAG_MOUNT_POINT = 0xA0000003;
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle device, uint code, byte[] input, int inputSize, IntPtr output, int outputSize, out int returned, IntPtr overlapped);
    // FILE_WRITE_ATTRIBUTES is enough for FSCTL_SET_REPARSE_POINT; share read/write/delete; BACKUP_SEMANTICS | OPEN_REPARSE_POINT.
    static SafeFileHandle OpenFolder(string path) { return CreateFileW(@"\\?\" + path, 0x100, 7, IntPtr.Zero, 3, 0x02000000 | 0x00200000, IntPtr.Zero); }
    static bool Control(string folder, uint code, byte[] buffer)
    {
        using (SafeFileHandle handle = OpenFolder(folder))
        {
            if (handle.IsInvalid) return false;
            int returned;
            return DeviceIoControl(handle, code, buffer, buffer.Length, IntPtr.Zero, 0, out returned, IntPtr.Zero);
        }
    }
    // REPARSE_DATA_BUFFER (MountPointReparseBuffer): tag, data length, reserved, offsets and lengths, substitute and print name.
    public static bool SetMountPoint(string folder, string target)
    {
        byte[] substitute = Encoding.Unicode.GetBytes(@"\??\" + target.TrimEnd('\\') + @"\");
        byte[] print = Encoding.Unicode.GetBytes(target);
        int dataLength = 8 + substitute.Length + 2 + print.Length + 2;
        byte[] buffer = new byte[8 + dataLength];
        BitConverter.GetBytes(IO_REPARSE_TAG_MOUNT_POINT).CopyTo(buffer, 0);
        BitConverter.GetBytes((ushort)dataLength).CopyTo(buffer, 4);
        BitConverter.GetBytes((ushort)0).CopyTo(buffer, 8);
        BitConverter.GetBytes((ushort)substitute.Length).CopyTo(buffer, 10);
        BitConverter.GetBytes((ushort)(substitute.Length + 2)).CopyTo(buffer, 12);
        BitConverter.GetBytes((ushort)print.Length).CopyTo(buffer, 14);
        substitute.CopyTo(buffer, 16);
        print.CopyTo(buffer, 16 + substitute.Length + 2);
        return Control(folder, FSCTL_SET_REPARSE_POINT, buffer);
    }
    public static bool DeleteMountPoint(string folder)
    {
        byte[] buffer = new byte[8];
        BitConverter.GetBytes(IO_REPARSE_TAG_MOUNT_POINT).CopyTo(buffer, 0);
        return Control(folder, FSCTL_DELETE_REPARSE_POINT, buffer);
    }
}
'@
	}
	# The setup works: an empty folder becomes a junction in place and a folder again.
	$probe = Join-Path $temp 'Probe'
	[void][IO.Directory]::CreateDirectory($probe)
	Assert-Equal ([SelfXTestReparse]::SetMountPoint($probe, $outside)) $true 'in-place race: setup turns an empty folder into a junction'
	Assert-Equal (Test-Path -LiteralPath (Join-Path $probe 'secret.log')) $true 'in-place race: setup junction leads to the outside folder'
	Assert-Equal ([SelfXTestReparse]::DeleteMountPoint($probe)) $true 'in-place race: setup turns the junction back into a folder'
	Assert-Equal ([bool]((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) $false 'in-place race: setup folder is a plain folder again'

	# The attacker runs in a runspace of this process (the type above is loaded here) and toggles every folder for a while.
	function Start-InPlaceAttacker([string]$Root, [int]$Count, [int]$Seconds) {
		$shell = [powershell]::Create()
		[void]$shell.AddScript({
			param($root, $outside, $count, $seconds)
			$end = (Get-Date).AddSeconds($seconds)
			while ((Get-Date) -lt $end) {
				for ($i = 1; $i -le $count; $i++) {
					$dir = Join-Path $root "e$i"
					if ([SelfXTestReparse]::SetMountPoint($dir, $outside)) { [void][SelfXTestReparse]::DeleteMountPoint($dir) }
				}
			}
		}).AddArgument($Root).AddArgument($outside).AddArgument($Count).AddArgument($Seconds)
		[pscustomobject]@{ Shell = $shell; Handle = $shell.BeginInvoke() }
	}
	function Stop-InPlaceAttacker($Attacker) { try { $Attacker.Shell.Stop(); $Attacker.Shell.Dispose() } catch {} }
	$inPlaceKeep = @(1..30 | ForEach-Object { Join-Path $outside "inplace$_.txt" })
	foreach ($file in $inPlaceKeep) { [IO.File]::WriteAllText($file, 'keep') }
	Set-TestOld $inPlaceKeep

	# /cleanold: several runs, the folders stay (they are new); every run lists them while the attacker toggles them.
	$inPlaceOld = Join-Path $temp 'InPlaceOld'
	$inPlaceCount = 200
	1..$inPlaceCount | ForEach-Object { [void][IO.Directory]::CreateDirectory((Join-Path $inPlaceOld "e$_")) }
	$attacker = Start-InPlaceAttacker -Root $inPlaceOld -Count $inPlaceCount -Seconds 20
	try {
		Start-Sleep -Milliseconds 300
		for ($run = 1; $run -le 15; $run++) { $null = Invoke-CleanOld @("/cleanoldpath:$inPlaceOld", '/minage:7') }
	} finally { Stop-InPlaceAttacker $attacker }
	$keptInPlace = @($inPlaceKeep | Where-Object { Test-Path -LiteralPath $_ }).Count
	Assert-Equal $keptInPlace 30 'in-place race: /cleanold: deletes no old file of the outside folder'
	Test-OutsideIntact 'in-place race cleanold'
	foreach ($dir in @(Get-ChildItem -LiteralPath $inPlaceOld -Force -ErrorAction SilentlyContinue)) { if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { [void][SelfXTestReparse]::DeleteMountPoint($dir.FullName) } }

	# /removetree: deletes the folders; each one may be a junction when it is listed.
	$inPlaceTree = Join-Path $temp 'InPlaceTree'
	for ($run = 1; $run -le 10; $run++) {
		1..$inPlaceCount | ForEach-Object { [void][IO.Directory]::CreateDirectory((Join-Path $inPlaceTree "e$_")) }
		$attacker = Start-InPlaceAttacker -Root $inPlaceTree -Count $inPlaceCount -Seconds 5
		try {
			Start-Sleep -Milliseconds 100
			$null = Invoke-Helper @("/removetree:$inPlaceTree")
		} finally { Stop-InPlaceAttacker $attacker }
		if (Test-Path -LiteralPath $inPlaceTree) {
			foreach ($dir in @(Get-ChildItem -LiteralPath $inPlaceTree -Force -ErrorAction SilentlyContinue)) { if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { [void][SelfXTestReparse]::DeleteMountPoint($dir.FullName) } }
		}
	}
	$keptTree = @($inPlaceKeep | Where-Object { Test-Path -LiteralPath $_ }).Count
	Assert-Equal $keptTree 30 'in-place race: /removetree: deletes no file of the outside folder'
	Test-OutsideIntact 'in-place race removetree'

	# The helper source checks every child handle (static check; the race above is probabilistic).
	$serviceSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Service\SelfXService.cs') -Raw
	Assert-Equal ([regex]::Matches($serviceSource, 'OpenExact\(').Count) 4 'in-place race: RemoveEntry, CleanFolder and CleanOld open children with OpenExact'
	Assert-Equal ([regex]::Matches($serviceSource, '(?m)^\s+using \(SafeFileHandle handle = Open\((child|path),').Count) 0 'in-place race: no child is opened without the final path check'

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
