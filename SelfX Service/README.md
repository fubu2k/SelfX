# SelfX Service

[English](README.en.md) | **Deutsch**

SelfX Service wird für das ganze Gerät installiert und arbeitet ohne
Netzwerkverbindung. Aktuelle Version: **2.8.0** (siehe das
[Änderungsprotokoll](../CHANGELOG.md)).

- Eine moderne Oberfläche mit änderbarer Größe für Nutzer ohne technisches Wissen
  (2.5.0): Navigationsleiste mit **Probleme lösen**, **Gerätestatus** und
  **Systeminformationen**, Symbolschaltflächen mit erklärenden Kurzinfos, dunkles
  und helles Design, Hilfe-Dialog mit den Support-Kontakten (Zeiten, Telefon,
  E-Mail, Teams-Chat, Website / Ticketsystem). Siehe
  [Benutzeroberfläche](../docs/Configuration.md#benutzeroberfläche).
- Hintergrundprüfungen (2.5.0): Der Dienst prüft den Gerätestatus regelmäßig
  (standardmäßig alle 15 Minuten, pausiert im Akkubetrieb, verschoben bei hoher
  Prozessorlast) und behält das Ergebnis, sodass SelfX Status und
  Systeminformationen sofort anzeigt. Siehe
  [Hintergrundprüfungen](../docs/Configuration.md#hintergrundprüfungen).
- Statussymbol (2.5.0): ein Statussymbol neben der Uhr für jeden Nutzer (grün,
  gelb, rot) mit einer Benachrichtigung, wenn ein Problem gefunden wird, zum
  Beispiel wenig Speicherplatz. Jeder Nutzer kann es ausblenden. Siehe
  [Statussymbol](../docs/Configuration.md#statussymbol).
- **Alle Probleme beheben** und Zeitzone des Nutzers (2.5.3): Eine Schaltfläche auf
  der Seite Gerätestatus führt alle vorbereiteten Reparaturen nacheinander aus;
  alle Zeiten erscheinen in der aktuellen Zeitzone des Nutzers. SelfX und das
  Statussymbol starten ohne Konsolenfenster (`SelfX.exe`).
- Ein Aktionskatalog (`Sources\Issues_List.xml`). Jede Aktion hat einen `Context`:
  - `User`-Aktionen laufen in der Sitzung des angemeldeten Nutzers.
  - `System`-Aktionen gehen an den lokalen Windows-Dienst **SelfXService**, der sie
    mit SYSTEM-Rechten ausführt. In der Liste sind diese Aktionen mit einem
    Schild-Symbol gekennzeichnet.
- Es sind keine Downloads, keine Remote-Konfiguration und kein zentraler Server
  nötig. Katalog, Skripte und Dienst liegen alle auf dem Gerät. Einige einzelne
  Aktionen brauchen das Netzwerk, um zu wirken, zum Beispiel die Intune-
  Synchronisierung.
- Branding: In `Tool_Config.xml` können Sie ein Firmenlogo, ein Symbol und die
  Farben festlegen. Siehe [Konfiguration](../docs/Configuration.md#branding).
- Mehrsprachige Oberfläche: Deutsch ist die Basissprache (2.6.12); steht
  `Tool_Language` auf `Auto`, nutzt SelfX die Anzeigesprache von Windows und
  Deutsch, wenn sie nicht verfügbar ist. Texte, die in einer Sprache fehlen,
  erscheinen auf Englisch. Nutzer können in den Einstellungen eine andere Sprache
  wählen (pro Nutzer gespeichert, 2.5.9). 24 Sprachen sind in `Sources\Languages`
  enthalten. Für eine weitere Sprache genügt eine XML-Datei. Siehe
  [Konfiguration](../docs/Configuration.md#sprachen).
- Jedes Skript beginnt mit einer Beschreibung und einem Versionsverlauf.
- Statuskarten mit einer vom Administrator konfigurierten Reparatur bieten eine
  lokalisierte Schaltfläche **Beheben**. Reparaturen laufen nach Bestätigung über
  den lokalen Dienst und prüfen danach den Status erneut. Jede Karte hat eine
  Schaltfläche **Erneut prüfen**, die nur diesen Status erneut prüft. Standardmäßig
  bieten Defender (immer) und Compliance (wenn nicht in Ordnung) ein Update der
  Signaturen (`Update-MpSignature`); die Zeile Defender zeigt Signaturversion und
  letzte Aktualisierung. Siehe
  [Reparaturen der Gesundheitsprüfung](../docs/Configuration.md#reparaturen).
- Lokale Gesundheitsergebnisse auf der Seite Gerätestatus: IME, Defender,
  Speicherplatz, BitLocker, ausstehender Neustart, zu installierende Updates
  (Offline-Cache von Windows Update), eine nach bestem Wissen zwischengespeicherte
  App-Zusammenfassung mit Ausnahmen, konfigurierbare Dienste und Skript-Prüfungen.
  Die Cloud-Compliance wird offline nicht abgeleitet. Siehe
  [Gesundheitsstatus](../docs/Configuration.md#gerätestatus).
- **Protokolle an den Support senden** (2.4.0): Die Aktion *Geräteprotokolle an den
  Support senden* und eine Schaltfläche in den Systeminformationen führen
  `Collect-DeviceLogs.ps1` mit Administratorrechten über den Dienst aus. Danach
  öffnen sie eine neue E-Mail (Outlook) an `Support_Mail` mit dem Bericht im
  Anhang; der Nutzer beschreibt das Problem und sendet sie ab. Siehe
  [Geräteprotokolle für den Support](../docs/Configuration.md#geräteprotokolle-für-den-support).
- Protokollierung und Reparaturen (2.6.0): Jedes Skript protokolliert nach
  `%ProgramData%\SelfX\Logs` (Nutzer nach `Logs\Users\<SID>`), alte Protokolle
  werden nach `Log_Retention_Days` gelöscht (Standard 90). **Jetzt neu starten**
  bei *Neustart ausstehend* (mit Neustart-Warnung), **Erneut versuchen** für
  fehlgeschlagene Unternehmens-Apps, und die Update-Reparatur installiert die
  ausstehenden Windows-Updates (2.6.3). Alle Aktionsskripte wurden geprüft und
  korrigiert (zum Beispiel Word, Teams, OneDrive und die Datenträgerprüfung).
  Siehe
  [Protokollierung](../docs/Configuration.md#protokolle-und-aufbewahrung)
  und [Reparaturen der Gesundheitsprüfung](../docs/Configuration.md#reparaturen).

## Aufbau des Pakets

| Pfad | Inhalt |
|---|---|
| `Install.ps1` | Installer für das ganze Gerät. Als Administrator ausführen. |
| `Uninstall.ps1` | Schließt offene SelfX-Fenster und Statussymbole und entfernt dann den Dienst, die Dateien, die Verknüpfungen und den Eintrag unter Apps & Features. |
| `Detection.ps1` | Erkennungsskript für Intune oder SCCM. `$ExpectedVersion` bei jedem Release anpassen. |
| `Test-CollectorOutput.ps1` | Löst die sichere Erstellung der Berichtsdatei aus `Collect-DeviceLogs.ps1` heraus und testet sie in einem temporären Ordner (vorab angelegte Datei, Verknüpfung, Hardlink, fremder Besitzer, Rechte des Standardberichts). Es wird nichts gesammelt (2.8.0). |
| `Test-InstallBinaries.ps1` | Löst die Prüfung der vorgebauten Programme aus `Install.ps1` heraus und testet sie gegen ein gefälschtes Paket (fehlender `Bin`-Ordner, fehlende oder geänderte Dateien, geänderte Quellen, defektes oder altes Manifest). Es wird nichts gebaut oder installiert (2.6.11, ab 2.7.0 Manifestformat 2). |
| `Test-LanguageFiles.ps1` | Prüft die Sprachdateien gegen `en.xml` und den Katalog. Vor dem Bau des Pakets ausführen. |
| `Test-HealthStatus.ps1` | Isolierte Tests der Gesundheitsprüfung; Systemdaten und die Ausführung von Erweiterungen sind durch Mocks ersetzt. |
| `Test-DeviceLogs.ps1` | Isolierte Tests der Funktion Geräteprotokolle (Wrapper, E-Mail-Helfer, Katalog, GUI-Schritt); Collector, ACLs, Outlook und Prozesse sind durch Mocks ersetzt. |
| `Test-Catalog.ps1` | Statische Sicherheitsprüfung des Aktionskatalogs, von `Health_Config.xml` und der Skripte, die als SYSTEM laufen (reine Dateinamen, ein Kontext pro Skript, keine Pflichtparameter, Kontext im Kopf, Zeitlimits der Reparaturen). Es wird nichts ausgeführt; vor jedem Release ausführen (2.6.10). |
| `Test-Uninstall.ps1` | Löst die Löschfunktion aus `Uninstall.ps1` heraus und prüft in einem temporären Ordner, dass Junctions entfernt und nie verfolgt werden (2.6.10). `Uninstall.ps1` selbst wird nicht ausgeführt. |
| `Test-ServicePipe.ps1` | Kompiliert den Dienst im Speicher und startet nur seinen Pipe-Listener unter einem Test-Pipe-Namen: prüft die Lesefrist, langsame Sender, zu große Anfragen und das Verbindungslimit pro Nutzer (2.6.11). Es wird nichts installiert und keine Aktion ausgeführt; keine Administratorrechte nötig. |
| `Test-UI.ps1` | Isolierte Tests der Benutzeroberfläche (XAML, Design, Texte), der Benachrichtigungen des Statussymbols und des Informations-Caches; es wird kein Fenster angezeigt. |
| `Test-Scripts.ps1` | Führt jedes Aktions- und Reparaturskript in einer temporären Sandbox mit Mocks für die Befehle aus und prüft Ergebnis und Protokoll (2.6.0); auf dem Gerät wird nichts verändert. |
| `Sources\SelfXLog.ps1` | Gemeinsame Protokollierung aller Skripte nach `%ProgramData%\SelfX\Logs` und die nutzerseitige Bereinigung der Protokolle (2.6.0). |
| `Sources\Scripts_to_run\SelfX_Device_Restart.ps1`, `SelfX_Apps_RetryInstall.ps1`, `SelfX_Updates_Install.ps1` | Reparaturen der Seite Gerätestatus: Neustart nach Bestätigung, fehlgeschlagene App-Installationen wiederholen, Windows-Updates über den Windows-Update-Orchestrator (Windows 11 24H2+, wie „Nach Updates suchen“ in den Einstellungen) und den Windows Update Agent installieren (2.6.0 / 2.6.3 / 2.6.9). |
| `Sources\SelfX_Tray.ps1` | Statussymbol im Infobereich (beim Anmelden über den HKLM-Run-Eintrag `SelfXTray` gestartet, und direkt nach der Installation für angemeldete Nutzer). |
| `Sources\Scripts_to_run\Collect-DeviceLogs.ps1`, `Sources\Scripts_to_run\SelfX_Device_CollectLogs.ps1`, `Sources\SupportReport.ps1` | Geräteprotokolle: nur lesender Collector, System-Wrapper und der E-Mail-Helfer der Oberfläche. |
| `Sources\HealthStatus.ps1`, `Sources\Health_Config.xml` | Collector auf Dienstseite und vom Administrator gesteuerte Gesundheitseinstellungen. Optionale Skripte kommen nach `Sources\HealthChecks`. |
| `Service\SelfXService.cs` | Quelltext des Windows-Dienstes. Wird einmal mit `tools\Build-SelfXBinaries.ps1` als .NET-10-Programm gebaut (ab 2.7.0, siehe [Installation](../docs/Installation.md#programme-bauen-selfx-service-ab-270)). |
| `Service\SelfXLauncher.cs` | Quelltext von `SelfX.exe` (2.5.3), dem Starter ohne Konsolenfenster, den die Verknüpfungen und der Autostart des Statussymbols verwenden. Wird wie der Dienst als .NET-10-Programm gebaut (ab 2.7.0). |
| `Service\SelfXSessionStarter.cs` | Von `Install.ps1` verwendet (2.5.8; ab 2.7.0 als `SelfXSessionStarter.dll` aus `Bin`, netstandard2.0): startet das Statussymbol direkt nach der Installation in den Sitzungen der angemeldeten Nutzer, mit deren normalen Rechten. |
| `Bin\` (Pflicht, nicht in Git) | Gebaute `SelfXService.exe`, `SelfX.exe`, `SelfXSessionStarter.dll` und das Manifest `SelfX.Binaries.json` aus `tools\Build-SelfXBinaries.ps1`. `Install.ps1` prüft die Dateien vor allem anderen und installiert sie; ohne `Bin` bricht die Installation ab (F9, ab 2.7.0 Pflicht). |
| `Service\Projects\` | .NET-10-Projektdateien (Dienst, Starter, Session-Starter) und die NuGet-Lock-Datei. Nur für den Build-Rechner; das Intune-Paket enthält sie nicht (2.7.0). |
| `Sources\` | Oberfläche (`Self_X.ps1`, reines WPF ohne zusätzliche Assemblies), Dienst-Client (`SelfXServiceClient.ps1`), Branding und Designs (`Branding.ps1`), Sprachen (`Localization.ps1`, `Languages\`), Katalog, Konfiguration und `Scripts_to_run`. |

## Funktionsweise

```text
Nutzer ──► Self_X.ps1 (Nutzersitzung)
              │  Nutzeraktion ──► pwsh.exe -File Scripts_to_run\<Skript>.ps1   (Nutzerrechte)
              │  Systemaktion
              ▼
           Named Pipe \\.\pipe\SelfX.Service  (nur lokal)
              ▼
           SelfXService (LocalSystem) ──► prüft den Katalog ──► pwsh.exe -File <Skript>.ps1 (SYSTEM)
```

Der Dienst akzeptiert `PING` zur Erreichbarkeit, `HEALTH [<Id> [<Base64-Name>]]` für
den festen lokalen Status-Collector (optional eine validierte Prüfung), `STATUS`
für das zwischengespeicherte Ergebnis der Hintergrundprüfungen (antwortet sofort,
führt nichts aus) und `RUN <Skript>.ps1` für Reparaturen. Eine Reparatur wird nur
angenommen, wenn

- der Skriptname ein reiner Dateiname ohne Pfad ist,
- der installierte `Issues_List.xml` eine Aktion mit diesem Skript und
  `<Context>System</Context>` enthält,
- die Datei in `%ProgramFiles%\SelfX\Scripts_to_run` existiert.

Nutzer können weder Parameter noch Skriptinhalt oder Pfade senden. Es läuft immer
nur eine Systemaktion, andere Anfragen erhalten die Antwort *busy*. Jede Aktion wird
nach ihrer `TimeoutSeconds` gestoppt: Standard ist 900, Maximum 7200. Der Dienst
übergibt die SID des anfragenden Nutzers (aus dem Pipe-Client-Token) in
`SELFX_CALLER_SID` an das Skript, sodass ein Skript Ergebnisse nur an diesen Nutzer
übergeben kann, zum Beispiel der Bericht mit den Geräteprotokollen.

## Sicherheitsmodell

- `%ProgramFiles%\SelfX` ist nur für SYSTEM und Administratoren schreibbar, Nutzer
  erhalten Lese- und Ausführungsrechte. Die Skripte, die als SYSTEM laufen, können
  Nutzer deshalb nicht ändern.
- Die Pipe verweigert den Netzwerkzugriff, daher können sich nur lokale,
  authentifizierte Nutzer verbinden.
- Bevor eine Anfrage gesendet wird, prüft der Client, dass der Prozess hinter der
  Pipe der laufende `SelfXService` ist (Prozess-ID des Pipe-Servers verglichen mit
  der Prozess-ID aus der Dienststeuerung, 2.6.10). Ist der Dienst gestoppt, wird ein
  Nutzerprozess abgewiesen, der den Pipe-Namen angelegt hat. Kann die Prüfung selbst
  nicht laufen, wird die Anfrage trotzdem gesendet. Im Konsolenmodus des Dienstes
  zur Fehlersuche weist die Prüfung die Pipe ab.
- Alle Anfragen und die Ausgabe der Skripte werden zusammen mit dem anfragenden
  Nutzer nach `%ProgramData%\SelfX\Logs\SelfXService.log` protokolliert; jedes
  Skript schreibt außerdem sein eigenes Protokoll (2.6.0). Nur SYSTEM und
  Administratoren können die Protokolle lesen; Nutzer können nur ihren eigenen Ordner
  unter `Logs\Users` lesen.
- Nutzer können in ihrem eigenen Ordner unter `Logs\Users` schreiben, deshalb liest
  SYSTEM ihn nie (2.6.10): Der Bericht mit den Geräteprotokollen enthält nur die
  Geräteprotokolle aus `%ProgramData%\SelfX\Logs`. Das SelfX-Fenster fügt die
  eigenen Nutzerprotokolle mit den Rechten des Nutzers seiner Kopie des Berichts
  hinzu.
- Geräte mit mehreren Nutzern (2.6.10): Der Bericht mit den Geräteprotokollen
  enthält nur die eigenen Daten des anfragenden Nutzers. Nur ein Administrator mit
  erhöhten Rechten (vom Dienst gelesenes Token, `SELFX_CALLER_ADMIN=1`) erhält den
  vollständigen Bericht. Siehe [Konfiguration](../docs/Configuration.md).
- Gesperrte Aktionen auf Geräten mit mehreren Nutzern (2.6.10): Bei Aktionen mit
  `OtherSessions=Block` (Neustart, Windows-Updates, Datenträgerprüfung, Neustart der
  Netzwerkadapter und des Intune-Dienstes) erhält ein normaler Nutzer einen Hinweis
  statt der Aktion, solange ein anderer Nutzer eine aktive Sitzung hat.
  Administratoren mit erhöhten Rechten sind nicht eingeschränkt. Lassen sich die
  Sitzungen nicht lesen, wird die Aktion blockiert.
- Pipe-Limits (2.6.10): Eine Verbindung muss ihre Anfrage innerhalb von 5 Sekunden
  senden und die Antwort lesen, sonst schließt der Dienst sie. Es sind höchstens 64
  Verbindungen gleichzeitig offen (8 pro Nutzer). Nach einer Prüfung muss derselbe
  Nutzer 3 Sekunden auf die nächste warten, nach einer Aktion 15 Sekunden, bis
  dieselbe Aktion erneut gestartet werden kann; der Dienst antwortet dann *busy*.
  Das verhindert, dass ein Nutzer die Verbindungen oder den Ausführungsplatz aller
  anderen Nutzer aufbraucht. Seit 2.6.11 sind die 5 Sekunden eine Frist für die
  ganze Anfrage (langsames Senden verlängert sie nicht), die Pipe nutzt
  überlappende Ein-/Ausgabe, damit die Frist ein hängendes Lesen oder Schreiben
  zuverlässig beendet, und das Limit von 8 Verbindungen pro Nutzer gilt beim
  Annehmen der Verbindung, bevor etwas gelesen wird. Nutzer ist der Besitzer des
  Client-Prozesses, wie Windows ihn meldet; Verbindungen, deren Besitzer sich nicht
  lesen lässt, teilen sich ein Limit von 8. `Test-ServicePipe.ps1` prüft diese
  Limits mit dem echten Dienstcode unter einem Test-Pipe-Namen.
- Programme (ab 2.7.0): `SelfXService.exe` und `SelfX.exe` sind .NET-10-Programme,
  die einmal auf einem Build-Rechner gebaut werden (Ordner `Bin`). Die
  Installation prüft sie vor jeder Änderung gegen das SHA256-Manifest; sie
  werden mit AppLocker-Hashregeln zugelassen. Auf dem Gerät wird nichts
  kompiliert. Siehe
  [Installation](../docs/Installation.md#programme-bauen-selfx-service-ab-270).
- Text aus Anfragen wird vor dem Protokollieren bereinigt (Steuerzeichen und
  Zeilentrenner werden zu `?`, langer Text wird gekürzt), und abgelehnte Anfragen
  werden höchstens 20-mal pro Minute protokolliert, sodass ein Nutzer weder
  Protokollzeilen fälschen noch ältere Einträge durch Fluten aus dem Protokoll
  verdrängen kann (2.6.10).
- Jede Systemaktion kann von jedem angemeldeten Nutzer gestartet werden. Nehmen Sie
  nur Skripte in den Katalog auf, die für alle sicher ausführbar sind.
- Der Status-Cache der Hintergrundprüfungen (`%ProgramData%\SelfX\Cache`) können nur
  SYSTEM und Administratoren lesen; Nutzer und das Statussymbol erhalten das
  validierte Ergebnis über die Anfrage `STATUS` der Pipe.
- Berichte mit Geräteprotokollen liegen in `%ProgramData%\SelfX\Reports\<Nutzer-SID>`.
  Nur SYSTEM, Administratoren und dieser Nutzer können sie lesen; sie werden beim
  nächsten Lauf ersetzt und nach 7 Tagen gelöscht. Der Bericht enthält Geräte-,
  Nutzer- und Mandantennamen; er wird nur gesendet, wenn der Nutzer die E-Mail
  absendet.

## Schnellstart

```powershell
# mit erhöhten Rechten, 64-Bit-Windows-PowerShell 5.1
Set-Location 'C:\Pfad\zu\SelfX Service'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Siehe [Installation](../docs/Installation.md#selfx-service),
[Konfiguration](../docs/Configuration.md#selfx-service) und das
[Benutzerhandbuch](../docs/User-Manual.md#selfx).
