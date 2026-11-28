<#
.SYNOPSIS
    Warning text before a disruptive action: "You appear to be in a meeting or presentation."

.DESCRIPTION
    Dot-sourced by Self_X.ps1 (user context, own session). Nothing is read from or changed on the device when the file is
    loaded.

    Get-SelfXNotificationState  asks the shell for the state of the own session (SHQueryUserNotificationState, shell32.dll,
                                documented). It returns the value 1 to 7 of QUERY_USER_NOTIFICATION_STATE, or 0 when the
                                state cannot be read (the call fails or the language mode does not allow it).
    Get-SelfXDisturbKind        pure: state in, kind out. None, FullScreen (2 busy, 3 Direct3D full screen), Presentation
                                (4 presentation settings) or QuietTime (6). Not present (1, screen saver or locked), accepts
                                notifications (5), Windows Store app (7, any such app, not only a full-screen one) and every
                                other value are None.
    Get-SelfXDisturbWarning     the text to add to the confirmation, or an empty string. It is empty when the setting is off,
                                when the action is not marked Disruptive (<Disruptive>True</Disruptive> in Issues_List.xml),
                                when the state is None or when it cannot be read.

    The result is a hint only. Nothing is switched, nothing is blocked, nothing is sent to the service, no other session is
    looked at, and no program name is read or logged. The microphone and camera state of the Windows privacy settings
    (CapabilityAccessManager\ConsentStore) is not used: its value was not confirmed on Windows 11 26H2 (see CHANGELOG.en.md).

.NOTES
    Name    : SelfXDisturb.ps1
    Package : SelfX Service
    Context : User (dot-sourced by Self_X.ps1; also loaded by Test-Disturb.ps1)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-28  fubu2k               Initial version.
#>

function Get-SelfXNotificationState {
	# 1 to 7 = QUERY_USER_NOTIFICATION_STATE of the own session, 0 = cannot be read.
	try {
		if (-not ('SelfXDisturb.Native' -as [type])) {
			Add-Type -Namespace SelfXDisturb -Name Native -ErrorAction Stop -MemberDefinition '[DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int state);'
		}
		$state = 0
		$result = [SelfXDisturb.Native]::SHQueryUserNotificationState([ref]$state)
		if ($result -ne 0 -or $state -lt 1 -or $state -gt 7) { return 0 }
		return [int]$state
	}
	catch { return 0 }
}

function Get-SelfXDisturbKind {
	# Pure: state of SHQueryUserNotificationState in, kind of the disturbance out.
	param([int]$State)
	switch ($State) {
		2 { return 'FullScreen' }
		3 { return 'FullScreen' }
		4 { return 'Presentation' }
		6 { return 'QuietTime' }
		default { return 'None' }
	}
}

function Get-SelfXDisturbWarning {
	# Returns the warning text when the action is disruptive, the setting is on and the own session looks busy; otherwise ''.
	# StateProvider is a script block that returns the state (default: Get-SelfXNotificationState); tests pass a fixed value.
	param(
		[bool]$Enabled,
		[bool]$Disruptive,
		[string]$Text,
		[scriptblock]$StateProvider = { Get-SelfXNotificationState }
	)
	if (-not $Enabled -or -not $Disruptive -or [string]::IsNullOrWhiteSpace($Text)) { return '' }
	$state = 0
	try { $state = [int](& $StateProvider) } catch { return '' }
	if ((Get-SelfXDisturbKind -State $state) -eq 'None') { return '' }
	return $Text
}
