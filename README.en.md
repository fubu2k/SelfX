# SelfX (Self fix)

**English** | [Deutsch](README.md)

SelfX is a self-service troubleshooting tool for Windows, written in PowerShell
and WPF. Users without technical knowledge can see the health of their device
and fix common problems with Teams, Office, OneDrive, Outlook, Intune, Windows
Update and the network on their own, before they call the support. They can also
send the logs of their device to the support in a few clicks.

**SelfX Service** is installed machine-wide and works fully offline. It runs
actions either as the signed-in user or, through the local **SelfXService**
Windows service, with SYSTEM rights. No network access, SCCM or Intune is
needed to fix a problem. See [Features](#features-of-selfx-service).

SelfX has no central backend, push messaging or centralized task reporting.

This repository ([fubu2k/SelfX](https://github.com/fubu2k/SelfX)) is a fork of
[wbaeck/SelfX](https://github.com/wbaeck/SelfX) and is developed **only for
SelfX Service**. SelfX Standard (per user) and SelfX Admin of the upstream
projects are not part of this fork; use the upstream repositories if you need
them. The work in this fork concentrates on the security, the tests and the
deployment of SelfX Service: see
[Security hardening in this fork](#security-hardening-in-this-fork) and the
[Changelog](CHANGELOG.en.md). Current version: **2.8.0**.

## Screenshots

The screenshots were taken with SelfX Service 2.8 and show sample data (fictional device
*Contoso*) and the placeholder logo of the delivered configuration.

**Troubleshooting:** actions in plain language, with search, categories and an
explanation for each action.

![Troubleshooting page, dark appearance](docs/images/selfx-troubleshooting-dark.png)

**Device status:** the results of the background checks, problems first, with
a **Fix** button where a repair is available.

![Device status page with problems and warnings](docs/images/selfx-device-status-dark.png)

**System information:** everything the support team asks for, in one place,
ready to copy or export.

![System information page](docs/images/selfx-system-information-dark.png)

**Light appearance:** *Automatic* follows the dark or light mode of Windows;
each user can also choose *Dark* or *Light*.

![Troubleshooting page, light appearance](docs/images/selfx-troubleshooting-light.png)

**Help in the navigation:** with `Ticket_Enabled` the button *Open a ticket with IT support* appears, with `Copilot_Enabled` also *Ask Copilot Chat* (both off by default).

![Navigation with ticket and Copilot Chat buttons](docs/images/selfx-ticket-copilot-light.png)

**Adaptive window:** in a narrow window the navigation shows only icons and the
cards rearrange.

![Device status in a narrow window](docs/images/selfx-device-status-narrow.png)

**Status icon next to the clock:** a colored dot shows the device status; the
menu opens SelfX, checks the status or sends the logs.

![Status icon states and menu](docs/images/selfx-tray-icon.png)

| Help and support contacts | Settings | Confirmation before an action |
|---|---|---|
| ![Help dialog](docs/images/selfx-help.png) | ![Settings dialog](docs/images/selfx-settings.png) | ![Confirmation dialog](docs/images/selfx-confirm.png) |

## Features of SelfX Service

### For the user

- **Troubleshooting page**
  - One card per action with a short description in plain language.
  - Search field, category buttons (Device, Intune, Office, OneDrive, Outlook,
    Teams, Browser) and a switch between the *simplified* view (a few general
    actions) and the *detailed* view (one action per symptom, for example
    *Teams is stuck on "Loading Microsoft Teams"*).
  - An info button explains what the action does. Every action asks for
    confirmation and tells the user what will happen (for example "Teams will
    close").
  - While an action runs, its button shows a rotating icon and *Running…*. The
    result appears in the message bar. A shield marks actions that run with
    administrator rights through the service.
- **Included actions**
  - Teams: clear the cache and restart.
  - Word and Excel: close the application and start it again.
  - OneDrive: start, restart or reset the client; check the disk for locked
    files (chkdsk).
  - Outlook: restore the *Teams meeting* button.
  - Microsoft Store: reset the Store.
  - Network: clear the DNS cache; restart the network adapters.
  - Device: empty the recycle bin and the temporary files when the device is
    slow.
  - Browsers: clear the cache of Chrome and Firefox.
  - Intune: restart the Intune service and force a synchronization.
  - Support: send the device logs to the support.
  - Administrators can add their own actions in an XML file.
- **Device status page**
  - One card per check with the state OK (green), Pending (yellow warning),
    Error (red) or Unknown (gray), problems first. A counter on the navigation
    shows the number of open points.
  - **Fix** repairs a problem after confirmation:
    - update the Defender signatures;
    - install pending Windows updates and Microsoft Store app updates;
    - try again to install company apps that failed;
    - restart the device, with its own warning.
  - **Fix all problems** runs all repairs at once, except the restart. The arrow
    button checks a single status again.
- **System information page**
  - Device, Windows, user and Intune/Entra ID management, and network details
    (LAN, Wi-Fi, VPN, internet, IP, DNS, MAC).
  - Double-click a line to copy it. Copy all, or export as TXT, HTML, CSV or JSON.
  - Shown immediately from the last collection and refreshed in the background.
- **Send logs to support**
  - The service collects all logs needed to analyze a device problem (event
    logs, Intune / Autopilot / ESP, apps, updates, SelfX logs) as SYSTEM.
  - SelfX then opens a new e-mail to the support with the report attached
    (`.zip`). The user describes the problem and sends it; nothing is sent
    automatically.
- **Help dialog (?)**
  - Support hours, phone number, e-mail, Teams chat and website / ticket
    system, each with a button to start it.
- **Settings (gear)**
  - Language: 24 languages; German is the default, *Automatic* uses the
    Windows display language (German if it is not available). Texts that are
    missing in a language are shown in English.
  - Appearance: *Automatic*, *Dark* or *Light*.
  - Status icon on or off; Windows notifications about problems on or off.
  - All choices are stored per user.
- **Status icon next to the clock**
  - Green, yellow, red or gray dot.
  - Tooltip with the number of problems and warnings.
  - One Windows notification when a new problem is found, for example low disk
    space.
  - Menu: open SelfX, show the device status, check now, send logs, switch
    notifications, hide the icon.
- **Modern, adaptive window**
  - Resizable, with a compact navigation in narrow windows.
  - Remembers size and position.
  - Right-to-left layout for Arabic, Persian and Urdu.
  - Own taskbar icon.
  - Only one window per user: a second start brings the open window to the front.

### For IT administrators

- **Local Windows service, fully offline.**
  - `SelfXService` runs as SYSTEM.
  - It only runs the scripts listed as system actions in the catalogue
    (whitelist); the user cannot pass a path or code to the service.
  - No central server, no cloud credentials on the client.
- **Background health checks**
  - Default every 15 minutes (5–1440).
  - Paused on battery and postponed while the processor is busy; the first
    check is delayed after start-up.
  - The result is cached, so SelfX and the status icon show it immediately.
- **Checks**
  - Intune Management Extension service.
  - Microsoft Defender (protection on, signatures up to date).
  - Local compliance criteria (BitLocker, Secure Boot, TPM, firewall, Defender,
    OS version).
  - Company apps from the local IME cache.
  - Disk capacity (default: error at 90% used or below 20 GB free).
  - BitLocker on all fixed volumes.
  - Pending restart.
  - Windows updates to install (local cache, no online scan).
  - Additional services with their expected state.
  - Your own read-only check scripts.
- **Configurable repairs:** map any check to a repair script and choose whether
  the **Fix** button is shown always or only when the check is not OK.
- **Logging**
  - All scripts log to `%ProgramData%\SelfX\Logs`; each user's logs go to their
    own, protected folder.
  - Housekeeping deletes logs older than 90 days (configurable).
- **Branding**
  - Company logo, icon, accent color, title bar, button and info colors.
  - Tool name, shortcuts and support contacts.
  - The delivered configuration contains placeholders (`Branding\company_logo.png`,
    `example.com`); replace them before packaging.
- **Settings for each feature**
  - Administrators can show or hide pages, buttons, the language and appearance
    settings, the status icon and its notifications.
  - All texts are in language files (`Languages\<culture>.xml`), so they can be
    changed or translated.
- **Intune deployment**
  - One Win32 app package, built with `tools\New-SelfXIntuneWin.ps1`.
  - Install, uninstall and detection scripts. Raise `Tool_Version` and
    `$ExpectedVersion` of `Detection.ps1` for every release, otherwise Intune
    does not roll out the update.
  - The service and the starter are .NET 10 programs (self-contained, LTS) that
    are built once on a build machine (`tools\Build-SelfXBinaries.ps1`, with
    ready AppLocker hash rules). `Install.ps1` checks them by SHA256 before it
    changes anything on the device; nothing is compiled on the device.
  - An update or uninstall closes the running SelfX windows and status icons;
    after the installation the status icon starts right away for all signed-in
    users.
- **Tested:** nine test suites (user interface, health checks, device logs,
  action scripts, language files, catalogue, uninstall, service pipe,
  installer programs). They mock every command that changes the device; the pipe
  test starts only the pipe listener of the service under a test name. GitHub
  Actions runs all of them, and a security-focused script analysis, for every
  pull request.

The details are described in [Configuration](docs/en/Configuration.md) and
[Installation](docs/en/Installation.md); the [User manual](docs/en/User-Manual.md)
explains SelfX for the users.

## Security hardening in this fork

SelfX Service can start scripts with SYSTEM rights for every signed-in user, so
it is treated as a security-critical program. The service was reviewed in
November 2026 and hardened in versions 2.6.10 and 2.6.11; the details are in the
[Changelog](CHANGELOG.en.md) and in the
[security model](SelfX%20Service/README.en.md#security-model) of the package.

- **Only approved actions.** The service runs only scripts that are listed with
  `Context=System` in the installed catalogue. Users can never pass a path,
  code or arguments. `Test-Catalog.ps1` checks the catalogue for every release.
- **Protected pipe.** The service limits connections (8 per user, 64 in total),
  gives every request one 5-second deadline, pauses between requests of the
  same user and cleans the text it logs. The SelfX window checks that the pipe
  is served by the real service.
- **Several users on one device.** The device logs report contains only the
  data of the requesting user, unless an elevated administrator asks for it.
  Actions that would disturb others (restart, Windows updates, disk check,
  restart of the network adapters) are not available to a normal user while
  another user is signed in (`OtherSessions`).
- **Careful file handling.** SYSTEM does not read logs from folders that users
  can change, and the uninstallation does not follow junctions.
- **Controlled build and deployment.** The .NET 10 programs are built once
  (reproducible, the NuGet package fixed by a lock file), checked by hash during
  installation and allowed with AppLocker hash rules. No compiler runs on the
  device.
- **Automatic checks.** Every pull request compiles the service and runs the
  tests and a script analysis.

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.en.md).

## Documentation

- [Installation](docs/en/Installation.md), including the release checklist of SelfX Service
- [Configuration](docs/en/Configuration.md)
- [User manual](docs/en/User-Manual.md)
- [Package notes of SelfX Service](SelfX%20Service/README.en.md)
- [Changelog](CHANGELOG.en.md)
- [Security policy](SECURITY.en.md)

## Repository layout

| Directory | Contents |
|---|---|
| `SelfX Service` | The package: installer, local Windows service (C# source), action catalogue with User and System actions, WPF application, scripts and tests |
| `tools` | `New-SelfXIntuneWin.ps1`, which builds the Intune package with Microsoft's signed Win32 Content Prep Tool (see [Building the Intune packages](docs/en/Installation.md#step-2-build-the-package)), and `Build-SelfXBinaries.ps1`, which builds the .NET 10 programs of SelfX Service (see [Building the programs](docs/en/Installation.md#step-2-build-the-package)) |
| `.github` | GitHub Actions workflow (compile, tests, script analysis), `CODEOWNERS`, Dependabot configuration |
| `build` | Not committed. Output of `New-SelfXIntuneWin.ps1`: `SelfX-Service-<version>.intunewin`; and of `Build-SelfXBinaries.ps1`: `SelfX.AppLocker.xml` |

Review each action script and its execution context before deploying it. Actions
are started as hidden PowerShell processes and may change device state or
terminate applications.

## Upstream and credits

SelfX was created by **Damien Van Robaeys** ([Syst & Deploy](https://www.systanddeploy.com))
as a tool that helps users solve common IT issues on their own. **Wolfgang Baeck**
([wbaeck/SelfX](https://github.com/wbaeck/SelfX)) built SelfX Service on it: the
local Windows service, the merged action catalogue, the health checks, the status
icon, the languages and the Intune packaging. This repository is a fork of his
project. The original project is here:

- Original repository: [damienvanrobaeys/SelfX](https://github.com/damienvanrobaeys/SelfX)
- Introduction of the tool: [blog post on Syst & Deploy (August 2022)](https://www.systanddeploy.com/2022/08/selfx-tool-allowing-users-to-solve.html)

Many thanks to Damien for the idea, the original WPF interface, the XML action
catalogue and the troubleshooting scripts. Many thanks to Wolfgang Baeck: this
fork would not exist without his SelfX Service, his clear structure, his
documentation and his tests, which made the security work possible. The
security hardening, the additional tests, the built .NET 10 programs and the CI were
added in this fork (see the [Changelog](CHANGELOG.en.md)). The license of the
original project is kept in [LICENSE.md](LICENSE.md); authors and sources are in [NOTICE.en.md](NOTICE.en.md).

The System information tab is based on the idea and data points of the
[System Information Tool](https://github.com/JayRHa/windows-system-information)
by Jannik Reinhard (MIT License, Copyright (c) 2026 Jannik Reinhard). SelfX
reimplements the collection in `SelfX Service\Sources\SystemInfo.ps1`.

The Intune package is built with Microsoft's
[Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool).
The executable is not included in this repository; the build script verifies
its Microsoft Authenticode signature before use.
