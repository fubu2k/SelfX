# Changelog

**English** | [Deutsch](CHANGELOG.md)

This log describes what changed in this fork ([fubu2k/SelfX](https://github.com/fubu2k/SelfX))
compared with its upstream [wbaeck/SelfX](https://github.com/wbaeck/SelfX) at SelfX Service
2.6.9. Everything up to version 2.6.9 comes from the upstream and is not listed here as new.
The history of each file is in its header.

The package version is `Tool_Version` in `SelfX Service\Sources\Tool_Config.xml`.
`Detection.ps1` must contain the same value, otherwise Intune does not detect the update
(the packaging script checks this). A release gets the tag `v<version>` (for example
`v3.0.0`); the release workflow checks that the tag and `Tool_Version` match.

## Unreleased

- **Package wizard (guided configuration):** `tools\New-SelfXPackage.ps1` asks questions with a
  recommendation (support, branding, ticket and organisations by OU, group tag and device class,
  Copilot Chat, behavior), writes the answers into a copy of the package, builds the Intune package,
  creates the platform scripts for the ticket routing and short Intune instructions. German and
  English; more languages via `tools\Wizard\Wizard.<culture>.xml`. See
  [Package wizard](docs/en/Guided-Setup.md). `New-SelfXIntuneWin.ps1` 1.8.0 has the new parameter
  `-SourceFolder`. Test: `tools\Test-SelfXPackageWizard.ps1` (runs in CI).
- **New action "A program window is outside the screen"** (category Device, user context):
  moves windows of the own user whose title bar cannot be reached on any screen (for example
  after a monitor was disconnected) to the primary screen. Nothing is closed, saved or
  changed in the settings; windows are moved through Microsoft UI Automation (no compiled
  code) and window titles are not written to the log. Programs with higher rights are
  skipped. New helper `SelfXWindows.ps1`, test: `Test-WindowHelper.ps1`.

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

Details: [Installation guide](docs/en/Installation.md).

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
