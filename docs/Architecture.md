# Architecture: code, configuration and trust

**English** | [Deutsch](de/Architecture.md)

This document describes how the files of **SelfX Service** are divided into classes, which lists
record them, how a device decides to trust them and where the limits of that trust are. It is
written for administrators and reviewers.

> **Status.** Sections marked **Today** describe what is implemented: the files are divided into
> the lists `SelfX.Code.json` and `SelfX.Config.json` (see
> [Installation](Installation.md#the-file-lists-selfxcodejson-and-selfxconfigjson)). Sections
> marked **Target** describe the planned structure with the folder layout, the version in the
> code list and two trust modes. It is introduced in several steps; until then the behavior
> described as **Today** applies.

## Contents

1. [Overview](#overview)
2. [The three file classes](#the-three-file-classes)
3. [Assignment of every file](#assignment-of-every-file)
4. [The two lists](#the-two-lists)
5. [Trust modes: hash and signature](#trust-modes-hash-and-signature)
6. [The trust anchor](#the-trust-anchor)
7. [The limit: local administrator](#the-limit-local-administrator)
8. [Who checks what](#who-checks-what)
9. [Files whose class is open](#files-whose-class-is-open)
10. [Folder layout](#folder-layout)

## Overview

- Every file of the package belongs to **exactly one class**: *code*, *configuration* or
  *company code*.
- **Code** is built by the project and is the same for every company. **Configuration** is set by
  the administrator of the company and can change at any time. **Company code** is a script that
  the company adds itself.
- Two lists record the files: `SelfX.Code.json` (code) and `SelfX.Config.json` (configuration and
  company code). A new logo or a new support number changes only the second list.
- Two trust modes decide how the lists are proven: **hash** (no certificate needed) and
  **signature** (Authenticode, recommended when the company has a code signing certificate).
- The **trust anchor** (which signers are allowed) is not part of the package. It comes from the
  Intune command line.
- The checks protect against accidents and against changes by normal users. They do not protect
  against a **local administrator** (see [The limit](#the-limit-local-administrator)).

## The three file classes

| Class | Content | Changed by | Changes | Recorded in |
|---|---|---|---|---|
| **Code** | `SelfXService.exe`, `SelfX.exe`, all DLLs, all `*.ps1` of the project (`Install.ps1`, `Uninstall.ps1`, `Sources\*.ps1`, `Scripts_to_run`, `HealthChecks`), the bundled language files, the default images | the project (release) | with a program update or a .NET security update | `SelfX.Code.json` |
| **Configuration** | `Tool_Config.xml`, `Issues_List.xml`, `Health_Config.xml`, `Ticket_Config.xml`, `Network_Test_Config.xml`, `Branding\*`, text overrides | the administrator of the company (package wizard) | at any time, without a new release | `SelfX.Config.json` |
| **Company code** | own scripts in `Scripts_to_run` or `HealthChecks` that the catalog or `Health_Config.xml` names | the administrator of the company | rarely | `SelfX.Config.json`, verified like code |

Rules (**Target**):

1. A file belongs to exactly one class.
2. The assignment is defined in **one place** (function `Get-SelfXFileClass` in
   `tools\SelfXPackage.Common.ps1`). Package build, `Install.ps1`, tests and the service apply the
   same rule.
3. A file that no rule knows is an **error** (fail closed), not a default class.
4. Configuration contains no executable code. It only selects which listed script runs. The
   service starts a script as SYSTEM only when `Issues_List.xml` (`Context="System"`) or
   `Health_Config.xml` names it and the file is listed and unchanged.

Consequence: changing the logo, an address or the catalog changes only configuration files. The
code list stays byte-identical, and so do the AppLocker and App Control rules that are based on it.

## Assignment of every file

The tables show the package **SelfX Service** as it is built today by
`tools\New-SelfXIntuneWin.ps1`; the rule that gives every file its class is the function
`Get-SelfXFileClass` in `tools\SelfXPackage.Common.ps1`. Paths are relative to the
folder `SelfX Service` of the repository. "Installed as" is the path in the installation folder
(`%ProgramFiles%\SelfX`).

**Today**, the two lists together contain: every file below `Sources` (89 files), `Uninstall.ps1`, the
DLLs of `Bin\WinRT` (as `WinRT/<name>`), `Bin\Audio\SelfXAudio.dll` (as `Audio/SelfXAudio.dll`)
and the programs `SelfXService.exe` and `SelfX.exe` from `Bin`. Files named `Test-*.ps1` and the
folder `Service\Projects` are removed from the staging folder before packaging and are not
shipped.

### Programs and libraries (built by `tools\Build-SelfXBinaries.ps1`)

| Package path | Installed as | Class |
|---|---|---|
| `Bin\SelfXService.exe` | `SelfXService.exe` | Code |
| `Bin\SelfX.exe` | `SelfX.exe` | Code |
| `Bin\WinRT\*.dll` (`SelfXWinRT.dll` and the Windows SDK projection DLLs of the build) | `WinRT/<name>` | Code |
| `Bin\Audio\SelfXAudio.dll` | `Audio/SelfXAudio.dll` | Code |

### Folder `Sources` (installed unchanged into the installation folder)

| Package path | Class |
|---|---|
| `Sources\Branding.ps1`, `CopilotClipboard.ps1`, `CopilotFacts.ps1`, `CopilotPrompt.ps1`, `HealthStatus.ps1`, `Localization.ps1`, `SelfXAudio.ps1`, `SelfXDefender.ps1`, `SelfXDeviceSecurity.ps1`, `SelfXLog.ps1`, `SelfXNetwork.ps1`, `SelfXOffice.ps1`, `SelfXServiceClient.ps1`, `SelfXWinRT.ps1`, `SelfXWindows.ps1`, `SelfX_Tray.ps1`, `Self_X.ps1`, `SupportLinks.ps1`, `SupportReport.ps1`, `SystemInfo.ps1`, `TicketMail.ps1`, `TicketSend.ps1` (22 files) | Code |
| `Sources\Tool_Config.xml` | Configuration |
| `Sources\Issues_List.xml` (action catalog) | Configuration |
| `Sources\Health_Config.xml` | Configuration |
| `Sources\Ticket_Config.xml` | Configuration |
| `Sources\Network_Test_Config.xml` | Configuration |
| `Sources\Branding\company_logo.png` (placeholder, replaced by the wizard with the company logo) | Configuration |
| `Sources\Languages\ar.xml`, `bn.xml`, `de.xml`, `en.xml`, `es.xml`, `fa.xml`, `fr.xml`, `hi.xml`, `id.xml`, `it.xml`, `ja.xml`, `ko.xml`, `nl.xml`, `pl.xml`, `pt.xml`, `ru.xml`, `sw.xml`, `th.xml`, `tr.xml`, `uk.xml`, `ur.xml`, `vi.xml`, `zh-Hans.xml`, `zh-Hant.xml` (24 files) | Code |
| `Sources\HealthChecks\Check-Compliance.ps1` | Code. Its `$Require` settings are to move into configuration (**Target**); until then an edited copy no longer matches the code list |
| `Sources\Repair.ico`, `Sources\icon_systray.ico`, `Sources\logo.png` | Code (default images). Company images belong in `Sources\Branding\`; replacing a default image in place is not supported |
| `Sources\Scripts_to_run\Collect-DeviceLogs.ps1`, `SelfX_Apps_RetryInstall.ps1`, `SelfX_Audio_Restore.ps1`, `SelfX_Browser_ClearChromeCache.ps1`, `SelfX_Browser_ClearEdgeCache.ps1`, `SelfX_Browser_ClearFirefoxCache.ps1`, `SelfX_Citrix_RestartWorkspace.ps1`, `SelfX_Defender_QuickScan.ps1`, `SelfX_Defender_UpdateSignature.ps1`, `SelfX_Device_AirePlaneMode.ps1`, `SelfX_Device_BringWindowsBack.ps1`, `SelfX_Device_ClearCache.ps1`, `SelfX_Device_CollectLogs.ps1`, `SelfX_Device_DeviceSlow.ps1`, `SelfX_Device_GpUpdate.ps1`, `SelfX_Device_Restart.ps1`, `SelfX_Device_SyncTime.ps1`, `SelfX_Excel_NewInstance.ps1`, `SelfX_Excel_Reboot.ps1`, `SelfX_Intune_RestartService.ps1`, `SelfX_Office_ResetLicence.ps1`, `SelfX_OneDrive_CHKDSK.ps1`, `SelfX_OneDrive_Reboot.ps1`, `SelfX_OneDrive_Reset.ps1`, `SelfX_OneDrive_Run.ps1`, `SelfX_Outlook_CleanAutoComplete.ps1`, `SelfX_Outlook_Reboot.ps1`, `SelfX_Outlook_TeamsAddIn.ps1`, `SelfX_Poste_WSReset.ps1`, `SelfX_Teams_Reboot.ps1`, `SelfX_Teams_ResetCache.ps1`, `SelfX_Updates_Install.ps1`, `SelfX_Word_Reboot.ps1` (33 files) | Code |

The 89 files of `Sources` are: 22 + 5 + 1 + 24 + 1 + 3 + 33 from the rows above.

### Other files of the package

| Package path | Installed | Class |
|---|---|---|
| `Uninstall.ps1` | yes, listed | Code |
| `Install.ps1` | no | Code, not listed, **open** (item 1) |
| `Detection.ps1` | no (uploaded to Intune separately) | Code template, not listed, **open** (item 1) |
| `README.md`, `README.en.md` | no | not code, not listed, **open** (item 1) |
| `Service\SelfXService.cs`, `SelfXLauncher.cs`, `SelfXSessionStarter.cs`, `SelfXWinRT.cs`, `SelfXAudio.cs` | no | Code (sources of the programs), not listed, **open** (item 1) |
| `Bin\SelfXSessionStarter.dll` | no (loaded by `Install.ps1` only) | Code, not listed, **open** (item 1) |
| `Bin\SelfX.Binaries.json` | no | build record of the programs, not listed, **open** (item 1) |
| `SelfX.Code.json`, `SelfX.Config.json` | yes (written at build) | the two lists themselves; they list every other installed file, not themselves |

## The two lists

### Today: `SelfX.Code.json` and `SelfX.Config.json`

Each list is a JSON object with `ManifestVersion` (1) and `Files`; `SelfX.Code.json` also has
`ToolVersion`, `SelfX.Config.json` also has `BuiltUtc`. The code list has no build time, so the same
code always gives the same bytes. `Files` maps the
relative name of each file (forward slashes) to its SHA256. A name consists of letters, digits,
`_`, space, `.`, `(`, `)` and `-`, and every segment starts with a letter, digit or `_`; a segment
is never `.` or `..`.
The package build writes both lists, `Install.ps1` copies them into the installation folder, and
their two digests are embedded in the `Detection.ps1` that is uploaded to Intune. A package from
an earlier version has `SelfX.Files.json` instead; `Install.ps1` removes the old installation
folder contents before copying, so no old list is left behind (the service would report a
left-over one as a file without an entry).

**Which list a file belongs to.** `Get-SelfXFileClass` knows the files of the project by name.
Configuration are the five settings files, everything below `Branding`, and every other script in
`Scripts_to_run` and `HealthChecks` or language file in `Languages` that is not on the list of
the project (own actions, own checks, an own language). Every file that no rule knows stops the
build (fail closed). `Install.ps1` and the service do not know the list of names; they check
only that no file is in both lists or in none, that the code list holds no settings file or file
of `Branding`, and that the configuration list holds nothing but settings files, `Branding`
files, own scripts and own language files. So no program, library, `Uninstall.ps1` or script of
the project can be moved into the list that carries the files of the company. The test
`Test-FileManifest.ps1` keeps the list of names equal to the files of the repository: a new file
of the project has to be added to `$script:SelfXCodeFileNames`, otherwise the test fails.

**Digest of a list:** SHA256 over the lines `<name>=<SHA256 in upper case>`, sorted by name
(ordinal), joined by LF, UTF-8 without BOM. `Detection.ps1` and the build use the same function.

### Target: `SelfX.Code.json` and `SelfX.Config.json`

| | `SelfX.Code.json` | `SelfX.Config.json` |
|---|---|---|
| Lists | all files of class *code* | all files of class *configuration* and *company code* |
| Fields | `ManifestVersion`, `ToolVersion`, `Files` (no build time, so the file is reproducible) | `ManifestVersion`, `ConfigRevision` (UTC time of the wizard run), `MinCodeVersion` (only in a package that replaces the configuration alone), `Files` |
| `Files` | relative name → SHA256, same name rules as today | same |
| Written by | the release build (GitHub Actions); identical for every company | the package wizard, automatically; nobody edits it by hand |
| Changes when | the code changes | the configuration changes |
| Signature mode | rewritten by the wizard after the company has signed the code files | additionally covered by the signed catalog `SelfX.Config.cat` |

- Every file is in **exactly one** list. A file in both lists, or in none, is an error.
- `Install.ps1` contains no hash. It reads both lists, checks the package before it changes
  anything and checks the installed folder after copying.
- The service reads both lists and checks them before every start.
- `Detection.ps1` receives two values from the wizard: the code version and the digest of the
  configuration list. A new logo changes only the second value.
- `SelfX.Binaries.json` stays. It binds the programs to the C# sources they were built from.
- The version of the code is `ToolVersion` in `SelfX.Code.json`. **Today** it is `Tool_Version`
  in `Tool_Config.xml`, which is a configuration file; `Detection.ps1`, the release workflow and
  the package build read it there.

## Trust modes: hash and signature

The wizard lets the administrator choose the mode (**Target**).

| | Mode **Hash** (no certificate) | Mode **Signature** (recommended with a certificate) |
|---|---|---|
| Code | `SelfX.Code.json` from the release, unchanged | Authenticode signature in every `.exe`, `.dll` and `.ps1`; `Install.ps1` and the service check signature and signer |
| Configuration | `SelfX.Config.json` written by the wizard | additionally the signed catalog `SelfX.Config.cat` (XML and PNG files cannot carry an embedded signature) |
| AppLocker / App Control | hash rules, generated by the wizard | **one** publisher rule or signer rule; it stays the same for all versions |
| Work per update | automatic, but new rules have to be distributed | none |
| Proves | the package was not changed after it was built | the package comes from an allowed signer |

A hash proves integrity, not origin: anyone who can write the list can write matching hashes. A
signature binds the files to a signer that the device accepts.

Why a catalog (`.cat`) and not a separate signature file: `New-FileCatalog` and `Test-FileCatalog`
exist in Windows PowerShell 5.1 and in PowerShell 7, a catalog can be signed with any Authenticode
tool (certificate store, PFX file, smart card or HSM, Azure Artifact Signing), and Windows checks
it with the same function (`WinVerifyTrust`) as programs.

## The trust anchor

The anchor says which signers a device accepts (**Target**, mode signature).

- It is **not** taken from the package, because a package that carries its own anchor only proves
  itself. It comes from the Intune command line:
  `Install.ps1 -TrustedSigner <thumbprint>[,<thumbprint>]` (SHA1 thumbprints, 40 hexadecimal
  characters; anything else stops the installation). The wizard writes the line for copying.
- `Install.ps1` stores the anchor in `HKLM\SOFTWARE\SelfX\Trust`: `Mode` (`Hash` or `Signature`)
  and `Signers` (`REG_MULTI_SZ`). SYSTEM (`S-1-5-18`) and Administrators (`S-1-5-32-544`) have full
  control, users can only read. The service reads the anchor from there and starts nothing when
  non-administrators can write the key.
- It is a **list** of signers, not one thumbprint: a new certificate can be allowed before the
  switch, so a renewal does not stop the rollout.
- A signature counts only when its status is `Valid` (the certificate chain is trusted on the
  device) **and** the thumbprint of the signer is in the list. "Any valid signature" is not enough.
- Without `-TrustedSigner` the hash mode applies, as today. Changing from signature back to hash
  during an update needs the explicit switch `-AllowHashMode`.
- A time stamp (RFC 3161) keeps a signature valid after the certificate expires. The wizard asks
  for a time stamp server; offline networks can use an internal one.
- An invalid signature or a signer that is not in the list is a hard stop **before** anything on
  the device changes. This also holds during Autopilot.

## The limit: local administrator

A check by the service does **not** protect against a local administrator. An administrator can
replace `SelfXService.exe` or change the anchor in `HKLM`; the administrator has SYSTEM rights
anyway.

What the checks do protect against:

- wrong folder rights that a normal user could abuse,
- packages that were changed on the way to the device,
- swapped or outdated versions,
- operating errors (broken or partial update).

Protection against an administrator comes only from **App Control for Business (WDAC)** in enforce
mode. This is where the signature helps most: one signer rule replaces the hash rules of each
version. See [Installation](Installation.md#app-control-for-business-wdac).

## Who checks what

| Component | Runs as | Today | Target |
|---|---|---|---|
| `Install.ps1` | SYSTEM, started by Intune, Windows PowerShell 5.1 | compares the package with both lists before copying and the installed folder after copying | the same with both lists; in mode signature also the signatures and the signer |
| `SelfXService.exe` | SYSTEM | compares the installed folder with both lists before every start; no file without an entry and no link may be in the way (event 4005) | the same with both lists; in mode signature also the signature of the scripts and the catalog |
| `Detection.ps1` | Intune, Windows PowerShell 5.1 | version and the digests of both lists | code version and configuration digest, separately |
| SelfX window, status icon | the signed-in user | read only | read only |

Users cannot pass a path, a command, an argument or code to the service. The service starts only
scripts that the installed catalog lists with `Context="System"`.

`Tool_Config.xml` holds two settings that affect these checks: `Service_FileCheck` (`Enforce` or
`Audit`, read by the service) and `Service_Privileges` (read by `Install.ps1`). The service
accepts `Audit` only when the file list is intact, `Tool_Config.xml` is not among the differences
and the check was not cut off at its limit of 20 problems.

## Files whose class is open

The mapping above was checked against the files of the repository and against
`Get-SelfXFileClass`. These points cannot be settled without a further rule:

1. **Files outside the installed set:** `Install.ps1` verifies the lists, so it cannot be listed in
   a list it verifies. `Detection.ps1` is a template: the build replaces the placeholder
   `__SELFX_CODE_HASH__` and `__SELFX_CONFIG_HASH__`, so every package has its own copy. `README*.md`, `Service\*.cs`,
   `Bin\SelfXSessionStarter.dll` and `Bin\SelfX.Binaries.json` are shipped but not installed and
   are not in the lists today.
2. **Company files in project folders:** settled. The list of names of the project tells a
   project file from a company file in the same folder (see above).
3. **`Bin\WinRT\*.dll`:** the Windows SDK projection DLLs next to `SelfXWinRT.dll` are the output
   of `dotnet publish`. The folder `Bin` is not part of the repository, so their names cannot be
   listed here.

## Folder layout

**Target**, second stage. The first stage separates the files logically through the two lists; the
second stage separates them physically.

```
Package                                 Device (%ProgramFiles%\SelfX)
+- Install.ps1  Uninstall.ps1           +- Uninstall.ps1  SelfXService.exe  SelfX.exe
+- SelfX.Code.json                      +- SelfX.Code.json
+- App\    (code: Bin, Sources, ...)    +- App\      (code only)
+- Config\                              +- Config\   (configuration only)
    +- *.xml  Branding\  Texts\             +- SelfX.Config.json [+ .cat]
    +- SelfX.Config.json [+ .cat]       (rights as today: users read and execute only)
```

The service loads the catalog and `Health_Config.xml` only from `Config\` and scripts only from
`App\`. A script below `Config\` (company code) starts only when it is in `SelfX.Config.json` and
the catalog names it. An installation in the old layout is replaced completely by an update, with
no mixed state.
