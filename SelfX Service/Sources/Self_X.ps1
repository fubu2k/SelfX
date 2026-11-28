<#
.SYNOPSIS
    SelfX (Self fix) - self-service troubleshooting window for the signed-in user.

.DESCRIPTION
    Modern, resizable window with three areas in the navigation bar on the left:
      - Troubleshooting   : catalogue of known issues (Issues_List.xml) in a simplified or detailed view.
                            The user selects an issue and runs the matching repair script from Scripts_to_run:
                              - Actions with Context "User" run directly as the signed-in user; SelfX watches the
                                script until it has ended and shows its result.
                              - Actions with Context "System" are sent to the local SelfX service
                                (SelfXService.exe, runs as SYSTEM), which only accepts scripts listed in the
                                installed catalogue. They are marked with a shield icon.
      - Device status     : status cards of the local health checks (HealthStatus.ps1 in the service) with
                            "Fix" (administrator-configured repair) and "Check again". The status of the
                            background checks of the service is shown immediately (STATUS request).
      - System information: read-only device details for the support team (SystemInfo.ps1). The last
                            collected information is shown immediately from a per-user cache and updated
                            in the background. Copy and export include the status.
    Buttons are icons with explaining tooltips. A help dialog shows the support contacts (hours, phone,
    mail, Teams chat, website / ticket system), the settings dialog switches the language, the theme and
    the tray icon.

    Everything is installed locally; the window works without any network connection.
    Settings and branding (company logo, colors) come from Tool_Config.xml (Branding.ps1). All texts are
    loaded from Languages\<culture>.xml (Localization.ps1): in the language chosen by the user in the
    settings (HKCU\Software\SelfX\Language, unless Show_Language_Setting is False), otherwise in
    Tool_Language or the Windows display language of the user. German (base language) is used when the language is not
    available; English is the fallback for missing texts. After a change of the language SelfX restarts itself on the same page. Only one window runs
    per user: starting SelfX again (for example from the tray icon) brings the open window to the front.

.PARAMETER Page
    Page to show: Troubleshooting (default), Status, SystemInfo or SendLogs (opens the confirmation of the
    "send device logs" action). Used by the tray icon.

.NOTES
    Name    : Self_X.ps1
    Package : SelfX Service
    Context : User (started from the SelfX shortcut or the tray icon)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX, http://www.systanddeploy.com)
    2.8.17   2026-11-23  fubu2k               Copilot Chat: optional clearing of the clipboard after a time (Copilot_Clear_Clipboard, Copilot_Clear_Clipboard_Seconds)
    2.8.18   2026-11-23  fubu2k               Calmer look: larger radii and spacing, three-step hint, status chips with icon, help buttons (ticket, Copilot) in the navigation
    2.8.26   2026-11-24  fubu2k               Optional wiki button in the navigation (Wiki_Enabled, Wiki_Url, Wiki_Name)
    2.8.27   2026-11-27  fubu2k               The displayed version is ToolVersion of SelfX.Code.json (the version is a property of the code), no longer Tool_Version of Tool_Config.xml
    3.1.0    2026-11-27  fubu2k               Code and configuration in two folders (App, Config): settings, catalog, ticket routing, network targets,
                                              images and own scripts and language files are resolved by SelfXPaths.ps1
    3.1.0    2026-11-27  fubu2k               Text overrides: Config\Texts\<culture>.xml replaces single texts of the language file (Localization.ps1)
    3.1.0    2026-11-27  fubu2k               System information: status symbol (OK, warning, error) at the end of a row with a status; used by the connection check
    3.1.0    2026-11-27  fubu2k               Repairs with two parts (Health_Config.xml UserScript): one confirmation, the part of the user, then the SYSTEM part
                                              through the service; "Free up space" lists what is deleted and shows the free space before and after;
                                              such repairs are never part of "Fix all problems"
    3.1.0    2026-11-27  fubu2k               Environment_Mode TerminalServer (Tool_Config.xml): actions and repairs not classified TerminalServer Show are not
                                              shown (SelfXEnvironment.ps1); a refusal of the service (ERROR TerminalServer) has its own message
    3.1.0    2026-11-28  fubu2k               TerminalServer_Health (Off or AdminOnly): page Device status only when the user may see it; system information,
                                              ticket and text for Copilot without rows of the class Server for normal users and without the
                                              kinds of connection (Get-SelfXViewScope)
    3.1.0    2026-11-28  fubu2k               The mode comes from Windows (Get-SelfXEnvironmentMode), not from Environment_Mode of Tool_Config.xml
#>
param(
	[ValidateSet('', 'Troubleshooting', 'Status', 'SystemInfo', 'SendLogs')]
	[string]$Page = ''
)

# Work in the code folder (App). The configuration (Config) is resolved by SelfXPaths.ps1, never relative to the working folder.
$Global:Current_Folder = Split-Path $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Current_Folder
[Environment]::CurrentDirectory = $Current_Folder

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

#******************************************************************************
# Per-user settings (theme, tray icon, window size) in HKCU\Software\SelfX
#******************************************************************************
$Global:SelfX_UserKey = 'HKCU:\Software\SelfX'

Function Get-SelfXUserSetting
	{
		param([string]$Name, $Default = $null)
		Try
			{
				If(-not (Test-Path -LiteralPath $Global:SelfX_UserKey)) { return $Default }
				$Value = (Get-ItemProperty -LiteralPath $Global:SelfX_UserKey -Name $Name -ErrorAction Stop).$Name
				If(($null -ne $Value) -and ("$Value" -ne '')) { return $Value }
			}
		Catch {}
		return $Default
	}

Function Set-SelfXUserSetting
	{
		param([string]$Name, $Value)
		Try
			{
				If(-not (Test-Path -LiteralPath $Global:SelfX_UserKey)) { New-Item -Path $Global:SelfX_UserKey -Force | Out-Null }
				Set-ItemProperty -LiteralPath $Global:SelfX_UserKey -Name $Name -Value $Value
			}
		Catch {}
	}

#******************************************************************************
# One window per user: a second start shows the open window (and the requested page)
#******************************************************************************
$Global:SelfX_GuiMutex = New-Object System.Threading.Mutex($false, 'Local\SelfX.Gui')
$IsFirstInstance = $false
Try { $IsFirstInstance = $Global:SelfX_GuiMutex.WaitOne(0) } Catch [System.Threading.AbandonedMutexException] { $IsFirstInstance = $true }
$Global:SelfX_ShowEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\SelfX.Gui.Show')
If(-not $IsFirstInstance)
	{
		Set-SelfXUserSetting 'ShowPage' $(If($Page) { $Page } Else { 'Activate' })
		[void]$Global:SelfX_ShowEvent.Set()
		exit
	}

#******************************************************************************
# Own taskbar identity: without it Windows groups the window with powershell.exe and shows the PowerShell
# icon. With an own AppUserModelID the taskbar shows the window icon (SelfX logo), and a pinned SelfX
# starts SelfX.exe again (relaunch properties of the window).
#******************************************************************************
$Global:SelfX_AppId = 'SelfX.SelfService'
Try
	{
		Add-Type -Namespace SelfXGui -Name Taskbar -ErrorAction Stop -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

[DllImport("shell32.dll")]
static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPropertyStore
{
    int GetCount(out uint count);
    int GetAt(uint index, out PropertyKey key);
    int GetValue(ref PropertyKey key, out PropVariant value);
    int SetValue(ref PropertyKey key, ref PropVariant value);
    int Commit();
}

[StructLayout(LayoutKind.Sequential, Pack = 4)]
struct PropertyKey { public Guid FormatId; public uint PropertyId; }

[StructLayout(LayoutKind.Sequential)]
struct PropVariant { public ushort VarType; public ushort Reserved1; public ushort Reserved2; public ushort Reserved3; public IntPtr Value; public IntPtr Value2; }

static readonly Guid AppUserModelKeys = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

static void SetText(IPropertyStore store, uint id, string text)
{
    PropertyKey key = new PropertyKey { FormatId = AppUserModelKeys, PropertyId = id };
    PropVariant value = new PropVariant { VarType = 31 };  // VT_LPWSTR
    value.Value = Marshal.StringToCoTaskMemUni(text);
    try { store.SetValue(ref key, ref value); } finally { Marshal.FreeCoTaskMem(value.Value); }
}

// Sets the AppUserModelID and the relaunch command, name and icon of a window (used when it is pinned).
public static void SetWindowIdentity(IntPtr hwnd, string appId, string command, string name, string icon)
{
    Guid iid = typeof(IPropertyStore).GUID;
    IPropertyStore store;
    if (SHGetPropertyStoreForWindow(hwnd, ref iid, out store) != 0 || store == null) return;
    try
    {
        if (!string.IsNullOrEmpty(command))
        {
            SetText(store, 2, command);   // System.AppUserModel.RelaunchCommand
            SetText(store, 4, name);      // System.AppUserModel.RelaunchDisplayNameResource
            if (!string.IsNullOrEmpty(icon)) SetText(store, 3, icon);  // System.AppUserModel.RelaunchIconResource
        }
        SetText(store, 5, appId);         // System.AppUserModel.ID
        store.Commit();
    }
    finally { Marshal.ReleaseComObject(store); }
}
'@
		# Before the first window is created, so the taskbar never shows the PowerShell button.
		[void][SelfXGui.Taskbar]::SetCurrentProcessExplicitAppUserModelID($Global:SelfX_AppId)
	}
Catch {}

# SelfX Service runs fully offline: catalog and scripts are installed locally and never downloaded.
# Client and helper scripts are also passed as text to background runspaces (no execution policy check there).
$Global:SelfXClient_Script = Get-Content -LiteralPath "$Current_Folder\SelfXServiceClient.ps1" -Raw
$Global:SelfXSupportReport_Script = Get-Content -LiteralPath "$Current_Folder\SupportReport.ps1" -Raw
# Paths of the configuration (folder Config next to App), the images and the own scripts of the company
. "$Current_Folder\SelfXPaths.ps1"
. "$Current_Folder\SelfXEnvironment.ps1"
. "$Current_Folder\SelfXServiceClient.ps1"
. "$Current_Folder\Branding.ps1"
. "$Current_Folder\Localization.ps1"
. "$Current_Folder\SelfXNetwork.ps1"
# Ticket e-mail (functions only, nothing runs when they are loaded)
. "$Current_Folder\SupportReport.ps1"
. "$Current_Folder\TicketMail.ps1"
. "$Current_Folder\SupportLinks.ps1"
. "$Current_Folder\TicketSend.ps1"
. "$Current_Folder\SystemInfo.ps1"
# Optional hand-over to Copilot Chat (functions only, nothing runs when they are loaded)
. "$Current_Folder\CopilotPrompt.ps1"
. "$Current_Folder\CopilotFacts.ps1"
. "$Current_Folder\CopilotClipboard.ps1"
# Logging of the window to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1)
. "$Current_Folder\SelfXLog.ps1"
Initialize-SelfXLog -Component 'SelfX'
$Global:SysInfo_Script = $Global:SelfXClient_Script + "`r`n" + (Get-Content -LiteralPath "$Current_Folder\SelfXNetwork.ps1" -Raw) + "`r`n" + (Get-Content -LiteralPath "$Current_Folder\SystemInfo.ps1" -Raw)

#******************************************************************************
# Settings (Tool_Config.xml), language and action catalogue
#******************************************************************************
$Config_XML = New-Object System.Xml.XmlDocument
$Config_XML.XmlResolver = $null
$XmlSettings = New-Object System.Xml.XmlReaderSettings
$XmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
$XmlSettings.XmlResolver = $null
$XmlReader = [System.Xml.XmlReader]::Create((Get-SelfXConfigPath -Name 'Tool_Config.xml' -CodeRoot $Current_Folder), $XmlSettings)
Try { $Config_XML.Load($XmlReader) } Finally { $XmlReader.Dispose() }
$GUI_Config = $Config_XML.GUI_Config

# Returns a setting of Tool_Config.xml, or Default when it is missing or empty
Function Get-SelfXText($Name, $Default)
	{
		$Value = $GUI_Config.$Name
		If([string]::IsNullOrWhiteSpace($Value)) { return $Default }
		return $Value.Trim()
	}

Function Get-SelfXConfigValue
	{
		param([string]$Name, [string]$Default)
		return (Get-SelfXText $Name $Default)
	}

# Language: choice of the user (SelfX > Settings), else Tool_Language (default de; Auto = Windows display language), German as base language, English as fallback for missing texts
$Show_Language_Setting = (Get-SelfXText "Show_Language_Setting" "True") -eq 'True'
# Bundled language files (App\Languages) first, then own language files of the company (Config\Languages).
$Global:SelfX_LanguageFolder = Get-SelfXLanguageFolders -CodeRoot $Current_Folder
$Global:SelfX_Language_Setting = Resolve-SelfXLanguageSetting -ConfigLanguage (Get-SelfXText "Tool_Language" "de") `
	-UserLanguage ([string](Get-SelfXUserSetting 'Language' '')) -AllowUserChoice $Show_Language_Setting -LanguageFolder $Global:SelfX_LanguageFolder
# Optional text overrides of the company (Config\Texts\<culture>.xml) replace single texts of the bundled language file.
$SelfX_UI_Language = Initialize-SelfXLanguage -LanguageFolder $Global:SelfX_LanguageFolder -Language $Global:SelfX_Language_Setting -TextOverrideFolder (Get-SelfXTextOverrideFolder -CodeRoot $Current_Folder)

# Action catalogue: base data and English texts. Names, categories and messages are translated per language.
$List_Issues_XML = New-Object System.Xml.XmlDocument
$List_Issues_XML.XmlResolver = $null
$XmlSettings = New-Object System.Xml.XmlReaderSettings
$XmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
$XmlSettings.XmlResolver = $null
$XmlReader = [System.Xml.XmlReader]::Create((Get-SelfXConfigPath -Name 'Issues_List.xml' -CodeRoot $Current_Folder), $XmlSettings)
Try { $List_Issues_XML.Load($XmlReader) } Finally { $XmlReader.Dispose() }
$Global:SelfX_Quick_Actions = @(Get-SelfXLocalizedActions -Catalog $List_Issues_XML -Section 'Quick_Solution')
$Global:SelfX_Detailed_Actions = @(Get-SelfXLocalizedActions -Catalog $List_Issues_XML -Section 'Detailed_Solution')
# Link actions (Context Link) open an https address from Tool_Config.xml (key Link_<Name>). An action whose setting is empty,
# "Off" or not a valid https address is not shown (the reason is logged).
Function Select-SelfXLinkActions
	{
		param($Actions)
		foreach($Action in $Actions)
			{
				If($Action.Context -ne 'Link') { $Action; continue }
				$Link = Resolve-SelfXCatalogLink -Key $Action.Link -Value (Get-SelfXText $Action.Link '')
				If($Link.State -eq 'Ok') { $Action; continue }
				If($Link.State -ne 'Off') { Write-SelfXLog "Action '$($Action.Id)' is not shown: setting '$($Action.Link)' is $($Link.State) (an https address is required)." 'Warning' }
			}
	}
$Global:SelfX_Quick_Actions = @(Select-SelfXLinkActions $Global:SelfX_Quick_Actions)
$Global:SelfX_Detailed_Actions = @(Select-SelfXLinkActions $Global:SelfX_Detailed_Actions)
# An action with <Requires>DomainJoined</Requires> is shown only on a domain or hybrid joined device (Win32_ComputerSystem.PartOfDomain).
# Only a clear "not joined" hides it: if the state cannot be read, the action stays visible (its script checks again and ends with exit 3).
Function Select-SelfXRequirementActions
	{
		param($Actions, $DomainJoined)
		foreach($Action in $Actions)
			{
				If($Action.Requires -ne 'DomainJoined' -or $DomainJoined -ne $false) { $Action; continue }
				Write-SelfXLog "Action '$($Action.Id)' is not shown: it needs a domain or hybrid joined device."
			}
	}
$SelfX_Needs_Domain = @(@($Global:SelfX_Quick_Actions) + @($Global:SelfX_Detailed_Actions) | Where-Object { $_.Requires -eq 'DomainJoined' }).Count -gt 0
$SelfX_Domain_Joined = $null
If($SelfX_Needs_Domain)
	{
		Try { $SelfX_Domain_Joined = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain }
		Catch { Write-SelfXLog "Domain membership could not be read: $($_.Exception.Message)" 'Warning' }
	}
$Global:SelfX_Quick_Actions = @(Select-SelfXRequirementActions $Global:SelfX_Quick_Actions $SelfX_Domain_Joined)
$Global:SelfX_Detailed_Actions = @(Select-SelfXRequirementActions $Global:SelfX_Detailed_Actions $SelfX_Domain_Joined)
# Mode from Windows (SelfXEnvironment.ps1): on Windows Server and other session hosts (TerminalServer) only actions classified
# <TerminalServer>Show</TerminalServer> are shown; they affect only the own session or profile. The service refuses the other
# System actions for every caller, so hiding them here keeps the list clear; it is not the security boundary.
$Global:SelfX_Environment = Get-SelfXEnvironmentMode
If(-not $Global:SelfX_Environment.Valid) { Write-SelfXLog "The product type of Windows cannot be read; SelfX works as on a terminal server." 'Warning' }
Function Select-SelfXEnvironmentActions
	{
		param($Actions, [string]$Mode)
		foreach($Action in $Actions)
			{
				If(Test-SelfXShownInEnvironment $Mode $Action.TerminalServer) { $Action; continue }
				Write-SelfXLog "Action '$($Action.Id)' is not shown: it is not classified TerminalServer Show (terminal server)."
			}
	}
$Global:SelfX_Quick_Actions = @(Select-SelfXEnvironmentActions $Global:SelfX_Quick_Actions $Global:SelfX_Environment.Mode)
$Global:SelfX_Detailed_Actions = @(Select-SelfXEnvironmentActions $Global:SelfX_Detailed_Actions $Global:SelfX_Environment.Mode)
# Repairs of the device status: with TerminalServer only those classified TerminalServer="Show" in Health_Config.xml. The health
# collection clears the others too; this second check also covers a status cache written before the mode was changed.
$Global:SelfX_RemediationClassification = Get-SelfXRemediationClassification -HealthConfigPath (Get-SelfXConfigPath -Name 'Health_Config.xml' -CodeRoot $Current_Folder)
# Mode TerminalServer: the device status and the server rows describe the server, not the place of work of the user.
# TerminalServer_Health (Off or AdminOnly) decides about the device status; normal users see only rows of the class User. The service
# checks the device status on its own (HEALTH, STATUS); the rest is collected with the rights of the user, so hiding it keeps the view
# and the ticket lean, it is not a security boundary.
$Global:SelfX_HealthAccess = ConvertTo-SelfXHealthAccess $Global:SelfX_Environment.Mode (Get-SelfXText 'TerminalServer_Health' '')
$Global:SelfX_View = Get-SelfXViewScope -Mode $Global:SelfX_Environment.Mode -HealthAccess $Global:SelfX_HealthAccess -IsAdmin (Test-SelfXElevatedAdministrator)
If($Global:SelfX_View.TerminalServer) { Write-SelfXLog "Terminal server: device status $(If($Global:SelfX_View.Health) { 'shown' } Else { 'not shown' }) (TerminalServer_Health $($Global:SelfX_HealthAccess)), server rows $(If($Global:SelfX_View.ServerRows) { 'shown' } Else { 'not shown' })." }

# The version of the code: ToolVersion of SelfX.Code.json in the install folder (Tool_Config.xml no longer carries it; an old Tool_Version
# element there is ignored). Display only: a missing or unreadable list shows '?' and is logged, it never stops the window.
Function Get-SelfXToolVersion
	{
		param([string]$InstallFolder)
		Try
			{
				$ListPath = Join-Path $InstallFolder 'SelfX.Code.json'
				$Item = Get-Item -LiteralPath $ListPath -Force -ErrorAction Stop
				If($Item.PSIsContainer -or $Item.Length -gt 1048576) { return $null }
				$Version = "$((Get-Content -LiteralPath $ListPath -Raw | ConvertFrom-Json).ToolVersion)".Trim()
				If($Version -match '^[0-9A-Za-z.\-]{1,30}\z') { return $Version }
			}
		Catch {}
		return $null
	}
$Tool_Version = Get-SelfXToolVersion $Current_Folder
If(-not $Tool_Version)
	{
		$Tool_Version = '?'
		Write-SelfXLog 'The version could not be read from SelfX.Code.json.' 'Warning'
	}
Write-SelfXLog "SelfX $Tool_Version opened: language $($SelfX_UI_Language.Culture) (setting $Global:SelfX_Language_Setting), page '$Page'."
$Tool_Name = Get-SelfXText "Tool_Name" "SelfX"
$Support_Phone_number = Get-SelfXText "Support_Phone_number" ""
$Support_Mail = Get-SelfXText "Support_Mail" ""
# Ticket by e-mail (off by default): recipient only from the configuration, Ticket_Mail empty = Support_Mail
$Ticket_Mail = (Get-SelfXText "Ticket_Mail" "").Trim()
If(-not $Ticket_Mail) { $Ticket_Mail = "$Support_Mail".Trim() }
$Ticket_Tag = (Get-SelfXText "Ticket_Subject_Tag" "SelfX").Trim()
$Ticket_Available = ((Get-SelfXText "Ticket_Enabled" "False") -eq 'True') -and (Test-SelfXTicketAddress $Ticket_Mail)
# Routing to the support units (Ticket_Config.xml); a file that cannot be used leaves the default recipient
$Ticket_Routing = $null
If($Ticket_Available)
	{
		Try
			{
				$Ticket_Routing = Read-SelfXTicketConfig -Path (Get-SelfXConfigPath -Name 'Ticket_Config.xml' -CodeRoot $Current_Folder)
				foreach($Ticket_Error in $Ticket_Routing.Errors) { Write-SelfXLog "Ticket_Config.xml: $Ticket_Error" 'Warning' }
			}
		Catch { Write-SelfXLog "Ticket_Config.xml could not be read: $($_.Exception.Message)" 'Warning' }
	}
# Company wiki (off by default): the button opens the configured https address in the web browser (SupportLinks.ps1)
$Wiki = Get-SelfXWikiSettings -Enabled (Get-SelfXText "Wiki_Enabled" "False") -Url (Get-SelfXText "Wiki_Url" "") -Name (Get-SelfXText "Wiki_Name" "")
foreach($Wiki_Warning in $Wiki.Warnings) { Write-SelfXLog $Wiki_Warning 'Warning' }
# Hand-over to Copilot Chat (off by default): only an https address from the configuration is opened, the user pastes the text
$Copilot_Url = (Get-SelfXText "Copilot_Url" "https://copilot.cloud.microsoft").Trim()
$Copilot_Available = ((Get-SelfXText "Copilot_Enabled" "False") -eq 'True') -and (Test-SelfXCopilotUrl $Copilot_Url)
If(((Get-SelfXText "Copilot_Enabled" "False") -eq 'True') -and -not $Copilot_Available) { Write-SelfXLog 'Copilot_Url is not a valid https address: the Copilot Chat button is not shown.' 'Warning' }
$Copilot_Audience = If((Get-SelfXText "Copilot_Audience" "User") -eq 'Admin') { 'Admin' } Else { 'User' }
$Copilot_AppNames = (Get-SelfXText "Copilot_Include_AppNames" "True") -eq 'True'
# Optional: empty the clipboard after a time, if the text of this copy is still on it (off by default)
$Copilot_ClearClipboard = (Get-SelfXText "Copilot_Clear_Clipboard" "False") -eq 'True'
$Copilot_ClearSetting = ConvertTo-SelfXClipboardClearSeconds (Get-SelfXText "Copilot_Clear_Clipboard_Seconds" "180")
$Copilot_ClearSeconds = $Copilot_ClearSetting.Seconds
If($Copilot_ClearClipboard -and -not $Copilot_ClearSetting.Valid) { Write-SelfXLog 'Copilot_Clear_Clipboard_Seconds is not a whole number from 30 to 600: 180 seconds are used.' 'Warning' }
$Run_Solution_Text = Get-SelfXString 'Warning_Click_Run_Solution_Text'
$Run_Explanation_Text = Get-SelfXString 'Warning_Click_Run_Explanation_Text'
$Service_Running_Text = Get-SelfXString 'Service_Running_Text'
$Service_Unavailable_Text = Get-SelfXString 'Service_Unavailable_Text'
$Service_Busy_Text = Get-SelfXString 'Service_Busy_Text'
$Service_OtherSessions_Text = Get-SelfXString 'Service_OtherSessions_Text'
$Global:SysInfo_Texts = Get-SelfXSystemInfoTexts
$SysInfo_Test_Host = Get-SelfXText "SystemInfo_Internet_Test_Host" "www.msftconnecttest.com"
$SysInfo_Test_Port = [int](Get-SelfXText "SystemInfo_Internet_Test_Port" "80")

# Icons (Segoe Fluent Icons / Segoe MDL2 Assets) of the categories, status checks and information sections
$Global:SelfX_CategoryGlyphs = @{ Teams = 0xE8BD; Office = 0xE8A5; OneDrive = 0xE753; Outlook = 0xE715; Device = 0xE7F4; Intune = 0xE821; Browser = 0xE774; Store = 0xE719 }
$Global:SelfX_HealthGlyphs = @{ IME = 0xE821; Defender = 0xEA18; Compliance = 0xE9D5; Applications = 0xE71D; Disk = 0xEDA2; BitLocker = 0xE72E
	PendingReboot = 0xE777; Updates = 0xE895; Service = 0xE713; Custom = 0xE9D9; Collection = 0xE7BA }
$Global:SelfX_InfoGlyphs = @{}
# Category names are the localized labels of SystemInfo.ps1 (defaults overlaid with the language file).
Set-SelfXInfoText $Global:SysInfo_Texts
foreach($Pair in @(@('Category_Device', 0xE7F4), @('Category_Windows', 0xE770), @('Category_User', 0xE77B), @('Category_Network', 0xE701), @('Category_Report', 0xE9F9)))
	{
		$Global:SelfX_InfoGlyphs[[string](Get-SelfXInfoText $Pair[0])] = [string][char]$Pair[1]
	}

#******************************************************************************
# Shared styles of the main window and the dialogs (colors come from the theme dictionary)
#******************************************************************************
$Global:SelfX_StylesXaml = @'
    <FontFamily x:Key="Icons">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>
    <Style x:Key="Glyph" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="{StaticResource Icons}"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToolTip">
            <Border Background="{DynamicResource Surface}" BorderBrush="{DynamicResource Stroke}" BorderThickness="1" CornerRadius="10" Padding="12,9" MaxWidth="360">
              <TextBlock Text="{Binding Content, RelativeSource={RelativeSource TemplatedParent}}" TextWrapping="Wrap" FontSize="12" Foreground="{DynamicResource TextPrimary}"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource Surface}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Stroke}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="14"/>
    </Style>
    <Style x:Key="BaseButton" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="18,9"/>
      <Setter Property="MinHeight" Value="40"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="Background" Value="{DynamicResource SurfaceAlt}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Stroke}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="ToolTipService.InitialShowDelay" Value="350"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="{DynamicResource RunButton}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource RunButton}"/>
      <Setter Property="Foreground" Value="{DynamicResource RunButtonFg}"/>
    </Style>
    <Style x:Key="IconButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="MinHeight" Value="0"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource HoverBg}"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="OutlineIconButton" TargetType="Button" BasedOn="{StaticResource IconButton}">
      <Setter Property="Background" Value="{DynamicResource SurfaceAlt}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Stroke}"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style x:Key="AccentIconButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="MinHeight" Value="0"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Background" Value="{DynamicResource RunButton}"/>
      <Setter Property="Foreground" Value="{DynamicResource RunButtonFg}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="Bd" Background="{TemplateBinding Background}" CornerRadius="20">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.7"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ChromeButton" TargetType="Button" BasedOn="{StaticResource IconButton}">
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Width" Value="42"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="MinHeight" Value="0"/>
      <Setter Property="Foreground" Value="{DynamicResource TitleBarFg}"/>
    </Style>
    <Style x:Key="ToolTile" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Width" Value="136"/>
      <Setter Property="MinHeight" Value="84"/>
      <Setter Property="Margin" Value="0,0,10,10"/>
      <Setter Property="Padding" Value="8,10"/>
      <Setter Property="Background" Value="{DynamicResource Surface}"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
    </Style>
    <Style x:Key="NavItem" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="Margin" Value="0,2"/>
      <Setter Property="ToolTipService.InitialShowDelay" Value="350"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Name="Bd" Background="Transparent" CornerRadius="12" Height="46">
              <Grid>
                <Rectangle Name="Ind" Width="3" Height="16" RadiusX="1.5" RadiusY="1.5" Fill="{DynamicResource Accent}" HorizontalAlignment="Left" Visibility="Hidden"/>
                <ContentPresenter Margin="12,0,8,0" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource HoverBg}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource SelectedBg}"/>
                <Setter TargetName="Ind" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Pill" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Name="Bd" CornerRadius="18" Padding="16,7" Background="{DynamicResource SurfaceAlt}" BorderBrush="{DynamicResource Stroke}" BorderThickness="1">
              <ContentPresenter TextElement.Foreground="{TemplateBinding Foreground}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource HoverBg}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Accent}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter Property="Foreground" Value="{DynamicResource AccentFg}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Segment" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border Name="Bd" CornerRadius="9" Padding="16,7" Background="Transparent">
              <ContentPresenter TextElement.Foreground="{TemplateBinding Foreground}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource HoverBg}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Surface}"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <DockPanel Background="Transparent">
              <Border Name="Track" DockPanel.Dock="Left" Width="40" Height="20" CornerRadius="10" BorderThickness="1"
                      BorderBrush="{DynamicResource TextSecondary}" Background="Transparent" VerticalAlignment="Top" Margin="0,1,10,0">
                <Ellipse Name="Knob" Width="12" Height="12" Margin="4,0" HorizontalAlignment="Left" Fill="{DynamicResource TextSecondary}"/>
              </Border>
              <ContentPresenter VerticalAlignment="Center"/>
            </DockPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="{DynamicResource Accent}"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Fill" Value="{DynamicResource AccentFg}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border CornerRadius="3" Margin="3,2" Background="{DynamicResource ScrollThumb}"/>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SubText" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="PageTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="28"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontFamily" Value="Segoe UI Variable Display, Segoe UI"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
'@

# Item templates of the main window: action row, status card and information card.
$Global:SelfX_TemplatesXaml = @'
    <DataTemplate x:Key="ActionTemplate">
      <Border Name="Row" Style="{StaticResource Card}" Padding="16,14" Margin="0,0,0,10">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Border Width="46" Height="46" CornerRadius="13" Background="{DynamicResource AccentSoft}" VerticalAlignment="Center">
            <TextBlock Style="{StaticResource Glyph}" Text="{Binding Glyph}" FontSize="20" Foreground="{DynamicResource AccentText}"/>
          </Border>
          <StackPanel Grid.Column="1" Margin="16,0,12,0" VerticalAlignment="Center">
            <TextBlock Text="{Binding Name}" FontSize="15" FontWeight="SemiBold" TextWrapping="Wrap"/>
            <TextBlock Text="{Binding ShortExplanation}" Foreground="{DynamicResource TextSecondary}" Margin="0,3,0,0" TextWrapping="Wrap" TextTrimming="CharacterEllipsis" MaxHeight="40"/>
          </StackPanel>
          <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock Name="CategoryText" Text="{Binding Category}" Foreground="{DynamicResource TextSecondary}" FontSize="12" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <TextBlock Name="RunningText" Text="{DynamicResource Str_Action_Running}" Foreground="{DynamicResource AccentText}" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,10,0" Visibility="Collapsed"/>
            <Border Name="Shield" Visibility="Collapsed" Background="Transparent" ToolTip="{DynamicResource Str_Shield}" Margin="0,0,6,0" Padding="4">
              <TextBlock Style="{StaticResource Glyph}" Text="&#xEA18;" FontSize="15" Foreground="{DynamicResource AccentText}"/>
            </Border>
            <Button Tag="Info" Style="{StaticResource IconButton}" ToolTip="{DynamicResource Str_Tooltip_Info}" Margin="0,0,6,0">
              <TextBlock Style="{StaticResource Glyph}" Text="&#xE946;" FontSize="16" Foreground="{DynamicResource InfoIcon}"/>
            </Button>
            <!-- While the action runs: rotating icon instead of the play icon, button locked (Running of the action). -->
            <Button Name="RunButton" Tag="Run" Style="{StaticResource AccentIconButton}" ToolTip="{DynamicResource Str_Tooltip_Run}" ToolTipService.ShowOnDisabled="True">
              <Grid>
                <TextBlock Name="RunGlyph" Style="{StaticResource Glyph}" Text="&#xE768;" FontSize="14" Margin="2,0,0,0" Foreground="{DynamicResource RunButtonFg}"/>
                <TextBlock Name="RunSpin" Style="{StaticResource Glyph}" Text="&#xE895;" FontSize="15" Foreground="{DynamicResource RunButtonFg}" Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
                  <TextBlock.RenderTransform><RotateTransform/></TextBlock.RenderTransform>
                </TextBlock>
              </Grid>
            </Button>
          </StackPanel>
        </Grid>
      </Border>
      <DataTemplate.Triggers>
        <DataTrigger Binding="{Binding Context}" Value="System"><Setter TargetName="Shield" Property="Visibility" Value="Visible"/></DataTrigger>
        <Trigger SourceName="Row" Property="IsMouseOver" Value="True"><Setter TargetName="Row" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>
        <DataTrigger Binding="{Binding Running}" Value="True">
          <Setter TargetName="RunGlyph" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="RunSpin" Property="Visibility" Value="Visible"/>
          <Setter TargetName="RunButton" Property="IsEnabled" Value="False"/>
          <Setter TargetName="RunButton" Property="ToolTip" Value="{DynamicResource Str_Action_Running}"/>
          <Setter TargetName="RunningText" Property="Visibility" Value="Visible"/>
          <Setter TargetName="CategoryText" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="Row" Property="BorderBrush" Value="{DynamicResource Accent}"/>
          <DataTrigger.EnterActions>
            <BeginStoryboard Name="RunSpinStory">
              <Storyboard><DoubleAnimation Storyboard.TargetName="RunSpin" Storyboard.TargetProperty="(UIElement.RenderTransform).(RotateTransform.Angle)" From="0" To="360" Duration="0:0:1.2" RepeatBehavior="Forever"/></Storyboard>
            </BeginStoryboard>
          </DataTrigger.EnterActions>
          <DataTrigger.ExitActions><StopStoryboard BeginStoryboardName="RunSpinStory"/></DataTrigger.ExitActions>
        </DataTrigger>
      </DataTemplate.Triggers>
    </DataTemplate>

    <DataTemplate x:Key="StatusTemplate">
      <Border Style="{StaticResource Card}" Width="{DynamicResource StatusCardWidth}" Margin="0,0,14,14" Padding="20,18">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <DockPanel>
            <Border Name="Chip" DockPanel.Dock="Right" CornerRadius="13" Padding="10,4" VerticalAlignment="Top" Background="{DynamicResource OkBg}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Name="ChipGlyph" Style="{StaticResource Glyph}" Text="&#xE73E;" FontSize="11" Margin="0,0,5,0" Foreground="{DynamicResource OkFg}"/>
                <TextBlock Name="ChipText" Text="{DynamicResource Str_Health_OK}" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource OkFg}"/>
              </StackPanel>
            </Border>
            <TextBlock Name="Icon" Style="{StaticResource Glyph}" Text="{Binding Glyph}" FontSize="20" VerticalAlignment="Top" Foreground="{DynamicResource OkFg}"/>
            <TextBlock Text="{Binding Property}" FontSize="14" FontWeight="SemiBold" Margin="12,1,8,0" TextWrapping="Wrap"/>
          </DockPanel>
          <TextBlock Grid.Row="1" Text="{Binding Detail}" TextWrapping="Wrap" TextTrimming="CharacterEllipsis" MaxHeight="96"
                     Foreground="{DynamicResource TextSecondary}" Margin="0,10,0,12" ToolTip="{Binding Detail}"/>
          <StackPanel Grid.Row="2" Orientation="Horizontal">
            <Button Name="Fix" Tag="Fix" Style="{StaticResource PrimaryButton}" Visibility="Collapsed" Margin="0,0,8,0" ToolTip="{DynamicResource Str_Tooltip_Fix}">
              <StackPanel Orientation="Horizontal">
                <Grid>
                  <TextBlock Name="FixIcon" Style="{StaticResource Glyph}" Text="{Binding FixGlyph}" FontSize="13" Foreground="{DynamicResource RunButtonFg}"/>
                  <TextBlock Name="FixSpin" Style="{StaticResource Glyph}" Text="&#xE895;" FontSize="13" Foreground="{DynamicResource RunButtonFg}" Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
                    <TextBlock.RenderTransform><RotateTransform/></TextBlock.RenderTransform>
                  </TextBlock>
                </Grid>
                <TextBlock Text="{Binding FixText}" Margin="8,0,0,0" Foreground="{DynamicResource RunButtonFg}"/>
              </StackPanel>
            </Button>
            <Button Tag="Check" Style="{StaticResource OutlineIconButton}" ToolTip="{DynamicResource Str_Check_Tooltip}">
              <TextBlock Style="{StaticResource Glyph}" Text="&#xE72C;" FontSize="14"/>
            </Button>
          </StackPanel>
        </Grid>
      </Border>
      <DataTemplate.Triggers>
        <DataTrigger Binding="{Binding HasFix}" Value="True"><Setter TargetName="Fix" Property="Visibility" Value="Visible"/></DataTrigger>
        <!-- The repair of this card runs: rotating icon and "Running ..." until the service has answered. -->
        <DataTrigger Binding="{Binding Running}" Value="True">
          <Setter TargetName="FixIcon" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="FixSpin" Property="Visibility" Value="Visible"/>
          <Setter TargetName="Fix" Property="ToolTip" Value="{DynamicResource Str_Action_Running}"/>
          <DataTrigger.EnterActions>
            <BeginStoryboard Name="FixSpinStory">
              <Storyboard><DoubleAnimation Storyboard.TargetName="FixSpin" Storyboard.TargetProperty="(UIElement.RenderTransform).(RotateTransform.Angle)" From="0" To="360" Duration="0:0:1.2" RepeatBehavior="Forever"/></Storyboard>
            </BeginStoryboard>
          </DataTrigger.EnterActions>
          <DataTrigger.ExitActions><StopStoryboard BeginStoryboardName="FixSpinStory"/></DataTrigger.ExitActions>
        </DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="Pending">
          <Setter TargetName="Chip" Property="Background" Value="{DynamicResource WarnBg}"/>
          <Setter TargetName="ChipText" Property="Foreground" Value="{DynamicResource WarnFg}"/>
          <Setter TargetName="ChipText" Property="Text" Value="{DynamicResource Str_Health_Pending}"/>
          <Setter TargetName="ChipGlyph" Property="Text" Value="&#xE7BA;"/>
          <Setter TargetName="ChipGlyph" Property="Foreground" Value="{DynamicResource WarnFg}"/>
          <Setter TargetName="Icon" Property="Foreground" Value="{DynamicResource WarnFg}"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="Error">
          <Setter TargetName="Chip" Property="Background" Value="{DynamicResource ErrBg}"/>
          <Setter TargetName="ChipText" Property="Foreground" Value="{DynamicResource ErrFg}"/>
          <Setter TargetName="ChipText" Property="Text" Value="{DynamicResource Str_Health_Error}"/>
          <Setter TargetName="ChipGlyph" Property="Text" Value="&#xEA39;"/>
          <Setter TargetName="ChipGlyph" Property="Foreground" Value="{DynamicResource ErrFg}"/>
          <Setter TargetName="Icon" Property="Foreground" Value="{DynamicResource ErrFg}"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding Status}" Value="Unknown">
          <Setter TargetName="Chip" Property="Background" Value="{DynamicResource NeutralBg}"/>
          <Setter TargetName="ChipText" Property="Foreground" Value="{DynamicResource NeutralFg}"/>
          <Setter TargetName="ChipText" Property="Text" Value="{DynamicResource Str_Health_Unknown}"/>
          <Setter TargetName="ChipGlyph" Property="Text" Value="&#xE9CE;"/>
          <Setter TargetName="ChipGlyph" Property="Foreground" Value="{DynamicResource NeutralFg}"/>
          <Setter TargetName="Icon" Property="Foreground" Value="{DynamicResource NeutralFg}"/>
        </DataTrigger>
      </DataTemplate.Triggers>
    </DataTemplate>

    <DataTemplate x:Key="InfoTemplate">
      <Border Style="{StaticResource Card}" Width="{DynamicResource InfoCardWidth}" Margin="0,0,14,14" Padding="20,16">
        <StackPanel Grid.IsSharedSizeScope="True">
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Style="{StaticResource Glyph}" Text="{Binding Glyph}" FontSize="16" Foreground="{DynamicResource AccentText}"/>
            <TextBlock Text="{Binding Title}" FontSize="14" FontWeight="SemiBold" Margin="10,0,0,0"/>
          </StackPanel>
          <ItemsControl ItemsSource="{Binding Rows}">
            <ItemsControl.ItemTemplate>
              <DataTemplate>
                <Grid Margin="0,3" Background="Transparent" Cursor="Hand" ToolTip="{DynamicResource Str_Copy_Hint}">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="Auto" SharedSizeGroup="Label"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <TextBlock Text="{Binding Property}" Foreground="{DynamicResource TextSecondary}" Margin="0,0,16,0" TextWrapping="Wrap" MaxWidth="220"/>
                  <TextBlock Grid.Column="1" Text="{Binding Value}" TextWrapping="Wrap" FlowDirection="LeftToRight"/>
                  <TextBlock Name="StatusGlyph" Grid.Column="2" Style="{StaticResource Glyph}" FontSize="14" Margin="10,1,0,0" VerticalAlignment="Top" Visibility="Collapsed"/>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding Status}" Value="OK">
                    <Setter TargetName="StatusGlyph" Property="Visibility" Value="Visible"/>
                    <Setter TargetName="StatusGlyph" Property="Text" Value="&#xE73E;"/>
                    <Setter TargetName="StatusGlyph" Property="Foreground" Value="{DynamicResource OkFg}"/>
                    <Setter TargetName="StatusGlyph" Property="ToolTip" Value="{DynamicResource Str_Health_OK}"/>
                    <Setter TargetName="StatusGlyph" Property="AutomationProperties.Name" Value="{DynamicResource Str_Health_OK}"/>
                  </DataTrigger>
                  <DataTrigger Binding="{Binding Status}" Value="Pending">
                    <Setter TargetName="StatusGlyph" Property="Visibility" Value="Visible"/>
                    <Setter TargetName="StatusGlyph" Property="Text" Value="&#xE7BA;"/>
                    <Setter TargetName="StatusGlyph" Property="Foreground" Value="{DynamicResource WarnFg}"/>
                    <Setter TargetName="StatusGlyph" Property="ToolTip" Value="{DynamicResource Str_Health_Pending}"/>
                    <Setter TargetName="StatusGlyph" Property="AutomationProperties.Name" Value="{DynamicResource Str_Health_Pending}"/>
                  </DataTrigger>
                  <DataTrigger Binding="{Binding Status}" Value="Error">
                    <Setter TargetName="StatusGlyph" Property="Visibility" Value="Visible"/>
                    <Setter TargetName="StatusGlyph" Property="Text" Value="&#xEA39;"/>
                    <Setter TargetName="StatusGlyph" Property="Foreground" Value="{DynamicResource ErrFg}"/>
                    <Setter TargetName="StatusGlyph" Property="ToolTip" Value="{DynamicResource Str_Health_Error}"/>
                    <Setter TargetName="StatusGlyph" Property="AutomationProperties.Name" Value="{DynamicResource Str_Health_Error}"/>
                  </DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ItemsControl.ItemTemplate>
          </ItemsControl>
        </StackPanel>
      </Border>
    </DataTemplate>

    <ItemsPanelTemplate x:Key="Wrap"><WrapPanel/></ItemsPanelTemplate>
'@

# Rotating "loading" icon (the transform is local to each element, so it can be animated).
Function Get-SelfXSpinnerXaml
	{
		param([string]$Name)
		return @"
<TextBlock Name="$Name" Style="{StaticResource Glyph}" Text="&#xE895;" FontSize="16" Margin="0,0,10,0" Visibility="Collapsed" Foreground="{DynamicResource AccentText}" RenderTransformOrigin="0.5,0.5">
  <TextBlock.RenderTransform><RotateTransform/></TextBlock.RenderTransform>
  <TextBlock.Triggers>
    <EventTrigger RoutedEvent="FrameworkElement.Loaded">
      <BeginStoryboard><Storyboard><DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(RotateTransform.Angle)" From="0" To="360" Duration="0:0:1.2" RepeatBehavior="Forever"/></Storyboard></BeginStoryboard>
    </EventTrigger>
  </TextBlock.Triggers>
</TextBlock>
"@
	}

#******************************************************************************
# Main window
#******************************************************************************
$MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SelfX" Width="1000" Height="680" MinWidth="640" MinHeight="480"
        WindowStyle="None" ResizeMode="CanResize" WindowStartupLocation="CenterScreen"
        Background="{DynamicResource WindowBg}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        Foreground="{DynamicResource TextPrimary}" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="40" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
__STYLES__
__TEMPLATES__
  </Window.Resources>

  <Border Name="Root" Background="{DynamicResource WindowBg}" BorderBrush="{DynamicResource Stroke}" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="40"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <Grid.ColumnDefinitions><ColumnDefinition Name="NavColumn" Width="220"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

      <!-- Title bar -->
      <DockPanel Grid.ColumnSpan="2" Background="{DynamicResource TitleBarBg}">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button Name="Btn_Help" Style="{StaticResource ChromeButton}"><TextBlock Style="{StaticResource Glyph}" Text="&#xE897;" FontSize="15"/></Button>
          <Button Name="Btn_Settings" Style="{StaticResource ChromeButton}"><TextBlock Style="{StaticResource Glyph}" Text="&#xE713;" FontSize="15"/></Button>
          <Button Name="Btn_About" Style="{StaticResource ChromeButton}"><TextBlock Style="{StaticResource Glyph}" Text="&#xE946;" FontSize="15"/></Button>
          <Rectangle Width="1" Margin="6,10" Fill="{DynamicResource Stroke}"/>
          <Button Name="Btn_Min" Style="{StaticResource ChromeButton}"><TextBlock Style="{StaticResource Glyph}" Text="&#xE921;" FontSize="10"/></Button>
          <Button Name="Btn_Max" Style="{StaticResource ChromeButton}"><TextBlock Name="Btn_Max_Glyph" Style="{StaticResource Glyph}" Text="&#xE922;" FontSize="10"/></Button>
          <Button Name="Btn_Close" Style="{StaticResource ChromeButton}"><TextBlock Style="{StaticResource Glyph}" Text="&#xE8BB;" FontSize="10"/></Button>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="14,0,0,0" VerticalAlignment="Center">
          <Image Name="AppIcon" Width="18" Height="18"/>
          <TextBlock Name="TitleText" Text="SelfX" FontWeight="SemiBold" Margin="10,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource TitleBarFg}"/>
        </StackPanel>
      </DockPanel>

      <!-- Navigation -->
      <Grid Grid.Row="1" Margin="8,6,8,10">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel>
          <Image Name="Brand_Logo" Height="40" MaxWidth="196" Margin="10,4,10,14" HorizontalAlignment="Left" Stretch="Uniform" Visibility="Collapsed"/>
          <RadioButton Name="Nav_Actions" Style="{StaticResource NavItem}" GroupName="Nav" IsChecked="True">
            <StackPanel Orientation="Horizontal">
              <TextBlock Style="{StaticResource Glyph}" Text="&#xE90F;" FontSize="16" Width="20"/>
              <TextBlock Name="NavText1" Margin="12,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
          </RadioButton>
          <RadioButton Name="Nav_Status" Style="{StaticResource NavItem}" GroupName="Nav">
            <Grid>
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Glyph}" Text="&#xEB51;" FontSize="16" Width="20"/>
                <TextBlock Name="NavText2" Margin="12,0,0,0" VerticalAlignment="Center"/>
              </StackPanel>
              <Border Name="NavBadge" CornerRadius="8" Background="{DynamicResource ErrSolid}" MinWidth="16" Height="16" Padding="5,0"
                      HorizontalAlignment="Right" VerticalAlignment="Center" Visibility="Collapsed">
                <TextBlock Name="NavBadgeText" FontSize="10" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
            </Grid>
          </RadioButton>
          <RadioButton Name="Nav_Info" Style="{StaticResource NavItem}" GroupName="Nav">
            <StackPanel Orientation="Horizontal">
              <TextBlock Style="{StaticResource Glyph}" Text="&#xE7F4;" FontSize="16" Width="20"/>
              <TextBlock Name="NavText3" Margin="12,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
          </RadioButton>
        </StackPanel>
        <StackPanel Grid.Row="2">
          <Button Name="Btn_Ticket" Style="{StaticResource PrimaryButton}" HorizontalAlignment="Stretch" HorizontalContentAlignment="Left" Margin="0,0,0,8" Padding="14,10" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal">
              <TextBlock Style="{StaticResource Glyph}" Text="&#xE7C3;" FontSize="16" Foreground="{DynamicResource RunButtonFg}"/>
              <TextBlock Name="NavText5" Margin="10,0,0,0" TextWrapping="Wrap" MaxWidth="150" FontWeight="SemiBold" Foreground="{DynamicResource RunButtonFg}"/>
            </StackPanel>
          </Button>
          <Button Name="Btn_Copilot" Style="{StaticResource BaseButton}" HorizontalAlignment="Stretch" HorizontalContentAlignment="Left" Margin="0,0,0,8" Padding="14,10" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal">
              <TextBlock Style="{StaticResource Glyph}" Text="&#xE8F2;" FontSize="16" Foreground="{DynamicResource AccentText}"/>
              <TextBlock Name="NavText6" Margin="10,0,0,0" TextWrapping="Wrap" MaxWidth="150"/>
            </StackPanel>
          </Button>
          <Button Name="Btn_Wiki" Style="{StaticResource BaseButton}" HorizontalAlignment="Stretch" HorizontalContentAlignment="Left" Margin="0,0,0,8" Padding="14,10" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal">
              <TextBlock Style="{StaticResource Glyph}" Text="&#xE736;" FontSize="16" Foreground="{DynamicResource AccentText}"/>
              <TextBlock Name="NavText7" Margin="10,0,0,0" TextWrapping="Wrap" MaxWidth="150"/>
            </StackPanel>
          </Button>
          <Button Name="Btn_SendLogs" Style="{StaticResource BaseButton}" HorizontalAlignment="Stretch" HorizontalContentAlignment="Left" Margin="0,0,0,10" Padding="12,8">
            <StackPanel Orientation="Horizontal">
              <TextBlock Style="{StaticResource Glyph}" Text="&#xE724;" FontSize="14"/>
              <TextBlock Name="NavText4" Margin="10,0,0,0" TextWrapping="Wrap" MaxWidth="160"/>
            </StackPanel>
          </Button>
          <Border Name="ServicePill" CornerRadius="12" Background="{DynamicResource SurfaceAlt}" Padding="10,7">
            <StackPanel Orientation="Horizontal">
              <Ellipse Name="ServiceDot" Width="8" Height="8" Fill="{DynamicResource NeutralFg}" VerticalAlignment="Center"/>
              <StackPanel Name="ServiceText" Margin="10,0,0,0">
                <TextBlock Name="ServiceLabel" FontSize="12" TextWrapping="Wrap" MaxWidth="160"/>
                <TextBlock Name="VersionLabel" FontSize="11" Foreground="{DynamicResource TextSecondary}"/>
              </StackPanel>
            </StackPanel>
          </Border>
        </StackPanel>
      </Grid>

      <!-- Content -->
      <Border Grid.Row="1" Grid.Column="1" Margin="0,0,12,12" Background="{DynamicResource ContentBg}" CornerRadius="18" BorderBrush="{DynamicResource Stroke}" BorderThickness="1">
        <Grid Margin="32,26,20,16">
          <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

          <!-- Page: troubleshooting -->
          <Grid Name="Page_Actions">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <StackPanel Margin="0,0,12,0">
              <TextBlock Name="Main_Title" Style="{StaticResource PageTitle}"/>
              <TextBlock Name="Subtitle" Style="{StaticResource SubText}" Margin="0,4,0,0"/>
              <!-- Three simple steps (explanation only, not clickable) -->
              <StackPanel Orientation="Horizontal" Margin="0,14,0,0" Focusable="False">
                <Border CornerRadius="12" Background="{DynamicResource SurfaceAlt}" Padding="12,7" Margin="0,0,8,0"><StackPanel Orientation="Horizontal"><Border Width="20" Height="20" CornerRadius="10" Background="{DynamicResource Accent}"><TextBlock Text="1" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource AccentFg}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Name="StepText1" Margin="8,0,0,0" VerticalAlignment="Center" FontSize="12"/></StackPanel></Border>
                <Border CornerRadius="12" Background="{DynamicResource SurfaceAlt}" Padding="12,7" Margin="0,0,8,0"><StackPanel Orientation="Horizontal"><Border Width="20" Height="20" CornerRadius="10" Background="{DynamicResource Accent}"><TextBlock Text="2" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource AccentFg}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Name="StepText2" Margin="8,0,0,0" VerticalAlignment="Center" FontSize="12"/></StackPanel></Border>
                <Border CornerRadius="12" Background="{DynamicResource SurfaceAlt}" Padding="12,7"><StackPanel Orientation="Horizontal"><Border Width="20" Height="20" CornerRadius="10" Background="{DynamicResource Accent}"><TextBlock Text="3" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource AccentFg}" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><TextBlock Name="StepText3" Margin="8,0,0,0" VerticalAlignment="Center" FontSize="12"/></StackPanel></Border>
              </StackPanel>
            </StackPanel>
            <DockPanel Grid.Row="1" Margin="0,16,12,10">
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" Margin="10,0,0,0">
                <Border CornerRadius="12" Background="{DynamicResource SurfaceAlt}" Padding="3">
                  <StackPanel Orientation="Horizontal">
                    <RadioButton Name="Mode_Simple" Style="{StaticResource Segment}" GroupName="View"/>
                    <RadioButton Name="Mode_Detailed" Style="{StaticResource Segment}" GroupName="View"/>
                  </StackPanel>
                </Border>
                <Button Name="Btn_ViewHelp" Style="{StaticResource IconButton}" Margin="4,0,0,0">
                  <TextBlock Style="{StaticResource Glyph}" Text="&#xE9CE;" FontSize="15" Foreground="{DynamicResource InfoIcon}"/>
                </Button>
              </StackPanel>
              <Border CornerRadius="12" Background="{DynamicResource Surface}" BorderBrush="{DynamicResource Stroke}" BorderThickness="1" Height="44">
                <Grid Margin="10,0">
                  <TextBlock Style="{StaticResource Glyph}" Text="&#xE721;" FontSize="13" HorizontalAlignment="Left" Foreground="{DynamicResource TextSecondary}"/>
                  <TextBlock Name="SearchHint" Margin="26,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource TextSecondary}" IsHitTestVisible="False"/>
                  <TextBox Name="FilterTextBox" Margin="22,0,26,0" Background="Transparent" BorderThickness="0" VerticalAlignment="Center"
                           Foreground="{DynamicResource TextPrimary}" CaretBrush="{DynamicResource TextPrimary}"/>
                  <Button Name="Btn_ClearSearch" Style="{StaticResource IconButton}" Width="26" Height="26" HorizontalAlignment="Right" Visibility="Collapsed">
                    <TextBlock Style="{StaticResource Glyph}" Text="&#xE711;" FontSize="10"/>
                  </Button>
                </Grid>
              </Border>
            </DockPanel>
            <DockPanel Grid.Row="2" Margin="0,0,12,6">
              <TextBlock Name="Actions_Count" DockPanel.Dock="Right" Foreground="{DynamicResource TextSecondary}" VerticalAlignment="Top" Margin="10,5,0,0"/>
              <ItemsControl Name="Categories" ItemsPanel="{StaticResource Wrap}"/>
            </DockPanel>
            <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto" Padding="0,0,12,0">
              <ItemsControl Name="ActionsList" ItemTemplate="{StaticResource ActionTemplate}"/>
            </ScrollViewer>
          </Grid>

          <!-- Page: device status -->
          <Grid Name="Page_Status" Visibility="Collapsed">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <DockPanel Margin="0,0,12,0">
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
__SPIN_STATUS__
                <Button Name="Btn_CheckAll" Style="{StaticResource OutlineIconButton}">
                  <TextBlock Style="{StaticResource Glyph}" Text="&#xE72C;" FontSize="15"/>
                </Button>
              </StackPanel>
              <StackPanel>
                <TextBlock Name="Status_Title" Style="{StaticResource PageTitle}"/>
                <TextBlock Name="Status_Subtitle" Style="{StaticResource SubText}" Margin="0,4,0,0"/>
              </StackPanel>
            </DockPanel>
            <Border Name="Status_Banner" Grid.Row="1" CornerRadius="14" Background="{DynamicResource InfoBg}" Padding="20,16" Margin="0,18,24,16">
              <DockPanel>
                <Button Name="Btn_FixAll" DockPanel.Dock="Right" Style="{StaticResource PrimaryButton}" VerticalAlignment="Center" Margin="12,0,0,0" Visibility="Collapsed">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Style="{StaticResource Glyph}" Text="&#xE90F;" FontSize="13" Foreground="{DynamicResource RunButtonFg}"/>
                    <TextBlock Name="Btn_FixAll_Text" Margin="8,0,0,0" Foreground="{DynamicResource RunButtonFg}"/>
                  </StackPanel>
                </Button>
                <TextBlock Name="Status_BannerGlyph" Style="{StaticResource Glyph}" Text="&#xE946;" FontSize="18" Margin="0,0,12,0" VerticalAlignment="Top"/>
                <StackPanel>
                  <TextBlock Name="Status_BannerTitle" FontWeight="SemiBold" TextWrapping="Wrap"/>
                  <TextBlock Name="Status_BannerText" Style="{StaticResource SubText}" Margin="0,2,0,0"/>
                </StackPanel>
              </DockPanel>
            </Border>
            <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
              <ItemsControl Name="StatusCards" ItemTemplate="{StaticResource StatusTemplate}" ItemsPanel="{StaticResource Wrap}"/>
            </ScrollViewer>
          </Grid>

          <!-- Page: system information -->
          <Grid Name="Page_Info" Visibility="Collapsed">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <DockPanel Margin="0,0,12,14">
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
__SPIN_INFO__
                <Button Name="SysInfo_Refresh" Style="{StaticResource OutlineIconButton}" Margin="0,0,6,0"><TextBlock Style="{StaticResource Glyph}" Text="&#xE72C;" FontSize="15"/></Button>
                <Button Name="SysInfo_Copy" Style="{StaticResource OutlineIconButton}" Margin="0,0,6,0"><TextBlock Style="{StaticResource Glyph}" Text="&#xE8C8;" FontSize="15"/></Button>
                <Button Name="SysInfo_Export" Style="{StaticResource OutlineIconButton}"><TextBlock Style="{StaticResource Glyph}" Text="&#xE74E;" FontSize="15"/></Button>
              </StackPanel>
              <StackPanel>
                <TextBlock Name="SysInfo_Title" Style="{StaticResource PageTitle}"/>
                <TextBlock Name="SysInfo_Status" Style="{StaticResource SubText}" Margin="0,4,0,0"/>
              </StackPanel>
            </DockPanel>
            <ScrollViewer Grid.Row="1" Grid.RowSpan="2" VerticalScrollBarVisibility="Auto">
              <StackPanel>
                <ItemsControl Name="InfoCards" ItemTemplate="{StaticResource InfoTemplate}" ItemsPanel="{StaticResource Wrap}"/>
                <StackPanel Name="SysInfo_Actions" Margin="0,8,12,0">
              <TextBlock Name="Tools_Title" FontWeight="SemiBold" Margin="0,0,0,8"/>
              <WrapPanel>
                <Button Name="SysInfo_SyncApps" Style="{StaticResource ToolTile}"><StackPanel><TextBlock Style="{StaticResource Glyph}" Text="&#xE895;" FontSize="20" Foreground="{DynamicResource AccentText}"/><TextBlock Name="SysInfo_SyncApps_Label" TextWrapping="Wrap" TextAlignment="Center" Margin="0,6,0,0" FontSize="12"/></StackPanel></Button>
                <Button Name="SysInfo_SyncCompliance" Style="{StaticResource ToolTile}"><StackPanel><TextBlock Style="{StaticResource Glyph}" Text="&#xE9D5;" FontSize="20" Foreground="{DynamicResource AccentText}"/><TextBlock Name="SysInfo_SyncCompliance_Label" TextWrapping="Wrap" TextAlignment="Center" Margin="0,6,0,0" FontSize="12"/></StackPanel></Button>
                <Button Name="SysInfo_CompanyPortal" Style="{StaticResource ToolTile}"><StackPanel><TextBlock Style="{StaticResource Glyph}" Text="&#xE719;" FontSize="20" Foreground="{DynamicResource AccentText}"/><TextBlock Name="SysInfo_CompanyPortal_Label" TextWrapping="Wrap" TextAlignment="Center" Margin="0,6,0,0" FontSize="12"/></StackPanel></Button>
                <Button Name="SysInfo_QuickAssist" Style="{StaticResource ToolTile}"><StackPanel><TextBlock Style="{StaticResource Glyph}" Text="&#xE716;" FontSize="20" Foreground="{DynamicResource AccentText}"/><TextBlock Name="SysInfo_QuickAssist_Label" TextWrapping="Wrap" TextAlignment="Center" Margin="0,6,0,0" FontSize="12"/></StackPanel></Button>
                <Button Name="SysInfo_MdmDiagnostics" Style="{StaticResource ToolTile}"><StackPanel><TextBlock Style="{StaticResource Glyph}" Text="&#xE9F9;" FontSize="20" Foreground="{DynamicResource AccentText}"/><TextBlock Name="SysInfo_MdmDiagnostics_Label" TextWrapping="Wrap" TextAlignment="Center" Margin="0,6,0,0" FontSize="12"/></StackPanel></Button>
                <Button Name="SysInfo_SendLogs" Style="{StaticResource ToolTile}"><StackPanel><TextBlock Style="{StaticResource Glyph}" Text="&#xE724;" FontSize="20" Foreground="{DynamicResource AccentText}"/><TextBlock Name="SysInfo_SendLogs_Label" TextWrapping="Wrap" TextAlignment="Center" Margin="0,6,0,0" FontSize="12"/></StackPanel></Button>
              </WrapPanel>
                </StackPanel>
              </StackPanel>
            </ScrollViewer>
          </Grid>

          <!-- Message bar: results of actions and the reboot reminder -->
          <Border Grid.Row="1" Name="InfoBar" CornerRadius="6" Background="{DynamicResource InfoBg}" BorderBrush="{DynamicResource Stroke}" BorderThickness="1" Padding="12,8" Margin="0,10,12,0" Visibility="Collapsed">
            <DockPanel>
              <Button Name="InfoBar_Close" DockPanel.Dock="Right" Style="{StaticResource IconButton}" Width="26" Height="26"><TextBlock Style="{StaticResource Glyph}" Text="&#xE711;" FontSize="10"/></Button>
              <TextBlock Name="InfoBar_Glyph" Style="{StaticResource Glyph}" Text="&#xE946;" FontSize="15" Margin="0,0,10,0" VerticalAlignment="Top"/>
              <TextBlock Name="InfoBar_Text" VerticalAlignment="Center" TextWrapping="Wrap"/>
            </DockPanel>
          </Border>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
'@
$MainXaml = $MainXaml.Replace('__STYLES__', $Global:SelfX_StylesXaml).Replace('__TEMPLATES__', $Global:SelfX_TemplatesXaml)
$MainXaml = $MainXaml.Replace('__SPIN_STATUS__', (Get-SelfXSpinnerXaml 'Status_Spinner')).Replace('__SPIN_INFO__', (Get-SelfXSpinnerXaml 'SysInfo_Spinner'))
[xml]$XamlMainWindow = $MainXaml

# Theme dictionary: brushes and texts used by DynamicResource in all windows of SelfX
$Global:SelfX_Theme = New-Object System.Windows.ResourceDictionary

# Create the window and a PowerShell variable for every named control
$Form = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $XamlMainWindow))
$Form.Resources.MergedDictionaries.Add($Global:SelfX_Theme)
$XamlMainWindow.SelectNodes("//*[@Name]") | ForEach-Object {
	$Control = $Form.FindName($_.Name)
	If($Control -ne $null) { Set-Variable -Name "$($_.Name)" -Value $Control -Scope Script }
}

#******************************************************************************
# Theme and branding (Branding section of Tool_Config.xml, theme of the user)
#******************************************************************************
$Global:SelfX_Accent = Get-SelfXAccentColor -BrandColor (Get-SelfXText "Brand_Accent_Color" "") -ToolColor (Get-SelfXText "Tool_Color" "Cyan")

# App mode of Windows (Settings > Personalization > Colors). Without the value Windows uses light.
Function Get-SelfXSystemTheme
	{
		$Value = $null
		Try { $Value = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop).AppsUseLightTheme } Catch {}
		If("$Value" -eq '0') { return 'Dark' }
		return 'Light'
	}

# Theme choice Auto (as Windows), Dark or Light; anything else uses Auto.
Function Resolve-SelfXTheme
	{
		param([string]$Theme)
		If($Theme -eq 'Dark') { return 'Dark' }
		If($Theme -eq 'Light') { return 'Light' }
		return (Get-SelfXSystemTheme)
	}

Function Set-SelfXTheme
	{
		param([string]$Theme)
		If($Theme -notin @('Auto', 'Dark', 'Light')) { $Theme = 'Auto' }
		$Global:SelfX_ThemeChoice = $Theme
		$Effective = Resolve-SelfXTheme $Theme
		$Global:SelfX_CurrentTheme = $Effective
		$Colors = New-SelfXThemeColors -Theme $Effective -Accent $Global:SelfX_Accent -TitleBarColor (Get-SelfXText "Brand_TitleBar_Color" "") `
			-RunButtonColor (Get-SelfXText "Brand_Run_Button_Color" "") -InfoButtonColor (Get-SelfXText "Brand_Info_Button_Color" "")
		Set-SelfXThemeResources -Dictionary $Global:SelfX_Theme -Colors $Colors
	}

# Theme Auto: follow a change of the Windows app mode while SelfX is open.
Function Update-SelfXAutoTheme
	{
		If($Global:SelfX_ThemeChoice -ne 'Auto') { return }
		If((Get-SelfXSystemTheme) -ne $Global:SelfX_CurrentTheme) { Set-SelfXTheme 'Auto' }
	}
Set-SelfXTheme (Get-SelfXUserSetting 'Theme' (Get-SelfXText "Tool_Theme" "Auto"))
$Theme_Timer = New-Object System.Windows.Threading.DispatcherTimer
$Theme_Timer.Interval = [TimeSpan]::FromSeconds(2)
$Theme_Timer.Add_Tick({ Update-SelfXAutoTheme })
$Theme_Timer.Start()

$Brand_Logo_Image = Get-SelfXImage -FileName (Get-SelfXText "Brand_Logo" "") -BaseFolder $Current_Folder
If($Brand_Logo_Image -ne $null)
	{
		$Brand_Logo.Source = $Brand_Logo_Image
		$Brand_Logo_Height = 0
		If([int]::TryParse((Get-SelfXText "Brand_Logo_Height" "40"), [ref]$Brand_Logo_Height) -and ($Brand_Logo_Height -ge 16) -and ($Brand_Logo_Height -le 120))
			{
				$Brand_Logo.Height = $Brand_Logo_Height
			}
		$Brand_Logo.Visibility = "Visible"
	}
$Brand_Icon_Image = Get-SelfXImage -FileName (Get-SelfXText "Brand_Icon" "Repair.ico") -BaseFolder $Current_Folder
If($Brand_Icon_Image -ne $null) { $Form.Icon = $Brand_Icon_Image; $AppIcon.Source = $Brand_Icon_Image }
# Taskbar: the window icon (all sizes of an .ico) and the relaunch data of a pinned SelfX.
$Global:SelfX_Icon_Path = Get-SelfXImagePath -Value (Get-SelfXText "Brand_Icon" "Repair.ico") -CodeRoot $Current_Folder
If(-not $Global:SelfX_Icon_Path) { $Global:SelfX_Icon_Path = Join-Path $Current_Folder 'Repair.ico' }
If(($Global:SelfX_Icon_Path -notlike '*.ico') -or -not (Test-Path -LiteralPath $Global:SelfX_Icon_Path -PathType Leaf)) { $Global:SelfX_Icon_Path = Join-Path $Current_Folder 'Repair.ico' }
If(Test-Path -LiteralPath $Global:SelfX_Icon_Path -PathType Leaf)
	{
		Try { $Form.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $Global:SelfX_Icon_Path)) } Catch {}
	}
$Form.Add_SourceInitialized({
	Try
		{
			$Handle = (New-Object System.Windows.Interop.WindowInteropHelper($Form)).Handle
			$Launcher = Join-Path $Current_Folder 'SelfX.exe'
			$Command = $(If(Test-Path -LiteralPath $Launcher -PathType Leaf) { "`"$Launcher`"" } Else { '' })
			[SelfXGui.Taskbar]::SetWindowIdentity($Handle, $Global:SelfX_AppId, $Command, $Tool_Name, "$Global:SelfX_Icon_Path,0")
		}
	Catch { Write-SelfXLog "Taskbar identity not set: $($_.Exception.Message)" Warning }
})

#******************************************************************************
# Texts of the window (language file) and texts used by templates and tooltips
#******************************************************************************
$Form.FlowDirection = $SelfX_UI_Language.FlowDirection
# The language tag lets WPF pick the right fonts for Chinese, Japanese, Korean, Arabic, Hindi, Thai ...
Try { $Form.Language = [System.Windows.Markup.XmlLanguage]::GetLanguage($SelfX_UI_Language.Culture) } Catch {}

foreach($Pair in @(
	@('Str_Tooltip_Run', 'Tooltip_Run'), @('Str_Action_Running', 'Action_Running_Label'), @('Str_Tooltip_Info', 'Run_explanation_Text'), @('Str_Shield', 'Shield_ToolTip'),
	@('Str_Fix', 'Health_Fix'), @('Str_Tooltip_Fix', 'Tooltip_Fix'), @('Str_Check_Tooltip', 'Health_Check_Tooltip'),
	@('Str_Copy_Hint', 'SystemInfo_Hint_Text')))
	{
		$Global:SelfX_Theme[$Pair[0]] = [string](Get-SelfXString $Pair[1])
	}
foreach($State in 'OK', 'Pending', 'Error', 'Unknown') { $Global:SelfX_Theme["Str_Health_$State"] = [string](Get-SelfXInfoText "Health_$State") }

$Main_Title_Text = Get-SelfXString 'Main_Title_Text'
$Main_Title.Text = $(If((Get-SelfXText "Show_Computer_Name_MainGUI" "False") -eq 'True') { "$Main_Title_Text ($env:COMPUTERNAME)" } Else { $Main_Title_Text })
$Form.Title = $(If((Get-SelfXText "Show_Computer_Name_title_bar" "False") -eq 'True') { "$Tool_Name ($env:COMPUTERNAME)" } Else { $Tool_Name })
# Right-to-left languages: keep Latin names with brackets, for example "SelfX (Self fix)", in the right order
If($SelfX_UI_Language.FlowDirection -eq 'RightToLeft')
	{
		$LRM = [string][char]0x200E
		$Form.Title = $LRM + $Form.Title + $LRM
	}
$TitleText.Text = $Form.Title
$Subtitle.Text = Get-SelfXString 'Subtitle_Text'
$NavText1.Text = Get-SelfXString 'Troubleshooting_Tab_Text'
$NavText2.Text = Get-SelfXString 'Nav_Status_Text'
$NavText3.Text = Get-SelfXString 'SystemInfo_Tab_Text'
$NavText4.Text = Get-SelfXString 'SystemInfo_SendLogs_Text'
$StepText1.Text = Get-SelfXString 'Step1_Text'
$StepText2.Text = Get-SelfXString 'Step2_Text'
$StepText3.Text = Get-SelfXString 'Step3_Text'
$NavText5.Text = Get-SelfXString 'Help_Ticket_Text'
$NavText6.Text = Get-SelfXString 'Copilot_Row_Label'
$NavText7.Text = $(If($Wiki.Name) { $Wiki.Name } Else { Get-SelfXString 'Wiki_Row_Label' })
$Btn_Ticket.ToolTip = Get-SelfXString 'Help_Ticket_Tooltip'
$Btn_Copilot.ToolTip = Get-SelfXString 'Copilot_Row_Text'
$Btn_Wiki.ToolTip = Get-SelfXString 'Wiki_Row_Text'
$Btn_SendLogs.ToolTip = Get-SelfXString 'Tooltip_SendLogs'
$VersionLabel.Text = Get-SelfXString 'Version_Text' $Tool_Version
$Mode_Simple.Content = Get-SelfXString 'Solution_Mode_Simple'
$Mode_Detailed.Content = Get-SelfXString 'Solution_Mode_Detailed'
$Btn_ViewHelp.ToolTip = Get-SelfXString 'View_Help_Tooltip'
$SearchHint.Text = Get-SelfXString 'Issue_filter_KeyWord_Text'
$Btn_ClearSearch.ToolTip = Get-SelfXString 'Close_Button_Text'
$Status_Title.Text = Get-SelfXString 'Nav_Status_Text'
$Btn_CheckAll.ToolTip = Get-SelfXString 'Status_CheckAll_Tooltip'
$Btn_FixAll_Text.Text = Get-SelfXString 'Status_FixAll'
$Btn_FixAll.ToolTip = Get-SelfXString 'Status_FixAll_Tooltip'
$SysInfo_Title.Text = Get-SelfXString 'SystemInfo_Title_Text'
$SysInfo_Refresh.ToolTip = (Get-SelfXString 'SystemInfo_Refresh_Text') + ': ' + (Get-SelfXString 'Tooltip_Refresh')
$SysInfo_Copy.ToolTip = (Get-SelfXString 'SystemInfo_Copy_Text') + ': ' + (Get-SelfXString 'Tooltip_Copy')
$SysInfo_Export.ToolTip = (Get-SelfXString 'SystemInfo_Export_Text') + ': ' + (Get-SelfXString 'Tooltip_Export')
# Remote support tool of the tile (Remote Help, else Quick Assist). Remote Help counts as installed when RemoteHelp.exe
# in the Program Files folder (writable only by administrators) is a plain file, no link, and validly signed by
# Microsoft Corporation. Then only Remote Help is offered and Quick Assist is not (one standard in the company).
Function Get-SelfXRemoteHelpPath
	{
		param([string]$Path = (Join-Path $env:ProgramFiles 'Remote Help\RemoteHelp.exe'), [string]$SubjectPattern = 'CN=Microsoft Corporation,*')
		Try
			{
				$Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
				If($Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $null }
				$Signature = Get-AuthenticodeSignature -LiteralPath $Item.FullName
				If($Signature.Status -ne 'Valid' -or -not $Signature.SignerCertificate -or $Signature.SignerCertificate.Subject -notlike $SubjectPattern) { return $null }
				return $Item.FullName
			}
		Catch { return $null }
	}
$Global:RemoteHelp_Path = Get-SelfXRemoteHelpPath
$Tools_Title.Text = Get-SelfXString 'Tools_Title_Text'
foreach($Tool in 'SyncApps', 'SyncCompliance', 'CompanyPortal', 'QuickAssist', 'MdmDiagnostics', 'SendLogs')
	{
		(Get-Variable "SysInfo_$($Tool)_Label").Value.Text = Get-SelfXString "SystemInfo_$($Tool)_Text"
		(Get-Variable "SysInfo_$Tool").Value.ToolTip = Get-SelfXString "Tooltip_$Tool"
	}
If($Global:RemoteHelp_Path)
	{
		$SysInfo_QuickAssist_Label.Text = Get-SelfXString 'SystemInfo_RemoteHelp_Text'
		$SysInfo_QuickAssist.ToolTip = Get-SelfXString 'Tooltip_RemoteHelp'
	}
$Btn_Help.ToolTip = Get-SelfXString 'Support_Button_ToolTip'
$Btn_Settings.ToolTip = Get-SelfXString 'Settings_Button_ToolTip'
$Btn_About.ToolTip = Get-SelfXString 'About_Button_ToolTip'
$InfoBar_Close.ToolTip = Get-SelfXString 'Close_Button_Text'

#******************************************************************************
# Message bar. $msgbar keeps the methods of the former alert bar (Clear, SetSuccessAlert, ...).
#******************************************************************************
Function Show-SelfXMessageBar
	{
		param([ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Kind, [string]$Text)
		$Look = @{ Info = @('InfoBg', 'AccentText', 0xE946); Success = @('OkBg', 'OkFg', 0xE930); Warning = @('WarnBg', 'WarnFg', 0xE7BA); Error = @('ErrBg', 'ErrFg', 0xEA39) }[$Kind]
		$InfoBar.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $Look[0])
		$InfoBar_Glyph.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Look[1])
		$InfoBar_Glyph.Text = [string][char]$Look[2]
		$InfoBar_Text.Text = $Text
		$InfoBar.Visibility = 'Visible'
		# Every message of the window is logged, so the support can follow what the user saw.
		Write-SelfXLog "Message ($Kind): $Text" $(Switch($Kind) { 'Error' { 'Error' } 'Warning' { 'Warning' } Default { 'Info' } })
	}
$msgbar = New-Object PSObject
$msgbar | Add-Member ScriptMethod Clear { $InfoBar.Visibility = 'Collapsed' }
$msgbar | Add-Member ScriptMethod SetInformationAlert { param($Text) Show-SelfXMessageBar Info $Text }
$msgbar | Add-Member ScriptMethod SetSuccessAlert { param($Text) Show-SelfXMessageBar Success $Text }
$msgbar | Add-Member ScriptMethod SetWarningAlert { param($Text) Show-SelfXMessageBar Warning $Text }
$msgbar | Add-Member ScriptMethod SetDangerAlert { param($Text) Show-SelfXMessageBar Error $Text }
$InfoBar_Close.Add_Click({ $msgbar.Clear() })

#******************************************************************************
# Dialogs in the SelfX style (confirmation, information, help, settings, about)
#******************************************************************************
# Creates a dialog window with the shared styles and theme. Content is XAML placed below the title.
Function New-SelfXDialog
	{
		param([string]$Title, [string]$ContentXaml, [int]$Width = 480)
		$DialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" ResizeMode="NoResize" SizeToContent="Height" ShowInTaskbar="False" WindowStartupLocation="CenterOwner"
        Background="{DynamicResource Surface}" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        Foreground="{DynamicResource TextPrimary}" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
__STYLES__
  </Window.Resources>
  <Border Background="{DynamicResource Surface}" BorderBrush="{DynamicResource Stroke}" BorderThickness="1">
    <StackPanel Margin="28,22,28,24">
      <DockPanel Name="DialogHeader" Background="Transparent" Margin="0,0,0,12">
        <TextBlock Name="DialogGlyph" Style="{StaticResource Glyph}" FontSize="20" Margin="0,0,12,0" Foreground="{DynamicResource AccentText}" Visibility="Collapsed"/>
        <TextBlock Name="DialogTitle" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap"/>
      </DockPanel>
__CONTENT__
    </StackPanel>
  </Border>
</Window>
'@
		$DialogXaml = $DialogXaml.Replace('__STYLES__', $Global:SelfX_StylesXaml).Replace('__CONTENT__', $ContentXaml)
		$Dialog = [Windows.Markup.XamlReader]::Parse($DialogXaml)
		$Dialog.Resources.MergedDictionaries.Add($Global:SelfX_Theme)
		$Dialog.Width = $Width
		$Dialog.FlowDirection = $Form.FlowDirection
		$Dialog.Language = $Form.Language
		$Dialog.Title = $Title
		$Dialog.FindName('DialogTitle').Text = $Title
		If($Form.IsLoaded) { $Dialog.Owner = $Form } Else { $Dialog.WindowStartupLocation = 'CenterScreen' }
		$Dialog.FindName('DialogHeader').Add_MouseLeftButtonDown({ Try { [System.Windows.Window]::GetWindow($this).DragMove() } Catch {} })
		return $Dialog
	}

# Shows a message with one or two buttons; returns "Affirmative" or "Negative" (like the former MahApps dialogs).
Function Show-SelfXDialog
	{
		param(
			[string]$Title,
			[string]$Message,
			[string]$AffirmativeText,
			[string]$NegativeText = '',
			[ValidateSet('Info', 'Question', 'Warning')][string]$Kind = 'Info'
		)
		$Content = @'
      <ScrollViewer MaxHeight="420" VerticalScrollBarVisibility="Auto"><TextBlock Name="DialogText" TextWrapping="Wrap" LineHeight="20"/></ScrollViewer>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,22,0,0">
        <Button Name="DialogYes" Style="{StaticResource PrimaryButton}" MinWidth="110" IsDefault="True"/>
        <Button Name="DialogNo" Style="{StaticResource BaseButton}" MinWidth="110" Margin="8,0,0,0" IsCancel="True"/>
      </StackPanel>
'@
		$Dialog = New-SelfXDialog -Title $Title -ContentXaml $Content
		$Glyph = $Dialog.FindName('DialogGlyph')
		$Glyph.Text = [string][char]@{ Info = 0xE946; Question = 0xE9CE; Warning = 0xE7BA }[$Kind]
		If($Kind -eq 'Warning') { $Glyph.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'WarnFg') }
		$Glyph.Visibility = 'Visible'
		$Dialog.FindName('DialogText').Text = $Message
		$Yes = $Dialog.FindName('DialogYes')
		$No = $Dialog.FindName('DialogNo')
		$Yes.Content = $AffirmativeText
		$Yes.Add_Click({ $Global:SelfX_DialogResult = 'Affirmative'; [System.Windows.Window]::GetWindow($this).Close() })
		If($NegativeText)
			{
				$No.Content = $NegativeText
				$No.Add_Click({ [System.Windows.Window]::GetWindow($this).Close() })
			}
		Else
			{
				# A single button never runs anything on Escape: only a click confirms.
				$No.Visibility = 'Collapsed'
			}
		$Global:SelfX_DialogResult = 'Negative'
		[void]$Dialog.ShowDialog()
		return $Global:SelfX_DialogResult
	}

#******************************************************************************
# Troubleshooting page: view (simplified/detailed), category filter and search
#******************************************************************************
# Adds the icon and a one-line explanation to the localized catalogue actions.
foreach($Action in @($Global:SelfX_Quick_Actions + $Global:SelfX_Detailed_Actions))
	{
		$Glyph = $Global:SelfX_CategoryGlyphs[[string]$Action.CategoryId]
		If(-not $Glyph) { $Glyph = 0xE90F }
		$Action | Add-Member -NotePropertyName Glyph -NotePropertyValue ([string][char]$Glyph) -Force
		$Short = (("$($Action.Explanation)" -split "\r?\n") | Where-Object { $_.Trim() } | Select-Object -First 1)
		$Action | Add-Member -NotePropertyName ShortExplanation -NotePropertyValue "$Short".Trim() -Force
		# True while the action runs (start button shows a rotating icon, see ActionTemplate).
		$Action | Add-Member -NotePropertyName Running -NotePropertyValue $False -Force
	}
$Global:SelfX_Category = ''

Function Get-SelfXCurrentActions
	{
		If($Mode_Detailed.IsChecked) { return $Global:SelfX_Detailed_Actions }
		return $Global:SelfX_Quick_Actions
	}

# Shows the actions of the current view that match the category and the search text.
Function Update-SelfXActionList
	{
		$Search = "$($FilterTextBox.Text)".Trim()
		$Shown = @(Get-SelfXCurrentActions | Where-Object {
			((-not $Global:SelfX_Category) -or ($_.Category -eq $Global:SelfX_Category)) -and
			((-not $Search) -or ("$($_.Name)".IndexOf($Search, [StringComparison]::CurrentCultureIgnoreCase) -ge 0))
		})
		$ActionsList.ItemsSource = $Shown
		$Actions_Count.Text = Get-SelfXString 'Available_Actions_Count' $Shown.Count
	}

# Category buttons ("All" and the categories of the current view).
Function Update-SelfXCategories
	{
		$Global:SelfX_Category = ''
		$Categories.Items.Clear()
		$Names = @('') + @(Get-SelfXCurrentActions | ForEach-Object { "$($_.Category)" } | Sort-Object -Unique)
		foreach($Name in $Names)
			{
				$Pill = New-Object System.Windows.Controls.RadioButton
				$Pill.Style = $Form.FindResource('Pill')
				$Pill.GroupName = 'Category'
				$Pill.Tag = $Name
				$Pill.Content = $(If($Name) { $Name } Else { Get-SelfXString 'Filter_All_Text' })
				$Pill.IsChecked = (-not $Name)
				$Pill.Add_Checked({ $Global:SelfX_Category = [string]$this.Tag; Update-SelfXActionList })
				[void]$Categories.Items.Add($Pill)
			}
		Update-SelfXActionList
	}

$Mode_Simple.Add_Checked({ Update-SelfXCategories })
$Mode_Detailed.Add_Checked({ Update-SelfXCategories })
$FilterTextBox.Add_TextChanged({
	$Has_Text = [bool]$FilterTextBox.Text
	$SearchHint.Visibility = $(If($Has_Text) { 'Collapsed' } Else { 'Visible' })
	$Btn_ClearSearch.Visibility = $(If($Has_Text) { 'Visible' } Else { 'Collapsed' })
	Update-SelfXActionList
})
$Btn_ClearSearch.Add_Click({ $FilterTextBox.Text = ''; $FilterTextBox.Focus() })
$Btn_ViewHelp.Add_Click({
	[void](Show-SelfXDialog -Title (Get-SelfXString 'Solution_Mode_Info_Title') -Message (Get-SelfXString 'Solution_Mode_Info_Text') -AffirmativeText (Get-SelfXString 'Button_Ok'))
})
If((Get-SelfXText "Default_Solution_Mode" "Simplified") -eq "Detailed") { $Mode_Detailed.IsChecked = $true } Else { $Mode_Simple.IsChecked = $true }

# Running state of the actions: the start button of a running action shows a rotating icon (ActionTemplate).
# PowerShell objects do not notify WPF, so the list is refreshed after every change.
$Global:SelfX_UserRuns = New-Object System.Collections.Generic.List[object]
Function Set-SelfXActionRunning
	{
		param($Row, [bool]$Running)
		If(-not $Row) { return }
		$Row.Running = $Running
		Try { $ActionsList.Items.Refresh() } Catch {}
	}

# User actions run in their own process: watched here until the script has ended, then the result is shown.
$UserRun_Timer = New-Object System.Windows.Threading.DispatcherTimer
$UserRun_Timer.Interval = [TimeSpan]::FromMilliseconds(500)
$UserRun_Timer.Add_Tick({
	foreach($Run in $Global:SelfX_UserRuns.ToArray())
		{
			If(-not $Run.Process.HasExited) { continue }
			$Code = $Run.Process.ExitCode
			$Run.Process.Dispose()
			[void]$Global:SelfX_UserRuns.Remove($Run)
			Write-SelfXLog "User action finished: $($Run.Script), exit code $Code." $(If($Code) { 'Warning' } Else { 'Info' })
			If(-not @($Global:SelfX_UserRuns.ToArray() | Where-Object { [object]::ReferenceEquals($_.Row, $Run.Row) }).Count) { Set-SelfXActionRunning $Run.Row $False }
			$msgbar.Clear()
			If($Code -eq 0) { $msgbar.SetSuccessAlert((Get-SelfXString 'Action_Success_Text' $Run.Name)) }
			Else { $msgbar.SetDangerAlert((Get-SelfXString 'Action_Failed_ExitCode_Text' $Run.Name $Code)) }
		}
	If(-not $Global:SelfX_UserRuns.Count) { $UserRun_Timer.Stop() }
})

# Runs the action after the confirmation of the catalogue (Alerte_MSG with the configured buttons).
Function Run_Remediation($rowObj)
	{
		$Script_Name = $rowObj.Script
		$AlerteWarning = $rowObj.Alerte_MSG
		$AlerteButtons = "$($rowObj.Buttons)".Trim()
		# Link action: confirmation, then the https address of the setting is opened in the browser of the user. No script runs.
		If(([string]$rowObj.Context).Trim() -eq 'Link')
			{
				$Link = Resolve-SelfXCatalogLink -Key ([string]$rowObj.Link).Trim() -Value (Get-SelfXText ([string]$rowObj.Link).Trim() '')
				If($Link.State -ne 'Ok') { Write-SelfXLog "Link action '$($rowObj.Id)' was not opened: setting is $($Link.State)." 'Warning'; return }
				$Link_Result = Show-SelfXDialog -Title "$Run_Solution_Text" -Message "$AlerteWarning" -AffirmativeText (Get-SelfXButtonText 'Ok') -NegativeText (Get-SelfXButtonText 'Cancel') -Kind Question
				Write-SelfXLog "Link action '$($rowObj.Name)': user answered $Link_Result."
				If($Link_Result -eq 'Affirmative')
					{
						Try
							{
								Start-Process $Link.Uri
								Write-SelfXLog "Link action '$($rowObj.Id)': opened (host $(([uri]$Link.Uri).Host))."
							}
						Catch
							{
								$msgbar.Clear()
								$msgbar.SetDangerAlert((Get-SelfXString 'Action_Failed_Text' "$($rowObj.Name) ($($_.Exception.Message))"))
							}
					}
				return
			}
		If([string]::IsNullOrWhiteSpace($Script_Name)) { return }
		# The action runs already (its start button is locked; this also covers a second request from the tray).
		If($rowObj.Running) { return }
		$Script_Name = ([string]$Script_Name).Trim()
		$Action_Context = ([string]$rowObj.Context).Trim()

		If(($Action_Context -eq "System") -and ($Global:SvcAction_Running -or $Global:FreeSpace_Active))
			{
				$msgbar.Clear()
				$msgbar.SetWarningAlert($Service_Busy_Text)
				return
			}

		If($AlerteButtons -eq "OK")
			{
				$Yes_Text = Get-SelfXString 'Button_Ok'
				$No_Text = ''
			}
		Else
			{
				# Button tokens of the catalogue (for example Yes_No or Ok_Cancel) are translated
				$BTN_Split = $AlerteButtons.Split("_")
				$Yes_Text = Get-SelfXButtonText $BTN_Split[0]
				$No_Text = Get-SelfXButtonText $(If($BTN_Split.Count -gt 1) { $BTN_Split[1] } Else { 'Cancel' })
			}

		$result = Show-SelfXDialog -Title "$Run_Solution_Text" -Message "$AlerteWarning" -AffirmativeText $Yes_Text -NegativeText $No_Text -Kind Question
		Write-SelfXLog "Action '$($rowObj.Name)' ($Script_Name, context $Action_Context): user answered $result."
		If($result -eq "Affirmative")
			{
				If($Action_Context -eq "System")
					{
						Start-SelfXSystemAction -Script $Script_Name -ActionName $rowObj.Name -PostAction ([string]$rowObj.Post_Action).Trim() -Row $rowObj
					}
				Else
					{
						# The script of the project (App\Scripts_to_run) or an own script of the company that is listed in SelfX.Config.json
						# with its current SHA256 (Config\Scripts_to_run); anything else is not started.
						$Script_Path = Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName $Script_Name -CodeRoot $Current_Folder
						If($Script_Path)
							{
								# User actions run in their own process and log their result themselves (Logs\Users\<SID>).
								Try
									{
										$Process = Start-SelfXHiddenPowerShell -Path $Script_Path -WorkingDirectory $Current_Folder -PassThru
										Write-SelfXLog "User action started: $Script_Name (process $($Process.Id))"
										$Global:SelfX_UserRuns.Add([pscustomobject]@{ Row = $rowObj; Process = $Process; Name = "$($rowObj.Name)"; Script = $Script_Name })
										Set-SelfXActionRunning $rowObj $True
										$msgbar.Clear()
										$msgbar.SetInformationAlert((Get-SelfXString 'Action_Running_Text' $rowObj.Name))
										$UserRun_Timer.Start()
									}
								Catch
									{
										$msgbar.Clear()
										$msgbar.SetDangerAlert((Get-SelfXString 'Action_Failed_Text' "$($rowObj.Name) ($($_.Exception.Message))"))
									}
							}
						Else
							{
								$msgbar.Clear()
								$msgbar.SetDangerAlert((Get-SelfXString 'Script_Not_Found_Text' $Script_Name))
							}
					}
			}
	}

Function See_Details($rowObj)
	{
		[void](Show-SelfXDialog -Title "$Run_Explanation_Text" -Message "$($rowObj.Explanation)" -AffirmativeText (Get-SelfXString 'Button_Ok'))
	}

$ActionsList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
	param($sender, $event)
	$Button = $event.OriginalSource
	If($Button -isnot [System.Windows.Controls.Button]) { return }
	$Row = $Button.DataContext
	Switch("$($Button.Tag)")
		{
			'Run'  { Run_Remediation -rowObj $Row }
			'Info' { See_Details -rowObj $Row }
		}
})

#******************************************************************************
# Actions with Context "System" are sent to the local SelfX service (runs as SYSTEM)
#******************************************************************************
$Global:SvcAction_Running = $False
# Repairs that SelfX treats specially (Health_Config.xml): the restart needs its own warning and never runs in
# "Fix all problems"; the update and app repairs report that they continue in the background.
$Global:SelfX_RestartScript = 'SelfX_Device_Restart.ps1'
$Global:SelfX_UpdatesScript = 'SelfX_Updates_Install.ps1'
$Global:SelfX_AppsScript = 'SelfX_Apps_RetryInstall.ps1'
$Global:SelfX_FreeSpaceScript = 'SelfX_Device_FreeSpace.ps1'

# Repairs with two parts (Health_Config.xml, Remediation UserScript): SelfX starts the part of the user itself (with the rights of
# the user, never through the service) and, when it has ended, the SYSTEM part through the service. Only names that the health
# result carries are used; SelfX resolves the user script like a user action of the catalogue (Resolve-SelfXScriptPath).
$Global:FreeSpace_Active = $False
$Global:FreeSpace_Pending = $False
$Global:FreeSpace_Card = $null
$Global:FreeSpace_Process = $null
$Global:FreeSpace_Before = $null
$Global:FreeSpace_TeamsSkipped = $False

# Free space in GB of the drive of the card (for example C:), or of the Windows drive; $null when it cannot be read.
Function Get-SelfXDriveFreeGB
	{
		param([string]$Drive = '')
		Try
			{
				If($Drive -notmatch '^[A-Za-z]:$') { $Drive = [IO.Path]::GetPathRoot([Environment]::SystemDirectory).TrimEnd('\') }
				Return ((New-Object System.IO.DriveInfo ($Drive + '\')).AvailableFreeSpace / 1GB)
			}
		Catch { Return $null }
	}

# Result sentence of "Free up space": free space before and now; a hint when the Teams cache was kept.
Function Get-SelfXFreeSpaceResultText
	{
		param([string]$Key)
		$Drive = "$($Global:FreeSpace_Card.HealthName)"
		$After = Get-SelfXDriveFreeGB $Drive
		$Before_Text = $(If($null -ne $Global:FreeSpace_Before) { '{0:N1}' -f $Global:FreeSpace_Before } Else { '?' })
		$After_Text = $(If($null -ne $After) { '{0:N1}' -f $After } Else { '?' })
		$Text = Get-SelfXString $Key $Drive $Before_Text $After_Text
		If($Global:FreeSpace_TeamsSkipped) { $Text += ' ' + (Get-SelfXString 'Health_FreeSpace_TeamsSkipped') }
		Return $Text
	}

$FreeSpace_Timer = New-Object System.Windows.Threading.DispatcherTimer
$FreeSpace_Timer.Interval = [TimeSpan]::FromMilliseconds(500)
$FreeSpace_Timer.Add_Tick({
	If($Global:FreeSpace_Process -and -not $Global:FreeSpace_Process.HasExited) { return }
	$FreeSpace_Timer.Stop()
	$Code = $null
	If($Global:FreeSpace_Process) { $Code = $Global:FreeSpace_Process.ExitCode; $Global:FreeSpace_Process.Dispose(); $Global:FreeSpace_Process = $null }
	$Card = $Global:FreeSpace_Card
	# Exit 2 of the user part of "Free up space": done, but Teams was open and its cache was kept.
	$Global:FreeSpace_TeamsSkipped = ($Code -eq 2) -and ($Card.Remediation -eq $Global:SelfX_FreeSpaceScript)
	Write-SelfXLog "Repair '$($Card.Property)': user part $($Card.UserRemediation) finished, exit code $Code." $(If($Code -in @(0, 2)) { 'Info' } Else { 'Warning' })
	# The part of the user frees what it can; the SYSTEM part runs in any case (they do not depend on each other).
	$Global:FreeSpace_Active = $False
	$Global:FreeSpace_Pending = $True
	Start-SelfXSystemAction -Script $Card.Remediation -ActionName $Card.Property -RefreshHealth -HealthId "$($Card.HealthId)" -HealthName "$($Card.HealthName)"
	If(-not ($Global:SvcAction_Running -and ($Global:SvcAction_Script -eq $Card.Remediation))) { $Global:FreeSpace_Pending = $False }
	Update-SelfXStatusView
})

Function Start-SelfXTwoPartRepair
	{
		param($Card)
		If($Global:SvcAction_Running -or $Global:FreeSpace_Active -or (Test-SelfXCheckRunning)) { $msgbar.SetWarningAlert($Service_Busy_Text); return }
		$Script_Path = Resolve-SelfXScriptPath -Folder 'Scripts_to_run' -FileName "$($Card.UserRemediation)" -CodeRoot $Current_Folder
		If(-not $Script_Path)
			{
				$msgbar.Clear()
				$msgbar.SetDangerAlert((Get-SelfXString 'Script_Not_Found_Text' "$($Card.UserRemediation)"))
				return
			}
		$Global:FreeSpace_Card = $Card
		$Global:FreeSpace_Before = Get-SelfXDriveFreeGB "$($Card.HealthName)"
		$Global:FreeSpace_TeamsSkipped = $False
		$Global:FreeSpace_Pending = $False
		Try { $Global:FreeSpace_Process = Start-SelfXHiddenPowerShell -Path $Script_Path -WorkingDirectory $Current_Folder -PassThru }
		Catch
			{
				$msgbar.Clear()
				$msgbar.SetDangerAlert((Get-SelfXString 'Action_Failed_Text' "$($Card.Property) ($($_.Exception.Message))"))
				return
			}
		$Global:FreeSpace_Active = $True
		Write-SelfXLog "Repair '$($Card.Property)': user part started: $($Card.UserRemediation) (process $($Global:FreeSpace_Process.Id))."
		$msgbar.Clear()
		$msgbar.SetInformationAlert((Get-SelfXString 'Action_Running_Text' $Card.Property))
		Update-SelfXFixAllButton
		Update-SelfXStatusView
		$FreeSpace_Timer.Start()
	}
# The quick scan reports its result in its own words: exit code 0 = no threats, 2 = Defender found threats (details in Windows Security).
$Global:SelfX_ScanScript = 'SelfX_Defender_QuickScan.ps1'
$SvcAction_Timer = New-Object System.Windows.Threading.DispatcherTimer
$SvcAction_Timer.Interval = [TimeSpan]::FromMilliseconds(500)
$SvcAction_Timer.Add_Tick({
	If(-not $Global:SvcAction_Handle.IsCompleted) { return }
	$SvcAction_Timer.Stop()
	Try
		{
			$Result = @($Global:SvcAction_PS.EndInvoke($Global:SvcAction_Handle)) | Select-Object -Last 1
		}
	Catch
		{
			$Result = [pscustomobject]@{ Status = 'Error'; ExitCode = $null; Message = $_.Exception.Message }
		}
	$Global:SvcAction_PS.Dispose()
	If($Global:SvcAction_Runspace) { $Global:SvcAction_Runspace.Dispose(); $Global:SvcAction_Runspace = $null }
	$Global:SvcAction_Running = $False
	$Form.Cursor = $null
	Update-SelfXFixAllButton
	# The action has ended: start / Fix button back to normal.
	Set-SelfXActionRunning $Global:SvcAction_Row $False
	$Global:SvcAction_Row = $null
	Update-SelfXStatusView

	$msgbar.Clear()
	Write-SelfXLog ("Service action '{0}' ({1}): {2}, exit code {3}. {4}" -f $Global:SvcAction_Name, $Global:SvcAction_Script, $Result.Status, $Result.ExitCode, $Result.Message) $(If($Result.Status -eq 'Success') { 'Info' } Else { 'Warning' })
	Switch($Result.Status)
		{
			'Success'     {
				If($Global:FreeSpace_Pending) { $msgbar.SetSuccessAlert((Get-SelfXFreeSpaceResultText 'Health_FreeSpace_Done')) }
				ElseIf($Global:SvcAction_PostAction -eq 'MailReport') { Show-SelfXReportMailResult -Report $Result.Report }
				ElseIf($Global:SvcAction_Script -and ($Global:SvcAction_Script -eq $Global:SelfX_RestartScript)) { $msgbar.SetWarningAlert((Get-SelfXString 'Health_Restart_Started')) }
				ElseIf($Global:SvcAction_Script -and ($Global:SvcAction_Script -eq $Global:SelfX_UpdatesScript) -and -not $Global:FixAll_Active) { $msgbar.SetSuccessAlert((Get-SelfXString 'Health_Updates_Done')) }
				ElseIf($Global:SvcAction_Script -and ($Global:SvcAction_Script -eq $Global:SelfX_AppsScript) -and -not $Global:FixAll_Active) { $msgbar.SetSuccessAlert((Get-SelfXString 'Health_Apps_Started')) }
				ElseIf($Global:SvcAction_Script -and ($Global:SvcAction_Script -eq $Global:SelfX_ScanScript)) { $msgbar.SetSuccessAlert((Get-SelfXString 'Defender_Scan_Clean_Text')) }
				Else { $msgbar.SetSuccessAlert((Get-SelfXString 'Action_Success_Text' $Global:SvcAction_Name)) }
			}
			'Failed'      {
				If($Global:FreeSpace_Pending) { $msgbar.SetWarningAlert((Get-SelfXFreeSpaceResultText 'Health_FreeSpace_Partial')) }
				ElseIf($Global:SvcAction_Script -and ($Global:SvcAction_Script -eq $Global:SelfX_ScanScript) -and ($Result.ExitCode -eq 2)) { $msgbar.SetWarningAlert((Get-SelfXString 'Defender_Scan_Threats_Text')) }
				Else { $msgbar.SetDangerAlert((Get-SelfXString 'Action_Failed_ExitCode_Text' $Global:SvcAction_Name $Result.ExitCode)) }
			}
			'Busy'        { $msgbar.SetWarningAlert($Service_Busy_Text) }
			'OtherSessions' { $msgbar.SetWarningAlert($Service_OtherSessions_Text) }
			'TerminalServer' { $msgbar.SetWarningAlert((Get-SelfXString 'Service_TerminalServer_Text')) }
			'Timeout'     { $msgbar.SetDangerAlert((Get-SelfXString 'Action_Timeout_Text' $Global:SvcAction_Name)) }
			'Unavailable' { $msgbar.SetDangerAlert($Service_Unavailable_Text); Update-SelfXServiceStatus }
			Default       { $msgbar.SetDangerAlert((Get-SelfXString 'Action_Failed_Text' "$Global:SvcAction_Name ($($Result.Message))")) }
		}
	$Global:FreeSpace_Pending = $False
	if ($Global:FixAll_Active) {
		# "Fix all problems": count the result, stop when the service is gone or busy, then run the next repair.
		If($Result.Status -eq 'Success') { $Global:FixAll_Success++ } Else { $Global:FixAll_Failed.Add($Global:FixAll_Current) }
		If($Result.Status -in @('Unavailable', 'Busy'))
			{
				while($Global:FixAll_Queue.Count) { $Global:FixAll_Failed.Add("$($Global:FixAll_Queue.Dequeue().Property)") }
			}
		$Global:SvcAction_RefreshHealth = $False
		Start-SelfXNextFixAll
		return
	}
	if ($Global:SvcAction_RefreshHealth) {
		$Global:SvcAction_RefreshHealth = $False
		# Windows restarts in a few seconds: no further check.
		If(($Result.Status -eq 'Success') -and $Global:SvcAction_Script -and ($Global:SvcAction_Script -eq $Global:SelfX_RestartScript)) { return }
		# Installed updates change several rows (updates, pending restart, compliance): check everything.
		If($Global:SvcAction_Script -and ($Global:SvcAction_Script -eq $Global:SelfX_UpdatesScript)) { Start-SysInfoHealthCheck -Id '' -Name ''; return }
		# Re-check only the remediated status; Start-SysInfoHealthCheck falls back to a full refresh.
		Start-SysInfoHealthCheck -Id $Global:SvcAction_HealthId -Name $Global:SvcAction_HealthName
	}
})

Function Start-SelfXSystemAction
	{
		param(
		[string]$Script,
		[string]$ActionName,
		[switch]$RefreshHealth,
		[string]$HealthId = '',
		[string]$HealthName = '',
		[string]$PostAction = '',
		$Row = $null
		)
		if ($Global:SvcAction_Running) { $msgbar.SetWarningAlert($Service_Busy_Text); return }
		$Global:SvcAction_RefreshHealth = [bool]$RefreshHealth
		$Global:SvcAction_HealthId = $HealthId
		$Global:SvcAction_HealthName = $HealthName
		$Global:SvcAction_PostAction = $PostAction
		$Global:SvcAction_Running = $True
		$Global:SvcAction_Name = $ActionName
		$Global:SvcAction_Script = $Script
		Write-SelfXLog "Service action '$ActionName' requested: $Script"
		# STA lets the MailReport step use the Outlook COM interface in the background.
		$Global:SvcAction_Runspace = [runspacefactory]::CreateRunspace()
		$Global:SvcAction_Runspace.ApartmentState = 'STA'
		$Global:SvcAction_Runspace.Open()
		$Run_Command = "Invoke-SelfXSystemAction -Script '$($Script -replace "'", "''")'"
		If($PostAction -eq 'MailReport')
			{
				# Texts are prepared here in the language of the user; the background runspace only opens the e-mail.
				$Global:SvcAction_Runspace.SessionStateProxy.SetVariable('SelfXMail', @{
					To      = $(If(Test-SelfXTicketAddress ("$Support_Mail".Trim())) { "$Support_Mail".Trim() } Else { '' })
					Subject = Get-SelfXString 'Report_Mail_Subject' $env:COMPUTERNAME
					Body    = (Get-SelfXString 'Report_Mail_Body' $env:COMPUTERNAME (ConvertTo-SelfXUserTime ([datetime]::UtcNow)).ToString('g')) + "`r`n`r`n"
					# Days of the own user logs added to the report (SupportReport.ps1 checks 1-60, default 7).
					Days    = Get-SelfXConfigValue 'DeviceLogs_Days' '7'
				})
				$Run_Command = $Global:SelfXSupportReport_Script + "`r`n" +
					"`$Result = $Run_Command`r`n" +
					"If(`$Result.Status -eq 'Success') { `$Result | Add-Member -NotePropertyName Report -NotePropertyValue (Send-SelfXSupportReport @SelfXMail) }`r`n" +
					"`$Result"
			}
		$Global:SvcAction_PS = [PowerShell]::Create()
		$Global:SvcAction_PS.Runspace = $Global:SvcAction_Runspace
		[void]$Global:SvcAction_PS.AddScript($Global:SelfXClient_Script + "`r`n" + $Run_Command)
		$Global:SvcAction_Handle = $Global:SvcAction_PS.BeginInvoke()
		$Form.Cursor = [System.Windows.Input.Cursors]::AppStarting
		$msgbar.Clear()
		# Installing updates takes minutes: say so, the Fix button shows "Running..." meanwhile.
		If(($Script -eq $Global:SelfX_UpdatesScript) -and -not $Global:FixAll_Active) { $msgbar.SetInformationAlert((Get-SelfXString 'Health_Updates_Started')) }
		Else { $msgbar.SetInformationAlert((Get-SelfXString 'Action_Running_Text' $ActionName)) }
		$SvcAction_Timer.Start()
		Update-SelfXFixAllButton
		# Start button of the action (or Fix button of the status card) shows that the action runs.
		$Global:SvcAction_Row = $Row
		Set-SelfXActionRunning $Row $True
		Update-SelfXStatusView
	}

# Result of the MailReport step (Send-SelfXSupportReport in SupportReport.ps1) for the user
Function Show-SelfXReportMailResult
	{
		param($Report)
		$Support_Address = If([string]::IsNullOrWhiteSpace($Support_Mail)) { Get-SelfXString 'Report_Support_Fallback' } Else { $Support_Mail.Trim() }
		Switch("$($Report.Status)")
			{
				'Outlook'            { $msgbar.SetSuccessAlert((Get-SelfXString 'Report_Mail_Opened_Text')) }
				'OutlookCommandLine' { $msgbar.SetSuccessAlert((Get-SelfXString 'Report_Mail_Recipient_Text' $Support_Address)) }
				'Manual'             { $msgbar.SetWarningAlert((Get-SelfXString 'Report_Mail_Manual_Text' $Report.Path $Support_Address)) }
				Default              { $msgbar.SetDangerAlert((Get-SelfXString 'Report_Not_Found_Text' "$($Report.Message)")) }
			}
	}

# State of the local service in the navigation bar (green = running, red = not available)
Function Update-SelfXServiceStatus
	{
		If(Test-SelfXService)
			{
				$ServiceDot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, 'OkSolid')
				$ServiceLabel.Text = Get-SelfXString 'Service_Short_Running'
				$ServicePill.ToolTip = $Service_Running_Text
			}
		Else
			{
				$ServiceDot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, 'ErrSolid')
				$ServiceLabel.Text = Get-SelfXString 'Service_Short_Unavailable'
				$ServicePill.ToolTip = $Service_Unavailable_Text
			}
	}

# "Send logs to support" runs the first catalog action with Post_Action MailReport (same confirmation and flow)
$Global:SysInfo_SendLogs_Action = @($Global:SelfX_Detailed_Actions + $Global:SelfX_Quick_Actions |
	Where-Object { ($_.Post_Action -eq 'MailReport') -and ($_.Context -eq 'System') }) | Select-Object -First 1
If($Global:SysInfo_SendLogs_Action -eq $null)
	{
		$SysInfo_SendLogs.Visibility = "Collapsed"
		$Btn_SendLogs.Visibility = "Collapsed"
	}
Else
	{
		$SysInfo_SendLogs.Add_Click({ Run_Remediation -rowObj $Global:SysInfo_SendLogs_Action })
		$Btn_SendLogs.Add_Click({ Run_Remediation -rowObj $Global:SysInfo_SendLogs_Action })
	}

# Help area of the navigation: with the ticket function the big "open a ticket" button replaces "Send logs to support"
# (the ticket e-mail carries the device information; the log report stays on the system information page); Copilot Chat has its own button when it is switched on. Both only open the same dialogs as the help window.
If($Ticket_Available)
	{
		$Btn_Ticket.Visibility = 'Visible'
		$Btn_SendLogs.Visibility = 'Collapsed'
		$Btn_Ticket.Add_Click({ Show-SelfXTicketDialog })
	}
If($Copilot_Available)
	{
		$Btn_Copilot.Visibility = 'Visible'
		$Btn_Copilot.Add_Click({ Show-SelfXCopilotDialog })
	}
If($Wiki.Available)
	{
		$Btn_Wiki.Visibility = 'Visible'
		$Btn_Wiki.Add_Click({ Open-SelfXUri $Wiki.Uri })
	}

#******************************************************************************
# Device status page: cached status of the service, full check, single check, Fix
#******************************************************************************
$Global:Health_Items = @()
$Global:Health_CollectedAt = $null
$Global:Health_State = ''
$Global:Health_Interval = 0
$Global:Health_Busy = $False
$Global:Health_Message = ''
$Global:Health_Unavailable = $False
$Global:Health_PendingCheck = $null
$Global:Health_AutoFull = $False

# Runs Get-SelfXStatusData (SystemInfo.ps1) in a background runspace: Cached, Full or Single.
Function Start-SelfXHealthJob
	{
		param([ValidateSet('Cached', 'Full', 'Single')][string]$Mode, [string]$Id = '', [string]$Name = '')
		# Terminal server without the device status for this user: no request to the service (it would refuse it).
		If(-not $Global:SelfX_View.Health) { return $False }
		If($Global:Health_Busy) { return $False }
		$Global:Health_Busy = $True
		$Global:Health_Job = $Mode
		$Global:Health_PS = [PowerShell]::Create()
		[void]$Global:Health_PS.AddScript($Global:SysInfo_Script).AddStatement().AddCommand('Get-SelfXStatusData').AddParameter('Mode', $Mode).AddParameter('Id', $Id).AddParameter('Name', $Name).AddParameter('Text', $Global:SysInfo_Texts)
		$Global:Health_Handle = $Global:Health_PS.BeginInvoke()
		$Health_Timer.Start()
		Update-SelfXStatusView
		return $True
	}

# A check runs (all or one status). Reading the cached status every minute takes only a moment and blocks nothing:
# the service answers STATUS without a lock, so a repair can start meanwhile.
Function Test-SelfXCheckRunning { return [bool]($Global:Health_Busy -and ($Global:Health_Job -ne 'Cached')) }

# Re-checks a single health status (card button and after a remediation). Unknown ids trigger a full check.
Function Start-SysInfoHealthCheck
	{
		param([string]$Id, [string]$Name)
		If($Global:Health_Busy) { $Global:Health_PendingCheck = @{ Id = $Id; Name = $Name }; return }
		If($Id -notin @('IME','Defender','Compliance','Applications','Disk','BitLocker','PendingReboot','Updates','Service','Custom')) { [void](Start-SelfXHealthJob -Mode Full); return }
		[void](Start-SelfXHealthJob -Mode Single -Id $Id -Name $Name)
	}

# Replaces the row(s) of one health check in place; all other rows stay unchanged.
Function Merge-SysInfoHealthItems
	{
		param([object[]]$Items, [string]$Id, [string]$Name, [object[]]$Results)
		$Results = @($Results | Where-Object { $_ -and "$($_.Status)" })
		If(-not $Results.Count) { return $Items }
		$Merged = New-Object System.Collections.Generic.List[object]
		$Inserted = $False
		foreach($Item in $Items)
			{
				If("$($Item.HealthId)" -eq $Id -and "$($Item.HealthName)" -eq $Name)
					{
						If(-not $Inserted) { foreach($Result in $Results) { $Merged.Add($Result) }; $Inserted = $True }
					}
				Else { $Merged.Add($Item) }
			}
		If(-not $Inserted) { foreach($Result in $Results) { $Merged.Add($Result) } }
		return $Merged.ToArray()
	}

$Health_Timer = New-Object System.Windows.Threading.DispatcherTimer
$Health_Timer.Interval = [TimeSpan]::FromMilliseconds(300)
$Health_Timer.Add_Tick({
	If(-not $Global:Health_Handle.IsCompleted) { return }
	$Health_Timer.Stop()
	Try { $Data = @($Global:Health_PS.EndInvoke($Global:Health_Handle)) | Select-Object -Last 1 }
	Catch { $Data = [pscustomobject]@{ Mode = $Global:Health_Job; Ok = $False; Message = $_.Exception.Message; Items = @() } }
	$Global:Health_PS.Dispose()
	$Global:Health_Busy = $False
	$Start_Full = $False
	# Checks started by the user are logged with their result (not the cached status read every minute).
	If("$($Data.Mode)" -ne 'Cached')
		{
			If(-not $Data.Ok) { Write-SelfXLog "Status check ($($Data.Mode) $($Data.Id)) failed: $($Data.Message)" Warning }
			Else { foreach($Item in @($Data.Items)) { Write-SelfXLog "Status $($Item.Property): $($Item.Status) - $($Item.Detail)" } }
		}
	If(-not $Data.Ok)
		{
			$Global:Health_Unavailable = $True
			$Global:Health_Message = "$($Data.Message)"
		}
	Else
		{
			$Global:Health_Unavailable = $False
			Switch($Data.Mode)
				{
					'Cached' {
						$Global:Health_State = "$($Data.State)"
						$Global:Health_Interval = [int]$Data.IntervalMinutes
						If(@($Data.Items).Count)
							{
								$Global:Health_Items = @($Data.Items)
								$Global:Health_CollectedAt = $Data.CollectedAt
							}
						ElseIf(-not $Global:Health_AutoFull)
							{
								# No background result yet (for example right after the start of the service): check now once.
								$Global:Health_AutoFull = $True
								$Start_Full = $True
							}
					}
					'Full' {
						$Global:Health_Items = @($Data.Items)
						$Global:Health_CollectedAt = $Data.CollectedAt
					}
					'Single' {
						$Global:Health_Items = @(Merge-SysInfoHealthItems -Items $Global:Health_Items -Id $Data.Id -Name $Data.Name -Results @($Data.Items))
					}
				}
		}
	Update-SelfXStatusView
	If($Start_Full) { [void](Start-SelfXHealthJob -Mode Full) }
	ElseIf($Global:Health_PendingCheck)
		{
			$Next = $Global:Health_PendingCheck
			$Global:Health_PendingCheck = $null
			Start-SysInfoHealthCheck -Id $Next.Id -Name $Next.Name
		}
})

# Formats a time in the time zone of the user: only the time for today, else date and time.
Function Format-SelfXTime
	{
		param([datetime]$Time)
		$Time = ConvertTo-SelfXUserTime $Time
		If($Time.Date -eq [datetime]::Now.Date) { return $Time.ToString('t') }
		return $Time.ToString('g')
	}

# "Fix all problems": visible while at least one error or warning has a configured repair.
$Global:Health_FixAll_Cards = @()
$Global:FixAll_Active = $False
$Global:FixAll_Queue = New-Object System.Collections.Queue
Function Update-SelfXFixAllButton
	{
		$Btn_FixAll.Visibility = $(If(@($Global:Health_FixAll_Cards).Count -or $Global:FixAll_Active) { 'Visible' } Else { 'Collapsed' })
		$Btn_FixAll.IsEnabled = -not ((Test-SelfXCheckRunning) -or $Global:SvcAction_Running -or $Global:FixAll_Active -or $Global:FreeSpace_Active)
	}

Function Update-SelfXStatusView
	{
		$Order = @{ Error = 0; Pending = 1; Unknown = 2; OK = 3 }
		$Index = 0
		$Cards = @($Global:Health_Items | ForEach-Object {
			# Terminal server: a repair that is not classified Show has no button (and its part of the user is not offered).
			$Offered = Test-SelfXRemediationOffered -Mode "$($Global:SelfX_Environment.Mode)" -Script "$($_.Remediation)" -Classification $Global:SelfX_RemediationClassification
			$Remediation = $(If($Offered) { "$($_.Remediation)" } Else { '' })
			$UserRemediation = $(If($Offered) { "$($_.UserRemediation)" } Else { '' })
			$Glyph = $Global:SelfX_HealthGlyphs["$($_.HealthId)"]
			If(-not $Glyph) { $Glyph = 0xE9D9 }
			$Fix_Text = Get-SelfXString 'Health_Fix'
			$Fix_Glyph = 0xE90F
			If("$($_.Remediation)" -and ("$($_.Remediation)" -eq $Global:SelfX_RestartScript)) { $Fix_Text = Get-SelfXString 'Health_Restart_Button'; $Fix_Glyph = 0xE777 }
			ElseIf("$($_.Remediation)" -and ("$($_.Remediation)" -eq $Global:SelfX_AppsScript)) { $Fix_Text = Get-SelfXString 'Health_Apps_Button'; $Fix_Glyph = 0xE896 }
			ElseIf("$($_.Remediation)" -and ("$($_.Remediation)" -eq $Global:SelfX_FreeSpaceScript)) { $Fix_Text = Get-SelfXString 'Health_FreeSpace_Button'; $Fix_Glyph = 0xE74D }
			# The repair of this card runs right now (Fix button with rotating icon and "Running ..."), also its part of the user.
			$Fix_Running = [bool](($Global:SvcAction_Running -and "$($_.Remediation)" -and ("$($_.Remediation)" -eq $Global:SvcAction_Script)) -or
				($Global:FreeSpace_Active -and "$($_.Remediation)" -and ("$($_.Remediation)" -eq "$($Global:FreeSpace_Card.Remediation)")))
			If($Fix_Running) { $Fix_Text = Get-SelfXString 'Action_Running_Label' }
			[pscustomobject]@{
				Property = $_.Property; Detail = $(If("$($_.Detail)") { "$($_.Detail)" } Else { "$($_.Value)" }); Status = "$($_.Status)"
				Remediation = $Remediation; UserRemediation = $UserRemediation; HasFix = [bool]$Remediation; HealthId = "$($_.HealthId)"; HealthName = "$($_.HealthName)"
				FixText = $Fix_Text; FixGlyph = [string][char]$Fix_Glyph; Running = $Fix_Running
				Glyph = [string][char]$Glyph; Rank = $Order["$($_.Status)"]; Index = $Index++
			}
		} | Sort-Object Rank, Index)
		$StatusCards.ItemsSource = $Cards

		$Errors = @($Cards | Where-Object { $_.Status -eq 'Error' }).Count
		$Warnings = @($Cards | Where-Object { $_.Status -eq 'Pending' }).Count
		$Issues = $Errors + $Warnings

		# Badge in the navigation: number of problems and warnings
		$NavBadge.Visibility = $(If($Issues) { 'Visible' } Else { 'Collapsed' })
		$NavBadgeText.Text = "$Issues"
		$NavBadge.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $(If($Errors) { 'ErrSolid' } Else { 'WarnSolid' }))

		$Status_Spinner.Visibility = $(If(Test-SelfXCheckRunning) { 'Visible' } Else { 'Collapsed' })
		$Btn_CheckAll.IsEnabled = -not (Test-SelfXCheckRunning)

		# One repair per script: several rows (for example two disks) can share the same repair.
		# The restart is never part of "Fix all problems": it would end all other repairs and the session. A repair with a part of
		# the user (UserScript, for example "Free up space") is not either: it has its own confirmation and can take long.
		$Seen = @{}
		$Global:Health_FixAll_Cards = @($Cards | Where-Object { $_.HasFix -and $_.Status -in @('Error', 'Pending') -and $_.Remediation -ne $Global:SelfX_RestartScript -and -not $_.UserRemediation } | Where-Object {
			$Key = "$($_.Remediation)".ToLowerInvariant()
			If($Seen.ContainsKey($Key)) { $False } Else { $Seen[$Key] = $True; $True }
		})
		Update-SelfXFixAllButton

		If($Global:Health_CollectedAt)
			{
				$Sub = Get-SelfXString 'Status_LastChecked_Text' (Format-SelfXTime $Global:Health_CollectedAt)
				If($Global:Health_State -eq 'Active' -and $Global:Health_Interval) { $Sub += '  ·  ' + (Get-SelfXString 'Status_Background_Text' $Global:Health_Interval) }
				If($Global:Health_State -eq 'Battery') { $Sub += '  ·  ' + (Get-SelfXString 'Status_Background_Battery_Text') }
				$Status_Subtitle.Text = $Sub
			}
		Else { $Status_Subtitle.Text = Get-SelfXString 'Status_NotChecked_Text' }

		$Banner = $null
		If($Global:Health_Unavailable -and -not $Cards.Count) { $Banner = @('ErrBg', 'ErrFg', 0xEA39, $Service_Unavailable_Text, $Global:Health_Message) }
		ElseIf(-not $Cards.Count) { $Banner = @('InfoBg', 'AccentText', 0xE946, (Get-SelfXString 'Status_Checking_Text'), '') }
		ElseIf($Issues) { $Banner = @($(If($Errors) { 'ErrBg' } Else { 'WarnBg' }), $(If($Errors) { 'ErrFg' } Else { 'WarnFg' }), 0xE7BA, (Get-SelfXString 'Status_Issues_Title' $Issues), (Get-SelfXString 'Status_Issues_Text')) }
		Else { $Banner = @('OkBg', 'OkFg', 0xE930, (Get-SelfXString 'Status_AllOk_Title'), (Get-SelfXString 'Status_AllOk_Text')) }
		$Status_Banner.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $Banner[0])
		$Status_BannerGlyph.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Banner[1])
		$Status_BannerGlyph.Text = [string][char]$Banner[2]
		$Status_BannerTitle.Text = $Banner[3]
		$Status_BannerText.Text = $Banner[4]
		$Status_BannerText.Visibility = $(If($Banner[4]) { 'Visible' } Else { 'Collapsed' })
	}

$StatusCards.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
	param($sender, $event)
	$Button = $event.OriginalSource
	If($Button -isnot [System.Windows.Controls.Button]) { return }
	$event.Handled = $True
	$Card = $Button.DataContext
	If(-not $Card) { return }
	If($Global:SvcAction_Running -or $Global:FreeSpace_Active -or (Test-SelfXCheckRunning))
		{
			$msgbar.SetWarningAlert($Service_Busy_Text)
			return
		}
	If("$($Button.Tag)" -eq 'Check')
		{
			# Only checks this status again; nothing is changed on the device.
			Start-SysInfoHealthCheck -Id "$($Card.HealthId)" -Name "$($Card.HealthName)"
			return
		}
	If(("$($Button.Tag)" -eq 'Fix') -and $Card.Remediation -and $Card.UserRemediation)
		{
			# Repair with a part of the user: one confirmation for both parts. "Free up space" lists what is deleted.
			If($Card.Remediation -eq $Global:SelfX_FreeSpaceScript)
				{
					$Answer = Show-SelfXDialog -Title (Get-SelfXString 'Health_FreeSpace_Title') -Message (Get-SelfXString 'Health_FreeSpace_Confirm' "$($Card.HealthName)") `
						-AffirmativeText (Get-SelfXString 'Button_Yes') -NegativeText (Get-SelfXString 'Button_No') -Kind Warning
				}
			Else
				{
					$Answer = Show-SelfXDialog -Title (Get-SelfXString 'Health_Fix') -Message (Get-SelfXString 'Health_Fix_Confirm' $Card.Property) `
						-AffirmativeText (Get-SelfXString 'Button_Yes') -NegativeText (Get-SelfXString 'Button_No') -Kind Warning
				}
			Write-SelfXLog "Fix '$($Card.Property)' ($($Card.UserRemediation), then $($Card.Remediation)): user answered $Answer."
			If($Answer -eq 'Affirmative') { Start-SelfXTwoPartRepair $Card }
			return
		}
	If(("$($Button.Tag)" -eq 'Fix') -and $Card.Remediation)
		{
			If($Card.Remediation -eq $Global:SelfX_RestartScript)
				{
					# Restart: own warning, the user must confirm explicitly (default button: cancel).
					$Answer = Show-SelfXDialog -Title (Get-SelfXString 'Health_Restart_Title') -Message (Get-SelfXString 'Health_Restart_Confirm') `
						-AffirmativeText (Get-SelfXString 'Button_Restart_Now') -NegativeText (Get-SelfXString 'Button_Cancel') -Kind Warning
				}
			Else
				{
					$Answer = Show-SelfXDialog -Title (Get-SelfXString 'Health_Fix') -Message (Get-SelfXString 'Health_Fix_Confirm' $Card.Property) `
						-AffirmativeText (Get-SelfXString 'Button_Yes') -NegativeText (Get-SelfXString 'Button_No') -Kind Warning
				}
			Write-SelfXLog "Fix '$($Card.Property)' ($($Card.Remediation)): user answered $Answer."
			If($Answer -eq 'Affirmative')
				{
					Start-SelfXSystemAction -Script $Card.Remediation -ActionName $Card.Property -RefreshHealth -HealthId "$($Card.HealthId)" -HealthName "$($Card.HealthName)"
				}
		}
})
$Btn_CheckAll.Add_Click({ Start-SysInfoHealthCheck -Id '' -Name '' })

# Runs the next repair of "Fix all problems"; after the last one, everything is checked again.
Function Start-SelfXNextFixAll
	{
		If($Global:FixAll_Queue.Count -eq 0)
			{
				$Global:FixAll_Active = $False
				$Done = Get-SelfXString 'Status_FixAll_Done' $Global:FixAll_Success $Global:FixAll_Total
				$msgbar.Clear()
				If($Global:FixAll_Failed.Count)
					{
						$msgbar.SetWarningAlert($Done + ' ' + (Get-SelfXString 'Status_FixAll_Failed' ($Global:FixAll_Failed -join ', ')))
					}
				Else { $msgbar.SetSuccessAlert($Done) }
				Update-SelfXFixAllButton
				Start-SysInfoHealthCheck -Id '' -Name ''
				return
			}
		$Card = $Global:FixAll_Queue.Dequeue()
		$Global:FixAll_Current = "$($Card.Property)"
		$Number = $Global:FixAll_Total - $Global:FixAll_Queue.Count
		Try { Start-SelfXSystemAction -Script $Card.Remediation -ActionName ('{0} ({1}/{2})' -f $Card.Property, $Number, $Global:FixAll_Total) }
		Catch
			{
				# The repair could not be started: count it and all remaining repairs as failed and finish.
				$Global:SvcAction_Running = $False
				$Global:FixAll_Failed.Add($Global:FixAll_Current)
				while($Global:FixAll_Queue.Count) { $Global:FixAll_Failed.Add("$($Global:FixAll_Queue.Dequeue().Property)") }
				Start-SelfXNextFixAll
			}
	}

$Btn_FixAll.Add_Click({
	If($Global:SvcAction_Running -or (Test-SelfXCheckRunning) -or $Global:FixAll_Active -or $Global:FreeSpace_Active)
		{
			$msgbar.SetWarningAlert($Service_Busy_Text)
			return
		}
	$Cards = @($Global:Health_FixAll_Cards)
	If(-not $Cards.Count) { return }
	$List = ($Cards | ForEach-Object { [string][char]0x2022 + ' ' + $_.Property }) -join "`r`n"
	$Answer = Show-SelfXDialog -Title (Get-SelfXString 'Status_FixAll') -Message (Get-SelfXString 'Health_FixAll_Confirm' $Cards.Count $List) `
		-AffirmativeText (Get-SelfXString 'Button_Yes') -NegativeText (Get-SelfXString 'Button_No') -Kind Warning
	If($Answer -ne 'Affirmative') { return }
	$Global:FixAll_Queue.Clear()
	foreach($Card in $Cards) { $Global:FixAll_Queue.Enqueue($Card) }
	$Global:FixAll_Total = $Cards.Count
	$Global:FixAll_Success = 0
	$Global:FixAll_Failed = New-Object System.Collections.Generic.List[string]
	$Global:FixAll_Active = $True
	Update-SelfXFixAllButton
	Start-SelfXNextFixAll
})

# While the window is open, the cached status of the background checks is read every minute (no check is run).
$Status_Refresh_Timer = New-Object System.Windows.Threading.DispatcherTimer
$Status_Refresh_Timer.Interval = [TimeSpan]::FromSeconds(60)
$Status_Refresh_Timer.Add_Tick({ If(-not $Global:Health_Busy -and -not $Global:SvcAction_Running) { [void](Start-SelfXHealthJob -Mode Cached) } })

#******************************************************************************
# System information page (idea and data points based on https://github.com/JayRHa/windows-system-information, MIT)
#******************************************************************************
$Global:SysInfo_Items = @()
$Global:SysInfo_Collecting = $False
$Global:SysInfo_CachedAt = $null
$SysInfo_Cache = Read-SelfXSystemInfoCache -Culture $SelfX_UI_Language.Culture
If($SysInfo_Cache) { $Global:SysInfo_Items = @($SysInfo_Cache.Items); $Global:SysInfo_CachedAt = $SysInfo_Cache.CollectedAt }

# One card per category, in the order of the collector.
Function Show-SysInfoItems
	{
		$Groups = [ordered]@{}
		foreach($Item in $Global:SysInfo_Items)
			{
				$Key = "$($Item.Category)"
				If(-not $Groups.Contains($Key)) { $Groups[$Key] = New-Object System.Collections.Generic.List[object] }
				$Groups[$Key].Add($Item)
			}
		$InfoCards.ItemsSource = @(foreach($Key in $Groups.Keys) {
			$Glyph = $Global:SelfX_InfoGlyphs[$Key]
			If(-not $Glyph) { $Glyph = [string][char]0xE946 }
			[pscustomobject]@{ Title = $Key; Glyph = $Glyph; Rows = $Groups[$Key].ToArray() }
		})
	}

Function Set-SysInfoBusy
	{
		param([bool]$Busy)
		$Global:SysInfo_Collecting = $Busy
		$SysInfo_Spinner.Visibility = $(If($Busy) { 'Visible' } Else { 'Collapsed' })
		$SysInfo_Refresh.IsEnabled = -not $Busy
		If($Busy -and $Global:SysInfo_CachedAt) { $SysInfo_Status.Text = Get-SelfXString 'SystemInfo_Cached_Text' (Format-SelfXTime $Global:SysInfo_CachedAt) }
		ElseIf($Busy) { $SysInfo_Status.Text = Get-SelfXString 'SystemInfo_Loading_Text' }
		Else { $SysInfo_Status.Text = Get-SelfXString 'SystemInfo_Hint_Text' }
	}

$SysInfo_Timer = New-Object System.Windows.Threading.DispatcherTimer
$SysInfo_Timer.Interval = [TimeSpan]::FromMilliseconds(300)
$SysInfo_Timer.Add_Tick({
	If(-not $Global:SysInfo_Handle.IsCompleted) { return }
	$SysInfo_Timer.Stop()
	Try { $Results = @($Global:SysInfo_PS.EndInvoke($Global:SysInfo_Handle)) }
	Catch { $Results = @(New-SelfXInfoItem (Get-SelfXInfoText 'Category_Report') (Get-SelfXInfoText 'Error') $_.Exception.Message) }
	$Global:SysInfo_PS.Dispose()
	If($Results.Count) { $Global:SysInfo_Items = $Results; $Global:SysInfo_CachedAt = $null }
	Show-SysInfoItems
	Set-SysInfoBusy $False
})

# Collects in a background runspace (the window stays responsive) and stores the result in the user cache.
Function Start-SysInfoCollection
	{
		If($Global:SysInfo_Collecting) { return }
		Set-SysInfoBusy $True
		$Global:SysInfo_PS = [PowerShell]::Create()
		[void]$Global:SysInfo_PS.AddScript($Global:SysInfo_Script).AddStatement().AddScript(
			'param($TestHost, $TestPort, $Text, $Culture, $NetworkConfig, $TerminalServer, $ServerRows) $Items = @(Get-SelfXSystemInfo -InternetTestHost $TestHost -InternetTestPort $TestPort -Text $Text -NetworkTestConfigPath $NetworkConfig -TerminalServer:$TerminalServer -ServerRows $ServerRows); try { Save-SelfXSystemInfoCache -Items $Items -Culture $Culture } catch { }; $Items'
		).AddArgument($SysInfo_Test_Host).AddArgument($SysInfo_Test_Port).AddArgument($Global:SysInfo_Texts).AddArgument($SelfX_UI_Language.Culture).AddArgument((Get-SelfXConfigPath -Name 'Network_Test_Config.xml' -CodeRoot $Current_Folder)).AddArgument([bool]$Global:SelfX_View.TerminalServer).AddArgument([bool]$Global:SelfX_View.ServerRows)
		$Global:SysInfo_Handle = $Global:SysInfo_PS.BeginInvoke()
		$SysInfo_Timer.Start()
	}

# Copy and export contain the information and the device status.
Function Get-SelfXReportItems { return @(@($Global:SysInfo_Items) + @($Global:Health_Items) | Where-Object { $_ }) }

$SysInfo_Refresh.Add_Click({ Start-SysInfoCollection })
$SysInfo_Copy.Add_Click({
	$All = Get-SelfXReportItems
	If($All.Count -gt 0)
		{
			[System.Windows.Clipboard]::SetText((ConvertTo-SelfXSystemInfoText -Items $All))
			$SysInfo_Status.Text = Get-SelfXString 'SystemInfo_Copied_Text' $NavText3.Text
		}
})
$InfoCards.AddHandler([System.Windows.UIElement]::MouseDownEvent, [System.Windows.Input.MouseButtonEventHandler]{
	param($sender, $event)
	If(($event.ClickCount -ne 2) -or ($event.ChangedButton -ne 'Left')) { return }
	$Row = $event.OriginalSource.DataContext
	If($Row -and ($Row.PSObject.Properties.Name -contains 'Value'))
		{
			[System.Windows.Clipboard]::SetText([string]$Row.Value)
			$SysInfo_Status.Text = Get-SelfXString 'SystemInfo_Copied_Text' $Row.Property
		}
}, $True)
$SysInfo_Export.Add_Click({
	$All = Get-SelfXReportItems
	If($All.Count -eq 0) { return }
	$SaveDialog = New-Object Microsoft.Win32.SaveFileDialog
	$SaveDialog.FileName = "SystemInfo_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmm')"
	$SaveDialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
	# A broken filter in a translation would throw: use the English one in that case
	$Export_Filter = Get-SelfXString 'SystemInfo_Export_Filter'
	If(([regex]::Matches($Export_Filter, '\|')).Count -ne 7) { $Export_Filter = "Text file (*.txt)|*.txt|HTML file (*.html)|*.html|CSV file (*.csv)|*.csv|JSON file (*.json)|*.json" }
	$SaveDialog.Filter = $Export_Filter
	If($SaveDialog.ShowDialog($Form))
		{
			Try
				{
					Export-SelfXSystemInfo -Items $All -Path $SaveDialog.FileName -Title $NavText3.Text
					$SysInfo_Status.Text = $SaveDialog.FileName
				}
			Catch { $SysInfo_Status.Text = $_.Exception.Message }
		}
})

Function Invoke-SysInfoAction
	{
		param([scriptblock]$Action)
		Try { & $Action } Catch { $SysInfo_Status.Text = $_.Exception.Message }
	}
$SysInfo_SyncApps.Add_Click({ Invoke-SysInfoAction { Start-Process "intunemanagementextension://syncapp" } })
$SysInfo_SyncCompliance.Add_Click({ Invoke-SysInfoAction { Start-Process "intunemanagementextension://synccompliance" } })
$SysInfo_CompanyPortal.Add_Click({ Invoke-SysInfoAction { Start-Process (Join-Path $env:SystemRoot "explorer.exe") -ArgumentList "shell:AppsFolder\Microsoft.CompanyPortal_8wekyb3d8bbwe!App" } })
# The tile keeps its internal name SysInfo_QuickAssist; with Remote Help installed it starts Remote Help only.
$SysInfo_QuickAssist.Add_Click({
	Invoke-SysInfoAction {
		If($Global:RemoteHelp_Path) { Start-Process -FilePath $Global:RemoteHelp_Path; return }
		$QuickAssist_Exe = "$env:SystemRoot\System32\quickassist.exe"
		If(Test-Path $QuickAssist_Exe) { Start-Process $QuickAssist_Exe } Else { Start-Process "ms-quick-assist:" }
	}
})
$SysInfo_MdmDiagnostics.Add_Click({
	Invoke-SysInfoAction {
		$Mdm_Folder = Join-Path $env:TEMP "SelfX_MDMDiagnostics"
		# Full paths (no search through the program path or the working directory).
		$Mdm_Tool = Join-Path $env:SystemRoot "System32\MdmDiagnosticsTool.exe"
		If(-not (Test-Path -LiteralPath $Mdm_Tool -PathType Leaf)) { throw "MdmDiagnosticsTool.exe was not found." }
		# cmd.exe without console window (CreateNoWindow): no black window opens while the logs are collected.
		$Mdm_Start = New-Object System.Diagnostics.ProcessStartInfo
		$Mdm_Start.FileName = "$env:SystemRoot\System32\cmd.exe"
		$Mdm_Start.Arguments = "/c `"`"$Mdm_Tool`" -out `"$Mdm_Folder`" & `"$env:SystemRoot\explorer.exe`" `"$Mdm_Folder`"`""
		$Mdm_Start.UseShellExecute = $False
		$Mdm_Start.CreateNoWindow = $True
		$Mdm_Start.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
		$Mdm_Process = [System.Diagnostics.Process]::Start($Mdm_Start)
		If($Mdm_Process) { $Mdm_Process.Dispose() }
		$SysInfo_Status.Text = $Mdm_Folder
	}
})
If((Get-SelfXText "Show_SystemInfo_Intune_Actions" "True") -ne 'True') { $SysInfo_Actions.Visibility = 'Collapsed' }

#******************************************************************************
# Help and support dialog (hours, phone, mail, Teams chat, website / ticket system)
#******************************************************************************
Function Open-SelfXUri
	{
		param([string]$Uri)
		# Only https, a plain mailto address and the Teams chat link of SelfX are opened (SupportLinks.ps1).
		$Safe_Uri = Get-SelfXSafeUri $Uri
		If(-not $Safe_Uri) { Write-SelfXLog "A link was not opened: only https, mailto with one address and msteams chat links are allowed." 'Warning'; return }
		Try { Start-Process $Safe_Uri } Catch { $msgbar.SetDangerAlert($_.Exception.Message) }
	}

# Ticket by e-mail: the user describes the issue, the device information is always added (text and file).
# The e-mail is only displayed (classic Outlook through COM, otherwise the default mail app), the user sends it.
Function Show-SelfXTicketDialog
	{
		$Dialog = New-SelfXDialog -Title (Get-SelfXString 'Ticket_Window_Title') -Width 560 -ContentXaml @'
      <TextBlock Name="TicketIntro" Style="{StaticResource SubText}" TextWrapping="Wrap" Margin="0,0,0,10"/>
      <TextBlock Name="TicketLabel" FontWeight="SemiBold" Margin="0,0,0,4"/>
      <TextBox Name="TicketText" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Height="140" MaxLength="3000" Padding="6"/>
      <TextBlock Name="TicketInfo" Style="{StaticResource SubText}" TextWrapping="Wrap" Margin="0,10,0,0"/>
      <TextBlock Name="TicketTarget" Style="{StaticResource SubText}" TextWrapping="Wrap" Margin="0,6,0,0"/>
      <TextBlock Name="TicketResult" TextWrapping="Wrap" Margin="0,10,0,0" Visibility="Collapsed"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
        <Button Name="TicketClose" MinWidth="100" Margin="0,0,8,0" IsCancel="True"/>
        <Button Name="TicketOpen" Style="{StaticResource PrimaryButton}" MinWidth="130" IsDefault="True"/>
      </StackPanel>
'@
		$Dialog.FindName('TicketIntro').Text = Get-SelfXString 'Ticket_Intro_Text'
		$Dialog.FindName('TicketLabel').Text = Get-SelfXString 'Ticket_Description_Label'
		$Dialog.FindName('TicketInfo').Text = Get-SelfXString 'Ticket_Info_Text'
		# Recipient from the routing (read only values of the device); the user cannot change it
		$Target = Get-SelfXTicketTarget -DefaultMail $Ticket_Mail -Config $Ticket_Routing
		$Global:SelfX_TicketTarget = $Target
		Write-SelfXLog "Ticket recipient: $($Target.Source), unit '$($Target.Unit)'"
		$Dialog.FindName('TicketTarget').Text = Get-SelfXString 'Ticket_Recipient_Text' $Target.To
		$Close = $Dialog.FindName('TicketClose')
		$Close.Content = Get-SelfXString 'Close_Button_Text'
		$Close.Add_Click({ [System.Windows.Window]::GetWindow($this).Close() })
		$Open = $Dialog.FindName('TicketOpen')
		$Open.Content = Get-SelfXString 'Ticket_Open_Button'
		$Open.Add_Click({
			$Dlg = [System.Windows.Window]::GetWindow($this)
			$Result = $Dlg.FindName('TicketResult')
			$this.IsEnabled = $False
			$Dlg.Cursor = [System.Windows.Input.Cursors]::Wait
			Try
				{
					$Items = @(Get-SelfXReportItems)
					$Info_Text = If($Items.Count) { ConvertTo-SelfXSystemInfoText -Items $Items } Else { Get-SelfXString 'Ticket_No_Info_Text' }
					$Ticket = New-SelfXTicket -Tag $Ticket_Tag -KindText (Get-SelfXString 'Ticket_Kind_Text') -DeviceName $env:COMPUTERNAME -Unit $Global:SelfX_TicketTarget.Unit -GroupTag $Global:SelfX_TicketTarget.GroupTag -Category $Global:SelfX_TicketTarget.Category -WindowsBuild $(If($Global:SelfX_View.ServerRows) { [string][Environment]::OSVersion.Version.Build } Else { '' }) -SelfXVersion "$Tool_Version" -UserText $Dlg.FindName('TicketText').Text -DeviceInfoText $Info_Text
					$Sent = Send-SelfXTicket -To $Global:SelfX_TicketTarget.To -Cc $Global:SelfX_TicketTarget.Cc -Ticket $Ticket -DeviceInfoText $Info_Text
					# The log names the result only, never the text of the user or the device information.
					Write-SelfXLog "Ticket e-mail prepared: $($Sent.Status), information rows: $($Items.Count)"
					Switch("$($Sent.Status)")
						{
							'Outlook' { $Result.Text = Get-SelfXString 'Ticket_Opened_Text' }
							'Manual'  { $Result.Text = Get-SelfXString 'Ticket_Manual_Text' $Sent.Path }
							Default   { $Result.Text = Get-SelfXString 'Ticket_Error_Text' "$($Sent.Message)" }
						}
				}
			Catch { $Result.Text = Get-SelfXString 'Ticket_Error_Text' $_.Exception.Message }
			Finally
				{
					$Dlg.Cursor = $null
					$this.IsEnabled = $True
				}
			$Result.Visibility = 'Visible'
		})
		[void]$Dialog.ShowDialog()
	}

# Copilot Chat hand-over: the user sees the prompt (descriptions and device facts, names and addresses replaced by placeholders),
# can change it, copies it and opens the configured address. Nothing is sent by SelfX; the user pastes and sends it.
Function Show-SelfXCopilotDialog
	{
		$Dialog = New-SelfXDialog -Title (Get-SelfXString 'Copilot_Window_Title') -Width 640 -ContentXaml @'
      <TextBlock Name="CopilotIntro" Style="{StaticResource SubText}" TextWrapping="Wrap" Margin="0,0,0,10"/>
      <TextBlock Name="CopilotLabel" FontWeight="SemiBold" Margin="0,0,0,4"/>
      <TextBox Name="CopilotText" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Height="80" MaxLength="1000" Padding="6"/>
      <TextBlock Name="CopilotWarning" Style="{StaticResource SubText}" TextWrapping="Wrap" Margin="0,6,0,0"/>
      <Button Name="CopilotPreviewButton" HorizontalAlignment="Left" MinWidth="130" Margin="0,8,0,0"/>
      <TextBlock Name="CopilotPreviewLabel" FontWeight="SemiBold" Margin="0,12,0,4"/>
      <TextBox Name="CopilotPreview" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Height="190" MaxLength="8000" Padding="6" FontFamily="Consolas"/>
      <TextBlock Name="CopilotTarget" Style="{StaticResource SubText}" TextWrapping="Wrap" Margin="0,10,0,0"/>
      <TextBlock Name="CopilotResult" TextWrapping="Wrap" Margin="0,10,0,0" Visibility="Collapsed"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
        <Button Name="CopilotClose" MinWidth="100" Margin="0,0,8,0" IsCancel="True"/>
        <Button Name="CopilotOpen" Style="{StaticResource PrimaryButton}" MinWidth="170" IsDefault="True" IsEnabled="False"/>
      </StackPanel>
'@
		$Dialog.FindName('CopilotIntro').Text = Get-SelfXString 'Copilot_Intro_Text'
		$Dialog.FindName('CopilotLabel').Text = Get-SelfXString 'Copilot_Description_Label'
		$Dialog.FindName('CopilotWarning').Text = Get-SelfXString 'Copilot_Warning_Text'
		$Dialog.FindName('CopilotPreviewLabel').Text = Get-SelfXString 'Copilot_Preview_Label'
		$Dialog.FindName('CopilotTarget').Text = Get-SelfXString 'Copilot_Target_Text' (Get-SelfXCopilotUrlHost $Copilot_Url)
		$Close = $Dialog.FindName('CopilotClose')
		$Close.Content = Get-SelfXString 'Close_Button_Text'
		$Close.Add_Click({ [System.Windows.Window]::GetWindow($this).Close() })
		$Preview_Button = $Dialog.FindName('CopilotPreviewButton')
		$Preview_Button.Content = Get-SelfXString 'Copilot_Preview_Button'
		$Preview_Button.Add_Click({
			$Dlg = [System.Windows.Window]::GetWindow($this)
			$Result = $Dlg.FindName('CopilotResult')
			Try
				{
					$Facts = Get-SelfXCopilotFacts -HealthItems @($Global:Health_Items) -SelfXVersion "$Tool_Version" -Language "$($SelfX_UI_Language.Culture)" -IncludeAppNames $Copilot_AppNames -TerminalServer ([bool]$Global:SelfX_View.TerminalServer) -ServerFacts ([bool]$Global:SelfX_View.ServerRows)
					$Context = @{ ComputerName = $env:COMPUTERNAME; UserName = $env:USERNAME; DomainName = @($env:USERDOMAIN, $env:USERDNSDOMAIN) }
					$Template = Get-SelfXString $(If($Copilot_Audience -eq 'Admin') { 'Copilot_Prompt_Admin' } Else { 'Copilot_Prompt_User' })
					$Prompt = New-SelfXCopilotPrompt -Facts $Facts -Description $Dlg.FindName('CopilotText').Text -Context $Context -Audience $Copilot_Audience -Language "$($SelfX_UI_Language.Culture)" -IncludeAppNames $Copilot_AppNames -Template $Template
					$Dlg.FindName('CopilotPreview').Text = $Prompt
					$Dlg.FindName('CopilotOpen').IsEnabled = $True
					$Result.Visibility = 'Collapsed'
					# The log names the size only, never the text of the user or the device facts.
					Write-SelfXLog "Copilot prompt prepared: audience $Copilot_Audience, $($Prompt.Length) characters, status rows: $(@($Facts.Status).Count)"
				}
			Catch
				{
					$Result.Text = Get-SelfXString 'Copilot_Error_Text' $_.Exception.Message
					$Result.Visibility = 'Visible'
				}
		})
		$Open = $Dialog.FindName('CopilotOpen')
		$Open.Content = Get-SelfXString 'Copilot_Open_Button'
		$Open.Add_Click({
			$Dlg = [System.Windows.Window]::GetWindow($this)
			$Result = $Dlg.FindName('CopilotResult')
			$Text = $Dlg.FindName('CopilotPreview').Text
			If([string]::IsNullOrWhiteSpace($Text)) { return }
			Try
				{
					# The text is kept out of the clipboard history (Win+V) and the cloud clipboard (CopilotClipboard.ps1).
					# With Copilot_Clear_Clipboard the copy carries a marker so that only this copy is emptied later.
					$Marker = If($Copilot_ClearClipboard) { [guid]::NewGuid().ToString('N') } Else { '' }
					$KeptOut = Set-SelfXClipboardPrivate -Text $Text -Marker $Marker
					# Only the address from the configuration (checked when SelfX started) is opened.
					If(-not (Test-SelfXCopilotUrl $Copilot_Url)) { Throw 'Copilot_Url' }
					Start-Process $Copilot_Url
					Write-SelfXLog "Copilot Chat opened (host $(Get-SelfXCopilotUrlHost $Copilot_Url)), prompt copied to the clipboard (kept out of the clipboard history: $KeptOut)"
					$Result.Text = Get-SelfXString 'Copilot_Opened_Text'
					If($Copilot_ClearClipboard)
						{
							If($KeptOut)
								{
									# The timer runs in the window process: it also fires when this dialog has been closed.
									$Script:SelfXCopilotResult = $Result
									Start-SelfXClipboardClearTimer -Marker $Marker -Seconds $Copilot_ClearSeconds -OnDone {
										param($ClearResult)
										If($ClearResult -eq 'Cleared' -and $Script:SelfXCopilotResult -and $Script:SelfXCopilotResult.Dispatcher.CheckAccess() -and $Script:SelfXCopilotResult.IsVisible)
											{ $Script:SelfXCopilotResult.Text = Get-SelfXString 'Copilot_Cleared_Text' }
									}
									$Result.Text = (Get-SelfXString 'Copilot_Opened_Text') + ' ' + (Get-SelfXString 'Copilot_Clear_Text' $Copilot_ClearSeconds)
								}
							Else { Write-SelfXLog 'Clipboard: the text was copied without the marker (plain text), it is not emptied automatically.' 'Warning' }
						}
				}
			Catch { $Result.Text = Get-SelfXString 'Copilot_Error_Text' $_.Exception.Message }
			$Result.Visibility = 'Visible'
		})
		[void]$Dialog.ShowDialog()
	}

Function Show-SelfXHelpDialog
	{
		$Dialog = New-SelfXDialog -Title (Get-SelfXString 'Support_Window_Title') -Width 520 -ContentXaml @'
      <TextBlock Name="HelpIntro" Style="{StaticResource SubText}" Margin="0,0,0,12"/>
      <StackPanel Name="HelpRows"/>
      <Button Name="HelpClose" Style="{StaticResource PrimaryButton}" MinWidth="110" HorizontalAlignment="Right" Margin="0,18,0,0" IsCancel="True" IsDefault="True"/>
'@
		$Rows = $Dialog.FindName('HelpRows')
		$Dialog.FindName('HelpIntro').Text = Get-SelfXString 'Support_Intro_Text'
		$Close = $Dialog.FindName('HelpClose')
		$Close.Content = Get-SelfXString 'Close_Button_Text'
		$Close.Add_Click({ [System.Windows.Window]::GetWindow($this).Close() })

		$Entries = New-Object System.Collections.Generic.List[object]
		If($Ticket_Available) { $Entries.Add(@(0xE7C3, (Get-SelfXString 'Ticket_Row_Label'), (Get-SelfXString 'Ticket_Row_Text'), (Get-SelfXString 'Ticket_Button'), 'selfx:ticket')) }
		If($Copilot_Available) { $Entries.Add(@(0xE8F2, (Get-SelfXString 'Copilot_Row_Label'), (Get-SelfXString 'Copilot_Row_Text'), (Get-SelfXString 'Copilot_Button'), 'selfx:copilot')) }
		$Hours = Get-SelfXText "Support_Hours" ""
		If($Hours) { $Entries.Add(@(0xE823, (Get-SelfXString 'Support_Hours_Label'), $Hours, '', '')) }
		If($Support_Phone_number) { $Entries.Add(@(0xE717, (Get-SelfXString 'Support_Phone_Label'), $Support_Phone_number, '', '')) }
		If($Support_Mail)
			{
				# The button only exists for one plain address (no list, no mailto parameters)
				$Mail_Uri = Get-SelfXSafeUri "mailto:$($Support_Mail.Trim())"
				If($Mail_Uri) { $Entries.Add(@(0xE715, (Get-SelfXString 'Support_Mail_Label'), $Support_Mail, (Get-SelfXString 'Support_Mail_Button'), $Mail_Uri)) }
				Else { Write-SelfXLog "Support_Mail is not one plain e-mail address; shown without a button." 'Warning'; $Entries.Add(@(0xE715, (Get-SelfXString 'Support_Mail_Label'), $Support_Mail, '', '')) }
			}
		$Teams = Get-SelfXText "Support_Teams" ""
		If($Teams)
			{
				# A user/channel address opens a chat; a full https link (e.g. a channel or a Teams app) is used as is.
				If($Teams -match '^https://') { $Teams_Uri = $Teams }
				ElseIf(Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\msteams') { $Teams_Uri = 'msteams:/l/chat/0/0?users=' + [uri]::EscapeDataString($Teams) }
				Else { $Teams_Uri = 'https://teams.microsoft.com/l/chat/0/0?users=' + [uri]::EscapeDataString($Teams) }
				$Teams_Safe = Get-SelfXSafeUri $Teams_Uri
				If($Teams_Safe) { $Entries.Add(@(0xE8BD, (Get-SelfXString 'Support_Teams_Label'), $Teams, (Get-SelfXString 'Support_Teams_Button'), $Teams_Safe)) }
				Else { Write-SelfXLog "Support_Teams gives no valid link (https or a plain address); shown without a button." 'Warning'; $Entries.Add(@(0xE8BD, (Get-SelfXString 'Support_Teams_Label'), $Teams, '', '')) }
			}
		$Website = Get-SelfXText "Support_Website" ""
		If($Website)
			{
				$Website_Uri = ConvertTo-SelfXSupportWebUri $Website
				If($Website_Uri) { $Entries.Add(@(0xE774, (Get-SelfXString 'Support_Website_Label'), $Website, (Get-SelfXString 'Support_Website_Button'), $Website_Uri)) }
				Else { Write-SelfXLog "Support_Website is ignored: only https:// links are allowed." 'Warning' }
			}

		If(-not $Entries.Count)
			{
				$None = New-Object System.Windows.Controls.TextBlock
				$None.Text = Get-SelfXString 'Support_None_Text'
				$None.TextWrapping = 'Wrap'
				[void]$Rows.Children.Add($None)
			}
		foreach($Entry in $Entries)
			{
				$Row = [Windows.Markup.XamlReader]::Parse(@'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="14" Background="{DynamicResource SurfaceAlt}" Padding="16,14" Margin="0,0,0,10">
  <DockPanel>
    <Button Name="Go" DockPanel.Dock="Right" Visibility="Collapsed" VerticalAlignment="Center" Margin="10,0,0,0"/>
    <TextBlock Name="Icon" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" VerticalAlignment="Top" Margin="0,2,12,0" Foreground="{DynamicResource AccentText}"/>
    <StackPanel>
      <TextBlock Name="Label" FontWeight="SemiBold"/>
      <TextBox Name="Value" IsReadOnly="True" BorderThickness="0" Background="Transparent" TextWrapping="Wrap" Foreground="{DynamicResource TextPrimary}" Padding="0" Margin="0,2,0,0"/>
    </StackPanel>
  </DockPanel>
</Border>
'@)
				$Row.FindName('Icon').Text = [string][char]$Entry[0]
				$Row.FindName('Label').Text = "$($Entry[1])".Trim().TrimEnd(':', [char]0xFF1A).Trim()
				$Row.FindName('Value').Text = $Entry[2]
				If($Entry[4])
					{
						$Go = $Row.FindName('Go')
						$Go.Style = $Dialog.FindResource('PrimaryButton')
						$Go.Content = $Entry[3]
						$Go.Tag = $Entry[4]
						$Go.Visibility = 'Visible'
						$Go.Add_Click({ Switch(([string]$this.Tag)) { 'selfx:ticket' { Show-SelfXTicketDialog } 'selfx:copilot' { Show-SelfXCopilotDialog } Default { Open-SelfXUri ([string]$this.Tag) } } })
					}
				[void]$Rows.Children.Add($Row)
			}
		[void]$Dialog.ShowDialog()
	}

#******************************************************************************
# Settings dialog: language, theme and tray icon of the user
#******************************************************************************
$Show_Theme_Setting = (Get-SelfXText "Show_Theme_Button" "True") -eq 'True'
$Show_Tray_Setting = (Get-SelfXText "Show_Tray_Icon" "True") -eq 'True'
# The user can switch the notifications off only when the administrator allows them (Tray_Notifications).
$Show_Notify_Setting = (Get-SelfXText "Tray_Notifications" "True") -eq 'True'
$Global:SelfX_RestartPage = ''

Function Test-SelfXTrayRunning
	{
		Try { $Mutex = [System.Threading.Mutex]::OpenExisting('Local\SelfX.Tray'); $Mutex.Dispose(); return $True } Catch { return $False }
	}

# Switches the tray icon of the user on (starts it) or off (asks the running icon to close).
Function Set-SelfXTrayEnabled
	{
		param([bool]$Enabled)
		Set-SelfXUserSetting 'TrayIcon' ([int]$Enabled)
		If($Enabled)
			{
				$Tray_Script = Join-Path $Current_Folder 'SelfX_Tray.ps1'
				If((Test-Path -LiteralPath $Tray_Script) -and -not (Test-SelfXTrayRunning))
					{
						# Not in the install folder: the long-running icon would lock it against updates and uninstallation.
						Try { Start-SelfXHiddenPowerShell -Path $Tray_Script } Catch {}
					}
			}
		Else
			{
				Try { $Signal = [System.Threading.EventWaitHandle]::OpenExisting('Local\SelfX.Tray.Command'); [void]$Signal.Set(); $Signal.Dispose() } Catch {}
			}
	}

# Entries of the language list: "Automatic (<default language>)" first, then all languages by name.
Function Get-SelfXLanguageChoices
	{
		$Default_Setting = Resolve-SelfXLanguageSetting -ConfigLanguage (Get-SelfXText "Tool_Language" "de") -UserLanguage '' -LanguageFolder $Global:SelfX_LanguageFolder
		$Default_Culture = Get-SelfXLanguageFileCulture -LanguageFolder $Global:SelfX_LanguageFolder -Language $Default_Setting
		$Languages = @(Get-SelfXLanguageList -LanguageFolder $Global:SelfX_LanguageFolder)
		$Default_Name = $Default_Culture
		foreach($Language in $Languages) { If($Language.Culture -eq $Default_Culture) { $Default_Name = $Language.Name } }
		$Choices = New-Object System.Collections.Generic.List[object]
		$Choices.Add([pscustomobject]@{ Culture = 'Auto'; Text = (Get-SelfXString 'Settings_Language_Auto' $Default_Name) })
		foreach($Language in $Languages) { $Choices.Add([pscustomobject]@{ Culture = $Language.Culture; Text = $Language.Name }) }
		return $Choices
	}

# Saves the language of the user. SelfX shows its texts in one language, so it restarts itself in the new
# language (same page, size and position); the status icon follows. Returns $True when SelfX restarts.
Function Set-SelfXUserLanguage
	{
		param([string]$Culture)
		Set-SelfXUserSetting 'Language' $Culture
		Write-SelfXLog "Language chosen by the user: $Culture"
		$Setting = Resolve-SelfXLanguageSetting -ConfigLanguage (Get-SelfXText "Tool_Language" "de") -UserLanguage $Culture `
			-AllowUserChoice $Show_Language_Setting -LanguageFolder $Global:SelfX_LanguageFolder
		Try { $Signal = [System.Threading.EventWaitHandle]::OpenExisting('Local\SelfX.Tray.Command'); [void]$Signal.Set(); $Signal.Dispose() } Catch {}
		If((Get-SelfXLanguageFileCulture -LanguageFolder $Global:SelfX_LanguageFolder -Language $Setting) -eq $SelfX_UI_Language.Culture) { return $False }
		# A running repair would lose its result window: the new language is used the next time SelfX opens.
		If($Global:SvcAction_Running -or $Global:FixAll_Active -or $Global:FreeSpace_Active) { return $False }
		$Global:SelfX_RestartPage = $(If($Nav_Status.IsChecked) { 'Status' } ElseIf($Nav_Info.IsChecked) { 'SystemInfo' } Else { 'Troubleshooting' })
		return $True
	}

Function Show-SelfXSettingsDialog
	{
		$Dialog = New-SelfXDialog -Title (Get-SelfXString 'Settings_Title') -ContentXaml @'
      <StackPanel Name="LanguagePanel" Margin="0,0,0,16">
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Style="{StaticResource Glyph}" Text="&#xE774;" FontSize="15" Margin="0,0,8,0" Foreground="{DynamicResource AccentText}"/>
          <TextBlock Name="LanguageLabel" FontWeight="SemiBold"/>
        </StackPanel>
        <ListBox Name="LanguageList" MaxHeight="190" Background="{DynamicResource SurfaceAlt}" BorderBrush="{DynamicResource Stroke}" BorderThickness="1"
                 Padding="2" ScrollViewer.HorizontalScrollBarVisibility="Disabled" DisplayMemberPath="Text">
          <ListBox.ItemContainerStyle>
            <Style TargetType="ListBoxItem">
              <Setter Property="Cursor" Value="Hand"/>
              <Setter Property="Template">
                <Setter.Value>
                  <ControlTemplate TargetType="ListBoxItem">
                    <Border Name="Bd" CornerRadius="4" Padding="10,5" Margin="1" Background="Transparent">
                      <ContentPresenter Name="Cp" TextElement.Foreground="{DynamicResource TextPrimary}"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource HoverBg}"/></Trigger>
                      <Trigger Property="IsSelected" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Accent}"/>
                        <Setter TargetName="Cp" Property="TextElement.Foreground" Value="{DynamicResource AccentFg}"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </Setter.Value>
              </Setter>
            </Style>
          </ListBox.ItemContainerStyle>
        </ListBox>
        <TextBlock Name="LanguageHint" Style="{StaticResource SubText}" Margin="0,6,0,0"/>
      </StackPanel>
      <StackPanel Name="ThemePanel" Margin="0,0,0,16">
        <TextBlock Name="ThemeLabel" FontWeight="SemiBold" Margin="0,0,0,8"/>
        <StackPanel Orientation="Horizontal">
          <RadioButton Name="ThemeAuto" Style="{StaticResource Pill}" GroupName="Theme"/>
          <RadioButton Name="ThemeDark" Style="{StaticResource Pill}" GroupName="Theme"/>
          <RadioButton Name="ThemeLight" Style="{StaticResource Pill}" GroupName="Theme"/>
        </StackPanel>
      </StackPanel>
      <StackPanel Name="TrayPanel">
        <CheckBox Name="TraySwitch" Style="{StaticResource Switch}"><TextBlock Name="TrayLabel" TextWrapping="Wrap" FontWeight="SemiBold"/></CheckBox>
        <TextBlock Name="TrayHint" Style="{StaticResource SubText}" Margin="50,4,0,0"/>
      </StackPanel>
      <StackPanel Name="NotifyPanel" Margin="0,14,0,0">
        <CheckBox Name="NotifySwitch" Style="{StaticResource Switch}"><TextBlock Name="NotifyLabel" TextWrapping="Wrap" FontWeight="SemiBold"/></CheckBox>
        <TextBlock Name="NotifyHint" Style="{StaticResource SubText}" Margin="50,4,0,0"/>
      </StackPanel>
      <Button Name="SettingsClose" Style="{StaticResource PrimaryButton}" MinWidth="110" HorizontalAlignment="Right" Margin="0,20,0,0" IsCancel="True" IsDefault="True"/>
'@
		$LanguageList = $Dialog.FindName('LanguageList')
		$Dialog.FindName('LanguageLabel').Text = Get-SelfXString 'Settings_Language_Text'
		$Dialog.FindName('LanguageHint').Text = Get-SelfXString 'Settings_Language_Hint'
		If($Show_Language_Setting)
			{
				$Choices = @(Get-SelfXLanguageChoices)
				$LanguageList.ItemsSource = $Choices
				$Current = [string](Get-SelfXUserSetting 'Language' 'Auto')
				$LanguageList.SelectedItem = $Choices[0]
				foreach($Choice in $Choices) { If($Choice.Culture -eq $Current) { $LanguageList.SelectedItem = $Choice } }
				$LanguageList.Add_Loaded({ If($this.SelectedItem) { $this.ScrollIntoView($this.SelectedItem) } })
				$LanguageList.Add_SelectionChanged({
					$Choice = $this.SelectedItem
					If(-not $Choice) { return }
					If(Set-SelfXUserLanguage $Choice.Culture) { [System.Windows.Window]::GetWindow($this).Close() }
					ElseIf(($Global:SvcAction_Running -or $Global:FixAll_Active -or $Global:FreeSpace_Active)) { $Hint = [System.Windows.Window]::GetWindow($this).FindName('LanguageHint'); $Hint.Text = Get-SelfXString 'Settings_Language_Later' }
				})
			}
		Else { $Dialog.FindName('LanguagePanel').Visibility = 'Collapsed' }

		$Dialog.FindName('ThemeLabel').Text = Get-SelfXString 'Settings_Theme_Text'
		$Auto = $Dialog.FindName('ThemeAuto')
		$Dark = $Dialog.FindName('ThemeDark')
		$Light = $Dialog.FindName('ThemeLight')
		$Auto.Content = Get-SelfXString 'Settings_Theme_Auto'
		$Auto.ToolTip = Get-SelfXString 'Settings_Theme_Auto_ToolTip'
		$Dark.Content = Get-SelfXString 'Settings_Theme_Dark'
		$Light.Content = Get-SelfXString 'Settings_Theme_Light'
		$Auto.IsChecked = ($Global:SelfX_ThemeChoice -eq 'Auto')
		$Dark.IsChecked = ($Global:SelfX_ThemeChoice -eq 'Dark')
		$Light.IsChecked = ($Global:SelfX_ThemeChoice -eq 'Light')
		$Auto.Add_Checked({ Set-SelfXTheme 'Auto'; Set-SelfXUserSetting 'Theme' 'Auto'; Write-SelfXLog 'Theme of the user: Auto (as Windows).' })
		$Dark.Add_Checked({ Set-SelfXTheme 'Dark'; Set-SelfXUserSetting 'Theme' 'Dark'; Write-SelfXLog 'Theme of the user: Dark.' })
		$Light.Add_Checked({ Set-SelfXTheme 'Light'; Set-SelfXUserSetting 'Theme' 'Light'; Write-SelfXLog 'Theme of the user: Light.' })
		If(-not $Show_Theme_Setting) { $Dialog.FindName('ThemePanel').Visibility = 'Collapsed' }

		$Switch = $Dialog.FindName('TraySwitch')
		$Dialog.FindName('TrayLabel').Text = Get-SelfXString 'Settings_Tray_Text'
		$Dialog.FindName('TrayHint').Text = Get-SelfXString 'Settings_Tray_Hint'
		$Switch.IsChecked = ([int](Get-SelfXUserSetting 'TrayIcon' 1) -ne 0)
		$Switch.Add_Click({ Set-SelfXTrayEnabled ([bool]$this.IsChecked) })
		If(-not $Show_Tray_Setting) { $Dialog.FindName('TrayPanel').Visibility = 'Collapsed' }

		# Windows notifications of the status icon about new problems (in addition to the colored icon).
		$Notify = $Dialog.FindName('NotifySwitch')
		$Dialog.FindName('NotifyLabel').Text = Get-SelfXString 'Settings_Notify_Text'
		$Dialog.FindName('NotifyHint').Text = Get-SelfXString 'Settings_Notify_Hint'
		$Notify.IsChecked = ([int](Get-SelfXUserSetting 'TrayNotifications' 1) -ne 0)
		$Notify.IsEnabled = [bool]$Switch.IsChecked
		$Notify.Add_Click({
			Set-SelfXUserSetting 'TrayNotifications' ([int][bool]$this.IsChecked)
			Write-SelfXLog "Notifications switched $(If($this.IsChecked) { 'on' } Else { 'off' }) in the settings."
		})
		# Without the icon there are no notifications: the switch is only active while the icon is shown.
		$Switch.Add_Click({ [System.Windows.Window]::GetWindow($this).FindName('NotifySwitch').IsEnabled = [bool]$this.IsChecked })
		If(-not ($Show_Tray_Setting -and $Show_Notify_Setting)) { $Dialog.FindName('NotifyPanel').Visibility = 'Collapsed' }

		$Close = $Dialog.FindName('SettingsClose')
		$Close.Content = Get-SelfXString 'Close_Button_Text'
		$Close.Add_Click({ [System.Windows.Window]::GetWindow($this).Close() })
		[void]$Dialog.ShowDialog()
		# New language selected: close the window; it is started again after ShowDialog of the main window.
		If($Global:SelfX_RestartPage) { $Form.Close() }
	}

#******************************************************************************
# About dialog
#******************************************************************************
Function Show-SelfXAboutDialog
	{
		$Dialog = New-SelfXDialog -Title $Tool_Name -Width 440 -ContentXaml @'
      <Image Name="AboutLogo" MaxHeight="90" MaxWidth="300" Stretch="Uniform" HorizontalAlignment="Left" Margin="0,0,0,14" Visibility="Collapsed"/>
      <TextBlock Name="AboutVersion" TextWrapping="Wrap"/>
      <Button Name="AboutClose" Style="{StaticResource PrimaryButton}" MinWidth="110" HorizontalAlignment="Right" Margin="0,20,0,0" IsCancel="True" IsDefault="True"/>
'@
		$Logo = $Brand_Logo_Image
		If($Logo -eq $null) { $Logo = Get-SelfXImage -FileName (Get-SelfXText "About_Logo" "logo.png") -BaseFolder $Current_Folder }
		If($Logo -ne $null) { $Image = $Dialog.FindName('AboutLogo'); $Image.Source = $Logo; $Image.Visibility = 'Visible' }
		$Catalog_Version = ([string]$List_Issues_XML.Actions.XML_Version).Trim()
		$Dialog.FindName('AboutVersion').Text = Get-SelfXString 'About_Version_Text' $Tool_Name $Tool_Version $Catalog_Version
		$Close = $Dialog.FindName('AboutClose')
		$Close.Content = Get-SelfXString 'Close_Button_Text'
		$Close.Add_Click({ [System.Windows.Window]::GetWindow($this).Close() })
		[void]$Dialog.ShowDialog()
	}

$Btn_Help.Add_Click({ Show-SelfXHelpDialog })
$Btn_Settings.Add_Click({ Show-SelfXSettingsDialog })
$Btn_About.Add_Click({ Show-SelfXAboutDialog })
If((Get-SelfXText "Show_Support_Button" "True") -ne 'True') { $Btn_Help.Visibility = 'Collapsed' }
If((Get-SelfXText "Show_About_Button" "True") -ne 'True') { $Btn_About.Visibility = 'Collapsed' }
If(-not ($Show_Theme_Setting -or $Show_Tray_Setting)) { $Btn_Settings.Visibility = 'Collapsed' }

#******************************************************************************
# Navigation, adaptive layout and window
#******************************************************************************
If(((Get-SelfXText "Show_Status_Page" "True") -ne 'True') -or -not $Global:SelfX_View.Health) { $Nav_Status.Visibility = 'Collapsed' }
If((Get-SelfXText "Show_SystemInfo_Tab" "True") -ne 'True') { $Nav_Info.Visibility = 'Collapsed' }

Function Show-SelfXPage
	{
		param([string]$Name)
		If(($Name -eq 'Status') -and ($Nav_Status.Visibility -ne 'Visible')) { $Name = 'Troubleshooting' }
		If(($Name -eq 'SystemInfo') -and ($Nav_Info.Visibility -ne 'Visible')) { $Name = 'Troubleshooting' }
		$Page_Actions.Visibility = $(If($Name -eq 'Status' -or $Name -eq 'SystemInfo') { 'Collapsed' } Else { 'Visible' })
		$Page_Status.Visibility = $(If($Name -eq 'Status') { 'Visible' } Else { 'Collapsed' })
		$Page_Info.Visibility = $(If($Name -eq 'SystemInfo') { 'Visible' } Else { 'Collapsed' })
		Switch($Name)
			{
				'Status'     { $Nav_Status.IsChecked = $True }
				'SystemInfo' { $Nav_Info.IsChecked = $True }
				Default      { $Nav_Actions.IsChecked = $True }
			}
	}
$Nav_Actions.Add_Checked({ Show-SelfXPage 'Troubleshooting' })
$Nav_Status.Add_Checked({ Show-SelfXPage 'Status' })
$Nav_Info.Add_Checked({ Show-SelfXPage 'SystemInfo' })
$Nav_Actions.ToolTip = $NavText1.Text
$Nav_Status.ToolTip = $NavText2.Text
$Nav_Info.ToolTip = $NavText3.Text

# Below 900 pixels the navigation shows only icons; cards reflow into 1-3 columns of the available width.
Function Update-SelfXLayout
	{
		$Narrow = $Form.ActualWidth -lt 900
		$NavColumn.Width = [System.Windows.GridLength]::new($(If($Narrow) { 60 } Else { 220 }))
		foreach($Element in $NavText1, $NavText2, $NavText3, $NavText4, $NavText5, $NavText6, $NavText7, $ServiceText) { $Element.Visibility = $(If($Narrow) { 'Collapsed' } Else { 'Visible' }) }
		If($Brand_Logo_Image -ne $null) { $Brand_Logo.Visibility = $(If($Narrow) { 'Collapsed' } Else { 'Visible' }) }
		$NavBadge.Margin = $(If($Narrow) { [System.Windows.Thickness]::new(0, -18, -6, 0) } Else { [System.Windows.Thickness]::new(0) })
	}
Function Update-SelfXCards
	{
		$Width = $StatusCards.ActualWidth
		If($Width -gt 0)
			{
				$Columns = $(If($Width -ge 900) { 3 } ElseIf($Width -ge 500) { 2 } Else { 1 })
				$Form.Resources['StatusCardWidth'] = [double][Math]::Floor(($Width - 14 * $Columns) / $Columns)
			}
		$Width = $InfoCards.ActualWidth
		If($Width -gt 0)
			{
				$Columns = $(If($Width -ge 720) { 2 } Else { 1 })
				$Form.Resources['InfoCardWidth'] = [double][Math]::Floor(($Width - 14 * $Columns) / $Columns)
			}
	}
$Form.Add_SizeChanged({ Update-SelfXLayout })
$StatusCards.Add_SizeChanged({ Update-SelfXCards })
$InfoCards.Add_SizeChanged({ Update-SelfXCards })

# Title bar buttons; a maximized borderless window needs a margin so that its edges stay on the screen.
$Btn_Close.Add_Click({ $Form.Close() })
$Btn_Min.Add_Click({ $Form.WindowState = 'Minimized' })
$Btn_Max.Add_Click({ $Form.WindowState = $(If($Form.WindowState -eq 'Maximized') { 'Normal' } Else { 'Maximized' }) })
$Form.Add_StateChanged({
	$Maximized = $Form.WindowState -eq 'Maximized'
	$Root.Margin = $(If($Maximized) { [System.Windows.Thickness]::new(7) } Else { [System.Windows.Thickness]::new(0) })
	$Btn_Max_Glyph.Text = [string][char]$(If($Maximized) { 0xE923 } Else { 0xE922 })
})

# Window size and position of the user (only restored when they are on a connected screen)
$Saved_Width = [double](Get-SelfXUserSetting 'WindowWidth' 0)
$Saved_Height = [double](Get-SelfXUserSetting 'WindowHeight' 0)
$Saved_Left = [double](Get-SelfXUserSetting 'WindowLeft' -100000)
$Saved_Top = [double](Get-SelfXUserSetting 'WindowTop' -100000)
If(($Saved_Width -ge $Form.MinWidth) -and ($Saved_Height -ge $Form.MinHeight))
	{
		$Form.Width = $Saved_Width
		$Form.Height = $Saved_Height
		$Screen_Left = [System.Windows.SystemParameters]::VirtualScreenLeft
		$Screen_Top = [System.Windows.SystemParameters]::VirtualScreenTop
		If(($Saved_Left -ge $Screen_Left) -and ($Saved_Top -ge $Screen_Top) -and
			(($Saved_Left + 100) -le ($Screen_Left + [System.Windows.SystemParameters]::VirtualScreenWidth)) -and
			(($Saved_Top + 100) -le ($Screen_Top + [System.Windows.SystemParameters]::VirtualScreenHeight)))
			{
				$Form.WindowStartupLocation = 'Manual'
				$Form.Left = $Saved_Left
				$Form.Top = $Saved_Top
			}
	}
If([int](Get-SelfXUserSetting 'WindowMaximized' 0)) { $Form.WindowState = 'Maximized' }
$Form.Add_Closing({
	$Bounds = $Form.RestoreBounds
	If(-not $Bounds.IsEmpty)
		{
			Set-SelfXUserSetting 'WindowWidth' ([int]$Bounds.Width)
			Set-SelfXUserSetting 'WindowHeight' ([int]$Bounds.Height)
			Set-SelfXUserSetting 'WindowLeft' ([int]$Bounds.Left)
			Set-SelfXUserSetting 'WindowTop' ([int]$Bounds.Top)
		}
	Set-SelfXUserSetting 'WindowMaximized' ([int]($Form.WindowState -eq 'Maximized'))
	$Status_Refresh_Timer.Stop()
	$Show_Request_Timer.Stop()
	$Theme_Timer.Stop()
	Write-SelfXLog 'SelfX closed.'
})

# Requests of a second start (shortcut or tray icon): bring this window to the front and show the page.
Function Invoke-SelfXPageRequest
	{
		param([string]$Name)
		If($Name -eq 'SendLogs')
			{
				Show-SelfXPage 'SystemInfo'
				If($Global:SysInfo_SendLogs_Action) { Run_Remediation -rowObj $Global:SysInfo_SendLogs_Action }
			}
		ElseIf($Name -and ($Name -ne 'Activate')) { Show-SelfXPage $Name }
	}
$Show_Request_Timer = New-Object System.Windows.Threading.DispatcherTimer
$Show_Request_Timer.Interval = [TimeSpan]::FromMilliseconds(400)
$Show_Request_Timer.Add_Tick({
	If(-not $Global:SelfX_ShowEvent.WaitOne(0)) { return }
	If($Form.WindowState -eq 'Minimized') { $Form.WindowState = 'Normal' }
	[void]$Form.Activate()
	$Form.Topmost = $True
	$Form.Topmost = $False
	Invoke-SelfXPageRequest ([string](Get-SelfXUserSetting 'ShowPage' 'Activate'))
})

If((Get-SelfXText "Show_Reboot_Warning" "True") -eq 'True') { $msgbar.SetInformationAlert((Get-SelfXString 'Reboot_Alert')) }

Update-SelfXStatusView
Show-SysInfoItems
Set-SysInfoBusy $False
Update-SelfXServiceStatus
Show-SelfXPage $(If($Page -in @('Status', 'SystemInfo')) { $Page } Else { 'Troubleshooting' })

$Form.Add_ContentRendered({
	Update-SelfXLayout
	# Status and information are loaded in the background; the cached values are already shown.
	[void](Start-SelfXHealthJob -Mode Cached)
	Start-SysInfoCollection
	$Status_Refresh_Timer.Start()
	$Show_Request_Timer.Start()
	# Right after the installation the tray icon starts only at the next sign-in; opening SelfX starts it now.
	If($Show_Tray_Setting -and ([int](Get-SelfXUserSetting 'TrayIcon' 1) -ne 0) -and -not (Test-SelfXTrayRunning)) { Set-SelfXTrayEnabled $True }
	If($Page -eq 'SendLogs') { Invoke-SelfXPageRequest 'SendLogs' }
})

[void]$Form.ShowDialog()

# Language changed in the settings: start SelfX again in the new language on the same page.
If($Global:SelfX_RestartPage)
	{
		Write-SelfXLog "SelfX starts again in the new language (page $Global:SelfX_RestartPage)."
		Try { $Global:SelfX_GuiMutex.ReleaseMutex() } Catch {}
		Try { Start-SelfXHiddenPowerShell -Path (Join-Path $Current_Folder 'Self_X.ps1') -Arguments "-Page $Global:SelfX_RestartPage" } Catch {}
	}
