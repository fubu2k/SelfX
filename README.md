# SelfX (Self fix)

SelfX is a Windows PowerShell and WPF self-service troubleshooting tool. This
fork contains three packages:

- **SelfX Service** (recommended) combines Standard and Admin into one package
  that is installed machine-wide and works fully offline. Actions run either as
  the user or, through the local **SelfXService** Windows service, with SYSTEM
  rights. Users can therefore fix problems on their own without network access,
  SCCM or Intune. The interface follows the Windows display language
  (24 languages included, English fallback; each user can choose another
  language in the settings) and supports company branding.
  The modern, resizable interface (2.5.0) has a Device status page with local
  health checks that the service runs in the background, a System information
  page, a help dialog with the support contacts and a status icon next to the
  clock; see [User interface](docs/Configuration.md#user-interface-selfx-service-250)
  and [Health status](docs/Configuration.md#health-status-selfx-service-230).
  Since 2.6.0 all scripts log to `%ProgramData%\SelfX\Logs` with automatic
  housekeeping, and the Device status page restarts the device (after a
  warning), retries failed company apps and installs Windows updates.
- **SelfX Standard** is installed per user and offers quick and detailed
  troubleshooting actions, plus a **System information** tab that shows device,
  Windows, user/Intune and network details that users can copy or export for the
  support team.
- **SelfX Admin** is a separately launched interface for actions that may
  require an elevated execution context. It does not install a service. Its
  `ServiceUI.exe` can display an application started by a deployment system in a
  signed-in user's session; it does not grant administrator rights or change the
  token used by the process.

This fork does not add a central backend, push messaging or centralized task
reporting.
## Documentation

- [Installation](docs/Installation.md)
- [Configuration](docs/Configuration.md)
- [User manual](docs/User-Manual.md)
- [SelfX Service package notes](SelfX%20Service/README.md)
- [SelfX Standard package notes](SelfX%20Standard/README.md)
- [SelfX Admin package notes](SelfX%20Admin/README.md)

## Repository layout

| Directory | Contents |
|---|---|
| `SelfX Service` | Machine-wide offline package: installer, local Windows service (C# source), merged action catalogue with User and System actions, WPF application and scripts |
| `SelfX Standard` | Per-user installer, detection and uninstall scripts, WPF application, XML configuration and troubleshooting scripts |
| `SelfX Admin` | WPF application, ServiceUI launcher, XML action list and administrative troubleshooting scripts |
| `tools` | `New-SelfXIntuneWin.ps1`, which builds the Intune packages with the open-source PowerShell module `SvRooij.ContentPrep.Cmdlet` (see [Building the Intune packages](docs/Installation.md#building-the-intune-packages)) |
| `build` | Output of `New-SelfXIntuneWin.ps1`: `SelfX-Admin-<version>.intunewin`, `SelfX-Service-<version>.intunewin`, `SelfX-User-<version>.intunewin` |

Review each action script and its execution context before deploying it. Actions
are started as hidden PowerShell processes and may change device state or
terminate applications.

## Upstream and credits

SelfX was created by **Damien Van Robaeys** ([Syst & Deploy](https://www.systanddeploy.com))
as a tool that helps users solve common IT issues on their own. This repository
is a fork of his project:

- Original repository: [damienvanrobaeys/SelfX](https://github.com/damienvanrobaeys/SelfX)
- Introduction of the tool: [blog post on Syst & Deploy (August 2022)](https://www.systanddeploy.com/2022/08/selfx-tool-allowing-users-to-solve.html)

Many thanks to Damien for the idea, the original WPF interface, the XML action
catalogue and the troubleshooting scripts this fork builds on. SelfX Service,
the local Windows service, the health checks, the status icon and the other
extensions described above were added in this fork. The license of the
original project is kept in [LICENSE.md](LICENSE.md).

The System information tab of SelfX Standard is based on the idea and data
points of the [System Information Tool](https://github.com/JayRHa/windows-system-information)
by Jannik Reinhard (MIT License, Copyright (c) 2026 Jannik Reinhard). SelfX
reimplements the collection in `SelfX Standard\Sources\SystemInfo.ps1` (also used by SelfX Service).

The Intune packages are built with the open-source PowerShell module
[SvRooij.ContentPrep.Cmdlet](https://github.com/svrooij/ContentPrep) by Stephan
van Rooij (GPL-3.0). It is installed from the PowerShell Gallery when needed and
is not part of this repository.
