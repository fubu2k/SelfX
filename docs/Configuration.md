# Konfiguration

[English](en/Configuration.md) | **Deutsch**

SelfX Service wird mit XML-Dateien im Ordner `SelfX Service\Sources` eingestellt.
Sie ändern die Dateien **im Paket, vor der Installation**. Nach der Installation
liegen sie in `%ProgramFiles%\SelfX` und nur Administratoren können sie ändern.
Neue Einstellungen kommen immer mit einer neuen Paketversion. SelfX lädt nichts aus
dem Netzwerk nach.

| Datei | Wofür |
|---|---|
| `Tool_Config.xml` | Allgemeine Einstellungen, Kontakte, Branding |
| `Issues_List.xml` | Aktionskatalog (Fehlerbehebung) |
| `Health_Config.xml` | Gerätestatus: Prüfungen, Reparaturen, Hintergrundprüfung |
| `Network_Test_Config.xml` | Netzwerk-Messungen (optional) |
| `Ticket_Config.xml` | Zuordnung von Tickets zu IT-Einheiten (optional) |
| `Languages\<Kultur>.xml` | Alle Texte, pro Sprache |

## SelfX Service

### Aktionskatalog

In `Issues_List.xml` steht jede Aktion, die SelfX anbietet. Eine Aktion hat einen
englischen Basistext. Die Übersetzungen stehen in den Sprachdateien und werden über
die `Id` der Aktion zugeordnet.

Wichtige Elemente einer Aktion:

| Element | Bedeutung |
|---|---|
| `Id` (Attribut) | Eindeutiger Name, zum Beispiel `D_Teams_SoundCuts`. Die Sprachdateien verwenden ihn. |
| `Name`, `Explanation`, `Alerte_MSG` | Titel, Erklärung und Bestätigungstext (englischer Basistext). |
| `Category` | Kategorie-Id: `Browser`, `Device`, `Intune`, `Office`, `OneDrive`, `Outlook`, `Teams`. Der Anzeigename kommt aus der Sprachdatei. |
| `Script` | Name des Skripts in `Scripts_to_run`. |
| `Context` | `User`: Das Skript läuft als angemeldeter Nutzer. `System`: Der Dienst führt das Skript als SYSTEM aus. Fehlt das Element, gilt `User`. |
| `TimeoutSeconds` | Nur für `System`. 1 bis 7200 Sekunden, Standard 900. Danach stoppt der Dienst das Skript. |
| `OtherSessions` | Nur für `System`. `Block`: Ein normaler Nutzer kann die Aktion nicht starten, solange ein anderer Nutzer aktiv angemeldet ist. Administratoren mit erhöhten Rechten sind nicht betroffen. Kann SelfX die Sitzungen nicht lesen, wird die Aktion blockiert. Setzen Sie `Block` an jeden Eintrag desselben Skripts. Im mitgelieferten Katalog gilt es für den Neustart des Intune-Dienstes, den Neustart der Netzwerkadapter und CHKDSK. |
| `Post_Action` | Nur für `System`. `MailReport`: Nach einem erfolgreichen Lauf öffnet SelfX eine E-Mail an den Support mit dem Bericht im Anhang (siehe [Geräteprotokolle](#geräteprotokolle-für-den-support)). |

`Explanation` und `Alerte_MSG` können auf einen gemeinsamen Text verweisen, zum
Beispiel `<Alerte_MSG Ref="Msg_Teams_Restart"/>`. Die gemeinsamen Texte stehen im
Abschnitt `Messages` der Datei.

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

**Regeln für `System`-Aktionen (Sicherheit):**

- `Script` ist nur ein Dateiname aus Buchstaben, Ziffern, `_`, `-` und `.`, endet auf
  `.ps1` und liegt in `Scripts_to_run`. Der Dienst weist alles andere ab. Nutzer
  können dem Dienst weder Pfade noch Argumente noch Code übergeben.
- Jeder angemeldete Nutzer kann jede `System`-Aktion starten. Nehmen Sie deshalb nur
  Aktionen auf, die für jeden Nutzer sicher sind.
- Das Skript läuft ohne Nutzerprofil, ohne Desktop und ohne Eingabeaufforderung.
  Es gibt einen Exitcode zurück (`0` = Erfolg). Ausgaben nach stdout und stderr
  werden protokolliert.
- Der Dienst übergibt die SID des anfragenden Nutzers in der Umgebungsvariablen
  `SELFX_CALLER_SID`. Verwenden Sie sie nur, um ein Ergebnis an diesen Nutzer zu
  übergeben, nie um zu entscheiden, ob eine Aktion erlaubt ist.
- Dasselbe Skript darf in mehreren Aktionen vorkommen. Der erste `System`-Eintrag
  legt die `TimeoutSeconds` fest.

**Neue Aktion hinzufügen:** Geben Sie ihr eine neue `Id` und ergänzen Sie die
Übersetzungen in den Sprachdateien. Ohne Übersetzung erscheint der englische Text.

Mitgelieferte `System`-Aktionen:

| Skript | Zweck |
|---|---|
| `SelfX_Intune_RestartService.ps1` | Dienst der Intune Management Extension neu starten |
| `SelfX_Device_AirePlaneMode.ps1` | Alle aktiven Netzwerkadapter neu starten |
| `SelfX_Device_SyncTime.ps1` | Uhr mit der konfigurierten Zeitquelle abgleichen (`w32tm /resync /force`, die Zeit-Konfiguration bleibt unverändert) |
| `SelfX_OneDrive_CHKDSK.ps1` | `chkdsk /r /f` für das Systemlaufwerk beim nächsten Neustart planen |
| `SelfX_Device_CollectLogs.ps1` | Geräteprotokolle sammeln und eine E-Mail mit dem Bericht öffnen |

### Einstellungen in Tool_Config.xml

Die Datei enthält nur Einstellungen, keine Texte. Alle Texte stehen in den
Sprachdateien (siehe [Sprachen](#sprachen)).

| Schlüssel | Bedeutung |
|---|---|
| `Tool_Version` | Erhöhen Sie sie bei jedem Release und setzen Sie denselben Wert in `Detection.ps1`. |
| `Tool_Language` | Standardsprache. `de` (Standard), `Auto` (Anzeigesprache von Windows) oder ein Kulturname wie `en`, `fr-CH`, `zh-Hans`. |
| `Show_Language_Setting` | `True` (Standard): Nutzer können die Sprache selbst wählen. `False`: Es gilt immer `Tool_Language`. |
| `Tool_Name` | Text in der Titelleiste und im Info-Dialog. |
| `Shortcut_Desktop`, `Shortcut_StartMenu`, `Shortcut_Name` | Verknüpfungen, die `Install.ps1` für alle Nutzer anlegt. |
| `Show_Computer_Name_MainGUI`, `Show_Computer_Name_title_bar` | Computername im Fenster anzeigen. |
| `Default_Solution_Mode` | `Simplified` oder `Detailed`. |
| `Show_Reboot_Warning`, `Show_About_Button` | Neustart-Erinnerung und Info-Schaltfläche (i). |
| `Show_Theme_Button` | `True`: Nutzer können das Design wählen (Automatisch, Dunkel, Hell). |
| `Show_Status_Page` | `True` (Standard): Seite *Gerätestatus* anzeigen. |
| `Show_SystemInfo_Tab`, `Show_SystemInfo_Intune_Actions`, `SystemInfo_Internet_Test_Host`, `SystemInfo_Internet_Test_Port` | Seite *Systeminformationen* und ihre Werkzeuge. |
| `Show_Support_Button`, `Support_Hours`, `Support_Phone_number`, `Support_Mail`, `Support_Teams`, `Support_Website` | Hilfe-Schaltfläche (?) und ihre Kontakte (siehe [Benutzeroberfläche](#benutzeroberfläche)). `Support_Mail` ist auch der Empfänger der E-Mail mit den Geräteprotokollen. |
| `DeviceLogs_Days`, `DeviceLogs_Compress` | Geräteprotokolle: Tage des Ereignisprotokolls (1 bis 60, Standard 7) und `.zip` (Standard) oder `.txt`. |
| `Ticket_Enabled`, `Ticket_Mail`, `Ticket_Subject_Tag` | Ticket per E-Mail (siehe [Ticket](#ticket-per-e-mail)). |
| `Copilot_Enabled`, `Copilot_Url`, `Copilot_Audience`, `Copilot_Include_AppNames` | Übergabe an Copilot Chat (siehe [Copilot Chat](#copilot-chat)). |
| `Log_Retention_Days` | Aufbewahrung der Protokolle (siehe [Protokolle](#protokolle-und-aufbewahrung)). |
| `Show_Tray_Icon`, `Tray_Notifications`, `Tray_Poll_Seconds` | Statussymbol (siehe [Statussymbol](#statussymbol)). |
| `Brand_*`, `Tool_Theme`, `Tool_Color` | Aussehen (siehe [Branding](#branding)). |

### Benutzeroberfläche

Das Fenster ist für Nutzer ohne technisches Wissen gebaut. Es lässt sich in der
Größe ändern (mindestens 640 × 480). Größe, Position, Design, Sprache und die Wahl
für das Statussymbol speichert SelfX pro Nutzer in `HKCU\Software\SelfX`. Pro Nutzer
läuft nur ein Fenster. Ein zweiter Start holt das offene Fenster nach vorn.

- **Navigation (links):** *Fehlerbehebung*, *Gerätestatus* (mit Zähler für Probleme
  und Warnungen), *Systeminformationen*, das Firmenlogo (`Brand_Logo`) und unten
  *Protokolle an Support senden* mit dem Zustand des Dienstes.
- **Fehlerbehebung:** Suche, Kategorien und eine Karte pro Aktion. Die Karte hat ein
  Info-Symbol (Erklärung), eine Start-Schaltfläche und ein Schild, wenn die Aktion
  über den Dienst läuft. Während eine Aktion läuft, ist ihre Schaltfläche gesperrt.
  Das Ergebnis (Exitcode 0 = Erfolg) erscheint in der Meldungsleiste und wird
  protokolliert.
- **Gerätestatus:** Eine Karte pro Prüfung, Probleme zuerst. Der Status ist *In
  Ordnung*, *Bald erledigen* (Warnung), *Fehler* oder *Unbekannt*.
  - *Beheben* (Schraubenschlüssel) führt nach einer Bestätigung die konfigurierte
    Reparatur aus.
  - Der Pfeil an der Karte prüft nur diesen Status erneut, der Pfeil oben prüft alles.
  - *Alle Probleme beheben* führt jede konfigurierte Reparatur einmal aus und prüft
    danach alles erneut. Ist der Dienst beschäftigt, werden übrige Reparaturen
    übersprungen und gemeldet.
  - Zeiten werden in der Zeitzone des Nutzers angezeigt.
- **Systeminformationen:** Eine Karte pro Abschnitt (Gerät, Windows, Nutzer und
  Verwaltung, Netzwerk, Bericht). Ein Doppelklick auf eine Zeile kopiert den Wert.
  Die letzten Werte erscheinen sofort aus `%LOCALAPPDATA%\SelfX\SystemInfo.json` und
  werden im Hintergrund aktualisiert. Kopieren und Export (TXT, HTML, CSV, JSON)
  enthalten auch den Gerätestatus. Darunter stehen Werkzeuge: Intune-Synchronisierung,
  Compliance-Prüfung, Unternehmensportal, Quick Assist, MDM-Protokolle und Protokolle
  senden.
- **Titelleiste:** Hilfe (?), Einstellungen (Sprache, Design, Statussymbol) und Info (i).
- **Hilfe-Dialog:** Zeigt nur die Kontakte, die Sie eingetragen haben:
  `Support_Hours`, `Support_Phone_number`, `Support_Mail` (öffnet eine E-Mail),
  `Support_Teams` (eine Nutzer- oder Postfachadresse öffnet einen Teams-Chat, ein
  vollständiger `https://`-Link wird unverändert geöffnet) und `Support_Website`
  (nur `https://`; `http://` wird ignoriert und im Protokoll vermerkt). Die Adresse in
  `Support_Mail` muss eine einzelne E-Mail-Adresse sein (keine Liste, keine Zusätze
  wie `?cc=`), sonst zeigt der Dialog sie ohne Schaltfläche. Ohne Kontakt bittet der Dialog, die IT-Abteilung
  zu kontaktieren.

### Hintergrundprüfungen

Der Dienst führt die Gesundheitsprüfungen regelmäßig im Hintergrund aus und speichert
das Ergebnis in `%ProgramData%\SelfX\Cache\Health.json` (nur SYSTEM und
Administratoren). SelfX und das Statussymbol lesen diesen Zwischenspeicher mit der
Anfrage `STATUS`. Die Anfrage antwortet sofort und führt nichts aus. Jede Prüfung,
die SelfX selbst startet, aktualisiert den Zwischenspeicher ebenfalls.

Einstellungen in `Health_Config.xml`:

```xml
<Background Enabled="true" IntervalMinutes="15" PauseOnBattery="true" MaxCpuPercent="75" StartDelaySeconds="120" />
```

| Attribut | Standard | Bedeutung |
|---|---|---|
| `Enabled` | `true` | `false`: keine Hintergrundprüfung. SelfX prüft dann beim Öffnen. |
| `IntervalMinutes` | `15` | 5 bis 1440. Abstand zwischen zwei Prüfungen. |
| `PauseOnBattery` | `true` | Im Akkubetrieb nicht prüfen. SelfX zeigt das letzte Ergebnis und weist auf die Pause hin. |
| `MaxCpuPercent` | `75` | 10 bis 100. Ist die Prozessorlast höher, wird die Prüfung um 2 Minuten verschoben. `100` = kein Limit. |
| `StartDelaySeconds` | `120` | 0 bis 3600. Wartezeit nach dem Start des Dienstes, damit die Anmeldung nicht langsamer wird. |

Fehlende oder ungültige Werte ersetzt der Standard. Während einer Reparatur wird
nicht geprüft. Die Prüfung läuft mit niedriger Priorität und höchstens 240 Sekunden
und schreibt nur eine Zeile in `SelfXService.log`. Änderungen gelten ohne Neustart
des Dienstes.

### Statussymbol

`SelfX_Tray.ps1` zeigt im Infobereich ein SelfX-Symbol mit farbigem Punkt: grün (in
Ordnung), gelb (Warnung), rot (Problem), grau (noch kein Status). Die Kurzinfo nennt
die Zahl der Probleme und Warnungen. Wechselt eine Prüfung zu *Fehler*, erscheint
einmal eine Windows-Benachrichtigung. Ein Klick darauf öffnet den Gerätestatus.
Das Rechtsklick-Menü öffnet SelfX, prüft den Status, sendet Protokolle, schaltet
Benachrichtigungen ein oder aus oder verbirgt das Symbol.

| Schlüssel in `Tool_Config.xml` | Standard | Bedeutung |
|---|---|---|
| `Show_Tray_Icon` | `True` | `Install.ps1` legt den Run-Eintrag `SelfXTray` in HKLM an. Das Symbol startet bei jeder Anmeldung. `False` entfernt den Eintrag. |
| `Tray_Notifications` | `True` | Benachrichtigung bei einem Fehler. `False` schaltet sie für alle aus und blendet den Schalter der Nutzer aus. |
| `Tray_Poll_Seconds` | `60` | 15 bis 3600. Wie oft das Symbol den Zwischenspeicher liest (es führt keine Prüfung aus). |

**Pro Nutzer:** Jeder Nutzer kann Benachrichtigungen ausschalten
(`HKCU\Software\SelfX\TrayNotifications`, 1 = an, 0 = aus) und das Symbol verbergen
oder wieder anzeigen (`HKCU\Software\SelfX\TrayIcon`). Das Symbol bleibt bei
ausgeschalteten Benachrichtigungen sichtbar, Probleme werden weiter gemerkt. Antworten
auf Aktionen des Nutzers erscheinen immer.

Das Symbol braucht keine Administratorrechte. Es liest nur den Zwischenspeicher über
die Pipe des Dienstes und erfasst kurz nach dem Start einmal die Systeminformationen
des Nutzers. Eine Installation oder ein Update über Intune (SYSTEM) startet die neue
Version in den Sitzungen der angemeldeten Nutzer. Nutzer, die das Symbol verborgen
haben, bekommen es nicht zurück. Nach einer Deinstallation werden die Symbole
geschlossen. SelfX Service zeigt nach der Installation keine Benachrichtigung.

### Geräteprotokolle für den Support

Die Aktion *Geräteprotokolle an den Support senden* (`Q_Device_SendLogs`,
`D_Device_SendLogs`) und die Schaltflächen *Protokolle an Support senden* sammeln alle
Protokolle, die für die Analyse eines Geräteproblems nötig sind, und öffnen eine
E-Mail an den Support mit dem Bericht im Anhang. Der Nutzer beschreibt das Problem
und sendet selbst. Nichts wird automatisch gesendet.

**Ablauf:**

1. Der Nutzer bestätigt. Die Oberfläche sendet `RUN SelfX_Device_CollectLogs.ps1` an
   den Dienst (Timeout 1800 Sekunden).
2. Der Dienst führt das Skript als SYSTEM aus. Es startet den nur lesenden Collector
   `Scripts_to_run\Collect-DeviceLogs.ps1` und schreibt den Bericht nach
   `%ProgramData%\SelfX\Reports\<Nutzer-SID>\DeviceLogs-<Computer>-<Zeit>.txt`,
   bei `DeviceLogs_Compress` ungleich `False` als `.zip`.
3. Der Ordner hat eine geschützte ACL: Vollzugriff für SYSTEM und Administratoren,
   Lesen nur für den anfragenden Nutzer. Der vorherige Bericht des Nutzers wird bei
   jedem Lauf gelöscht, Berichte über 7 Tage alt für alle Nutzer.
4. Die Oberfläche kopiert den Bericht nach `%LOCALAPPDATA%\SelfX\Reports` und öffnet
   eine neue E-Mail:
   - klassisches Outlook (COM): Empfänger `Support_Mail`, Betreff und Text aus der
     Sprachdatei (`Report_Mail_Subject`, `Report_Mail_Body`), Bericht im Anhang;
   - sonst `outlook.exe /a <Datei>`;
   - sonst (zum Beispiel neues Outlook) die Standard-Mail-App über `mailto:` und ein
     Explorer-Fenster mit der markierten Datei, die der Nutzer anhängt.

**Inhalt:** Der Collector liest nur. Er ändert nichts, lädt keine Registry-Struktur,
installiert nichts und sendet nichts. Der Bericht enthält Computer-, Nutzer- und
Mandantennamen und Protokolle des Geräts (Autopilot/ESP, IME und Win32-Apps,
Servicing, Ereignisprotokolle, AppX, Windows Update, Netzwerk, Sprache). Er braucht
etwa eine bis einige Minuten. Die Abschnitte und Parameter stehen im Kopf von
`Collect-DeviceLogs.ps1`.

**Was ein normaler Nutzer sieht:** Der Bericht wird pro Nutzer gekürzt. Der Dienst
liest das Token des Anfragenden und setzt `SELFX_CALLER_ADMIN`. Der Wert `1` gilt nur,
wenn die Gruppe *Administratoren* im Token **aktiviert** ist (erhöhte Rechte). Fehlt
der Wert oder ist er anders, gilt der Nutzer als normaler Nutzer.

| | Administrator (`1`) | Normaler Nutzer |
|---|---|---|
| Collector | vollständig | `-UserView -CallerSid <eigene SID>` |
| Seriennummer, Konsolennutzer | ja | nein |
| Sitzungen (`quser`) | alle | nur die eigene |
| `dsregcmd` | alles | nur Beitritts- und Anmeldestatus, keine Mandanten-, Geräte- oder Nutzer-IDs |
| Profile und Registry-Strukturen von Nutzern | alle | nur die eigenen |
| AppX-Nutzereinträge | alle | nur der eigene |
| Namen, SIDs und Profilordner anderer Nutzer | unverändert | ersetzt durch `<other user>` |
| SelfX-Geräteprotokolle (`SelfXService.log`, Skriptprotokolle) | ja | nein |
| Eigene SelfX-Nutzerprotokolle | ja | ja |

Ein Administrator, der SelfX **ohne** erhöhte Rechte startet, gilt als normaler
Nutzer. Ohne `-UserView` (Intune-Win32-App, Remediation, manueller Lauf) ist der
Bericht vollständig.

**SelfX-Protokolle im Bericht:** Zwei Seiten fügen sie mit ihren jeweils eigenen
Rechten hinzu:

- Das **Skript als SYSTEM** fügt, nur für Administratoren, `SelfXService.log`,
  `Install.log`, `Uninstall.log` und alle anderen `*.log` aus
  `%ProgramData%\SelfX\Logs` der letzten `DeviceLogs_Days` Tage hinzu. Es liest nur
  Dateien direkt in diesem Ordner, den Unterordner `Logs\Users` nie.
- Das **SelfX-Fenster (der Nutzer)** fügt die Protokolle des eigenen Nutzers aus
  `Logs\Users\<eigene SID>` der Kopie des Berichts hinzu. Protokolle anderer Nutzer
  kommen nie hinzu. Ein Fehler dabei stoppt die E-Mail nicht.

In der `.zip` stehen sie im Ordner `SelfX-Logs` (Nutzerprotokolle in `SelfX-Logs\User`),
im `.txt` als letzter Abschnitt. Es gelten höchstens 2 MB pro Datei und 30 MB pro Seite.

*Warum zwei Seiten:* Nutzer können ihren Ordner unter `Logs\Users` ändern. Würde
SYSTEM ihn lesen, könnte ein Nutzer das Lesen (zum Beispiel mit einer Junction, die
zwischen Prüfung und Lesen getauscht wird) auf eine geschützte Datei umlenken. Das
Fenster liest mit den Rechten des Nutzers und kann deshalb nur hinzufügen, was der
Nutzer ohnehin lesen darf.

`SelfXService.log` nennt die Nutzer, die auf dem Gerät Aktionen gestartet haben.

**Exitcodes von `SelfX_Device_CollectLogs.ps1`:** `0` Bericht erstellt, `1` Sammeln
oder Komprimieren fehlgeschlagen, `2` anfragender Nutzer unbekannt.

**Anpassen:** Für ein eigenes Berichtsskript behalten Sie `Post_Action` `MailReport`
bei und schreiben den Bericht als `DeviceLogs-*.zip` oder `DeviceLogs-*.txt` mit
derselben ACL nach `%ProgramData%\SelfX\Reports\<SELFX_CALLER_SID>`. Entfernen Sie
beide Katalogaktionen, um die Funktion auszublenden. Die Schaltfläche in den
Systeminformationen erscheint nur, wenn eine `System`-Aktion mit `MailReport`
existiert.

### Netzwerk-Messungen

Optional und standardmäßig aus. Die Datei `Network_Test_Config.xml` schaltet auf der
Seite *Systeminformationen* im Bereich Netzwerk zusätzliche Zeilen ein:

- Antwortzeit zum Standardgateway,
- Dauer einer Namensauflösung (DNS),
- Dauer eines TCP-Verbindungsaufbaus.

Die Messungen laufen im Nutzerkontext, nur lesend, im Hintergrund zusammen mit den
übrigen Systeminformationen. Nutzer können keine Ziele eintragen oder ändern.

```xml
<Network_Test_Config>
  <Settings Enabled="True" Gateway="True" Samples="3" TimeoutMs="2000" />
  <Targets>
    <Target Label="Intranet" Host="intranet.example.org" Port="443" />
    <Target Label="Internet" Host="www.example.org" Port="443" />
  </Targets>
</Network_Test_Config>
```

| Einstellung | Bedeutung |
|---|---|
| `Enabled` | `True` schaltet die Messungen ein. Standard: `False`. |
| `Gateway` | `True` (Standard): Ping zum Standardgateway. |
| `Samples` | Messungen je Wert, 1 bis 5. Standard: 3. |
| `TimeoutMs` | Wartezeit je Messung, 200 bis 5000 ms. Standard: 2000. |
| `Target` | Bis zu 5 Ziele. `Label`: Anzeigename (Buchstaben, Ziffern, `. _ -`, Leerzeichen, bis 40 Zeichen). `Host`: DNS-Name oder IPv4-Adresse. `Port`: optional, 1 bis 65535. |

**Ziele frei wählen:** Der Name des Ziels steht nur in der Konfiguration. So legt Ihre
Organisation fest, was gemessen wird:

- Ein **interner Name** (nur im Firmennetz oder über VPN erreichbar) zeigt die
  Qualität der internen Verbindung.
- Ein **aus dem Internet erreichbarer Name** zeigt die Verbindung eines Geräts, das
  mobil ohne VPN arbeitet. Nehmen Sie eine Adresse, die Ihre Organisation selbst
  betreibt oder die für solche Tests gedacht ist.
- Sie können beides kombinieren.

**Messwerte:**

- *Latenz: Standardgateway*: Mittelwert, Minimum, Maximum und Zahl der verlorenen
  Antworten. Ohne bekannte IPv4-Gateway-Adresse fehlt die Zeile.
- *DNS-Abfrage: Label*: Dauer der Namensauflösung über den Windows-Resolver. Dessen
  Zwischenspeicher gilt, wiederholte Messungen können schneller sein. Bei einer
  IPv4-Adresse als `Host` entfällt die Zeile.
- *Verbindung: Label*: Dauer, bis die TCP-Verbindung zu `Host:Port` steht. Sie wird
  sofort geschlossen, es werden keine Daten gesendet. Ohne `Port` entfällt die Zeile.
- Gehen alle Messungen eines Werts verloren, ist die Zeile ein Fehler, gehen einige
  verloren, eine Warnung.
- Ein Durchlauf dauert höchstens 20 Sekunden. Danach steht bei den übrigen Zeilen
  „nicht gemessen (Zeitlimit erreicht)“.
- Es wird kein Durchsatz gemessen.

**Sicherheit:** Ziele kommen nur aus der Datei (nur Administratoren können sie
ändern). `Host` wird streng geprüft: nur Buchstaben, Ziffern, Bindestrich und Punkte,
kein Schema, kein Pfad, kein Port, keine Leerzeichen. Es gibt höchstens 5 Ziele. Eine
DTD in der XML ist verboten. Ungültige Einträge werden übersprungen, eine nicht
lesbare Datei schaltet die Messungen aus. Die Zeilen erscheinen auch in Kopie, Export
und Ticket der Systeminformationen, mit den eingetragenen Hostnamen. Das Gerät sendet
nur eine Namensabfrage, Ping-Pakete zum Gateway und den TCP-Verbindungsaufbau zu den
Zielen.

**Vor der Verteilung prüfen:** `tools\Test-SelfXNetworkMeasure.ps1` zeigt
Einstellungen, Ziele und ungültige Einträge. Mit `-Run` führt es die Messungen einmal
auf dem aktuellen Gerät aus, auch bei `Enabled="False"`.

### Ticket per E-Mail

Optional und standardmäßig aus (`Ticket_Enabled` = `False`). Ist die Funktion
eingeschaltet und eine gültige Adresse gesetzt, zeigt der Hilfe-Dialog (?) die Zeile
*Problem melden* mit der Schaltfläche *Ticket erstellen*.

**Ablauf (Nutzerkontext, keine erhöhten Rechte):**

1. Der Nutzer beschreibt das Problem (bis 3000 Zeichen).
2. SelfX fügt **immer** die Geräteinformationen hinzu: alle Zeilen aus
   *Systeminformationen* und *Gerätestatus*, Gerätename, Windows-Build und
   SelfX-Version. Der Nutzer kann sie nicht abwählen, sieht sie aber in der E-Mail.
3. Die E-Mail wird nur **angezeigt, nie automatisch gesendet**. Der Nutzer prüft sie
   und sendet selbst.

**Übergabe an das Mailprogramm:**

- *Klassisches Outlook (COM):* Empfänger, Betreff, vollständiger Text und die Datei
  `TicketInfo-<Gerät>-<Zeit>.txt` als Anhang.
- *Neues Outlook und andere Programme (`mailto`):* Empfänger, Betreff und Text. Der
  Link ist in der Länge begrenzt, deshalb wird der Text bei Bedarf gekürzt
  (Beschreibung und Kernfelder zuerst, Geräteinformationen zuletzt). Die vollständige
  Datei wird im Explorer markiert und muss vom Nutzer angehängt werden. Die Oberfläche
  weist darauf hin.
- Die Datei liegt in `%LOCALAPPDATA%\SelfX\Reports` (nur für den Nutzer). Ältere
  `TicketInfo-*`-Dateien werden beim nächsten Ticket gelöscht.

**Aufbau der E-Mail (für Filter und Automatisierung):** Betreff
`[<Ticket_Subject_Tag>][<Art>] <Gerät>`. Die Art steht in der Sprache des Nutzers,
zum Beispiel *Störung*. Der Text beginnt mit festen englischen Feldnamen (`Time (UTC)`,
`Computer`, `Windows build`, `SelfX version`), danach folgen `Description of the user:`
und `Device information:` als abgesetzte Blöcke.

**Empfänger bestimmen.** Die Reihenfolge, von der höchsten Priorität:

1. **Registry pro Gerät:** `TicketMail` (und optional `TicketCc`) in
   `HKLM\SOFTWARE\SelfX\Support`. Intune kann sie pro Entra-Gerätegruppe setzen
   (Beispiel in der [Installationsanleitung](Installation.md)). Wechselt ein Gerät die
   Gruppe, ändern sich die Werte mit dem Skript der neuen Gruppe, ohne neues Paket.
2. **Regeln in `Ticket_Config.xml`** (siehe unten).
3. **`Ticket_Mail`** in `Tool_Config.xml`, sonst **`Support_Mail`**.

Jede Adresse muss genau eine einfache Adresse sein, sonst wird der Wert ignoriert und
die nächste Stufe gilt. Der Empfänger steht im Dialog („Die E-Mail geht an: …“). Der
Nutzer kann ihn nicht ändern.

**Regeln in `Ticket_Config.xml`:** Die Datei liegt im Installationsordner (nur
Administratoren können sie ändern). Sie enthält beliebig viele IT-Einheiten und
Regeln. Nichts ist im Code festgelegt.

- `<Unit Id="IT1" Mail="it1@example.com" Cc="" />` legt eine Einheit mit Empfänger und
  optionaler Kopie fest. Die `Id` besteht aus Buchstaben, Ziffern, `.`, `_`, `-`
  (bis 40 Zeichen). Mail und Cc sind je genau eine einfache Adresse.
- `<Rule Source="GroupTag|OU|Category" Match="..." Unit="IT1" />` weist einen Wert
  einer Einheit zu. `Match` ist ein exakter Wert (Groß-/Kleinschreibung egal).
  Statt `Match` können Sie `Regex` verwenden (.NET-Ausdruck, bis 300 Zeichen, Zeitlimit
  200 ms). Enthält der Ausdruck eine benannte Gruppe `(?'unit'...)`, kann `Unit`
  entfallen. Beispiel: `^[A-Z]{2}-(?'unit'IT[0-9]+)-[A-Z]{3}$` für Group-Tags wie
  `DE-IT1-BER`.
- Regeln werden von oben nach unten geprüft. Die **erste passende gewinnt**.
- Die Werte kommen vom Gerät (nur lesen): `GroupTag` und `Category` aus
  `HKLM\SOFTWARE\SelfX\Support` (REG_SZ, nur Administratoren können schreiben, erlaubt
  sind Buchstaben, Ziffern, Leerzeichen, `.`, `_`, `-`, bis 64 Zeichen) und `OU` aus
  dem Distinguished Name des Computerkontos (Hybrid-Geräte,
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine`).
  Ungültige Werte zählen als leer.
- Ungültige Einträge (falsche Adresse, unbekannte Einheit, ungültiger Ausdruck,
  doppelte Id, mehr als 500 Einheiten oder 2000 Regeln) werden übersprungen und als
  Warnung im SelfX-Protokoll genannt. Ist die Datei nicht lesbar, gilt die
  Standardadresse.
- Gruppen-Tag, Einheit und Kategorie stehen als Felder im Ticket (`Group tag`,
  `Support unit`, `Device category`).
- **Prüfen vor der Verteilung:**
  `tools\Test-SelfXTicketRouting.ps1 -GroupTag ... -Category ... -OU ...` zeigt Fehler
  der Datei und das Ergebnis für die angegebenen Werte. Es sendet nichts und liest
  keine Registry.

**Hinweis zu Postfächern:** Verwenden Sie nur gemeinsame Funktionspostfächer, keine
persönlichen. `Ticket_Config.xml` liegt auf jedem Gerät und kann von jedem Nutzer
gelesen werden. Adressen, die nicht jeder sehen soll, gehören deshalb in die
Registrywerte pro Gerät. Dort liegt nur die Adresse der eigenen Einheit.

**Sicherheit:** Empfänger und Kopie kommen nur aus `Tool_Config.xml`,
`Ticket_Config.xml` und der Registry (jeweils nur für Administratoren schreibbar). Der
Nutzer kann sie nicht ändern. Felder werden bereinigt: keine Zeilenumbrüche im
Betreff, feste Längen, der Gerätename muss ein gültiger Name sein. Freitext und
Geräteinformationen stehen in Codeblöcken, damit ein Ticketsystem daraus keine
Befehle ausführt (zum Beispiel GitLab-Quick-Actions). Testen Sie vor dem Einschalten,
ob das in Ihrer Version greift. Die Geräteinformationen enthalten Adressen (zum
Beispiel Proxy) und Gerätedaten und sind für die IT bestimmt. Das Protokoll nennt nur
das Ergebnis (`Outlook`, `Manual`, `Error`) und die Zeilenzahl, nie den Text.

### Copilot Chat

Optional und standardmäßig aus (`Copilot_Enabled` = `False`). Ist die Funktion an und
`Copilot_Url` eine gültige Adresse, zeigt der Hilfe-Dialog (?) die Zeile *Copilot Chat
fragen* mit der Schaltfläche *Text vorbereiten*. Die Hilfe-Schaltfläche muss dafür
sichtbar sein (`Show_Support_Button` = `True`). Copilot Chat ist die Chat-Funktion in
Microsoft 365. SelfX nutzt keine Schnittstelle und kein Token: Der Nutzer fügt den
Text selbst in Copilot Chat ein.

**Ablauf (Nutzerkontext, keine erhöhten Rechte):**

1. Der Nutzer beschreibt das Problem mit eigenen Worten (optional, bis 1000 Zeichen)
   und wählt *Text erstellen*.
2. SelfX zeigt den fertigen Text in einer Vorschau. Der Nutzer kann ihn lesen und
   ändern.
3. *Kopieren und Copilot öffnen* legt den Text in die Zwischenablage und öffnet die
   Adresse aus `Copilot_Url`. Der Nutzer fügt den Text ein (Strg+V) und sendet ihn
   selbst ab. SelfX sendet nichts.
4. Copilot Chat soll in einfacher Sprache antworten. Mit `Copilot_Audience` = `Admin`
   antwortet es für IT-Personal mit technischen Schritten.

**Was im Text steht (feste Liste):** Windows-Ausgabe, -Version und -Build, SelfX-Version
und Sprache, Tage seit dem letzten Neustart, Laufwerke (Buchstabe, belegt in Prozent,
frei in GB), der Gerätestatus (Name der Prüfung, Zustand, gekürzte Einzelheiten; dazu
gehören auch ausstehende Updates, ein anstehender Neustart und Firmen-Apps mit
Fehlern) und das Netzwerk (nur die Art der Verbindung: LAN, WLAN, Mobilfunk, VPN, und
die Art des Proxys: keiner, manuell, Skript). Es gibt keinen Internettest, SelfX stellt
keine Netzwerkverbindung her.

**Was nicht im Text steht:** Gerätename, Nutzername, Domäne, E-Mail-Adressen,
IP- und MAC-Adressen, Seriennummern, die Seite *Systeminformationen*, Protokolle.
Taucht so etwas in der Beschreibung oder in Einzelheiten auf, wird es durch
Platzhalter ersetzt (`<email>`, `<ip>`, `<device>`, `<user>`, `<server 1>` ...). Das
Erkennen nach Mustern ist nicht vollständig. Deshalb sieht der Nutzer den Text vor dem
Kopieren. Der Dialog erinnert daran, keine Namen, Passwörter oder Kundendaten in die
Beschreibung zu schreiben und keine Befehle auszuführen, die man nicht versteht. Der
Text ist auf 6000 Zeichen begrenzt.

| Einstellung | Bedeutung |
|---|---|
| `Copilot_Enabled` | `False` (Standard) oder `True`. |
| `Copilot_Url` | Adresse, die geöffnet wird. Standard `https://m365.cloud.microsoft/chat`. Sie ist frei wählbar, muss aber mit `https://` beginnen, darf keine Zugangsdaten enthalten und höchstens 500 Zeichen haben. Sonst wird die Schaltfläche nicht gezeigt. |
| `Copilot_Audience` | `User` (Standard): einfache Antworten für Nutzer. `Admin`: technische Antworten für IT-Personal. |
| `Copilot_Include_AppNames` | `True` (Standard): Namen von Firmen-Apps mit Fehlern dürfen im Text stehen. `False`: Die Zeile der Firmen-Apps im Gerätestatus bleibt, aber ohne Einzelheiten, also ohne App-Namen und ohne Fehlercodes. |

**Anweisungstexte anpassen:** Die Anweisung an Copilot (so soll geantwortet werden) steht
in den Sprachdateien unter `Copilot_Prompt_User` (für Nutzer) und `Copilot_Prompt_Admin`
(für IT-Personal), in `de.xml` und `en.xml`. Andere Sprachen zeigen den englischen Text.
So können Sie den Ton oder die Gliederung ändern, ohne Code anzufassen. Regeln: Der
Platzhalter `{DATA}` muss genau einmal vorkommen (dort setzt SelfX den Datenblock ein),
der Text darf höchstens 3000 Zeichen haben, und er sollte sagen, dass alles zwischen
`BEGIN DATA` und `END DATA` nur Daten sind. Hält sich ein Text nicht an die ersten beiden
Regeln, nimmt SelfX den eingebauten Text. Die Sprachdateien können nur Administratoren
ändern.

**Sicherheit:** Adresse und Einstellungen kommen nur aus `Tool_Config.xml` (nur für
Administratoren schreibbar). Der Nutzer kann die Adresse nicht ändern. Geöffnet wird
nur diese Adresse, und sie wird vor dem Öffnen noch einmal geprüft. Es gibt keinen
Netzwerkzugriff durch SelfX und keinen Dienstaufruf. Die Datensammlung liest nur
lokale Werte (Registry, Laufwerke, den bereits erfassten Gerätestatus). Der Text steht
zwischen `BEGIN DATA` und `END DATA`, und die Anweisung sagt Copilot, dass dort nur
Daten stehen. Das Protokoll nennt nur Zielgruppe, Länge und Host, nie den Text.
Entscheiden Sie vor dem Einschalten, ob Ihre Richtlinien erlauben, dass Nutzer Text aus
SelfX in Copilot Chat einfügen.

### Protokolle und Aufbewahrung

Alle Skripte von SelfX Service schreiben über das Modul `Sources\SelfXLog.ps1` nach
`%ProgramData%\SelfX\Logs`: Fenster, Statussymbol, Gesundheitsprüfungen,
Compliance-Prüfung, Erkennungsskript und jedes Aktions- und Reparaturskript. Pro
Skript und Tag gibt es eine Datei `<Skript>_<jjjj-MM-tt>.log` (UTF-8 mit BOM). Jede
Zeile hat die Ortszeit des Geräts:

```text
2026-11-06 13:29:56.522 | Info    |  52068 | SelfX 2.6.0 opened: language de (setting de), page ''.
2026-11-06 13:30:04.426 | Warning |  52068 | Message (Warning): Windows restarts in about 30 seconds. ...
```

| Ordner | Inhalt | Lesbar für |
|---|---|---|
| `Logs` | Skripte als SYSTEM (Reparaturen, System-Aktionen, `HealthStatus`, `Check-Compliance`, `Detection`), `SelfXService.log`, `Install.log`, `Uninstall.log` | SYSTEM und Administratoren |
| `Logs\Users\<SID>` | Skripte des Nutzers: Fenster (`SelfX_*`), Statussymbol (`SelfX_Tray_*`), Nutzeraktionen | den Nutzer, SYSTEM und Administratoren |

Das Fenster protokolliert seinen Start, jede Aktion mit der Antwort des Nutzers, das
Ergebnis jeder Dienstaktion (Status und Exitcode), vom Nutzer gestartete
Statusprüfungen, Sprachwechsel und **jede angezeigte Meldung**. Das Statussymbol
protokolliert Statusänderungen, Benachrichtigungen und warum es endet. `HealthStatus`
protokolliert jedes Ergebnis der Hintergrundprüfung.

`Install.ps1` richtet `Logs\Users` so ein, dass jeder Nutzer nur seinen eigenen
Ordner anlegen kann und die Ordner anderer weder auflisten noch lesen kann. Ein
Ordner, der ein Link ist oder einem anderen Konto gehört, wird nie benutzt. Ist
`Logs\Users` nicht nutzbar, gehen die Nutzerprotokolle nach `%LOCALAPPDATA%\SelfX\Logs`.

**Aufbewahrung:** Dateien, die älter sind als `Log_Retention_Days` (1 bis 3650,
Standard **90**), werden gelöscht:

- Der Dienst löscht alte `*.log`- und `*.old`-Dateien in `Logs` einmal am Tag, auch
  wenn die Hintergrundprüfung aus ist, und schreibt die Zahl in `SelfXService.log`.
- Jeder Nutzer löscht alte Dateien in seinem eigenen Ordner `Logs\Users\<SID>`,
  höchstens einmal am Tag, wenn ein SelfX-Skript startet. Der Dienst löscht dort nie,
  weil ein Löschen als SYSTEM keinem Link folgen darf, den ein Nutzer anlegen könnte.

`Uninstall.ps1` behält die Protokolle. Mit `-RemoveLogs` wird `%ProgramData%\SelfX`
gelöscht.

### Gerätestatus

Die Seite *Gerätestatus* zeigt das Ergebnis der lokalen Gesundheitsprüfungen. Sie
liest den Zwischenspeicher der Hintergrundprüfung, wenn SelfX geöffnet wird, und
fordert `HEALTH` an, wenn der Nutzer erneut prüft.

| Status | Bedeutung |
|---|---|
| **In Ordnung** (grün) | Alles passt. |
| **Bald erledigen** (gelb, technisch „Pending“) | Eine Aktion steht aus, zum Beispiel Updates oder Compliance. Das ist eine Warnung, kein Fehler. |
| **Fehler** (rot) | Die Prüfung ist fehlgeschlagen. |
| **Unbekannt** (grau) | Daten fehlen, die Quelle wird nicht unterstützt oder der Dienst ist nicht verfügbar. Das ist keine bestandene Prüfung. |

Technische Details bleiben englisch, Beschriftungen und Statuswörter folgen der
Sprache der Oberfläche. Kopieren und Export enthalten die Ergebnisse. Der Bericht ist
eine Momentaufnahme, keine laufende Überwachung.

Stellen Sie `Sources\Health_Config.xml` vor dem Paketieren ein. Der Installer kopiert
sie neben `HealthStatus.ps1`, schreibbar nur für Administratoren und SYSTEM. Der
Client kann dem Dienst weder Pfad noch Code übergeben.

**Die Prüfungen:**

| Prüfung | Was geprüft wird |
|---|---|
| IME | Der Dienst `IntuneManagementExtension` muss laufen. Fehlt er oder ist er gestoppt, ist das ein Fehler. |
| Defender | Dienst, Virenschutz und Echtzeitschutz sind aktiv, die Signaturen sind nicht als veraltet gemeldet und höchstens 7 Tage alt. Passiver Modus oder Virenschutz eines Drittanbieters kann deshalb einen Fehler ergeben. Eine fehlgeschlagene Abfrage ist *Unbekannt*. Das Detail nennt Signaturversion und Zeit des letzten Updates. Standardmäßig bietet die Zeile *Beheben* (`Update-MpSignature`). |
| Compliance | Intune bewertet die Compliance in der Cloud, Windows speichert dafür keinen lokalen Status. Mit `<Compliance Script="Check-Compliance.ps1" />` prüft das Paket die lokalen Kriterien einer typischen Intune-Compliance-Richtlinie: Intune-Registrierung, BitLocker auf dem Systemlaufwerk, Secure Boot, TPM, Firewall (alle Profile), Defender (Virenschutz, Spyware-Schutz, Echtzeitschutz, aktuelle Signaturen) und optional eine Mindestversion von Windows. Gleichen Sie `$Require` im Skript mit Ihrer Richtlinie ab. Maßgeblich bleibt das Unternehmensportal. Exit `0` = In Ordnung, anderer Exitcode = *Bald erledigen*. Fehlendes Skript, Ausnahme oder Timeout = Fehler. Ohne das Element `Compliance` ist die Zeile *Unbekannt*. Solange die Zeile nicht in Ordnung ist, bietet sie *Beheben* (Defender-Signaturen aktualisieren). |
| Anwendungen | Zwischenspeicher des IME-Berichts für Win32-Apps plus Ihre eigenen Anwendungsprüfungen. Erfolg (`1000`) ist In Ordnung, `5000` bis `5999` sind Fehler, alles andere ist *Unbekannt*. Fehler hat Vorrang vor Unbekannt, Unbekannt vor In Ordnung. Ohne einbezogene Ergebnisse ist das Gesamtergebnis *Unbekannt*. |
| Datenträger | Je festes Laufwerk ein Fehler, wenn mindestens 90 % belegt **oder** weniger als 20 GiB frei sind (als GB angezeigt). Genau 20 GiB genügen nur bei einer Belegung unter 90 %. Die Werte sind einstellbar. |
| BitLocker | Jedes OS- und feste Datenvolume muss vollständig verschlüsselt und der Schutz aktiv sein. Ausgesetzte, unverschlüsselte oder teilweise verschlüsselte Volumes sind Fehler. Nicht lesbare Daten sind *Unbekannt*. Schlüssel und Wiederherstellungsgeheimnisse werden nicht erfasst. |
| Neustart ausstehend | Fehler, wenn Windows einen Neustart meldet: `RebootPending` (Component Based Servicing), `RebootRequired` (Windows Update), `RebootRequired` des Windows Update Agents, Updates des Orchestrators mit `ReadyToReboot` (das Detail nennt die Updates) oder eine ausstehende Umbenennung des Computers. `PendingFileRenameOperations` wird absichtlich ignoriert, weil Installer es oft dauerhaft gesetzt lassen. Nicht lesbare Registry-Daten sind *Unbekannt*. |
| Zu installierende Updates | Durchsucht nur den **lokalen Cache des Windows Update Agents** (offline, kein Scan, Download oder Installation). Jedes nicht installierte, nicht ausgeblendete Update (außer reinen Browse- oder optionalen Updates) ergibt *Bald erledigen* und steht im Detail. Ein leerer Cache ist nur in Ordnung, wenn der letzte erfolgreiche Scan höchstens `MaxSearchAgeDays` (Standard 14) zurückliegt, sonst *Unbekannt*. Nur über ConfigMgr verteilte Updates gehören nicht dazu. Solange Updates ausstehen, bietet die Zeile *Beheben* (siehe [Reparaturen](#reparaturen)). |
| Zusätzliche Dienste | Genauer Dienstname und erwarteter Zustand (`Running` oder `Stopped`). |
| Skriptprüfungen | Exit `0` = In Ordnung, Exit `1` = Fehler. Andere Exitcodes, fehlende Dateien, Ausnahmen und Timeouts sind ebenfalls Fehler. |

**Grenzen der Anwendungsprüfung:** Der IME-Zwischenspeicher ist ein
Implementierungsdetail, keine stabile Microsoft-Schnittstelle, kein Inventar
installierter Software und kein Live-Bericht von Intune. Er kann veraltet sein und
mehrere Einträge für dieselbe App enthalten. Alle verfügbaren Einträge zählen: Ein
fehlgeschlagener Eintrag wird nicht verworfen, weil ein anderer erfolgreich war.
Ändert sich das Format oder sind Daten nicht lesbar, ist das Ergebnis *Unbekannt*.
Eine erfolgreiche Installation beweist nicht, dass die App funktioniert. Für Apps ohne
IME oder für Funktionsprüfungen nehmen Sie eigene Prüfungen.

**Beispiel `Health_Config.xml`:**

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

**Apps ausschließen und benennen:** `Exclude` vergleicht Namen ohne Beachtung der
Groß-/Kleinschreibung mit PowerShell-Platzhaltern (`*`, `?`, `[...]`). Auch App-IDs
lassen sich ausschließen. SelfX nimmt den Namen aus dem IME-Zwischenspeicher, sonst
aus den App-Richtlinien in den IME-Protokollen (`AppWorkload.log`) und zeigt erst dann
die App-ID. Mit `Application Id="..." Name="..."` legen Sie einen Namen fest, wenn
keiner gefunden wird. Ausgeschlossene Prüfungen laufen nicht. Schließen Sie alle Apps
aus, ergibt das kein *In Ordnung*. Die Zeile heißt *Unternehmens-Apps (Intune)*. Ihr
Detail nennt fehlgeschlagene Apps mit Fehlercode, zum Beispiel
`Monitoring Agent (error 0x87D1041C)`. Apps, die für das Gerät nicht gelten
(EnforcementState 3000 bis 3999), zählen nicht.

**Eigene Prüfskripte:** Legen Sie `Sources\HealthChecks` an und dort Ihre `.ps1`-Dateien
ab. Es sind nur einfache Dateinamen erlaubt, keine Unterordner, absoluten Pfade oder
`..`. Reparse Points am Ordner oder am Skript werden abgewiesen. Das Standardpaket
enthält nur `Check-Compliance.ps1`. Beispiel für eine nur lesende Prüfung:

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

**Sicherheit und Regeln für Prüfskripte:**

- Sie laufen bei jeder Aktualisierung nicht interaktiv als SYSTEM, ohne Rückfrage.
- Sie müssen nur lesen und wiederholbar sein. Sie dürfen nie neu starten, abmelden,
  Einstellungen ändern, Eingaben abfragen oder losgelöste Prozesse starten.
- Prüfen und signieren Sie sie vor der Verteilung. SelfX kann nicht beweisen, dass ein
  Skript nur liest. Schreiben Sie keine Zugangsdaten hinein.
- Der Exitcode bestimmt den Status. Die letzte nicht leere stdout-Zeile (bis 400
  Zeichen) erscheint als Detail, sonst `Exit code: N`. stderr wird verworfen.
- Timeout: 1 bis 30 Sekunden je Skript, Standard 30. Insgesamt höchstens 5
  Skriptprüfungen (Compliance, Anwendungsprüfungen und eigene zusammen) und 16
  zusätzliche Dienste. Bei einem Timeout beendet SelfX den Prozessbaum.
- Eine Dienstanfrage dauert höchstens 240 Sekunden und liefert höchstens 20.000
  Zeichen. Zu große Ergebnisse werden abgewiesen, nicht als In Ordnung gezeigt.
- Reparaturen und von SelfX angeforderte Prüfungen teilen sich eine Sperre. Eine
  gleichzeitige Anfrage bekommt *Busy*. Eine Prüfung, die während einer
  Hintergrundprüfung angefordert wird, wartet auf deren Ende.

**Tests vor dem Paketieren:** Führen Sie alle Tests des Pakets aus (siehe
[Release-Checkliste](Installation.md#release-checkliste-selfx-service)).
`Test-Catalog.ps1` prüft Katalog und Gesundheitskonfiguration. Die Tests ersetzen
Systemprüfungen und Skriptausführungen durch Mocks. Sie installieren keinen Dienst.
`Test-ServicePipe.ps1` startet nur den Pipe-Listener unter einem Test-Pipe-Namen.
`Test-Scripts.ps1` führt jedes Aktions- und Reparaturskript in einer Sandbox mit Mocks
aus. Nur die lesenden Skripte `Check-Compliance.ps1`, `Detection.ps1` und
`HealthStatus.ps1` laufen echt.

#### Einzelprüfung

Der Client kann eine einzelne Prüfung anfordern: `HEALTH <Id> [<Base64-UTF-8-Name>]`,
zum Beispiel `HEALTH Disk Qzo=` für Laufwerk `C:`. Der Dienst akzeptiert nur bekannte
Ids (`IME`, `Defender`, `Compliance`, `Applications`, `Disk`, `BitLocker`,
`PendingReboot`, `Updates`, `Service`, `Custom`) und einen streng Base64-codierten
Namen. `HealthStatus.ps1` führt dann nur diese Prüfung aus der geschützten
`Health_Config.xml` aus. Ein Name, der dort nicht steht, wird nie geprüft und ergibt
*Unbekannt*. Die Oberfläche ersetzt nur die betroffene Karte, der Dienst aktualisiert
nur diese Zeilen im Zwischenspeicher. Zeilen vom Typ `Collection` (Fehler des
Collectors) lösen eine vollständige Aktualisierung aus.

### Reparaturen

Die Gesundheitsprüfungen lesen nur. Damit eine Statuszeile die Schaltfläche *Beheben*
anbietet, legen Sie ein Reparaturskript in `Sources\Scripts_to_run` und tragen es in
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

| Attribut | Bedeutung |
|---|---|
| `Id` | Typ der Prüfung: `IME`, `Defender`, `Compliance`, `Applications`, `Disk`, `BitLocker`, `PendingReboot`, `Updates`, `Service`, `Custom`. |
| `Name` | Optional. Genauer technischer Name der Zeile (nicht die übersetzte Beschriftung). Ohne `Name` gilt die Reparatur für jede Zeile dieses Typs. Überschneidende Zuordnungen sind ein Konfigurationsfehler. |
| `Script` | Skript in `Scripts_to_run`. |
| `When` | `NotOK`: nur anbieten, solange die Zeile nicht in Ordnung ist. Standard `Always`: immer anbieten. |
| `TimeoutSeconds` | Zeitlimit des Dienstes für diese Reparatur. Positive Zahl bis 7200, Standard 900. |
| `OtherSessions` | `Block` wirkt wie im Aktionskatalog. Die mitgelieferte Konfiguration setzt es für `Updates` und `PendingReboot`. Ist das Skript auch im Katalog eine `System`-Aktion, gilt zuerst der Katalogeintrag. Setzen Sie `Block` dann auch dort. |

**So läuft eine Reparatur:** Der Nutzer bestätigt. Der Dienst prüft das Skript gegen
die geschützte Liste der Reparaturen (oder den Katalog der System-Aktionen) und führt
es als SYSTEM mit Zeitlimit und Protokoll aus. Pfade, Argumente oder Skripte des
Nutzers werden nie angenommen. Reparaturskripte brauchen keinen Eintrag im Katalog.
Jeder angemeldete Nutzer kann die freigegebenen Reparaturen anfordern.

Das Fenster erlaubt nur eine Reparatur zur selben Zeit. Danach prüft es nur den
reparierten Status erneut. Angezeigt wird das Ergebnis dieser Prüfung, nicht der
Exitcode des Skripts. Eine Reparatur mit Exit `0` kann deshalb einen roten Status
hinterlassen. Ist die Prüfung oder der Dienst nicht verfügbar, ist das Ergebnis
*Unbekannt*.

Reparaturen müssen ohne Nutzerinteraktion laufen. Sie dürfen nie abmelden, neu
starten, herunterfahren, in den Energiesparmodus wechseln oder losgelöste Prozesse
starten. Das gilt auch für `PendingReboot`: Die erneute Prüfung zeigt nur, ob noch ein
Neustart aussteht. Prüfen, verteilen und signieren Sie Reparaturskripte als
Administrator.

**Mitgelieferte Reparaturen:**

*Defender-Signaturen* (`SelfX_Defender_UpdateSignature.ps1`): Führt `Update-MpSignature`
als SYSTEM aus, mit den Update-Quellen der Defender-Richtlinie. Aktiv für Defender und
Compliance, jeweils nur solange die Zeile nicht in Ordnung ist:

```xml
<Remediation Id="Defender" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
<Remediation Id="Compliance" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
```

Um das Update auch bei einer Defender-Zeile in Ordnung anzubieten, entfernen Sie
`When="NotOK"`. Es braucht eine erreichbare Update-Quelle. Offline endet es mit Exit
`1` und der Status bleibt. Entfernen Sie die Zeilen, um es zu deaktivieren.

*Updates* (`SelfX_Updates_Install.ps1`):

```xml
<Remediation Id="Updates" Script="SelfX_Updates_Install.ps1" When="NotOK" TimeoutSeconds="7200" />
```

Solange Updates ausstehen, bietet die Zeile *Zu installierende Updates* die Schaltfläche
*Beheben*. Währenddessen zeigt sie *Läuft…*. Danach meldet SelfX, dass Windows Update
fertig ist, und prüft den ganzen Gerätestatus erneut. Das Skript läuft als SYSTEM:

1. Es startet den Update-Scan für Microsoft-Store-Apps über die MDM-Bridge
   (`MDM_EnterpriseModernAppManagement_AppManagement01.UpdateScanMethod`). Das
   funktioniert auch, wenn der Store für Nutzer gesperrt ist. Der Store aktualisiert
   die Apps danach im Hintergrund.
2. Es startet „Nach Updates suchen“ des Windows-Update-Orchestrators über die
   dokumentierte WinRT-API `Windows.Management.Update.WindowsUpdateManager`
   (`StartScan(userInitiated: true)`, dasselbe wie die Schaltfläche in den
   Einstellungen). Windows lädt und installiert die Updates selbst, nach den
   Richtlinien des Geräts. *Einstellungen > Windows Update* zeigt den Fortschritt. Das
   Skript wartet höchstens 90 Minuten, bis nichts mehr geladen oder installiert wird,
   und protokolliert jedes Update mit Aktion, Fortschritt und Wartegrund, zum Beispiel
   `2026-11 Security Update (KB5132061): action Install, progress Install 70`. Updates,
   die nur noch auf den Neustart warten (`ReadyToReboot`), gelten als erledigt.
   Feature-Updates (neue Windows-Version) überlässt das Skript der Update-Richtlinie.

Das Skript startet Windows **nie** neu. Braucht ein Update einen Neustart, zeigt ihn die
Zeile *Neustart ausstehend*. Exit `0`: alle Updates installiert oder nichts zu tun.
Exit `1`: Suche, Download oder Installation ist bei mindestens einem Update
fehlgeschlagen (die KB-Nummern stehen im Protokoll), der Orchestrator arbeitet nach 90
Minuten noch, oder die WinRT-Komponente `WinRT\SelfXWinRT.dll` fehlt (dann bitte SelfX
neu installieren; es gibt keinen anderen Update-Weg). Ein Store-Scan, der sich nicht
starten lässt (zum Beispiel ohne MDM-Bridge), wird protokolliert, lässt die Reparatur
aber nicht fehlschlagen. Das Protokoll liegt in
`%ProgramData%\SelfX\Logs\SelfX_Updates_Install_<Datum>.log`. Entfernen Sie die Zeile,
um die Reparatur zu deaktivieren.

*Neustart* (`SelfX_Device_Restart.ps1`):

```xml
<Remediation Id="PendingReboot" Script="SelfX_Device_Restart.ps1" When="NotOK" />
```

Die Zeile *Neustart ausstehend* bietet *Jetzt neu starten* an. SelfX zeigt eine eigene
Warnung: Windows startet etwa 30 Sekunden nach der Bestätigung neu, der Nutzer soll
seine Arbeit speichern und alle Programme schließen. Nach der Bestätigung führt der
Dienst `shutdown.exe /r /t 30 /d p:4:1` als SYSTEM aus. Der Neustart ist **nie** Teil
von *Alle Probleme beheben*. Entfernen Sie die Zeile, um die Schaltfläche
auszublenden.

*App-Wiederholung* (`SelfX_Apps_RetryInstall.ps1`):

```xml
<Remediation Id="Applications" Script="SelfX_Apps_RetryInstall.ps1" When="NotOK" TimeoutSeconds="300" />
```

Die Zeile *Unternehmens-Apps (Intune)* bietet *Erneut versuchen* an, solange eine
App-Installation fehlgeschlagen ist. Die Intune Management Extension wiederholt eine
fehlgeschlagene Win32-App sonst erst nach ihrem Wiederholungsplan (standardmäßig 24
Stunden). Das Skript entfernt für jede App mit Fehler im lokalen IME-Zwischenspeicher
das zwischengespeicherte Ergebnis und die Einträge des Wiederholungsplans (GRS) und
startet den Dienst `IntuneManagementExtension` neu. Die IME meldet sich danach bei
Intune und installiert die App innerhalb weniger Minuten erneut. Der Nutzer sieht den
Fortschritt im Unternehmensportal. Es wird keine App deinstalliert. Geändert wird nur
der IME-Zwischenspeicher unter `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps`.
Schlägt die Installation erneut fehl, liegt das Problem in der App oder ihrer
Zuweisung. Der Nutzer kann dann die Geräteprotokolle an den Support senden, und der
Support sieht den Fehlercode in Intune.

### Branding

Firmenlogo, Symbol und Farben stehen im Abschnitt `Branding` von `Tool_Config.xml`.
Kopieren Sie die Bilder vor dem Bau des Pakets nach `SelfX Service\Sources` oder in
einen Unterordner wie `Sources\Branding`. Pfade gelten relativ zum Installationsordner.
Alle Schlüssel sind optional. Ist ein Wert leer oder ungültig oder fehlt die Datei,
gilt der Standard.

Die mitgelieferte `Tool_Config.xml` enthält Platzhalter: das Logo
`Branding\company_logo.png` („YOUR LOGO“), das Blau des SelfX-Logos (`#0072BC`) und die
Kontakte `Mon-Fri 08:00-17:00`, `+1 555 0100`, `support@example.com` und
`https://support.example.com`. Ersetzen Sie sie vor dem Bau des Pakets durch Ihre
Werte oder leeren Sie sie, um sie auszublenden.

| Schlüssel | Standard | Bedeutung |
|---|---|---|
| `Brand_Logo` | leer (kein Logo) | Logo oben in der Navigation und im Info-Dialog. PNG, JPG, BMP, GIF oder ICO, in der Navigation höchstens 196 Pixel breit. Ein transparentes PNG passt zu beiden Designs am besten. Ist es leer, zeigt der Info-Dialog `About_Logo`. |
| `Brand_Logo_Height` | `40` | Höhe in der Navigation in Pixeln (16 bis 120). Die Breite wird passend skaliert. |
| `Brand_Icon` | `Repair.ico` | Symbol von Fenster, Taskleiste und Statussymbol. Eine `.ico`-Datei verwendet `Install.ps1` auch für Verknüpfungen und den Eintrag unter Apps & Features. SelfX hat eine eigene Taskleistenschaltfläche (AppUserModelID `SelfX.SelfService`) mit diesem Symbol. Ein angeheftetes SelfX startet `SelfX.exe`. Nehmen Sie eine `.ico` mit 256 × 256 Pixeln für ein scharfes Symbol. |
| `Brand_Accent_Color` | leer (nutzt `Tool_Color`) | Firmenfarbe als `#RRGGBB` für Schaltflächen, Auswahl, Markierung der Navigation, Links und Symbole. Die Textfarbe (weiß oder schwarz) wird automatisch gewählt. Sehr dunkle oder sehr helle Farben werden für Text und Symbole angepasst, damit sie in beiden Designs lesbar bleiben. |
| `Brand_TitleBar_Color` | Fensterhintergrund | Hintergrund der Titelleiste als `#RRGGBB`. Die Textfarbe wird automatisch gewählt. |
| `Brand_Run_Button_Color` | Akzentfarbe | Start-Schaltflächen (Play) und *Beheben*. |
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

**Design:** `Tool_Theme` (`Auto`, `Dark`, `Light`) legt das Standarddesign fest. Der
Standard ist `Auto`, auch bei fehlendem oder unbekanntem Wert. `Auto` folgt dem
App-Modus von Windows (`AppsUseLightTheme` in
`HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`, hell, wenn der
Wert fehlt) und reagiert auf Änderungen, während SelfX offen ist. Ist
`Show_Theme_Button` `True`, kann jeder Nutzer im Einstellungsdialog *Automatisch*,
*Dunkel* oder *Hell* wählen. Die Wahl steht in `HKCU\Software\SelfX\Theme` und hat
Vorrang vor `Tool_Theme`. Die Branding-Farben gelten in beiden Designs. `Tool_Color`
akzeptiert die früheren MahApps-Farbnamen (`Cyan`, `Teal`, `Blue` ...). SelfX Service
verwendet MahApps.Metro nicht mehr und lädt dafür nichts aus dem Netzwerk.

### Sprachen

Die Basissprache ist Deutsch. Mit `Tool_Language` = `Auto` folgt SelfX der
Anzeigesprache von Windows. Nutzer können unter *Einstellungen* (Zahnrad) selbst eine
Sprache wählen. Die Texte stehen in `Sources\Languages\<Kultur>.xml`:

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

Englisch ist die Referenz für die Schlüssel und der Rückfall. Die anderen Sprachen
wurden maschinell übersetzt. Lassen Sie sie vor einem Rollout von Muttersprachlern
prüfen.

**Welche Sprache gilt?** SelfX prüft der Reihe nach:

1. Die Wahl des Nutzers (gespeichert in `HKCU\Software\SelfX\Language`). *Automatisch*
   bedeutet: weiter mit Schritt 2. Die Wahl wird ignoriert, wenn `Show_Language_Setting`
   `False` ist, wenn der Wert kein Kulturname ist oder wenn die Sprachdatei fehlt.
   Nach einem Wechsel startet SelfX auf derselben Seite neu, das Statussymbol folgt.
   Läuft noch eine Reparatur, gilt die neue Sprache beim nächsten Öffnen.
2. `Tool_Language` in `Tool_Config.xml`.
3. Die Kultur und ihre übergeordneten Kulturen. `de-CH` nutzt `de.xml`, `pt-BR` nutzt
   `pt.xml`, `zh-CN` nutzt `zh-Hans.xml`, `zh-TW` nutzt `zh-Hant.xml`. Schweizerdeutsch
   (`gsw`) nutzt `de.xml`.
4. Passt keine Datei, gilt `de.xml`.

Fehlt ein Text in der gewählten Sprache, erscheint er auf Englisch (`en.xml`).
Katalogtexte fallen auf den englischen Basistext in `Issues_List.xml` zurück. Eine
Beschriftung bleibt also nie leer.

**Aufbau einer Sprachdatei:**

| Abschnitt | Inhalt |
|---|---|
| `UI` | Texte von Fenster, Dialogen, Kurzinfos, Meldungsleiste, Gerätestatus, Systeminformationen und Statussymbol. `{0}`, `{1}` sind Platzhalter, zum Beispiel für den Aktionsnamen. |
| `SystemInfo` | Beschriftungen und Werte der Systeminformationen und der Statusprüfungen |
| `Catalog/Categories` | Anzeigenamen der Kategorien |
| `Catalog/Messages`, `Catalog/Actions` | Gemeinsame Meldungen sowie `Name`, `Explanation` und `Alerte_MSG` je Aktions-`Id`. Felder mit `Ref` übernehmen die übersetzte Meldung. |

**Sprache hinzufügen:**

1. Kopieren Sie `en.xml` (oder eine vollständige Übersetzung wie `de.xml`) nach
   `<Kultur>.xml`. Nehmen Sie den neutralen Kulturnamen, zum Beispiel `cs.xml`, damit
   alle regionalen Varianten die Datei nutzen.
2. Setzen Sie `Culture`, `Name` und `NativeName` am Wurzelelement. Für Schriften von
   rechts nach links setzen Sie `FlowDirection="RightToLeft"`.
3. Übersetzen Sie die Texte. Behalten Sie Elementnamen, Ids und Platzhalter bei, und
   das Muster `|*.txt|` in `SystemInfo_Export_Filter`.
4. Prüfen Sie die Datei und bauen Sie dann das Paket:

   ```powershell
   & '.\SelfX Service\Test-LanguageFiles.ps1' -Culture cs
   ```

   Die Prüfung meldet fehlende oder unbekannte Schlüssel, defekte Platzhalter und
   Katalogeinträge, die es nicht gibt. Ohne `-Culture` prüft sie alle Dateien.

Dafür ist keine Codeänderung nötig. Um einen Text für Ihr Unternehmen zu ändern, zum
Beispiel den Haupttitel, bearbeiten Sie ihn in den Sprachdateien.

## Änderungen sicher ausliefern

1. Sichern Sie die aktuellen XML-Dateien und Skripte.
2. Prüfen Sie, dass das XML wohlgeformt bleibt.
3. Prüfen Sie, dass jedes verwendete Skript im Paket existiert.
4. Testen Sie Aktionen und Bestätigungstexte auf einem Testgerät.
5. Liefern Sie Änderungen nur als neue Paketversion aus (Intune-Paket, siehe
   [Installation](Installation.md#intune-paket-erstellen)). SelfX lädt keine
   Konfiguration aus dem Netzwerk nach.
