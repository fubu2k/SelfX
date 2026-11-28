# CLAUDE.md - binding rules for work on SelfX (fubu2k/SelfX)

This file is the rule set for every Claude session in this repository. Read it completely before the first
change. When a rule here and a file of the repository disagree, the repository is right: fix this file in the
same pull request.

Checked against `main` at commit `d2192be` (2026-11-27, `Version.txt` = 3.1.0).

## 0. Before any work

1. `git fetch origin` and compare the local branch with `origin/main`. A local `main` can be far behind.
2. Branch from the current `main` of this fork: `feature/...`, `fix/...`, `security/...`, `docs/...`.
   Never commit to `main`. Pull requests go from the branch to `main` of **fubu2k/SelfX**. The upstream
   (wbaeck/SelfX) is history only: nothing is merged from it and no pull request goes there.
3. Name the execution context of every piece of code you touch: signed-in user, administrator, SYSTEM
   (service), Intune installation (SYSTEM, Windows PowerShell 5.1), build machine or CI.
4. Security comes first. A change that widens what a normal user can make SYSTEM do is not acceptable,
   whatever the feature gain.

## 1. Tools, plugins and skills

Inventory of the session of 2026-11-27. Tools differ between sessions: check what is present before you rely
on a row, and say so when a needed tool is missing instead of working around it.

| Tool / plugin / skill | Kind | Use in this repository |
|---|---|---|
| `Windows-MCP` (`PowerShell`, `FileSystem`, `Registry`, `Process`, `Snapshot`/`Screenshot`) | local MCP server on the Windows development PC | The terminal of this project: git, all `Test-*.ps1`, PSScriptAnalyzer, `dotnet` build, package build. PowerShell 7.6, Windows PowerShell 5.1, .NET SDK 10 and git are installed there. |
| `Microsoft Learn` (`microsoft_docs_search`, `microsoft_docs_fetch`, `microsoft_code_sample_search`) | connector | Official documentation: .NET 10, named pipes, `WinVerifyTrust`, Authenticode, AppLocker, App Control (WDAC), Defender ASR, Intune Win32 apps, Autopilot / ESP. |
| `microsoft-docs:microsoft-docs`, `microsoft-docs:microsoft-code-reference` | skills | The first for concepts, limits and configuration; the second before writing or reviewing C# / .NET / Win32 API calls (signatures, deprecated patterns). |
| `claude-security:claude-security`, `:threat-model`, `:attack-surface-analysis`, `:ci-review` | skills (plugin Claude Security) | Scan of a branch or diff, threat model, audit of what a normal user can reach through the pipe. |
| `git` (development PC) | CLI through `Windows-MCP` | Branches, commits, diff, log. `gh` is not installed on the development PC. |
| `gh` (cloud workspace) + `add_repo` | CLI | Pull requests, issues, CI logs through the REST API (`gh api repos/fubu2k/SelfX/...`); `gh pr create` and other GraphQL commands are blocked there. Works only after the repository was attached to the session with `add_repo` (access `push` for write operations). |
| `github-cli-health-check` | skill (plugin) | Only to find out why `gh` does not work. |
| Project documents (`Projects` tool, `claude/selfx-*.md`) | project knowledge | Architecture plan, security reviews, device test checklists, decisions. Read the matching document before a step of the plan. |
| `Explore`, `Plan`, `general-purpose` | subagents | Only when the user asks for a subagent. |
| Computer use, built-in browser, Claude in Chrome | desktop / browser control | Only on request: look at the SelfX window on the test device, Intune admin center. Never to enter credentials. |
| Artifact types (Docs, Design, Whiteboard), `project-artifact` | artifacts | Mockups of the window and the package wizard, plans, status pages. Not a replacement for files in the repository. |
| `WebSearch`, `WebFetch` | web | Only for what Microsoft Learn does not cover (release notes of GitHub Actions, CycloneDX, NuGet advisories). |

Not present in the inventoried session: a GitHub MCP server, a Sequential Thinking MCP server, a separate
Filesystem MCP server. Present but **never** to be used for this repository: `home-assistant`,
`opus-gateway-test`, `unifi-network`, `claude-for-msft-365-install`.

### Binding triggers

| When | Use | Rule |
|---|---|---|
| Any change to `Issues_List.xml`, `Health_Config.xml` or a script in `Scripts_to_run` / `HealthChecks` | `Windows-MCP` PowerShell | Run `Test-Catalog.ps1`, `Test-Scripts.ps1`, `Test-LanguageFiles.ps1`, `Test-FileManifest.ps1` before you report the change as done. |
| Any change to a `.ps1` | `Windows-MCP` PowerShell | Run the tests of section 5 and PSScriptAnalyzer with `.github\PSScriptAnalyzerSettings.psd1`. |
| Any change to `Service\*.cs` | `Windows-MCP` PowerShell, `microsoft-docs:microsoft-code-reference` | Verify every Windows / .NET API against the documentation first; then `tools\Build-SelfXBinaries.ps1`, `Test-ServicePipe.ps1`, `Test-SafeDelete.ps1`, `Test-InstallBinaries.ps1`. |
| Question about .NET 10, named pipes, ACLs, signatures, AppLocker, WDAC, ASR, Intune, Autopilot | `Microsoft Learn` | Look it up; do not answer from memory. Name the source in the pull request when a design decision rests on it. |
| Change to the pipe protocol, the trust check, `Install.ps1`, `Uninstall.ps1`, file or registry rights | `claude-security:claude-security` on the diff (or `:threat-model`) | In addition to the tests, before the pull request. |
| Pull request, issue, CI log | `gh api` after `add_repo` | Create a pull request with `gh api repos/fubu2k/SelfX/pulls -f title=... -f head=<branch> -f base=main -F body=@<file>`. Without access: write title and description into the chat and say that the pull request was not created. |
| Tests | development PC only | Never run the PowerShell tests in the Linux cloud workspace: it has neither `pwsh` nor `dotnet`, and the code is Windows-only. |
| Step of the architecture plan | `Projects` tool | Read the plan document and its addenda first. |

The tests are plain PowerShell scripts with their own assertions (exit code 0 or 1). The repository does not use
Pester; do not add Pester tests and do not add a test framework.

## 2. Project and architecture

**SelfX Service** is a self-service troubleshooting tool for Windows 11 (25H2, build 26200, is the minimum; the
installation stops on older builds) and for terminal servers with Windows Server 2022 or 2025 with Desktop
Experience (build 20348 or newer). Users without technical knowledge fix common problems (Teams, Office,
OneDrive, Outlook, Intune, Windows Update, network) and send device logs to the support.

- The mode comes from Windows, never from a setting: product type workstation (Windows 11) = `Client`, every
  other product type and unreadable data = `TerminalServer` (service: `IsTerminalServer`, PowerShell:
  `Get-SelfXEnvironmentMode` in `SelfXEnvironment.ps1`). With `TerminalServer` only entries classified
  `TerminalServer` = `Show` are offered and the service refuses the others. `Install.ps1` stops on Server Core,
  domain controllers and Windows Enterprise multi-session. Intune cannot install apps on Windows Server: servers
  get the package folder by hand or with Configuration Manager (`Detection.ps1` ends "not detected" with exit
  code 0 and no output, which both Intune and Configuration Manager read as "not installed").

- Installed machine-wide, works **fully offline**: no central backend, no download of scripts or configuration,
  no cloud credentials on the client. Do not add any of these.
- Only SelfX Service is developed here. SelfX Standard and SelfX Admin are not part of this fork.

| Part | Technology | Runs as |
|---|---|---|
| Window `Sources\Self_X.ps1`, status icon `Sources\SelfX_Tray.ps1` | PowerShell 7 + plain WPF, no third-party assemblies | signed-in user |
| Service `Service\SelfXService.cs` (`SelfXService.exe`) | C# / .NET 10, self-contained | LocalSystem |
| Starter `Service\SelfXLauncher.cs` (`SelfX.exe`), `SelfXSessionStarter.cs`, `SelfXWinRT.cs`, `SelfXAudio.cs`, `SelfXDisturb.cs` | C# / .NET 10 (session starter: netstandard2.0) | user / installer |
| Action and check scripts `Sources\Scripts_to_run`, `Sources\HealthChecks` | PowerShell 7 | user or SYSTEM, per catalogue |
| `Install.ps1`, `Uninstall.ps1`, `Detection.ps1`, `Scripts_to_run\Collect-DeviceLogs.ps1` | **Windows PowerShell 5.1** compatible (Intune and Autopilot start them there) | SYSTEM |
| `tools\*.ps1` | Windows PowerShell 5.1 and PowerShell 7 | build machine / CI |

Flow of a System action: window -> named pipe `\\.\pipe\SelfX.Service` (local only) -> service checks the
installed catalogue and the files -> `pwsh.exe -File <script>.ps1` as SYSTEM. Pipe requests: `PING`, `STATUS`,
`HEALTH [<Id> [<base64 name>]]`, `RUN <script>.ps1`.

### Layout

| Path | Contents |
|---|---|
| `SelfX Service\` | The package: `Install.ps1`, `Uninstall.ps1`, `Detection.ps1`, `Version.txt`, 35 `Test-*.ps1`, `Service\` (C# sources, `Service\Projects\` with the project files and `packages.lock.json`), `Sources\` |
| `SelfX Service\Sources\` | Window, helpers (`SelfX*.ps1`, `Localization.ps1`, `SelfXPaths.ps1`), catalogue `Issues_List.xml`, `Health_Config.xml`, `Tool_Config.xml`, `Ticket_Config.xml`, `Network_Test_Config.xml`, `Languages\` (24 files), `Branding\`, `Scripts_to_run\` (33), `HealthChecks\` |
| `SelfX Service\Bin\` | Not in Git. Output of `tools\Build-SelfXBinaries.ps1` with `SelfX.Binaries.json` |
| `tools\` | Build (`Build-SelfXBinaries.ps1`), packaging (`New-SelfXIntuneWin.ps1`, `SelfXPackage.Common.ps1`), wizard (console `New-SelfXPackage.ps1`, window `Start-SelfXPackageWizard.cmd`, `Wizard\`), offline feed (`Export-SelfXOfflineFeed.ps1`, `SelfXOfflineFeed.Common.ps1`), release (`SelfXRelease.Common.ps1`), signing (`SelfXSigning.ps1`), AppLocker / WDAC / SBOM / ASR tools, and their tests |
| `offline-feed\` | NuGet packages of the build and `SelfX.OfflineFeed.json` (SHA512 of each file). `NuGet.config` allows only this folder. |
| `docs\`, `docs\de\`, `docs\images\` | Installation, Configuration, Architecture, Guided-Setup, User-Manual (English; German in `docs\de`) |
| `.github\` | `workflows\service-ci.yml`, `workflows\release.yml`, `CODEOWNERS`, `dependabot.yml`, `PSScriptAnalyzerSettings.psd1` |
| `build\`, `.nuget-cache\` | Not in Git (build output) |

The repository keeps `Sources`. The package build sorts its files by class into `App` (code, listed in
`SelfX.Code.json`) and `Config` (configuration and company scripts, listed in `SelfX.Config.json`); on the device
they are `%ProgramFiles%\SelfX\App` and `%ProgramFiles%\SelfX\Config`. The class of a file is decided in one
place: `Get-SelfXFileClass` in `tools\SelfXPackage.Common.ps1`. Details: `docs\Architecture.md`.

## 3. Security rules (not negotiable)

Every signed-in user can send requests to a service that runs as SYSTEM. Treat every input of the pipe, every
file a user can write and every environment variable as hostile.

**3.1 SYSTEM context and whitelist**
- The service starts a script as SYSTEM only when the **installed** `Issues_List.xml` lists its plain file name
  with `Context` = `System` (or `Health_Config.xml` names it as a remediation) and the file passes the file check.
- `RUN` accepts a plain file name only (letters, digits, `_`, `-`, `.`, ending in `.ps1`; no path, no `..`).
  Never add a request, a field or a parameter that carries a path, an argument, script text or code. System
  scripts have no mandatory parameters; the service starts them without parameters.
- `SELFX_CALLER_SID` and `SELFX_CALLER_ADMIN` are set by the service from the pipe client token. A script may use
  the SID to hand a result to that user, never to decide whether something is allowed.
- Every System action can be started by every user. Add one only when it is safe for everyone and on devices
  with several users. One script has one context: never list a script as `User` and as `System`.
- Configuration never contains executable code; it only selects which listed script runs. A file without a class
  or without a list entry is an error (fail closed), never a default.

**3.2 Pipe and sessions.** Keep these limits; a change needs a test in `Test-ServicePipe.ps1` and a reason in the
pull request. They are constants in `SelfXService.cs`:

| Limit | Value |
|---|---|
| Connections in total / per user | 64 / 8 (applied when the connection is accepted) |
| Deadline for the whole request | 5 s (`RequestReadTimeoutMs`), overlapped I/O |
| Response write / client close | 10 s / 10 s |
| Request length | 512 characters |
| Pause per user after a check / before the same action again | 3 s / 15 s |
| System actions at the same time | 1 (others get *busy*) |
| Script timeout | default 900 s, maximum 7200 s; health 240 s |
| Rejected requests in the log | 20 per minute; log text cleaned and shortened to 600 characters |

- Pipe ACL: network access denied, local authenticated users only. The client checks that the pipe server is the
  running `SelfXService` (process ID from the service control manager).
- `OtherSessions` = `Block` stays on every disturbing action (restart, Windows updates, disk check, restart of the
  network adapters, restart of the Intune service, time synchronization) and on **every** catalogue entry of the
  same script. A normal user is blocked while another user has an active session; elevated administrators are not;
  when the sessions cannot be read, the action is blocked. A new disturbing action gets `OtherSessions` = `Block`.
- The device logs report contains only the data of the requesting user unless an elevated administrator asks.

**3.3 File system and registry**
- SYSTEM never reads from a folder a user can write (`%ProgramData%\SelfX\Logs\Users\<SID>`, `%TEMP%`,
  `%LOCALAPPDATA%`, the profile). User logs are added to a report by the window with the rights of the user.
- Delete code never follows junctions or symbolic links (`Uninstall.ps1`, `/removetree:` and `/cleandata:` of
  `SelfXService.exe`). `Test-Uninstall.ps1` and `Test-SafeDelete.ps1` must keep passing.
- `%ProgramFiles%\SelfX`: SYSTEM and administrators write, users read and execute. `%ProgramData%\SelfX\Cache`:
  SYSTEM and administrators only. `Reports\<SID>`: SYSTEM, administrators and that user.
- Accounts and groups **always by SID**, never by name (names are localized: "Everyone" is "Jeder" on German
  Windows): `S-1-1-0`, `S-1-5-18`, `S-1-5-32-544`, `S-1-5-32-545`. This holds for ACLs, icacls, AppLocker, pipe
  rights and group comparisons, in PowerShell and in C#.
- Paths come from one resolver: `Sources\SelfXPaths.ps1` in PowerShell, `GetConfigRoot` / `GetConfigFilePath` /
  `ResolveScriptPath` in the service. No environment variable, registry value or request may influence them.
- Read XML without DTD. Read a file once and check what was read (no second look by path).

**3.4 No compiling on the device; integrity**
- Nothing is compiled on a device. The programs are built once with `tools\Build-SelfXBinaries.ps1`
  (reproducible; CI builds twice and compares the SHA256). `Install.ps1` checks `Bin` against
  `SelfX.Binaries.json` and the package against `SelfX.Code.json` / `SelfX.Config.json` **before** it changes
  anything, and the installed folder after the copy. Never add `Add-Type` with source text, `csc.exe` or
  `dotnet build` to a file that is installed. (`Add-Type -LiteralPath` of a built, listed DLL is the existing
  pattern.)
- Nobody writes a hash by hand. Hashes, lists and digests are written by the build and the package tools.
- Trust anchor `HKLM\SOFTWARE\SelfX\Trust` (`Mode` = `Hash` or `Signature`, `Signers`): written by `Install.ps1`,
  never taken from the package, read by the service before every start. Missing or unsafe anchor = nothing
  starts (event 4006); failed signature check = nothing starts, also with `Service_FileCheck` = `Audit`
  (event 4007); file differences = event 4005. An empty or malformed signer list is an error, never "allow all".
- No `Invoke-Expression`, no string-built command lines, no plain-text passwords (the PSScriptAnalyzer rules in
  `.github\PSScriptAnalyzerSettings.psd1` fail the CI). Start processes with an argument list. Passwords stay
  `SecureString` and never reach a log, an output or an error message.
- Logs and error messages: no tokens, no passwords, no contents of other users. Log text that comes from a
  request is cleaned first.
- GitHub Actions stay pinned to a full commit SHA, workflow tokens stay `contents: read` (in `release.yml` only the last
  step of the last job gets a token that can write releases), `persist-credentials: false`.

State in every pull request that touches section 3: attack surface, rights context, misuse scenarios, the
countermeasures, remaining risks and the tests.

## 4. Change workflows

**4.1 New or changed action**

| File | What |
|---|---|
| `Sources\Issues_List.xml` | `<Action Id="...">` with a new, stable `Id` (never change a released `Id`); `Context`; for `System` also `TimeoutSeconds` and, when disturbing, `OtherSessions`. Raise `XML_Version` and add a history line. |
| `Sources\Scripts_to_run\<name>.ps1` | Header with `.SYNOPSIS`, `.DESCRIPTION`, `.NOTES` (`Name`, `Package`, `Context : User` or `Context : System`, `Version`, history table). Logging through `SelfXLog.ps1`. Exit code 0 = success. |
| `tools\SelfXPackage.Common.ps1` | Add the new project file to `$script:SelfXCodeFileNames`; otherwise the build stops and `Test-FileManifest.ps1` fails. |
| `Sources\Languages\<culture>.xml` | `<Action Id>` / `<Message Id>` texts. English base text is in `Issues_List.xml`. `de.xml` and `en.xml` are the minimum; this project delivers new texts in **all 24** language files. Keep placeholders (`{0}`) and element names. |
| `Test-Scripts.ps1` (and a test of its own when the script has logic) | The script runs in the sandbox with mocked commands. |
| `docs\Configuration.md` + `docs\de\Configuration.md`, `README.md` + `README.de.md`, `CHANGELOG.en.md` + `CHANGELOG.md` | Describe the action, its context and its effect. |

A new health check or remediation: the same, with `Health_Config.xml` instead of the catalogue and
`Test-HealthStatus.ps1`. Check scripts are read-only.

**4.2 C# and NuGet**
- Versions are fixed in the `.csproj` files; `packages.lock.json` is checked in and the build restores in locked
  mode from `offline-feed` only.
- No new or updated package (also from Dependabot) and no new SDK version without, in the **same** pull request:
  `tools\Export-SelfXOfflineFeed.ps1` (online, same .NET SDK 10; it runs the NuGet vulnerability audit), the
  changed `offline-feed\*.nupkg`, the new SHA512 values in `offline-feed\SelfX.OfflineFeed.json` and the updated
  `packages.lock.json`. `tools\Test-SelfXOfflineFeed.ps1` and the CI job "Build with .NET 10" must pass.
- Never add a package source to `NuGet.config` and never name an internet source in the build script.
- Prefer no new dependency: call Windows directly when that is reasonable (as `SelfXTrust` does).

**4.3 Version and release**
- The version is the one line of `SelfX Service\Version.txt`. `$ExpectedVersion` in `Detection.ps1` must be the
  same value (the packaging script stops otherwise), with a history line in `Detection.ps1`. Without both,
  Intune does not roll out the update. `Tool_Config.xml` does not carry the version.
- Changed files get a new version and a history line in their own header.
- Release: tag `v<Version.txt>` on `main`; `release.yml` runs the CI tests for the tagged commit, builds programs,
  `.intunewin`, payload archive, SBOM and `SHA256SUMS.txt`, takes the notes from the section of the version in
  `CHANGELOG.en.md` and **publishes** the release (a draft only with the repository variable `RELEASE_DRAFT=true`).
  A pushed tag is therefore a public release: create tags only on explicit request.
- Upload to Intune the `build\SelfX-Service-<version>.Detection.ps1` that the build writes, not the copy in the
  repository (it holds the placeholders `__SELFX_CODE_HASH__` and `__SELFX_CONFIG_HASH__`).
- A change must keep working for: new installation, update, uninstall, detection, Autopilot / ESP (a missing
  PowerShell 7 must never make Autopilot fail; an unsafe state is a hard stop).

**4.4 Pull request.** Small and focused. The description names: purpose, affected part (Service, tools, docs),
technical change, security effect, rights context, tests, risks, rollback. Also give a list of the changed files
and a test checklist. Write titles, descriptions and commit messages in English.

## 5. Tests and quality

All of these must pass locally and in CI (`.github\workflows\service-ci.yml`, five jobs) before a change counts
as done. A failing or skipped test is reported, never hidden.

| Set | Files | Where |
|---|---|---|
| Package tests | all 35 `SelfX Service\Test-*.ps1` | PowerShell 7 (job "Tests in PowerShell 7") |
| Tool tests | `tools\Test-SelfXPackageWizard.ps1`, `Test-SelfXOfflineFeed.ps1`, `Test-SelfXAppLockerRules.ps1`, `Test-SelfXAsrEvents.ps1`, `Test-SelfXRelease.ps1`, `Test-SelfXWizardGui.ps1` | PowerShell 7 and Windows PowerShell 5.1 |
| Windows PowerShell 5.1 set (the CI expects exactly twelve) | `Test-Compat51.ps1`, `Test-Detection.ps1`, `Test-FileManifest.ps1`, `Test-InstallBinaries.ps1`, `Test-InstallConfigOnly.ps1`, `Test-Uninstall.ps1` and the six tool tests | job "Tests in Windows PowerShell 5.1" |
| Signing | `tools\Test-SelfXSigning.ps1` | both editions (job "Signing library") |
| Build | `tools\Build-SelfXBinaries.ps1` twice, SBOM, `Test-InstallBinaries.ps1` and `Test-SafeDelete.ps1` with the built `Bin` (`SELFX_REQUIRE_BIN=1`), DLL load, service in console mode | job "Build with .NET 10 (self-contained)" |
| Script analysis | PSScriptAnalyzer 1.23.0 on `SelfX Service` and `tools` with `.github\PSScriptAnalyzerSettings.psd1`; zero findings | job "PSScriptAnalyzer (security rules)" |

`tools\Test-SelfXNetworkMeasure.ps1` and `tools\Test-SelfXTicketRouting.ps1` are check tools for administrators,
not CI tests.

Run locally (each test in its own process, so mocks of one test cannot affect the next):

```powershell
$tests = @(Get-ChildItem '.\SelfX Service' -Filter 'Test-*.ps1') +
         @(Get-Item .\tools\Test-SelfXPackageWizard.ps1, .\tools\Test-SelfXOfflineFeed.ps1, .\tools\Test-SelfXAppLockerRules.ps1, .\tools\Test-SelfXAsrEvents.ps1, .\tools\Test-SelfXRelease.ps1, .\tools\Test-SelfXWizardGui.ps1)
foreach ($t in $tests) { pwsh -NoProfile -ExecutionPolicy Bypass -File $t.FullName; if ($LASTEXITCODE -ne 0) { Write-Warning "$($t.Name) failed" } }
```

Rules for tests:
- A test changes nothing on the device. Every command that changes the system is **mocked**: services, registry
  (use a test key below `HKCU`), ACLs, processes, restart, Windows Update, Defender, Outlook, event log, network.
  Work in a temporary folder. The pipe test starts only the pipe listener under a test pipe name.
- A change to the system infrastructure (service, pipe, installer, uninstaller, trust check, file lists) comes
  with tests in the matching file, including **negative** tests: invalid XML, manipulated paths, links, missing
  files, missing rights, oversized or slow requests, wrong signer.
- Test certificates only as the existing helpers do it (`tools\SelfXTestCertificate.ps1`); adding a root
  certificate needs GitHub Actions or `SELFX_TEST_ALLOW_ROOT_IMPORT=1`.
- When a test file is added to the Windows PowerShell 5.1 set, update the list and the expected count in
  `service-ci.yml`.
- Tests that cannot run locally (Autopilot, Intune, a second signed-in user, AppLocker / WDAC enforcement) go
  into the pull request as a manual test list. Say plainly what was not tried on a device.

## 6. Style and conventions

- **Language:** code, comments, identifiers, commit messages and pull requests in English. Documentation in
  English **and** German, English leading: `README.md` / `README.de.md`, `docs\*.md` / `docs\de\*.md`. Note the
  older naming of three pairs: `CHANGELOG.en.md`, `SECURITY.en.md`, `NOTICE.en.md` and
  `SelfX Service\README.en.md` are English, the files without `.en` are German. Change both files of a pair in
  the same pull request.
- **Writing:** plain, short sentences for administrators and users; no marketing. User-facing texts must be
  understandable without IT knowledge.
- **Changelog:** new entries under "Unreleased" in both changelog files: what changed, changed behaviour, tests,
  and what was not tried on a device. Facts only.
- **Public texts** (commits, pull requests, issues, code, docs): no personal data, no names of persons, no
  internal host names, addresses or tenant names, and no "decided by ..." reasoning; describe what changed and
  how it works.
- **Placeholders stay placeholders:** `Sources\Branding\company_logo.png`, `example.com` addresses and the sample
  company "Contoso" are the delivered configuration. Never replace them with real company data in the
  repository; real values enter through the package wizard on a copy in `build\`. Default images (`logo.png`,
  `Repair.ico`, `icon_systray.ico`) are code and are not replaced in place.
- **PowerShell:** follow the file you edit (tabs or spaces as found, `$ErrorActionPreference = 'Stop'`,
  `-LiteralPath`, explicit error handling, no silent `catch {}`). Files that must run in Windows PowerShell 5.1
  use no PowerShell 7 syntax (`Test-Compat51.ps1` checks this); a script with non-ASCII characters needs a UTF-8
  byte order mark. Style rules of PSScriptAnalyzer are deliberately not enforced; do not reformat files.
- **C#:** one source file per program, no new project or package without need, constants for every limit,
  comments say why.
- **Scope:** change as little as possible. No drive-by refactoring, no new framework, no telemetry.
- **Screenshots** in `docs\images` show sample data only. Do not replace them unless asked.
