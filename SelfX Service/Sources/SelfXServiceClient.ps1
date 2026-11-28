<#
.SYNOPSIS
    Provide GUI helpers for requests to the local SelfX Windows service.

.DESCRIPTION
    Loaded by the SelfX GUI and the tray icon in the signed-in user session; defining these
    functions alone performs no action. Uses the local named pipe "SelfX.Service" for PING,
    RUN, HEALTH and STATUS requests. STATUS returns the status cache of the background checks
    without running anything.
    RUN asks the service to launch a catalog-approved System script as LOCAL SYSTEM; its
    side effects depend on the selected script. The client itself does not elevate or edit
    files. A connection timeout limits connection attempts, not the synchronous response
    read; execution timeouts are enforced by the service. Maps DONE 0 to Success and other
    DONE codes to Failed, preserving the child exit code; Busy, Timeout, Unavailable and
    Error results have no child exit code. Test-SelfXService returns a Boolean.

.NOTES
    Name    : SelfXServiceClient.ps1
    Package : SelfX Service
    Context : GUI helper
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.6.10   2026-11-22  fubu2k               Security: before a request is sent, the client checks that the process behind
                                              the pipe is the running SelfXService (process ID from the service control
                                              manager); a process of a user that created the pipe name while the service
                                              was stopped is refused
    3.1.0    2026-11-27  fubu2k               Health results may carry UserRemediation (first part of a repair in the context of the user);
                                              checked with the same name rule and only together with a Remediation
    3.1.0    2026-11-27  fubu2k               Answer ERROR TerminalServer (action refused in Environment_Mode TerminalServer) = status TerminalServer
    3.1.0    2026-11-28  fubu2k               Answer UNAVAILABLE TerminalServer to STATUS (state Unavailable, no rows) and HEALTH (clear error)
#>

$Script:SelfXDefaultPipeName = 'SelfX.Service'
$Script:SelfXDefaultServiceName = 'SelfXService'

function Get-SelfXPipeServerState {
	# 1 = the pipe is served by the running service, 0 = it is not, -1 = cannot be determined.
	# The process ID of the pipe server (GetNamedPipeServerProcessId) is compared with the process ID that the service
	# control manager reports for the service; a user process has no access to either value to fake it. Authenticated
	# users may query the status of the service (default service ACL), so no process has to be opened.
	param(
		[Parameter(Mandatory = $true)][System.IO.Pipes.NamedPipeClientStream]$Pipe,
		[string]$ServiceName = $Script:SelfXDefaultServiceName
	)
	if (-not ('SelfXClient.PipeServerCheck' -as [type])) {
		Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace SelfXClient
{
    public static class PipeServerCheck
    {
        [StructLayout(LayoutKind.Sequential)]
        struct SERVICE_STATUS_PROCESS
        {
            public uint dwServiceType, dwCurrentState, dwControlsAccepted, dwWin32ExitCode, dwServiceSpecificExitCode, dwCheckPoint, dwWaitHint, dwProcessId, dwServiceFlags;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetNamedPipeServerProcessId(IntPtr pipe, out uint processId);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr OpenSCManager(string machine, string database, uint access);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr OpenService(IntPtr manager, string name, uint access);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool QueryServiceStatusEx(IntPtr service, int infoLevel, out SERVICE_STATUS_PROCESS status, uint size, out uint needed);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool CloseServiceHandle(IntPtr handle);

        public static int Check(IntPtr pipe, string serviceName)
        {
            uint serverPid;
            if (!GetNamedPipeServerProcessId(pipe, out serverPid)) return -1;
            IntPtr manager = OpenSCManager(null, null, 0x0001);       // SC_MANAGER_CONNECT
            if (manager == IntPtr.Zero) return -1;
            try
            {
                IntPtr service = OpenService(manager, serviceName, 0x0004);   // SERVICE_QUERY_STATUS
                if (service == IntPtr.Zero) return -1;
                try
                {
                    SERVICE_STATUS_PROCESS status;
                    uint needed;
                    if (!QueryServiceStatusEx(service, 0, out status, (uint)Marshal.SizeOf(typeof(SERVICE_STATUS_PROCESS)), out needed)) return -1;
                    return (status.dwProcessId != 0 && status.dwProcessId == serverPid) ? 1 : 0;
                }
                finally { CloseServiceHandle(service); }
            }
            finally { CloseServiceHandle(manager); }
        }
    }
}
'@
	}
	return [SelfXClient.PipeServerCheck]::Check($Pipe.SafePipeHandle.DangerousGetHandle(), $ServiceName)
}

function Test-SelfXPipeServer {
	# Throws when the pipe is definitely not served by the SelfX service. An error while checking (for example a
	# restricted language mode that blocks Add-Type) does not stop the request: the check must not break the tool.
	param([Parameter(Mandatory = $true)]$Pipe)
	$state = -1
	try { $state = [int](Get-SelfXPipeServerState -Pipe $Pipe) } catch { $state = -1 }
	if ($state -eq 0) { throw 'The pipe is not served by the running SelfX service.' }
}

function Get-SelfXPowerShellPath {
	# PowerShell 7 at its fixed machine-wide location (writable only by administrators). No PATH search:
	# a user cannot put another pwsh.exe in front of it.
	$path = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'PowerShell 7 is not installed (expected: %ProgramFiles%\PowerShell\7\pwsh.exe).' }
	return $path
}

function Start-SelfXHiddenPowerShell {
	# Starts a PowerShell script in the user context without a console window. CREATE_NO_WINDOW
	# (CreateNoWindow) creates no console at all, so nothing flashes and Windows Terminal (default
	# terminal on Windows 11) is not opened; -WindowStyle Hidden alone shows the console briefly.
	# -PassThru returns the process (the caller watches HasExited / ExitCode and disposes it).
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[string]$Arguments = '',
		[string]$WorkingDirectory = $env:SystemRoot,
		[switch]$PassThru
	)
	$start = New-Object System.Diagnostics.ProcessStartInfo
	$start.FileName = Get-SelfXPowerShellPath
	$start.Arguments = ("-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Path`" $Arguments").TrimEnd()
	$start.WorkingDirectory = $WorkingDirectory
	$start.UseShellExecute = $false
	$start.CreateNoWindow = $true
	$start.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
	$process = [System.Diagnostics.Process]::Start($start)
	if ($PassThru) { return $process }
	if ($process) { $process.Dispose() }
}

function Invoke-SelfXServiceRequest {
	param(
		[Parameter(Mandatory = $true)][string]$Request,
		[string]$PipeName = $Script:SelfXDefaultPipeName,
		[int]$ConnectTimeoutMs = 3000
	)
	# Identification lets the service identify the caller without granting impersonation rights.
	$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName, [System.IO.Pipes.PipeDirection]::InOut,
		[System.IO.Pipes.PipeOptions]::None, [System.Security.Principal.TokenImpersonationLevel]::Identification)
	try {
		$pipe.Connect($ConnectTimeoutMs)
		# Nothing is sent before the server is known: only the real service may answer on the default pipe.
		if ($PipeName -eq $Script:SelfXDefaultPipeName) { Test-SelfXPipeServer -Pipe $pipe }
		# A BOM-free UTF-8 line matches the service protocol; flush before waiting for a reply.
		$encoding = New-Object System.Text.UTF8Encoding($false)
		$writer = New-Object System.IO.StreamWriter($pipe, $encoding, 1024, $true)
		$writer.AutoFlush = $true
		$reader = New-Object System.IO.StreamReader($pipe, $encoding, $false, 1024, $true)
		$writer.WriteLine($Request)
		# ConnectTimeoutMs does not limit this blocking read; RUN is bounded by the service.
		return $reader.ReadLine()
	}
	finally {
		$pipe.Dispose()
	}
}

function Test-SelfXService {
	param([string]$PipeName = $Script:SelfXDefaultPipeName)
	try {
		return ((Invoke-SelfXServiceRequest -Request 'PING' -PipeName $PipeName -ConnectTimeoutMs 1000) -like 'PONG*')
	}
	catch {
		return $false
	}
}

function Invoke-SelfXSystemAction {
	param(
		[Parameter(Mandatory = $true)][string]$Script,
		[string]$PipeName = $Script:SelfXDefaultPipeName
	)
	try {
		$response = Invoke-SelfXServiceRequest -Request "RUN $Script" -PipeName $PipeName
	}

	catch {
		return [pscustomobject]@{ Status = 'Unavailable'; ExitCode = $null; Message = $_.Exception.Message }
	}

	# Only DONE carries a process exit code; transport and scheduling failures do not.
	if ($response -match '^DONE (-?\d+)$') {
		$exitCode = [int]$Matches[1]
		$status = if ($exitCode -eq 0) { 'Success' } else { 'Failed' }
		return [pscustomobject]@{ Status = $status; ExitCode = $exitCode; Message = $response }
	}
	switch -Regex ($response) {
		'^BUSY'    { return [pscustomobject]@{ Status = 'Busy'; ExitCode = $null; Message = $response } }
		'^ERROR OtherSessions$' { return [pscustomobject]@{ Status = 'OtherSessions'; ExitCode = $null; Message = $response } }
		'^ERROR TerminalServer$' { return [pscustomobject]@{ Status = 'TerminalServer'; ExitCode = $null; Message = $response } }
		'^TIMEOUT' { return [pscustomobject]@{ Status = 'Timeout'; ExitCode = $null; Message = $response } }
		default    { return [pscustomobject]@{ Status = 'Error'; ExitCode = $null; Message = "$response" } }
	}
}

function Get-SelfXServiceHealthReport {
    # HEALTH accepts only an optional whitelisted check Id and a base64 result name;
    # all probes and scripts come from the protected installation.
    param(
        [ValidateSet('', 'IME', 'Defender', 'Compliance', 'Applications', 'Disk', 'BitLocker', 'PendingReboot', 'Updates', 'Service', 'Custom')]
        [string]$Id = '',
        [ValidateLength(0, 200)][string]$Name = ''
    )
    $request = 'HEALTH'
    if ($Id) {
        $request += " $Id"
        if ($Name) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Name)
            if ($bytes.Length -gt 297) { throw 'Health check name is too long.' }
            $request += ' ' + [Convert]::ToBase64String($bytes)
        }
    }
    $response = Invoke-SelfXServiceRequest -Request $request
    # Environment_Mode TerminalServer: the service gives no device status to this caller (TerminalServer_Health).
    if ("$response" -ceq 'UNAVAILABLE TerminalServer') { throw 'The device status is not available on this terminal server.' }
    # -match (not -notmatch) fills $Matches with the base64 group used below.
    if (-not ($response -match '^HEALTH ([A-Za-z0-9+/=]+)$')) { throw "Health request failed: $response" }
    if ($response.Length -gt 30000) { throw 'Health response exceeds size limit.' }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
    return (ConvertFrom-SelfXHealthJson -Json $json)
}

function ConvertFrom-SelfXHealthJson {
    # Validates the health items of the service: known ids and states, bounded count and safe remediation names.
    param([Parameter(Mandatory = $true)][string]$Json)
    # Windows PowerShell 5.1 returns a JSON array as one object; assigning it first unrolls the items.
    $parsed = ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    $items = @($parsed)
    if (-not $items.Count -or $items.Count -gt 128) { throw 'Invalid health result count.' }
    foreach ($item in $items) {
        if ($item.Status -notin @('OK','Pending','Error','Unknown') -or
            $item.Id -notin @('IME','Defender','Compliance','Applications','Disk','BitLocker','PendingReboot','Updates','Service','Custom','Collection') -or
            $null -eq $item.Detail) { throw 'Invalid health result.' }
        if ($item.Remediation -and ("$($item.Remediation)" -notmatch '^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,90}\.ps1$' -or
            "$($item.Remediation)".Contains('..'))) { throw 'Invalid health remediation filename.' }
        if ($item.UserRemediation -and ("$($item.UserRemediation)" -notmatch '^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,90}\.ps1$' -or
            "$($item.UserRemediation)".Contains('..') -or -not $item.Remediation)) { throw 'Invalid health remediation filename.' }
    }
    return $items
}

function Get-SelfXServiceStatusCache {
    # Reads the status cache of the service (STATUS): no check is run, so the answer is immediate.
    # Returns CollectedAt (UTC; the GUI shows it in the time zone of the user, or $null when no check
    # has finished yet), IntervalMinutes,
    # State (Active, Battery or Disabled) and the validated Results.
    param([string]$PipeName = $Script:SelfXDefaultPipeName, [int]$ConnectTimeoutMs = 2000)
    $response = Invoke-SelfXServiceRequest -Request 'STATUS' -PipeName $PipeName -ConnectTimeoutMs $ConnectTimeoutMs
    # Environment_Mode TerminalServer: the service gives no device status to this caller (TerminalServer_Health).
    if ("$response" -ceq 'UNAVAILABLE TerminalServer') { return [pscustomobject]@{ CollectedAt = $null; IntervalMinutes = 0; State = 'Unavailable'; Results = @() } }
    # -match (not -notmatch) fills $Matches with the groups used below.
    if ("$response".Length -gt 100000 -or
        -not ("$response" -match '^STATUS (NONE|\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) (\d{1,4}) (Active|Battery|Disabled) ([A-Za-z0-9+/=]+|-)$')) {
        throw "Status request failed: $response"
    }
    # Groups: 1 = time (UTC) or NONE, 2 = interval, 3 = background state, 4 = base64 JSON or "-".
    $time = $Matches[1]; $interval = [int]$Matches[2]; $state = $Matches[3]; $data = $Matches[4]
    $collected = $null
    $results = @()
    if ($time -ne 'NONE' -and $data -ne '-') {
        $collected = [datetime]::ParseExact($time, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal')
        $results = @(ConvertFrom-SelfXHealthJson -Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($data))))
    }
    return [pscustomobject]@{ CollectedAt = $collected; IntervalMinutes = $interval; State = $state; Results = $results }
}
