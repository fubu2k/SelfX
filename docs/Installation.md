# Installation

[English](en/Installation.md) | **Deutsch**

Diese Anleitung beschreibt die Installation von **SelfX Service** auf verwalteten
Windows-Geräten, insbesondere mit Microsoft Intune.

## Voraussetzungen

- Ein unterstützter Windows-Desktop mit Windows PowerShell und WPF.
- Das vollständige Paketverzeichnis, einschließlich der Inhalte von `assembly` und
  `Scripts_to_run`.
- Für SelfX Service: 64-Bit-Windows-PowerShell 5.1 und .NET Framework 4.x. Der
  Installer installiert entweder die vorkompilierten Programme des Pakets (Ordner
  `Bin`, siehe [Vorkompilierte Programme](#vorkompilierte-programme-selfx-service-2611))
  oder kompiliert den Dienst mit dem C#-Compiler, der zum .NET Framework gehört.
  Ein Internetzugang oder ein SDK ist nicht nötig.

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
   `%ProgramFiles%\SelfX\SelfX.exe` (2.5.3). Enthält das Paket den Ordner `Bin`,
   prüft der Installer zuerst die vorkompilierten Programme gegen ihr
   SHA256-Manifest und kopiert sie (2.6.11); eine fehlgeschlagene Prüfung stoppt
   die Installation. Ohne `Bin` kompiliert er `Service\SelfXService.cs` und
   `Service\SelfXLauncher.cs`; der Compiler schreibt seine temporären Dateien dann
   in einen Ordner unterhalb des Installationsordners, nicht nach `C:\Windows\Temp`.
   `SelfX.exe` ist ein kleiner Starter ohne Konsole: Er startet SelfX
   (`/page:<Seite>` optional) oder das Statussymbol (`/tray`) mit einer
   versteckten Windows PowerShell, sodass kein Befehlsfenster erscheint, auch nicht
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
[Protokollierung](Configuration.md#protokollierung-und-aufbewahrung-selfx-service-260).

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

Erhöhen Sie bei jedem Release `Tool_Version` (`Sources\Tool_Config.xml`) und
`$ExpectedVersion` (`Detection.ps1`) auf denselben Wert. Lassen Sie sie unverändert,
findet Intune die alte Version, hält das Gerät für aktuell und installiert das neue
Paket nicht. `tools\New-SelfXIntuneWin.ps1` bricht ab, wenn die beiden Werte
voneinander abweichen.

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
  [Benutzeroberfläche](Configuration.md#benutzeroberfläche-selfx-service-250) und
  [Hintergrundprüfungen](Configuration.md#hintergrundprüfungen-und-status-cache-selfx-service-250),
- `Sources\Health_Config.xml` und, falls Sie eigene nur lesende Prüfskripte
  verwenden, `Sources\HealthChecks`; siehe
  [Gesundheitsstatus](Configuration.md#gesundheitsstatus-selfx-service-230).

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
4. Optional: die vorkompilierten Programme mit `tools\Build-SelfXBinaries.ps1` bauen
   (siehe unten) und die Hashregeln aus `build\SelfX.AppLocker.xml` in die
   AppLocker-Richtlinie übernehmen. Ein neuer Build hat neue Hashes: Ersetzen Sie
   die Regeln des vorherigen Builds.
5. Das Paket mit `tools\New-SelfXIntuneWin.ps1` bauen (siehe
   [Intune-Paket erstellen](#intune-paket-erstellen)).
6. Auf einem Gerät testen, das nicht produktiv ist: Neuinstallation, Update von der
   vorherigen Version, Deinstallation, Erkennung. Als Standardnutzer testen und, wenn
   Sie gemeinsam genutzte Geräte haben, mit einem zweiten angemeldeten Nutzer.
7. Das Paket in Intune veröffentlichen.

### Vorkompilierte Programme (SelfX Service 2.6.11)

Ohne weitere Schritte kompiliert `Install.ps1` `SelfXService.exe` und `SelfX.exe`
auf jedem Gerät. Die Dateien haben dann auf jedem Gerät einen anderen Hash, sodass
AppLocker oder WDAC sie nicht mit einer Hashregel zulassen können. Bauen Sie sie
stattdessen einmal auf einem Build-Rechner mit Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1
```

Das Skript schreibt `SelfX Service\Bin` (nicht eingecheckt): `SelfXService.exe`,
`SelfX.exe`, `SelfXSessionStarter.dll` (nur vom Installer verwendet) und das
Manifest `SelfX.Binaries.json` mit dem SHA256 der drei Quellen und der drei
Dateien. Die Dateien sind nicht signiert. Sind auf dem Build-Rechner die
AppLocker-Cmdlets verfügbar, schreibt das Skript außerdem `SelfX.AppLocker.xml`
neben den Ordner `Bin` (in `build\`, nicht im Paket): Hashregeln für die drei
Dateien, bereit zum Zusammenführen mit Ihrer AppLocker-Richtlinie
(`Set-AppLockerPolicy -XmlPolicy ... -Merge` oder Import im Richtlinien-Editor /
in Intune). AppLocker verwendet einen eigenen Hash der Datei (Authenticode SHA256),
nicht den SHA256 des Manifests; übernehmen Sie die Regeln immer aus dieser Datei.
Bauen Sie danach das Intune-Paket; der Ordner `Bin` ist Teil davon.

Enthält das Paket `Bin`, prüft `Install.ps1` vor der Installation:

- das Manifest und alle drei Dateien sind vorhanden;
- die Quellen des Pakets (`Service\*.cs`) haben die Hashes des Manifests, die
  Programme wurden also aus genau diesen Quellen gebaut;
- jede Datei hat den Hash des Manifests.

Jede fehlgeschlagene Prüfung stoppt die Installation mit Exitcode `1`; stattdessen
wird nichts kompiliert. Der Grund steht in `%ProgramData%\SelfX\Logs\Install.log`.
Ohne `Bin` kompiliert das Gerät wie bisher; die temporären Dateien des Compilers
werden dann in einen Ordner unterhalb des Installationsordners statt nach
`C:\Windows\Temp` geschrieben. `tools\New-SelfXIntuneWin.ps1` weigert sich, einen
Ordner `Bin` zu paketieren, der aus anderen Quellen gebaut wurde. Bauen Sie `Bin`
nach jeder Änderung von `Service\*.cs` neu und ersetzen Sie gleichzeitig die
Hashregeln in AppLocker: Ein neuer Build hat neue Hashes, die alten Regeln passen
nicht mehr.

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

## Checkliste für die Bereitstellung

1. Die XML-Aktionsliste und jedes referenzierte `.ps1`-Skript prüfen.
2. Als System installieren (der Installer braucht Administratorrechte).
3. Die Oberfläche und jede vorgesehene Aktion auf einem nicht produktiven Gerät
   testen.
4. Statussymbol und Fenster als Standardnutzer prüfen (ohne Administratorrechte).
5. Das vollständige Paket zusammenhalten; keine Symbole, XML-, XAML- oder
   Aktionsskripte weglassen.
6. Der [Release-Checkliste](#release-checkliste-selfx-service) folgen.
