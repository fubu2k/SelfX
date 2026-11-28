<#
.SYNOPSIS
    First name of the signed-in user and the greeting of the SelfX window.

.DESCRIPTION
    Loaded by Self_X.ps1 (user context, own session): the text of this file and of SelfXWinRT.ps1 is passed to a background runspace,
    which calls Get-SelfXUserFirstName with a time limit; the window opens at once with the neutral greeting and adds the name when it
    arrives. Nothing is read from or changed on the device when the file is loaded.

    Source of the first name: Windows.System.User.GetDefault() and the property KnownUserProperties.FirstName (documented WinRT API),
    through the Windows SDK projection in the folder WinRT of the install folder. Import-SelfXWinRTProjection (SelfXWinRT.ps1) checks the DLLs
    of that folder against SelfX.Code.json before anything is loaded; the checked projection DLLs are then loaded from the same folder.
    Nothing is compiled. No LDAP, no Microsoft Graph, no network request of SelfX, no request to the service. Windows returns an empty
    text when the property is not available or when the privacy setting "Account info" does not allow it; then the greeting stays
    neutral. Only the first name is used: a missing first name is never guessed from the display name or the account name.

    Get-SelfXUserFirstName      the cleaned first name, or '' (also on any error and after TimeoutMs). Never throws.
    ConvertTo-SelfXGreetingName pure: removes control characters, characters that change the reading direction and line separators,
                                folds white space and keeps at most 40 characters (never cutting a character in two).
    ConvertTo-SelfXGreetingMode pure: Greeting_Name of Tool_Config.xml. Empty or missing = FirstName (default), FirstName, Off; any
                                other value = Off.
    Get-SelfXGreetingText       pure: the text for the hour of the day (morning 5-11, day 12-17, evening 18-4) with the name in {0},
                                or the neutral text without a name. A text without {0} (for example an override in Config\Texts) never
                                shows a name. The name is inserted as plain text (no format string).

    The name is shown only through TextBlock.Text (never placed in XAML), is not logged, not saved and not sent anywhere.

.NOTES
    Name    : UserName.ps1
    Package : SelfX Service
    Context : User (background runspace of Self_X.ps1; also loaded by Test-UI.ps1)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-28  fubu2k               Initial version.
#>

# Characters that are removed from a name: control characters, the marks and embeddings that change the reading direction (they could
# make the greeting read differently), the byte order mark and the line and paragraph separators. Joiners (ZWJ, ZWNJ) stay: some
# scripts need them.
$Script:SelfXGreetingNameFilter = '[\p{Cc}؜‎‏‪-‮⁦-⁩﻿  \u0085]'
$Script:SelfXGreetingNameMaxLength = 40

function ConvertTo-SelfXGreetingName {
	# Pure: a name that is safe to show in one line, or ''.
	param([AllowNull()][string]$Name)
	if ([string]::IsNullOrEmpty($Name)) { return '' }
	$clean = [regex]::Replace($Name, $Script:SelfXGreetingNameFilter, '')
	$clean = [regex]::Replace($clean, '\s+', ' ').Trim()
	if ($clean.Length -le $Script:SelfXGreetingNameMaxLength) { return $clean }
	# Cut by text elements, so a surrogate pair or a letter with its combining marks is never split.
	$result = New-Object System.Text.StringBuilder
	$elements = [Globalization.StringInfo]::GetTextElementEnumerator($clean)
	while ($elements.MoveNext()) {
		$element = [string]$elements.GetTextElement()
		if ($result.Length + $element.Length -gt $Script:SelfXGreetingNameMaxLength) { break }
		[void]$result.Append($element)
	}
	return $result.ToString().Trim()
}

function ConvertTo-SelfXGreetingMode {
	# Pure: Greeting_Name of Tool_Config.xml -> FirstName or Off.
	param([AllowNull()][string]$Value)
	$text = "$Value".Trim()
	if ($text -eq '' -or $text -ieq 'FirstName') { return 'FirstName' }
	return 'Off'
}

function Get-SelfXGreetingText {
	# Pure: Texts has the keys Morning, Day, Evening (each with {0}) and Neutral.
	param([AllowNull()][string]$Name, [int]$Hour, [Parameter(Mandatory = $true)][hashtable]$Texts)
	$neutral = "$($Texts['Neutral'])"
	$clean = ConvertTo-SelfXGreetingName -Name $Name
	if (-not $clean) { return $neutral }
	$key = $(if ($Hour -ge 5 -and $Hour -lt 12) { 'Morning' } elseif ($Hour -ge 12 -and $Hour -lt 18) { 'Day' } else { 'Evening' })
	$template = "$($Texts[$key])"
	if (-not $template.Contains('{0}')) { return $neutral }
	return $template.Replace('{0}', $clean)
}

function Read-SelfXWinRTFirstName {
	# The raw first name from Windows.System.User (see above). Needs Import-SelfXWinRTProjection (SelfXWinRT.ps1) in the same runspace.
	param([Parameter(Mandatory = $true)][string]$InstallFolder, [int]$TimeoutMs = 2000)
	if (-not ('Windows.System.User' -as [type])) {
		# Checks every DLL of WinRT against SelfX.Code.json and keeps them open (read sharing only), then loads the checked files.
		Import-SelfXWinRTProjection -InstallFolder $InstallFolder
	}
	$user = [Windows.System.User]::GetDefault()
	if ($null -eq $user) { return '' }
	$task = [System.WindowsRuntimeSystemExtensions]::AsTask($user.GetPropertyAsync([Windows.System.KnownUserProperties]::FirstName))
	if (-not $task.Wait($TimeoutMs)) { return '' }
	$value = $task.Result
	if ($value -isnot [string]) { return '' }
	return $value
}

function Get-SelfXUserFirstName {
	# The cleaned first name or ''. Provider (tests) replaces the WinRT call; it returns the raw text.
	param([string]$InstallFolder = $PSScriptRoot, [int]$TimeoutMs = 2000, [scriptblock]$Provider)
	try {
		if ($Provider) { $raw = & $Provider } else { $raw = Read-SelfXWinRTFirstName -InstallFolder $InstallFolder -TimeoutMs $TimeoutMs }
		if ($raw -isnot [string]) { return '' }
		return (ConvertTo-SelfXGreetingName -Name $raw)
	}
	catch { return '' }
}
