<#
.SYNOPSIS
    Tests the check of the links of the help dialog (Sources\SupportLinks.ps1, finding N7 of the code review).

.DESCRIPTION
    Pure functions, nothing is read from or changed on the device. Checked: https only, no user name in the link, no
    white space or control characters, mailto only with one plain address, only the Teams chat link of SelfX, everything
    else refused. Also checks in the sources that the link functions are used and that no program is started by a bare
    name in Self_X.ps1.

.NOTES
    Name    : Test-SupportLinks.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.0    2026-11-23  fubu2k               Initial version (code review finding N7).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ("$Actual" -cne "$Expected") { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}
. (Join-Path $PSScriptRoot 'Sources\TicketMail.ps1')
. (Join-Path $PSScriptRoot 'Sources\SupportLinks.ps1')

# --- https ----------------------------------------------------------------------------------------
Assert-Equal (Get-SelfXSafeUri 'https://support.example.com/help?id=1') 'https://support.example.com/help?id=1' 'https: normal link is kept'
Assert-Equal (Get-SelfXSafeUri '  https://support.example.com  ') 'https://support.example.com/' 'https: spaces around are trimmed, host gets its slash'
Assert-Equal (Get-SelfXSafeUri 'HTTPS://Support.Example.com/A') 'https://support.example.com/A' 'https: scheme and host in lower case'
Assert-Equal (Get-SelfXSafeUri 'http://support.example.com') '' 'http is refused'
Assert-Equal (Get-SelfXSafeUri 'ftp://support.example.com') '' 'ftp is refused'
Assert-Equal (Get-SelfXSafeUri 'file:///C:/Windows/System32/cmd.exe') '' 'file: is refused'
Assert-Equal (Get-SelfXSafeUri 'ms-settings:network') '' 'other schemes are refused'
Assert-Equal (Get-SelfXSafeUri 'C:\Windows\System32\cmd.exe') '' 'a path is refused'
Assert-Equal (Get-SelfXSafeUri '\\server\share\x.exe') '' 'a UNC path is refused'
Assert-Equal (Get-SelfXSafeUri 'https://user:secret@support.example.com') '' 'user name and password in the link are refused'
Assert-Equal (Get-SelfXSafeUri 'https://user@support.example.com') '' 'user name in the link is refused'
Assert-Equal (Get-SelfXSafeUri 'https://') '' 'https without host is refused'
Assert-Equal (Get-SelfXSafeUri "https://support.example.com/a b") '' 'white space in the link is refused'
Assert-Equal (Get-SelfXSafeUri "https://support.example.com/a`r`nHost: x") '' 'line break in the link is refused'
Assert-Equal (Get-SelfXSafeUri ("https://support.example.com/" + ('a' * 2100))) '' 'a link over 2000 characters is refused'
Assert-Equal (Get-SelfXSafeUri $null) '' 'null is refused'
Assert-Equal (Get-SelfXSafeUri '') '' 'empty is refused'

# --- mailto ---------------------------------------------------------------------------------------
Assert-Equal (Get-SelfXSafeUri 'mailto:support@example.com') 'mailto:support@example.com' 'mailto: one plain address'
Assert-Equal (Get-SelfXSafeUri 'mailto:support@example.com?cc=boss@example.com') '' 'mailto: parameters are refused'
Assert-Equal (Get-SelfXSafeUri 'mailto:support@example.com&body=x') '' 'mailto: & is refused'
Assert-Equal (Get-SelfXSafeUri 'mailto:a@example.com,b@example.com') '' 'mailto: a list is refused'
Assert-Equal (Get-SelfXSafeUri 'mailto:a@example.com;b@example.com') '' 'mailto: a semicolon list is refused'
Assert-Equal (Get-SelfXSafeUri 'mailto:') '' 'mailto: without address is refused'
Assert-Equal (Get-SelfXSafeUri 'mailto:Name <a@example.com>') '' 'mailto: a display name is refused'

# --- Teams ----------------------------------------------------------------------------------------
$chat = 'msteams:/l/chat/0/0?users=' + [uri]::EscapeDataString('helpdesk@example.com')
Assert-Equal (Get-SelfXSafeUri $chat) $chat 'msteams: the chat link that SelfX builds is accepted'
Assert-Equal (Get-SelfXSafeUri 'msteams:/l/chat/0/0?users=a@example.com&message=x') '' 'msteams: extra parameters are refused'
Assert-Equal (Get-SelfXSafeUri 'msteams:/l/call/0/0?users=a@example.com') '' 'msteams: other actions are refused'
Assert-Equal (Get-SelfXSafeUri 'msteams:/l/chat/0/0?users=') '' 'msteams: without users is refused'

# --- website ----------------------------------------------------------------------------------------
Assert-Equal (ConvertTo-SelfXSupportWebUri 'https://support.example.com') 'https://support.example.com/' 'website: https accepted'
Assert-Equal (ConvertTo-SelfXSupportWebUri 'http://support.example.com') '' 'website: http refused'
Assert-Equal (ConvertTo-SelfXSupportWebUri 'mailto:support@example.com') '' 'website: mailto refused'
Assert-Equal (ConvertTo-SelfXSupportWebUri 'msteams:/l/chat/0/0?users=a%40example.com') '' 'website: msteams refused'

# --- the sources use the checks and start no program by a bare name ----------------------------------------
$gui = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sources\Self_X.ps1'))
Assert-Equal ($gui.Contains('. "$Current_Folder\SupportLinks.ps1"')) $true 'Self_X.ps1 loads SupportLinks.ps1'
Assert-Equal ($gui.Contains('Start-Process $Safe_Uri')) $true 'Open-SelfXUri opens only the checked link'
Assert-Equal ($gui.Contains('Start-Process $Uri')) $false 'Open-SelfXUri does not open an unchecked link'
Assert-Equal ($gui -match '"mailto:\$Support_Mail"') $false 'the mailto link is not built from the unchecked Support_Mail'
Assert-Equal ($gui -match '\^https\?://') $false 'http:// is not accepted for Support_Website'
Assert-Equal ($gui -match 'Start-Process\s+"explorer\.exe"') $false 'Self_X.ps1 starts Explorer with its full path'
Assert-Equal ($gui -match '/c MdmDiagnosticsTool\.exe') $false 'the MDM diagnostics start with the full path of the tool'
Assert-Equal ($gui -match '& explorer\.exe') $false 'the MDM diagnostics open Explorer with its full path'
foreach ($name in 'SelfX_Outlook_Reboot.ps1', 'SelfX_Outlook_TeamsAddIn.ps1', 'SelfX_Word_Reboot.ps1') {
	$text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "Sources\Scripts_to_run\$name"))
	Assert-Equal ($text -match "Start-Process -FilePath '[A-Za-z]+\.exe'") $false "$name does not start the program by a bare name"
}
$self = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sources\SupportLinks.ps1'))
foreach ($pattern in 'Start-Process', 'Invoke-Expression', '\biex\b', 'Set-ItemProperty', 'New-Item', 'Out-File', 'Set-Content', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Get-ItemProperty') {
	Assert-Equal ($self -match $pattern) $false "SupportLinks.ps1 does not use $pattern"
}

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
