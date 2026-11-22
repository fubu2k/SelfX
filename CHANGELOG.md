# Änderungsprotokoll

[English](CHANGELOG.en.md) | **Deutsch**

Änderungen dieses Forks ([fubu2k/SelfX](https://github.com/fubu2k/SelfX)) gegenüber
seinem Upstream [wbaeck/SelfX](https://github.com/wbaeck/SelfX) bei SelfX Service
2.6.9. Neueste Version zuerst.

Die Paketversion ist `Tool_Version` in `SelfX Service\Sources\Tool_Config.xml`.
`Detection.ps1` muss denselben Wert enthalten, sonst erkennt Intune das Update nicht
(das Paketierungsskript prüft das). Die Versionsnummern in den Verläufen der
einzelnen Dateien zeigen, wo eine Änderung gemacht wurde. Änderungen, die mit 2.6.10
gekennzeichnet sind, entstanden vor der Anhebung der Paketversion; sie werden mit
**2.6.11** ausgeliefert, der ersten Paketversion dieses Forks.

## Nicht veröffentlicht (SelfX Service, Phase 2 der Umstellung)

Dienst, Fenster und Statussymbol starten PowerShell 7 statt Windows PowerShell 5.1.
Wird zusammen mit dem Ersatz für die Windows-Update-Schnittstelle (WinRT) und der
Anhebung der Version ausgeliefert.

### Geändert

- CI: Die Tests laufen jetzt verbindlich in PowerShell 7. Windows PowerShell 5.1 prüft nur noch
  `Install.ps1`, `Uninstall.ps1`, `Detection.ps1` und den Log-Sammler (Intune startet sie dort).
  Health-Prüfung und Support-Bericht enthalten keine PowerShell-5.1-Zweige mehr.
- „Updates installieren“ nutzt nur noch den Windows-Update-Orchestrator (`SelfXWinRT.dll`,
  PowerShell 7). Die Windows-Update-Agent-API und der PowerShell-5.1-Zweig sind entfernt
  (Mindestversion Windows 11 25H2). Fehlt die Orchestrator-API, endet die Aktion mit Exit 1.
- Mindestversion: Windows 11 25H2 (Build 26200). `Install.ps1` prüft die Build-Nummer
  (Registry) vor jeder Änderung und bricht bei älteren Builds hart ab; die bestehende
  Installation bleibt unverändert.
- Der Dienst startet alle Skripte mit `%ProgramFiles%\PowerShell\7\pwsh.exe` (fester
  Pfad, keine PATH-Suche). Er setzt für das Skript nur die maschinenweiten Modulordner
  (`PSModulePath`) und schaltet Telemetrie und Update-Prüfung von PowerShell aus. Fehlt
  PowerShell 7, startet er nichts und meldet „PowerShell 7 is not installed“.
- `SelfX.exe`, `Start-SelfXHiddenPowerShell`, die Health-Prüfung und der Log-Sammler
  nutzen denselben festen Pfad.
- Autopilot muss immer funktionieren: Fehlt PowerShell 7 (oder ist es älter als 7.6),
  installiert `Install.ps1` SelfX trotzdem und gibt nur eine Warnung aus. Bis PowerShell 7
  da ist, startet der Dienst keine Skripte und meldet „PowerShell 7 is not installed“.
  Ist PowerShell 7 vorhanden, aber für Normalnutzer änderbar (Ordner oder `pwsh.exe`), bricht
  die Installation vor allen Änderungen ab (Sicherheit). Der Dienst prüft Rechte und Version
  außerdem vor jedem Start, denn PowerShell 7 kann erst nach SelfX installiert werden.
  `Install.ps1` und `Uninstall.ps1` laufen weiter in Windows PowerShell 5.1 und
  beenden Fenster und Statussymbole von `powershell.exe` und `pwsh.exe`.
- Die Tests `Test-ServicePipe.ps1` und `Test-HealthStatus.ps1` übersetzen den Dienst auch
  in PowerShell 7; `Test-InstallBinaries.ps1` prüft die neue Voraussetzung.

- Neue Bibliothek `SelfXWinRT.dll` (.NET 10, Windows-SDK-Projektion) ersetzt in
  PowerShell 7 den WinRT-Zugriff auf den Windows-Update-Orchestrator (Windows 11 24H2
  und neuer), den PowerShell 7 nicht mehr nach Namen laden kann. Sie enthält keine
  eigene Logik und liefert nur das Manager-Objekt. `Build-SelfXBinaries.ps1` baut sie
  zusammen mit den zwei Projektionsdateien nach `Bin\WinRT`; `Install.ps1` prüft jede
  Datei per SHA256 und kopiert sie nach `%ProgramFiles%\SelfX\WinRT`. Auf älterem Windows
  fallen die Skripte wie bisher auf den Windows Update Agent zurück.
- Manifest `SelfX.Binaries.json` hat jetzt Format 3 (Einträge `WinRT/...`). Pakete mit
  Format 2 lehnt der Installer ab: Paket neu bauen.

## 2.7.0 - 2026-11-22 (SelfX Service)

Dienst und Starter laufen auf .NET 10 (LTS, Support bis 14.11.2028). Die Programme
werden einmal auf einem Build-Rechner gebaut; die Geräte kompilieren nichts mehr.
`Tool_Version` und `$ExpectedVersion` wurden angehoben: Paket neu bauen und verteilen.

### Geändert

- `SelfXService.exe` und `SelfX.exe` sind .NET-10-Programme (self-contained, eine Datei,
  je etwa 36 MB). Auf den Geräten ist keine .NET-Laufzeit nötig. Die Oberfläche und
  alle Skripte laufen weiter in Windows PowerShell 5.1.
- `tools\Build-SelfXBinaries.ps1` baut mit `dotnet publish` (.NET SDK 10 auf dem
  Build-Rechner). Der Aufruf bleibt gleich. Das Manifest hat das Format 2.
- `Install.ps1` verlangt den Ordner `Bin` und prüft ihn, bevor es die bestehende
  Installation anfasst. Das Kompilieren auf dem Gerät entfällt. Fehlt `Bin`, bricht
  die Installation mit einer klaren Meldung ab und die alte Version bleibt.
- `tools\New-SelfXIntuneWin.ps1` baut kein Paket ohne geprüftes `Bin` und packt die
  .NET-Projektdateien nicht mit ein.
- Neu: .NET-Projekte unter `SelfX Service\Service\Projects`, NuGet-Lock-Datei,
  CI-Job, der zweimal baut und die Hashes vergleicht und den Dienst startet.
- Installationsanleitung mit Schritt-für-Schritt-Ablauf neu geschrieben.

### Hinweis

Neue Programme haben neue Hashes: AppLocker-Regeln des Vorgängers ersetzen.

## 2.6.12 - 2026-11-22 (SelfX Service)

Deutsch ist die Basissprache der Benutzeroberfläche; Englisch ist der Rückfall.
`Tool_Version` und `$ExpectedVersion` wurden angehoben: Paket neu verteilen.

### Geändert

- `Tool_Language` in `Tool_Config.xml` ist jetzt standardmäßig `de` (vorher `Auto`,
  die Anzeigesprache von Windows). Nutzer können in SelfX > Einstellungen weiterhin
  eine andere Sprache wählen; `Auto` bleibt möglich.
- Passt keine Sprachdatei (zum Beispiel `Auto` auf einem Gerät mit tschechischer
  Oberfläche), verwendet SelfX Deutsch statt Englisch. Ein Text, der in der
  gewählten Sprache fehlt, erscheint auf Englisch.
- `Test-UI.ps1` testet die Basissprache.

Nicht geändert: Die Texte der Aktionen in `Issues_List.xml` bleiben englische
Basistexte; sie werden nur verwendet, wenn ein Text weder auf Deutsch noch auf
Englisch vorliegt.

## Repository, 2026-11-22

- Der Fork wird nur noch für SelfX Service entwickelt. Die Ordner `SelfX Standard`
  und `SelfX Admin` wurden entfernt; nutzen Sie bei Bedarf die Upstream-Projekte.
  `tools\New-SelfXIntuneWin.ps1` (1.3.0) baut nur noch das Paket von SelfX Service;
  `Test-UI.ps1` liest keine Datei von SelfX Standard mehr.
- README, Installationsanleitung, Konfigurationsanleitung, Benutzerhandbuch und
  `SECURITY.md` beschreiben nur noch SelfX Service.
- Die Paketversion von SelfX Service blieb unverändert (2.6.11).
- Deutsch ist die Hauptsprache des Repositorys; die englischen Fassungen liegen als
  `*.en.md` und unter `docs/en`.

## 2.6.11 - 2026-11-22 (SelfX Service)

Release zur Sicherheitshärtung. Es ersetzt den Dienst und den Installer: das
**gesamte Paket** neu verteilen. Das Update wird wie jedes andere Update
installiert; `Tool_Version` und `$ExpectedVersion` in `Detection.ps1` wurden beide
auf 2.6.11 angehoben.

### Sicherheit

- **Zuverlässige Fristen an der Pipe.** Die Pipe des Dienstes nutzt überlappende
  Ein-/Ausgabe. Das Lesen der Anfrage, das Schreiben der Antwort und das Warten auf
  den Client werden abgebrochen, wenn die Frist abläuft; endet die Operation nicht,
  wird die Verbindung geschlossen. Eine Frist von 5 Sekunden gilt für die ganze
  Anfrage, langsames Senden verlängert sie nicht.
- **Verbindungslimit vor dem Lesen.** Das Limit von 8 Verbindungen pro Nutzer wird
  beim Annehmen der Verbindung angewendet, anhand des Besitzers des Client-Prozesses,
  den Windows meldet. Ein Nutzer kann die 64 Verbindungsplätze aller Nutzer nicht
  mehr belegen, bevor der Dienst eine Anfrage gelesen hat.
- **Vorkompilierte Programme per Hash geprüft (optional).**
  `tools\Build-SelfXBinaries.ps1` baut `SelfXService.exe`, `SelfX.exe` und
  `SelfXSessionStarter.dll` einmal auf einem Build-Rechner und schreibt
  `SelfX Service\Bin\SelfX.Binaries.json` mit dem SHA256 der Quellen und Dateien.
  Sind die AppLocker-Cmdlets verfügbar, schreibt es außerdem
  `build\SelfX.AppLocker.xml` mit Hashregeln für die drei Dateien. Enthält das Paket
  `Bin`, prüft `Install.ps1` das Manifest, die Quellen und den Hash jeder Datei und
  bricht mit Exitcode 1 ab, wenn etwas nicht passt; stattdessen wird nichts
  kompiliert. Die Dateien sind nicht signiert.
- **Geschützter TEMP-Ordner des Compilers.** Ohne `Bin` kompiliert das Gerät die
  Programme weiterhin, aber der Compiler schreibt seine temporären Dateien jetzt in
  einen Ordner unterhalb des geschützten Installationsordners statt nach
  `C:\Windows\Temp`.
- **Paketierung.** `tools\New-SelfXIntuneWin.ps1` weist einen Ordner `Bin` zurück,
  der aus anderen Quellen gebaut wurde als denen im Paket.

### Hinzugefügt

- `Test-ServicePipe.ps1`: startet den Pipe-Listener des Dienstes unter einem
  Testnamen und prüft die Fristen, langsame Sender, zu große Anfragen und das Limit
  pro Nutzer. Er braucht weder Installation noch Administratorrechte.
- `Test-InstallBinaries.ps1`: testet die Prüfung der vorkompilierten Programme und
  den geschützten TEMP-Ordner des Compilers.
- GitHub-Actions-Workflow `.github/workflows/service-ci.yml`: kompiliert Dienst,
  Launcher und Session-Starter, führt alle `Test-*.ps1` in Windows PowerShell 5.1
  aus und führt PSScriptAnalyzer mit Sicherheitsregeln für jeden Pull Request und
  jede Änderung an `main` aus. Der Workflow hat nur Leserechte und nutzt auf einen
  Commit festgelegte Actions.
- `SECURITY.md` (vertrauliches Melden von Schwachstellen), `.github/CODEOWNERS` und
  Dependabot für die festgelegten GitHub Actions; dieses `CHANGELOG.md`.

### Behoben

- Vier bestehende Tests schlugen beim ersten Lauf auf einem Windows-Runner fehl
  (Parserfehler in `Test-Catalog.ps1`, eine geänderte Methodensignatur in
  `Test-HealthStatus.ps1` und zwei Tests, die ein Konto ohne erhöhte Rechte
  voraussetzten). Der Produktcode war nicht betroffen.

### Geändert

- Eine Verbindung über dem Limit pro Nutzer wird ohne Antwort geschlossen (vorher:
  die Antwort *busy*). Das SelfX-Fenster erreicht dieses Limit nicht.
- Dokumentation: neue Installations- und Release-Checkliste, Beschreibung der
  vorkompilierten Programme und der AppLocker-Regeln, aktualisierte Testliste.

## 2.6.10 - 2026-11-22 (SelfX Service; mit 2.6.11 ausgeliefert)

Befunde der Sicherheitsprüfung von SelfX Service. Die Nummern der Pull Requests
beziehen sich auf dieses Repository.

### Sicherheit

- **Bericht mit den Geräteprotokollen (#1, #2).** Der Bericht liest die
  Protokollordner der Nutzer nicht mehr als SYSTEM (Nutzer können diese Ordner
  ändern). Das SelfX-Fenster fügt die eigenen Nutzerprotokolle mit den Rechten des
  Nutzers hinzu. Auf Geräten mit mehreren Nutzern erhält ein normaler Nutzer nur die
  eigenen Daten; nur ein Administrator mit erhöhten Rechten (vom Dienst aus dem
  Client-Token gelesen, `SELFX_CALLER_ADMIN=1`) erhält den vollständigen Bericht.
- **Status-Cache (#3).** Eine einzelne Gesundheitsprüfung (`HEALTH <Id> <Name>`) mit
  unbekanntem Namen kann dem Status-Cache, den alle Nutzer und das Statussymbol
  gemeinsam verwenden, keine Zeilen mehr hinzufügen.
- **Dienstprotokoll und Anfragen (#4).** Text aus Anfragen wird vor dem
  Protokollieren bereinigt und gekürzt, abgelehnte Anfragen werden höchstens 20-mal
  pro Minute protokolliert (ein Nutzer kann das Protokoll nicht fluten) und die
  Anfragemuster enden mit `\z` statt `$`.
- **Pipe-Limits (#6).** Der Dienst schließt Verbindungen, die 5 Sekunden lang nichts
  senden oder die Antwort nicht lesen, führt jede Verbindung in einem eigenen Thread
  aus und nimmt höchstens 64 Verbindungen an (8 pro Nutzer). Nach einer Prüfung
  wartet derselbe Nutzer 3 Sekunden bis zur nächsten; nach einer Aktion 15 Sekunden,
  bis dieselbe Aktion erneut gestartet werden kann. In beiden Fällen antwortet der
  Dienst *busy*.
- **Prüfung des Pipe-Servers (#7).** Bevor das SelfX-Fenster eine Anfrage sendet,
  prüft es, dass die Pipe vom laufenden `SelfXService` bedient wird (Prozess-ID des
  Pipe-Servers verglichen mit der Prozess-ID aus der Dienststeuerung). Ein
  Nutzerprozess, der den Pipe-Namen angelegt hat, während der Dienst gestoppt war,
  wird abgewiesen.
- **Deinstallation (#8).** `Uninstall.ps1 -RemoveLogs` löscht die Datenordner, ohne
  Junctions oder symbolischen Links zu folgen, die Nutzer angelegt haben.
- **Mehrere Nutzer auf einem Gerät (#9).** Neues Katalogelement `OtherSessions` (und
  Attribut an einer Reparatur in `Health_Config.xml`): Mit `Block` kann ein normaler
  Nutzer die Aktion nicht starten, solange ein anderer Nutzer eine aktive Sitzung
  hat. Die mitgelieferte Konfiguration setzt es für den Neustart, Windows-Updates,
  die Datenträgerprüfung, den Neustart der Netzwerkadapter und den Neustart des
  Intune-Dienstes. Administratoren mit erhöhten Rechten sind nicht eingeschränkt;
  lassen sich die Sitzungen nicht lesen, wird die Aktion blockiert.

### Hinzugefügt

- `Test-Catalog.ps1` (#5): statische Prüfung des Katalogs, von `Health_Config.xml`
  und der Skripte, die als SYSTEM laufen (reine Dateinamen, ein Kontext pro Skript,
  keine Pflichtparameter, Zeitlimits der Reparaturen).
- `Test-Uninstall.ps1` (#8) sowie Erweiterungen von `Test-HealthStatus.ps1` und
  `Test-DeviceLogs.ps1`.

## Basierend auf Upstream 2.6.9

Windows-Updates über den Windows-Update-Orchestrator, die Erkennung eines
ausstehenden Neustarts und die übrigen Änderungen bis SelfX Service 2.6.9 stammen
von [wbaeck/SelfX](https://github.com/wbaeck/SelfX). Der Verlauf jeder Datei steht in
ihrem Kopf.
