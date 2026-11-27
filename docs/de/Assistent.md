# Paketassistent (geführte Konfiguration)

[English](../Guided-Setup.md) | **Deutsch**

Der Assistent `tools\New-SelfXPackage.ps1` führt Sie mit Fragen durch die Einstellungen von SelfX
und baut daraus das Intune-Paket. Zu jeder Frage zeigt er eine **Empfehlung**. Am Ende erklärt er in
Kurzform, was Sie in Intune tun müssen. Er läuft auf dem Build-Rechner, in Windows PowerShell 5.1 und
PowerShell 7 und braucht keinen Netzwerkzugriff. Ein Kennwort fragt er nur ab, wenn Sie mit einer PFX-Datei signieren (siehe
[Signieren](#paket-signieren-vertrauensmodus-signatur)).

Nach der letzten Antwort baut der Assistent alles **in einem Lauf, ohne weitere Fragen**: Er prüft die Dateien, schreibt Ihre
Einstellungen und das Logo, signiert (optional), verpackt, schreibt das Erkennungsskript, die AppLocker- und App-Control-Dateien, die
Skripte für Intune und die Anleitung. Das Ergebnis ersetzt den Ausgabeordner erst, wenn jeder Schritt gelungen ist: Ein Fehler
hinterlässt keinen halb fertigen Ordner, und ein früheres Ergebnis bleibt unverändert. Derselbe Lauf steht anderen Programmen als
Funktion `Invoke-SelfXPackageBuild` zur Verfügung (`tools\Wizard\SelfXWizard.ps1`): Antworten, Nutzlast-Ordner, Ausgabeordner,
Werkzeugpfad, optionales Zertifikat und ein Rückruf für den Fortschritt.

## Aufruf

Am besten starten Sie mit dem **Nutzlast-Archiv** eines Release (`SelfX-Service-<Version>-payload.zip`, siehe
[Installationsanleitung](Installation.md#schritt-2-paket-bauen)). Entpacken Sie es in einen leeren Ordner und starten Sie den Assistenten
von dort; das .NET SDK ist **nicht** nötig, denn das Archiv enthält die Programme. Die Dateien werden zuerst gegen
`App\SelfX.Code.json` geprüft: Eine geänderte oder hinzugefügte Datei beendet den Lauf.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXPackage.ps1
```

Im Repository arbeitet der Assistent mit dem Paketordner `SelfX Service` und braucht den Ordner `Bin` (`-BuildBinaries` baut ihn, mit
dem .NET SDK 10). Außerdem brauchen Sie `IntuneWinAppUtil.exe`. Die Datei laden Sie von Microsoft herunter:
<https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool> (Datei `IntuneWinAppUtil.exe` im Repository, am besten
vom neuesten Release-Tag). Der Assistent fragt nach dem Pfad der Datei und prüft die Microsoft-Signatur.

Wichtige Parameter:

| Parameter | Bedeutung |
|---|---|
| `-Language de` | Sprache des Assistenten (`de`, `en`). Ohne Angabe fragt der Assistent zuerst auf Englisch; Englisch ist vorgewählt, die anderen Sprachen stehen in einer Nummernliste. |
| `-AnswerFile <Datei>` | Verwendet gespeicherte Antworten, stellt keine Fragen (für Updates und Automatisierung). |
| `-OutputFolder <Ordner>` | Standard: `build\SelfX-Guided` im Repository, `SelfX-Guided` neben dem entpackten Nutzlast-Archiv. Der Ordner muss neu, leer oder das Ergebnis eines früheren Laufs sein. |
| `-ToolPath <Datei>` | Pfad von `IntuneWinAppUtil.exe`. |
| `-PayloadFolder <Ordner>` | Ein Ordner im Aufbau des entpackten Nutzlast-Archivs. Standard: das entpackte Archiv, das `tools` enthält, sonst das Repository. |
| `-BuildBinaries` | Nur im Repository: baut den Ordner `Bin`, wenn er fehlt. |
| `-ConfigureOnly` | Schreibt nur Konfiguration, Skripte und Anleitung; es wird nichts verpackt oder signiert. |
| `-CertificateThumbprint <Fingerabdruck>` | Vertrauensmodus Signatur: signiert mit diesem Codesignatur-Zertifikat aus dem Zertifikatspeicher. |
| `-PfxPath <Datei>` | Vertrauensmodus Signatur: signiert mit einer PFX-Datei. Der Assistent fragt das Kennwort ab (verdeckt, wird nie gespeichert). |
| `-TimestampServer <Adresse>` | Zeitstempeldienst (`http` oder `https`) für die Signaturen. Empfohlen. |

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
5. **Copilot Chat und Firmen-Wiki:** Copilot nur anbieten, wenn Sie es lizenziert haben; Zielgruppe der
   Antwort, Zwischenablage leeren. Optional eine Wiki-Schaltfläche mit `https://`-Adresse und Namen.
6. **Verhalten auf dem Gerät:** Statussymbol, Verknüpfungen. Im Expertenmodus: Protokoll-Aufbewahrung,
   Dateiprüfung (`Enforce` oder `Audit`) und Rechte des Dienstes. Ohne Expertenmodus bleiben die sicheren Standardwerte.
7. **AppLocker und App Control:** ob AppLocker-Regeln erzeugt werden (Standard ja) und, wenn Sie App Control for Business (WDAC)
   einsetzen, die ID Ihrer Basisrichtlinie. Ohne ID entsteht keine App-Control-Datei. Die Regelskripte brauchen Windows PowerShell 5.1;
   AppLocker zusätzlich die AppLocker-Cmdlets, App Control das Modul ConfigCI. Fehlen sie, endet der Lauf mit einem klaren Text:
   Antworten Sie *nein* oder erzeugen Sie die Dateien auf einem anderen PC (`tools\New-SelfXAppLockerRules.ps1`,
   `tools\New-SelfXWdacPolicy.ps1`).
8. **Bau:** Ausgabeordner und Pfad von `IntuneWinAppUtil.exe`.

Jede Eingabe wird geprüft (Adressen, https-Links, Farben, Längen, Zeichen). Eine ungültige Eingabe
wird sofort abgelehnt. Die Werte werden als Text in die XML-Dateien geschrieben und dabei maskiert. Das Logo muss eine `png`-, `jpg`- oder
`ico`-Datei von höchstens 2 MB sein; der Assistent prüft die **ersten Bytes der Datei**, nicht nur die Endung, und speichert sie als
`logo.<Typ>`. Die Antworten enthalten nie ein Kennwort oder einen Schlüssel: Ein Name, der keine Frage ist, wird abgelehnt.

## Paket signieren (Vertrauensmodus Signatur)

Ohne Zertifikat entsteht das Paket im Vertrauensmodus **Hash** (keine Signatur; `SelfX.Code.json` ist die Datei des Release). Mit
`-CertificateThumbprint` oder `-PfxPath` baut der Assistent ein **signiertes** Paket in der Reihenfolge, die die Dateilisten verlangen: Er
signiert jedes Programm und jedes Skript, schreibt `Bin\SelfX.Binaries.json` und `App\SelfX.Code.json` mit den neuen Hashes neu, erzeugt
den signierten Katalog `SelfX.Code.cat` über alles außerhalb von `Config` und schreibt danach `Config\SelfX.Config.json` und den
signierten Katalog `Config\SelfX.Config.cat`. Auch das Erkennungsskript für Intune wird signiert, die AppLocker-Regeln sind je
Regelsammlung eine Herausgeberregel, und die Anleitung zeigt den Installationsbefehl mit `-TrustedSigner <Fingerabdruck>`. Einzelheiten
und den Weg zurück: [Einmal einrichten statt je Version](Installation.md#einmal-einrichten-statt-je-version).

Ein signierter Lauf braucht ein Zertifikat, das für Codesignatur gültig ist, einen privaten Schlüssel hat und auf dem Build-PC als
vertrauenswürdig gilt. Das Kennwort einer PFX-Datei wird als sichere Zeichenfolge gelesen, einmal benutzt und nie in eine Datei, ein
Protokoll, `selfx-answers.json` oder eine Fehlermeldung geschrieben. Schützen Sie das Zertifikat: Wer es hat, kann Dateien signieren, die
SelfX annimmt.

## Ergebnis

Im Ausgabeordner:

| Datei | Wofür |
|---|---|
| `SelfX-Service-<Version>.intunewin` | Das Paket für Intune. |
| `SelfX-Service-<Version>.Detection.ps1` | Das Erkennungsskript. Laden Sie **diese** Datei hoch. |
| `Set-SelfXSupportUnit-*.ps1` | Plattformskripte für die Ticket-Zuordnung (je Einheit, Group Tag und Geräteklasse). Einheiten, die nur nach OU zugeordnet werden, brauchen keins. |
| `SelfX-Intune-Guide.<Sprache>.txt` | Kurzanleitung für Intune. |
| `selfx-answers.json` | Ihre Antworten für den nächsten Lauf. **Enthält Postfachadressen: nicht in Git einchecken.** |
| `SelfX.AppLocker.xml` | AppLocker-Regeln (Hash-Regeln, bei einem signierten Paket eine Herausgeberregel). Nur bei der Antwort *ja*. |
| `AppControl\` | Die ergänzende App-Control-Richtlinie (WDAC) als `.xml` und `.cip`. Nur mit einer ID der Basisrichtlinie. |
| `package\` | Das konfigurierte Paket (Eingabe der Paketierung). |

Die Nutzlast und die Dateien im Repository werden **nicht** verändert. Für ein Update entpacken Sie das Nutzlast-Archiv des neuen Release
und starten den Assistenten mit `-AnswerFile`. Im Vertrauensmodus Hash ist `App\SelfX.Code.json` im Ergebnis Lauf für Lauf die Datei der
Nutzlast.

## Was Sie in Intune tun

Die Kurzanleitung steht am Ende des Laufs und in `SelfX-Intune-Guide.<Sprache>.txt`. Die Einzelheiten
stehen in der [Installationsanleitung](Installation.md#schritt-3-in-intune-einrichten). Der Schritt vor dem Test behandelt auch die
Defender-ASR-Regel für ausführbare Dateien (blockierte SelfX-Datei finden, höchstens vier Dateien ausschließen):
[Defender ASR: Regel für ausführbare Dateien](Installation.md#defender-asr-regel-für-ausführbare-dateien).

## Weitere Sprache für den Assistenten

Kopieren Sie `tools\Wizard\Wizard.en.xml` nach `Wizard.<Kultur>.xml`, setzen Sie `Culture` und `Name` und
übersetzen Sie die Texte. Fehlende Texte erscheinen auf Englisch.
`tools\Test-SelfXPackageWizard.ps1` prüft Ids und Platzhalter.
