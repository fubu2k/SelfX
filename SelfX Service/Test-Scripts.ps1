<#
.SYNOPSIS
    Run the SelfX Service action, repair and check scripts in a sandbox and verify their result and log.
.DESCRIPTION
    Every script of Sources\Scripts_to_run is executed (or, for the scripts with dangerous effects, its
    functions are called) with mocked commands: no process is closed, nothing is started, no service,
    network adapter, volume, registry value or Windows Update is touched and Windows is never restarted.
    APPDATA, LOCALAPPDATA, TEMP and ProgramData point to a temporary sandbox, so the cache scripts delete
    only sandbox files and all logs (SelfXLog.ps1) are written to the sandbox, where they are checked.
    The read-only scripts Check-Compliance.ps1, Detection.ps1 and HealthStatus.ps1 -Collect run for real
    in a child process (with the sandbox ProgramData), to verify their output and log.
    Also checks the headers, the logging and the catalog / Health_Config references of all scripts.
    Run in Windows PowerShell 5.1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Scripts.ps1
.NOTES
    Version: 2.6.9
    History:
    2.6.0  2026-11-06  Wolfgang Baeck  Initial version: sandbox tests of all action, repair and check scripts.
    2.6.3  2026-11-06  Wolfgang Baeck  Updates: Windows Update Agent flow with a simulated session.
    2.6.9  2026-11-19  Wolfgang Baeck  Updates: simulated Windows Update orchestrator; WUA skips feature updates.
#>
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility
Import-Module Microsoft.PowerShell.Management
Import-Module Microsoft.PowerShell.Security
$sources = Join-Path $PSScriptRoot 'Sources'
$scripts = Join-Path $sources 'Scripts_to_run'

$script:assertions = 0
function Assert-Equal($Actual, $Expected, $Message) {
	$script:assertions++
	if ($Actual -ne $Expected) { throw "$Message : expected '$Expected', got '$Actual'." }
}

#----------------------------------------------------------------------------------------------------
# Mocks: everything that could change this device. Functions take precedence over cmdlets; module
# autoloading is disabled, so no real module can replace a mock.
#----------------------------------------------------------------------------------------------------
# Global: inside the mocks "$script:" would be the scope of the tested script.
$global:SelfXTestCalls = New-Object System.Collections.Generic.List[string]
$script:calls = $global:SelfXTestCalls
$global:FakeProcesses = New-Object System.Collections.Generic.List[object]
function global:New-FakeProcess([string]$Name, [string]$Path) {
	$process = [pscustomobject]@{ ProcessName = $Name; Name = $Name; Path = $Path; SessionId = 1; Id = (Get-Random -Minimum 10000 -Maximum 99999) }
	$global:FakeProcesses.Add($process)
}
function global:Get-Process {
	param([Parameter(Position = 0)][string[]]$Name, [int]$Id)
	if ($PSBoundParameters.ContainsKey('Id')) { return [pscustomobject]@{ Id = $Id; SessionId = 1 } }
	@($global:FakeProcesses | Where-Object { $p = $_; -not $Name -or ($Name | Where-Object { $p.ProcessName -like $_ }) })
}
function global:Stop-Process {
	param([Parameter(ValueFromPipeline = $true)]$InputObject, [switch]$Force)
	process { foreach ($item in @($InputObject)) { if ($item) { $global:SelfXTestCalls.Add("Stop-Process $($item.ProcessName)"); [void]$global:FakeProcesses.Remove($item) } } }
}
function global:Start-Process {
	param([Parameter(Position = 0)][string]$FilePath, [Parameter(Position = 1)]$ArgumentList, [switch]$PassThru, [switch]$Wait, $WindowStyle)
	$global:SelfXTestCalls.Add("Start-Process $FilePath $(@($ArgumentList) -join ' ')".Trim())
	if ($PassThru) { $fake = [pscustomobject]@{ ExitCode = 0 }; $fake | Add-Member ScriptMethod WaitForExit { param($ms) $true }; return $fake }
}
function global:Start-Sleep { param([int]$Seconds, [int]$Milliseconds) }
function global:Restart-Service { param($Name, [switch]$Force, $ErrorAction) $global:SelfXTestCalls.Add("Restart-Service $Name") }
function global:Get-Service { param($Name, $ErrorAction) [pscustomobject]@{ Name = $Name; Status = 'Running' } }
# The network cmdlets (compatibility layer in PowerShell 7) are not used any more: calling them fails the test. SelfXNetwork.ps1 reads CIM.
function global:Restart-NetAdapter { throw 'Restart-NetAdapter is not allowed (use SelfXNetwork.ps1)' }
function global:Get-NetAdapter { throw 'Get-NetAdapter is not allowed (use SelfXNetwork.ps1)' }
function global:Get-NetRoute { throw 'Get-NetRoute is not allowed (use SelfXNetwork.ps1)' }
# Repair-Volume and Clear-DnsClientCache (compatibility layer in PowerShell 7) are not used any more: calling them fails the test. The scripts use CIM.
function global:Repair-Volume { throw 'Repair-Volume is not allowed (use CIM MSFT_Volume.Repair)' }
function global:Clear-RecycleBin { param([switch]$Force, $Confirm, $ErrorAction) $global:SelfXTestCalls.Add('Clear-RecycleBin'); throw 'The system cannot find the path specified.' }
function global:Clear-DnsClientCache { throw 'Clear-DnsClientCache is not allowed (use CIM MSFT_DNSClientCache.Clear)' }
# The Defender module is not used any more (compatibility layer in PowerShell 7): calling it fails the test. SelfXDefender.ps1 reads CIM.
function global:Get-MpComputerStatus { throw 'Get-MpComputerStatus is not allowed (use SelfXDefender.ps1)' }
function global:Update-MpSignature { throw 'Update-MpSignature is not allowed (use SelfXDefender.ps1)' }
# Only the two network classes are simulated (raw CIM objects of root\StandardCimv2); every other class or method fails the test.
function global:Get-CimInstance {
	param($Namespace, $ClassName, $Filter, $ErrorAction)
	if ($Namespace -eq 'root\StandardCimv2' -and $ClassName -eq 'MSFT_NetAdapter') { if ($global:FakeCimFails) { throw 'Mock CIM denied' }; return $global:FakeAdapters }
	if ($Namespace -eq 'root\Microsoft\Windows\Defender' -and $ClassName -eq 'MSFT_MpComputerStatus') { return [pscustomobject]@{ AntivirusSignatureVersion = $global:SignatureVersion; AntivirusSignatureLastUpdated = [datetime]'2026-11-06 10:00' } }
	if ($Namespace -eq 'root\CIMV2\Security\MicrosoftVolumeEncryption' -and $ClassName -eq 'Win32_EncryptableVolume') { if ($global:FakeCimFails) { throw 'Mock CIM denied' }; return $global:FakeVolumes }
	if ($Namespace -eq 'root\CIMV2\Security\MicrosoftTpm' -and $ClassName -eq 'Win32_Tpm') { if ($global:FakeCimFails) { throw 'Mock CIM denied' }; return $global:FakeTpm }
	if ($Namespace -eq 'root\Microsoft\Windows\Storage' -and $ClassName -eq 'MSFT_Volume') { return @([pscustomobject]@{ DriveLetter = [char]'Z' }, [pscustomobject]@{ DriveLetter = [char]("$env:SystemDrive".TrimEnd(':', '\')[0]) }) }
	if ($Namespace -eq 'root\StandardCimv2' -and $ClassName -eq 'MSFT_NetRoute') { if ($global:FakeCimFails) { throw 'Mock CIM denied' }; return $global:FakeRoutes }
	throw "Get-CimInstance is not allowed in tests ($ClassName)"
}
function global:Invoke-CimMethod {
	param($InputObject, $Namespace, $ClassName, $MethodName, $Arguments, $ErrorAction)
	if ($Namespace -eq 'root\StandardCimv2' -and $ClassName -eq 'MSFT_DNSClientCache' -and $MethodName -eq 'Clear') {
		$global:SelfXTestCalls.Add('Dns-Clear')
		if ($global:DnsFails) { throw 'Access denied' }
		return $null
	}
	if ($MethodName -eq 'Repair' -and $InputObject.DriveLetter) {
		$global:SelfXTestCalls.Add("Repair $($InputObject.DriveLetter) offline=$($Arguments.OfflineScanAndFix)")
		return [pscustomobject]@{ ReturnValue = $(if ($null -ne $global:RepairReturn) { $global:RepairReturn } else { 0 }); Output = 0 }
	}
	if ($Namespace -eq 'root\Microsoft\Windows\Defender' -and $ClassName -eq 'MSFT_MpSignature' -and $MethodName -eq 'Update') {
		$global:SelfXTestCalls.Add('Defender-Update')
		if ($global:UpdateFails) { throw 'No connection' }
		$global:SignatureVersion = '1.441.99.0'
		return [pscustomobject]@{ ReturnValue = $(if ($null -ne $global:UpdateReturn) { $global:UpdateReturn } else { 0 }) }
	}
	if ($MethodName -ne 'Restart' -or -not $InputObject.InterfaceIndex) { throw 'Invoke-CimMethod is not allowed in tests' }
	$global:SelfXTestCalls.Add("Restart-NetAdapter $($InputObject.Name)")
}
function global:Register-ScheduledTask { throw 'Forbidden in tests' }
function global:New-ScheduledTask { throw 'Forbidden in tests' }
function global:New-ScheduledTaskAction { throw 'Forbidden in tests' }
function global:Start-ScheduledTask { throw 'Forbidden in tests' }
# Registry: HKCU / HKLM writes are only recorded; file system calls go to the real cmdlets (sandbox).
function global:Set-ItemProperty {
	param([string]$LiteralPath, [string]$Path, $Name, $Value, $Type, [switch]$Force)
	$target = "$LiteralPath$Path"
	if ($target -like 'HK*') { $global:SelfXTestCalls.Add("Set-ItemProperty $target $Name=$Value"); return }
	Microsoft.PowerShell.Management\Set-ItemProperty @PSBoundParameters
}
function global:New-Item {
	param([string]$Path, [string]$ItemType, [switch]$Force, $Value)
	if ($Path -like 'HK*') { $global:SelfXTestCalls.Add("New-Item $Path"); return }
	Microsoft.PowerShell.Management\New-Item @PSBoundParameters
}
$PSModuleAutoLoadingPreference = 'None'
foreach ($name in 'Get-Process', 'Stop-Process', 'Start-Process', 'Restart-Service', 'Get-Service', 'Restart-NetAdapter', 'Get-NetAdapter', 'Get-NetRoute',
	'Repair-Volume', 'Clear-RecycleBin', 'Clear-DnsClientCache', 'Update-MpSignature', 'Get-MpComputerStatus', 'Get-CimInstance', 'Invoke-CimMethod',
	'Register-ScheduledTask', 'New-ScheduledTask', 'Start-ScheduledTask', 'Set-ItemProperty', 'New-Item', 'Start-Sleep') {
	Assert-Equal (Get-Command $name).CommandType Function "Mock resolution: $name"
}

# Sandbox for the profile folders, TEMP and ProgramData (logs).
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('SelfXScriptTests-' + [guid]::NewGuid().ToString('N'))
$saved = @{ LOCALAPPDATA = $env:LOCALAPPDATA; APPDATA = $env:APPDATA; TEMP = $env:TEMP; TMP = $env:TMP; ProgramData = $env:ProgramData }
function New-SandboxFile([string]$Path) { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [IO.File]::WriteAllText($Path, 'x') }
function Get-SandboxLog([string]$Component) {
	$files = @(Get-ChildItem -LiteralPath $sandbox -Recurse -File -Filter "$($Component)_*.log" -ErrorAction SilentlyContinue)
	return (($files | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n")
}
function Invoke-TestScript([string]$Name, [hashtable]$Arguments = @{}) {
	$script:calls.Clear()
	$global:LASTEXITCODE = $null
	$result = [pscustomobject]@{ ExitCode = $null; Output = @(); Error = '' }
	try { $result.Output = @(& (Join-Path $scripts $Name) @Arguments 2>&1); $result.ExitCode = $global:LASTEXITCODE }
	catch { $result.Error = "$($_.Exception.Message) @ $($_.ScriptStackTrace -replace '\r?\n', ' <- ')"; $result.ExitCode = 1 }
	return $result
}

try {
	[void][IO.Directory]::CreateDirectory($sandbox)
	$env:LOCALAPPDATA = Join-Path $sandbox 'Local'
	$env:APPDATA = Join-Path $sandbox 'Roaming'
	$env:TEMP = Join-Path $sandbox 'Temp'
	$env:TMP = $env:TEMP
	$env:ProgramData = Join-Path $sandbox 'ProgramData'
	foreach ($folder in $env:LOCALAPPDATA, $env:APPDATA, $env:TEMP, $env:ProgramData) { [void][IO.Directory]::CreateDirectory($folder) }

	#------------------------------------------------------------------------------------------------
	# Static checks: header, logging, references
	#------------------------------------------------------------------------------------------------
	$catalog = [xml][IO.File]::ReadAllText("$sources\Issues_List.xml")
	$health = [xml][IO.File]::ReadAllText("$sources\Health_Config.xml")
	$referenced = @($catalog.SelectNodes('//Action/Script') | ForEach-Object { $_.InnerText.Trim() }) + @($health.SelectNodes('//Remediation') | ForEach-Object { $_.GetAttribute('Script') })
	$script:unused = @()
	foreach ($name in ($referenced | Sort-Object -Unique)) { Assert-Equal (Test-Path -LiteralPath (Join-Path $scripts $name)) $true "Referenced script exists: $name" }
	foreach ($file in Get-ChildItem -LiteralPath $scripts -Filter '*.ps1') {
		if ($file.Name -eq 'Collect-DeviceLogs.ps1') { continue }   # external collector, logged by SelfX_Device_CollectLogs.ps1
		$text = [IO.File]::ReadAllText($file.FullName)
		# Code checks only after the header (its history describes the former behaviour).
		$code = $text.Substring($text.IndexOf('#>') + 2)
		$errors = $null
		[void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
		Assert-Equal @($errors).Count 0 "$($file.Name) parses"
		Assert-Equal ($text -match 'Version\s*:\s*2\.\d+\.\d+') $true "$($file.Name) header version 2.x.y"
		Assert-Equal ($code.Contains('Initialize-SelfXLog')) $true "$($file.Name) initializes the logging"
		Assert-Equal ($code -match '(?i)-like\s+"\*(word|teams)\*"') $false "$($file.Name) uses no *word* / *teams* wildcards"
		Assert-Equal ($code.Contains('echo Y|')) $false "$($file.Name) does not answer prompts in English only"
		Assert-Equal ($code -match '(?i)C:\\Users\\') $false "$($file.Name) uses no fixed C:\Users path"
		if ($referenced -notcontains $file.Name) { $script:unused += $file.Name }
	}
	foreach ($action in $catalog.SelectNodes('//Action')) {
		$text = [IO.File]::ReadAllText((Join-Path $scripts $action.Script.Trim()))
		Assert-Equal ($text -match "Context\s*:\s*$($action.Context.Trim())") $true "$($action.Script) header context matches the catalog ($($action.GetAttribute('Id')))"
	}
	foreach ($remediation in $health.SelectNodes('//Remediation')) {
		Assert-Equal ([IO.File]::ReadAllText((Join-Path $scripts $remediation.GetAttribute('Script'))) -match 'Context\s*:\s*System') $true "$($remediation.GetAttribute('Script')) runs as System"
	}

	#------------------------------------------------------------------------------------------------
	# User actions
	#------------------------------------------------------------------------------------------------
	$chrome = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default'
	foreach ($item in 'Cache\data_0', 'Code Cache\js\a', 'Cookies', 'Network\Cookies', 'History', 'Bookmarks') { New-SandboxFile (Join-Path $chrome $item) }
	New-FakeProcess 'chrome' 'C:\Program Files\Google\Chrome\Application\chrome.exe'
	$run = Invoke-TestScript 'SelfX_Browser_ClearChromeCache.ps1'
	Assert-Equal $run.ExitCode 0 "Chrome cache: exit code ($($run.Error) $($run.Output -join ' '))"
	Assert-Equal "$(Test-Path (Join-Path $chrome 'Cache'))/$(Test-Path (Join-Path $chrome 'Cookies'))/$(Test-Path (Join-Path $chrome 'Bookmarks'))" 'False/False/True' 'Chrome cache: caches removed, bookmarks kept'
	Assert-Equal ($script:calls -contains 'Stop-Process chrome') $true 'Chrome cache: Chrome closed'
	Assert-Equal ((Get-SandboxLog 'SelfX_Browser_ClearChromeCache') -match 'Removed Cache') $true 'Chrome cache: logged'

	$edge = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default'
	foreach ($item in 'Cache\data_0', 'Code Cache\js\a', 'GPUCache\x', 'Cookies', 'Network\Cookies', 'History', 'Login Data', 'Bookmarks') { New-SandboxFile (Join-Path $edge $item) }
	New-FakeProcess 'msedge' 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
	$run = Invoke-TestScript 'SelfX_Browser_ClearEdgeCache.ps1'
	Assert-Equal $run.ExitCode 0 "Edge cache: exit code ($($run.Error) $($run.Output -join ' '))"
	Assert-Equal "$(Test-Path (Join-Path $edge 'Cache'))/$(Test-Path (Join-Path $edge 'Code Cache'))/$(Test-Path (Join-Path $edge 'GPUCache'))" 'False/False/False' 'Edge cache: cache folders removed'
	Assert-Equal "$(Test-Path (Join-Path $edge 'Cookies'))/$(Test-Path (Join-Path $edge 'Network\Cookies'))/$(Test-Path (Join-Path $edge 'History'))/$(Test-Path (Join-Path $edge 'Login Data'))/$(Test-Path (Join-Path $edge 'Bookmarks'))" 'True/True/True/True/True' 'Edge cache: cookies, history, passwords and bookmarks kept'
	Assert-Equal ($script:calls -contains 'Stop-Process msedge') $true 'Edge cache: Edge closed'
	Assert-Equal ((Get-SandboxLog 'SelfX_Browser_ClearEdgeCache') -match 'Removed Cache') $true 'Edge cache: logged'
	$run = Invoke-TestScript 'SelfX_Browser_ClearEdgeCache.ps1'
	Assert-Equal $run.ExitCode 0 'Edge cache: second run without cache folders is fine'

	foreach ($root in $env:LOCALAPPDATA, $env:APPDATA) { New-SandboxFile (Join-Path $root 'Mozilla\Firefox\Profiles\abc.default\cache2\entries\x'); New-SandboxFile (Join-Path $root 'Mozilla\Firefox\Profiles\abc.default\cookies.sqlite'); New-SandboxFile (Join-Path $root 'Mozilla\Firefox\Profiles\abc.default\places.sqlite') }
	$run = Invoke-TestScript 'SelfX_Browser_ClearFirefoxCache.ps1'
	Assert-Equal $run.ExitCode 0 'Firefox cache: exit code'
	Assert-Equal "$(Test-Path (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles\abc.default\cookies.sqlite'))/$(Test-Path (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles\abc.default\places.sqlite'))" 'False/True' 'Firefox cache: cookies removed, places kept'
	Assert-Equal ((Get-SandboxLog 'SelfX_Browser_ClearFirefoxCache') -match '2 profile folder') $true 'Firefox cache: both profile roots logged'

	$global:DnsFails = $false
	Assert-Equal (Invoke-TestScript 'SelfX_Device_ClearCache.ps1').ExitCode 0 'DNS cache: exit code'
	Assert-Equal ($script:calls -join ';') 'Dns-Clear' 'DNS cache: cleared through CIM (MSFT_DNSClientCache.Clear) only'
	$global:DnsFails = $true
	Assert-Equal (Invoke-TestScript 'SelfX_Device_ClearCache.ps1').ExitCode 1 'DNS cache: failure is exit 1'
	Assert-Equal ((Get-SandboxLog 'SelfX_Device_ClearCache') -match 'Error.*Access denied') $true 'DNS cache: failure logged'

	New-SandboxFile (Join-Path $env:TEMP 'a.tmp'); New-SandboxFile (Join-Path $env:TEMP 'sub\b.tmp')
	$run = Invoke-TestScript 'SelfX_Device_DeviceSlow.ps1'
	Assert-Equal $run.ExitCode 0 'Device slow: an empty recycle bin is no error'
	Assert-Equal @(Get-ChildItem -LiteralPath $env:TEMP -Force | Where-Object { $_.Name -ne 'SelfX' }).Count 0 'Device slow: TEMP emptied'
	Assert-Equal ((Get-SandboxLog 'SelfX_Device_DeviceSlow') -match 'TEMP: 2 item\(s\) removed') $true 'Device slow: logged'

	New-FakeProcess 'EXCEL' 'C:\Office\EXCEL.EXE'
	$run = Invoke-TestScript 'SelfX_Excel_Reboot.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Stop-Process EXCEL;Start-Process C:\Office\EXCEL.EXE' 'Excel: closed and started again'
	$run = Invoke-TestScript 'SelfX_Excel_Reboot.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls.Count)" '0|0' 'Excel: nothing to do when not running'

	New-FakeProcess 'WINWORD' 'C:\Office\WINWORD.EXE'
	New-FakeProcess '1Password' 'C:\Apps\1Password.exe'
	New-FakeProcess 'wordpad' 'C:\Windows\wordpad.exe'
	$run = Invoke-TestScript 'SelfX_Word_Reboot.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Stop-Process WINWORD;Start-Process C:\Office\WINWORD.EXE' 'Word: only WINWORD is closed and started again'
	Assert-Equal @($global:FakeProcesses | Where-Object { $_.ProcessName -in '1Password', 'wordpad' }).Count 2 'Word: 1Password and WordPad keep running'
	$global:FakeProcesses.Clear()

	New-FakeProcess 'ms-teams' 'C:\Program Files\WindowsApps\MSTeams_1_x64__8wekyb3d8bbwe\ms-teams.exe'
	New-FakeProcess 'ms-teams' 'C:\Program Files\WindowsApps\MSTeams_1_x64__8wekyb3d8bbwe\ms-teams.exe'
	New-FakeProcess 'TeamViewer' 'C:\Apps\TeamViewer.exe'
	$run = Invoke-TestScript 'SelfX_Teams_Reboot.ps1'
	Assert-Equal $run.ExitCode 0 'Teams restart: exit code'
	Assert-Equal @($script:calls | Where-Object { $_ -like 'Stop-Process*' }).Count 2 'Teams restart: both Teams processes closed'
	Assert-Equal ($script:calls[-1] -like '*explorer.exe shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams') $true 'Teams restart: new Teams started through its app ID'
	Assert-Equal @($global:FakeProcesses | Where-Object ProcessName -eq 'TeamViewer').Count 1 'Teams restart: TeamViewer keeps running'

	$newTeamsCache = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
	New-SandboxFile (Join-Path $newTeamsCache 'EBWebView\a'); New-SandboxFile (Join-Path $newTeamsCache 'settings.json')
	New-SandboxFile (Join-Path $env:APPDATA 'Microsoft\Teams\IndexedDB\x'); New-SandboxFile (Join-Path $env:APPDATA 'Microsoft\Teams\desktop-config.json')
	$run = Invoke-TestScript 'SelfX_Teams_ResetCache.ps1'
	Assert-Equal $run.ExitCode 0 'Teams cache: exit code'
	Assert-Equal "$(@(Get-ChildItem -LiteralPath $newTeamsCache -Force).Count)/$(Test-Path (Join-Path $env:APPDATA 'Microsoft\Teams\IndexedDB'))/$(Test-Path (Join-Path $env:APPDATA 'Microsoft\Teams\desktop-config.json'))" '0/False/True' 'Teams cache: caches removed, configuration kept'
	Assert-Equal ($script:calls[-1] -like '*shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams') $true 'Teams cache: new Teams started again'
	$global:FakeProcesses.Clear()

	$oneDrive = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
	New-SandboxFile $oneDrive
	New-FakeProcess 'OneDrive' $oneDrive
	$run = Invoke-TestScript 'SelfX_OneDrive_Reboot.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" "0|Stop-Process OneDrive;Start-Process $oneDrive /background" 'OneDrive restart: closed and started in the background'
	New-FakeProcess 'OneDrive' $oneDrive
	$run = Invoke-TestScript 'SelfX_OneDrive_Reset.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" "0|Stop-Process OneDrive;Start-Process $oneDrive /reset;Start-Process $oneDrive /background" 'OneDrive reset: reset and background start'
	$run = Invoke-TestScript 'SelfX_OneDrive_Run.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" "0|Start-Process $oneDrive" 'OneDrive start: started from LOCALAPPDATA'
	New-FakeProcess 'OneDrive' $oneDrive
	$run = Invoke-TestScript 'SelfX_OneDrive_Run.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls.Count)" '0|0' 'OneDrive start: no second start when running'
	$global:FakeProcesses.Clear()

	New-FakeProcess 'OUTLOOK' 'C:\Office\OUTLOOK.EXE'
	$run = Invoke-TestScript 'SelfX_Outlook_TeamsAddIn.ps1'
	Assert-Equal $run.ExitCode 0 'Outlook add-in: exit code'
	Assert-Equal (@($script:calls | Where-Object { $_ -like 'Set-ItemProperty HKCU:*TeamsAddin.FastConnect LoadBehavior=3' }).Count) 1 'Outlook add-in: LoadBehavior 3'
	Assert-Equal (@($script:calls | Where-Object { $_ -like 'Set-ItemProperty HKCU:*DoNotDisableAddinList TeamsAddin.FastConnect=1' }).Count) 1 'Outlook add-in: not disabled again'
	Assert-Equal "$($script:calls[-2])|$($script:calls[-1])" 'Stop-Process OUTLOOK|Start-Process C:\Office\OUTLOOK.EXE' 'Outlook add-in: Outlook restarted'

	$run = Invoke-TestScript 'SelfX_Poste_WSReset.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls[0])" "0|Start-Process $(Join-Path $env:SystemRoot 'System32\wsreset.exe')" 'Store reset: wsreset started'

	#------------------------------------------------------------------------------------------------
	# System actions and repairs (through the service as SYSTEM)
	#------------------------------------------------------------------------------------------------
	$global:SignatureVersion = '1.441.85.0'
	$global:UpdateFails = $false
	$run = Invoke-TestScript 'SelfX_Defender_UpdateSignature.ps1'
	Assert-Equal ($run.ExitCode -eq 0 -and "$($run.Output[0])" -like 'Defender signatures: 1.441.85.0 -> 1.441.99.0 (last update *)') $true 'Defender: signatures updated'
	$global:UpdateFails = $true
	Assert-Equal (Invoke-TestScript 'SelfX_Defender_UpdateSignature.ps1').ExitCode 1 'Defender: failure is exit 1'
	$global:UpdateFails = $false
	$global:UpdateReturn = 3
	$run = Invoke-TestScript 'SelfX_Defender_UpdateSignature.ps1'
	Assert-Equal ($run.ExitCode -eq 1 -and "$($run.Output[0])" -like '*Defender signature update returned 3*') $true 'Defender: a return value other than 0 is an error (exit 1)'
	$global:UpdateReturn = $null
	$global:SignatureVersion = '1.441.85.0'
	$run = Invoke-TestScript 'SelfX_Defender_UpdateSignature.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Defender-Update' 'Defender: the update runs through CIM (MSFT_MpSignature.Update) only'

	$run = Invoke-TestScript 'SelfX_Device_SyncTime.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls.Count)|$($script:calls[0] -like '*\System32\w32tm.exe /resync /force')" '0|1|True' "Time sync: w32tm called once with fixed arguments ($($run.Error))"
	$run = Invoke-TestScript 'SelfX_Intune_RestartService.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Restart-Service IntuneManagementExtension' 'IME restart'

	$run = Invoke-TestScript 'SelfX_OneDrive_CHKDSK.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" "0|Repair $("$env:SystemDrive".TrimEnd(':', '\')) offline=True" 'Disk check: offline scan and fix scheduled through CIM (language independent)'
	$global:RepairReturn = 5
	$run = Invoke-TestScript 'SelfX_OneDrive_CHKDSK.ps1'
	Assert-Equal ($run.ExitCode -eq 1 -and "$($run.Output)" -like '*Repair returned 5*') $true 'Disk check: a return value other than 0 is an error (exit 1)'
	$global:RepairReturn = $null

	# Network adapters: host with cable, Wi-Fi, hidden cellular profiles and a Hyper-V switch; then a virtual machine.
	function New-FakeCimAdapter($Name, $Description, $Index, $Operational, $Admin, [bool]$Disconnected, $Ndis, $NdisMedium, [bool]$Hardware, [bool]$Virtual, [bool]$Hidden = $false) {
		[pscustomobject]@{ Name = $Name; InterfaceDescription = $Description; InterfaceIndex = $Index; InterfaceOperationalStatus = $Operational; InterfaceAdminStatus = $Admin
			OperationalStatusDownMediaDisconnected = $Disconnected; NdisPhysicalMedium = $Ndis; NdisMedium = $NdisMedium; HardwareInterface = $Hardware; ConnectorPresent = $Hardware; Virtual = $Virtual; Hidden = $Hidden }
	}
	function New-FakeCimRoute($Prefix, $Index, $NextHop) { [pscustomobject]@{ DestinationPrefix = $Prefix; InterfaceIndex = $Index; NextHop = $NextHop } }
	$global:FakeCimFails = $false
	$global:FakeAdapters = @(
		(New-FakeCimAdapter 'Ethernet' 'Realtek USB GbE' 11 1 1 $false 14 0 $true $false)
		(New-FakeCimAdapter 'Wi-Fi' 'Intel Wi-Fi 6E' 5 2 1 $true 9 16 $true $false)
		(New-FakeCimAdapter 'Cellular 7' 'Fibocom L860' 41 2 1 $false 8 0 $true $false -Hidden $true)
		(New-FakeCimAdapter 'vEthernet (Default Switch)' 'Hyper-V Virtual Ethernet Adapter' 60 1 1 $false 0 0 $false $true)
		(New-FakeCimAdapter 'Ethernet 2' 'Disabled NIC' 12 2 2 $false 14 0 $true $false))
	$global:FakeRoutes = @((New-FakeCimRoute '0.0.0.0/0' 11 '192.168.10.1'), (New-FakeCimRoute '192.168.10.0/24' 5 '0.0.0.0'))
	$run = Invoke-TestScript 'SelfX_Device_AirePlaneMode.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Restart-NetAdapter Ethernet;Restart-NetAdapter Wi-Fi' 'Network restart: physical present adapters only (hidden and disabled adapters are kept)'
	$global:FakeAdapters = @((New-FakeCimAdapter 'Ethernet' 'Microsoft Hyper-V Network Adapter' 4 1 1 $false 0 0 $false $false))
	$global:FakeRoutes = @((New-FakeCimRoute '0.0.0.0/0' 4 '192.168.250.1'))
	$run = Invoke-TestScript 'SelfX_Device_AirePlaneMode.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Restart-NetAdapter Ethernet' 'Network restart: virtual machine adapter with default route'
	$global:FakeRoutes = @()
	Assert-Equal (Invoke-TestScript 'SelfX_Device_AirePlaneMode.ps1').ExitCode 1 'Network restart: no adapter is exit 1'
	$global:FakeCimFails = $true
	$run = Invoke-TestScript 'SelfX_Device_AirePlaneMode.ps1'
	Assert-Equal ($run.ExitCode -ne 0 -and @($script:calls).Count -eq 0) $true 'Network restart: unreadable adapters are an error and nothing is restarted'
	$global:FakeCimFails = $false

	# Restart: only the function is called, with a non-existent shutdown.exe; the script body never runs.
	. (Join-Path $scripts 'SelfX_Device_Restart.ps1')
	$restartText = [IO.File]::ReadAllText((Join-Path $scripts 'SelfX_Device_Restart.ps1'))
	Assert-Equal ($restartText.Contains('& $ShutdownExe /r /t $DelaySeconds /d p:4:1')) $true 'Restart: shutdown /r with delay and planned reason'
	Assert-Equal ($restartText -match '/l\b|/s\b|/p\b|/h\b|logoff|LockWorkStation') $false 'Restart: no sign-out, shutdown or hibernate'
	$dummy = Join-Path $sandbox 'does-not-exist\shutdown.exe'
	Assert-Equal (Test-Path -LiteralPath $dummy) $false 'Restart: dummy shutdown.exe does not exist'
	$failed = $false
	try { [void](Invoke-SelfXRestart -ShutdownExe $dummy -DelaySeconds 30) } catch { $failed = $_.Exception.Message -like 'shutdown.exe not found*' }
	Assert-Equal $failed $true 'Restart: missing shutdown.exe is reported'

	# Updates: only the Windows Update orchestrator (no Windows Update Agent API).
	. (Join-Path $scripts 'SelfX_Updates_Install.ps1')
	function Write-SelfXLog { param($Message, $Level) $script:updateLog.Add("$Level|$Message") }
	$script:updateLog = New-Object System.Collections.Generic.List[string]
	$updatesText = [IO.File]::ReadAllText((Join-Path $scripts 'SelfX_Updates_Install.ps1'))
	$updatesCode = $updatesText.Substring($updatesText.IndexOf('#>') + 2)
	Assert-Equal ($updatesCode -match '(?i)UsoClient|shutdown|Restart-Computer|RebootRequired\\') $false 'Updates: no UsoClient (fails on Windows 11 24H2), never restarts, no registry restart markers'
	Assert-Equal ($updatesCode -match '(?i)Microsoft\.Update\.(Session|UpdateColl)|CreateUpdateInstaller|PSEdition') $false 'Updates: no Windows Update Agent API and no PowerShell 5.1 branch any more'

	# Orchestrator (Windows 11 25H2+): simulated WindowsUpdateManager. Each poll step plays the next state.
	function New-FakeOrchestratorUpdate([string]$Id, [string]$Title, [object[]]$Steps, [bool]$Feature = $false) {
		$u = [pscustomobject]@{ UpdateId = $Id; Title = $Title; IsEulaAccepted = $false; IsFeatureUpdate = $Feature; Steps = $Steps; Step = 0
			CurrentAction = ''; ActionProgress = $null; AttentionRequiredInfo = $null }
		$u | Add-Member ScriptMethod AcceptEula { $this.IsEulaAccepted = $true }
		$u
	}
	function New-FakeManager([object[]]$Updates, [int]$ScanPolls = 1, [switch]$ThrowOnScan) {
		$m = [pscustomobject]@{ Updates = $Updates; ScanPolls = $ScanPolls; Polls = 0; Scans = (New-Object System.Collections.Generic.List[string]); ThrowOnScan = [bool]$ThrowOnScan }
		$m | Add-Member ScriptMethod StartScan { param($user) if ($this.ThrowOnScan) { throw 'Access denied' }; $this.Scans.Add("user=$user") }
		$m | Add-Member ScriptProperty IsScanning { $this.Polls -lt $this.ScanPolls }
		$m | Add-Member ScriptMethod GetApplicableUpdates {
			$this.Polls++
			foreach ($u in $this.Updates) {
				$s = $u.Steps[[Math]::Min($u.Step, $u.Steps.Count - 1)]; $u.Step++
				$u.CurrentAction = "$($s[0])"
				$u.ActionProgress = $(if ($s[0]) { [pscustomobject]@{ Action = $s[0]; Progress = $s[1] } } else { $null })
				$u.AttentionRequiredInfo = $(if ($s[2]) { [pscustomobject]@{ Reason = $s[2] } } else { $null })
			}
			@($this.Updates | Where-Object { "$($_.Steps[[Math]::Min($_.Step - 1, $_.Steps.Count - 1)][0])" -ne 'Gone' })
		}
		$m
	}
	$script:updateLog.Clear()
	$lcu = New-FakeOrchestratorUpdate 'a1' '2026-11 Security Update (KB5132061)' @(@('Download', 40, ''), @('Install', 70, ''), @('', 0, 'ReadyToReboot'))
	$drv = New-FakeOrchestratorUpdate 'b2' 'Audio driver' @(@('Download', 10, ''), @('Install', 90, ''), @('Gone', 0, ''))
	$manager = New-FakeManager @($lcu, $drv)
	$result = Install-SelfXOrchestratorUpdates -Manager $manager -PollSeconds 1 -IdleSeconds 3 -ScanStartSeconds 2 -TimeoutSeconds 100
	Assert-Equal ($manager.Scans -join ';') 'user=True' 'Updates: orchestrator scan as "Check for updates" in Settings (user initiated)'
	Assert-Equal "$($result.Ok)|$($result.TimedOut)|$($result.Text)" 'True|False|Windows Update orchestrator: all updates processed; restart required to complete: 2026-11 Security Update (KB5132061)' 'Updates: orchestrator installs, restart reported'
	Assert-Equal "$($lcu.IsEulaAccepted)/$($drv.IsEulaAccepted)" 'True/True' 'Updates: EULAs accepted for the orchestrator'
	Assert-Equal (@($script:updateLog | Where-Object { $_ -like '*KB5132061): action Install, progress Install 70' }).Count) 1 'Updates: orchestrator progress logged per update'

	$seeker = New-FakeOrchestratorUpdate 'c3' 'Optional driver' @(,@('', 0, 'SeekerUpdate'))
	$upgrade = New-FakeOrchestratorUpdate 'd4' 'Windows 11, version 26H2' @(,@('', 0, 'SeekerUpdate')) -Feature $true
	$result = Install-SelfXOrchestratorUpdates -Manager (New-FakeManager @($seeker, $upgrade)) -PollSeconds 1 -IdleSeconds 3 -ScanStartSeconds 2 -TimeoutSeconds 100
	Assert-Equal "$($result.Ok)|$($result.Remaining -join ',')" 'False|Optional driver' 'Updates: an update the orchestrator does not install remains for the WUA API; feature update left to the policy'
	Assert-Equal ($result.Text -like '*1 update(s) not installed: Optional driver (SeekerUpdate)*feature update(s) left to the update policy: Windows 11, version 26H2') $true 'Updates: waiting reason and feature update reported'

	$busy = New-FakeOrchestratorUpdate 'e5' 'Cumulative update' @(,@('Install', 50, ''))
	$result = Install-SelfXOrchestratorUpdates -Manager (New-FakeManager @($busy)) -PollSeconds 1 -IdleSeconds 3 -ScanStartSeconds 2 -TimeoutSeconds 6
	Assert-Equal "$($result.Ok)|$($result.TimedOut)" 'False|True' 'Updates: orchestrator still installing after the time limit (no parallel WUA installation)'
	Assert-Equal ($updatesCode.Contains('if (-not $orchestrator.Ok) { $failed = $true }') -and $updatesCode.Contains('$manager.StartScan($false)')) $true 'Updates: orchestrator result decides the exit code; Settings refreshed afterwards'
	Assert-Equal ($updatesCode.Contains('if (-not $manager) {') -and $updatesCode.Contains('$failed = $true')) $true 'Updates: missing orchestrator API is an error, not a silent skip'
	Assert-Equal ((Get-SelfXUpdateManager) -eq $null -or (Get-SelfXUpdateManager).GetType().FullName -eq 'Windows.Management.Update.WindowsUpdateManager') $true 'Updates: orchestrator API is created or missing, never an exception'

	# App retry: reset of the cached error and the retry schedule of failed apps (registry mocked).
	. "$sources\HealthStatus.ps1"
	. (Join-Path $scripts 'SelfX_Apps_RetryInstall.ps1')
	$userKey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\57f4b2f0-0ef4-4927-ab53-d91d54f4a5fd'
	$appId = '046f98d8-667e-4463-b776-d69d48a632d3'
	$script:removed = New-Object System.Collections.Generic.List[string]
	function Test-Path { param([string]$LiteralPath, $PathType) $true }
	function Remove-Item { param([string]$LiteralPath, [switch]$Recurse, [switch]$Force, $ErrorAction) $script:removed.Add($LiteralPath) }
	function Get-ChildItem { param([string]$LiteralPath, $ErrorAction) @([pscustomobject]@{ PSPath = "$LiteralPath\hash1" }, [pscustomobject]@{ PSPath = "$LiteralPath\hash2" }) }
	function Get-ItemProperty { param([string]$LiteralPath, $ErrorAction) if ($LiteralPath -like '*hash1') { [pscustomobject]@{ "$($appId)_1" = 'x' } } else { [pscustomobject]@{ 'ffffffff-0000-0000-0000-000000000000' = 'x' } } }
	$report = [pscustomobject]@{ Id = $appId; AppKey = "$userKey\$($appId)_7"; UserKey = $userKey }
	Assert-Equal (Reset-SelfXFailedApp -Report $report) 2 'App retry: app result and its retry schedule removed'
	Assert-Equal ($script:removed -join ';') "$userKey\$($appId)_7;$userKey\GRS\hash1" 'App retry: only the keys of the failed app'
	$outside = $false
	try { [void](Reset-SelfXFailedApp -Report ([pscustomobject]@{ Id = $appId; AppKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Other\$appId"; UserKey = $userKey })) } catch { $outside = $true }
	Assert-Equal $outside $true 'App retry: nothing outside the IME cache is deleted'
	Microsoft.PowerShell.Management\Remove-Item Function:\Test-Path, Function:\Remove-Item, Function:\Get-ChildItem, Function:\Get-ItemProperty

	# App status: app id from the key <app id>_<revision> (not the user id), names from the IME logs, error codes.
	function Get-ChildItem { param([string]$LiteralPath, [switch]$Recurse, $ErrorAction, [switch]$File)
		if ($LiteralPath -like 'HKLM:*') {
			@([pscustomobject]@{ PSPath = 'app1'; Name = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\57f4b2f0-0ef4-4927-ab53-d91d54f4a5fd\$($appId)_7" }
			  [pscustomobject]@{ PSPath = 'app2'; Name = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\57f4b2f0-0ef4-4927-ab53-d91d54f4a5fd\0675cabb-3d3d-4c3f-abfd-349fb022d5cc_2' }
			  [pscustomobject]@{ PSPath = 'app3'; Name = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\00000000-0000-0000-0000-000000000000\11111111-2222-3333-4444-555555555555_1' })
		} else { Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters } }
	function Get-ItemProperty { param([string]$LiteralPath, $ErrorAction)
		switch ($LiteralPath) {
			'app1' { [pscustomobject]@{ EnforcementStateMessage = '{"EnforcementState":5000,"ErrorCode":-2016345060}' } }
			'app2' { [pscustomobject]@{ EnforcementStateMessage = '{"EnforcementState":1000,"ErrorCode":0}' } }
			'app3' { [pscustomobject]@{ EnforcementStateMessage = '{"EnforcementState":3000,"ErrorCode":null}' } }
		} }
	function Test-Path { param([string]$LiteralPath, $PathType) if ($LiteralPath -like 'HKLM:*') { return $true }; Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath }
	$reports = @(Get-SelfXAppReports)
	Assert-Equal $reports[0].Id $appId 'App status: app id from <app id>_<revision>, not the user id'
	Assert-Equal $reports[0].UserKey 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\57f4b2f0-0ef4-4927-ab53-d91d54f4a5fd' 'App status: user key'
	Assert-Equal (Format-SelfXAppError -2016345060) '0x87D1041C' 'App status: error code in hex'
	$imeLogs = Join-Path $sandbox 'ImeLogs'
	New-SandboxFile (Join-Path $imeLogs 'AppWorkload.log')
	[IO.File]::WriteAllText((Join-Path $imeLogs 'AppWorkload.log'), "Get policies [{`"Id`":`"$appId`",`"Name`":`"Monitoring \`"Agent\`"`",`"Version`":7}]")
	$names = Get-SelfXImeAppNames -Ids @($appId) -LogFolder $imeLogs
	Assert-Equal $names[$appId] 'Monitoring "Agent"' 'App status: name from the IME log (JSON unescaped)'
	function Get-SelfXImeAppNames { param($Ids, $LogFolder) @{ $appId = 'Monitoring Agent'; '0675cabb-3d3d-4c3f-abfd-349fb022d5cc' = 'Vantage Service' } }
	[xml]$appConfig = '<Applications/>'
	$appHealth = Get-SelfXApplicationHealth -Configuration $appConfig.DocumentElement
	Assert-Equal $appHealth.Status 'Error' 'App status: failed app is an error'
	Assert-Equal $appHealth.Detail '1 of 2 app(s) could not be installed: Monitoring Agent (error 0x87D1041C).' 'App status: clear detail with name and error (not applicable app not counted)'
	Microsoft.PowerShell.Management\Remove-Item Function:\Get-ChildItem, Function:\Get-ItemProperty, Function:\Test-Path, Function:\Get-SelfXImeAppNames

	#------------------------------------------------------------------------------------------------
	# Secure Boot from the registry (SelfXDeviceSecurity.ps1): the SecureBoot module is not used
	function global:Confirm-SecureBootUEFI { throw 'Confirm-SecureBootUEFI is not allowed (use SelfXDeviceSecurity.ps1)' }
	. (Join-Path $sources 'SelfXDeviceSecurity.ps1')
	function Test-Path { param([string]$LiteralPath) $script:sbKey }
	function Get-ItemProperty { param([string]$LiteralPath, $ErrorAction) $script:sbValues }
	$script:sbKey = $true; $script:sbValues = [pscustomobject]@{ UEFISecureBootEnabled = 1 }
	Assert-Equal (Get-SelfXSecureBootEnabled -Path 'HKLM:\x') $true 'Secure Boot: 1 is on'
	$script:sbValues = [pscustomobject]@{ UEFISecureBootEnabled = 0 }
	Assert-Equal (Get-SelfXSecureBootEnabled -Path 'HKLM:\x') $false 'Secure Boot: 0 is off'
	foreach ($case in @(@{ Key = $false; Values = $null }, @{ Key = $true; Values = [pscustomobject]@{ PolicyVersion = 1 } })) {
		$script:sbKey = $case.Key; $script:sbValues = $case.Values
		$thrown = ''
		try { $null = Get-SelfXSecureBootEnabled -Path 'HKLM:\x' } catch { $thrown = $_.Exception.GetType().Name }
		Assert-Equal $thrown 'PlatformNotSupportedException' 'Secure Boot: missing key or value means legacy BIOS (PlatformNotSupportedException)'
	}
	Microsoft.PowerShell.Management\Remove-Item Function:\Test-Path, Function:\Get-ItemProperty

	#------------------------------------------------------------------------------------------------
	# BitLocker and TPM through CIM (SelfXDeviceSecurity.ps1): the BitLocker and TPM cmdlets are not used (values measured on a device)
	function global:Get-BitLockerVolume { throw 'Get-BitLockerVolume is not allowed (use SelfXDeviceSecurity.ps1)' }
	function global:Get-Tpm { throw 'Get-Tpm is not allowed (use SelfXDeviceSecurity.ps1)' }
	$global:FakeVolumes = @(
		[pscustomobject]@{ DriveLetter = 'C:'; VolumeType = 0; ProtectionStatus = 1; ConversionStatus = 1 },
		[pscustomobject]@{ DriveLetter = 'D:'; VolumeType = 1; ProtectionStatus = 0; ConversionStatus = 0 },
		[pscustomobject]@{ DriveLetter = 'E:'; VolumeType = 2; ProtectionStatus = 2; ConversionStatus = 2 })
	$bl = @(Get-SelfXBitLockerVolumes)
	Assert-Equal (($bl | ForEach-Object { "$($_.MountPoint)/$($_.VolumeType)/$($_.ProtectionStatus)/$($_.VolumeStatus)" }) -join ';') 'C:/OperatingSystem/On/FullyEncrypted;D:/FixedData/Off/FullyDecrypted;E:/Removable/Unknown/EncryptionInProgress' 'BitLocker: CIM values mapped like Get-BitLockerVolume'
	$global:FakeVolumes = @([pscustomobject]@{ DriveLetter = 'C:'; VolumeType = 9; ProtectionStatus = 7; ConversionStatus = $null })
	$bl = @(Get-SelfXBitLockerVolumes)
	Assert-Equal "$($bl[0].VolumeType)|$($null -eq $bl[0].ProtectionStatus)|$($null -eq $bl[0].VolumeStatus)" 'Unknown|True|True' 'BitLocker: unknown CIM values stay unknown (no guess)'
	$global:FakeCimFails = $true
	$thrown = ''
	try { $null = @(Get-SelfXBitLockerVolumes) } catch { $thrown = $_.Exception.Message }
	Assert-Equal $thrown 'Mock CIM denied' 'BitLocker: an unreadable class throws (callers show unknown)'
	$global:FakeCimFails = $false
	$global:FakeTpm = [pscustomobject]@{ IsEnabled_InitialValue = $true; IsActivated_InitialValue = $true; IsOwned_InitialValue = $true }
	Assert-Equal "$((Get-SelfXTpmStatus).TpmPresent)/$((Get-SelfXTpmStatus).TpmReady)" 'True/True' 'TPM: present and ready'
	$global:FakeTpm = [pscustomobject]@{ IsEnabled_InitialValue = $true; IsActivated_InitialValue = $false; IsOwned_InitialValue = $true }
	Assert-Equal "$((Get-SelfXTpmStatus).TpmPresent)/$((Get-SelfXTpmStatus).TpmReady)" 'True/False' 'TPM: not activated is not ready'
	$global:FakeTpm = $null
	Assert-Equal "$((Get-SelfXTpmStatus).TpmPresent)/$((Get-SelfXTpmStatus).TpmReady)" 'False/False' 'TPM: no instance means not present'

	#------------------------------------------------------------------------------------------------
	# Read-only scripts, run for real in a child process (sandbox ProgramData for their logs)
	#------------------------------------------------------------------------------------------------
	$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
	[void][IO.Directory]::CreateDirectory((Join-Path $env:ProgramData 'SelfX\Logs'))
	$output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sources 'HealthChecks\Check-Compliance.ps1') 2>&1)
	Assert-Equal ($LASTEXITCODE -in 0, 1) $true 'Check-Compliance runs (exit 0 or 1)'
	Assert-Equal ("$($output[-1])" -match '^(Not met|Local compliance criteria met):') $true 'Check-Compliance: result is the last output line'
	Assert-Equal ((Get-SandboxLog 'Check-Compliance') -match '(Not met|criteria met)') $true 'Check-Compliance: result logged'

	$output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Detection.ps1') 2>&1)
	Assert-Equal "$LASTEXITCODE|$(@($output).Count)" '1|0' 'Detection: not installed here, exit 1 without output'
	Assert-Equal ((Get-SandboxLog 'Detection') -match 'SelfX \d+\.\d+\.\d+: not detected') $true 'Detection: result logged'

	$cache = Join-Path $sandbox 'Health.json'
	$json = (& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sources 'HealthStatus.ps1') -Collect -OnlyId Disk -CacheFile $cache 2>&1) -join ''
	$parsed = ConvertFrom-Json $json
	Assert-Equal (@($parsed)[0].Id) 'Disk' 'HealthStatus -Collect: stdout is still pure JSON with logging'
	Assert-Equal ((Get-SandboxLog 'HealthStatus') -match 'Health check Disk finished') $true 'HealthStatus: run logged'

	# Logs of the scripts: user actions fall back to LOCALAPPDATA without the installed Logs\Users folder; an
	# elevated test run (for example a CI runner) logs to ProgramData\SelfX\Logs. Both are inside the sandbox.
	Assert-Equal (@(Get-ChildItem -LiteralPath $sandbox -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue).Count -ge 10) $true 'Logs of the user actions written'
} finally {
	foreach ($key in $saved.Keys) { Set-Item -Path "Env:$key" -Value $saved[$key] }
	Microsoft.PowerShell.Management\Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:unused.Count) { Write-Output "Note: not used by the catalog or Health_Config (available for administrators): $($script:unused -join ', ')" }
Write-Output "PASS: $script:assertions assertions. All commands with effects mocked; files only in a temporary sandbox."
