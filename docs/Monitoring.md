# Monitoring

SelfX checks the device status on every device (see [Device status](Configuration.md#device-status)). Two
optional ways show this status centrally. Both only read what the SelfX service already writes on the device.
SelfX itself sends nothing and stays fully offline.

| Way | Systems | What you need |
|---|---|---|
| [Intune Remediations](#intune-remediations-windows-11) | Windows 11 | Intune and a license for Remediations (for example Windows Enterprise E3 or E5) |
| [Log Analytics](#log-analytics-with-the-azure-monitor-agent) | Windows 11 and Windows Server | The [inventory file](#inventory-file), the Azure Monitor Agent, a data collection rule and a Log Analytics workspace |

The package wizard offers both on the page *More settings* and puts the files into the output folder
(`Detect-SelfXHealth.ps1`, `SelfX-Inventory-DCR.json`). For a package for Windows Server it offers only the
inventory file: Intune does not manage Windows Server.

## Contents

- [Intune Remediations (Windows 11)](#intune-remediations-windows-11)
- [Inventory file](#inventory-file)
- [Log Analytics with the Azure Monitor Agent](#log-analytics-with-the-azure-monitor-agent)
- [Sample queries (KQL)](#sample-queries-kql)
- [What was not tested](#what-was-not-tested)

## Intune Remediations (Windows 11)

`tools\Intune\Detect-SelfXHealth.ps1` is a detection script for Intune Remediations. It runs as SYSTEM in
Windows PowerShell 5.1, reads the status cache of the service and changes nothing. No remediation script is needed.

**What it checks first.** The cache `%ProgramData%\SelfX\Cache\Health.json` is used only when:

- Windows is Windows 11 and SelfX is installed (`%ProgramFiles%\SelfX\Config` exists),
- neither `%ProgramData%\SelfX`, the folder `Cache` nor the file is a link,
- the file belongs to SYSTEM or the Administrators group (checked by SID),
- the file has 1 to 60000 bytes and is valid JSON,
- the file is younger than two intervals of the background checks (`IntervalMinutes` in `Health_Config.xml`,
  default 15, so 30 minutes).

**Output.** Exactly one line of at most 2000 characters (Intune keeps at most 2048):

```text
SelfX Error | IME=OK; Defender=OK; Compliance=Pending; Applications=Error; Disk=OK; Updates=Pending | FailedApps=0a1b2c3d-0000-4000-8000-00000000000a:0x87D1041C
```

Per check type the worst status of its rows (`Error`, `Pending`, `Unknown`, `OK`), then at most 20 failed apps
with their error code (`Stalled` for a download without progress). The line has no names, no detail texts, no user
names and no paths. It also has no time, so it only changes when the status changes.

| Exit code | Meaning | Intune shows |
|---|---|---|
| `0` | No row is `Error` (`Pending` and `Unknown` are warnings) | Without issues |
| `1` | A row is `Error`, or the cache cannot be used (`SelfX Unavailable \| <reason>`) | With issues |

**Create the script package.** In the Intune admin center: *Devices* > *Manage devices* > *Scripts and
remediations* > *Create script package*.

1. *Detection script file*: `Detect-SelfXHealth.ps1` from the output folder of the wizard. No remediation script.
2. *Run this script using the logged-on credentials*: **No** (SYSTEM).
3. *Enforce script signature check*: **No**. Yes only when the wizard signed the script (trust mode Signature)
   and the signing certificate is trusted on the devices.
4. *Run script in 64-bit PowerShell*: **Yes**.
5. Assign it to the same device groups as SelfX, with a schedule such as daily.

The result is in the package under *Device status*, column *Pre-remediation detection output*.

**Good to know.**

- On battery the background checks pause (`PauseOnBattery`), and with `Background Enabled="false"` the cache is only
  updated when a user opens SelfX. The cache then gets older than two intervals and the line says
  `SelfX Unavailable | status cache is older than ...` (exit code 1).
- The file is plain ASCII, so Intune reads it as UTF-8 also with an enforced signature check.
- Microsoft Learn: [Remediations](https://learn.microsoft.com/intune/device-management/tools/deploy-remediations)
  (licenses, settings, the limit of 2048 characters).

## Inventory file

With `<Inventory Enabled="true" />` in `Health_Config.xml` (or the question in the wizard) the service appends one
line to `%ProgramData%\SelfX\Inventory\SelfX.Inventory.json` after every full check. Default: off.

- Format: JSON Lines (one JSON object per line), UTF-8 without byte order mark, fixed schema.
- Rights: like the cache (SYSTEM and administrators). The service does not write through a link.
- Size: `MaxSizeKB` (64 to 10240, default 1024). A larger file is renamed to `SelfX.Inventory.json.old`; an older
  `.old` is deleted. The name `.old` does not match the file pattern of the collector, so no line is read twice.
- Windows Server: nothing is written while `TerminalServer_Health` is `Off` (the default). With `AdminOnly` the
  file is written.
- Uninstall removes the folder.

**Schema version 1** (every field in every line, in this order):

| Field | Type | Values |
|---|---|---|
| `SchemaVersion` | int | `1` |
| `TimeGenerated` | datetime | Time of the check in UTC, ISO 8601 |
| `Mode` | string | `Client` (Windows 11) or `TerminalServer` (Windows Server) |
| `Overall` | string | Worst status of all rows: `OK`, `Unknown`, `Pending`, `Error` |
| `IME`, `Defender`, `Compliance`, `Applications`, `Disk`, `BitLocker`, `PendingReboot`, `Updates`, `Service`, `Custom` | string | Worst status of the rows of this type; empty = not checked |
| `FailedApps` | string | `<app id>:<error code>` (or `:Stalled`, `:-` without a valid code), separated by `;`, at most 20 |

Example:

```json
{"SchemaVersion":1,"TimeGenerated":"2026-11-28T08:00:00Z","Mode":"Client","Overall":"Error","IME":"OK","Defender":"OK","Compliance":"Pending","Applications":"Error","Disk":"OK","BitLocker":"OK","PendingReboot":"OK","Updates":"Pending","Service":"","Custom":"","FailedApps":"0a1b2c3d-0000-4000-8000-00000000000a:0x87D1041C"}
```

The file contains no names, no detail texts and no user names. The device name is added by the collector
(column `Computer`), not by SelfX.

## Log Analytics with the Azure Monitor Agent

The steps follow Microsoft Learn (checked on 2026-11-28). They were **not tried** with SelfX; see
[What was not tested](#what-was-not-tested).

1. **Workspace.** A Log Analytics workspace in the region of the data collection rule.
2. **Table.** Create the custom table `SelfXInventory_CL` before the rule. Microsoft Learn names a REST call for
   this; the columns are those of the schema plus `Computer` and `FilePath`:

   ```powershell
   $columns = @(
       @{ name = 'TimeGenerated'; type = 'dateTime' }, @{ name = 'Computer'; type = 'string' }, @{ name = 'FilePath'; type = 'string' },
       @{ name = 'SchemaVersion'; type = 'int' }, @{ name = 'Mode'; type = 'string' }, @{ name = 'Overall'; type = 'string' }
   ) + @('IME', 'Defender', 'Compliance', 'Applications', 'Disk', 'BitLocker', 'PendingReboot', 'Updates', 'Service', 'Custom', 'FailedApps' |
       ForEach-Object { @{ name = $_; type = 'string' } })
   $body = @{ properties = @{ schema = @{ name = 'SelfXInventory_CL'; columns = $columns } } } | ConvertTo-Json -Depth 5
   Invoke-AzRestMethod -Method PUT -Payload $body -Path '/subscriptions/<subscription-id>/resourcegroups/<resource-group>/providers/microsoft.operationalinsights/workspaces/<workspace-name>/tables/SelfXInventory_CL?api-version=2021-12-01-preview'
   ```

3. **Agent.**
   - **Windows 11:** the Azure Monitor Agent client installer (MSI). The device must be Microsoft Entra joined or
     hybrid joined. Rules are associated with a *monitored object* of the tenant and then apply to **all** Windows
     clients of the tenant with this agent; a finer assignment is not possible. Microsoft describes the client
     installer as made for devices that are always connected; it is not optimized for laptops on battery.
   - **Windows Server:** outside Azure as an Azure Arc-enabled server, in Azure as a virtual machine with the agent
     extension. The rule is associated with the machines directly.
4. **Data collection rule.** Start from `SelfX-Inventory-DCR.json` (output folder of the wizard, or `tools\Intune`)
   and replace the values in angle brackets: region, subscription, resource group, workspace and the data collection
   endpoint (the samples of Microsoft Learn for JSON files contain `dataCollectionEndpointId`). The data source is
   `logFiles` with `format` `json` and the exact file pattern
   `C:\ProgramData\SelfX\Inventory\SelfX.Inventory.json`. In the portal: data source *Custom JSON Logs*,
   table `SelfXInventory_CL`, transformation `source`.
5. **Association.** Windows Server: associate the rule with the machines. Windows 11: associate the rule with the
   monitored object of the tenant.
6. **Check.** The table `Heartbeat` shows the agent; after the next full check of SelfX (default every 15 minutes)
   the table `SelfXInventory_CL` gets a line per device.

Microsoft Learn:
[Collect JSON file](https://learn.microsoft.com/azure/azure-monitor/vm/data-collection-log-json),
[DCR samples](https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-rule-samples#json-logs),
[Azure Monitor Agent on Windows client devices](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-windows-client).

## Sample queries (KQL)

Latest status per device:

```kusto
SelfXInventory_CL
| summarize arg_max(TimeGenerated, *) by Computer
| project Computer, TimeGenerated, Mode, Overall, IME, Defender, Compliance, Applications, Disk, BitLocker, PendingReboot, Updates, FailedApps
```

Devices whose latest status is an error:

```kusto
SelfXInventory_CL
| where TimeGenerated > ago(1d)
| summarize arg_max(TimeGenerated, *) by Computer
| where Overall == "Error"
```

Failed apps by app ID and error code:

```kusto
SelfXInventory_CL
| where TimeGenerated > ago(1d)
| summarize arg_max(TimeGenerated, FailedApps) by Computer
| where isnotempty(FailedApps)
| mv-expand App = split(FailedApps, ";") to typeof(string)
| extend AppId = tostring(split(App, ":")[0]), Code = tostring(split(App, ":")[1])
| summarize Devices = dcount(Computer) by AppId, Code
| order by Devices desc
```

Devices without a line for two days:

```kusto
SelfXInventory_CL
| summarize Last = max(TimeGenerated) by Computer
| where Last < ago(2d)
```

## What was not tested

Tested with the test scripts (mocked, on the development PC): the detection script with a missing, old, broken,
empty, too large or foreign-owned cache, a cache behind a link, the length of the line and that no name or detail
text appears; the inventory line, rotation, links, `TerminalServer_Health` `Off` and the switch in `Health_Config.xml`;
the wizard (questions, files, guide).

**Not tried on a device:**

- the script package in Intune (upload, schedule, the column of the detection output, the signature check with a
  signed script),
- the Azure Monitor Agent on Windows 11 (client installer, monitored object) and on Windows Server (Azure Arc),
- the data collection rule `SelfX-Inventory-DCR.json`, the custom table, the transformation and the queries,
- whether the agent reads the file again correctly after the rotation to `.old`,
- whether a data collection endpoint is still needed for JSON files in your setup.
