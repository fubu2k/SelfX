# Package wizard (guided configuration)

**English** | [Deutsch](de/Assistent.md)

The wizard `tools\New-SelfXPackage.ps1` walks you through the SelfX settings with questions and builds
the Intune package from your answers. Every question shows a **recommendation**. At the end it
explains briefly what to do in Intune. It runs on the build machine in Windows PowerShell 5.1 and
PowerShell 7 and needs no network access. It asks for a password only when you sign with a PFX file (see
[Signing](#sign-the-package-trust-mode-signature)).

After the last answer the wizard builds everything **in one run, without further questions**: it checks the files, writes your
settings and the logo, signs (optional), packs, writes the detection script, the AppLocker and App Control files, the scripts for
Intune and the instructions. The result replaces the output folder only when every step worked: an error leaves no half-finished folder
and an earlier result stays as it was. The same run is available to other programs as the function `Invoke-SelfXPackageBuild`
(`tools\Wizard\SelfXWizard.ps1`): answers, payload folder, output folder, tool path, optional certificate and a callback for the progress.

## The window (recommended)

`tools\Start-SelfXPackageWizard.cmd` opens the wizard as a window in the style of SelfX. Double-click it in the unpacked payload
archive (or in the repository). It starts Windows PowerShell 5.1 with `-NoProfile -STA`; PowerShell 7 works as well
(`pwsh -NoProfile -STA -File .\tools\Wizard\SelfXWizardGui.ps1`). No administrator rights are needed.

| Page | What you set |
|---|---|
| Language | Language of the wizard (de, en) and the default language of SelfX on the devices |
| Basics | Name of your organisation and of the tool |
| Support | E-mail address, phone, hours, website and Teams contact of the support |
| Branding | Logo (file dialog, preview) and company color; the window shows the color at once |
| Ticket | Ticket e-mail and, for several organisations, one mailbox per organisation, chosen by group tag, OU or device class |
| Further settings | Copilot Chat, company wiki, status icon, shortcuts, expert settings, AppLocker and App Control (recommended values preset) |
| Summary | Your answers, the package folder, the output folder, `IntuneWinAppUtil.exe`, "only write the configuration" |
| Build the Intune package | One click; a list shows every step; **Cancel** stops the build, the output folder stays unchanged |
| Result | Files, **Open folder**, **Copy instructions** and the instructions for Intune |

![Package wizard window: Branding page with logo preview and company color](images/selfx-wizard-branding-en.png)

- Every value is checked as you type, with the same rules as the console; the error is shown at the field and **Next** stays on the
  page until the marked fields are correct.
- **Load answers** reads a `selfx-answers.json` (an answer with an unknown name is refused), **Save answers** writes one. The file
  never contains a password or a key.
- The build runs in the background: the window stays usable. The result is the same as `New-SelfXPackage.ps1` with the same answers.
- Keyboard: Tab moves through the fields, Enter is **Next**, the underlined letters work with Alt. Screen readers read the name of every
  field, its recommendation and its error.
- The window follows the light or dark mode of Windows and uses the colors and styles of SelfX.
- Not yet in the window: signing (trust mode Signature; use the console with `-CertificateThumbprint` or `-PfxPath`) and the network
  targets of the connection test.

![Package wizard window: build with the progress list](images/selfx-wizard-build-en.png)

![Package wizard window: result with the instructions for Intune](images/selfx-wizard-result-en.png)

The console version below stays for automation (answer file) and for signing.

## Run it

The best starting point is the **payload archive** of a release (`SelfX-Service-<version>-payload.zip`, see the
[installation guide](Installation.md#step-2-build-the-package)). Unpack it into an empty folder and start the wizard from there; the
.NET SDK is **not** needed, because the archive contains the programs. The files are checked against `App\SelfX.Code.json` first: a
changed or added file stops the run.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXPackage.ps1
```

In the repository the wizard works on the package folder `SelfX Service` and needs the folder `Bin` (`-BuildBinaries` builds it, with
the .NET SDK 10). You need `IntuneWinAppUtil.exe`. Download the file from Microsoft:
<https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool> (file `IntuneWinAppUtil.exe` in the repository,
preferably from the latest release tag). The wizard asks for the path of the file and checks the Microsoft signature.

| Parameter | Meaning |
|---|---|
| `-Language en` | Language of the wizard (`de`, `en`). Without it the wizard asks first, in English; English is preselected and the other languages are a numbered list. |
| `-AnswerFile <file>` | Uses saved answers and asks nothing (for updates and automation). |
| `-OutputFolder <folder>` | Default: `build\SelfX-Guided` in the repository, `SelfX-Guided` next to the unpacked payload archive. The folder must be new, empty or the result of an earlier run. |
| `-ToolPath <file>` | Path of `IntuneWinAppUtil.exe`. |
| `-PayloadFolder <folder>` | A folder in the layout of the unpacked payload archive. Default: the unpacked archive that contains `tools`, otherwise the repository. |
| `-BuildBinaries` | Only in the repository: builds the folder `Bin` if it is missing. |
| `-ConfigureOnly` | Writes configuration, scripts and instructions only; nothing is packed or signed. |
| `-CertificateThumbprint <thumbprint>` | Trust mode Signature: signs with this code signing certificate from the certificate store. |
| `-PfxPath <file>` | Trust mode Signature: signs with a PFX file. The wizard asks for the password (hidden, never stored). |
| `-TimestampServer <address>` | Time stamp service (`http` or `https`) for the signatures. Recommended. |

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
7. **AppLocker and App Control:** whether to create AppLocker rules (default yes) and, if you use App Control for Business (WDAC), the
   ID of your base policy. Without an ID no App Control file is written. The rule scripts need Windows PowerShell 5.1; AppLocker also the
   AppLocker cmdlets, App Control the module ConfigCI. Without them the run stops with a clear text: answer *no* or create the files on
   another PC (`tools\New-SelfXAppLockerRules.ps1`, `tools\New-SelfXWdacPolicy.ps1`).
8. **Build:** output folder and path of `IntuneWinAppUtil.exe`.

Every input is checked (addresses, https links, colors, lengths, characters); an invalid input is
refused at once. Values are written to the XML files as escaped text. The logo must be a `png`, `jpg` or `ico` file of at most 2 MB; the
wizard checks the **first bytes of the file**, not only the extension, and stores it as `logo.<type>`. The answers never contain a
password or a key: a name that is no question is refused.

## Sign the package (trust mode Signature)

Without a certificate the package is built in the trust mode **Hash** (no signature; `SelfX.Code.json` is the one of the release). With
`-CertificateThumbprint` or `-PfxPath` the wizard builds a **signed** package in the order that the file lists need: it signs every
program and script, writes `Bin\SelfX.Binaries.json` and `App\SelfX.Code.json` again with the new hashes, makes the signed catalog
`SelfX.Code.cat` of everything outside `Config`, then writes `Config\SelfX.Config.json` and the signed catalog
`Config\SelfX.Config.cat`. The detection script for Intune is signed too, the AppLocker rules are one publisher rule per rule collection and
the instructions show the install command with `-TrustedSigner <thumbprint>`. Details and the way back:
[Set up once instead of per version](Installation.md#set-up-once-instead-of-per-version).

A signed run needs a certificate that is valid for code signing, has a private key and is trusted on the build PC. The password of a PFX
file is read as a secure string, used once and never written to a file, a log, `selfx-answers.json` or an error message. Keep the
certificate protected: whoever has it can sign files that SelfX accepts.

## Result

| File | Purpose |
|---|---|
| `SelfX-Service-<version>.intunewin` | The package for Intune. |
| `SelfX-Service-<version>.Detection.ps1` | The detection script. Upload **this** file. |
| `Set-SelfXSupportUnit-*.ps1` | Platform scripts for the ticket routing (per unit, group tag and device class). Units routed by OU only need none. |
| `SelfX-Intune-Guide.<language>.txt` | Short Intune instructions. |
| `selfx-answers.json` | Your answers for the next run. **Contains mailbox addresses: do not commit it.** |
| `SelfX.AppLocker.xml` | AppLocker rules (hash rules, or one publisher rule for a signed package). Only with the answer *yes*. |
| `AppControl\` | The App Control (WDAC) supplemental policy as `.xml` and `.cip`. Only with a base policy ID. |
| `package\` | The configured package (input of the packaging). |

The payload and the repository files are **not** changed. For an update unpack the payload archive of the new release and run the wizard
with `-AnswerFile`. In the trust mode Hash, `App\SelfX.Code.json` of the result is the one of the payload, run after run.

## What to do in Intune

The short instructions appear at the end of the run and in `SelfX-Intune-Guide.<language>.txt`. Details:
[installation guide](Installation.md#step-3-set-up-in-intune). The last step before the test also covers the Defender ASR rule for
executable files (how to find a blocked SelfX file and which files to exclude, at most four):
[Defender ASR: rule for executable files](Installation.md#defender-asr-rule-for-executable-files).

## Add a language to the wizard

Copy `tools\Wizard\Wizard.en.xml` to `Wizard.<culture>.xml`, set `Culture` and `Name` and translate the
texts. Missing texts appear in English. `tools\Test-SelfXPackageWizard.ps1` checks Ids and placeholders.
