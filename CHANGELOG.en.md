# Changelog

**English** | [Deutsch](CHANGELOG.md)

Changes of this fork ([fubu2k/SelfX](https://github.com/fubu2k/SelfX)) compared
with its upstream [wbaeck/SelfX](https://github.com/wbaeck/SelfX) at SelfX
Service 2.6.9. Newest version first.

The package version is `Tool_Version` in `SelfX Service\Sources\Tool_Config.xml`.
`Detection.ps1` must contain the same value, otherwise Intune does not detect
the update (the packaging script checks this). The version numbers in the
histories of the single files show where a change was made. Changes marked
2.6.10 were made before the package version was raised; they are delivered with
**2.6.11**, the first package version of this fork.

## Unreleased (SelfX Service, phase 2 of the migration)

The service, the window and the status icon start PowerShell 7 instead of Windows
PowerShell 5.1. Shipped together with the replacement for the Windows Update interface
(WinRT) and the version bump.

### Changed

- BitLocker and TPM without modules: device status and compliance check read CIM (`Win32_EncryptableVolume`, `Win32_Tpm`,
  file `Sources\SelfXDeviceSecurity.ps1`) instead of `Get-BitLockerVolume` and `Get-Tpm`. This fixes an earlier bug: data
  drives were never checked because the type was named "Data", not "FixedData". Fixed data drives without BitLocker
  now show "Error" in the BitLocker status.
- Secure Boot check (compliance) reads the registry (`UEFISecureBootEnabled`, new file `Sources\SelfXDeviceSecurity.ps1`)
  instead of `Confirm-SecureBootUEFI`: no Windows PowerShell compatibility layer and no administrator rights needed.
- Defender without the Defender module: status (device status, compliance) and signature update use CIM
  (`root\Microsoft\Windows\Defender`, new file `Sources\SelfXDefender.ps1`) instead of `Get-MpComputerStatus`
  and `Update-MpSignature`. Update sources and their order still come from the Defender policy.
- Network without the NetAdapter module: adapters, default routes and the adapter restart ("Restart network")
  use CIM (`root\StandardCimv2`, new file `Sources\SelfXNetwork.ps1`) instead of `Get-NetAdapter`,
  `Get-NetRoute` and `Restart-NetAdapter`. PowerShell 7 no longer starts Windows PowerShell 5.1 for it.
  Also fixes that devices without an IPv6 default route lost all default routes.
- CI: the tests now run in PowerShell 7 as a blocking job. Windows PowerShell 5.1 only checks
  `Install.ps1`, `Uninstall.ps1`, `Detection.ps1` and the log collector (Intune starts them there).
  The health check and the support report no longer contain PowerShell 5.1 branches.
- "Install updates" uses only the Windows Update orchestrator (`SelfXWinRT.dll`,
  PowerShell 7). The Windows Update Agent API and the PowerShell 5.1 branch are removed
  (minimum version Windows 11 25H2). If the orchestrator API is missing, the action ends with exit 1.
- Minimum version: Windows 11 25H2 (build 26200). `Install.ps1` checks the build number
  (registry) before changing anything and stops hard on older builds; the existing
  installation stays unchanged.
- The service starts every script with `%ProgramFiles%\PowerShell\7\pwsh.exe` (fixed
  path, no PATH search). For the script it sets only the machine-wide module folders
  (`PSModulePath`) and turns off PowerShell telemetry and the update check. When
  PowerShell 7 is missing it starts nothing and reports "PowerShell 7 is not installed".
- `SelfX.exe`, `Start-SelfXHiddenPowerShell`, the health check and the log collector use
  the same fixed path.
- Autopilot must always work: when PowerShell 7 is missing (or older than 7.6),
  `Install.ps1` installs SelfX anyway and only warns. Until PowerShell 7 is there the
  service starts no scripts and reports "PowerShell 7 is not installed". When PowerShell 7
  is present but normal users can change it (folder or `pwsh.exe`), the installation stops
  before anything is changed (security). The service checks rights and version again before
  every start, because PowerShell 7 can be installed after SelfX. `Install.ps1` and
  `Uninstall.ps1` still run in Windows PowerShell 5.1 and close windows and status icons
  of `powershell.exe` and `pwsh.exe`.
- `Test-ServicePipe.ps1` and `Test-HealthStatus.ps1` also compile the service in
  PowerShell 7; `Test-InstallBinaries.ps1` tests the new prerequisite.

- New library `SelfXWinRT.dll` (.NET 10, Windows SDK projection) replaces the WinRT access
  to the Windows Update orchestrator (Windows 11 24H2 and newer) in PowerShell 7, which
  cannot load Windows Runtime types by name any more. It contains no logic of its own and
  only returns the manager object. `Build-SelfXBinaries.ps1` builds it with the two
  projection files into `Bin\WinRT`; `Install.ps1` checks every file by SHA256 and copies
  it to `%ProgramFiles%\SelfX\WinRT`. On older Windows the scripts fall back to the Windows
  Update Agent as before.
- The manifest `SelfX.Binaries.json` now has format 3 (entries `WinRT/...`). The installer
  refuses packages with format 2: build the package again.

## 2.7.0 - 2026-11-22 (SelfX Service)

The service and the starter run on .NET 10 (LTS, supported until 14 Nov 2028). The
programs are built once on a build machine; the devices no longer compile anything.
`Tool_Version` and `$ExpectedVersion` were raised: build and deploy the package again.

### Changed

- `SelfXService.exe` and `SelfX.exe` are .NET 10 programs (self-contained, one file,
  about 36 MB each). No .NET runtime is needed on the devices. The user interface and
  all scripts still run in Windows PowerShell 5.1.
- `tools\Build-SelfXBinaries.ps1` builds with `dotnet publish` (.NET SDK 10 on the
  build machine). The call stays the same. The manifest has format 2.
- `Install.ps1` requires the folder `Bin` and checks it before it touches the existing
  installation. Compiling on the device was removed. When `Bin` is missing, the
  installation stops with a clear message and the old version stays.
- `tools\New-SelfXIntuneWin.ps1` builds no package without a checked `Bin` and does not
  package the .NET project files.
- New: .NET projects in `SelfX Service\Service\Projects`, NuGet lock file, a CI job that
  builds twice, compares the hashes and starts the service.
- Installation guide rewritten with a step-by-step procedure.

### Note

New programs have new hashes: replace the AppLocker rules of the previous build.

## 2.6.12 - 2026-11-22 (SelfX Service)

German is the base language of the user interface; English is the fallback.
Raise of `Tool_Version` and `$ExpectedVersion`: redeploy the package.

### Changed

- `Tool_Language` in `Tool_Config.xml` is now `de` by default (before: `Auto`,
  the Windows display language). Users can still choose another language in
  SelfX > Settings; `Auto` remains possible.
- If no language file matches (for example `Auto` on a device in Czech), SelfX
  uses German instead of English. A text that is missing in the selected
  language is shown in English.
- `Test-UI.ps1` tests the base language.

Not changed: the texts of the actions in `Issues_List.xml` stay English base
texts, which are used only if a text is missing in German and in English.

## Repository, 2026-11-22

- The fork is developed only for SelfX Service. The folders `SelfX Standard`
  and `SelfX Admin` were removed; use the upstream projects if you need them.
  `tools\New-SelfXIntuneWin.ps1` (1.3.0) builds only the SelfX Service package;
  `Test-UI.ps1` no longer reads a file of SelfX Standard.
- README, installation guide, configuration guide, user manual and
  `SECURITY.md` describe only SelfX Service.
- The package version of SelfX Service is unchanged (2.6.11).

## 2.6.11 - 2026-11-22 (SelfX Service)

Security hardening release. It replaces the service and the installer: redeploy
the **entire package**. The update installs like every other update;
`Tool_Version` and `$ExpectedVersion` of `Detection.ps1` are both raised to
2.6.11.

### Security

- **Pipe deadlines that work reliably.** The pipe of the service uses
  overlapped I/O. Reading the request, writing the answer and waiting for the
  client are cancelled when the deadline passes; if the operation does not end,
  the connection is closed. One 5-second deadline covers the whole request, so
  sending slowly does not extend it.
- **Connection limit before reading.** The limit of 8 connections per user is
  applied when the connection is accepted, using the owner of the client
  process reported by Windows. One user can no longer occupy the 64 connection
  slots of all users before the service has read a request.
- **Prebuilt programs checked by hash (optional).** `tools\Build-SelfXBinaries.ps1`
  builds `SelfXService.exe`, `SelfX.exe` and `SelfXSessionStarter.dll` once on a
  build machine and writes `SelfX Service\Bin\SelfX.Binaries.json` with the
  SHA256 of the sources and the files. When the AppLocker cmdlets are
  available, it also writes `build\SelfX.AppLocker.xml` with hash rules for the
  three files. If the package contains `Bin`, `Install.ps1` checks the
  manifest, the sources and the hash of every file and stops with exit code 1
  when anything does not match; nothing is compiled instead. The files are not
  signed.
- **Protected compiler TEMP.** Without `Bin`, the device still compiles the
  programs, but the compiler now writes its temporary files to a folder below
  the protected install folder instead of `C:\Windows\Temp`.
- **Packaging.** `tools\New-SelfXIntuneWin.ps1` refuses a `Bin` folder that was
  built from other sources than the ones in the package.

### Added

- `NOTICE.md` / `NOTICE.en.md`: authors and sources (Damien Van Robaeys, Wolfgang Baeck, Jannik Reinhard).
- `Test-ServicePipe.ps1`: starts the pipe listener of the service under a test
  pipe name and checks the deadlines, slow senders, oversized requests and the
  per-user limit. It needs no installation and no administrator rights.
- `Test-InstallBinaries.ps1`: tests the check of the prebuilt programs and the
  protected compiler TEMP.
- GitHub Actions workflow `.github/workflows/service-ci.yml`: compiles the
  service, launcher and session starter, runs all `Test-*.ps1` in Windows
  PowerShell 5.1 and runs PSScriptAnalyzer with security rules for every pull
  request and every change of `main`. The workflow has read-only rights and
  uses actions pinned to a commit.
- `SECURITY.md` (private reporting of vulnerabilities), `.github/CODEOWNERS`
  and Dependabot for the pinned GitHub Actions; this `CHANGELOG.md`.

### Fixed

- Four existing tests failed on the first run on a Windows runner (parser error
  in `Test-Catalog.ps1`, a changed method signature in `Test-HealthStatus.ps1`,
  and two tests that assumed a non-elevated account). The product code was not
  affected.

### Changed

- A connection above the per-user limit is closed without an answer (before:
  the answer *busy*). The SelfX window does not reach this limit.
- Documentation: new installation and release checklist, description of the
  prebuilt programs and of the AppLocker rules, updated test list.

## 2.6.10 - 2026-11-22 (SelfX Service; delivered with 2.6.11)

Findings of the security review of SelfX Service. The pull request numbers
refer to this repository.

### Security

- **Device logs report (#1, #2).** The report no longer reads the log folders of
  the users as SYSTEM (users can change these folders). The SelfX window adds
  the own user logs with the rights of the user. On multi-user devices a normal
  user receives only the own data; only an elevated administrator (read by the
  service from the client token, `SELFX_CALLER_ADMIN=1`) gets the complete
  report.
- **Status cache (#3).** A single health check (`HEALTH <Id> <name>`) with an
  unknown name can no longer append rows to the status cache that all users and
  the status icon share.
- **Service log and requests (#4).** Text from requests is cleaned and
  shortened before it is logged, rejected requests are logged at most 20 times
  per minute (a user cannot flood the log), and the request patterns end with
  `\z` instead of `$`.
- **Pipe limits (#6).** The service closes connections that send nothing for 5
  seconds or do not read the answer, runs every connection in its own thread
  and accepts at most 64 connections (8 per user). After a check, the same user
  waits 3 seconds for the next one; after an action, 15 seconds before the same
  action can be started again. In both cases the service answers *busy*.
- **Pipe server check (#7).** Before the SelfX window sends a request it
  checks that the pipe is served by the running `SelfXService` (process ID of
  the pipe server compared with the process ID from the service control
  manager). A user process that created the pipe name while the service was
  stopped is refused.
- **Uninstall (#8).** `Uninstall.ps1 -RemoveLogs` deletes the data folders
  without following junctions or symbolic links that users created.
- **Several users on one device (#9).** New catalogue element
  `OtherSessions` (and attribute on a remediation in `Health_Config.xml`):
  with `Block`, a normal user cannot start the action while another user has an
  active session. The delivered configuration sets it for the restart,
  Windows updates, the disk check, the restart of the network adapters and the
  restart of the Intune service. Elevated administrators are not restricted;
  if the sessions cannot be read, the action is blocked.

### Added

- `Test-Catalog.ps1` (#5): static check of the catalogue, `Health_Config.xml`
  and the scripts that run as SYSTEM (plain file names, one context per script,
  no mandatory parameters, remediation timeouts).
- `Test-Uninstall.ps1` (#8) and extensions of `Test-HealthStatus.ps1` and
  `Test-DeviceLogs.ps1`.

## Based on upstream 2.6.9

Windows updates through the Windows Update orchestrator, pending restart
detection and the other changes up to SelfX Service 2.6.9 come from
[wbaeck/SelfX](https://github.com/wbaeck/SelfX). The history of every file is in
its header.
