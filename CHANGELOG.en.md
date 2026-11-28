# Changelog

**English** | [Deutsch](CHANGELOG.md)

This log describes what changed in this fork ([fubu2k/SelfX](https://github.com/fubu2k/SelfX))
compared with its upstream [wbaeck/SelfX](https://github.com/wbaeck/SelfX) at SelfX Service
2.6.9. Everything up to version 2.6.9 comes from the upstream and is not listed here as new.
The history of each file is in its header.

The package version is the one line of `SelfX Service\Version.txt`; the build writes it into `SelfX.Code.json`
(`ToolVersion`). `Detection.ps1` must contain the same value, otherwise Intune does not detect the update
(the packaging script checks this). A release gets the tag `v<version>` (for example
`v3.0.0`); the release workflow checks that the tag and `Version.txt` match.

## Unreleased (SelfX Service)

- **Time stamp service of the package wizard; `Detection.ps1` without an embedded signature (`tools\SelfXSigning.ps1` 3.1.1, `tools\Wizard\SelfXWizard.ps1` 3.1.13, `tools\Wizard\SelfXWizardGui.ps1` 1.10.0, `tools\New-SelfXPackage.ps1` 1.4.0, `tools\Wizard\Wizard.de.xml` / `Wizard.en.xml` 1.10.0, `Install.ps1`, `docs\Certificate-Guide.md`, `docs\Architecture.md`, `docs\Guided-Setup.md`):** The address of the time stamp service is at most 300 characters (`http` or `https`, no user information, as before). It is used only while the package is built and is saved in `selfx-answers.json` as the build setting `TimestampServer`, never in a settings file of the package: `Read-WizardAnswers` never sees it, `Test-WizardAnswerSet` refuses it as an answer, the window loads it into the page Signature and saves it from there, the console takes it from the answer file when `-TimestampServer` is missing. Before the first file is signed, `Assert-SelfXTimestampService` makes one test signature with the service; when it gives no time stamp, the build stops with a short message that names only the host (before, every file of the package failed after its own wait). A signed build without a time stamp service needs the explicit confirmation: `Invoke-SelfXPackageBuild -NoTimestamp` (window: the existing switch *Sign without a time stamp*; console: `-NoTimestamp` or a question). `Install.ps1` in the trust mode Signature no longer needs an embedded signature on `Detection.ps1` at the top of the package (exactly this path, `Test-SelfXUnsignedPackageFile`; also for `-ConfigOnly`): it is never run or installed by `Install.ps1`, and a full package still covers it with `SelfX.Code.cat`. A `Detection.ps1` in another folder and files with similar names must be signed as before. The detection script for Intune is still signed by the wizard in the trust mode Signature. Changed behaviour: a console or script build with a certificate and without `-TimestampServer` now stops unless `-NoTimestamp` is given. Tests: `tools\Test-SelfXSigning.ps1` (300/301 characters, user information, test signature accepted, failure with a plain text, no time stamp, refused addresses, test script removed, unreachable server), `tools\Test-SelfXPackageWizard.ps1` (kind `timestamp`, answer file with and without the address, address in no file of the package, `-NoTimestamp` rules, test signature first, unreachable service: nothing signed and no output), `tools\Test-SelfXWizardGui.ps1` (one field on one page, 300/301 characters, `-NoTimestamp` to the build, load and save), `Test-InstallBinaries.ps1` and `Test-InstallConfigOnly.ps1` (unsigned `Detection.ps1` at the top accepted and still checked by the catalog; `App\Detection.ps1`, `Detection2.ps1` and others refused). Not tried on a device: a build with a real time stamp service, a service that is down, a signed package with an unsigned `Detection.ps1` on a device.

- **Plain text for app error codes (`Sources\SystemInfo.ps1`, `Sources\Languages\*.xml`):** In the row "Company apps", a known error code of an app installation gets one sentence in the language of the user: what happened and what the user can do. Twelve codes with a source on Microsoft Learn (Intune app installation error reference: 0x87D1041C, 0x8000FFFF; Windows Installer: 1602, 1603, 1618, 1619, 1625, 1632, 1638, 3010 as 0x8007xxxx; system errors 5 and 112). An exit code of an installer written as 0x0000xxxx is looked up as 0x8007xxxx. Unknown codes stay as they are. The text is added by the window (`Add-SelfXAppErrorText`); the service, the health collection and the status cache are unchanged, and nothing is started (the existing repair "Retry" stays the only button). Texts in all 24 language files. Not used: a separate file `AppErrorCodes.xml` (the codes are the English defaults in `SystemInfo.ps1`). Tests: `Test-HealthStatus.ps1`, `Test-LanguageFiles.ps1`. Not tried on a device: a real failed app installation.
- **Wizard question for the hint before disruptive actions (`tools\Wizard\SelfXWizard.ps1` 3.1.12, `tools\Wizard\SelfXWizardGui.ps1` 1.9.0, `tools\Wizard\Wizard.de.xml` / `Wizard.en.xml`):** New question `DisturbWarning` (yes/no, default yes) on the page More settings writes `Disturb_Warning`. An answer file without it keeps the hint on. Tests: `tools\Test-SelfXPackageWizard.ps1`, `tools\Test-SelfXWizardGui.ps1`.
- **The shell call of the disturbance hint is made by a built library (new `Service\SelfXDisturb.cs` and `Service\Projects\SelfXDisturb`, `Sources\SelfXDisturb.ps1` 3.1.0, `Install.ps1`, `tools\Build-SelfXBinaries.ps1` 3.1.0, `tools\SelfXPackage.Common.ps1`, `tools\New-SelfXIntuneWin.ps1`, `tools\Wizard\SelfXWizard.ps1` 3.1.10, `.github\workflows\service-ci.yml`, new `Test-DisturbLoad.ps1`, `Test-Disturb.ps1`, `Test-InstallBinaries.ps1`, `Test-FileManifest.ps1`, `docs\*`):** `SelfXDisturb.ps1` no longer compiles the call to `SHQueryUserNotificationState` on the device (`Add-Type` with source text). The call is in `SelfXDisturb.dll`, built once by `tools\Build-SelfXBinaries.ps1` (offline, no package), listed with its SHA256 in `SelfX.Binaries.json` and `SelfX.Code.json` and installed by `Install.ps1` into `%ProgramFiles%\SelfX\App\Disturb`, in the same way as `SelfXAudio.dll`. The library has one native call, loaded from the system folder only (`DefaultDllImportSearchPaths`), takes no input, reads one value and never throws (0 = cannot be read). Before the window loads it, `SelfXDisturb.ps1` compares the file with `SelfX.Code.json` (folder `Disturb` holds exactly this file, no link, hash from the open handle, handle kept open); a changed, missing or additional file, a link or an invalid list means no hint, never an error. Changed behaviour: none for users. The Defender ASR exclusion guide (documentation and package wizard, German and English) now names five files, `SelfXDisturb.dll` is the new one; without the exclusion a blocked library only means no hint. A running window holds the library open, so an update while a window is open is handled like the one for `SelfXWinRT.dll`. Tests: new `Test-DisturbLoad.ps1` (accepted, changed, missing, additional file, sub folder, links, broken, oversized or unknown list, wrong hash, state 0 on every failed check, no compiling), `Test-Disturb.ps1` (static checks of `SelfXDisturb.cs`: one native call, system folder only, no file, registry or process use), `Test-InstallBinaries.ps1` and `Test-FileManifest.ps1` (the library like the audio library, with refusal cases), `tools\Test-SelfXAsrEvents.ps1`, `tools\Test-SelfXPackageWizard.ps1`; new CI step that loads the built library and reads the state. Not tried on a device: the built library on a Windows 11 device with a real full-screen program, an update with an open window, the ASR rule with the new file.
- **Package for Windows Server without a `.intunewin` file (`tools\Wizard\SelfXWizard.ps1` 3.1.10, `tools\Wizard\SelfXWizardGui.ps1` 1.8.0, `tools\New-SelfXPackage.ps1` 1.3.3, `tools\Wizard\Wizard.de.xml` / `Wizard.en.xml`, `Test-SelfXPackageWizard.ps1`, `Test-SelfXWizardGui.ps1`):** Intune cannot install apps on Windows Server, so a package built with the answer `TargetOS` = `WindowsServer` no longer gets a `.intunewin` file. `Invoke-SelfXPackageBuild` leaves out the step `pack` for it and does not require `IntuneWinAppUtil.exe` (a missing or failing tool path does not matter). Detection script, rule files, the folder `package` and `SelfX-Server-Guide.<language>.txt` stay; the server instructions no longer name the `.intunewin` file. In the window the tool field of the summary page is hidden and the progress list has no step `pack` for Windows Server; the console no longer asks for the tool path. Packages for Windows 11 are unchanged and still need the tool. No change to the installed program, the service or the pipe. Tests: server package without a tool path, with a missing and with a failing tool, as configuration package, steps of the progress list, tool field and result files of the window, Windows 11 unchanged and still refused without a tool. Not tried on a device: installation of a server package on a Windows Server.

- **Hint before disruptive actions (`Sources\SelfXDisturb.ps1` 3.1.0, `Sources\Self_X.ps1`, `Sources\Localization.ps1`, `Sources\Issues_List.xml` 2.4.14, `Sources\Tool_Config.xml`, `Sources\Languages\*.xml` (24 files), `tools\SelfXPackage.Common.ps1`, `Test-Catalog.ps1`, new `Test-Disturb.ps1`):** Before an action that can end a meeting, the confirmation shows one more sentence when the own session of the user looks busy: *You appear to be in a meeting or presentation. This action can interrupt it.* Disruptive actions carry the new optional catalogue element `<Disruptive>True</Disruptive>`: the actions of the scripts that close Teams, Word, Excel or Outlook (`SelfX_Teams_ResetCache.ps1`, `SelfX_Word_Reboot.ps1`, `SelfX_Excel_Reboot.ps1`, `SelfX_Outlook_Reboot.ps1`, `SelfX_Outlook_TeamsAddIn.ps1`) and the restart of the network adapters (`SelfX_Device_AirePlaneMode.ps1`); the restart repair of the device status always has the hint. The window reads `SHQueryUserNotificationState` (shell32, documented) for its own session and adds the hint for the states busy (full screen), Direct3D full screen, presentation settings and quiet time. It is a hint only: nothing is switched, blocked or sent to the service, no other session and no program name is read, and the log names only the action Id. If the state cannot be read, the confirmation has no hint. New setting `Disturb_Warning` in `Tool_Config.xml` (`True` default, `False` = no hint). New text `Disturb_Warning_Text` in all 24 language files. `Test-Catalog.ps1` checks that `Disruptive` is exactly `True`, belongs to an action with a script and is the same on every entry of a script (negative examples). **Deviations from the plan:** the plan names an attribute; the catalogue uses elements for its fields, so `Disruptive` is an element. The microphone and camera state (`CapabilityAccessManager\ConsentStore`, `LastUsedTimeStop` = 0) is not used: on a Windows 11 26H2 test device (build 26300) a classic desktop program that opened the default microphone with `waveIn` for four seconds created no `LastUsedTimeStart` or `LastUsedTimeStop` value for itself within the following seconds, and packaged apps and the camera were not tried, so the value is not confirmed. Changed behaviour: with the delivered `Disturb_Warning` = `True` the confirmation of the marked actions can show the extra sentence. Tests: `Test-Disturb.ps1` (kind for every state, all combinations of setting, marking and state, failing provider, the delivered catalogue, the 24 language files, static checks that `SelfXDisturb.ps1` uses no registry, process, service, file or log), `Test-Catalog.ps1`, `Test-LanguageFiles.ps1`, `Test-UI.ps1`. Not tried on a device: the three states with a real full-screen program, presentation settings and quiet time (only the state 5, nothing running, was read on the test device), the confirmation dialogs with the hint, a right-to-left language, a screen reader, a terminal server.

- **Fixed support address on a terminal server (`Sources\TicketSend.ps1` 3.1.0, `Sources\Self_X.ps1`, `Sources\Tool_Config.xml`, `tools\Wizard\SelfXWizard.ps1` 3.1.9, `tools\Wizard\SelfXWizardGui.ps1` 1.7.0, `tools\Wizard\Wizard.de.xml` / `Wizard.en.xml` 1.8.0):** New setting `TerminalServer_Support_Mail`. On Windows Server it replaces `Support_Mail` and `Ticket_Mail`: it is the support e-mail, the ticket recipient and the address in the help window. The ticket routing (`Ticket_Config.xml`, the address set for a device in the registry) is not used there; the computer name stays in the ticket. Empty or not one plain address: `Support_Mail` and `Ticket_Mail` stay, still without routing, with a warning in the log. On Windows 11 nothing changes. The wizard asks for the address (required) for a package for Windows Server. Tests: `Test-Ticket.ps1` (`Get-SelfXSupportContact`: Client, terminal server, invalid addresses, target without routing), `Test-UI.ps1`, `tools\Test-SelfXPackageWizard.ps1`. Not tried on a device: ticket and help window on Windows Server.
- **Windows Server as a terminal server; the mode comes from Windows (`Install.ps1`, `Detection.ps1`, `Service\SelfXService.cs`, `Sources\SelfXEnvironment.ps1`, `Sources\Self_X.ps1`, `Sources\SelfX_Tray.ps1`, `Sources\HealthStatus.ps1`, `Sources\Tool_Config.xml`, `Sources\Issues_List.xml` 2.4.13, `Sources\Health_Config.xml`, `tools\Wizard\SelfXWizard.ps1` 3.1.8, `tools\Wizard\SelfXWizardGui.ps1` 1.6.0, `tools\Wizard\Wizard.de.xml` / `Wizard.en.xml` 1.7.0, `CLAUDE.md`):** SelfX now installs on Windows Server 2022 and 2025 with Desktop Experience (build 20348 or newer) next to Windows 11 25H2 (build 26200). `Install.ps1` stops before any change on Server Core, on a domain controller, on Windows Enterprise multi-session (EditionID `ServerRdsh`) and when the product type or the build cannot be read. The setting `Environment_Mode` is removed: the service takes the mode from the product type of Windows (RtlGetVersion; workstation = `Client`, everything else and unreadable data = `TerminalServer`), the window, the status icon and the health collection from `ProductOptions\ProductType` in the registry. An old `Environment_Mode` in `Tool_Config.xml` is ignored (a note in `SelfXService.log`); event 4009 is no longer written. `TerminalServer_Health` stays and applies only on Windows Server. The wizard asks *For which Windows is this package?* (`Windows11` or `WindowsServer`) instead of *Where does SelfX run?*; for `WindowsServer` it asks for `TerminalServer_Health` and writes `SelfX-Server-Guide.<language>.txt`: installation by hand or with Configuration Manager, because Intune cannot install apps on Windows Server. `Detection.ps1` now ends "not detected" with exit code 0 and no output (was 1), so Configuration Manager can use it as its detection method; for Intune the result is the same. Tests: `Test-InstallBinaries.ps1` (Windows 11, Server 2022/2025, Server 2019, Server Core, no desktop, multi-session, domain controller, unreadable and unknown values), `Test-ServicePipe.ps1` (mode through a test field: TerminalServer refuses, an old `Environment_Mode Client` does not switch it, Client with any `Tool_Config.xml`; device status per mode), `Test-HealthStatus.ps1` (mode from the product type, mocked; the CI runs on Windows Server), `Test-UI.ps1`, `Test-Detection.ps1`, `tools\Test-SelfXPackageWizard.ps1` (question, server guide, server package). Not tried on a device: installation and use on Windows Server 2022 and 2025, the stop on Server Core and on multi-session, an installation with Configuration Manager.
- **Device status and system information on a terminal server (`Service\SelfXService.cs`, `Sources\SelfXEnvironment.ps1`, `Sources\SystemInfo.ps1`, `Sources\SelfXServiceClient.ps1`, `Sources\CopilotFacts.ps1` 3.1.0, `Sources\Self_X.ps1`, `Sources\SelfX_Tray.ps1`, `Sources\Tool_Config.xml`, `tools\Wizard\*`):** New setting `TerminalServer_Health` = `Off` (default) or `AdminOnly`; it applies only with `Environment_Mode` = `TerminalServer`, any other value counts as `Off`. `Off`: the service runs no background checks (also with `Background Enabled`), writes no status cache and answers `HEALTH` and `STATUS` with `UNAVAILABLE TerminalServer` to every caller; SelfX shows no page *Device status*, the tray icon shows no status and no notifications and only opens SelfX. `AdminOnly`: the service answers `HEALTH` and `STATUS` only to elevated administrators. A `Tool_Config.xml` that the service cannot read counts as `TerminalServer` with `Off`. The daily log housekeeping keeps running. On a terminal server normal users see in *System information*, the ticket and the text for Copilot only rows of their account and session (user, UPN, time zone, proxy, network drives, Citrix Workspace, time of the collection); the rows of the server are shown to elevated administrators only and are not even read for normal users (no `dsregcmd`, no internet test, no connection check). LAN, Wi-Fi, mobile and VPN are not shown on a terminal server. The package wizard asks for `TerminalServer_Health` when the package is for a terminal server. Changed behaviour: none with `Environment_Mode` = `Client`. Tests: `Test-ServicePipe.ps1` (280 checks: access table, `HEALTH` and `STATUS` as user and as administrator in every combination, background loop), `Test-HealthStatus.ps1` (635), `Test-UI.ps1` (382), `Test-CopilotFacts.ps1` (452), `Test-SelfXPackageWizard.ps1`. Not tried on a device: a terminal server with several users, an elevated administrator with `AdminOnly`, the tray icon without status.
- **One package for PCs and session hosts: `Environment_Mode` (`Sources\Tool_Config.xml`, `Sources\Issues_List.xml` 2.4.12, `Sources\Health_Config.xml`, new `Sources\SelfXEnvironment.ps1` 3.1.0, `Sources\Self_X.ps1`, `Sources\SelfX_Tray.ps1`, `Sources\HealthStatus.ps1`, `Sources\Localization.ps1`, `Sources\SelfXServiceClient.ps1`, `Service\SelfXService.cs`, `Sources\Languages\*.xml` (24 files), `tools\Wizard\*`, `tools\SelfXPackage.Common.ps1`):** New setting `Environment_Mode` = `Client` (default) or `TerminalServer`; any other value counts as `Client` and is logged. Every action has the required element `<TerminalServer>Show</TerminalServer>` or `Hide`, every repair the attribute `TerminalServer`; `Test-Catalog.ps1` fails without it or when the entries of one script differ. `Show` = only the own session or profile, `Hide` = the whole device or all users. With `TerminalServer` the window, the status icon and the device status hide what is not `Show`, also the part of the user of a repair, and the service refuses `RUN` for it for every caller, also elevated administrators (answer `ERROR TerminalServer`, own message in SelfX, event 4008). A missing classification counts as `Hide`; a `Tool_Config.xml` that the service cannot read counts as `TerminalServer`. The check of other active sessions (`OtherSessions`) is the same in both modes. At the start the service warns when Windows is a session host (product type of a server as Windows Enterprise multi-session reports it, or application server mode) but the mode is `Client` (log, event 4009); it never changes the mode. The package wizard asks "Where does SelfX run?". Delivered classification: user actions of the own session `Show`; no sound, clear DNS cache, Store reset and all `System` actions and repairs `Hide`. Changed behaviour: none with the delivered `Client`. Tests: `Test-Catalog.ps1` (600 checks, negative examples), `Test-ServicePipe.ps1` (252 checks, both modes through `ProcessRequest` of a test instance, nothing is started), `Test-HealthStatus.ps1` (615), `Test-UI.ps1` (376), `Test-SelfXPackageWizard.ps1`. Not tried on a device: Windows Enterprise multi-session, a Remote Desktop Session Host, event 4009, two users at the same time with `TerminalServer`.
- **Chrome and Firefox cache actions stop only processes of their own session (`Sources\Scripts_to_run\SelfX_Browser_ClearChromeCache.ps1` 2.6.1, `Sources\Scripts_to_run\SelfX_Browser_ClearFirefoxCache.ps1` 2.6.1, `Test-Scripts.ps1`):** Both scripts stopped every reachable `chrome` or `firefox` process, including those of other signed-in sessions on a multi-user device. They now stop only the processes of the session in which they run, as the Edge script already did. A static test checks that every user script which calls `Stop-Process` filters by session. Behaviour change: browser windows of other users stay open. Tests: `Test-Scripts.ps1` (643 assertions) and the package tests on the development PC; PSScriptAnalyzer was not run locally. Not tried on a device: a second signed-in user with an open Chrome or Firefox window.
- **Free up space on the disk row (`Sources\Scripts_to_run\SelfX_Device_FreeSpaceUser.ps1` 3.1.0, `Sources\Scripts_to_run\SelfX_Device_FreeSpace.ps1` 3.1.0, `Service\SelfXService.cs`, `Sources\Health_Config.xml`, `Sources\HealthStatus.ps1`, `Sources\SelfXServiceClient.ps1` 3.1.0, `Sources\SystemInfo.ps1`, `Sources\Self_X.ps1`, `Sources\Languages\*.xml` (24 files), `tools\SelfXPackage.Common.ps1`):** The row of drive `C:` gets the button **Free up space** while it is not OK. SelfX asks once and lists what is deleted; then it runs a part as the signed-in user and a part as SYSTEM, and at the end it shows the free space before and now. Part of the user (`SelfX_Device_FreeSpaceUser.ps1`, `Context : User`): own recycle bin, own TEMP, own Teams cache only while no Teams process of the session runs (Teams is never closed; when it runs, the cache is kept, exit code 2, and SelfX says so). Part as SYSTEM (`SelfX_Device_FreeSpace.ps1`, no parameters): `Dism.exe` from System32 with the fixed arguments `/Online /Cleanup-Image /StartComponentCleanup` (never `/ResetBase`), the Delivery Optimization cache (`Delete-DeliveryOptimizationCache -Force`, pinned files stay, module loaded by its full path), and entries older than `MinimumAgeDays` in `Windows\Temp` and in the Intune content (`Content\Incoming`, `Content\Staging`, `Windows\IMECache`). The Intune content is skipped while `AgentExecutor.exe` or `msiexec.exe` runs or when something there changed during the last `ImeQuietMinutes` (a heuristic, there is no query for it). Thresholds: new element `<DiskCleanup MinimumAgeDays="7" ImeQuietMinutes="60" />` in `Health_Config.xml`; an invalid value stops the SYSTEM part before anything is deleted. The old entries are deleted by the new mode `SelfXService.exe /cleanold:<WindowsTemp|ImeIncoming|ImeStaging|ImeCache> /minage:<days>`: the four folders are fixed in the program (known folders of Windows, never an argument), every entry is opened once without following a link, judged on that handle (newest of creation, write and change time) and deleted through it; a link is deleted itself and never followed; a folder is deleted only when it is old and empty afterwards; entries in use are kept and counted. `/cleanoldpath:` does the same below any local folder for the tests and is refused for SYSTEM. New in `Health_Config.xml`: attribute `UserScript` of a remediation (a first part that SelfX starts as the user; the service never runs it; returned as `UserRemediation`, same name rule, never the same file as `Script`). A repair with `UserScript` has its own confirmation and is never part of *Fix all problems*; no other action of the service starts while its part of the user runs. 6 new texts in all 24 languages. Tests: `Test-SafeDelete.ps1` (old and new files, folders and junctions, a folder that is or lies behind a junction, missing folder, wrong folder names and ages, folders swapped for junctions while the helper runs), `Test-Scripts.ps1` (both scripts with mocks; DISM arguments, helper arguments and the four folder names checked statically; thresholds with invalid values and a DTD; Intune check with processes and recent changes), `Test-HealthStatus.ps1` (`UserRemediation` from the collection, refused names, client check, the service never allows the `UserScript`, the flow in SelfX: part of the user, then the SYSTEM part, result text, failed step, no second start), `Test-Catalog.ps1` (a `UserScript` is a plain name, declares `Context : User`, is no SYSTEM script). **Deviations from the plan:** the plan names a new catalogue action; the action is a repair of the disk row instead, because one catalogue action has one script and one context and a repair can now have a part of the user (`UserScript`); there is no entry in `Issues_List.xml`. The Teams cache is not taken over from `SelfX_Teams_ResetCache.ps1` (that script closes and restarts Teams); the same folders are deleted only while Teams is closed. Deleting with an age needed a new mode of the existing delete helper in the service program instead of PowerShell, because users can write to `Windows\Temp`. Not tried on a device: DISM duration and free space gained, the Delivery Optimization cmdlet as SYSTEM in PowerShell 7, a device with an Intune installation running, a system drive other than `C:`, the window with a screen reader, closing SelfX while the part of the user runs (the SYSTEM part then does not start).

- **Connection check with a verdict and the wizard page Connection check (`Sources\SystemInfo.ps1`, `Sources\Network_Test_Config.xml`, `Sources\Self_X.ps1`, `Sources\Languages\*.xml` (24 files), `tools\Wizard\SelfXWizard.ps1` 3.1.5, `tools\Wizard\SelfXWizardGui.ps1` 1.3.0, `tools\Wizard\SelfXWizardGui.xaml`, `Wizard.en.xml`/`Wizard.de.xml`, `tools\New-SelfXPackage.ps1` 1.3.1, `tools\Test-SelfXNetworkMeasure.ps1` 3.1.0):** The optional network measurements of the System information now answer one question: is it the Wi-Fi or router, the internet, the Microsoft services or the company network? Four rows (local network, internet, Microsoft services, company network) show *reachable*, *partly reachable*, *not reachable* or *not measured* with a status symbol, and one sentence says what is probably wrong (for example *The internet works, the company network cannot be reached: check the VPN.*). The rows and the sentence are part of *Copy*, *Export*, the support report and the ticket. The System information list shows a status symbol at the end of a row for the states OK, pending and error. `Network_Test_Config.xml`: a target has the new attributes `Group` (`Local`, `Internet`, `Microsoft`, `Company`) and, for `Company`, `Kind` (`Vpn`, `Intranet`); at most 12 targets; the same strict check of host and port as before; the whole run stops after 15 seconds. The file is delivered with four Microsoft targets (`manage.microsoft.com`, `login.microsoftonline.com`, `graph.windows.net`, `enterpriseregistration.windows.net`, TCP 443; source: Microsoft Learn, *Network endpoints for Microsoft Intune*, checked on 2026-11-27); `Microsoft="False"` switches the group off. `HostNames="False"` keeps host names out of the rows (copy, export, ticket). The measurements stay off by default and users cannot add targets. The verdict is a pure function (`Get-SelfXConnectionVerdict`: states of the four groups in, verdict id out). Deviations from the plan: besides the four sentences of the plan there are the verdicts *Microsoft services not reachable*, *company network not reachable at the location* (`Kind="Intranet"`), *partly reachable* and *no data*; the *Internet reachable* test counts as one Internet target; a gateway that does not answer while the internet works is not reported as *router down* (some firewalls drop ping); targets without a group are measured and shown but do not count; the settings `Microsoft` and `HostNames` are new. Wizard: new page **Connection check** between *Ticket* and *Further settings* (answers `NetworkEnabled`, `NetworkMicrosoft`, `NetworkHostNames` and the list `NetworkTargets` with `Label`, `Host`, `Port`, `Group`, `Kind`; new check kind `netTarget`; `Set-SelfXNetworkTestConfig` writes the file and keeps its comments and the four Microsoft targets; at most 8 own targets because four of the 12 are delivered; targets without the measurement switched on are refused, not ignored; the console asks the same questions; `selfx-answers.json` and `New-SelfXPackage.ps1 -AnswerFile` know `NetworkTargets`). The sections of the console are now numbered x/9. Texts of the wizard: `de` and `en`. Tests: `Test-NetworkMeasure.ps1` (216 checks: table test of the verdict for all combinations, targets, limits, the 15-second limit), `Test-LanguageFiles.ps1` (17 new texts in all 24 languages), `tools\Test-SelfXPackageWizard.ps1` (kind `netTarget` with scheme, path, port 0 and 65536, unknown group, kind outside `Company`, 13 targets, label twice, targets with the measurement off, written file), `tools\Test-SelfXWizardGui.ps1` (page order, errors at the field, limit of 8, answers of the window identical to the console and the same `Network_Test_Config.xml`, loading targets from an answer file). Not tried on a device: the connection check behind a proxy or captive portal, with a real VPN and with a firewall that blocks ICMP, the screen reader on the new page, the status symbol on a high-contrast theme. Known and unrelated: `Test-ConfigPath.ps1` and `Test-FileManifest.ps1` fail on a German Windows because they compare English error texts; the same on `main`.

- **Configuration package: `Install.ps1 -ConfigOnly` (`Install.ps1`, `Detection.ps1`, `Uninstall.ps1` 3.1.0, `tools\SelfXPackage.Common.ps1`, `tools\Wizard\SelfXWizard.ps1` 3.1.4, `tools\Wizard\SelfXWizardGui.ps1` 1.2.0, `tools\New-SelfXPackage.ps1` 1.3.0):** The assistant can build a second, small package (`SelfX-Config-<version>.intunewin`) with only `Install.ps1`, `Detection.ps1` and `Config`. `Install.ps1 -ConfigOnly` replaces the folder `Config` of an installed SelfX: the trust mode is the one of the anchor on the device (`-TrustedSigner` and `-AllowHashMode` are refused with it), the package is checked like in a full installation (list, SHA256, no link, in the mode Signature the signatures and `Config\SelfX.Config.cat`), `MinCodeVersion` in `SelfX.Config.json` must not be newer than the installed code, and settings that only the full installation applies (shortcuts, status icon entry, icon, `Service_Privileges`) must be unchanged. The folder is copied next to the install folder (`SelfX.ConfigStage`), checked, and exchanged by renaming (`SelfX.ConfigOld`); an error puts the old folder back, an interrupted run is repaired by the next run. Service, programs and anchor are not touched and nothing is restarted; a script that holds a file of `Config` open makes the exchange wait about 20 seconds and then stop with exit code 1. `Detection.ps1` has `$PackageKind` (`Full`, `FullWithoutConfig`, `ConfigOnly`); the configuration package compares only the configuration digest. The wizard has the choice *Full / Full with separate configuration / Configuration package* (console: `-SeparateConfig`, `-ConfigPackage`), a guide for the second app (dependency on the full app, supersedence only among configuration apps) and no AppLocker or App Control files for it. `Uninstall.ps1` removes the work folders of an interrupted run. New test `Test-InstallConfigOnly.ps1` (in the Windows PowerShell 5.1 set: twelve tests), extended `Test-Detection.ps1`, `Test-SelfXPackageWizard.ps1`, `Test-SelfXWizardGui.ps1`. **Deviation from the plan, found in step 16:** with `Detection.ps1` of the full package comparing the configuration digest, the two packages would install each other again and again; the new kind `FullWithoutConfig` (option `-SeparateConfig`) prevents that. Not tried on a device: Intune with two apps and a dependency, Autopilot, a signed configuration package on a device in the mode Signature, an open SelfX window during the exchange.

- **Package wizard: page Signature and instructions as steps (`tools\Wizard\SelfXWizardGui.ps1` 1.1.0, `SelfXWizardGui.xaml` 1.1.0, `tools\Wizard\SelfXWizard.ps1` 3.1.3, `Wizard.en.xml`/`Wizard.de.xml` 1.4.0, `tools\New-SelfXPackage.ps1` 1.2.0):** The window has a page **Signature** before the summary: no certificate (trust mode Hash, with the consequences explained), a certificate from the stores (only certificates with a private key, the key usage Code Signing and a valid period are listed; expired ones are not offered) or a PFX file. The PFX password is read from a password box as a `SecureString` only, used once to open the file (in memory, not imported) and disposed; the box is emptied. It never reaches the state, the answers, a text, the window title or an error message. The page shows subject, issuer, end of validity, thumbprint and the revocation list addresses of the certificate and its chain, with a warning when there is none, no HTTP address or only internal names. A time stamp service is required unless signing without one is switched on explicitly. New: additional allowed signers for a change of the certificate (window field, console `-AdditionalSigner`, `Invoke-SelfXPackageBuild -AdditionalSigner`): they go into `-TrustedSigner` of the install command (at most 10 thumbprints in total), nothing is signed with them. The progress list shows signing and the catalog. The result page shows the instructions for Intune as steps with copy buttons (app name, package, install and uninstall command with `-TrustedSigner`, requirement script, detection script, thumbprints, output folder, ASR file list) from the new function `Get-SelfXIntuneGuideSteps`; the text file is the same lines. The instructions of the trust mode Signature name events 4006/4007, that a refused signature stops `Install.ps1` before `Install.log` is written, and a step for the change of the certificate (60 minutes until the service notices an expired certificate). New guide `docs\Certificate-Guide.md` / `docs\de\Zertifikat.md`: requirements of the certificate, request from AD CS, trust on the devices with Intune (trusted certificate profile; Trusted Publishers only when own policies require it), signing with the wizard, expiry, change and revocation. Tests: `tools\Test-SelfXWizardGui.ps1` 1.1.0 (207 checks in PowerShell 7 and Windows PowerShell 5.1: expired certificate not offered, store and PFX mode, wrong and right password, the password in no text, help text, window title, state or answer file, time stamp and additional signers, only-configure with a certificate refused, the certificate reaches the background build, instructions as steps). Tried on a PC with the test script; a signed build from the window with a real `IntuneWinAppUtil.exe`, a certificate of a real PKI, the Intune profiles and a screen reader were not tried.

- **Package wizard as a window (`tools\Start-SelfXPackageWizard.cmd` 1.0.0, `tools\Wizard\SelfXWizardGui.ps1` 1.0.0, `tools\Wizard\SelfXWizardGui.xaml`, `tools\Wizard\Wizard.en.xml`/`Wizard.de.xml` 1.3.0, `tools\Wizard\SelfXWizard.ps1` 3.1.2, `tools\New-SelfXPackage.ps1` 1.1.1, `tools\SelfXRelease.Common.ps1` 3.1.1):** The package wizard has a WPF window in the style of SelfX. Pages: language, basics, support, branding (logo with preview, company color shown at once), ticket (several organisations with one mailbox each, by group tag, OU or device class), further settings, summary with the build settings, build with a progress list and cancel, result with the files and the instructions for Intune. Every value is checked as it is typed with the checks of the console (`ConvertTo-WizardValue`, `Test-WizardUnitValues`, the logo check `Read-WizardLogo`); the error is shown at the field and the next page opens only without errors. The answers are the same object the console makes from an answer file (`Test-WizardAnswerSet`); the build is `Invoke-SelfXWizardBuild` in a background runspace (the window stays usable; cancel works until the result is written). Answers can be loaded and saved (`selfx-answers.json`, never a password or a key; unknown answers refused, at most 1 MB). Texts only from `Wizard.<culture>.xml` (de and en complete). Keyboard (Tab, Enter, access keys) and names, recommendations and errors for screen readers (UI Automation). The styles are read from `Sources\Self_X.ps1` (parsed, not run) and the colors from `Sources\Branding.ps1`; light or dark follows Windows. Signing and the network targets are not in the window yet (console). Start: `tools\Start-SelfXPackageWizard.cmd` (Windows PowerShell 5.1, `-NoProfile -STA`), it is part of the payload archive. The console version stays for automation; it now uses the shared functions `Get-WizardBuildDefaults` and `Invoke-SelfXWizardBuild` (same behavior). Fix: several Intune platform scripts are listed one per line in the instructions (they were joined into one line). Tests: new `tools\Test-SelfXWizardGui.ps1` in PowerShell 7 and Windows PowerShell 5.1 (CI: now eleven tests in the 5.1 job): text ids of every page in de and en, every console question on exactly one page, styles from Self_X.ps1 and negative cases, XAML in light and dark, checks at the field (e-mail, header injection, script address, logo, colour, units), answers of the window identical to the console and the same files of a build with `-ConfigureOnly`, answer files, cancel. Screenshots in `docs\images\selfx-wizard-*`. Tried on a PC with the test script and the window; a real `IntuneWinAppUtil.exe` run from the window, a screen reader and a run from a real release archive were not tried.

- **Package wizard builds in one run (`tools\Wizard\SelfXWizard.ps1` 3.1.1, `tools\New-SelfXPackage.ps1` 1.1.0, `tools\SelfXPackage.Common.ps1`, `tools\New-SelfXWdacPolicy.ps1` 1.2.0):** The new function `Invoke-SelfXPackageBuild` (answers, payload folder, output folder, tool path, optional certificate and time stamp server, progress callback with step id and text) does a whole package build without a question: it checks the answers, the tool and the certificate, copies the package part of the unpacked payload archive, checks the copy against `App\SelfX.Code.json`, `Bin\SelfX.Binaries.json` and `Detection.ps1`, writes the settings and the logo, optionally signs every program and script (trust mode Signature), writes `SelfX.Binaries.json`, `SelfX.Code.json`, `SelfX.Code.cat`, `SelfX.Config.json` and `Config\SelfX.Config.cat` in the order the file lists need, packs with `IntuneWinAppUtil.exe` (Microsoft signature checked), writes the detection script with the digests (signed in the mode Signature), the AppLocker rules (hash or publisher) and, with a base policy ID, the App Control (WDAC) supplemental policy, the platform scripts, the instructions and `selfx-answers.json`. Everything is built in a work folder next to the output folder and replaces the output folder in one move: an error leaves no half-finished output and an earlier result stays. An output folder with foreign content, inside the payload, or a payload with a changed, added or unknown file, an old layout or a signature already is refused. In the mode Hash `SelfX.Code.json` of the result is the one of the payload. `selfx-answers.json` never contains a password or a key (an unknown answer name stops the run). Logo: only `png`, `jpg`, `ico` (file header checked, at most 2 MB, file read once, stored as `logo.<type>`); `bmp` and `gif` are no longer accepted. New answers `AppLockerRules` and `WdacBasePolicyId`; the instructions name `-TrustedSigner`, the rule files and the way back (`-AllowHashMode`). `New-SelfXPackage.ps1` only asks and calls the function; it works on the unpacked payload archive without the .NET SDK (in the repository `-BuildBinaries` stays possible) and has the new parameters `-PayloadFolder`, `-CertificateThumbprint`, `-PfxPath` (the password is asked for as a secure string and never stored) and `-TimestampServer`. `New-SelfXWdacPolicy.ps1` reads the package layout `App`/`Config` and has `-DetectionFile`. Tests: `tools\Test-SelfXPackageWizard.ps1` (complete run with a dummy for `IntuneWinAppUtil.exe`, abort in the middle, second run, changed payload, logo check, secret in the answers; the signed run only with a trusted test root). The new wizard texts exist in `de` and `en` only (the wizard has no other language files). Tried with the test script in PowerShell 7 and Windows PowerShell 5.1 on a PC; the signed run, the AppLocker and App Control scripts in the wizard and a real `IntuneWinAppUtil.exe` run were not tried on a device.

- **Repository front page (`README.md`, `README.de.md`):** short description of SelfX, badges (CI, release, license), a step-by-step download and hash check, and the version 3.1.0. Documentation only; no change to the programs, scripts or the package. Not tried on a device.

- **Release workflow: payload archive, release notes, automatic publishing (`.github\workflows\release.yml`, `tools\SelfXRelease.Common.ps1`
  3.1.0):** A version tag now builds, besides the Intune package (`.intunewin`), its detection script, the SBOM and `SHA256SUMS.txt`, the
  **payload archive** `SelfX-Service-<version>-payload.zip`: the package folder as it is packed (`Install.ps1`, `Uninstall.ps1`,
  `Detection.ps1`, `Bin`, `App` with `SelfX.Code.json`, `Config` with the default configuration and `SelfX.Config.json`, `Service`), the
  package assistant and the scripts it calls (`tools\Wizard`, `New-SelfXPackage.ps1` and the tools below it), `LICENSE.md`, `NOTICE.md` and
  `NOTICE.en.md`. The archive is reproducible (names in ordinal order, fixed time stamp). A link, a name outside the allowed characters, a
  name twice and a missing required file stop the build. A new file of the assistant has to be added to the list in
  `SelfXRelease.Common.ps1`; the test fails until it is. `New-SelfXIntuneWin.ps1` has the new parameter `-PayloadFile` and writes the
  archive from the same package folder that goes into the `.intunewin`. The **release notes** are the section of the version in
  `CHANGELOG.en.md` (an error when it is missing, doubled or empty) plus the fixed block "Files and how to verify" (file table, a PowerShell
  command that checks `SHA256SUMS.txt`, and the command for the build provenance). `SHA256SUMS.txt` covers all release files. **The release
  is published automatically** when, in the same run, all tests of the CI workflow passed for the tagged commit (`service-ci.yml` has the
  new trigger `workflow_call`; `release.yml` calls it) and the files were checked against `SHA256SUMS.txt` (exactly the five release files,
  format and every hash). The release is created as a draft first and published after the upload; if a step fails, no release is left.
  The repository variable `RELEASE_DRAFT=true` creates a draft instead, and `RELEASE_ATTEST=false` turns off the optional build
  provenance of the payload archive (`actions/attest-build-provenance`; only that job gets the rights `id-token` and `attestations`).
  Unchanged: the workflow starts only on version tags, the token that can write releases is used in the last step of the last job only
  (it runs no code of the repository), no secret is used, all actions are pinned to a commit SHA (new: `actions/upload-artifact` 7.0.2,
  `actions/download-artifact` 8.0.2, `actions/attest-build-provenance` 4.2.2). A release that already exists is never touched. New test
  `tools\Test-SelfXRelease.ps1` (notes from the changelog with the negative cases and the check command of the notes, payload archive with
  negative cases and manipulated archives, checksum file, structure of both workflows, docs), added to both test jobs of the CI. Docs:
  docs/Installation.md, "Alternative: release on GitHub", with the steps to try the workflow without a release. The workflow itself has
  not run on GitHub yet.

- **Defender ASR rule for executable files: diagnosis and exclusion (`tools\Get-SelfXAsrEvents.ps1` 3.1.0):** If the ASR rule "Block
  executable files from running unless they meet a prevalence, age, or trusted list criterion" (`01443614-cd74-433a-b99e-2ecdc07bfc25`)
  is active, Defender can block programs of SelfX. New read-only script `Get-SelfXAsrEvents.ps1` (Windows PowerShell 5.1 and PowerShell 7)
  reads the events 1121 (block mode) and 1122 (audit mode) of `Microsoft-Windows-Windows Defender/Operational` for this one rule and shows
  time, mode, blocked file, starting process and whether the file is in the SelfX program folder (`-SelfXOnly`, `-Days`, `-MaxEvents`).
  The log, the rule and the fields are fixed in the script (no parameter names a log, a computer or a file). It changes nothing, never reads
  the fields `User` and the command lines, shows the profile folder of a user as `<user>`, reads event XML without DTD and reports events
  that it cannot assign to a rule instead of hiding them. Docs: docs/Installation.md, "Defender ASR: rule for executable files" (cause,
  how to find the file, audit mode, per-rule exclusion for at most the four SelfX files `SelfXService.exe`, `SelfX.exe`, `SelfXWinRT.dll`
  and `SelfXAudio.dll`, not the folder and not the global exclusion, programs of the release, signing is no guarantee; sources: Microsoft
  Learn "ASR rules reference" and "ASR FAQ"). The Intune instructions of the package wizard get four new texts (`guide.asr`, `guide.asr1`
  to `guide.asr3` in `Wizard.de.xml` and `Wizard.en.xml`, language files 1.1.0) and one more step before the test step. New test
  `tools\Test-SelfXAsrEvents.ps1` (synthetic events instead of the log: only this rule, Block and Audit, unreadable events, DTD and
  entity, no user name, control characters, limits, errors of the log, read-only commands only, texts of the docs and the wizard), added to
  both test jobs of the CI. The event field names come from an example event, not from the documentation of Microsoft. Not tried on a
  device on which the rule is active.
- **Publisher rules for AppLocker and App Control (`tools\New-SelfXAppLockerRules.ps1` 1.1.0, `tools\New-SelfXWdacPolicy.ps1` 1.1.0):**
  For a package signed with the certificate of the company the rules no longer change with every version. `New-SelfXAppLockerRules.ps1
  -Mode Publisher` reads the publisher from the signature of the given files (all must be signed with status `Valid` by the same
  certificate; never a parameter) and writes **one publisher rule for each rule collection** (Exe, Dll, Script): Allow, SID `S-1-1-0`,
  no product, file name or version range, fixed rule IDs, no hash rules. `New-SelfXWdacPolicy.ps1 -Level Publisher` creates the
  supplemental policy with `New-CIPolicy -Level Publisher -Fallback Hash`: a signer rule of the signing certificate instead of hash
  rules, hash rules only for files without signature, fixed policy ID as before. Before the scan it stops for a file with an invalid
  signature, for several signers (unless `-AllowMultipleSigners`) and for a package whose `Install.ps1` is not signed; after the
  scan it checks the policy (signer rules without file attribute, no hash rule next to a signed file, no denied signer) and lists the
  trusted publishers. **Default unchanged:** without `-Mode` / `-Level` both tools write hash rules as before. New files:
  `tools\SelfXPublisherRules.ps1` (functions of the publisher mode and the checks, no AppLocker or ConfigCI cmdlet),
  `tools\SelfXTestCertificate.ps1` (test helper). Docs: docs/Installation.md, "Set up once instead of per version". Tests:
  `Test-SelfXAppLockerRules.ps1` (structure, SID instead of name, no hash rule or version, changed policies as negative tests, mocked
  signature states, refusals; with a trusted test certificate also a run with signed files), `Test-WdacPolicy.ps1` (checks of signer
  policies on synthetic texts, refusal without a signed file; with a trusted test certificate also a run). Not tried on a device.
- **Trust mode in the service (`SelfXService.exe`, version 3.1.0):** Before every start of a script the service reads the trust anchor
  `HKLM\SOFTWARE\SelfX\Trust` (64-bit view). An anchor that is missing, invalid (`Mode` not `Hash` or `Signature`; in the mode signature
  `Signers` not a list of 1 to 10 SHA1 thumbprints) or not protected (owner other than SYSTEM `S-1-5-18` or Administrators
  `S-1-5-32-544`, or another identity may change the key) starts nothing: new **event 4006**. `Mode` = `Hash`: behaviour as before.
  `Mode` = `Signature` (docs/Architecture.md, "The mode signature in the service"): the lists, the catalogs and every listed file are
  opened once (readable, not writable, replaceable, renamable or deletable) and stay open until the started script has ended;
  `SelfX.Code.json` must be a member of the signed `App\SelfX.Code.cat` and `SelfX.Config.json` a member of the signed
  `Config\SelfX.Config.cat`; the file check runs on the open handles; every listed `.ps1`, `.psm1`, `.psd1` and `.dll` must carry an
  embedded signature; every settings file must be a member of `SelfX.Config.cat`. A signature counts when Windows accepts it
  (`WinVerifyTrust`) and the signer is in `Signers`. A failed signature check starts nothing, also with `Service_FileCheck` = `Audit`:
  new **event 4007**. Revocation is checked from the local cache only (no network request). Positive results are kept for 60 minutes
  per file (path, write time, size and SHA256 of the open handle; never negative results; the list of signers is applied at every
  start). No new package: the calls of Windows are made directly (class `SelfXTrust`). **`Install.ps1`:** in the mode signature the two
  catalogs are now installed next to their lists (`SelfX.Code.cat` into `App`, `Config\SelfX.Config.cat` into `Config`) and compared
  with the checked catalogs after the copy (`Copy-SelfXPayload -SignedPackage`, `Test-SelfXInstalledFiles -SignedPackage`,
  `Test-SelfXInstalledLists`); in the mode hash no catalog is installed. **Changed behaviour:** an installation without the anchor
  (installed before the anchor existed, service replaced by hand) starts no action until the package is installed again. New for the
  experiment behind the check: `tools\SelfXTrustProbe.cs` and `tools\Measure-SelfXTrustCheck.ps1` (cases and time per check on a
  device). Tests: `Test-ServicePipe.ps1` (anchor missing, invalid and unsafe; pinned files; with test certificates: wrong signer,
  changed XML, missing and unsigned catalog, unsigned and changed script, unsigned library, cache), `Test-InstallBinaries.ps1` (copy
  step with catalogs). Not part of this change: the package tools do not sign yet.
- **Trust mode signature in `Install.ps1` (`-TrustedSigner`, version 3.1.0):** `Install.ps1 -TrustedSigner <thumbprint>[,<thumbprint>]`
  installs a signed package (docs/Architecture.md, "The mode signature in `Install.ps1`"). The list holds SHA1 thumbprints of 40
  hexadecimal characters (at most 10, separated by commas; anything else stops the installation, also a given but empty parameter).
  Before anything on the device is changed, also before the data folder is prepared: no link in the package; every `.exe`, `.dll`,
  `.ps1`, `.psm1` and `.psd1` has a signature with the status `Valid` of a signer of the list; `Config\SelfX.Config.cat` is signed by
  a signer of the list, uses SHA256 and matches the folder `Config`; the new catalog `SelfX.Code.cat` at the top of the package is
  signed by a signer of the list and matches everything outside `Config` (so `SelfX.Code.json`, the language files, the images,
  `SelfX.Binaries.json` and the sources are covered too). The checks of `SelfX.Binaries.json`, `SelfX.Code.json` and
  `SelfX.Config.json` stay; after the copy the installed lists must be the lists that the catalogs covered. The catalogs are checked
  in the package and are not installed. New functions: `ConvertTo-SelfXTrustedSignerList`, `Resolve-SelfXTrustMode`,
  `Test-SelfXFileSignature`, `Test-SelfXPackageCatalog`, `Test-SelfXPackageSignatures`, `Test-SelfXInstalledLists`,
  `Get-SelfXTrustAnchor`, `Set-SelfXTrustAnchor`, `Test-SelfXTrustAnchorState`. **Trust anchor:** in both modes `Install.ps1` writes
  `HKLM\SOFTWARE\SelfX\Trust` (`Mode` = `Hash` or `Signature`; `Signers` as `REG_MULTI_SZ` in the mode signature) before the service is
  registered: owner Administrators (`S-1-5-32-544`), rights not inherited, SYSTEM (`S-1-5-18`) and Administrators full control, users
  (`S-1-5-32-545`) read; the anchor is read back and its rights are checked. **Downgrade:** a device whose anchor says `Signature` (or
  cannot be understood) is installed without `-TrustedSigner` only with the new switch `-AllowHashMode`; both together are an error.
  A signed package without `-TrustedSigner` is refused with a hint. Without `-TrustedSigner` the mode hash works as before.
  **Changed behaviour:** the parameters of `Install.ps1` are bound by name only (`-InstallFolder <path>` instead of a path without a
  name). `Detection.ps1` requires the anchor (`Test-SelfXTrustAnchor`, 64-bit view; the mode is logged and not judged), so an
  installation of an earlier build is installed again once. `Uninstall.ps1` removes the anchor (`HKLM\SOFTWARE\SelfX\Support` stays).
  Revocation: the check of Windows is used; new `tools\Measure-SelfXRevocationDelay.ps1` measures on a device how long
  `Get-AuthenticodeSignature` takes when the revocation list address of the certificate cannot be reached. Tests:
  `Test-InstallBinaries.ps1` (list of signers, mode and downgrade, all refusals of signatures and catalogs with replaced cmdlets, copy
  step, anchor in a test key below HKCU, the same answers as `tools\SelfXSigning.ps1`; with a trusted test root also real signatures and
  catalogs), `Test-Detection.ps1` (anchor). Not part of this change: the package tools do not sign yet, and the service does not read
  the anchor yet.
- **Fix (tests): `tools\Test-SelfXSigning.ps1` no longer stops the CI jobs "Signing library".** Part 2 added its test certificates to
  `Cert:\CurrentUser\Root`; Windows shows a question there, and a process without a desktop waits for it until the job is cancelled.
  With administrator rights the test now uses `Cert:\LocalMachine\Root` (no question); on GitHub Actions part 2 runs only with
  administrator rights. Two expectations follow what Windows reports: a script with text added after the signature block has the status
  `NotSigned`, a script changed before the block `HashMismatch`. `tools\SelfXSigning.ps1` is unchanged.
- **Signing library (`tools\SelfXSigning.ps1`, tools only, not part of the package):** Functions for the trust mode "signature"
  (docs/Architecture.md), working in Windows PowerShell 5.1 and PowerShell 7: `Get-SelfXSigningCertificate` (certificates of
  `Cert:\CurrentUser\My` and `Cert:\LocalMachine\My` with private key, key usage Code Signing and a valid period, or a PFX file with a
  `SecureString` password that is not imported into a store), `Set-SelfXCodeSignature` (SHA256, chain without the root, optional
  http/https time stamp server; all input is checked before the first file is signed, every file is read back), `New-SelfXSignedCatalog`
  (`New-FileCatalog` version 2 and signature; no unsigned catalog is left when signing fails), `Test-SelfXSignature` (status `Valid` and
  the signer in the list of allowed thumbprints; returns the reason) and `Test-SelfXSignedCatalog` (signer and folder contents; names changed,
  missing and extra files). The password is never converted to plain text and never appears in an output, log or message. Nothing uses the
  library yet. Tests: new `tools\Test-SelfXSigning.ps1` (part 1 on every system, part 2 with self-signed test certificates in
  `Cert:\CurrentUser`), new CI job "Signing library" (Windows PowerShell 5.1 and PowerShell 7).
- **Text overrides (`Config\Texts\<culture>.xml`, version 3.1.0):** A company can replace single texts without changing a
  bundled language file. The optional file has the format of the language files and holds only the texts to change (`UI`,
  `SystemInfo`, `Catalog`); it is configuration (class Config, listed in `SelfX.Config.json`) and is installed into
  `%ProgramFiles%\SelfX\Config\Texts`. `Localization.ps1` loads the bundled file first and then the override of the culture of
  the loaded file (`de-CH` uses `Texts\de.xml`): `Initialize-SelfXLanguage -TextOverrideFolder`, new functions
  `Read-SelfXTextOverride`, `Test-SelfXOverrideText`, `Set-SelfXTextOverride`, `Import-SelfXTextOverride`,
  `Get-SelfXTextEntries`, `Get-SelfXTextReference`; the folder comes from `Get-SelfXTextOverrideFolder` (`SelfXPaths.ps1`).
  A text is used only when its id is known in a bundled file, it is given once, is not empty, not longer than 1500 characters,
  has no markup (no `<`, no entity such as `&amp;`), no control characters and the same placeholders as the bundled text; the
  Copilot prompts cannot be overridden. Unknown ids and refused texts are ignored and written to the log of the user (id and
  reason, never a text). The file is read once as bytes, must not be a link, larger than 256 KB or have a DTD; the root
  attributes of an override are not used, so it cannot add or replace a language. Placement rule (`Install.ps1`,
  `tools\SelfXPackage.Common.ps1`, `SelfXService.cs`, `SelfXPaths.ps1`): `Texts/<culture>.xml` is accepted in
  `SelfX.Config.json`; nothing below `Texts` may be in `SelfX.Code.json`. `Test-LanguageFiles.ps1` also checks the text
  overrides (`-TextsFolder`) with the same functions. Docs: `docs/Configuration.md` (section "Change single texts"),
  `docs/Architecture.md` (DE and EN). Tests: new `Test-TextOverrides.ps1`; extended `Test-FileManifest.ps1`,
  `Test-ConfigPath.ps1`, `Test-ServicePipe.ps1`.
- **Package and device, code and configuration in two folders (version 3.1.0):** The package has the folders `App` (code)
  and `Config` (configuration) instead of `Sources`; `tools\New-SelfXIntuneWin.ps1` sorts the files of `Sources` by their file
  class (`ConvertTo-SelfXPackageLayout` in `tools\SelfXPackage.Common.ps1`; a file without a class stops the build). On the
  device the programs, libraries, scripts, language files and default images of the project, `Uninstall.ps1` and
  `SelfX.Code.json` are in `%ProgramFiles%\SelfX\App`; the settings files, `Branding`, own scripts and language files and
  `SelfX.Config.json` are in `%ProgramFiles%\SelfX\Config`; the rights are unchanged (users `S-1-5-32-545` read and execute
  only). One path resolver: `Sources\SelfXPaths.ps1` (`Get-SelfXConfigPath`, `Get-SelfXImagePath`, `Resolve-SelfXScriptPath`,
  Windows PowerShell 5.1 and PowerShell 7) and in the service `GetConfigRoot`, `GetConfigFilePath`, `ResolveScriptPath`; the
  configuration folder is `Config` next to a code folder named `App`, otherwise the code folder itself. The service loads the
  catalog, `Health_Config.xml` and `Tool_Config.xml` only from `Config` and scripts of the project only from `App`; an own
  script below `Config` starts only when the catalog or `Health_Config.xml` names it and `SelfX.Config.json` lists it with its
  current SHA256, also with `Service_FileCheck` = `Audit`; a script of the project with the same name wins (likewise in
  `Self_X.ps1` for user actions and in `HealthStatus.ps1` for own check scripts). The file check of the service and of
  `Install.ps1` compares every folder only with its own list and allows nothing next to `App` and `Config` (empty folders that
  are still in use excepted). Images: `Branding\...` in `Config`, other relative values in `App`. Own language files in
  `Config\Languages` are offered but cannot replace a bundled language. Migration: `Install.ps1` 3.1.0 removes an
  installation in the old layout completely before the copy (new functions `Clear-SelfXInstallFolder`,
  `Copy-SelfXPayload`) and refuses a package in the old layout; `Uninstall.ps1` 3.1.0 removes both layouts and reads
  `Tool_Config.xml` without DTD; `Detection.ps1` 3.1.0 detects only the new layout. **Note:** own scripts that look for
  `SelfXLog.ps1` or `SelfXOffice.ps1` through `Split-Path -Parent $PSScriptRoot` have to be adapted (`docs/Configuration.md`,
  section "Own scripts of the company"). `Version.txt` and `Detection.ps1` are set to 3.1.0. Tests: new
  `Test-ConfigPath.ps1`; extended `Test-FileManifest.ps1`, `Test-InstallBinaries.ps1` (update 3.0.2 -> 3.1.0, mixed state,
  locked file), `Test-Uninstall.ps1`, `Test-Detection.ps1`, `Test-ServicePipe.ps1`, `Test-Compat51.ps1`.
- **Package, the version is a property of the code (`Version.txt`, `SelfX.Code.json`):** The version is no longer stored in the settings file
  `Tool_Config.xml`. The new file `SelfX Service\Version.txt` (one line) is the only source; the build writes it into `ToolVersion` of
  `SelfX.Code.json`. A new version therefore changes no configuration file, and a changed configuration (for example a logo) does not
  change the version. `SelfX.Config.json` has `ConfigRevision` (UTC time of the packaging run, not part of the digest) instead of
  `BuiltUtc`. Readers adapted: `Detection.ps1` 3.0.4 compares `$ExpectedVersion` with `ToolVersion` of the installed `SelfX.Code.json`
  (new function `Test-SelfXInstalledPackage`: code version, code digest and configuration digest are reported separately);
  `Install.ps1` 2.9.1 reads the version from the checked `SelfX.Code.json` and refuses a package without it before anything is changed
  (a package without the two lists was installed with a warning before); `Self_X.ps1` 2.8.27 shows the version from `SelfX.Code.json`
  (`?` when it cannot be read); `release.yml` compares the tag with `Version.txt`; `New-SelfXIntuneWin.ps1` 1.10.0,
  `New-SelfXPackage.ps1` 1.0.1, `Build-SelfXBinaries.ps1` 2.8.21 and `New-SelfXWdacPolicy.ps1` 1.0.1 read `Version.txt`
  (`Get-SelfXVersionFromFile` in `tools\SelfXPackage.Common.ps1` accepts one line of at most 30 letters, digits, `.` and `-`).
  `Version.txt` is not part of the package. An old `Tool_Version` element in a company's `Tool_Config.xml` is ignored. No text of the
  user interface changed. Tests: version change leaves all configuration files unchanged, configuration change leaves the version and the
  code list unchanged, detection of code version, code files and configuration separately, negative tests for `Version.txt`,
  `ConfigRevision`, `ToolVersion` and a damaged code list, and a scan that no script, tool or workflow reads `Tool_Version`.
- **Package, two file lists (`SelfX.Code.json`, `SelfX.Config.json`):** `SelfX.Files.json` is replaced by two lists. `SelfX.Code.json`
  holds the programs, libraries and the scripts, language files and images of the project; `SelfX.Config.json` holds the settings
  files, everything below `Branding` and own scripts and language files. Every file is in exactly one list, an unknown file stops the
  build, and a file in both lists or in the wrong list is refused. The code list has no build time, so a changed company logo changes
  only `SelfX.Config.json` and the configuration digest. New `tools\SelfXPackage.Common.ps1` (file classes, both lists, digest,
  `Detection.ps1` writer). `Install.ps1` 2.9.0 checks the package and the installed folder against both lists; `Detection.ps1` 3.0.3
  checks two digests; the service (2.9.0) reads both lists with the same rules (event 4005 unchanged, `Service_FileCheck` unchanged);
  `SelfXWinRT.ps1` and `SelfXAudio.ps1` read the hashes of their libraries from `SelfX.Code.json`. `Tool_Version` is unchanged.
  Tests adapted and extended (logo test, class and placement tests, negative tests).
- **Documentation, architecture:** New `docs/Architecture.md` (German: `docs/de/Architecture.md`): the three file classes (code,
  configuration, company code), the assignment of every file of the package SelfX Service, the planned lists `SelfX.Code.json` and
  `SelfX.Config.json`, the trust modes hash and signature, the trust anchor and the limit of the checks against a local
  administrator. It also names the files whose class is still open. Linked from the README and the installation guide. No code
  change.
- **Security, report file (`Collect-DeviceLogs.ps1` 1.3.6):** A report file is only overwritten when it existed and was checked as
  trusted. After a planted file was removed the report is always created new (`CreateNew`), so a file that a user creates in the gap
  is never written. A default report (`-Protect`) is opened without sharing: until the access rights are set nobody can hold a read
  handle. `-UserView` accepts only the SID of a user account.
- **System information export (`SystemInfo.ps1` 2.8.26):** The file name from the save dialog is used literally (`-LiteralPath`).
  A name with `[` `]` failed or could match other files.

## 3.0.2 - 2026-11-24 (SelfX Service)

- **Security, report reader:** `SelfX_Device_CollectLogs.ps1` (2.8.21) releases the report only to the account of the requesting
  user. Only user SIDs are allowed as reader (`S-1-5-21-...` local/domain, `S-1-12-1-...` Entra ID). Groups and well-known SIDs such
  as Everyone (`S-1-1-0`), Authenticated Users (`S-1-5-11`) or Users (`S-1-5-32-545`) are refused (exit code 2, no report), and
  again in `Set-ReportAcl` as a second safeguard.
- **Security, PowerShell 7 check at installation:** `Install.ps1` (2.8.6) checks pwsh.exe like the service does before every start:
  only SYSTEM, Administrators and TrustedInstaller may change or take over pwsh.exe, its folder and the folders above it. The rights
  are read as SIDs (an unknown SID is no longer skipped); when they cannot be read, the installation stops. Tests added in
  `Test-DeviceLogs.ps1` and `Test-InstallBinaries.ps1`.

## 3.0.1 - 2026-11-24 (SelfX Service)

- **AppLocker hash rules:** `tools\Build-SelfXBinaries.ps1` (2.8.20) writes `build\SelfX.AppLocker.xml` again on German and other localized
  Windows versions: the rules apply to the SID `S-1-1-0` instead of the name "Everyone", which cannot be resolved there. In
  PowerShell 7 the rules are created through Windows PowerShell 5.1 (new `tools\New-SelfXAppLockerRules.ps1`), because the AppLocker
  cmdlets do not accept a list of paths in PowerShell 7. The script checks that every program has one Allow rule.
- **Offline build:** building the programs needs no internet any more. `NuGet.config` in the repository root allows only the
  folder `offline-feed` (NuGet packages with the manifest `SelfX.OfflineFeed.json`, SHA512 of each file).
  `tools\Build-SelfXBinaries.ps1` (2.8.19) checks the folder against the manifest and against the SDK version of the export before
  every build, restores into a fresh package cache inside the repository and stops when a package is missing, changed or
  additional. The new `tools\Export-SelfXOfflineFeed.ps1` is the only script that talks to nuget.org: it fills the folder, runs the
  NuGet vulnerability audit (the audit is off for the offline build) and proves the folder with an offline restore. The runtime
  packs of WindowsDesktop and AspNetCore are no longer requested (`DisableTransitiveFrameworkReferenceDownloads`). New test
  `tools\Test-SelfXOfflineFeed.ps1`. Before the first offline build run the export once (see the installation guide, "Offline build").

## 3.0.0 - 2026-11-23 (SelfX Service)

Version 3.0.0 combines all changes since the upstream state 2.6.9 was taken over.
The most important points:

- **New design:** calmer window, new app icon, three-step hint and status marks with a
  symbol (see below).
- **New technology:** the service and the starter are .NET 10 programs that are built once;
  all scripts run in PowerShell 7.6. The minimum version is Windows 11 25H2.
- **More security:** before every script start the service checks the installed files
  against a file list, runs with limited rights and protects its pipe and its data folders.
  SelfX optionally supports App Control for Business (WDAC).
- **New actions, ticket by email, Copilot Chat and Remote Help.**
- **SelfX Service only:** SelfX Standard and SelfX Admin are removed.

### Important when updating from 2.6.9

1. Deploy **PowerShell 7 (7.6 or newer)** as a Win32 app and set the requirement rule for
   Windows 11 25H2 (build 26200). Without PowerShell 7 SelfX is still installed (Autopilot
   is not affected) but starts no scripts.
2. Build the package again: `tools\Build-SelfXBinaries.ps1` (.NET SDK 10 on the build
   computer), then `tools\New-SelfXIntuneWin.ps1`. The devices no longer compile anything.
3. Upload the **new** `.intunewin` file and the `Detection.ps1` that the packaging step
   creates to Intune (folder `build`).
4. Replace existing **AppLocker rules**: the new programs have new hashes.
5. The default language of the interface is now German (`Tool_Language` = `de`).

Details: [Installation guide](docs/Installation.md).

### New design

- Calmer look of the window: larger rounded corners and spacing, softer base colors,
  larger buttons and cards, rounded content area.
- Three-step hint "Select problem – Confirm – Done" below the title.
- Status marks with a symbol next to the text, not only with color.
- New app icon (wrench on a rounded blue square) for the window, taskbar, shortcuts and
  status icon, in all sizes from 16 to 256 pixels.
- On Windows 11 the status icon stays permanently next to the clock (`Tray_Pin_Icon`,
  default `True`; users can switch it off with `HKCU\Software\SelfX\TrayPin = 0`).
- New screenshots in the documentation.

### New features for users

- New actions:
  - "Microsoft Edge: Clear cache" (cookies, history and passwords stay).
  - "Outlook is not responding" (ends and restarts classic Outlook).
  - "The time on your device is wrong" (time service, through the SelfX service).
  - "Office asks for activation or reports an unlicensed product" (resets only the
    license token).
  - "Outlook suggests wrong or outdated email addresses".
  - "No sound on this PC" (makes the default playback device audible again).
  - "Scan this PC for viruses" (Microsoft Defender quick scan, through the SelfX service).
  - "Update the company settings (Group Policy)" (only on devices joined to a domain;
    new optional catalog field `Requires`).
- New action type "Link": after the confirmation it opens an https address from
  `Tool_Config.xml` (for example reset password or security info).
- System information: warning "Restart recommended" after 7 days of uptime, new rows for
  proxy and network drives, more precise status line "Restart pending".
- Optional network measurements (off by default, `Network_Test_Config.xml`): response time
  to the gateway and DNS and TCP duration to up to 5 targets.
- **Ticket by email** (off by default, `Ticket_Enabled`): the user describes the problem,
  SelfX adds the device information and opens the email (classic or new Outlook, default mail
  program). The user sends it. The responsible IT unit is determined by `Ticket_Config.xml`
  (group tag, OU, device category) or registry values per device.
- **Copilot Chat** (off by default, `Copilot_Enabled`): SelfX builds a text for Microsoft 365
  Copilot Chat from a few checked device values (names and addresses as placeholders), shows
  a preview and opens `https://copilot.cloud.microsoft`. The text does not enter the
  clipboard history; optionally the clipboard is cleared after some time
  (`Copilot_Clear_Clipboard`).
- **Remote Help:** if Microsoft Remote Help is installed and validly signed, the remote
  support tile starts only Remote Help and Quick Assist is not offered. Without Remote Help
  it stays Quick Assist.
- German is the base language of the interface (before: the Windows display language);
  24 languages, missing texts appear in English. Missing translations were added.
- **New button "Company wiki" (optional):** `Wiki_Enabled`, `Wiki_Url` (`https://` only) and `Wiki_Name` (up to 40 characters) in `Tool_Config.xml` show a button in the navigation, styled like the Copilot button, that opens the wiki address in the web browser. Off by default; an invalid address hides the button and writes a warning to the log. Runs in the user context. Texts in all 24 languages, new questions in the package wizard, tests in `Test-SupportLinks.ps1` and `Test-SelfXPackageWizard.ps1`.
- **New action "Excel opens every file in the same window"** (category Office, user context):
  starts a second, independent Excel instance (`excel.exe /x`), for example to compare two
  workbooks on two screens. Nothing is closed or changed; the program path comes from
  `SelfXOffice.ps1` (below Program Files, no link) and the only argument is the fixed switch
  `/x`. Texts in all 24 languages, tests in `Test-Scripts.ps1`.
- **New action "A program window is outside the screen"** (category Device, user context):
  moves windows of the own user whose title bar cannot be reached on any screen (for example
  after a monitor was disconnected) to the primary screen. Nothing is closed, saved or
  changed in the settings; windows are moved through Microsoft UI Automation (no compiled
  code) and window titles are not written to the log. Programs with higher rights are
  skipped. New helper `SelfXWindows.ps1`, test: `Test-WindowHelper.ps1`.
- **New action "Citrix Workspace does not respond or does not show your apps"** (category
  Citrix, user context): closes the Citrix Workspace app processes of the own user account and
  starts the app again. Application and desktop sessions that are already open are not ended;
  the saved sign-in and the settings stay unchanged. The program path must be below Program
  Files (no link); there is no user input. Only the current Citrix Workspace app is
  supported, not the Receiver.

### New features for administrators

- **File list `SelfX.Files.json`:** the packaging step writes the SHA256 of every installed
  file into the package. `Install.ps1` checks it before and after copying, the service before
  **every** script start (setting `Service_FileCheck` = `Enforce` or `Audit`).
  `Detection.ps1` also checks the file list, so an update is found even without a new version.
- **Limited service rights:** `Service_Privileges` = `Restricted` (default) limits the token
  of the service to nine required rights; `SeTcb`, `SeDebug` and other dangerous rights
  are no longer held by the service.
- **Optional App Control for Business (WDAC):** `tools\New-SelfXWdacPolicy.ps1` creates a
  supplemental policy with hash rules from the package (audit or enforce).
- **Prebuilt programs:** `SelfXService.exe`, `SelfX.exe` and `SelfXWinRT.dll` are built once
  on a build computer; `SelfX.Binaries.json` holds the hashes, and
  `tools\Build-SelfXBinaries.ps1` can write AppLocker hash rules.
- **Release workflow** (`.github/workflows/release.yml`): runs only on a tag, checks the tag
  against `Tool_Version`, builds programs, `.intunewin`, SBOM (CycloneDX) and
  `SHA256SUMS.txt` and creates a release draft.
- **Windows event log:** the service writes events 4001 to 4005 and 4099 (source
  `SelfXService`).
- **Several users on one device:** `OtherSessions` = `Block` blocks disturbing actions
  (restart, updates, disk check, network and Intune restart) while another user is signed in;
  administrators with elevated rights may still start them.
- **Device reports:** normal users see only their own data, an administrator with elevated
  rights sees the full report. New: summary of the event logs. The service deletes reports
  automatically after 7 days.
- Prerequisite check during installation: Windows 11 25H2, safe folder rights for
  PowerShell 7 (otherwise abort before any change).
- **Package wizard (guided configuration):** `tools\New-SelfXPackage.ps1` asks questions with a
  recommendation (support, branding, ticket and organisations by OU, group tag and device class,
  Copilot Chat, behavior), writes the answers into a copy of the package, builds the Intune package,
  creates the platform scripts for the ticket routing and short Intune instructions. German and
  English; more languages via `tools\Wizard\Wizard.<culture>.xml`. See
  [Package wizard](docs/Guided-Setup.md). `New-SelfXIntuneWin.ps1` 1.8.0 has the new parameter
  `-SourceFolder`. Test: `tools\Test-SelfXPackageWizard.ps1` (runs in CI).
- **Citrix Workspace in the system information:** when the Citrix Workspace app is installed,
  SelfX shows the row "Citrix Workspace" with the version under "Device". The row is also part of
  the device information of the support ticket. The reachability of StoreFront or the Gateway can be
  measured with a target in `Network_Test_Config.xml` (example in the file). Test:
  `Test-CitrixInfo.ps1`.

### Security

Findings of a security review (OWASP, Microsoft, BSI), all fixed:

- **Service and pipe:** fixed time limits for reading and writing, connection limits (64 in
  total, 8 per user), check of the pipe server by the window, `FirstPipeInstance` against
  pipes created in advance, cleaned and throttled service log, job object that ends all child
  processes when the service stops, no unhandled exceptions any more.
- **Files and folders:** `%ProgramData%\SelfX` is protected against links and foreign
  entries during installation, reports are created safely (temp folder, hard links),
  deleting as SYSTEM does not follow junctions, compiler TEMP folder protected.
- **Input:** all XML files are read without DTD; links from `Tool_Config.xml` must be
  https (or `mailto:` with one address); CSV export protects against formulas;
  Teams installer logs are read only in a safe way.
- **Flow:** actions run only through the whitelist of the catalog, parameters never come from the user.
- **Supply chain:** pinned GitHub Actions, Dependabot, CodeQL, PSScriptAnalyzer,
  SBOM, CODEOWNERS, `SECURITY.md`.

### Intune, package and tools

- Programs: .NET 10 (LTS), self-contained, one file each; no runtime on the device.
- Scripts run with `%ProgramFiles%\PowerShell\7\pwsh.exe` (fixed path); `Install.ps1`,
  `Uninstall.ps1` and `Detection.ps1` stay in Windows PowerShell 5.1 so that Autopilot
  and Intune can start them.
- Windows modules replaced by CIM: BitLocker, TPM, Secure Boot, Defender, network adapters,
  DNS cache and disk repair. This also fixes that data drives were never checked for BitLocker.
- "Install updates" uses only the Windows Update orchestrator (`SelfXWinRT.dll`).
- Automatic tests (`Test-*.ps1`) run in PowerShell 7 for every pull request; the installation
  scripts are also checked in Windows PowerShell 5.1.
- Cleaned up: Office code that existed several times merged in `SelfXOffice.ps1`.

### Removed

- **SelfX Standard** and **SelfX Admin**: the fork develops only SelfX Service.
  Use the upstream projects if you need them.
- Support for Windows versions older than 11 25H2 and the Windows Update Agent.

## Based on upstream 2.6.9

Windows updates through the Windows Update orchestrator, the detection of a pending
restart and all other changes up to SelfX Service 2.6.9 come from
[wbaeck/SelfX](https://github.com/wbaeck/SelfX).
