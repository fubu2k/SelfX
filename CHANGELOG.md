# Änderungsprotokoll

[English](CHANGELOG.en.md) | **Deutsch**

Dieses Protokoll beschreibt, was sich in diesem Fork ([fubu2k/SelfX](https://github.com/fubu2k/SelfX))
gegenüber seinem Upstream [wbaeck/SelfX](https://github.com/wbaeck/SelfX) bei SelfX Service
2.6.9 geändert hat. Alles bis Version 2.6.9 stammt aus dem Upstream und wird hier nicht
als neu aufgeführt. Der Verlauf jeder Datei steht in ihrem Kopf.

Die Paketversion ist die eine Zeile in `SelfX Service\Version.txt`; der Bau schreibt sie in `SelfX.Code.json`
(`ToolVersion`). `Detection.ps1` muss denselben Wert enthalten, sonst erkennt Intune das Update nicht
(das Paketierungsskript prüft das). Ein Release bekommt das Tag `v<Version>` (zum
Beispiel `v3.0.0`); der Release-Workflow prüft, dass Tag und `Version.txt` übereinstimmen.

## Unveröffentlicht (SelfX Service)

- **Vertrauensmodus im Dienst (`SelfXService.exe`, Version 3.1.0):** Vor jedem Start eines Skripts liest der Dienst den Vertrauensanker
  `HKLM\SOFTWARE\SelfX\Trust` (64-Bit-Sicht). Ein Anker, der fehlt, ungültig ist (`Mode` nicht `Hash` oder `Signature`; im Modus Signatur
  `Signers` keine Liste von 1 bis 10 SHA1-Fingerabdrücken) oder nicht geschützt ist (Besitzer nicht SYSTEM `S-1-5-18` oder
  Administratoren `S-1-5-32-544`, oder eine andere Identität darf den Schlüssel ändern), startet nichts: neues **Ereignis 4006**.
  `Mode` = `Hash`: Verhalten wie bisher. `Mode` = `Signature` (docs/de/Architecture.md, „Der Modus Signatur im Dienst“): Die Listen, die
  Kataloge und jede gelistete Datei werden einmal geöffnet (lesbar, nicht schreibbar, ersetzbar, umbenennbar oder löschbar) und
  bleiben offen, bis das gestartete Skript beendet ist; `SelfX.Code.json` muss Mitglied der signierten `App\SelfX.Code.cat` sein und
  `SelfX.Config.json` Mitglied der signierten `Config\SelfX.Config.cat`; die Dateiprüfung läuft auf den offenen Handles; jede gelistete
  `.ps1`, `.psm1`, `.psd1` und `.dll` muss eine eingebettete Signatur tragen; jede Einstellungsdatei muss Mitglied von
  `SelfX.Config.cat` sein. Eine Signatur zählt, wenn Windows sie akzeptiert (`WinVerifyTrust`) und der Signierer in `Signers` steht.
  Eine fehlgeschlagene Signaturprüfung startet nichts, auch mit `Service_FileCheck` = `Audit`: neues **Ereignis 4007**. Die
  Sperrprüfung nutzt nur den lokalen Zwischenspeicher (kein Netzabruf). Positive Ergebnisse werden je Datei 60 Minuten behalten (Pfad,
  Schreibzeit, Größe und SHA256 des offenen Handles; nie negative Ergebnisse; die Liste der Signierer gilt bei jedem Start). Kein
  neues Paket: Die Aufrufe von Windows erfolgen direkt (Klasse `SelfXTrust`). **`Install.ps1`:** Im Modus Signatur werden die zwei
  Kataloge jetzt neben ihren Listen installiert (`SelfX.Code.cat` nach `App`, `Config\SelfX.Config.cat` nach `Config`) und nach dem
  Kopieren mit den geprüften Katalogen verglichen (`Copy-SelfXPayload -SignedPackage`, `Test-SelfXInstalledFiles -SignedPackage`,
  `Test-SelfXInstalledLists`); im Modus Hash wird kein Katalog installiert. **Geändertes Verhalten:** Eine Installation ohne Anker
  (installiert, bevor es den Anker gab; Dienst von Hand ersetzt) startet keine Aktion, bis das Paket neu installiert ist. Neu für den
  Versuch hinter der Prüfung: `tools\SelfXTrustProbe.cs` und `tools\Measure-SelfXTrustCheck.ps1` (Fälle und Zeit je Prüfung auf einem
  Gerät). Tests: `Test-ServicePipe.ps1` (Anker fehlt, ungültig und unsicher; festgehaltene Dateien; mit Testzertifikaten: falscher
  Signierer, veränderte XML, fehlender und unsignierter Katalog, unsigniertes und verändertes Skript, unsignierte Bibliothek,
  Zwischenspeicher), `Test-InstallBinaries.ps1` (Kopierschritt mit Katalogen). Nicht Teil dieser Änderung: Die Paketwerkzeuge
  signieren noch nicht.
- **Vertrauensmodus Signatur in `Install.ps1` (`-TrustedSigner`, Version 3.1.0):** `Install.ps1 -TrustedSigner <Fingerabdruck>[,<Fingerabdruck>]`
  installiert ein signiertes Paket (docs/de/Architecture.md, „Der Modus Signatur in `Install.ps1`“). Die Liste enthält SHA1-Fingerabdrücke
  mit 40 Hexadezimalzeichen (höchstens 10, durch Kommas getrennt; alles andere bricht die Installation ab, auch ein angegebener, aber
  leerer Parameter). Vor jeder Änderung am Gerät, auch bevor der Datenordner vorbereitet wird: keine Verknüpfung im Paket; jede `.exe`,
  `.dll`, `.ps1`, `.psm1` und `.psd1` trägt eine Signatur mit dem Status `Valid` eines Signierers der Liste; `Config\SelfX.Config.cat`
  ist von einem Signierer der Liste signiert, verwendet SHA256 und passt zum Ordner `Config`; der neue Katalog `SelfX.Code.cat` oben im
  Paket ist von einem Signierer der Liste signiert und passt zu allem außerhalb von `Config` (damit sind auch `SelfX.Code.json`, die
  Sprachdateien, die Bilder, `SelfX.Binaries.json` und die Quellen abgedeckt). Die Prüfungen von `SelfX.Binaries.json`,
  `SelfX.Code.json` und `SelfX.Config.json` bleiben; nach dem Kopieren müssen die installierten Listen die Listen sein, die die Kataloge
  abgedeckt haben. Die Kataloge werden im Paket geprüft und nicht installiert. Neue Funktionen: `ConvertTo-SelfXTrustedSignerList`,
  `Resolve-SelfXTrustMode`, `Test-SelfXFileSignature`, `Test-SelfXPackageCatalog`, `Test-SelfXPackageSignatures`,
  `Test-SelfXInstalledLists`, `Get-SelfXTrustAnchor`, `Set-SelfXTrustAnchor`, `Test-SelfXTrustAnchorState`. **Vertrauensanker:** In
  beiden Modi schreibt `Install.ps1` `HKLM\SOFTWARE\SelfX\Trust` (`Mode` = `Hash` oder `Signature`; `Signers` als `REG_MULTI_SZ` im Modus
  Signatur), bevor der Dienst registriert wird: Besitzer Administratoren (`S-1-5-32-544`), Rechte nicht vererbt, SYSTEM (`S-1-5-18`) und
  Administratoren Vollzugriff, Benutzer (`S-1-5-32-545`) lesen; der Anker wird zurückgelesen und seine Rechte werden geprüft.
  **Herabstufung:** Ein Gerät, dessen Anker `Signature` sagt (oder sich nicht deuten lässt), wird ohne `-TrustedSigner` nur mit dem
  neuen Schalter `-AllowHashMode` installiert; beides zusammen ist ein Fehler. Ein signiertes Paket ohne `-TrustedSigner` wird mit einem
  Hinweis abgelehnt. Ohne `-TrustedSigner` arbeitet der Modus Hash wie bisher. **Geändertes Verhalten:** Die Parameter von `Install.ps1`
  werden nur über ihren Namen gebunden (`-InstallFolder <Pfad>` statt eines Pfads ohne Namen). `Detection.ps1` verlangt den Anker
  (`Test-SelfXTrustAnchor`, 64-Bit-Sicht; der Modus wird protokolliert und nicht bewertet); eine Installation eines früheren Stands wird
  deshalb einmal erneut installiert. `Uninstall.ps1` entfernt den Anker (`HKLM\SOFTWARE\SelfX\Support` bleibt). Sperrprüfung: Es wird die
  Prüfung von Windows verwendet; neu `tools\Measure-SelfXRevocationDelay.ps1` misst auf einem Gerät, wie lange
  `Get-AuthenticodeSignature` braucht, wenn die Sperrlisten-Adresse des Zertifikats nicht erreichbar ist. Tests:
  `Test-InstallBinaries.ps1` (Liste der Signierer, Modus und Herabstufung, alle Ablehnungen von Signaturen und Katalogen mit ersetzten
  Cmdlets, Kopierschritt, Anker in einem Testschlüssel unter HKCU, gleiche Antworten wie `tools\SelfXSigning.ps1`; mit vertrauenswürdigem
  Teststamm auch echte Signaturen und Kataloge), `Test-Detection.ps1` (Anker). Nicht Teil dieser Änderung: Die Paketwerkzeuge signieren
  noch nicht, und der Dienst liest den Anker noch nicht.
- **Korrektur (Tests): `tools\Test-SelfXSigning.ps1` hält die CI-Jobs „Signing library“ nicht mehr an.** Teil 2 fügte seine
  Testzertifikate in `Cert:\CurrentUser\Root` ein; dort stellt Windows eine Rückfrage, und ein Prozess ohne Desktop wartet darauf, bis der
  Job abgebrochen wird. Mit Administratorrechten verwendet der Test jetzt `Cert:\LocalMachine\Root` (keine Rückfrage); auf GitHub Actions
  läuft Teil 2 nur mit Administratorrechten. Zwei Erwartungen folgen dem, was Windows meldet: Ein Skript mit Text hinter dem
  Signaturblock hat den Status `NotSigned`, ein vor dem Block geändertes Skript `HashMismatch`. `tools\SelfXSigning.ps1` ist unverändert.
- **Signaturbibliothek (`tools\SelfXSigning.ps1`, nur Werkzeuge, nicht Teil des Pakets):** Funktionen für den Vertrauensmodus „Signatur“
  (docs/de/Architecture.md), lauffähig in Windows PowerShell 5.1 und PowerShell 7: `Get-SelfXSigningCertificate` (Zertifikate aus
  `Cert:\CurrentUser\My` und `Cert:\LocalMachine\My` mit privatem Schlüssel, Schlüsselverwendung Codesignatur und gültigem Zeitraum, oder
  eine PFX-Datei mit `SecureString`-Kennwort, die nicht in einen Speicher importiert wird), `Set-SelfXCodeSignature` (SHA256, Kette ohne
  Stamm, optionaler http/https-Zeitstempeldienst; die gesamte Eingabe wird vor der ersten Signatur geprüft, jede Datei wird zurückgelesen),
  `New-SelfXSignedCatalog` (`New-FileCatalog` Version 2 und Signatur; bei einem Fehler beim Signieren bleibt kein unsignierter Katalog
  zurück), `Test-SelfXSignature` (Status `Valid` und Signierer in der Liste erlaubter Fingerabdrücke; nennt den Grund) und
  `Test-SelfXSignedCatalog` (Signierer und Ordnerinhalt; nennt geänderte, fehlende und zusätzliche Dateien). Das Kennwort wird nie in
  Klartext umgewandelt und erscheint in keiner Ausgabe, keinem Protokoll und keiner Meldung. Die Bibliothek wird noch von nichts verwendet.
  Tests: neu `tools\Test-SelfXSigning.ps1` (Teil 1 auf jedem System, Teil 2 mit selbstsignierten Testzertifikaten in `Cert:\CurrentUser`),
  neuer CI-Job „Signing library“ (Windows PowerShell 5.1 und PowerShell 7).
- **Text-Überschreibungen (`Config\Texts\<Kultur>.xml`, Version 3.1.0):** Ein Unternehmen kann einzelne Texte ersetzen, ohne
  eine mitgelieferte Sprachdatei zu ändern. Die optionale Datei hat das Format der Sprachdateien und enthält nur die zu
  ändernden Texte (`UI`, `SystemInfo`, `Catalog`); sie ist Konfiguration (Klasse Config, in `SelfX.Config.json` gelistet) und
  wird nach `%ProgramFiles%\SelfX\Config\Texts` installiert. `Localization.ps1` lädt erst die mitgelieferte Datei, dann die
  Überschreibung der Kultur der geladenen Datei (`de-CH` nutzt `Texts\de.xml`): `Initialize-SelfXLanguage -TextOverrideFolder`,
  neue Funktionen `Read-SelfXTextOverride`, `Test-SelfXOverrideText`, `Set-SelfXTextOverride`, `Import-SelfXTextOverride`,
  `Get-SelfXTextEntries`, `Get-SelfXTextReference`; den Ordner liefert `Get-SelfXTextOverrideFolder` (`SelfXPaths.ps1`).
  Ein Text gilt nur, wenn seine Kennung in einer mitgelieferten Datei bekannt ist, er nur einmal vorkommt, nicht leer und nicht
  länger als 1500 Zeichen ist, kein Markup (kein `<`, keine Entität wie `&amp;`), keine Steuerzeichen und dieselben Platzhalter
  wie der mitgelieferte Text hat; die Copilot-Prompts lassen sich nicht überschreiben. Unbekannte Kennungen und abgelehnte Texte
  werden ignoriert und im Protokoll des Nutzers vermerkt (Kennung und Grund, nie ein Text). Die Datei wird einmal als Bytes
  gelesen, darf kein Link, nicht größer als 256 KB und ohne DTD sein; die Attribute des Wurzelelements einer Überschreibung
  werden nicht verwendet, sie kann also keine Sprache hinzufügen oder ersetzen. Platzierungsregel (`Install.ps1`,
  `tools\SelfXPackage.Common.ps1`, `SelfXService.cs`, `SelfXPaths.ps1`): `Texts/<Kultur>.xml` ist in `SelfX.Config.json`
  erlaubt; unter `Texts` darf nichts in `SelfX.Code.json` stehen. `Test-LanguageFiles.ps1` prüft die Text-Überschreibungen
  (`-TextsFolder`) mit denselben Funktionen. Doku: `docs/de/Configuration.md` (Abschnitt „Einzelne Texte ändern“),
  `docs/de/Architecture.md` (DE und EN). Tests: neu `Test-TextOverrides.ps1`; erweitert `Test-FileManifest.ps1`,
  `Test-ConfigPath.ps1`, `Test-ServicePipe.ps1`.
- **Paket und Gerät, Code und Konfiguration in zwei Ordnern (Version 3.1.0):** Das Paket hat statt `Sources` die Ordner
  `App` (Code) und `Config` (Konfiguration); `tools\New-SelfXIntuneWin.ps1` sortiert die Dateien aus `Sources` nach ihrer
  Dateiklasse (`ConvertTo-SelfXPackageLayout` in `tools\SelfXPackage.Common.ps1`, eine Datei ohne Klasse bricht den Bau ab).
  Auf dem Gerät liegen Programme, Bibliotheken, Skripte, Sprachdateien und Standardbilder des Projekts, `Uninstall.ps1` und
  `SelfX.Code.json` in `%ProgramFiles%\SelfX\App`, die Einstellungsdateien, `Branding`, eigene Skripte und Sprachdateien und
  `SelfX.Config.json` in `%ProgramFiles%\SelfX\Config`; die Rechte sind unverändert (Benutzer `S-1-5-32-545` nur Lesen und
  Ausführen). Ein Pfad-Auflöser: `Sources\SelfXPaths.ps1` (`Get-SelfXConfigPath`, `Get-SelfXImagePath`,
  `Resolve-SelfXScriptPath`, Windows PowerShell 5.1 und PowerShell 7) und im Dienst `GetConfigRoot`, `GetConfigFilePath`,
  `ResolveScriptPath`; der Konfigurationsordner ist `Config` neben einem Code-Ordner namens `App`, sonst der Code-Ordner
  selbst. Der Dienst lädt Katalog, `Health_Config.xml` und `Tool_Config.xml` nur aus `Config` und Skripte des Projekts nur
  aus `App`; ein eigenes Skript unter `Config` startet nur, wenn Katalog oder `Health_Config.xml` es nennen und
  `SelfX.Config.json` es mit seinem aktuellen SHA256 führt, auch bei `Service_FileCheck` = `Audit`; ein Projektskript gleichen
  Namens hat Vorrang (ebenso in `Self_X.ps1` für Nutzeraktionen und in `HealthStatus.ps1` für eigene Prüfskripte). Die
  Dateiprüfung von Dienst und `Install.ps1` vergleicht jeden Ordner nur mit seiner Liste und lässt neben `App` und `Config`
  nichts zu (leere, noch benutzte Ordner ausgenommen). Bilder: `Branding\...` in `Config`, andere relative Werte in `App`.
  Eigene Sprachdateien in `Config\Languages` werden angeboten, ersetzen aber keine mitgelieferte Sprache. Umstellung:
  `Install.ps1` 3.1.0 entfernt eine Installation im alten Aufbau vollständig vor dem Kopieren (neue Funktionen
  `Clear-SelfXInstallFolder`, `Copy-SelfXPayload`) und lehnt ein Paket im alten Aufbau ab; `Uninstall.ps1` 3.1.0 entfernt
  beide Aufbauten und liest `Tool_Config.xml` ohne DTD; `Detection.ps1` 3.1.0 erkennt nur den neuen Aufbau. **Achtung:**
  Eigene Skripte, die `SelfXLog.ps1` oder `SelfXOffice.ps1` über `Split-Path -Parent $PSScriptRoot` suchen, müssen angepasst
  werden (`docs/Configuration.md`, Abschnitt „Eigene Skripte der Firma“). `Version.txt` und `Detection.ps1` stehen auf 3.1.0.
  Tests: neu `Test-ConfigPath.ps1`; erweitert `Test-FileManifest.ps1`, `Test-InstallBinaries.ps1` (Update 3.0.2 → 3.1.0,
  Mischzustand, gesperrte Datei), `Test-Uninstall.ps1`, `Test-Detection.ps1`, `Test-ServicePipe.ps1`, `Test-Compat51.ps1`.
- **Paket, die Version ist eine Eigenschaft des Codes (`Version.txt`, `SelfX.Code.json`):** Die Version steht nicht mehr in der
  Einstellungsdatei `Tool_Config.xml`. Die neue Datei `SelfX Service\Version.txt` (eine Zeile) ist die einzige Quelle; der Bau
  schreibt sie in `ToolVersion` von `SelfX.Code.json`. Eine neue Version ändert damit keine Konfigurationsdatei, und eine geänderte
  Konfiguration (zum Beispiel ein Logo) ändert die Version nicht. `SelfX.Config.json` hat `ConfigRevision` (UTC-Zeit des Paketlaufs,
  nicht Teil des Digests) statt `BuiltUtc`. Leser angepasst: `Detection.ps1` 3.0.4 vergleicht `$ExpectedVersion` mit `ToolVersion` der
  installierten `SelfX.Code.json` (neue Funktion `Test-SelfXInstalledPackage`: Code-Version, Code-Digest und Konfigurations-Digest
  werden getrennt gemeldet); `Install.ps1` 2.9.1 liest die Version aus der geprüften `SelfX.Code.json` und lehnt ein Paket ohne sie ab,
  bevor etwas geändert wird (ein Paket ohne die beiden Listen wurde bisher mit Warnung installiert); `Self_X.ps1` 2.8.27 zeigt die
  Version aus `SelfX.Code.json` an (`?`, wenn sie nicht gelesen werden kann); `release.yml` vergleicht das Tag mit `Version.txt`;
  `New-SelfXIntuneWin.ps1` 1.10.0, `New-SelfXPackage.ps1` 1.0.1, `Build-SelfXBinaries.ps1` 2.8.21 und `New-SelfXWdacPolicy.ps1`
  1.0.1 lesen `Version.txt` (`Get-SelfXVersionFromFile` in `tools\SelfXPackage.Common.ps1` erlaubt eine Zeile mit höchstens 30
  Buchstaben, Ziffern, `.` und `-`). `Version.txt` gehört nicht zum Paket. Ein altes Element `Tool_Version` in der `Tool_Config.xml`
  einer Firma wird ignoriert. Kein Text der Oberfläche geändert. Tests: Versionswechsel lässt alle Konfigurationsdateien
  unverändert, Konfigurationswechsel lässt Version und Code-Liste unverändert, getrennte Erkennung von Code-Version, Code-Dateien und
  Konfiguration, Negativtests für `Version.txt`, `ConfigRevision`, `ToolVersion` und eine beschädigte Code-Liste sowie eine Prüfung,
  dass kein Skript, Werkzeug oder Workflow `Tool_Version` liest.
- **Paket, zwei Dateilisten (`SelfX.Code.json`, `SelfX.Config.json`):** `SelfX.Files.json` wird durch zwei Listen ersetzt.
  `SelfX.Code.json` enthält die Programme, Bibliotheken sowie die Skripte, Sprachdateien und Bilder des Projekts;
  `SelfX.Config.json` enthält die Einstellungsdateien, alles unter `Branding` sowie eigene Skripte und Sprachdateien. Jede Datei
  steht in genau einer Liste, eine unbekannte Datei stoppt den Bau, und eine Datei in beiden Listen oder in der falschen Liste wird
  abgelehnt. Die Code-Liste hat keine Bauzeit, ein geändertes Firmenlogo ändert daher nur `SelfX.Config.json` und den
  Konfigurations-Digest. Neu: `tools\SelfXPackage.Common.ps1` (Dateiklassen, beide Listen, Digest, Schreiber der `Detection.ps1`).
  `Install.ps1` 2.9.0 prüft Paket und installierten Ordner gegen beide Listen; `Detection.ps1` 3.0.3 prüft zwei Digests; der Dienst
  (2.9.0) liest beide Listen mit denselben Regeln (Ereignis 4005 und `Service_FileCheck` unverändert); `SelfXWinRT.ps1` und
  `SelfXAudio.ps1` lesen die Hashes ihrer Bibliotheken aus `SelfX.Code.json`. `Tool_Version` bleibt unverändert. Tests angepasst und
  erweitert (Logo-Test, Klassen- und Platzierungstests, Negativtests).
- **Dokumentation, Architektur:** Neu `docs/de/Architecture.md` (Englisch: `docs/Architecture.md`): die drei Dateiklassen (Code,
  Konfiguration, eigener Code der Firma), die Zuordnung jeder Datei des Pakets SelfX Service, die geplanten Listen `SelfX.Code.json`
  und `SelfX.Config.json`, die Vertrauensmodi Hash und Signatur, der Vertrauensanker und die Grenze der Prüfungen gegenüber einem
  lokalen Administrator. Sie nennt auch die Dateien, deren Klasse noch offen ist. Verlinkt aus README und Installationsanleitung.
  Keine Codeänderung.
- **Sicherheit, Berichtsdatei (`Collect-DeviceLogs.ps1` 1.3.6):** Eine Berichtsdatei wird nur noch überschrieben, wenn sie vorhanden war
  und als vertrauenswürdig geprüft wurde. Nach dem Entfernen einer untergeschobenen Datei wird immer neu angelegt (`CreateNew`), sodass
  eine Datei, die ein Nutzer in der Lücke anlegt, nicht beschrieben wird. Ein Standardbericht (`-Protect`) wird ohne Freigabe geöffnet:
  Bis die Zugriffsrechte gesetzt sind, kann niemand ein Lese-Handle halten. `-UserView` akzeptiert nur die SID eines Benutzerkontos.
- **Export der Systeminformationen (`SystemInfo.ps1` 2.8.26):** Der Dateiname aus dem Speichern-Dialog wird wörtlich verwendet
  (`-LiteralPath`). Ein Name mit `[` `]` schlug fehl oder konnte andere Dateien treffen.

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
