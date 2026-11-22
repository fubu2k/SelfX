# Sicherheitsrichtlinie

[English](SECURITY.en.md) | **Deutsch**

SelfX Service führt einen Windows-Dienst als LOCAL SYSTEM aus und nimmt über eine
lokale Named Pipe Anfragen jedes angemeldeten Nutzers entgegen. Eine Schwachstelle
kann deshalb auf jedem verwalteten Gerät zu einer Rechteausweitung führen. Bitte
melden Sie sie vertraulich.

## Schwachstelle melden

- Nutzen Sie das **private Melden von Sicherheitslücken auf GitHub** in diesem
  Repository (Reiter *Security*, *Report a vulnerability*).
- Öffnen Sie **kein** öffentliches Issue und keinen Pull Request zu einer
  Schwachstelle, bevor ein Fix verfügbar ist.
- Geben Sie die Version aus dem Skript- oder Quelltext-Kopf, den Windows-Build, den
  Ausführungskontext (Nutzer, Administrator, SYSTEM, Intune-Bereitstellung) und die
  Schritte zur Reproduktion an.
- Fügen Sie keine Token, Kennwörter, Geräteprotokolle mit personenbezogenen Daten
  oder internen Hostnamen bei.

Sie erhalten innerhalb von 14 Tagen eine Antwort. Fixes entstehen auf einem Branch
`security/...` und werden über einen Pull Request gemergt; die Versionshinweise
nennen den Befund, sobald eine korrigierte Version verfügbar ist.

## Geltungsbereich

Im Geltungsbereich, mit Priorität:

- **SelfX Service**: `SelfXService.cs` und sein Pipe-Protokoll, der Aktionskatalog
  (`Issues_List.xml`, `Health_Config.xml`), jedes Skript, das mit
  `Context : System` läuft, `Install.ps1`, `Uninstall.ps1`, `Detection.ps1`,
  Datei- und Ordnerberechtigungen unter `%ProgramFiles%\SelfX` und
  `%ProgramData%\SelfX`.
- `tools/New-SelfXIntuneWin.ps1` (Paketierung).

Außerhalb des Geltungsbereichs: Schwachstellen, die vorher Administratorrechte auf
dem Gerät voraussetzen, und Binärdateien von Drittanbietern (melden Sie diese dem
jeweiligen Hersteller).
