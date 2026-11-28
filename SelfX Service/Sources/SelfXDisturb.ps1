<#
.SYNOPSIS
    Warning text before a disruptive action: "You appear to be in a meeting or presentation."

.DESCRIPTION
    Dot-sourced by Self_X.ps1 (user context, own session). Nothing is read from or changed on the device when the file is
    loaded.

    The state comes from SelfXDisturb.dll (Service\SelfXDisturb.cs), a library that is built once with
    tools\Build-SelfXBinaries.ps1 and installed into the folder Disturb of the install folder. Nothing is compiled on the
    device. Before the library is loaded, its SHA256 is compared with SelfX.Code.json (same check as SelfXAudio.ps1): a
    changed, missing or additional file, a link or an invalid list means nothing is loaded and the state is 0 (no hint).

    Get-SelfXNotificationState  asks the shell for the state of the own session (SHQueryUserNotificationState, shell32.dll,
                                documented) through the checked library. It returns the value 1 to 7 of
                                QUERY_USER_NOTIFICATION_STATE, or 0 when the state cannot be read (the library is missing or
                                does not match the list, or the call fails).
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
    3.1.0    2026-11-28  fubu2k               The shell call is made by the built SelfXDisturb.dll (hash check before loading), no Add-Type.
#>

# Open file handle of the checked DLL; it stays open until the process ends (see above).
if ($null -eq $Script:SelfXDisturbHandle) { $Script:SelfXDisturbHandle = $null }

# SHA256 of Disturb/SelfXDisturb.dll from SelfX.Code.json of the install folder. Throws when the list is missing, too large, a link,
# invalid or does not list the library.
function Get-SelfXDisturbExpectedHash {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$listPath = Join-Path $InstallFolder 'SelfX.Code.json'
	$list = Get-Item -LiteralPath $listPath -Force -ErrorAction SilentlyContinue
	if (-not $list -or $list.PSIsContainer) { throw 'SelfX.Code.json is missing.' }
	if ($list.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'SelfX.Code.json is a link.' }
	if ($list.Length -gt 1048576) { throw 'SelfX.Code.json is too large.' }
	try { $manifest = [IO.File]::ReadAllText($listPath) | ConvertFrom-Json -ErrorAction Stop }
	catch { throw 'SelfX.Code.json is not valid JSON.' }
	if (-not $manifest -or "$($manifest.ManifestVersion)" -ne '1' -or -not $manifest.Files) { throw 'SelfX.Code.json has an unknown format.' }
	$property = $manifest.Files.PSObject.Properties['Disturb/SelfXDisturb.dll']
	if (-not $property) { throw 'SelfXDisturb.dll is not listed in SelfX.Code.json.' }
	$hash = "$($property.Value)"
	if ($hash -notmatch '^[0-9A-Fa-f]{64}$') { throw 'SelfX.Code.json has an invalid hash for Disturb/SelfXDisturb.dll.' }
	return $hash.ToUpperInvariant()
}

# Checks the folder Disturb and the DLL and keeps the DLL open (read sharing only). Throws when anything differs.
function Test-SelfXDisturbFiles {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$expected = Get-SelfXDisturbExpectedHash -InstallFolder $InstallFolder
	$folderPath = Join-Path $InstallFolder 'Disturb'
	$folder = Get-Item -LiteralPath $folderPath -Force -ErrorAction SilentlyContinue
	if (-not $folder -or -not $folder.PSIsContainer) { throw 'The folder Disturb is missing.' }
	if ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The folder Disturb is a link.' }
	$entries = @(Get-ChildItem -LiteralPath $folderPath -Force)
	foreach ($entry in $entries) {
		if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Disturb\$($entry.Name) is a link." }
		if ($entry.PSIsContainer) { throw "Disturb\$($entry.Name) is a folder." }
		if ($entry.Name -ine 'SelfXDisturb.dll') { throw "Disturb\$($entry.Name) is not expected." }
	}
	if ($entries.Count -ne 1) { throw 'Disturb\SelfXDisturb.dll is missing.' }
	$stream = $null
	try {
		$stream = New-Object IO.FileStream($entries[0].FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
		$actual = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($stream)).Replace('-', '')
		if ($actual -ne $expected) { throw 'Disturb\SelfXDisturb.dll does not match SelfX.Code.json.' }
	}
	catch {
		if ($stream) { $stream.Dispose() }
		$cause = if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }
		if ($cause -is [IO.IOException] -or $cause -is [UnauthorizedAccessException]) { throw "Disturb\SelfXDisturb.dll cannot be opened for the check ($($cause.GetType().Name))." }
		throw
	}
	$previous = $Script:SelfXDisturbHandle
	$Script:SelfXDisturbHandle = $stream
	if ($previous) { $previous.Dispose() }
}

# Checks the file and then loads SelfXDisturb.dll. Afterwards [SelfX.SelfXDisturb]::GetNotificationState() is available.
# Throws (nothing is loaded) when the check fails.
function Import-SelfXDisturb {
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$InstallFolder = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	Test-SelfXDisturbFiles -InstallFolder $InstallFolder
	[void][Reflection.Assembly]::LoadFrom((Join-Path (Join-Path $InstallFolder 'Disturb') 'SelfXDisturb.dll'))
}

function Get-SelfXNotificationState {
	# 1 to 7 = QUERY_USER_NOTIFICATION_STATE of the own session, 0 = cannot be read (library missing or not matching the list).
	param([string]$InstallFolder = $PSScriptRoot)
	try {
		if (-not ('SelfX.SelfXDisturb' -as [type])) { Import-SelfXDisturb -InstallFolder $InstallFolder }
		$state = [int][SelfX.SelfXDisturb]::GetNotificationState()
		if ($state -lt 1 -or $state -gt 7) { return 0 }
		return $state
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
