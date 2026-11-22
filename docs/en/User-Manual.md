# SelfX user manual

**English** | [Deutsch](../User-Manual.md)

SelfX is a self-service interface for selected troubleshooting tasks. The
available actions depend on the XML catalogue configured by your support team.

## SelfX

SelfX helps you solve common problems on your device yourself. It is installed
on your device and also works without a network connection.

Start **SelfX (Self fix)** from the Desktop, the Start menu or the SelfX icon
next to the clock. The window can be resized and maximized; SelfX remembers its
size. If SelfX is already open, it comes to the front.

The bar on the left has three areas:

| Area | What you find there |
|---|---|
| **Troubleshooting** | Solutions for common problems |
| **Device status** | Checks of your device, for example disk space or updates. The number shows how many items need your attention. |
| **System information** | Information about your device for the support team |

Move the mouse over a button to see what it does. Nothing happens without your
confirmation.

### Solve a problem

1. Open **Troubleshooting**.
2. Type a word in the search field (for example *Teams* or *slow*) or click a
   category.
3. Click the **i** button to read more about a solution.
4. Click the round **play** button, read the message and confirm.

While a solution runs, its play button turns into a rotating arrow and
**Running…** is shown next to it; you cannot start the same solution a second
time. As soon as it has finished, the button is a play button again and the
message bar at the bottom shows whether it worked. The **Fix** button on the
**Device status** page shows the same while its repair runs.

Use **Simplified view** for a short list by product, or **Detailed view** for
specific problems. The **?** button next to it explains the difference.

Solutions with a **shield** need administrator rights. SelfX runs them for you
through the local SelfX service, so you do not need an administrator account.
Only one shield solution can run at a time.

If another person is signed in to the same device (for example on a shared PC
or in a remote session), SelfX does not run solutions that would disturb that
person, such as restarting the device, installing updates, the disk check or
restarting the network adapters. SelfX tells you so. Try again when you are the
only user, or ask your support team.

At the bottom left you see whether the SelfX service is running (green dot). If
it is not running (red dot), solutions with a shield and the device status are
not available. Restart your device or contact your support team.

### Device status

The **Device status** area shows one card per check: Windows management (IME),
Microsoft Defender, compliance, applications, disk space, BitLocker, pending
restart and updates to install. Your support team may add further checks.
Problems are shown first.

- **Green / OK:** everything is fine.
- **Yellow / Pending:** something should be done soon, for example updates to
  install. This is a warning, not an error.
- **Red / Error:** there is a problem. Read the text on the card.
- **Gray / Unknown:** SelfX cannot tell, for example because the information is
  not available. This does not mean that everything is fine.

The status is checked automatically in the background (usually every 15
minutes, not while the device runs on battery), so it is shown immediately.
The line under the title shows when it was last checked.

- **Fix** (wrench): repairs the problem automatically. Save your work, click
  the button and confirm. Afterwards SelfX checks this status again. The button
  appears only where your support team has prepared a repair, for example on
  **Microsoft Defender** (updates the virus definitions), on **Compliance**
  while your device is not compliant and on **Updates to install**: SelfX
  searches, downloads and installs the updates. This can take several minutes;
  the button shows **Running…** until it is finished, and you can keep working.
  Afterwards SelfX checks the device status again; if a restart is needed, the
  **Restart pending** card shows it.
- **Restart now** on **Restart pending**: restarts the device to complete
  updates and changes. SelfX asks first. Save your work and close all programs;
  the restart begins about 30 seconds after you confirm. **Cancel** changes
  nothing. *Fix all problems* never restarts the device.
- **Try again** on **Company apps (Intune)**: an app from your company could not
  be installed (the card shows its name). SelfX starts the installation again at
  once instead of waiting until the next day; follow it in the **Company Portal**.
  If it fails again, the cause is in the app or its distribution: send the logs to
  the support (button **Send logs to support**).
- **Arrows** on a card: checks only this status again, for example after you
  fixed something yourself. Nothing is changed on your device.
- **Arrows** at the top: checks everything again. This can take up to a minute.
- **Fix all problems**: appears at the top when at least one problem can be
  repaired automatically. After you confirm the list, SelfX runs the repairs one
  after another and then checks everything again. Save your work first.

All times (for example *last checked* or the last Defender update) are shown in
the time zone of your device, also right after the time zone changed, for
example during the first setup of a new device.

Examples: **Restart pending (red)**: click **Restart now** or restart the device
yourself. **Updates to install (yellow)**: click **Fix**, or install them in
**Settings** > **Windows Update**, or wait for the automatic installation.

SelfX logs what it does (for example which action you started and its result)
on your device, so your support team can follow a problem. The logs contain no
passwords and are deleted automatically after 90 days.

### System information

The **System information** area shows details about your device that the
support team often asks for: device, Windows, user and management, network.
The last known values are shown immediately and updated in the background.

- Double-click a line to copy its value.
- The buttons at the top refresh the information, copy everything (for example
  to paste it into a support request) or save it as a file.
- The **Tools** below the information sync your Intune apps, check compliance,
  open the Company Portal, start Quick Assist (a support person can see your
  screen, only with your consent), collect the device management logs or send
  the device logs to the support.

The information contains your device name, your user name and network
addresses. Share it only with your support team.

### Send the device logs to the support

If the support team asks for the logs of your device, click **Send logs to
support** (bottom left, in System information or in the menu of the SelfX icon
next to the clock).

1. Confirm. SelfX collects the logs with administrator rights through the
   local SelfX service; you do not need an administrator account. This can take
   several minutes. Nothing on your device is changed.
2. When the logs are ready, a new e-mail to the support opens with the report
   attached (a `.zip` file). It also contains the logs of SelfX itself (what
   SelfX did on your device and your own SelfX actions), so the support can see
   which solutions you already tried.
3. Describe your issue in the e-mail and send it. SelfX never sends anything by
   itself.

If Outlook cannot be opened automatically (for example with the new Outlook),
SelfX opens a new e-mail in your default mail app and an Explorer window with
the report selected. Attach that file to the e-mail. The report contains the
name of your device, your user name and the logs of the device. Only you and
the administrators can read it on the device. Send it only to your support team.

### Help, settings and the SelfX icon

- **?** (top right): how to reach your support team, for example support
  hours, phone number, e-mail, Teams chat or the website / ticket system.
  Buttons start an e-mail, a Teams chat or open the website.
- **Gear**: choose the language of SelfX, choose the appearance (*Automatic*,
  the default, uses the same dark or light mode as Windows, or always *Dark* or *Light*),
  show or hide the SelfX icon next to the clock and switch the
  notifications about problems on or off.
- **i**: version of SelfX.

The **SelfX icon** next to the clock shows the device status at a glance: a
green, yellow or red dot (gray = not known yet). Move the mouse over it to see
a summary. When a problem is found, for example low disk space, Windows shows a
notification once; click it to open the device status. If you do not want
these notifications, switch off **Show notifications about problems** with the
gear button or **Show notifications** in the menu of the icon; the colored icon
still shows the status. Right-click the icon to
open SelfX, check the status now, send the logs to the support or hide the
icon. You can show it again in SelfX with the gear button.

SelfX is shown in the display language of Windows. To use another language,
click the **gear** and choose your language under **Language**. The languages
are listed in their own name, for example *Deutsch* or *français*. SelfX
restarts in the selected language and remembers your choice. The SelfX icon
next to the clock also uses it. **Automatic** goes back to the language of
Windows. If your language is not available, SelfX is shown in English. Your
support team can hide the choice and set a fixed language.

## Important cautions

- Save open documents before actions that restart or terminate applications.
- The OneDrive CHKDSK action runs `chkdsk /r /f` on the system drive. It is scheduled for the next restart; restart the device afterwards.
  The check can take a long time.
- The network-adapter action interrupts network connectivity while adapters
  restart.
- The device-cleanup action empties the Recycle Bin and removes files from the
  current user's temporary directory.
- Contact your support team if an action fails or the issue remains.
