# Installation

**English** | [Deutsch](de/Installation.md)

This guide shows step by step how to build **SelfX Service**, deploy it with Microsoft
Intune and check it. It is written for administrators. You do not need programming skills.

![SelfX 3.0 with the new design: Troubleshooting page](images/selfx-troubleshooting-light.png)

*The new design of SelfX 3.0: calm colors, rounded cards, large buttons and a three-step hint
("Select problem – Confirm – Done"). There is a light and a dark design; SelfX follows the
Windows setting.*

## Contents

1. [The most important points](#the-most-important-points)
2. [Requirements](#requirements)
3. [Step 1: Prepare the build machine once](#step-1-prepare-the-build-machine-once)
4. [Step 2: Build the package](#step-2-build-the-package)
5. [Step 3: Set up in Intune](#step-3-set-up-in-intune)
6. [Step 4: Test](#step-4-test)
7. [Update to a new version](#update-to-a-new-version)
8. [Uninstall](#uninstall)
9. [Optional building blocks](#optional-building-blocks)
10. [Background: what the installation does](#background-what-the-installation-does)
11. [Troubleshooting](#troubleshooting)
12. [Deployment checklist](#deployment-checklist)

## The most important points

- SelfX Service is installed **once per device** and works without internet.
- You build the package **on a build machine**. Nothing is compiled on the devices.
- The devices need **Windows 11 25H2** (build 26200 or newer) and **PowerShell 7.6 or
  newer**. Terminal servers with **Windows Server 2022 or 2025** are supported too; they are
  installed without Intune (see [Windows Server](#windows-server-terminal-server)).
- Always deploy the **whole package**, never single files.
- The version number in `SelfX Service\Version.txt` and the value `$ExpectedVersion` in
  `Detection.ps1` must be **the same**. Otherwise Intune does not detect the update. The version
  is a property of the code: the build writes it into `SelfX.Code.json`; the settings file
  `Tool_Config.xml` does not carry it.
- If PowerShell 7 is missing, SelfX is still installed. This keeps Autopilot undisturbed.

## Requirements

**On the devices:**

| Requirement | Details |
|---|---|
| Windows 11 25H2 (build 26200) or newer, 64-bit, or Windows Server 2022 or 2025 with Desktop Experience (build 20348 or newer) | On older versions, on Server Core, on a domain controller and on Windows Enterprise multi-session the installer stops before it changes anything. On Windows Server SelfX works as on a terminal server. |
| PowerShell 7.6 or newer | Installed for all users (MSI from Microsoft), path `%ProgramFiles%\PowerShell\7\pwsh.exe`. The Store version (MSIX) does not work. |
| Windows PowerShell 5.1 | Part of Windows. SelfX uses it only for `Install.ps1`, `Uninstall.ps1`, `Detection.ps1` and `Collect-DeviceLogs.ps1`. |
| .NET | **Not needed.** The service and the starter bring everything with them. |

**On the build machine (not on the devices):**

| Requirement | Details |
|---|---|
| Windows computer | A normal administrator workstation is enough. **No internet needed** (see "Offline build"). |
| .NET SDK 10 | "SDK", not only "Runtime". The same version as at the export of the folder `offline-feed`. |
| `IntuneWinAppUtil.exe` | The Win32 Content Prep Tool from Microsoft. |
| The SelfX repository | `git clone` or ZIP from GitHub, including the folder `offline-feed` (NuGet packages with hash list). |

## Step 1: Prepare the build machine once

Nothing is downloaded on the build machine. Everything it needs comes from the repository or from your own software distribution.

1. Install the **.NET SDK 10** from your software distribution. The version must match the one with which the folder `offline-feed` was created (see "Offline build" below).
2. Open a **new** PowerShell window and check the version:

   ```powershell
   dotnet --version
   ```

   The output must start with `10.`.
3. Put `IntuneWinAppUtil.exe` (Microsoft Win32 Content Prep Tool) in a folder, for example `C:\Tools\IntuneWinAppUtil.exe`, and note the path. Get the file on a computer **with** internet access from the official repository <https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool> and transfer it to the build machine. The packaging script checks the Microsoft signature.
4. Copy the repository **including the folder `offline-feed`** to the build machine, for example as a ZIP file or on a data medium.

## Step 2: Build the package

> **Easier with the wizard:** `tools\Start-SelfXPackageWizard.cmd` (window) or `tools\New-SelfXPackage.ps1` (console) asks questions with recommendations, then builds the package
> in one run (settings, logo, optional signature, packing, detection script, AppLocker and App Control files) and explains the steps
> in Intune. It works on the unpacked **payload archive** of a release, so the .NET SDK is not needed. See
> [Package wizard](Guided-Setup.md). The steps below show the manual way.

Repeat this step for every new version. Open PowerShell in the folder of the repository.

1. **Adjust the settings.** Branding, support contacts and features are in
   `SelfX Service\Sources\Tool_Config.xml` (see [Configuration](Configuration.md)).
2. **Check the version number.** For a new release, enter the same number in two places:
   - `SelfX Service\Version.txt` (one line, for example `3.0.3`)
   - `$ExpectedVersion` in `Detection.ps1`

   The packaging script stops if the two values differ. Changing the settings (for example a
   logo) does not change the version, and a new version changes no settings file.
3. **Build the programs.** The command creates the folder `SelfX Service\Bin`:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1
   ```

   At the end the script shows the built files with their hash. The build needs no internet:
   all NuGet packages come from the folder `offline-feed` and are checked against
   `SelfX.OfflineFeed.json` first (see "Offline build" below).
4. **Adjust AppLocker** (only if you use AppLocker). The script writes
   `build\SelfX.AppLocker.xml`. Take over these rules and delete the rules of the previous
   version before the package reaches the devices. For a **signed** package use publisher rules
   instead, which you set up once ([Set up once instead of per version](#set-up-once-instead-of-per-version)).
5. **Create the Intune package.** Set `-ToolPath` to the path from step 1:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1 -ToolPath C:\Tools\IntuneWinAppUtil.exe
   ```

Result in the folder `build`:

| File | Purpose |
|---|---|
| `SelfX-Service-<version>.intunewin` | The package for Intune. |
| `SelfX-Service-<version>.Detection.ps1` | The detection script for Intune. Upload **this** file, not the copy in the repository. |

The script checks beforehand: the setup file exists, all XML files are valid, `Bin` matches the
source code, the two versions are the same and `IntuneWinAppUtil.exe` has the Microsoft
signature. It uploads nothing to Intune.

**Alternative: release on GitHub.** After the merge, rename `## Unreleased` in `CHANGELOG.en.md` to
`## <version> - <date>` and set the tag `v<version>` (the number in `Version.txt`, for example `v3.1.0`) on `main`. The workflow
`.github/workflows/release.yml` then does this in one run:

1. It checks that the tag and `Version.txt` match and that `CHANGELOG.en.md` has a section for the version. That section is the
   description of the release, followed by a fixed block "Files and how to verify".
2. It builds the programs and the files of the table below.
3. It runs all tests of the CI workflow (`service-ci.yml`) for the tagged commit.
4. It checks the files against `SHA256SUMS.txt` (exactly these files, every hash), in the build and again in the job that publishes, before it uploads them.
5. It publishes the release.

If one step fails, no release is created. A second run for the same tag does not touch an existing release.

| File | Purpose |
|---|---|
| `SelfX-Service-<version>.intunewin` | The package for Intune with the default configuration, for tests. |
| `SelfX-Service-<version>.Detection.ps1` | The detection script of that package. |
| `SelfX-Service-<version>-payload.zip` | The payload archive: the package folder as it is packed (`Install.ps1`, `Uninstall.ps1`, `Detection.ps1`, `Bin`, `App` with `SelfX.Code.json`, `Config` with the default configuration and `SelfX.Config.json`, `Service`), the package assistant and the scripts it calls (`tools`), `LICENSE.md`, `NOTICE.md`, `NOTICE.en.md`. Use it to configure and package SelfX for your company without the .NET SDK. |
| `SelfX-Service-<version>.sbom.cdx.json` | Bill of materials (SBOM). |
| `SHA256SUMS.txt` | SHA-256 of all other files. The release notes show a command to check them. |

Two repository variables (Settings, Secrets and variables, Actions, *Variables*) change the behaviour:

- `RELEASE_DRAFT` = `true` creates a draft instead of a published release (publish it by hand after checking the files).
- `RELEASE_ATTEST` = `false` turns off the build provenance attestation of the payload archive. Without the variable it is created
  (`gh attestation verify <file> --repo <owner>/<repository>` checks it).

**Try the workflow without a release.** Set `RELEASE_DRAFT` to `true`. On a branch that you do not merge, set a version that does not exist
(for example `9.9.9`) in `SelfX Service\Version.txt`, in `$ExpectedVersion` of `Detection.ps1` and as a section `## 9.9.9` in
`CHANGELOG.en.md`, and push the tag `v9.9.9` on that commit. After the run, check the draft and the log, then delete the draft, the tag and
the branch, and set `RELEASE_DRAFT` back.

### Offline build: renew the package folder

The build loads **nothing** from the internet. `NuGet.config` in the repository allows only the folder `offline-feed` as
package source. Before every build `Build-SelfXBinaries.ps1` checks the folder against `offline-feed\SelfX.OfflineFeed.json`
(SHA512 of every package), builds with a fresh package cache `.nuget-cache` inside the repository and stops when a package
is missing, changed or additional in the folder. The build machine therefore needs only the .NET SDK 10 (from your software
distribution), `IntuneWinAppUtil.exe` and the repository **with** the folder `offline-feed`.

Renew the folder only for a **new SDK version** (the runtime package belongs to the SDK version; the build reports it when the
versions differ) or a **new or updated package**:

1. Use a computer **with internet** and **the same .NET SDK 10** as the build machine.
2. Run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-SelfXOfflineFeed.ps1
   ```

   The script downloads the packages from nuget.org into an empty temporary folder, runs the NuGet vulnerability audit (it
   stops on a finding; after your own check use `-AllowVulnerabilities`), checks that all packages of `packages.lock.json` are
   present, rewrites `offline-feed` and, as a proof, restores all projects from this folder only (no internet, empty cache,
   lock files enforced).
3. **The first time:** the packages that no lock file lists (runtime package, Windows SDK projection) are fixed only by the
   hash list. Run the export on a second computer as a check; the hashes in `SelfX.OfflineFeed.json` must be identical.
4. Check `git diff`, commit the folder and copy the repository to the build machine.
5. **Test without internet:** disconnect the build machine from the network and run step 2.3. The build must finish without
   an error.

Dependabot proposals for NuGet packages do not change the folder: repeat the export after you accept one.

## Step 3: Set up in Intune

Open the Microsoft Intune admin center: *Apps > Windows > Add > Windows app (Win32)*. Upload the
file `SelfX-Service-<version>.intunewin`.

### 3.1 App settings

| Setting | Value |
|---|---|
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Detection rule | Custom script: `SelfX-Service-<version>.Detection.ps1` from the folder `build` |
| Requirement | Windows 11 25H2, see 3.3 |
| Dependency | App "PowerShell 7", *Automatically install* = Yes, see 3.2 |

The detection reports "installed" only if the version, the registered service, the file
list **and** the trust anchor (`HKLM\SOFTWARE\SelfX\Trust`, written by `Install.ps1`) match. So an
update with changed files but the same version number is also detected. An installation of a
version without the anchor is not detected and is installed again once.

#### Optional: signed package (trust mode signature)

For a package whose files are signed with the code signing certificate of the company, add the
thumbprint of the signing certificate to the install command:

`%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -TrustedSigner <thumbprint>`

- The thumbprint is the SHA1 thumbprint of the **signing certificate** (40 hexadecimal characters,
  no spaces), not the one of the certification authority. Several thumbprints are separated by
  commas without spaces (`-TrustedSigner <old>,<new>`), so a renewed certificate can be allowed
  before the switch.
- `Install.ps1` then installs only when every program and script of the package is signed by one of
  these certificates and the two signed catalogs (`Config\SelfX.Config.cat`, `SelfX.Code.cat`) match
  the package. Otherwise it stops before anything on the device is changed
  ([Architecture](Architecture.md#the-mode-signature-in-installps1)).
- The certificate chain (root and intermediate certificates) must be trusted on the device
  **before** SelfX is installed, also during Autopilot: assign the certificate profile so that it
  arrives first.
- A device that was installed with `-TrustedSigner` refuses an installation without the parameter.
  To go back to an unsigned package, add the switch `-AllowHashMode` once.
- Revocation list: Windows asks the address that is named in the certificate. For devices outside
  the company network it should be an HTTP address that is reachable from the internet. A list
  that cannot be reached does not stop the installation (default setting of Windows) but can slow
  it down; `tools\Measure-SelfXRevocationDelay.ps1` measures this on a test device.
- The package wizard signs the package (page **Signature** of the window, or `-CertificateThumbprint` /
  `-PfxPath` in the console) and writes the install command with `-TrustedSigner`. How to get the
  certificate, how devices trust it and how to change it: [Code signing certificate](Certificate-Guide.md).

### 3.2 PowerShell 7 as its own Win32 app

1. Download the MSI file (`PowerShell-7.6.x-win-x64.msi`) from Microsoft and package it as a
   **Win32 app**, not as a line-of-business (MSI) app. Mixing both types can fail with
   Autopilot.
2. Install command, for example:

   ```text
   msiexec.exe /package PowerShell-7.6.x-win-x64.msi /quiet DISABLE_TELEMETRY=1 USE_MU=0 ENABLE_MU=0
   ```

   Do not change the installation folder. `ADD_PATH` is not needed. Test the command on a
   test device first.
3. Detection rule: file `%ProgramFiles%\PowerShell\7\pwsh.exe`, file version greater than or
   equal to 7.6.0.
4. Deploy new PowerShell versions as a new version of this app.
5. In the SelfX app under *Dependencies*, add the app "PowerShell 7" with *Automatically
   install* = Yes. Intune then installs PowerShell 7 first.

### 3.3 Requirement rule for Windows 11 25H2

Check whether the portal offers "Windows 11 25H2" as the minimum operating system. If not, add
a requirement rule of type *Script*: output data type *Integer*, operator *Greater than or equal
to*, value `26200`:

```powershell
[int](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber)
```

Older devices then do not receive the app instead of failing with an error.

### 3.4 Autopilot and the status page (ESP)

Autopilot installs apps in any order and must never fail because of SelfX. Therefore:

- Do **not** add SelfX or PowerShell 7 to the list of blocking apps of the ESP (*Block device
  use until these required apps are installed* = *Selected*, without these two apps).
- A missing PowerShell 7 is only a **warning**. SelfX then starts no scripts, but checks again
  before every start and works as soon as PowerShell 7 is there.
- An **unsafe** PowerShell 7 is a hard stop instead (see the table below).

| Situation on the device | Installer | Service |
|---|---|---|
| Windows older than 25H2 | Stops before any change, exit code 1. An existing installation stays unchanged. | not affected |
| PowerShell 7 is missing or older than 7.6 | **Warning** in the installation log, the installation continues. | starts no script and reports the reason |
| The folder `%ProgramFiles%\PowerShell\7` or `pwsh.exe` can be changed by normal users | Stops before any change, exit code 1. | starts nothing |

### 3.5 Assignment

Assign the app to a device group as *Required*. Start with a small pilot group.

## Step 4: Test

Test on a device that is not in production:

1. New installation: the SelfX window, the status icon next to the clock and the shortcuts
   appear.
2. Run an action as a **normal user** (without administrator rights).
3. Update from the previous version.
4. Uninstall and detection.
5. On a device with several users: keep a second user signed in.
6. Installation without PowerShell 7 (warning, SelfX works by itself later) and on
   Windows 11 24H2 (stops with exit code 1).
7. An Autopilot run with both apps (the provisioning must not hang).

Check on the device:

```powershell
Get-Service SelfXService
Get-Content "$env:ProgramData\SelfX\Logs\Install.log" -Tail 20          # as administrator
Get-Content "$env:ProgramData\SelfX\Logs\SelfXService.log" -Tail 20     # as administrator
```

Run the tests of the repository like this (each test ends with exit code 1 if it finds an
error; GitHub Actions runs the same tests for every pull request):

```powershell
Get-ChildItem '.\SelfX Service' -Filter 'Test-*.ps1' | ForEach-Object {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { Write-Warning "$($_.Name) failed" }
}
```

## Update to a new version

1. Always deploy the **whole package**. The window and the service must fit together.
2. Raise `Version.txt` and `$ExpectedVersion` to the same new value.
3. Build the programs and the package again (step 2) and replace the AppLocker rules (not needed
   with publisher rules for a package signed by the same certificate, see
   [Set up once instead of per version](#set-up-once-instead-of-per-version)).
4. Upload the new `.intunewin` **and** the new detection script to the same Intune app.
5. Before packaging, check the support contacts in `Tool_Config.xml` and `Health_Config.xml`
   (see [Configuration](Configuration.md)).
6. If only the settings change, a [second package for the configuration](#second-intune-package-the-configuration-only) is enough.

**Update from SelfX 2.6.9 (upstream):** In addition the devices need Windows 11 25H2 and
PowerShell 7.6 (step 3). The package must be built again with the .NET SDK 10; the old method of
compiling the service on the device no longer exists. Also replace the AppLocker rules. The
default language of the interface is now German (`Tool_Language` = `de`). All changes are in
the [changelog](../CHANGELOG.en.md).

## Uninstall

`Uninstall.ps1` removes the service, `%ProgramFiles%\SelfX` (with `App` and `Config`, and also an
installation in the old layout of 3.0.x), the shortcuts, the entry under Apps
& features, the autostart of the status icon, the status cache and the reports. Open SelfX
windows and status icons are closed first. If another program keeps a file open, the uninstaller
tries again for up to 90 seconds.

- The logs are kept. With `-RemoveLogs`, `%ProgramData%\SelfX` is deleted as well.
- Settings of single users (`HKCU\Software\SelfX`, `%LOCALAPPDATA%\SelfX`) are not removed.
- The result is in `%ProgramData%\SelfX\Logs\Uninstall.log`.

## Optional building blocks

### Windows Server (terminal server)

SelfX runs on Windows Server 2022 and 2025 with Desktop Experience. There it takes the mode
`TerminalServer` from Windows: only actions for the own session are offered, and the service refuses
the others ([Configuration, Terminal server](Configuration.md#terminal-server-windows-server)).

**Intune cannot install apps on Windows Server.** Only Windows Server Insider Preview builds can be
enrolled in Intune; production servers cannot. Install SelfX by hand or with Configuration Manager:

1. Build the package with the assistant and answer *For which Windows is this package?* with
   `WindowsServer`. The assistant then asks who gets the device status (`TerminalServer_Health`) and
   writes the instructions `SelfX-Server-Guide.<language>.txt` instead of the Intune guide. No
   `.intunewin` file is built for it and `IntuneWinAppUtil.exe` is not needed.
2. Install PowerShell 7.6 or newer (MSI, machine-wide) on the server.
3. Copy the folder `package` of the output folder unchanged to the server or to a share that only
   administrators can change. Users may only read it: `Install.ps1` checks every file against the file
   lists, but whoever can change the share can also change the lists.
4. In an elevated 64-bit Windows PowerShell in that folder:
   `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1`
   (with `-TrustedSigner <thumbprint>` for a signed package). Uninstall: the same with `Uninstall.ps1`.
5. Configuration Manager: an application with the deployment type *Script Installer*, content = the
   copied folder, the commands above, installation behavior *Install for system*, not as a 32-bit
   process. Detection method: a custom PowerShell script with the content of
   `SelfX-Service-<version>.Detection.ps1`. It writes a line and exits with 0 when SelfX is installed and
   writes nothing otherwise, as Configuration Manager expects.

`Install.ps1` stops without a change on Server Core (no desktop for the window and the status icon), on a
domain controller and on Windows Enterprise multi-session. A Group Policy startup script is not a good
fit: `Install.ps1` installs again at every start (the service is stopped and the files are replaced).

### Second Intune package: the configuration only

The assistant can build a **second, small package** (`SelfX-Config-<version>.intunewin`) that holds only `Install.ps1`, `Detection.ps1` and
the folder `Config`. Install it with `Install.ps1 -ConfigOnly`. It replaces the settings of a SelfX that is **already installed** (support
address, logo, ticket routing, action lists, language) and nothing else: the service, the programs and the trust anchor are not touched and
nothing is restarted. An open SelfX window shows the new settings after it is closed and opened again.

**When is it worth it?** When the settings change often and the code rarely. The small package installs in seconds, you do not test the
whole product again, and the code package (the large one) stays as it is. If you change settings only together with a new version, one
package is simpler: stay with it.

**How to build and install both packages**

1. Build the full package with the assistant, answer *Full package with a separate configuration package* (console: `-SeparateConfig`). Its detection script does
   not compare the configuration, so the full package is not installed again when only the configuration changed.
2. Build the configuration package from the same release and the **same answers**: answer *Configuration package* (console: `-ConfigPackage`).
3. In Intune create **two apps**: the full app as before, and the configuration app with the install command
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -ConfigOnly` (the assistant writes the exact line in its instructions).
   Uninstall command: a command that does nothing (`...powershell.exe -NoProfile -Command exit 0`); the full app removes SelfX.
4. Add the **full app as a dependency** of the configuration app (*Automatically install: Yes*). Assign both to the same device groups.
5. Detection of the configuration app: the file `SelfX-Config-<version>.Detection.ps1` (it compares only the configuration).

**Updating the configuration later.** Build a new configuration package and upload it as a **new version of the configuration app**, or create a new app and add
the old one under *Supersedence* with *Uninstall previous version* set to **No**. Supersedence is for the configuration apps among themselves:
a newer configuration app replaces an older one, the devices install the new one and the old one is no longer required.

> **Never set supersedence between the configuration app and the full app.** The full app would be uninstalled by the supersedence and SelfX would be removed
> from the device.

**What `-ConfigOnly` checks (it stops before it changes anything)**

- SelfX is installed and has a trust anchor; the anchor is safe. The mode (Hash or Signature) is the one of the device. `-TrustedSigner` and
  `-AllowHashMode` cannot be combined with `-ConfigOnly`: a configuration package cannot change who is trusted.
- The package holds only `Install.ps1`, `Config` and `Detection.ps1` (it is neither run nor installed), no link, and every file is in `Config\SelfX.Config.json` with its SHA256. In the mode Signature the
  scripts and `Config\SelfX.Config.cat` must carry a valid signature of a signer of the device.
- `MinCodeVersion` in `SelfX.Config.json` (the code version the configuration is made for) must not be newer than the installed code version
  (`App\SelfX.Code.json`). Install the full package first when it is.
- Settings that only the full installation applies (shortcut name, shortcut on the desktop or in the Start menu, the entry of the status icon,
  the icon, `Service_Privileges`) must be the same as on the device. If they differ, the configuration package refuses with their names: change
  them with the full package. Everything else in `Tool_Config.xml` is read when SelfX runs and can change.

The folder `Config` is exchanged by renaming: the new folder is copied next to the install folder and checked there, then `Config` is renamed to
`SelfX.ConfigOld` (next to the install folder) and the new folder to `Config`; an error puts the old folder back. The folders next to the install folder are called `SelfX.ConfigStage` and `SelfX.ConfigOld`
(the service refuses to start scripts when the install folder holds anything but `App` and `Config`). A script of an action that is running holds files open: the
exchange waits and tries again for about 20 seconds, then it stops with exit code 1 and Intune tries again later. The result is in
`%ProgramData%\SelfX\Logs\Install.log`.

**Detection and the full package.** After a new code version the full package replaces `Config` with the configuration of its own build. The configuration
package then no longer matches (its digest differs) and Intune installs it again: the settings of the configuration package apply again. Build both packages from the same
release and the same answers, and roll out the full package first.

### Ticket routing with Intune

Only needed if you use the ticket function (`Ticket_Enabled`) with rules for group tag or
category in `Ticket_Config.xml` (see [Configuration](Configuration.md#ticket-by-e-mail)). SelfX
only reads the values. They are in `HKLM\SOFTWARE\SelfX\Support`:

- `GroupTag` and `Category` (each up to 64 characters: letters, digits, space, `.`, `_`, `-`)
- `TicketMail` and `TicketCc`: exactly one plain address per value, shared (functional)
  mailboxes only, no personal mailboxes

Hybrid devices can also be assigned by OU; nothing has to be set for that.

How to proceed (*Devices > Scripts and remediations > Platform scripts*):

1. Copy the script below for each unit and adjust the values at the top.
2. Settings: *Run this script using the logged on credentials* = **No** (runs as SYSTEM),
   *Run script in 64-bit PowerShell host* = **Yes**.
3. Assign the script to an Entra device group. The groups should exclude each other. The script
   always sets all four values; when a device moves to another group, the script of the new
   group replaces the values of the old one.
4. Check on the device: `Get-ItemProperty 'HKLM:\SOFTWARE\SelfX\Support'`. Before deployment,
   `tools\Test-SelfXTicketRouting.ps1 -GroupTag ... -Category ...` shows which unit results.

The script runs in Windows PowerShell 5.1 and PowerShell 7 and changes only these four values.
Invalid values stop it before anything is written.

```powershell
# Set-SelfXSupportUnit.ps1 (example) - sets the values SelfX reads for the ticket routing.
# Intune platform script: run as SYSTEM (not as the signed-in user), 64-bit, one copy per assignment.
# Use shared (functional) mailboxes only, no personal mailboxes.
$GroupTag   = 'DE-IT1-BER'          # optional, up to 64 characters: letters, digits, space, . _ -
$Category   = 'Category-A'          # optional, same rules
$TicketMail = 'it1-service@example.com'   # recipient of the ticket e-mail: exactly one plain address
$TicketCc   = ''                    # optional second address (needs TicketMail)
# An empty value removes the registry value. All four values are always set, so a script of a new
# group replaces what a script of the old group set when a device moves to another group.

$ErrorActionPreference = 'Stop'
$key = 'HKLM:\SOFTWARE\SelfX\Support'    # below HKLM\SOFTWARE: only administrators can write, users can only read
$tag = '^[A-Za-z0-9._ -]{1,64}\z'
$mail = '^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,}\z'
$values = [ordered]@{ GroupTag = @($GroupTag, $tag); Category = @($Category, $tag); TicketMail = @($TicketMail, $mail); TicketCc = @($TicketCc, $mail) }
foreach ($name in $values.Keys) {
    $value = ("$($values[$name][0])").Trim()
    if ($value -and $value -notmatch $values[$name][1]) { Write-Output "$name has an invalid value."; exit 1 }
}
foreach ($name in $values.Keys) {
    $value = ("$($values[$name][0])").Trim()
    if ($value) {
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -LiteralPath $key -Name $name -Value $value -PropertyType String -Force | Out-Null
    } elseif (Test-Path -LiteralPath $key) {
        Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue
    }
}
Write-Output 'SelfX support values set.'
exit 0
```

### App Control for Business (WDAC)

SelfX does not need WDAC, and nothing of it is switched on in the package. If your organization
uses App Control for Business, you can use it in addition to prevent programs and scripts other
than the delivered SelfX ones from running on the devices. By default SelfX is allowed by hash;
for a package signed with the certificate of your company a signer rule is available
([Set up once instead of per version](#set-up-once-instead-of-per-version)).

1. **Base policy.** It belongs to your organization. It must allow supplemental policies (rule
   option 17) and allow the files signed by Microsoft, including
   `%ProgramFiles%\PowerShell\7\pwsh.exe` and the Intune agent.
2. **Build the package** (step 2).
3. **Create the supplemental policy**, in Windows PowerShell 5.1 on an administrator PC (module
   ConfigCI):

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXWdacPolicy.ps1 -BasePolicyId {GUID of the base policy}
   ```

   The script writes the XML and the `.cip` file to `build\wdac`. It contains hash rules for all
   programs, libraries and scripts of the package. It changes nothing on the PC. The wizard (`New-SelfXPackage.ps1`) runs this
   script for you when you give the ID of the base policy; the script then reads the package folder `package` of the result
   (folders `App`, `Config` and `Bin`) and the generated detection script (`-DetectionFile`), as Intune runs it.
4. **Deploy** with Intune (App Control for Business policy) to the same devices as the SelfX
   package. The policy must be on the device before the package.
5. **Audit mode first.** Whether the policies audit or enforce is decided by the base policy
   (rule option 3, "Audit Mode"). In audit mode everything keeps running, and Windows logs what
   would be blocked (log `Microsoft-Windows-CodeIntegrity/Operational`, event 3076). Check on a
   test device that no event is created for SelfX. Only then does the organization remove
   option 3.
6. **For every new version**, create the policy again and deploy it with the package, because
   every script change changes its hash. For staged rollouts, create the policy with
   `-PolicyId {new GUID}` per version and remove the old one when all devices are updated.

Notes: switch on rule option 19 ("Dynamic Code Security") only after a test in audit mode,
because SelfX scripts use `Add-Type`. A local administrator can replace an unsigned policy. The
template has not yet been tried on a device.

### Set up once instead of per version

With the default hash rules, AppLocker and App Control have to be replaced for every new version,
because every changed file has a new hash. For a package that is signed with the code signing
certificate of your company, **publisher rules** replace them: you create them once, and they stay
the same for every later version that is signed with the same certificate.

Requirements:

- The package is signed (trust mode signature, see
  [Optional: signed package](#optional-signed-package-trust-mode-signature) and
  [Architecture](Architecture.md#trust-modes-hash-and-signature)).
- The certificate chain of the signing certificate is trusted on the PC where you create the rules.
  A file whose signature Windows does not accept (changed after signing, certificate not trusted)
  stops both scripts; so does a file without signature (AppLocker) or a package whose `Install.ps1`
  is not signed (App Control).
- Windows PowerShell 5.1 (`powershell.exe`). For App Control also the module ConfigCI.

**AppLocker.** Give the script signed files of the package, separated by `|`: at least one program
and one script, for example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXAppLockerRules.ps1 -Mode Publisher -PathList "C:\Package\Bin\SelfXService.exe|C:\Package\Bin\SelfX.exe|C:\Package\Install.ps1" -OutputFile C:\Package\SelfX.AppLocker.Publisher.xml -RuleNamePrefix SelfX
```

- The script reads the publisher name from the signature (it is never a parameter) and writes
  **one publisher rule for each rule collection** (Exe, Dll, Script): Allow, for the SID `S-1-1-0`
  (Everyone), without product, file name or version range. No hash rules.
- All files must be signed by the same certificate. The rules have fixed IDs: a second run for the
  same publisher gives the same file.
- Take over the rules once and delete the hash rules of earlier SelfX versions. A new version signed
  with the same certificate needs no change. A renewed certificate with the same subject (same
  publisher name) needs none either; with another subject create the rules again, add them before
  the first package with the new certificate reaches the devices, and remove the old ones when all
  devices are updated.
- Without `-Mode` (or with `-Mode Hash`) the script writes hash rules as before; that stays the
  default for a package that is not signed.

**App Control for Business (WDAC).** Step 3 of [App Control for Business (WDAC)](#app-control-for-business-wdac)
with the additional parameter `-Level Publisher`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXWdacPolicy.ps1 -BasePolicyId {GUID of the base policy} -Level Publisher
```

- The policy contains a signer rule (certification authority and publisher name of the signing
  certificate, no version) instead of the hash rules. A file without signature gets a hash rule
  instead (fallback); with a fully signed package the policy contains no hash rule at all.
- The policy ID stays fixed. Deploy the policy once; a new signed version needs no new policy.
  Only when the signing certificate changes, create the policy again (during the change both
  certificates are in use: add `-AllowMultipleSigners`).
- The script stops before the scan for a file with an invalid signature, for files signed by
  different certificates (without `-AllowMultipleSigners`) and for a package whose `Install.ps1` is
  not signed (use the level Hash for it). After the scan it checks the policy: signer rules without
  file attribute, and no hash rule next to a signed file.
- The output lists the publishers that the policy trusts. Check that this is your signing
  certificate and nobody else.

What a publisher rule does **not** do:

- It trusts the **signer**, not a file or a version. Anyone who can sign with this certificate gets
  files allowed, so keep the key protected (smart card, HSM or a restricted signing host). To
  withdraw the trust, replace the certificate and the rules.
- It does not stop an older, still correctly signed SelfX version from running. The version bound
  comes from the file lists and, in the mode signature, from the checks of `Install.ps1` and of the
  service ([Architecture](Architecture.md#the-limit-local-administrator)).
- The limit for a local administrator stays: only App Control in enforce mode helps against them.

The scripts are covered by automatic tests; the generated policies have not yet been tried on a
device. Test them in audit mode first.

### Defender ASR: rule for executable files

If your devices use the attack surface reduction (ASR) rule **Block executable files from running unless they meet a prevalence,
age, or trusted list criterion** (ID `01443614-cd74-433a-b99e-2ecdc07bfc25`), Defender can block programs of SelfX. This section
explains the cause, how to find the blocked file and what you can do about it. It follows the documentation of Microsoft and the
way the package is built; **it has not been tried on a device on which the rule is active.**

**What the rule does.** It stops executable files (for example `.exe`, `.dll`, `.scr`) from starting unless they meet a trust
criterion. It needs cloud-delivered protection. The cloud protection of Microsoft decides from prevalence, age and a trusted list;
you cannot set these criteria. The user sees a notification, the rule creates no alert in the Defender portal ([ASR rules
reference](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference), [ASR
FAQ](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-faq)).

**Why SelfX can be affected.** `SelfXService.exe`, `SelfX.exe`, `SelfXWinRT.dll`, `SelfXAudio.dll` and `SelfXDisturb.dll` are built on your build machine (step 2.3) and
exist only on your devices. A program that Microsoft has not seen before may not meet the criteria, and the FAQ says that a new
version of an app can be blocked while it builds reputation. This is a conclusion from the way SelfX is built, not a statement of
Microsoft about SelfX.

**1. Find the blocked file.** Copy `tools\Get-SelfXAsrEvents.ps1` to the device and run it there (read only; elevated if the log
cannot be read otherwise):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-SelfXAsrEvents.ps1 -SelfXOnly
```

The script reads the events 1121 (rule fired in block mode) and 1122 (rule fired in audit mode) of the log `Microsoft-Windows-Windows
Defender/Operational` for this one rule and shows `Time`, `Mode` (`Block` or `Audit`), `File` (the blocked file),
`StartedBy` (the process that wanted to start it) and `InSelfXFolder`. Without `-SelfXOnly` it shows the events for all programs;
`-Days` (default 30) and `-MaxEvents` (default 100) limit the list. It changes nothing and shows no user name: it never reads the
fields `User` and the command lines, and the profile folder of a user in a path is shown as `<user>`. A path outside the local
profile folders is shown as the event reports it, so look at the output before you pass it on. In Defender for Endpoint the same
events are available in advanced hunting as `AsrUntrustedExecutableBlocked` and `AsrUntrustedExecutableAudited`.

No events can mean that the rule is off, that the file is excluded (excluded files write no events) or that nothing was blocked.
The names of the event fields (`ID`, `Path`, `Process Name`) are not described by Microsoft; they come from an example event. If
the script reports events that it could not assign to a rule, the layout of the events differs from that example.

**2. Audit mode first.** Set the rule to **Audit** on the pilot devices. The rule then writes event 1122 and blocks nothing. The
FAQ recommends audit mode for rules in general to find the programs that need an exclusion, and for this rule if you update apps
often.

**3. Exclude exactly the SelfX files, for this rule only.** In Intune open *Endpoint security > Attack surface reduction* and the
policy of the type *Attack surface reduction rules*. After the rule is set to Audit, Block or Warn, the setting **ASR Only Per Rule
Exclusions** appears for this rule ([configure ASR rules and
exclusions](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-configure)). Add only the files that
the events name, at most these five:

```
C:\Program Files\SelfX\App\SelfXService.exe
C:\Program Files\SelfX\App\SelfX.exe
C:\Program Files\SelfX\App\WinRT\SelfXWinRT.dll
C:\Program Files\SelfX\App\Audio\SelfXAudio.dll
C:\Program Files\SelfX\App\Disturb\SelfXDisturb.dll
```

- Do **not** exclude the folder `C:\Program Files\SelfX` and do not use a wildcard. Do **not** use the global setting *Attack
  Surface Reduction Only Exclusions*: it applies to every ASR rule on the device.
- If an event names another library of `App\WinRT` (the Windows SDK projection), exclude exactly that file, and only after you
  compared its SHA256 with `SelfX.Code.json`.
- The rule honors per-rule exclusions ([ASR rules overview](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-overview)).
  An exclusion applies only when the program starts: restart the service `SelfXService` or the device. Excluded files write no
  events, so the list of the script gets shorter after the exclusion; the proof is that the notification stops and SelfX starts.
- An exclusion lowers the protection. It applies to the path: another file at the same path would not be checked by this rule
  either. Users have only read and execute rights in the folder; the file lists, the file check of the service and, if you use
  them, AppLocker or App Control still protect the content. A local administrator can change both (see
  [Architecture](Architecture.md#the-limit-local-administrator)).

**4. Programs from the release.** The release workflow builds the programs once and delivers them inside the `.intunewin` of the
release (built with the settings of the repository, not with yours). Everybody who uses that file has the same programs. A package
with your own settings contains the programs of your own build; whether two builds on different machines give identical files is
not verified (the CI compares two builds on one runner). Only identical files can build up a shared reputation; Microsoft documents
no way to rely on it.

**5. Signing is no guarantee.** The documentation of Microsoft for this rule does not say that signed files pass. A signed package
(trust mode Signature) can therefore still be blocked, and there is no guarantee that signing solves the block: test your signed
package in audit mode. According to the ASR rules overview the rule honors indicators of compromise for files and certificates, so an
*Allow* indicator for the signing certificate in Defender for Endpoint is one more option. This was not tried with SelfX.

## Background: what the installation does

`Install.ps1` runs with administrator rights, in Intune as SYSTEM. It checks **right at the
start**, before it changes anything: Windows version, folder rights of PowerShell 7, the programs
in `Bin` (SHA256 manifest) and the file list. If something does not match, it ends with exit
code 1 and the existing installation stays unchanged. Then:

1. It stops and removes an existing `SelfXService`.
2. It empties `%ProgramFiles%\SelfX` (the folder itself stays) and creates two folders in it:
   `App` (code: programs, libraries, scripts and language files of the project, `Uninstall.ps1`,
   `SelfX.Code.json`) and `Config` (configuration: the settings files, `Branding`, your own
   scripts and language files, `SelfX.Config.json`). Users may only read and run there; SYSTEM
   and administrators have full control (the same rights as before).
3. It installs `SelfXService.exe` (the service) and `SelfX.exe` (a small starter without a
   console window that starts SelfX or the status icon with a hidden PowerShell 7) into `App`.
   It checks the installed files against both lists once more; besides `App` and `Config`
   nothing may be left in `%ProgramFiles%\SelfX`.
4. It registers and starts the service `SelfXService` (LocalSystem, automatic start, restart
   after a failure) and limits its rights.
5. It creates shortcuts on the public desktop and in the Start menu and an entry under Apps &
   features.
6. If `Show_Tray_Icon` = `True` (default), it creates the autostart `SelfXTray`. As SYSTEM the
   installer starts the status icon in every active user session with the normal rights of the
   user. With a manual installation it appears at the next sign-in.

An update does not fail when a user has SelfX open: the installer empties the folder instead of
deleting it and retries locked files for 20 seconds.

**Update from version 3.0.x (old layout).** Up to 3.0.x all files were directly in
`%ProgramFiles%\SelfX`. From 3.1.0 on the installer first removes that content completely and
then installs `App` and `Config`; there is no mixed state. An empty old folder that a running
program still uses as working folder may remain until the next sign-out; a file of the old
layout next to `App` and `Config` stops the installation (exit code 1). `Detection.ps1` of 3.1.0
does not detect the old layout, so Intune installs the update. The package itself has the
folders `App` and `Config` instead of `Sources`; build it with `tools\New-SelfXIntuneWin.ps1`
(the repository keeps the folder `Sources`).

### Logs

| Log | Location | Who can read it |
|---|---|---|
| Installation | `%ProgramData%\SelfX\Logs\Install.log` | administrators, SYSTEM |
| Service | `%ProgramData%\SelfX\Logs\SelfXService.log` (rotates at 5 MB to `.old`) | administrators, SYSTEM |
| Scripts | `%ProgramData%\SelfX\Logs` (one file per script and day) | administrators, SYSTEM |
| Window, status icon, user actions | `%ProgramData%\SelfX\Logs\Users\<SID>` | each user only their own folder |

Files older than `Log_Retention_Days` (default 90) are deleted automatically (see
[Logs and retention](Configuration.md#logs-and-retention)).

### Windows event log

The service writes security-relevant events to the *Application* log (source `SelfXService`) so
that Defender for Endpoint, Intune or a SIEM can evaluate them. The texts are fixed and contain
no request texts and no user names. For each event ID at most 10 entries in 10 minutes apply;
after that 4099 reports the number of skipped ones.

| ID | Level | Meaning |
|---|---|---|
| 4001 | Error | The pipe name already belongs to another process; the service accepts no connections until it is free. |
| 4002 | Warning | A request or connection was rejected (invalid, not allowed, limit). |
| 4003 | Warning | PowerShell 7 is not protected against changes by users; actions as SYSTEM are not started. |
| 4004 | Error | `%ProgramData%\SelfX` is not protected (link or foreign owner); the service writes nothing there until an administrator repairs it (reinstall SelfX). |
| 4005 | Error | Installed scripts or configurations do not match `SelfX.Code.json` and `SelfX.Config.json`; the service starts nothing. With `Service_FileCheck` = `Audit` only a warning. |
| 4006 | Error | The trust anchor `HKLM\SOFTWARE\SelfX\Trust` is missing, invalid or can be changed by an identity other than SYSTEM and Administrators; the service starts nothing. Install SelfX again. |
| 4007 | Error | Trust mode signature: an installed script or library has no valid signature of an allowed signer, or a signed catalog (`SelfX.Code.cat`, `SelfX.Config.cat`) is missing or does not match; the service starts nothing, also with `Service_FileCheck` = `Audit`. The SelfX log names the file and the reason. |
| 4008 | Warning | Terminal server (Windows Server, mode `TerminalServer`): a request for an action that is not classified `TerminalServer` = `Show` was refused. The SelfX log names the action. |
| 4009 | - | Not written any more: the mode comes from Windows and cannot differ from it. |
| 4099 | Warning | Further events of the same ID were not written (limit). |

### The file lists `SelfX.Code.json` and `SelfX.Config.json`

The package build writes the SHA256 of every installed file to one of two lists. `SelfX.Code.json`
holds the programs, libraries and the scripts, language files and images of the project;
`SelfX.Config.json` holds the settings files, everything below `Branding` and your own scripts and
language files. Every file is in exactly one list; a file in both lists, in none, or in the wrong
list is refused. The lists are created again with every build; you do not have to maintain
anything by hand. A changed company logo changes only `SelfX.Config.json`. Earlier versions had a
single list `SelfX.Files.json`; the installation replaces it.

- `Install.ps1` checks before and after copying that every file matches the list and that no
  file without an entry is in the package.
- The service checks before **every** start (action, health check, background check) that all
  listed files are unchanged, that no file without an entry is in the folder and that no link is
  in the way. On a deviation it starts nothing and writes event 4005.
- Before that, the service reads the trust anchor that `Install.ps1` wrote (event 4006 when it is
  missing, invalid or not protected). A device installed with `-TrustedSigner` additionally checks
  signatures before every start: the two lists against the signed catalogs, every listed script and
  library by its embedded signature, the settings files against `SelfX.Config.cat` (event 4007). The
  checked files stay open, and so unchangeable, until the script has ended. Revocation is checked
  from the local cache only, so the service does not wait on a device without a network
  ([Architecture](Architecture.md#the-mode-signature-in-the-service)).
- For the first rollout you can set `Service_FileCheck` to `Audit` (log only).
- The libraries `WinRT\*.dll` (Windows Update interface) `Audio\SelfXAudio.dll` (action "No
  sound on this PC") and `Disturb\SelfXDisturb.dll` (hint before disruptive actions) are also checked **when loaded** and kept open meanwhile, so that they cannot
  be replaced between the check and loading.
- Limit: the check detects accidents (broken or partial update) and a replaced `SelfX.exe`, but
  not an attacker with administrator rights. The folder rights and App Control help against
  that.

Which file belongs to which class, the split into the code list and the configuration list and the
planned trust modes are described in [Architecture](Architecture.md).

### Execution policy `-ExecutionPolicy Bypass`

The service, the starter, the window, the status icon and the health check start PowerShell with
`-ExecutionPolicy Bypass`. This is intended: the scripts are in the protected installation
folder, and the execution policy is not a security boundary anyway. The file list and App Control
provide protection.

If your group policy enforces `AllSigned`, `Bypass` has no effect. Then sign all SelfX scripts
(the files in `Sources`, all check and action scripts, also `Collect-DeviceLogs.ps1`) with a
trusted code signing certificate. There is no signing concept of its own.

### Service privileges

The service runs as LocalSystem. `Install.ps1` limits its token with `sc.exe privs` to the
required rights (`Service_Privileges` = `Restricted`, default). Dangerous rights such as
`SeTcbPrivilege`, `SeDebugPrivilege`, `SeCreateTokenPrivilege`, `SeLoadDriverPrivilege` and
`SeSecurityPrivilege` are then not held by the service.

| Right | Purpose |
|---|---|
| `SeChangeNotifyPrivilege` | every process |
| `SeImpersonatePrivilege` | check the pipe client |
| `SeCreateGlobalPrivilege` | global objects of the service |
| `SeShutdownPrivilege` | action Restart |
| `SeSystemtimePrivilege` | synchronize the time |
| `SeBackupPrivilege`, `SeRestorePrivilege`, `SeTakeOwnershipPrivilege` | file repairs (for example spooler) |
| `SeManageVolumePrivilege` | disk check |

Check: `sc.exe qprivs SelfXService`. If setting fails, `Install.ps1` only reports a warning
(Autopilot never fails because of it). `Service_Privileges` = `Default` keeps all rights and is
meant only for troubleshooting. Test every system action once on a test device before
deployment.

## Troubleshooting

| Message or situation | Meaning and solution |
|---|---|
| `The command dotnet was not found` | The .NET SDK 10 is missing, or the PowerShell window is older than the installation. Install the SDK and open a new window. |
| `The .NET SDK 10 is required, found '…'` | No SDK 10 is installed. With several SDKs, the `global.json` in the repository selects SDK 10 automatically. |
| `The offline feed folder … does not exist` or `SelfX.OfflineFeed.json is missing` | The folder `offline-feed` is missing or empty. Run the export on a computer with internet (section "Offline build") and copy the folder. |
| `… does not match its SHA512` or `… not listed in SelfX.OfflineFeed.json` | A package in the folder `offline-feed` was changed or added. Restore the folder from the repository or repeat the export. |
| `The offline feed was exported with .NET SDK …` | The build machine has another SDK version than the export. Install the same version or repeat the export with this version. |
| `NU1101` or `NU1102` during the build | A package is missing in the folder `offline-feed`. Repeat the export. |
| `The folder Bin is missing …` | Step 2.3 was not run before building the package. Repeat steps 2.3 and 2.5. |
| `Bin was not built from the current …` | A source file was changed after building. Repeat steps 2.3 and 2.5. |
| Installation ends with exit code 1 | The last line of `Install.log` names the reason. The existing installation stays unchanged. |
| `Trust mode Signature: … have no valid signature of an allowed signer` | A program or script of the package is not signed, was changed after signing, is signed by a certificate that is not in `-TrustedSigner`, or its certificate chain is not trusted on the device (reason in brackets: `NotSigned`, `HashMismatch`, `SignerNotAllowed`, `NotTrusted`). This message is not in `Install.log`: run the install command in an elevated console to read it. |
| `… is not a valid signed catalog …` | A file was changed, added or removed after the catalog was signed (the message names it), or the catalog is missing or signed by another certificate. Sign the package again. |
| `This device is in the trust mode Signature …` | The device was installed with `-TrustedSigner` and the install command has no such parameter. Add `-TrustedSigner`, or `-AllowHashMode` to change to an unsigned package on purpose. |
| `The package is signed … but -TrustedSigner was not given` | A signed package was installed without `-TrustedSigner`. Add the parameter to the install command. |
| `-TrustedSigner: every entry must be a SHA1 thumbprint …` | The value contains a space, another character or an empty entry. Use 40 hexadecimal characters per thumbprint and commas without spaces. |
| Intune does not detect SelfX after the update of this version | The trust anchor is missing (`Detection_<date>.log`: `trust anchor missing`). Intune installs the package again; afterwards the anchor exists. |
| Intune does not detect an update | `Version.txt` and `$ExpectedVersion` stayed the same, or you uploaded the copy from the repository instead of `build\SelfX-Service-<version>.Detection.ps1`. |
| Defender blocks a SelfX program (Defender notification, event 1121 for the rule `01443614-cd74-433a-b99e-2ecdc07bfc25`) | The ASR rule for executable files decided against the file. Find the file with `tools\Get-SelfXAsrEvents.ps1` and follow [Defender ASR: rule for executable files](#defender-asr-rule-for-executable-files). |
| SelfX starts no action | PowerShell 7.6 is missing (warning in `Install.log`), or event 4005 reports a deviating file. The SelfX log names the details. |
| SelfX starts no action, event 4006 | The trust anchor `HKLM\SOFTWARE\SelfX\Trust` is missing (installation of an earlier build), was changed, or its rights allow other identities than SYSTEM and Administrators to change it. Install the package again; `Install.ps1` writes the anchor with the correct rights. |
| SelfX starts no action, event 4007 | Device installed with `-TrustedSigner`: the SelfX log (`SelfXService.log`) names the file and the reason. `UntrustedRoot` or `Chaining`: the certificate chain of the signer is not (or no longer) trusted on the device. `Expired`: the certificate expired and the signature has no time stamp. `Revoked`: the certificate was revoked. `SignerNotAllowed`: the signer is not in `Signers` of the anchor (install again with the new thumbprint in `-TrustedSigner`). `NoSignature`, `BadDigest`, `NotInCatalogOrCatalogUnsigned`: a file was changed or is not signed; install the package again. |

## Deployment checklist

1. Configuration adjusted (branding, support contacts, features) and all XML files valid.
2. `Version.txt` and `$ExpectedVersion` are the same and new; history added in `Detection.ps1`.
3. All tests run without errors.
4. Programs built, AppLocker rules replaced (if used).
5. Package built; `.intunewin` **and** `…Detection.ps1` from `build` used.
6. PowerShell 7 set up as a Win32 app and as a dependency; requirement rule Windows 11 25H2
   set; neither SelfX nor PowerShell 7 blocks the ESP.
7. Checked on a test device (new installation, update, uninstall, standard user, Autopilot; if your tenant uses the ASR rule for
   executable files, also its events: [Defender ASR](#defender-asr-rule-for-executable-files)).
8. Deploy to a pilot group first, then broadly.
