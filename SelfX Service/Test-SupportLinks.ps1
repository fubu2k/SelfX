<#
.SYNOPSIS
    Tests the check of the links of the help dialog (Sources\SupportLinks.ps1).

.DESCRIPTION
    Pure functions, nothing is read from or changed on the device. Checked: https only, no user name in the link, no
    white space or control characters, mailto only with one plain address, only the Teams chat link of SelfX, everything
    else refused. Also checks in the sources that the link functions are used and that no program is started by a bare
    name in Self_X.ps1.

.NOTES
    Name    : Test-SupportLinks.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.14

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.0    2026-11-23  fubu2k               Initial version.
    2.8.14   2026-11-23  fubu2k               Tests for Resolve-SelfXCatalogLink (links of catalogue actions).
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

# --- links of catalogue actions (Context Link) ---------------------------------------------------------------
function Get-LinkState($Key, $Value) { (Resolve-SelfXCatalogLink -Key $Key -Value $Value).State }
Assert-Equal (Resolve-SelfXCatalogLink -Key 'Link_PasswordReset' -Value 'https://passwordreset.microsoftonline.com/').Uri 'https://passwordreset.microsoftonline.com/' 'catalogue link: https address is returned'
Assert-Equal (Get-LinkState 'Link_PasswordReset' 'https://passwordreset.microsoftonline.com/') 'Ok' 'catalogue link: state Ok'
Assert-Equal (Get-LinkState 'Link_SecurityInfo' '  https://mysignins.microsoft.com/security-info  ') 'Ok' 'catalogue link: spaces around are trimmed'
Assert-Equal (Get-LinkState 'Link_PasswordReset' '') 'Off' 'catalogue link: empty value switches the action off'
Assert-Equal (Get-LinkState 'Link_PasswordReset' $null) 'Off' 'catalogue link: missing value switches the action off'
Assert-Equal (Get-LinkState 'Link_PasswordReset' 'off') 'Off' 'catalogue link: Off (any case) switches the action off'
foreach ($bad in 'http://passwordreset.microsoftonline.com/', 'file:///C:/Windows/System32/cmd.exe', 'ms-settings:network', 'mailto:a@b.de', 'msteams:/l/chat/0/0?users=a%40example.com', 'https://user:pw@example.com/', 'https://example.com/a b', 'javascript:alert(1)', 'C:\\Windows\\System32\\cmd.exe', '\\\\server\\share') {
	Assert-Equal (Get-LinkState 'Link_PasswordReset' $bad) 'Invalid' "catalogue link: '$bad' is refused"
	Assert-Equal ([bool](Resolve-SelfXCatalogLink -Key 'Link_PasswordReset' -Value $bad).Uri) $false "catalogue link: '$bad' gives no address"
}
foreach ($badKey in '', 'PasswordReset', 'Link_', 'Link_a b', 'Link_a;b', 'link_PasswordReset', 'Support_Website', 'Copilot_Url', '..\\Link_A', ('Link_' + ('a' * 41))) {
	Assert-Equal (Get-LinkState $badKey 'https://example.com/') 'BadKey' "catalogue link: key '$badKey' is refused"
}
Assert-Equal (Get-LinkState ('Link_' + ('a' * 40)) 'https://example.com/') 'Ok' 'catalogue link: key with 40 characters is accepted'

# --- the sources use the checks and start no program by a bare name ----------------------------------------
$gui = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sources\Self_X.ps1'))
Assert-Equal ($gui.Contains('. "$Current_Folder\SupportLinks.ps1"')) $true 'Self_X.ps1 loads SupportLinks.ps1'
Assert-Equal ($gui.Contains('Start-Process $Safe_Uri')) $true 'Open-SelfXUri opens only the checked link'
Assert-Equal ($gui.Contains('Start-Process $Uri')) $false 'Open-SelfXUri does not open an unchecked link'
Assert-Equal ($gui.Contains('Start-Process $Link.Uri')) $true 'a link action opens only the address that Resolve-SelfXCatalogLink returned'
Assert-Equal ($gui -match 'Start-Process\s+\$rowObj') $false 'a link action never opens a value of the catalogue row directly'
Assert-Equal ($gui -match '"mailto:\$Support_Mail"') $false 'the mailto link is not built from the unchecked Support_Mail'
Assert-Equal ($gui -match '\^https\?://') $false 'http:// is not accepted for Support_Website'
Assert-Equal ($gui -match 'Start-Process\s+"explorer\.exe"') $false 'Self_X.ps1 starts Explorer with its full path'
Assert-Equal ($gui -match '/c MdmDiagnosticsTool\.exe') $false 'the MDM diagnostics start with the full path of the tool'
Assert-Equal ($gui -match '& explorer\.exe') $false 'the MDM diagnostics open Explorer with its full path'
foreach ($name in 'SelfX_Outlook_Reboot.ps1', 'SelfX_Outlook_TeamsAddIn.ps1', 'SelfX_Word_Reboot.ps1') {
	$text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "Sources\Scripts_to_run\$name"))
	Assert-Equal ($text -match "Start-Process -FilePath '[A-Za-z]+\.exe'") $false "$name does not start the program by a bare name"
}
# Wiki button settings
$w = Get-SelfXWikiSettings -Enabled 'True' -Url 'https://wiki.contoso.example/start' -Name '  Contoso Wiki  '
Assert-Equal $w.Available $true 'wiki: valid https address is available'
Assert-Equal $w.Uri 'https://wiki.contoso.example/start' 'wiki: address is kept'
Assert-Equal $w.Name 'Contoso Wiki' 'wiki: name is trimmed'
Assert-Equal (Get-SelfXWikiSettings -Enabled 'False' -Url 'https://wiki.contoso.example' -Name '').Available $false 'wiki: off by default value'
Assert-Equal (Get-SelfXWikiSettings -Enabled '' -Url 'https://wiki.contoso.example' -Name '').Available $false 'wiki: empty switch is off'
Assert-Equal (Get-SelfXWikiSettings -Enabled 'true' -Url 'https://wiki.contoso.example' -Name '').Available $false 'wiki: only exact True switches it on'
foreach ($badUrl in '', 'http://wiki.contoso.example', 'javascript:alert(1)', 'file:///C:/x', '\\server\share', 'https://user:pw@wiki.contoso.example', 'wiki.contoso.example', "https://wiki.contoso.example/`r`nx", ('https://wiki.contoso.example/' + ('a' * 2000))) {
	$bad = Get-SelfXWikiSettings -Enabled 'True' -Url $badUrl -Name 'x'
	Assert-Equal $bad.Available $false "wiki: rejects '$($badUrl.Substring(0, [Math]::Min(30, $badUrl.Length)))'"
	Assert-Equal ($bad.Warnings.Count -ge 1) $true 'wiki: invalid address gives a warning'
}
$long = Get-SelfXWikiSettings -Enabled 'True' -Url 'https://wiki.contoso.example' -Name ('N' * 60)
Assert-Equal $long.Name.Length 40 'wiki: name is shortened to 40 characters'
Assert-Equal ($long.Warnings.Count -eq 1) $true 'wiki: shortened name gives a warning'
Assert-Equal (Get-SelfXWikiSettings -Enabled 'True' -Url 'https://wiki.contoso.example' -Name "A`tB`0C").Name 'A B C' 'wiki: control characters become spaces'
Assert-Equal (Get-SelfXWikiSettings -Enabled 'True' -Url 'https://wiki.contoso.example' -Name $null).Name '' 'wiki: no name means localized text'

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
