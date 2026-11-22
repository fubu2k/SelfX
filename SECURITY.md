# Security policy

SelfX Service runs a Windows service as LOCAL SYSTEM and accepts requests from every signed-in user through a
local named pipe. A weakness can therefore lead to privilege escalation on every managed device. Please report
it privately.

## Reporting a vulnerability

- Use **GitHub private vulnerability reporting** of this repository (*Security* tab, *Report a vulnerability*).
- Do **not** open a public issue or pull request for a vulnerability before a fix is available.
- Include the version from the script or source header, the Windows
  build, the execution context (user, administrator, SYSTEM, Intune deployment) and the steps to reproduce.
- Do not include tokens, passwords, device logs with personal data or internal host names.

You get an answer within 14 days. Fixes are made on a `security/...` branch and merged through a pull request;
the release notes name the finding once a fixed version is available.

## Scope

In scope, with priority:

- **SelfX Service**: `SelfXService.cs` and its named pipe protocol, the action catalogue (`Issues_List.xml`,
  `Health_Config.xml`), every script that runs with `Context : System`, `Install.ps1`, `Uninstall.ps1`,
  `Detection.ps1`, file and folder permissions under `%ProgramFiles%\SelfX` and `%ProgramData%\SelfX`.
- `tools/New-SelfXIntuneWin.ps1` (packaging).

Out of scope: weaknesses that require administrator rights on the device beforehand, and third-party binaries
(report those to their vendor).

## Supported versions

Only the latest version on `main` of this fork is supported. Upstream: https://github.com/wbaeck/SelfX
