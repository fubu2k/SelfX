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
| `SelfX_Device_SyncTime.ps1` | Die Uhr mit der konfigurierten Zeitquelle abgleichen (`w32tm /resync /force`, Konfiguration unverändert) |
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
| `Ticket_Enabled`, `Ticket_Mail`, `Ticket_Subject_Tag` | Ticket per E-Mail (Standard aus): Schaltfläche *Ticket erstellen* im Hilfe-Dialog. `Ticket_Mail` ist der Empfänger (leer = `Support_Mail`, genau eine Adresse, nur aus dieser Konfiguration), `Ticket_Subject_Tag` die Kennung am Betreffanfang für Filter (Buchstaben, Ziffern, `.`, `_`, `-`, bis 20 Zeichen, sonst `SelfX`) |
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
  zeigen In Ordnung, Bald erledigen (technisch „Pending“, Warnung), Fehler oder Unbekannt. **Beheben**
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

### Ticket per E-Mail (SelfX Service 2.8.5, Zuordnung 2.8.6)

Optional und standardmäßig aus (`Ticket_Enabled` = `False`). Wenn eingeschaltet und eine gültige Adresse gesetzt ist, zeigt der Hilfe-Dialog (?) die Zeile *Problem melden* mit der Schaltfläche *Ticket erstellen*.

**Ablauf (Nutzerkontext, keine erhöhten Rechte):**
1. Der Nutzer beschreibt das Problem (bis 3000 Zeichen).
2. SelfX fügt **immer** die Geräteinformationen hinzu: alle Zeilen aus *Systeminformationen* und *Gerätestatus*, dazu Gerätename, Windows-Build und SelfX-Version. Der Nutzer kann sie nicht abwählen, sieht sie aber in der geöffneten E-Mail.
3. Die E-Mail wird nur **angezeigt, nie automatisch gesendet**. Der Nutzer prüft sie und sendet selbst.

**Übergabe an das Mailprogramm:**
- Klassisches Outlook (COM): Empfänger, Betreff, vollständiger Text und die Datei `TicketInfo-<Gerät>-<Zeit>.txt` als Anhang.
- Neues Outlook und andere Mailprogramme (mailto): Empfänger, Betreff und Text; der Link ist in der Länge begrenzt, deshalb wird der Text bei Bedarf gekürzt (Beschreibung und Kernfelder zuerst, Geräteinformationen zuletzt). Die vollständige Datei wird im Explorer markiert und muss vom Nutzer angehängt werden (die Oberfläche sagt das).
- Die Datei liegt in `%LOCALAPPDATA%\SelfX\Reports` (nur der Nutzer); ältere `TicketInfo-*`-Dateien werden beim nächsten Ticket gelöscht.

**Aufbau der E-Mail (für Filter und Automatisierung):** Betreff `[<Ticket_Subject_Tag>][<Art>] <Gerät>` (Art in der Sprache des Nutzers, z. B. *Störung*); Text mit festen englischen Feldnamen (`Time (UTC)`, `Computer`, `Windows build`, `SelfX version`), danach `Description of the user:` und `Device information:`, beide als abgesetzter Block.

**Zuordnung zur IT-Einheit (`Ticket_Config.xml`):** Die Datei liegt im Installationsordner (nur Administratoren können sie ändern) und enthält **beliebig viele** IT-Einheiten und Regeln. Nichts ist im Code festgelegt.
- `<Unit Id="IT1" Mail="it1@example.com" Cc="" />`: Einheit mit Empfänger und optionaler Kopie (Id: Buchstaben, Ziffern, `.`, `_`, `-`, bis 40 Zeichen; je genau eine einfache Adresse).
- `<Rule Source="GroupTag|OU|Category" Match="..." Unit="IT1" />` oder `<Rule Source="..." Regex="..." />`: `Match` ist ein exakter Wert (Groß-/Kleinschreibung egal), `Regex` ein .NET-Ausdruck (bis 300 Zeichen, mit Zeitlimit von 200 ms). Mit `Regex` kann `Unit` entfallen, wenn der Ausdruck eine benannte Gruppe `(?'unit'...)` enthält; deren Text ist dann die Einheit, z. B. `^[A-Z]{2}-(?'unit'IT[0-9]+)-[A-Z]{3}$` für Group-Tags wie `DE-IT1-BER`. Regeln werden von oben nach unten geprüft, die **erste passende gewinnt**; ohne Treffer geht die E-Mail an `Ticket_Mail` (sonst `Support_Mail`) aus `Tool_Config.xml`.
- Werte des Geräts (nur lesen): `GroupTag` und `Category` aus `HKLM\SOFTWARE\SelfX\Support` (REG_SZ, nur Administratoren können schreiben, z. B. per Intune gesetzt; erlaubt sind Buchstaben, Ziffern, Leerzeichen, `.`, `_`, `-`, bis 64 Zeichen), `OU` aus dem Distinguished Name des Computerkontos (Hybrid-Geräte, `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine`). Ungültige Werte zählen als leer.
- **Adresse pro Gerät (Registry, Vorrang):** Stehen in `HKLM\SOFTWARE\SelfX\Support` die Werte `TicketMail` (und optional `TicketCc`), gehen Empfänger und Kopie genau dorthin; die Regeln in `Ticket_Config.xml` werden dann nicht benötigt. Jede Adresse muss genau eine einfache Adresse sein, sonst wird der Wert ignoriert (dann gelten die Regeln, danach die Standardadresse). Die Werte setzt Intune pro Entra-Gerätegruppe (Beispiel in der [Installationsanleitung](Installation.md)); wechselt ein Gerät die Gruppe, ändern sich die Werte mit dem Skript der neuen Gruppe, ohne neues Paket.
- **Datenschutz und Compliance:** Es sollten nur gemeinsame Funktionspostfächer verwendet werden, keine persönlichen Postfächer. `Ticket_Config.xml` liegt auf jedem Gerät und kann von jedem Nutzer gelesen werden: Adressen, die nicht jede Organisationseinheit sehen soll, gehören nicht in diese Datei, sondern in die Registrywerte pro Gerät (dort liegt nur die Adresse der eigenen Einheit).
- Ungültige Einträge (falsche Adresse, unbekannte Einheit, ungültiger Ausdruck, doppelte Id, mehr als 500 Einheiten oder 2000 Regeln) werden übersprungen und im SelfX-Protokoll als Warnung genannt; ist die Datei nicht lesbar, gilt die Standardadresse. Der Empfänger steht im Dialog („Die E-Mail geht an: …“), der Nutzer kann ihn nicht ändern.
- Gruppen-Tag, Einheit und Kategorie stehen als Felder im Ticket (`Group tag`, `Support unit`, `Device category`).
- Prüfung vor der Verteilung: `tools\Test-SelfXTicketRouting.ps1 -GroupTag ... -Category ... -OU ...` zeigt Fehler der Datei und das Ergebnis für die angegebenen Werte (sendet nichts, liest keine Registry).

**Sicherheit:** Empfänger und Kopie kommen nur aus `Tool_Config.xml` und `Ticket_Config.xml` (nur Administratoren schreibbar) und müssen je genau eine einfache Adresse sein; der Nutzer kann sie nicht ändern. Felder werden bereinigt (keine Zeilenumbrüche im Betreff, feste Längen, Gerätename muss ein gültiger Name sein). Freitext und Geräteinformationen stehen in Codeblöcken, damit ein Ticketsystem daraus keine Befehle (z. B. GitLab-Quick-Actions) ausführt; ob das in der eigenen GitLab-Version greift, vor dem Einschalten testen. Die Geräteinformationen enthalten Adressen (z. B. Proxy) und Gerätedaten und sind für die IT bestimmt: vor dem Einschalten Datenschutz/Personalrat klären. Das Protokoll nennt nur das Ergebnis (`Outlook`, `Manual`, `Error`) und die Zeilenzahl, nie den Text.

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
Nutzer erneut prüft. Sie zeigt **In Ordnung** (grün), **Bald erledigen** (technisch „Pending“, gelbe Warnung),
**Fehler** (rot) oder **Unbekannt** (grau). Bald erledigen bedeutet eine offene Aktion
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

### Reparaturen der Gesundheitsprüfung

Die Gesundheitsprüfungen bleiben nur lesend. Um eine vom Nutzer ausgelöste
Schaltfläche **Beheben** an einer Statuszeile anzubieten, legen Sie ein
Reparaturskript unter `Sources\Scripts_to_run` ab und tragen es in
`Health_Config.xml` ein:

```xml
<Remediations>
  <Remediation Id="IME" Script="SelfX_Intune_RestartService.ps1" />
  <Remediation Id="Service" Name="Spooler" Script="Repair-Spooler.ps1" />
  <Remediation Id="Disk" Name="C:" Script="Repair-Disk.ps1" />
  <Remediation Id="Custom" Name="Business check" Script="Repair-BusinessCheck.ps1" />
  <Remediation Id="Compliance" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
</Remediations>
```

`Id` entspricht einem Ergebnistyp (`IME`, `Defender`, `Compliance`, `Applications`,
`Disk`, `BitLocker`, `PendingReboot`, `Updates`, `Service`, `Custom`). Das optionale
`Name` entspricht dem genauen technischen Namen, nicht der übersetzten Beschriftung.
Ohne Name gilt die Zuordnung für jede Zeile dieses Typs. Konfigurieren Sie für eine
Zeile keine sich überschneidenden Zuordnungen: Mehrdeutige Zuordnungen werden als
Konfigurationsfehler gemeldet. Das optionale `When="NotOK"` bietet die Reparatur nur
an, solange die Zeile nicht in Ordnung ist (Ausstehend, Fehler oder Unbekannt); der
Standard `Always` bietet sie bei jedem Status an.

**Standardreparatur (2.3.4):** Das Paket enthält
`Scripts_to_run\SelfX_Defender_UpdateSignature.ps1`, das `Update-MpSignature` als
SYSTEM mit den durch die Defender-Richtlinie festgelegten Update-Quellen ausführt,
und aktiviert es in der mitgelieferten `Health_Config.xml`:

```xml
<Remediation Id="Defender" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
<Remediation Id="Compliance" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
```

Seit 2.5.4 zeigen die Zeilen Defender und Compliance **Beheben** nur, solange sie
nicht in Ordnung sind, weil veraltete Signaturen nach längerer Abwesenheit eine
häufige Ursache für fehlende Compliance sind. Um das Signatur-Update auch bei einer
Defender-Zeile in Ordnung anzubieten, entfernen Sie `When="NotOK"` aus der
Defender-Zeile. Das Update braucht eine erreichbare Update-Quelle; offline schlägt es
fehl (Exit 1) und der Status bleibt unverändert. Entfernen Sie die beiden Zeilen, um
es zu deaktivieren.

**Reparatur der Updates (2.5.6, korrigiert in 2.6.3 und 2.6.9):** Das Paket enthält
`Scripts_to_run\SelfX_Updates_Install.ps1` und aktiviert es in der mitgelieferten
`Health_Config.xml`:

```xml
<Remediation Id="Updates" Script="SelfX_Updates_Install.ps1" When="NotOK" TimeoutSeconds="7200" />
```

Solange Updates ausstehen, bietet die Zeile **Zu installierende Updates**
**Beheben** an. Während die Installation läuft, zeigt die Schaltfläche **Läuft…**,
und die Meldungsleiste sagt, dass die Updates gesucht, geladen und installiert
werden; danach meldet SelfX, dass Windows Update fertig ist, und prüft den gesamten
Gerätestatus erneut (Updates, Neustart ausstehend, Compliance). Das Skript läuft als
SYSTEM und

1. startet den Update-Scan für Microsoft-Store-Apps der MDM-Bridge
   (`MDM_EnterpriseModernAppManagement_AppManagement01.UpdateScanMethod`). Das
   funktioniert auch, wenn der Store für Nutzer gesperrt ist. Der Store aktualisiert
   die Apps asynchron im Hintergrund.
2. startet unter Windows 11 25H2 und neuer (Mindestversion, 2.6.10) **„Nach Updates suchen“ des
   Windows-Update-Orchestrators** über die dokumentierte WinRT-API
   `Windows.Management.Update.WindowsUpdateManager`
   (`StartScan(userInitiated: true)`, dasselbe wie die Schaltfläche in den
   Einstellungen). Windows lädt und installiert die Updates selbst, mit den
   Richtlinien des Geräts, und **Einstellungen > Windows Update zeigt den
   Fortschritt**. Das Skript wartet, bis kein Update mehr geladen oder installiert
   wird (höchstens 90 Minuten), und protokolliert jedes Update mit seiner Aktion, dem
   Fortschritt und dem Grund, warum es wartet, zum Beispiel
   `2026-11 Security Update (KB5132061): action Install, progress Install 70` oder
   `Optional driver: waiting: SeekerUpdate`. Updates, die nur noch auf den Neustart
   warten (`ReadyToReboot`), gelten als erledigt. Feature-Updates (neue
   Windows-Version) überlässt es der Update-Richtlinie.
   Jedes Update wird in `%ProgramData%\SelfX\Logs\SelfX_Updates_Install_<Datum>.log`
   protokolliert. Danach aktualisiert ein Hintergrundscan des Orchestrators die Seite in
   den Einstellungen. Arbeitet der Orchestrator nach 90 Minuten noch, endet die Reparatur
   mit Exit `1`; Windows arbeitet im Hintergrund weiter. Ist die Orchestrator-API nicht
   verfügbar (`WinRT\SelfXWinRT.dll` fehlt), endet die Reparatur mit Exit `1` und bittet,
   SelfX neu zu installieren; einen anderen Update-Weg gibt es nicht.

Die Versionen 2.6.0 bis 2.6.2 nutzten `UsoClient.exe StartDownload` /
`StartInstall`. Windows 11 24H2 weist diese Befehle ab (Exitcode `-2147024809` /
`0x80070057` im Protokoll), sodass nur ein Scan lief und nichts installiert wurde;
ein bereits ausstehender Neustart wurde sogar als installiert gemeldet. 2.6.3
verwendet `UsoClient.exe` nicht mehr. Die Versionen 2.6.3 bis 2.6.8 nutzten nur die
Windows-Update-Agent-API. Microsoft dokumentiert, dass die Seite Windows Update in
den Einstellungen nur Updates des Orchestrators zeigt und dass über die WUA-API
behandelte Updates dort nicht erscheinen und mit ihm kollidieren können, sodass die
Updates in den Einstellungen weiterhin als ausstehend angezeigt werden konnten. Seit 2.6.10 wird die Windows-Update-Agent-API nicht mehr zum Installieren genutzt. Vor
2.6.9 wurde ein Klick auf **Beheben** außerdem mit „Eine andere Aktion läuft noch“
abgewiesen, während SelfX den zwischengespeicherten Status las (einmal pro Minute,
für einen Moment).

Das Skript startet Windows **nie neu**. Braucht ein Update einen Neustart, zeigt ihn
die Zeile **Neustart ausstehend**. Exit `0` = alle ausgewählten Updates installiert
(oder nichts zu installieren); Exit `1` = Suche, Download oder Installation ist bei
mindestens einem Update fehlgeschlagen (die fehlgeschlagenen KB-Nummern stehen im
Protokoll). Ein Store-Scan, der sich nicht starten lässt (zum Beispiel ohne
MDM-Bridge), wird protokolliert, lässt die Reparatur aber nicht fehlschlagen.
Entfernen Sie die Zeile, um sie zu deaktivieren.

**Reparatur Neustart (2.6.0):** Die Zeile **Neustart ausstehend** bietet **Jetzt neu
starten** an:

```xml
<Remediation Id="PendingReboot" Script="SelfX_Device_Restart.ps1" When="NotOK" />
```

SelfX erkennt dieses Skript und fragt mit einer eigenen Warnung: Windows startet neu,
um die ausstehenden Updates und Änderungen abzuschließen, der Nutzer soll seine
Arbeit speichern und alle Programme schließen, der Neustart beginnt etwa 30 Sekunden
nach der Bestätigung (**Jetzt neu starten** / **Abbrechen**). Nach der Bestätigung
führt der Dienst `shutdown.exe /r /t 30 /d p:4:1` als SYSTEM aus; Windows zeigt seine
Neustart-Benachrichtigung. Der Neustart ist **nie** Teil von **Alle Probleme
beheben**. Entfernen Sie die Zeile, um die Schaltfläche auszublenden.

**Reparatur App-Wiederholung (2.6.0):** Die Zeile **Unternehmens-Apps (Intune)**
bietet **Erneut versuchen** an, solange eine App-Installation fehlgeschlagen ist:

```xml
<Remediation Id="Applications" Script="SelfX_Apps_RetryInstall.ps1" When="NotOK" TimeoutSeconds="300" />
```

Die Intune Management Extension wiederholt eine fehlgeschlagene Win32-App erst nach
ihrem Wiederholungsplan (standardmäßig 24 Stunden). `SelfX_Apps_RetryInstall.ps1`
entfernt für jede App, deren letztes Ergebnis im lokalen IME-Cache ein Fehler ist,
dieses zwischengespeicherte Ergebnis und die Einträge des Wiederholungsplans (GRS)
der App und startet den Dienst IntuneManagementExtension neu. Die IME meldet sich
dann bei Intune und installiert die App innerhalb weniger Minuten erneut; der Nutzer
sieht den Fortschritt im Unternehmensportal. Es wird keine App deinstalliert, und
geändert wird nur der IME-Cache unter
`HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps`. Schlägt die
Installation erneut fehl, liegt das Problem in der App oder ihrer Zuweisung; der
Nutzer kann die Geräteprotokolle an den Support senden, und das Support-Team sieht
den Fehlercode in Intune.

Das optionale `TimeoutSeconds` an einer `Remediation` (seit 2.5.6) legt das
Laufzeitlimit des Dienstes für diese Reparatur fest: eine positive Zahl, auf 7200
Sekunden begrenzt; der Standard sind 900 Sekunden.

Das optionale `OtherSessions="Block"` an einer `Remediation` wirkt wie das
Katalogelement `OtherSessions`: Ein normaler Nutzer kann die Reparatur nicht
starten, solange ein anderer Nutzer eine aktive Sitzung hat. Die mitgelieferte
Konfiguration setzt es für `Updates` und für den Neustart (`PendingReboot`). Ein
Skript, das zugleich eine `System`-Aktion im Katalog ist, verwendet zuerst den
Katalogeintrag; setzen Sie `Block` auch dort.

Die Schaltfläche **Beheben** erscheint nur auf Karten mit einer konfigurierten
Reparatur (auch auf Karten In Ordnung und Unbekannt, sofern nicht `When="NotOK"`
gilt). Der Neustart und die App-Wiederholung nutzen **Jetzt neu starten** und
**Erneut versuchen**. Die Texte der Schaltflächen und Bestätigungen sind in allen 24
Sprachen der Oberfläche enthalten. Jede Karte hat außerdem eine Schaltfläche
**Erneut prüfen** (Pfeile), die nur diesen Status ohne Bestätigung und ohne
Ausführung einer Reparatur erneut prüft (siehe [Einzelprüfung](#einzelprüfung)). Vor
2.5.0 zeigten Zeilen ohne Reparatur eine Schaltfläche mit der Beschriftung In
Ordnung, Ausstehend oder Fehler. Der Nutzer muss vor der Ausführung bestätigen. Der
lokale Dienst prüft das Skript gegen die geschützte Positivliste der Reparaturen
(oder den vorhandenen Katalog der System-Aktionen) und führt es dann als SYSTEM mit
dem vorhandenen Zeitlimit und der Protokollierung aus. Es werden keine beliebigen
Pfade, Befehlsargumente oder vom Nutzer gelieferten Skripte akzeptiert.
Reparaturskripte brauchen keinen zusätzlichen Eintrag im Fehlerbehebungskatalog.
Jeder lokale angemeldete Nutzer kann diese freigegebenen Reparaturen anfordern,
genau wie die vorhandenen System-Aktionen.

Das Fenster verhindert eine zweite Reparatur, solange eine läuft. Nach dem Ende,
auch bei Fehler oder Timeout, prüft es nur den reparierten Status erneut (Zeilen der
Erfassung selbst fallen auf eine vollständige Aktualisierung zurück). Das Ergebnis
der Aktion bleibt in der Meldungsleiste; der angezeigte Gesundheitsstatus wird vom
frischen Prüfergebnis bestimmt, nicht vom Exitcode des Skripts. Eine Reparatur, die
0 zurückgibt, kann daher einen roten Status hinterlassen. Ist die Prüfung oder der
Dienst nicht verfügbar, ist das aktualisierte Ergebnis Unbekannt statt eines
erfundenen In-Ordnung.

### Einzelprüfung

Seit 2.3.2 kann der Client eine einzelne Prüfung mit
`HEALTH <Id> [<Base64-UTF-8-Name>]` anfordern, zum Beispiel `HEALTH Disk Qzo=` für
das Laufwerk `C:`. Der Dienst akzeptiert nur die bekannten Ids (`IME`, `Defender`,
`Compliance`, `Applications`, `Disk`, `BitLocker`, `PendingReboot`, `Updates`,
`Service`, `Custom`) und einen streng Base64-codierten Namen; alles andere wird
abgewiesen. `HealthStatus.ps1` führt dann nur diese Prüfung aus der geschützten
`Health_Config.xml` aus: Ein Name, der dort nicht konfiguriert ist, wird nie
geprüft und ergibt eine Zeile Unbekannt. Die Oberfläche ersetzt nur die betroffene
Karte, und der Dienst aktualisiert nur diese Zeilen im Status-Cache; alle anderen
Informationen bleiben erhalten. Zeilen vom Typ `Collection` (Fehler des Collectors)
lösen stattdessen eine vollständige Aktualisierung aus.

Reparaturen müssen ohne Nutzerinteraktion ausführbar sein. Verwenden Sie in diesen
Skripten nie Abmelden, Neustart, Herunterfahren, Energiesparmodus oder losgelöste
Aktionen. Das gilt auch für `PendingReboot`: Die erneute Prüfung zeigt nur, ob noch
ein Neustart aussteht; den Neustart führt der Nutzer selbst aus. Administratoren
müssen sie prüfen, bereitstellen und, wo nötig, signieren. Seit 2.3.4 ist standardmäßig
nur das Defender-Signatur-Update aktiviert (Defender immer, Compliance wenn nicht in
Ordnung).

### Branding

Firmenlogo, Symbol und Farben werden im Abschnitt `Branding` von `Tool_Config.xml`
festgelegt. Kopieren Sie die Bilddateien vor dem Bau des Pakets nach
`SelfX Service\Sources` oder in einen Unterordner wie `Sources\Branding`. Pfade sind
relativ zum Installationsordner. Alle Schlüssel sind optional; ist ein Wert leer oder
ungültig oder fehlt die Datei, verwendet SelfX den Standard.

Die mitgelieferte `Tool_Config.xml` enthält Platzhalter (2.6.8): das Logo
`Branding\company_logo.png` („YOUR LOGO“), das Blau des SelfX-Logos (`#0072BC`) und
die Support-Kontakte `Mon-Fri 08:00-17:00`, `+1 555 0100`, `support@example.com` und
`https://support.example.com`. Ersetzen Sie sie vor dem Bau des Pakets durch die
Werte Ihres Unternehmens oder leeren Sie sie, um sie auszublenden.

| Schlüssel | Standard | Zweck |
|---|---|---|
| `Brand_Logo` | leer (kein Logo) | Firmenlogo oben in der Navigationsleiste und im Info-Dialog. PNG, JPG, BMP, GIF oder ICO, in der Navigation höchstens 196 Pixel breit. Ein transparentes PNG passt am besten zu beiden Designs. Ist es leer, zeigt der Info-Dialog `About_Logo`. |
| `Brand_Logo_Height` | `40` | Höhe des Logos in der Navigationsleiste in Pixeln (16–120). Die Breite wird passend skaliert. |
| `Brand_Icon` | `Repair.ico` | Symbol des Fensters, der Taskleiste und des Statussymbols. Ist es eine `.ico`-Datei, verwendet `Install.ps1` es auch für die Verknüpfungen und den Eintrag unter Apps & Features. Seit 2.6.2 hat SelfX eine eigene Taskleistenschaltfläche (AppUserModelID `SelfX.SelfService`) mit diesem Symbol statt des PowerShell-Symbols; ein an die Taskleiste angeheftetes SelfX startet `SelfX.exe`. Verwenden Sie eine `.ico` mit 256 × 256 Pixeln für ein scharfes Taskleistensymbol. |
| `Brand_Accent_Color` | leer (nutzt `Tool_Color`) | Firmenfarbe als `#RRGGBB` für Schaltflächen, Auswahlen, die Markierung der Navigation, Links und Symbole. Die Textfarbe auf der Akzentfarbe (weiß oder schwarz) wird automatisch gewählt; eine sehr dunkle oder sehr helle Farbe wird für Text und Symbole aufgehellt oder abgedunkelt, damit sie auf beiden Designs lesbar bleibt. |
| `Brand_TitleBar_Color` | Fensterhintergrund | Hintergrund der Titelleiste als `#RRGGBB`, zum Beispiel die Unternehmensfarbe. Die Textfarbe wird automatisch gewählt. |
| `Brand_Run_Button_Color` | Akzentfarbe | Start-Schaltflächen (Play) und **Beheben**. |
| `Brand_Info_Button_Color` | Akzentfarbe | Symbole „Mehr Informationen“. |

Beispiel:

```xml
<Brand_Logo>Branding\contoso.png</Brand_Logo>
<Brand_Logo_Height>48</Brand_Logo_Height>
<Brand_Icon>Branding\contoso.ico</Brand_Icon>
<Brand_Accent_Color>#E20074</Brand_Accent_Color>
<Brand_TitleBar_Color>#3A0021</Brand_TitleBar_Color>
<Brand_Run_Button_Color>#E20074</Brand_Run_Button_Color>
<Brand_Info_Button_Color>#6C6C6C</Brand_Info_Button_Color>
```

`Tool_Theme` (`Auto`, `Dark` oder `Light`) wählt das Standarddesign; seit 2.6.7 ist
der Standard `Auto` (auch wenn der Wert fehlt oder unbekannt ist). Jeder Nutzer kann
es im Einstellungsdialog ändern (wenn `Show_Theme_Button` `True` ist):
*Automatisch*, *Dunkel* oder *Hell*. *Automatisch* (`Auto`, 2.6.6) nutzt den
App-Modus von Windows (Einstellungen > Personalisierung > Farben,
`AppsUseLightTheme` in `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`;
hell, wenn der Wert fehlt) und folgt einer Änderung, während SelfX geöffnet ist. Die
Wahl des Nutzers wird in `HKCU\Software\SelfX\Theme` gespeichert und hat Vorrang vor
`Tool_Theme`; Nutzer, die zuvor *Dunkel* oder *Hell* gewählt haben, behalten ihre
Wahl. Die Branding-Farben gelten für beide Designs. `Tool_Color` akzeptiert die
früheren MahApps-Farbnamen (`Cyan`, `Teal`, `Blue` ...). Seit 2.5.0 verwendet
SelfX Service MahApps.Metro nicht mehr; für die Farben wird keine Datei geschrieben
und kein Netzwerkzugriff genutzt.

### Sprachen

Die Basissprache der Oberfläche ist Deutsch (2.6.12). Mit `Tool_Language` auf `Auto`
folgt sie der Anzeigesprache von Windows des angemeldeten Nutzers. Nutzer können in
SelfX > Einstellungen (Zahnrad) selbst eine andere Sprache wählen. Die Texte stehen
in `Sources\Languages\<Kultur>.xml`. Enthaltene Sprachen:

| Datei | Sprache | Datei | Sprache | Datei | Sprache |
|---|---|---|---|---|---|
| `en.xml` | Englisch (Referenz) | `pl.xml` | Polnisch | `hi.xml` | Hindi |
| `de.xml` | Deutsch (Basissprache) | `ru.xml` | Russisch | `bn.xml` | Bengalisch |
| `fr.xml` | Französisch | `uk.xml` | Ukrainisch | `zh-Hans.xml` | Chinesisch (vereinfacht) |
| `es.xml` | Spanisch | `tr.xml` | Türkisch | `zh-Hant.xml` | Chinesisch (traditionell) |
| `it.xml` | Italienisch | `ar.xml` | Arabisch (rechts nach links) | `ja.xml` | Japanisch |
| `pt.xml` | Portugiesisch | `fa.xml` | Persisch (rechts nach links) | `ko.xml` | Koreanisch |
| `nl.xml` | Niederländisch | `ur.xml` | Urdu (rechts nach links) | `vi.xml` | Vietnamesisch |
| `id.xml` | Indonesisch | `th.xml` | Thailändisch | `sw.xml` | Suaheli |

Englisch ist die Referenz für die Schlüssel und der Rückfall; die anderen Dateien
wurden maschinell übersetzt. Lassen Sie sie vor einem Rollout von Muttersprachlern
prüfen.

So wird die Sprache gewählt (`Localization.ps1`):

1. Die vom Nutzer gewählte Sprache (2.5.9). Der Einstellungsdialog listet
   **Automatisch (<Sprache>)** und jede Sprachdatei unter ihrem eigenen Namen, zum
   Beispiel *Deutsch*, *français*, *日本語*. Die Wahl wird pro Nutzer in
   `HKCU\Software\SelfX\Language` gespeichert. *Automatisch* speichert `Auto`, das
   „Schritt 2 verwenden“ bedeutet. Nach einer Änderung startet SelfX auf derselben
   Seite in der neuen Sprache neu, und das Statussymbol folgt. Läuft noch eine
   Reparatur, wird die neue Sprache beim nächsten Öffnen von SelfX verwendet. Die
   Wahl wird ignoriert, wenn `Show_Language_Setting` `False` ist, wenn der Wert kein
   Kulturname ist oder wenn seine Sprachdatei nicht mehr existiert.
2. `Tool_Language` in `Tool_Config.xml`: `de` (Standard) ist Deutsch, `Auto` nutzt
   die Anzeigesprache von Windows, jeder andere Wert wird als Kulturname verwendet.
3. Die Kultur und ihre übergeordneten Kulturen werden der Reihe nach versucht. Zum
   Beispiel nutzt `de-CH` die `de.xml`, `pt-BR` die `pt.xml`, `zh-CN` die
   `zh-Hans.xml` und `zh-TW` die `zh-Hant.xml`. Schweizerdeutsch (`gsw`, auch
   `gsw-CH`) nutzt ebenfalls `de.xml`, wenn keine Sprachdatei für Schweizerdeutsch
   vorhanden ist.
4. Passt keine Datei, wird `de.xml` (die Basissprache) verwendet. Ein Text, der in
   der gewählten Sprache fehlt, erscheint auf Englisch (`en.xml`).

Jeder Text wird zuerst in der gewählten Sprache und dann auf Englisch gesucht,
sodass ein fehlender Eintrag nie eine leere Beschriftung hinterlässt. Katalogtexte
fallen auf den englischen Basistext in `Issues_List.xml` zurück.

Eine Sprachdatei hat vier Teile:

| Abschnitt | Inhalt |
|---|---|
| `UI` | Texte des Hauptfensters, der Dialoge, Kurzinfos, der Meldungsleiste, der Seiten Gerätestatus und Systeminformationen und des Statussymbols. `{0}`, `{1}` sind Platzhalter, zum Beispiel für den Aktionsnamen. |
| `SystemInfo` | Beschriftungen und Werte der Seite Systeminformationen und der Statusprüfungen |
| `Catalog/Categories` | Anzeigenamen der Kategorie-Ids |
| `Catalog/Messages`, `Catalog/Actions` | Übersetzungen der gemeinsamen Meldungen und von `Name`, `Explanation` und `Alerte_MSG` pro Aktions-`Id`. Felder mit `Ref` übernehmen die übersetzte Meldung. |

Um eine Sprache hinzuzufügen:

1. Kopieren Sie `en.xml` (oder eine vollständige Übersetzung wie `de.xml`) nach
   `<Kultur>.xml`. Verwenden Sie den neutralen Kulturnamen, zum Beispiel `cs.xml`
   für Tschechisch, damit alle regionalen Varianten sie nutzen.
2. Setzen Sie `Culture`, `Name` und `NativeName` am Wurzelelement. Setzen Sie
   `FlowDirection="RightToLeft"` für Schriften von rechts nach links.
3. Übersetzen Sie die Texte. Behalten Sie Elementnamen, Ids und Platzhalter bei.
   Behalten Sie das Muster `|*.txt|` in `SystemInfo_Export_Filter` bei.
4. Prüfen Sie die Datei und bauen Sie dann das Paket:

   ```powershell
   & '.\SelfX Service\Test-LanguageFiles.ps1' -Culture cs
   ```

   Die Prüfung meldet fehlende oder unbekannte Schlüssel, defekte Platzhalter und
   Katalogeinträge, die nicht existieren. Ohne `-Culture` prüft sie alle Dateien.

Es ist keine Codeänderung nötig. Um einen Text für Ihr Unternehmen zu ändern, zum
Beispiel den Haupttitel, bearbeiten Sie ihn in den Sprachdateien.

## Änderungen sicher bearbeiten und veröffentlichen

1. Sichern Sie die aktuellen XML-Dateien und Skripte.
2. Prüfen Sie, dass das XML wohlgeformt bleibt.
3. Prüfen Sie, dass jedes referenzierte Skript im entsprechenden Paket existiert.
4. Testen Sie das Verhalten der Aktionen und die Bestätigungstexte auf einem
   Testgerät.
5. Liefern Sie Änderungen nur als neue Paketversion aus (Intune-Paket, siehe
   [Installation](Installation.md#intune-paket-erstellen)). SelfX lädt keine
   Konfiguration aus dem Netzwerk nach.
