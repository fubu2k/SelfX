# Configuration

**English** | [Deutsch](../Configuration.md)

SelfX Service is set up with XML files in the folder `SelfX Service\Sources`. You
change the files **in the package, before installation**. After installation they
are in `%ProgramFiles%\SelfX` and only administrators can change them. New settings
always come with a new package version. SelfX does not download anything from the
network.

| File | Purpose |
|---|---|
| `Tool_Config.xml` | General settings, contacts, branding |
| `Issues_List.xml` | Action catalogue (troubleshooting) |
| `Health_Config.xml` | Device status: checks, repairs, background check |
| `Network_Test_Config.xml` | Network measurements (optional) |
| `Ticket_Config.xml` | Assigning tickets to IT units (optional) |
| `Languages\<culture>.xml` | All texts, one file per language |

## SelfX Service

### Action catalogue

`Issues_List.xml` lists every action SelfX offers. An action has an English base
text. The translations are in the language files and are matched by the `Id` of the
action.

Important elements of an action:

| Element | Meaning |
|---|---|
| `Id` (attribute) | Unique name, for example `D_Teams_SoundCuts`. The language files use it. |
| `Name`, `Explanation`, `Alerte_MSG` | Title, explanation and confirmation text (English base text). |
| `Category` | Category id: `Account`, `Browser`, `Device`, `Intune`, `Office`, `OneDrive`, `Outlook`, `Teams`. The display name comes from the language file. |
| `Script` | Name of the script in `Scripts_to_run`. Not used with `Context` `Link`. |
| `Link` | `Context` `Link` only: name of the setting in `Tool_Config.xml` (`Link_<Name>`, letters and digits) that holds the https address. |
| `Context` | `User`: the script runs as the signed-in user. `System`: the service runs the script as SYSTEM. `Link`: after the confirmation SelfX opens the https address of the setting (field `Link`) in the browser of the user; no script runs and the service is not involved. If the element is missing, `User` applies. |
| `TimeoutSeconds` | `System` only. 1 to 7200 seconds, default 900. After that the service stops the script. |
| `OtherSessions` | `System` only. `Block`: a standard user cannot start the action while another user is actively signed in. Administrators with elevated rights are not affected. If SelfX cannot read the sessions, the action is blocked. Set `Block` on every entry of the same script. In the supplied catalogue it applies to restarting the Intune service, restarting the network adapters and CHKDSK. |
| `Post_Action` | `System` only. `MailReport`: after a successful run, SelfX opens an e-mail to the support with the report attached (see [Device logs](#device-logs-for-the-support)). |

`Explanation` and `Alerte_MSG` can point to a shared text, for example
`<Alerte_MSG Ref="Msg_Teams_Restart"/>`. The shared texts are in the `Messages`
section of the file.

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

**Rules for `System` actions (security):**

- `Script` is only a file name made of letters, digits, `_`, `-` and `.`, ends in
  `.ps1` and is in `Scripts_to_run`. The service rejects everything else. Users cannot
  hand the service paths, arguments or code.
- Every signed-in user can start every `System` action. Only add actions that are safe
  for every user.
- The script runs without a user profile, without a desktop and without prompts. It
  returns an exit code (`0` = success). Output to stdout and stderr is logged.
- The service passes the SID of the requesting user in the environment variable
  `SELFX_CALLER_SID`. Use it only to hand a result to that user, never to decide
  whether an action is allowed.
- The same script can appear in several actions. The first `System` entry sets the
  `TimeoutSeconds`.

**Add a new action:** give it a new `Id` and add the translations to the language
files. Without a translation, the English text is shown.

Supplied `System` actions:

| Script | Purpose |
|---|---|
| `SelfX_Intune_RestartService.ps1` | Restart the Intune Management Extension service |
| `SelfX_Device_AirePlaneMode.ps1` | Restart all active network adapters |
| `SelfX_Device_SyncTime.ps1` | Sync the clock with the configured time source (`w32tm /resync /force`, the time configuration stays unchanged) |
| `SelfX_OneDrive_CHKDSK.ps1` | Schedule `chkdsk /r /f` for the system drive at the next restart |
| `SelfX_Device_CollectLogs.ps1` | Collect the device logs and open an e-mail with the report |

### Settings in Tool_Config.xml

The file contains settings only, no texts. All texts are in the language files (see
[Languages](#languages)).

| Key | Meaning |
|---|---|
| `Tool_Version` | Raise it with every release and set the same value in `Detection.ps1`. |
| `Tool_Language` | Default language. `de` (default), `Auto` (Windows display language) or a culture name such as `en`, `fr-CH`, `zh-Hans`. |
| `Show_Language_Setting` | `True` (default): users can choose the language themselves. `False`: `Tool_Language` always applies. |
| `Tool_Name` | Text in the title bar and the About dialog. |
| `Shortcut_Desktop`, `Shortcut_StartMenu`, `Shortcut_Name` | Shortcuts that `Install.ps1` creates for all users. |
| `Show_Computer_Name_MainGUI`, `Show_Computer_Name_title_bar` | Show the computer name in the window. |
| `Default_Solution_Mode` | `Simplified` or `Detailed`. |
| `Show_Reboot_Warning`, `Show_About_Button` | Restart reminder and the About button (i). |
| `Show_Theme_Button` | `True`: users can choose the design (Automatic, Dark, Light). |
| `Show_Status_Page` | `True` (default): show the *Device status* page. |
| `Show_SystemInfo_Tab`, `Show_SystemInfo_Intune_Actions`, `SystemInfo_Internet_Test_Host`, `SystemInfo_Internet_Test_Port` | The *System information* page and its tools. |
| `Show_Support_Button`, `Support_Hours`, `Support_Phone_number`, `Support_Mail`, `Support_Teams`, `Support_Website` | The help button (?) and its contacts (see [User interface](#user-interface)). `Support_Mail` is also the recipient of the e-mail with the device logs. |
| `DeviceLogs_Days`, `DeviceLogs_Compress` | Device logs: days of event log history (1 to 60, default 7) and `.zip` (default) or `.txt`. |
| `Ticket_Enabled`, `Ticket_Mail`, `Ticket_Subject_Tag` | Ticket by e-mail (see [Ticket](#ticket-by-e-mail)). |
| `Link_PasswordReset`, `Link_SecurityInfo` | Addresses of the link actions "Reset your password" (default `https://passwordreset.microsoftonline.com/`) and "Manage the sign-in methods" (default `https://mysignins.microsoft.com/security-info`). `https://` only, without user name and password. Empty or `Off` hides the action; an invalid value hides it and is noted in the log. Your own link actions: a key `Link_<Name>` in `Tool_Config.xml` and an action with `Context` `Link` in the catalogue. |
| `Copilot_Enabled`, `Copilot_Url`, `Copilot_Audience`, `Copilot_Include_AppNames` | Hand-over to Copilot Chat (see [Copilot Chat](#copilot-chat)). |
| `Log_Retention_Days` | How long logs are kept (see [Logs](#logs-and-retention)). |
| `Service_FileCheck` | `Enforce` (default) or `Audit`: before every start the service compares the installed scripts and configuration with `SelfX.Files.json`. `Enforce` starts nothing when they differ, `Audit` only logs (event 4005); see [File list](Installation.md#file-list-selfxfilesjson). |
| `Service_Privileges` | `Restricted` (default) or `Default`: privileges of the service, read by `Install.ps1` (see [Service privileges](Installation.md#service-privileges)). |
| `Show_Tray_Icon`, `Tray_Notifications`, `Tray_Poll_Seconds` | The tray icon (see [Tray icon](#tray-icon)). |
| `Brand_*`, `Tool_Theme`, `Tool_Color` | Appearance (see [Branding](#branding)). |

### User interface

The window is built for users without technical knowledge. You can resize it
(minimum 640 × 480). SelfX stores size, position, design, language and the tray icon
choice per user in `HKCU\Software\SelfX`. Only one window runs per user. A second
start brings the open window to the front.

- **Navigation (left):** *Troubleshooting*, *Device status* (with a counter for
  problems and warnings), *System information*, the company logo (`Brand_Logo`) and, at
  the bottom, *Send logs to support* with the state of the service.
- **Troubleshooting:** search, categories and one card per action. A card has an info
  icon (explanation), a start button and a shield when the action runs through the
  service. While an action runs, its button is locked. The result (exit code 0 =
  success) appears in the message bar and is logged.
- **Device status:** one card per check, problems first. The status is *OK*,
  *Pending* (warning), *Error* or *Unknown*.
  - *Fix* (wrench) runs the configured repair after a confirmation.
  - The arrow on a card re-checks only that status, the arrow at the top checks
    everything.
  - *Fix all problems* runs every configured repair once and then checks everything
    again. If the service is busy, the remaining repairs are skipped and reported.
  - Times are shown in the user's time zone.
- **System information:** one card per section (Device, Windows, User and management,
  Network, Report). A double click on a row copies the value. The last values appear
  immediately from `%LOCALAPPDATA%\SelfX\SystemInfo.json` and are refreshed in the
  background. Copy and export (TXT, HTML, CSV, JSON) also contain the device status.
  Tools below: Intune sync, compliance check, Company Portal, Remote Help or Quick Assist, MDM logs
  and send logs.
- **Title bar:** Help (?), Settings (language, design, tray icon) and About (i).
- **Help dialog:** shows only the contacts you have entered: `Support_Hours`,
  `Support_Phone_number`, `Support_Mail` (opens an e-mail), `Support_Teams` (a user or
  mailbox address opens a Teams chat, a full `https://` link opens unchanged) and
  `Support_Website` (only `https://`; `http://` is ignored and noted in the log). The address in `Support_Mail` must be one plain e-mail address (no list, no additions such as `?cc=`), otherwise the dialog shows it without a button. Without any contact, the dialog
  asks the user to contact the IT department.

### Remote support: Remote Help or Quick Assist

The tile in the tools starts **Remote Help** when it is installed, otherwise Quick
Assist. With Remote Help installed, SelfX does not offer Quick Assist: one standard
in the company.

- **Detection:** `%ProgramFiles%\Remote Help\RemoteHelp.exe` must be a plain file (no
  link) with a valid signature of "Microsoft Corporation". A file without a valid
  signature counts as not installed. The window reads this at start.
- **Deployment:** Remote Help is an Intune add-on with its own license for users and
  helpers. Deploy the app with Intune (Win32 app, install command
  `remotehelpinstaller.exe /quiet acceptTerms=1`). SelfX cannot check whether a user is
  licensed; the rule is: app installed = Remote Help.
- **Limit:** SelfX controls only its own tile. Block Quick Assist itself with your
  policies (for example Intune, AppLocker or App Control).
- There is no setting for this: without Remote Help it stays Quick Assist.

### Background checks

The service runs the health checks in the background on a regular basis and stores
the result in `%ProgramData%\SelfX\Cache\Health.json` (SYSTEM and administrators
only). SelfX and the tray icon read this cache with the request `STATUS`. The request
answers immediately and does not run anything. Every check that SelfX starts itself
also updates the cache.

Settings in `Health_Config.xml`:

```xml
<Background Enabled="true" IntervalMinutes="15" PauseOnBattery="true" MaxCpuPercent="75" StartDelaySeconds="120" />
```

| Attribute | Default | Meaning |
|---|---|---|
| `Enabled` | `true` | `false`: no background checks. SelfX then checks when it is opened. |
| `IntervalMinutes` | `15` | 5 to 1440. Time between two checks. |
| `PauseOnBattery` | `true` | Do not check on battery. SelfX shows the last result and notes the pause. |
| `MaxCpuPercent` | `75` | 10 to 100. If processor load is higher, the check is postponed by 2 minutes. `100` = no limit. |
| `StartDelaySeconds` | `120` | 0 to 3600. Wait after the service starts, so sign-in is not slowed down. |

Missing or invalid values use the default. No check runs during a repair. The check
runs at low priority and for at most 240 seconds and writes only one line to
`SelfXService.log`. Changes apply without restarting the service.

### Tray icon

`SelfX_Tray.ps1` shows a SelfX icon with a coloured dot in the notification area:
green (OK), yellow (warning), red (problem), grey (no status yet). The tooltip gives
the number of problems and warnings. When a check changes to *Error*, one Windows
notification appears. Clicking it opens the device status. The right-click menu opens
SelfX, checks the status, sends logs, turns notifications on or off or hides the icon.

| Key in `Tool_Config.xml` | Default | Meaning |
|---|---|---|
| `Show_Tray_Icon` | `True` | `Install.ps1` creates the HKLM run entry `SelfXTray`. The icon starts at every sign-in. `False` removes the entry. |
| `Tray_Notifications` | `True` | Notification on an error. `False` turns it off for everyone and hides the user switch. |
| `Tray_Poll_Seconds` | `60` | 15 to 3600. How often the icon reads the cache (it does not run a check). |
| `Tray_Pin_Icon` | `True` | Windows 11 hides new icons in the overflow (arrow). `True`: at start the icon sets `IsPromoted = 1` for the user, so it stays next to the clock. The key `HKCU\Control Panel\NotifyIconSettings` is not documented by Microsoft. A user can switch it off with `HKCU\Software\SelfX\TrayPin = 0`. |

**Per user:** each user can turn notifications off
(`HKCU\Software\SelfX\TrayNotifications`, 1 = on, 0 = off) and hide or show the icon
(`HKCU\Software\SelfX\TrayIcon`). With notifications off, the icon stays visible and
problems are still remembered. Answers to the user's own actions always appear.

The icon needs no administrator rights. It only reads the cache through the pipe of
the service and, shortly after it starts, collects the user's system information once.
An installation or update through Intune (SYSTEM) starts the new version in the
sessions of the signed-in users. Users who hid the icon do not get it back. After an
uninstall, the icons are closed. SelfX Service shows no notification after the
installation.

### Device logs for the support

The action *Send device logs to support* (`Q_Device_SendLogs`, `D_Device_SendLogs`)
and the *Send logs to support* buttons collect all logs needed to analyse a device
problem and open an e-mail to the support with the report attached. The user
describes the problem and sends it. Nothing is sent automatically.

**How it works:**

1. The user confirms. The interface sends `RUN SelfX_Device_CollectLogs.ps1` to the
   service (timeout 1800 seconds).
2. The service runs the script as SYSTEM. It starts the read-only collector
   `Scripts_to_run\Collect-DeviceLogs.ps1` and writes the report to
   `%ProgramData%\SelfX\Reports\<user SID>\DeviceLogs-<computer>-<time>.txt`, as a
   `.zip` unless `DeviceLogs_Compress` is `False`.
3. The folder has a protected ACL: full control for SYSTEM and administrators, read
   access only for the requesting user. The user's previous report is deleted on every
   run, reports older than 7 days are deleted for all users. In addition, the service
   deletes reports older than 7 days and empty user folders once a day (also when no new
   report is created). The next report replaces the copy in `%LOCALAPPDATA%`.
4. The interface copies the report to `%LOCALAPPDATA%\SelfX\Reports` and opens a new
   e-mail:
   - classic Outlook (COM): recipient `Support_Mail`, subject and text from the
     language file (`Report_Mail_Subject`, `Report_Mail_Body`), report attached;
   - otherwise `outlook.exe /a <file>`;
   - otherwise (for example new Outlook) the default mail app through `mailto:` and
     an Explorer window with the file selected, which the user attaches.

**Content:** the collector only reads. It does not change anything, load a registry
hive, install anything or send anything. The report contains computer, user and tenant
names and device logs (Autopilot/ESP, IME and Win32 apps, servicing, event logs, AppX,
Windows Update, network, language). It takes about one to a few minutes. The sections
and parameters are in the header of `Collect-DeviceLogs.ps1`.

Section 8 starts with a **summary of the event logs** (*System*, *Application*, Windows Update,
device management): critical events, errors and warnings of the last `DeviceLogs_Days` days,
counted per provider and event id (the 15 most frequent, with first and last time). The message
text is deliberately **not** included, because it can contain names, paths and addresses; provider
names are limited to harmless characters. The support sees at a glance what occurs unusually
often. The single events follow below as before.

**What a standard user sees:** the report is trimmed per user. The service reads the
token of the requesting user and sets `SELFX_CALLER_ADMIN`. The value `1` applies only
if the *Administrators* group is **enabled** in the token (elevated rights). If the
value is missing or different, the user counts as a standard user.

| | Administrator (`1`) | Standard user |
|---|---|---|
| Collector | full | `-UserView -CallerSid <own SID>` |
| Serial number, console user | yes | no |
| Sessions (`quser`) | all | only their own |
| `dsregcmd` | everything | only join and sign-in state, no tenant, device or user ids |
| User profiles and registry hives | all | only their own |
| AppX user entries | all | only their own |
| Names, SIDs and profile folders of other users | unchanged | replaced by `<other user>` |
| SelfX device logs (`SelfXService.log`, script logs) | yes | no |
| Own SelfX user logs | yes | yes |

An administrator who starts SelfX **without** elevated rights counts as a standard
user. Without `-UserView` (Intune Win32 app, remediation, manual run), the report is
complete.

**SelfX logs in the report:** two sides add them, each with its own rights:

- The **script running as SYSTEM** adds, for administrators only, `SelfXService.log`,
  `Install.log`, `Uninstall.log` and all other `*.log` files from
  `%ProgramData%\SelfX\Logs` of the last `DeviceLogs_Days` days. It reads only files
  directly in this folder and never the subfolder `Logs\Users`.
- The **SelfX window (the user)** adds the logs of the user's own account from
  `Logs\Users\<own SID>` to its copy of the report. Logs of other users are never
  added. A problem here does not stop the e-mail.

In the `.zip` they are in the folder `SelfX-Logs` (user logs in `SelfX-Logs\User`), in
a `.txt` report they are the last section. At most 2 MB per file and 30 MB per side
are added.

*Why two sides:* users can change their folder under `Logs\Users`. If SYSTEM read it,
a user could redirect the read (for example with a junction swapped between check and
read) to a protected file. The window reads with the user's rights and can therefore
only add what the user may read anyway.

`SelfXService.log` names the users who started actions on the device.

**Exit codes of `SelfX_Device_CollectLogs.ps1`:** `0` report created, `1` collecting or
compressing failed, `2` requesting user unknown.

**Customising:** for your own report script, keep `Post_Action` `MailReport` and write
the report as `DeviceLogs-*.zip` or `DeviceLogs-*.txt` with the same ACL to
`%ProgramData%\SelfX\Reports\<SELFX_CALLER_SID>`. Remove both catalogue actions to hide
the function. The button on the system information page appears only if a `System`
action with `MailReport` exists.

### Network measurements

Optional and off by default. The file `Network_Test_Config.xml` turns on extra rows in
the Network section of the *System information* page:

- response time to the default gateway,
- time of a name lookup (DNS),
- time to open a TCP connection.

The measurements run in the user context, read-only, in the background together with
the other system information. Users cannot add or change targets.

```xml
<Network_Test_Config>
  <Settings Enabled="True" Gateway="True" Samples="3" TimeoutMs="2000" />
  <Targets>
    <Target Label="Intranet" Host="intranet.example.org" Port="443" />
    <Target Label="Internet" Host="www.example.org" Port="443" />
  </Targets>
</Network_Test_Config>
```

| Setting | Meaning |
|---|---|
| `Enabled` | `True` turns the measurements on. Default: `False`. |
| `Gateway` | `True` (default): ping to the default gateway. |
| `Samples` | Measurements per value, 1 to 5. Default: 3. |
| `TimeoutMs` | Wait time per measurement, 200 to 5000 ms. Default: 2000. |
| `Target` | Up to 5 targets. `Label`: display name (letters, digits, `. _ -`, spaces, up to 40 characters). `Host`: DNS name or IPv4 address. `Port`: optional, 1 to 65535. |

**Choose the targets freely:** the name of the target is only in the configuration. So
your organisation decides what is measured:

- An **internal name** (reachable only in the company network or over VPN) shows the
  quality of the internal connection.
- A **name reachable from the internet** shows the connection of a device that works
  mobile without VPN. Use an address your organisation operates itself or one that is
  meant for such tests.
- You can combine both.

**Values:**

- *Latency: default gateway*: average, minimum, maximum and number of lost replies. If
  no IPv4 gateway address is known, the row is missing.
- *DNS lookup: label*: time of the name lookup through the Windows resolver. Its cache
  applies, so repeated measurements can be faster. With an IPv4 address as `Host`, the
  row is left out.
- *Connection: label*: time until the TCP connection to `Host:Port` is open. It is
  closed immediately, no data is sent. Without `Port`, the row is left out.
- If all measurements of a value are lost, the row is an error. If some are lost, it
  is a warning.
- One run takes at most 20 seconds. After that, the remaining rows show "not measured
  (time limit reached)".
- Throughput is not measured.

**Security:** targets come only from the file (only administrators can change it).
`Host` is checked strictly: only letters, digits, hyphens and dots, no scheme, no
path, no port, no spaces. There are at most 5 targets. A DTD in the XML is forbidden.
Invalid entries are skipped, an unreadable file turns the measurements off. The rows
also appear in copy, export and ticket of the system information, with the configured
host names. The device sends only a name query, ping packets to the gateway and the
TCP connection setup to the targets.

**Check before rollout:** `tools\Test-SelfXNetworkMeasure.ps1` shows settings, targets
and invalid entries. With `-Run` it runs the measurements once on the current device,
even with `Enabled="False"`.

### Ticket by e-mail

Optional and off by default (`Ticket_Enabled` = `False`). When the function is on and a
valid address is set, the help dialog (?) shows the row *Report an issue* with the
button *Create ticket*.

**Flow (user context, no elevated rights):**

1. The user describes the problem (up to 3000 characters).
2. SelfX **always** adds the device information: all rows from *System information* and
   *Device status*, device name, Windows build and SelfX version. The user cannot turn
   it off but sees it in the e-mail.
3. The e-mail is only **shown, never sent automatically**. The user checks it and sends
   it.

**Hand-over to the mail program:**

- *Classic Outlook (COM):* recipient, subject, full text and the file
  `TicketInfo-<device>-<time>.txt` as an attachment.
- *New Outlook and other programs (`mailto`):* recipient, subject and text. The link
  has a length limit, so the text is shortened when needed (description and key fields
  first, device information last). The full file is selected in Explorer and the user
  must attach it. The interface says so.
- The file is in `%LOCALAPPDATA%\SelfX\Reports` (only for the user). Older
  `TicketInfo-*` files are deleted at the next ticket.

**E-mail layout (for filters and automation):** subject
`[<Ticket_Subject_Tag>][<kind>] <device>`. The kind is in the user's language, for
example *Incident*. The text starts with fixed English field names (`Time (UTC)`,
`Computer`, `Windows build`, `SelfX version`), followed by `Description of the user:`
and `Device information:` as separate blocks.

**Choosing the recipient.** The order, highest priority first:

1. **Registry per device:** `TicketMail` (and optionally `TicketCc`) in
   `HKLM\SOFTWARE\SelfX\Support`. Intune can set them per Entra device group (example in
   the [installation guide](Installation.md)). If a device changes group, the values
   change with the script of the new group, without a new package.
2. **Rules in `Ticket_Config.xml`** (see below).
3. **`Ticket_Mail`** in `Tool_Config.xml`, otherwise **`Support_Mail`**.

Every address must be exactly one plain address, otherwise the value is ignored and the
next level applies. The recipient is shown in the dialog ("The e-mail goes to: ...").
The user cannot change it.

**Rules in `Ticket_Config.xml`:** the file is in the installation folder (only
administrators can change it). It holds any number of IT units and rules. Nothing is
fixed in the code.

- `<Unit Id="IT1" Mail="it1@example.com" Cc="" />` defines a unit with a recipient and
  an optional copy. The `Id` consists of letters, digits, `.`, `_`, `-` (up to 40
  characters). Mail and Cc are each exactly one plain address.
- `<Rule Source="GroupTag|OU|Category" Match="..." Unit="IT1" />` assigns a value to a
  unit. `Match` is an exact value (case-insensitive). Instead of `Match` you can use
  `Regex` (.NET expression, up to 300 characters, time limit 200 ms). If the
  expression contains a named group `(?'unit'...)`, `Unit` can be left out. Example:
  `^[A-Z]{2}-(?'unit'IT[0-9]+)-[A-Z]{3}$` for group tags such as `DE-IT1-BER`.
- Rules are checked from top to bottom. The **first match wins**.
- The values come from the device (read only): `GroupTag` and `Category` from
  `HKLM\SOFTWARE\SelfX\Support` (REG_SZ, only administrators can write, allowed are
  letters, digits, spaces, `.`, `_`, `-`, up to 64 characters) and `OU` from the
  distinguished name of the computer account (hybrid devices,
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine`). Invalid
  values count as empty.
- Invalid entries (wrong address, unknown unit, invalid expression, duplicate id, more
  than 500 units or 2000 rules) are skipped and named as a warning in the SelfX log. If
  the file is unreadable, the default address applies.
- Group tag, unit and category appear as fields in the ticket (`Group tag`,
  `Support unit`, `Device category`).
- **Check before rollout:**
  `tools\Test-SelfXTicketRouting.ps1 -GroupTag ... -Category ... -OU ...` shows errors
  of the file and the result for the given values. It sends nothing and reads no
  registry.

**Note on mailboxes:** use only shared functional mailboxes, not personal ones.
`Ticket_Config.xml` is on every device and every user can read it. Addresses that not
everyone should see therefore belong in the registry values per device. There only the
address of the own unit is stored.

**Security:** recipient and copy come only from `Tool_Config.xml`, `Ticket_Config.xml`
and the registry (each writable only by administrators). The user cannot change them.
Fields are sanitised: no line breaks in the subject, fixed lengths, the device name
must be a valid name. Free text and device information are in code blocks, so a ticket
system does not run commands from them (for example GitLab quick actions). Test
whether this works in your version before you turn it on. The device information
contains addresses (for example proxy) and device data and is meant for the IT. The log
names only the result (`Outlook`, `Manual`, `Error`) and the number of lines, never the
text.

### Copilot Chat

Optional and off by default (`Copilot_Enabled` = `False`). When the function is on and
`Copilot_Url` is a valid address, the help dialog (?) shows the row *Ask Copilot Chat*
with the button *Prepare text*. The help button must be visible for this
(`Show_Support_Button` = `True`). Copilot Chat is the chat function in Microsoft 365.
SelfX uses no interface and no token: the user pastes the text into Copilot Chat.

**Flow (user context, no elevated rights):**

1. The user describes the problem in their own words (optional, up to 1000 characters)
   and chooses *Create text*.
2. SelfX shows the finished text in a preview. The user can read and change it.
3. *Copy and open Copilot* puts the text in the clipboard and opens the address from
   `Copilot_Url`. The user pastes the text (Ctrl+V) and sends it. SelfX sends nothing.
   SelfX asks Windows **not** to keep the text in the clipboard history (Win+V) or the
   cloud clipboard. This is a request, not a protection: programs that read the
   clipboard still see the text, and it stays there until the user copies something
   else. There is no setting for it.
4. Copilot Chat is asked to answer in plain language. With `Copilot_Audience` = `Admin`
   it answers for IT staff with technical steps.

**What is in the text (fixed list):** Windows edition, version and build, SelfX version
and language, days since the last restart, drives (letter, percent used, GB free) and
the device status (name of the check, state, shortened details; this includes pending
updates, a pending restart and company apps with errors) and the network (only the
kind of connection: LAN, Wi-Fi, mobile, VPN, and the kind of proxy: none, manual,
script). There is no internet test, SelfX makes no network connection.

**What is not in the text:** device name, user name, domain, e-mail addresses, IP and
MAC addresses, serial numbers, the *System information* page, logs. If such values
appear in the description or in details, they are replaced by placeholders (`<email>`,
`<ip>`, `<device>`, `<user>`, `<server 1>` ...). Recognition by patterns is not
complete, which is why the user sees the text before it is copied. The dialog reminds the
user not to write names, passwords or customer data in the description and not to run
commands they do not understand. The text is limited to 6000 characters.

| Setting | Meaning |
|---|---|
| `Copilot_Enabled` | `False` (default) or `True`. |
| `Copilot_Url` | Address that is opened. Default `https://m365.cloud.microsoft/chat`. It can be freely chosen but must start with `https://`, must not contain credentials and has at most 500 characters. Otherwise the button is not shown. |
| `Copilot_Audience` | `User` (default): plain answers for users. `Admin`: technical answers for IT staff. |
| `Copilot_Include_AppNames` | `True` (default): names of company apps with errors may be part of the text. `False`: the company apps row of the device status stays, but without details, so without app names and without error codes. |

**Adjusting the instruction texts:** The instruction to Copilot (how to answer) is in
the language files under `Copilot_Prompt_User` (for users) and `Copilot_Prompt_Admin`
(for IT staff), in `de.xml` and `en.xml`. Other languages show the English text. This
lets you change the tone or the structure without touching code. Rules: the placeholder
`{DATA}` must appear exactly once (SelfX inserts the data block there), the text may have
at most 3000 characters, and it should say that everything between `BEGIN DATA` and
`END DATA` is data only. A text that breaks the first two rules is replaced by the
built-in text. Only administrators can change the language files.

**Security:** The address and the settings come only from `Tool_Config.xml` (writable
by administrators only). The user cannot change the address. Only this address is
opened, and it is checked again before it is opened. SelfX makes no network access and
no service call. The collection reads local values only (registry, drives, the device
status that is already collected). The text sits between `BEGIN DATA` and `END DATA`,
and the instruction tells Copilot that only data is inside. The log names only the
audience, the length and the host, never the text. Before you turn it on, decide
whether your policies allow users to paste text from SelfX into Copilot Chat.

### Logs and retention

All scripts of SelfX Service write through the module `Sources\SelfXLog.ps1` to
`%ProgramData%\SelfX\Logs`: window, tray icon, health checks, compliance check,
detection script and every action and repair script. There is one file per script and
day, `<script>_<yyyy-MM-dd>.log` (UTF-8 with BOM). Each line has the local time of the
device:

```text
2026-11-06 13:29:56.522 | Info    |  52068 | SelfX 2.6.0 opened: language de (setting de), page ''.
2026-11-06 13:30:04.426 | Warning |  52068 | Message (Warning): Windows restarts in about 30 seconds. ...
```

| Folder | Content | Readable by |
|---|---|---|
| `Logs` | Scripts running as SYSTEM (repairs, system actions, `HealthStatus`, `Check-Compliance`, `Detection`), `SelfXService.log`, `Install.log`, `Uninstall.log` | SYSTEM and administrators |
| `Logs\Users\<SID>` | The user's scripts: window (`SelfX_*`), tray icon (`SelfX_Tray_*`), user actions | the user, SYSTEM and administrators |

The window logs its start, every action with the user's answer, the result of every
service action (status and exit code), status checks started by the user, language
changes and **every message shown**. The tray icon logs status changes, notifications
and why it ends. `HealthStatus` logs every result of the background check.

`Install.ps1` sets up `Logs\Users` so that each user can create only their own folder
and cannot list or read the folders of others. A folder that is a link or belongs to
another account is never used. If `Logs\Users` cannot be used, the user logs go to
`%LOCALAPPDATA%\SelfX\Logs`.

**Retention:** files older than `Log_Retention_Days` (1 to 3650, default **90**) are
deleted:

- The service deletes old `*.log` and `*.old` files in `Logs` once a day, even when the
  background check is off, and writes the number to `SelfXService.log`.
- Each user deletes old files in their own folder `Logs\Users\<SID>`, at most once a
  day, when a SelfX script starts. The service never deletes there, because a delete
  as SYSTEM must not follow a link a user could create.

`Uninstall.ps1` keeps the logs. With `-RemoveLogs`, `%ProgramData%\SelfX` is deleted.

### Device status

The *Device status* page shows the result of the local health checks. It reads the
cache of the background check when SelfX is opened and requests `HEALTH` when the user
checks again.

| Status | Meaning |
|---|---|
| **OK** (green) | Everything is fine. |
| **Pending** (yellow) | An action is open, for example updates or compliance. This is a warning, not an error. |
| **Error** (red) | The check failed. |
| **Unknown** (grey) | Data is missing, the source is not supported or the service is not available. This is not a passed check. |

Technical details stay in English, labels and status words follow the language of the
interface. Copy and export contain the results. The report is a snapshot, not
continuous monitoring.

Set up `Sources\Health_Config.xml` before packaging. The installer copies it next to
`HealthStatus.ps1`, writable only by administrators and SYSTEM. The client can hand
the service neither a path nor code.

**The checks:**

| Check | What is checked |
|---|---|
| IME | The service `IntuneManagementExtension` must run. If it is missing or stopped, this is an error. |
| Defender | Service, antivirus and real-time protection are on, the signatures are not reported as outdated and are at most 7 days old. Passive mode or third-party antivirus can therefore give an error. A failed query is *Unknown*. The detail names the signature version and the time of the last update. By default the row offers *Fix* (`Update-MpSignature`). |
| Compliance | Intune evaluates compliance in the cloud, Windows stores no local status for it. With `<Compliance Script="Check-Compliance.ps1" />`, the package checks the local criteria of a typical Intune compliance policy: Intune enrolment, BitLocker on the system drive, Secure Boot, TPM, firewall (all profiles), Defender (antivirus, spyware protection, real-time protection, current signatures) and optionally a minimum Windows version. Match `$Require` in the script to your policy. The Company Portal stays authoritative. Exit `0` = OK, any other exit code = *Pending*. A missing script, an exception or a timeout = Error. Without the element `Compliance`, the row is *Unknown*. While the row is not OK, it offers *Fix* (update the Defender signatures). |
| Applications | Cache of the IME report for Win32 apps plus your own application checks. Success (`1000`) is OK, `5000` to `5999` are errors, everything else is *Unknown*. Error beats Unknown, Unknown beats OK. Without any included result, the overall result is *Unknown*. |
| Disk | Per fixed drive an error if at least 90 % is used **or** less than 20 GiB is free (shown as GB). Exactly 20 GiB is enough only if usage is below 90 %. The values are configurable. |
| BitLocker | Every OS and fixed data volume must be fully encrypted with protection on. Suspended, unencrypted or partly encrypted volumes are errors. Unreadable data is *Unknown*. Keys and recovery secrets are not collected. |
| Pending reboot | Error if Windows reports a restart: `RebootPending` (Component Based Servicing), `RebootRequired` (Windows Update), `RebootRequired` of the Windows Update Agent, orchestrator updates with `ReadyToReboot` (the detail names the updates) or a pending computer rename. `PendingFileRenameOperations` is ignored on purpose, because installers often leave it set permanently. Unreadable registry data is *Unknown*. |
| Updates to install | Searches only the **local cache of the Windows Update Agent** (offline, no scan, download or installation). Every uninstalled, not hidden update (except pure browse or optional updates) gives *Pending* and is listed in the detail. An empty cache is OK only if the last successful scan was at most `MaxSearchAgeDays` (default 14) ago, otherwise *Unknown*. Updates distributed only through ConfigMgr are not included. While updates are pending, the row offers *Fix* (see [Repairs](#repairs)). |
| Additional services | Exact service name and expected state (`Running` or `Stopped`). |
| Script checks | Exit `0` = OK, exit `1` = Error. Other exit codes, missing files, exceptions and timeouts are errors too. |

**Limits of the application check:** the IME cache is an implementation detail, not a
stable Microsoft interface, not an inventory of installed software and not a live
report from Intune. It can be outdated and can hold several entries for the same app.
All available entries count: a failed entry is not dropped because another one
succeeded. If the format changes or data is unreadable, the result is *Unknown*. A
successful installation does not prove that the app works. For apps without IME or for
function checks, use your own checks.

**Example `Health_Config.xml`:**

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

**Excluding and naming apps:** `Exclude` compares names case-insensitively with
PowerShell wildcards (`*`, `?`, `[...]`). App ids can be excluded as well. SelfX takes
the name from the IME cache, otherwise from the app policies in the IME logs
(`AppWorkload.log`), and shows the app id only after that. With
`Application Id="..." Name="..."` you set a name when none is found. Excluded checks do
not run. If you exclude all apps, the result is not *OK*. The row is called *Company
apps (Intune)*. Its detail names failed apps with the error code, for example
`Monitoring Agent (error 0x87D1041C)`. Apps that do not apply to the device
(EnforcementState 3000 to 3999) are not counted.

**Your own check scripts:** create `Sources\HealthChecks` and put your `.ps1` files
there. Only plain file names are allowed, no subfolders, absolute paths or `..`.
Reparse points on the folder or the script are rejected. The standard package contains
only `Check-Compliance.ps1`. Example of a read-only check:

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

**Security and rules for check scripts:**

- They run non-interactively as SYSTEM at every refresh, without a prompt.
- They must only read and be repeatable. They must never restart, sign out, change
  settings, ask for input or start detached processes.
- Review and sign them before rollout. SelfX cannot prove that a script only reads.
  Do not put credentials in them.
- The exit code sets the status. The last non-empty stdout line (up to 400 characters)
  is shown as the detail, otherwise `Exit code: N`. stderr is discarded.
- Timeout: 1 to 30 seconds per script, default 30. At most 5 script checks in total
  (compliance, application checks and your own together) and 16 additional services. On
  a timeout, SelfX ends the process tree.
- A service request takes at most 240 seconds and returns at most 20,000 characters.
  Results that are too large are rejected, not shown as OK.
- Repairs and checks requested by SelfX share one lock. A concurrent request gets
  *Busy*. A check requested while a background check runs waits for it to finish.

**Tests before packaging:** run all tests of the package (see the
[release checklist](Installation.md#release-checklist-selfx-service)).
`Test-Catalog.ps1` checks the catalogue and the health configuration. The tests replace
system checks and script runs with mocks. They do not install a service.
`Test-ServicePipe.ps1` starts only the pipe listener under a test pipe name.
`Test-Scripts.ps1` runs every action and repair script in a sandbox with mocks. Only
the read-only scripts `Check-Compliance.ps1`, `Detection.ps1` and `HealthStatus.ps1`
run for real.

#### Single check

The client can request a single check: `HEALTH <Id> [<Base64-UTF-8-name>]`, for
example `HEALTH Disk Qzo=` for drive `C:`. The service accepts only known ids (`IME`,
`Defender`, `Compliance`, `Applications`, `Disk`, `BitLocker`, `PendingReboot`,
`Updates`, `Service`, `Custom`) and a strictly Base64-encoded name. `HealthStatus.ps1`
then runs only that check from the protected `Health_Config.xml`. A name that is not
configured there is never checked and gives *Unknown*. The interface replaces only the
affected card, the service updates only those rows in the cache. Rows of type
`Collection` (collector errors) trigger a full refresh.

### Repairs

The health checks only read. For a status row to offer the button *Fix*, put a repair
script in `Sources\Scripts_to_run` and add it to `Health_Config.xml`:

```xml
<Remediations>
  <Remediation Id="IME" Script="SelfX_Intune_RestartService.ps1" />
  <Remediation Id="Service" Name="Spooler" Script="Repair-Spooler.ps1" />
  <Remediation Id="Disk" Name="C:" Script="Repair-Disk.ps1" />
  <Remediation Id="Custom" Name="Business check" Script="Repair-BusinessCheck.ps1" />
  <Remediation Id="Compliance" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
</Remediations>
```

| Attribute | Meaning |
|---|---|
| `Id` | Type of the check: `IME`, `Defender`, `Compliance`, `Applications`, `Disk`, `BitLocker`, `PendingReboot`, `Updates`, `Service`, `Custom`. |
| `Name` | Optional. Exact technical name of the row (not the translated label). Without `Name`, the repair applies to every row of this type. Overlapping assignments are a configuration error. |
| `Script` | Script in `Scripts_to_run`. |
| `When` | `NotOK`: offer only while the row is not OK. Default `Always`: always offer. |
| `TimeoutSeconds` | Time limit of the service for this repair. Positive number up to 7200, default 900. |
| `OtherSessions` | `Block` works as in the action catalogue. The supplied configuration sets it for `Updates` and `PendingReboot`. If the script is also a `System` action in the catalogue, the catalogue entry applies first. Then set `Block` there too. |

**How a repair runs:** the user confirms. The service checks the script against the
protected list of repairs (or the catalogue of system actions) and runs it as SYSTEM
with a time limit and logging. Paths, arguments or scripts from the user are never
accepted. Repair scripts need no catalogue entry. Every signed-in user can request the
released repairs.

The window allows only one repair at a time. Afterwards it re-checks only the repaired
status. The result of that check is shown, not the exit code of the script. A repair
that returns 0 can therefore leave a red status. If the check or the service is not
available, the result is *Unknown*.

Repairs must run without user interaction. They must never sign out, restart, shut
down, sleep or start detached processes. This also applies to `PendingReboot`: the
re-check only shows whether a restart is still pending. Review, deploy and sign repair
scripts as an administrator.

**Supplied repairs:**

*Defender signatures* (`SelfX_Defender_UpdateSignature.ps1`): runs `Update-MpSignature`
as SYSTEM with the update sources of the Defender policy. Active for Defender and
Compliance, in each case only while the row is not OK:

```xml
<Remediation Id="Defender" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
<Remediation Id="Compliance" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
```

To offer the update also for a Defender row that is OK, remove `When="NotOK"`. It needs
a reachable update source. Offline it ends with exit `1` and the status stays. Remove
the lines to turn it off.

*Updates* (`SelfX_Updates_Install.ps1`):

```xml
<Remediation Id="Updates" Script="SelfX_Updates_Install.ps1" When="NotOK" TimeoutSeconds="7200" />
```

While updates are pending, the row *Updates to install* offers *Fix*. During the run it
shows *Running…*. Afterwards SelfX reports that Windows Update has finished and checks
the whole device status again. The script runs as SYSTEM:

1. It starts the update scan for Microsoft Store apps through the MDM bridge
   (`MDM_EnterpriseModernAppManagement_AppManagement01.UpdateScanMethod`). This also
   works when the Store is blocked for users. The Store then updates the apps in the
   background.
2. It starts "Check for updates" of the Windows Update orchestrator through the
   documented WinRT API `Windows.Management.Update.WindowsUpdateManager`
   (`StartScan(userInitiated: true)`, the same as the button in Settings). Windows
   downloads and installs the updates itself, following the policies of the device.
   *Settings > Windows Update* shows the progress. The script waits up to 90 minutes
   until nothing is downloading or installing any more and logs every update with
   action, progress and reason for waiting, for example
   `2026-11 Security Update (KB5132061): action Install, progress Install 70`. Updates
   that only wait for the restart (`ReadyToReboot`) count as done. Feature updates (a
   new Windows version) are left to the update policy.

The script **never** restarts Windows. If an update needs a restart, the row *Pending
reboot* shows it. Exit `0`: all updates installed or nothing to do. Exit `1`: search,
download or installation failed for at least one update (the KB numbers are in the
log), the orchestrator is still working after 90 minutes, or the WinRT component
`WinRT\SelfXWinRT.dll` is missing (then please reinstall SelfX; there is no other
update path). A Store scan that cannot be started (for example without the MDM bridge)
is logged but does not make the repair fail. The log is in
`%ProgramData%\SelfX\Logs\SelfX_Updates_Install_<date>.log`. Remove the line to turn
the repair off.

*Restart* (`SelfX_Device_Restart.ps1`):

```xml
<Remediation Id="PendingReboot" Script="SelfX_Device_Restart.ps1" When="NotOK" />
```

The row *Pending reboot* offers *Restart now*. SelfX shows its own warning: Windows
restarts about 30 seconds after the confirmation, the user should save their work and
close all programs. After the confirmation the service runs
`shutdown.exe /r /t 30 /d p:4:1` as SYSTEM. The restart is **never** part of *Fix all
problems*. Remove the line to hide the button.

*App retry* (`SelfX_Apps_RetryInstall.ps1`):

```xml
<Remediation Id="Applications" Script="SelfX_Apps_RetryInstall.ps1" When="NotOK" TimeoutSeconds="300" />
```

The row *Company apps (Intune)* offers *Retry* while an app installation has failed.
The Intune Management Extension otherwise retries a failed Win32 app only after its
retry schedule (24 hours by default). For every app with an error in the local IME
cache, the script removes the cached result and the retry schedule entries (GRS) and
restarts the service `IntuneManagementExtension`. The IME then contacts Intune and
installs the app again within a few minutes. The user sees the progress in the Company
Portal. No app is uninstalled. Only the IME cache under
`HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps` is changed. If the
installation fails again, the problem is in the app or its assignment. The user can
then send the device logs to the support, and the support sees the error code in
Intune.

### Branding

Company logo, icon and colours are in the `Branding` section of `Tool_Config.xml`.
Copy the images to `SelfX Service\Sources` or to a subfolder such as `Sources\Branding`
before building the package. Paths are relative to the installation folder. All keys
are optional. If a value is empty or invalid or the file is missing, the default
applies.

The supplied `Tool_Config.xml` contains placeholders: the logo
`Branding\company_logo.png` ("YOUR LOGO"), the blue of the SelfX logo (`#0072BC`) and
the contacts `Mon-Fri 08:00-17:00`, `+1 555 0100`, `support@example.com` and
`https://support.example.com`. Replace them with your values before building the
package, or empty them to hide them.

| Key | Default | Meaning |
|---|---|---|
| `Brand_Logo` | empty (no logo) | Logo at the top of the navigation and in the About dialog. PNG, JPG, BMP, GIF or ICO, at most 196 pixels wide in the navigation. A transparent PNG fits both designs best. If empty, the About dialog shows `About_Logo`. |
| `Brand_Logo_Height` | `40` | Height in the navigation in pixels (16 to 120). The width scales accordingly. |
| `Brand_Icon` | `Repair.ico` | Icon of window, taskbar and tray icon. `Install.ps1` also uses an `.ico` file for shortcuts and the entry under Apps & features. SelfX has its own taskbar button (AppUserModelID `SelfX.SelfService`) with this icon. A pinned SelfX starts `SelfX.exe`. Use an `.ico` with 256 × 256 pixels for a sharp icon. |
| `Brand_Accent_Color` | empty (uses `Tool_Color`) | Company colour as `#RRGGBB` for buttons, selection, navigation marker, links and icons. The text colour (white or black) is chosen automatically. Very dark or very light colours are adjusted for text and icons so that they stay readable in both designs. |
| `Brand_TitleBar_Color` | window background | Background of the title bar as `#RRGGBB`. The text colour is chosen automatically. |
| `Brand_Run_Button_Color` | accent colour | Start buttons (play) and *Fix*. |
| `Brand_Info_Button_Color` | accent colour | "More information" icons. |

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

**Design:** `Tool_Theme` (`Auto`, `Dark`, `Light`) sets the default design. The default
is `Auto`, also when the value is missing or unknown. `Auto` follows the Windows app
mode (`AppsUseLightTheme` in
`HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`, light if the value
is missing) and reacts to changes while SelfX is open. If `Show_Theme_Button` is
`True`, each user can choose *Automatic*, *Dark* or *Light* in the settings dialog. The
choice is stored in `HKCU\Software\SelfX\Theme` and takes precedence over
`Tool_Theme`. The branding colours apply in both designs. `Tool_Color` accepts the
former MahApps colour names (`Cyan`, `Teal`, `Blue` ...). SelfX Service no longer uses
MahApps.Metro and downloads nothing from the network for this.

### Languages

The base language is German. With `Tool_Language` = `Auto`, SelfX follows the Windows
display language. Users can choose a language themselves under *Settings* (gear). The
texts are in `Sources\Languages\<culture>.xml`:

| File | Language | File | Language | File | Language |
|---|---|---|---|---|---|
| `en.xml` | English (reference) | `pl.xml` | Polish | `hi.xml` | Hindi |
| `de.xml` | German (base language) | `ru.xml` | Russian | `bn.xml` | Bengali |
| `fr.xml` | French | `uk.xml` | Ukrainian | `zh-Hans.xml` | Chinese (simplified) |
| `es.xml` | Spanish | `tr.xml` | Turkish | `zh-Hant.xml` | Chinese (traditional) |
| `it.xml` | Italian | `ar.xml` | Arabic (right to left) | `ja.xml` | Japanese |
| `pt.xml` | Portuguese | `fa.xml` | Persian (right to left) | `ko.xml` | Korean |
| `nl.xml` | Dutch | `ur.xml` | Urdu (right to left) | `vi.xml` | Vietnamese |
| `id.xml` | Indonesian | `th.xml` | Thai | `sw.xml` | Swahili |

English is the reference for the keys and the fallback. The other languages were
machine-translated. Have native speakers review them before a rollout.

**Which language applies?** SelfX checks in this order:

1. The user's choice (stored in `HKCU\Software\SelfX\Language`). *Automatic* means:
   continue with step 2. The choice is ignored if `Show_Language_Setting` is `False`, if
   the value is not a culture name or if the language file is missing. After a change,
   SelfX restarts on the same page, the tray icon follows. If a repair is still
   running, the new language applies the next time SelfX is opened.
2. `Tool_Language` in `Tool_Config.xml`.
3. The culture and its parent cultures. `de-CH` uses `de.xml`, `pt-BR` uses `pt.xml`,
   `zh-CN` uses `zh-Hans.xml`, `zh-TW` uses `zh-Hant.xml`. Swiss German (`gsw`) uses
   `de.xml`.
4. If no file matches, `de.xml` applies.

If a text is missing in the chosen language, it appears in English (`en.xml`).
Catalogue texts fall back to the English base text in `Issues_List.xml`. A label is
therefore never empty.

**Structure of a language file:**

| Section | Content |
|---|---|
| `UI` | Texts of the window, dialogs, tooltips, message bar, device status, system information and tray icon. `{0}`, `{1}` are placeholders, for example for the action name. |
| `SystemInfo` | Labels and values of the system information and the status checks |
| `Catalog/Categories` | Display names of the categories |
| `Catalog/Messages`, `Catalog/Actions` | Shared messages, plus `Name`, `Explanation` and `Alerte_MSG` per action `Id`. Fields with `Ref` take the translated message. |

**Add a language:**

1. Copy `en.xml` (or a complete translation such as `de.xml`) to `<culture>.xml`. Use
   the neutral culture name, for example `cs.xml`, so that all regional variants use
   the file.
2. Set `Culture`, `Name` and `NativeName` on the root element. For right-to-left
   scripts, set `FlowDirection="RightToLeft"`.
3. Translate the texts. Keep element names, ids and placeholders, and the pattern
   `|*.txt|` in `SystemInfo_Export_Filter`.
4. Check the file and then build the package:

   ```powershell
   & '.\SelfX Service\Test-LanguageFiles.ps1' -Culture cs
   ```

   The check reports missing or unknown keys, broken placeholders and catalogue entries
   that do not exist. Without `-Culture` it checks all files.

No code change is needed. To change a text for your company, for example the main
title, edit it in the language files.

## Rolling out changes safely

1. Back up the current XML files and scripts.
2. Check that the XML stays well-formed.
3. Check that every script that is used exists in the package.
4. Test the actions and confirmation texts on a test device.
5. Deliver changes only as a new package version (Intune package, see
   [Installation](Installation.md#building-the-intune-package)). SelfX does not download
   configuration from the network.
