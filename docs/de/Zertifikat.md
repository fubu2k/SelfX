# Codesignatur-Zertifikat für SelfX

[English](../Certificate-Guide.md) | **Deutsch**

Mit einem Codesignatur-Zertifikat Ihrer Organisation signiert der Paketassistent jedes Programm,
jedes Skript und die beiden Kataloge des SelfX-Pakets (Vertrauensmodus **Signatur**). Die Geräte
nehmen dann nur Dateien an, die mit Ihrem Zertifikat signiert sind, und AppLocker und App Control
brauchen **eine** Herausgeberregel, die für jede Version gleich bleibt, statt neuer Hash-Regeln je
Version ([Installation](Installation.md#einmal-einrichten-statt-je-version)).

Diese Anleitung ist für das Team, das die PKI betreibt, und für den Administrator, der das Paket
baut. Ohne Zertifikat funktioniert SelfX ebenfalls (Vertrauensmodus **Hash**).

## Inhalt

- [Was das Zertifikat braucht](#was-das-zertifikat-braucht)
- [Bei einer internen PKI anfordern (AD CS)](#bei-einer-internen-pki-anfordern-ad-cs)
- [Den Geräten das Vertrauen geben](#den-geräten-das-vertrauen-geben)
- [Mit dem Paketassistenten signieren](#mit-dem-paketassistenten-signieren)
- [Ablauf und Wechsel des Zertifikats](#ablauf-und-wechsel-des-zertifikats)
- [Quellen](#quellen)

## Was das Zertifikat braucht

| Eigenschaft | Anforderung |
|---|---|
| Verwendungszweck | Erweiterte Schlüsselverwendung **Codesignatur** (`1.3.6.1.5.5.7.3.3`); Schlüsselverwendung **Digitale Signatur** |
| Privater Schlüssel | Auf dem PC, der das Paket baut (Zertifikatspeicher des Benutzers oder des Computers, Smartcard), oder in einer PFX-Datei |
| Algorithmus | RSA mit 2048 Bit oder mehr, Signatur-Hash SHA-256 |
| Antragsteller | Der Name Ihrer Organisation, mit `O=` (AppLocker zeigt ihn als Herausgeber) |
| Sperrliste | Eine **öffentliche HTTP-Adresse an erster Stelle** der Sperrlisten-Verteilungspunkte |
| Gültigkeit | Nach den Regeln Ihrer PKI, zum Beispiel ein bis drei Jahre |

Warum die HTTP-Adresse wichtig ist: Windows fragt beim Prüfen einer Signatur die Sperrliste ab, die
im Zertifikat steht. Geräte außerhalb des Firmennetzes (bei Intune der Normalfall) erreichen
`ldap://`- oder `file://`-Adressen und interne Namen nicht. `Install.ps1` behandelt die Signatur dann
als gültig (Standard von Windows); ein gesperrtes Zertifikat wird nur dort bemerkt, wo die Liste
erreichbar ist. Der Assistent zeigt die Adressen des gewählten Zertifikats und warnt, wenn keine
HTTP-Adresse dabei ist oder nur interne Namen vorkommen.

Schützen Sie den Schlüssel: Wer damit signieren kann, bekommt Dateien über Ihre Herausgeberregeln
erlaubt. Nutzen Sie eine Smartcard, ein HSM oder einen einzigen, eingeschränkten Signatur-PC, und
erlauben Sie den Export des Schlüssels nur, wenn Sie eine PFX-Datei brauchen.

## Bei einer internen PKI anfordern (AD CS)

Eine Unternehmenszertifizierungsstelle der Active Directory-Zertifikatdienste hat die
Zertifikatvorlage **Codesignatur** („Code Signing“, zum digitalen Signieren von Software,
Antragstellertyp Benutzer). Das PKI-Team:

1. Dupliziert die Vorlage **Codesignatur** unter einem neuen Namen (das Original nicht ändern), zum
   Beispiel „SelfX Codesignatur“.
2. Beschränkt **Registrieren** auf eine kleine Gruppe von Paket-Administratoren und verlangt nach
   Möglichkeit die Genehmigung durch einen Zertifikatverwalter.
3. Legt Schlüssellänge (RSA 2048 oder mehr), SHA-256, Gültigkeit und die Exportierbarkeit des
   Schlüssels fest.
4. Prüft, dass die Zertifizierungsstelle eine öffentliche HTTP-Adresse für die Sperrliste an erster
   Stelle nennt.
5. Veröffentlicht die Vorlage auf der Zertifizierungsstelle.

Der Paket-Administrator fordert das Zertifikat dann auf dem Signatur-PC an: `certmgr.msc` →
**Eigene Zertifikate** → **Zertifikate** → **Alle Aufgaben** → **Neues Zertifikat anfordern**, Vorlage
wählen, registrieren. Auf der Registerkarte **Details** den Verwendungszweck prüfen, unter
**Zertifizierungspfad** die Kette.

Ein Zertifikat einer öffentlichen Zertifizierungsstelle funktioniert genauso; seiner Kette vertraut
Windows bereits.

## Den Geräten das Vertrauen geben

SelfX vergleicht den Fingerabdruck des Signierers mit der Liste aus `-TrustedSigner` der
Installation, **und** Windows muss die Signatur anerkennen: Der Kette des Zertifikats muss auf jedem
Gerät vertraut werden, bevor SelfX installiert wird (auch während Autopilot).

- **Stamm- und Zwischenzertifikat Ihrer Zertifizierungsstelle:** Geräte einer Domäne vertrauen
  ihnen oft schon (Gruppenrichtlinie). Sonst verteilen Sie sie mit Intune: **Geräte** →
  **Konfiguration** → **Erstellen** → Plattform **Windows 10 und höher** → **Vorlagen** →
  **Vertrauenswürdiges Zertifikat**. Das Stammzertifikat als DER-codierte `.cer`-Datei (ohne privaten
  Schlüssel) hochladen, Zielspeicher **Computerzertifikatspeicher – Stamm**; ein zweites Profil mit
  dem Zwischenzertifikat und dem Ziel **Computerzertifikatspeicher – Zwischenzertifizierungsstellen**.
  Beide denselben Geräten wie SelfX zuweisen. Das Profil liefert nur Stamm- und
  Zwischenzertifikate, nicht das Signaturzertifikat selbst.
- **Signaturzertifikat unter „Vertrauenswürdige Herausgeber“:** SelfX braucht das **nicht**;
  `Install.ps1` und der Dienst prüfen den Fingerabdruck selbst. Nötig ist es nur, wenn Ihre eigenen
  Richtlinien es verlangen (zum Beispiel eine Ausführungsrichtlinie `AllSigned` für PowerShell).
  Intune kann es mit einem benutzerdefinierten Profil (OMA-URI) des RootCATrustedCertificates-CSP
  schreiben: `./Device/Vendor/MSFT/RootCATrustedCertificates/TrustedPublisher/<SHA1-Fingerabdruck>/EncodedCertificate`,
  Wert: das Zertifikat als Base64-Text ohne Zeilenumbrüche. Mit SelfX nicht ausprobiert.

## Mit dem Paketassistenten signieren

Fenster (`tools\Start-SelfXPackageWizard.cmd`), Seite **Signatur**:

- **Zertifikat aus dem Speicher:** Die Liste zeigt nur Zertifikate mit privatem Schlüssel,
  Verwendungszweck Codesignatur und gültigem Zeitraum aus den Speichern Ihres Benutzers und des
  Computers. Abgelaufene Zertifikate werden nicht angeboten.
- **Zertifikatsdatei (PFX):** Datei wählen und Kennwort eingeben. Die Datei wird nur im
  Arbeitsspeicher geöffnet (nicht importiert); das Kennwort wird einmal verwendet, danach wird das
  Feld geleert. Das Kennwort wird nie angezeigt, gespeichert, protokolliert oder in
  `selfx-answers.json` geschrieben.
- **Zeitstempeldienst (erforderlich):** die Adresse des Zeitstempeldienstes des Anbieters Ihres
  Zertifikats oder Ihrer PKI. Signieren ohne Zeitstempel muss ausdrücklich eingeschaltet werden und
  ist nur für Tests gedacht.
- **Weitere erlaubte Signierer:** nur für einen Zertifikatswechsel (unten).

Konsole: `tools\New-SelfXPackage.ps1 -CertificateThumbprint <Fingerabdruck>` oder `-PfxPath <Datei>`
(das Kennwort wird verdeckt abgefragt), `-TimestampServer <Adresse>`, `-AdditionalSigner <Fingerabdruck>`
([Paketassistent](Assistent.md)).

Die Ergebnisseite zeigt die Schritte für Intune mit Kopieren-Schaltflächen; der Installationsbefehl
enthält `-TrustedSigner` mit dem oder den Fingerabdrücken.

## Ablauf und Wechsel des Zertifikats

**Mit Zeitstempel** bleibt eine Signatur gültig, nachdem das Zertifikat abgelaufen ist. **Ohne**
Zeitstempel werden die Signaturen am Tag des Ablaufs ungültig: `Install.ps1` lehnt das Paket ab, und
der Dienst startet nichts mehr (Ereignis 4007, Grund `Expired`; er bemerkt das spätestens nach
60 Minuten, auch bei unveränderten Dateien).

Geräte nehmen nur die Signierer an, die in `-TrustedSigner` ihrer letzten Installation stehen
(höchstens 10 Fingerabdrücke). Wechseln Sie das Zertifikat in drei Schritten:

1. **Neues Zertifikat ankündigen.** Paket noch mit dem **alten** Zertifikat neu bauen und den
   Fingerabdruck des **neuen** unter „Weitere erlaubte Signierer“ eintragen (Konsole:
   `-AdditionalSigner`). Als neue Version hochladen und warten, bis alle Geräte es haben.
2. **Umstellen.** Mit dem **neuen** Zertifikat bauen; der alte Fingerabdruck darf eine Weile als
   zusätzlicher Signierer bleiben.
3. **Aufräumen.** Später ohne den alten Fingerabdruck bauen.

AppLocker und App Control: Ein verlängertes Zertifikat mit **gleichem Antragsteller** braucht keine
neuen Regeln. Bei anderem Antragsteller die Herausgeberregeln neu erstellen und vor dem ersten Paket
mit dem neuen Zertifikat verteilen (während des Wechsels werden beide Regeln gebraucht; App Control:
`-AllowMultipleSigners`), siehe [Einmal einrichten statt je Version](Installation.md#einmal-einrichten-statt-je-version).

Gesperrtes Zertifikat (Schlüssel verloren oder gestohlen): bei der Zertifizierungsstelle sperren, ein
neues anfordern und die drei Schritte ohne Wartezeit dazwischen ausführen. Geräte, die die Sperrliste
erreichen, lehnen die alten Signaturen ab (Ereignis 4007, Grund `Revoked`).

Auf keinem Gerät ausprobiert: das Intune-Profil für „Vertrauenswürdige Herausgeber“, ein gesperrtes
Zertifikat auf einem Gerät und ein signiertes Paket aus dem Fenster mit einem echten
`IntuneWinAppUtil.exe`.

## Quellen

- Microsoft Learn: [Certificate templates concepts (AD CS)](https://learn.microsoft.com/windows-server/identity/ad-cs/certificate-template-concepts),
  [Manage AD CS certificate templates](https://learn.microsoft.com/windows-server/identity/ad-cs/manage-certificate-templates)
- Microsoft Learn: [Create a code signing certificate for App Control for Business](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/deployment/create-code-signing-cert-for-appcontrol)
- Microsoft Learn: [Trusted root certificate profiles for Microsoft Intune](https://learn.microsoft.com/intune/device-configuration/certificates/trusted-root-profiles)
- Microsoft Learn: [RootCATrustedCertificates CSP](https://learn.microsoft.com/windows/client-management/mdm/rootcacertificates-csp)
- Microsoft Learn: [Time stamping Authenticode signatures](https://learn.microsoft.com/windows/win32/seccrypto/time-stamping-authenticode-signatures)
