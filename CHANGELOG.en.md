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
