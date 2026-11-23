<#
.SYNOPSIS
    Install the pending Windows updates now and start the update of the Microsoft Store apps.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service" when the user clicks the remediation button of the "Updates to install" status
    row (Health_Config.xml, Remediation Id="Updates"). While it runs, the button in SelfX shows
    "Running..."; afterwards SelfX checks the whole device status again (updates, pending restart).

    1. Microsoft Store apps: starts the Store app update scan of the MDM bridge
       (MDM_EnterpriseModernAppManagement_AppManagement01.UpdateScanMethod) as SYSTEM. This also
       works when the Store app is blocked for users. The Store updates the apps in the background.
    2. Windows Update orchestrator (Windows 11 25H2 and newer, Windows.Management.Update
       .WindowsUpdateManager): StartScan(userInitiated = true) works exactly like "Check for updates"
       in Settings, so the updates are downloaded and installed by Windows itself, with the policies of
       the device, and Settings shows their progress. The script waits while updates are downloaded or
       installed (at most OrchestratorTimeoutSeconds) and logs every update with its action, progress
       and the reason why it waits (for example ReadyToReboot, SeekerUpdate, NeedMoreSpace).
    Before 2.6.3 the installation was started with "UsoClient StartDownload / StartInstall". Windows 11
    24H2 no longer accepts these commands (error 0x80070057), so only a scan ran and nothing was
    installed; a restart that was already pending was even reported as "updates installed".
    2.6.3 to 2.6.8 used only the Windows Update Agent API. Microsoft documents that the Settings page
    shows only updates of the orchestrator; updates handled through the WUA API do not appear there and
    can conflict with it. So the updates could still be listed as pending in Settings. Since 2.6.10 only the
    orchestrator is used (Windows 11 25H2 is the minimum version); the Windows Update Agent API is gone.

    Never restarts Windows and never signs out the user. When an update needs a restart, the
    "Restart pending" status row shows it; the user restarts with its button or himself.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Output: one summary line. Exit 0 = all selected updates installed (or nothing to install);
    exit 1 = search, download or installation failed for at least one update.

.NOTES
    Name    : SelfX_Updates_Install.ps1
    Package : SelfX Service
    Context : System
    Version : 2.8.14

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.5.6    2026-11-05  Wolfgang Baeck       Initial version: install pending Windows updates, Store app update scan
    2.6.0    2026-11-06  Wolfgang Baeck       Windows Update orchestrator (UsoClient); logging
    2.6.3    2026-11-06  Wolfgang Baeck       Installation through the Windows Update Agent API again: UsoClient
                                              StartDownload / StartInstall fail on Windows 11 24H2 (0x80070057) and a
                                              pending restart was reported as installed; result logged per update
    2.6.9    2026-11-19  Wolfgang Baeck       Windows 11 24H2+: installs through the Windows Update orchestrator
                                              (WindowsUpdateManager, as "Check for updates" in Settings) and waits
                                              for it; the Windows Update Agent API only installs what is left;
                                              feature updates and updates waiting for the restart are skipped
    2.6.10   2026-11-22  fubu2k               Windows 11 25H2 minimum: only the orchestrator (SelfXWinRT.dll, PowerShell 7);
                                              the Windows Update Agent API and the PowerShell 5.1 path are removed;
                                              a missing orchestrator API is an error (exit 1)
    2.8.14   2026-11-23  fubu2k               The WinRT libraries are checked against SelfX.Files.json before they are loaded
                                              (SelfXWinRT.ps1, finding N4); a difference = orchestrator API not available (exit 1)
#>

# Microsoft Store apps: update scan of the MDM bridge (asynchronous).
function Start-SelfXStoreUpdate {
	try {
		$storeClass = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction Stop
		$scan = Invoke-CimMethod -InputObject $storeClass -MethodName 'UpdateScanMethod' -ErrorAction Stop
		if ($scan.ReturnValue -in @($null, 0)) { return [pscustomobject]@{ Ok = $true; Text = 'Store apps: update started' } }
		return [pscustomobject]@{ Ok = $false; Text = "Store apps: update scan returned $($scan.ReturnValue)" }
	} catch {
		return [pscustomobject]@{ Ok = $false; Text = "Store apps: not started ($($_.Exception.Message))" }
	}
}

# Windows Update orchestrator (Windows.Management.Update.WindowsUpdateManager, Windows 11 25H2 and newer) through
# SelfXWinRT.dll in the folder WinRT of the install folder. Import-SelfXWinRT (SelfXWinRT.ps1) checks the DLLs against
# SelfX.Files.json and keeps them open while it loads them (finding N4). PowerShell 7 cannot load the Windows Runtime type
# by name. Returns $null when the API is not available or a check fails (the reason is logged; replaced in tests).
function Get-SelfXUpdateManager {
	try {
		$installFolder = Split-Path -Parent $PSScriptRoot
		. (Join-Path $installFolder 'SelfXWinRT.ps1')
		Import-SelfXWinRT -InstallFolder $installFolder
		return [SelfX.SelfXWinRT]::CreateUpdateManager('SelfX')
	} catch {
		if (Get-Command -Name Write-SelfXLog -ErrorAction SilentlyContinue) { Write-SelfXLog "WinRT library not loaded: $($_.Exception.Message)" Warning }
		return $null
	}
}

# State of one orchestrator update: current action, progress and the reason why it waits.
function Get-SelfXOrchestratorUpdateState {
	param($Update)
	$reason = ''
	try { if ($Update.AttentionRequiredInfo) { $reason = "$($Update.AttentionRequiredInfo.Reason)" } } catch { }
	if ($reason -in @('None', '0')) { $reason = '' }
	$action = "$($Update.CurrentAction)"
	$progress = ''
	try { if ($Update.ActionProgress -and "$($Update.ActionProgress.Action)") { $progress = "$($Update.ActionProgress.Action) $($Update.ActionProgress.Progress)" } } catch { }
	$parts = @()
	if ($action) { $parts += "action $action" }
	if ($progress) { $parts += "progress $progress" }
	if ($reason) { $parts += "waiting: $reason" }
	if (-not $parts.Count) { $parts += 'not started' }
	[pscustomobject]@{
		Title   = "$($Update.Title)"
		Reason  = $reason
		# Windows works on the update: an action without a blocking reason.
		Active  = [bool]($action -and -not $reason)
		Restart = [bool]($reason -eq 'ReadyToReboot' -or $action -in @('PostReboot', 'Commit'))
		Feature = [bool]$Update.IsFeatureUpdate
		Text    = $parts -join ', '
	}
}

# "Check for updates" through the orchestrator and wait until Windows has processed the updates.
# Time is counted in poll steps, so the tests run without waiting. Returns the summary and the remaining updates.
function Install-SelfXOrchestratorUpdates {
	param(
		$Manager,
		[int]$TimeoutSeconds = 5400,
		[int]$IdleSeconds = 300,
		[int]$ScanStartSeconds = 60,
		[int]$PollSeconds = 15
	)
	Write-SelfXLog 'Check for updates through the Windows Update orchestrator (as in Settings).'
	$Manager.StartScan($true)
	$elapsed = 0
	$idle = 0
	$scanSeen = $false
	$timedOut = $false
	$logged = @{}
	while ($true) {
		Start-Sleep -Seconds $PollSeconds
		$elapsed += $PollSeconds
		$scanning = [bool]$Manager.IsScanning
		if ($scanning) { $scanSeen = $true }
		$active = 0
		foreach ($update in @($Manager.GetApplicableUpdates())) {
			if (-not $update) { continue }
			if (-not $update.IsEulaAccepted) {
				try { $update.AcceptEula(); Write-SelfXLog "EULA accepted: $($update.Title)" } catch { Write-SelfXLog "EULA not accepted: $($update.Title) ($($_.Exception.Message))" Warning }
			}
			$state = Get-SelfXOrchestratorUpdateState $update
			$key = "$($update.UpdateId)|$($state.Title)"
			if ($logged[$key] -ne $state.Text) { $logged[$key] = $state.Text; Write-SelfXLog "$($state.Title): $($state.Text)" }
			if ($state.Active) { $active++ }
		}
		# The scan can start a few seconds later; until then nothing is idle.
		if (-not $scanSeen -and -not $active -and $elapsed -lt $ScanStartSeconds) { continue }
		if ($scanning -or $active) { $idle = 0 } else { $idle += $PollSeconds }
		if ($idle -ge $IdleSeconds) { break }
		if ($elapsed -ge $TimeoutSeconds) { $timedOut = $true; break }
	}

	$restart = @(); $waiting = @(); $remaining = @(); $features = @()
	foreach ($update in @($Manager.GetApplicableUpdates())) {
		if (-not $update) { continue }
		$state = Get-SelfXOrchestratorUpdateState $update
		if ($state.Restart) { $restart += $state.Title }
		elseif ($state.Feature) { $features += $state.Title }
		else {
			$remaining += $state.Title
			$waiting += $(if ($state.Reason) { "$($state.Title) ($($state.Reason))" } else { "$($state.Title) (not started)" })
		}
	}
	if ($timedOut) { $text = "Windows Update orchestrator: still working after $TimeoutSeconds seconds" }
	elseif (-not $remaining.Count) { $text = 'Windows Update orchestrator: all updates processed' }
	else { $text = "Windows Update orchestrator: $($remaining.Count) update(s) not installed: $($waiting -join '; ')" }
	if ($restart.Count) { $text += "; restart required to complete: $($restart -join ', ')" }
	if ($features.Count) { $text += "; feature update(s) left to the update policy: $($features -join ', ')" }
	[pscustomobject]@{ Ok = (-not $timedOut -and -not $remaining.Count); Text = $text; TimedOut = $timedOut; Remaining = $remaining; Restart = $restart }
}

# Dot-sourcing (tests) only defines the functions; the service runs the script with -File.
if ($MyInvocation.InvocationName -ne '.') {
	# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
	$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
	if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
	else { function Write-SelfXLog { param($Message, $Level) } }

	$summary = New-Object System.Collections.Generic.List[string]
	$failed = $false
	$store = Start-SelfXStoreUpdate
	$summary.Add($store.Text)
	Write-SelfXLog $store.Text $(if ($store.Ok) { 'Info' } else { 'Warning' })

	# Windows 11 25H2+: Windows installs the updates itself (visible in Settings), with the policies of the device.
	# There is no second path: the Windows Update Agent API is not used any more (its updates do not appear in Settings
	# and can conflict with the orchestrator).
	$manager = Get-SelfXUpdateManager
	if (-not $manager) {
		$text = 'Windows Update orchestrator API not available (WinRT libraries missing, changed or not loadable; see the SelfX log). Reinstall SelfX Service.'
		$summary.Add($text)
		Write-SelfXLog $text Error
		$failed = $true
	} else {
		try {
			$orchestrator = Install-SelfXOrchestratorUpdates -Manager $manager
			$summary.Add($orchestrator.Text)
			Write-SelfXLog $orchestrator.Text $(if ($orchestrator.Ok) { 'Info' } else { 'Warning' })
			if (-not $orchestrator.Ok) { $failed = $true }
		} catch {
			$summary.Add("Windows Update orchestrator failed: $($_.Exception.Message)")
			Write-SelfXLog "Windows Update orchestrator failed: $($_.Exception.Message)" Error
			$failed = $true
		}
		# Settings shows the state of the orchestrator: a background scan refreshes it.
		try { $manager.StartScan($false) } catch { }
	}
	Write-Output ($summary -join '. ')
	# The Store scan is optional (blocked Store, no MDM bridge): only Windows Update decides the result.
	if ($failed) { exit 1 }
	exit 0
}
