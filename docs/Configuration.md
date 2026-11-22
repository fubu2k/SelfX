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

