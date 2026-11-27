<#
.SYNOPSIS
    Tests the text overrides of the company (Config\Texts\<culture>.xml, Sources\Localization.ps1).

.DESCRIPTION
    Dot-sources Localization.ps1 and SelfXPaths.ps1 (functions only) and works in a temporary folder with the layout of an
    installation (<root>\App\Languages with copies of the bundled files, <root>\Config\Texts). Nothing is installed, no process is
    started, no setting of the device is changed. Write-SelfXLog is replaced by a function that collects the lines.
    Checked:
      - Test-SelfXOverrideText: accepts a normal text, "Settings > Personalization" and the limit of 1500 characters; refuses an empty
        text, a longer text, "<", entities (&amp;, &#60;), control characters, other placeholders than the bundled text, another
        number of "|" separators in SystemInfo_Export_Filter and the Copilot prompts;
      - Read-SelfXTextOverride: accepts UI, SystemInfo, Category, Message and Action texts; ignores unknown ids and ids with
        unexpected characters (an XPath fragment) without naming them; refuses duplicates; a problem never contains a text of the file;
        refuses a file that is missing, a link, larger than 256 KB, empty, not valid XML, has a DTD, another root element or another
        Culture (nothing of it is used);
      - Initialize-SelfXLanguage: without the folder or the file nothing changes; the override replaces single texts, for the
        culture of the loaded file (de-CH uses Texts\de.xml); other languages are not affected; an override adds a text that a
        language file lacks; the bundled file wins for everything else (root attributes of the override are not used, the
        override cannot add a language); an invalid file leaves the bundled texts as they are; the log names ids and reasons, never a text;
      - every bundled text of all language files is a valid override of itself (the limits fit the real texts) except the Copilot prompts;
      - Get-SelfXTextOverrideFolder and Get-SelfXConfigPath: Texts\<culture>.xml is a configuration file, other names below Texts are refused;
      - SelfX.Config.json may list a text override and SelfX.Code.json may not (placement rule), see also Test-FileManifest.ps1.
    PowerShell 7 (Windows PowerShell 5.1 also works):
    pwsh.exe -NoProfile -File .\Test-TextOverrides.ps1

.NOTES
    Name    : Test-TextOverrides.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version.
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Message) {
	$script:checks++
	try { & $Action | Out-Null; $script:errors.Add("$Message (no error)") }
	catch { if ($_.Exception.Message -notmatch $Pattern) { $script:errors.Add("$Message (wrong error: $($_.Exception.Message))") } }
}

$sources = Join-Path $PSScriptRoot 'Sources'
. (Join-Path $sources 'SelfXPaths.ps1')
. (Join-Path $sources 'Localization.ps1')

# The log of SelfX is replaced by a collector (Import-SelfXTextOverride writes to Write-SelfXLog when it exists).
$script:log = New-Object System.Collections.Generic.List[string]
function Write-SelfXLog { param([Parameter(Position = 0)][AllowEmptyString()][string]$Message = '', [Parameter(Position = 1)][string]$Level = 'Info') $script:log.Add("$Level|$Message") }

$root = Join-Path ([IO.Path]::GetTempPath()) ('SelfXTextOverrideTest_' + [guid]::NewGuid().ToString('N'))
$app = Join-Path $root 'App'
$config = Join-Path $root 'Config'
$texts = Join-Path $config 'Texts'
$marker = 'SECRET-TEXT-4711'

function Write-Override([string]$Culture, [string]$Body, [string]$Attributes = '') {
	# Texts\<culture>.xml with the given body; the Culture attribute is the file name unless Attributes replaces the root attributes.
	if (-not $Attributes) { $Attributes = "Culture=""$Culture""" }
	[IO.File]::WriteAllText((Join-Path $texts "$Culture.xml"), "<?xml version=""1.0"" encoding=""utf-8""?>`r`n<SelfX_Language $Attributes>`r`n$Body`r`n</SelfX_Language>", (New-Object Text.UTF8Encoding($false)))
}
function Get-Reference([string]$Culture) {
	$bundled = Read-SelfXLanguageFile -Path (Join-Path $app "Languages\$Culture.xml")
	Return (Get-SelfXTextReference -Document @($bundled, (Read-SelfXLanguageFile -Path (Join-Path $app 'Languages\en.xml')), (Read-SelfXLanguageFile -Path (Join-Path $app 'Languages\de.xml'))))
}
function Get-ProblemText($Result) { Return (@($Result.Problems | ForEach-Object { "$($_.Kind)|$($_.Key)|$($_.Message)" }) -join "`n") }

try {
	foreach ($folder in 'App\Languages', 'Config\Texts') { New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force | Out-Null }
	foreach ($file in Get-ChildItem -LiteralPath (Join-Path $sources 'Languages') -Filter '*.xml') { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $app 'Languages') }
	$deReference = Get-Reference 'de'

	# --- The check of one text ---
	Assert-Equal (Test-SelfXOverrideText -Key 'UI/Action_Success_Text' -Text 'Erledigt: {0}' -ReferenceText 'Fertig: {0}') $null 'text: a normal text with the placeholder is accepted'
	Assert-Equal (Test-SelfXOverrideText -Key 'UI/X' -Text 'Settings > Personalization > Colors' -ReferenceText 'x') $null 'text: ">" is allowed (menu paths)'
	Assert-Equal (Test-SelfXOverrideText -Key 'UI/X' -Text ("`r`n`t  Zeile eins`r`n`t  Zeile zwei`r`n") -ReferenceText 'x') $null 'text: indented multi-line text is accepted'
	Assert-Equal (Test-SelfXOverrideText -Key 'UI/X' -Text ('a' * 1500) -ReferenceText 'x') $null 'text: 1500 characters are accepted'
	Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/X' -Text ('a' * 1501) -ReferenceText 'x')) $true 'text: 1501 characters are refused'
	foreach ($case in @(
			@('empty', ''), @('blank', "  `r`n  "), @('tag', 'Hello <b>x</b>'), @('lone <', 'a < b'), @('entity', 'Tom &amp; Jerry'), @('numeric entity', 'a &#60; b'),
			@('hex entity', 'a &#x3C; b'), @('NEL', "a$([char]0x85)b"), @('DEL', "a$([char]0x7F)b"), @('BEL', "a$([char]7)b"))) {
		Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/X' -Text $case[1] -ReferenceText 'x')) $true "text: $($case[0]) is refused"
	}
	Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/Action_Success_Text' -Text 'Erledigt' -ReferenceText 'Fertig: {0}')) $true 'text: a missing placeholder is refused'
	Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/Action_Success_Text' -Text 'Erledigt: {0} {1}' -ReferenceText 'Fertig: {0}')) $true 'text: an additional placeholder is refused'
	Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/Action_Success_Text' -Text 'Erledigt: {1}' -ReferenceText 'Fertig: {0}')) $true 'text: another placeholder index is refused'
	Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/X' -Text 'Seite {0:D2}' -ReferenceText 'Seite {0}')) $true 'text: another format of a placeholder is refused'
	Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/X' -Text 'Hallo' -ReferenceText 'Hallo {0}')) $true 'text: a text without placeholder cannot replace a text with one'
	Assert-Equal (Test-SelfXOverrideText -Key 'UI/SystemInfo_Export_Filter' -Text 'a|b|c' -ReferenceText 'x|y|z') $null 'filter: the same number of separators is accepted'
	Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/SystemInfo_Export_Filter' -Text 'a|b' -ReferenceText 'x|y|z')) $true 'filter: another number of separators is refused'
	Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/Copilot_Prompt_User' -Text 'Hello' -ReferenceText 'x')) $true 'text: the Copilot prompt cannot be overridden'
	Assert-Equal ($null -ne (Test-SelfXOverrideText -Key 'UI/Copilot_Prompt_Admin' -Text 'Hello' -ReferenceText 'x')) $true 'text: the Copilot admin prompt cannot be overridden'
	Assert-Equal (Test-SelfXOverrideText -Key 'UI/copilot_prompt_user' -Text 'Hello' -ReferenceText 'x') $null 'text: the Copilot rule compares the id exactly (an id in another case is not a known id anyway)'

	# --- Reading a file: accepted entries ---
	$goodBody = @"
	<UI>
		<Action_Success_Text>Erledigt: {0}</Action_Success_Text>
		<Main_Title_Text>
			Hilfe
			   vom Team
		</Main_Title_Text>
	</UI>
	<SystemInfo><Category_Device>Ihr Gerät</Category_Device></SystemInfo>
	<Catalog>
		<Categories><Category Id="Device">Geräte</Category></Categories>
		<Messages><Message Id="Msg_Teams_Restart">Teams wird neu gestartet.</Message></Messages>
		<Actions><Action Id="Q_Teams"><Name>Teams neu starten</Name><Explanation>Schließt Teams und startet es neu.</Explanation></Action></Actions>
	</Catalog>
"@
	Write-Override 'de' $goodBody
	$result = Read-SelfXTextOverride -Path (Join-Path $texts 'de.xml') -Culture 'de' -Reference $deReference
	Assert-Equal $result.Loaded $true 'read: a valid file is loaded'
	Assert-Equal @($result.Problems).Count 0 'read: a valid file has no problems'
	Assert-Equal (@($result.Texts.Keys | Sort-Object) -join ',') 'Action/Q_Teams/Explanation,Action/Q_Teams/Name,Category/Device,Message/Msg_Teams_Restart,SystemInfo/Category_Device,UI/Action_Success_Text,UI/Main_Title_Text' 'read: UI, SystemInfo, Category, Message and Action texts are accepted'
	Assert-Equal $result.Texts['UI/Main_Title_Text'] "Hilfe`r`nvom Team" 'read: the indentation of a multi-line text is removed like in language files'

	# --- Reading a file: ids ---
	$body = @"
	<UI>
		<Not_A_Known_Text>x</Not_A_Known_Text>
		<Action_Success_Text>Erledigt: {0}</Action_Success_Text>
		<Action_Success_Text>$marker {0}</Action_Success_Text>
	</UI>
	<Catalog><Categories>
		<Category Id="x' or '1'='1">$marker</Category>
		<Category Id="..\..\x">$marker</Category>
		<Category Id="NoSuchCategory">$marker</Category>
	</Categories></Catalog>
"@
	Write-Override 'de' $body
	$result = Read-SelfXTextOverride -Path (Join-Path $texts 'de.xml') -Culture 'de' -Reference $deReference
	Assert-Equal @($result.Texts.Keys).Count 1 'ids: only the known text is accepted'
	Assert-Equal $result.Texts['UI/Action_Success_Text'] 'Erledigt: {0}' 'ids: the first of two equal ids wins'
	Assert-Equal (@($result.Problems | Where-Object { $_.Kind -eq 'Unknown' }).Count) 4 'ids: an unknown id, two ids with unexpected characters and an unknown category are ignored'
	Assert-Equal (@($result.Problems | Where-Object { $_.Kind -eq 'Rejected' }).Count) 1 'ids: the second text of a duplicate id is refused'
	Assert-Equal ((Get-ProblemText $result).Contains($marker)) $false 'ids: no problem contains a text of the file'
	Assert-Equal ((Get-ProblemText $result) -match "or '1'") $false 'ids: an id with unexpected characters is not repeated in a problem'
	Assert-Equal ((Get-ProblemText $result).Contains('UI/Not_A_Known_Text')) $true 'ids: an unknown id of the right form is named'

	# --- Reading a file: texts that are refused ---
	$body = @"
	<UI>
		<Action_Success_Text>$marker &lt;b&gt;</Action_Success_Text>
		<Action_Running_Text>$marker</Action_Running_Text>
		<Main_Title_Text>$marker &amp;amp; x</Main_Title_Text>
		<Subtitle_Text>$('x' * 1501) $marker</Subtitle_Text>
		<Health_Fix>$marker</Health_Fix>
	</UI>
"@
	Write-Override 'de' $body
	$result = Read-SelfXTextOverride -Path (Join-Path $texts 'de.xml') -Culture 'de' -Reference $deReference
	Assert-Equal (@($result.Texts.Keys) -join ',') 'UI/Health_Fix' 'refused: only the valid text remains'
	Assert-Equal (@($result.Problems | Where-Object { $_.Kind -eq 'Rejected' }).Count) 4 'refused: markup, missing placeholder, entity and too long text are refused'
	Assert-Equal ((Get-ProblemText $result).Contains($marker)) $false 'refused: no problem contains a text of the file'
	Assert-Equal (@($result.Problems).Count -le $Script:SelfXTextOverrideMaxProblems) $true 'refused: the number of problems is limited'
	# Many unknown ids: the list of problems stays short.
	$many = (1..200 | ForEach-Object { "<Unknown_$_>x</Unknown_$_>" }) -join ''
	Write-Override 'de' "<UI>$many</UI>"
	$result = Read-SelfXTextOverride -Path (Join-Path $texts 'de.xml') -Culture 'de' -Reference $deReference
	Assert-Equal @($result.Problems).Count $Script:SelfXTextOverrideMaxProblems '200 unknown ids give at most 50 problems'

	# --- Reading a file: the file as a whole ---
	$path = Join-Path $texts 'de.xml'
	$result = Read-SelfXTextOverride -Path (Join-Path $texts 'missing.xml') -Culture 'de' -Reference $deReference
	Assert-Equal "$($result.Loaded)/$(@($result.Problems | Where-Object { $_.Kind -eq 'File' }).Count)" 'False/1' 'file: a missing file is a problem and is not loaded'
	[IO.File]::WriteAllBytes($path, [byte[]]@())
	Assert-Equal (Read-SelfXTextOverride -Path $path -Culture 'de' -Reference $deReference).Loaded $false 'file: an empty file is not loaded'
	[IO.File]::WriteAllText($path, '<SelfX_Language Culture="de"><UI><Health_Fix>x</UI>')
	Assert-Equal (Read-SelfXTextOverride -Path $path -Culture 'de' -Reference $deReference).Loaded $false 'file: invalid XML is not loaded'
	[IO.File]::WriteAllText($path, '<?xml version="1.0"?><!DOCTYPE SelfX_Language [<!ENTITY e "x">]><SelfX_Language Culture="de"><UI><Health_Fix>&e;</Health_Fix></UI></SelfX_Language>')
	$result = Read-SelfXTextOverride -Path $path -Culture 'de' -Reference $deReference
	Assert-Equal "$($result.Loaded)/$(@($result.Texts.Keys).Count)" 'False/0' 'file: a DTD is refused and nothing is used'
	[IO.File]::WriteAllText($path, '<Other Culture="de"><UI><Health_Fix>x</Health_Fix></UI></Other>')
	Assert-Equal (Read-SelfXTextOverride -Path $path -Culture 'de' -Reference $deReference).Loaded $false 'file: another root element is not loaded'
	Write-Override 'de' '<UI><Health_Fix>x</Health_Fix></UI>' 'Culture="fr"'
	Assert-Equal (Read-SelfXTextOverride -Path $path -Culture 'de' -Reference $deReference).Loaded $false 'file: another Culture than the file name is not loaded'
	Write-Override 'de' ('<UI><Health_Fix>x</Health_Fix></UI>' + (' ' * 262200))
	Assert-Equal (Read-SelfXTextOverride -Path $path -Culture 'de' -Reference $deReference).Loaded $false 'file: a file larger than 256 KB is not loaded'
	Remove-Item -LiteralPath $path
	$linkTarget = Join-Path $root 'Elsewhere.xml'
	Write-Override 'de' '<UI><Health_Fix>from the link target</Health_Fix></UI>'
	Move-Item -LiteralPath $path -Destination $linkTarget
	$linked = $false
	try { New-Item -ItemType SymbolicLink -Path $path -Target $linkTarget | Out-Null; $linked = $true } catch { }
	if ($linked) {
		Assert-Equal (Read-SelfXTextOverride -Path $path -Culture 'de' -Reference $deReference).Loaded $false 'file: a link is not loaded'
		Remove-Item -LiteralPath $path
	}
	elseif ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine('skipped: no right to create a symbolic link') }
	Remove-Item -LiteralPath $linkTarget

	# --- Initialize-SelfXLanguage ---
	$folders = @(Join-Path $app 'Languages')
	$plain = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de'
	$bundledSuccess = Get-SelfXString 'Action_Success_Text' 'X'
	Assert-Equal $bundledSuccess 'Fertig: X' 'init: bundled text without an override'
	Assert-Equal "$($plain.TextOverrideApplied)/$($null -eq $plain.TextOverrideFile)" '0/True' 'init: no folder, nothing applied'
	$withFolder = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de' -TextOverrideFolder $texts
	Assert-Equal "$($withFolder.TextOverrideApplied)/$($null -eq $withFolder.TextOverrideFile)" '0/True' 'init: a folder without the file changes nothing'
	Assert-Equal (Get-SelfXString 'Action_Success_Text' 'X') $bundledSuccess 'init: the text is the bundled text'
	Assert-Equal (Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de' -TextOverrideFolder (Join-Path $root 'NoSuchFolder')).TextOverrideApplied 0 'init: a missing folder changes nothing'
	$script:log.Clear()
	Write-Override 'de' $goodBody
	$info = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de' -TextOverrideFolder $texts
	Assert-Equal $info.TextOverrideApplied 7 'init: seven texts are applied'
	Assert-Equal $info.TextOverrideFile (Join-Path $texts 'de.xml') 'init: the file is named'
	Assert-Equal (Get-SelfXString 'Action_Success_Text' 'X') 'Erledigt: X' 'init: a UI text is replaced and keeps its placeholder'
	Assert-Equal (Get-SelfXString 'Main_Title_Text') "Hilfe`r`nvom Team" 'init: a multi-line text is replaced'
	Assert-Equal (Get-SelfXString 'Action_Running_Text' 'X') 'Läuft: X' 'init: another text stays as it is'
	Assert-Equal ((Get-SelfXSystemInfoTexts)['Category_Device']) 'Ihr Gerät' 'init: a SystemInfo text is replaced'
	Assert-Equal (Get-SelfXCategoryName -Id 'Device') 'Geräte' 'init: a category name is replaced'
	Assert-Equal (Get-SelfXLanguageNode -XPath "/SelfX_Language/Catalog/Messages/Message[@Id='Msg_Teams_Restart']") 'Teams wird neu gestartet.' 'init: a shared message is replaced'
	Assert-Equal (Get-SelfXLanguageNode -XPath "/SelfX_Language/Catalog/Actions/Action[@Id='Q_Teams']/Name") 'Teams neu starten' 'init: the name of an action is replaced'
	Assert-Equal (Get-SelfXLanguageNode -XPath "/SelfX_Language/Catalog/Actions/Action[@Id='Q_Teams']/Alerte_MSG") ((Read-SelfXLanguageFile -Path (Join-Path $app 'Languages\de.xml')).SelectSingleNode("/SelfX_Language/Catalog/Actions/Action[@Id='Q_Teams']/Alerte_MSG").InnerText | ForEach-Object { Format-SelfXText $_ }) 'init: another field of the action stays as it is'
	Assert-Equal ($script:log | Where-Object { $_ -like 'Info|Text override de.xml: 7 texts applied, 0 entries*' }).Count 1 'init: the log says how many texts were applied'
	# The bundled file stays untouched on disk, and the next start without the override gives the bundled texts again.
	Assert-Equal ([IO.File]::ReadAllText((Join-Path $app 'Languages\de.xml')).Contains('Erledigt: {0}')) $false 'init: the bundled file is not changed'
	[void](Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de')
	Assert-Equal (Get-SelfXString 'Action_Success_Text' 'X') $bundledSuccess 'init: without the folder the bundled text is back'
	# The override belongs to the culture of the loaded file: de-CH loads de.xml and uses Texts\de.xml.
	$info = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de-CH' -TextOverrideFolder $texts
	Assert-Equal "$($info.Culture)/$($info.TextOverrideApplied)" 'de/7' 'init: de-CH uses the override of de'
	# Another language is not affected; English text of the fallback stays the bundled one.
	$info = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'fr' -TextOverrideFolder $texts
	Assert-Equal "$($info.Culture)/$($info.TextOverrideApplied)" 'fr/0' 'init: the override of de is not used for French'
	Assert-Equal (Get-SelfXString 'Action_Success_Text' 'X') 'Action terminée : X' 'init: the French text is the bundled French text'
	# The root attributes of the override are not used: it cannot rename or replace a language.
	Write-Override 'de' '<UI><Health_Fix>Reparieren</Health_Fix></UI>' 'Culture="de" NativeName="Hacked" FlowDirection="RightToLeft" Version="9"'
	$info = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de' -TextOverrideFolder $texts
	Assert-Equal "$($info.Name)/$($info.FlowDirection)/$($info.File)" "Deutsch/LeftToRight/$(Join-Path $app 'Languages\de.xml')" 'init: name, direction and file of the language come from the bundled file'
	Assert-Equal (Get-SelfXString 'Health_Fix') 'Reparieren' 'init: the text of that file is still applied'
	# An override for a culture without a bundled file is not used (an override cannot add a language): Esperanto falls back to German
	# and gets the override of German (Texts\de.xml, written above), never Texts\eo.xml.
	Write-Override 'eo' '<UI><Health_Fix>Riparu</Health_Fix></UI>'
	$info = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'eo' -TextOverrideFolder $texts
	Assert-Equal "$($info.Culture)/$($info.TextOverrideApplied)/$(Get-SelfXString 'Health_Fix')" 'de/1/Reparieren' 'init: Texts\eo.xml does not create a language (German is the base language and uses Texts\de.xml)'
	Remove-Item -LiteralPath (Join-Path $texts 'eo.xml')
	# A text that the language file lacks is added (an untranslated text): eo.xml is a copy of de.xml without Action_Success_Text.
	$custom = New-Object System.Xml.XmlDocument
	$custom.Load((Join-Path $app 'Languages\de.xml'))
	$custom.DocumentElement.SetAttribute('Culture', 'eo')
	[void]$custom.SelectSingleNode('/SelfX_Language/UI/Action_Success_Text').ParentNode.RemoveChild($custom.SelectSingleNode('/SelfX_Language/UI/Action_Success_Text'))
	$custom.Save((Join-Path $app 'Languages\eo.xml'))
	[void](Initialize-SelfXLanguage -LanguageFolder $folders -Language 'eo')
	$english = Get-SelfXString 'Action_Success_Text' 'X'
	Assert-Equal ($english -ne 'Fertig: X' -and $english -ne 'Action_Success_Text') $true 'init: a text missing in the language file comes from English'
	Write-Override 'eo' '<UI><Action_Success_Text>Farite: {0}</Action_Success_Text></UI>'
	$info = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'eo' -TextOverrideFolder $texts
	Assert-Equal "$($info.Culture)/$($info.TextOverrideApplied)" 'eo/1' 'init: the override of an untranslated text is applied'
	Assert-Equal (Get-SelfXString 'Action_Success_Text' 'X') 'Farite: X' 'init: the text is added to the language'
	Remove-Item -LiteralPath (Join-Path $texts 'eo.xml'), (Join-Path $app 'Languages\eo.xml')

	# --- An unusable override leaves the bundled texts and is logged without any text ---
	$script:log.Clear()
	Write-Override 'de' "<UI><Action_Success_Text>$marker</Action_Success_Text><Health_Fix>Gut</Health_Fix><Unknown_Id>$marker</Unknown_Id></UI>"
	$info = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de' -TextOverrideFolder $texts
	Assert-Equal "$($info.TextOverrideApplied)/$(Get-SelfXString 'Action_Success_Text' 'X')/$(Get-SelfXString 'Health_Fix')" '1/Fertig: X/Gut' 'bad: the refused text stays bundled, the valid text is applied'
	Assert-Equal (($script:log -join "`n").Contains($marker)) $false 'bad: the log contains no text of the file'
	Assert-Equal (($script:log | Where-Object { $_ -like 'Warning|Text override de.xml*' }).Count) 3 'bad: a warning for the summary and one for each ignored or refused entry'
	Assert-Equal ((($script:log -join "`n") -match 'UI/Action_Success_Text') -and (($script:log -join "`n") -match 'UI/Unknown_Id')) $true 'bad: the log names the ids'
	$script:log.Clear()
	[IO.File]::WriteAllText((Join-Path $texts 'de.xml'), '<?xml version="1.0"?><!DOCTYPE x [<!ENTITY e SYSTEM "file:///c:/windows/win.ini">]><SelfX_Language Culture="de"><UI><Health_Fix>&e;</Health_Fix></UI></SelfX_Language>')
	$info = Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de' -TextOverrideFolder $texts
	Assert-Equal "$($info.TextOverrideApplied)/$(Get-SelfXString 'Health_Fix')" "0/$((Read-SelfXLanguageFile -Path (Join-Path $app 'Languages\de.xml')).SelectSingleNode('/SelfX_Language/UI/Health_Fix').InnerText)" 'bad: a file with an external entity changes nothing'
	Assert-Equal (($script:log | Where-Object { $_ -like 'Warning|*not valid XML*' }).Count) 1 'bad: the reason is logged'
	Assert-Equal (Initialize-SelfXLanguage -LanguageFolder $folders -Language 'de' -TextOverrideFolder $texts).Culture 'de' 'bad: the language still loads'
	Remove-Item -LiteralPath (Join-Path $texts 'de.xml')
	# A culture name with path characters is never turned into a path.
	foreach ($name in '..\x', '../x', 'de/../en', 'C:\x', '', 'a') {
		$info = Import-SelfXTextOverride -TextOverrideFolder $texts -Culture $name -LanguageFolder $folders
		Assert-Equal ($null -eq $info.File) $true "import: the culture '$name' is refused"
	}

	# --- Every bundled text is a valid override of itself (the limits fit the real texts) ---
	$full = Join-Path $root 'Full'
	New-Item -ItemType Directory -Path $full | Out-Null
	foreach ($file in Get-ChildItem -LiteralPath (Join-Path $app 'Languages') -Filter '*.xml') {
		$culture = $file.BaseName
		$own = New-Object System.Xml.XmlDocument
		$own.Load($file.FullName)
		$entries = @(Get-SelfXTextEntries -Document $own | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Text) -and $_.Key -notlike 'UI/Copilot_Prompt_*' })
		Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $full "$culture.xml")
		$result = Read-SelfXTextOverride -Path (Join-Path $full "$culture.xml") -Culture $culture -Reference (Get-Reference $culture)
		$refused = @($result.Problems | Where-Object { $_.Key -notlike 'UI/Copilot_Prompt_*' })
		Assert-Equal "$culture/$($refused.Count)/$($result.Texts.Count -ge $entries.Count)" "$culture/0/True" "bundled: every text of $culture.xml is a valid override of itself"
	}

	# --- Paths and the placement rule ---
	Assert-Equal (Get-SelfXTextOverrideFolder -CodeRoot $app) $texts 'folder: Config\Texts next to App'
	Assert-Equal (Get-SelfXTextOverrideFolder -CodeRoot $sources) ([IO.Path]::GetFullPath((Join-Path $sources 'Texts'))) 'folder: Texts in the code folder in the flat layout'
	foreach ($name in 'Texts\de.xml', 'Texts/de-CH.xml', 'Texts\zh-Hans.xml') {
		Assert-Equal (Get-SelfXConfigPath -Name $name -CodeRoot $app) ([IO.Path]::GetFullPath((Join-Path $config $name.Replace('/', '\')))) "config path: $name is in Config"
	}
	foreach ($bad in 'Texts', 'Texts\', 'Texts\x.ps1', 'Texts\de.xml.txt', 'Texts\sub\de.xml', 'Texts\..\Tool_Config.xml', 'Texts\..\..\App\Self_X.ps1', 'Texts\toolong-language-name.xml', 'Texts\de.xml:stream', 'Texts\d.xml', 'Texts\de_CH.xml') {
		Assert-Throws { Get-SelfXConfigPath -Name $bad -CodeRoot $app } 'is not a configuration file|outside the configuration folder|Cannot bind|empty' "config path: '$bad' is refused"
	}
}
finally {
	Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | ForEach-Object { try { [IO.File]::Delete($_.FullName) } catch {} }
	Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
