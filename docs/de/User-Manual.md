# SelfX Benutzerhandbuch

[English](../User-Manual.md) | **Deutsch**

SelfX hilft Ihnen, häufige Probleme an Ihrem Computer selbst zu lösen. Bevor Sie das
Support-Team anrufen oder schreiben, können Sie es hier versuchen. Welche Lösungen zur
Verfügung stehen, legt Ihr Support-Team fest.

![Seite Fehlerbehebung im hellen Design](../images/selfx-troubleshooting-light.png)

## Inhalt

1. [SelfX öffnen](#selfx-öffnen)
2. [Die Oberfläche](#die-oberfläche)
3. [Ein Problem lösen](#ein-problem-lösen)
4. [Gerätestatus](#gerätestatus)
5. [Systeminformationen](#systeminformationen)
6. [Support anfragen und Protokolle senden](#support-anfragen-und-protokolle-senden)
7. [Das SelfX-Symbol neben der Uhr](#das-selfx-symbol-neben-der-uhr)
8. [Einstellungen: Sprache und Design](#einstellungen-sprache-und-design)
9. [Wichtige Hinweise](#wichtige-hinweise)

## SelfX öffnen

Starten Sie **SelfX** über das Symbol auf dem Desktop, über das Startmenü oder über das
SelfX-Symbol neben der Uhr. Sie brauchen dafür keine Administratorrechte.

Das Fenster lässt sich in der Größe ändern und maximieren. SelfX merkt sich die Größe.
Ist SelfX schon geöffnet, kommt das Fenster nach vorn.

## Die Oberfläche

Die Leiste links hat drei Bereiche:

| Bereich | Was Sie dort finden |
|---|---|
| **Fehlerbehebung** | Lösungen für häufige Probleme |
| **Gerätestatus** | Prüfungen Ihres Geräts, zum Beispiel Speicherplatz oder Updates. Die Zahl zeigt, wie viele Punkte Ihre Aufmerksamkeit brauchen. |
| **Systeminformationen** | Angaben zu Ihrem Gerät, die das Support-Team oft braucht |

Ist das Firmen-Wiki eingeschaltet, zeigt die Leiste außerdem die Schaltfläche **Firmen-Wiki**. Sie öffnet das Wiki Ihres Unternehmens im Webbrowser.

SelfX hat ein **neues Design**: ruhige Farben, große Schaltflächen und einen Hinweis oben,
der die Schritte zeigt: **Problem auswählen – Bestätigen – Fertig**. Es gibt ein helles und
ein dunkles Design. Standardmäßig folgt SelfX Windows.

Bewegen Sie die Maus über eine Schaltfläche, um zu sehen, was sie tut. **Ohne Ihre
Bestätigung geschieht nichts.**

## Ein Problem lösen

1. Öffnen Sie **Fehlerbehebung**.
2. Geben Sie ein Wort in das Suchfeld ein, zum Beispiel *Teams* oder *langsam*. Oder klicken Sie
   auf eine Kategorie.
3. Klicken Sie auf **i**, um zu lesen, was die Lösung macht.
4. Klicken Sie auf **Start**, lesen Sie die Meldung und bestätigen Sie.

Während eine Lösung läuft, zeigt ihre Schaltfläche einen drehenden Pfeil und **Läuft…**. Dieselbe
Lösung können Sie in dieser Zeit nicht noch einmal starten. Danach zeigt die Meldungsleiste unten,
ob es geklappt hat.

Mit **Vereinfachte Ansicht** sehen Sie eine kurze Liste. Mit **Detaillierte Ansicht** sehen Sie
alle einzelnen Probleme. Die Schaltfläche **?** erklärt den Unterschied.

**Lösungen für Konto und Anmeldung:** Sie öffnen nur eine Webseite und ändern nichts auf Ihrem Gerät.

- **Passwort vergessen oder abgelaufen:** öffnet die Seite, auf der Sie Ihr Kennwort selbst zurücksetzen.
- **Anmeldemethoden verwalten:** öffnet die Sicherheitsinformationen Ihres Kontos, zum Beispiel für eine neue Telefonnummer oder eine neue Authenticator-App.

**Neu in Version 3.0 (Beispiele):**

- **Citrix Workspace reagiert nicht oder zeigt keine Anwendungen:** startet die Citrix-Workspace-App Ihres Benutzerkontos neu. Bereits geöffnete Anwendungen und Desktops werden nicht beendet.
- **Ein Programmfenster liegt außerhalb des Bildschirms:** holt Fenster Ihres Benutzers, die nach dem Abstecken eines Monitors nicht mehr sichtbar sind, auf den Hauptbildschirm. Nichts wird geschlossen.
- **Excel öffnet alle Dateien im selben Fenster:** startet eine zweite, unabhängige Excel-Instanz, damit Sie zwei Arbeitsmappen auf zwei Bildschirmen vergleichen können. Nichts wird geschlossen oder geändert.

**Lösungen mit einem Schild** brauchen Administratorrechte. SelfX führt sie über seinen lokalen
Dienst aus, Sie brauchen also kein Administratorkonto. Es läuft immer nur eine solche Lösung.

**Wenn eine andere Person am selben Gerät angemeldet ist** (zum Beispiel an einem gemeinsam
genutzten PC), führt SelfX keine Lösungen aus, die diese Person stören würden. Dazu gehören der
Neustart, Updates, die Festplattenprüfung und der Neustart der Netzwerkadapter. SelfX sagt Ihnen
dann Bescheid. Versuchen Sie es später noch einmal oder fragen Sie das Support-Team.

**Unten links** sehen Sie, ob der SelfX-Dienst läuft (grüner Punkt). Bei einem roten Punkt sind
Lösungen mit Schild und der Gerätestatus nicht verfügbar. Starten Sie Ihren Computer neu oder
wenden Sie sich an das Support-Team.

## Gerätestatus

Der Bereich **Gerätestatus** zeigt eine Karte für jede Prüfung. Dazu gehören zum Beispiel die
Verwaltung durch das Unternehmen, Microsoft Defender, die Compliance, Apps, der Speicherplatz,
BitLocker, ein ausstehender Neustart und Updates. Probleme stehen oben.

| Farbe | Bedeutung |
|---|---|
| Grün (**In Ordnung**) | Alles ist gut. |
| Gelb (**Bald erledigen**) | Bald sollte etwas getan werden, zum Beispiel Updates. Das ist eine Warnung, kein Fehler. |
| Rot (**Fehler**) | Es gibt ein Problem. Der Text auf der Karte sagt, was. |
| Grau (**Unbekannt**) | SelfX kann es nicht sagen. Das heißt **nicht**, dass alles in Ordnung ist. |

SelfX prüft den Status im Hintergrund, meist alle 15 Minuten. Im Akkubetrieb pausiert die
Prüfung. Die Zeile unter dem Titel zeigt, wann zuletzt geprüft wurde.

**Was die Schaltflächen auf den Karten tun:**

- **Beheben** (Schraubenschlüssel): Repariert das Problem automatisch. Speichern Sie vorher Ihre
  Arbeit, bestätigen Sie und warten Sie. Das kann einige Minuten dauern. Danach prüft SelfX den
  Status erneut. Die Schaltfläche gibt es nur, wenn Ihr Support-Team eine Reparatur vorbereitet
  hat. Zum Beispiel bei **Zu installierende Updates**: SelfX sucht, lädt und installiert Updates.
- **Jetzt neu starten** (bei **Neustart ausstehend**): Startet den Computer neu, damit Updates
  fertig werden. Speichern Sie vorher Ihre Arbeit und schließen Sie alle Programme. Nach Ihrer
  Bestätigung beginnt der Neustart nach etwa 30 Sekunden. **Abbrechen** ändert nichts. *Alle
  Probleme beheben* startet den Computer **nie** neu.
- **Erneut versuchen** (bei **Unternehmens-Apps**): Eine App Ihres Unternehmens konnte nicht
  installiert werden. SelfX startet die Installation sofort neu. Den Fortschritt sehen Sie im
  Unternehmensportal. Schlägt sie wieder fehl, senden Sie die Protokolle an den Support.
  Bei bekannten Fehlercodes sagt die Karte in einem Satz, was schiefging und was Sie tun können
  (zum Beispiel das Gerät neu starten oder Speicherplatz freigeben).
- **Pfeil** auf einer Karte: Prüft nur diesen Status erneut. Oben: prüft alles erneut.
- **Alle Probleme beheben**: Führt alle möglichen Reparaturen nacheinander aus. Speichern Sie
  vorher Ihre Arbeit.

**Beispiele:**

- **Neustart ausstehend (rot):** Klicken Sie auf **Jetzt neu starten** oder starten Sie den
  Computer selbst neu.
- **Zu installierende Updates (gelb):** Klicken Sie auf **Beheben**. Oder installieren Sie Updates
  unter **Einstellungen > Windows Update**.

## Systeminformationen

Der Bereich **Systeminformationen** zeigt Angaben über Gerät, Windows, Nutzer, Verwaltung und
Netzwerk. Die letzten Werte stehen sofort da und werden im Hintergrund aktualisiert.

- **Doppelklick** auf eine Zeile kopiert den Wert.
- Die Schaltflächen oben aktualisieren die Angaben, kopieren alles oder speichern es als Datei.
- Unter den Angaben finden Sie **Werkzeuge**:
  - Intune synchronisieren: die Verwaltung des Geräts neu abgleichen.
  - Compliance prüfen.
  - Das Unternehmensportal öffnen.
  - **Fernwartung**: Startet **Remote Help**, wenn es auf Ihrem Gerät installiert ist. Sonst startet
    es Quick Assist. Eine Person vom Support kann dann Ihren Bildschirm sehen, aber nur mit Ihrer
    Zustimmung.
  - Die Protokolle der Geräteverwaltung sammeln.
  - Die Geräteprotokolle an den Support senden.

Ist die Citrix-Workspace-App installiert, steht ihre Version unter **Gerät**.

Die Angaben enthalten Gerätename, Benutzername und Netzwerkadressen. Geben Sie sie nur an Ihr
Support-Team weiter.

## Support anfragen und Protokolle senden

SelfX bietet zwei Wege, das Support-Team zu erreichen.

**Kontakt anzeigen:** Klicken Sie oben rechts auf **?**. Dort stehen Servicezeiten, Telefonnummer,
E-Mail-Adresse, Teams-Adresse und Website. Schaltflächen öffnen direkt eine E-Mail, einen Teams-Chat
oder die Website.

**Problem melden (Ticket per E-Mail):** Ist diese Funktion eingeschaltet, zeigt der Hilfe-Dialog die
Zeile **Problem melden**. So geht es:

1. Klicken Sie auf **Ticket erstellen** und beschreiben Sie das Problem.
2. SelfX fügt die Angaben zu Ihrem Gerät automatisch hinzu. Das können Sie nicht abwählen.
3. Sie sehen die E-Mail vor dem Senden. Der Empfänger steht im Dialog.
4. Sie senden die E-Mail selbst. **SelfX sendet nie von selbst.**

Öffnet sich Ihr E-Mail-Programm nicht mit der Datei, markiert SelfX die Datei im Explorer. Hängen
Sie sie dann selbst an.

**Copilot Chat fragen:** Ist diese Funktion eingeschaltet, zeigt der Hilfe-Dialog **Copilot Chat
fragen**:

1. Beschreiben Sie das Problem mit eigenen Worten (optional) und klicken Sie auf **Text erstellen**.
2. Sie sehen eine Vorschau. Lesen oder ändern Sie den Text.
3. Klicken Sie auf **Kopieren und Copilot öffnen**. Fügen Sie den Text in Copilot Chat ein (Strg+V)
   und senden Sie ihn selbst ab.

Der Text enthält keine Namen, E-Mail-Adressen oder IP-Adressen. Prüfen Sie ihn trotzdem vor dem
Senden. Schreiben Sie keine Passwörter oder Kundendaten hinein. Der Text bleibt nach dem Kopieren
kurz in der Zwischenablage. Ist die Funktion so eingestellt, leert SelfX sie nach einigen Minuten.

**Geräteprotokolle an den Support senden:** Klicken Sie unten links, in den Systeminformationen oder im
Menü des SelfX-Symbols auf **Protokolle an Support senden**.

1. Bestätigen Sie. SelfX sammelt die Protokolle über seinen Dienst. Das dauert einige Minuten.
   Auf Ihrem Gerät wird nichts verändert.
2. Danach öffnet sich eine E-Mail an den Support mit dem Bericht als `.zip`-Datei im Anhang. Der
   Bericht enthält auch die Protokolle von SelfX, damit der Support sieht, was Sie schon versucht haben.
3. Beschreiben Sie Ihr Problem und senden Sie die E-Mail ab.

Der Bericht enthält Gerätename, Benutzername und Protokolle. Nur Sie und Administratoren können ihn auf
dem Gerät lesen. Senden Sie ihn nur an Ihr Support-Team.

## Das SelfX-Symbol neben der Uhr

Das Symbol neben der Uhr zeigt den Gerätestatus auf einen Blick:

- **grün**: alles in Ordnung
- **gelb**: Warnung
- **rot**: Problem
- **grau**: noch kein Ergebnis

Bewegen Sie die Maus darüber, um eine Zusammenfassung zu sehen. Das Symbol bleibt unter Windows 11
dauerhaft neben der Uhr. Es verschwindet also nicht im Überlaufmenü (Pfeil).

Wird ein Problem gefunden, zeigt Windows einmal eine Benachrichtigung. Ein Klick darauf öffnet den
Gerätestatus. Möchten Sie keine Benachrichtigungen, schalten Sie sie mit dem **Zahnrad** oder im Menü
des Symbols aus. Das farbige Symbol zeigt den Status trotzdem.

**Rechtsklick auf das Symbol:** SelfX öffnen, Status jetzt prüfen, Protokolle senden oder das Symbol
verbergen. Wieder anzeigen können Sie es über das Zahnrad in SelfX.

## Einstellungen: Sprache und Design

Klicken Sie auf das **Zahnrad** in SelfX:

- **Sprache:** Wählen Sie Ihre Sprache. Jede Sprache steht unter ihrem eigenen Namen, zum Beispiel
  *Deutsch* oder *français*. SelfX startet danach neu und merkt sich die Wahl. Auch das Symbol neben
  der Uhr nutzt die neue Sprache. **Automatisch** nimmt die Sprache von Windows. Ist sie nicht
  verfügbar, zeigt SelfX Deutsch. Texte, die es in Ihrer Sprache nicht gibt, erscheinen auf Englisch.
  Manche Unternehmen legen die Sprache fest. Dann fehlt diese Auswahl.
- **Design:** *Automatisch* folgt Windows, *Dunkel* und *Hell* stellen Sie fest ein.
- **Symbol neben der Uhr** anzeigen oder verbergen.
- **Benachrichtigungen über Probleme** ein- oder ausschalten.

Unter **i** finden Sie die Version von SelfX.

## Wichtige Hinweise

- **Speichern Sie Ihre Arbeit**, bevor Sie eine Lösung starten. Manche Lösungen starten Programme neu
  oder beenden sie. Neustarts betreffen alle offenen Programme.
- **Festplattenprüfung (chkdsk):** Die Prüfung wird für den nächsten Neustart geplant. Sie kann lange
  dauern. Starten Sie den Computer danach neu.
- **Netzwerk-Neustart:** Während die Netzwerkadapter neu starten, ist die Verbindung kurz unterbrochen.
- **Speicher aufräumen:** Löscht temporäre Dateien und leert den Papierkorb Ihres Benutzers.
- **Zeit korrigieren:** Gleicht die Uhr Ihres Geräts mit der Zeitquelle ab.
- **Datenschutz:** SelfX sendet nichts von selbst. Protokolle, Berichte und Texte gehen nur an Ihr
  Support-Team, wenn Sie es bestätigen. Protokolle enthalten keine Passwörter. Sie werden nach 90 Tagen
  automatisch gelöscht.
- Wenden Sie sich an Ihr Support-Team, wenn eine Lösung fehlschlägt oder das Problem bleibt.
