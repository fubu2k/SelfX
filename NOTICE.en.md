# Notices on authorship and licenses

As of 2026-11-22. This repository is a fork of SelfX (the SelfX Service package only). The license file
[LICENSE.md](LICENSE.md) contains the text and the original copyright line of the original project (MIT License) unchanged,
plus the copyright line for the changes in this fork. This notice adds to it and does not replace it.

## Origin

| Part | Author / source | License |
|------|-----------------|---------|
| SelfX (idea, WPF interface, XML action catalogue, troubleshooting scripts) | Damien Van Robaeys, [damienvanrobaeys/SelfX](https://github.com/damienvanrobaeys/SelfX), introduced on [Syst & Deploy (August 2022)](https://www.systanddeploy.com/2022/08/selfx-tool-allowing-users-to-solve.html) | MIT according to his repository (`LICENSE.md`, added 2024-05-21). The blog post names no license. |
| SelfX Service (service, installer, health checks, tests, documentation) | Wolfgang Baeck, [wbaeck/SelfX](https://github.com/wbaeck/SelfX), a fork of damienvanrobaeys/SelfX | His README points to the license of the original project in `LICENSE.md`; there is no separate license file for his additions. |
| Changes in this fork (security hardening, .NET 10 service, PowerShell 7 migration, tests, CI, documentation) | fubu2k, with the help of Claude Code (Anthropic) | Copyright (c) 2026 fubu2k, under the terms of the MIT License in [LICENSE.md](LICENSE.md). |

## Other sources

- **System Information Tool** by Jannik Reinhard
  ([JayRHa/windows-system-information](https://github.com/JayRHa/windows-system-information), MIT License,
  Copyright (c) 2026 Jannik Reinhard): idea and data points of the System information page.
  A comparison on 2026-11-22 (state of his repository: commit `00c5220`, 2026-10-14) found no copied program code:
  no identical function names, no identical functional code lines (only generic keywords and XAML boilerplate) and none of
  his scripts. The only common elements are public Windows data sources (for example the classes `Win32_ComputerSystem` and
  `Win32_OperatingSystem`, the registry path of the MDM accounts and the `intunemanagementextension://` protocol). He is
  named as a source of the idea, not because the MIT License requires it here. If code is taken from there in the future,
  his full MIT notice must be added to this file.
- **Microsoft Win32 Content Prep Tool**: not part of this repository. `tools\New-SelfXIntuneWin.ps1` does not bundle it but
  checks Microsoft's Authenticode signature before using it.
- **Built programs** (service and launcher, .NET 10 self-contained) contain parts of the Microsoft .NET runtime and the
  NuGet package `System.ServiceProcess.ServiceController` (both Microsoft, MIT License).
