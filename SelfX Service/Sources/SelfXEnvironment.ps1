<#
.SYNOPSIS
    Environment_Mode of SelfX (Client or TerminalServer) and the TerminalServer classification of actions and repairs.

.DESCRIPTION
    Shared by the window (Self_X.ps1), the status icon (SelfX_Tray.ps1) and the health collection (HealthStatus.ps1, run as
    SYSTEM by the service). Dot-sourcing defines functions only.
    Environment_Mode comes from Tool_Config.xml: TerminalServer (case is ignored) = terminal server or session host with several
    users; empty, missing or Client = Client; any other value = Client, marked as not valid so that the caller can log it.
    An unreadable Tool_Config.xml counts as TerminalServer (fail closed).
    With TerminalServer only entries classified Show are offered (<TerminalServer>Show</TerminalServer> in Issues_List.xml,
    TerminalServer="Show" in Health_Config.xml); a missing or any other value is Hide. With Client everything is offered.
    The service (SelfXService.cs) applies the same rules to RUN, because the window is no security boundary.

.NOTES
    Name    : SelfXEnvironment.ps1
    Package : SelfX Service
    Context : User (window, status icon) and System (health collection)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version (Environment_Mode, classification Show or Hide)
    3.1.0    2026-11-28  fubu2k               TerminalServer_Health (Off or AdminOnly) and the view of a user: device status, rows of the class Server,
                                              kinds of connection (ConvertTo-SelfXHealthAccess, Test-SelfXElevatedAdministrator, Get-SelfXViewScope)
#>

function ConvertTo-SelfXEnvironmentMode {
	# Mode = 'Client' or 'TerminalServer'; Valid = $false for a value that is neither empty, Client nor TerminalServer.
	param([AllowNull()][AllowEmptyString()][string]$Value)
	$text = "$Value".Trim()
	if ($text -ieq 'TerminalServer') { return [pscustomobject]@{ Mode = 'TerminalServer'; Valid = $true } }
	return [pscustomobject]@{ Mode = 'Client'; Valid = ($text.Length -eq 0 -or $text -ieq 'Client') }
}

function Read-SelfXEnvironmentXml {
	# Reads an XML settings file without DTD and without resolving external resources. Throws when it cannot be read.
	param([Parameter(Mandatory = $true)][string]$Path)
	$settings = New-Object System.Xml.XmlReaderSettings
	$settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
	$settings.XmlResolver = $null
	$document = New-Object System.Xml.XmlDocument
	$document.XmlResolver = $null
	$reader = [System.Xml.XmlReader]::Create($Path, $settings)
	try { $document.Load($reader) } finally { $reader.Dispose() }
	return $document
}

function Get-SelfXEnvironmentMode {
	# Environment_Mode of Tool_Config.xml. An unreadable file = TerminalServer with Valid = $false (fail closed).
	param([Parameter(Mandatory = $true)][string]$ToolConfigPath)
	try { $document = Read-SelfXEnvironmentXml -Path $ToolConfigPath }
	catch { return [pscustomobject]@{ Mode = 'TerminalServer'; Valid = $false } }
	$node = $document.SelectSingleNode('/GUI_Config/Environment_Mode')
	return ConvertTo-SelfXEnvironmentMode $(if ($node) { $node.InnerText } else { '' })
}

function Test-SelfXShownInEnvironment {
	# $true when an entry with this classification is offered in the mode: always with Client, only Show (exact) with TerminalServer.
	param([string]$Mode, [AllowNull()][AllowEmptyString()][string]$Classification)
	if ($Mode -cne 'TerminalServer') { return $true }
	return ("$Classification".Trim() -ceq 'Show')
}

function ConvertTo-SelfXHealthAccess {
	# Who gets the device status (the same rule as the service): Everyone with Client; with TerminalServer AdminOnly only for exactly
	# that value (case is ignored), otherwise Off (default, empty, any other value).
	param([string]$Mode, [AllowNull()][AllowEmptyString()][string]$Value)
	if ($Mode -cne 'TerminalServer') { return 'Everyone' }
	if ("$Value".Trim() -ieq 'AdminOnly') { return 'AdminOnly' }
	return 'Off'
}

function Test-SelfXElevatedAdministrator {
	# True when this process runs with the elevated token of a member of Administrators (S-1-5-32-544). The filtered token of an
	# administrator without elevation (UAC) is false, as in the service.
	try {
		$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
		return $principal.IsInRole((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
	} catch { return $false }
}

function Get-SelfXViewScope {
	# What the window, the status icon, the ticket and the text for Copilot show to this user:
	#   TerminalServer = the kinds of connection (LAN, Wi-Fi, mobile, VPN) are left out (they do not matter on a terminal server);
	#   ServerRows     = rows of the class Server (device, Windows, management, addresses): always with Client, with TerminalServer only
	#                    for elevated administrators;
	#   Health         = device status: Everyone, or AdminOnly and an elevated administrator. The service checks this on its own.
	param([string]$Mode, [string]$HealthAccess, [bool]$IsAdmin)
	$terminalServer = $Mode -ceq 'TerminalServer'
	return [pscustomobject]@{
		TerminalServer = $terminalServer
		ServerRows     = (-not $terminalServer) -or $IsAdmin
		Health         = ($HealthAccess -ceq 'Everyone') -or ($HealthAccess -ceq 'AdminOnly' -and $IsAdmin)
	}
}

function Get-SelfXRemediationClassification {
	# Script name (lower case) -> $true when every remediation of Health_Config.xml with this Script is classified Show.
	# An unreadable file gives an empty table: with TerminalServer no repair is then offered.
	param([Parameter(Mandatory = $true)][string]$HealthConfigPath)
	$table = @{}
	try { $document = Read-SelfXEnvironmentXml -Path $HealthConfigPath }
	catch { return $table }
	foreach ($remediation in @($document.SelectNodes('/HealthConfig/Remediations/Remediation'))) {
		$key = "$($remediation.GetAttribute('Script'))".Trim().ToLowerInvariant()
		if (-not $key) { continue }
		$shown = Test-SelfXShownInEnvironment 'TerminalServer' $remediation.GetAttribute('TerminalServer')
		if ($table.ContainsKey($key)) { $table[$key] = $table[$key] -and $shown } else { $table[$key] = $shown }
	}
	return $table
}

function Test-SelfXRemediationOffered {
	# $true when the repair with this Script is offered in the mode (Client: always; TerminalServer: only when classified Show).
	param([string]$Mode, [string]$Script, [hashtable]$Classification)
	if ($Mode -cne 'TerminalServer') { return $true }
	$key = "$Script".Trim().ToLowerInvariant()
	return [bool]($Classification -and $Classification.ContainsKey($key) -and $Classification[$key])
}
