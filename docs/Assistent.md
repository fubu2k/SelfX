# Paketassistent (geführte Konfiguration)

[English](en/Guided-Setup.md) | **Deutsch**

Der Assistent `tools\New-SelfXPackage.ps1` führt Sie mit Fragen durch die Einstellungen von SelfX
und baut daraus das Intune-Paket. Zu jeder Frage zeigt er eine **Empfehlung**. Am Ende erklärt er in
Kurzform, was Sie in Intune tun müssen. Er läuft auf dem Build-Rechner, in Windows PowerShell 5.1 und
PowerShell 7, ohne Passwort und ohne Netzwerkzugriff (außer beim Bau der Programme).

## Aufruf

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXPackage.ps1
```

Voraussetzungen wie in der [Installationsanleitung](Installation.md#voraussetzungen): .NET SDK 10
(nur zum Bau der Programme) und `IntuneWinAppUtil.exe`. Der Assistent fragt nach dem Pfad der Datei.

Wichtige Parameter:

| Parameter | Bedeutung |
|---|---|
| `-Language de` | Sprache des Assistenten (`de`, `en`). Ohne Angabe fragt er; vorgewählt ist die Windows-Sprache. |
| `-AnswerFile <Datei>` | Verwendet gespeicherte Antworten, stellt keine Fragen (für Updates und Automatisierung). |
| `-OutputFolder <Ordner>` | Standard: `build\SelfX-Guided`. |
| `-ToolPath <Datei>` | Pfad von `IntuneWinAppUtil.exe`. |
| `-BuildBinaries` | Baut den Ordner `Bin`, wenn er fehlt. |
| `-ConfigureOnly` | Schreibt nur Konfiguration, Skripte und Anleitung; es wird nichts gebaut. |

## Die Fragen

1. **Grundlagen:** Standardsprache, Sprachwahl durch Nutzer, Name der Organisation, Name des Werkzeugs.
2. **Support-Kontakte:** Funktionspostfach, Telefon, Servicezeiten, Webseite, Teams.
3. **Branding:** Logo (wird kopiert) und Firmenfarbe.
4. **Ticket per E-Mail:** Ticket-Funktion an oder aus, Standard-Empfänger, Betreff-Kennzeichen.
   Müssen **andere Organisationen oder Standorte** an andere Postfächer gehen, legen Sie je Postfach
   eine **Einheit** an. Dafür fragt der Assistent nach
   - **Hybrid-Join:** dann ordnet SelfX nach dem **OU-Namen** zu (zum Beispiel `OU=Berlin`),
   - **Autopilot-Group-Tag (Entra ID):** die zuverlässigste Zuordnung für reine Cloud-Geräte,
   - **Geräteklasse** (zum Beispiel Notebook, Desktop, Tablet), wenn ein anderes Team Tablets oder
     Kiosk-PCs betreut.

   SelfX läuft nur unter Windows 11. **Smartphones (iOS, Android) kann SelfX nicht abdecken.**
   Die Regeln stehen in dieser Reihenfolge in `Ticket_Config.xml`: zuerst Group Tags, dann OUs,
   dann Geräteklassen; die erste passende Regel gewinnt.
5. **Copilot Chat:** nur anbieten, wenn Sie es lizenziert haben; Zielgruppe der Antwort, Zwischenablage leeren.
6. **Verhalten auf dem Gerät:** Statussymbol, Verknüpfungen. Im Expertenmodus: Protokoll-Aufbewahrung,
   Dateiprüfung (`Enforce` oder `Audit`) und Rechte des Dienstes. Ohne Expertenmodus bleiben die sicheren Standardwerte.
7. **Bau:** Ausgabeordner und Pfad von `IntuneWinAppUtil.exe`.

Jede Eingabe wird geprüft (Adressen, https-Links, Farben, Längen, Zeichen). Eine ungültige Eingabe
wird sofort abgelehnt. Die Werte werden als Text in die XML-Dateien geschrieben und dabei maskiert.

## Ergebnis

Im Ausgabeordner:

| Datei | Wofür |
|---|---|
| `SelfX-Service-<Version>.intunewin` | Das Paket für Intune. |
| `SelfX-Service-<Version>.Detection.ps1` | Das Erkennungsskript. Laden Sie **diese** Datei hoch. |
| `Set-SelfXSupportUnit-*.ps1` | Plattformskripte für die Ticket-Zuordnung (je Einheit, Group Tag und Geräteklasse). Einheiten, die nur nach OU zugeordnet werden, brauchen keins. |
| `SelfX-Intune-Guide.<Sprache>.txt` | Kurzanleitung für Intune. |
| `selfx-answers.json` | Ihre Antworten für den nächsten Lauf. **Enthält Postfachadressen: nicht in Git einchecken.** |
| `package\` | Das konfigurierte Paket (Eingabe der Paketierung). |

Die Dateien im Repository werden **nicht** verändert. Für ein Update erhöhen Sie `Tool_Version` und
`$ExpectedVersion` und starten den Assistenten mit `-AnswerFile`.

## Was Sie in Intune tun

Die Kurzanleitung steht am Ende des Laufs und in `SelfX-Intune-Guide.<Sprache>.txt`. Die Einzelheiten
stehen in der [Installationsanleitung](Installation.md#schritt-3-in-intune-einrichten).

## Weitere Sprache für den Assistenten

Kopieren Sie `tools\Wizard\Wizard.en.xml` nach `Wizard.<Kultur>.xml`, setzen Sie `Culture` und `Name` und
übersetzen Sie die Texte. Fehlende Texte erscheinen auf Englisch.
`tools\Test-SelfXPackageWizard.ps1` prüft Ids und Platzhalter.
