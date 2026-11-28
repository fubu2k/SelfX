<#
.SYNOPSIS
    First name of the signed-in user and the greeting of the SelfX window.

.DESCRIPTION
    Dot-sourced by Self_X.ps1 (user context, own session). Nothing is read from or changed on the device when the file is loaded.

    The window never loads a WinRT library itself, so an open window holds no file of App\WinRT (an update can replace them). It
    starts this file as a short process of its own (Start-SelfXFirstNameLookup: PowerShell 7 from its fixed path, fixed arguments as a
    list, no input of the user, no console window) and reads one line from its output. The process ends by itself; after 2 seconds the
    window ends it (Get-SelfXFirstNameLookupState) and the greeting stays neutral. The window opens at once with the neutral greeting.

    In that process (switch -PrintFirstName) the first name comes from Windows.System.User.GetDefault() and the property
    KnownUserProperties.FirstName (documented WinRT API), through the Windows SDK projection in the folder WinRT next to this file.
    Import-SelfXWinRTProjection (SelfXWinRT.ps1) checks the DLLs of that folder against SelfX.Code.json before anything is loaded.
    Nothing is compiled. No LDAP, no Microsoft Graph, no network request of SelfX, no request to the service. Windows returns an empty
    text when the property is not available or when the privacy setting "Account info" does not allow it; then the greeting stays
    neutral. Only the first name is used: a missing first name is never guessed from the display name or the account name.

    Get-SelfXUserFirstName          the cleaned first name, or '' (also on any error and after TimeoutMs). Never throws.
    Start-SelfXFirstNameLookup      starts the process described above and returns Process, Output (task of its standard output) and Watch.
    Get-SelfXFirstNameLookupState   Done and Name: the cleaned first line of the output once the process has ended; after TimeoutMs the
                                    process tree is ended and Name is ''. Never throws.
    ConvertTo-SelfXGreetingName     pure: removes control characters, characters that change the reading direction and line separators,
                                    folds white space and keeps at most 40 characters (never cutting a character in two).
    ConvertTo-SelfXGreetingMode     pure: Greeting_Name of Tool_Config.xml. Empty or missing = FirstName (default), FirstName, Off; any
                                    other value = Off.
    Get-SelfXGreetingText           pure: the text for the hour of the day (morning 5-11, day 12-17, evening 18-4) with the name in {0},
                                    or the neutral text without a name. A text without {0} (for example an override in Config\Texts)
                                    never shows a name. The name is inserted as plain text (no format string).

    The name is shown only through TextBlock.Text (never placed in XAML), is not logged, not saved and not sent anywhere.

.PARAMETER PrintFirstName
    Only for the process that Start-SelfXFirstNameLookup starts: write the cleaned first name (or an empty line) and end.

.NOTES
    Name    : UserName.ps1
    Package : SelfX Service
    Context : User (dot-sourced by Self_X.ps1; own short process of the window; also loaded by Test-UI.ps1)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-28  fubu2k               Initial version.
#>
param([switch]$PrintFirstName)

# Characters that are removed from a name: control characters, the marks and embeddings that change the reading direction (they could
# make the greeting read differently), the byte order mark and the line and paragraph separators. Joiners (ZWJ, ZWNJ) stay: some
# scripts need them. Built from code points, so this file stays plain ASCII.
$Script:SelfXGreetingNameFilter = '[\p{Cc}' + (-join @(0x061C, 0x200E, 0x200F, 0x2028, 0x2029, 0xFEFF | ForEach-Object { [char]$_ })) +
	[char]0x202A + '-' + [char]0x202E + [char]0x2066 + '-' + [char]0x2069 + ']'
$Script:SelfXGreetingNameMaxLength = 40
# At most this many characters of the output of the lookup process are read.
$Script:SelfXGreetingMaxOutput = 1000

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
	# The raw first name from Windows.System.User (see above). Needs Import-SelfXWinRTProjection (SelfXWinRT.ps1).
	param([Parameter(Mandatory = $true)][string]$InstallFolder, [int]$TimeoutMs = 1500)
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
	param([string]$InstallFolder = $PSScriptRoot, [int]$TimeoutMs = 1500, [scriptblock]$Provider)
	try {
		if ($Provider) { $raw = & $Provider } else { $raw = Read-SelfXWinRTFirstName -InstallFolder $InstallFolder -TimeoutMs $TimeoutMs }
		if ($raw -isnot [string]) { return '' }
		return (ConvertTo-SelfXGreetingName -Name $raw)
	}
	catch { return '' }
}

function Start-SelfXFirstNameLookup {
	# Starts UserName.ps1 -PrintFirstName from the code folder as a process of its own (see above). Needs Get-SelfXPowerShellPath
	# (SelfXServiceClient.ps1). Every argument is an entry of the list (no command line is built from text).
	param([Parameter(Mandatory = $true)][string]$InstallFolder)
	$folder = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
	$start = New-Object System.Diagnostics.ProcessStartInfo
	$start.FileName = Get-SelfXPowerShellPath
	foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $folder 'UserName.ps1'), '-PrintFirstName')) {
		$start.ArgumentList.Add($argument)
	}
	$start.WorkingDirectory = $folder
	$start.UseShellExecute = $false
	$start.CreateNoWindow = $true
	$start.RedirectStandardOutput = $true
	$start.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
	$watch = [Diagnostics.Stopwatch]::StartNew()
	$process = [System.Diagnostics.Process]::Start($start)
	return [pscustomobject]@{ Process = $process; Output = $process.StandardOutput.ReadToEndAsync(); Watch = $watch }
}

function Get-SelfXFirstNameLookupState {
	# Done = $false while the process runs within TimeoutMs. Done = $true with the cleaned first line of the output when it has ended,
	# or with Name '' after TimeoutMs (the process tree is ended) or on any error. The process is disposed when Done.
	param([Parameter(Mandatory = $true)]$Lookup, [int]$TimeoutMs = 2000)
	$name = ''
	try {
		if ($Lookup.Process.HasExited -and $Lookup.Output.IsCompleted) {
			$text = "$($Lookup.Output.Result)"
			if ($text.Length -gt $Script:SelfXGreetingMaxOutput) { $text = $text.Substring(0, $Script:SelfXGreetingMaxOutput) }
			$name = ConvertTo-SelfXGreetingName -Name (@($text -split "`r?`n")[0])
		}
		elseif ($Lookup.Watch.ElapsedMilliseconds -lt $TimeoutMs) { return [pscustomobject]@{ Done = $false; Name = '' } }
		else { $Lookup.Process.Kill($true) }
	}
	catch { $name = '' }
	try { $Lookup.Process.Dispose() } catch { Write-Verbose "The lookup process was not disposed ($($_.Exception.GetType().Name))." }
	return [pscustomobject]@{ Done = $true; Name = $name }
}

if ($PrintFirstName) {
	# The own process of the window: load the checked projection here, write one line, end.
	. (Join-Path $PSScriptRoot 'SelfXWinRT.ps1')
	[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
	[Console]::Out.WriteLine((Get-SelfXUserFirstName -InstallFolder $PSScriptRoot -TimeoutMs 1500))
	exit 0
}
