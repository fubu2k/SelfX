# Installation

[English](en/Installation.md) | **Deutsch**

Diese Anleitung beschreibt die Installation von **SelfX Service** auf verwalteten
Windows-Geräten, insbesondere mit Microsoft Intune.

## Voraussetzungen

- Das vollständige Paketverzeichnis, einschließlich der Inhalte von `assembly` und
  `Scripts_to_run`.
- Für SelfX Service auf dem Gerät (ab 2.8.0):
  - **Windows 11 25H2 (Build 26200) oder neuer**, 64 Bit. Der Installer bricht auf
    älteren Versionen ab, bevor er etwas ändert.
  - **PowerShell 7.6 oder neuer**, für alle Nutzer installiert (Microsoft-MSI) unter
    `%ProgramFiles%\PowerShell\7\pwsh.exe`. Dienst, Fenster und Statussymbol starten
    dieses PowerShell 7. Die Store-Variante (MSIX) ist nicht nutzbar, weil sie nur
    für einen Nutzer installiert wird. Wie Sie PowerShell 7 mit Intune verteilen,
    steht unter [Windows-Version und PowerShell 7](#windows-version-und-powershell-7-ab-280).
  - Die in Windows enthaltene 64-Bit-Windows-PowerShell 5.1 braucht SelfX nur noch für
    `Install.ps1`, `Uninstall.ps1`, `Detection.ps1` und `Collect-DeviceLogs.ps1`. Sie
    müssen diese vier Dateien auch ohne PowerShell 7 ausführen können (zum Beispiel
    bei Autopilot).
  - Eine .NET-Installation ist **nicht** nötig: Dienst und Starter sind
    .NET-10-Programme, die alles Nötige selbst mitbringen (self-contained).
- Für das Bauen des Pakets (nicht auf den Geräten): ein Windows-Rechner mit dem
  .NET SDK 10, siehe [Schnellstart](#schnellstart-eine-neue-version-ausrollen). Der
  Installer installiert nur die vorgebauten Programme aus dem Ordner `Bin` des
  Pakets (siehe [Programme bauen](#programme-bauen-selfx-service-ab-270)). Er
  kompiliert nichts auf dem Gerät und braucht dort weder Internet noch SDK.

## Schnellstart: eine neue Version ausrollen

Diese Schritte gelten für jede neue Version von SelfX Service. Sie brauchen dafür
**einen Windows-Rechner zum Bauen** (den „Build-Rechner"). Auf den Geräten Ihrer
Nutzer wird nichts gebaut oder kompiliert.

### Einmal vorbereiten: der Build-Rechner

1. Nehmen Sie einen Windows-Rechner mit Internetzugang. Ein normaler
   Administrator-Arbeitsplatz reicht. Er muss nicht zu den verwalteten Geräten
   gehören.
2. Installieren Sie das **.NET SDK 10** („SDK", nicht nur „Runtime"). Download:
   <https://dotnet.microsoft.com/download/dotnet/10.0>. Öffnen Sie danach ein neues
   PowerShell-Fenster und prüfen Sie:

   ```powershell
   dotnet --version
   ```

   Die Ausgabe muss mit `10.` beginnen. Eine andere Hauptversion lehnt das
   Bauskript ab.
3. Laden Sie das Repository auf den Rechner (`git clone` oder ZIP von GitHub).
4. Laden Sie `IntuneWinAppUtil.exe` aus dem offiziellen Microsoft-Repository
   (<https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool>) und merken Sie
   sich den Pfad, zum Beispiel `C:\Tools\IntuneWinAppUtil.exe`.

### Bei jeder neuen Version

1. **Repository aktualisieren.** Mit `git pull` oder einem neuen ZIP. Wechseln Sie
   danach im PowerShell-Fenster in den Ordner des Repositorys.
2. **Einstellungen prüfen.** Branding und Support-Kontakte stehen in
   `SelfX Service\Sources\Tool_Config.xml` und `Health_Config.xml`.
3. **Versionsnummer erhöhen.** Tragen Sie dieselbe neue Nummer an zwei Stellen ein:
   `Tool_Version` in `Sources\Tool_Config.xml` und `$ExpectedVersion` in
   `Detection.ps1`. Sonst hält Intune das Gerät für aktuell und verteilt nichts.
4. **Tests prüfen.** Wenn Sie über einen Pull Request arbeiten, laufen die Tests
   automatisch auf GitHub. Sie sehen dort grüne Häkchen. Bei einem roten Test nicht
   weitermachen.
5. **Programme bauen.** Dieser Befehl erzeugt den Ordner `SelfX Service\Bin`:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1
   ```

   Am Ende zeigt das Skript drei Dateien mit ihrem Hash an (`SelfXService.exe`,
   `SelfX.exe`, `SelfXSessionStarter.dll`). Der erste Lauf lädt das Microsoft-Paket
   `System.ServiceProcess.ServiceController` aus dem Internet; die Version ist
   festgelegt und wird geprüft.
6. **AppLocker anpassen** (nur wenn Sie AppLocker nutzen). Das Skript schreibt
   `build\SelfX.AppLocker.xml`. Übernehmen Sie diese Regeln in Ihre Richtlinie und
   löschen Sie die Regeln der vorherigen Version. Tun Sie das, bevor das Paket die
   Geräte erreicht.
7. **Intune-Paket erstellen.** Der Pfad hinter `-ToolPath` ist der aus Schritt 4 der
   Vorbereitung:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1 -ToolPath C:\Tools\IntuneWinAppUtil.exe
   ```

   Ergebnis: `build\SelfX-Service-<Version>.intunewin`. Das Skript bricht ab, wenn
   `Bin` fehlt oder nicht zu den Quelltexten passt.
8. **Auf einem Testgerät prüfen.** Installieren Sie das Paket auf einem Gerät, das
   nicht produktiv ist: Neuinstallation, Update von der Vorversion, Deinstallation.
   Prüfen Sie SelfX als normaler Nutzer ohne Administratorrechte.
9. **In Intune hochladen.** Als Win32-App mit den Befehlen aus der Tabelle unter
   [SelfX Service](#selfx-service). Erkennung: das Skript `Detection.ps1`.

### Wenn etwas schiefgeht

| Meldung | Bedeutung und Lösung |
|---|---|
| `The command dotnet was not found` | Das .NET SDK 10 ist nicht installiert, oder das PowerShell-Fenster ist älter als die Installation. SDK installieren und ein neues Fenster öffnen. |
| `The .NET SDK 10 is required, found '…'` | Es ist kein SDK 10 installiert (oder nur ein anderes). SDK 10 installieren. Sind mehrere SDKs installiert, wählt die `global.json` im Repository automatisch das SDK 10. |
| `The folder Bin is missing …` | Schritt 5 wurde nicht ausgeführt, oder das Paket wurde vorher gebaut. Schritt 5 und 7 wiederholen. |
| `Bin was not built from the current …` | Ein Quelltext wurde nach dem Bauen geändert. Schritt 5 und 7 wiederholen. |
| Die Installation auf dem Gerät endet mit Exitcode 1 | Den Grund nennt die letzte Zeile von `%ProgramData%\SelfX\Logs\Install.log`. Die bisherige Installation bleibt dann unverändert. |

## SelfX Service

SelfX Service wird für das ganze Gerät installiert und läuft vollständig offline.
Sie brauchen zwei Dinge: das komplette Paketverzeichnis und Administratorrechte. Der
Installer läuft entweder manuell mit erhöhten Rechten oder über Intune/SCCM im
SYSTEM-Kontext:

```powershell
Set-Location 'C:\Pfad\zu\SelfX Service'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Von einem 32-Bit-Agenten aus verwenden Sie
`%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe`. Der Installer:

1. Stoppt und entfernt einen vorhandenen `SelfXService`.
2. Leert `%ProgramFiles%\SelfX` und kopiert `Sources` und `Uninstall.ps1` hinein.
   Der Ordner selbst bleibt erhalten, weil ein geöffnetes SelfX-Fenster oder
   Statussymbol ihn als Arbeitsverzeichnis nutzen kann. Dateien, die kurz in
   Benutzung sind, werden 20 Sekunden lang erneut versucht. Danach ersetzt der
   Installer die vererbten Berechtigungen, sodass SYSTEM und Administratoren
   Vollzugriff haben und Benutzer nur lesen und ausführen dürfen.
3. Installiert `%ProgramFiles%\SelfX\SelfXService.exe` (den Dienst) und
   `%ProgramFiles%\SelfX\SelfX.exe` (2.5.3). Beide kommen aus dem Ordner `Bin` des
   Pakets. Der Installer prüft sie **ganz am Anfang**, bevor er etwas auf dem Gerät
   ändert, gegen ihr SHA256-Manifest. Fehlt `Bin` oder passt eine Datei nicht, endet
   die Installation mit Exitcode 1 und die bisherige Installation bleibt unverändert
   (2.7.0). Auf dem Gerät wird nichts kompiliert.
   `SelfX.exe` ist ein kleiner Starter ohne Konsole: Er startet SelfX
   (`/page:<Seite>` optional) oder das Statussymbol (`/tray`) mit einem
   versteckten PowerShell 7 (`pwsh.exe`), sodass kein Befehlsfenster erscheint, auch nicht
   mit Windows Terminal als Standardterminal.
4. Registriert und startet den **SelfX-Dienst** (`SelfXService`). Er läuft als
   LocalSystem, startet automatisch und wird nach einem Fehler neu gestartet.
5. Legt Verknüpfungen für alle Nutzer auf dem öffentlichen Desktop und im
   Startmenü an (Ziel `SelfX.exe`), gemäß `Tool_Config.xml`.
6. Fügt einen Eintrag unter Apps & Features hinzu.
7. Ist `Show_Tray_Icon` auf `True` (Standard), wird der HKLM-Run-Eintrag
   `SelfXTray` (`SelfX.exe /tray`) angelegt, sodass das Statussymbol
   (`SelfX_Tray.ps1`) bei jeder Anmeldung für alle Nutzer startet. Seit 2.5.8
   erscheint das Symbol auch direkt nach der Installation. Laufende Statussymbole
   werden geschlossen, bevor die Dateien ersetzt werden. Läuft der Installer als
   SYSTEM (Intune/SCCM), startet er `SelfX.exe /tray` in jeder aktiven
   Nutzersitzung, mit den normalen Rechten des angemeldeten Nutzers, nicht
   erhöht. Das Ergebnis steht in `Install.log` (`Status icon: Session <n>:
   started`). Führen Sie den Installer manuell als Administrator aus, erlaubt
   Windows das nicht: Das Symbol erscheint bei der nächsten Anmeldung oder wenn der
   Nutzer SelfX öffnet. Geöffnete SelfX-Fenster werden nicht geschlossen.

Das Installationsprotokoll ist `%ProgramData%\SelfX\Logs\Install.log`. Das
Dienstprotokoll ist `%ProgramData%\SelfX\Logs\SelfXService.log`; es rotiert bei
5 MB nach `.old`. Beide Protokolle können nur Administratoren und SYSTEM lesen.
Seit 2.6.0 protokolliert jedes SelfX-Skript nach `%ProgramData%\SelfX\Logs` (eine
Datei pro Skript und Tag); das Fenster, das Statussymbol und die Nutzeraktionen
protokollieren nach `%ProgramData%\SelfX\Logs\Users\<SID>`. Diesen Ordner legt der
Installer so an, dass jeder Nutzer nur den eigenen Ordner anlegen und lesen kann.
Protokolldateien, die älter sind als `Log_Retention_Days` (Standard 90), werden
automatisch gelöscht; siehe
[Protokollierung](Configuration.md#protokolle-und-aufbewahrung).

Sicherheitsrelevante Ereignisse schreibt der Dienst zusätzlich in das Windows-Ereignisprotokoll
(Protokoll *Anwendung*, Quelle `SelfXService`), damit Defender for Endpoint, Intune oder ein SIEM sie
auswerten können. Die Texte sind fest und enthalten keine Anfragetexte und keine Nutzernamen (das
Anwendungsprotokoll kann jeder Nutzer lesen); Einzelheiten stehen im geschützten `SelfXService.log`. Je
Ereignis-ID gelten höchstens 10 Einträge in 10 Minuten, danach meldet 4099 die Zahl der ausgelassenen.

| ID | Stufe | Bedeutung |
|---|---|---|
| 4001 | Fehler | Der Pipe-Name gehört schon einem anderen Prozess; der Dienst nimmt keine Verbindungen an, bis er frei ist. |
| 4002 | Warnung | Eine Anfrage oder Verbindung wurde abgelehnt (ungültig, nicht erlaubt, Begrenzung). |
| 4003 | Warnung | PowerShell 7 ist nicht gegen Änderungen durch Nutzer geschützt; Aktionen als SYSTEM werden nicht gestartet. |
| 4004 | Fehler | `%ProgramData%\SelfX` ist nicht geschützt (Verknüpfung oder fremder Besitzer); der Dienst schreibt dort nichts, bis ein Administrator es repariert (SelfX neu installieren). |
| 4005 | Fehler | Die installierten Skripte oder Konfigurationen stimmen nicht mit `SelfX.Files.json` überein (geändert, fehlend, nicht gelistet, Verknüpfung, Liste fehlt oder ungültig); der Dienst startet nichts. Mit `Service_FileCheck` = `Audit` Warnung, Aktionen laufen weiter. Die Einzelheiten stehen im SelfX-Protokoll. |
| 4099 | Warnung | Weitere Ereignisse derselben ID wurden nicht geschrieben (Begrenzung). |

Der Installer endet bei Erfolg mit Exitcode 0 und bei einem Fehler mit 1. Den Grund
finden Sie in der letzten Zeile von `Install.log` (`Installation failed: ...`).

> **Hinweis zu alten Versionen:** Bis 2.5.1 schlug ein Update fehl, wenn ein Nutzer
> SelfX oder das Statussymbol geöffnet hatte. Windows löscht keinen Ordner, den ein
> laufendes Programm als Arbeitsverzeichnis nutzt. Der Installer hatte dann Dienst
> und Dateien schon entfernt und brach ab. Seit 2.5.2 leert er den Ordner, statt ihn
> zu löschen. Um ein solches Gerät zu reparieren, verteilen Sie 2.5.2 oder neuer. Eine
> Abmeldung ist nicht nötig.

Für Intune-Win32-Apps:

| Einstellung | Wert |
|---|---|
| Installationsbefehl | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Deinstallationsbefehl | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Installationsverhalten | System |
| Erkennung | Benutzerdefiniertes Skript `Detection.ps1`. Setzen Sie `$ExpectedVersion` auf die `Tool_Version` des Releases. |
| Voraussetzung (Requirement) | Windows 11 25H2 (Build 26200) oder neuer, siehe [Windows-Version und PowerShell 7](#windows-version-und-powershell-7-ab-280). |
| Abhängigkeit | App „PowerShell 7“ (Automatisch installieren: Ja), siehe denselben Abschnitt. |

Erhöhen Sie bei jedem Release `Tool_Version` (`Sources\Tool_Config.xml`) und
`$ExpectedVersion` (`Detection.ps1`) auf denselben Wert. Lassen Sie sie unverändert,
findet Intune die alte Version, hält das Gerät für aktuell und installiert das neue
Paket nicht. `tools\New-SelfXIntuneWin.ps1` bricht ab, wenn die beiden Werte
voneinander abweichen.

**Release über GitHub (Tag, nur Entwurf).** Statt das Paket von Hand zu bauen, kann der Workflow
`.github/workflows/release.yml` es erzeugen: `Tool_Version` und `Detection.ps1` anpassen, mergen, dann den Tag
`v<Tool_Version>` (zum Beispiel `v2.8.1`) auf main setzen und pushen. Der Workflow bricht ab, wenn Tag und
`Tool_Version` nicht übereinstimmen. Er baut die Programme (`Bin`), das `.intunewin`
(`IntuneWinAppUtil.exe` in der festgelegten Version, Microsoft-Signatur wird geprüft), eine Stückliste
(`SelfX-Service-<Version>.sbom.cdx.json`, SBOM im Format CycloneDX; sie listet die Programme mit SHA-256 und die
NuGet-Pakete mit Version und Hash) und `SHA256SUMS.txt`. Er legt daraus einen **Entwurf** unter *Releases* an und
veröffentlicht nichts. Prüfen Sie den Entwurf, vergleichen Sie die SHA-256-Werte, laden Sie die `.intunewin` in
die Intune-Oberfläche (Microsoft Intune Admin Center > Apps > Windows > Hinzufügen > Windows-App (Win32)) hoch und
veröffentlichen Sie den Entwurf erst danach. Optional: Die Repository-Variable `INTUNEWINAPPUTIL_SHA256` legt den
Hash von `IntuneWinAppUtil.exe` fest; ohne sie gilt nur Tag plus Microsoft-Signatur. Eine GitHub Artifact
Attestation wird nicht verwendet.

`Uninstall.ps1` entfernt den Dienst, `%ProgramFiles%\SelfX`, die Verknüpfungen, den
Eintrag unter Apps & Features, den Autostart des Statussymbols (`SelfXTray`), den
Status-Cache (`%ProgramData%\SelfX\Cache`) und die Berichte mit Geräteprotokollen
(`%ProgramData%\SelfX\Reports`). Bevor es Dateien löscht, schließt es offene
SelfX-Fenster und Statussymbole aller angemeldeten Nutzer, weil diese den
Installationsordner in Benutzung halten. Vor Version 2.5.7 schlug die Deinstallation
in diesem Fall fehl. Nutzt ein anderes Programm noch eine Datei, zum Beispiel ein im
Installationsordner geöffnetes Explorer-Fenster, versucht der Deinstaller es bis zu
90 Sekunden lang erneut. Zwei Reste werden nicht als Fehler gemeldet:

- ein leerer Installationsordner, der noch in Benutzung ist,
- ein Dienst, der nur zum Löschen markiert ist, zum Beispiel weil die
  Dienste-Konsole geöffnet ist.

Das Ergebnis steht in `%ProgramData%\SelfX\Logs\Uninstall.log`. Protokolle bleiben
erhalten; mit `-RemoveLogs` wird auch `%ProgramData%\SelfX` gelöscht.
Einstellungen und Caches einzelner Nutzer (`HKCU\Software\SelfX`,
`%LOCALAPPDATA%\SelfX`) werden nicht entfernt.

> Erzwingt eine Gruppenrichtlinie die PowerShell-Ausführungsrichtlinie `AllSigned`,
> hat der Schalter `-ExecutionPolicy Bypass` keine Wirkung. Signieren Sie dann
> `Self_X.ps1`, `SelfXServiceClient.ps1`, `Branding.ps1`, `Localization.ps1`,
> `SystemInfo.ps1`, `HealthStatus.ps1`, `SupportReport.ps1`, `SelfX_Tray.ps1`,
> `SelfXLog.ps1`, alle Skripte der Gesundheitserweiterungen und alle Aktionsskripte
> (einschließlich `Collect-DeviceLogs.ps1`) mit einem vertrauenswürdigen
> Codesignatur-Zertifikat.

Führen Sie alle Tests von SelfX Service aus, bevor Sie ein Paket bauen (siehe die
[Release-Checkliste](#release-checkliste-selfx-service)). Jeder Test endet mit
Exitcode 1, wenn er einen Fehler findet; GitHub Actions führt dieselben Tests für
jeden Pull Request aus:

```powershell
Get-ChildItem '.\SelfX Service' -Filter 'Test-*.ps1' | ForEach-Object {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { Write-Warning "$($_.Name) failed" }
}
```

Nachdem Sie eine Sprachdatei geändert oder hinzugefügt haben, führen Sie nur die
Sprachprüfung aus: `& '.\SelfX Service\Test-LanguageFiles.ps1'` (optional mit
`-Culture <Code>`). Die Tests ersetzen die Befehle, die das Gerät verändern, durch
Mocks. `Test-ServicePipe.ps1` startet den Pipe-Listener des Dienstes im Testprozess
unter einem Test-Pipe-Namen; es wird nichts installiert und es sind keine
Administratorrechte nötig.

### Windows-Version und PowerShell 7 (ab 2.8.0)

Der Installer prüft beides, **bevor** er etwas auf dem Gerät ändert. Autopilot
installiert Apps in beliebiger Reihenfolge und darf nie an SelfX scheitern. Deshalb
ist ein fehlendes PowerShell 7 nur eine Warnung, ein unsicheres dagegen ein harter
Abbruch:

| Lage auf dem Gerät | Installer | Dienst |
|---|---|---|
| Windows älter als 25H2 (Build 26200) | Abbruch vor jeder Änderung, Exitcode 1. Eine vorhandene Installation bleibt unverändert. | nicht betroffen |
| PowerShell 7 fehlt oder ist älter als 7.6 | **Warnung** im Installationsprotokoll, die Installation läuft weiter | startet kein Skript und meldet den Grund. Er prüft vor **jedem** Skriptstart erneut, sodass SelfX nach der Installation von PowerShell 7 ohne weiteres Zutun arbeitet. |
| Der Ordner `%ProgramFiles%\PowerShell\7` oder `pwsh.exe` ist für normale Nutzer änderbar | Abbruch vor jeder Änderung, Exitcode 1 | startet nichts (der Dienst führt `pwsh.exe` als SYSTEM aus) |

Das Ergebnis steht in `%ProgramData%\SelfX\Logs\Install.log`.

**PowerShell 7 mit Intune verteilen**

1. Laden Sie die MSI-Datei (`PowerShell-7.6.x-win-x64.msi`) von Microsoft und
   verpacken Sie sie als **Win32-App**, nicht als Branchen-App (MSI). Die Mischung
   aus Branchen-App (MSI) und Win32-App bei Autopilot kann fehlschlagen, weil beide
   den Dienst TrustedInstaller nutzen.
2. Installationsbefehl, zum Beispiel:
   `msiexec.exe /package PowerShell-7.6.x-win-x64.msi /quiet DISABLE_TELEMETRY=1 USE_MU=0 ENABLE_MU=0`
   (keine Telemetrie, Updates nur über Intune). Den Installationsordner nicht
   ändern: SelfX nutzt den festen Pfad `%ProgramFiles%\PowerShell\7\pwsh.exe`.
   `ADD_PATH` ist nicht nötig. Prüfen Sie den Befehl vor der Verteilung auf einem
   Testgerät.
3. Erkennungsregel: Datei `%ProgramFiles%\PowerShell\7\pwsh.exe`, Dateiversion
   größer oder gleich 7.6.0.
4. Neue PowerShell-Versionen verteilen Sie als neue Version dieser App.

**SelfX mit PowerShell 7 verbinden**

- **Abhängigkeit (empfohlen).** In der SelfX-App unter *Abhängigkeiten* die App
  „PowerShell 7“ hinzufügen, *Automatisch installieren* = Ja (Standard). Intune
  installiert dann zuerst PowerShell 7. Schlägt das fehl, wird SelfX nicht
  installiert und Intune versucht es erneut (drei Versuche im Abstand von fünf
  Minuten, danach etwa alle 24 Stunden). Ohne Abhängigkeit installiert SelfX auch
  ohne PowerShell 7 (mit Warnung) und arbeitet, sobald PowerShell 7 da ist.
- **Autopilot und Statusseite (ESP).** Beide Apps als Win32-App einrichten. Nehmen
  Sie weder SelfX noch PowerShell 7 in die Liste der blockierenden Apps auf (ESP:
  *Block device use until these required apps are installed if they are assigned to
  the user/device* = *Selected*, ohne diese beiden Apps). Ein Fehler bei einer dieser Apps hält
  dann die Bereitstellung nicht auf. Wenn Sie PowerShell 7 trotzdem blockierend
  wollen, beachten Sie die Zeitbegrenzung der ESP (Standard 60 Minuten) und die
  Einstellung *Allow users to use device if installation error occurs*.
- **Voraussetzungsregel Windows 11 25H2.** Prüfen Sie im Portal, ob das
  Mindest-Betriebssystem „Windows 11 25H2“ zur Auswahl steht. Wenn nicht, legen Sie
  eine zusätzliche Voraussetzungsregel vom Typ *Skript* an: Ausgabedatentyp
  *Ganzzahl*, Operator *Größer oder gleich*, Wert `26200`, Skript:

  ```powershell
  [int](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber)
  ```

  Ältere Geräte erhalten die App dann nicht (statt eines Installationsfehlers).
- **Erkennung.** `Detection.ps1` bleibt wie bisher: Es erkennt SelfX nur bei exakt
  passender `Tool_Version` und registriertem Dienst. Für PowerShell 7 gilt die
  Erkennungsregel der PowerShell-App, nicht `Detection.ps1`.

### Ticket-Zuordnung: Werte per Intune setzen (ab 2.8.6)

Nur nötig, wenn die Ticket-Funktion (`Ticket_Enabled`) mit Regeln für Group-Tag oder Kategorie in `Ticket_Config.xml` genutzt wird (siehe [Konfiguration](Configuration.md#ticket-per-e-mail)). SelfX liest die Werte nur; sie stehen in `HKLM\SOFTWARE\SelfX\Support`: `GroupTag` und `Category` (je REG_SZ, bis 64 Zeichen: Buchstaben, Ziffern, Leerzeichen, `.`, `_`, `-`) sowie die Adressen `TicketMail` und `TicketCc` der zuständigen Einheit (je genau eine einfache Adresse; nur Funktionspostfächer, keine persönlichen Postfächer). Das Paket SelfX legt den Schlüssel nicht an. Hybrid-Geräte können zusätzlich nach der OU zugeordnet werden; dafür ist nichts zu setzen.

Beispiel mit einem Intune-Plattformskript (*Geräte > Skripte und Fehlerbehebungen > Plattformskripts*):
1. Das Skript unten je Einheit kopieren und die Werte oben anpassen (`TicketMail` ist der Empfänger der Einheit).
2. Einstellungen: *Dieses Skript mit den Anmeldeinformationen des angemeldeten Benutzers ausführen* = **Nein** (läuft als SYSTEM), *Skripthost in 64-Bit-PowerShell ausführen* = **Ja**.
3. Einer Entra-Gerätegruppe zuweisen, deren Mitglieder zu diesem Wert passen (zum Beispiel dynamische Gruppe nach Group-Tag oder Gerätekategorie). Das Skript ist wiederholbar: erneutes Ausführen setzt dieselben Werte. Es setzt immer alle vier Werte; wechselt ein Gerät in eine andere Gruppe, ersetzt das Skript der neuen Gruppe die Werte der alten. Die Gruppen sollten sich gegenseitig ausschließen, damit ein Gerät nur zu einem Skript gehört.
4. Bei vielen Einheiten: ein Skript je Einheit, oder ein Skript, das den Wert aus einer Tabelle nach Gerätename oder Gruppe wählt. Anzahl und Namen der Tags sind frei; sie müssen nur zu den Regeln in `Ticket_Config.xml` passen.
5. Kontrolle auf dem Gerät (lesend): `Get-ItemProperty 'HKLM:\SOFTWARE\SelfX\Support'`. Vor der Verteilung prüft `tools\Test-SelfXTicketRouting.ps1 -GroupTag ... -Category ...`, welche Einheit herauskommt.

Das Skript läuft in Windows PowerShell 5.1 und in PowerShell 7 und ändert nur diese vier Werte; ungültige Werte brechen ab, bevor etwas geschrieben wird.

```powershell
# Set-SelfXSupportUnit.ps1 (example) - sets the values SelfX reads for the ticket routing.
# Intune platform script: run as SYSTEM (not as the signed-in user), 64-bit, one copy per assignment.
# Use shared (functional) mailboxes only, no personal mailboxes.
$GroupTag   = 'DE-IT1-BER'          # optional, up to 64 characters: letters, digits, space, . _ -
$Category   = 'Category-A'          # optional, same rules
$TicketMail = 'it1-service@example.com'   # recipient of the ticket e-mail: exactly one plain address
$TicketCc   = ''                    # optional second address (needs TicketMail)
# An empty value removes the registry value. All four values are always set, so a script of a new
# group replaces what a script of the old group set when a device moves to another group.

$ErrorActionPreference = 'Stop'
$key = 'HKLM:\SOFTWARE\SelfX\Support'    # below HKLM\SOFTWARE: only administrators can write, users can only read
$tag = '^[A-Za-z0-9._ -]{1,64}\z'
$mail = '^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,}\z'
$values = [ordered]@{ GroupTag = @($GroupTag, $tag); Category = @($Category, $tag); TicketMail = @($TicketMail, $mail); TicketCc = @($TicketCc, $mail) }
foreach ($name in $values.Keys) {
    $value = ("$($values[$name][0])").Trim()
    if ($value -and $value -notmatch $values[$name][1]) { Write-Output "$name has an invalid value."; exit 1 }
}
foreach ($name in $values.Keys) {
    $value = ("$($values[$name][0])").Trim()
    if ($value) {
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -LiteralPath $key -Name $name -Value $value -PropertyType String -Force | Out-Null
    } elseif (Test-Path -LiteralPath $key) {
        Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue
    }
}
Write-Output 'SelfX support values set.'
exit 0
```

### Update: immer das ganze Paket verteilen

Verteilen Sie bei jedem Update das **gesamte Paket**, nie nur einzelne Dateien.
Der Installer baut den Dienst neu, und Oberfläche und Dienst müssen zusammenpassen.
Eine neue Oberfläche mit einem alten Dienst funktioniert nicht.

Folgende Versionen haben den Dienst oder den Installer geändert. Für sie gilt die
Regel besonders:

| Version | Neu | Was bei einem alten Dienst passiert |
|---|---|---|
| 2.3.0 bis 2.3.4 | Gesundheitsbericht (`HEALTH`), Positivliste der Reparaturen, Einzelprüfung, Defender-Signatur-Update | Der Dienst muss `HEALTH` und die neuen Prüfungen unterstützen. Nur die neue Oberfläche auf eine ältere Installation zu kopieren, genügt nicht. |
| 2.4.0 | Geräteprotokolle für den Support | Die Aktion endet mit Exitcode 2, weil der alte Dienst den anfragenden Nutzer nicht übergibt. Tragen Sie in `Tool_Config.xml` bei `Support_Mail` die Helpdesk-Adresse ein. |
| 2.5.0 | Neue Oberfläche, Hintergrundprüfungen mit Status-Cache (`STATUS`), Statussymbol | SelfX liest den Status mit `STATUS`, das ältere Dienste nicht kennen. |
| 2.6.0 | Protokollierung, Reparaturen Neustart und App-Wiederholung, Windows-Updates | Der Installer legt `Logs\Users` an, und der Dienst bereinigt die Protokolle. |
| 2.6.10 und 2.6.11 | Sicherheitshärtung (siehe [Änderungsprotokoll](../CHANGELOG.md)) | Erhöhen Sie `Tool_Version` und `$ExpectedVersion`. |

Prüfen Sie vor dem Paketieren:

- die Support-Kontakte des Hilfe-Dialogs in `Tool_Config.xml` (`Support_Hours`,
  `Support_Phone_number`, `Support_Mail`, `Support_Teams`, `Support_Website`),
- das Element `Background` in `Health_Config.xml`; siehe
  [Benutzeroberfläche](Configuration.md#benutzeroberfläche) und
  [Hintergrundprüfungen](Configuration.md#hintergrundprüfungen),
- `Sources\Health_Config.xml` und, falls Sie eigene nur lesende Prüfskripte
  verwenden, `Sources\HealthChecks`; siehe
  [Gesundheitsstatus](Configuration.md#gerätestatus).

SelfX Service braucht die MahApps.Metro-Assemblies nicht mehr. Geben Sie Nutzern
keinen Schreibzugriff auf den Installationsordner oder auf die Prüfskripte.

Installation prüfen:

```powershell
Get-Service SelfXService
Get-Content "$env:ProgramData\SelfX\Logs\SelfXService.log" -Tail 20   # als Administrator
```

### Release-Checkliste (SelfX Service)

1. Konfiguration anpassen: Branding und Support-Kontakte in
   `Sources\Tool_Config.xml`, `Sources\Health_Config.xml`, der Katalog.
2. `Tool_Version` in `Sources\Tool_Config.xml` erhöhen und denselben Wert als
   `$ExpectedVersion` in `Detection.ps1` setzen; in den Verlauf beider Dateien eine
   Zeile eintragen.
3. Alle Tests ausführen (siehe oben). Jeden Fehler beheben, bevor es weitergeht.
4. Die Programme mit `tools\Build-SelfXBinaries.ps1` bauen (Pflicht, siehe
   [Programme bauen](#programme-bauen-selfx-service-ab-270)) und, wenn Sie AppLocker
   nutzen, die Hashregeln aus `build\SelfX.AppLocker.xml` in die Richtlinie
   übernehmen. Ein neuer Build hat neue Hashes: Ersetzen Sie die Regeln des
   vorherigen Builds.
5. Das Paket mit `tools\New-SelfXIntuneWin.ps1` bauen (siehe
   [Intune-Paket erstellen](#intune-paket-erstellen)).
6. Auf einem Gerät testen, das nicht produktiv ist: Neuinstallation, Update von der
   vorherigen Version, Deinstallation, Erkennung. Als Standardnutzer testen und, wenn
   Sie gemeinsam genutzte Geräte haben, mit einem zweiten angemeldeten Nutzer.
   Zusätzlich (ab 2.8.0): Installation ohne PowerShell 7 (Warnung im Protokoll, der
   Dienst startet keine Skripte, nach der Installation von PowerShell 7 funktioniert
   SelfX ohne weiteres Zutun), mit änderbarem PowerShell-7-Ordner (Abbruch,
   Exitcode 1) und auf Windows 11 24H2 (Abbruch, Exitcode 1). Einen Autopilot-Lauf
   mit beiden Apps prüfen (die Bereitstellung darf nicht hängen).
7. Das Paket in Intune veröffentlichen.

### Programme bauen (SelfX Service ab 2.7.0)

`SelfXService.exe` (der Dienst) und `SelfX.exe` (der Starter) sind .NET-10-Programme.
Sie werden **einmal** auf einem Build-Rechner mit dem .NET SDK 10 gebaut und mit dem
Paket verteilt. So haben alle Geräte dieselben Dateien mit demselben Hash. AppLocker
oder WDAC können sie dann mit einer Hashregel zulassen, und auf den Geräten läuft
kein Compiler als SYSTEM. Der Befehl:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1
```

Das Skript prüft zuerst, ob das SDK 10 installiert ist, und baut dann die drei
Projekte aus `SelfX Service\Service\Projects` mit `dotnet publish`:

- Die Programme sind *self-contained* und bestehen aus einer Datei (je etwa 36 MB).
  Die .NET-Laufzeit steckt darin. Updates der Laufzeit kommen mit einer neuen
  SelfX-Version, nicht über Windows Update.
- Das einzige NuGet-Paket (`System.ServiceProcess.ServiceController` von Microsoft)
  ist in `packages.lock.json` mit Version und Hash festgelegt. Eine andere Version
  lässt den Bau scheitern.
- Der Bau ist reproduzierbar: Dieselben Quelltexte und dasselbe SDK ergeben
  dieselben Dateien. Die CI auf GitHub prüft das bei jedem Pull Request.

Das Skript schreibt `SelfX Service\Bin` (nicht eingecheckt): `SelfXService.exe`,
`SelfX.exe`, `SelfXSessionStarter.dll` (nur vom Installer verwendet) und das
Manifest `SelfX.Binaries.json` mit dem SHA256 der drei Quelltexte und der drei
Dateien (Manifestformat 2). Die Dateien sind nicht signiert. Sind auf dem
Build-Rechner die AppLocker-Cmdlets verfügbar, schreibt das Skript außerdem
`SelfX.AppLocker.xml` in den Ordner `build\` (nicht im Paket): Hashregeln für die
drei Dateien, bereit zum Zusammenführen mit Ihrer AppLocker-Richtlinie
(`Set-AppLockerPolicy -XmlPolicy ... -Merge` oder Import im Richtlinien-Editor / in
Intune). AppLocker verwendet einen eigenen Hash der Datei (Authenticode SHA256),
nicht den SHA256 des Manifests; übernehmen Sie die Regeln immer aus dieser Datei.
Bauen Sie danach das Intune-Paket; der Ordner `Bin` ist Teil davon.

`Install.ps1` verlangt `Bin` und prüft vor der Installation:

- der Ordner `Bin`, das Manifest und alle drei Dateien sind vorhanden;
- das Manifest hat das Format 2 (Pakete, die mit 2.6.x gebaut wurden, werden
  abgelehnt);
- die Quelltexte des Pakets (`Service\*.cs`) haben die Hashes des Manifests, die
  Programme wurden also aus genau diesen Quelltexten gebaut;
- jede Datei hat den Hash des Manifests.

Jede fehlgeschlagene Prüfung stoppt die Installation mit Exitcode `1`, **bevor** der
alte Dienst oder die alten Dateien angefasst werden. Der Grund steht in
`%ProgramData%\SelfX\Logs\Install.log`. `tools\New-SelfXIntuneWin.ps1` bricht ab,
wenn `Bin` fehlt oder nicht zu den Quelltexten passt, und packt die
.NET-Projektdateien nicht mit ein. Bauen Sie `Bin` nach jeder Änderung von
`Service\*.cs` neu und ersetzen Sie gleichzeitig die Hashregeln in AppLocker.

> **Hinweis zum Wechsel von 2.6.x:** Version 2.6.x hat den Dienst auf dem Gerät mit
> dem .NET Framework kompiliert. Ab 2.7.0 ist das nicht mehr möglich. Verteilen Sie
> immer das ganze Paket (siehe [Update: immer das ganze Paket
> verteilen](#update-immer-das-ganze-paket-verteilen)). Der Dienst startet die
> Skripte mit PowerShell 7 (ab 2.8.0, siehe [Windows-Version und PowerShell
> 7](#windows-version-und-powershell-7-ab-280)).

## Intune-Paket erstellen

`tools\New-SelfXIntuneWin.ps1` erstellt die `.intunewin`-Datei von SelfX Service im
Ordner `build` des Repositorys (der Ordner wird nicht eingecheckt, siehe
`.gitignore`). Es verwendet das
[Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
von Microsoft (`IntuneWinAppUtil.exe`); laden Sie die ausführbare Datei aus dem
offiziellen Repository herunter und übergeben Sie ihren Pfad mit `-ToolPath`. Das
Skript prüft die Authenticode-Signatur von Microsoft, bevor es die Datei startet.
Die ausführbare Datei liegt nicht in diesem Repository, und das Skript installiert
kein PowerShell-Paketierungsmodul.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1 `
  -ToolPath C:\Tools\IntuneWinAppUtil.exe
```

| Quellordner | Setup-Datei | Paket |
|---|---|---|
| `SelfX Service` | `Install.ps1` | `build\SelfX-Service-<Version>.intunewin` |

Die Version ist `Tool_Version` (`Sources\Tool_Config.xml`). Das Skript kopiert den
Ordner in einen temporären Staging-Ordner und lässt die Tests der Paketierung
(`Test-*.ps1`) weg. Vor dem Paketieren prüft es, dass die Setup-Datei existiert und
jede XML-Datei gültig ist. Außerdem prüft es, dass `$ExpectedVersion` in
`Detection.ps1` gleich `Tool_Version` ist. Mit `-ToolPath` prüft es die
Microsoft-Signatur von `IntuneWinAppUtil.exe`. Es lädt nichts nach Intune hoch.
Exitcode `0` bedeutet, dass das Paket erstellt wurde; `1`, dass es fehlgeschlagen
ist. Führen Sie vor dem Bauen die Tests von SelfX Service aus.

Verwenden Sie das Paket in Intune wie folgt:

| Installationsbefehl | Installationsverhalten | Deinstallation / Erkennung |
|---|---|---|
| `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` | System | `Uninstall.ps1`, benutzerdefiniertes Skript `Detection.ps1` (siehe [SelfX Service](#selfx-service)) |

## Dateiliste (SelfX.Files.json)

`tools\New-SelfXIntuneWin.ps1` schreibt beim Paketbau die Datei `SelfX.Files.json` in das Paket. Sie enthält den
SHA256 jeder Datei, die `Install.ps1` in den Installationsordner kopiert (alles unter `Sources` und `Uninstall.ps1`).
Die Liste wird bei jedem Paketbau neu erzeugt: Wer ein Skript oder eine Konfiguration ändert, muss nichts von Hand
nachpflegen, sondern das Paket neu bauen. `Install.ps1` prüft vor der Installation, dass jede Datei zur Liste passt
und keine Datei ohne Eintrag im Paket liegt; sonst bricht die Installation ab, bevor etwas geändert wird (die
bestehende Installation bleibt unberührt). Fehlt die Liste (älteres Paket), gibt es nur eine Warnung. Die Liste wird
auch im Installationsordner abgelegt: Der Dienst prüft vor **jedem** Start (Aktion, Health-Check, Hintergrundprüfung),
dass alle gelisteten Dateien unverändert sind, dass kein Skript und keine XML-Datei ohne Eintrag im Installationsordner
liegt und dass keine Verknüpfung (Junction, Symlink) im Weg ist. Bei einer Abweichung startet er nichts, schreibt
Ereignis 4005 und die Einzelheiten ins SelfX-Protokoll; die Installation selbst ist nie betroffen (Autopilot läuft
unverändert). Fehlt die Liste im Installationsordner, gilt das ebenfalls als Abweichung. Für den ersten Rollout kann
`Service_FileCheck` auf `Audit` gestellt werden (nur protokollieren). `Bin` hat weiterhin die eigene Liste
`SelfX.Binaries.json`.

## App Control for Business (WDAC), optional

SelfX braucht WDAC nicht und im Paket ist nichts davon eingeschaltet. Wer App Control for Business (früher WDAC)
einsetzt, kann damit zusätzlich zur Dateiliste verhindern, dass auf den Geräten andere als die ausgelieferten
SelfX-Programme und -Skripte laufen. SelfX bleibt unsigniert und wird per Hash zugelassen (keine eigenen Zertifikate).

1. **Basisrichtlinie.** Sie gehört Ihrer Organisation. Sie muss ergänzende Richtlinien erlauben (Regeloption 17,
   „Allow Supplemental Policies“) und die von Microsoft signierten Dateien zulassen, darunter PowerShell 7
   (`%ProgramFiles%\PowerShell\7\pwsh.exe`) und den Intune-Agenten.
2. **Paket bauen** (Programme, dann `New-SelfXIntuneWin.ps1`), siehe oben.
3. **Ergänzende Richtlinie erzeugen** in Windows PowerShell 5.1 auf einem Administrator-PC (Modul ConfigCI):
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXWdacPolicy.ps1 -BasePolicyId {GUID der Basisrichtlinie}`.
   Das Skript legt in `build\wdac` die XML-Datei und die `.cip`-Datei ab. Sie enthält Hashregeln für alle Programme,
   Bibliotheken und Skripte des Pakets, auch für `Install.ps1`, `Detection.ps1` und `Uninstall.ps1`. Sie ändert nichts
   auf dem PC.
4. **Verteilen** mit Intune (Richtlinie für App Control for Business bzw. ApplicationControl-CSP) an dieselben Geräte
   wie das SelfX-Paket.
5. **Erst im Überwachungsmodus.** Ob die Richtlinien im Überwachungs- oder im Erzwingungsmodus laufen, bestimmt die
   **Basisrichtlinie** (Regeloption 3, „Audit Mode“); die ergänzende Richtlinie legt das nicht fest. Im
   Überwachungsmodus läuft alles weiter, und Windows protokolliert, was die Richtlinie blockieren würde (Protokoll
   `Microsoft-Windows-CodeIntegrity/Operational`, Ereignis 3076). Prüfen Sie auf einem Testgerät, dass für SelfX
   (Installation per Autopilot und ESP, Oberfläche, Statussymbol, alle Aktionen als Nutzer und als SYSTEM, Update,
   Deinstallation) kein Ereignis entsteht. Erst dann nimmt die Organisation die Option 3 aus der Basisrichtlinie.
6. **Bei jeder neuen Version** die ergänzende Richtlinie neu erzeugen und mit dem Paket verteilen: Jede Änderung an
   einem Skript ändert seinen Hash. Mit der festen Richtlinien-ID ersetzt die neue die alte; Geräte mit der alten
   SelfX-Version würden im Erzwingungsmodus dann blockiert. Für gestaffelte Rollouts erzeugen Sie die Richtlinie mit
   `-PolicyId {neue GUID}` pro Version und entfernen die alte Richtlinie, wenn alle Geräte aktualisiert sind.

Hinweise: Die Richtlinie muss vor dem Paket auf dem Gerät sein (Autopilot: dieselbe Zuweisung, im Überwachungsmodus
testen, bevor erzwungen wird). SelfX-Skripte verwenden `Add-Type` für einzelne P/Invoke-Aufrufe; die Regeloption 19
(„Dynamic Code Security“) darf nur nach einem Test im Überwachungsmodus eingeschaltet werden. Eine unsignierte
Richtlinie kann ein lokaler Administrator ersetzen; ob sie signiert wird, entscheidet die Organisation. Die Vorlage ist
noch nicht auf einem Gerät erprobt.

## Ausführungsrichtlinie (`-ExecutionPolicy Bypass`)

Dienst, Starter, Fenster, Statussymbol und Health-Check starten PowerShell mit `-ExecutionPolicy Bypass`. Das ist
gewollt und vertretbar, weil die Skripte im geschützten Installationsordner liegen (nur Administratoren und SYSTEM
dürfen schreiben, geprüft durch `Install.ps1`, die Dateiliste und den Dienst). Die Ausführungsrichtlinie ist ohnehin
keine Sicherheitsgrenze: Jeder Nutzer kann sie mit `-ExecutionPolicy Bypass` umgehen. Zusätzlichen Schutz bieten nur
die Dateiliste (`SelfX.Files.json`, der Dienst startet nichts Abweichendes) und App Control for Business (siehe oben).
Erzwingt Ihre Organisation `AllSigned` per Gruppenrichtlinie, gilt der Hinweis zum Signieren im Abschnitt
[SelfX Service](#selfx-service). Ein eigenes Signaturkonzept gibt es nicht: SelfX bleibt unsigniert und wird per Hash
zugelassen.

## Rechte des Dienstes

Der Dienst läuft als LocalSystem. `Install.ps1` begrenzt sein Token mit `sc.exe privs` auf die Rechte, die die
Aktionen brauchen (Einstellung `Service_Privileges` in `Tool_Config.xml`, Standard `Restricted`). Der Dienst und alle
Skripte, die er startet, können die übrigen Rechte von LocalSystem dann nicht nutzen, zum Beispiel
`SeTcbPrivilege`, `SeDebugPrivilege`, `SeCreateTokenPrivilege`, `SeLoadDriverPrivilege` und `SeSecurityPrivilege`.

| Recht | Wofür |
|---|---|
| `SeChangeNotifyPrivilege` | jeder Prozess |
| `SeImpersonatePrivilege` | Pipe-Client prüfen |
| `SeCreateGlobalPrivilege` | globale Objekte des Dienstes |
| `SeShutdownPrivilege` | Aktion Neustart (`shutdown.exe`) |
| `SeSystemtimePrivilege` | Zeit synchronisieren |
| `SeBackupPrivilege`, `SeRestorePrivilege`, `SeTakeOwnershipPrivilege` | Dateireparaturen (zum Beispiel Spooler) |
| `SeManageVolumePrivilege` | Datenträgerprüfung |

Prüfen: `sc.exe qprivs SelfXService` zeigt die gesetzte Liste. Schlägt das Setzen fehl, meldet `Install.ps1` eine
Warnung und der Dienst behält die Standardrechte; die Installation (Autopilot) scheitert deshalb nie. Mit
`Service_Privileges` = `Default` bleiben alle LocalSystem-Rechte; das ist nur zur Fehlersuche gedacht. Testen Sie
vor der Verteilung jede System-Aktion einmal auf einem Testgerät (Checkliste in der Dokumentation der Gerätetests).

## Checkliste für die Bereitstellung

1. Die XML-Aktionsliste und jedes referenzierte `.ps1`-Skript prüfen.
2. Als System installieren (der Installer braucht Administratorrechte).
3. Die Oberfläche und jede vorgesehene Aktion auf einem nicht produktiven Gerät
   testen.
4. Statussymbol und Fenster als Standardnutzer prüfen (ohne Administratorrechte).
5. Das vollständige Paket zusammenhalten; keine Symbole, XML-, XAML- oder
   Aktionsskripte weglassen.
6. Der [Release-Checkliste](#release-checkliste-selfx-service) folgen.
