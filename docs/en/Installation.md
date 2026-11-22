# Installation

**English** | [Deutsch](../Installation.md)

This guide describes the installation of **SelfX Service** on managed Windows
devices, in particular with Microsoft Intune.

## Requirements

- A supported Windows desktop with Windows PowerShell and WPF.
- The complete package directory, including its `assembly` and
  `Scripts_to_run` content.
- For SelfX Service, 64-bit Windows PowerShell 5.1 and .NET Framework 4.x. The
  installer either installs the prebuilt programs of the package (folder `Bin`,
  see [Prebuilt programs](#prebuilt-programs-selfx-service-2611)) or compiles
  the service with the C# compiler that ships with the .NET Framework. No
  internet access or SDK is needed.

## SelfX Service

SelfX Service installs machine-wide and runs fully offline. Run the installer
as administrator, either manually or from Intune/SCCM in SYSTEM context:

```powershell
Set-Location 'C:\Path\To\SelfX Service'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

From a 32-bit agent, use
`%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe`. The installer:

1. Stops and removes an existing `SelfXService`.
2. Empties `%ProgramFiles%\SelfX` and copies `Sources` and `Uninstall.ps1`
   into it. The folder itself is kept, because an open SelfX window or status
   icon may use it as working directory. Files that are briefly in use are
   retried for 20 seconds. The installer then
   replaces inherited permissions so that SYSTEM and Administrators have full
   control and Users can only read and execute.
3. Installs `%ProgramFiles%\SelfX\SelfXService.exe` (the service) and
   `%ProgramFiles%\SelfX\SelfX.exe` (2.5.3). When the package contains the
   folder `Bin`, the installer first checks the prebuilt programs against their
   SHA256 manifest and copies them (2.6.11); a failed check stops the
   installation. Without `Bin` it compiles `Service\SelfXService.cs` and
   `Service\SelfXLauncher.cs`; the compiler then writes its temporary files to
   a folder below the install folder, not to `C:\Windows\Temp`.
   `SelfX.exe` is a small starter without a console: it starts SelfX
   (`/page:<Page>` optional) or the status icon (`/tray`) with a hidden Windows
   PowerShell, so no command window appears, also not with Windows Terminal as
   default terminal.
4. Registers and starts the **SelfX Service** (`SelfXService`). It runs as
   LocalSystem, starts automatically, and restarts after a failure.
5. Creates shortcuts for all users on the public desktop and in the Start
   menu (target `SelfX.exe`), according to `Tool_Config.xml`.
6. Adds an Apps & Features entry.
7. When `Show_Tray_Icon` is `True` (default), adds the HKLM Run entry
   `SelfXTray` (`SelfX.exe /tray`), so the status icon (`SelfX_Tray.ps1`) starts at every sign-in
   for all users. Since 2.5.8 the icon also appears right after the
   installation. Running status icons are closed before the files are
   replaced. When the installer runs as SYSTEM (Intune/SCCM), it starts
   `SelfX.exe /tray` in every active user session, with the normal rights of
   the signed-in user, not elevated. The result is written to `Install.log`
   (`Status icon: Session <n>: started`). When you run the installer manually
   as administrator, Windows does not allow this: the icon appears at the next
   sign-in or when the user opens SelfX. Open SelfX windows are not closed.

The installation log is `%ProgramData%\SelfX\Logs\Install.log`. The service log
is `%ProgramData%\SelfX\Logs\SelfXService.log`. It rotates to `.old` at 5 MB.
Both logs can be read only by administrators and SYSTEM. Since 2.6.0 every
SelfX script logs to `%ProgramData%\SelfX\Logs` (one file per script and day);
the window, the status icon and the user actions log to
`%ProgramData%\SelfX\Logs\Users\<SID>`, which the installer creates so that
each user can only create and read the own folder. Log files older than
`Log_Retention_Days` (default 90) are deleted automatically; see
[Logging](Configuration.md#logging-and-log-housekeeping-selfx-service-260).

The installer exits with code 0 on success and 1 on an error. The reason is
the last line of `Install.log` (`Installation failed: ...`). Up to version
2.5.1, an update failed with exit code 1 while a user had SelfX or the status
icon open. Windows refuses to delete a folder that a running program uses as
working directory, so the installer stopped after it had already removed the
service and the files. Version 2.5.2 empties the folder instead of deleting
it. The status icon no longer uses the install folder as working directory.
To repair a device on which an older update failed, deploy 2.5.2. A sign-out
is not needed.

For Intune Win32 apps:

| Setting | Value |
|---|---|
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Detection | Custom script `Detection.ps1`. Set `$ExpectedVersion` to the `Tool_Version` of the release. |

Raise `Tool_Version` (`Sources\Tool_Config.xml`) and `$ExpectedVersion`
(`Detection.ps1`) for every release, to the same value. If you leave them
unchanged, Intune finds the old version, treats the device as up to date and
does not install the new package. `tools\New-SelfXIntuneWin.ps1` stops when the
two values differ.

`Uninstall.ps1` removes the service, `%ProgramFiles%\SelfX`, the shortcuts,
the Apps & Features entry, the status icon autostart (`SelfXTray`), the status
cache (`%ProgramData%\SelfX\Cache`) and the device logs reports
(`%ProgramData%\SelfX\Reports`). Before it deletes files, it closes open
SelfX windows and status icons of all signed-in users, because they keep the
install folder in use. Before version 2.5.7, the uninstallation failed in
that case. If another program still uses a file, for example an Explorer
window opened in the install folder, the uninstaller retries for up to 90
seconds. Two leftovers are not reported as errors:

- an empty install folder that is still in use,
- a service that is only marked for deletion, for example because the
  Services console is open.

The result is logged in `%ProgramData%\SelfX\Logs\Uninstall.log`. Logs are
kept; add `-RemoveLogs` to delete `%ProgramData%\SelfX` as
well. Per-user settings and caches (`HKCU\Software\SelfX`,
`%LOCALAPPDATA%\SelfX`) are not removed.

> If a Group Policy enforces the PowerShell execution policy `AllSigned`, the
> `-ExecutionPolicy Bypass` switch has no effect. In that case, sign
> `Self_X.ps1`, `SelfXServiceClient.ps1`, `Branding.ps1`, `Localization.ps1`,
> `SystemInfo.ps1`, `HealthStatus.ps1`, `SupportReport.ps1`, `SelfX_Tray.ps1`, `SelfXLog.ps1`, all health extension scripts and all action scripts
> (including `Collect-DeviceLogs.ps1`) with a trusted code-signing
> certificate.

Run all tests of SelfX Service before you build a package (see the
[release checklist](#release-checklist-selfx-service)). Every test exits with
code 1 when it finds an error; GitHub Actions runs the same tests for every
pull request:

```powershell
Get-ChildItem '.\SelfX Service' -Filter 'Test-*.ps1' | ForEach-Object {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { Write-Warning "$($_.Name) failed" }
}
```

After you change or add a language file, run only the language check:
`& '.\SelfX Service\Test-LanguageFiles.ps1'` (optionally with `-Culture <code>`).
The tests mock the commands that change the device. `Test-ServicePipe.ps1`
starts the pipe listener of the service in the test process under a test pipe
name; nothing is installed and no administrator rights are needed.

For version 2.3.0 health reporting, redeploy the **entire package**: the service
binary is rebuilt by the installer and must support `HEALTH`. Copying only the
new GUI to a 2.2.0 installation is not sufficient. Version 2.3.1 remediation
allowlisting, the 2.3.2 single-status recheck (`HEALTH <Id> [name]`) and the
2.3.3 `PendingReboot`/`Updates` check Ids also
require redeploying the service, not just the GUI. Version 2.3.4 (Pending
status, Defender signature update script
`Scripts_to_run\SelfX_Defender_UpdateSignature.ps1` and default remediations)
also requires redeploying the entire package. Version 2.4.0 (device logs for
the support) also requires redeploying the entire package: the service passes
the requesting user to the script (`SELFX_CALLER_SID`); with an older service
the action fails with exit code 2. Set `Support_Mail` in `Tool_Config.xml` to
the helpdesk address that receives the device logs. Version 2.5.0 (modern user
interface, background checks with status cache and the `STATUS` request, tray
icon) also requires redeploying the entire package: SelfX 2.5.0 reads the
status with `STATUS`, which older services do not know. Before packaging, set
the support contacts of the help dialog (`Support_Hours`,
`Support_Phone_number`, `Support_Mail`, `Support_Teams`, `Support_Website`)
and check the `Background` element of `Health_Config.xml`; see
[User interface](Configuration.md#user-interface-selfx-service-250) and
[Background checks](Configuration.md#background-checks-and-status-cache-selfx-service-250).
SelfX Service no longer needs the MahApps.Metro assemblies. Version 2.6.0
(logging, restart and app retry repairs, updates installed by SelfX) also requires redeploying the entire package: the installer
creates `Logs\Users` and the service compiles the log housekeeping. Configure
`Sources\Health_Config.xml` and optionally add reviewed read-only scripts under
`Sources\HealthChecks` before packaging; see
[Health status](Configuration.md#health-status-selfx-service-230).
Versions 2.6.10 and 2.6.11 (security hardening, see the
[Changelog](../../CHANGELOG.en.md)) change the service and the installer. Redeploy the
**entire package** and raise `Tool_Version` and `$ExpectedVersion`.
Do not grant users write access to the install folder or check scripts.

Check the installation:

```powershell
Get-Service SelfXService
Get-Content "$env:ProgramData\SelfX\Logs\SelfXService.log" -Tail 20   # as administrator
```

### Release checklist (SelfX Service)

1. Adapt the configuration: branding and support contacts in
   `Sources\Tool_Config.xml`, `Sources\Health_Config.xml`, the catalogue.
2. Raise `Tool_Version` in `Sources\Tool_Config.xml` and set the same value as
   `$ExpectedVersion` in `Detection.ps1`; add a line to the history of both
   files.
3. Run all tests (see above). Fix every error before you continue.
4. Optional: build the prebuilt programs with `tools\Build-SelfXBinaries.ps1`
   (see below) and merge the hash rules of `build\SelfX.AppLocker.xml` into your
   AppLocker policy. A new build has new hashes: replace the rules of the
   previous build.
5. Build the package with `tools\New-SelfXIntuneWin.ps1` (see
   [Building the Intune packages](#building-the-intune-package)).
6. Test on a device that is not in production: new installation, update from
   the previous version, uninstallation, detection. Test as a standard user and,
   if you have shared devices, with a second signed-in user.
7. Publish the package in Intune.

### Prebuilt programs (SelfX Service 2.6.11)

Without further steps, `Install.ps1` compiles `SelfXService.exe` and `SelfX.exe`
on every device. The files then have a different hash on each device, so
AppLocker or WDAC cannot allow them with a hash rule. Build them once instead,
on a build machine with Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1
```

The script writes `SelfX Service\Bin` (not committed): `SelfXService.exe`,
`SelfX.exe`, `SelfXSessionStarter.dll` (used only by the installer) and the
manifest `SelfX.Binaries.json` with the SHA256 of the three sources and the
three files. The files are not signed. When the AppLocker cmdlets are
available on the build machine, the script also writes
`SelfX.AppLocker.xml` next to the `Bin` folder (in `build\`, not in the
package): hash rules for the three files, ready to merge into your AppLocker
policy (`Set-AppLockerPolicy -XmlPolicy ... -Merge` or import in the policy
editor / Intune). AppLocker uses its own hash of the file (Authenticode
SHA256), not the SHA256 of the manifest; always take the rules from this file.
Build the Intune package afterwards; the `Bin` folder is part of it.

When the package contains `Bin`, `Install.ps1` checks before installing:

- the manifest and all three files exist;
- the sources of the package (`Service\*.cs`) have the hashes of the manifest,
  so the programs were built from exactly these sources;
- each file has the hash of the manifest.

Any failed check stops the installation with exit code `1`; nothing is compiled
instead. The reason is in `%ProgramData%\SelfX\Logs\Install.log`. Without `Bin`
the device compiles as before; the temporary files of the compiler are then
written to a folder below the install folder instead of `C:\Windows\Temp`.
`tools\New-SelfXIntuneWin.ps1` refuses to package a `Bin` folder that was built
from other sources. Rebuild `Bin` after every change of `Service\*.cs`, and
replace the hash rules in AppLocker at the same time: a new build has new
hashes, and the old rules no longer match.

## Building the Intune package

`tools\New-SelfXIntuneWin.ps1` creates the `.intunewin` file of SelfX Service in
the `build` folder of the repository (the folder is not committed, see
`.gitignore`). It uses Microsoft's
[Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
(`IntuneWinAppUtil.exe`); download the executable from the official repository
and pass its path with `-ToolPath`. The script verifies the Microsoft
Authenticode signature before running it. The executable is not stored in this
repository, and the script does not install a PowerShell packaging module.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1 `
  -ToolPath C:\Tools\IntuneWinAppUtil.exe
```

| Source folder | Setup file | Package |
|---|---|---|
| `SelfX Service` | `Install.ps1` | `build\SelfX-Service-<version>.intunewin` |

The version is `Tool_Version` (`Sources\Tool_Config.xml`). The script copies the folder to a
temporary staging folder and leaves out the packaging tests (`Test-*.ps1`).
Before packaging it checks that the setup file exists and that every XML file
is valid. It also checks that `$ExpectedVersion` in
`Detection.ps1` equals `Tool_Version`. With `-ToolPath` it verifies the
Microsoft signature of `IntuneWinAppUtil.exe`. It uploads nothing to Intune. Exit code
`0` means the package was created; `1` means it failed. Run the
tests of SelfX Service before building.

Use the package in Intune as follows:

| Install command | Install behavior | Uninstall / detection |
|---|---|---|
| `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` | System | `Uninstall.ps1`, custom script `Detection.ps1` (see [SelfX Service](#selfx-service)) |

## Deployment checklist

1. Review the XML action list and every referenced `.ps1` script.
2. Install as System (the installer needs administrator rights).
3. Test the UI and each intended action on a non-production device.
4. Check the status icon and the window as a standard user (no administrator).
5. Keep the complete package together; do not omit icons, XML, XAML or action
   scripts.
6. Follow the [release checklist](#release-checklist-selfx-service).
