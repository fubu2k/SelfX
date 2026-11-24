# Änderungsprotokoll

[English](CHANGELOG.en.md) | **Deutsch**

Dieses Protokoll beschreibt, was sich in diesem Fork ([fubu2k/SelfX](https://github.com/fubu2k/SelfX))
gegenüber seinem Upstream [wbaeck/SelfX](https://github.com/wbaeck/SelfX) bei SelfX Service
2.6.9 geändert hat. Alles bis Version 2.6.9 stammt aus dem Upstream und wird hier nicht
als neu aufgeführt. Der Verlauf jeder Datei steht in ihrem Kopf.

Die Paketversion ist `Tool_Version` in `SelfX Service\Sources\Tool_Config.xml`.
`Detection.ps1` muss denselben Wert enthalten, sonst erkennt Intune das Update nicht
(das Paketierungsskript prüft das). Ein Release bekommt das Tag `v<Version>` (zum
Beispiel `v3.0.0`); der Release-Workflow prüft, dass Tag und `Tool_Version` übereinstimmen.

## 3.0.2 - 2026-11-24 (SelfX Service)

- **Sicherheit, Berichtsleser:** `SelfX_Device_CollectLogs.ps1` (2.8.21) gibt den Bericht nur noch dem Konto des anfragenden Nutzers
  frei. Als Leser sind nur Nutzer-SIDs erlaubt (`S-1-5-21-…` lokal/Domäne, `S-1-12-1-…` Entra ID). Gruppen und bekannte SIDs wie
  Jeder (`S-1-1-0`), Authentifizierte Benutzer (`S-1-5-11`) oder Benutzer (`S-1-5-32-545`) werden abgelehnt (Exitcode 2, kein
  Bericht), zusätzlich in `Set-ReportAcl` als zweite Sicherung.
- **Sicherheit, PowerShell-7-Prüfung bei der Installation:** `Install.ps1` (2.8.6) prüft pwsh.exe wie der Dienst vor jedem Start:
  nur SYSTEM, Administratoren und TrustedInstaller dürfen pwsh.exe, den Ordner und die Ordner darüber ändern oder übernehmen.
  Die Rechte werden als SID gelesen (eine unbekannte SID wird nicht mehr übersprungen); sind sie nicht lesbar, bricht die
  Installation ab. Tests in `Test-DeviceLogs.ps1` und `Test-InstallBinaries.ps1` ergänzt.

## 3.0.1 - 2026-11-24 (SelfX Service)

- **AppLocker-Hashregeln:** `tools\Build-SelfXBinaries.ps1` (2.8.20) schreibt `build\SelfX.AppLocker.xml` auch auf deutschem und
  anderem lokalisiertem Windows wieder: Die Regeln gelten für die SID `S-1-1-0` statt für den Namen „Everyone“, der dort nicht
  aufgelöst werden kann. In PowerShell 7 entstehen die Regeln über Windows PowerShell 5.1 (neu `tools\New-SelfXAppLockerRules.ps1`),
  weil die AppLocker-Cmdlets dort keine Pfadliste annehmen. Das Skript prüft, dass jedes Programm genau eine Allow-Regel hat.
- **Offline-Bau:** Der Bau der Programme braucht kein Internet mehr. `NuGet.config` im Hauptordner erlaubt nur den Ordner
  `offline-feed` (NuGet-Pakete mit der Hashliste `SelfX.OfflineFeed.json`, SHA512 je Datei).
  `tools\Build-SelfXBinaries.ps1` (2.8.19) prüft den Ordner vor jedem Bau gegen die Hashliste und gegen die SDK-Version des
  Exports, stellt in einem frischen Paketcache im Repository wieder her und bricht ab, wenn ein Paket fehlt, verändert wurde
  oder zusätzlich vorhanden ist. Das neue `tools\Export-SelfXOfflineFeed.ps1` ist das einzige Skript, das nuget.org anspricht: Es
  füllt den Ordner, führt die NuGet-Schwachstellenprüfung aus (beim Offline-Bau ist sie aus) und beweist den Ordner mit einem Offline-Restore. Die Runtime-Pakete von WindowsDesktop und AspNetCore werden nicht mehr angefordert
  (`DisableTransitiveFrameworkReferenceDownloads`). Neuer Test `tools\Test-SelfXOfflineFeed.ps1`. Vor dem ersten Offline-Bau den
  Export einmal ausführen (siehe Installationsanleitung, „Offline-Build“).

## 3.0.0 - 2026-11-23 (SelfX Service)

Version 3.0.0 fasst alle Änderungen seit der Übernahme des Upstream-Stands 2.6.9 zusammen.
Die wichtigsten Punkte:

- **Neues Design:** ruhigere Oberfläche, neues App-Icon, Drei-Schritte-Hinweis und
  Statusmarken mit Symbol (siehe unten).
- **Neue Technik:** Dienst und Starter sind .NET-10-Programme, die einmal gebaut werden;
  alle Skripte laufen in PowerShell 7.6. Mindestversion ist Windows 11 25H2.
- **Mehr Sicherheit:** Der Dienst prüft vor jedem Skriptstart die installierten Dateien
  gegen eine Dateiliste, läuft mit begrenzten Rechten und schützt seine Pipe und seine
  Datenordner. Optional unterstützt SelfX App Control for Business (WDAC).
- **Neue Aktionen, Ticket per E-Mail, Copilot Chat und Remote Help.**
- **Nur noch SelfX Service:** SelfX Standard und SelfX Admin sind entfernt.

### Wichtig beim Update von 2.6.9

1. Stellen Sie **PowerShell 7 (ab 7.6)** als Win32-App bereit und setzen Sie die
   Voraussetzungsregel für Windows 11 25H2 (Build 26200). Ohne PowerShell 7 wird SelfX
   trotzdem installiert (Autopilot bleibt unberührt), startet aber keine Skripte.
2. Bauen Sie das Paket neu: `tools\Build-SelfXBinaries.ps1` (.NET SDK 10 auf dem
   Build-Rechner), danach `tools\New-SelfXIntuneWin.ps1`. Die Geräte kompilieren nichts mehr.
3. Laden Sie die **neue** `.intunewin`-Datei und die vom Paketbau erzeugte
   `Detection.ps1` in Intune hoch (Ordner `build`).
4. Ersetzen Sie vorhandene **AppLocker-Regeln**: Die neuen Programme haben neue Hashes.
5. Die Standardsprache der Oberfläche ist jetzt Deutsch (`Tool_Language` = `de`).

Einzelheiten: [Installationsanleitung](docs/de/Installation.md).

### Neues Design

- Ruhigere Optik des Fensters: größere Rundungen und Abstände, weichere Grundfarben,
  größere Schaltflächen und Karten, abgerundeter Inhaltsbereich.
- Drei-Schritte-Hinweis „Problem auswählen – Bestätigen – Fertig“ unter dem Titel.
- Status-Marken mit Symbol neben dem Text, nicht nur mit Farbe.
- Neues App-Icon (Schraubenschlüssel auf abgerundetem blauem Quadrat) für Fenster,
  Taskleiste, Verknüpfungen und Statussymbol, in allen Größen von 16 bis 256 Pixel.
- Das Statussymbol steht unter Windows 11 dauerhaft neben der Uhr (`Tray_Pin_Icon`,
  Standard `True`; Nutzer können es mit `HKCU\Software\SelfX\TrayPin = 0` abschalten).
- Neue Bildschirmfotos in der Dokumentation.

### Neue Funktionen für Nutzer

- Neue Aktionen:
  - „Microsoft Edge: Zwischenspeicher leeren“ (Cookies, Verlauf, Kennwörter bleiben).
  - „Outlook reagiert nicht mehr“ (beendet und startet das klassische Outlook).
  - „Die Uhrzeit Ihres Geräts stimmt nicht“ (Zeitdienst, über den SelfX-Dienst).
  - „Office fordert zur Aktivierung auf oder meldet ein nicht lizenziertes Produkt“
    (setzt nur das Lizenz-Token zurück).
  - „Outlook schlägt falsche oder veraltete E-Mail-Adressen vor“.
  - „Kein Ton an diesem PC“ (stellt das Standard-Wiedergabegerät wieder hörbar).
  - „Diesen PC auf Viren prüfen“ (Microsoft Defender Schnellscan, über den SelfX-Dienst).
  - „Die Unternehmenseinstellungen (Gruppenrichtlinien) aktualisieren“ (nur auf Geräten,
    die einer Domäne beigetreten sind; neues optionales Katalogfeld `Requires`).
- Neuer Aktionstyp „Link“: öffnet nach der Bestätigung eine https-Adresse aus der
  `Tool_Config.xml` (zum Beispiel Kennwort zurücksetzen oder Sicherheitsinfo).
- Systeminformationen: Warnung „Neustart empfohlen“ ab 7 Tagen Betriebszeit, neue Zeilen
  für Proxy und Netzlaufwerke, genauere Statuszeile „Neustart ausstehend“.
- Optionale Netzwerk-Messungen (Standard aus, `Network_Test_Config.xml`): Antwortzeit zum
  Gateway sowie DNS- und TCP-Dauer zu bis zu 5 Zielen.
- **Ticket per E-Mail** (Standard aus, `Ticket_Enabled`): Der Nutzer beschreibt das Problem,
  SelfX fügt die Geräteinformationen hinzu und öffnet die E-Mail (klassisches oder neues
  Outlook, Standard-Mailprogramm). Der Nutzer sendet selbst. Die zuständige IT-Einheit
  wird über `Ticket_Config.xml` (Group-Tag, OU, Gerätekategorie) oder Registrywerte je
  Gerät bestimmt.
- **Copilot Chat** (Standard aus, `Copilot_Enabled`): SelfX erzeugt aus wenigen geprüften
  Gerätedaten einen Text für Microsoft 365 Copilot Chat (Namen und Adressen als
  Platzhalter), zeigt eine Vorschau und öffnet `https://copilot.cloud.microsoft`. Der Text
  landet nicht im Verlauf der Zwischenablage; optional wird die Zwischenablage nach
  einer Zeit geleert (`Copilot_Clear_Clipboard`).
- **Remote Help:** Ist Microsoft Remote Help installiert und gültig signiert, startet die
  Fernwartungs-Kachel nur noch Remote Help und Quick Assist wird nicht angeboten. Ohne
  Remote Help bleibt es bei Quick Assist.
- Deutsch ist die Basissprache der Oberfläche (vorher Windows-Anzeigesprache); 24 Sprachen,
  fehlende Texte erscheinen auf Englisch. Zuletzt fehlende Übersetzungen wurden ergänzt.
- **Neue Schaltfläche „Firmen-Wiki“ (optional):** `Wiki_Enabled`, `Wiki_Url` (nur `https://`) und `Wiki_Name` (bis 40 Zeichen) in `Tool_Config.xml` blenden in der Navigation eine Schaltfläche im Stil der Copilot-Schaltfläche ein, die die Wiki-Adresse im Webbrowser öffnet. Standardmäßig aus; eine ungültige Adresse blendet die Schaltfläche aus und schreibt eine Warnung ins Protokoll. Läuft im Nutzerkontext. Texte in allen 24 Sprachen, neue Fragen im Paketassistenten, Tests in `Test-SupportLinks.ps1` und `Test-SelfXPackageWizard.ps1`.
- **Neue Aktion „Excel öffnet alle Dateien im selben Fenster“** (Kategorie Office, Nutzerkontext):
  startet eine zweite, unabhängige Excel-Instanz (`excel.exe /x`), zum Beispiel um zwei
  Arbeitsmappen auf zwei Bildschirmen zu vergleichen. Es wird nichts geschlossen oder geändert;
  der Programmpfad kommt aus `SelfXOffice.ps1` (unter Program Files, kein Link), das einzige
  Argument ist der feste Schalter `/x`. Texte in allen 24 Sprachen, Tests in `Test-Scripts.ps1`.
- **Neue Aktion „Ein Programmfenster liegt außerhalb des Bildschirms“** (Kategorie Gerät,
  Nutzerkontext): holt Fenster des eigenen Benutzers, deren Titelleiste auf keinem Bildschirm
  erreichbar ist (zum Beispiel nach dem Abstecken eines Monitors), auf den Hauptbildschirm.
  Es wird nichts geschlossen, gespeichert oder an Einstellungen geändert; Fenster werden über
  Microsoft UI Automation verschoben (kein kompilierter Code), Fenstertitel stehen nicht im
  Log. Programme mit höheren Rechten werden übersprungen. Neuer Helfer `SelfXWindows.ps1`,
  Test: `Test-WindowHelper.ps1`.
- **Neue Aktion „Citrix Workspace reagiert nicht oder zeigt keine Anwendungen“** (Kategorie
  Citrix, Nutzerkontext): beendet die Prozesse der Citrix-Workspace-App im eigenen Benutzerkonto
  und startet die App neu. Offene Anwendungs- und Desktop-Sitzungen werden nicht beendet,
  gespeicherte Anmeldung und Einstellungen bleiben unverändert. Der Programmpfad muss unter
  Program Files liegen (kein Link); es gibt keine Nutzereingaben. Nur die aktuelle
  Citrix Workspace App wird unterstützt, nicht der Receiver.

### Neue Funktionen für Administratoren

- **Dateiliste `SelfX.Files.json`:** Der Paketbau schreibt den SHA256 jeder installierten
  Datei in das Paket. `Install.ps1` prüft sie vor und nach dem Kopieren, der Dienst vor
  **jedem** Skriptstart (Einstellung `Service_FileCheck` = `Enforce` oder `Audit`).
  `Detection.ps1` prüft zusätzlich die Dateiliste und erkennt so Updates auch ohne neue Version.
- **Dienstrechte begrenzt:** `Service_Privileges` = `Restricted` (Standard) begrenzt das Token
  des Dienstes auf neun nötige Rechte; `SeTcb`, `SeDebug` und weitere gefährliche Rechte
  hat der Dienst nicht mehr.
- **Optional App Control for Business (WDAC):** `tools\New-SelfXWdacPolicy.ps1` erzeugt aus
  dem Paket eine ergänzende Richtlinie mit Hashregeln (Überwachung oder Erzwingung).
- **Vorkompilierte Programme:** `SelfXService.exe`, `SelfX.exe` und `SelfXWinRT.dll`
  werden einmal auf einem Build-Rechner gebaut; `SelfX.Binaries.json` enthält die Hashes,
  und `tools\Build-SelfXBinaries.ps1` schreibt auf Wunsch AppLocker-Hashregeln.
- **Release-Workflow** (`.github/workflows/release.yml`): läuft nur bei einem Tag, prüft
  den Tag gegen `Tool_Version`, baut Programme, `.intunewin`, SBOM (CycloneDX) und
  `SHA256SUMS.txt` und legt einen Release-Entwurf an.
- **Windows-Ereignisprotokoll:** Der Dienst schreibt Ereignisse 4001 bis 4005 und 4099
  (Quelle `SelfXService`).
- **Mehrere Nutzer auf einem Gerät:** `OtherSessions` = `Block` sperrt störende Aktionen
  (Neustart, Updates, Datenträgerprüfung, Netzwerk- und Intune-Neustart), solange ein anderer
  Nutzer angemeldet ist; Administratoren mit erhöhten Rechten dürfen sie trotzdem starten.
- **Geräteberichte:** Normale Nutzer sehen nur ihre eigenen Daten, ein Administrator mit
  erhöhten Rechten den ganzen Bericht. Neu: Zusammenfassung der Ereignisprotokolle.
  Der Dienst löscht Berichte nach 7 Tagen automatisch.
- Voraussetzungsprüfung bei der Installation: Windows 11 25H2, sichere Ordnerrechte für
  PowerShell 7 (sonst Abbruch vor jeder Änderung).
- **Paketassistent (geführte Konfiguration):** `tools\New-SelfXPackage.ps1` stellt Fragen mit
  Empfehlung (Support, Branding, Ticket und Organisationen nach OU, Group Tag und Geräteklasse,
  Copilot Chat, Verhalten), schreibt die Antworten in eine Kopie des Pakets, baut das Intune-Paket,
  erzeugt die Plattformskripte für die Ticket-Zuordnung und eine Kurzanleitung für Intune.
  Deutsch und Englisch, weitere Sprachen über `tools\Wizard\Wizard.<Kultur>.xml`. Siehe
  [Paketassistent](docs/de/Assistent.md). `New-SelfXIntuneWin.ps1` 1.8.0 hat den neuen Parameter
  `-SourceFolder`. Test: `tools\Test-SelfXPackageWizard.ps1` (läuft in der CI).
- **Citrix Workspace in den Systeminformationen:** Ist die Citrix Workspace App installiert, zeigt
  SelfX unter „Gerät“ die Zeile „Citrix Workspace“ mit der Version. Die Zeile steht auch in den
  Geräteinformationen des Support-Tickets. Die Erreichbarkeit von StoreFront oder Gateway lässt sich
  über ein Ziel in `Network_Test_Config.xml` messen (Beispiel in der Datei). Test:
  `Test-CitrixInfo.ps1`.

### Sicherheit

Befunde einer Sicherheitsprüfung (OWASP, Microsoft, BSI), alle behoben:

- **Dienst und Pipe:** feste Fristen für Lesen und Schreiben, Verbindungslimits (64 gesamt,
  8 pro Nutzer), Prüfung des Pipe-Servers durch das Fenster, `FirstPipeInstance` gegen
  vorab angelegte Pipes, bereinigtes und gedrosseltes Dienstprotokoll, Job-Objekt, das
  alle Kindprozesse beim Stoppen beendet, keine unbehandelten Ausnahmen mehr.
- **Dateien und Ordner:** `%ProgramData%\SelfX` wird beim Installieren vor Verknüpfungen
  und fremden Einträgen geschützt, Berichte werden sicher angelegt (Temp-Ordner,
  Hardlinks), Löschen als SYSTEM folgt keinen Junctions, TEMP-Ordner des Compilers geschützt.
- **Eingaben:** Alle XML-Dateien werden ohne DTD gelesen; Links aus `Tool_Config.xml` müssen
  https (oder `mailto:` mit einer Adresse) sein; CSV-Export schützt vor Formeln;
  Teams-Installer-Protokolle werden nur sicher gelesen.
- **Ablauf:** Aktionen laufen nur über die Whitelist des Katalogs, Parameter kommen nie vom Nutzer.
- **Lieferkette:** festgelegte GitHub Actions, Dependabot, CodeQL, PSScriptAnalyzer,
  SBOM, CODEOWNERS, `SECURITY.md`.

### Intune, Paket und Werkzeuge

- Programme: .NET 10 (LTS), self-contained, je eine Datei; keine Laufzeit auf dem Gerät.
- Skripte laufen mit `%ProgramFiles%\PowerShell\7\pwsh.exe` (fester Pfad); `Install.ps1`,
  `Uninstall.ps1` und `Detection.ps1` bleiben in Windows PowerShell 5.1, damit Autopilot
  und Intune sie starten können.
- Windows-Module ersetzt durch CIM: BitLocker, TPM, Secure Boot, Defender, Netzwerkadapter,
  DNS-Cache und Datenträgerreparatur. Das behebt nebenbei, dass Datenlaufwerke bei BitLocker
  nie geprüft wurden.
- „Updates installieren“ nutzt nur noch den Windows-Update-Orchestrator (`SelfXWinRT.dll`).
- Automatische Tests (`Test-*.ps1`) laufen bei jedem Pull Request in PowerShell 7; die
  Installationsskripte werden zusätzlich in Windows PowerShell 5.1 geprüft.
- Aufgeräumt: mehrfach vorhandener Office-Code in `SelfXOffice.ps1` zusammengeführt.

### Entfernt

- **SelfX Standard** und **SelfX Admin**: Der Fork entwickelt nur SelfX Service.
  Bei Bedarf nutzen Sie die Upstream-Projekte.
- Unterstützung für ältere Windows-Versionen als 11 25H2 und der Windows Update Agent.

## Basierend auf Upstream 2.6.9

Windows-Updates über den Windows-Update-Orchestrator, die Erkennung eines
ausstehenden Neustarts und alle übrigen Änderungen bis SelfX Service 2.6.9 stammen
von [wbaeck/SelfX](https://github.com/wbaeck/SelfX).
