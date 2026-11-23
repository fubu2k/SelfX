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

## Nicht veröffentlicht (SelfX Service)

### Neu
- Neue Aktion „Diesen PC auf Viren prüfen (Microsoft Defender Schnellscan)“ (Systemkontext über den SelfX-Dienst, Kategorie Gerät, Detailansicht, `SelfX_Defender_QuickScan.ps1`): startet einen Schnellscan über CIM (`MSFT_MpScan.Start`, ScanType 1), wartet bis zum Ende (Dienst-Zeitlimit 40 Minuten) und liest danach die Funde seit dem Start (`MSFT_MpThreatDetection`, `MSFT_MpThreat`). Das Ergebnis wird als Meldung angezeigt: keine Bedrohung gefunden (Exit 0) oder Bedrohung gefunden (Exit 2, Warnung mit Hinweis auf die Windows-Sicherheit); Exit 1 bei Fehler oder wenn Defender nicht aktiv ist (z. B. anderes Antivirenprodukt). Protokolliert werden nur Anzahl und Bedrohungsnamen, keine Dateipfade. SelfX löscht, verschiebt oder ändert nichts; die Behandlung folgt der Defender-Richtlinie. Gesperrt, solange ein anderer Nutzer angemeldet ist (`OtherSessions=Block`). Neue Funktionen `Start-SelfXDefenderQuickScan` und `Get-SelfXDefenderDetection` in `SelfXDefender.ps1`, Tests in `Test-Scripts.ps1`, Texte in allen 24 Sprachdateien. Die ursprüngliche Vorlage (Vollscan als Job, Ergebnis immer „keine Bedrohung“) wurde nicht übernommen.
- Neue Aktion „Office fordert zur Aktivierung auf oder meldet ein nicht lizenziertes Produkt“ (Nutzerkontext, Kategorie Office, Detailansicht, `SelfX_Office_ResetLicence.ps1`): beendet die Office-Apps der eigenen Sitzung (Word, Excel, PowerPoint, Outlook, Access, OneNote, Publisher, Visio, Project, Skype for Business; Teams nicht) und entfernt nur den Inhalt der Lizenz-Token-Ordner des Benutzers: `%LOCALAPPDATA%\Microsoft\Office\Licenses` und `\Microsoft\Office\<Version>\Licensing` jeder vorhandenen Version. Unabhängig von Office-Version, Bitness und Installationsart (kein fester Pfad `16.0`). Registry, Dokumente, Einstellungen und Programmdateien werden nicht verändert; Links (Junctions, Symlinks) werden nie verfolgt. Beim nächsten Start meldet sich Office neu an. Ein Office-Programm, das sich nicht schließen lässt, bricht die Aktion ab, ohne etwas zu löschen. Neuer Helfer `Get-SelfXOfficeLicenseFolder` in `SelfXOffice.ps1`. Texte in allen 24 Sprachen, Katalog 2.4.6.
- Neue Aktion „Outlook schlägt falsche oder veraltete E-Mail-Adressen vor“ (Nutzerkontext, Kategorie Outlook, Detailansicht, `SelfX_Outlook_CleanAutoComplete.ps1`): beendet das klassische Outlook der eigenen Sitzung (bittet es zuerst um das Schließen, beendet es nach 10 Sekunden), startet es mit dem Schalter `/cleanautocompletecache` und leert so die AutoVervollständigen-Liste der vorgeschlagenen Adressen. Postfach, Kontakte und Profil bleiben unverändert; das neue Outlook ist nicht betroffen. Das Programm wird unabhängig von Office-Version, Bitness (32 oder 64 Bit) und Installationsart gefunden: Pfad des laufenden Outlook, App-Paths-Registrierung, Office-InstallRoot jeder installierten Version; verwendet wird nur eine Datei unterhalb von Program Files, im `PATH` wird nichts gesucht. Neuer Helfer `Sources\SelfXOffice.ps1` (Programmpfad, nur Prozesse der eigenen Sitzung), Tests `Test-OfficeHelper.ps1` und `Test-Scripts.ps1`. Texte in allen 24 Sprachdateien.
- Copilot Chat (Standard aus, `Copilot_Enabled`): Zeile *Copilot Chat fragen* im Hilfe-Dialog. Der Nutzer beschreibt das Problem, SelfX zeigt eine Vorschau des Textes (feste Liste von Gerätedaten aus `Sources\CopilotFacts.ps1`, Namen und Adressen als Platzhalter), kopiert ihn und öffnet die Adresse `Copilot_Url` (nur `https://`, frei wählbar). Der Nutzer fügt den Text selbst ein, SelfX sendet nichts und nutzt keine Schnittstelle. Neue Einstellungen `Copilot_Enabled`, `Copilot_Url`, `Copilot_Audience`, `Copilot_Include_AppNames`, Texte in allen 24 Sprachdateien, Test `Test-CopilotFacts.ps1`. Details in `docs/Configuration.md`.
- Grundlage für „Copilot Chat“ (`Sources\CopilotPrompt.ps1`, Test `Test-CopilotPrompt.ps1`): Baukasten, der aus wenigen geprüften Gerätedaten einen kurzen Prompt für Microsoft 365 Copilot Chat erzeugt. Nur eine feste Liste von Feldern kommt hinein, Namen, Adressen und Kennungen werden durch Platzhalter ersetzt (`<email>`, `<ip>`, `<device>`, `<server 1>` ...), die Länge ist begrenzt. Der Baukasten liest nichts vom Gerät, nutzt keine Zwischenablage und sendet nichts. Dazu die Prüfung der Adresse, die Copilot Chat öffnet (nur `https://`, keine Zugangsdaten).
- Systeminformationen: optionale Netzwerk-Messungen (Standard aus, Datei `Network_Test_Config.xml`): Antwortzeit zum Standardgateway sowie DNS-Abfragedauer und TCP-Verbindungsdauer zu bis zu 5 konfigurierten Zielen (interner oder aus dem Internet erreichbarer Domainname frei wählbar, nur Administratoren ändern die Datei, Hostname und Port streng geprüft, höchstens 20 Sekunden je Durchlauf, Nutzerkontext, nur lesend). Prüfwerkzeug `tools\Test-SelfXNetworkMeasure.ps1`, Test `Test-NetworkMeasure.ps1`.
- Ticket per E-Mail: Empfänger und Kopie lassen sich pro Gerät in der Registry setzen (`HKLM\SOFTWARE\SelfX\Support`: `TicketMail`, `TicketCc`, nur Administratoren schreibbar) und haben Vorrang vor den Regeln in `Ticket_Config.xml`. So trägt jedes Gerät nur die Adresse der eigenen Einheit. Doku: nur Funktionspostfächer; Beispielskript für Intune in der Installationsanleitung.
- Ticket per E-Mail: Zuordnung zur zuständigen IT-Einheit über die neue Datei `Ticket_Config.xml` mit beliebig vielen Einheiten (Empfänger, optionale Kopie) und Regeln für Group-Tag, OU und Gerätekategorie (exakter Wert oder Regex, erste passende Regel gilt, sonst Standardadresse). Group-Tag und Kategorie werden aus `HKLM\SOFTWARE\SelfX\Support` gelesen, die OU aus dem Computerkonto. Neu: `tools\Test-SelfXTicketRouting.ps1` zur Prüfung vor der Verteilung.
- Ticket per E-Mail (Standard aus, `Ticket_Enabled`): Schaltfläche *Ticket erstellen* im Hilfe-Dialog. Der Nutzer beschreibt das Problem, SelfX fügt immer alle Geräteinformationen hinzu (Text und Datei) und öffnet die E-Mail in klassischem Outlook (COM) oder im Standard-Mailprogramm (z. B. neues Outlook, mailto plus Datei im Explorer); gesendet wird nur vom Nutzer. Empfänger nur aus der Konfiguration (`Ticket_Mail`, sonst `Support_Mail`). Neue Datei `TicketSend.ps1`, Tests in `Test-Ticket.ps1`.
- Grundlage für „Ticket aus SelfX“ (`Sources\TicketMail.ps1`, Test `Test-Ticket.ps1`): Ticketmodell mit standardisiertem Betreff und Text, bereinigten Feldern, Freitext im abgesetzten Block und geprüftem mailto-Link. Nur Bausteine ohne Funktion und ohne Oberfläche; es ändert sich nichts für Nutzer.

- Systeminformationen: Die Zeile „Betriebszeit“ wird ab 7 Tagen ohne Neustart als Warnung mit dem Hinweis „Neustart empfohlen (nicht „Herunterfahren“)“ angezeigt (nur lesend; SelfX startet Windows nie selbst neu). Grund für den Hinweis: Mit Schnellstart setzt „Herunterfahren“ die Betriebszeit nicht zurück.
- Systeminformationen, Bereich Netzwerk: neue Zeilen „Proxy (Benutzereinstellung)“ (manueller Proxy mit Server und Port, Adresse des Konfigurationsskripts; Zugangsdaten in Adressen werden maskiert) und „Netzlaufwerke“ (nur die Laufwerksbuchstaben, auch getrennte, keine Freigabepfade). Nur lesend, keine Netzwerkzugriffe. Hinweis: Die Proxy-Adressen erscheinen auch im Export der Systeminformationen.
- Neue Aktion „Microsoft Edge: Zwischenspeicher leeren“ (Nutzerkontext, Kategorie Browser, `SelfX_Browser_ClearEdgeCache.ps1`): schließt Edge der eigenen Sitzung und löscht nur die Ordner `Cache`, `Code Cache` und `GPUCache` des Standardprofils; Cookies, Verlauf, Kennwörter und Lesezeichen bleiben. Verknüpfte Ordner (Junctions) werden übersprungen. Deutscher Text in `de.xml`, andere Sprachen zeigen den englischen Text.
- Neue Aktion „Outlook reagiert nicht mehr“ (Nutzerkontext, Kategorie Outlook, `SelfX_Outlook_Reboot.ps1`): beendet das klassische Outlook der eigenen Sitzung und startet es wieder. Profil, Datendateien und Add-ins bleiben unverändert; das neue Outlook (`olk.exe`) ist nicht betroffen. Deutscher Text in `de.xml`, andere Sprachen zeigen den englischen Text.
- Neue Aktion „Die Uhrzeit Ihres Geräts stimmt nicht“ (Systemkontext über den SelfX-Dienst, Kategorie Gerät, `SelfX_Device_SyncTime.ps1`): startet bei Bedarf den Windows-Zeitdienst und führt `w32tm.exe /resync /force` mit festen Argumenten aus. Zeitquelle, Konfiguration und Zeitzone werden nicht verändert. Gesperrt, solange ein anderer Nutzer angemeldet ist (`OtherSessions=Block`). Deutscher Text in `de.xml`, andere Sprachen zeigen den englischen Text.

### Geändert
- Statussymbol (Windows 11): Das Symbol wird dauerhaft neben der Uhr angezeigt und nicht mehr im Überlauf (Pfeil) versteckt. Neu: `Tray_Pin_Icon` in `Tool_Config.xml` (Standard `True`), Nutzerwert `HKCU\Software\SelfX\TrayPin = 0` schaltet es ab. Läuft im Nutzerkontext und schreibt nur `IsPromoted` des eigenen Eintrags in `HKCU\Control Panel\NotifyIconSettings`. Test `Test-TrayPin.ps1`.
- Fernwartung: Ist Remote Help installiert (`%ProgramFiles%\Remote Help\RemoteHelp.exe`, gültig von Microsoft signiert, kein Link), startet die Kachel Remote Help, und Quick Assist wird in SelfX nicht angeboten. Ohne Remote Help bleibt es bei Quick Assist. Keine neue Einstellung. Läuft im Nutzerkontext. Texte `SystemInfo_RemoteHelp_Text` und `Tooltip_RemoteHelp` (de, en; andere Sprachen zeigen den englischen Text). Test `Test-RemoteHelp.ps1`.
- Dienst 2.8.3: Die tägliche Aufräumung löscht jetzt auch Geräteberichte (`%ProgramData%\SelfX\Reports\<SID>\DeviceLogs-*.txt|.zip`) nach 7 Tagen und leere Nutzerordner, nicht mehr nur beim nächsten Bericht. Nur Ordner mit SID-Namen, nur Berichtsdateien, keine Links, nur Ordner von SYSTEM oder Administratoren. Test in `Test-ServicePipe.ps1`.
- Dokumentation (Befund N10): Neuer Abschnitt „Ausführungsrichtlinie (`-ExecutionPolicy Bypass`)“ in `docs\Installation.md`: warum SelfX mit `Bypass` startet, dass die Ausführungsrichtlinie keine Sicherheitsgrenze ist und was stattdessen schützt (Dateiliste, WDAC). Keine Codeänderung.
- Deutscher Neustart-Hinweis unten im Hauptfenster (`Reboot_Alert` in `de.xml`): „Starten Sie Ihr Gerät bitte täglich neu. Dann laufen Updates und Programme zuverlässiger.“ statt „mindestens einmal pro Woche“. Die anderen Sprachen sind unverändert.
- Sicherheit (Befund N4, Teil 3): Optionale Unterstützung für App Control for Business (WDAC). Neu: `tools\New-SelfXWdacPolicy.ps1` erzeugt aus dem Paket (Bin, Sources, `Install.ps1`, `Detection.ps1`, `Uninstall.ps1`) eine ergänzende Richtlinie mit Hashregeln für alle Programme, Bibliotheken und Skripte; ob Überwachung oder Erzwingung gilt, bestimmt die Basisrichtlinie. Neuer Abschnitt „App Control for Business (WDAC), optional“ in `docs\Installation.md` (Ablauf, Überwachungsmodus zuerst, Update je Version, Hinweise zu Autopilot). Im Paket und auf den Geräten ändert sich nichts. Test `Test-WdacPolicy.ps1`.
- Sicherheit (Befund N4, Teil 2): Der Dienst (2.8.2) prüft vor **jedem** Start eines Skripts (Aktion, Health-Check, Hintergrundprüfung) die installierten Dateien gegen `SelfX.Files.json`: SHA256 aller gelisteten Dateien, kein Skript und keine XML-Datei ohne Eintrag, keine Verknüpfung (Junction, Symlink) im Weg. Bei einer Abweichung oder fehlender/ungültiger Liste startet er nichts (Antwort `ERROR Installed files are not intact`, Ereignis 4005, Einzelheiten im SelfX-Protokoll). Neue Einstellung `Service_FileCheck` (`Enforce` Standard, `Audit` = nur protokollieren) in `Tool_Config.xml`. Die Installation ist nicht betroffen. Tests in `Test-ServicePipe.ps1`.
- Sicherheit (Befund N4, Teil 1): Dateiliste `SelfX.Files.json`. `tools\New-SelfXIntuneWin.ps1` (1.5.0) schreibt beim Paketbau den SHA256 jeder installierten Datei (alles unter `Sources`, dazu `Uninstall.ps1`) in das Paket; die Liste entsteht bei jedem Bau neu, es gibt nichts von Hand zu pflegen. `Install.ps1` prüft das Paket vor der Installation gegen die Liste (geänderte, fehlende oder nicht gelistete Dateien, ungültige Namen: Abbruch, bevor etwas geändert wird; fehlende Liste: Warnung) und legt die Liste im Installationsordner ab. Der Dienst nutzt sie in einem folgenden PR, um Skripte vor dem Start zu prüfen. Test `Test-FileManifest.ps1` (auch in Windows PowerShell 5.1).
- Sicherheit (Befund N5, Teil 2): Das Token des Dienstes wird auf die nötigen Rechte begrenzt. `Install.ps1` setzt mit `sc.exe privs` neun Rechte (ChangeNotify, Impersonate, CreateGlobal, Shutdown, Systemtime, Backup, Restore, TakeOwnership, ManageVolume); `SeTcb`, `SeDebug`, `SeCreateToken`, `SeLoadDriver`, `SeSecurity` und weitere fehlen dem Dienst und allen Skripten, die er startet. Neue Einstellung `Service_Privileges` in `Tool_Config.xml`: `Restricted` (Standard) oder `Default` (alle LocalSystem-Rechte, nur zur Fehlersuche). Schlägt das Setzen fehl, gibt es nur eine Warnung (Autopilot bleibt unberührt). Jede System-Aktion vor der Verteilung auf einem Testgerät prüfen, siehe `docs/Installation.md`. Tests in `Test-InstallBinaries.ps1`.
- Sicherheit (Befund N5, Teil 1): Der Dienst braucht `SeTcbPrivilege` nicht mehr. Die Prüfung `OtherSessions=Block` liest die angemeldeten Sitzungen über `WTSQuerySessionInformation` (Konto als `DOMÄNE\Nutzer`) statt über `WTSQueryUserToken` und vergleicht sie mit dem Konto der Sitzung des Aufrufers; das funktioniert für lokale, Domänen- und Entra-ID-Konten. Unlesbare Sitzungen blockieren wie bisher (fail closed). Verhalten für Nutzer unverändert. Test in `Test-ServicePipe.ps1`. Teil 2 (Dienstrechte begrenzen) folgt.
- Sicherheit (Befund N12): Release-Workflow `.github/workflows/release.yml`: läuft nur bei einem Tag `v<major>.<minor>.<patch>`, prüft den Tag gegen `Tool_Version`, baut Programme, `.intunewin`, SBOM (CycloneDX 1.5, neu `tools\New-SelfXSbom.ps1`) und `SHA256SUMS.txt` und legt einen Release-Entwurf an (keine automatische Veröffentlichung; Token mit Schreibrecht nur im letzten Schritt, keine weiteren Fremd-Actions). CI prüft die SBOM. Verteilung weiter über die `.intunewin` in der Intune-Oberfläche, siehe `docs/Installation.md`.
- Aufräumen (Befunde N11, N13): `Collect-DeviceLogs.ps1` (1.3.2) enthält keine Swisscom-spezifischen Teile mehr: die Abschnitte „Swisscom deployment“ und „Swisscom logs“, der Registrywert `HKCU\Software\Swisscom` und der Parameter `-MaxLinesPerLog` sind entfernt, die Abschnitte heißen jetzt 1 bis 10; die übrigen Abschnitte (ESP, Autopilot, Intune-Erweiterung, Servicing, Ereignisse, AppX) bleiben. Der interne Typ für die OOBE-Abfrage heißt `SelfX.DeviceLogs.Collector`. Die Kommentare in `SelfXService.cs`, `SelfXLauncher.cs`, `SelfXSessionStarter.cs` und den `.csproj`-Dateien nennen nicht mehr den .NET-Framework-Compiler (C# 5), sondern den Build mit dem .NET-10-SDK; die Versionszeile von `SelfXService.cs` ist 2.8.0. Keine Codeänderung im Dienst.
- Sicherheit (Befund N9): Alle XML-Dateien, die die Oberfläche, das Statussymbol, die Health-Prüfung, die Protokollverwaltung und das Sammelskript lesen (`Tool_Config.xml`, `Issues_List.xml`, `Health_Config.xml`, Sprachdateien), werden über einen `XmlReader` mit `DtdProcessing = Prohibit` und ohne Resolver geladen. Eine Datei mit DOCTYPE oder Entitäten (Entity-Expansion, externe Entitäten) wird abgelehnt; die ausgelieferten Dateien enthalten keins. Statische Prüfung in `Test-Scripts.ps1`.
- Sicherheit (Befunde N7, N8): Hilfe-Dialog und Systeminformationen. Links aus `Tool_Config.xml` werden vor dem Öffnen geprüft (neu `Sources\SupportLinks.ps1`): nur `https://`, `mailto:` mit genau einer Adresse und der Teams-Chat-Link von SelfX; `Support_Website` mit `http://` wird nicht mehr angezeigt, eine ungültige `Support_Mail` oder `Support_Teams` wird ohne Schaltfläche gezeigt, das Protokoll nennt den Grund. Der Empfänger der Geräteprotokoll-E-Mail wird nur als einzelne gültige Adresse übernommen. Programme starten mit vollem Pfad: `explorer.exe` und `MdmDiagnosticsTool.exe` aus dem Windows-Ordner; Outlook und Word werden nicht mehr über den Programmnamen gestartet (Pfad aus dem beendeten Prozess oder aus App Paths; ist er unbekannt, wird nichts beendet). Tests `Test-SupportLinks.ps1`, `Test-Scripts.ps1`.
- Sicherheit (Befunde N3, N6, F12): Der Dienst legt die erste Pipe-Instanz mit `FirstPipeInstance` an. Gehört der Pipe-Name schon einem anderen Prozess, tritt der Dienst nicht bei, protokolliert das (`SelfXService.log`, Windows-Ereignis 4001) und versucht es jede Sekunde erneut. Neu: Einträge im Windows-Ereignisprotokoll (Anwendung, Quelle `SelfXService`, IDs 4001 bis 4004 und 4099; feste Texte ohne Nutzerdaten, je ID höchstens 10 in 10 Minuten), siehe `docs/Installation.md`. `%ProgramData%\SelfX` wird beim Start und täglich geprüft (Verknüpfung, Besitzer); solange es nicht sicher ist, schreibt der Dienst dort nichts und liest keinen Statuscache (Ereignis 4004). Test in `Test-ServicePipe.ps1`.
- Sicherheit (Befund N2): `Collect-DeviceLogs.ps1` (1.3.1) legt die Berichtsdatei sicher an. Eine vorab in `C:\Windows\Temp` angelegte Datei, Verknüpfung oder ein Hardlink (Besitzer nicht SYSTEM, Administratoren, TrustedInstaller oder das ausführende Konto) wird entfernt (nur der Name, nie das Ziel) und der Bericht neu angelegt; die Standardberichte sind nur für SYSTEM und Administratoren lesbar. Der Pfad der Intune-Diagnose (`%windir%\temp\%computername%*.log`) bleibt gleich. Test `Test-CollectorOutput.ps1`.
- Sicherheit (Befund F12): `Install.ps1` bereitet `%ProgramData%\SelfX` vor der Nutzung vor. Ein vorab angelegter Ordner oder eine Verknüpfung (Junction) wird nicht mehr übernommen: Verknüpfungen werden entfernt (nie das Ziel), Einträge, die nicht SYSTEM, Administratoren oder TrustedInstaller gehören, werden gelöscht (Nutzerbereich `Logs\Users` bleibt unberührt), danach werden Besitzer und Rechte neu gesetzt. Fehlschläge von `icacls` brechen die Installation ab. Test in `Test-InstallBinaries.ps1`.
- Copilot Chat: Die englischen Anweisungstexte bitten Copilot jetzt, in der Sprache der Problembeschreibung zu antworten, ohne Beschreibung in der Sprache der Oberfläche aus den Daten. Das hilft Nutzern, deren Sprache keinen eigenen Anweisungstext hat (sie bekommen den englischen).
- Copilot Chat: Die Anweisungstexte des Prompts stehen jetzt in den Sprachdateien (`Copilot_Prompt_User`, `Copilot_Prompt_Admin` in `de.xml` und `en.xml`, andere Sprachen zeigen Englisch) und lassen sich ohne Codeänderung anpassen. Ein Text ohne `{DATA}`, mit `{DATA}` mehrfach oder länger als 3000 Zeichen wird durch den eingebauten Text ersetzt. Inhalt unverändert; ein Test stellt sicher, dass Sprachdatei und eingebauter Text übereinstimmen.
- Copilot Chat: `Copilot_Include_AppNames` = `False` entfernt jetzt auch die Einzelheiten der Zeile *Firmen-Apps* im Gerätestatus. Vorher standen die App-Namen dort weiterhin im Text. Neu im Text: Art der Verbindung (LAN, WLAN, Mobilfunk, VPN) und Art des Proxys (keiner, manuell, Skript), aus lokalen Werten, ohne Internettest und ohne Adressen. Im Dialog steht ein Hinweis (keine Namen, Passwörter oder Kundendaten schreiben, keine Befehle ausführen, die man nicht versteht).
- Dokumentation: `docs/Configuration.md` in einfacherer Sprache neu geschrieben, überholte Versionshinweise und Verlaufstexte entfernt, Überschriften ohne Versionsnummern (Links angepasst).
- Übersetzungen ergänzt: In allen 22 Sprachdateien (außer Deutsch und Englisch) fehlten 28 Texte und wurden bisher auf Englisch angezeigt: Hinweis bei angemeldeter anderer Person (`Service_OtherSessions_Text`), Ticket-Dialog (`Ticket_*`), Hinweis zur Betriebszeit, Proxy und Netzlaufwerke sowie die Netzwerk-Messungen (`Latency_*`).

- Statuszeile „Neustart ausstehend“: Der Text nennt jetzt den letzten Neustart und, wenn die letzte Update-Installation danach lag, deren Zeitpunkt (nur lesend, Zeiten in der Zeitzone des Nutzers). Fehlen die Quellen, entfällt nur der Zusatz.

## 2.8.0 - 2026-11-22 (SelfX Service)

Dienst, Fenster und Statussymbol starten PowerShell 7 (ab 7.6) statt Windows PowerShell 5.1.
Mindestversion ist Windows 11 25H2 (Build 26200). `Tool_Version` und `$ExpectedVersion`
wurden angehoben: Paket neu bauen und verteilen. Vor dem Verteilen PowerShell 7 als
Win32-App bereitstellen und die Voraussetzungsregel für Build 26200 setzen
(siehe [Installation](docs/Installation.md#windows-version-und-powershell-7-ab-280)).

### Geändert

- Dokumentation: `docs/Installation.md` beschreibt Windows 11 25H2 und PowerShell 7 als Voraussetzung, das Verhalten des
  Installers und des Dienstes, die Verteilung von PowerShell 7 mit Intune (Win32-App, Abhängigkeit, Autopilot/ESP,
  Voraussetzungsregel für Build 26200) und die erweiterte Release-Checkliste.
- DNS-Cache leeren und Systemlaufwerk prüfen ohne Kompatibilitätsschicht: CIM (`MSFT_DNSClientCache.Clear`,
  `MSFT_Volume.Repair` mit `OfflineScanAndFix`) statt `Clear-DnsClientCache` und `Repair-Volume`.
- BitLocker und TPM ohne Module: Gerätestatus und Compliance-Prüfung lesen CIM (`Win32_EncryptableVolume`, `Win32_Tpm`,
  Datei `Sources\SelfXDeviceSecurity.ps1`) statt `Get-BitLockerVolume` und `Get-Tpm`. Dabei wird ein früherer Fehler behoben:
  Datenlaufwerke wurden nie geprüft, weil der Typ „Data“ statt „FixedData“ hieß. Feste Datenlaufwerke ohne BitLocker
  zeigen jetzt „Fehler“ im BitLocker-Status.
- Secure-Boot-Prüfung (Compliance) liest die Registry (`UEFISecureBootEnabled`, neue Datei `Sources\SelfXDeviceSecurity.ps1`)
  statt `Confirm-SecureBootUEFI`: ohne Windows-PowerShell-Kompatibilitätsschicht und ohne Administratorrechte.
- Defender ohne Defender-Modul: Status (Gerätestatus, Compliance) und Signatur-Update nutzen CIM
  (`root\Microsoft\Windows\Defender`, neue Datei `Sources\SelfXDefender.ps1`) statt `Get-MpComputerStatus`
  und `Update-MpSignature`. Update-Quellen und Reihenfolge kommen weiter aus der Defender-Richtlinie.
- Netzwerk ohne NetAdapter-Modul: Adapter, Standardrouten und der Adapter-Neustart („Netzwerk neu starten“)
  nutzen CIM (`root\StandardCimv2`, neue Datei `Sources\SelfXNetwork.ps1`) statt `Get-NetAdapter`,
  `Get-NetRoute` und `Restart-NetAdapter`. Dadurch startet PowerShell 7 dafür kein Windows PowerShell 5.1 mehr.
  Behebt nebenbei, dass bei Geräten ohne IPv6-Standardroute alle Standardrouten verworfen wurden.
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

- `LICENSE.md`: zusätzliche Copyright-Zeile für die Änderungen in diesem Fork (Text und Originalzeile unverändert).
- `NOTICE.md` / `NOTICE.en.md`: Urheber und Quellen (Damien Van Robaeys, Wolfgang Baeck, Jannik Reinhard).
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
