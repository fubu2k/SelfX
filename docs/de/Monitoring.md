# Überwachung

SelfX prüft den Gerätestatus auf jedem Gerät (siehe [Gerätestatus](Configuration.md#gerätestatus)). Zwei
optionale Wege zeigen diesen Status zentral. Beide lesen nur, was der SelfX-Dienst ohnehin auf dem Gerät schreibt.
SelfX selbst sendet nichts und bleibt vollständig offline.

| Weg | Systeme | Was Sie brauchen |
|---|---|---|
| [Intune-Remediations](#intune-remediations-windows-11) | Windows 11 | Intune und eine Lizenz für Remediations (zum Beispiel Windows Enterprise E3 oder E5) |
| [Log Analytics](#log-analytics-mit-dem-azure-monitor-agent) | Windows 11 und Windows Server | Die [Inventardatei](#inventardatei), den Azure Monitor Agent, eine Datensammlungsregel und einen Log-Analytics-Arbeitsbereich |

Der Paketassistent bietet beides auf der Seite *Weitere Einstellungen* an und legt die Dateien in den
Ausgabeordner (`Detect-SelfXHealth.ps1`, `SelfX-Inventory-DCR.json`). Für ein Paket für Windows Server bietet er
nur die Inventardatei an: Intune verwaltet Windows Server nicht.

## Inhalt

- [Intune-Remediations (Windows 11)](#intune-remediations-windows-11)
- [Inventardatei](#inventardatei)
- [Log Analytics mit dem Azure Monitor Agent](#log-analytics-mit-dem-azure-monitor-agent)
- [Beispielabfragen (KQL)](#beispielabfragen-kql)
- [Was nicht getestet wurde](#was-nicht-getestet-wurde)

## Intune-Remediations (Windows 11)

`tools\Intune\Detect-SelfXHealth.ps1` ist ein Erkennungsskript für Intune-Remediations. Es läuft als SYSTEM in
Windows PowerShell 5.1, liest den Status-Cache des Dienstes und ändert nichts. Ein Wartungsskript ist nicht nötig.

**Was es zuerst prüft.** Der Cache `%ProgramData%\SelfX\Cache\Health.json` wird nur verwendet, wenn:

- Windows ein Windows 11 ist und SelfX installiert ist (`%ProgramFiles%\SelfX\Config` existiert),
- weder `%ProgramData%\SelfX` noch der Ordner `Cache` noch die Datei ein Link ist,
- die Datei SYSTEM oder der Gruppe Administratoren gehört (per SID geprüft),
- die Datei 1 bis 60000 Byte groß und gültiges JSON ist,
- die Datei jünger als zwei Intervalle der Hintergrundprüfung ist (`IntervalMinutes` in `Health_Config.xml`,
  Standard 15, also 30 Minuten).

**Ausgabe.** Genau eine Zeile mit höchstens 2000 Zeichen (Intune behält höchstens 2048):

```text
SelfX Error | IME=OK; Defender=OK; Compliance=Pending; Applications=Error; Disk=OK; Updates=Pending | FailedApps=0a1b2c3d-0000-4000-8000-00000000000a:0x87D1041C
```

Je Prüfungsart der schlechteste Status ihrer Zeilen (`Error`, `Pending`, `Unknown`, `OK`), danach höchstens 20
fehlgeschlagene Apps mit Fehlercode (`Stalled` für einen Download ohne Fortschritt). Die Zeile enthält keine Namen,
keine Detailtexte, keine Benutzernamen und keine Pfade. Sie enthält auch keine Uhrzeit und ändert sich deshalb nur,
wenn sich der Status ändert.

| Exitcode | Bedeutung | Intune zeigt |
|---|---|---|
| `0` | Keine Zeile ist `Error` (`Pending` und `Unknown` sind Warnungen) | Ohne Probleme |
| `1` | Eine Zeile ist `Error`, oder der Cache kann nicht verwendet werden (`SelfX Unavailable \| <Grund>`) | Mit Problemen |

**Skriptpaket anlegen.** Im Intune Admin Center: *Geräte* > *Geräte verwalten* > *Skripts und Wartungen* >
*Skriptpaket erstellen*.

1. *Erkennungsskriptdatei*: `Detect-SelfXHealth.ps1` aus dem Ausgabeordner des Assistenten. Kein Wartungsskript.
2. *Dieses Skript mit den Anmeldeinformationen des angemeldeten Benutzers ausführen*: **Nein** (SYSTEM).
3. *Skriptsignaturprüfung erzwingen*: **Nein**. Ja nur, wenn der Assistent das Skript signiert hat
   (Vertrauensmodus Signatur) und das Signaturzertifikat auf den Geräten vertrauenswürdig ist.
4. *Skript in 64-Bit-PowerShell ausführen*: **Ja**.
5. Denselben Gerätegruppen wie SelfX zuweisen, mit einem Zeitplan wie täglich.

Das Ergebnis steht im Paket unter *Gerätestatus*, Spalte *Erkennungsausgabe vor der Wartung*.

**Gut zu wissen.**

- Im Akkubetrieb pausiert die Hintergrundprüfung (`PauseOnBattery`), und mit `Background Enabled="false"` wird der
  Cache nur aktualisiert, wenn jemand SelfX öffnet. Der Cache wird dann älter als zwei Intervalle, und die Zeile
  lautet `SelfX Unavailable | status cache is older than ...` (Exitcode 1).
- Die Datei ist reines ASCII; Intune liest sie deshalb auch mit erzwungener Signaturprüfung als UTF-8.
- Microsoft Learn: [Remediations](https://learn.microsoft.com/intune/device-management/tools/deploy-remediations)
  (Lizenzen, Einstellungen, die Grenze von 2048 Zeichen).

## Inventardatei

Mit `<Inventory Enabled="true" />` in `Health_Config.xml` (oder der Frage im Assistenten) hängt der Dienst nach
jeder vollständigen Prüfung eine Zeile an `%ProgramData%\SelfX\Inventory\SelfX.Inventory.json` an. Standard: aus.

- Format: JSON Lines (ein JSON-Objekt je Zeile), UTF-8 ohne Byte-Order-Mark, festes Schema.
- Rechte: wie der Cache (SYSTEM und Administratoren). Der Dienst schreibt nicht über einen Link.
- Größe: `MaxSizeKB` (64 bis 10240, Standard 1024). Eine größere Datei wird in `SelfX.Inventory.json.old`
  umbenannt; eine ältere `.old` wird gelöscht. Der Name `.old` passt nicht zum Dateimuster des Sammlers, so wird
  keine Zeile doppelt gelesen.
- Windows Server: Es wird nichts geschrieben, solange `TerminalServer_Health` auf `Off` steht (Standard). Mit
  `AdminOnly` wird die Datei geschrieben.
- Die Deinstallation entfernt den Ordner.

**Schemaversion 1** (jedes Feld in jeder Zeile, in dieser Reihenfolge):

| Feld | Typ | Werte |
|---|---|---|
| `SchemaVersion` | int | `1` |
| `TimeGenerated` | datetime | Zeit der Prüfung in UTC, ISO 8601 |
| `Mode` | string | `Client` (Windows 11) oder `TerminalServer` (Windows Server) |
| `Overall` | string | Schlechtester Status aller Zeilen: `OK`, `Unknown`, `Pending`, `Error` |
| `IME`, `Defender`, `Compliance`, `Applications`, `Disk`, `BitLocker`, `PendingReboot`, `Updates`, `Service`, `Custom` | string | Schlechtester Status der Zeilen dieser Art; leer = nicht geprüft |
| `FailedApps` | string | `<App-ID>:<Fehlercode>` (oder `:Stalled`, `:-` ohne gültigen Code), getrennt durch `;`, höchstens 20 |

Beispiel:

```json
{"SchemaVersion":1,"TimeGenerated":"2026-11-28T08:00:00Z","Mode":"Client","Overall":"Error","IME":"OK","Defender":"OK","Compliance":"Pending","Applications":"Error","Disk":"OK","BitLocker":"OK","PendingReboot":"OK","Updates":"Pending","Service":"","Custom":"","FailedApps":"0a1b2c3d-0000-4000-8000-00000000000a:0x87D1041C"}
```

Die Datei enthält keine Namen, keine Detailtexte und keine Benutzernamen. Den Gerätenamen ergänzt der Sammler
(Spalte `Computer`), nicht SelfX.

## Log Analytics mit dem Azure Monitor Agent

Die Schritte folgen Microsoft Learn (geprüft am 28.11.2026). Sie wurden mit SelfX **nicht ausprobiert**; siehe
[Was nicht getestet wurde](#was-nicht-getestet-wurde).

1. **Arbeitsbereich.** Ein Log-Analytics-Arbeitsbereich in der Region der Datensammlungsregel.
2. **Tabelle.** Die benutzerdefinierte Tabelle `SelfXInventory_CL` vor der Regel anlegen. Microsoft Learn nennt
   dafür einen REST-Aufruf; die Spalten sind die des Schemas plus `Computer` und `FilePath`:

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
   - **Windows 11:** der Client-Installer des Azure Monitor Agent (MSI). Das Gerät muss in Microsoft Entra
     eingebunden oder hybrid eingebunden sein. Regeln werden einem *überwachten Objekt* des Mandanten zugeordnet und
     gelten dann für **alle** Windows-Clients des Mandanten mit diesem Agent; eine feinere Zuordnung ist nicht
     möglich. Microsoft beschreibt den Client-Installer als gedacht für ständig verbundene Geräte; für Laptops im
     Akkubetrieb ist er nicht optimiert.
   - **Windows Server:** außerhalb von Azure als Server mit Azure Arc, in Azure als virtuelle Maschine mit der
     Agent-Erweiterung. Die Regel wird den Maschinen direkt zugeordnet.
4. **Datensammlungsregel.** Von `SelfX-Inventory-DCR.json` ausgehen (Ausgabeordner des Assistenten oder
   `tools\Intune`) und die Werte in spitzen Klammern ersetzen: Region, Abonnement, Ressourcengruppe, Arbeitsbereich
   und den Datensammlungsendpunkt (die Beispiele von Microsoft Learn für JSON-Dateien enthalten
   `dataCollectionEndpointId`). Die Datenquelle ist `logFiles` mit `format` `json` und dem genauen Dateimuster
   `C:\ProgramData\SelfX\Inventory\SelfX.Inventory.json`. Im Portal: Datenquelle *Benutzerdefinierte JSON-Protokolle*,
   Tabelle `SelfXInventory_CL`, Transformation `source`.
5. **Zuordnung.** Windows Server: die Regel den Maschinen zuordnen. Windows 11: die Regel dem überwachten Objekt des
   Mandanten zuordnen.
6. **Kontrolle.** Die Tabelle `Heartbeat` zeigt den Agent; nach der nächsten vollständigen Prüfung von SelfX
   (Standard alle 15 Minuten) bekommt die Tabelle `SelfXInventory_CL` eine Zeile je Gerät.

Microsoft Learn:
[JSON-Datei sammeln](https://learn.microsoft.com/azure/azure-monitor/vm/data-collection-log-json),
[DCR-Beispiele](https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-rule-samples#json-logs),
[Azure Monitor Agent auf Windows-Clients](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-windows-client).

## Beispielabfragen (KQL)

Letzter Status je Gerät:

```kusto
SelfXInventory_CL
| summarize arg_max(TimeGenerated, *) by Computer
| project Computer, TimeGenerated, Mode, Overall, IME, Defender, Compliance, Applications, Disk, BitLocker, PendingReboot, Updates, FailedApps
```

Geräte, deren letzter Status ein Fehler ist:

```kusto
SelfXInventory_CL
| where TimeGenerated > ago(1d)
| summarize arg_max(TimeGenerated, *) by Computer
| where Overall == "Error"
```

Fehlgeschlagene Apps nach App-ID und Fehlercode:

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

Geräte ohne Zeile seit zwei Tagen:

```kusto
SelfXInventory_CL
| summarize Last = max(TimeGenerated) by Computer
| where Last < ago(2d)
```

## Was nicht getestet wurde

Mit den Testskripten geprüft (mit Mocks, auf dem Entwicklungs-PC): das Erkennungsskript mit fehlendem, altem,
kaputtem, leerem, zu großem oder fremdem Cache, einem Cache hinter einem Link, die Länge der Zeile und dass kein Name
und kein Detailtext erscheint; die Inventarzeile, die Rotation, Links, `TerminalServer_Health` `Off` und der Schalter in
`Health_Config.xml`; der Assistent (Fragen, Dateien, Anleitung).

**Nicht auf einem Gerät ausprobiert:**

- das Skriptpaket in Intune (Hochladen, Zeitplan, die Spalte der Erkennungsausgabe, die Signaturprüfung mit einem
  signierten Skript),
- der Azure Monitor Agent auf Windows 11 (Client-Installer, überwachtes Objekt) und auf Windows Server (Azure Arc),
- die Datensammlungsregel `SelfX-Inventory-DCR.json`, die benutzerdefinierte Tabelle, die Transformation und die
  Abfragen,
- ob der Agent die Datei nach der Rotation nach `.old` wieder richtig liest,
- ob für JSON-Dateien in Ihrer Umgebung noch ein Datensammlungsendpunkt nötig ist.
