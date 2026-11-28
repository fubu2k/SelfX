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

- **Hinweis vor störenden Aktionen (`Sources\SelfXDisturb.ps1` 3.1.0, `Sources\Self_X.ps1`, `Sources\Localization.ps1`, `Sources\Issues_List.xml` 2.4.14, `Sources\Tool_Config.xml`, `Sources\Languages\*.xml` (24 Dateien), `tools\SelfXPackage.Common.ps1`, `Test-Catalog.ps1`, neu `Test-Disturb.ps1`):** Vor einer Aktion, die eine Besprechung beenden kann, zeigt die Bestätigung einen zusätzlichen Satz, wenn die eigene Sitzung des Nutzers beschäftigt wirkt: *Sie sind anscheinend in einer Besprechung oder Präsentation. Diese Aktion kann sie unterbrechen.* Störende Aktionen tragen das neue optionale Katalogelement `<Disruptive>True</Disruptive>`: die Aktionen der Skripte, die Teams, Word, Excel oder Outlook schließen (`SelfX_Teams_ResetCache.ps1`, `SelfX_Word_Reboot.ps1`, `SelfX_Excel_Reboot.ps1`, `SelfX_Outlook_Reboot.ps1`, `SelfX_Outlook_TeamsAddIn.ps1`) und der Neustart der Netzwerkadapter (`SelfX_Device_AirePlaneMode.ps1`); die Reparatur „Neustart“ im Gerätestatus hat den Hinweis immer. Das Fenster liest für die eigene Sitzung `SHQueryUserNotificationState` (shell32, dokumentiert) und ergänzt den Hinweis bei den Zuständen beschäftigt (Vollbild), Direct3D-Vollbild, Präsentationseinstellungen und Ruhezeit. Es ist nur ein Hinweis: Es wird nichts abgeschaltet, blockiert oder an den Dienst gesendet, keine andere Sitzung und kein Programmname wird gelesen, und das Protokoll nennt nur die Aktions-Id. Lässt sich der Zustand nicht lesen, hat die Bestätigung keinen Hinweis. Neue Einstellung `Disturb_Warning` in `Tool_Config.xml` (`True` Standard, `False` = kein Hinweis). Neuer Text `Disturb_Warning_Text` in allen 24 Sprachdateien. `Test-Catalog.ps1` prüft, dass `Disruptive` genau `True` ist, zu einer Aktion mit Skript gehört und bei allen Einträgen eines Skripts gleich ist (Negativbeispiele). **Abweichungen vom Plan:** Der Plan nennt ein Attribut; der Katalog führt seine Felder als Elemente, daher ist `Disruptive` ein Element. Der Mikrofon- und Kamerazustand (`CapabilityAccessManager\ConsentStore`, `LastUsedTimeStop` = 0) wird nicht verwendet: Auf einem Windows-11-26H2-Testgerät (Build 26300) erzeugte ein klassisches Desktopprogramm, das vier Sekunden lang das Standardmikrofon mit `waveIn` öffnete, in den folgenden Sekunden keinen Wert `LastUsedTimeStart` oder `LastUsedTimeStop` für sich selbst; paketierte Apps und die Kamera wurden nicht versucht, der Wert ist also nicht bestätigt. Geändertes Verhalten: Mit dem ausgelieferten `Disturb_Warning` = `True` kann die Bestätigung der gekennzeichneten Aktionen den Zusatzsatz zeigen. Tests: `Test-Disturb.ps1` (Art für jeden Zustand, alle Kombinationen aus Einstellung, Kennzeichnung und Zustand, ausfallender Lieferant, der ausgelieferte Katalog, die 24 Sprachdateien, statische Prüfungen, dass `SelfXDisturb.ps1` keine Registry, keinen Prozess, keinen Dienst, keine Datei und kein Protokoll nutzt), `Test-Catalog.ps1`, `Test-LanguageFiles.ps1`, `Test-UI.ps1`. Nicht auf einem Gerät versucht: die drei Zustände mit einem echten Vollbildprogramm, Präsentationseinstellungen und Ruhezeit (auf dem Testgerät wurde nur der Zustand 5, nichts läuft, gelesen), die Bestätigungsdialoge mit dem Hinweis, eine Rechts-nach-links-Sprache, ein Screenreader, ein Terminalserver.

- **Feste Support-Adresse auf einem Terminalserver (`Sources\TicketSend.ps1` 3.1.0, `Sources\Self_X.ps1`, `Sources\Tool_Config.xml`, `tools\Wizard\SelfXWizard.ps1` 3.1.9, `tools\Wizard\SelfXWizardGui.ps1` 1.7.0, `tools\Wizard\Wizard.de.xml` / `Wizard.en.xml` 1.8.0):** Neue Einstellung `TerminalServer_Support_Mail`. Auf Windows Server ersetzt sie `Support_Mail` und `Ticket_Mail`: Sie ist die Support-E-Mail, der Empfänger des Tickets und die Adresse im Hilfe-Fenster. Die Ticket-Zuordnung (`Ticket_Config.xml`, die für ein Gerät in der Registry gesetzte Adresse) wird dort nicht genutzt; der Computername bleibt im Ticket. Leer oder keine einzelne Adresse: `Support_Mail` und `Ticket_Mail` bleiben, weiterhin ohne Zuordnung, mit einer Warnung im Protokoll. Auf Windows 11 ändert sich nichts. Der Assistent fragt bei einem Paket für Windows Server nach der Adresse (Pflicht). Tests: `Test-Ticket.ps1` (`Get-SelfXSupportContact`: Client, Terminalserver, ungültige Adressen, Ziel ohne Zuordnung), `Test-UI.ps1`, `tools\Test-SelfXPackageWizard.ps1`. Nicht auf einem Gerät ausprobiert: Ticket und Hilfe-Fenster auf Windows Server.
- **Windows Server als Terminalserver; der Modus kommt von Windows (`Install.ps1`, `Detection.ps1`, `Service\SelfXService.cs`, `Sources\SelfXEnvironment.ps1`, `Sources\Self_X.ps1`, `Sources\SelfX_Tray.ps1`, `Sources\HealthStatus.ps1`, `Sources\Tool_Config.xml`, `Sources\Issues_List.xml` 2.4.13, `Sources\Health_Config.xml`, `tools\Wizard\SelfXWizard.ps1` 3.1.8, `tools\Wizard\SelfXWizardGui.ps1` 1.6.0, `tools\Wizard\Wizard.de.xml` / `Wizard.en.xml` 1.7.0, `CLAUDE.md`):** SelfX lässt sich jetzt neben Windows 11 25H2 (Build 26200) auch auf Windows Server 2022 und 2025 mit Desktopdarstellung (Build 20348 oder neuer) installieren. `Install.ps1` bricht vor jeder Änderung ab auf Server Core, auf einem Domänencontroller, auf Windows Enterprise multi-session (EditionID `ServerRdsh`) und wenn Produkttyp oder Build nicht gelesen werden können. Die Einstellung `Environment_Mode` entfällt: Der Dienst übernimmt den Modus aus dem Produkttyp von Windows (RtlGetVersion; Arbeitsstation = `Client`, alles andere und nicht lesbare Daten = `TerminalServer`), Fenster, Statussymbol und Statuserfassung aus `ProductOptions\ProductType` in der Registry. Ein altes `Environment_Mode` in `Tool_Config.xml` wird ignoriert (Hinweis in `SelfXService.log`); Ereignis 4009 wird nicht mehr geschrieben. `TerminalServer_Health` bleibt und gilt nur auf Windows Server. Der Assistent fragt *Für welches Windows ist das Paket?* (`Windows11` oder `WindowsServer`) statt *Wo läuft SelfX?*; bei `WindowsServer` fragt er nach `TerminalServer_Health` und schreibt `SelfX-Server-Guide.<Sprache>.txt`: Installation von Hand oder mit Configuration Manager, weil Intune auf Windows Server keine Apps installieren kann. `Detection.ps1` beendet „nicht erkannt“ jetzt mit Exit-Code 0 ohne Ausgabe (bisher 1), damit Configuration Manager es als Erkennungsmethode nutzen kann; für Intune ist das Ergebnis gleich. Tests: `Test-InstallBinaries.ps1` (Windows 11, Server 2022/2025, Server 2019, Server Core, ohne Desktop, multi-session, Domänencontroller, nicht lesbare und unbekannte Werte), `Test-ServicePipe.ps1` (Modus über ein Testfeld: TerminalServer lehnt ab, ein altes `Environment_Mode Client` schaltet nicht um, Client mit beliebiger `Tool_Config.xml`; Gerätestatus je Modus), `Test-HealthStatus.ps1` (Modus aus dem Produkttyp, gemockt; die CI läuft auf Windows Server), `Test-UI.ps1`, `Test-Detection.ps1`, `tools\Test-SelfXPackageWizard.ps1` (Frage, Server-Anleitung, Server-Paket). Nicht auf einem Gerät ausprobiert: Installation und Nutzung auf Windows Server 2022 und 2025, der Abbruch auf Server Core und auf multi-session, eine Installation mit Configuration Manager.
- **Gerätestatus und Systeminformationen auf einem Terminalserver (`Service\SelfXService.cs`, `Sources\SelfXEnvironment.ps1`, `Sources\SystemInfo.ps1`, `Sources\SelfXServiceClient.ps1`, `Sources\CopilotFacts.ps1` 3.1.0, `Sources\Self_X.ps1`, `Sources\SelfX_Tray.ps1`, `Sources\Tool_Config.xml`, `tools\Wizard\*`):** Neue Einstellung `TerminalServer_Health` = `Off` (Standard) oder `AdminOnly`; sie gilt nur bei `Environment_Mode` = `TerminalServer`, jeder andere Wert gilt als `Off`. `Off`: Der Dienst führt keine Hintergrundprüfungen aus (auch nicht mit `Background Enabled`), schreibt keinen Status-Cache und beantwortet `HEALTH` und `STATUS` für jeden Aufrufer mit `UNAVAILABLE TerminalServer`; SelfX zeigt keine Seite *Gerätestatus*, das Statussymbol zeigt keinen Status und keine Benachrichtigungen und öffnet nur SelfX. `AdminOnly`: Der Dienst beantwortet `HEALTH` und `STATUS` nur Administratoren mit erhöhten Rechten. Eine `Tool_Config.xml`, die der Dienst nicht lesen kann, gilt als `TerminalServer` mit `Off`. Die tägliche Protokollpflege läuft weiter. Auf einem Terminalserver sehen normale Nutzer in den *Systeminformationen*, im Ticket und im Text für Copilot nur Zeilen zu ihrem Konto und ihrer Sitzung (Nutzer, UPN, Zeitzone, Proxy, Netzlaufwerke, Citrix Workspace, Zeitpunkt der Erfassung); die Zeilen des Servers sehen nur Administratoren mit erhöhten Rechten, für normale Nutzer werden sie gar nicht erst gelesen (kein `dsregcmd`, kein Internettest, kein Verbindungstest). LAN, WLAN, Mobilfunk und VPN werden auf einem Terminalserver nicht angezeigt. Der Paket-Assistent fragt nach `TerminalServer_Health`, wenn das Paket für einen Terminalserver ist. Geändertes Verhalten: keines bei `Environment_Mode` = `Client`. Tests: `Test-ServicePipe.ps1` (280 Prüfungen: Zugriffstabelle, `HEALTH` und `STATUS` als Nutzer und als Administrator in allen Kombinationen, Hintergrundschleife), `Test-HealthStatus.ps1` (635), `Test-UI.ps1` (382), `Test-CopilotFacts.ps1` (452), `Test-SelfXPackageWizard.ps1`. Auf einem Gerät nicht geprüft: ein Terminalserver mit mehreren Nutzern, ein Administrator mit erhöhten Rechten bei `AdminOnly`, das Statussymbol ohne Status.
- **Ein Paket für PCs und Sitzungshosts: `Environment_Mode` (`Sources\Tool_Config.xml`, `Sources\Issues_List.xml` 2.4.12, `Sources\Health_Config.xml`, neu `Sources\SelfXEnvironment.ps1` 3.1.0, `Sources\Self_X.ps1`, `Sources\SelfX_Tray.ps1`, `Sources\HealthStatus.ps1`, `Sources\Localization.ps1`, `Sources\SelfXServiceClient.ps1`, `Service\SelfXService.cs`, `Sources\Languages\*.xml` (24 Dateien), `tools\Wizard\*`, `tools\SelfXPackage.Common.ps1`):** Neue Einstellung `Environment_Mode` = `Client` (Standard) oder `TerminalServer`; jeder andere Wert gilt als `Client` und wird protokolliert. Jede Aktion hat das Pflichtelement `<TerminalServer>Show</TerminalServer>` oder `Hide`, jede Reparatur das Attribut `TerminalServer`; `Test-Catalog.ps1` schlägt fehl, wenn es fehlt oder die Einträge eines Skripts sich unterscheiden. `Show` = nur die eigene Sitzung oder das eigene Profil, `Hide` = das ganze Gerät oder alle Nutzer. Bei `TerminalServer` blenden Fenster, Statussymbol und Gerätestatus aus, was nicht `Show` ist, auch den Nutzerteil einer Reparatur, und der Dienst lehnt `RUN` dafür für jeden Aufrufer ab, auch für Administratoren mit erhöhten Rechten (Antwort `ERROR TerminalServer`, eigene Meldung in SelfX, Ereignis 4008). Eine fehlende Einstufung gilt als `Hide`; eine `Tool_Config.xml`, die der Dienst nicht lesen kann, gilt als `TerminalServer`. Die Prüfung anderer aktiver Sitzungen (`OtherSessions`) gilt in beiden Modi gleich. Beim Start warnt der Dienst, wenn Windows ein Sitzungshost ist (Produkttyp eines Servers, wie ihn Windows Enterprise multi-session meldet, oder Anwendungsservermodus), der Modus aber `Client` ist (Protokoll, Ereignis 4009); er ändert den Modus nie. Der Paket-Assistent fragt „Wo läuft SelfX?“. Mitgelieferte Einstufung: Nutzeraktionen der eigenen Sitzung `Show`; kein Ton, DNS-Cache leeren, Store zurücksetzen und alle `System`-Aktionen und Reparaturen `Hide`. Geändertes Verhalten: keines mit dem mitgelieferten `Client`. Tests: `Test-Catalog.ps1` (600 Prüfungen, Negativbeispiele), `Test-ServicePipe.ps1` (252 Prüfungen, beide Modi über `ProcessRequest` einer Testinstanz, nichts wird gestartet), `Test-HealthStatus.ps1` (615), `Test-UI.ps1` (376), `Test-SelfXPackageWizard.ps1`. Auf einem Gerät nicht geprüft: Windows Enterprise multi-session, ein Remotedesktop-Sitzungshost, Ereignis 4009, zwei Nutzer gleichzeitig mit `TerminalServer`.
- **Chrome- und Firefox-Cache-Aktionen beenden nur Prozesse der eigenen Sitzung (`Sources\Scripts_to_run\SelfX_Browser_ClearChromeCache.ps1` 2.6.1, `Sources\Scripts_to_run\SelfX_Browser_ClearFirefoxCache.ps1` 2.6.1, `Test-Scripts.ps1`):** Beide Skripte beendeten jeden erreichbaren Prozess `chrome` bzw. `firefox`, auch den anderer angemeldeter Sitzungen auf einem Mehrbenutzergerät. Sie beenden jetzt nur die Prozesse der Sitzung, in der sie laufen, wie es das Edge-Skript schon tat. Ein statischer Test prüft, dass jedes Nutzerskript, das `Stop-Process` aufruft, nach Sitzung filtert. Verhaltensänderung: Browserfenster anderer Nutzer bleiben offen. Tests: `Test-Scripts.ps1` (643 Prüfungen) und die Paketests auf dem Entwicklungs-PC; PSScriptAnalyzer lokal nicht ausgeführt. Auf einem Gerät nicht geprüft: zweite angemeldete Nutzer mit offenem Chrome- oder Firefox-Fenster.
- **Speicherplatz freigeben in der Festplatten-Zeile (`Sources\Scripts_to_run\SelfX_Device_FreeSpaceUser.ps1` 3.1.0, `Sources\Scripts_to_run\SelfX_Device_FreeSpace.ps1` 3.1.0, `Service\SelfXService.cs`, `Sources\Health_Config.xml`, `Sources\HealthStatus.ps1`, `Sources\SelfXServiceClient.ps1` 3.1.0, `Sources\SystemInfo.ps1`, `Sources\Self_X.ps1`, `Sources\Languages\*.xml` (24 Dateien), `tools\SelfXPackage.Common.ps1`):** Die Zeile von Laufwerk `C:` bekommt die Schaltfläche **Speicherplatz freigeben**, solange sie nicht in Ordnung ist. SelfX fragt einmal und zählt auf, was gelöscht wird; dann führt es einen Teil als angemeldeter Nutzer und einen Teil als SYSTEM aus und zeigt am Ende den freien Platz vorher und jetzt. Teil des Nutzers (`SelfX_Device_FreeSpaceUser.ps1`, `Context : User`): eigener Papierkorb, eigenes TEMP, eigener Teams-Cache nur, wenn kein Teams-Prozess der Sitzung läuft (Teams wird nie geschlossen; läuft es, bleibt der Cache erhalten, Exitcode 2, und SelfX sagt das). Teil als SYSTEM (`SelfX_Device_FreeSpace.ps1`, ohne Parameter): `Dism.exe` aus System32 mit den festen Argumenten `/Online /Cleanup-Image /StartComponentCleanup` (nie `/ResetBase`), der Delivery-Optimization-Cache (`Delete-DeliveryOptimizationCache -Force`, angeheftete Dateien bleiben, Modul über den vollen Pfad geladen) und Einträge älter als `MinimumAgeDays` in `Windows\Temp` und in den Intune-Inhalten (`Content\Incoming`, `Content\Staging`, `Windows\IMECache`). Die Intune-Inhalte werden übersprungen, solange `AgentExecutor.exe` oder `msiexec.exe` läuft oder dort in den letzten `ImeQuietMinutes` etwas geändert wurde (eine Heuristik, eine Abfrage dafür gibt es nicht). Schwellen: neues Element `<DiskCleanup MinimumAgeDays="7" ImeQuietMinutes="60" />` in `Health_Config.xml`; ein ungültiger Wert stoppt den SYSTEM-Teil, bevor etwas gelöscht wird. Die alten Einträge löscht der neue Modus `SelfXService.exe /cleanold:<WindowsTemp|ImeIncoming|ImeStaging|ImeCache> /minage:<Tage>`: Die vier Ordner stehen fest im Programm (bekannte Ordner von Windows, nie ein Argument), jeder Eintrag wird einmal geöffnet, ohne einer Verknüpfung zu folgen, an diesem Handle beurteilt (neueste von Erstellungs-, Schreib- und Änderungszeit) und darüber gelöscht; eine Verknüpfung wird selbst gelöscht und nie verfolgt; ein Ordner wird nur gelöscht, wenn er alt und danach leer ist; benutzte Einträge bleiben und werden gezählt. `/cleanoldpath:` macht dasselbe unterhalb eines beliebigen lokalen Ordners für die Tests und wird für SYSTEM abgelehnt. Neu in `Health_Config.xml`: Attribut `UserScript` einer Reparatur (ein erster Teil, den SelfX als Nutzer startet; der Dienst führt ihn nie aus; zurückgegeben als `UserRemediation`, gleiche Namensregel, nie dieselbe Datei wie `Script`). Eine Reparatur mit `UserScript` hat eine eigene Bestätigung und ist nie Teil von *Alle Probleme beheben*; solange ihr Teil des Nutzers läuft, startet keine andere Aktion des Dienstes. 6 neue Texte in allen 24 Sprachen. Tests: `Test-SafeDelete.ps1` (alte und neue Dateien, Ordner und Junctions, ein Ordner, der eine Junction ist oder hinter einer liegt, fehlender Ordner, falsche Ordnernamen und Alter, Ordner, die während des Laufs gegen Junctions getauscht werden), `Test-Scripts.ps1` (beide Skripte mit Mocks; DISM-Argumente, Argumente des Helfers und die vier Ordnernamen statisch geprüft; Schwellen mit ungültigen Werten und einer DTD; Intune-Prüfung mit Prozessen und frischen Änderungen), `Test-HealthStatus.ps1` (`UserRemediation` aus der Sammlung, abgelehnte Namen, Prüfung im Client, der Dienst lässt das `UserScript` nie zu, der Ablauf in SelfX: Teil des Nutzers, dann SYSTEM-Teil, Ergebnistext, fehlgeschlagener Schritt, kein zweiter Start), `Test-Catalog.ps1` (ein `UserScript` ist ein einfacher Name, deklariert `Context : User`, ist kein SYSTEM-Skript). **Abweichungen vom Plan:** Der Plan nennt eine neue Katalogaktion; die Aktion ist stattdessen eine Reparatur der Festplatten-Zeile, weil eine Katalogaktion ein Skript und einen Kontext hat und eine Reparatur jetzt einen Teil des Nutzers haben kann (`UserScript`); in `Issues_List.xml` gibt es keinen Eintrag. Der Teams-Cache wird nicht über `SelfX_Teams_ResetCache.ps1` geleert (das Skript schließt Teams und startet es neu); dieselben Ordner werden nur gelöscht, wenn Teams geschlossen ist. Löschen nach Alter brauchte einen neuen Modus des vorhandenen Löschhelfers im Dienstprogramm statt PowerShell, weil Nutzer in `Windows\Temp` schreiben können. Nicht auf einem Gerät ausprobiert: Dauer von DISM und gewonnener Platz, das Delivery-Optimization-Cmdlet als SYSTEM in PowerShell 7, ein Gerät mit laufender Intune-Installation, ein anderes Systemlaufwerk als `C:`, das Fenster mit einem Screenreader, SelfX schließen, während der Teil des Nutzers läuft (der SYSTEM-Teil startet dann nicht).

- **Verbindungstest mit Urteil und Assistentenseite Verbindungstest (`Sources\SystemInfo.ps1`, `Sources\Network_Test_Config.xml`, `Sources\Self_X.ps1`, `Sources\Languages\*.xml` (24 Dateien), `tools\Wizard\SelfXWizard.ps1` 3.1.5, `tools\Wizard\SelfXWizardGui.ps1` 1.3.0, `tools\Wizard\SelfXWizardGui.xaml`, `Wizard.en.xml`/`Wizard.de.xml`, `tools\New-SelfXPackage.ps1` 1.3.1, `tools\Test-SelfXNetworkMeasure.ps1` 3.1.0):** Die optionalen Netzwerk-Messungen der Systeminformationen beantworten jetzt eine Frage: Liegt es am WLAN oder Router, am Internet, an den Microsoft-Diensten oder am Firmennetz? Vier Zeilen (lokales Netzwerk, Internet, Microsoft-Dienste, Firmennetz) zeigen *erreichbar*, *teilweise erreichbar*, *nicht erreichbar* oder *nicht gemessen* mit einem Statussymbol, und ein Satz sagt, was vermutlich nicht stimmt (zum Beispiel *Das Internet funktioniert, das Firmennetz ist nicht erreichbar: VPN prüfen.*). Die Zeilen und der Satz gehören zu *Kopieren*, *Exportieren*, dem Support-Bericht und dem Ticket. Die Liste der Systeminformationen zeigt am Zeilenende ein Statussymbol für die Zustände OK, ausstehend und Fehler. `Network_Test_Config.xml`: Ein Ziel hat die neuen Attribute `Group` (`Local`, `Internet`, `Microsoft`, `Company`) und bei `Company` zusätzlich `Kind` (`Vpn`, `Intranet`); höchstens 12 Ziele; dieselbe strenge Prüfung von Host und Port wie bisher; der ganze Lauf endet nach 15 Sekunden. Die Datei wird mit vier Microsoft-Zielen ausgeliefert (`manage.microsoft.com`, `login.microsoftonline.com`, `graph.windows.net`, `enterpriseregistration.windows.net`, TCP 443; Quelle: Microsoft Learn, *Network endpoints for Microsoft Intune*, geprüft am 27.11.2026); `Microsoft="False"` schaltet die Gruppe ab. `HostNames="False"` hält Hostnamen aus den Zeilen (Kopie, Export, Ticket). Die Messungen bleiben standardmäßig aus, Benutzer können keine Ziele hinzufügen. Das Urteil ist eine reine Funktion (`Get-SelfXConnectionVerdict`: Zustände der vier Gruppen hinein, Urteils-Id heraus). Abweichungen vom Plan: Zusätzlich zu den vier Sätzen des Plans gibt es die Urteile *Microsoft-Dienste nicht erreichbar*, *Firmennetz am Standort nicht erreichbar* (`Kind="Intranet"`), *teilweise erreichbar* und *keine Daten*; der Test *Internet erreichbar* zählt als ein Internet-Ziel; ein Gateway, das nicht antwortet, während das Internet funktioniert, wird nicht als *Router ausgefallen* gemeldet (manche Firewalls verwerfen Ping); Ziele ohne Gruppe werden gemessen und angezeigt, zählen aber nicht; die Einstellungen `Microsoft` und `HostNames` sind neu. Assistent: neue Seite **Verbindungstest** zwischen *Ticket* und *Weitere Einstellungen* (Antworten `NetworkEnabled`, `NetworkMicrosoft`, `NetworkHostNames` und die Liste `NetworkTargets` mit `Label`, `Host`, `Port`, `Group`, `Kind`; neue Prüfart `netTarget`; `Set-SelfXNetworkTestConfig` schreibt die Datei und lässt die Kommentare und die vier Microsoft-Ziele stehen; höchstens 8 eigene Ziele, weil vier der 12 mitgeliefert werden; Ziele ohne eingeschaltete Messung werden abgelehnt, nicht ignoriert; die Konsole stellt dieselben Fragen; `selfx-answers.json` und `New-SelfXPackage.ps1 -AnswerFile` kennen `NetworkTargets`). Die Abschnitte der Konsole sind jetzt x/9 nummeriert. Texte des Assistenten: `de` und `en`. Tests: `Test-NetworkMeasure.ps1` (216 Prüfungen: Tabellentest des Urteils für alle Kombinationen, Ziele, Grenzen, 15-Sekunden-Grenze), `Test-LanguageFiles.ps1` (17 neue Texte in allen 24 Sprachen), `tools\Test-SelfXPackageWizard.ps1` (Prüfart `netTarget` mit Schema, Pfad, Port 0 und 65536, unbekannter Gruppe, Art außerhalb von `Company`, 13 Zielen, doppelter Bezeichnung, Ziele bei ausgeschalteter Messung, geschriebene Datei), `tools\Test-SelfXWizardGui.ps1` (Seitenreihenfolge, Fehler am Feld, Grenze von 8, Antworten des Fensters identisch zur Konsole und dieselbe `Network_Test_Config.xml`, Laden der Ziele aus einer Antwortdatei). Nicht auf einem Gerät geprüft: der Verbindungstest hinter einem Proxy oder Captive Portal, mit einem echten VPN und mit einer Firewall, die ICMP sperrt, der Screenreader auf der neuen Seite, das Statussymbol im Kontrastdesign. Bekannt und unabhängig: `Test-ConfigPath.ps1` und `Test-FileManifest.ps1` schlagen unter einem deutschen Windows fehl, weil sie englische Fehlertexte vergleichen; auf `main` ebenso.

- **Konfigurationspaket: `Install.ps1 -ConfigOnly` (`Install.ps1`, `Detection.ps1`, `Uninstall.ps1` 3.1.0, `tools\SelfXPackage.Common.ps1`, `tools\Wizard\SelfXWizard.ps1` 3.1.4, `tools\Wizard\SelfXWizardGui.ps1` 1.2.0, `tools\New-SelfXPackage.ps1` 1.3.0):** Der Assistent kann ein zweites, kleines Paket (`SelfX-Config-<Version>.intunewin`) mit nur `Install.ps1`, `Detection.ps1` und `Config` bauen. `Install.ps1 -ConfigOnly` ersetzt den Ordner `Config` eines installierten SelfX: Der Vertrauensmodus ist der des Ankers auf dem Gerät (`-TrustedSigner` und `-AllowHashMode` werden damit abgelehnt), das Paket wird wie bei der vollständigen Installation geprüft (Liste, SHA256, kein Link, im Modus Signatur die Signaturen und `Config\SelfX.Config.cat`), `MinCodeVersion` in `SelfX.Config.json` darf nicht neuer sein als der installierte Code, und Einstellungen, die nur die vollständige Installation anwendet (Verknüpfungen, Eintrag des Statussymbols, Symbol, `Service_Privileges`), müssen unverändert sein. Der Ordner wird neben den Installationsordner kopiert (`SelfX.ConfigStage`), geprüft und durch Umbenennen getauscht (`SelfX.ConfigOld`); bei einem Fehler kommt der alte Ordner zurück, ein unterbrochener Lauf wird vom nächsten Lauf repariert. Dienst, Programme und Anker bleiben unberührt und nichts wird neu gestartet; hält ein Skript eine Datei von `Config` offen, wartet der Austausch etwa 20 Sekunden und endet dann mit Exitcode 1. `Detection.ps1` hat `$PackageKind` (`Full`, `FullWithoutConfig`, `ConfigOnly`); das Konfigurationspaket vergleicht nur den Konfigurations-Digest. Der Assistent hat die Auswahl *Vollständig / Vollständig mit getrennter Konfiguration / Konfigurationspaket* (Konsole: `-SeparateConfig`, `-ConfigPackage`), eine Anleitung für die zweite App (Abhängigkeit zur vollständigen App, Ablösung nur unter Konfigurations-Apps) und erzeugt dafür keine AppLocker- oder App-Control-Dateien. `Uninstall.ps1` entfernt die Arbeitsordner eines unterbrochenen Laufs. Neuer Test `Test-InstallConfigOnly.ps1` (im Satz Windows PowerShell 5.1: zwölf Tests), erweitert `Test-Detection.ps1`, `Test-SelfXPackageWizard.ps1`, `Test-SelfXWizardGui.ps1`. **Abweichung vom Plan, in Schritt 16 gefunden:** Vergleicht das `Detection.ps1` des vollständigen Pakets den Konfigurations-Digest, würden sich die beiden Pakete immer wieder gegenseitig neu installieren; die neue Art `FullWithoutConfig` (Option `-SeparateConfig`) verhindert das. Nicht auf einem Gerät ausprobiert: Intune mit zwei Apps und Abhängigkeit, Autopilot, ein signiertes Konfigurationspaket auf einem Gerät im Modus Signatur, ein geöffnetes SelfX-Fenster während des Austauschs.

- **Paketassistent: Seite Signatur und Anleitung in Schritten (`tools\Wizard\SelfXWizardGui.ps1` 1.1.0, `SelfXWizardGui.xaml` 1.1.0, `tools\Wizard\SelfXWizard.ps1` 3.1.3, `Wizard.en.xml`/`Wizard.de.xml` 1.4.0, `tools\New-SelfXPackage.ps1` 1.2.0):** Das Fenster hat vor der Zusammenfassung eine Seite **Signatur**: kein Zertifikat (Vertrauensmodus Hash, mit Erklärung der Folgen), ein Zertifikat aus den Speichern (angezeigt werden nur Zertifikate mit privatem Schlüssel, Verwendungszweck Codesignatur und gültigem Zeitraum; abgelaufene werden nicht angeboten) oder eine PFX-Datei. Das PFX-Kennwort wird aus einem Kennwortfeld nur als `SecureString` gelesen, einmal zum Öffnen der Datei verwendet (im Arbeitsspeicher, nicht importiert) und verworfen; das Feld wird geleert. Es gelangt nie in den Zustand, die Antworten, einen Text, den Fenstertitel oder eine Fehlermeldung. Die Seite zeigt Antragsteller, Aussteller, Ablauf, Fingerabdruck und die Sperrlisten-Adressen des Zertifikats und seiner Kette, mit einer Warnung, wenn keine, keine HTTP-Adresse oder nur interne Namen vorhanden sind. Ein Zeitstempeldienst ist Pflicht, außer das Signieren ohne Zeitstempel wird ausdrücklich eingeschaltet. Neu: weitere erlaubte Signierer für einen Zertifikatswechsel (Feld im Fenster, Konsole `-AdditionalSigner`, `Invoke-SelfXPackageBuild -AdditionalSigner`): Sie kommen in `-TrustedSigner` des Installationsbefehls (insgesamt höchstens 10 Fingerabdrücke), damit wird nichts signiert. Die Fortschrittsliste zeigt Signieren und Katalog. Die Ergebnisseite zeigt die Anleitung für Intune als Schritte mit Kopieren-Schaltflächen (App-Name, Paket, Installations- und Deinstallationsbefehl mit `-TrustedSigner`, Anforderungsskript, Erkennungsskript, Fingerabdrücke, Ausgabeordner, ASR-Dateiliste) aus der neuen Funktion `Get-SelfXIntuneGuideSteps`; die Textdatei enthält dieselben Zeilen. Die Anleitung im Vertrauensmodus Signatur nennt die Ereignisse 4006/4007, dass eine abgelehnte Signatur `Install.ps1` beendet, bevor `Install.log` geschrieben wird, und einen Schritt für den Zertifikatswechsel (60 Minuten, bis der Dienst ein abgelaufenes Zertifikat bemerkt). Neue Anleitung `docs\Certificate-Guide.md` / `docs\de\Zertifikat.md`: Anforderungen an das Zertifikat, Anforderung bei AD CS, Vertrauen auf den Geräten mit Intune (Profil „Vertrauenswürdiges Zertifikat“; „Vertrauenswürdige Herausgeber“ nur, wenn eigene Richtlinien es verlangen), Signieren mit dem Assistenten, Ablauf, Wechsel und Sperrung. Tests: `tools\Test-SelfXWizardGui.ps1` 1.1.0 (207 Prüfungen in PowerShell 7 und Windows PowerShell 5.1: abgelaufenes Zertifikat nicht angeboten, Speicher- und PFX-Modus, falsches und richtiges Kennwort, das Kennwort in keinem Text, Hilfetext, Fenstertitel, Zustand oder Antwortdatei, Zeitstempel und weitere Signierer, Nur-Konfigurieren mit Zertifikat abgelehnt, das Zertifikat erreicht den Hintergrund-Bau, Anleitung in Schritten). Auf einem PC mit dem Testskript ausprobiert; ein signierter Bau aus dem Fenster mit einem echten `IntuneWinAppUtil.exe`, ein Zertifikat einer echten PKI, die Intune-Profile und ein Screenreader wurden nicht ausprobiert.

- **Paketassistent als Fenster (`tools\Start-SelfXPackageWizard.cmd` 1.0.0, `tools\Wizard\SelfXWizardGui.ps1` 1.0.0, `tools\Wizard\SelfXWizardGui.xaml`, `tools\Wizard\Wizard.en.xml`/`Wizard.de.xml` 1.3.0, `tools\Wizard\SelfXWizard.ps1` 3.1.2, `tools\New-SelfXPackage.ps1` 1.1.1, `tools\SelfXRelease.Common.ps1` 3.1.1):** Der Paketassistent hat ein WPF-Fenster im Stil von SelfX. Seiten: Sprache, Grundlagen, Support, Branding (Logo mit Vorschau, Firmenfarbe sofort sichtbar), Ticket (mehrere Organisationen mit je einem Postfach, nach Gruppentag, OU oder Geräteklasse), weitere Einstellungen, Zusammenfassung mit den Einstellungen für den Bau, Bau mit Fortschrittsliste und Abbrechen, Ergebnis mit den Dateien und der Anleitung für Intune. Jeder Wert wird schon beim Tippen mit den Prüfungen der Konsole geprüft (`ConvertTo-WizardValue`, `Test-WizardUnitValues`, die Logo-Prüfung `Read-WizardLogo`); der Fehler steht am Feld, die nächste Seite öffnet sich nur ohne Fehler. Die Antworten sind dasselbe Objekt, das die Konsole aus einer Antwortdatei bildet (`Test-WizardAnswerSet`); gebaut wird mit `Invoke-SelfXWizardBuild` in einem Hintergrund-Runspace (das Fenster bleibt bedienbar; Abbrechen geht, bis das Ergebnis geschrieben wird). Antworten lassen sich laden und speichern (`selfx-answers.json`, nie ein Kennwort oder Schlüssel; unbekannte Antworten abgelehnt, höchstens 1 MB). Texte nur aus `Wizard.<Kultur>.xml` (de und en vollständig). Tastatur (Tab, Enter, Zugriffstasten) und Namen, Empfehlungen und Fehler für Screenreader (UI Automation). Die Stile werden aus `Sources\Self_X.ps1` gelesen (geparst, nicht ausgeführt), die Farben aus `Sources\Branding.ps1`; Hell oder Dunkel folgt Windows. Signieren und Netzwerkziele sind noch nicht im Fenster (Konsole). Start: `tools\Start-SelfXPackageWizard.cmd` (Windows PowerShell 5.1, `-NoProfile -STA`), die Datei ist Teil des Nutzlast-Archivs. Die Konsolenfassung bleibt für die Automatisierung; sie nutzt jetzt die gemeinsamen Funktionen `Get-WizardBuildDefaults` und `Invoke-SelfXWizardBuild` (gleiches Verhalten). Fehlerbehebung: Mehrere Intune-Plattformskripte stehen in der Anleitung je in einer eigenen Zeile (sie wurden in eine Zeile zusammengezogen). Tests: neu `tools\Test-SelfXWizardGui.ps1` in PowerShell 7 und Windows PowerShell 5.1 (CI: jetzt elf Tests im 5.1-Job): Text-Ids jeder Seite in de und en, jede Konsolenfrage auf genau einer Seite, Stile aus Self_X.ps1 mit Negativfällen, XAML in Hell und Dunkel, Prüfungen am Feld (E-Mail, Header-Injection, Skriptadresse, Logo, Farbe, Einheiten), Antworten des Fensters gleich der Konsole und dieselben Dateien eines Baus mit `-ConfigureOnly`, Antwortdateien, Abbrechen. Screenshots in `docs\images\selfx-wizard-*`. Auf einem PC mit dem Testskript und dem Fenster ausprobiert; ein echter Lauf von `IntuneWinAppUtil.exe` aus dem Fenster, ein Screenreader und ein Lauf aus einem echten Release-Archiv wurden nicht ausprobiert.

- **Paketassistent baut in einem Lauf (`tools\Wizard\SelfXWizard.ps1` 3.1.1, `tools\New-SelfXPackage.ps1` 1.1.0, `tools\SelfXPackage.Common.ps1`, `tools\New-SelfXWdacPolicy.ps1` 1.2.0):** Die neue Funktion `Invoke-SelfXPackageBuild` (Antworten, Nutzlast-Ordner, Ausgabeordner, Werkzeugpfad, optional Zertifikat und Zeitstempeldienst, Rückruf mit Schritt-Id und Text) erledigt einen ganzen Paketbau ohne Rückfrage: Sie prüft Antworten, Werkzeug und Zertifikat, kopiert den Paketteil des entpackten Nutzlast-Archivs, prüft die Kopie gegen `App\SelfX.Code.json`, `Bin\SelfX.Binaries.json` und `Detection.ps1`, schreibt Einstellungen und Logo, signiert optional jedes Programm und jedes Skript (Vertrauensmodus Signatur), schreibt `SelfX.Binaries.json`, `SelfX.Code.json`, `SelfX.Code.cat`, `SelfX.Config.json` und `Config\SelfX.Config.cat` in der Reihenfolge, die die Dateilisten verlangen, verpackt mit `IntuneWinAppUtil.exe` (Microsoft-Signatur geprüft), schreibt das Erkennungsskript mit den Digests (im Modus Signatur signiert), die AppLocker-Regeln (Hash oder Herausgeber) und mit einer ID der Basisrichtlinie die ergänzende App-Control-Richtlinie (WDAC), die Plattformskripte, die Anleitung und `selfx-answers.json`. Alles entsteht in einem Arbeitsordner neben dem Ausgabeordner und ersetzt diesen in einem Zug: Ein Fehler hinterlässt keine halbe Ausgabe, ein früheres Ergebnis bleibt. Abgelehnt werden ein Ausgabeordner mit fremdem Inhalt oder innerhalb der Nutzlast sowie eine Nutzlast mit geänderter, hinzugefügter oder unbekannter Datei, mit altem Aufbau oder mit bereits vorhandener Signatur. Im Modus Hash ist `SelfX.Code.json` im Ergebnis die Datei der Nutzlast. `selfx-answers.json` enthält nie ein Kennwort oder einen Schlüssel (ein unbekannter Antwortname beendet den Lauf). Logo: nur `png`, `jpg`, `ico` (Dateikopf geprüft, höchstens 2 MB, Datei einmal gelesen, gespeichert als `logo.<Typ>`); `bmp` und `gif` werden nicht mehr angenommen. Neue Antworten `AppLockerRules` und `WdacBasePolicyId`; die Anleitung nennt `-TrustedSigner`, die Regeldateien und den Weg zurück (`-AllowHashMode`). `New-SelfXPackage.ps1` fragt nur noch und ruft die Funktion auf; es arbeitet mit dem entpackten Nutzlast-Archiv ohne .NET SDK (im Repository bleibt `-BuildBinaries` möglich) und hat die neuen Parameter `-PayloadFolder`, `-CertificateThumbprint`, `-PfxPath` (das Kennwort wird als sichere Zeichenfolge abgefragt und nie gespeichert) und `-TimestampServer`. `New-SelfXWdacPolicy.ps1` liest den Paketaufbau `App`/`Config` und hat `-DetectionFile`. Tests: `tools\Test-SelfXPackageWizard.ps1` (kompletter Lauf mit einer Attrappe für `IntuneWinAppUtil.exe`, Abbruch mitten im Lauf, zweiter Lauf, geänderte Nutzlast, Logo-Prüfung, Geheimnis in den Antworten; der signierte Lauf nur mit einer vertrauenswürdigen Test-Wurzel). Die neuen Assistententexte gibt es nur in `de` und `en` (der Assistent hat keine weiteren Sprachdateien). Mit dem Testskript in PowerShell 7 und Windows PowerShell 5.1 auf einem PC ausprobiert; der signierte Lauf, die AppLocker- und App-Control-Skripte im Assistenten und ein echter Lauf von `IntuneWinAppUtil.exe` wurden auf keinem Gerät ausprobiert.

- **Startseite des Repositorys (`README.md`, `README.de.md`):** kurze Beschreibung von SelfX, Badges (CI, Release, Lizenz), Schritt-für-Schritt-Anleitung zum Herunterladen und Prüfen der Hashes sowie die Version 3.1.0. Nur Dokumentation; keine Änderung an Programmen, Skripten oder dem Paket. Auf einem Gerät nicht getestet.

- **Release-Workflow: Nutzlast-Archiv, Release-Notes, automatische Veröffentlichung (`.github\workflows\release.yml`,
  `tools\SelfXRelease.Common.ps1` 3.1.0):** Ein Versions-Tag baut jetzt neben dem Intune-Paket (`.intunewin`), seinem Erkennungsskript, der
  SBOM und `SHA256SUMS.txt` auch das **Nutzlast-Archiv** `SelfX-Service-<Version>-payload.zip`: der Paketordner, wie er gepackt wird
  (`Install.ps1`, `Uninstall.ps1`, `Detection.ps1`, `Bin`, `App` mit `SelfX.Code.json`, `Config` mit der Standardkonfiguration und
  `SelfX.Config.json`, `Service`), der Paketassistent und die Skripte, die er aufruft (`tools\Wizard`, `New-SelfXPackage.ps1` und die
  Werkzeuge darunter), `LICENSE.md`, `NOTICE.md` und `NOTICE.en.md`. Das Archiv ist reproduzierbar (Namen in Ordinal-Reihenfolge, feste
  Zeitmarke). Eine Verknüpfung, ein Name mit nicht erlaubten Zeichen, ein doppelter Name und eine fehlende Pflichtdatei stoppen den Bau.
  Eine neue Datei des Assistenten muss in die Liste in `SelfXRelease.Common.ps1`; der Test schlägt fehl, bis sie dort steht.
  `New-SelfXIntuneWin.ps1` hat den neuen Parameter `-PayloadFile` und schreibt das Archiv aus demselben Paketordner, der in die `.intunewin`
  kommt. Die **Release-Notes** sind der Abschnitt der Version in `CHANGELOG.en.md` (Fehler, wenn er fehlt, doppelt oder leer ist) plus der
  feste Block "Files and how to verify" (Dateitabelle, ein PowerShell-Befehl, der `SHA256SUMS.txt` prüft, und der Befehl für die
  Herkunftsbestätigung). `SHA256SUMS.txt` deckt alle Release-Dateien ab. **Das Release wird automatisch veröffentlicht**, wenn im selben
  Lauf alle Tests des CI-Workflows für den getaggten Commit bestanden haben (`service-ci.yml` hat den neuen Auslöser `workflow_call`;
  `release.yml` ruft ihn auf) und die Dateien gegen `SHA256SUMS.txt` geprüft wurden (genau die fünf Release-Dateien, Format und jeder
  Hash). Das Release entsteht zuerst als Entwurf und wird nach dem Hochladen veröffentlicht; schlägt ein Schritt fehl, bleibt kein Release
  zurück. Die Repository-Variable `RELEASE_DRAFT=true` legt stattdessen einen Entwurf an, und `RELEASE_ATTEST=false` schaltet die optionale
  Herkunftsbestätigung des Nutzlast-Archivs ab (`actions/attest-build-provenance`; nur dieser Job erhält die Rechte `id-token` und
  `attestations`). Unverändert: Der Workflow startet nur auf Versions-Tags, das Token, das Releases schreiben kann, wird nur im letzten
  Schritt des letzten Jobs verwendet (er führt keinen Code des Repositorys aus), es wird kein Geheimnis verwendet, alle Actions sind auf
  einen Commit-SHA festgelegt (neu: `actions/upload-artifact` 7.0.2, `actions/download-artifact` 8.0.2, `actions/attest-build-provenance`
  4.2.2). Ein bereits vorhandenes Release wird nie angefasst. Neuer Test `tools\Test-SelfXRelease.ps1` (Notes aus dem Changelog mit den
  Negativfällen und dem Prüfbefehl der Notes, Nutzlast-Archiv mit Negativfällen und manipulierten Archiven, Prüfsummendatei, Aufbau
  beider Workflows, Doku), in beiden Test-Jobs der CI. Doku: docs/de/Installation.md, "Alternative: Release auf GitHub", mit den
  Schritten, den Workflow ohne Release auszuprobieren. Der Workflow selbst ist auf GitHub noch nicht gelaufen.

- **Defender-ASR-Regel für ausführbare Dateien: Diagnose und Ausschluss (`tools\Get-SelfXAsrEvents.ps1` 3.1.0):** Ist die ASR-Regel
  „Block executable files from running unless they meet a prevalence, age, or trusted list criterion“ (`01443614-cd74-433a-b99e-2ecdc07bfc25`)
  aktiv, kann Defender Programme von SelfX blockieren. Das neue, nur lesende Skript `Get-SelfXAsrEvents.ps1` (Windows PowerShell 5.1 und
  PowerShell 7) liest die Ereignisse 1121 (Blockmodus) und 1122 (Überwachungsmodus) aus `Microsoft-Windows-Windows Defender/Operational`
  nur für diese eine Regel und zeigt Zeit, Modus, blockierte Datei, startenden Prozess und ob die Datei im Programmordner von SelfX liegt
  (`-SelfXOnly`, `-Days`, `-MaxEvents`). Protokoll, Regel und Felder stehen fest im Skript (kein Parameter nennt ein Protokoll, einen
  Rechner oder eine Datei). Es ändert nichts, liest die Felder `User` und die Befehlszeilen nie, zeigt den Profilordner eines Benutzers als
  `<user>`, liest die Ereignis-XML ohne DTD und meldet Ereignisse, die es keiner Regel zuordnen kann, statt sie zu verbergen. Doku:
  docs/de/Installation.md, „Defender ASR: Regel für ausführbare Dateien“ (Ursache, Prüfweg, Überwachungsmodus, Ausschluss je Regel für
  höchstens die vier SelfX-Dateien `SelfXService.exe`, `SelfX.exe`, `SelfXWinRT.dll` und `SelfXAudio.dll`, nicht der Ordner und nicht der
  globale Ausschluss, Programme des Releases, Signieren ist keine Zusage; Quellen: Microsoft Learn „ASR rules reference“ und „ASR FAQ“).
  Die Intune-Kurzanleitung des Paketassistenten bekommt vier neue Texte (`guide.asr`, `guide.asr1` bis `guide.asr3` in `Wizard.de.xml`
  und `Wizard.en.xml`, Sprachdateien 1.1.0) und einen weiteren Schritt vor dem Teststep. Neuer Test `tools\Test-SelfXAsrEvents.ps1`
  (nachgebildete Ereignisse statt des Protokolls: nur diese Regel, Block und Audit, unlesbare Ereignisse, DTD und Entität, kein
  Benutzername, Steuerzeichen, Grenzen, Fehler des Protokolls, nur lesende Befehle, Texte der Doku und des Assistenten), in beiden
  Testjobs der CI eingetragen. Die Feldnamen der Ereignisse stammen aus einem Beispielereignis, nicht aus der Dokumentation von
  Microsoft. Nicht auf einem Gerät erprobt, auf dem die Regel aktiv ist.
- **Herausgeberregeln für AppLocker und App Control (`tools\New-SelfXAppLockerRules.ps1` 1.1.0, `tools\New-SelfXWdacPolicy.ps1` 1.1.0):**
  Für ein mit dem Zertifikat der Organisation signiertes Paket ändern sich die Regeln nicht mehr mit jeder Version. `New-SelfXAppLockerRules.ps1
  -Mode Publisher` liest den Herausgeber aus der Signatur der übergebenen Dateien (alle müssen mit dem Status `Valid` vom selben
  Zertifikat signiert sein; nie ein Parameter) und schreibt **eine Herausgeberregel je Regelsammlung** (Exe, Dll, Script): Zulassen, SID
  `S-1-1-0`, kein Produkt, Dateiname oder Versionsbereich, feste Regel-IDs, keine Hashregeln. `New-SelfXWdacPolicy.ps1 -Level Publisher`
  erzeugt die ergänzende Richtlinie mit `New-CIPolicy -Level Publisher -Fallback Hash`: eine Signer-Regel des Signierzertifikats statt
  Hashregeln, Hashregeln nur für Dateien ohne Signatur, feste Richtlinien-ID wie bisher. Vor dem Scan stoppt es bei einer Datei mit
  ungültiger Signatur, bei mehreren Signierern (außer mit `-AllowMultipleSigners`) und bei einem Paket, dessen `Install.ps1` nicht
  signiert ist; nach dem Scan prüft es die Richtlinie (Signer-Regeln ohne Dateiattribut, keine Hashregel neben einer signierten Datei,
  kein gesperrter Signierer) und listet die Herausgeber, denen vertraut wird. **Standard unverändert:** ohne `-Mode` / `-Level` schreiben
  beide Werkzeuge wie bisher Hashregeln. Neue Dateien: `tools\SelfXPublisherRules.ps1` (Funktionen des Herausgebermodus und die
  Prüfungen, kein AppLocker- oder ConfigCI-Cmdlet), `tools\SelfXTestCertificate.ps1` (Testhilfe). Doku: docs/de/Installation.md,
  „Einmal einrichten statt je Version“. Tests: `Test-SelfXAppLockerRules.ps1` (Aufbau, SID statt Name, keine Hashregel oder Version,
  veränderte Richtlinien als Negativtests, nachgebildete Signaturzustände, Ablehnungen; mit vertrauenswürdigem Testzertifikat auch ein Lauf
  mit signierten Dateien), `Test-WdacPolicy.ps1` (Prüfungen von Signer-Richtlinien an künstlichen Texten, Ablehnung ohne signierte Datei;
  mit vertrauenswürdigem Testzertifikat auch ein Lauf). Nicht auf einem Gerät erprobt.
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
