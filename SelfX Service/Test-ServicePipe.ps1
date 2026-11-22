<#
.SYNOPSIS
    Tests the limits of the service pipe with the real service code (findings F3, A4, A5).

.DESCRIPTION
    Compiles Service\SelfXService.cs in memory and starts only its pipe listener in this process, under a test
    pipe name of its own ("SelfX.Test.<guid>"). Nothing is installed, no service is registered, no action and no
    health check is run (the background checks start after 120 seconds; the test stops the listener before).
    Checked:
      - PING answers PONG.
      - A5: the per-user limit (8 open connections) applies before any data is read: a 9th connection of the
        same user is closed without an answer while 8 silent connections are open.
      - A4: silent connections are closed by the service after the read deadline (5 s), and PING answers again.
      - A4: a client that sends slowly cannot extend the deadline (one deadline for the whole request).
      - An oversized request without a line end is cut and rejected, not answered with PONG.
      - N3: when another process already owns the pipe name, the service does not join it (FirstPipeInstance), logs
        the problem and serves as soon as the name is free.
    Runs as a normal user, needs no administrator rights. Duration about 30 seconds. Windows PowerShell 5.1:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-ServicePipe.ps1

.NOTES
    Name    : Test-ServicePipe.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 2.6.11
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.11   2026-11-22  fubu2k               Initial version (security review findings A4 and A5).
    2.8.0    2026-11-23  fubu2k               First pipe instance check (finding N3).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-True($Condition, $Message) {
	$script:checks++
	if (-not $Condition) { $script:errors.Add($Message) }
}

# Makes the service type available: loads the program built from the real project file (same compiler settings and
# packages as the release build). Runs in PowerShell 7 and needs the .NET SDK 10.
function Add-SelfXServiceType {
	param([string]$Path)
	$project = Join-Path (Split-Path -Parent $Path) 'Projects\SelfXService\SelfXService.csproj'
	$output = Join-Path ([IO.Path]::GetTempPath()) ('SelfXServiceBuild_' + [guid]::NewGuid().ToString('N'))
	# global.json in the repository root selects the SDK.
	Push-Location (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Path)))
	try { $log = @(& dotnet build $project -c Release -o $output --nologo -v q 2>&1); $code = $LASTEXITCODE } finally { Pop-Location }
	if ($code -ne 0) { throw ("dotnet build of the service failed:`n" + (($log | Select-Object -Last 15) -join "`n")) }
	[void][Reflection.Assembly]::LoadFrom((Join-Path $output 'SelfXService.dll'))
}

$source = Join-Path $PSScriptRoot 'Service\SelfXService.cs'
Add-SelfXServiceType -Path $source

# --- PowerShell 7 must not be replaceable by normal users: the service checks the rights before every start ---
$protectionMethod = [SelfX.SelfXService].GetMethod('IsPowerShellProtected', [Reflection.BindingFlags]'NonPublic,Static')
Assert-True ($null -ne $protectionMethod) 'The service has the rights check for PowerShell 7'
$fakeFolder = Join-Path ([IO.Path]::GetTempPath()) ('SelfXPwshTest_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fakeFolder -Force | Out-Null
$fakeExe = Join-Path $fakeFolder 'pwsh.exe'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination $fakeExe
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Test-ProtectionResult([string]$Path) {
	$arguments = [object[]]@($Path, $null)
	return [bool]$protectionMethod.Invoke($null, $arguments)
}
& icacls.exe $fakeFolder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "*$($currentSid):(OI)(CI)F" | Out-Null
Assert-True (Test-ProtectionResult $fakeExe) 'Folder for administrators only: protected'
& icacls.exe $fakeFolder /grant '*S-1-5-32-545:(OI)(CI)M' | Out-Null
Assert-True (-not (Test-ProtectionResult $fakeExe)) 'Users can modify the folder: not protected (nothing is started)'
& icacls.exe $fakeFolder /remove:g '*S-1-5-32-545' | Out-Null
& icacls.exe $fakeFolder /grant '*S-1-1-0:(OI)(CI)W' | Out-Null
Assert-True (-not (Test-ProtectionResult $fakeExe)) 'Everyone can write: not protected'
& icacls.exe $fakeFolder /remove:g '*S-1-1-0' | Out-Null
& icacls.exe $fakeFolder /grant '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
Assert-True (Test-ProtectionResult $fakeExe) 'Users can read and run: protected'
Assert-True (-not (Test-ProtectionResult (Join-Path $fakeFolder 'missing.exe'))) 'Rights cannot be read: not protected (fail closed)'
Remove-Item -LiteralPath $fakeFolder -Recurse -Force -ErrorAction SilentlyContinue

$pipeName = 'SelfX.Test.' + [guid]::NewGuid().ToString('N')
$dataRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfXPipeTest_' + [guid]::NewGuid().ToString('N'))
$logDirectory = Join-Path $dataRoot 'Logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

function New-TestClient {
	# Asynchronous client handle, so that the test can wait with a timeout.
	$client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut,
		[System.IO.Pipes.PipeOptions]::Asynchronous, [System.Security.Principal.TokenImpersonationLevel]::Identification)
	$client.Connect(3000)
	return $client
}

function Send-TestBytes($Client, [string]$Text) {
	$data = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Text)
	$Client.Write($data, 0, $data.Length)
	$Client.Flush()
}

function Read-TestAnswer($Client, [int]$TimeoutMs) {
	# Returns the answer line, '' when the service closed the connection without an answer, $null on a timeout.
	$buffer = New-Object byte[] 1024
	$text = New-Object System.Text.StringBuilder
	$watch = [Diagnostics.Stopwatch]::StartNew()
	while ($true) {
		$remaining = $TimeoutMs - [int]$watch.ElapsedMilliseconds
		if ($remaining -le 0) { return $null }
		try {
			$pending = $Client.BeginRead($buffer, 0, $buffer.Length, $null, $null)
			if (-not $pending.AsyncWaitHandle.WaitOne($remaining)) { return $null }
			$count = $Client.EndRead($pending)
		}
		catch { return $text.ToString().Trim() }
		if ($count -le 0) { return $text.ToString().Trim() }
		[void]$text.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $count))
		if ($text.ToString().Contains("`n")) { return $text.ToString().Trim() }
	}
}

function Invoke-TestRequest([string]$Request, [int]$TimeoutMs = 5000) {
	$client = $null
	try {
		$client = New-TestClient
		Send-TestBytes $client ($Request + "`n")
		return Read-TestAnswer $client $TimeoutMs
	}
	catch { return '' }
	finally { if ($client) { $client.Dispose() } }
}

$service = New-Object SelfX.SelfXService($pipeName, $logDirectory)
$silent = New-Object System.Collections.Generic.List[object]
try {
	# 0. N3: another process already owns the pipe name. The service must not join it (FirstPipeInstance): it logs the
	#    problem, keeps retrying, and serves as soon as the name is free.
	$squatter = New-Object System.IO.Pipes.NamedPipeServerStream($pipeName, [IO.Pipes.PipeDirection]::InOut, 254, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::Asynchronous)
	try {
		Write-Output 'trace: squatter created'
		$service.StartListening()
		Write-Output 'trace: service started'
		Start-Sleep -Milliseconds 2500
		$logPath = Join-Path $logDirectory 'SelfXService.log'
		$logText = if (Test-Path -LiteralPath $logPath) { [IO.File]::ReadAllText($logPath) } else { '' }
		Assert-True ($logText -match 'already in use by another process') 'N3: the service logs that the pipe name is already in use'
	}
	finally { $squatter.Dispose() }
	Write-Output 'trace: squatter disposed'
	Start-Sleep -Milliseconds 2500
	Assert-True ((Invoke-TestRequest 'PING') -like 'PONG *') 'N3: the service answers as soon as the pipe name is free'
	Write-Output 'trace: ping done'
	$logText = [IO.File]::ReadAllText($logPath)
	Assert-True ($logText -match 'is free now') 'N3: the service logs that the pipe name is free'

	# 1. Basic answer.
	Assert-True ((Invoke-TestRequest 'PING') -like 'PONG *') 'PING answers PONG'

	# 2. A5: 8 silent connections of this user, the 9th is refused before anything is read.
	for ($i = 0; $i -lt 8; $i++) { $silent.Add((New-TestClient)) }
	Start-Sleep -Milliseconds 300
	$refused = Invoke-TestRequest 'PING' 2000
	Assert-True ($refused -notlike 'PONG*') "A 9th connection of the same user is refused while 8 are open (answer: '$refused')"

	# 3. A4: the service closes the silent connections after the read deadline (5 s plus grace).
	$closed = 0
	foreach ($client in $silent) {
		if ((Read-TestAnswer $client 9000) -ne $null) { $closed++ }
	}
	Assert-True ($closed -eq 8) "The service closes silent connections after the deadline ($closed of 8 closed)"
	foreach ($client in $silent) { $client.Dispose() }
	$silent.Clear()
	Start-Sleep -Milliseconds 300
	$watch = [Diagnostics.Stopwatch]::StartNew()
	$answer = Invoke-TestRequest 'PING' 2000
	Assert-True (($answer -like 'PONG *') -and $watch.ElapsedMilliseconds -lt 2000) "PING answers within 2 s after the silent connections ended (answer: '$answer')"

	# 4. A4: sending slowly does not extend the deadline (line end after 5.5 s).
	$slow = New-TestClient
	try {
		Send-TestBytes $slow 'PI'
		Start-Sleep -Milliseconds 2500
		Send-TestBytes $slow 'N'
		Start-Sleep -Milliseconds 3000
		try { Send-TestBytes $slow "G`n" } catch { }
		$slowAnswer = Read-TestAnswer $slow 4000
	}
	finally { $slow.Dispose() }
	Assert-True ($slowAnswer -notlike 'PONG*') "A request sent slowly over more than 5 s is not answered (answer: '$slowAnswer')"

	# 5. An oversized request without a line end is cut at 512 bytes and rejected.
	$big = New-TestClient
	try {
		Send-TestBytes $big ('PING' + ('A' * 2000))
		$bigAnswer = Read-TestAnswer $big 8000
	}
	finally { $big.Dispose() }
	Assert-True (($bigAnswer -ne $null) -and ($bigAnswer -notlike 'PONG*')) "An oversized request is rejected (answer: '$bigAnswer')"

	# 6. The service still works.
	Assert-True ((Invoke-TestRequest 'PING') -like 'PONG *') 'PING answers PONG at the end'
}
finally {
	foreach ($client in $silent) { try { $client.Dispose() } catch { } }
	try { $service.StopListening() } catch { }
	Remove-Item -LiteralPath $dataRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
