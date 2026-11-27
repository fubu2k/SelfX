# Package wizard (guided configuration)

**English** | [Deutsch](de/Assistent.md)

The wizard `tools\New-SelfXPackage.ps1` walks you through the SelfX settings with questions and builds
the Intune package from your answers. Every question shows a **recommendation**. At the end it
explains briefly what to do in Intune. It runs on the build machine in Windows PowerShell 5.1 and
PowerShell 7, asks for no password and needs no network access (except to build the programs).

## Run it

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXPackage.ps1
```

Requirements as in the [installation guide](Installation.md): .NET SDK 10 (only to build the programs)
and `IntuneWinAppUtil.exe`. Download the file from Microsoft:
<https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool> (file `IntuneWinAppUtil.exe` in the repository,
preferably from the latest release tag). The wizard asks for the path of the file and checks the Microsoft signature.

| Parameter | Meaning |
|---|---|
| `-Language en` | Language of the wizard (`de`, `en`). Without it the wizard asks first, in English; English is preselected and the other languages are a numbered list. |
| `-AnswerFile <file>` | Uses saved answers and asks nothing (for updates and automation). |
| `-OutputFolder <folder>` | Default: `build\SelfX-Guided`. |
| `-ToolPath <file>` | Path of `IntuneWinAppUtil.exe`. |
| `-BuildBinaries` | Builds the folder `Bin` if it is missing. |
| `-ConfigureOnly` | Writes configuration, scripts and instructions only; nothing is built. |

## The questions

1. **Basics:** default language, language choice by users, organisation name, tool name.
2. **Support contacts:** shared mailbox, phone, hours, website, Teams.
3. **Branding:** logo (copied) and company color.
4. **Ticket by e-mail:** on or off, default recipient, subject marker. If **other organisations or
   locations** need other mailboxes, you define one **unit** per mailbox. The wizard asks about
   - **hybrid join:** SelfX then routes by **OU name** (for example `OU=Berlin`),
   - **Autopilot group tag (Entra ID):** the most reliable criterion for cloud-only devices,
   - **device class** (for example notebook, desktop, tablet) if another team handles tablets or kiosk PCs.

   SelfX runs on Windows 11 only. **SelfX cannot cover smartphones (iOS, Android).**
   The rules are written to `Ticket_Config.xml` in this order: group tags, then OUs, then device
   classes; the first matching rule wins.
5. **Copilot Chat and company wiki:** offer Copilot only if it is licensed; audience of the answer, clear
   the clipboard. Optionally a wiki button with an `https://` address and a name.
6. **Behavior on the device:** status icon, shortcuts. In expert mode: log retention, file check
   (`Enforce` or `Audit`) and service rights. Without expert mode the secure defaults stay.
7. **Build:** output folder and path of `IntuneWinAppUtil.exe`.

Every input is checked (addresses, https links, colors, lengths, characters); an invalid input is
refused at once. Values are written to the XML files as escaped text.

## Result

| File | Purpose |
|---|---|
| `SelfX-Service-<version>.intunewin` | The package for Intune. |
| `SelfX-Service-<version>.Detection.ps1` | The detection script. Upload **this** file. |
| `Set-SelfXSupportUnit-*.ps1` | Platform scripts for the ticket routing (per unit, group tag and device class). Units routed by OU only need none. |
| `SelfX-Intune-Guide.<language>.txt` | Short Intune instructions. |
| `selfx-answers.json` | Your answers for the next run. **Contains mailbox addresses: do not commit it.** |
| `package\` | The configured package (input of the packaging). |

The repository files are **not** changed. For an update raise `Version.txt` (in `SelfX Service`) and `$ExpectedVersion`
and run the wizard with `-AnswerFile`.

## What to do in Intune

The short instructions appear at the end of the run and in `SelfX-Intune-Guide.<language>.txt`. Details:
[installation guide](Installation.md#step-3-set-up-in-intune). The last step before the test also covers the Defender ASR rule for
executable files (how to find a blocked SelfX file and which files to exclude, at most four):
[Defender ASR: rule for executable files](Installation.md#defender-asr-rule-for-executable-files).

## Add a language to the wizard

Copy `tools\Wizard\Wizard.en.xml` to `Wizard.<culture>.xml`, set `Culture` and `Name` and translate the
texts. Missing texts appear in English. `tools\Test-SelfXPackageWizard.ps1` checks Ids and placeholders.
