<#
.SYNOPSIS
    Retry the failed Intune app installations now.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service" when the user clicks the remediation button of the "Company apps" status row
    (Health_Config.xml, Remediation Id="Applications").

    The Intune Management Extension (IME) retries a failed Win32 app only after its retry
    schedule (by default after 24 hours). For every app whose last result in the local IME cache
    is an error (EnforcementState 5000-5999) the script removes this cached result and the retry
    schedule entries (GRS) of the app, then restarts the IntuneManagementExtension service. The
    IME then checks in with Intune and installs the app again within a few minutes (progress in
    the Company Portal under Downloads and updates). Without failed apps only the service is
    restarted, which also starts a new app check-in.
    Retry of one app (pipe request APPRETRY): the service reads the IME cache itself, accepts only an app that
    it lists as not installed and passes its ID in SELFX_APP_ID (never a parameter, never from the client).
    The script then reads the cache again and changes only the entries of this app, and only while the
    status row lists it as failed or as stalled in the download (Get-SelfXImeAppStates in HealthStatus.ps1,
    same rules and StalledMinutes). Otherwise nothing is changed and the IME is not restarted (exit 4).
    Only the IME cache under HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps is
    changed; no app is uninstalled and Windows is not restarted. When the installation fails
    again, the error is a problem of the app or its assignment: the support team sees it in Intune.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Exit 0 = IME restarted (retry started); exit 1 = error; exit 4 = the app of SELFX_APP_ID needs no retry
    any more (nothing changed).

.NOTES
    Name    : SelfX_Apps_RetryInstall.ps1
    Package : SelfX Service
    Context : System
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.0    2026-11-06  Wolfgang Baeck       Initial version: retry failed Win32 app installations (Applications row)
    2.8.22   2026-11-24  fubu2k               Security: the registry keys must match the exact IME Win32Apps form (anchored, app key below the user key)
    3.1.0    2026-11-28  fubu2k               Retry of one app: SELFX_APP_ID (set by the service from its own reading of the IME cache) limits
                                              the reset to the entries of this app while it failed or its download stalled; otherwise exit 4
                                              without a change. No parameter
#>

# Removes the cached result and the retry schedule (GRS) of one failed app. Returns the number of removed keys.
function Reset-SelfXFailedApp {
	param([Parameter(Mandatory = $true)]$Report)
	$id = "$($Report.Id)"
	if ($id -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { throw "Invalid app id '$id'." }
	# Never delete anything outside the IME Win32Apps cache. Both keys must have exactly the form that HealthStatus.ps1 builds
	# (anchored at the start and the end, no other hive, no deeper or additional path parts):
	#   user key: Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\<user GUID or SID>
	#   app key : <user key>\<app id>[_<n>]
	$cache = '^Registry::HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\IntuneManagementExtension\\Win32Apps\\'
	$userKey = "$($Report.UserKey)"
	$appKey = "$($Report.AppKey)"
	if ($userKey -notmatch ($cache + '[0-9A-Za-z-]+$')) { throw "Unexpected registry path '$userKey'." }
	if ($appKey -notmatch ('^' + [regex]::Escape($userKey) + '\\' + [regex]::Escape($id) + '(_\d+)?$')) { throw "Registry path '$appKey' does not belong to app $id." }
	$removed = 0
	if (Test-Path -LiteralPath $Report.AppKey) { Remove-Item -LiteralPath $Report.AppKey -Recurse -Force -ErrorAction Stop; $removed++ }
	$grs = Join-Path $Report.UserKey 'GRS'
	if (Test-Path -LiteralPath $grs) {
		foreach ($entry in @(Get-ChildItem -LiteralPath $grs -ErrorAction Stop)) {
			$names = @((Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue).PSObject.Properties | ForEach-Object { $_.Name })
			if ($names | Where-Object { $_ -like "*$id*" }) { Remove-Item -LiteralPath $entry.PSPath -Recurse -Force -ErrorAction Stop; $removed++ }
		}
	}
	return $removed
}

# The entries of the IME cache that a retry resets.
#   Without AppId (all failed apps; also "Fix all problems"): every entry with EnforcementState 5000-5999.
#   With AppId (retry of one app): the entries of this app that are not installed (1000) and not "not applicable" (3000-3999),
#   and only while the status row lists the app as failed or as stalled in the download (States = Get-SelfXImeAppStates);
#   otherwise none.
function Select-SelfXRetryReports {
	param([object[]]$Reports, [string]$AppId = '', [object[]]$States = @())
	if (-not $AppId) {
		return @($Reports | Where-Object { $state = 0; [int]::TryParse("$($_.State)", [ref]$state) -and $state -ge 5000 -and $state -lt 6000 })
	}
	$id = $AppId.ToLowerInvariant()
	if (-not @($States | Where-Object { "$($_.Id)" -ceq $id -and "$($_.Problem)" -in @('Failed', 'Stalled') }).Count) { return @() }
	return @($Reports | Where-Object {
		$state = 0
		if (-not [int]::TryParse("$($_.State)", [ref]$state)) { $state = 0 }
		"$($_.Id)".ToLowerInvariant() -ceq $id -and $state -ne 1000 -and -not ($state -ge 3000 -and $state -lt 4000)
	})
}

# Dot-sourcing (tests) only defines the function; the service runs the script with -File.
if ($MyInvocation.InvocationName -ne '.') {
	$root = Split-Path -Parent $PSScriptRoot
	# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
	$SelfXLogScript = Join-Path $root 'SelfXLog.ps1'
	if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
	else { function Write-SelfXLog { param($Message, $Level) } }
	try {
		# The cache reader and the name lookup are the same as for the status row.
		. (Join-Path $root 'HealthStatus.ps1')
		$reports = @(Get-SelfXAppReports)
		$target = "$env:SELFX_APP_ID"
		if ($target) {
			# Retry of one app: the service hands over only an ID that it read itself from the IME cache; it is checked here once more
			# and compared with a new reading (the app may have been installed or removed since the window showed it).
			if ($target -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { throw 'The app ID from the service is not valid.' }
			$states = @(Get-SelfXImeAppStates -Configuration (Read-SelfXHealthConfig -Root $root).SelectSingleNode('/HealthConfig/Applications'))
			$failed = @(Select-SelfXRetryReports -Reports $reports -AppId $target -States $states)
			if (-not $failed.Count) {
				$text = "App $target needs no retry any more (installed, no longer in the local cache, no longer failed or its download is not stalled); nothing was changed."
				Write-SelfXLog $text Warning
				Write-Output $text
				exit 4
			}
		} else {
			$failed = @(Select-SelfXRetryReports -Reports $reports)
		}
		$names = Get-SelfXImeAppNames -Ids @($failed | ForEach-Object { $_.Id })
		$reset = @()
		foreach ($report in $failed) {
			$name = $report.Name
			if (-not $name -and $names.ContainsKey("$($report.Id)".ToLowerInvariant())) { $name = $names["$($report.Id)".ToLowerInvariant()] }
			if (-not $name) { $name = $report.Id }
			$keys = Reset-SelfXFailedApp -Report $report
			Write-SelfXLog ("Reset app {0} ({1}, state {2}, {3}): {4} registry key(s) removed." -f $name, $report.Id, $report.State, (Format-SelfXAppError $report.ErrorCode), $keys)
			if ($reset -notcontains $name) { $reset += $name }
		}
		Restart-Service -Name IntuneManagementExtension -Force -ErrorAction Stop
		$status = (Get-Service -Name IntuneManagementExtension -ErrorAction Stop).Status
		Write-SelfXLog "IntuneManagementExtension restarted: $status"
		if ($reset.Count) { $text = "Installation retried for $($reset.Count) app(s): $($reset -join ', '). The apps are installed again within a few minutes." }
		else { $text = 'No failed app installation in the local cache; the app check-in was started again.' }
		Write-SelfXLog $text
		Write-Output $text
		if ("$status" -ne 'Running') { exit 1 }
		exit 0
	} catch {
		Write-SelfXLog "Retry of the app installations failed: $($_.Exception.Message)" Error
		Write-Output "Retry of the app installations failed: $($_.Exception.Message)"
		exit 1
	}
}
