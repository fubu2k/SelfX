<#
.SYNOPSIS
    Mode of SelfX (Client or TerminalServer, from Windows) and the TerminalServer classification of actions and repairs.

.DESCRIPTION
    Shared by the window (Self_X.ps1), the status icon (SelfX_Tray.ps1) and the health collection (HealthStatus.ps1, run as
    SYSTEM by the service). Dot-sourcing defines functions only.
    The mode comes from Windows, never from a setting: ProductType WinNT (Windows 11) = Client; ServerNT (Windows Server, also
    Windows Enterprise multi-session) and LanmanNT (domain controller) = TerminalServer; a value that cannot be read or is unknown =
    TerminalServer, marked as not valid so that the caller can log it (fail closed). The value is
    HKLM\SYSTEM\CurrentControlSet\Control\ProductOptions\ProductType, which every user can read; the service reads the same product
    type with RtlGetVersion. An Environment_Mode element in Tool_Config.xml (earlier build) is ignored.
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
    3.1.0    2026-11-28  fubu2k               The mode comes from the product type of Windows (Get-SelfXWindowsProductType); Environment_Mode of
                                              Tool_Config.xml is no longer read
#>

function ConvertTo-SelfXEnvironmentMode {
	# Product type of Windows -> Mode = 'Client' or 'TerminalServer'. Only WinNT (case is ignored) is Client. ServerNT and LanmanNT are
	# TerminalServer; an empty or unknown value is TerminalServer with Valid = $false (fail closed).
	param([AllowNull()][AllowEmptyString()][string]$ProductType)
	$text = "$ProductType".Trim()
	if ($text -ieq 'WinNT') { return [pscustomobject]@{ Mode = 'Client'; Valid = $true } }
	return [pscustomobject]@{ Mode = 'TerminalServer'; Valid = ($text -ieq 'ServerNT' -or $text -ieq 'LanmanNT') }
}

function Get-SelfXWindowsProductType {
	# ProductType of the running Windows (WinNT, ServerNT or LanmanNT); '' when it cannot be read.
	try { return [string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions' -Name ProductType -ErrorAction Stop).ProductType }
	catch { return '' }
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
	# The mode of this Windows (see ConvertTo-SelfXEnvironmentMode). No parameter: nothing a user writes can change it.
	return ConvertTo-SelfXEnvironmentMode (Get-SelfXWindowsProductType)
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
