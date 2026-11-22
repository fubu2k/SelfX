# Installation

**English** | [Deutsch](../Installation.md)

This guide describes the installation of **SelfX Service** on managed Windows
devices, in particular with Microsoft Intune.

## Requirements

- A supported Windows desktop with Windows PowerShell and WPF.
- The complete package directory, including its `assembly` and
  `Scripts_to_run` content.
- For SelfX Service on the device: 64-bit Windows and the 64-bit Windows
  PowerShell 5.1 that ships with Windows. A .NET installation is **not** needed:
  the service and the starter are .NET 10 programs that bring everything they need
  (self-contained). Whether your Windows version is supported by .NET 10 is stated
  in Microsoft's support policy.
- To build the package (not on the devices): a Windows computer with the .NET SDK
  10, see the [quick start](#quick-start-rolling-out-a-new-version). The installer
  only installs the prebuilt programs from the folder `Bin` of the package (see
  [Building the programs](#building-the-programs-selfx-service-since-270)). It
  compiles nothing on the device and needs neither internet nor an SDK there.

## Quick start: rolling out a new version

These steps apply to every new version of SelfX Service. You need **one Windows
computer for building** (the "build machine"). Nothing is built or compiled on
the devices of your users.

### Prepare once: the build machine

1. Use a Windows computer with internet access. An ordinary administrator
   workstation is enough; it does not have to be one of the managed devices.
2. Install the **.NET SDK 10** ("SDK", not only "Runtime"). Download:
   <https://dotnet.microsoft.com/download/dotnet/10.0>. Then open a new PowerShell
   window and check:

   ```powershell
   dotnet --version
   ```

   The output must start with `10.`. The build script refuses any other major
   version.
3. Get the repository onto the computer (`git clone` or the ZIP from GitHub).
4. Download `IntuneWinAppUtil.exe` from Microsoft's official repository
   (<https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool>) and note its
   path, for example `C:\Tools\IntuneWinAppUtil.exe`.

### For every new version

1. **Update the repository.** With `git pull` or a new ZIP. Then change into the
   repository folder in the PowerShell window.
2. **Check the settings.** Branding and support contacts are in
   `SelfX Service\Sources\Tool_Config.xml` and `Health_Config.xml`.
3. **Raise the version number.** Enter the same new number in two places:
   `Tool_Version` in `Sources\Tool_Config.xml` and `$ExpectedVersion` in
   `Detection.ps1`. Otherwise Intune considers the device up to date and deploys
   nothing.
4. **Check the tests.** When you work through a pull request, the tests run
   automatically on GitHub and you see green check marks. If a test is red, do not
   continue.
5. **Build the programs.** This command creates the folder `SelfX Service\Bin`:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1
   ```

   At the end the script lists three files with their hash (`SelfXService.exe`,
   `SelfX.exe`, `SelfXSessionStarter.dll`). The first run downloads the Microsoft
   package `System.ServiceProcess.ServiceController` from the internet; its
   version is fixed and checked.
6. **Adapt AppLocker** (only if you use AppLocker). The script writes
   `build\SelfX.AppLocker.xml`. Merge these rules into your policy and delete the
   rules of the previous version. Do this before the package reaches the devices.
7. **Create the Intune package.** The path after `-ToolPath` is the one from step 4
   of the preparation:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1 -ToolPath C:\Tools\IntuneWinAppUtil.exe
   ```

   Result: `build\SelfX-Service-<version>.intunewin`. The script stops when `Bin`
   is missing or does not match the sources.
8. **Test on a test device.** Install the package on a device that is not in
   production: new installation, update from the previous version, uninstallation.
   Check SelfX as a normal user without administrator rights.
9. **Upload to Intune.** As a Win32 app with the commands from the table under
   [SelfX Service](#selfx-service). Detection: the script `Detection.ps1`.

### If something goes wrong

| Message | Meaning and solution |
|---|---|
| `The command dotnet was not found` | The .NET SDK 10 is not installed, or the PowerShell window is older than the installation. Install the SDK and open a new window. |
| `The .NET SDK 10 is required, found '…'` | No SDK 10 is installed (or only another one). Install SDK 10. When several SDKs are installed, the `global.json` in the repository selects SDK 10 automatically. |
| `The folder Bin is missing …` | Step 5 was not run, or the package was built before. Repeat steps 5 and 7. |
| `Bin was not built from the current …` | A source file was changed after the build. Repeat steps 5 and 7. |
| The installation on the device ends with exit code 1 | The last line of `%ProgramData%\SelfX\Logs\Install.log` gives the reason. The previous installation then stays unchanged. |

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
   `%ProgramFiles%\SelfX\SelfX.exe` (2.5.3). Both come from the folder `Bin` of the
   package. The installer checks them against their SHA256 manifest **at the very
   start**, before it changes anything on the device. When `Bin` is missing or a
   file does not match, the installation ends with exit code 1 and the existing
   installation stays unchanged (2.7.0). Nothing is compiled on the device.
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
4. Build the programs with `tools\Build-SelfXBinaries.ps1` (required, see
   [Building the programs](#building-the-programs-selfx-service-since-270)) and,
   if you use AppLocker, merge the hash rules of `build\SelfX.AppLocker.xml` into
   your policy. A new build has new hashes: replace the rules of the previous
   build.
5. Build the package with `tools\New-SelfXIntuneWin.ps1` (see
   [Building the Intune packages](#building-the-intune-package)).
6. Test on a device that is not in production: new installation, update from
   the previous version, uninstallation, detection. Test as a standard user and,
   if you have shared devices, with a second signed-in user.
7. Publish the package in Intune.

### Building the programs (SelfX Service since 2.7.0)

`SelfXService.exe` (the service) and `SelfX.exe` (the starter) are .NET 10 programs.
They are built **once** on a build machine with the .NET SDK 10 and shipped with the
package. All devices then have the same files with the same hash, so AppLocker or WDAC
can allow them with a hash rule, and no compiler runs as SYSTEM on the devices. The
command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1
```

The script first checks that SDK 10 is installed and then builds the three projects
in `SelfX Service\Service\Projects` with `dotnet publish`:

- The programs are *self-contained* and consist of one file (about 36 MB each). The
  .NET runtime is inside. Runtime updates come with a new SelfX version, not through
  Windows Update.
- The only NuGet package (`System.ServiceProcess.ServiceController` from Microsoft)
  is fixed with version and hash in `packages.lock.json`. Another version makes the
  build fail.
- The build is reproducible: the same sources and the same SDK give the same files.
  The CI on GitHub checks this for every pull request.

The script writes `SelfX Service\Bin` (not committed): `SelfXService.exe`, `SelfX.exe`,
`SelfXSessionStarter.dll` (used by the installer only) and the manifest
`SelfX.Binaries.json` with the SHA256 of the three sources and the three files
(manifest format 2). The files are not signed. When the AppLocker cmdlets are available
on the build machine, the script also writes `SelfX.AppLocker.xml` to the folder
`build\` (not part of the package): hash rules for the three files, ready to be merged
into your AppLocker policy (`Set-AppLockerPolicy -XmlPolicy ... -Merge` or import in the
policy editor / in Intune). AppLocker uses its own hash of the file (Authenticode
SHA256), not the SHA256 of the manifest; always take the rules from this file. Then
build the Intune package; the folder `Bin` is part of it.

`Install.ps1` requires `Bin` and checks before the installation:

- the folder `Bin`, the manifest and all three files exist;
- the manifest has format 2 (packages built with 2.6.x are refused);
- the sources of the package (`Service\*.cs`) have the hashes of the manifest, so the
  programs were built from exactly these sources;
- every file has the hash of the manifest.

Every failed check stops the installation with exit code `1` **before** the old service
or the old files are touched. The reason is in `%ProgramData%\SelfX\Logs\Install.log`.
`tools\New-SelfXIntuneWin.ps1` stops when `Bin` is missing or does not match the
sources, and does not package the .NET project files. Rebuild `Bin` after every change
of `Service\*.cs` and replace the AppLocker hash rules at the same time.

> **Note on the change from 2.6.x:** Version 2.6.x compiled the service on the device
> with the .NET Framework. From 2.7.0 that is no longer possible. Always deploy the
> whole package. The service still starts the scripts with Windows PowerShell 5.1.

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
