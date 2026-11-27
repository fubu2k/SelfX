# Architektur: Code, Konfiguration und Vertrauen

[English](../Architecture.md) | **Deutsch**

Dieses Dokument beschreibt, wie die Dateien von **SelfX Service** in Klassen eingeteilt sind,
welche Listen sie erfassen, wie ein Gerät entscheidet, ihnen zu vertrauen, und wo die Grenzen
dieses Vertrauens liegen. Es ist für Administratoren und Prüfer geschrieben.

> **Stand.** Abschnitte mit **Heute** beschreiben SelfX Service 3.0.2: Eine Liste,
> `SelfX.Files.json`, erfasst alle installierten Dateien (siehe
> [Installation](Installation.md#die-dateiliste-selfxfilesjson)). Abschnitte mit **Ziel**
> beschreiben die geplante Struktur mit zwei Listen und zwei Vertrauensmodi. Sie wird in
> mehreren Schritten eingeführt; bis dahin gilt das Verhalten von 3.0.2.

## Inhalt

1. [Überblick](#überblick)
2. [Die drei Dateiklassen](#die-drei-dateiklassen)
3. [Zuordnung jeder Datei](#zuordnung-jeder-datei)
4. [Die zwei Listen](#die-zwei-listen)
5. [Vertrauensmodi: Hash und Signatur](#vertrauensmodi-hash-und-signatur)
6. [Der Vertrauensanker](#der-vertrauensanker)
7. [Die Grenze: lokaler Administrator](#die-grenze-lokaler-administrator)
8. [Wer prüft was](#wer-prüft-was)
9. [Dateien mit offener Klasse](#dateien-mit-offener-klasse)
10. [Ordneraufbau](#ordneraufbau)

## Überblick

- Jede Datei des Pakets gehört zu **genau einer Klasse**: *Code*, *Konfiguration* oder
  *eigener Code der Firma*.
- **Code** baut das Projekt, er ist für jede Firma gleich. **Konfiguration** legt der
  Administrator der Firma fest, sie kann sich jederzeit ändern. **Eigener Code der Firma** ist ein
  Skript, das die Firma selbst hinzufügt.
- Zwei Listen erfassen die Dateien: `SelfX.Code.json` (Code) und `SelfX.Config.json`
  (Konfiguration und eigener Code der Firma). Ein neues Logo oder eine neue Support-Nummer ändert
  nur die zweite Liste.
- Zwei Vertrauensmodi bestimmen, wie die Listen belegt werden: **Hash** (kein Zertifikat nötig)
  und **Signatur** (Authenticode, empfohlen, wenn die Firma ein Zertifikat zur Codesignatur hat).
- Der **Vertrauensanker** (welche Signierer erlaubt sind) ist nicht Teil des Pakets. Er kommt aus
  der Intune-Befehlszeile.
- Die Prüfungen schützen vor Unfällen und vor Änderungen durch normale Nutzer. Sie schützen nicht
  vor einem **lokalen Administrator** (siehe
  [Die Grenze](#die-grenze-lokaler-administrator)).

## Die drei Dateiklassen

| Klasse | Inhalt | Geändert von | Ändert sich | Erfasst in |
|---|---|---|---|---|
| **Code** | `SelfXService.exe`, `SelfX.exe`, alle DLLs, alle `*.ps1` des Projekts (`Install.ps1`, `Uninstall.ps1`, `Sources\*.ps1`, `Scripts_to_run`, `HealthChecks`), die mitgelieferten Sprachdateien, die Standardbilder | dem Projekt (Release) | bei einem Programm-Update oder einem .NET-Sicherheitsupdate | `SelfX.Code.json` |
| **Konfiguration** | `Tool_Config.xml`, `Issues_List.xml`, `Health_Config.xml`, `Ticket_Config.xml`, `Network_Test_Config.xml`, `Branding\*`, Text-Überschreibungen | dem Administrator der Firma (Paketassistent) | jederzeit, ohne neues Release | `SelfX.Config.json` |
| **Eigener Code der Firma** | eigene Skripte in `Scripts_to_run` oder `HealthChecks`, die der Katalog oder `Health_Config.xml` nennt | dem Administrator der Firma | selten | `SelfX.Config.json`, geprüft wie Code |

Regeln (**Ziel**):

1. Eine Datei gehört zu genau einer Klasse.
2. Die Zuordnung ist an **einer Stelle** festgelegt (Funktion `Get-SelfXFileClass` in
   `tools\SelfXPackage.Common.ps1`). Paketbau, `Install.ps1`, Tests und der Dienst wenden dieselbe
   Regel an.
3. Eine Datei, die keine Regel kennt, ist ein **Fehler** (fail closed), keine Standardklasse.
4. Konfiguration enthält keinen ausführbaren Code. Sie wählt nur aus, welches gelistete Skript
   läuft. Der Dienst startet ein Skript als SYSTEM nur, wenn `Issues_List.xml`
   (`Context="System"`) oder `Health_Config.xml` es nennt und die Datei gelistet und unverändert
   ist.

Folge: Ein anderes Logo, eine andere Adresse oder ein geänderter Katalog ändert nur
Konfigurationsdateien. Die Code-Liste bleibt byte-identisch, ebenso die AppLocker- und
App-Control-Regeln, die darauf beruhen.

## Zuordnung jeder Datei

Die Tabellen zeigen das Paket **SelfX Service**, wie `tools\New-SelfXIntuneWin.ps1` es heute baut
(Funktion `New-SelfXFileManifest`). Pfade gelten relativ zum Ordner `SelfX Service` des
Repositorys. „Installiert als“ ist der Pfad im Installationsordner (`%ProgramFiles%\SelfX`).

**Heute** listet `SelfX.Files.json`: jede Datei unter `Sources` (89 Dateien), `Uninstall.ps1`, die
DLLs aus `Bin\WinRT` (als `WinRT/<Name>`), `Bin\Audio\SelfXAudio.dll` (als
`Audio/SelfXAudio.dll`) und die Programme `SelfXService.exe` und `SelfX.exe` aus `Bin`. Dateien
mit dem Namen `Test-*.ps1` und der Ordner `Service\Projects` werden vor dem Verpacken aus dem
Zwischenordner entfernt und nicht ausgeliefert.

### Programme und Bibliotheken (gebaut von `tools\Build-SelfXBinaries.ps1`)

| Paketpfad | Installiert als | Klasse |
|---|---|---|
| `Bin\SelfXService.exe` | `SelfXService.exe` | Code |
| `Bin\SelfX.exe` | `SelfX.exe` | Code |
| `Bin\WinRT\*.dll` (`SelfXWinRT.dll` und die Windows-SDK-Projektions-DLLs des Builds) | `WinRT/<Name>` | Code |
| `Bin\Audio\SelfXAudio.dll` | `Audio/SelfXAudio.dll` | Code |

### Ordner `Sources` (unverändert in den Installationsordner kopiert)

| Paketpfad | Klasse |
|---|---|
| `Sources\Branding.ps1`, `CopilotClipboard.ps1`, `CopilotFacts.ps1`, `CopilotPrompt.ps1`, `HealthStatus.ps1`, `Localization.ps1`, `SelfXAudio.ps1`, `SelfXDefender.ps1`, `SelfXDeviceSecurity.ps1`, `SelfXLog.ps1`, `SelfXNetwork.ps1`, `SelfXOffice.ps1`, `SelfXServiceClient.ps1`, `SelfXWinRT.ps1`, `SelfXWindows.ps1`, `SelfX_Tray.ps1`, `Self_X.ps1`, `SupportLinks.ps1`, `SupportReport.ps1`, `SystemInfo.ps1`, `TicketMail.ps1`, `TicketSend.ps1` (22 Dateien) | Code |
| `Sources\Tool_Config.xml` | Konfiguration |
| `Sources\Issues_List.xml` (Aktionskatalog) | Konfiguration |
| `Sources\Health_Config.xml` | Konfiguration |
| `Sources\Ticket_Config.xml` | Konfiguration |
| `Sources\Network_Test_Config.xml` | Konfiguration |
| `Sources\Branding\company_logo.png` (Platzhalter, der Assistent ersetzt ihn durch das Firmenlogo) | Konfiguration |
| `Sources\Languages\ar.xml`, `bn.xml`, `de.xml`, `en.xml`, `es.xml`, `fa.xml`, `fr.xml`, `hi.xml`, `id.xml`, `it.xml`, `ja.xml`, `ko.xml`, `nl.xml`, `pl.xml`, `pt.xml`, `ru.xml`, `sw.xml`, `th.xml`, `tr.xml`, `uk.xml`, `ur.xml`, `vi.xml`, `zh-Hans.xml`, `zh-Hant.xml` (24 Dateien) | Code |
| `Sources\HealthChecks\Check-Compliance.ps1` | Code. Die `$Require`-Einstellungen wandern in die Konfiguration (**Ziel**); bis dahin passt eine bearbeitete Kopie nicht mehr zur Code-Liste |
| `Sources\Repair.ico`, `Sources\icon_systray.ico`, `Sources\logo.png` | Code (Standardbilder). Firmenbilder gehören nach `Sources\Branding\`; ein Standardbild an Ort und Stelle zu überschreiben ist nicht vorgesehen |
| `Sources\Scripts_to_run\Collect-DeviceLogs.ps1`, `SelfX_Apps_RetryInstall.ps1`, `SelfX_Audio_Restore.ps1`, `SelfX_Browser_ClearChromeCache.ps1`, `SelfX_Browser_ClearEdgeCache.ps1`, `SelfX_Browser_ClearFirefoxCache.ps1`, `SelfX_Citrix_RestartWorkspace.ps1`, `SelfX_Defender_QuickScan.ps1`, `SelfX_Defender_UpdateSignature.ps1`, `SelfX_Device_AirePlaneMode.ps1`, `SelfX_Device_BringWindowsBack.ps1`, `SelfX_Device_ClearCache.ps1`, `SelfX_Device_CollectLogs.ps1`, `SelfX_Device_DeviceSlow.ps1`, `SelfX_Device_GpUpdate.ps1`, `SelfX_Device_Restart.ps1`, `SelfX_Device_SyncTime.ps1`, `SelfX_Excel_NewInstance.ps1`, `SelfX_Excel_Reboot.ps1`, `SelfX_Intune_RestartService.ps1`, `SelfX_Office_ResetLicence.ps1`, `SelfX_OneDrive_CHKDSK.ps1`, `SelfX_OneDrive_Reboot.ps1`, `SelfX_OneDrive_Reset.ps1`, `SelfX_OneDrive_Run.ps1`, `SelfX_Outlook_CleanAutoComplete.ps1`, `SelfX_Outlook_Reboot.ps1`, `SelfX_Outlook_TeamsAddIn.ps1`, `SelfX_Poste_WSReset.ps1`, `SelfX_Teams_Reboot.ps1`, `SelfX_Teams_ResetCache.ps1`, `SelfX_Updates_Install.ps1`, `SelfX_Word_Reboot.ps1` (33 Dateien) | Code |

Die 89 Dateien unter `Sources` ergeben sich aus den Zeilen oben: 22 + 5 + 1 + 24 + 1 + 3 + 33.

### Weitere Dateien des Pakets

| Paketpfad | Installiert | Klasse |
|---|---|---|
| `Uninstall.ps1` | ja, gelistet | Code |
| `Install.ps1` | nein | Code, nicht gelistet, **offen** (Punkt 1) |
| `Detection.ps1` | nein (wird getrennt nach Intune hochgeladen) | Code-Vorlage, nicht gelistet, **offen** (Punkt 1) |
| `README.md`, `README.en.md` | nein | kein Code, nicht gelistet, **offen** (Punkt 1) |
| `Service\SelfXService.cs`, `SelfXLauncher.cs`, `SelfXSessionStarter.cs`, `SelfXWinRT.cs`, `SelfXAudio.cs` | nein | Code (Quelltext der Programme), nicht gelistet, **offen** (Punkt 1) |
| `Bin\SelfXSessionStarter.dll` | nein (wird nur von `Install.ps1` geladen) | Code, nicht gelistet, **offen** (Punkt 1) |
| `Bin\SelfX.Binaries.json` | nein | Bauprotokoll der Programme, nicht gelistet, **offen** (Punkt 1) |
| `SelfX.Files.json` | ja (beim Bau geschrieben) | die Liste selbst; im Ziel durch die zwei Listen ersetzt |

## Die zwei Listen

### Heute: `SelfX.Files.json`

Ein JSON-Objekt mit `ManifestVersion` (1), `ToolVersion`, `BuiltUtc` und `Files`. `Files`
ordnet dem relativen Namen jeder Datei (Schrägstriche) ihren SHA256 zu. Ein Name besteht aus
Buchstaben, Ziffern, `_`, Leerzeichen, `.`, `(`, `)` und `-`, und jeder Abschnitt beginnt mit
einem Buchstaben, einer Ziffer oder `_`; ein Abschnitt ist nie `.` oder `..`. Der Paketbau
schreibt die Liste, `Install.ps1` kopiert sie in den Installationsordner, und ihr Digest steckt
in der `Detection.ps1`, die nach Intune hochgeladen wird.

**Digest einer Liste:** SHA256 über die Zeilen `<Name>=<SHA256 in Großbuchstaben>`, nach Namen
sortiert (ordinal), mit LF verbunden, UTF-8 ohne BOM. `Detection.ps1` und der Bau verwenden
dieselbe Funktion.

### Ziel: `SelfX.Code.json` und `SelfX.Config.json`

| | `SelfX.Code.json` | `SelfX.Config.json` |
|---|---|---|
| Listet | alle Dateien der Klasse *Code* | alle Dateien der Klassen *Konfiguration* und *eigener Code der Firma* |
| Felder | `ManifestVersion`, `ToolVersion`, `BuiltUtc`, `Files` | `ManifestVersion`, `ConfigRevision` (UTC-Zeit des Assistentenlaufs), `MinCodeVersion` (nur in einem Paket, das allein die Konfiguration ersetzt), `Files` |
| `Files` | relativer Name → SHA256, gleiche Namensregeln wie heute | gleich |
| Geschrieben von | dem Release-Build (GitHub Actions); für jede Firma identisch | dem Paketassistenten, automatisch; niemand bearbeitet sie von Hand |
| Ändert sich, wenn | sich der Code ändert | sich die Konfiguration ändert |
| Modus Signatur | vom Assistenten neu geschrieben, nachdem die Firma die Code-Dateien signiert hat | zusätzlich durch den signierten Katalog `SelfX.Config.cat` abgedeckt |

- Jede Datei steht in **genau einer** Liste. Eine Datei in beiden Listen oder in keiner ist ein
  Fehler.
- `Install.ps1` enthält keinen Hash. Es liest beide Listen, prüft das Paket, bevor es etwas
  ändert, und prüft nach dem Kopieren den installierten Ordner.
- Der Dienst liest beide Listen und prüft sie vor jedem Start.
- `Detection.ps1` bekommt vom Assistenten zwei Werte: die Code-Version und den Digest der
  Konfigurationsliste. Ein neues Logo ändert nur den zweiten Wert.
- `SelfX.Binaries.json` bleibt. Sie bindet die Programme an die C#-Quelltexte, aus denen sie
  gebaut wurden.
- Die Version des Codes ist `ToolVersion` in `SelfX.Code.json`. **Heute** ist es `Tool_Version`
  in `Tool_Config.xml`, einer Konfigurationsdatei; `Detection.ps1`, der Release-Workflow und der
  Paketbau lesen sie dort.

## Vertrauensmodi: Hash und Signatur

Der Assistent lässt den Administrator den Modus wählen (**Ziel**).

| | Modus **Hash** (kein Zertifikat) | Modus **Signatur** (empfohlen mit Zertifikat) |
|---|---|---|
| Code | `SelfX.Code.json` aus dem Release, unverändert | Authenticode-Signatur in jeder `.exe`, `.dll` und `.ps1`; `Install.ps1` und der Dienst prüfen Signatur und Signierer |
| Konfiguration | `SelfX.Config.json`, vom Assistenten geschrieben | zusätzlich der signierte Katalog `SelfX.Config.cat` (XML- und PNG-Dateien können keine eingebettete Signatur tragen) |
| AppLocker / App Control | Hashregeln, vom Assistenten erzeugt | **eine** Herausgeberregel bzw. Signer-Regel; sie bleibt für alle Versionen gleich |
| Aufwand je Update | automatisch, aber neue Regeln müssen verteilt werden | keiner |
| Belegt | das Paket wurde nach dem Bau nicht verändert | das Paket stammt von einem erlaubten Signierer |

Ein Hash belegt die Unversehrtheit, nicht die Herkunft: Wer die Liste schreiben kann, kann
passende Hashes schreiben. Eine Signatur bindet die Dateien an einen Signierer, den das Gerät
akzeptiert.

Warum ein Katalog (`.cat`) und keine eigene Signaturdatei: `New-FileCatalog` und
`Test-FileCatalog` gibt es in Windows PowerShell 5.1 und in PowerShell 7, ein Katalog lässt sich
mit jedem Authenticode-Werkzeug signieren (Zertifikatsspeicher, PFX-Datei, Smartcard oder HSM,
Azure Artifact Signing), und Windows prüft ihn mit derselben Funktion (`WinVerifyTrust`) wie
Programme.

## Der Vertrauensanker

Der Anker legt fest, welche Signierer ein Gerät akzeptiert (**Ziel**, Modus Signatur).

- Er stammt **nicht** aus dem Paket, denn ein Paket mit eigenem Anker belegt nur sich selbst. Er
  kommt aus der Intune-Befehlszeile: `Install.ps1 -TrustedSigner <Fingerabdruck>[,<Fingerabdruck>]`
  (SHA1-Fingerabdrücke, 40 Hexadezimalzeichen; alles andere bricht die Installation ab). Der
  Assistent schreibt die Zeile zum Kopieren.
- `Install.ps1` speichert den Anker unter `HKLM\SOFTWARE\SelfX\Trust`: `Mode` (`Hash` oder
  `Signature`) und `Signers` (`REG_MULTI_SZ`). SYSTEM (`S-1-5-18`) und Administratoren
  (`S-1-5-32-544`) haben Vollzugriff, Benutzer dürfen nur lesen. Der Dienst liest den Anker von
  dort und startet nichts, wenn Nicht-Administratoren den Schlüssel beschreiben können.
- Es ist eine **Liste** von Signierern, kein einzelner Fingerabdruck: Ein neues Zertifikat kann vor
  dem Wechsel schon erlaubt werden, sodass eine Erneuerung den Rollout nicht stoppt.
- Eine Signatur zählt nur, wenn ihr Status `Valid` ist (die Zertifikatskette ist auf dem Gerät
  vertrauenswürdig) **und** der Fingerabdruck des Signierers in der Liste steht. „Irgendeine
  gültige Signatur“ genügt nicht.
- Ohne `-TrustedSigner` gilt der Modus Hash wie heute. Der Wechsel von Signatur zurück zu Hash bei
  einem Update braucht den ausdrücklichen Schalter `-AllowHashMode`.
- Ein Zeitstempel (RFC 3161) hält eine Signatur nach Ablauf des Zertifikats gültig. Der Assistent
  fragt nach einem Zeitstempeldienst; abgeschottete Netze können einen internen verwenden.
- Eine ungültige Signatur oder ein Signierer, der nicht in der Liste steht, ist ein harter Abbruch
  **vor** jeder Änderung am Gerät. Das gilt auch bei Autopilot.

## Die Grenze: lokaler Administrator

Eine Prüfung durch den Dienst schützt **nicht** vor einem lokalen Administrator. Ein Administrator
kann `SelfXService.exe` austauschen oder den Anker in `HKLM` ändern; er hat ohnehin
SYSTEM-Rechte.

Wovor die Prüfungen schützen:

- falsche Ordnerrechte, die ein normaler Nutzer ausnutzen könnte,
- Pakete, die auf dem Weg zum Gerät verändert wurden,
- vertauschte oder veraltete Versionen,
- Bedienfehler (defektes oder halbes Update).

Schutz vor einem Administrator bietet nur **App Control for Business (WDAC)** im Enforce-Modus.
Genau dort hilft die Signatur am meisten: Eine Signer-Regel ersetzt die Hashregeln jeder Version.
Siehe [Installation](Installation.md#app-control-for-business-wdac).

## Wer prüft was

| Komponente | Läuft als | Heute | Ziel |
|---|---|---|---|
| `Install.ps1` | SYSTEM, von Intune gestartet, Windows PowerShell 5.1 | vergleicht das Paket vor dem Kopieren und den installierten Ordner nach dem Kopieren mit `SelfX.Files.json` | dasselbe mit beiden Listen; im Modus Signatur zusätzlich die Signaturen und der Signierer |
| `SelfXService.exe` | SYSTEM | vergleicht vor jedem Start den installierten Ordner mit `SelfX.Files.json`; keine Datei ohne Eintrag und keine Verknüpfung darf im Weg sein (Ereignis 4005) | dasselbe mit beiden Listen; im Modus Signatur zusätzlich die Signatur der Skripte und des Katalogs |
| `Detection.ps1` | Intune, Windows PowerShell 5.1 | Version und Digest von `SelfX.Files.json` | Code-Version und Konfigurations-Digest, getrennt |
| SelfX-Fenster, Statussymbol | der angemeldete Nutzer | nur lesend | nur lesend |

Nutzer können dem Dienst weder Pfad noch Befehl, Argument oder Code übergeben. Der Dienst startet
nur Skripte, die der installierte Katalog mit `Context="System"` führt.

`Tool_Config.xml` enthält zwei Einstellungen, die diese Prüfungen beeinflussen: `Service_FileCheck`
(`Enforce` oder `Audit`, vom Dienst gelesen) und `Service_Privileges` (von `Install.ps1`
gelesen). Der Dienst akzeptiert `Audit` nur, wenn die Dateiliste intakt ist, `Tool_Config.xml`
nicht zu den Abweichungen gehört und die Prüfung nicht an ihrer Grenze von 20 Problemen
abgebrochen wurde.

## Dateien mit offener Klasse

Die Zuordnung oben wurde gegen die Dateien des Repositorys und gegen `New-SelfXFileManifest`
geprüft. Diese Punkte lassen sich ohne eine weitere Regel nicht klären:

1. **Dateien außerhalb des installierten Satzes:** `Install.ps1` prüft die Listen, kann also nicht
   in einer Liste stehen, die es prüft. `Detection.ps1` ist eine Vorlage: Der Bau ersetzt den
   Platzhalter `__SELFX_FILES_HASH__`, sodass jedes Paket eine eigene Kopie hat. `README*.md`,
   `Service\*.cs`, `Bin\SelfXSessionStarter.dll` und `Bin\SelfX.Binaries.json` werden
   ausgeliefert, aber nicht installiert und stehen heute nicht in `SelfX.Files.json`.
2. **Firmendateien in Projektordnern:** Die Dokumentation beschreibt, eigene Skripte in
   `Scripts_to_run` und `HealthChecks` abzulegen und eine Sprache hinzuzufügen, indem man `en.xml`
   nach `Languages\<Kultur>.xml` kopiert. Eine Regel, die eine Projektdatei von einer Firmendatei
   im selben Ordner unterscheidet, ist noch nicht festgelegt.
3. **`Bin\WinRT\*.dll`:** Die Windows-SDK-Projektions-DLLs neben `SelfXWinRT.dll` sind die Ausgabe
   von `dotnet publish`. Der Ordner `Bin` gehört nicht zum Repository, daher lassen sich ihre
   Namen hier nicht aufführen.

## Ordneraufbau

**Ziel**, zweite Stufe. Die erste Stufe trennt die Dateien logisch über die zwei Listen; die
zweite Stufe trennt sie physisch.

```
Paket                                   Gerät (%ProgramFiles%\SelfX)
+- Install.ps1  Uninstall.ps1           +- Uninstall.ps1  SelfXService.exe  SelfX.exe
+- SelfX.Code.json                      +- SelfX.Code.json
+- App\    (Code: Bin, Sources, ...)    +- App\      (nur Code)
+- Config\                              +- Config\   (nur Konfiguration)
    +- *.xml  Branding\  Texts\             +- SelfX.Config.json [+ .cat]
    +- SelfX.Config.json [+ .cat]       (Rechte wie heute: Benutzer nur lesen und ausführen)
```

Der Dienst lädt den Katalog und `Health_Config.xml` nur aus `Config\` und Skripte nur aus `App\`.
Ein Skript unter `Config\` (eigener Code der Firma) startet nur, wenn es in `SelfX.Config.json`
steht und der Katalog es nennt. Eine Installation im alten Aufbau wird durch ein Update
vollständig ersetzt, es bleibt kein Mischzustand.
