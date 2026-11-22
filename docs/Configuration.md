# Konfiguration

[English](en/Configuration.md) | **Deutsch**

SelfX nutzt XML-Dateien für seine Einstellungen und seinen Aktionskatalog.
Bearbeiten Sie sie im Paket vor der Installation.

## SelfX Service

SelfX Service wird mit den Dateien in `SelfX Service\Sources` konfiguriert.
Bearbeiten Sie sie im Paket vor der Installation. Nach der Installation können die
Dateien in `%ProgramFiles%\SelfX` nur Administratoren ändern. Änderungen werden
durch eine neue Paketversion ausgeliefert. Es gibt kein Remote-Update und keinen
Download beim Start.

### Aktionskatalog

`Issues_List.xml` hat die Struktur `XML_Version`, `Quick_Solution`,
`Detailed_Solution`, `Action` mit englischen Basistexten. Außerdem enthält er:

- Ein Attribut `Id` an jeder Aktion, zum Beispiel
  `<Action Id="D_Teams_SoundCuts">`. Es muss eindeutig sein. Die Sprachdateien
  übersetzen die Aktion über diese Id.
- Einen optionalen Abschnitt `Messages` mit Texten, die mehrere Aktionen teilen.
  `Explanation` und `Alerte_MSG` können mit `Ref="<Message-Id>"` darauf verweisen,
  statt einen eigenen Text zu haben, zum Beispiel
  `<Alerte_MSG Ref="Msg_Teams_Restart"/>`.
- `Category` enthält eine Kategorie-Id (`Browser`, `Device`, `Intune`, `Office`,
  `OneDrive`, `Outlook`, `Teams`). Der angezeigte Name kommt aus der Sprachdatei.

Jede Aktion hat diese zusätzlichen Elemente:

| Element | Werte | Zweck |
|---|---|---|
| `Context` | `User` oder `System` | `User` führt das Skript als angemeldeter Nutzer aus. `System` sendet den Skriptnamen an den SelfXService, der es als SYSTEM ausführt. Fehlt das Element oder hat es einen anderen Wert, wird die Aktion als `User` behandelt. |
| `TimeoutSeconds` | 1–7200, Standard 900 | Nur für `System`-Aktionen. Der Dienst stoppt das Skript und seine Kindprozesse nach dieser Zeit und meldet einen Timeout. |
| `OtherSessions` | leer oder `Block` | Optional, nur für `System`-Aktionen. `Block`: Ein normaler Nutzer kann die Aktion nicht starten, solange ein anderer Nutzer eine **aktive** Sitzung auf dem Gerät hat (der Dienst antwortet `ERROR OtherSessions`, das Fenster zeigt einen Hinweis). Administratoren mit erhöhten Rechten sind nicht eingeschränkt. Lassen sich die Sitzungen nicht lesen, wird die Aktion blockiert (fail closed). Setzen Sie es an jedem Eintrag desselben Skripts; der Dienst blockiert, wenn ein beliebiger `System`-Eintrag des Skripts `Block` angibt. Standard im mitgelieferten Katalog: Neustart des Intune-Dienstes, Neustart der Netzwerkadapter und die CHKDSK-Reparatur. |
| `Post_Action` | leer oder `MailReport` | Optional, nur für `System`-Aktionen. `MailReport`: Nach einem erfolgreichen Lauf hängt die Oberfläche den neuesten Bericht des Nutzers an eine neue Support-E-Mail. Siehe [Geräteprotokolle für den Support](#geräteprotokolle-für-den-support-selfx-service-240). |

Beispiel:

```xml
<Action Id="D_Intune_RestartService">
	<Name>Restart Intune service</Name>
	<Buttons>Ok_Cancel</Buttons>
	<Explanation>You want to force a synchronization between your device and Intune.</Explanation>
	<Script>SelfX_Intune_RestartService.ps1</Script>
	<Context>System</Context>
	<TimeoutSeconds>300</TimeoutSeconds>
	<Category>Intune</Category>
	<Alerte_MSG>The Intune Management Extension service will be restarted.

Do you want to continue?</Alerte_MSG>
</Action>
```

Regeln für `System`-Aktionen:

- `Script` muss ein reiner Dateiname aus Buchstaben, Ziffern, `_`, `-` und `.`
  sein und auf `.ps1` enden. Die Datei muss in `Scripts_to_run` liegen. Der Dienst
  weist alle anderen Namen ab.
- Dasselbe Skript darf in mehreren Aktionen vorkommen, zum Beispiel in der
  vereinfachten und der detaillierten Ansicht. Der erste `System`-Eintrag eines
  Skripts legt seine `TimeoutSeconds` fest.
- Das Skript läuft nicht interaktiv als SYSTEM: Es gibt kein Benutzerprofil, keinen
  Desktop und keine Eingabeaufforderungen. Verwenden Sie nicht interaktive Befehle,
  geben Sie einen aussagekräftigen Exitcode zurück (`0` = Erfolg) und schreiben Sie
  Diagnoseausgaben nach stdout oder stderr. Die Ausgabe wird protokolliert.
- Jeder angemeldete Nutzer kann jede `System`-Aktion starten. Nehmen Sie nur
  Aktionen auf, die für jeden Nutzer sicher sind.
- Der Dienst übergibt die SID des anfragenden Nutzers in der Umgebungsvariable
  `SELFX_CALLER_SID` (aus dem Pipe-Client-Token gelesen, SelfX Service 2.4.0 und
  neuer). Verwenden Sie sie nur, um Ergebnisse an diesen Nutzer zu übergeben, nie,
  um zu entscheiden, ob eine Aktion erlaubt ist.

Wenn Sie eine Aktion hinzufügen, geben Sie ihr eine neue `Id` und ergänzen Sie ihre
Übersetzungen in den Sprachdateien (siehe [Sprachen](#sprachen)). Ohne Übersetzung
erscheint der englische Text aus `Issues_List.xml`.

Die mitgelieferten `System`-Aktionen sind:

| Skript | Zweck |
|---|---|
| `SelfX_Intune_RestartService.ps1` | Den Dienst der Intune Management Extension neu starten |
| `SelfX_Device_AirePlaneMode.ps1` | Alle aktivierten physischen Netzwerkadapter neu starten |
| `SelfX_OneDrive_CHKDSK.ps1` | `chkdsk /r /f` des Systemlaufwerks für den nächsten Neustart planen |
| `SelfX_Device_CollectLogs.ps1` | Die Geräteprotokolle mit `Collect-DeviceLogs.ps1` sammeln und eine Support-E-Mail mit dem Bericht öffnen (`Post_Action` `MailReport`) |

### UI-Einstellungen

`Tool_Config.xml` enthält nur Einstellungen. Alle Texte des Fensters stehen in den
Sprachdateien (siehe [Sprachen](#sprachen)). Textschlüssel wie `Main_Title_Text`,
`Subtitle_Text` oder `SystemInfo_*_Text`, `Link_Scripts` und die Schlüssel der
Installations-Benachrichtigungen werden nicht verwendet.

| Schlüssel | Zweck |
|---|---|
| `Tool_Language` | Standardsprache. `de` (Standard, Basissprache) zeigt Deutsch. `Auto` nutzt die Anzeigesprache von Windows des Nutzers (Deutsch, wenn keine Sprachdatei passt). Ein anderer Kulturname wie `en`, `fr-CH` oder `zh-Hans` legt diese Sprache fest. Texte, die in einer Sprache fehlen, erscheinen auf Englisch. Nutzer können in den Einstellungen eine andere Sprache wählen, sofern `Show_Language_Setting` nicht `False` ist; siehe [Sprachen](#sprachen). |
| `Tool_Name` | Text in der Titelleiste und im Info-Dialog |
| `Shortcut_Desktop`, `Shortcut_StartMenu`, `Shortcut_Name` | Verknüpfungen für alle Nutzer, die `Install.ps1` anlegt |
| `Show_Computer_Name_MainGUI`, `Show_Computer_Name_title_bar` | Den Computernamen neben dem Titel anzeigen |
| `Default_Solution_Mode` | `Simplified` oder `Detailed` |
| `Show_Reboot_Warning`, `Show_About_Button` | Neustart-Erinnerung und Info-Schaltfläche (i) anzeigen oder ausblenden |
| `Show_Theme_Button` | `True`: Nutzer können das Erscheinungsbild (Automatisch wie Windows, Dunkel oder Hell) im Einstellungsdialog (Zahnrad) wählen |
| `Show_Language_Setting` | `True` (Standard, 2.5.9): Nutzer können die Sprache von SelfX im Einstellungsdialog wählen. `False` blendet die Auswahl aus und verwendet immer `Tool_Language`; eine zuvor von einem Nutzer gespeicherte Sprache wird dann ignoriert. |
| `Show_Support_Button`, `Support_Hours`, `Support_Phone_number`, `Support_Mail`, `Support_Teams`, `Support_Website` | Hilfe-Schaltfläche (?) und die Kontakte des Hilfe-Dialogs, siehe [Benutzeroberfläche](#benutzeroberfläche-selfx-service-250). `Support_Mail` ist auch der Empfänger der E-Mail mit den Geräteprotokollen. |
| `DeviceLogs_Days`, `DeviceLogs_Compress` | Bericht mit Geräteprotokollen: Tage des Ereignisprotokoll-Verlaufs (1–60, Standard 7) und `.zip` (`True`, Standard) oder `.txt` als Anhang |
| `Log_Retention_Days` | Protokolldateien, die älter sind als diese Anzahl Tage, werden gelöscht (1–3650, Standard 90, 2.6.0); siehe [Protokollierung](#protokollierung-und-aufbewahrung-selfx-service-260) |
| `Show_Status_Page` | `True` (Standard): die Seite Gerätestatus anzeigen |
| `Show_SystemInfo_Tab`, `Show_SystemInfo_Intune_Actions`, `SystemInfo_Internet_Test_Host`, `SystemInfo_Internet_Test_Port` | Seite Systeminformationen und ihre Werkzeuge |
| `Show_Tray_Icon`, `Tray_Notifications`, `Tray_Poll_Seconds` | Statussymbol, siehe [Statussymbol](#statussymbol-selfx-service-250) |

Erhöhen Sie `Tool_Version` bei jedem Release und setzen Sie denselben Wert in
`Detection.ps1`.

### Benutzeroberfläche (SelfX Service 2.5.0)

Das Fenster ist für Nutzer ohne technisches Wissen gestaltet. Seine Größe lässt
sich ändern, es kann maximiert werden (Minimum 640 × 480); unter 900 Pixel zeigt
die Navigationsleiste nur Symbole, und die Karten ordnen sich in einer bis drei
Spalten an. Größe, Position, Design, Sprache und die Wahl für das Statussymbol
werden pro Nutzer in `HKCU\Software\SelfX` gespeichert. Pro Nutzer läuft nur ein
SelfX-Fenster: Ein zweiter Start (Verknüpfung oder Statussymbol) bringt das offene
Fenster in den Vordergrund.

- **Navigationsleiste** (links): *Fehlerbehebung*, *Gerätestatus* (mit einem Zähler
  der Probleme und Warnungen), *Systeminformationen*, oben das Firmenlogo
  (`Brand_Logo`), unten **Protokolle an Support senden** und der Zustand des
  lokalen Dienstes.
- **Fehlerbehebung**: Suchfeld, Kategorieschaltflächen, Umschalter zwischen
  vereinfachter und detaillierter Ansicht (das Info-Symbol erklärt den
  Unterschied) und eine Karte pro Aktion mit einem Info-Symbol (Erklärung), einer
  Start-Schaltfläche (ausführen, mit Bestätigung) und einem Schild für Aktionen mit
  Administratorrechten. Solange eine Aktion läuft (2.6.1), zeigt ihre
  Start-Schaltfläche ein rotierendes Symbol und *Läuft…* und ist gesperrt; sobald
  die Aktion beendet ist, wird sie wieder normal. System-Aktionen enden, wenn der
  Dienst geantwortet hat; Nutzeraktionen werden beobachtet, bis ihr Skriptprozess
  beendet ist, dann erscheint das Ergebnis (Exitcode 0 = Erfolg) in der
  Meldungsleiste und wird protokolliert. Die Schaltfläche **Beheben** einer
  Statuskarte verhält sich ebenso, solange ihre Reparatur läuft.
- **Gerätestatus**: eine Karte pro Prüfung, Probleme zuerst. Farbe und Beschriftung
  zeigen In Ordnung, Ausstehend (Warnung), Fehler oder Unbekannt. **Beheben**
  (Schraubenschlüssel) führt nach Bestätigung die konfigurierte Reparatur aus; die
  Pfeil-Schaltfläche prüft nur diesen Status erneut; die Pfeil-Schaltfläche oben
  prüft alles. **Alle Probleme beheben** (2.5.3) erscheint, wenn mindestens eine
  Karte mit Fehler oder Ausstehend eine Reparatur hat; nach einer Bestätigung führt
  sie jede konfigurierte Reparatur einmal aus (eine pro Skript, nacheinander über
  den Dienst) und prüft dann alles erneut. Ist der Dienst nicht verfügbar oder
  beschäftigt, werden die übrigen Reparaturen übersprungen und gemeldet. Zeiten
  werden als UTC erfasst (`{utc:...}`-Marker in den Details der Gesundheitsprüfung)
  und in der aktuellen Zeitzone des Nutzers angezeigt, auch nach einer
  automatischen Änderung der Zeitzone während der OOBE. Der Status der
  Hintergrundprüfungen des Dienstes wird sofort angezeigt, siehe
  [Hintergrundprüfungen](#hintergrundprüfungen-und-status-cache-selfx-service-250).
- **Systeminformationen**: eine Karte pro Abschnitt (Gerät, Windows, Nutzer und
  Verwaltung, Netzwerk, Bericht); ein Doppelklick auf eine Zeile kopiert ihren
  Wert. Die zuletzt erfassten Werte erscheinen sofort aus
  `%LOCALAPPDATA%\SelfX\SystemInfo.json` und werden im Hintergrund aktualisiert.
  Aktualisieren, Kopieren und Exportieren (TXT, HTML, CSV, JSON) sind
  Symbolschaltflächen; Kopieren und Export enthalten den Gerätestatus. Die
  *Werkzeuge* (Intune-Synchronisierung, Compliance-Prüfung, Unternehmensportal,
  Quick Assist, MDM-Protokolle, Protokolle senden) sind Kacheln unter den
  Informationen.
- **Titelleiste**: Hilfe (?), Einstellungen (Zahnrad: Sprache, Design,
  Statussymbol) und Info (i).
- **Hilfe-Dialog**: zeigt nur die konfigurierten Kontakte: `Support_Hours`,
  `Support_Phone_number`, `Support_Mail` (Schaltfläche *E-Mail schreiben*),
  `Support_Teams` (Schaltfläche *Chat starten*: Eine Nutzer- oder
  Gruppenpostfach-Adresse öffnet einen Teams-Chat, ein vollständiger
  `https://`-Teams-Link wird unverändert geöffnet) und `Support_Website`
  (Schaltfläche *Öffnen*, nur `http://` oder `https://`). Ohne Kontakt bittet der
  Dialog den Nutzer, die IT-Abteilung zu kontaktieren.

Jede Symbolschaltfläche hat eine Kurzinfo, die erklärt, was geschieht. Bestätigungen,
Erklärungen und Meldungen nutzen Dialoge im gleichen Stil; Ergebnisse von Aktionen
und die Neustart-Erinnerung erscheinen in der Meldungsleiste unten.

### Hintergrundprüfungen und Status-Cache (SelfX Service 2.5.0)

Der Dienst führt alle Gesundheitsprüfungen regelmäßig im Hintergrund aus und behält
das Ergebnis in `%ProgramData%\SelfX\Cache\Health.json` (nur für SYSTEM und
Administratoren lesbar). SelfX und das Statussymbol lesen es mit der Anfrage
`STATUS`, die sofort antwortet und nichts ausführt. Jede Prüfung, die SelfX startet
(alle oder ein einzelner Status), aktualisiert ebenfalls den Cache.

Einstellungen in `Health_Config.xml`:

```xml
<Background Enabled="true" IntervalMinutes="15" PauseOnBattery="true" MaxCpuPercent="75" StartDelaySeconds="120" />
```

| Attribut | Standard | Zweck |
|---|---|---|
| `Enabled` | `true` | `false` = keine Hintergrundprüfungen; SelfX prüft dann, wenn es geöffnet wird. |
| `IntervalMinutes` | `15` | 5–1440. Zeit zwischen zwei Hintergrundprüfungen. |
| `PauseOnBattery` | `true` | Keine Hintergrundprüfung im Akkubetrieb. SelfX zeigt das letzte Ergebnis und den Hinweis, dass die Prüfungen pausiert sind. |
| `MaxCpuPercent` | `75` | 10–100. Eine Prüfung wird verschoben (neuer Versuch nach 2 Minuten), solange die Prozessorlast höher ist; `100` = kein Limit. |
| `StartDelaySeconds` | `120` | 0–3600. Erste Prüfung nach dem Start des Dienstes, damit die Anmeldung nicht verlangsamt wird. |

Fehlende oder ungültige Werte verwenden den Standard. Eine Hintergrundprüfung wird
außerdem verschoben, solange eine Reparatur läuft. Sie führt PowerShell mit
niedrigerer Priorität und dem 240-Sekunden-Limit der Gesundheitserfassung aus; nach
`SelfXService.log` wird nur eine Zusammenfassungszeile geschrieben. Änderungen der
Einstellungen gelten ohne Neustart des Dienstes.

### Statussymbol (SelfX Service 2.5.0)

`SelfX_Tray.ps1` zeigt im Infobereich ein SelfX-Symbol mit einem farbigen Punkt:
grün (in Ordnung), gelb (Warnung), rot (Problem) oder grau (Status noch nicht
verfügbar). Die Kurzinfo zeigt die Anzahl der Probleme und Warnungen. Wechselt
eine Prüfung zu Fehler, zum Beispiel *Datenträgerkapazität*, erscheint einmal eine
Windows-Benachrichtigung; ein Klick darauf öffnet die Seite Gerätestatus. Unter
Windows 10 und 11 erscheinen diese Benachrichtigungen als Windows-Toast
(und bleiben im Benachrichtigungscenter erhalten). Das Rechtsklick-Menü öffnet
SelfX, den Gerätestatus, prüft den Status jetzt, sendet die Protokolle an den
Support, schaltet die Benachrichtigungen ein oder aus (2.6.5) oder verbirgt das
Symbol.

| Schlüssel in `Tool_Config.xml` | Standard | Zweck |
|---|---|---|
| `Show_Tray_Icon` | `True` | `Install.ps1` legt den HKLM-Run-Eintrag `SelfXTray` an, sodass das Symbol bei jeder Anmeldung für alle Nutzer startet, und startet es (als SYSTEM, seit 2.5.8) sofort für die angemeldeten Nutzer. `False` entfernt den Eintrag. |
| `Tray_Notifications` | `True` | Eine Benachrichtigung zeigen, wenn eine Prüfung zu Fehler wechselt. Jeder Nutzer kann die Benachrichtigungen ausschalten (2.6.5). `False` schaltet sie für alle Nutzer aus und blendet den Nutzerschalter aus. |
| `Tray_Poll_Seconds` | `60` | 15–3600. Wie oft das Symbol den zwischengespeicherten Status liest (es wird keine Prüfung ausgeführt). |

**Benachrichtigungen pro Nutzer (2.6.5):** Jeder Nutzer entscheidet, ob zusätzlich
zum farbigen Symbol Windows-Benachrichtigungen erscheinen: Schalter
*Benachrichtigungen über Probleme anzeigen* in SelfX > Einstellungen oder
*Benachrichtigungen anzeigen* im Menü des Symbols. Die Wahl wird in
`HKCU\Software\SelfX\TrayNotifications` gespeichert (1 = an, Standard; 0 = aus) und
gilt sofort ohne Neustart des Symbols. Solange sie aus sind, zeigt das Symbol das
Problem weiterhin (roter Punkt, Kurzinfo) und Probleme werden weiterhin gemerkt,
sodass das erneute Einschalten bereits bekannte Probleme nicht erneut meldet.
Antworten auf Aktionen des Nutzers (*Status jetzt prüfen*, *Dieses Symbol
verbergen*) erscheinen immer.

SelfX Service zeigt nach der Installation keine Benachrichtigung.

Jeder Nutzer kann das Symbol verbergen (Menü *Dieses Symbol verbergen* oder
SelfX > Einstellungen) und in SelfX > Einstellungen wieder anzeigen; die Wahl wird in
`HKCU\Software\SelfX\TrayIcon` gespeichert. Das Symbol braucht keine
Administratorrechte: Es liest nur den Status-Cache über die Pipe des Dienstes. Kurz
nach dem Start erfasst es einmal im Hintergrund die Systeminformationen des Nutzers,
sodass SelfX sie sofort anzeigt. Eine Installation oder ein Update über Intune/SCCM
(SYSTEM) schließt die laufenden Symbole und startet die neue Version sofort in den
Sitzungen der angemeldeten Nutzer (2.5.8); Nutzer, die das Symbol ausgeschaltet
haben, bekommen es nicht zurück. Nach einer Deinstallation werden die Symbole
geschlossen. Das Öffnen von SelfX startet das Symbol ebenfalls, wenn es noch nicht
läuft (zum Beispiel nach einer manuellen Installation).

### Geräteprotokolle für den Support (SelfX Service 2.4.0)

Die Aktion **Geräteprotokolle an den Support senden** (`Q_Device_SendLogs` in der
vereinfachten Ansicht, `D_Device_SendLogs` in der detaillierten Ansicht, Kategorie
`Device`) und die Schaltflächen **Protokolle an Support senden** (Navigationsleiste,
Seite Systeminformationen und Statussymbol) sammeln alle Protokolle, die zur Analyse
eines Geräteproblems nötig sind, und öffnen eine neue E-Mail an den Support mit dem
Bericht im Anhang. Der Nutzer beschreibt das Problem und sendet die E-Mail; nichts
wird automatisch gesendet.

Funktionsweise:

1. Der Nutzer bestätigt die Aktion. Die Oberfläche sendet
   `RUN SelfX_Device_CollectLogs.ps1` an den lokalen Dienst (Schild-Aktion, Timeout
   1800 Sekunden).
2. Der Dienst führt den Wrapper als SYSTEM aus und übergibt die SID des anfragenden
   Nutzers in `SELFX_CALLER_SID`. Der Wrapper startet den nur lesenden Collector
   `Scripts_to_run\Collect-DeviceLogs.ps1` mit Administratorrechten. Er schreibt
   einen Bericht nach
   `%ProgramData%\SelfX\Reports\<Nutzer-SID>\DeviceLogs-<Computer>-<Zeit>.txt` und
   komprimiert ihn zu einer `.zip`-Datei (sofern `DeviceLogs_Compress` nicht `False`
   ist).
3. Der Berichtsordner des Nutzers hat eine geschützte ACL: SYSTEM und
   Administratoren haben Vollzugriff, nur der anfragende Nutzer kann lesen. Kein
   anderer Nutzer kann den Bericht lesen. Der vorherige Bericht des Nutzers wird bei
   jedem Lauf gelöscht; Berichte, die älter als 7 Tage sind, werden für alle Nutzer
   gelöscht.
4. Nach einem erfolgreichen Lauf kopiert die Oberfläche den Bericht nach
   `%LOCALAPPDATA%\SelfX\Reports` und öffnet eine neue E-Mail mit der Kopie im
   Anhang:
   - klassisches Outlook über COM: Empfänger `Support_Mail`, lokalisierter Betreff
     (`Report_Mail_Subject`) und Text (`Report_Mail_Body`) werden eingetragen;
   - sonst `outlook.exe /a <Datei>` (der Nutzer trägt den Empfänger ein);
   - sonst (zum Beispiel neues Outlook, das keine COM-Schnittstelle hat) die
     Standard-Mail-App über `mailto:` und ein Explorer-Fenster mit der markierten
     Datei, sodass der Nutzer sie anhängen kann.

Der Collector liest das Gerät nur: Er ändert nichts, lädt keine Registry-Struktur,
startet keine Installation und sendet nichts. Der Bericht enthält den Computernamen,
Nutzer- und Mandantennamen und Protokollinhalte des Geräts (Autopilot-/ESP-Status,
IME- und Win32-App-Protokolle, Servicing-Protokolle, Ereignisprotokolle, AppX,
Windows Update, Netzwerk- und Sprachstatus). Er läuft etwa ein bis einige Minuten.
Die Liste der Abschnitte und die Parameter stehen im Kopf von
`Collect-DeviceLogs.ps1`; ersetzen Sie die Datei, um den Collector zu aktualisieren.

**Umfang des Berichts auf Geräten mit mehreren Nutzern (2.6.10):** Der Bericht wird
pro Nutzer beschnitten. Der Dienst liest das Token des Pipe-Clients und übergibt
`SELFX_CALLER_ADMIN` an das Skript: `1` nur, wenn die lokale Gruppe *Administratoren*
in diesem Token **aktiviert** ist (ein Administrator mit erhöhten Rechten), sonst
`0`. Ein fehlender oder anderer Wert (zum Beispiel bei einem älteren Dienst) gilt als
normaler Nutzer (fail closed).

| | Administrator (`1`) | Normaler Nutzer (`0` oder fehlend) |
|---|---|---|
| Collector | vollständig | `-UserView -CallerSid <eigene SID>` |
| Seriennummer, Konsolennutzer | ja | nein |
| Sitzungen (`quser`) | alle | nur die eigene Sitzung |
| Beitrittsstatus (`dsregcmd`) | alles | nur Beitritts- und Anmeldestatus, keine Mandanten-, Geräte- oder Nutzer-IDs |
| Profile und Nutzerstrukturen der Registry | alle | eigenes Profil und eigene Struktur |
| AppX-Nutzereinträge | alle | eigener Eintrag |
| Namen, SIDs und Profilordner anderer lokaler Nutzer in jeder Zeile | unverändert | ersetzt durch `<other user>` |
| SelfX-Geräteprotokolle (`SelfXService.log`, Skriptprotokolle) | ja | nein (sie nennen alle Nutzer) |
| Eigene SelfX-Nutzerprotokolle | ja | ja |

Der Collector läuft auch ohne `-UserView` (Intune-Win32-App, Remediation, manueller
Lauf): Der Bericht ist dann wie bisher vollständig. Beachten Sie, dass ein
Administrator, der SelfX **ohne** erhöhte Rechte ausführt, als normaler Nutzer
behandelt wird, weil die Gruppe Administratoren im gefilterten Token nur „deny-only“
ist.

**SelfX-Protokolle im Bericht (2.6.4, geändert in 2.6.10):** Der Bericht enthält die
Protokolle von SelfX selbst (siehe
[Protokollierung](#protokollierung-und-aufbewahrung-selfx-service-260)). Sie werden
von zwei verschiedenen Seiten hinzugefügt, jede mit ihren eigenen Rechten:

- der **Wrapper (SYSTEM)** fügt, **nur für Administratoren** (siehe Tabelle oben),
  die Geräteprotokolle aus `%ProgramData%\SelfX\Logs` hinzu: immer
  `SelfXService.log`, `Install.log` und `Uninstall.log`, außerdem alle anderen
  `*.log`-Dateien (Skripte, Gesundheitsprüfungen, Erkennung) der letzten
  `DeviceLogs_Days` Tage. Es werden nur die Dateien direkt in diesem Ordner gelesen;
  der Unterordner `Logs\Users` wird als SYSTEM nie gelesen;
- das **SelfX-Fenster (der angemeldete Nutzer)** fügt die Protokolle des **eigenen
  Nutzers** (Fenster, Statussymbol, Nutzeraktionen) aus
  `%ProgramData%\SelfX\Logs\Users\<eigene SID>` der letzten `DeviceLogs_Days` Tage
  seiner Kopie des Berichts in `%LOCALAPPDATA%\SelfX\Reports` hinzu, mit den Rechten
  des Nutzers. Protokolle anderer Nutzer werden nie hinzugefügt.

In der `.zip` sind sie eigene Dateien im Ordner `SelfX-Logs` (`SelfX-Logs\User` für
die Nutzerprotokolle); in einem `.txt`-Bericht werden sie als letzter Abschnitt
angehängt. Es werden höchstens die letzten 2 MB jeder Datei und 30 MB pro Seite
hinzugefügt.

Warum: Nutzer können ihren eigenen Ordner unter `Logs\Users` anlegen und ändern.
Würde SYSTEM ihn lesen, könnte ein Nutzer das Lesen (zum Beispiel mit einer
Junction, die zwischen Prüfung und Lesen ausgetauscht wird) auf eine geschützte
Datei umlenken, deren Inhalt dann im Bericht stünde, den der Nutzer öffnen kann. Weil
das Fenster die eigenen Protokolle mit den Rechten des Nutzers liest, kann es nur
hinzufügen, was der Nutzer ohnehin lesen könnte. Ein Problem beim Hinzufügen der
Nutzerprotokolle stoppt die E-Mail nie. Übersprungen werden eine Junction als Ordner
und Dateien, die ein anderes Konto besitzt.

Beachten Sie, dass `SelfXService.log` (Geräteprotokolle) die Nutzer nennt, die auf
diesem Gerät Aktionen gestartet haben.

Exitcodes von `SelfX_Device_CollectLogs.ps1`: `0` Bericht erstellt, `1` Sammeln oder
Komprimieren fehlgeschlagen, `2` anfragender Nutzer unbekannt (Dienst älter als
2.4.0). Der Wrapper schreibt die Zusammenfassung des Collectors und den Berichtspfad
nach `SelfXService.log` und (2.6.0) in sein eigenes Protokoll.

Um die Funktion mit einem anderen Berichtsskript zu nutzen, behalten Sie
`Post_Action` `MailReport` bei und schreiben Sie den Bericht als `DeviceLogs-*.zip`
oder `DeviceLogs-*.txt` mit derselben ACL nach
`%ProgramData%\SelfX\Reports\<SELFX_CALLER_SID>`. Entfernen Sie beide
Katalogaktionen, um die Funktion auszublenden; die Schaltfläche in den
Systeminformationen erscheint nur, wenn eine `System`-Aktion mit `MailReport`
existiert.

### Protokollierung und Aufbewahrung (SelfX Service 2.6.0)

Alle Skripte von SelfX Service protokollieren über das gemeinsame Modul
`Sources\SelfXLog.ps1` nach `%ProgramData%\SelfX\Logs`: das Fenster, das
Statussymbol, die Gesundheitsprüfungen, die Compliance-Prüfung, das
Erkennungsskript und jedes Aktions- und Reparaturskript. Eine Datei pro Skript und
Tag, `<Skript>_<jjjj-MM-tt>.log`, UTF-8 mit BOM, eine Zeile pro Eintrag in der
Ortszeit des Geräts:

```text
2026-11-06 13:29:56.522 | Info    |  52068 | SelfX 2.6.0 opened: language de (setting de), page ''.
2026-11-06 13:30:04.426 | Warning |  52068 | Message (Warning): Windows restarts in about 30 seconds. ...
```

| Ordner | Inhalt | Lesbar für |
|---|---|---|
| `Logs` | Skripte, die als SYSTEM laufen (Reparaturen und über den Dienst gestartete System-Aktionen, `HealthStatus`, `Check-Compliance`, `Detection`), `SelfXService.log`, `Install.log`, `Uninstall.log` | SYSTEM und Administratoren |
| `Logs\Users\<SID>` | Skripte des Nutzers: das Fenster (`SelfX_*`), das Statussymbol (`SelfX_Tray_*`) und die Nutzeraktionen | Den Nutzer, SYSTEM und Administratoren |

Das Fenster protokolliert seinen Start, jede Aktion mit der Antwort des Nutzers, das
Ergebnis jeder Dienstaktion (Status und Exitcode), die vom Nutzer gestarteten
Statusprüfungen, die Sprachwechsel und **jede dem Nutzer angezeigte Meldung**. Das
Statussymbol protokolliert Statusänderungen, Benachrichtigungen und warum es endet.
Jedes Aktionsskript protokolliert seine Schritte und sein Ergebnis; unerwartete
Fehler werden protokolliert, bevor das Skript endet. `HealthStatus` protokolliert
jedes Prüfergebnis der Hintergrundprüfungen (eine Zeile pro Prüfung alle 15
Minuten).

`Install.ps1` legt `Logs\Users` so an, dass Nutzer nur ihren eigenen Ordner anlegen
können (CREATOR OWNER = Vollzugriff darauf) und die Ordner anderer Nutzer weder
auflisten noch lesen können. Ein Ordner, der ein Link ist oder einem anderen Konto
gehört, wird nie verwendet. Ohne diesen Ordner (Installationen vor 2.6.0 oder wenn er
nicht verwendet werden kann) gehen die Nutzerprotokolle nach
`%LOCALAPPDATA%\SelfX\Logs`.

**Aufbewahrung:** Protokolldateien, die älter sind als `Log_Retention_Days` in
`Tool_Config.xml` (1–3650, Standard **90**), werden gelöscht:

- Der SelfX-Dienst löscht alte `*.log`- und `*.old`-Dateien in `Logs` einmal am Tag
  (das erste Mal nach der Startverzögerung der Hintergrundprüfungen), auch wenn die
  Hintergrundprüfungen ausgeschaltet sind, und protokolliert die Anzahl der
  gelöschten Dateien in `SelfXService.log`.
- Jeder Nutzer löscht die alten Dateien seines eigenen Ordners `Logs\Users\<SID>`,
  höchstens einmal am Tag, wenn ein SelfX-Skript startet. Der Dienst löscht nie in
  `Logs\Users`: Nutzer können dort Ordner anlegen, und ein Löschen als SYSTEM darf
  keinem Link folgen, den ein Nutzer anlegen könnte.

`Uninstall.ps1` behält die Protokolle; `-RemoveLogs` löscht `%ProgramData%\SelfX`.

### Gesundheitsstatus (SelfX Service 2.3.0)

Die Seite Gerätestatus (seit 2.5.0; zuvor im Reiter Systeminformationen) zeigt das
Ergebnis der lokalen Gesundheitsprüfungen des Dienstes. Sie liest den Status-Cache
der Hintergrundprüfungen, wenn SelfX geöffnet wird, und fordert `HEALTH` an, wenn der
Nutzer erneut prüft. Sie zeigt **In Ordnung** (grün), **Ausstehend** (gelbe Warnung),
**Fehler** (rot) oder **Unbekannt** (grau). Ausstehend bedeutet eine offene Aktion
(zu installierende Updates, Gerät noch nicht konform); das ist eine Warnung, kein
Fehler. Unbekannt bedeutet fehlende Daten, eine nicht unterstützte Quelle oder einen
nicht verfügbaren Dienst; es ist keine erfolgreiche Prüfung. Technische Details
bleiben englisch; Beschriftungen und Statuswörter folgen der Sprache der Oberfläche.
Kopieren und alle Exporte enthalten die Ergebnisse. Die vorhandenen Abschnitte Gerät,
Windows, Nutzer/Verwaltung, Netzwerk und Bericht bleiben zuerst; der Gesundheitsstatus
wird darunter in derselben Liste angehängt. Der Bericht ist eine Momentaufnahme, keine
laufende Überwachung.

Konfigurieren Sie `Sources\Health_Config.xml` vor dem Paketieren. Der Installer
kopiert sie neben `HealthStatus.ps1`, mit Schreibzugriff nur für Administratoren/SYSTEM.
Der Client kann dem Dienst weder einen Pfad noch Code übergeben.

| Prüfung | Auslegung |
|---|---|
| IME | `IntuneManagementExtension` muss laufen; fehlend oder gestoppt ist Fehler. |
| Defender | Dienst, Virenschutz und Echtzeitschutz müssen aktiviert sein; die Signaturen dürfen nicht als veraltet gemeldet werden und höchstens 7 Tage alt sein. Passiver Modus/Virenschutz von Drittanbietern kann deshalb Fehler ergeben. Eine fehlgeschlagene Abfrage ist Unbekannt. Das Detail beginnt mit der Signaturversion und der Zeit des letzten Signatur-Updates, gefolgt von Produkt- und Engine-Version. Standardmäßig bietet die Zeile **Beheben**, das `Update-MpSignature` ausführt (siehe [Reparaturen der Gesundheitsprüfung](#reparaturen-der-gesundheitsprüfung)). |
| Compliance | Intune bewertet die Compliance in der Cloud; Windows speichert keinen lokalen Compliance-Status, SelfX kann den Status des Unternehmensportals also nicht lesen. Seit 2.5.5 enthält das Paket `HealthChecks\Check-Compliance.ps1`, aktiviert mit `<Compliance Script="Check-Compliance.ps1" />`: Es prüft die lokalen Kriterien einer typischen Intune-Windows-Compliance-Richtlinie (Intune-Registrierung, BitLocker auf dem Systemlaufwerk, Secure Boot, TPM, Firewall für alle Profile, Defender-Virenschutz/Spyware-Schutz/Echtzeitschutz, aktuelle Signaturen, optional eine Mindestversion von Windows) und zeigt die nicht erfüllten Kriterien. Gleichen Sie `$Require` im Skript mit Ihrer Compliance-Richtlinie ab; das Unternehmensportal bleibt maßgeblich. Exit `0` = In Ordnung, jeder andere Exitcode = **Ausstehend** (Warnung). Ein fehlendes Skript, eine Ausnahme oder ein Timeout ist Fehler. Ohne das Element `Compliance` ist die Zeile Unbekannt. Solange die Zeile nicht in Ordnung ist, bietet sie **Beheben** an, um die Defender-Signaturen zu aktualisieren, die häufigste Ursache nach längerer Abwesenheit. |
| Anwendungen | Bestmöglicher **lokaler IME-Win32-App-Berichts-Cache**, plus konfigurierte Anwendungsprüfungen. Ein bekannter zwischengespeicherter Erfolg (`1000`) ist In Ordnung; Fehlerzustände (`5000` bis `5999`) sind Fehler; andere Zustände sind Unbekannt. Fehler hat Vorrang vor Unbekannt, das Vorrang vor In Ordnung hat. Ohne einbezogene Ergebnisse ist das Gesamtergebnis Unbekannt. |
| Datenträger | Jedes feste logische Laufwerk: Fehler, wenn der belegte Speicher **mindestens 90 % ODER der freie Speicher unter 20 GiB** beträgt (als GB angezeigt, PowerShell `1GB`). Genau 20 GiB genügen nur, wenn die Belegung unter 90 % liegt. Die Schwellenwerte sind konfigurierbar. |
| BitLocker | Jedes zurückgegebene OS-/feste Datenvolume muss vollständig verschlüsselt und der Schutz aktiviert sein; ausgesetzte, unverschlüsselte oder teilweise verschlüsselte Volumes sind Fehler. Nicht unterstützte/nicht lesbare Daten sind Unbekannt. Es werden keine Schlüssel oder Wiederherstellungsgeheimnisse erfasst. |
| Neustart ausstehend | Fehler, wenn Windows einen ausstehenden Neustart meldet: der Schlüssel `RebootPending` des Component Based Servicing, der Schlüssel `RebootRequired` von Windows Update, `RebootRequired` des Windows Update Agents (`Microsoft.Update.SystemInfo`), Updates des Windows-Update-Orchestrators, die auf den Neustart warten (`ReadyToReboot`, Windows 11 24H2+, was die Einstellungen als *Jetzt neu starten* zeigen; seit 2.6.9 nennt das Detail die Updates) oder eine ausstehende Umbenennung des Computers. `PendingFileRenameOperations` wird absichtlich ignoriert, weil Installer und Sicherheitsprodukte es oft dauerhaft gesetzt lassen. Nicht lesbare Registry-Daten sind Unbekannt; eine fehlschlagende Windows-Update-API verbirgt das Registry-Ergebnis nicht. |
| Zu installierende Updates | Durchsucht nur den **lokalen Cache des Windows Update Agents** (offline, kein Scan, Download oder Installation). Jedes nicht installierte, nicht ausgeblendete Update (außer reinen Browse-Updates/optionalen) ist **Ausstehend** (Warnung) und im Detail aufgelistet. Ein leerer Cache ist nur in Ordnung, wenn der letzte erfolgreiche Windows-Update-Scan höchstens `MaxSearchAgeDays` alt ist (Standard 14); sonst, oder wenn das Scan-Datum unbekannt ist, ist das Ergebnis Unbekannt. Updates, die nur über ConfigMgr verteilt werden, sind nicht Teil dieser Cache-Ansicht. Solange die Zeile Ausstehend ist, installiert **Beheben** die ausstehenden Windows-Updates und startet die Updates der Microsoft-Store-Apps als SYSTEM, ohne Neustart (seit 2.5.6, siehe [Reparaturen der Gesundheitsprüfung](#reparaturen-der-gesundheitsprüfung)). |
| Zusätzliche Dienste | Genauer Dienstname und erwarteter Zustand (`Running` oder `Stopped`). |
| Skriptprüfungen | Exit `0` = In Ordnung; Exit `1` = Fehler. Andere Exitcodes, fehlende Dateien, Ausnahmen und Timeouts sind ebenfalls Fehler. |

**Einschränkungen bei Anwendungen:** Der IME-Registry-Cache ist ein
Implementierungsdetail, keine stabile Microsoft-API, kein Inventar installierter
Software und kein Live-Bericht von Intune. Er kann veraltet sein und mehrere
Nutzer-/Geräteeinträge für dieselbe App enthalten. Alle verfügbaren einbezogenen
Einträge werden berücksichtigt (ein fehlgeschlagener Eintrag wird nicht verworfen,
weil ein anderer Eintrag erfolgreich war). Änderungen des Cache-Formats oder nicht
lesbare Daten ergeben Unbekannt. Eine erfolgreiche Installation beweist nicht, dass
die Anwendung funktioniert. Verwenden Sie ausdrückliche Prüfungen für Apps ohne IME
oder Funktionsprüfungen; SelfX kann nicht jede installierte Anwendung automatisch
diagnostizieren.

```xml
<HealthConfig>
  <Disk UsedPercentError="90" MinimumFreeGB="20" />
  <Updates MaxSearchAgeDays="14" />
  <Applications>
    <Exclude Name="Test application*" />
    <Exclude Name="00000000-0000-0000-0000-000000000001" />
    <Application Id="00000000-0000-0000-0000-000000000002"
                 Name="Business client" />
    <Application Name="Business client"
                 Script="Check-BusinessClient.ps1" TimeoutSeconds="15" />
  </Applications>
  <Services>
    <Service Name="Spooler" Expected="Running" />
  </Services>
  <Compliance Script="Check-Compliance.ps1" TimeoutSeconds="30" />
  <CustomChecks>
    <Check Name="Local support data"
           Script="Check-SupportData.ps1" TimeoutSeconds="10" />
  </CustomChecks>
</HealthConfig>
```

Ausschlüsse vergleichen Namen **ohne Beachtung der Groß-/Kleinschreibung mit
PowerShell-Platzhaltern** (`*`, `?`, Klammerausdrücke); auch App-IDs können
ausgeschlossen werden. Namen aus dem IME-Cache werden verwendet, wenn sie verfügbar
sind; sonst übernimmt SelfX den Namen aus den App-Richtlinien in den IME-Protokollen
(`AppWorkload.log`, seit 2.6.0) und zeigt erst dann die App-ID. Geben Sie eine
Zuordnung `Application Id="..." Name="..."` an, wenn Sie namensbasierte Ausschlüsse
brauchen, aber kein Name gefunden wird. Ausgeschlossene Prüfungen werden nicht
ausgeführt. Der Ausschluss aller Apps erzeugt kein In-Ordnung-Ergebnis. Seit 2.6.0
heißt die Zeile **Unternehmens-Apps (Intune)**; ihr Detail nennt die Apps, die mit
ihrem Fehlercode fehlgeschlagen sind (zum Beispiel `Monitoring Agent (error
0x87D1041C)`), und Apps, die für das Gerät nicht gelten (EnforcementState
3000-3999, Voraussetzungen nicht erfüllt), werden nicht gezählt. Die App-ID wird aus
dem Schlüssel `Win32Apps\<Nutzer>\<App-ID>_<Revision>` gelesen; vor 2.6.0 konnte
statt der App die Nutzer-ID angezeigt werden.

Legen Sie `Sources\HealthChecks` an und legen Sie dort Erweiterungs-`.ps1`-Dateien
ab. Es werden nur einfache Dateinamen akzeptiert (keine Unterverzeichnisse,
absoluten Pfade oder `..`); Reparse Points in diesem Ordner oder am Skript werden
abgewiesen. Das Standardpaket enthält nur `Check-Compliance.ps1` (siehe die Zeile
Compliance oben). Beispiel für eine nur lesende Anwendungsprüfung:

```powershell
<#
.SYNOPSIS
    Check whether the installed business client executable is present.
.NOTES
    Version: 1.0.0
    History:
    1.0.0  2026-10-28  Your company  Initial presence check.
#>
$ErrorActionPreference = 'Stop'
try {
    if (Test-Path -LiteralPath 'C:\Program Files\BusinessClient\Client.exe' -PathType Leaf) {
        exit 0
    }
    exit 1
} catch { exit 1 }
```

**Sicherheit und Laufzeitvertrag:** Die Prüfungen laufen bei jeder Aktualisierung
nicht interaktiv als SYSTEM, ohne Bestätigungsabfrage. Sie müssen nur lesend und
idempotent sein und dürfen nie neu starten, abmelden, Einstellungen ändern, Eingaben
abfragen oder losgelöste Arbeit starten. Prüfen/signieren Sie sie vor der
Bereitstellung; beliebige vom Administrator gelieferte Skripte kann SelfX nicht als
nur lesend beweisen. In Skripten sollten keine Anmeldedaten stehen. Exitcodes legen
ihren Status fest; die letzte nicht leere stdout-Zeile (höchstens 400 Zeichen) wird
als Detailtext angezeigt, sonst `Exit code: N`. stderr wird geleert, aber nicht in
den Bericht aufgenommen. Der Timeout beträgt 1–30 Sekunden pro Skript, Standard 30;
höchstens 5 Skriptprüfungen insgesamt (Compliance, App-Prüfungen und eigene
zusammen) und 16 zusätzliche Dienste. Bei einem Timeout versucht SelfX, diesen
Prozessbaum zu beenden. Die gesamte Dienstanfrage ist auf 240 Sekunden und 20.000
Zeichen begrenzt; zu große Ergebnisse werden ausdrücklich abgewiesen, nicht als In
Ordnung angezeigt. Reparaturaktionen und von SelfX angeforderte Prüfungen teilen
eine Sperre: Eine gleichzeitige Anfrage liefert Busy; versuchen Sie es nach dem
Ende erneut. Eine Prüfung, die angefordert wird, während eine Hintergrundprüfung
läuft, wartet bis zu deren Ende.

Führen Sie vor dem Paketieren alle Tests des Pakets aus, siehe die
[Release-Checkliste](Installation.md#release-checkliste-selfx-service). Der Katalog
und die Gesundheitskonfiguration werden außerdem von `Test-Catalog.ps1` (2.6.10)
geprüft.

Die Tests ersetzen alle Systemprüfungen und Skriptausführungen durch Mocks. Sie
installieren keinen Dienst und führen keine echten eigenen Skripte aus;
`Test-ServicePipe.ps1` startet nur den Pipe-Listener des Dienstes unter einem
Test-Pipe-Namen. `Test-Scripts.ps1` (2.6.0) führt jedes Aktions- und
Reparaturskript in einer temporären Sandbox mit Mocks für die Befehle aus (es wird
kein Prozess geschlossen, nichts gestartet oder neu gestartet) und prüft Ergebnis
und Protokoll; nur die nur lesenden Skripte `Check-Compliance.ps1`, `Detection.ps1`
und `HealthStatus.ps1` laufen echt.

