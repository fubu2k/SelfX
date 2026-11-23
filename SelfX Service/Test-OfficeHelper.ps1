<#
.SYNOPSIS
    Tests the Office helper functions (Sources\SelfXOffice.ps1): program path and processes of the own session.

.DESCRIPTION
    Runs in a sandbox: the Program Files variables point to a temporary folder, the registry reads (App Paths, Office
    InstallRoot) are simulated and the process functions are mocked, so nothing on the device is read, started or closed.
    Checked:
      - Test-SelfXOfficeProgramPath: only an existing file of the expected name below a Program Files folder is accepted;
        other folders, similar folder names, "..", UNC paths, relative paths, wrong names and folders are refused;
      - Get-SelfXOfficeAppPath: order of the sources (process, App Paths 64 bit and 32 bit view, Office InstallRoot of every
        version, newest first), refusal of untrusted values, no path when nothing valid is found, Word and Excel;
      - Get-SelfXOfficeLicenseFolder: Licenses and <version>\Licensing of every version folder, only existing folders;
      - Get-SelfXOwnSessionProcess and Close-SelfXOwnSessionProcess: only processes of the own Windows session, the
        process is asked to close first and ended only when it does not close.

.NOTES
    Name    : Test-OfficeHelper.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.4

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.0    2026-11-23  fubu2k               Initial version.
    2.8.4    2026-11-23  fubu2k               Tests for Get-SelfXOfficeLicenseFolder.
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ("$Actual" -cne "$Expected") { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}

# Mocks (global functions take precedence over the cmdlets). Registry paths (HKLM:) are simulated, everything else is real.
$global:FakeRegValues = @{}
$global:FakeRegKeys = @{}
$global:FakeProcesses = New-Object System.Collections.Generic.List[object]
$global:SelfXTestCalls = New-Object System.Collections.Generic.List[string]
function global:Get-ItemProperty {
	param($LiteralPath, $Path, $Name, $ErrorAction)
	if ("$LiteralPath" -like 'HKLM:*') { if ($global:FakeRegValues.ContainsKey("$LiteralPath")) { return $global:FakeRegValues["$LiteralPath"] }; return $null }
	Microsoft.PowerShell.Management\Get-ItemProperty @PSBoundParameters
}
function global:Get-ChildItem {
	param($LiteralPath, $Path, $Filter, [switch]$Recurse, [switch]$File, [switch]$Directory, [switch]$Force, $ErrorAction)
	if ("$LiteralPath" -like 'HKLM:*') { if ($global:FakeRegKeys.ContainsKey("$LiteralPath")) { return @($global:FakeRegKeys["$LiteralPath"] | ForEach-Object { [pscustomobject]@{ PSChildName = $_ } }) }; return @() }
	Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
}
function global:Get-Process {
	param([Parameter(Position = 0)][string[]]$Name, [int]$Id)
	if ($PSBoundParameters.ContainsKey('Id')) { return [pscustomobject]@{ Id = $Id; SessionId = 1 } }
	@($global:FakeProcesses | Where-Object { $p = $_; -not $Name -or ($Name | Where-Object { $p.ProcessName -like $_ }) })
}
function global:Stop-Process {
	param([Parameter(ValueFromPipeline = $true)]$InputObject, [switch]$Force)
	process { foreach ($item in @($InputObject)) { if ($item) { $global:SelfXTestCalls.Add("Stop-Process $($item.ProcessName) session $($item.SessionId)"); if (-not $item.Immortal) { [void]$global:FakeProcesses.Remove($item) } } } }
}
function global:Start-Sleep { param([int]$Seconds, [int]$Milliseconds) }
function New-FakeProcess([string]$Name, [int]$Session = 1, [bool]$ClosesOnRequest = $false, [bool]$Immortal = $false) {
	$process = [pscustomobject]@{ ProcessName = $Name; SessionId = $Session; Immortal = $Immortal; Closes = $ClosesOnRequest }
	$process | Add-Member ScriptMethod CloseMainWindow {
		$global:SelfXTestCalls.Add("CloseMainWindow $($this.ProcessName) session $($this.SessionId)")
		if ($this.Closes) { [void]$global:FakeProcesses.Remove($this) }
		return $true
	}
	$global:FakeProcesses.Add($process)
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('SelfXOfficeTests-' + [guid]::NewGuid().ToString('N'))
$saved = @{ PF = $env:ProgramFiles; PF6432 = $env:ProgramW6432; PF86 = ${env:ProgramFiles(x86)} }
function New-SandboxFile([string]$Path) { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [IO.File]::WriteAllText($Path, 'x') }
try {
	[void][IO.Directory]::CreateDirectory($sandbox)
	$pf64 = Join-Path $sandbox 'Program Files'
	$pf86 = Join-Path $sandbox 'Program Files (x86)'
	$env:ProgramFiles = $pf64; $env:ProgramW6432 = $pf64; ${env:ProgramFiles(x86)} = $pf86
	. (Join-Path $PSScriptRoot 'Sources\SelfXOffice.ps1')

	$out64 = Join-Path $pf64 'Microsoft Office\root\Office16\OUTLOOK.EXE'
	$out86 = Join-Path $pf86 'Microsoft Office\root\Office16\OUTLOOK.EXE'
	$outMsi = Join-Path $pf64 'Microsoft Office\Office15\OUTLOOK.EXE'
	$word64 = Join-Path $pf64 'Microsoft Office\root\Office16\WINWORD.EXE'
	$excel86 = Join-Path $pf86 'Microsoft Office\root\Office16\EXCEL.EXE'
	foreach ($file in $out64, $out86, $outMsi, $word64, $excel86) { New-SandboxFile $file }
	$evil = Join-Path $sandbox 'evil\OUTLOOK.EXE'; New-SandboxFile $evil
	$similar = Join-Path $sandbox 'Program Files-evil\OUTLOOK.EXE'; New-SandboxFile $similar
	[void][IO.Directory]::CreateDirectory((Join-Path $pf64 'Folder\OUTLOOK.EXE'))
	$appPaths64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE'
	$appPaths86 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE'

	# --- Test-SelfXOfficeProgramPath ----------------------------------------------------------------
	Assert-Equal (Test-SelfXOfficeProgramPath $out64 'OUTLOOK.EXE') $true 'path: file below Program Files is accepted'
	Assert-Equal (Test-SelfXOfficeProgramPath $out86 'OUTLOOK.EXE') $true 'path: file below Program Files (x86) is accepted'
	Assert-Equal (Test-SelfXOfficeProgramPath ('"' + $out64 + '"') 'OUTLOOK.EXE') $true 'path: quotes around the value are removed'
	Assert-Equal (Test-SelfXOfficeProgramPath $out64.ToLowerInvariant() 'outlook.exe') $true 'path: case does not matter'
	Assert-Equal (Test-SelfXOfficeProgramPath $out64 'WINWORD.EXE') $false 'path: wrong file name is refused'
	Assert-Equal (Test-SelfXOfficeProgramPath $evil 'OUTLOOK.EXE') $false 'path: file outside Program Files is refused'
	Assert-Equal (Test-SelfXOfficeProgramPath $similar 'OUTLOOK.EXE') $false 'path: folder with a similar name is refused'
	Assert-Equal (Test-SelfXOfficeProgramPath (Join-Path $pf64 'Microsoft Office\..\..\evil\OUTLOOK.EXE') 'OUTLOOK.EXE') $false 'path: ".." out of Program Files is refused'
	Assert-Equal (Test-SelfXOfficeProgramPath '\\server\share\OUTLOOK.EXE' 'OUTLOOK.EXE') $false 'path: UNC path is refused'
	Assert-Equal (Test-SelfXOfficeProgramPath 'OUTLOOK.EXE' 'OUTLOOK.EXE') $false 'path: relative path is refused'
	Assert-Equal (Test-SelfXOfficeProgramPath '' 'OUTLOOK.EXE') $false 'path: empty value is refused'
	Assert-Equal (Test-SelfXOfficeProgramPath (Join-Path $pf64 'Microsoft Office\missing\OUTLOOK.EXE') 'OUTLOOK.EXE') $false 'path: missing file is refused'
	Assert-Equal (Test-SelfXOfficeProgramPath (Join-Path $pf64 'Folder\OUTLOOK.EXE') 'OUTLOOK.EXE') $false 'path: folder is refused'
	Assert-Equal (Test-SelfXOfficeProgramPath ($out64 + '" /x') 'OUTLOOK.EXE') $false 'path: arguments after the path are refused'

	# --- Get-SelfXOfficeAppPath -----------------------------------------------------------------------
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook) '' 'app path: nothing registered gives no path'
	$global:FakeRegValues[$appPaths64] = [pscustomobject]@{ '(default)' = ('"' + $out64 + '"') }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook) $out64 'app path: App Paths (64 bit view) with quotes'
	$global:FakeRegValues.Clear()
	$global:FakeRegValues[$appPaths86] = [pscustomobject]@{ '(default)' = $out86 }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook) $out86 'app path: 32-bit Office, App Paths of the 32 bit view'
	$global:FakeRegValues.Clear()
	$global:FakeRegValues[$appPaths64] = [pscustomobject]@{ '(default)' = $evil }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook) '' 'app path: untrusted App Paths value is refused'
	$global:FakeRegValues.Clear()
	$global:FakeRegValues[$appPaths64] = [pscustomobject]@{ '(default)' = $out64 }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook -ProcessPath $out86) $out86 'app path: path of the running process comes first'
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook -ProcessPath $evil) $out64 'app path: untrusted process path falls back to App Paths'

	# Office InstallRoot of every version, newest first (MSI Office 15.0 and Click-to-Run 16.0), no App Paths entry
	$global:FakeRegValues.Clear()
	$officeKey = 'HKLM:\SOFTWARE\Microsoft\Office'
	$global:FakeRegKeys[$officeKey] = @('15.0', 'Common', 'ClickToRun', '16.0', 'abc')
	$global:FakeRegValues["$officeKey\15.0\Outlook\InstallRoot"] = [pscustomobject]@{ Path = (Split-Path -Parent $outMsi) + '\' }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook) $outMsi 'app path: InstallRoot of Office 15.0 (MSI)'
	$global:FakeRegValues["$officeKey\16.0\Outlook\InstallRoot"] = [pscustomobject]@{ Path = (Split-Path -Parent $out64) }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook) $out64 'app path: newest Office version first (16.0 before 15.0)'
	$global:FakeRegKeys[$officeKey] = @('9.0', '16.0')
	$global:FakeRegValues.Remove("$officeKey\15.0\Outlook\InstallRoot")
	$global:FakeRegValues["$officeKey\9.0\Outlook\InstallRoot"] = [pscustomobject]@{ Path = (Split-Path -Parent $outMsi) }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook) $out64 'app path: versions are sorted as numbers (16.0 before 9.0)'
	$global:FakeRegValues.Clear(); $global:FakeRegKeys.Clear()
	$wowKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office'
	$global:FakeRegKeys[$wowKey] = @('16.0')
	$global:FakeRegValues["$wowKey\16.0\Outlook\InstallRoot"] = [pscustomobject]@{ Path = (Split-Path -Parent $out86) }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook) $out86 'app path: 32-bit Office, InstallRoot of the 32 bit view'
	$global:FakeRegValues.Clear(); $global:FakeRegKeys.Clear()
	$global:FakeRegKeys[$officeKey] = @('16.0')
	$global:FakeRegValues["$officeKey\16.0\Outlook\InstallRoot"] = [pscustomobject]@{ Path = (Split-Path -Parent $evil) }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Outlook) '' 'app path: untrusted InstallRoot is refused'

	# Word and Excel use their own file names and registry keys
	$global:FakeRegValues.Clear(); $global:FakeRegKeys.Clear()
	$global:FakeRegValues['HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\WINWORD.EXE'] = [pscustomobject]@{ '(default)' = $word64 }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Word) $word64 'app path: Word'
	Assert-Equal (Get-SelfXOfficeAppPath -Application Excel) '' 'app path: Excel is not mixed up with Word'
	$global:FakeRegKeys[$wowKey] = @('16.0')
	$global:FakeRegValues["$wowKey\16.0\Excel\InstallRoot"] = [pscustomobject]@{ Path = (Split-Path -Parent $excel86) }
	Assert-Equal (Get-SelfXOfficeAppPath -Application Excel) $excel86 'app path: Excel from its InstallRoot'
	$failed = $false
	try { Get-SelfXOfficeAppPath -Application Access | Out-Null } catch { $failed = $true }
	Assert-Equal $failed $true 'app path: only Outlook, Word and Excel are accepted'

	# --- License token folders ---------------------------------------------------------------------------
	$localApp = Join-Path $sandbox 'LocalAppData'
	Assert-Equal @(Get-SelfXOfficeLicenseFolder -LocalAppData $localApp).Count 0 'license folders: nothing exists, nothing returned'
	Assert-Equal @(Get-SelfXOfficeLicenseFolder -LocalAppData '').Count 0 'license folders: empty base folder gives nothing'
	Assert-Equal @(Get-SelfXOfficeLicenseFolder -LocalAppData 'Office').Count 0 'license folders: relative base folder gives nothing'
	$officeBase = Join-Path $localApp 'Microsoft\Office'
	foreach ($relative in 'Licenses', '16.0\Licensing', '15.0\Licensing', '14.0\Common', '16.0\Wef', 'Teams\Licensing', '16.0.1\Licensing', 'x16.0\Licensing') {
		[void][IO.Directory]::CreateDirectory((Join-Path $officeBase $relative))
	}
	$licenseFolders = @(Get-SelfXOfficeLicenseFolder -LocalAppData $localApp | ForEach-Object { $_.Substring($officeBase.Length + 1) } | Sort-Object)
	Assert-Equal ($licenseFolders -join ';') '15.0\Licensing;16.0\Licensing;Licenses' 'license folders: Licenses and the Licensing folder of every version folder that exists'
	Assert-Equal ($licenseFolders -contains '14.0\Common') $false 'license folders: a version folder without Licensing is not returned'
	[void][IO.File]::WriteAllText((Join-Path $officeBase '17.0'), 'x')
	Assert-Equal @(Get-SelfXOfficeLicenseFolder -LocalAppData $localApp).Count 3 'license folders: a file with a version name is ignored'

	# --- Processes of the own session -----------------------------------------------------------------
	$global:FakeProcesses.Clear(); $global:SelfXTestCalls.Clear()
	New-FakeProcess 'OUTLOOK' 1
	New-FakeProcess 'OUTLOOK' 2
	New-FakeProcess 'olk' 1
	Assert-Equal @(Get-SelfXOwnSessionProcess -Name 'OUTLOOK').Count 1 'process: only the process of the own session is returned'
	Assert-Equal (Close-SelfXOwnSessionProcess -Name 'OUTLOOK') $true 'process: stubborn process is ended and gone'
	Assert-Equal ($global:SelfXTestCalls -join ';') 'CloseMainWindow OUTLOOK session 1;Stop-Process OUTLOOK session 1' 'process: asked to close first, then ended, own session only'
	Assert-Equal "$(@($global:FakeProcesses | Where-Object { $_.ProcessName -eq 'OUTLOOK' -and $_.SessionId -eq 2 }).Count)|$(@($global:FakeProcesses | Where-Object ProcessName -eq 'olk').Count)" '1|1' 'process: other session and other programs keep running'

	$global:FakeProcesses.Clear(); $global:SelfXTestCalls.Clear()
	New-FakeProcess 'OUTLOOK' 1 $true
	Assert-Equal (Close-SelfXOwnSessionProcess -Name 'OUTLOOK') $true 'process: process that closes itself'
	Assert-Equal ($global:SelfXTestCalls -join ';') 'CloseMainWindow OUTLOOK session 1' 'process: a process that closes is not ended'
	$global:SelfXTestCalls.Clear()
	Assert-Equal (Close-SelfXOwnSessionProcess -Name 'OUTLOOK') $true 'process: nothing running is fine'
	Assert-Equal $global:SelfXTestCalls.Count 0 'process: nothing running, nothing done'
	$global:FakeProcesses.Clear(); $global:SelfXTestCalls.Clear()
	New-FakeProcess 'OUTLOOK' 1 $false $true
	Assert-Equal (Close-SelfXOwnSessionProcess -Name 'OUTLOOK') $false 'process: a process that cannot be ended is reported'

	# --- Sources ------------------------------------------------------------------------------------
	$text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sources\SelfXOffice.ps1'))
	foreach ($pattern in 'Invoke-Expression', '\biex\b', 'Set-ItemProperty', 'New-Item', 'Remove-Item', 'Out-File', 'Set-Content', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-Process', 'Get-Command') {
		Assert-Equal ($text -match $pattern) $false "SelfXOffice.ps1 does not use $pattern"
	}
	$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Sources\SelfXOffice.ps1'), [ref]$null, [ref]$null)
	Assert-Equal ($ast.Extent.Text.Length -gt 0) $true 'SelfXOffice.ps1 parses'
} finally {
	$env:ProgramFiles = $saved.PF; $env:ProgramW6432 = $saved.PF6432; ${env:ProgramFiles(x86)} = $saved.PF86
	foreach ($name in 'Get-ItemProperty', 'Get-ChildItem', 'Get-Process', 'Stop-Process', 'Start-Sleep') { Remove-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue }
	if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
