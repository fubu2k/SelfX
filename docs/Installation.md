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
  newer**.
- Always deploy the **whole package**, never single files.
- The version number `Tool_Version` and the value `$ExpectedVersion` in `Detection.ps1` must
  be **the same**. Otherwise Intune does not detect the update.
- If PowerShell 7 is missing, SelfX is still installed. This keeps Autopilot undisturbed.

## Requirements

**On the devices:**

| Requirement | Details |
|---|---|
| Windows 11 25H2 (build 26200) or newer, 64-bit | On older versions the installer stops before it changes anything. |
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

> **Easier with the wizard:** `tools\New-SelfXPackage.ps1` asks questions with recommendations, builds the package
> and explains the steps in Intune. See [Package wizard](Guided-Setup.md). The steps below show the manual way.

Repeat this step for every new version. Open PowerShell in the folder of the repository.

1. **Adjust the settings.** Branding, support contacts and features are in
   `SelfX Service\Sources\Tool_Config.xml` (see [Configuration](Configuration.md)).
2. **Check the version number.** For a new release, enter the same number in two places:
   - `Tool_Version` in `Sources\Tool_Config.xml`
   - `$ExpectedVersion` in `Detection.ps1`

   The packaging script stops if the two values differ.
3. **Build the programs.** The command creates the folder `SelfX Service\Bin`:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1
   ```

   At the end the script shows the built files with their hash. The build needs no internet:
   all NuGet packages come from the folder `offline-feed` and are checked against
   `SelfX.OfflineFeed.json` first (see "Offline build" below).
4. **Adjust AppLocker** (only if you use AppLocker). The script writes
   `build\SelfX.AppLocker.xml`. Take over these rules and delete the rules of the previous
   version before the package reaches the devices.
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

**Alternative: release on GitHub.** After the merge, set the tag `v<Tool_Version>` (for example
`v3.0.0`) on `main`. The workflow `.github/workflows/release.yml` builds the programs, the
`.intunewin`, a bill of materials (SBOM) and `SHA256SUMS.txt` and creates a **draft** under
*Releases*. It publishes nothing. Check the hashes and publish the draft only afterwards. The
workflow stops if the tag and `Tool_Version` do not match.

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

The detection reports "installed" only if the version, the registered service **and** the file
list match. So an update with changed files but the same version number is also detected.

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
2. Raise `Tool_Version` and `$ExpectedVersion` to the same new value.
3. Build the programs and the package again (step 2) and replace the AppLocker rules.
4. Upload the new `.intunewin` **and** the new detection script to the same Intune app.
5. Before packaging, check the support contacts in `Tool_Config.xml` and `Health_Config.xml`
   (see [Configuration](Configuration.md)).

**Update from SelfX 2.6.9 (upstream):** In addition the devices need Windows 11 25H2 and
PowerShell 7.6 (step 3). The package must be built again with the .NET SDK 10; the old method of
compiling the service on the device no longer exists. Also replace the AppLocker rules. The
default language of the interface is now German (`Tool_Language` = `de`). All changes are in
the [changelog](../CHANGELOG.en.md).

## Uninstall

`Uninstall.ps1` removes the service, `%ProgramFiles%\SelfX`, the shortcuts, the entry under Apps
& features, the autostart of the status icon, the status cache and the reports. Open SelfX
windows and status icons are closed first. If another program keeps a file open, the uninstaller
tries again for up to 90 seconds.

- The logs are kept. With `-RemoveLogs`, `%ProgramData%\SelfX` is deleted as well.
- Settings of single users (`HKCU\Software\SelfX`, `%LOCALAPPDATA%\SelfX`) are not removed.
- The result is in `%ProgramData%\SelfX\Logs\Uninstall.log`.

## Optional building blocks

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
than the delivered SelfX ones from running on the devices. SelfX stays unsigned and is allowed
by hash.

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
   programs, libraries and scripts of the package. It changes nothing on the PC.
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

## Background: what the installation does

`Install.ps1` runs with administrator rights, in Intune as SYSTEM. It checks **right at the
start**, before it changes anything: Windows version, folder rights of PowerShell 7, the programs
in `Bin` (SHA256 manifest) and the file list. If something does not match, it ends with exit
code 1 and the existing installation stays unchanged. Then:

1. It stops and removes an existing `SelfXService`.
2. It empties `%ProgramFiles%\SelfX` (the folder itself stays) and copies `Sources` and
   `Uninstall.ps1` into it. Users may only read and run there; SYSTEM and administrators have
   full control.
3. It installs `SelfXService.exe` (the service) and `SelfX.exe` (a small starter without a
   console window that starts SelfX or the status icon with a hidden PowerShell 7). It checks
   the installed files against the list once more.
4. It registers and starts the service `SelfXService` (LocalSystem, automatic start, restart
   after a failure) and limits its rights.
5. It creates shortcuts on the public desktop and in the Start menu and an entry under Apps &
   features.
6. If `Show_Tray_Icon` = `True` (default), it creates the autostart `SelfXTray`. As SYSTEM the
   installer starts the status icon in every active user session with the normal rights of the
   user. With a manual installation it appears at the next sign-in.

An update does not fail when a user has SelfX open: the installer empties the folder instead of
deleting it and retries locked files for 20 seconds.

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
- For the first rollout you can set `Service_FileCheck` to `Audit` (log only).
- The libraries `WinRT\*.dll` (Windows Update interface) and `Audio\SelfXAudio.dll` (action "No
  sound on this PC") are also checked **when loaded** and kept open meanwhile, so that they cannot
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
| Intune does not detect an update | `Tool_Version` and `$ExpectedVersion` stayed the same, or you uploaded the copy from the repository instead of `build\SelfX-Service-<version>.Detection.ps1`. |
| SelfX starts no action | PowerShell 7.6 is missing (warning in `Install.log`), or event 4005 reports a deviating file. The SelfX log names the details. |

## Deployment checklist

1. Configuration adjusted (branding, support contacts, features) and all XML files valid.
2. `Tool_Version` and `$ExpectedVersion` are the same and new; history added in both files.
3. All tests run without errors.
4. Programs built, AppLocker rules replaced (if used).
5. Package built; `.intunewin` **and** `…Detection.ps1` from `build` used.
6. PowerShell 7 set up as a Win32 app and as a dependency; requirement rule Windows 11 25H2
   set; neither SelfX nor PowerShell 7 blocks the ESP.
7. Checked on a test device (new installation, update, uninstall, standard user, Autopilot).
8. Deploy to a pilot group first, then broadly.
