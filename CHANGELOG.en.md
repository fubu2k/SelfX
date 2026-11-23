# Changelog

**English** | [Deutsch](CHANGELOG.md)

Changes of this fork ([fubu2k/SelfX](https://github.com/fubu2k/SelfX)) compared
with its upstream [wbaeck/SelfX](https://github.com/wbaeck/SelfX) at SelfX
Service 2.6.9. Newest version first.

The package version is `Tool_Version` in `SelfX Service\Sources\Tool_Config.xml`.
`Detection.ps1` must contain the same value, otherwise Intune does not detect
the update (the packaging script checks this). The version numbers in the
histories of the single files show where a change was made. Changes marked
2.6.10 were made before the package version was raised; they are delivered with
**2.6.11**, the first package version of this fork.

## Unreleased (SelfX Service)

### Security
- Finding M2 (Intune detection without a version change): `Detection.ps1` (2.8.1) now also compares the digest of the installed file list `SelfX.Files.json` (SHA256 over the sorted lines `name=SHA256`, `BuiltUtc` is not part of it) with a value that `tools\New-SelfXIntuneWin.ps1` (1.7.0) embeds. For that the script writes `build\SelfX-Service-<version>.Detection.ps1` next to the `.intunewin`; upload this file as the detection script to Intune (the release workflow adds it to the draft). Changed files without a new `Tool_Version` therefore count as not installed and are deployed. The copy in the repository only has a placeholder and still checks the version only (with a log note). A missing, damaged or different file list means not detected. New test `Test-Detection.ps1` (runs in 5.1 and 7). Read-only, no change of rights.
- Finding M1 (time window in recursive deletes as SYSTEM): `Install.ps1` (2.8.4) and `Uninstall.ps1` (2.6.11) no longer delete folders with `Get-Item` + `Remove-Item` (check and delete were separate steps, so a user could put a junction in their folder below `Logs\Users` in between). `SelfXService.exe` now contains the installer helper `SafeTree` (`/removetree:<path>`, `/cleandata:<folder> /trusted:<SIDs> /skip:<subfolder>`, version 2.8.19): every entry is opened once with `FILE_FLAG_OPEN_REPARSE_POINT` (a link is opened itself, never its target), judged on that handle (link, folder, owner) and deleted through the same handle; folders stay open (no share-delete) until their content is deleted. A link in the path of the root means nothing is deleted. No fallback to a delete by path: if the helper is missing or fails, `Install.ps1` stops, and `Uninstall.ps1` keeps the user data and prints a message. `Install.ps1` now checks `Bin` before it prepares the data folder. New test `Test-SafeDelete.ps1` (including folder/junction swaps while deleting); the data folder tests in `Test-InstallBinaries.ps1` run with the built helper; CI step after the .NET build. It needs no additional rights and deletes only what the caller may delete anyway.
- Finding M3 (user view of the device logs incomplete): in the user view (`-UserView`), `Collect-DeviceLogs.ps1` (1.3.4) now also omits the enrollment account (UPN), the ids and the FirstSync tree of the device enrollment, the Autopilot registry values (tenant, profile name, policy cache) and the raw ESP tracking tree, the process command lines, the contents of the Intune Management Extension logs, the Windows servicing logs (CBS, DISM, setupact, Windows Update), the Teams installer logs and the crash reports (WER), and the text of single events; ESP results and Win32Apps keys of other users are skipped. In addition, every report text (also the console output of the findings) passes through the new function `Protect-UserViewText`: e-mail addresses become `<hidden>`, SIDs of other users become `<other user>`. Without `-UserView` (administrator, Intune) nothing changes. The user view table in `docs/Configuration.md` lists the areas; tests in `Test-UserView.ps1`. Runs in the rights context of the service (SYSTEM) and only reads; no rights are added.

### Added
- Action "Refresh the company settings (Group Policy) of this PC" is now shown only on devices that are joined to a domain (domain or hybrid). The action catalogue has the new optional field `Requires` (value `DomainJoined`, XML 2.4.11, checked by `Test-Catalog.ps1`). Only a clear "not joined" hides the action; if the state cannot be read it stays visible and the script still checks itself (exit 3). Display rule in user context only, no change of rights.
- New action "No sound on this PC" (user context, category Device, detailed view, `SelfX_Audio_Restore.ps1`): makes the **default playback device** audible again. If it is muted, the sound is switched on; if the volume is below 30 %, it is raised to 30 %, a higher volume stays as it is. Nothing is toggled (the legacy script pressed the mute key and silenced an audible device) and the volume is never lowered; the microphone, other devices, the default device, drivers, services and the registry are not touched, no process is started and no key is sent. The Core Audio calls are in the new library `SelfXAudio.dll` (built by `tools\Build-SelfXBinaries.ps1` into `Bin\Audio`, installed into the protected folder `Audio`). The loader `Sources\SelfXAudio.ps1` compares the DLL with `SelfX.Files.json` (entry `Audio/SelfXAudio.dll`) before loading, keeps the file open and loads nothing if the file, the folder or the list differ. New test `Test-AudioLoad.ps1`, load step in the CI. AppLocker/WDAC rules need one more hash (see `docs\Installation.md`). No administrator or SYSTEM rights needed.
- Copilot Chat: optional clearing of the clipboard (`Copilot_Clear_Clipboard`, default `False`; `Copilot_Clear_Clipboard_Seconds`, 30 to 600, default 180). When the time is over, SelfX empties the clipboard only if the text of this copy is still on it (random marker in its own format; neither the text nor other content is read). If the user has copied something else, it is left alone. Retry when the clipboard is locked for a moment, only the result is logged. The timer runs in the window: if SelfX is closed earlier, the text stays. The dialog names the time and shows a note after the clipboard has been emptied (texts `Copilot_Clear_Text`, `Copilot_Cleared_Text` in German and English). Functions in `Sources\CopilotClipboard.ps1`, tests in `Test-CopilotClipboard.ps1`, details in `docs/en/Configuration.md`.
- Device logs (report for the support): section 8 now starts with a summary of the event logs *System*, *Application*, Windows Update and device management. Critical events, errors and warnings of the last `DeviceLogs_Days` days are counted per provider and event id (the 15 most frequent, with first and last time, a note when more than 5000 events exist). The message text is deliberately not included (it can contain names, paths and addresses), provider names are cleaned. New function `Get-EventCountSummary` in `Collect-DeviceLogs.ps1` (1.3.3), test `Test-EventSummary.ps1`. Runs like the rest of the report in the service (read-only); the report in the ticket / e-mail is the same attachment.
- New action "Refresh the company settings (Group Policy) of this PC" (user context, category Device, detailed view, `SelfX_Device_GpUpdate.ps1`): checks through CIM (`Win32_ComputerSystem.PartOfDomain`) that the device is joined to a domain (also hybrid joined devices; Entra ID joined only devices and workgroups: exit code 3, nothing is started) and runs `gpupdate.exe /force` from System32 with fixed arguments. The input of gpupdate is an empty file (never "y", no `echo y`), the switches `/logoff` and `/boot` are never used: no restart, no sign-out. The script waits up to 5 minutes, ends a hanging run and reports exit code 0 (done) or 1 (error, timeout). No administrator rights, no service. Tests in `Test-Scripts.ps1`, texts in all 24 language files. Note: the action is also shown on devices without a domain and ends there with exit code 3.
- New action "Check this PC for viruses (Microsoft Defender quick scan)" (system context through the SelfX service, category Device, detailed view, `SelfX_Defender_QuickScan.ps1`): starts a quick scan through CIM (`MSFT_MpScan.Start`, ScanType 1), waits until it has finished (service time limit 40 minutes) and then reads the detections since the start (`MSFT_MpThreatDetection`, `MSFT_MpThreat`). The result is shown as a message: no threat found (exit 0) or threat found (exit 2, warning pointing to Windows Security); exit 1 on error or when Defender is not active (for example another antivirus product). Only the number and the names of the threats are logged, no file paths. SelfX does not delete, move or change anything; handling follows the Defender policy. New functions `Start-SelfXDefenderQuickScan` and `Get-SelfXDefenderDetection` in `SelfXDefender.ps1`, tests in `Test-Scripts.ps1`, texts in all 24 language files. The original template (full scan as a job, result always "no threats") was not taken over.
- New action type "Link" in the catalogue (`Context` `Link`, field `Link`): after the confirmation SelfX opens an https address from `Tool_Config.xml` (key `Link_<Name>`) in the browser of the user. No script runs and the service is not involved; the service does not know such entries. Only https addresses without user name and password are opened (`Resolve-SelfXCatalogLink` in `SupportLinks.ps1`); an empty value, `Off` or an invalid value hides the action. New actions in the category "Account": "Forgot or expired password: reset it yourself" (`Link_PasswordReset`, default `https://passwordreset.microsoftonline.com/`) and "Manage the sign-in methods of your account (security info)" (`Link_SecurityInfo`, default `https://mysignins.microsoft.com/security-info`). `Test-Catalog.ps1` checks that link actions have no script and that their key in `Tool_Config.xml` holds a valid https address. Texts in all 24 languages, catalogue 2.4.7.
- New action "Office asks to activate or reports an unlicensed product" (user context, category Office, detailed view, `SelfX_Office_ResetLicence.ps1`): closes the Office apps of the own session (Word, Excel, PowerPoint, Outlook, Access, OneNote, Publisher, Visio, Project, Skype for Business; not Teams) and removes only the contents of the license token folders of the user: `%LOCALAPPDATA%\Microsoft\Office\Licenses` and `\Microsoft\Office\<version>\Licensing` of every version that exists. Independent of the Office version, bitness and installation type (no fixed `16.0` path). Registry, documents, settings and program files are not changed; links (junctions, symbolic links) are never followed. Office asks to sign in at the next start. An Office app that does not close stops the action without deleting anything. New helper `Get-SelfXOfficeLicenseFolder` in `SelfXOffice.ps1`. Texts in all 24 languages, catalogue 2.4.6.
- New action "Outlook suggests wrong or outdated e-mail addresses" (user context, category Outlook, detailed view, `SelfX_Outlook_CleanAutoComplete.ps1`): closes classic Outlook of the own session (asks it to close first, ends it after 10 seconds), starts it with the switch `/cleanautocompletecache` and so clears the auto-complete list of suggested addresses. Mailbox, contacts and profile stay unchanged; the new Outlook is not affected. The program is found independent of the Office version, the bitness (32 or 64 bit) and the installation type: path of the running Outlook, App Paths registration, Office InstallRoot of every installed version; only a file below Program Files is used and nothing is searched in `PATH`. New helper `Sources\SelfXOffice.ps1` (program path, processes of the own session only), tests `Test-OfficeHelper.ps1` and `Test-Scripts.ps1`. Texts in all 24 language files.
- Copilot Chat (off by default, `Copilot_Enabled`): row *Ask Copilot Chat* in the help dialog. The user describes the problem, SelfX shows a preview of the text (fixed list of device facts from `Sources\CopilotFacts.ps1`, names and addresses as placeholders), copies it and opens the address `Copilot_Url` (`https://` only, freely selectable). The user pastes the text, SelfX sends nothing and uses no interface. New settings `Copilot_Enabled`, `Copilot_Url`, `Copilot_Audience`, `Copilot_Include_AppNames`, texts in all 24 language files, test `Test-CopilotFacts.ps1`. Details in `docs/en/Configuration.md`.
- Basis for "Copilot Chat" (`Sources\CopilotPrompt.ps1`, test `Test-CopilotPrompt.ps1`): building blocks that turn a few validated device facts into a short prompt for Microsoft 365 Copilot Chat. Only a fixed list of fields gets in, names, addresses and identifiers are replaced by placeholders (`<email>`, `<ip>`, `<device>`, `<server 1>` ...), and the length is limited. The building blocks read nothing from the device, do not use the clipboard and send nothing. Also the check of the address that opens Copilot Chat (`https://` only, no credentials).
- System information: optional network measurements (off by default, file `Network_Test_Config.xml`): round-trip time to the default gateway and DNS lookup and TCP connection duration to up to 5 configured targets (internal or internet-reachable domain name freely selectable, only administrators change the file, host name and port strictly checked, at most 20 seconds per run, user context, read-only). Check tool `tools\Test-SelfXNetworkMeasure.ps1`, test `Test-NetworkMeasure.ps1`.
- Ticket by e-mail: recipient and Cc can be set per device in the registry (`HKLM\SOFTWARE\SelfX\Support`: `TicketMail`, `TicketCc`, writable by administrators only) and take precedence over the rules in `Ticket_Config.xml`. Each device then holds only the address of its own unit. Documentation: shared mailboxes only; example Intune script in the installation guide.
- Ticket by e-mail: assignment to the responsible IT unit through the new file `Ticket_Config.xml` with any number of units (recipient, optional Cc) and rules for group tag, OU and device category (exact value or Regex, first matching rule wins, otherwise the default address). Group tag and category are read from `HKLM\SOFTWARE\SelfX\Support`, the OU from the computer account. New: `tools\Test-SelfXTicketRouting.ps1` for a check before distribution.
- Ticket by e-mail (off by default, `Ticket_Enabled`): button *Create ticket* in the help dialog. The user describes the issue, SelfX always adds all device information (text and file) and opens the e-mail in classic Outlook (COM) or the default mail program (for example new Outlook, mailto plus file in Explorer); only the user sends it. Recipient only from the configuration (`Ticket_Mail`, otherwise `Support_Mail`). New file `TicketSend.ps1`, tests in `Test-Ticket.ps1`.
- Foundation for "open a ticket from SelfX" (`Sources\TicketMail.ps1`, test `Test-Ticket.ps1`): ticket model with a standardised subject and body, cleaned fields, the free text in a fenced block and a validated mailto link. Building blocks only, no function and no user interface yet; nothing changes for users.

- System information: the "Uptime" row is shown as a warning with the hint "restart recommended (not "Shut down")" from 7 days without a restart (read-only; SelfX never restarts Windows). Reason: with fast startup "Shut down" does not reset the uptime.
- System information, Network section: new rows "Proxy (user setting)" (manual proxy with server and port, address of the configuration script; credentials in addresses are masked) and "Network drives" (drive letters only, also disconnected ones, no share paths). Read-only, no network access. Note: the proxy addresses also appear in the export of the system information.
- New action "Microsoft Edge: clear the cache" (user context, category Browser, `SelfX_Browser_ClearEdgeCache.ps1`): closes Edge of the own session and removes only the `Cache`, `Code Cache` and `GPUCache` folders of the Default profile; cookies, history, passwords and bookmarks stay. Linked folders (junctions) are skipped. German text in `de.xml`, other languages show the English text.
- New action "Solve an issue with Outlook" (user context, category Outlook, `SelfX_Outlook_Reboot.ps1`): closes classic Outlook of the own session and starts it again. Profile, data files and add-ins stay unchanged; the new Outlook (`olk.exe`) is not affected. German text in `de.xml`, other languages show the English text.
- New action "The time of your device is wrong" (system context through the SelfX service, category Device, `SelfX_Device_SyncTime.ps1`): starts the Windows Time service when needed and runs `w32tm.exe /resync /force` with fixed arguments. Time source, configuration and time zone are not changed. Blocked while another user is signed in (`OtherSessions=Block`). German text in `de.xml`, other languages show the English text.

### Changed
- Security (follow-up findings N1 to N3 of the review of the file list check, service 2.8.6): (N1) The service checks `Tool_Config.xml` and `Issues_List.xml` first; when the check stops at 20 problems this is noted as the last entry in the log and in event 4005, and `Service_FileCheck=Audit` no longer applies then (the stop still ends in a refusal, only the list was incomplete). (N2) Every file in the install folder, of any type (also `.json`, `.config`, `.cmd`, `.bat`, `.vbs`, `.psc1`, `.manifest`), must be in `SelfX.Files.json`; only the list itself is exempt. (N3) The rights check of PowerShell 7 before every start accepts only SYSTEM, Administrators and TrustedInstaller as writers of `pwsh.exe`, its folder and all folders up to the drive root (any other identity with write, delete, permission or ownership rights is refused, groups such as CREATOR OWNER included); rules that only apply to child items do not count. Tests in `Test-ServicePipe.ps1` (2.8.20). The check in `Install.ps1` is unchanged.
- The four restart actions for Outlook, Word, Excel and the Teams meeting add-in (`SelfX_Outlook_Reboot.ps1`, `SelfX_Word_Reboot.ps1`, `SelfX_Excel_Reboot.ps1`, `SelfX_Outlook_TeamsAddIn.ps1`) now use the shared function `Stop-SelfXOfficeApp` of `SelfXOffice.ps1` (the same code existed four times). Behaviour is unchanged (processes of the own session are ended at once, then the app starts again, without a question). New: the program path is checked (below Program Files, no link) and found independent of the Office version and 32/64 bit, also through the Office install paths; if no valid path is known, nothing is closed. A process running outside Program Files is no longer taken over as the start path. No change of rights, user context.
- Missing translations added: in the 22 languages other than German and English, the actions "Outlook" (Q_Outlook), "Synchronize the clock" (Q_Device_SyncTime) and "Edge cache" (D_Edge_Cache), the clipboard notes of Copilot Chat and the Remote Help texts showed the English text only. The Copilot prompts stay in English on purpose (they exist in English and German only; they tell Copilot to answer in the language of the problem description). `Test-LanguageFiles.ps1` no longer warns about them. The translations are machine-made; a review by native speakers (ar, fa, ur, bn, hi, th, sw) is recommended.
- Copilot Chat: the default address `Copilot_Url` is now `https://copilot.cloud.microsoft` (before: `https://m365.cloud.microsoft/chat`). Values already set in `Tool_Config.xml` stay unchanged. Tests adjusted.
- Copilot Chat: the copied text is put on the clipboard in a way that asks Windows not to keep it in the clipboard history (Win+V) or the cloud clipboard (formats `CanIncludeInClipboardHistory`, `CanUploadToCloudClipboard`, `ExcludeClipboardContentFromMonitorProcessing`; new file `Sources\CopilotClipboard.ps1`, test `Test-CopilotClipboard.ps1`). This is a request to Windows, not a protection against programs that read the clipboard, and it does not empty the clipboard. If the object cannot be created, the text is copied as plain text as before and a warning is logged (never the text). No new setting.
- Security (finding N4, follow-up): the DLLs in the folder `WinRT` are checked when they are loaded. `SelfX.Files.json` now also lists `WinRT/<name>.dll` (from `Bin\WinRT`), `Install.ps1` checks them in the package, the service refuses an unlisted `.dll` in the installation folder (service 2.8.4), and the new helper `Sources\SelfXWinRT.ps1` (`Import-SelfXWinRT`) compares every DLL with the list before loading it and keeps the files open (read only) so they cannot be replaced between the check and the load. A mismatch, an additional DLL, a sub folder, a link or a missing list: nothing is loaded (update action: interface not available, reason in the log; restart information empty). Autopilot and the installation are not affected. Test `Test-WinRTLoad.ps1`, `Test-FileManifest.ps1` extended. No signature; an administrator can change the DLL and the list together.
- Security (finding N4, follow-up): `SelfX.Files.json` now also lists `SelfXService.exe` and `SelfX.exe` (from `Bin`). The package build fails when one of them is missing; `Install.ps1` (2.8.3) checks them in the package and, after copying, compares the **installed folder** with the list once more (new function `Test-SelfXInstalledFiles`; a difference between the checked package and the copy stops the installation before the service is created). The service (2.8.5) counts `.exe` among the checked files: the two programs are compared by SHA256, an unlisted `.exe` in the installation folder is refused (event 4005, `Service_FileCheck` applies as before). Limit: a replaced `SelfXService.exe` skips its own check; the check detects accidents (broken update), the protection against an attacker comes from the folder rights and App Control. Tests in `Test-FileManifest.ps1` (2.8.3).
- Status icon (Windows 11): the icon is shown permanently next to the clock and no longer hidden in the overflow (arrow). New: `Tray_Pin_Icon` in `Tool_Config.xml` (default `True`); the user value `HKCU\Software\SelfX\TrayPin = 0` switches it off. Runs in the user context and only writes `IsPromoted` of its own entry under `HKCU\Control Panel\NotifyIconSettings`. Test `Test-TrayPin.ps1`.
- Remote support: when Remote Help is installed (`%ProgramFiles%\Remote Help\RemoteHelp.exe`, validly signed by Microsoft, no link), the tile starts Remote Help and SelfX does not offer Quick Assist. Without Remote Help it stays Quick Assist. No new setting. Runs in the user context. Texts `SystemInfo_RemoteHelp_Text` and `Tooltip_RemoteHelp` (de, en; other languages show the English text). Test `Test-RemoteHelp.ps1`.
- Service 2.8.3: the daily housekeeping now also deletes device reports (`%ProgramData%\SelfX\Reports\<SID>\DeviceLogs-*.txt|.zip`) after 7 days and empty user folders, not only at the next report. Only SID-named folders, only report files, no links, only folders owned by SYSTEM or administrators. Test in `Test-ServicePipe.ps1`.
- Documentation (finding N10): new section "Execution policy (`-ExecutionPolicy Bypass`)" in `docs\Installation.md`: why SelfX starts with `Bypass`, that the execution policy is not a security boundary and what protects instead (file list, WDAC). No code change.
- German restart hint at the bottom of the main window (`Reboot_Alert` in `de.xml`) now says to restart the device daily instead of at least once a week. The other languages are unchanged.
- Security (finding N4, part 3): optional support for App Control for Business (WDAC). New: `tools\New-SelfXWdacPolicy.ps1` creates a supplemental policy with hash rules for all programs, libraries and scripts from the package (Bin, Sources, `Install.ps1`, `Detection.ps1`, `Uninstall.ps1`); audit or enforced mode is decided by the base policy. New section "App Control for Business (WDAC), optional" in `docs\Installation.md` (procedure, audit mode first, update per version, notes on Autopilot). Nothing changes in the package or on the devices. Test `Test-WdacPolicy.ps1`.
- Security (finding N4, part 2): the service (2.8.2) checks the installed files against `SelfX.Files.json` before **every** start of a script (action, health check, background check): SHA256 of all listed files, no script and no XML file without an entry, no link (junction, symbolic link) in the way. On a mismatch or a missing or invalid list it starts nothing (answer `ERROR Installed files are not intact`, event 4005, details in the SelfX log). New setting `Service_FileCheck` (`Enforce` default, `Audit` = log only) in `Tool_Config.xml`. The installation is not affected. Tests in `Test-ServicePipe.ps1`.
- Security (finding N4, part 1): file list `SelfX.Files.json`. `tools\New-SelfXIntuneWin.ps1` (1.5.0) writes the SHA256 of every installed file (everything below `Sources`, plus `Uninstall.ps1`) into the package when it is built; the list is created again at every build, nothing is maintained by hand. `Install.ps1` checks the package against the list before the installation (changed, missing or unlisted files, invalid names: abort before anything is changed; missing list: warning) and places the list in the installation folder. The service will use it in a following PR to check scripts before they start. Test `Test-FileManifest.ps1` (also in Windows PowerShell 5.1).
- Security (finding N5, part 2): the token of the service is limited to the privileges it needs. `Install.ps1` sets nine privileges with `sc.exe privs` (ChangeNotify, Impersonate, CreateGlobal, Shutdown, Systemtime, Backup, Restore, TakeOwnership, ManageVolume); `SeTcb`, `SeDebug`, `SeCreateToken`, `SeLoadDriver`, `SeSecurity` and others are missing for the service and all scripts it starts. New setting `Service_Privileges` in `Tool_Config.xml`: `Restricted` (default) or `Default` (all LocalSystem privileges, only to find a problem). If setting fails there is only a warning (Autopilot is not affected). Test every System action on a test device before the rollout, see `docs/Installation.md`. Tests in `Test-InstallBinaries.ps1`.
- Security (finding N5, part 1): the service no longer needs `SeTcbPrivilege`. The `OtherSessions=Block` check reads the signed-in sessions through `WTSQuerySessionInformation` (account as `DOMAIN\user`) instead of `WTSQueryUserToken` and compares them with the account of the caller's session; this works for local, domain and Entra ID accounts. Sessions that cannot be read still block (fail closed). Behavior for users is unchanged. Test in `Test-ServicePipe.ps1`. Part 2 (limit the service privileges) follows.
- Security (finding N12): release workflow `.github/workflows/release.yml`: runs only for a tag `v<major>.<minor>.<patch>`, checks the tag against `Tool_Version`, builds the programs, the `.intunewin`, the SBOM (CycloneDX 1.5, new `tools\New-SelfXSbom.ps1`) and `SHA256SUMS.txt` and creates a draft release (nothing is published automatically; the token with write permission is used only in the last step, no further third-party actions). CI checks the SBOM. Distribution stays the `.intunewin` in the Intune admin center, see `docs/Installation.md`.
- Cleanup (findings N11, N13): `Collect-DeviceLogs.ps1` (1.3.2) no longer contains Swisscom specific parts: the sections "Swisscom deployment" and "Swisscom logs", the registry value `HKCU\Software\Swisscom` and the parameter `-MaxLinesPerLog` are removed, the sections are now numbered 1 to 10; the other sections (ESP, Autopilot, Intune extension, servicing, events, AppX) stay. The internal type of the OOBE query is named `SelfX.DeviceLogs.Collector`. The comments in `SelfXService.cs`, `SelfXLauncher.cs`, `SelfXSessionStarter.cs` and the `.csproj` files no longer name the .NET Framework compiler (C# 5) but the build with the .NET 10 SDK; the version line of `SelfXService.cs` is 2.8.0. No code change in the service.
- Security (finding N9): All XML files read by the window, the status icon, the health check, the log management and the collector script (`Tool_Config.xml`, `Issues_List.xml`, `Health_Config.xml`, language files) are loaded through an `XmlReader` with `DtdProcessing = Prohibit` and no resolver. A file with a DOCTYPE or entities (entity expansion, external entities) is rejected; the shipped files contain none. Static check in `Test-Scripts.ps1`.
- Security (findings N7, N8): help dialog and system information. Links from `Tool_Config.xml` are checked before they are opened (new `Sources\SupportLinks.ps1`): only `https://`, `mailto:` with exactly one address and the Teams chat link of SelfX; a `Support_Website` with `http://` is no longer shown, an invalid `Support_Mail` or `Support_Teams` is shown without a button, the log names the reason. The recipient of the device logs e-mail is only used as one valid address. Programs start with their full path: `explorer.exe` and `MdmDiagnosticsTool.exe` from the Windows folder; Outlook and Word are no longer started by program name (path from the closed process or from App Paths; if it is unknown nothing is closed). Tests `Test-SupportLinks.ps1`, `Test-Scripts.ps1`.
- Security (findings N3, N6, F12): The service creates the first pipe instance with `FirstPipeInstance`. When another process already owns the pipe name, the service does not join it, logs this (`SelfXService.log`, Windows event 4001) and retries every second. New: entries in the Windows event log (Application, source `SelfXService`, IDs 4001 to 4004 and 4099; fixed texts without user data, at most 10 per ID in 10 minutes), see `docs/en/Installation.md`. `%ProgramData%\SelfX` is checked at start and daily (link, owner); while it is not safe, the service writes nothing there and reads no status cache (event 4004). Test in `Test-ServicePipe.ps1`.
- Security (finding N2): `Collect-DeviceLogs.ps1` (1.3.1) creates the report file safely. A file, link or hard link created in advance in `C:\Windows\Temp` (owner not SYSTEM, administrators, TrustedInstaller or the running account) is removed (the name only, never the target) and the report is created new; default reports are readable only by SYSTEM and administrators. The path of the Intune diagnostics (`%windir%\temp\%computername%*.log`) is unchanged. Test `Test-CollectorOutput.ps1`.
- Security (finding F12): `Install.ps1` prepares `%ProgramData%\SelfX` before use. A folder or junction created in advance is no longer taken over: links are removed (never the target), entries not owned by SYSTEM, administrators or TrustedInstaller are deleted (the user area `Logs\Users` is left alone), then owner and rights are set again. A failing `icacls` stops the installation. Test in `Test-InstallBinaries.ps1`.
- Copilot Chat: the English instruction texts now ask Copilot to answer in the language of the problem description, or in the interface language named in the data if there is no description. This helps users whose interface language has no instruction text of its own (they get the English text).
- Copilot Chat: the instruction texts of the prompt are now in the language files (`Copilot_Prompt_User`, `Copilot_Prompt_Admin` in `de.xml` and `en.xml`, other languages show English) and can be adjusted without a code change. A text without `{DATA}`, with `{DATA}` more than once or longer than 3000 characters is replaced by the built-in text. Content unchanged; a test makes sure that the language file and the built-in text match.
- Copilot Chat: `Copilot_Include_AppNames` = `False` now also removes the details of the *Company apps* row in the device status. Before, the app names were still part of the text there. New in the text: kind of connection (LAN, Wi-Fi, mobile, VPN) and kind of proxy (none, manual, script), from local values, without an internet test and without addresses. The dialog shows a note (do not write names, passwords or customer data, do not run commands you do not understand).
- Documentation: `docs/Configuration.md` rewritten in plainer language, outdated version notes and history removed, headings without version numbers (links updated).
- Translations added: all 22 language files (except German and English) were missing 28 texts, which were shown in English: notice while another person is signed in (`Service_OtherSessions_Text`), ticket dialog (`Ticket_*`), uptime hint, proxy and network drives, and the network measurements (`Latency_*`).

- Status row "Restart pending": the text now names the last restart and, when the last update installation was after it, its time (read-only, times in the time zone of the user). If the sources are missing, only the addition is left out.

## 2.8.0 - 2026-11-22 (SelfX Service)

The service, the window and the status icon start PowerShell 7 (7.6 or newer) instead of
Windows PowerShell 5.1. The minimum version is Windows 11 25H2 (build 26200). `Tool_Version`
and `$ExpectedVersion` were raised: rebuild and redeploy the package. Before deploying,
provide PowerShell 7 as a Win32 app and set the requirement rule for build 26200
(see [Installation](docs/en/Installation.md#windows-version-and-powershell-7-since-280)).

### Changed

- Documentation: `docs/en/Installation.md` describes Windows 11 25H2 and PowerShell 7 as requirements, the behavior of the
  installer and the service, deploying PowerShell 7 with Intune (Win32 app, dependency, Autopilot/ESP, requirement rule for
  build 26200) and the extended release checklist.
- Clearing the DNS cache and checking the system drive without the compatibility layer: CIM (`MSFT_DNSClientCache.Clear`,
  `MSFT_Volume.Repair` with `OfflineScanAndFix`) instead of `Clear-DnsClientCache` and `Repair-Volume`.
- BitLocker and TPM without modules: device status and compliance check read CIM (`Win32_EncryptableVolume`, `Win32_Tpm`,
  file `Sources\SelfXDeviceSecurity.ps1`) instead of `Get-BitLockerVolume` and `Get-Tpm`. This fixes an earlier bug: data
  drives were never checked because the type was named "Data", not "FixedData". Fixed data drives without BitLocker
  now show "Error" in the BitLocker status.
- Secure Boot check (compliance) reads the registry (`UEFISecureBootEnabled`, new file `Sources\SelfXDeviceSecurity.ps1`)
  instead of `Confirm-SecureBootUEFI`: no Windows PowerShell compatibility layer and no administrator rights needed.
- Defender without the Defender module: status (device status, compliance) and signature update use CIM
  (`root\Microsoft\Windows\Defender`, new file `Sources\SelfXDefender.ps1`) instead of `Get-MpComputerStatus`
  and `Update-MpSignature`. Update sources and their order still come from the Defender policy.
- Network without the NetAdapter module: adapters, default routes and the adapter restart ("Restart network")
  use CIM (`root\StandardCimv2`, new file `Sources\SelfXNetwork.ps1`) instead of `Get-NetAdapter`,
  `Get-NetRoute` and `Restart-NetAdapter`. PowerShell 7 no longer starts Windows PowerShell 5.1 for it.
  Also fixes that devices without an IPv6 default route lost all default routes.
- CI: the tests now run in PowerShell 7 as a blocking job. Windows PowerShell 5.1 only checks
  `Install.ps1`, `Uninstall.ps1`, `Detection.ps1` and the log collector (Intune starts them there).
  The health check and the support report no longer contain PowerShell 5.1 branches.
- "Install updates" uses only the Windows Update orchestrator (`SelfXWinRT.dll`,
  PowerShell 7). The Windows Update Agent API and the PowerShell 5.1 branch are removed
  (minimum version Windows 11 25H2). If the orchestrator API is missing, the action ends with exit 1.
- Minimum version: Windows 11 25H2 (build 26200). `Install.ps1` checks the build number
  (registry) before changing anything and stops hard on older builds; the existing
  installation stays unchanged.
- The service starts every script with `%ProgramFiles%\PowerShell\7\pwsh.exe` (fixed
  path, no PATH search). For the script it sets only the machine-wide module folders
  (`PSModulePath`) and turns off PowerShell telemetry and the update check. When
  PowerShell 7 is missing it starts nothing and reports "PowerShell 7 is not installed".
- `SelfX.exe`, `Start-SelfXHiddenPowerShell`, the health check and the log collector use
  the same fixed path.
- Autopilot must always work: when PowerShell 7 is missing (or older than 7.6),
  `Install.ps1` installs SelfX anyway and only warns. Until PowerShell 7 is there the
  service starts no scripts and reports "PowerShell 7 is not installed". When PowerShell 7
  is present but normal users can change it (folder or `pwsh.exe`), the installation stops
  before anything is changed (security). The service checks rights and version again before
  every start, because PowerShell 7 can be installed after SelfX. `Install.ps1` and
  `Uninstall.ps1` still run in Windows PowerShell 5.1 and close windows and status icons
  of `powershell.exe` and `pwsh.exe`.
- `Test-ServicePipe.ps1` and `Test-HealthStatus.ps1` also compile the service in
  PowerShell 7; `Test-InstallBinaries.ps1` tests the new prerequisite.

- New library `SelfXWinRT.dll` (.NET 10, Windows SDK projection) replaces the WinRT access
  to the Windows Update orchestrator (Windows 11 24H2 and newer) in PowerShell 7, which
  cannot load Windows Runtime types by name any more. It contains no logic of its own and
  only returns the manager object. `Build-SelfXBinaries.ps1` builds it with the two
  projection files into `Bin\WinRT`; `Install.ps1` checks every file by SHA256 and copies
  it to `%ProgramFiles%\SelfX\WinRT`. On older Windows the scripts fall back to the Windows
  Update Agent as before.
- The manifest `SelfX.Binaries.json` now has format 3 (entries `WinRT/...`). The installer
  refuses packages with format 2: build the package again.

## 2.7.0 - 2026-11-22 (SelfX Service)

The service and the starter run on .NET 10 (LTS, supported until 14 Nov 2028). The
programs are built once on a build machine; the devices no longer compile anything.
`Tool_Version` and `$ExpectedVersion` were raised: build and deploy the package again.

### Changed

- `SelfXService.exe` and `SelfX.exe` are .NET 10 programs (self-contained, one file,
  about 36 MB each). No .NET runtime is needed on the devices. The user interface and
  all scripts still run in Windows PowerShell 5.1.
- `tools\Build-SelfXBinaries.ps1` builds with `dotnet publish` (.NET SDK 10 on the
  build machine). The call stays the same. The manifest has format 2.
- `Install.ps1` requires the folder `Bin` and checks it before it touches the existing
  installation. Compiling on the device was removed. When `Bin` is missing, the
  installation stops with a clear message and the old version stays.
- `tools\New-SelfXIntuneWin.ps1` builds no package without a checked `Bin` and does not
  package the .NET project files.
- New: .NET projects in `SelfX Service\Service\Projects`, NuGet lock file, a CI job that
  builds twice, compares the hashes and starts the service.
- Installation guide rewritten with a step-by-step procedure.

### Note

New programs have new hashes: replace the AppLocker rules of the previous build.

## 2.6.12 - 2026-11-22 (SelfX Service)

German is the base language of the user interface; English is the fallback.
Raise of `Tool_Version` and `$ExpectedVersion`: redeploy the package.

### Changed

- `Tool_Language` in `Tool_Config.xml` is now `de` by default (before: `Auto`,
  the Windows display language). Users can still choose another language in
  SelfX > Settings; `Auto` remains possible.
- If no language file matches (for example `Auto` on a device in Czech), SelfX
  uses German instead of English. A text that is missing in the selected
  language is shown in English.
- `Test-UI.ps1` tests the base language.

Not changed: the texts of the actions in `Issues_List.xml` stay English base
texts, which are used only if a text is missing in German and in English.

## Repository, 2026-11-22

- The fork is developed only for SelfX Service. The folders `SelfX Standard`
  and `SelfX Admin` were removed; use the upstream projects if you need them.
  `tools\New-SelfXIntuneWin.ps1` (1.3.0) builds only the SelfX Service package;
  `Test-UI.ps1` no longer reads a file of SelfX Standard.
- README, installation guide, configuration guide, user manual and
  `SECURITY.md` describe only SelfX Service.
- The package version of SelfX Service is unchanged (2.6.11).

## 2.6.11 - 2026-11-22 (SelfX Service)

Security hardening release. It replaces the service and the installer: redeploy
the **entire package**. The update installs like every other update;
`Tool_Version` and `$ExpectedVersion` of `Detection.ps1` are both raised to
2.6.11.

### Security

- **Pipe deadlines that work reliably.** The pipe of the service uses
  overlapped I/O. Reading the request, writing the answer and waiting for the
  client are cancelled when the deadline passes; if the operation does not end,
  the connection is closed. One 5-second deadline covers the whole request, so
  sending slowly does not extend it.
- **Connection limit before reading.** The limit of 8 connections per user is
  applied when the connection is accepted, using the owner of the client
  process reported by Windows. One user can no longer occupy the 64 connection
  slots of all users before the service has read a request.
- **Prebuilt programs checked by hash (optional).** `tools\Build-SelfXBinaries.ps1`
  builds `SelfXService.exe`, `SelfX.exe` and `SelfXSessionStarter.dll` once on a
  build machine and writes `SelfX Service\Bin\SelfX.Binaries.json` with the
  SHA256 of the sources and the files. When the AppLocker cmdlets are
  available, it also writes `build\SelfX.AppLocker.xml` with hash rules for the
  three files. If the package contains `Bin`, `Install.ps1` checks the
  manifest, the sources and the hash of every file and stops with exit code 1
  when anything does not match; nothing is compiled instead. The files are not
  signed.
- **Protected compiler TEMP.** Without `Bin`, the device still compiles the
  programs, but the compiler now writes its temporary files to a folder below
  the protected install folder instead of `C:\Windows\Temp`.
- **Packaging.** `tools\New-SelfXIntuneWin.ps1` refuses a `Bin` folder that was
  built from other sources than the ones in the package.

### Added

- `LICENSE.md`: additional copyright line for the changes in this fork (text and original line unchanged).
- `NOTICE.md` / `NOTICE.en.md`: authors and sources (Damien Van Robaeys, Wolfgang Baeck, Jannik Reinhard).
- `Test-ServicePipe.ps1`: starts the pipe listener of the service under a test
  pipe name and checks the deadlines, slow senders, oversized requests and the
  per-user limit. It needs no installation and no administrator rights.
- `Test-InstallBinaries.ps1`: tests the check of the prebuilt programs and the
  protected compiler TEMP.
- GitHub Actions workflow `.github/workflows/service-ci.yml`: compiles the
  service, launcher and session starter, runs all `Test-*.ps1` in Windows
  PowerShell 5.1 and runs PSScriptAnalyzer with security rules for every pull
  request and every change of `main`. The workflow has read-only rights and
  uses actions pinned to a commit.
- `SECURITY.md` (private reporting of vulnerabilities), `.github/CODEOWNERS`
  and Dependabot for the pinned GitHub Actions; this `CHANGELOG.md`.

### Fixed

- Four existing tests failed on the first run on a Windows runner (parser error
  in `Test-Catalog.ps1`, a changed method signature in `Test-HealthStatus.ps1`,
  and two tests that assumed a non-elevated account). The product code was not
  affected.

### Changed

- A connection above the per-user limit is closed without an answer (before:
  the answer *busy*). The SelfX window does not reach this limit.
- Documentation: new installation and release checklist, description of the
  prebuilt programs and of the AppLocker rules, updated test list.

## 2.6.10 - 2026-11-22 (SelfX Service; delivered with 2.6.11)

Findings of the security review of SelfX Service. The pull request numbers
refer to this repository.

### Security

- **Device logs report (#1, #2).** The report no longer reads the log folders of
  the users as SYSTEM (users can change these folders). The SelfX window adds
  the own user logs with the rights of the user. On multi-user devices a normal
  user receives only the own data; only an elevated administrator (read by the
  service from the client token, `SELFX_CALLER_ADMIN=1`) gets the complete
  report.
- **Status cache (#3).** A single health check (`HEALTH <Id> <name>`) with an
  unknown name can no longer append rows to the status cache that all users and
  the status icon share.
- **Service log and requests (#4).** Text from requests is cleaned and
  shortened before it is logged, rejected requests are logged at most 20 times
  per minute (a user cannot flood the log), and the request patterns end with
  `\z` instead of `$`.
- **Pipe limits (#6).** The service closes connections that send nothing for 5
  seconds or do not read the answer, runs every connection in its own thread
  and accepts at most 64 connections (8 per user). After a check, the same user
  waits 3 seconds for the next one; after an action, 15 seconds before the same
  action can be started again. In both cases the service answers *busy*.
- **Pipe server check (#7).** Before the SelfX window sends a request it
  checks that the pipe is served by the running `SelfXService` (process ID of
  the pipe server compared with the process ID from the service control
  manager). A user process that created the pipe name while the service was
  stopped is refused.
- **Uninstall (#8).** `Uninstall.ps1 -RemoveLogs` deletes the data folders
  without following junctions or symbolic links that users created.
- **Several users on one device (#9).** New catalogue element
  `OtherSessions` (and attribute on a remediation in `Health_Config.xml`):
  with `Block`, a normal user cannot start the action while another user has an
  active session. The delivered configuration sets it for the restart,
  Windows updates, the disk check, the restart of the network adapters and the
  restart of the Intune service. Elevated administrators are not restricted;
  if the sessions cannot be read, the action is blocked.

### Added

- `Test-Catalog.ps1` (#5): static check of the catalogue, `Health_Config.xml`
  and the scripts that run as SYSTEM (plain file names, one context per script,
  no mandatory parameters, remediation timeouts).
- `Test-Uninstall.ps1` (#8) and extensions of `Test-HealthStatus.ps1` and
  `Test-DeviceLogs.ps1`.

## Based on upstream 2.6.9

Windows updates through the Windows Update orchestrator, pending restart
detection and the other changes up to SelfX Service 2.6.9 come from
[wbaeck/SelfX](https://github.com/wbaeck/SelfX). The history of every file is in
its header.
