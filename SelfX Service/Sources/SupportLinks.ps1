<#
.SYNOPSIS
    Checks the links of the help dialog (finding N7 of the code review).

.DESCRIPTION
    Pure functions, nothing is read from or changed on the device. The links come from Tool_Config.xml (only
    administrators can change it) and are opened with the rights of the user. They are checked anyway, so that a typing
    mistake or a wrong value cannot open something else than a web page, a plain mail address or a Teams chat:
      - https only (no http, no file:, no other scheme), no user name or password in the link, no white space or control
        characters, at most 2000 characters;
      - mailto: only with one plain address (no list, no ?cc= or &body= parameters), checked with Test-SelfXTicketAddress
        (TicketMail.ps1 must be loaded);
      - msteams: only the chat link that SelfX builds itself (msteams:/l/chat/0/0?users=<escaped address>).
    Everything else gives $null.

.NOTES
    Name    : SupportLinks.ps1
    Package : SelfX Service
    Context : Dot-sourced by Self_X.ps1 (user context); also loaded by Test-SupportLinks.ps1
    Version : 2.8.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.0    2026-11-23  fubu2k               Initial version (code review finding N7).
#>

function Get-SelfXSafeUri {
	# Returns the link (https links in normal form) when it is allowed, otherwise $null.
	param($Uri)
	$text = "$Uri".Trim()
	if (-not $text -or $text.Length -gt 2000) { return $null }
	if ($text -match '[\x00-\x20\x7F]') { return $null }
	if ($text -match '^(?i:https):') {
		$parsed = $null
		if (-not [uri]::TryCreate($text, [UriKind]::Absolute, [ref]$parsed)) { return $null }
		if ($parsed.Scheme -cne 'https' -or [string]::IsNullOrEmpty($parsed.Host) -or $parsed.UserInfo) { return $null }
		return $parsed.AbsoluteUri
	}
	if ($text -match '^(?i:mailto):(?<address>[^?&]+)\z') {
		if (Test-SelfXTicketAddress $Matches['address']) { return $text }
		return $null
	}
	if ($text -cmatch '^msteams:/l/chat/0/0\?users=[A-Za-z0-9%._~@-]{1,300}\z') { return $text }
	return $null
}

function ConvertTo-SelfXSupportWebUri {
	# The website of the help dialog: https only. Returns the link or $null.
	param($Value)
	$safe = Get-SelfXSafeUri $Value
	if ($safe -and $safe -cmatch '^https://') { return $safe }
	return $null
}
