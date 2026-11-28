# SelfX User Manual

**English** | [Deutsch](de/User-Manual.md)

SelfX helps you solve common problems on your computer yourself. Before you call or write to the
support team, you can try it here. Your support team decides which solutions are available.

![Troubleshooting page in the light design](images/selfx-troubleshooting-light.png)

## Contents

1. [Open SelfX](#open-selfx)
2. [The interface](#the-interface)
3. [Solve a problem](#solve-a-problem)
4. [Device status](#device-status)
5. [System information](#system-information)
6. [Contact support and send logs](#contact-support-and-send-logs)
7. [The SelfX icon next to the clock](#the-selfx-icon-next-to-the-clock)
8. [Settings: language and design](#settings-language-and-design)
9. [Important notes](#important-notes)

## Open SelfX

Start **SelfX** from the desktop icon, from the Start menu or from the SelfX icon next to the clock.
You do not need administrator rights for this.

You can resize and maximize the window. SelfX remembers the size. If SelfX is already open, the window
comes to the front.

## The interface

The bar on the left has three areas:

| Area | What you find there |
|---|---|
| **Troubleshooting** | Solutions for common problems |
| **Device status** | Checks of your device, for example disk space or updates. The number shows how many points need your attention. |
| **System information** | Details about your device that the support team often needs |

If the option is on for the device, the bar also shows the **Company wiki** button. It opens your company's wiki in the web browser.

SelfX has a **new design**: calm colors, large buttons and a hint at the top that shows the steps:
**Select problem – Confirm – Done**. There is a light and a dark design. By default SelfX follows
Windows.

Move the mouse over a button to see what it does. **Nothing happens without your confirmation.**

## Solve a problem

1. Open **Troubleshooting**.
2. Type a word into the search field, for example *Teams* or *slow*. Or click a category.
3. Click **i** to read what the solution does.
4. Click **Start**, read the message and confirm.

While a solution runs, its button shows a turning arrow and **Running…**. You cannot start the same
solution again during this time. Afterwards the message bar at the bottom shows whether it worked.

**Simplified view** shows a short list. **Detailed view** shows every single problem. The **?** button
explains the difference.

**Solutions for account and sign-in:** They only open a web page and change nothing on your device.

- **Forgot or expired password:** opens the page where you can reset your password yourself.
- **Manage sign-in methods:** opens the security info of your account, for example to add a new phone number or authenticator app.

**New in version 3.0 (examples):**

- **Citrix Workspace does not respond or does not show your apps:** restarts the Citrix Workspace app of your user account. Application and desktop sessions that are already open are not ended.
- **A program window is outside the screen:** moves windows of your user account that you can no longer see (for example after a monitor was disconnected) to the main screen. Nothing is closed.
- **Excel opens every file in the same window:** starts a second, independent Excel instance, so that you can compare two workbooks on two screens. Nothing is closed or changed.

**Solutions with a shield** need administrator rights. SelfX runs them through its local service, so you
do not need an administrator account. Only one such solution runs at a time.

**If another person is signed in** on the same device (for example on a shared PC), SelfX does not run
solutions that would disturb that person. These include the restart, updates, the disk check and the
restart of network adapters. SelfX tells you so. Try again later or ask the support team.

**At the bottom left** you see whether the SelfX service is running (green dot). With a red dot, solutions
with a shield and the device status are not available. Restart your computer or contact the support team.

## Device status

The **Device status** area shows one card for each check. These include company management, Microsoft
Defender, compliance, apps, disk space, BitLocker, a pending restart and updates. Problems are at the top.

| Color | Meaning |
|---|---|
| Green (**OK**) | Everything is fine. |
| Yellow (**Pending**) | Something should be done soon, for example updates. This is a warning, not an error. |
| Red (**Error**) | There is a problem. The text on the card says what. |
| Grey (**Unknown**) | SelfX cannot tell. This does **not** mean that everything is fine. |

SelfX checks the status in the background, usually every 15 minutes. On battery the check pauses. The line
under the title shows when the last check ran.

**What the buttons on the cards do:**

- **Fix** (wrench): repairs the problem automatically. Save your work first, confirm and wait. This can take
  several minutes. Afterwards SelfX checks the status again. The button appears only if your support team
  has prepared a repair. For example for **Updates to install**: SelfX searches, downloads and installs
  updates.
- **Restart now** (for **Pending restart**): restarts the computer so that updates can finish. Save your work
  and close all programs first. After your confirmation the restart starts after about 30 seconds. **Cancel**
  changes nothing. *Fix all problems* **never** restarts the computer.
- **Retry** (for **Company apps**): a company app could not be installed. SelfX restarts the installation at
  once. You can follow the progress in the company portal. If it fails again, send the logs to support.
  For known error codes the card says in one sentence what went wrong and what you can do (for example
  restart the device or free up disk space).
- **Arrow** on a card: checks only this status again. At the top: checks everything again.
- **Fix all problems**: runs all possible repairs one after another. Save your work first.

**Examples:**

- **Pending restart (red):** click **Restart now** or restart the computer yourself.
- **Updates to install (yellow):** click **Fix**. Or install updates under **Settings > Windows Update**.

## System information

The **System information** area shows details about device, Windows, user, management and network. The
last values appear at once and are updated in the background.

- **Double-click** a row to copy its value.
- The buttons at the top update the details, copy everything or save it as a file.
- Under the details you find **Tools**:
  - Synchronize Intune: re-sync the device management.
  - Check compliance.
  - Open the company portal.
  - **Remote support**: starts **Remote Help** if it is installed on your device. Otherwise it starts
    Quick Assist. A person from support can then see your screen, but only with your consent.
  - Collect the device management logs.
  - Send the device logs to support.

If the Citrix Workspace app is installed, its version appears under **Device**.

The details contain your device name, your user name and network addresses. Share them only with your
support team.

## Contact support and send logs

SelfX offers two ways to reach the support team.

**Show contact details:** Click **?** at the top right. You will find support hours, phone number, e-mail
address, Teams address and website. Buttons open an e-mail, a Teams chat or the website directly.

**Report a problem (ticket by e-mail):** If this function is switched on, the help dialog shows the row
**Report a problem**. Here is how it works:

1. Click **Create ticket** and describe the problem.
2. SelfX adds the details about your device automatically. You cannot deselect them.
3. You see the e-mail before it is sent. The recipient is shown in the dialog.
4. You send the e-mail yourself. **SelfX never sends anything by itself.**

If your mail program does not open with the file, SelfX marks the file in Explorer. Then attach it yourself.

**Ask Copilot Chat:** If this function is switched on, the help dialog shows **Ask Copilot Chat**:

1. Describe the problem in your own words (optional) and click **Create text**.
2. You see a preview. Read or change the text.
3. Click **Copy and open Copilot**. Paste the text into Copilot Chat (Ctrl+V) and send it yourself.

The text contains no names, e-mail addresses or IP addresses. Still check it before sending. Do not write
passwords or customer data into it. After copying, the text stays in the clipboard for a short time. If
SelfX is set up that way, it clears the clipboard after a few minutes.

**Send device logs to support:** Click **Send logs to support** at the bottom left, in the system information
or in the menu of the SelfX icon.

1. Confirm. SelfX collects the logs through its service. This takes a few minutes. Nothing on your device
   is changed.
2. Then an e-mail to support opens with the report as a `.zip` file attached. The report also contains the
   SelfX logs, so that support can see what you have already tried.
3. Describe your problem and send the e-mail.

The report contains your device name, your user name and logs. Only you and administrators can read it on the
device. Send it only to your support team.

## The SelfX icon next to the clock

The icon next to the clock shows the device status at a glance:

- **green**: everything is fine
- **yellow**: warning
- **red**: problem
- **grey**: no result yet

Move the mouse over it to see a summary. On Windows 11 the icon stays permanently next to the clock. It does
not disappear into the overflow menu (arrow).

When a problem is found, Windows shows a notification once. Clicking it opens the device status. If you do not
want notifications, switch them off with the **gear icon** or in the menu of the icon. The colored icon still
shows the status.

**Right-click the icon:** open SelfX, check the status now, send logs or hide the icon. To show it again, use
the gear icon in SelfX.

## Settings: language and design

Click the **gear icon** in SelfX:

- **Language:** choose your language. Each language is shown under its own name, for example *Deutsch* or
  *English*. SelfX restarts afterwards and remembers your choice. The icon next to the clock also uses the new
  language. **Automatic** uses the language of Windows. If that is not available, SelfX shows German. Texts that
  do not exist in your language appear in English. Some companies fix the language. Then this choice is missing.
- **Design:** *Automatic* follows Windows, *Dark* and *Light* set it permanently.
- **Show or hide** the icon next to the clock.
- **Switch notifications about problems** on or off.

Under **i** you find the version of SelfX.

## Important notes

- **Save your work** before you start a solution. Some solutions restart or close programs. A restart affects all
  open programs.
- **Disk check (chkdsk):** the check is scheduled for the next restart. It can take a long time. Restart the
  computer afterwards.
- **Network restart:** while the network adapters restart, the connection is briefly interrupted.
- **Free up disk space:** deletes temporary files and empties the recycle bin of your user.
- **Correct the time:** synchronizes the clock of your device with the time source.
- **Privacy:** SelfX sends nothing by itself. Logs, reports and texts go only to your support team, and only when
  you confirm it. Logs do not contain passwords. They are deleted automatically after 90 days.
- Contact your support team if a solution fails or the problem remains.
