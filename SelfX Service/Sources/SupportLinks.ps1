<#
.SYNOPSIS
    Checks the links of the help dialog.

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

    Catalogue links (Context Link in Issues_List.xml): the catalogue names a key of Tool_Config.xml (Link_<Name>), the
    address comes from that key. Resolve-SelfXCatalogLink accepts only such a key and only an https address; an empty
    value or "Off" switches the action off.

.NOTES
    Name    : SupportLinks.ps1
    Package : SelfX Service
    Context : Dot-sourced by Self_X.ps1 (user context); also loaded by Test-SupportLinks.ps1
    Version : 2.8.26

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.0    2026-11-23  fubu2k               Initial version.
    2.8.14   2026-11-23  fubu2k               Resolve-SelfXCatalogLink (links of catalogue actions with Context Link).
    2.8.26   2026-11-24  fubu2k               Get-SelfXWikiSettings (optional wiki button).
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

function Resolve-SelfXCatalogLink {
	# Address of a catalogue action with Context Link. Key = name of the setting in Tool_Config.xml (Link_<Name>),
	# Value = its value. State: Ok (Uri is set), Off (empty or "Off": the action is not shown), Invalid (not an https
	# address), BadKey (the key is not of the form Link_<letters and digits>).
	param($Key, $Value)
	if ("$Key" -cnotmatch '^Link_[A-Za-z0-9]{1,40}$') { return [pscustomobject]@{ Uri = $null; State = 'BadKey' } }
	$text = "$Value".Trim()
	if (-not $text -or $text -ieq 'Off') { return [pscustomobject]@{ Uri = $null; State = 'Off' } }
	$uri = ConvertTo-SelfXSupportWebUri $text
	if (-not $uri) { return [pscustomobject]@{ Uri = $null; State = 'Invalid' } }
	return [pscustomobject]@{ Uri = $uri; State = 'Ok' }
}

function Get-SelfXWikiSettings {
	# Settings of the optional wiki button: Enabled, Url and Name come from Tool_Config.xml (Wiki_Enabled, Wiki_Url,
	# Wiki_Name). Result: Available ($true only when the button is on and the address is a valid https address), Uri (checked
	# address), Name (text for the button, no control characters, at most 40 characters; empty = use the localized text) and
	# Warnings (what was ignored or shortened, for the log).
	param($Enabled, $Url, $Name)
	$warnings = New-Object System.Collections.Generic.List[string]
	$result = [pscustomobject]@{ Available = $false; Uri = $null; Name = ''; Warnings = $warnings }
	if ("$Enabled".Trim() -cne 'True') { return $result }
	$uri = ConvertTo-SelfXSupportWebUri $Url
	if (-not $uri) { $warnings.Add('Wiki_Url is not a valid https address: the wiki button is not shown.'); return $result }
	$text = ("$Name" -replace '[\x00-\x1F\x7F]', ' ').Trim()
	if ($text.Length -gt 40) { $text = $text.Substring(0, 40).Trim(); $warnings.Add('Wiki_Name is longer than 40 characters and was shortened.') }
	$result.Available = $true
	$result.Uri = $uri
	$result.Name = $text
	return $result
}
