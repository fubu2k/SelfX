# SelfX Benutzerhandbuch

[English](en/User-Manual.md) | **Deutsch**

SelfX ist eine Selbsthilfe-Oberfläche für ausgewählte Fehlerbehebungen. Welche
Aktionen verfügbar sind, hängt vom XML-Katalog ab, den Ihr Support-Team
konfiguriert hat.

## SelfX

SelfX hilft Ihnen, häufige Probleme auf Ihrem Gerät selbst zu lösen. Es ist auf
Ihrem Gerät installiert und funktioniert auch ohne Netzwerkverbindung.

Starten Sie **SelfX (Self fix)** über den Desktop, das Startmenü oder das
SelfX-Symbol neben der Uhr. Die Größe des Fensters lässt sich ändern, es kann
maximiert werden; SelfX merkt sich die Größe. Ist SelfX schon geöffnet, kommt es
in den Vordergrund.

Die Leiste links hat drei Bereiche:

| Bereich | Was Sie dort finden |
|---|---|
| **Fehlerbehebung** | Lösungen für häufige Probleme |
| **Gerätestatus** | Prüfungen Ihres Geräts, zum Beispiel Speicherplatz oder Updates. Die Zahl zeigt, wie viele Punkte Ihre Aufmerksamkeit brauchen. |
| **Systeminformationen** | Informationen über Ihr Gerät für das Support-Team |

Bewegen Sie die Maus über eine Schaltfläche, um zu sehen, was sie macht. Ohne Ihre
Bestätigung geschieht nichts.

### Ein Problem lösen

1. Öffnen Sie **Fehlerbehebung**.
2. Geben Sie ein Wort in das Suchfeld ein (zum Beispiel *Teams* oder *langsam*)
   oder klicken Sie auf eine Kategorie.
3. Klicken Sie auf die Schaltfläche **i**, um mehr über eine Lösung zu lesen.
4. Klicken Sie auf die runde Schaltfläche **Start**, lesen Sie die Meldung und
   bestätigen Sie.

Solange eine Lösung läuft, wird ihre Start-Schaltfläche zu einem rotierenden Pfeil
und daneben steht **Läuft…**; dieselbe Lösung können Sie nicht ein zweites Mal
starten. Sobald sie fertig ist, ist die Schaltfläche wieder ein Startknopf, und die
Meldungsleiste unten zeigt, ob es geklappt hat. Die Schaltfläche **Beheben** auf der
Seite **Gerätestatus** zeigt dasselbe, solange ihre Reparatur läuft.

Mit **Vereinfachte Ansicht** erhalten Sie eine kurze Liste nach Produkt, mit
**Detaillierte Ansicht** die einzelnen Probleme. Die Schaltfläche **?** daneben
erklärt den Unterschied.

Lösungen mit einem **Schild** brauchen Administratorrechte. SelfX führt sie für Sie
über den lokalen SelfX-Dienst aus, Sie brauchen also kein Administratorkonto. Es
kann nur eine Lösung mit Schild gleichzeitig laufen.

Ist an demselben Gerät eine andere Person angemeldet (zum Beispiel an einem
gemeinsam genutzten PC oder in einer Remotesitzung), führt SelfX keine Lösungen
aus, die diese Person stören würden, etwa den Neustart des Geräts, die Installation
von Updates, die Datenträgerprüfung oder den Neustart der Netzwerkadapter. SelfX
weist Sie darauf hin. Versuchen Sie es erneut, wenn Sie allein angemeldet sind,
oder fragen Sie Ihr Support-Team.

Unten links sehen Sie, ob der SelfX-Dienst läuft (grüner Punkt). Läuft er nicht
(roter Punkt), sind Lösungen mit Schild und der Gerätestatus nicht verfügbar.
Starten Sie Ihr Gerät neu oder wenden Sie sich an Ihr Support-Team.

### Gerätestatus

Der Bereich **Gerätestatus** zeigt eine Karte pro Prüfung: Windows-Verwaltung
(IME), Microsoft Defender, Compliance, Anwendungen, Speicherplatz, BitLocker,
ausstehender Neustart und zu installierende Updates. Ihr Support-Team kann weitere
Prüfungen ergänzen. Probleme stehen zuerst.

- **Grün / In Ordnung:** Alles ist gut.
- **Gelb / Ausstehend:** Bald sollte etwas getan werden, zum Beispiel
  Updates installieren. Das ist eine Warnung, kein Fehler.
- **Rot / Fehler:** Es gibt ein Problem. Lesen Sie den Text auf der Karte.
- **Grau / Unbekannt:** SelfX kann es nicht sagen, zum Beispiel weil die
  Information nicht verfügbar ist. Das bedeutet nicht, dass alles in Ordnung ist.

Der Status wird automatisch im Hintergrund geprüft (meist alle 15 Minuten, nicht
im Akkubetrieb) und deshalb sofort angezeigt. Die Zeile unter dem Titel zeigt, wann
zuletzt geprüft wurde.

- **Beheben** (Schraubenschlüssel): Repariert das Problem automatisch. Speichern
  Sie Ihre Arbeit, klicken Sie auf die Schaltfläche und bestätigen Sie. Danach
  prüft SelfX diesen Status erneut. Die Schaltfläche erscheint nur dort, wo Ihr
  Support-Team eine Reparatur vorbereitet hat, zum Beispiel bei **Microsoft
  Defender** (aktualisiert die Virendefinitionen), bei **Compliance**, solange Ihr
  Gerät nicht konform ist, und bei **Zu installierende Updates**: SelfX sucht,
  lädt und installiert die Updates. Das kann einige Minuten dauern; die
  Schaltfläche zeigt **Läuft…**, bis sie fertig ist, und Sie können weiterarbeiten.
  Danach prüft SelfX den Gerätestatus erneut; ist ein Neustart nötig, zeigt ihn die
  Karte **Neustart ausstehend**.
- **Jetzt neu starten** bei **Neustart ausstehend**: Startet das Gerät neu, um
  Updates und Änderungen abzuschließen. SelfX fragt vorher. Speichern Sie Ihre
  Arbeit und schließen Sie alle Programme; der Neustart beginnt etwa 30 Sekunden
  nach Ihrer Bestätigung. **Abbrechen** ändert nichts. *Alle Probleme beheben*
  startet das Gerät nie neu.
- **Erneut versuchen** bei **Unternehmens-Apps (Intune)**: Eine App Ihres
  Unternehmens konnte nicht installiert werden (die Karte zeigt ihren Namen).
  SelfX startet die Installation sofort neu, statt bis zum nächsten Tag zu warten;
  verfolgen Sie sie im **Unternehmensportal**. Schlägt sie erneut fehl, liegt die
  Ursache in der App oder ihrer Verteilung: Senden Sie die Protokolle an den
  Support (Schaltfläche **Protokolle an Support senden**).
- **Pfeile** auf einer Karte: Prüfen nur diesen Status erneut, zum Beispiel nachdem
  Sie selbst etwas behoben haben. Auf Ihrem Gerät wird nichts verändert.
- **Pfeile** oben: Prüfen alles erneut. Das kann bis zu einer Minute dauern.
- **Alle Probleme beheben**: Erscheint oben, wenn mindestens ein Problem
  automatisch repariert werden kann. Nachdem Sie die Liste bestätigt haben, führt
  SelfX die Reparaturen nacheinander aus und prüft dann alles erneut. Speichern Sie
  vorher Ihre Arbeit.

Alle Zeiten (zum Beispiel *zuletzt geprüft* oder das letzte Defender-Update) werden
in der Zeitzone Ihres Geräts angezeigt, auch direkt nach einer Änderung der
Zeitzone, zum Beispiel bei der Ersteinrichtung eines neuen Geräts.

Beispiele: **Neustart ausstehend (rot)**: Klicken Sie auf **Jetzt neu starten**
oder starten Sie das Gerät selbst neu. **Zu installierende Updates (gelb)**:
Klicken Sie auf **Beheben**, installieren Sie sie in den **Einstellungen** >
**Windows Update** oder warten Sie auf die automatische Installation.

SelfX protokolliert auf Ihrem Gerät, was es tut (zum Beispiel welche Aktion Sie
gestartet haben und mit welchem Ergebnis), damit Ihr Support-Team ein Problem
nachvollziehen kann. Die Protokolle enthalten keine Kennwörter und werden nach 90
Tagen automatisch gelöscht.

### Systeminformationen

Der Bereich **Systeminformationen** zeigt Angaben zu Ihrem Gerät, nach denen das
Support-Team oft fragt: Gerät, Windows, Nutzer und Verwaltung, Netzwerk. Die
zuletzt bekannten Werte erscheinen sofort und werden im Hintergrund aktualisiert.

- Doppelklicken Sie auf eine Zeile, um ihren Wert zu kopieren.
- Die Schaltflächen oben aktualisieren die Informationen, kopieren alles (zum
  Beispiel, um es in eine Support-Anfrage einzufügen) oder speichern es als Datei.
- Die **Werkzeuge** unter den Informationen synchronisieren Ihre Intune-Apps,
  prüfen die Compliance, öffnen das Unternehmensportal, starten Quick Assist (eine
  Support-Person kann Ihren Bildschirm sehen, nur mit Ihrer Zustimmung), sammeln
  die Protokolle der Geräteverwaltung oder senden die Geräteprotokolle an den
  Support.

Die Informationen enthalten Ihren Gerätenamen, Ihren Benutzernamen und
Netzwerkadressen. Geben Sie sie nur an Ihr Support-Team weiter.

### Geräteprotokolle an den Support senden

Wenn das Support-Team die Protokolle Ihres Geräts anfordert, klicken Sie auf
**Protokolle an Support senden** (unten links, in den Systeminformationen oder im
Menü des SelfX-Symbols neben der Uhr).

1. Bestätigen Sie. SelfX sammelt die Protokolle mit Administratorrechten über den
   lokalen SelfX-Dienst; Sie brauchen kein Administratorkonto. Das kann einige
   Minuten dauern. Auf Ihrem Gerät wird nichts verändert.
2. Sind die Protokolle fertig, öffnet sich eine neue E-Mail an den Support mit dem
   Bericht im Anhang (eine `.zip`-Datei). Er enthält auch die Protokolle von SelfX
   selbst (was SelfX auf Ihrem Gerät getan hat und Ihre eigenen SelfX-Aktionen),
   sodass der Support sehen kann, welche Lösungen Sie schon versucht haben.
3. Beschreiben Sie Ihr Problem in der E-Mail und senden Sie sie ab. SelfX sendet
   nie von selbst etwas.

Lässt sich Outlook nicht automatisch öffnen (zum Beispiel beim neuen Outlook),
öffnet SelfX eine neue E-Mail in Ihrer Standard-Mail-App und ein Explorer-Fenster
mit dem markierten Bericht. Hängen Sie diese Datei an die E-Mail an. Der Bericht
enthält den Namen Ihres Geräts, Ihren Benutzernamen und die Protokolle des Geräts.
Auf dem Gerät können nur Sie und die Administratoren ihn lesen. Senden Sie ihn nur
an Ihr Support-Team.

### Hilfe, Einstellungen und das SelfX-Symbol

- **?** (oben rechts): So erreichen Sie Ihr Support-Team, zum Beispiel
  Servicezeiten, Telefonnummer, E-Mail, Teams-Chat oder Website / Ticketsystem.
  Schaltflächen starten eine E-Mail, einen Teams-Chat oder öffnen die Website.
- **Zahnrad**: Wählen Sie die Sprache von SelfX, das Erscheinungsbild
  (*Automatisch*, die Voreinstellung, nutzt den dunklen oder hellen Modus von
  Windows, oder immer *Dunkel* oder *Hell*), zeigen oder verbergen Sie das
  SelfX-Symbol neben der Uhr und schalten Sie die Benachrichtigungen über Probleme
  ein oder aus.
- **i**: Version von SelfX.

Das **SelfX-Symbol** neben der Uhr zeigt den Gerätestatus auf einen Blick: ein
grüner, gelber oder roter Punkt (grau = noch nicht bekannt). Bewegen Sie die Maus
darüber, um eine Zusammenfassung zu sehen. Wird ein Problem gefunden, zum Beispiel
wenig Speicherplatz, zeigt Windows einmal eine Benachrichtigung; klicken Sie
darauf, um den Gerätestatus zu öffnen. Möchten Sie diese Benachrichtigungen nicht,
schalten Sie **Benachrichtigungen über Probleme anzeigen** mit dem Zahnrad oder
**Benachrichtigungen anzeigen** im Menü des Symbols aus; das farbige Symbol zeigt
den Status weiterhin. Mit einem Rechtsklick auf das Symbol öffnen Sie SelfX,
prüfen den Status jetzt, senden die Protokolle an den Support oder verbergen das
Symbol. Mit dem Zahnrad in SelfX können Sie es wieder anzeigen.

SelfX erscheint standardmäßig auf Deutsch. Um eine andere Sprache zu nutzen,
klicken Sie auf das **Zahnrad** und wählen Ihre Sprache unter **Sprache**. Die
Sprachen stehen unter ihrem eigenen Namen, zum Beispiel *Deutsch* oder
*français*. SelfX startet in der gewählten Sprache neu und merkt sich Ihre Wahl.
Das SelfX-Symbol neben der Uhr verwendet sie ebenfalls. **Automatisch** wechselt
zur Sprache von Windows; ist sie nicht verfügbar, erscheint SelfX auf Deutsch.
Texte, die es in Ihrer Sprache nicht gibt, erscheinen auf Englisch. Ihr
Support-Team kann die Auswahl ausblenden und eine feste Sprache vorgeben.

## Wichtige Hinweise

- Speichern Sie offene Dokumente vor Aktionen, die Anwendungen neu starten oder
  beenden.
- Die Aktion OneDrive-CHKDSK führt `chkdsk /r /f` auf dem Systemlaufwerk aus. Sie
  wird für den nächsten Neustart geplant; starten Sie das Gerät danach neu. Die
  Prüfung kann lange dauern.
- Die Aktion für Netzwerkadapter unterbricht die Netzwerkverbindung, während die
  Adapter neu starten.
- Die Aktion zur Gerätebereinigung leert den Papierkorb und entfernt Dateien aus
  dem temporären Ordner des aktuellen Nutzers.
- Wenden Sie sich an Ihr Support-Team, wenn eine Aktion fehlschlägt oder das
  Problem bleibt.
