# Changelog

**English** | [Deutsch](CHANGELOG.md)

This log describes what changed in this fork ([fubu2k/SelfX](https://github.com/fubu2k/SelfX))
compared with its upstream [wbaeck/SelfX](https://github.com/wbaeck/SelfX) at SelfX Service
2.6.9. Everything up to version 2.6.9 comes from the upstream and is not listed here as new.
The history of each file is in its header.

The package version is the one line of `SelfX Service\Version.txt`; the build writes it into `SelfX.Code.json`
(`ToolVersion`). `Detection.ps1` must contain the same value, otherwise Intune does not detect the update
(the packaging script checks this). A release gets the tag `v<version>` (for example
`v3.0.0`); the release workflow checks that the tag and `Version.txt` match.

## Unreleased (SelfX Service)

- **Package wizard as a window (`tools\Start-SelfXPackageWizard.cmd` 1.0.0, `tools\Wizard\SelfXWizardGui.ps1` 1.0.0, `tools\Wizard\SelfXWizardGui.xaml`, `tools\Wizard\Wizard.en.xml`/`Wizard.de.xml` 1.3.0, `tools\Wizard\SelfXWizard.ps1` 3.1.2, `tools\New-SelfXPackage.ps1` 1.1.1, `tools\SelfXRelease.Common.ps1` 3.1.1):** The package wizard has a WPF window in the style of SelfX. Pages: language, basics, support, branding (logo with preview, company color shown at once), ticket (several organisations with one mailbox each, by group tag, OU or device class), further settings, summary with the build settings, build with a progress list and cancel, result with the files and the instructions for Intune. Every value is checked as it is typed with the checks of the console (`ConvertTo-WizardValue`, `Test-WizardUnitValues`, the logo check `Read-WizardLogo`); the error is shown at the field and the next page opens only without errors. The answers are the same object the console makes from an answer file (`Test-WizardAnswerSet`); the build is `Invoke-SelfXWizardBuild` in a background runspace (the window stays usable; cancel works until the result is written). Answers can be loaded and saved (`selfx-answers.json`, never a password or a key; unknown answers refused, at most 1 MB). Texts only from `Wizard.<culture>.xml` (de and en complete). Keyboard (Tab, Enter, access keys) and names, recommendations and errors for screen readers (UI Automation). The styles are read from `Sources\Self_X.ps1` (parsed, not run) and the colors from `Sources\Branding.ps1`; light or dark follows Windows. Signing and the network targets are not in the window yet (console). Start: `tools\Start-SelfXPackageWizard.cmd` (Windows PowerShell 5.1, `-NoProfile -STA`), it is part of the payload archive. The console version stays for automation; it now uses the shared functions `Get-WizardBuildDefaults` and `Invoke-SelfXWizardBuild` (same behavior). Fix: several Intune platform scripts are listed one per line in the instructions (they were joined into one line). Tests: new `tools\Test-SelfXWizardGui.ps1` in PowerShell 7 and Windows PowerShell 5.1 (CI: now eleven tests in the 5.1 job): text ids of every page in de and en, every console question on exactly one page, styles from Self_X.ps1 and negative cases, XAML in light and dark, checks at the field (e-mail, header injection, script address, logo, colour, units), answers of the window identical to the console and the same files of a build with `-ConfigureOnly`, answer files, cancel. Screenshots in `docs\images\selfx-wizard-*`. Tried on a PC with the test script and the window; a real `IntuneWinAppUtil.exe` run from the window, a screen reader and a run from a real release archive were not tried.

- **Package wizard builds in one run (`tools\Wizard\SelfXWizard.ps1` 3.1.1, `tools\New-SelfXPackage.ps1` 1.1.0, `tools\SelfXPackage.Common.ps1`, `tools\New-SelfXWdacPolicy.ps1` 1.2.0):** The new function `Invoke-SelfXPackageBuild` (answers, payload folder, output folder, tool path, optional certificate and time stamp server, progress callback with step id and text) does a whole package build without a question: it checks the answers, the tool and the certificate, copies the package part of the unpacked payload archive, checks the copy against `App\SelfX.Code.json`, `Bin\SelfX.Binaries.json` and `Detection.ps1`, writes the settings and the logo, optionally signs every program and script (trust mode Signature), writes `SelfX.Binaries.json`, `SelfX.Code.json`, `SelfX.Code.cat`, `SelfX.Config.json` and `Config\SelfX.Config.cat` in the order the file lists need, packs with `IntuneWinAppUtil.exe` (Microsoft signature checked), writes the detection script with the digests (signed in the mode Signature), the AppLocker rules (hash or publisher) and, with a base policy ID, the App Control (WDAC) supplemental policy, the platform scripts, the instructions and `selfx-answers.json`. Everything is built in a work folder next to the output folder and replaces the output folder in one move: an error leaves no half-finished output and an earlier result stays. An output folder with foreign content, inside the payload, or a payload with a changed, added or unknown file, an old layout or a signature already is refused. In the mode Hash `SelfX.Code.json` of the result is the one of the payload. `selfx-answers.json` never contains a password or a key (an unknown answer name stops the run). Logo: only `png`, `jpg`, `ico` (file header checked, at most 2 MB, file read once, stored as `logo.<type>`); `bmp` and `gif` are no longer accepted. New answers `AppLockerRules` and `WdacBasePolicyId`; the instructions name `-TrustedSigner`, the rule files and the way back (`-AllowHashMode`). `New-SelfXPackage.ps1` only asks and calls the function; it works on the unpacked payload archive without the .NET SDK (in the repository `-BuildBinaries` stays possible) and has the new parameters `-PayloadFolder`, `-CertificateThumbprint`, `-PfxPath` (the password is asked for as a secure string and never stored) and `-TimestampServer`. `New-SelfXWdacPolicy.ps1` reads the package layout `App`/`Config` and has `-DetectionFile`. Tests: `tools\Test-SelfXPackageWizard.ps1` (complete run with a dummy for `IntuneWinAppUtil.exe`, abort in the middle, second run, changed payload, logo check, secret in the answers; the signed run only with a trusted test root). The new wizard texts exist in `de` and `en` only (the wizard has no other language files). Tried with the test script in PowerShell 7 and Windows PowerShell 5.1 on a PC; the signed run, the AppLocker and App Control scripts in the wizard and a real `IntuneWinAppUtil.exe` run were not tried on a device.

- **Repository front page (`README.md`, `README.de.md`):** short description of SelfX, badges (CI, release, license), a step-by-step download and hash check, and the version 3.1.0. Documentation only; no change to the programs, scripts or the package. Not tried on a device.

- **Release workflow: payload archive, release notes, automatic publishing (`.github\workflows\release.yml`, `tools\SelfXRelease.Common.ps1`
  3.1.0):** A version tag now builds, besides the Intune package (`.intunewin`), its detection script, the SBOM and `SHA256SUMS.txt`, the
  **payload archive** `SelfX-Service-<version>-payload.zip`: the package folder as it is packed (`Install.ps1`, `Uninstall.ps1`,
  `Detection.ps1`, `Bin`, `App` with `SelfX.Code.json`, `Config` with the default configuration and `SelfX.Config.json`, `Service`), the
  package assistant and the scripts it calls (`tools\Wizard`, `New-SelfXPackage.ps1` and the tools below it), `LICENSE.md`, `NOTICE.md` and
  `NOTICE.en.md`. The archive is reproducible (names in ordinal order, fixed time stamp). A link, a name outside the allowed characters, a
  name twice and a missing required file stop the build. A new file of the assistant has to be added to the list in
  `SelfXRelease.Common.ps1`; the test fails until it is. `New-SelfXIntuneWin.ps1` has the new parameter `-PayloadFile` and writes the
  archive from the same package folder that goes into the `.intunewin`. The **release notes** are the section of the version in
  `CHANGELOG.en.md` (an error when it is missing, doubled or empty) plus the fixed block "Files and how to verify" (file table, a PowerShell
  command that checks `SHA256SUMS.txt`, and the command for the build provenance). `SHA256SUMS.txt` covers all release files. **The release
  is published automatically** when, in the same run, all tests of the CI workflow passed for the tagged commit (`service-ci.yml` has the
  new trigger `workflow_call`; `release.yml` calls it) and the files were checked against `SHA256SUMS.txt` (exactly the five release files,
  format and every hash). The release is created as a draft first and published after the upload; if a step fails, no release is left.
  The repository variable `RELEASE_DRAFT=true` creates a draft instead, and `RELEASE_ATTEST=false` turns off the optional build
  provenance of the payload archive (`actions/attest-build-provenance`; only that job gets the rights `id-token` and `attestations`).
  Unchanged: the workflow starts only on version tags, the token that can write releases is used in the last step of the last job only
  (it runs no code of the repository), no secret is used, all actions are pinned to a commit SHA (new: `actions/upload-artifact` 7.0.2,
  `actions/download-artifact` 8.0.2, `actions/attest-build-provenance` 4.2.2). A release that already exists is never touched. New test
  `tools\Test-SelfXRelease.ps1` (notes from the changelog with the negative cases and the check command of the notes, payload archive with
  negative cases and manipulated archives, checksum file, structure of both workflows, docs), added to both test jobs of the CI. Docs:
  docs/Installation.md, "Alternative: release on GitHub", with the steps to try the workflow without a release. The workflow itself has
  not run on GitHub yet.

- **Defender ASR rule for executable files: diagnosis and exclusion (`tools\Get-SelfXAsrEvents.ps1` 3.1.0):** If the ASR rule "Block
  executable files from running unless they meet a prevalence, age, or trusted list criterion" (`01443614-cd74-433a-b99e-2ecdc07bfc25`)
  is active, Defender can block programs of SelfX. New read-only script `Get-SelfXAsrEvents.ps1` (Windows PowerShell 5.1 and PowerShell 7)
  reads the events 1121 (block mode) and 1122 (audit mode) of `Microsoft-Windows-Windows Defender/Operational` for this one rule and shows
  time, mode, blocked file, starting process and whether the file is in the SelfX program folder (`-SelfXOnly`, `-Days`, `-MaxEvents`).
  The log, the rule and the fields are fixed in the script (no parameter names a log, a computer or a file). It changes nothing, never reads
  the fields `User` and the command lines, shows the profile folder of a user as `<user>`, reads event XML without DTD and reports events
  that it cannot assign to a rule instead of hiding them. Docs: docs/Installation.md, "Defender ASR: rule for executable files" (cause,
  how to find the file, audit mode, per-rule exclusion for at most the four SelfX files `SelfXService.exe`, `SelfX.exe`, `SelfXWinRT.dll`
  and `SelfXAudio.dll`, not the folder and not the global exclusion, programs of the release, signing is no guarantee; sources: Microsoft
  Learn "ASR rules reference" and "ASR FAQ"). The Intune instructions of the package wizard get four new texts (`guide.asr`, `guide.asr1`
  to `guide.asr3` in `Wizard.de.xml` and `Wizard.en.xml`, language files 1.1.0) and one more step before the test step. New test
  `tools\Test-SelfXAsrEvents.ps1` (synthetic events instead of the log: only this rule, Block and Audit, unreadable events, DTD and
  entity, no user name, control characters, limits, errors of the log, read-only commands only, texts of the docs and the wizard), added to
  both test jobs of the CI. The event field names come from an example event, not from the documentation of Microsoft. Not tried on a
  device on which the rule is active.
- **Publisher rules for AppLocker and App Control (`tools\New-SelfXAppLockerRules.ps1` 1.1.0, `tools\New-SelfXWdacPolicy.ps1` 1.1.0):**
  For a package signed with the certificate of the company the rules no longer change with every version. `New-SelfXAppLockerRules.ps1
  -Mode Publisher` reads the publisher from the signature of the given files (all must be signed with status `Valid` by the same
  certificate; never a parameter) and writes **one publisher rule for each rule collection** (Exe, Dll, Script): Allow, SID `S-1-1-0`,
  no product, file name or version range, fixed rule IDs, no hash rules. `New-SelfXWdacPolicy.ps1 -Level Publisher` creates the
  supplemental policy with `New-CIPolicy -Level Publisher -Fallback Hash`: a signer rule of the signing certificate instead of hash
  rules, hash rules only for files without signature, fixed policy ID as before. Before the scan it stops for a file with an invalid
  signature, for several signers (unless `-AllowMultipleSigners`) and for a package whose `Install.ps1` is not signed; after the
  scan it checks the policy (signer rules without file attribute, no hash rule next to a signed file, no denied signer) and lists the
  trusted publishers. **Default unchanged:** without `-Mode` / `-Level` both tools write hash rules as before. New files:
  `tools\SelfXPublisherRules.ps1` (functions of the publisher mode and the checks, no AppLocker or ConfigCI cmdlet),
  `tools\SelfXTestCertificate.ps1` (test helper). Docs: docs/Installation.md, "Set up once instead of per version". Tests:
  `Test-SelfXAppLockerRules.ps1` (structure, SID instead of name, no hash rule or version, changed policies as negative tests, mocked
  signature states, refusals; with a trusted test certificate also a run with signed files), `Test-WdacPolicy.ps1` (checks of signer
  policies on synthetic texts, refusal without a signed file; with a trusted test certificate also a run). Not tried on a device.
- **Trust mode in the service (`SelfXService.exe`, version 3.1.0):** Before every start of a script the service reads the trust anchor
  `HKLM\SOFTWARE\SelfX\Trust` (64-bit view). An anchor that is missing, invalid (`Mode` not `Hash` or `Signature`; in the mode signature
  `Signers` not a list of 1 to 10 SHA1 thumbprints) or not protected (owner other than SYSTEM `S-1-5-18` or Administrators
  `S-1-5-32-544`, or another identity may change the key) starts nothing: new **event 4006**. `Mode` = `Hash`: behaviour as before.
  `Mode` = `Signature` (docs/Architecture.md, "The mode signature in the service"): the lists, the catalogs and every listed file are
  opened once (readable, not writable, replaceable, renamable or deletable) and stay open until the started script has ended;
  `SelfX.Code.json` must be a member of the signed `App\SelfX.Code.cat` and `SelfX.Config.json` a member of the signed
  `Config\SelfX.Config.cat`; the file check runs on the open handles; every listed `.ps1`, `.psm1`, `.psd1` and `.dll` must carry an
  embedded signature; every settings file must be a member of `SelfX.Config.cat`. A signature counts when Windows accepts it
  (`WinVerifyTrust`) and the signer is in `Signers`. A failed signature check starts nothing, also with `Service_FileCheck` = `Audit`:
  new **event 4007**. Revocation is checked from the local cache only (no network request). Positive results are kept for 60 minutes
  per file (path, write time, size and SHA256 of the open handle; never negative results; the list of signers is applied at every
  start). No new package: the calls of Windows are made directly (class `SelfXTrust`). **`Install.ps1`:** in the mode signature the two
  catalogs are now installed next to their lists (`SelfX.Code.cat` into `App`, `Config\SelfX.Config.cat` into `Config`) and compared
  with the checked catalogs after the copy (`Copy-SelfXPayload -SignedPackage`, `Test-SelfXInstalledFiles -SignedPackage`,
  `Test-SelfXInstalledLists`); in the mode hash no catalog is installed. **Changed behaviour:** an installation without the anchor
  (installed before the anchor existed, service replaced by hand) starts no action until the package is installed again. New for the
  experiment behind the check: `tools\SelfXTrustProbe.cs` and `tools\Measure-SelfXTrustCheck.ps1` (cases and time per check on a
  device). Tests: `Test-ServicePipe.ps1` (anchor missing, invalid and unsafe; pinned files; with test certificates: wrong signer,
  changed XML, missing and unsigned catalog, unsigned and changed script, unsigned library, cache), `Test-InstallBinaries.ps1` (copy
  step with catalogs). Not part of this change: the package tools do not sign yet.
- **Trust mode signature in `Install.ps1` (`-TrustedSigner`, version 3.1.0):** `Install.ps1 -TrustedSigner <thumbprint>[,<thumbprint>]`
  installs a signed package (docs/Architecture.md, "The mode signature in `Install.ps1`"). The list holds SHA1 thumbprints of 40
  hexadecimal characters (at most 10, separated by commas; anything else stops the installation, also a given but empty parameter).
  Before anything on the device is changed, also before the data folder is prepared: no link in the package; every `.exe`, `.dll`,
  `.ps1`, `.psm1` and `.psd1` has a signature with the status `Valid` of a signer of the list; `Config\SelfX.Config.cat` is signed by
  a signer of the list, uses SHA256 and matches the folder `Config`; the new catalog `SelfX.Code.cat` at the top of the package is
  signed by a signer of the list and matches everything outside `Config` (so `SelfX.Code.json`, the language files, the images,
  `SelfX.Binaries.json` and the sources are covered too). The checks of `SelfX.Binaries.json`, `SelfX.Code.json` and
  `SelfX.Config.json` stay; after the copy the installed lists must be the lists that the catalogs covered. The catalogs are checked
  in the package and are not installed. New functions: `ConvertTo-SelfXTrustedSignerList`, `Resolve-SelfXTrustMode`,
  `Test-SelfXFileSignature`, `Test-SelfXPackageCatalog`, `Test-SelfXPackageSignatures`, `Test-SelfXInstalledLists`,
  `Get-SelfXTrustAnchor`, `Set-SelfXTrustAnchor`, `Test-SelfXTrustAnchorState`. **Trust anchor:** in both modes `Install.ps1` writes
  `HKLM\SOFTWARE\SelfX\Trust` (`Mode` = `Hash` or `Signature`; `Signers` as `REG_MULTI_SZ` in the mode signature) before the service is
  registered: owner Administrators (`S-1-5-32-544`), rights not inherited, SYSTEM (`S-1-5-18`) and Administrators full control, users
  (`S-1-5-32-545`) read; the anchor is read back and its rights are checked. **Downgrade:** a device whose anchor says `Signature` (or
  cannot be understood) is installed without `-TrustedSigner` only with the new switch `-AllowHashMode`; both together are an error.
  A signed package without `-TrustedSigner` is refused with a hint. Without `-TrustedSigner` the mode hash works as before.
  **Changed behaviour:** the parameters of `Install.ps1` are bound by name only (`-InstallFolder <path>` instead of a path without a
  name). `Detection.ps1` requires the anchor (`Test-SelfXTrustAnchor`, 64-bit view; the mode is logged and not judged), so an
  installation of an earlier build is installed again once. `Uninstall.ps1` removes the anchor (`HKLM\SOFTWARE\SelfX\Support` stays).
  Revocation: the check of Windows is used; new `tools\Measure-SelfXRevocationDelay.ps1` measures on a device how long
  `Get-AuthenticodeSignature` takes when the revocation list address of the certificate cannot be reached. Tests:
  `Test-InstallBinaries.ps1` (list of signers, mode and downgrade, all refusals of signatures and catalogs with replaced cmdlets, copy
  step, anchor in a test key below HKCU, the same answers as `tools\SelfXSigning.ps1`; with a trusted test root also real signatures and
  catalogs), `Test-Detection.ps1` (anchor). Not part of this change: the package tools do not sign yet, and the service does not read
  the anchor yet.
- **Fix (tests): `tools\Test-SelfXSigning.ps1` no longer stops the CI jobs "Signing library".** Part 2 added its test certificates to
  `Cert:\CurrentUser\Root`; Windows shows a question there, and a process without a desktop waits for it until the job is cancelled.
  With administrator rights the test now uses `Cert:\LocalMachine\Root` (no question); on GitHub Actions part 2 runs only with
  administrator rights. Two expectations follow what Windows reports: a script with text added after the signature block has the status
  `NotSigned`, a script changed before the block `HashMismatch`. `tools\SelfXSigning.ps1` is unchanged.
- **Signing library (`tools\SelfXSigning.ps1`, tools only, not part of the package):** Functions for the trust mode "signature"
  (docs/Architecture.md), working in Windows PowerShell 5.1 and PowerShell 7: `Get-SelfXSigningCertificate` (certificates of
  `Cert:\CurrentUser\My` and `Cert:\LocalMachine\My` with private key, key usage Code Signing and a valid period, or a PFX file with a
  `SecureString` password that is not imported into a store), `Set-SelfXCodeSignature` (SHA256, chain without the root, optional
  http/https time stamp server; all input is checked before the first file is signed, every file is read back), `New-SelfXSignedCatalog`
  (`New-FileCatalog` version 2 and signature; no unsigned catalog is left when signing fails), `Test-SelfXSignature` (status `Valid` and
  the signer in the list of allowed thumbprints; returns the reason) and `Test-SelfXSignedCatalog` (signer and folder contents; names changed,
  missing and extra files). The password is never converted to plain text and never appears in an output, log or message. Nothing uses the
  library yet. Tests: new `tools\Test-SelfXSigning.ps1` (part 1 on every system, part 2 with self-signed test certificates in
  `Cert:\CurrentUser`), new CI job "Signing library" (Windows PowerShell 5.1 and PowerShell 7).
- **Text overrides (`Config\Texts\<culture>.xml`, version 3.1.0):** A company can replace single texts without changing a
  bundled language file. The optional file has the format of the language files and holds only the texts to change (`UI`,
  `SystemInfo`, `Catalog`); it is configuration (class Config, listed in `SelfX.Config.json`) and is installed into
  `%ProgramFiles%\SelfX\Config\Texts`. `Localization.ps1` loads the bundled file first and then the override of the culture of
  the loaded file (`de-CH` uses `Texts\de.xml`): `Initialize-SelfXLanguage -TextOverrideFolder`, new functions
  `Read-SelfXTextOverride`, `Test-SelfXOverrideText`, `Set-SelfXTextOverride`, `Import-SelfXTextOverride`,
  `Get-SelfXTextEntries`, `Get-SelfXTextReference`; the folder comes from `Get-SelfXTextOverrideFolder` (`SelfXPaths.ps1`).
  A text is used only when its id is known in a bundled file, it is given once, is not empty, not longer than 1500 characters,
  has no markup (no `<`, no entity such as `&amp;`), no control characters and the same placeholders as the bundled text; the
  Copilot prompts cannot be overridden. Unknown ids and refused texts are ignored and written to the log of the user (id and
  reason, never a text). The file is read once as bytes, must not be a link, larger than 256 KB or have a DTD; the root
  attributes of an override are not used, so it cannot add or replace a language. Placement rule (`Install.ps1`,
  `tools\SelfXPackage.Common.ps1`, `SelfXService.cs`, `SelfXPaths.ps1`): `Texts/<culture>.xml` is accepted in
  `SelfX.Config.json`; nothing below `Texts` may be in `SelfX.Code.json`. `Test-LanguageFiles.ps1` also checks the text
  overrides (`-TextsFolder`) with the same functions. Docs: `docs/Configuration.md` (section "Change single texts"),
  `docs/Architecture.md` (DE and EN). Tests: new `Test-TextOverrides.ps1`; extended `Test-FileManifest.ps1`,
  `Test-ConfigPath.ps1`, `Test-ServicePipe.ps1`.
- **Package and device, code and configuration in two folders (version 3.1.0):** The package has the folders `App` (code)
  and `Config` (configuration) instead of `Sources`; `tools\New-SelfXIntuneWin.ps1` sorts the files of `Sources` by their file
  class (`ConvertTo-SelfXPackageLayout` in `tools\SelfXPackage.Common.ps1`; a file without a class stops the build). On the
  device the programs, libraries, scripts, language files and default images of the project, `Uninstall.ps1` and
  `SelfX.Code.json` are in `%ProgramFiles%\SelfX\App`; the settings files, `Branding`, own scripts and language files and
  `SelfX.Config.json` are in `%ProgramFiles%\SelfX\Config`; the rights are unchanged (users `S-1-5-32-545` read and execute
  only). One path resolver: `Sources\SelfXPaths.ps1` (`Get-SelfXConfigPath`, `Get-SelfXImagePath`, `Resolve-SelfXScriptPath`,
  Windows PowerShell 5.1 and PowerShell 7) and in the service `GetConfigRoot`, `GetConfigFilePath`, `ResolveScriptPath`; the
  configuration folder is `Config` next to a code folder named `App`, otherwise the code folder itself. The service loads the
  catalog, `Health_Config.xml` and `Tool_Config.xml` only from `Config` and scripts of the project only from `App`; an own
  script below `Config` starts only when the catalog or `Health_Config.xml` names it and `SelfX.Config.json` lists it with its
  current SHA256, also with `Service_FileCheck` = `Audit`; a script of the project with the same name wins (likewise in
  `Self_X.ps1` for user actions and in `HealthStatus.ps1` for own check scripts). The file check of the service and of
  `Install.ps1` compares every folder only with its own list and allows nothing next to `App` and `Config` (empty folders that
  are still in use excepted). Images: `Branding\...` in `Config`, other relative values in `App`. Own language files in
  `Config\Languages` are offered but cannot replace a bundled language. Migration: `Install.ps1` 3.1.0 removes an
  installation in the old layout completely before the copy (new functions `Clear-SelfXInstallFolder`,
  `Copy-SelfXPayload`) and refuses a package in the old layout; `Uninstall.ps1` 3.1.0 removes both layouts and reads
  `Tool_Config.xml` without DTD; `Detection.ps1` 3.1.0 detects only the new layout. **Note:** own scripts that look for
  `SelfXLog.ps1` or `SelfXOffice.ps1` through `Split-Path -Parent $PSScriptRoot` have to be adapted (`docs/Configuration.md`,
  section "Own scripts of the company"). `Version.txt` and `Detection.ps1` are set to 3.1.0. Tests: new
  `Test-ConfigPath.ps1`; extended `Test-FileManifest.ps1`, `Test-InstallBinaries.ps1` (update 3.0.2 -> 3.1.0, mixed state,
  locked file), `Test-Uninstall.ps1`, `Test-Detection.ps1`, `Test-ServicePipe.ps1`, `Test-Compat51.ps1`.
- **Package, the version is a property of the code (`Version.txt`, `SelfX.Code.json`):** The version is no longer stored in the settings file
  `Tool_Config.xml`. The new file `SelfX Service\Version.txt` (one line) is the only source; the build writes it into `ToolVersion` of
  `SelfX.Code.json`. A new version therefore changes no configuration file, and a changed configuration (for example a logo) does not
  change the version. `SelfX.Config.json` has `ConfigRevision` (UTC time of the packaging run, not part of the digest) instead of
  `BuiltUtc`. Readers adapted: `Detection.ps1` 3.0.4 compares `$ExpectedVersion` with `ToolVersion` of the installed `SelfX.Code.json`
  (new function `Test-SelfXInstalledPackage`: code version, code digest and configuration digest are reported separately);
  `Install.ps1` 2.9.1 reads the version from the checked `SelfX.Code.json` and refuses a package without it before anything is changed
  (a package without the two lists was installed with a warning before); `Self_X.ps1` 2.8.27 shows the version from `SelfX.Code.json`
  (`?` when it cannot be read); `release.yml` compares the tag with `Version.txt`; `New-SelfXIntuneWin.ps1` 1.10.0,
  `New-SelfXPackage.ps1` 1.0.1, `Build-SelfXBinaries.ps1` 2.8.21 and `New-SelfXWdacPolicy.ps1` 1.0.1 read `Version.txt`
  (`Get-SelfXVersionFromFile` in `tools\SelfXPackage.Common.ps1` accepts one line of at most 30 letters, digits, `.` and `-`).
  `Version.txt` is not part of the package. An old `Tool_Version` element in a company's `Tool_Config.xml` is ignored. No text of the
  user interface changed. Tests: version change leaves all configuration files unchanged, configuration change leaves the version and the
  code list unchanged, detection of code version, code files and configuration separately, negative tests for `Version.txt`,
  `ConfigRevision`, `ToolVersion` and a damaged code list, and a scan that no script, tool or workflow reads `Tool_Version`.
- **Package, two file lists (`SelfX.Code.json`, `SelfX.Config.json`):** `SelfX.Files.json` is replaced by two lists. `SelfX.Code.json`
  holds the programs, libraries and the scripts, language files and images of the project; `SelfX.Config.json` holds the settings
  files, everything below `Branding` and own scripts and language files. Every file is in exactly one list, an unknown file stops the
  build, and a file in both lists or in the wrong list is refused. The code list has no build time, so a changed company logo changes
  only `SelfX.Config.json` and the configuration digest. New `tools\SelfXPackage.Common.ps1` (file classes, both lists, digest,
  `Detection.ps1` writer). `Install.ps1` 2.9.0 checks the package and the installed folder against both lists; `Detection.ps1` 3.0.3
  checks two digests; the service (2.9.0) reads both lists with the same rules (event 4005 unchanged, `Service_FileCheck` unchanged);
  `SelfXWinRT.ps1` and `SelfXAudio.ps1` read the hashes of their libraries from `SelfX.Code.json`. `Tool_Version` is unchanged.
  Tests adapted and extended (logo test, class and placement tests, negative tests).
- **Documentation, architecture:** New `docs/Architecture.md` (German: `docs/de/Architecture.md`): the three file classes (code,
  configuration, company code), the assignment of every file of the package SelfX Service, the planned lists `SelfX.Code.json` and
  `SelfX.Config.json`, the trust modes hash and signature, the trust anchor and the limit of the checks against a local
  administrator. It also names the files whose class is still open. Linked from the README and the installation guide. No code
  change.
- **Security, report file (`Collect-DeviceLogs.ps1` 1.3.6):** A report file is only overwritten when it existed and was checked as
  trusted. After a planted file was removed the report is always created new (`CreateNew`), so a file that a user creates in the gap
  is never written. A default report (`-Protect`) is opened without sharing: until the access rights are set nobody can hold a read
  handle. `-UserView` accepts only the SID of a user account.
- **System information export (`SystemInfo.ps1` 2.8.26):** The file name from the save dialog is used literally (`-LiteralPath`).
  A name with `[` `]` failed or could match other files.

## 3.0.2 - 2026-11-24 (SelfX Service)

- **Security, report reader:** `SelfX_Device_CollectLogs.ps1` (2.8.21) releases the report only to the account of the requesting
  user. Only user SIDs are allowed as reader (`S-1-5-21-...` local/domain, `S-1-12-1-...` Entra ID). Groups and well-known SIDs such
  as Everyone (`S-1-1-0`), Authenticated Users (`S-1-5-11`) or Users (`S-1-5-32-545`) are refused (exit code 2, no report), and
  again in `Set-ReportAcl` as a second safeguard.
- **Security, PowerShell 7 check at installation:** `Install.ps1` (2.8.6) checks pwsh.exe like the service does before every start:
  only SYSTEM, Administrators and TrustedInstaller may change or take over pwsh.exe, its folder and the folders above it. The rights
  are read as SIDs (an unknown SID is no longer skipped); when they cannot be read, the installation stops. Tests added in
  `Test-DeviceLogs.ps1` and `Test-InstallBinaries.ps1`.

## 3.0.1 - 2026-11-24 (SelfX Service)

- **AppLocker hash rules:** `tools\Build-SelfXBinaries.ps1` (2.8.20) writes `build\SelfX.AppLocker.xml` again on German and other localized
  Windows versions: the rules apply to the SID `S-1-1-0` instead of the name "Everyone", which cannot be resolved there. In
  PowerShell 7 the rules are created through Windows PowerShell 5.1 (new `tools\New-SelfXAppLockerRules.ps1`), because the AppLocker
  cmdlets do not accept a list of paths in PowerShell 7. The script checks that every program has one Allow rule.
- **Offline build:** building the programs needs no internet any more. `NuGet.config` in the repository root allows only the
  folder `offline-feed` (NuGet packages with the manifest `SelfX.OfflineFeed.json`, SHA512 of each file).
  `tools\Build-SelfXBinaries.ps1` (2.8.19) checks the folder against the manifest and against the SDK version of the export before
  every build, restores into a fresh package cache inside the repository and stops when a package is missing, changed or
  additional. The new `tools\Export-SelfXOfflineFeed.ps1` is the only script that talks to nuget.org: it fills the folder, runs the
  NuGet vulnerability audit (the audit is off for the offline build) and proves the folder with an offline restore. The runtime
  packs of WindowsDesktop and AspNetCore are no longer requested (`DisableTransitiveFrameworkReferenceDownloads`). New test
  `tools\Test-SelfXOfflineFeed.ps1`. Before the first offline build run the export once (see the installation guide, "Offline build").

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

Details: [Installation guide](docs/Installation.md).

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
- **New button "Company wiki" (optional):** `Wiki_Enabled`, `Wiki_Url` (`https://` only) and `Wiki_Name` (up to 40 characters) in `Tool_Config.xml` show a button in the navigation, styled like the Copilot button, that opens the wiki address in the web browser. Off by default; an invalid address hides the button and writes a warning to the log. Runs in the user context. Texts in all 24 languages, new questions in the package wizard, tests in `Test-SupportLinks.ps1` and `Test-SelfXPackageWizard.ps1`.
- **New action "Excel opens every file in the same window"** (category Office, user context):
  starts a second, independent Excel instance (`excel.exe /x`), for example to compare two
  workbooks on two screens. Nothing is closed or changed; the program path comes from
  `SelfXOffice.ps1` (below Program Files, no link) and the only argument is the fixed switch
  `/x`. Texts in all 24 languages, tests in `Test-Scripts.ps1`.
- **New action "A program window is outside the screen"** (category Device, user context):
  moves windows of the own user whose title bar cannot be reached on any screen (for example
  after a monitor was disconnected) to the primary screen. Nothing is closed, saved or
  changed in the settings; windows are moved through Microsoft UI Automation (no compiled
  code) and window titles are not written to the log. Programs with higher rights are
  skipped. New helper `SelfXWindows.ps1`, test: `Test-WindowHelper.ps1`.
- **New action "Citrix Workspace does not respond or does not show your apps"** (category
  Citrix, user context): closes the Citrix Workspace app processes of the own user account and
  starts the app again. Application and desktop sessions that are already open are not ended;
  the saved sign-in and the settings stay unchanged. The program path must be below Program
  Files (no link); there is no user input. Only the current Citrix Workspace app is
  supported, not the Receiver.

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
- **Package wizard (guided configuration):** `tools\New-SelfXPackage.ps1` asks questions with a
  recommendation (support, branding, ticket and organisations by OU, group tag and device class,
  Copilot Chat, behavior), writes the answers into a copy of the package, builds the Intune package,
  creates the platform scripts for the ticket routing and short Intune instructions. German and
  English; more languages via `tools\Wizard\Wizard.<culture>.xml`. See
  [Package wizard](docs/Guided-Setup.md). `New-SelfXIntuneWin.ps1` 1.8.0 has the new parameter
  `-SourceFolder`. Test: `tools\Test-SelfXPackageWizard.ps1` (runs in CI).
- **Citrix Workspace in the system information:** when the Citrix Workspace app is installed,
  SelfX shows the row "Citrix Workspace" with the version under "Device". The row is also part of
  the device information of the support ticket. The reachability of StoreFront or the Gateway can be
  measured with a target in `Network_Test_Config.xml` (example in the file). Test:
  `Test-CitrixInfo.ps1`.

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
