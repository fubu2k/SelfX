# Configuration

**English** | [Deutsch](../Configuration.md)

SelfX uses XML files for its settings and its action catalogue. Edit them in
the package before installation.

## SelfX Service

SelfX Service is configured with the files in `SelfX Service\Sources`. Edit them in the package before installation. After
installation, the files in `%ProgramFiles%\SelfX` can be changed only by
administrators. Deploy changes by publishing a new package version. There is no
remote update and no download at launch.

### Action catalogue

`Issues_List.xml` has the structure `XML_Version`, `Quick_Solution`,
`Detailed_Solution`, `Action` with English base texts. It also contains:

- An `Id` attribute on every action, for example `<Action Id="D_Teams_SoundCuts">`.
  It must be unique. The language files use it to translate the action.
- An optional `Messages` section with texts shared by several actions.
  `Explanation` and `Alerte_MSG` can point to one of them with
  `Ref="<message Id>"` instead of their own text, for example
  `<Alerte_MSG Ref="Msg_Teams_Restart"/>`.
- `Category` contains a category Id (`Browser`, `Device`, `Intune`, `Office`,
  `OneDrive`, `Outlook`, `Teams`). The displayed name comes from the language
  file.

Each action has these additional elements:

| Element | Values | Purpose |
|---|---|---|
| `Context` | `User` or `System` | `User` runs the script as the signed-in user. `System` sends the script name to the SelfXService, which runs it as SYSTEM. If the element is missing or has another value, the action is treated as `User`. |
| `TimeoutSeconds` | 1–7200, default 900 | Only for `System` actions. The service stops the script and its child processes after this time and reports a timeout. |
| `OtherSessions` | empty or `Block` | Optional, only for `System` actions. `Block`: a normal user cannot start the action while another user has an **active** session on the device (the service answers `ERROR OtherSessions`, the window shows a notice). Elevated administrators are not restricted. If the sessions cannot be read, the action is blocked (fail closed). Set it on every entry of the same script; the service blocks when any `System` entry of the script says `Block`. Default in the delivered catalog: restart of the Intune service, restart of the network adapters and the CHKDSK repair. |
| `Post_Action` | empty or `MailReport` | Optional, only for `System` actions. `MailReport`: after a successful run the GUI attaches the newest report of the user to a new support e-mail. See [Device logs for the support](#device-logs-for-the-support-selfx-service-240). |

Example:

```xml
<Action Id="D_Intune_RestartService">
	<Name>Restart Intune service</Name>
	<Buttons>Ok_Cancel</Buttons>
	<Explanation>You want to force a synchronization between your device and Intune.</Explanation>
	<Script>SelfX_Intune_RestartService.ps1</Script>
	<Context>System</Context>
	<TimeoutSeconds>300</TimeoutSeconds>
	<Category>Intune</Category>
	<Alerte_MSG>The Intune Management Extension service will be restarted.

Do you want to continue?</Alerte_MSG>
</Action>
```

Rules for `System` actions:

- `Script` must be a plain file name made of letters, digits, `_`, `-` and `.`,
  ending in `.ps1`. The file must be in `Scripts_to_run`. The service rejects
  all other names.
- The same script may appear in several actions, for example in the simplified
  and the detailed view. The first `System` entry for a script sets its
  `TimeoutSeconds`.
- The script runs non-interactively as SYSTEM: there is no user profile, no
  desktop and no prompts. Use non-interactive commands, return a meaningful
  exit code (`0` = success), and write diagnostic output to stdout or stderr.
  The output is logged.
- Any signed-in user can start any `System` action. Only add actions that are
  safe for every user.
- The service passes the SID of the requesting user in the environment
  variable `SELFX_CALLER_SID` (read from the pipe client token, SelfX Service
  2.4.0 and later). Use it only to deliver results to that user, never to
  decide whether an action is allowed.

When you add an action, give it a new `Id` and add its translations to the
language files (see [Languages](#languages)). Without a translation, the English
text from `Issues_List.xml` is shown.

The included `System` actions are:

| Script | Purpose |
|---|---|
| `SelfX_Intune_RestartService.ps1` | Restart the Intune Management Extension service |
| `SelfX_Device_AirePlaneMode.ps1` | Restart all enabled physical network adapters |
| `SelfX_Device_SyncTime.ps1` | Synchronize the clock with the configured time source (`w32tm /resync /force`, configuration unchanged) |
| `SelfX_OneDrive_CHKDSK.ps1` | Schedule `chkdsk /r /f` of the system drive for the next restart |
| `SelfX_Device_CollectLogs.ps1` | Collect the device logs with `Collect-DeviceLogs.ps1` and open a support e-mail with the report (`Post_Action` `MailReport`) |

### UI settings

`Tool_Config.xml` contains only settings. All texts of the window are in the
language files (see [Languages](#languages)). Text keys such as `Main_Title_Text`,
`Subtitle_Text` or `SystemInfo_*_Text`, `Link_Scripts` and install toast keys
are not used.

| Key | Purpose |
|---|---|
| `Tool_Language` | Default language. `de` (default, base language) shows German. `Auto` uses the Windows display language of the user (German if no language file matches). Another culture name such as `en`, `fr-CH` or `zh-Hans` sets that language. Texts that are missing in a language are shown in English. Users can choose another language in the settings unless `Show_Language_Setting` is `False`; see [Languages](#languages). |
| `Tool_Name` | Text in the title bar and the About dialog |
| `Shortcut_Desktop`, `Shortcut_StartMenu`, `Shortcut_Name` | Shortcuts for all users created by `Install.ps1` |
| `Show_Computer_Name_MainGUI`, `Show_Computer_Name_title_bar` | Show the computer name beside the title |
| `Default_Solution_Mode` | `Simplified` or `Detailed` |
| `Show_Reboot_Warning`, `Show_About_Button` | Show or hide the reboot reminder and the About button (i) |
| `Show_Theme_Button` | `True`: users can choose the appearance (Automatic as Windows, Dark or Light) in the settings dialog (gear) |
| `Show_Language_Setting` | `True` (default, 2.5.9): users can choose the language of SelfX in the settings dialog. `False` hides the choice and always uses `Tool_Language`; a language saved earlier by a user is then ignored. |
| `Show_Support_Button`, `Support_Hours`, `Support_Phone_number`, `Support_Mail`, `Support_Teams`, `Support_Website` | Help button (?) and the contacts of the help dialog, see [User interface](#user-interface-selfx-service-250). `Support_Mail` is also the recipient of the device logs e-mail. |
| `DeviceLogs_Days`, `DeviceLogs_Compress` | Device logs report: days of event log history (1–60, default 7) and `.zip` (`True`, default) or `.txt` attachment |
| `Ticket_Enabled`, `Ticket_Mail`, `Ticket_Subject_Tag` | Ticket by e-mail (off by default): button *Create ticket* in the help dialog. `Ticket_Mail` is the recipient (empty = `Support_Mail`, exactly one address, only from this configuration), `Ticket_Subject_Tag` the marker at the start of the subject for filters (letters, digits, `.`, `_`, `-`, up to 20 characters, otherwise `SelfX`) |
| `Log_Retention_Days` | Log files older than this number of days are deleted (1–3650, default 90, 2.6.0); see [Logging](#logging-and-log-housekeeping-selfx-service-260) |
| `Show_Status_Page` | `True` (default): show the Device status page |
| `Show_SystemInfo_Tab`, `Show_SystemInfo_Intune_Actions`, `SystemInfo_Internet_Test_Host`, `SystemInfo_Internet_Test_Port` | System information page and its tools |
| `Show_Tray_Icon`, `Tray_Notifications`, `Tray_Poll_Seconds` | Tray icon, see [Tray icon](#tray-icon-selfx-service-250) |

Increase `Tool_Version` for each release and set the same value in
`Detection.ps1`.

### User interface (SelfX Service 2.5.0)

The window is designed for users without technical knowledge. It can be
resized and maximized (minimum 640 × 480); below 900 pixels the navigation bar
shows only icons and the cards rearrange in one to three columns. Size,
position, theme, language and the tray icon choice are stored per user in
`HKCU\Software\SelfX`. Only one SelfX window runs per user: a second start
(shortcut or tray icon) brings the open window to the front.

- **Navigation bar** (left): *Troubleshooting*, *Device status* (with a counter
  of problems and warnings), *System information*, the company logo
  (`Brand_Logo`) at the top, **Send logs to support** and the state of the local
  service at the bottom.
- **Troubleshooting**: search field, category buttons, switch between the
  simplified and the detailed view (the info icon explains the difference) and
  one card per action with an info icon (explanation), a play button (run, with
  confirmation) and a shield for actions with administrator rights. While an
  action runs (2.6.1), its play button shows a rotating icon and *Running…* and
  is locked; it returns to normal as soon as the action has ended. System actions
  end when the service has answered; user actions are watched until their script
  process has ended, then the result (exit code 0 = success) is shown in the
  message bar and logged. The **Fix** button of a status card does the same while
  its repair runs.
- **Device status**: one card per check, problems first. The color and the
  label show OK, Pending (warning), Error or Unknown. **Fix** (wrench) runs the
  configured repair after confirmation; the arrow button checks only this
  status again; the arrow button at the top checks everything. **Fix all
  problems** (2.5.3) appears when at least one Error or Pending card has a
  repair; after one confirmation it runs each configured repair once (one per
  script, one after another through the service) and then checks everything
  again. If the service is unavailable or busy, the remaining repairs are
  skipped and reported. Times are collected as UTC (`{utc:...}` markers in
  health details) and shown in the current time zone of the user, also after
  an automatic time zone change during the OOBE. The status of
  the background checks of the service is shown immediately, see
  [Background checks](#background-checks-and-status-cache-selfx-service-250).
- **System information**: one card per section (device, Windows, user and
  management, network, report); double-click a line to copy its value. The last
  collected values are shown immediately from `%LOCALAPPDATA%\SelfX\SystemInfo.json`
  and updated in the background. Refresh, copy and export (TXT, HTML, CSV, JSON)
  are icon buttons; copy and export include the device status. The *Tools*
  (Intune sync, compliance check, Company Portal, Quick Assist, MDM logs, send
  logs) are tiles below the information.
- **Title bar**: help (?), settings (gear: language, theme, tray icon) and About (i).
- **Help dialog**: shows only the configured contacts: `Support_Hours`,
  `Support_Phone_number`, `Support_Mail` (button *Write e-mail*),
  `Support_Teams` (button *Start chat*: a user or shared mailbox address opens a
  Teams chat, a full `https://` Teams link is opened as is) and
  `Support_Website` (button *Open*, only `http://` or `https://`). Without any
  contact the dialog asks the user to contact the IT department.

Every icon button has a tooltip that explains what happens. Confirmations,
explanations and messages use dialogs in the same style; results of actions
and the reboot reminder appear in the message bar at the bottom.

### Background checks and status cache (SelfX Service 2.5.0)

The service runs all health checks regularly in the background and keeps the
result in `%ProgramData%\SelfX\Cache\Health.json` (readable by SYSTEM and
administrators only). SelfX and the tray icon read it with the request
`STATUS`, which answers immediately and runs nothing. Every check that SelfX
starts (all, or a single status) also updates the cache.

Settings in `Health_Config.xml`:

```xml
<Background Enabled="true" IntervalMinutes="15" PauseOnBattery="true" MaxCpuPercent="75" StartDelaySeconds="120" />
```

| Attribute | Default | Purpose |
|---|---|---|
| `Enabled` | `true` | `false` = no background checks; SelfX then checks when it is opened. |
| `IntervalMinutes` | `15` | 5–1440. Time between two background checks. |
| `PauseOnBattery` | `true` | No background check while the device runs on battery. SelfX shows the last result and the note that the checks are paused. |
| `MaxCpuPercent` | `75` | 10–100. A check is postponed (retry after 2 minutes) while the processor load is higher; `100` = no limit. |
| `StartDelaySeconds` | `120` | 0–3600. First check after the start of the service, so the sign-in is not slowed down. |

Missing or invalid values use the default. A background check is also
postponed while a repair is running. It runs PowerShell with below-normal
priority and the 240-second limit of the health collection; only a summary
line is written to `SelfXService.log`. Changes of the settings apply without a
restart of the service.

### Tray icon (SelfX Service 2.5.0)

`SelfX_Tray.ps1` shows a SelfX icon in the notification area with a colored
dot: green (OK), yellow (warning), red (problem) or gray (status not available
yet). The tooltip shows the number of problems and warnings. When a check
changes to Error, for example *Disk capacity*, a Windows notification is shown
once; clicking it opens the Device status page. On Windows 10 and 11 these
notifications are shown as Windows toast notifications (and kept in the
notification center). The right-click menu opens SelfX, the device status,
checks the status now, sends the logs to the support, switches the
notifications on or off (2.6.5) or hides the icon.

| Key in `Tool_Config.xml` | Default | Purpose |
|---|---|---|
| `Show_Tray_Icon` | `True` | `Install.ps1` creates the HKLM Run entry `SelfXTray`, so the icon starts at every sign-in for all users, and (as SYSTEM, since 2.5.8) starts it right away for the signed-in users. `False` removes the entry. |
| `Tray_Notifications` | `True` | Show a notification when a check changes to Error. Each user can switch the notifications off (2.6.5). `False` switches them off for all users and hides the user switch. |
| `Tray_Poll_Seconds` | `60` | 15–3600. How often the icon reads the cached status (no check is run). |

**Notifications per user (2.6.5):** each user decides whether Windows
notifications are shown in addition to the colored icon: switch *Show
notifications about problems* in SelfX > Settings, or *Show notifications* in
the menu of the icon. The choice is stored in `HKCU\Software\SelfX\TrayNotifications`
(1 = on, default; 0 = off) and applies at once without a restart of the icon.
While they are off, the icon still shows the problem (red dot, tooltip) and
problems are still remembered, so switching the notifications on again does not
announce problems that were already known. Answers to actions of the user
(*Check status now*, *Hide this icon*) are always shown.

SelfX Service has no notification after the installation.

Each user can hide the icon (menu *Hide this icon* or SelfX > Settings) and
show it again in SelfX > Settings; the choice is stored in
`HKCU\Software\SelfX\TrayIcon`. The icon needs no administrator rights: it
only reads the status cache through the pipe of the service. Shortly after the
start it collects the system information of the user once in the background,
so SelfX shows it immediately. An installation or update through Intune/SCCM
(SYSTEM) closes the running icons and starts the new version right away in
the sessions of the signed-in users (2.5.8); users who switched the icon off
do not get it back. After an uninstall the icons are closed.
Opening SelfX also starts the icon when it is not running yet (for example
after a manual installation).

### Device logs for the support (SelfX Service 2.4.0)

The action **Send the device logs to the support** (`Q_Device_SendLogs` in the
simplified view, `D_Device_SendLogs` in the detailed view, category `Device`)
and the buttons **Send logs to support** (navigation bar, System information page and tray icon) collect
all logs that are needed to analyze a device problem and open a new e-mail to
the support with the report attached. The user describes the issue and sends
the e-mail; nothing is sent automatically.

How it works:

1. The user confirms the action. The GUI sends `RUN SelfX_Device_CollectLogs.ps1`
   to the local service (shield action, timeout 1800 seconds).
2. The service runs the wrapper as SYSTEM and passes the SID of the requesting
   user in `SELFX_CALLER_SID`. The wrapper starts the read-only collector
   `Scripts_to_run\Collect-DeviceLogs.ps1` with administrator rights. It writes
   one report to `%ProgramData%\SelfX\Reports\<user SID>\DeviceLogs-<computer>-<time>.txt`
   and compresses it to a `.zip` file (unless `DeviceLogs_Compress` is `False`).
3. The report folder of the user has a protected ACL: SYSTEM and
   Administrators have full control, only the requesting user can read. No
   other user can read the report. The previous report of the user is deleted
   at each run; reports older than 7 days are deleted for all users.
4. After a successful run the GUI copies the report to
   `%LOCALAPPDATA%\SelfX\Reports` and opens a new e-mail with the copy attached:
   - classic Outlook through COM: recipient `Support_Mail`, localized subject
     (`Report_Mail_Subject`) and text (`Report_Mail_Body`) are filled in;
   - otherwise `outlook.exe /a <file>` (the user enters the recipient);
   - otherwise (for example new Outlook, which has no COM interface) the
     default mail app through `mailto:` and an Explorer window with the file
     selected, so the user can attach it.

The collector only reads the device: it changes nothing, loads no hive, starts
no installation and sends nothing. The report contains the computer name, user
and tenant names and log content of the device (Autopilot/ESP state, IME and
Win32 app logs, servicing logs, event logs, AppX, Windows Update, network and
language state). It runs in about one to a few minutes. The section list and
the parameters are described in the header of `Collect-DeviceLogs.ps1`; replace
the file to update the collector.

**Scope of the report on multi-user devices (2.6.10):** the report is cut per
user. The service reads the token of the pipe client and passes
`SELFX_CALLER_ADMIN` to the script: `1` only if the local group *Administrators*
is **enabled** in that token (an elevated administrator), otherwise `0`. A
missing or any other value (for example an older service) counts as a normal
user (fail closed).

| | Administrator (`1`) | Normal user (`0` or missing) |
|---|---|---|
| Collector | complete | `-UserView -CallerSid <own SID>` |
| Serial number, console user | yes | no |
| Sessions (`quser`) | all | own session only |
| Join state (`dsregcmd`) | everything | join and sign-in state only, no tenant, device or user IDs |
| Profiles and user hives | all | own profile and own hive |
| AppX user entries | all | own entry |
| Names, SIDs and profile folders of other local users in any line | as they are | replaced by `<other user>` |
| SelfX machine logs (`SelfXService.log`, script logs) | yes | no (they name all users) |
| Own SelfX user logs | yes | yes |

The collector also runs without `-UserView` (Intune Win32 app, remediation,
manual run): the report is then complete as before. Note that an administrator
who runs SelfX **without** elevation is treated as a normal user, because the
Administrators group is only deny-only in the filtered token.

**SelfX logs in the report (2.6.4, changed in 2.6.10):** the report contains the
logs of SelfX itself (see [Logging](#logging-and-log-housekeeping-selfx-service-260)).
They are added by two different parties, each with its own rights:

- the **wrapper (SYSTEM)** adds, **for administrators only** (see the table above), the machine logs from `%ProgramData%\SelfX\Logs`:
  `SelfXService.log`, `Install.log` and `Uninstall.log` always, all other `*.log`
  files (scripts, health checks, detection) of the last `DeviceLogs_Days` days.
  Only the files directly in that folder are read; the subfolder `Logs\Users` is
  never read as SYSTEM;
- the **SelfX window (the signed-in user)** adds the logs of the **own user**
  (window, status icon, user actions) from
  `%ProgramData%\SelfX\Logs\Users\<own SID>` of the last `DeviceLogs_Days` days
  to its copy of the report in `%LOCALAPPDATA%\SelfX\Reports`, with the rights
  of the user. Logs of other users are never added.

In the `.zip` they are separate files in the folder `SelfX-Logs` (`SelfX-Logs\User`
for the user logs); in a `.txt` report they are appended as the last section.
At most the last 2 MB of each file and 30 MB per party are added.

Why: users can create and change their own folder under `Logs\Users`. If SYSTEM
read it, a user could redirect the read (for example with a junction replaced
between the check and the read) to a protected file, whose content would then be
in the report that the user can open. Because the window reads the own logs with
the rights of the user, it can only add what the user could read anyway. A
problem while adding the user logs never stops the e-mail. Skipped are a
junction as folder and files that another account owns.

Note that `SelfXService.log` (machine logs) names the users who started actions
on this device.

Exit codes of `SelfX_Device_CollectLogs.ps1`: `0` report created, `1`
collection or compression failed, `2` requesting user unknown (service older
than 2.4.0). The wrapper writes the collector summary and the report path to
`SelfXService.log` and (2.6.0) to its own log.

To use the feature with another report script, keep `Post_Action` `MailReport`
and write the report as `DeviceLogs-*.zip` or `DeviceLogs-*.txt` to
`%ProgramData%\SelfX\Reports\<SELFX_CALLER_SID>` with the same ACL. Remove both
catalogue actions to hide the feature; the System information button is shown
only when a `System` action with `MailReport` exists.

### Ticket by e-mail (SelfX Service 2.8.5, assignment 2.8.6)

Optional and off by default (`Ticket_Enabled` = `False`). When enabled and a valid address is set, the help dialog (?) shows the row *Report an issue* with the button *Create ticket*.

**Flow (user context, no elevated rights):**
1. The user describes the issue (up to 3000 characters).
2. SelfX **always** adds the device information: all rows of *System information* and *Device status*, plus device name, Windows build and SelfX version. The user cannot switch it off but sees it in the opened e-mail.
3. The e-mail is only **displayed, never sent automatically**. The user checks it and sends it.

**Hand-over to the mail program:**
- Classic Outlook (COM): recipient, subject, complete text and the file `TicketInfo-<device>-<time>.txt` attached.
- New Outlook and other mail programs (mailto): recipient, subject and text; the link length is limited, so the text is cut if needed (description and core fields first, device information last). The complete file is selected in Explorer and the user attaches it (the dialog says so).
- The file is in `%LOCALAPPDATA%\SelfX\Reports` (user only); older `TicketInfo-*` files are deleted with the next ticket.

**E-mail layout (for filters and automation):** subject `[<Ticket_Subject_Tag>][<kind>] <device>` (kind in the language of the user, for example *Incident*); body with fixed English field names (`Time (UTC)`, `Computer`, `Windows build`, `SelfX version`), then `Description of the user:` and `Device information:`, both as fenced blocks.

**Assignment to the IT unit (`Ticket_Config.xml`):** The file is in the install folder (only administrators can change it) and contains **any number** of IT units and rules. Nothing is fixed in the code.
- `<Unit Id="IT1" Mail="it1@example.com" Cc="" />`: unit with recipient and optional Cc (Id: letters, digits, `.`, `_`, `-`, up to 40 characters; exactly one plain address each).
- `<Rule Source="GroupTag|OU|Category" Match="..." Unit="IT1" />` or `<Rule Source="..." Regex="..." />`: `Match` is an exact value (case is ignored), `Regex` a .NET expression (up to 300 characters, time limit 200 ms). With `Regex`, `Unit` can be left out when the expression has a named group `(?'unit'...)`; its text is then the unit, for example `^[A-Z]{2}-(?'unit'IT[0-9]+)-[A-Z]{3}$` for group tags like `DE-IT1-BER`. Rules are checked from top to bottom and the **first match wins**; without a match the e-mail goes to `Ticket_Mail` (otherwise `Support_Mail`) of `Tool_Config.xml`.
- Values of the device (read only): `GroupTag` and `Category` from `HKLM\SOFTWARE\SelfX\Support` (REG_SZ, only administrators can write, for example set by Intune; letters, digits, spaces, `.`, `_`, `-`, up to 64 characters), `OU` from the distinguished name of the computer account (hybrid devices, `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine`). Invalid values count as empty.
- **Address per device (registry, takes precedence):** When `HKLM\SOFTWARE\SelfX\Support` contains `TicketMail` (and optionally `TicketCc`), recipient and Cc are exactly these; the rules in `Ticket_Config.xml` are then not needed. Each address must be exactly one plain address, otherwise the value is ignored (the rules apply, then the default address). Intune sets the values per Entra device group (example in the [installation guide](Installation.md)); when a device changes the group, the values change with the script of the new group, without a new package.
- **Privacy and compliance:** Only shared (functional) mailboxes should be used, no personal mailboxes. `Ticket_Config.xml` is on every device and can be read by every user: addresses that not every organisational unit should see do not belong in this file but in the per-device registry values (which hold only the address of the own unit).
- Entries that are not valid (wrong address, unknown unit, invalid expression, duplicate Id, more than 500 units or 2000 rules) are skipped and named as a warning in the SelfX log; if the file cannot be read, the default address is used. The recipient is shown in the dialog ("The e-mail goes to: ..."), the user cannot change it.
- Group tag, unit and category are fields of the ticket (`Group tag`, `Support unit`, `Device category`).
- Check before distribution: `tools\Test-SelfXTicketRouting.ps1 -GroupTag ... -Category ... -OU ...` shows errors of the file and the result for the given values (sends nothing, reads no registry).

**Security:** Recipient and Cc come only from `Tool_Config.xml` and `Ticket_Config.xml` (writable by administrators only) and must be exactly one plain address each; the user cannot change them. Fields are cleaned (no line breaks in the subject, fixed lengths, the device name must be a valid name). Free text and device information are in code blocks so a ticket system does not run commands from them (for example GitLab quick actions); test whether this works in your GitLab version before enabling. The device information contains addresses (for example the proxy) and device data and is meant for IT: clarify privacy and works council questions before enabling. The log names only the result (`Outlook`, `Manual`, `Error`) and the number of rows, never the text.

### Logging and log housekeeping (SelfX Service 2.6.0)

All SelfX Service scripts log to `%ProgramData%\SelfX\Logs` through the shared
module `Sources\SelfXLog.ps1`: the window, the status icon, the health checks,
the compliance check, the detection script and every action and repair script.
One file per script and day, `<Script>_<yyyy-MM-dd>.log`, UTF-8 with BOM, one line
per entry in the local time of the device:

```text
2026-11-06 13:29:56.522 | Info    |  52068 | SelfX 2.6.0 opened: language de (setting de), page ''.
2026-11-06 13:30:04.426 | Warning |  52068 | Message (Warning): Windows restarts in about 30 seconds. ...
```

| Folder | Content | Readable by |
|---|---|---|
| `Logs` | Scripts that run as SYSTEM (repairs and System actions started through the service, `HealthStatus`, `Check-Compliance`, `Detection`), `SelfXService.log`, `Install.log`, `Uninstall.log` | SYSTEM and administrators |
| `Logs\Users\<SID>` | Scripts of the user: the window (`SelfX_*`), the status icon (`SelfX_Tray_*`) and the user actions | The user, SYSTEM and administrators |

The window logs its start, every action with the answer of the user, the result
of every service action (status and exit code), the status checks started by the
user, the language changes and **every message shown to the user**. The status
icon logs status changes, notifications and why it stops. Each action script logs
its steps and its result; unexpected errors are logged before the script ends.
`HealthStatus` logs every check result of the background checks (one line per
check every 15 minutes).

`Install.ps1` creates `Logs\Users` so that users can only create their own
folder (CREATOR OWNER = full control on it) and cannot list or read the folders
of other users. A folder that is a link or belongs to another account is never
used. Without that folder (installations before 2.6.0, or when it cannot be
used) the user logs go to `%LOCALAPPDATA%\SelfX\Logs`.

**Housekeeping:** log files older than `Log_Retention_Days` in `Tool_Config.xml`
(1–3650, default **90**) are deleted:

- The SelfX service deletes old `*.log` and `*.old` files in `Logs` once a day
  (first time after the start delay of the background checks), also while the
  background checks are disabled, and logs the number of deleted files in
  `SelfXService.log`.
- Each user deletes the old files of the own `Logs\Users\<SID>` folder, at most
  once a day, when a SelfX script starts. The service never deletes inside
  `Logs\Users`: users can create folders there, and a deletion as SYSTEM must not
  follow a link that a user could create.

`Uninstall.ps1` keeps the logs; `-RemoveLogs` deletes `%ProgramData%\SelfX`.

### Health status (SelfX Service 2.3.0)

The Device status page (since 2.5.0; before in the System information tab)
shows the result of the local health checks of the service. It reads the
status cache of the background checks when SelfX opens and requests `HEALTH`
when the user checks again. It displays **OK** (green), **Pending** (yellow warning),
**Error** (red), or **Unknown** (gray). Pending means an outstanding action
(updates to install, device not compliant yet); it is a warning, not an error.
Unknown means missing data, an unsupported source, or an unavailable
service; it is not a successful check. Technical details remain in English;
labels and status words follow the UI language. Copy and all exports include
the results. Existing device, Windows, user/management, network and report
sections remain first; health status is appended below them in the same list.
The report is a snapshot, not continuous monitoring.

Configure `Sources\Health_Config.xml` before packaging. The installer copies it
alongside `HealthStatus.ps1`, with write access only for administrators/SYSTEM.
The client cannot supply a path or code to the service.

| Check | Interpretation |
|---|---|
| IME | `IntuneManagementExtension` must be running; missing or stopped is Error. |
| Defender | Service, antivirus and real-time protection must be enabled; signatures must not be reported outdated and must be at most 7 days old. Passive mode/third-party antivirus can therefore produce Error. A failed query is Unknown. The detail starts with the signature version and the time of the last signature update, followed by product and engine version. By default the row offers **Fix**, which runs `Update-MpSignature` (see [Health remediation](#health-remediation)). |
| Compliance | Intune evaluates compliance in the cloud; Windows stores no local compliance state, so SelfX cannot read the Company Portal status. Since 2.5.5 the package ships `HealthChecks\Check-Compliance.ps1`, enabled with `<Compliance Script="Check-Compliance.ps1" />`: it checks the local criteria of a typical Intune Windows compliance policy (Intune enrollment, BitLocker on the system drive, Secure Boot, TPM, firewall for all profiles, Defender antivirus/antispyware/real-time protection, up-to-date signatures, optional minimum OS version) and shows the criteria that are not met. Align `$Require` in the script with your compliance policy; the Company Portal stays authoritative. Exit `0` = OK, any other exit code = **Pending** (warning). Missing script, exception or timeout are Error. Without the `Compliance` element the row is Unknown. While the row is not OK, it offers **Fix** to update the Defender signatures, the most frequent cause after a longer absence. |
| Applications | Best-effort **local IME Win32 app reporting cache**, plus configured application probes. Known cached success (`1000`) is OK; failure states (`5000` through `5999`) are Error; other states are Unknown. Error takes precedence over Unknown, which takes precedence over OK. With no included results, the overall result is Unknown. |
| Disk | Every fixed logical disk: Error when used space is **at least 90% OR free space is below 20 GiB** (displayed as GB, PowerShell `1GB`). Exactly 20 GiB is sufficient only if usage is below 90%. Thresholds are configurable. |
| BitLocker | Every returned OS/fixed-data volume must be fully encrypted with protection On; suspended, unencrypted or partially encrypted volumes are Error. Unsupported/unreadable data is Unknown. No keys or recovery secrets are collected. |
| Pending reboot | Error when Windows reports a pending restart: the Component Based Servicing `RebootPending` key, the Windows Update `RebootRequired` key, `RebootRequired` of the Windows Update Agent (`Microsoft.Update.SystemInfo`), updates of the Windows Update orchestrator that wait for the restart (`ReadyToReboot`, Windows 11 24H2+, what Settings shows as *Restart now*; since 2.6.9, the detail names the updates), or a pending computer rename. `PendingFileRenameOperations` is deliberately ignored because installers and security products often leave it set permanently. Unreadable registry data is Unknown; a failing Windows Update API does not hide the registry result. |
| Updates to install | Searches only the **local Windows Update Agent cache** (offline, no scan, download or installation). Any not-installed, not-hidden update (except browse-only/optional ones) is **Pending** (warning) and listed in the detail. An empty cache is OK only if the last successful Windows Update scan is at most `MaxSearchAgeDays` old (default 14); otherwise, or when the scan date is unknown, the result is Unknown. Updates deployed only through ConfigMgr are not part of this cache view. While the row is Pending, **Fix** installs the pending Windows updates and starts the Microsoft Store app updates as SYSTEM, without a restart (since 2.5.6, see [Health remediation](#health-remediation)). |
| Additional services | Exact service name and expected state (`Running` or `Stopped`). |
| Script checks | Exit `0` = OK; exit `1` = Error. Other exit codes, missing files, exceptions and timeouts are also Error. |

**Application limitations:** the IME registry cache is an implementation detail,
not a stable Microsoft API, installed-software inventory, or live Intune report.
It can be stale and can contain several user/device records for the same app.
All available included records are considered (a failed record is not discarded
because another record succeeded). Cache format changes or unreadable data
produce Unknown. A successful installation does not prove that the application
works. Use explicit probes for non-IME apps or functional checks; SelfX cannot
automatically diagnose every installed application.

```xml
<HealthConfig>
  <Disk UsedPercentError="90" MinimumFreeGB="20" />
  <Updates MaxSearchAgeDays="14" />
  <Applications>
    <Exclude Name="Test application*" />
    <Exclude Name="00000000-0000-0000-0000-000000000001" />
    <Application Id="00000000-0000-0000-0000-000000000002"
                 Name="Business client" />
    <Application Name="Business client"
                 Script="Check-BusinessClient.ps1" TimeoutSeconds="15" />
  </Applications>
  <Services>
    <Service Name="Spooler" Expected="Running" />
  </Services>
  <Compliance Script="Check-Compliance.ps1" TimeoutSeconds="30" />
  <CustomChecks>
    <Check Name="Local support data"
           Script="Check-SupportData.ps1" TimeoutSeconds="10" />
  </CustomChecks>
</HealthConfig>
```

Exclusions match names **case-insensitively with PowerShell wildcards**
(`*`, `?`, bracket expressions); app IDs can also be excluded. IME cache names
are used if available; otherwise SelfX takes the name from the app policies in
the IME logs (`AppWorkload.log`, since 2.6.0) and only then shows the app ID.
Supply an `Application Id="..." Name="..."` mapping when you need name-based
exclusions but no name is found. Excluded probes are not executed. Excluding all apps
does not manufacture an OK result. Since 2.6.0 the row is labelled **Company apps
(Intune)**; its detail names the apps that failed with their error code (for
example `Monitoring Agent (error 0x87D1041C)`), and apps that do not apply to the
device (EnforcementState 3000-3999, requirements not met) are not counted. The
app ID is read from the key `Win32Apps\<user>\<app id>_<revision>`; before 2.6.0
the user ID could be shown instead of the app.

Create `Sources\HealthChecks` and put extension `.ps1` files there. Only simple
filenames are accepted (no subdirectories, absolute paths or `..`); reparse
points in that folder or the script are rejected. The default package contains
only `Check-Compliance.ps1` (see the Compliance row above). Example read-only application probe:

```powershell
<#
.SYNOPSIS
    Check whether the installed business client executable is present.
.NOTES
    Version: 1.0.0
    History:
    1.0.0  2026-10-28  Your company  Initial presence check.
#>
$ErrorActionPreference = 'Stop'
try {
    if (Test-Path -LiteralPath 'C:\Program Files\BusinessClient\Client.exe' -PathType Leaf) {
        exit 0
    }
    exit 1
} catch { exit 1 }
```

**Security and runtime contract:** checks execute non-interactively as SYSTEM
on each refresh, without a confirmation prompt. They must be read-only,
idempotent and must never reboot, sign out, modify settings, prompt for input
or launch detached work. Review/sign them before deployment; arbitrary
administrator-supplied scripts cannot be proven read-only by SelfX. No
credentials should be stored in scripts. Exit codes define their status; the
last non-empty stdout line (at most 400 characters) is shown as detail text,
otherwise `Exit code: N`. stderr is drained but not included in the report.
Timeout is 1-30 seconds per script, default 30; at most 5 script checks total
(compliance, app probes and custom combined), and 16 additional services.
On timeout SelfX attempts to terminate that process tree. The entire service
request is capped at 240 seconds and 20,000 characters; oversize results are
rejected explicitly, not shown as OK. Repair actions and checks requested by
SelfX share a lock: a concurrent request returns Busy; retry after it finishes.
A check requested while a background check runs waits until it has finished.

Run all tests of the package before packaging, see the
[release checklist](Installation.md#release-checklist-selfx-service). The
catalogue and the health configuration are also checked by `Test-Catalog.ps1`
(2.6.10).

Tests mock all system probes and script execution. They do not install a
service or execute real custom scripts; `Test-ServicePipe.ps1` only starts the
pipe listener of the service under a test pipe name. `Test-Scripts.ps1` (2.6.0) runs every
action and repair script in a temporary sandbox with mocked commands (no
process is closed, nothing is started or restarted) and checks its result and
its log; only the read-only scripts `Check-Compliance.ps1`, `Detection.ps1`
and `HealthStatus.ps1` run for real.

### Health remediation

Health checks remain read-only. To offer a user-triggered **Fix** button on a
status row, install a repair script under `Sources\Scripts_to_run` and add it
to `Health_Config.xml`:

```xml
<Remediations>
  <Remediation Id="IME" Script="SelfX_Intune_RestartService.ps1" />
  <Remediation Id="Service" Name="Spooler" Script="Repair-Spooler.ps1" />
  <Remediation Id="Disk" Name="C:" Script="Repair-Disk.ps1" />
  <Remediation Id="Custom" Name="Business check" Script="Repair-BusinessCheck.ps1" />
  <Remediation Id="Compliance" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
</Remediations>
```

`Id` matches a result type (`IME`, `Defender`, `Compliance`, `Applications`,
`Disk`, `BitLocker`, `PendingReboot`, `Updates`, `Service`, `Custom`). Optional `Name` matches the exact
technical name, not the translated label. With no Name, the mapping applies
to every row of that type. Do not configure overlapping mappings for a row:
ambiguous mappings are reported as configuration errors. Optional
`When="NotOK"` offers the repair only while the row is not OK (Pending, Error
or Unknown); the default `Always` offers it on every status.

**Default remediation (2.3.4):** the package ships
`Scripts_to_run\SelfX_Defender_UpdateSignature.ps1`, which runs
`Update-MpSignature` as SYSTEM with the update sources defined by Defender
policy, and enables it in the default `Health_Config.xml`:

```xml
<Remediation Id="Defender" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
<Remediation Id="Compliance" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
```

Since 2.5.4 the Defender and Compliance rows show **Fix** only while they are
not OK, because outdated signatures after a longer absence
are a frequent cause of non-compliance. To offer the signature update on an OK
Defender row as well, remove `When="NotOK"` from the Defender line. The update needs a reachable update
source; offline it fails (exit 1) and the status stays unchanged. Remove the
two lines to disable this.

**Updates remediation (2.5.6, fixed in 2.6.3 and 2.6.9):** the package ships
`Scripts_to_run\SelfX_Updates_Install.ps1` and enables it in the default `Health_Config.xml`:

```xml
<Remediation Id="Updates" Script="SelfX_Updates_Install.ps1" When="NotOK" TimeoutSeconds="7200" />
```

While updates are pending, the **Updates to install** row offers **Fix**. While the installation
runs, the button shows **Running…** and the message bar says that the updates are being searched,
downloaded and installed; afterwards SelfX reports that Windows Update has finished and checks the
whole device status again (updates, restart pending, compliance). The script runs as SYSTEM and

1. starts the Microsoft Store app update scan of the MDM bridge
   (`MDM_EnterpriseModernAppManagement_AppManagement01.UpdateScanMethod`). This also works when the
   Store is blocked for users. The Store updates the apps asynchronously in the background.
2. on Windows 11 25H2 and newer (minimum version, 2.6.10) starts **"Check for updates" of the Windows Update
   orchestrator** through the documented WinRT API `Windows.Management.Update.WindowsUpdateManager`
   (`StartScan(userInitiated: true)`, the same as the button in Settings). Windows downloads and
   installs the updates itself, with the policies of the device, and **Settings > Windows Update
   shows the progress**. The script waits until no update is downloaded or installed any more (at
   most 90 minutes) and logs each update with its action, progress and the reason why it waits, for
   example `2026-11 Security Update (KB5132061): action Install, progress Install 70` or
   `Optional driver: waiting: SeekerUpdate`. Updates that only wait for the restart (`ReadyToReboot`)
   are done. Feature updates (new Windows version) are left to the update policy.
   Every update is logged in `%ProgramData%\SelfX\Logs\SelfX_Updates_Install_<date>.log`. Afterwards a
   background scan of the orchestrator refreshes the page in Settings. While the orchestrator is still
   working after 90 minutes, the repair ends with exit `1`; Windows continues in the background. If the
   orchestrator API is not available (`WinRT\SelfXWinRT.dll` missing), the repair ends with exit `1` and
   asks to reinstall SelfX; there is no other update path.

2.6.0 to 2.6.2 used `UsoClient.exe StartDownload` / `StartInstall`. Windows 11 24H2 rejects these
commands (exit code `-2147024809` / `0x80070057` in the log), so only a scan ran and nothing was
installed; a restart that was already pending was even reported as installed. 2.6.3 no longer uses
`UsoClient.exe`. 2.6.3 to 2.6.8 used only the Windows Update Agent API. Microsoft documents that the
Windows Update page in Settings shows only updates of the orchestrator and that updates handled
through the WUA API do not appear there and can conflict with it, so the updates could still be
shown as pending in Settings. Since 2.6.10 the Windows Update Agent API is not used any more for installing. Before 2.6.9 a click on **Fix** was also refused with "Another action
is still running" while SelfX read the cached status (once a minute, for a moment).

The script **never restarts** Windows. If an update needs a restart, the **Restart pending** row
shows it. Exit `0` = all selected updates installed (or nothing to install); exit `1` = search,
download or installation failed for at least one update (the failed KB numbers are in the log). A
Store scan that cannot be started (for example without the MDM bridge) is logged but does not fail
the repair. Remove the line to disable it.

**Restart remediation (2.6.0):** the **Restart pending** row offers **Restart now**:

```xml
<Remediation Id="PendingReboot" Script="SelfX_Device_Restart.ps1" When="NotOK" />
```

SelfX recognises this script and asks with its own warning: Windows restarts to complete the
pending updates and changes, the user should save the work and close all programs, the restart
begins about 30 seconds after the confirmation (**Restart now** / **Cancel**). After the
confirmation the service runs `shutdown.exe /r /t 30 /d p:4:1` as SYSTEM; Windows shows its restart
notification. The restart is **never** part of **Fix all problems**. Remove the line to hide the
button.

**App retry remediation (2.6.0):** the **Company apps (Intune)** row offers **Try again** while an app
installation failed:

```xml
<Remediation Id="Applications" Script="SelfX_Apps_RetryInstall.ps1" When="NotOK" TimeoutSeconds="300" />
```

The Intune Management Extension retries a failed Win32 app only after its retry schedule (by default
24 hours). `SelfX_Apps_RetryInstall.ps1` removes, for every app whose last result in the local IME
cache is an error, this cached result and the retry schedule entries (GRS) of the app, and restarts
the IntuneManagementExtension service. The IME then checks in with Intune and installs the app again
within a few minutes; the user sees the progress in the Company Portal. No app is uninstalled and
only the IME cache under `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps` is changed.
When the installation fails again, the problem is in the app or its assignment; the user can send
the device logs to the support, and the support team sees the error code in Intune.

Optional `TimeoutSeconds` on a `Remediation` (since 2.5.6) sets the run time limit of the service
for this repair: a positive number, capped at 7200 seconds; the default is 900 seconds.

Optional `OtherSessions="Block"` on a `Remediation` works like the catalog element `OtherSessions`: a
normal user cannot start the repair while another user has an active session. The delivered
configuration sets it for `Updates` and for the restart (`PendingReboot`). A script that is also a
catalog `System` action uses the catalog entry first; set `Block` there as well.

The **Fix** button is shown only on cards with a configured repair (including OK and
Unknown cards unless `When="NotOK"`). It is labelled **Beheben** in German and **Fix** in English;
the restart and the app retry use **Neu starten** / **Restart now** and **Erneut versuchen** /
**Try again**. Button and confirmation texts are included in all 24 UI languages. Every card also has a
**check again** button (arrows) that re-checks only that status
without confirmation and without running any repair (see
[Single-status recheck](#single-status-recheck)). Before 2.5.0 rows without a
repair showed a button labelled Ok, Pending or Error instead.
The user must confirm before execution. The local service validates the script
against the protected remediation allowlist (or existing System action
catalogue), then runs it as SYSTEM with the existing repair timeout and logging.
No arbitrary paths, command arguments or user-supplied scripts are accepted.
Remediation scripts do not need an additional troubleshooting catalogue entry.
Any local signed-in user can request these approved repairs, just like
existing System actions.

The window prevents a second repair while one is running. On completion,
including failure or timeout, it re-checks the repaired status only (rows of
the collection itself fall back to a full refresh). The action result stays in
the message bar; the fresh check result,
not the script exit code, determines the displayed health status. A repair
that returns 0 can therefore still leave a red status. If the check or service
is unavailable, the refreshed result is Unknown rather than fabricated OK.

### Single-status recheck

Since 2.3.2 the client can request one check with
`HEALTH <Id> [<base64 UTF-8 name>]`, for example `HEALTH Disk Qzo=` for drive
`C:`. The service accepts only the known Ids (`IME`, `Defender`, `Compliance`,
`Applications`, `Disk`, `BitLocker`, `PendingReboot`, `Updates`, `Service`, `Custom`) and a strictly
base64-encoded name; anything else is rejected. `HealthStatus.ps1` then runs
only that check from the protected `Health_Config.xml`: a name that is not
configured there is never probed and returns an Unknown row. The UI replaces
only the affected card and the service updates only these rows in the status
cache; all other information is kept. Rows of
type `Collection` (collector errors) trigger a full refresh instead.

Repairs must be suitable for execution without user interaction. Never use
sign-out, restart, shutdown, sleep or detached actions in these scripts. This
also applies to `PendingReboot`: the recheck only shows whether a restart is
still pending; the user restarts the device themselves.
Administrators must review, deploy and, where required, sign them. Since
2.3.4 only the Defender signature update (Defender always, Compliance when
not OK) is enabled by default.

### Branding

Company logo, icon and colors are set in the `Branding` section of
`Tool_Config.xml`. Copy the image files into `SelfX Service\Sources`, or into a
subfolder such as `Sources\Branding`, before you build the package. Paths are
relative to the install folder. All keys are optional; if a value is empty,
invalid or the file is missing, SelfX uses the default.

The delivered `Tool_Config.xml` contains placeholders (2.6.8): the logo
`Branding\company_logo.png` ("YOUR LOGO"), the blue of the SelfX logo
(`#0072BC`) and the support contacts `Mon-Fri 08:00-17:00`, `+1 555 0100`,
`support@example.com` and `https://support.example.com`. Replace them with the
values of your company before you build the package, or empty them to hide them.

| Key | Default | Purpose |
|---|---|---|
| `Brand_Logo` | empty (no logo) | Company logo at the top of the navigation bar and in the About dialog. PNG, JPG, BMP, GIF or ICO, at most 196 pixels wide in the navigation. A transparent PNG works best on both themes. If empty, the About dialog shows `About_Logo`. |
| `Brand_Logo_Height` | `40` | Height of the logo in the navigation bar, in pixels (16–120). The width is scaled to fit. |
| `Brand_Icon` | `Repair.ico` | Icon of the window, the taskbar and the tray icon. If it is an `.ico` file, `Install.ps1` also uses it for the shortcuts and the Apps & Features entry. Since 2.6.2 SelfX has its own taskbar button (AppUserModelID `SelfX.SelfService`) with this icon instead of the PowerShell icon; a SelfX pinned to the taskbar starts `SelfX.exe`. Use an `.ico` with 256 × 256 pixels for a sharp taskbar icon. |
| `Brand_Accent_Color` | empty (uses `Tool_Color`) | Company color as `#RRGGBB` for buttons, selections, the navigation marker, links and icons. The text color on the accent (white or black) is chosen automatically; a very dark or very light color is lightened or darkened for text and icons so it stays readable on both themes. |
| `Brand_TitleBar_Color` | window background | Title bar background as `#RRGGBB`, for example the corporate color. The text color is chosen automatically. |
| `Brand_Run_Button_Color` | accent color | Run (play) and **Fix** buttons. |
| `Brand_Info_Button_Color` | accent color | "More information" icons. |

Example:

```xml
<Brand_Logo>Branding\contoso.png</Brand_Logo>
<Brand_Logo_Height>48</Brand_Logo_Height>
<Brand_Icon>Branding\contoso.ico</Brand_Icon>
<Brand_Accent_Color>#E20074</Brand_Accent_Color>
<Brand_TitleBar_Color>#3A0021</Brand_TitleBar_Color>
<Brand_Run_Button_Color>#E20074</Brand_Run_Button_Color>
<Brand_Info_Button_Color>#6C6C6C</Brand_Info_Button_Color>
```

`Tool_Theme` (`Auto`, `Dark` or `Light`) selects the default theme; since 2.6.7
the default is `Auto` (also when the value is missing or unknown). Each user
can change it in the settings dialog (if `Show_Theme_Button` is `True`): *Automatic*,
*Dark* or *Light*. *Automatic* (`Auto`, 2.6.6) uses the app mode of Windows
(Settings > Personalization > Colors, `AppsUseLightTheme` in
`HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`; light if
the value is missing) and follows a change while SelfX is open. The choice of
the user is stored in `HKCU\Software\SelfX\Theme` and wins over `Tool_Theme`;
users who chose *Dark* or *Light* before keep their choice. The
branding colors apply to both themes. `Tool_Color` accepts the former MahApps
color names (`Cyan`, `Teal`, `Blue` ...). Since 2.5.0 SelfX Service no longer
uses MahApps.Metro; no file is written for the colors and no network access
is used.

### Languages

By default the user interface follows the Windows display language of the
signed-in user. Users can choose another language themselves in SelfX >
Settings (gear). The texts are in `Sources\Languages\<culture>.xml`. Included languages:

| File | Language | File | Language | File | Language |
|---|---|---|---|---|---|
| `en.xml` | English (reference) | `pl.xml` | Polish | `hi.xml` | Hindi |
| `de.xml` | German | `ru.xml` | Russian | `bn.xml` | Bengali |
| `fr.xml` | French | `uk.xml` | Ukrainian | `zh-Hans.xml` | Chinese (Simplified) |
| `es.xml` | Spanish | `tr.xml` | Turkish | `zh-Hant.xml` | Chinese (Traditional) |
| `it.xml` | Italian | `ar.xml` | Arabic (right to left) | `ja.xml` | Japanese |
| `pt.xml` | Portuguese | `fa.xml` | Persian (right to left) | `ko.xml` | Korean |
| `nl.xml` | Dutch | `ur.xml` | Urdu (right to left) | `vi.xml` | Vietnamese |
| `id.xml` | Indonesian | `th.xml` | Thai | `sw.xml` | Swahili |

English is the reference; the other files were machine translated. Have them
reviewed by native speakers before a rollout.

How the language is selected (`Localization.ps1`):

1. The language chosen by the user (2.5.9). The settings dialog lists
   **Automatic (<language>)** and every language file, each by its own name,
   for example *Deutsch*, *français*, *日本語*. The choice is stored per user
   in `HKCU\Software\SelfX\Language`. *Automatic* stores `Auto`, which
   means "use step 2". After a change, SelfX restarts on the same page in the
   new language, and the status icon follows. If a repair is still running,
   the new language is used the next time SelfX is opened. The choice is
   ignored when `Show_Language_Setting` is `False`, when the value is not a
   culture name, or when its language file no longer exists.
2. `Tool_Language` in `Tool_Config.xml`: `de` (default) is German, `Auto` uses
   the Windows display language, any other value is used as the culture name.
3. The culture and its parent cultures are tried in order. For example
   `de-CH` uses `de.xml`, `pt-BR` uses `pt.xml`, `zh-CN` uses `zh-Hans.xml` and
   `zh-TW` uses `zh-Hant.xml`. Swiss German (`gsw`, including `gsw-CH`)
   also uses `de.xml` when no Swiss German language file is available.
4. If no file matches, `de.xml` (the base language) is used. A text that is
   missing in the selected language is shown in English (`en.xml`).

Each text is looked up in the selected language first and then in English, so a
missing entry never leaves an empty label. Catalogue texts fall back to the
English base text in `Issues_List.xml`.

A language file has four parts:

| Section | Content |
|---|---|
| `UI` | Texts of the main window, dialogs, tooltips, message bar, Device status and System information pages and the tray icon. `{0}`, `{1}` are placeholders, for example the action name. |
| `SystemInfo` | Labels and values of the System information page and the status checks |
| `Catalog/Categories` | Display names of the category Ids |
| `Catalog/Messages`, `Catalog/Actions` | Translations of the shared messages and of `Name`, `Explanation` and `Alerte_MSG` per action `Id`. Fields that use `Ref` take the translated message. |

To add a language:

1. Copy `en.xml` (or a complete translation such as `de.xml`) to
   `<culture>.xml`. Use the neutral culture name, for example `cs.xml` for
   Czech, so that all regional variants use it.
2. Set `Culture`, `Name` and `NativeName` on the root element. Set
   `FlowDirection="RightToLeft"` for right-to-left scripts.
3. Translate the texts. Keep the element names, Ids and placeholders. Keep the
   `|*.txt|` pattern in `SystemInfo_Export_Filter`.
4. Check the file, then build the package:

   ```powershell
   & '.\SelfX Service\Test-LanguageFiles.ps1' -Culture cs
   ```

   The check reports missing or unknown keys, broken placeholders and
   catalogue entries that do not exist. Run it without `-Culture` to check all
   files.

No code change is needed. To change a text for your company, for example the
main title, edit it in the language files.

## Editing and publishing safely

1. Back up the current XML and scripts.
2. Validate that the XML remains well-formed.
3. Confirm each referenced script exists in the corresponding package.
4. Test action behavior and user confirmation text on a test device.
5. For remote updates, publish the XML and ZIP from a trusted HTTPS location
   and update the XML version.
