# Hinweise zu Urheberschaft und Lizenzen

Stand: 22.11.2026. Dieses Repository ist ein Fork von SelfX (nur das Paket SelfX Service). Die Lizenzdatei
[LICENSE.md](LICENSE.md) enthält den Text und die ursprüngliche Copyright-Zeile des ursprünglichen Projekts (MIT-Lizenz) unverändert,
ergänzt um die Copyright-Zeile für die Änderungen in diesem Fork. Dieser Hinweis ergänzt sie, ersetzt sie aber nicht.

## Herkunft

| Teil | Urheber / Quelle | Lizenz |
|------|------------------|--------|
| SelfX (Idee, WPF-Oberfläche, XML-Aktionskatalog, Skripte zur Fehlerbehebung) | Damien Van Robaeys, [damienvanrobaeys/SelfX](https://github.com/damienvanrobaeys/SelfX), vorgestellt auf [Syst & Deploy (August 2022)](https://www.systanddeploy.com/2022/08/selfx-tool-allowing-users-to-solve.html) | MIT laut seinem Repository (`LICENSE.md`, hinzugefügt am 21.05.2024). Der Blogbeitrag nennt keine Lizenz. |
| SelfX Service (Dienst, Installer, Health-Prüfungen, Tests, Doku) | Wolfgang Baeck, [wbaeck/SelfX](https://github.com/wbaeck/SelfX), Fork von damienvanrobaeys/SelfX | Sein README verweist auf die Lizenz des Originalprojekts in `LICENSE.md`; eine eigene Lizenzdatei für seine Ergänzungen gibt es dort nicht. |
| Änderungen in diesem Fork (Sicherheitshärtung, .NET-10-Dienst, PowerShell-7-Umstellung, Tests, CI, Doku) | fubu2k, mit Unterstützung von Claude Code (Anthropic) | Copyright (c) 2026 fubu2k, lizenziert unter der MIT-Lizenz (Text in [LICENSE.md](LICENSE.md)). |

## Weitere Quellen

- **System Information Tool** von Jannik Reinhard
  ([JayRHa/windows-system-information](https://github.com/JayRHa/windows-system-information), MIT-Lizenz,
  Copyright (c) 2026 Jannik Reinhard): Idee und Datenpunkte der Seite „Systeminformationen“.
  Ein Vergleich am 22.11.2026 (Stand seines Repositorys: Commit `00c5220`, 14.10.2026) ergab keinen übernommenen
  Programmcode: keine identischen Funktionsnamen, keine identischen fachlichen Codezeilen (nur allgemeine
  Schlüsselwörter und XAML-Rahmen) und keine Übernahme seiner Skripte. Gleich sind nur öffentliche Windows-Datenquellen
  (zum Beispiel die Klassen `Win32_ComputerSystem` und `Win32_OperatingSystem`, der Registrypfad der MDM-Konten und das
  `intunemanagementextension://`-Protokoll). Die Nennung erfolgt als Quellenangabe, nicht weil sie die MIT-Lizenz hier
  verlangt. Wird künftig Code von dort übernommen, muss sein MIT-Hinweis vollständig hierher.
- **Microsoft Win32 Content Prep Tool**: gehört nicht zu diesem Repository. `tools\New-SelfXIntuneWin.ps1` lädt es nicht
  mit, prüft aber vor der Verwendung die Authenticode-Signatur von Microsoft.
- **Gebaute Programme** (Dienst und Starter, .NET 10 self-contained) enthalten Teile der Microsoft-.NET-Laufzeit und das
  NuGet-Paket `System.ServiceProcess.ServiceController` (beide Microsoft, MIT-Lizenz).

## Haftungsausschluss

Die Software wird so bereitgestellt, wie sie ist, ohne jede ausdrückliche oder stillschweigende Gewährleistung, unter
anderem ohne Gewähr für Marktgängigkeit, Eignung für einen bestimmten Zweck, Freiheit von Mängeln und Fehlern oder
Nichtverletzung von Rechten Dritter. Die Autoren und Rechteinhaber haften nicht für Ansprüche, Schäden oder sonstige
Haftung, die aus der Software oder ihrer Nutzung entstehen. SelfX Service läuft mit SYSTEM-Rechten und ändert
Einstellungen auf dem Gerät: Prüfen und testen Sie jede Version vor dem Einsatz in Ihrer Umgebung.

Verbindlich ist der englische Wortlaut der MIT-Lizenz:

> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
> WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
> COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
> ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
