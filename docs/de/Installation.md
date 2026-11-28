# Installation

[English](../Installation.md) | **Deutsch**

Diese Anleitung zeigt Schritt für Schritt, wie Sie **SelfX Service** bauen, mit
Microsoft Intune verteilen und prüfen. Sie ist für Administratoren geschrieben. Sie
brauchen keine Programmierkenntnisse.

![SelfX 3.0 mit dem neuen Design: Seite Fehlerbehebung](../images/selfx-troubleshooting-light.png)

*Das neue Design von SelfX 3.0: ruhige Farben, runde Karten, große Schaltflächen und ein
Drei-Schritte-Hinweis („Problem auswählen – Bestätigen – Fertig“). Es gibt ein helles und
ein dunkles Design; SelfX folgt der Windows-Einstellung.*

## Inhalt

1. [Das Wichtigste in Kürze](#das-wichtigste-in-kürze)
2. [Voraussetzungen](#voraussetzungen)
3. [Schritt 1: Build-Rechner einmal vorbereiten](#schritt-1-build-rechner-einmal-vorbereiten)
4. [Schritt 2: Paket bauen](#schritt-2-paket-bauen)
5. [Schritt 3: In Intune einrichten](#schritt-3-in-intune-einrichten)
6. [Schritt 4: Testen](#schritt-4-testen)
7. [Update auf eine neue Version](#update-auf-eine-neue-version)
8. [Deinstallation](#deinstallation)
9. [Optionale Bausteine](#optionale-bausteine)
10. [Hintergrund: Was die Installation macht](#hintergrund-was-die-installation-macht)
11. [Fehlerbehebung](#fehlerbehebung)
12. [Checkliste für die Bereitstellung](#checkliste-für-die-bereitstellung)

## Das Wichtigste in Kürze

- SelfX Service wird **einmal pro Gerät** installiert und arbeitet ohne Internet.
- Sie bauen das Paket **auf einem Build-Rechner**. Auf den Geräten wird nichts
  kompiliert.
- Auf den Geräten müssen **Windows 11 25H2** (Build 26200 oder neuer) und
  **PowerShell 7.6 oder neuer** vorhanden sein. Terminalserver mit **Windows Server 2022 oder 2025**
  werden ebenfalls unterstützt; sie werden ohne Intune installiert (siehe
  [Windows Server](#windows-server-terminalserver)).
- Verteilt wird immer das **ganze Paket**, nie einzelne Dateien.
- Die Versionsnummer in `SelfX Service\Version.txt` und der Wert `$ExpectedVersion` in
  `Detection.ps1` müssen **gleich** sein. Sonst erkennt Intune das Update nicht. Die Version
  ist eine Eigenschaft des Codes: Der Bau schreibt sie in `SelfX.Code.json`; die
  Einstellungsdatei `Tool_Config.xml` enthält sie nicht.
- Fehlt PowerShell 7, wird SelfX trotzdem installiert. So bleibt Autopilot ungestört.

## Voraussetzungen

**Auf den Geräten:**

| Voraussetzung | Einzelheiten |
|---|---|
| Windows 11 25H2 (Build 26200) oder neuer, 64 Bit, oder Windows Server 2022 oder 2025 mit Desktopdarstellung (Build 20348 oder neuer) | Auf älteren Versionen, auf Server Core, auf einem Domänencontroller und auf Windows Enterprise multi-session bricht der Installer ab, bevor er etwas ändert. Auf Windows Server arbeitet SelfX wie auf einem Terminalserver. |
| PowerShell 7.6 oder neuer | Für alle Nutzer installiert (MSI von Microsoft), Pfad `%ProgramFiles%\PowerShell\7\pwsh.exe`. Die Store-Variante (MSIX) geht nicht. |
| Windows PowerShell 5.1 | Ist in Windows enthalten. SelfX nutzt sie nur für `Install.ps1`, `Uninstall.ps1`, `Detection.ps1` und `Collect-DeviceLogs.ps1`. |
| .NET | **Nicht nötig.** Dienst und Starter bringen alles selbst mit. |

**Auf dem Build-Rechner (nicht auf den Geräten):**

| Voraussetzung | Einzelheiten |
|---|---|
| Windows-Rechner | Ein normaler Administrator-Arbeitsplatz reicht. **Kein Internet nötig** (siehe „Offline-Build“). |
| .NET SDK 10 | „SDK“, nicht nur „Runtime“. Dieselbe Version wie beim Export des Ordners `offline-feed`. |
| `IntuneWinAppUtil.exe` | Das Win32 Content Prep Tool von Microsoft. |
| Das SelfX-Repository | `git clone` oder ZIP von GitHub, einschließlich des Ordners `offline-feed` (NuGet-Pakete mit Hashliste). |

## Schritt 1: Build-Rechner einmal vorbereiten

Auf dem Build-Rechner wird nichts aus dem Internet geladen. Alles Nötige kommt aus dem Repository oder aus Ihrer eigenen Softwareverteilung.

1. Installieren Sie das **.NET SDK 10** aus Ihrer Softwareverteilung. Die Version muss zu der passen, mit der der Ordner `offline-feed` erzeugt wurde (siehe „Offline-Build“ unten).
2. Öffnen Sie ein **neues** PowerShell-Fenster und prüfen Sie die Version:

   ```powershell
   dotnet --version
   ```

   Die Ausgabe muss mit `10.` beginnen.
3. Legen Sie `IntuneWinAppUtil.exe` (Win32 Content Prep Tool von Microsoft) in einen Ordner, zum Beispiel `C:\Tools\IntuneWinAppUtil.exe`, und merken Sie sich den Pfad. Die Datei laden Sie auf einem Rechner **mit** Internet aus dem offiziellen Repository <https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool> und übertragen sie auf den Build-Rechner. Das Paketskript prüft die Microsoft-Signatur.
4. Kopieren Sie das Repository **einschließlich des Ordners `offline-feed`** auf den Build-Rechner, zum Beispiel als ZIP-Datei oder über einen Datenträger.

## Schritt 2: Paket bauen

> **Einfacher mit dem Assistenten:** `tools\Start-SelfXPackageWizard.cmd` (Fenster) oder `tools\New-SelfXPackage.ps1` (Konsole) stellt Fragen mit Empfehlungen, baut das Paket danach
> in einem Lauf (Einstellungen, Logo, optional Signatur, Verpacken, Erkennungsskript, AppLocker- und App-Control-Dateien) und erklärt die
> Schritte in Intune. Er arbeitet mit dem entpackten **Nutzlast-Archiv** eines Release, das .NET SDK ist also nicht nötig. Siehe
> [Paketassistent](Assistent.md). Die folgenden Schritte zeigen den manuellen Weg.

Wiederholen Sie diesen Schritt bei jeder neuen Version. Öffnen Sie PowerShell im Ordner
des Repositorys.

1. **Einstellungen anpassen.** Branding, Support-Kontakte und Funktionen stehen in
   `SelfX Service\Sources\Tool_Config.xml` (siehe [Konfiguration](Configuration.md)).
2. **Versionsnummer prüfen.** Bei einem neuen Release tragen Sie dieselbe Nummer an zwei
   Stellen ein:
   - `SelfX Service\Version.txt` (eine Zeile, zum Beispiel `3.0.3`)
   - `$ExpectedVersion` in `Detection.ps1`

   Das Paketskript bricht ab, wenn beide Werte verschieden sind. Eine geänderte Einstellung
   (zum Beispiel ein Logo) ändert die Version nicht, und eine neue Version ändert keine
   Einstellungsdatei.
3. **Programme bauen.** Der Befehl erzeugt den Ordner `SelfX Service\Bin`:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-SelfXBinaries.ps1
   ```

   Am Ende zeigt das Skript die gebauten Dateien mit ihrem Hash. Der Bau braucht kein
   Internet: Alle NuGet-Pakete kommen aus dem Ordner `offline-feed` und werden vorher gegen
   `SelfX.OfflineFeed.json` geprüft (siehe „Offline-Build“ unten).
4. **AppLocker anpassen** (nur wenn Sie AppLocker nutzen). Das Skript schreibt
   `build\SelfX.AppLocker.xml`. Übernehmen Sie diese Regeln und löschen Sie die Regeln der
   vorherigen Version, bevor das Paket die Geräte erreicht. Für ein **signiertes** Paket nehmen
   Sie stattdessen Herausgeberregeln, die Sie einmal einrichten
   ([Einmal einrichten statt je Version](#einmal-einrichten-statt-je-version)).
5. **Intune-Paket erstellen.** Setzen Sie bei `-ToolPath` den Pfad aus Schritt 1:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1 -ToolPath C:\Tools\IntuneWinAppUtil.exe
   ```

Ergebnis im Ordner `build`:

| Datei | Wofür |
|---|---|
| `SelfX-Service-<Version>.intunewin` | Das Paket für Intune. |
| `SelfX-Service-<Version>.Detection.ps1` | Das Erkennungsskript für Intune. Laden Sie **diese** Datei hoch, nicht die Kopie im Repository. |

Das Skript prüft vorher: Die Setup-Datei ist da, alle XML-Dateien sind gültig, `Bin` passt
zu den Quelltexten, die beiden Versionen sind gleich und `IntuneWinAppUtil.exe` hat die
Microsoft-Signatur. Es lädt nichts nach Intune hoch.

**Alternative: Release auf GitHub.** Benennen Sie nach dem Merge `## Unveröffentlicht` in `CHANGELOG.md` und `## Unreleased` in
`CHANGELOG.en.md` in `## <Version> - <Datum>` um und setzen Sie das Tag `v<Version>` (die Nummer aus `Version.txt`, zum Beispiel
`v3.1.0`) auf `main`. Der Workflow `.github/workflows/release.yml` erledigt dann in einem Lauf:

1. Er prüft, ob Tag und `Version.txt` übereinstimmen und ob `CHANGELOG.en.md` einen Abschnitt für die Version hat. Dieser Abschnitt
   ist die Beschreibung des Releases, dazu kommt ein fester Block "Files and how to verify".
2. Er baut die Programme und die Dateien der Tabelle unten.
3. Er führt alle Tests des CI-Workflows (`service-ci.yml`) für den getaggten Commit aus.
4. Er prüft die Dateien gegen `SHA256SUMS.txt` (genau diese Dateien, jeder Hash), im Build und noch einmal im veröffentlichenden Job, bevor er sie hochlädt.
5. Er veröffentlicht das Release.

Schlägt ein Schritt fehl, entsteht kein Release. Ein zweiter Lauf für dasselbe Tag fasst ein vorhandenes Release nicht an.

| Datei | Zweck |
|---|---|
| `SelfX-Service-<Version>.intunewin` | Das Paket für Intune mit der Standardkonfiguration, für Tests. |
| `SelfX-Service-<Version>.Detection.ps1` | Das Erkennungsskript dieses Pakets. |
| `SelfX-Service-<Version>-payload.zip` | Das Nutzlast-Archiv: der Paketordner, wie er gepackt wird (`Install.ps1`, `Uninstall.ps1`, `Detection.ps1`, `Bin`, `App` mit `SelfX.Code.json`, `Config` mit der Standardkonfiguration und `SelfX.Config.json`, `Service`), der Paketassistent und die Skripte, die er aufruft (`tools`), `LICENSE.md`, `NOTICE.md`, `NOTICE.en.md`. Damit konfigurieren und packen Sie SelfX für Ihre Firma ohne .NET SDK. |
| `SelfX-Service-<Version>.sbom.cdx.json` | Stückliste (SBOM). |
| `SHA256SUMS.txt` | SHA-256 aller anderen Dateien. Die Release-Notes zeigen einen Befehl zur Prüfung. |

Zwei Repository-Variablen (Settings, Secrets and variables, Actions, *Variables*) ändern das Verhalten:

- `RELEASE_DRAFT` = `true` legt einen Entwurf statt eines veröffentlichten Releases an (nach der Prüfung der Dateien von Hand veröffentlichen).
- `RELEASE_ATTEST` = `false` schaltet die Herkunftsbestätigung (Build Provenance) des Nutzlast-Archivs ab. Ohne die Variable wird sie
  erstellt (`gh attestation verify <Datei> --repo <Besitzer>/<Repository>` prüft sie).

**Den Workflow ohne Release ausprobieren.** Setzen Sie `RELEASE_DRAFT` auf `true`. Tragen Sie auf einem Branch, den Sie nicht mergen, eine
Version ein, die es nicht gibt (zum Beispiel `9.9.9`): in `SelfX Service\Version.txt`, in `$ExpectedVersion` von `Detection.ps1` und als
Abschnitt `## 9.9.9` in `CHANGELOG.en.md`, und pushen Sie das Tag `v9.9.9` auf diesen Commit. Prüfen Sie nach dem Lauf den Entwurf und das
Protokoll, löschen Sie dann Entwurf, Tag und Branch und setzen Sie `RELEASE_DRAFT` zurück.

### Offline-Build: Paketordner erneuern

Der Bau lädt **nichts** aus dem Internet. `NuGet.config` im Repository erlaubt nur den Ordner `offline-feed` als
Paketquelle. `Build-SelfXBinaries.ps1` prüft den Ordner vor jedem Bau gegen `offline-feed\SelfX.OfflineFeed.json`
(SHA512 je Paket), baut mit einem frischen Paketcache `.nuget-cache` im Repository und bricht ab, wenn ein Paket fehlt,
verändert wurde oder zusätzlich im Ordner liegt. Der Build-Rechner braucht deshalb nur das .NET SDK 10 (aus Ihrer
Softwareverteilung), `IntuneWinAppUtil.exe` und das Repository **mit** dem Ordner `offline-feed`.

Den Ordner erneuern Sie nur bei einer **neuen SDK-Version** (das Runtime-Paket gehört zur SDK-Version; der Bau meldet es,
wenn die Versionen nicht passen) oder bei einem **neuen oder aktualisierten Paket**:

1. Öffnen Sie einen Rechner **mit Internet** und **demselben .NET SDK 10** wie der Build-Rechner.
2. Führen Sie aus:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-SelfXOfflineFeed.ps1
   ```

   Das Skript lädt die Pakete von nuget.org in einen leeren Zwischenordner, lässt die NuGet-Schwachstellenprüfung laufen
   (bei einer Meldung bricht es ab; nach eigener Prüfung geht `-AllowVulnerabilities`), prüft, dass alle Pakete der
   `packages.lock.json` vorhanden sind, schreibt `offline-feed` neu und stellt zur Kontrolle alle Projekte nur aus diesem Ordner
   wieder her (ohne Internet, leerer Cache, Lock-Dateien erzwungen).
3. **Beim ersten Mal:** Die Pakete, die in keiner Lock-Datei stehen (Runtime-Paket, Windows-SDK-Projektion), sind nur durch
   die Hashliste festgelegt. Führen Sie den Export zur Kontrolle auf einem zweiten Rechner aus; die Hashes in
   `SelfX.OfflineFeed.json` müssen übereinstimmen.
4. Prüfen Sie `git diff`, checken Sie den Ordner ein und kopieren Sie das Repository auf den Build-Rechner.
5. **Test ohne Internet:** Trennen Sie den Build-Rechner vom Netz und führen Sie Schritt 2.3 aus. Der Bau muss ohne
   Fehlermeldung durchlaufen.

Dependabot-Vorschläge für NuGet-Pakete ändern den Ordner nicht: Nach einer Übernahme den Export wiederholen.

## Schritt 3: In Intune einrichten

Öffnen Sie das Microsoft Intune Admin Center: *Apps > Windows > Hinzufügen > Windows-App
(Win32)*. Laden Sie die Datei `SelfX-Service-<Version>.intunewin` hoch.

### 3.1 App-Einstellungen

| Einstellung | Wert |
|---|---|
| Installationsbefehl | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Deinstallationsbefehl | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Installationsverhalten | System |
| Erkennungsregel | Benutzerdefiniertes Skript: `SelfX-Service-<Version>.Detection.ps1` aus dem Ordner `build` |
| Voraussetzung (Requirement) | Windows 11 25H2, siehe 3.3 |
| Abhängigkeit | App „PowerShell 7“, *Automatisch installieren* = Ja, siehe 3.2 |

Die Erkennung meldet „installiert“ nur, wenn Version, registrierter Dienst, Dateiliste **und**
Vertrauensanker (`HKLM\SOFTWARE\SelfX\Trust`, von `Install.ps1` geschrieben) passen. So wird auch
ein Update mit geänderten Dateien, aber gleicher Versionsnummer, erkannt. Eine Installation einer
Version ohne Anker wird nicht erkannt und einmal erneut installiert.

#### Optional: signiertes Paket (Vertrauensmodus Signatur)

Für ein Paket, dessen Dateien mit dem Codesignatur-Zertifikat des Unternehmens signiert sind,
kommt der Fingerabdruck des Signaturzertifikats in den Installationsbefehl:

`%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -TrustedSigner <Fingerabdruck>`

- Der Fingerabdruck ist der SHA1-Fingerabdruck des **Signaturzertifikats** (40 Hexadezimalzeichen,
  ohne Leerzeichen), nicht der der Zertifizierungsstelle. Mehrere Fingerabdrücke werden durch
  Kommas ohne Leerzeichen getrennt (`-TrustedSigner <alt>,<neu>`); so lässt sich ein erneuertes
  Zertifikat schon vor dem Wechsel erlauben.
- `Install.ps1` installiert dann nur, wenn jedes Programm und jedes Skript des Pakets von einem
  dieser Zertifikate signiert ist und die beiden signierten Kataloge (`Config\SelfX.Config.cat`,
  `SelfX.Code.cat`) zum Paket passen. Andernfalls bricht es vor jeder Änderung am Gerät ab
  ([Architektur](Architecture.md#der-modus-signatur-in-installps1)).
- Die Zertifikatskette (Stamm- und Zwischenzertifikate) muss auf dem Gerät vertrauenswürdig sein,
  **bevor** SelfX installiert wird, auch bei Autopilot: Das Zertifikatsprofil so zuweisen, dass es
  zuerst ankommt.
- Ein Gerät, das mit `-TrustedSigner` installiert wurde, lehnt eine Installation ohne den
  Parameter ab. Für den Weg zurück zu einem unsignierten Paket einmal den Schalter
  `-AllowHashMode` angeben.
- Sperrliste: Windows fragt die Adresse ab, die im Zertifikat steht. Für Geräte außerhalb des
  Firmennetzes sollte das eine aus dem Internet erreichbare HTTP-Adresse sein. Eine nicht
  erreichbare Liste bricht die Installation nicht ab (Standardeinstellung von Windows), kann sie
  aber verlangsamen; `tools\Measure-SelfXRevocationDelay.ps1` misst das auf einem Testgerät.
- Der Paketassistent signiert das Paket (Seite **Signatur** des Fensters oder `-CertificateThumbprint` /
  `-PfxPath` in der Konsole) und schreibt den Installationsbefehl mit `-TrustedSigner`. Wie Sie das
  Zertifikat bekommen, wie die Geräte ihm vertrauen und wie Sie es wechseln:
  [Codesignatur-Zertifikat](Zertifikat.md).

### 3.2 PowerShell 7 als eigene Win32-App

1. Laden Sie die MSI-Datei (`PowerShell-7.6.x-win-x64.msi`) von Microsoft und verpacken Sie
   sie als **Win32-App**, nicht als Branchen-App (MSI). Die Mischung beider Typen kann bei
   Autopilot fehlschlagen.
2. Installationsbefehl, zum Beispiel:

   ```text
   msiexec.exe /package PowerShell-7.6.x-win-x64.msi /quiet DISABLE_TELEMETRY=1 USE_MU=0 ENABLE_MU=0
   ```

   Ändern Sie den Installationsordner nicht. `ADD_PATH` ist nicht nötig. Testen Sie den
   Befehl vorher auf einem Testgerät.
3. Erkennungsregel: Datei `%ProgramFiles%\PowerShell\7\pwsh.exe`, Dateiversion größer
   oder gleich 7.6.0.
4. Neue PowerShell-Versionen verteilen Sie als neue Version dieser App.
5. In der SelfX-App unter *Abhängigkeiten* die App „PowerShell 7“ hinzufügen,
   *Automatisch installieren* = Ja. Intune installiert dann zuerst PowerShell 7.

### 3.3 Voraussetzungsregel für Windows 11 25H2

Prüfen Sie, ob das Portal „Windows 11 25H2“ als Mindest-Betriebssystem anbietet. Wenn
nicht, legen Sie eine Voraussetzungsregel vom Typ *Skript* an: Ausgabedatentyp *Ganzzahl*,
Operator *Größer oder gleich*, Wert `26200`:

```powershell
[int](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber)
```

Ältere Geräte erhalten die App dann nicht, statt mit einem Fehler abzubrechen.

### 3.4 Autopilot und Statusseite (ESP)

Autopilot installiert Apps in beliebiger Reihenfolge und darf nie an SelfX scheitern.
Deshalb gilt:

- Nehmen Sie **weder SelfX noch PowerShell 7** in die Liste der blockierenden Apps der ESP
  auf (*Block device use until these required apps are installed* = *Selected*, ohne
  diese beiden Apps).
- Ein fehlendes PowerShell 7 ist nur eine **Warnung**. SelfX startet dann keine Skripte,
  prüft aber vor jedem Start erneut und arbeitet, sobald PowerShell 7 da ist.
- Ein **unsicheres** PowerShell 7 ist dagegen ein harter Abbruch (siehe Tabelle unten).

| Lage auf dem Gerät | Installer | Dienst |
|---|---|---|
| Windows älter als 25H2 | Abbruch vor jeder Änderung, Exitcode 1. Eine vorhandene Installation bleibt unverändert. | nicht betroffen |
| PowerShell 7 fehlt oder ist älter als 7.6 | **Warnung** im Installationsprotokoll, die Installation läuft weiter. | startet kein Skript und meldet den Grund |
| Der Ordner `%ProgramFiles%\PowerShell\7` oder `pwsh.exe` ist für normale Nutzer änderbar | Abbruch vor jeder Änderung, Exitcode 1. | startet nichts |

### 3.5 Zuweisung

Weisen Sie die App einer Gerätegruppe als *Erforderlich* zu. Beginnen Sie mit einer kleinen
Pilotgruppe.

## Schritt 4: Testen

Testen Sie auf einem Gerät, das nicht produktiv ist:

1. Neuinstallation: Das SelfX-Fenster, das Statussymbol neben der Uhr und die
   Verknüpfungen erscheinen.
2. Als **normaler Nutzer** (ohne Administratorrechte) eine Aktion ausführen.
3. Update von der Vorversion.
4. Deinstallation und Erkennung.
5. Auf einem Gerät mit mehreren Nutzern: zweiten Nutzer angemeldet lassen.
6. Installation ohne PowerShell 7 (Warnung, später funktioniert SelfX von selbst) und
   auf Windows 11 24H2 (Abbruch mit Exitcode 1).
7. Einen Autopilot-Lauf mit beiden Apps (die Bereitstellung darf nicht hängen).

Prüfen auf dem Gerät:

```powershell
Get-Service SelfXService
Get-Content "$env:ProgramData\SelfX\Logs\Install.log" -Tail 20          # als Administrator
Get-Content "$env:ProgramData\SelfX\Logs\SelfXService.log" -Tail 20     # als Administrator
```

Die Tests des Repositorys führen Sie so aus (jeder Test endet mit Exitcode 1, wenn er einen
Fehler findet; GitHub Actions führt dieselben Tests bei jedem Pull Request aus):

```powershell
Get-ChildItem '.\SelfX Service' -Filter 'Test-*.ps1' | ForEach-Object {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { Write-Warning "$($_.Name) failed" }
}
```

## Update auf eine neue Version

1. Verteilen Sie immer das **ganze Paket**. Oberfläche und Dienst müssen zusammenpassen.
2. Erhöhen Sie `Version.txt` und `$ExpectedVersion` auf denselben neuen Wert.
3. Bauen Sie Programme und Paket neu (Schritt 2) und ersetzen Sie die AppLocker-Regeln (bei
   Herausgeberregeln für ein mit demselben Zertifikat signiertes Paket nicht nötig, siehe
   [Einmal einrichten statt je Version](#einmal-einrichten-statt-je-version)).
4. Laden Sie die neue `.intunewin` **und** das neue Erkennungsskript in dieselbe Intune-App
   hoch.
5. Prüfen Sie vor dem Paketieren die Support-Kontakte in `Tool_Config.xml` und
   `Health_Config.xml` (siehe [Konfiguration](Configuration.md)).
6. Ändern sich nur die Einstellungen, reicht ein [zweites Paket für die Konfiguration](#zweites-intune-paket-nur-die-konfiguration).

**Update von SelfX 2.6.9 (Upstream):** Zusätzlich brauchen die Geräte Windows 11 25H2 und
PowerShell 7.6 (Schritt 3). Das Paket muss mit dem .NET SDK 10 neu gebaut werden; die alte
Methode, den Dienst auf dem Gerät zu kompilieren, gibt es nicht mehr. Ersetzen Sie auch die
AppLocker-Regeln. Die Standardsprache der Oberfläche ist jetzt Deutsch
(`Tool_Language` = `de`). Alle Änderungen stehen im [Änderungsprotokoll](../../CHANGELOG.md).

## Deinstallation

`Uninstall.ps1` entfernt den Dienst, `%ProgramFiles%\SelfX` (mit `App` und `Config`, auch eine
Installation im alten Aufbau von 3.0.x), die Verknüpfungen, den Eintrag
unter Apps & Features, den Autostart des Statussymbols, den Status-Cache und die Berichte.
Offene SelfX-Fenster und Statussymbole werden vorher geschlossen. Hält ein anderes
Programm eine Datei offen, versucht der Deinstaller es bis zu 90 Sekunden lang erneut.

- Die Protokolle bleiben erhalten. Mit `-RemoveLogs` wird auch `%ProgramData%\SelfX`
  gelöscht.
- Einstellungen einzelner Nutzer (`HKCU\Software\SelfX`, `%LOCALAPPDATA%\SelfX`) werden
  nicht entfernt.
- Das Ergebnis steht in `%ProgramData%\SelfX\Logs\Uninstall.log`.

## Optionale Bausteine

### Windows Server (Terminalserver)

SelfX läuft auf Windows Server 2022 und 2025 mit Desktopdarstellung. Dort übernimmt es den Modus
`TerminalServer` von Windows: Angeboten werden nur Aktionen für die eigene Sitzung, und der Dienst lehnt
die anderen ab ([Konfiguration, Terminalserver](Configuration.md#terminalserver-windows-server)).

**Intune kann auf Windows Server keine Apps installieren.** Nur Builds von Windows Server Insider
Preview lassen sich in Intune registrieren, Server im Betrieb nicht. Installieren Sie SelfX von Hand oder
mit Configuration Manager:

1. Bauen Sie das Paket mit dem Assistenten und beantworten Sie *Für welches Windows ist das Paket?* mit
   `WindowsServer`. Der Assistent fragt dann, wer den Gerätestatus bekommt (`TerminalServer_Health`),
   und schreibt statt der Intune-Anleitung die Anleitung `SelfX-Server-Guide.<Sprache>.txt`. Eine Datei
   `.intunewin` wird dafür nicht gebaut und `IntuneWinAppUtil.exe` wird nicht gebraucht.
2. Installieren Sie PowerShell 7.6 oder neuer (MSI, für alle Nutzer) auf dem Server.
3. Kopieren Sie den Ordner `package` des Ausgabeordners unverändert auf den Server oder in eine Freigabe,
   die nur Administratoren ändern können. Nutzer dürfen nur lesen: `Install.ps1` prüft jede Datei gegen
   die Dateilisten, wer die Freigabe ändern kann, kann aber auch die Listen ändern.
4. In einer erhöhten 64-Bit-Windows-PowerShell in diesem Ordner:
   `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1`
   (bei einem signierten Paket mit `-TrustedSigner <Fingerabdruck>`). Deinstallieren: dasselbe mit
   `Uninstall.ps1`.
5. Configuration Manager: eine Anwendung mit dem Bereitstellungstyp *Skriptinstallationsprogramm*,
   Inhalt = der kopierte Ordner, die Befehle oben, Installationsverhalten *Für System installieren*,
   nicht als 32-Bit-Prozess. Erkennungsmethode: ein benutzerdefiniertes PowerShell-Skript mit dem Inhalt
   von `SelfX-Service-<Version>.Detection.ps1`. Es schreibt eine Zeile und endet mit 0, wenn SelfX
   installiert ist, und schreibt sonst nichts, wie Configuration Manager es erwartet.

`Install.ps1` bricht ohne Änderung ab auf Server Core (kein Desktop für das Fenster und das
Statussymbol), auf einem Domänencontroller und auf Windows Enterprise multi-session. Ein
Gruppenrichtlinien-Startskript passt nicht gut: `Install.ps1` installiert bei jedem Start neu (der Dienst
wird angehalten und die Dateien werden ersetzt).

### Zweites Intune-Paket: nur die Konfiguration

Der Assistent kann ein **zweites, kleines Paket** bauen (`SelfX-Config-<Version>.intunewin`), das nur `Install.ps1`, `Detection.ps1` und den Ordner
`Config` enthält. Es wird mit `Install.ps1 -ConfigOnly` installiert. Es ersetzt die Einstellungen eines SelfX, das **schon installiert** ist (Support-Adresse,
Logo, Ticket-Zuordnung, Aktionslisten, Sprache) und sonst nichts: Dienst, Programme und Vertrauensanker bleiben unberührt, nichts wird neu gestartet. Ein
geöffnetes SelfX-Fenster zeigt die neuen Einstellungen, nachdem es geschlossen und wieder geöffnet wurde.

**Wann lohnt sich das?** Wenn sich die Einstellungen oft ändern und der Code selten. Das kleine Paket ist in Sekunden installiert, Sie testen nicht
das ganze Produkt neu, und das Code-Paket (das große) bleibt wie es ist. Ändern Sie Einstellungen nur zusammen mit einer neuen Version, ist ein Paket
einfacher: Bleiben Sie dann dabei.

**Beide Pakete bauen und installieren**

1. Bauen Sie das vollständige Paket mit dem Assistenten und antworten Sie *Vollständiges Paket mit getrenntem Konfigurationspaket* (Konsole: `-SeparateConfig`). Sein Erkennungsskript
   vergleicht die Konfiguration nicht; das vollständige Paket wird also nicht neu installiert, wenn sich nur die Konfiguration geändert hat.
2. Bauen Sie das Konfigurationspaket aus demselben Release mit **denselben Antworten**: *Konfigurationspaket* (Konsole: `-ConfigPackage`).
3. Legen Sie in Intune **zwei Apps** an: die vollständige App wie bisher und die Konfigurations-App mit dem Installationsbefehl
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -ConfigOnly` (der Assistent schreibt die genaue Zeile in seine Anleitung).
   Deinstallationsbefehl: ein Befehl, der nichts tut (`...powershell.exe -NoProfile -Command exit 0`); die vollständige App entfernt SelfX.
4. Tragen Sie die **vollständige App als Abhängigkeit** der Konfigurations-App ein (*Automatisch installieren: Ja*). Weisen Sie beide denselben Gerätegruppen zu.
5. Erkennung der Konfigurations-App: die Datei `SelfX-Config-<Version>.Detection.ps1` (sie vergleicht nur die Konfiguration).

**Konfiguration später ändern.** Bauen Sie ein neues Konfigurationspaket und laden Sie es als **neue Version der Konfigurations-App** hoch, oder legen Sie eine neue
App an und tragen Sie die alte unter *Ablösung (Supersedence)* ein, mit *Vorherige Version deinstallieren* auf **Nein**. Die Ablösung gilt nur zwischen
Konfigurations-Apps: Eine neuere ersetzt eine ältere, die Geräte installieren die neue, die alte ist nicht mehr erforderlich.

> **Richten Sie nie eine Ablösung zwischen Konfigurations-App und vollständiger App ein.** Die vollständige App würde durch die Ablösung deinstalliert und SelfX
> würde vom Gerät entfernt.

**Was `-ConfigOnly` prüft (es hält an, bevor es etwas ändert)**

- SelfX ist installiert und hat einen Vertrauensanker; der Anker ist sicher. Der Modus (Hash oder Signatur) ist der des Geräts. `-TrustedSigner` und
  `-AllowHashMode` lassen sich nicht mit `-ConfigOnly` kombinieren: Ein Konfigurationspaket kann nicht ändern, wem vertraut wird.
- Das Paket enthält nur `Install.ps1` und `Config`, keinen Link, und jede Datei steht mit ihrem SHA256 in `Config\SelfX.Config.json`. Im Modus Signatur müssen die Skripte
  und `Config\SelfX.Config.cat` eine gültige Signatur eines Signierers des Geräts tragen.
- `MinCodeVersion` in `SelfX.Config.json` (die Code-Version, für die die Konfiguration gemacht ist) darf nicht neuer sein als der installierte Code
  (`App\SelfX.Code.json`). Installieren Sie in diesem Fall zuerst das vollständige Paket.
- Einstellungen, die nur die vollständige Installation anwendet (Name der Verknüpfung, Verknüpfung auf dem Desktop oder im Startmenü, Eintrag des Statussymbols,
  Symbol, `Service_Privileges`), müssen mit denen auf dem Gerät übereinstimmen. Weichen sie ab, lehnt das Konfigurationspaket mit ihren Namen ab: Ändern Sie sie
  mit dem vollständigen Paket. Alles andere in `Tool_Config.xml` wird gelesen, wenn SelfX läuft, und darf sich ändern.

Der Ordner `Config` wird durch Umbenennen getauscht: Der neue Ordner wird neben den Installationsordner kopiert und dort geprüft, dann wird `Config` in `SelfX.ConfigOld` (neben dem Installationsordner) und der neue
Ordner in `Config` umbenannt; bei einem Fehler kommt der alte Ordner zurück. Die Ordner neben dem Installationsordner heißen `SelfX.ConfigStage` und `SelfX.ConfigOld` (der Dienst startet
keine Skripte, wenn der Installationsordner mehr als `App` und `Config` enthält). Das Skript einer laufenden Aktion hält Dateien offen: Der Austausch wartet und versucht es etwa
20 Sekunden lang erneut, dann endet er mit Exitcode 1 und Intune versucht es später noch einmal. Das Ergebnis steht in `%ProgramData%\SelfX\Logs\Install.log`.

**Erkennung und das vollständige Paket.** Nach einer neuen Code-Version ersetzt das vollständige Paket `Config` durch die Konfiguration seines eigenen Builds. Das Konfigurationspaket
passt dann nicht mehr (sein Digest weicht ab) und Intune installiert es erneut: Die Einstellungen des Konfigurationspakets gelten wieder. Bauen Sie beide Pakete aus demselben
Release mit denselben Antworten und verteilen Sie das vollständige Paket zuerst.

### Ticket-Zuordnung per Intune

Nur nötig, wenn Sie die Ticket-Funktion (`Ticket_Enabled`) mit Regeln für Group-Tag oder
Kategorie in `Ticket_Config.xml` nutzen (siehe
[Konfiguration](Configuration.md#ticket-per-e-mail)). SelfX liest die Werte nur. Sie stehen in
`HKLM\SOFTWARE\SelfX\Support`:

- `GroupTag` und `Category` (je bis 64 Zeichen: Buchstaben, Ziffern, Leerzeichen, `.`, `_`, `-`)
- `TicketMail` und `TicketCc`: genau eine einfache Adresse je Wert, nur Funktionspostfächer,
  keine persönlichen Postfächer

Hybrid-Geräte können zusätzlich nach der OU zugeordnet werden; dafür ist nichts zu setzen.

So gehen Sie vor (*Geräte > Skripte und Fehlerbehebungen > Plattformskripts*):

1. Kopieren Sie das Skript unten je Einheit und passen Sie die Werte oben an.
2. Einstellungen: *Mit den Anmeldeinformationen des angemeldeten Benutzers ausführen* =
   **Nein** (läuft als SYSTEM), *Skripthost in 64-Bit-PowerShell ausführen* = **Ja**.
3. Weisen Sie das Skript einer Entra-Gerätegruppe zu. Die Gruppen sollten sich gegenseitig
   ausschließen. Das Skript setzt immer alle vier Werte; wechselt ein Gerät die Gruppe,
   ersetzt das Skript der neuen Gruppe die Werte der alten.
4. Kontrolle auf dem Gerät: `Get-ItemProperty 'HKLM:\SOFTWARE\SelfX\Support'`. Vor der
   Verteilung zeigt `tools\Test-SelfXTicketRouting.ps1 -GroupTag ... -Category ...`, welche
   Einheit herauskommt.

Das Skript läuft in Windows PowerShell 5.1 und PowerShell 7 und ändert nur diese vier
Werte. Ungültige Werte brechen ab, bevor etwas geschrieben wird.

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

### App Control for Business (WDAC)

SelfX braucht WDAC nicht, und im Paket ist nichts davon eingeschaltet. Wenn Ihre
Organisation App Control for Business einsetzt, können Sie damit zusätzlich verhindern, dass
auf den Geräten andere als die ausgelieferten SelfX-Programme und -Skripte laufen. Standardmäßig
wird SelfX per Hash zugelassen; für ein mit dem Zertifikat Ihrer Organisation signiertes Paket
gibt es eine Signer-Regel ([Einmal einrichten statt je Version](#einmal-einrichten-statt-je-version)).

1. **Basisrichtlinie.** Sie gehört Ihrer Organisation. Sie muss ergänzende Richtlinien
   erlauben (Regeloption 17) und die von Microsoft signierten Dateien zulassen, darunter
   `%ProgramFiles%\PowerShell\7\pwsh.exe` und den Intune-Agenten.
2. **Paket bauen** (Schritt 2).
3. **Ergänzende Richtlinie erzeugen**, in Windows PowerShell 5.1 auf einem
   Administrator-PC (Modul ConfigCI):

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXWdacPolicy.ps1 -BasePolicyId {GUID der Basisrichtlinie}
   ```

   Das Skript legt in `build\wdac` die XML- und die `.cip`-Datei ab. Sie enthält
   Hashregeln für alle Programme, Bibliotheken und Skripte des Pakets. Es ändert nichts auf
   dem PC. Der Assistent (`New-SelfXPackage.ps1`) ruft dieses Skript für Sie auf, wenn Sie die ID der Basisrichtlinie angeben; das Skript
   liest dann den Ordner `package` des Ergebnisses (Ordner `App`, `Config` und `Bin`) und das erzeugte Erkennungsskript
   (`-DetectionFile`), so wie Intune es ausführt.
4. **Verteilen** mit Intune (Richtlinie für App Control for Business) an dieselben Geräte
   wie das SelfX-Paket. Die Richtlinie muss vor dem Paket auf dem Gerät sein.
5. **Erst im Überwachungsmodus.** Ob überwacht oder erzwungen wird, bestimmt die
   Basisrichtlinie (Regeloption 3, „Audit Mode“). Im Überwachungsmodus läuft alles weiter,
   und Windows protokolliert, was blockiert würde (Protokoll
   `Microsoft-Windows-CodeIntegrity/Operational`, Ereignis 3076). Prüfen Sie auf einem
   Testgerät, dass für SelfX kein Ereignis entsteht. Erst dann schaltet die Organisation
   die Option 3 ab.
6. **Bei jeder neuen Version** die Richtlinie neu erzeugen und mit dem Paket verteilen,
   denn jede Skriptänderung ändert den Hash. Für gestaffelte Rollouts erzeugen Sie die
   Richtlinie mit `-PolicyId {neue GUID}` je Version und entfernen die alte, wenn alle
   Geräte aktualisiert sind.

Hinweise: Regeloption 19 („Dynamic Code Security“) nur nach einem Test im Überwachungsmodus
einschalten, weil SelfX-Skripte `Add-Type` nutzen. Eine unsignierte Richtlinie kann ein
lokaler Administrator ersetzen. Die Vorlage ist noch nicht auf einem Gerät erprobt.

### Einmal einrichten statt je Version

Bei den Hashregeln (Standard) müssen AppLocker und App Control für jede neue Version ersetzt
werden, weil jede geänderte Datei einen neuen Hash hat. Für ein Paket, das mit dem
Codesignatur-Zertifikat Ihrer Organisation signiert ist, ersetzen **Herausgeberregeln** sie: Sie
erzeugen sie einmal, und sie bleiben für jede spätere Version gleich, die mit demselben Zertifikat
signiert ist.

Voraussetzungen:

- Das Paket ist signiert (Vertrauensmodus Signatur, siehe
  [Optional: signiertes Paket](#optional-signiertes-paket-vertrauensmodus-signatur) und
  [Architektur](Architecture.md#vertrauensmodi-hash-und-signatur)).
- Die Zertifikatskette des Signierzertifikats ist auf dem PC vertrauenswürdig, auf dem Sie die
  Regeln erzeugen. Eine Datei, deren Signatur Windows nicht akzeptiert (nach dem Signieren
  verändert, Zertifikat nicht vertrauenswürdig), stoppt beide Skripte; ebenso eine Datei ohne
  Signatur (AppLocker) oder ein Paket, dessen `Install.ps1` nicht signiert ist (App Control).
- Windows PowerShell 5.1 (`powershell.exe`). Für App Control zusätzlich das Modul ConfigCI.

**AppLocker.** Übergeben Sie dem Skript signierte Dateien des Pakets, getrennt durch `|`:
mindestens ein Programm und ein Skript, zum Beispiel:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXAppLockerRules.ps1 -Mode Publisher -PathList "C:\Paket\Bin\SelfXService.exe|C:\Paket\Bin\SelfX.exe|C:\Paket\Install.ps1" -OutputFile C:\Paket\SelfX.AppLocker.Publisher.xml -RuleNamePrefix SelfX
```

- Das Skript liest den Herausgebernamen aus der Signatur (er ist nie ein Parameter) und schreibt
  **eine Herausgeberregel je Regelsammlung** (Exe, Dll, Script): Zulassen, für die SID `S-1-1-0`
  (Jeder), ohne Produkt, Dateinamen oder Versionsbereich. Keine Hashregeln.
- Alle Dateien müssen mit demselben Zertifikat signiert sein. Die Regeln haben feste IDs: Ein
  zweiter Lauf für denselben Herausgeber ergibt dieselbe Datei.
- Übernehmen Sie die Regeln einmal und löschen Sie die Hashregeln früherer SelfX-Versionen. Eine
  neue, mit demselben Zertifikat signierte Version braucht keine Änderung. Ein erneuertes
  Zertifikat mit demselben Antragsteller (gleicher Herausgebername) braucht auch keine; bei einem
  anderen Antragsteller erzeugen Sie die Regeln neu, fügen sie hinzu, bevor das erste Paket mit
  dem neuen Zertifikat die Geräte erreicht, und entfernen die alten, wenn alle Geräte aktualisiert
  sind.
- Ohne `-Mode` (oder mit `-Mode Hash`) schreibt das Skript wie bisher Hashregeln; das bleibt der
  Standard für ein Paket, das nicht signiert ist.

**App Control for Business (WDAC).** Schritt 3 von
[App Control for Business (WDAC)](#app-control-for-business-wdac) mit dem zusätzlichen Parameter
`-Level Publisher`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXWdacPolicy.ps1 -BasePolicyId {GUID der Basisrichtlinie} -Level Publisher
```

- Die Richtlinie enthält statt der Hashregeln eine Signer-Regel (Zertifizierungsstelle und
  Herausgebername des Signierzertifikats, keine Version). Eine Datei ohne Signatur bekommt
  stattdessen eine Hashregel (Rückfall); bei einem vollständig signierten Paket enthält die
  Richtlinie gar keine Hashregel.
- Die Richtlinien-ID bleibt fest. Verteilen Sie die Richtlinie einmal; eine neue signierte Version
  braucht keine neue Richtlinie. Nur wenn sich das Signierzertifikat ändert, erzeugen Sie die
  Richtlinie neu (während des Wechsels sind beide Zertifikate im Einsatz: `-AllowMultipleSigners`
  ergänzen).
- Das Skript stoppt vor dem Scan bei einer Datei mit ungültiger Signatur, bei Dateien, die mit
  verschiedenen Zertifikaten signiert sind (ohne `-AllowMultipleSigners`), und bei einem Paket,
  dessen `Install.ps1` nicht signiert ist (dafür die Stufe Hash verwenden). Nach dem Scan prüft es
  die Richtlinie: Signer-Regeln ohne Dateiattribut und keine Hashregel neben einer signierten
  Datei.
- Die Ausgabe nennt die Herausgeber, denen die Richtlinie vertraut. Prüfen Sie, dass das Ihr
  Signierzertifikat ist und kein anderes.

Was eine Herausgeberregel **nicht** leistet:

- Sie vertraut dem **Signierer**, nicht einer Datei oder Version. Wer mit diesem Zertifikat
  signieren kann, bekommt Dateien zugelassen; schützen Sie den Schlüssel (Smartcard, HSM oder ein
  eingeschränkter Signier-Host). Um das Vertrauen zu entziehen, tauschen Sie Zertifikat und Regeln
  aus.
- Sie verhindert nicht, dass eine ältere, noch korrekt signierte SelfX-Version läuft. Die
  Versionsbindung kommt aus den Dateilisten und, im Modus Signatur, aus den Prüfungen von
  `Install.ps1` und Dienst ([Architektur](Architecture.md#die-grenze-lokaler-administrator)).
- Die Grenze für einen lokalen Administrator bleibt: Nur App Control im Erzwingungsmodus hilft
  gegen ihn.

Die Skripte sind durch automatische Tests abgedeckt; die erzeugten Richtlinien sind noch nicht auf
einem Gerät erprobt. Testen Sie sie zuerst im Überwachungsmodus.

### Defender ASR: Regel für ausführbare Dateien

Nutzen Ihre Geräte die Regel **Block executable files from running unless they meet a prevalence, age, or trusted list criterion**
zur Verringerung der Angriffsfläche (ASR, ID `01443614-cd74-433a-b99e-2ecdc07bfc25`), kann Defender Programme von SelfX blockieren.
Dieser Abschnitt erklärt die Ursache, wie Sie die blockierte Datei finden und was Sie tun können. Er folgt der Dokumentation von
Microsoft und dem Aufbau des Pakets; **er ist nicht auf einem Gerät erprobt, auf dem die Regel aktiv ist.**

**Was die Regel macht.** Sie hindert ausführbare Dateien (zum Beispiel `.exe`, `.dll`, `.scr`) am Start, wenn sie kein
Vertrauenskriterium erfüllen. Sie braucht den Cloudschutz. Der Cloudschutz von Microsoft entscheidet anhand von Verbreitung, Alter und
einer Vertrauensliste; diese Kriterien können Sie nicht einstellen. Der Benutzer sieht eine Benachrichtigung, im Defender-Portal
erzeugt die Regel keine Warnung ([Referenz der ASR-Regeln](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-reference),
[ASR-FAQ](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-faq); beide Seiten sind englisch).

**Warum SelfX betroffen sein kann.** `SelfXService.exe`, `SelfX.exe`, `SelfXWinRT.dll`, `SelfXAudio.dll` und `SelfXDisturb.dll` werden auf Ihrem
Build-Rechner gebaut (Schritt 2.3) und gibt es nur auf Ihren Geräten. Ein Programm, das Microsoft noch nie gesehen hat, erfüllt die
Kriterien unter Umständen nicht, und laut FAQ kann eine neue Version einer App blockiert werden, solange sie Ruf aufbaut. Das ist ein
Schluss aus dem Aufbau von SelfX, keine Aussage von Microsoft über SelfX.

**1. Die blockierte Datei finden.** Kopieren Sie `tools\Get-SelfXAsrEvents.ps1` auf das Gerät und führen Sie es dort aus (nur
lesend; mit erhöhten Rechten, wenn das Protokoll sonst nicht lesbar ist):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-SelfXAsrEvents.ps1 -SelfXOnly
```

Das Skript liest die Ereignisse 1121 (Regel im Blockmodus ausgelöst) und 1122 (Regel im Überwachungsmodus ausgelöst) des Protokolls
`Microsoft-Windows-Windows Defender/Operational` nur für diese eine Regel und zeigt `Time` (Zeit), `Mode` (`Block` oder `Audit`),
`File` (die blockierte Datei), `StartedBy` (der Prozess, der sie starten wollte) und `InSelfXFolder`. Ohne `-SelfXOnly` zeigt es die
Ereignisse für alle Programme; `-Days` (Standard 30) und `-MaxEvents` (Standard 100) begrenzen die Liste. Es ändert nichts und zeigt
keinen Benutzernamen: Es liest weder das Feld `User` noch die Befehlszeilen, und der Profilordner eines Benutzers wird in Pfaden als
`<user>` angezeigt. Ein Pfad außerhalb der lokalen Profilordner wird so angezeigt, wie das Ereignis ihn meldet; sehen Sie sich die
Ausgabe an, bevor Sie sie weitergeben. In Defender for Endpoint stehen dieselben Ereignisse im Advanced Hunting als
`AsrUntrustedExecutableBlocked` und `AsrUntrustedExecutableAudited` bereit.

Keine Ereignisse können bedeuten: Die Regel ist aus, die Datei ist ausgeschlossen (ausgeschlossene Dateien schreiben keine
Ereignisse) oder nichts wurde blockiert. Die Namen der Ereignisfelder (`ID`, `Path`, `Process Name`) beschreibt Microsoft nicht; sie
stammen aus einem Beispielereignis. Meldet das Skript Ereignisse, die es keiner Regel zuordnen konnte, weicht der Aufbau der
Ereignisse von diesem Beispiel ab.

**2. Zuerst der Überwachungsmodus.** Stellen Sie die Regel auf den Pilotgeräten auf **Audit**. Die Regel schreibt dann Ereignis 1122
und blockiert nichts. Die FAQ empfiehlt den Überwachungsmodus für Regeln allgemein, um die Programme zu finden, die einen Ausschluss
brauchen, und für diese Regel, wenn Sie Apps oft aktualisieren.

**3. Genau die SelfX-Dateien ausschließen, nur für diese Regel.** Öffnen Sie in Intune *Endpoint Security > Verringerung der
Angriffsfläche* und die Richtlinie vom Typ *Attack surface reduction rules*. Sobald die Regel auf Audit, Block oder Warn steht,
erscheint für sie die Einstellung **ASR Only Per Rule Exclusions** (Namen der englischen Oberfläche; [ASR-Regeln und Ausschlüsse
konfigurieren](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-configure)). Tragen Sie nur die
Dateien ein, die die Ereignisse nennen, höchstens diese fünf:

```
C:\Program Files\SelfX\App\SelfXService.exe
C:\Program Files\SelfX\App\SelfX.exe
C:\Program Files\SelfX\App\WinRT\SelfXWinRT.dll
C:\Program Files\SelfX\App\Audio\SelfXAudio.dll
C:\Program Files\SelfX\App\Disturb\SelfXDisturb.dll
```

- Schließen Sie **nicht** den Ordner `C:\Program Files\SelfX` aus und verwenden Sie keinen Platzhalter. Verwenden Sie **nicht** die
  globale Einstellung *Attack Surface Reduction Only Exclusions*: Sie gilt für jede ASR-Regel auf dem Gerät.
- Nennt ein Ereignis eine andere Bibliothek in `App\WinRT` (die Windows-SDK-Projektion), schließen Sie genau diese Datei aus, und erst
  nachdem Sie ihren SHA256 mit `SelfX.Code.json` verglichen haben.
- Die Regel beachtet Ausschlüsse je Regel ([Übersicht der ASR-Regeln](https://learn.microsoft.com/en-us/defender-endpoint/attack-surface-reduction-rules-overview)).
  Ein Ausschluss gilt erst, wenn das Programm startet: Starten Sie den Dienst `SelfXService` oder das Gerät neu. Ausgeschlossene
  Dateien schreiben keine Ereignisse; die Liste des Skripts wird nach dem Ausschluss also kürzer, und der Beleg ist, dass die
  Benachrichtigung ausbleibt und SelfX startet.
- Ein Ausschluss senkt den Schutz. Er gilt für den Pfad: Auch eine andere Datei an demselben Pfad würde von dieser Regel nicht
  geprüft. Benutzer haben im Ordner nur Lese- und Ausführungsrechte; die Dateilisten, die Dateiprüfung des Dienstes und, wenn Sie sie
  nutzen, AppLocker oder App Control schützen den Inhalt weiter. Ein lokaler Administrator kann beides ändern (siehe
  [Architektur](Architecture.md#die-grenze-lokaler-administrator)).

**4. Programme aus dem Release.** Der Release-Workflow baut die Programme einmal und liefert sie in der `.intunewin` des Releases
(gebaut mit den Einstellungen des Repositorys, nicht mit Ihren). Wer diese Datei nutzt, hat dieselben Programme. Ein Paket mit Ihren
eigenen Einstellungen enthält die Programme Ihres eigenen Builds; ob zwei Builds auf verschiedenen Rechnern identische Dateien ergeben,
ist nicht geprüft (die CI vergleicht zwei Builds nur auf einem Runner). Nur identische Dateien können einen gemeinsamen Ruf aufbauen;
Microsoft beschreibt keinen Weg, sich darauf zu verlassen.

**5. Signieren ist keine Zusage.** Die Dokumentation von Microsoft zu dieser Regel sagt nicht, dass signierte Dateien durchgelassen
werden. Ein signiertes Paket (Vertrauensmodus Signatur) kann deshalb trotzdem blockiert werden; es gibt keine Zusage, dass das
Signieren den Block löst. Testen Sie Ihr signiertes Paket im Überwachungsmodus. Laut Übersicht der ASR-Regeln beachtet die Regel
Indikatoren (IoC) für Dateien und Zertifikate; ein Indikator *Zulassen* für das Signaturzertifikat in Defender for Endpoint ist also
eine weitere Möglichkeit. Das wurde mit SelfX nicht erprobt.

## Hintergrund: Was die Installation macht

`Install.ps1` läuft mit Administratorrechten, in Intune als SYSTEM. Es prüft **ganz am
Anfang**, bevor es etwas ändert: Windows-Version, PowerShell-7-Ordnerrechte, die Programme
in `Bin` (SHA256-Manifest) und die Dateiliste. Passt etwas nicht, endet es mit Exitcode 1,
und die bisherige Installation bleibt unverändert. Danach:

1. Es stoppt und entfernt einen vorhandenen `SelfXService`.
2. Es leert `%ProgramFiles%\SelfX` (der Ordner selbst bleibt) und legt darin zwei Ordner an:
   `App` (Code: Programme, Bibliotheken, Skripte und Sprachdateien des Projekts,
   `Uninstall.ps1`, `SelfX.Code.json`) und `Config` (Konfiguration: die Einstellungsdateien,
   `Branding`, Ihre eigenen Skripte und Sprachdateien, `SelfX.Config.json`). Benutzer dürfen
   dort nur lesen und ausführen; SYSTEM und Administratoren haben Vollzugriff (dieselben
   Rechte wie bisher).
3. Es installiert `SelfXService.exe` (den Dienst) und `SelfX.exe` (einen kleinen Starter
   ohne Konsolenfenster, der SelfX oder das Statussymbol mit einem versteckten
   PowerShell 7 startet) nach `App`. Es prüft die installierten Dateien noch einmal gegen
   beide Listen; außer `App` und `Config` darf in `%ProgramFiles%\SelfX` nichts übrig sein.
4. Es registriert und startet den Dienst `SelfXService` (LocalSystem, automatischer Start,
   Neustart nach einem Fehler) und begrenzt seine Rechte.
5. Es legt Verknüpfungen auf dem öffentlichen Desktop und im Startmenü an und einen
   Eintrag unter Apps & Features.
6. Ist `Show_Tray_Icon` = `True` (Standard), legt es den Autostart `SelfXTray` an. Als
   SYSTEM startet der Installer das Statussymbol in jeder aktiven Nutzersitzung mit den
   normalen Rechten des Nutzers. Bei manueller Installation erscheint es bei der nächsten
   Anmeldung.

Ein Update bricht nicht ab, wenn ein Nutzer SelfX geöffnet hat: Der Installer leert den
Ordner, statt ihn zu löschen, und wiederholt gesperrte Dateien 20 Sekunden lang.

**Update von Version 3.0.x (alter Aufbau).** Bis 3.0.x lagen alle Dateien direkt in
`%ProgramFiles%\SelfX`. Ab 3.1.0 entfernt der Installer diesen Inhalt zuerst vollständig und
installiert danach `App` und `Config`; einen Mischzustand gibt es nicht. Ein leerer alter
Ordner, den ein laufendes Programm noch als Arbeitsordner nutzt, darf bis zur nächsten
Abmeldung bleiben; eine Datei des alten Aufbaus neben `App` und `Config` bricht die
Installation ab (Exitcode 1). `Detection.ps1` von 3.1.0 erkennt den alten Aufbau nicht, daher
installiert Intune das Update. Das Paket selbst hat die Ordner `App` und `Config` statt
`Sources`; bauen Sie es mit `tools\New-SelfXIntuneWin.ps1` (im Repository bleibt der Ordner
`Sources`).

### Protokolle

| Protokoll | Ort | Wer liest |
|---|---|---|
| Installation | `%ProgramData%\SelfX\Logs\Install.log` | Administratoren, SYSTEM |
| Dienst | `%ProgramData%\SelfX\Logs\SelfXService.log` (rotiert bei 5 MB nach `.old`) | Administratoren, SYSTEM |
| Skripte | `%ProgramData%\SelfX\Logs` (eine Datei pro Skript und Tag) | Administratoren, SYSTEM |
| Fenster, Statussymbol, Nutzeraktionen | `%ProgramData%\SelfX\Logs\Users\<SID>` | jeder Nutzer nur den eigenen Ordner |

Dateien, die älter sind als `Log_Retention_Days` (Standard 90), werden automatisch gelöscht
(siehe [Protokolle und Aufbewahrung](Configuration.md#protokolle-und-aufbewahrung)).

### Windows-Ereignisprotokoll

Der Dienst schreibt seine Ereignisse in ein eigenes Protokoll **SelfX** (Ereignisanzeige:
*Anwendungs- und Dienstprotokolle* > *SelfX*, Quelle `SelfXService`), damit Defender for
Endpoint, Intune oder ein SIEM sie auswerten können. `Install.ps1` legt das Protokoll an (höchstens
20 MB, wenn es voll ist, werden die ältesten Einträge überschrieben); `Uninstall.ps1` entfernt es.
Versionen vor 3.1.0 schrieben mit derselben Quelle in das Protokoll *Anwendung*: Das Update hängt
die Quelle in das Protokoll SelfX um, ältere Einträge bleiben im Protokoll Anwendung. Lässt sich
das Protokoll nicht anlegen, läuft die Installation mit einer Warnung in `Install.log` weiter; der
Dienst schreibt dann nur `SelfXService.log`.

Wie das Protokoll Anwendung kann jeder angemeldete Nutzer das Protokoll lesen. Deshalb enthalten
die Einträge keine Anfragetexte, keine Nutzernamen, keine Pfade aus Nutzerprofilen und keine
Detailtexte der Gerätestatus-Prüfungen. Die SID des Nutzers, der eine Aktion gestartet hat, steht
nur darin, wenn in `Tool_Config.xml` `EventLog_CallerSid` = `True` gesetzt ist (Standard `False`,
siehe [Konfiguration](Configuration.md#protokolle-und-aufbewahrung)). Jedes Feld wird bereinigt
(Steuerzeichen entfernt, `%` wird `_`) und gekürzt (Feld 1 auf 800, die übrigen Felder auf 256
Zeichen); ein leeres Feld ist `-`.

Begrenzung je Ereignis-ID: Sicherheitsereignisse (4001-4008) höchstens 10 Einträge in 10 Minuten,
Betriebsereignisse (4010-4013) höchstens 20 Einträge je Minute. Danach meldet 4099 die Zahl der
ausgelassenen Einträge. Auf Windows 11 und auf einem Terminalserver entstehen dieselben Ereignisse.

| ID | Stufe | Bedeutung |
|---|---|---|
| 4001 | Fehler | Der Pipe-Name gehört schon einem anderen Prozess; der Dienst nimmt keine Verbindungen an, bis er frei ist. |
| 4002 | Warnung | Eine Anfrage oder Verbindung wurde abgelehnt (ungültig, nicht erlaubt, Begrenzung). |
| 4003 | Warnung | PowerShell 7 ist nicht gegen Änderungen durch Nutzer geschützt; Aktionen als SYSTEM werden nicht gestartet. |
| 4004 | Fehler | `%ProgramData%\SelfX` ist nicht geschützt (Verknüpfung oder fremder Besitzer); der Dienst schreibt dort nichts, bis ein Administrator es repariert (SelfX neu installieren). |
| 4005 | Fehler | Installierte Skripte oder Konfigurationen stimmen nicht mit `SelfX.Code.json` und `SelfX.Config.json` überein; der Dienst startet nichts. Mit `Service_FileCheck` = `Audit` nur eine Warnung. |
| 4006 | Fehler | Der Vertrauensanker `HKLM\SOFTWARE\SelfX\Trust` fehlt, ist ungültig oder kann von einer anderen Identität als SYSTEM und Administratoren geändert werden; der Dienst startet nichts. SelfX neu installieren. |
| 4007 | Fehler | Vertrauensmodus Signatur: Ein installiertes Skript oder eine Bibliothek hat keine gültige Signatur eines erlaubten Signierers, oder ein signierter Katalog (`SelfX.Code.cat`, `SelfX.Config.cat`) fehlt oder passt nicht; der Dienst startet nichts, auch mit `Service_FileCheck` = `Audit`. Das SelfX-Protokoll nennt Datei und Grund. |
| 4008 | Warnung | Terminalserver (Windows Server, Modus `TerminalServer`): Eine Anfrage für eine Aktion, die nicht als `TerminalServer` = `Show` eingestuft ist, wurde abgelehnt. Das SelfX-Protokoll nennt die Aktion. |
| 4009 | - | Nicht belegt (früher eine Warnung zum Modus; der Modus kommt von Windows). Die ID bleibt frei. |
| 4010 | Information | Eine Aktion wurde als SYSTEM gestartet (auch eine Reparatur einer Gerätestatus-Prüfung). |
| 4011 | Information | Eine Aktion als SYSTEM endete mit Exitcode 0. |
| 4012 | Warnung / Fehler | Eine Aktion als SYSTEM ist fehlgeschlagen: Warnung bei einem Exitcode ungleich 0, Fehler bei Zeitüberschreitung oder wenn PowerShell 7 nicht gestartet werden konnte. |
| 4013 | Warnung | Eine Zeile des Gerätestatus hat auf *Fehler* gewechselt. Auch für eine Zeile, die bei der ersten Prüfung nach dem Start des Dienstes auf *Fehler* steht. |
| 4099 | Warnung | Weitere Ereignisse einer ID wurden nicht geschrieben (Begrenzung). |

#### Felder für ein SIEM

Jeder Eintrag trägt seine Werte als getrennte Zeichenfolgen (Einfügezeichenfolgen; in der
XML-Ansicht der Ereignisanzeige `EventData`, in PowerShell `(Get-WinEvent -LogName SelfX).Properties`).
Feld 1 ist immer ein fester englischer Text; die Reihenfolge der Felder ändert sich nicht. Die
Ereignisanzeige zeigt Feld 1 als Beschreibung.

| ID | Feld 1 | Feld 2 | Feld 3 | Feld 4 | Feld 5 | Feld 6 |
|---|---|---|---|---|---|---|
| 4001-4008 | fester Text | - | - | - | - | - |
| 4010 | fester Text | Skript (Dateiname aus dem Katalog) | SID des Aufrufers oder `-` | Aufrufer ist erhöhter Administrator: `True` / `False` | - | - |
| 4011 | fester Text | Skript | Ergebnis: `ExitCode` | Exitcode: `0` | Dauer in Sekunden | SID des Aufrufers oder `-` |
| 4012 | fester Text | Skript | Ergebnis: `ExitCode`, `Timeout` oder `StartError` | Exitcode, `-` ohne | Dauer in Sekunden | SID des Aufrufers oder `-` |
| 4013 | fester Text | Art der Prüfung (`Id` in `Health_Config.xml`, zum Beispiel `Disk`, `Services`) | Name der Zeile (zum Beispiel Laufwerk oder Dienst, kann leer sein = `-`) | vorheriger Status (`OK`, `Pending`, `Unknown` oder `-` bei der ersten Prüfung) | - | - |
| 4099 | fester Text | begrenzte Ereignis-ID | Zahl der ausgelassenen Einträge | - | - | - |

Beispiel (PowerShell, als Administrator oder Nutzer):
`Get-WinEvent -FilterHashtable @{ LogName = 'SelfX'; Id = 4012 } | ForEach-Object { $_.Properties[1].Value }`
listet die Skripte der fehlgeschlagenen Aktionen.

Eine fehlgeschlagene Installation einer Unternehmens-App bekommt kein eigenes Ereignis: Sie
erscheint als Ereignis 4013 für die Zeile `Applications`.

### Die Dateilisten `SelfX.Code.json` und `SelfX.Config.json`

Der Paketbau schreibt den SHA256 jeder installierten Datei in eine von zwei Listen.
`SelfX.Code.json` enthält die Programme, Bibliotheken sowie die Skripte, Sprachdateien und Bilder
des Projekts; `SelfX.Config.json` enthält die Einstellungsdateien, alles unter `Branding` und Ihre
eigenen Skripte und Sprachdateien. Jede Datei steht in genau einer Liste; eine Datei in beiden
Listen, in keiner oder in der falschen Liste wird abgelehnt. Die Listen werden bei jedem Bau neu
erzeugt; Sie müssen nichts von Hand pflegen. Ein geändertes Firmenlogo ändert nur
`SelfX.Config.json`. Frühere Versionen hatten eine einzige Liste `SelfX.Files.json`; die
Installation ersetzt sie.

- `Install.ps1` prüft vor und nach dem Kopieren, dass jede Datei zur Liste passt und keine
  Datei ohne Eintrag im Paket liegt.
- Der Dienst prüft vor **jedem** Start (Aktion, Gesundheitsprüfung, Hintergrundprüfung), dass
  alle gelisteten Dateien unverändert sind, dass keine Datei ohne Eintrag im Ordner liegt und
  dass keine Verknüpfung im Weg ist. Bei einer Abweichung startet er nichts und schreibt
  Ereignis 4005.
- Davor liest der Dienst den Vertrauensanker, den `Install.ps1` geschrieben hat (Ereignis 4006,
  wenn er fehlt, ungültig oder nicht geschützt ist). Ein mit `-TrustedSigner` installiertes Gerät
  prüft vor jedem Start zusätzlich Signaturen: die zwei Listen gegen die signierten Kataloge, jedes
  gelistete Skript und jede Bibliothek über die eingebettete Signatur, die Einstellungsdateien gegen
  `SelfX.Config.cat` (Ereignis 4007). Die geprüften Dateien bleiben geöffnet und damit unveränderbar,
  bis das Skript beendet ist. Die Sperrprüfung nutzt nur den lokalen Zwischenspeicher, der Dienst
  wartet also auf einem Gerät ohne Netz nicht
  ([Architektur](Architecture.md#der-modus-signatur-im-dienst)).
- Für den ersten Rollout können Sie `Service_FileCheck` auf `Audit` stellen (nur
  protokollieren).
- Die Bibliotheken `WinRT\*.dll` (Windows-Update-Schnittstelle) `Audio\SelfXAudio.dll`
  (Aktion „Kein Ton an diesem PC“) und `Disturb\SelfXDisturb.dll` (Hinweis vor störenden Aktionen) werden zusätzlich **beim Laden** geprüft und dabei
  geöffnet gehalten, damit sie nicht zwischen Prüfung und Laden ersetzt werden können.
- Grenze: Die Prüfung erkennt Unfälle (defektes oder halbes Update) und eine ausgetauschte
  `SelfX.exe`, aber keinen Angreifer mit Administratorrechten. Dagegen helfen die
  Ordnerrechte und App Control.

Welche Datei zu welcher Klasse gehört, die Aufteilung in eine Code-Liste und eine
Konfigurationsliste sowie die geplanten Vertrauensmodi beschreibt die [Architektur](Architecture.md).

### Ausführungsrichtlinie `-ExecutionPolicy Bypass`

Dienst, Starter, Fenster, Statussymbol und Gesundheitsprüfung starten PowerShell mit
`-ExecutionPolicy Bypass`. Das ist gewollt: Die Skripte liegen im geschützten
Installationsordner, und die Ausführungsrichtlinie ist ohnehin keine Sicherheitsgrenze.
Schutz bieten die Dateiliste und App Control.

Erzwingt Ihre Gruppenrichtlinie `AllSigned`, hat `Bypass` keine Wirkung. Signieren Sie dann
alle SelfX-Skripte (die Dateien in `Sources`, alle Prüf- und Aktionsskripte, auch
`Collect-DeviceLogs.ps1`) mit einem vertrauenswürdigen Codesignatur-Zertifikat. Ein eigenes
Signaturkonzept gibt es nicht.

### Rechte des Dienstes

Der Dienst läuft als LocalSystem. `Install.ps1` begrenzt sein Token mit `sc.exe privs` auf die
nötigen Rechte (`Service_Privileges` = `Restricted`, Standard). Gefährliche Rechte wie
`SeTcbPrivilege`, `SeDebugPrivilege`, `SeCreateTokenPrivilege`, `SeLoadDriverPrivilege` und
`SeSecurityPrivilege` hat der Dienst dann nicht.

| Recht | Wofür |
|---|---|
| `SeChangeNotifyPrivilege` | jeder Prozess |
| `SeImpersonatePrivilege` | Pipe-Client prüfen |
| `SeCreateGlobalPrivilege` | globale Objekte des Dienstes |
| `SeShutdownPrivilege` | Aktion Neustart |
| `SeSystemtimePrivilege` | Zeit synchronisieren |
| `SeBackupPrivilege`, `SeRestorePrivilege`, `SeTakeOwnershipPrivilege` | Dateireparaturen (zum Beispiel Spooler) |
| `SeManageVolumePrivilege` | Datenträgerprüfung |

Prüfen: `sc.exe qprivs SelfXService`. Schlägt das Setzen fehl, meldet `Install.ps1` nur eine
Warnung (Autopilot scheitert nie daran). `Service_Privileges` = `Default` lässt alle Rechte
und ist nur für die Fehlersuche gedacht. Testen Sie vor der Verteilung jede System-Aktion
einmal auf einem Testgerät.

## Fehlerbehebung

| Meldung oder Lage | Bedeutung und Lösung |
|---|---|
| `The command dotnet was not found` | Das .NET SDK 10 fehlt, oder das PowerShell-Fenster ist älter als die Installation. SDK installieren und ein neues Fenster öffnen. |
| `The .NET SDK 10 is required, found '…'` | Es ist kein SDK 10 installiert. Bei mehreren SDKs wählt die `global.json` im Repository automatisch SDK 10. |
| `The offline feed folder … does not exist` oder `SelfX.OfflineFeed.json is missing` | Der Ordner `offline-feed` fehlt oder ist leer. Export auf einem Rechner mit Internet ausführen (Abschnitt „Offline-Build“) und den Ordner kopieren. |
| `… does not match its SHA512` oder `… not listed in SelfX.OfflineFeed.json` | Ein Paket im Ordner `offline-feed` wurde verändert oder ergänzt. Ordner aus dem Repository wiederherstellen oder den Export wiederholen. |
| `The offline feed was exported with .NET SDK …` | Auf dem Build-Rechner ist eine andere SDK-Version installiert als beim Export. Dieselbe Version installieren oder den Export mit dieser Version wiederholen. |
| `NU1101` oder `NU1102` beim Bau | Ein Paket fehlt im Ordner `offline-feed`. Export wiederholen. |
| `The folder Bin is missing …` | Schritt 2.3 fehlt oder wurde vor dem Paketbau nicht ausgeführt. Schritt 2.3 und 2.5 wiederholen. |
| `Bin was not built from the current …` | Ein Quelltext wurde nach dem Bauen geändert. Schritt 2.3 und 2.5 wiederholen. |
| Installation endet mit Exitcode 1 | Den Grund nennt die letzte Zeile von `Install.log`. Die bisherige Installation bleibt unverändert. |
| `Trust mode Signature: … have no valid signature of an allowed signer` | Ein Programm oder Skript des Pakets ist nicht signiert, wurde nach dem Signieren geändert, ist von einem Zertifikat signiert, das nicht in `-TrustedSigner` steht, oder seine Zertifikatskette ist auf dem Gerät nicht vertrauenswürdig (Grund in Klammern: `NotSigned`, `HashMismatch`, `SignerNotAllowed`, `NotTrusted`). Diese Meldung steht nicht in `Install.log`: zum Lesen den Installationsbefehl in einer Konsole mit erhöhten Rechten ausführen. |
| `… is not a valid signed catalog …` | Eine Datei wurde nach dem Signieren des Katalogs geändert, hinzugefügt oder entfernt (die Meldung nennt sie), oder der Katalog fehlt oder ist von einem anderen Zertifikat signiert. Das Paket neu signieren. |
| `This device is in the trust mode Signature …` | Das Gerät wurde mit `-TrustedSigner` installiert, und der Installationsbefehl enthält den Parameter nicht. `-TrustedSigner` ergänzen, oder `-AllowHashMode`, um bewusst auf ein unsigniertes Paket zu wechseln. |
| `The package is signed … but -TrustedSigner was not given` | Ein signiertes Paket wurde ohne `-TrustedSigner` installiert. Den Parameter im Installationsbefehl ergänzen. |
| `-TrustedSigner: every entry must be a SHA1 thumbprint …` | Der Wert enthält ein Leerzeichen, ein anderes Zeichen oder einen leeren Eintrag. Je Fingerabdruck 40 Hexadezimalzeichen verwenden, Kommas ohne Leerzeichen. |
| Intune erkennt SelfX nach dem Update auf diese Version nicht | Der Vertrauensanker fehlt (`Detection_<Datum>.log`: `trust anchor missing`). Intune installiert das Paket erneut; danach ist der Anker vorhanden. |
| Intune erkennt ein Update nicht | `Version.txt` und `$ExpectedVersion` sind gleich geblieben, oder Sie haben die Kopie aus dem Repository statt `build\SelfX-Service-<Version>.Detection.ps1` hochgeladen. |
| Defender blockiert ein SelfX-Programm (Defender-Benachrichtigung, Ereignis 1121 für die Regel `01443614-cd74-433a-b99e-2ecdc07bfc25`) | Die ASR-Regel für ausführbare Dateien hat gegen die Datei entschieden. Finden Sie die Datei mit `tools\Get-SelfXAsrEvents.ps1` und folgen Sie [Defender ASR: Regel für ausführbare Dateien](#defender-asr-regel-für-ausführbare-dateien). |
| SelfX startet keine Aktion | PowerShell 7.6 fehlt (Warnung im `Install.log`), oder Ereignis 4005 meldet eine abweichende Datei. Das SelfX-Protokoll nennt die Einzelheiten. |
| SelfX startet keine Aktion, Ereignis 4006 | Der Vertrauensanker `HKLM\SOFTWARE\SelfX\Trust` fehlt (Installation eines früheren Builds), wurde geändert, oder seine Rechte erlauben anderen Identitäten als SYSTEM und Administratoren eine Änderung. Paket neu installieren; `Install.ps1` schreibt den Anker mit den richtigen Rechten. |
| SelfX startet keine Aktion, Ereignis 4007 | Gerät mit `-TrustedSigner` installiert: Das SelfX-Protokoll (`SelfXService.log`) nennt Datei und Grund. `UntrustedRoot` oder `Chaining`: Die Zertifikatskette des Signierers ist auf dem Gerät nicht (mehr) vertrauenswürdig. `Expired`: Das Zertifikat ist abgelaufen und die Signatur hat keinen Zeitstempel. `Revoked`: Das Zertifikat wurde gesperrt. `SignerNotAllowed`: Der Signierer steht nicht in `Signers` des Ankers (mit dem neuen Fingerabdruck in `-TrustedSigner` neu installieren). `NoSignature`, `BadDigest`, `NotInCatalogOrCatalogUnsigned`: Eine Datei wurde geändert oder ist nicht signiert; Paket neu installieren. |

## Checkliste für die Bereitstellung

1. Konfiguration angepasst (Branding, Support-Kontakte, Funktionen) und alle XML-Dateien
   gültig.
2. `Version.txt` und `$ExpectedVersion` sind gleich und neu; Verlauf in `Detection.ps1`
   ergänzt.
3. Alle Tests laufen ohne Fehler.
4. Programme gebaut, AppLocker-Regeln ersetzt (falls genutzt).
5. Paket gebaut; `.intunewin` **und** `…Detection.ps1` aus `build` verwendet.
6. PowerShell 7 als Win32-App und als Abhängigkeit eingerichtet; Voraussetzungsregel
   Windows 11 25H2 gesetzt; weder SelfX noch PowerShell 7 blockieren die ESP.
7. Auf einem Testgerät geprüft (Neuinstallation, Update, Deinstallation, Standardnutzer,
   Autopilot; nutzt Ihr Mandant die ASR-Regel für ausführbare Dateien, auch deren Ereignisse:
   [Defender ASR](#defender-asr-regel-für-ausführbare-dateien)).
8. Erst mit einer Pilotgruppe verteilen, dann breit.
