<#
.SYNOPSIS
    Language support for the SelfX GUI: loads the language file that matches the Windows display language.

.DESCRIPTION
    The texts of the user interface, the action catalogue and the System information tab are stored in
    Sources\Languages\<culture>.xml (for example de.xml, fr.xml, zh-Hans.xml). This script selects the file
    that fits the Windows display language of the signed-in user and returns the texts.

    Selection of the language:
      1. The language chosen by the user in SelfX > Settings (HKCU\Software\SelfX\Language, see
         Resolve-SelfXLanguageSetting), unless the administrator hides the choice (Show_Language_Setting).
      2. Otherwise Tool_Language in Tool_Config.xml. "Auto" (default) uses the Windows display language
         (CurrentUICulture), any other value is used as culture name, for example "de" or "fr-CH".
      3. The culture and its parent cultures are tried in order, for example
         de-CH -> de, zh-TW -> zh-Hant -> zh, pt-BR -> pt.
         Swiss German (gsw, including gsw-CH) also falls back to German (de).
      4. If no file matches, German (de.xml, the base language) is used.

    Every text is looked up in the selected language first and then in English (fallback). Catalogue texts that are
    missing in both files use the English text in Issues_List.xml. A new language therefore
    only needs a new file in the Languages folder; no code change is required.

    Text overrides: the company can replace single texts without changing a bundled language file. The optional file
    Config\Texts\<culture>.xml has the format of the language files (root SelfX_Language, Culture = file name) and holds only the texts
    to replace (UI, SystemInfo, Catalog). <culture> is the culture of the bundled file that was loaded (for example de for de-CH).
    The bundled file (class Code) is loaded first, then the override (class Config). Ids that no bundled file knows are ignored and
    written to the log. A text is accepted only when it is not empty, not longer than 1500 characters, has no markup (no "<", no entity
    such as &amp;), no control characters and the same placeholders as the bundled text. The file must not be a link, not be larger than
    256 KB and not have a DTD. An override cannot add a language and cannot replace a file.

    The script only reads local files. It does not need a network connection.

.NOTES
    Name    : Localization.ps1
    Package : SelfX Service
    Context : GUI helper (dot-sourced by Self_X.ps1 as the signed-in user)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.2.0    2026-10-28  Wolfgang Baeck       Initial version: multilingual user interface
    2.8.14   2026-11-23  fubu2k               Pass the Link field of catalogue actions (Context Link)
    3.1.0    2026-11-27  fubu2k               LanguageFolder can name several folders (bundled files in App\Languages first, own files of the company
                                              in Config\Languages); a culture found in an earlier folder wins
    3.1.0    2026-11-27  fubu2k               Text overrides: Config\Texts\<culture>.xml replaces single texts after the bundled file is loaded
                                              (Initialize-SelfXLanguage -TextOverrideFolder, Read-SelfXTextOverride, Set-SelfXTextOverride)
    3.1.0    2026-11-27  fubu2k               Catalogue field TerminalServer is passed on with each action (Environment_Mode, SelfXEnvironment.ps1)
    3.1.0    2026-11-28  fubu2k               Catalogue field Disruptive is passed on with each action (SelfXDisturb.ps1)
#>

$Script:SelfX_Language = $null
$Script:SelfX_LanguageFallback = $null

Function Find-SelfXLanguageFile
{
	<#
	.SYNOPSIS
		Returns the path of <Name>.xml in the first of the folders that has it, else the path in the first folder (missing file).
	.DESCRIPTION
		The folders are searched in the given order: the bundled files of the code come first, so an own file of the company
		cannot replace a bundled language. Name is a culture name checked by the caller (Test-SelfXLanguageName or a fixed name).
	#>
	param(
		[string[]]$LanguageFolder,
		[string]$Name
	)
	$Folders = @($LanguageFolder | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
	foreach($Folder in $Folders)
		{
			$Path = Join-Path $Folder "$Name.xml"
			If(Test-Path -LiteralPath $Path -PathType Leaf) { return $Path }
		}
	If($Folders.Count -gt 0) { return (Join-Path $Folders[0] "$Name.xml") }
	return $null
}

Function Read-SelfXLanguageFile
{
	<#
	.SYNOPSIS
		Loads one language file. Returns $null if the file is missing or not valid XML.
	#>
	param([string]$Path)
	If([string]::IsNullOrEmpty($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
	Try
		{
			# XmlDocument.Load honours the encoding declaration, so UTF-8 files without BOM are read correctly
			$Document = New-Object System.Xml.XmlDocument
			$Document.XmlResolver = $null
			$XmlSettings = New-Object System.Xml.XmlReaderSettings
			$XmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
			$XmlSettings.XmlResolver = $null
			$XmlReader = [System.Xml.XmlReader]::Create($Path, $XmlSettings)
			Try { $Document.Load($XmlReader) } Finally { $XmlReader.Dispose() }
			If($Document.DocumentElement.LocalName -ne 'SelfX_Language') { return $null }
			return $Document
		}
	Catch
		{
			return $null
		}
}

Function Get-SelfXCultureCandidates
{
	<#
	.SYNOPSIS
		Returns the culture name and all parent culture names, for example de-CH, de.
	#>
	param([System.Globalization.CultureInfo]$Culture)
	$Names = New-Object System.Collections.Generic.List[string]
	$Current = $Culture
	While(($Current -ne $null) -and ($Current.Name -ne ''))
		{
			If(-not $Names.Contains($Current.Name)) { $Names.Add($Current.Name) }
			$Current = $Current.Parent
		}
	If(($Culture -ne $null) -and ($Culture.TwoLetterISOLanguageName -eq 'gsw') -and (-not $Names.Contains('de')))
		{
			$Names.Add('de')
		}
	return $Names
}

Function Test-SelfXLanguageName
{
	<#
	.SYNOPSIS
		True for a culture name such as "de", "fr-CH" or "zh-Hans" (no path characters).
	#>
	param([string]$Name)
	return ("$Name" -match '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}$')
}

Function Resolve-SelfXLanguageSetting
{
	<#
	.SYNOPSIS
		Returns the language setting for Initialize-SelfXLanguage: the choice of the user or Tool_Language.
	.DESCRIPTION
		The user choice (HKCU\Software\SelfX\Language) wins when the administrator allows it
		(Show_Language_Setting), it is a valid culture name and its language file exists. "Auto" or an
		empty user value means "use the default", that is Tool_Language (normally "Auto" = Windows language).
	#>
	param(
		[string]$ConfigLanguage = 'Auto',
		[string]$UserLanguage = '',
		[bool]$AllowUserChoice = $true,
		[string[]]$LanguageFolder = @()
	)
	$User = "$UserLanguage".Trim()
	If($AllowUserChoice -and ($User -ne '') -and ($User -ne 'Auto') -and (Test-SelfXLanguageName $User))
		{
			$Folders = @($LanguageFolder | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
			If($Folders.Count -eq 0) { return $User }
			$Path = Find-SelfXLanguageFile -LanguageFolder $Folders -Name $User
			If(Test-Path -LiteralPath $Path -PathType Leaf) { return $User }
		}
	$Config = "$ConfigLanguage".Trim()
	If($Config -eq '') { return 'Auto' }
	return $Config
}

Function Get-SelfXLanguageFileCulture
{
	<#
	.SYNOPSIS
		Returns the culture of the language file that Initialize-SelfXLanguage selects for a setting, without loading it.
	#>
	param(
		[string[]]$LanguageFolder,
		[string]$Language = 'Auto'
	)
	$Culture = [System.Globalization.CultureInfo]::CurrentUICulture
	If((-not [string]::IsNullOrWhiteSpace($Language)) -and ($Language.Trim() -ne 'Auto'))
		{
			Try { $Culture = [System.Globalization.CultureInfo]::GetCultureInfo($Language.Trim()) } Catch {}
		}
	foreach($Name in (Get-SelfXCultureCandidates -Culture $Culture))
		{
			$Path = Find-SelfXLanguageFile -LanguageFolder $LanguageFolder -Name $Name
			If($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Name }
		}
	# Base language of SelfX
	return 'de'
}

Function Get-SelfXLanguageList
{
	<#
	.SYNOPSIS
		Returns the available languages (Culture, Name in the language itself, FlowDirection), sorted by name.
	.DESCRIPTION
		Only the root element of each file is read, so the list is fast. Files whose name differs from their
		Culture attribute or that are no SelfX language file are skipped.
	#>
	param([string[]]$LanguageFolder)
	$List = New-Object System.Collections.Generic.List[object]
	$Seen = @{}
	$Files = @(foreach($Folder in @($LanguageFolder | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) { Get-ChildItem -LiteralPath $Folder -Filter '*.xml' -File -ErrorAction SilentlyContinue })
	foreach($File in $Files)
		{
			# A culture of an earlier folder (bundled files) wins over an own file with the same name.
			If($Seen.ContainsKey($File.BaseName.ToLowerInvariant())) { continue }
			$Reader = $null
			Try
				{
					$Settings = New-Object System.Xml.XmlReaderSettings
					$Settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
					$Reader = [System.Xml.XmlReader]::Create($File.FullName, $Settings)
					[void]$Reader.MoveToContent()
					If($Reader.LocalName -ne 'SelfX_Language') { continue }
					$Culture = $Reader.GetAttribute('Culture')
					If(($Culture -ne $File.BaseName) -or -not (Test-SelfXLanguageName $Culture)) { continue }
					$Name = $Reader.GetAttribute('NativeName')
					If([string]::IsNullOrWhiteSpace($Name)) { $Name = $Culture }
					$Flow = $(If($Reader.GetAttribute('FlowDirection') -eq 'RightToLeft') { 'RightToLeft' } Else { 'LeftToRight' })
					$Seen[$File.BaseName.ToLowerInvariant()] = $true
					$List.Add([pscustomobject]@{ Culture = $Culture; Name = $Name; FlowDirection = $Flow })
				}
			Catch {}
			Finally
				{
					If($Reader -ne $null) { $Reader.Dispose() }
				}
		}
	return @($List | Sort-Object -Property @{ Expression = { $_.Name.ToLowerInvariant() } })
}

# Text overrides of the company (Config\Texts\<culture>.xml): limits, see Read-SelfXTextOverride.
$Script:SelfXTextOverrideMaxFileBytes = 262144
$Script:SelfXTextOverrideMaxTextLength = 1500
$Script:SelfXTextOverrideMaxProblems = 50
$Script:SelfXTextOverrideKeyPattern = '^((UI|SystemInfo|Category|Message)/[A-Za-z0-9_.-]{1,80}|Action/[A-Za-z0-9_.-]{1,80}/(Name|Explanation|Alerte_MSG))\z'

Function Get-SelfXTextPlaceholders
{
	<#
	.SYNOPSIS
		Returns the sorted placeholders ({0}, {1:D2} ...) of a text as one string, to compare a text with its reference.
	#>
	param([string]$Text)
	return (([regex]::Matches("$Text", '\{\d+(:[^}]*)?\}') | ForEach-Object { $_.Value } | Sort-Object) -join ' ')
}

Function Get-SelfXTextEntries
{
	<#
	.SYNOPSIS
		Returns the texts of a language document as entries (Key, Text) with the key forms UI/<Id>, SystemInfo/<Id>, Category/<Id>,
		Message/<Id> and Action/<Id>/<Name|Explanation|Alerte_MSG>.
	.DESCRIPTION
		Only reads the document. The keys are built from names in the document; callers check them with
		$Script:SelfXTextOverrideKeyPattern before they use them.
	#>
	param([System.Xml.XmlDocument]$Document)
	$Entries = New-Object System.Collections.Generic.List[object]
	If(($Document -eq $null) -or ($Document.DocumentElement -eq $null)) { return ,$Entries }
	$Root = $Document.DocumentElement
	foreach($Section in 'UI', 'SystemInfo')
		{
			$Node = $Root.SelectSingleNode($Section)
			If($Node -eq $null) { continue }
			foreach($Child in $Node.ChildNodes)
				{
					If($Child.NodeType -eq 'Element') { $Entries.Add([pscustomobject]@{ Key = "$Section/$($Child.LocalName)"; Text = $Child.InnerText }) }
				}
		}
	foreach($Pair in @(@('Category', 'Catalog/Categories/Category'), @('Message', 'Catalog/Messages/Message')))
		{
			foreach($Node in $Root.SelectNodes($Pair[1]))
				{
					$Entries.Add([pscustomobject]@{ Key = "$($Pair[0])/$($Node.GetAttribute('Id'))"; Text = $Node.InnerText })
				}
		}
	foreach($Action in $Root.SelectNodes('Catalog/Actions/Action'))
		{
			foreach($Child in $Action.ChildNodes)
				{
					If($Child.NodeType -eq 'Element') { $Entries.Add([pscustomobject]@{ Key = "Action/$($Action.GetAttribute('Id'))/$($Child.LocalName)"; Text = $Child.InnerText }) }
				}
		}
	return ,$Entries
}

Function Get-SelfXTextReference
{
	<#
	.SYNOPSIS
		Returns a hashtable key -> text of all texts that a text override may replace: the first document that has a text for a key wins.
	.DESCRIPTION
		Normally the bundled file of the selected language, then English, then German (the base language). The text is the
		reference for the placeholders of the override.
	#>
	param([System.Xml.XmlDocument[]]$Document)
	$Reference = @{}
	foreach($Item in @($Document))
		{
			If($Item -eq $null) { continue }
			foreach($Entry in (Get-SelfXTextEntries -Document $Item))
				{
					If($Entry.Key -notmatch $Script:SelfXTextOverrideKeyPattern) { continue }
					If((-not $Reference.ContainsKey($Entry.Key)) -and (-not [string]::IsNullOrWhiteSpace($Entry.Text))) { $Reference[$Entry.Key] = $Entry.Text }
				}
		}
	return $Reference
}

Function Test-SelfXOverrideText
{
	<#
	.SYNOPSIS
		Checks one override text. Returns $null when it is accepted, otherwise the reason (English, no part of the text).
	.DESCRIPTION
		A text is accepted when it is not a Copilot prompt (UI/Copilot_Prompt_*), not empty, not longer than 1500 characters, has no markup (no "<", no entity such as &amp;), no
		control characters and the same placeholders as the reference text (and, for SystemInfo_Export_Filter, the same number of "|" separators).
	#>
	param(
		[string]$Key,
		[string]$Text,
		[string]$ReferenceText
	)
	# The Copilot prompts are no display texts (they are handed to Copilot and contain pseudo placeholders such as <device>).
	If($Key -clike 'UI/Copilot_Prompt_*') { return 'the Copilot prompts cannot be overridden' }
	$Value = Format-SelfXText $Text
	If([string]::IsNullOrWhiteSpace($Value)) { return 'the text is empty' }
	If($Value.Length -gt $Script:SelfXTextOverrideMaxTextLength) { return "the text is longer than $($Script:SelfXTextOverrideMaxTextLength) characters" }
	# No markup: no "<" (a tag cannot start without it) and no entity such as &amp; or &#60;. A single ">" is allowed (menu paths such as Settings > Personalization).
	If($Value.Contains('<') -or ($Value -match '&#?[A-Za-z0-9]+;')) { return 'the text contains markup (< or an entity such as &amp;)' }
	If($Value -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]') { return 'the text contains a control character' }
	If((Get-SelfXTextPlaceholders $Value) -ne (Get-SelfXTextPlaceholders $ReferenceText)) { return 'the placeholders differ from the bundled text' }
	If(($Key -ceq 'UI/SystemInfo_Export_Filter') -and ($Value.Split('|').Count -ne $ReferenceText.Split('|').Count)) { return 'the number of | separators differs from the bundled text' }
	return $null
}

Function Read-SelfXTextOverride
{
	<#
	.SYNOPSIS
		Reads and checks one override file. Returns Texts (key -> text of the accepted entries), Problems and Loaded.
	.DESCRIPTION
		The file has the format of the language files (root SelfX_Language, Culture = file name) and may hold any of their texts. It is read
		once, as bytes: a file that is a link, larger than 256 KB, not valid XML (a DTD is refused), without the root element
		SelfX_Language or with another Culture is not used at all. Inside a usable file a text is applied only when its key is a
		known text of the bundled files (Reference), it has not been given before and Test-SelfXOverrideText accepts it; every
		other entry is ignored. Problems (Kind File, Unknown or Rejected, Key, Message) never contain a text of the file and
		name a key only when it has the form of a text id. Nothing is changed on the device.
	.PARAMETER Culture
		Culture name of the language the file belongs to (the file name without .xml).
	.PARAMETER Reference
		Result of Get-SelfXTextReference.
	#>
	param(
		[string]$Path,
		[string]$Culture,
		[hashtable]$Reference
	)
	$Texts = [ordered]@{}
	$Problems = New-Object System.Collections.Generic.List[object]
	$Result = [pscustomobject]@{ Texts = $Texts; Problems = $Problems; Loaded = $false }
	Function Add-Problem([string]$Kind, [string]$Key, [string]$Message)
		{
			If($Problems.Count -lt $Script:SelfXTextOverrideMaxProblems) { $Problems.Add([pscustomobject]@{ Kind = $Kind; Key = $Key; Message = $Message }) }
		}
	Try
		{
			$Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
			If($Item.PSIsContainer) { Add-Problem 'File' '' 'the path is a folder'; return $Result }
			If($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Add-Problem 'File' '' 'the file is a link'; return $Result }
			If($Item.Length -gt $Script:SelfXTextOverrideMaxFileBytes) { Add-Problem 'File' '' "the file is larger than $($Script:SelfXTextOverrideMaxFileBytes) bytes"; return $Result }
			$Bytes = [IO.File]::ReadAllBytes($Item.FullName)
		}
	Catch
		{
			Add-Problem 'File' '' 'the file cannot be read'
			return $Result
		}
	$Document = New-Object System.Xml.XmlDocument
	$Document.XmlResolver = $null
	$Stream = New-Object System.IO.MemoryStream (, $Bytes)
	Try
		{
			$XmlSettings = New-Object System.Xml.XmlReaderSettings
			$XmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
			$XmlSettings.XmlResolver = $null
			$XmlSettings.MaxCharactersInDocument = $Script:SelfXTextOverrideMaxFileBytes
			$XmlReader = [System.Xml.XmlReader]::Create($Stream, $XmlSettings)
			Try { $Document.Load($XmlReader) } Finally { $XmlReader.Dispose() }
		}
	Catch
		{
			Add-Problem 'File' '' 'the file is not valid XML (a DTD is not allowed)'
			return $Result
		}
	Finally { $Stream.Dispose() }
	If($Document.DocumentElement.LocalName -ne 'SelfX_Language') { Add-Problem 'File' '' 'the root element must be SelfX_Language'; return $Result }
	If($Document.DocumentElement.GetAttribute('Culture') -ne $Culture) { Add-Problem 'File' '' "the Culture attribute must be '$Culture' (the name of the file)"; return $Result }
	$Result.Loaded = $true
	foreach($Entry in (Get-SelfXTextEntries -Document $Document))
		{
			If($Entry.Key -notmatch $Script:SelfXTextOverrideKeyPattern) { Add-Problem 'Unknown' '' 'an entry has no valid text id and is ignored'; continue }
			If(-not $Reference.ContainsKey($Entry.Key)) { Add-Problem 'Unknown' $Entry.Key 'unknown text id, ignored'; continue }
			If($Texts.Contains($Entry.Key)) { Add-Problem 'Rejected' $Entry.Key 'the text id is given more than once, the first text is used'; continue }
			$Reason = Test-SelfXOverrideText -Key $Entry.Key -Text $Entry.Text -ReferenceText $Reference[$Entry.Key]
			If($Reason) { Add-Problem 'Rejected' $Entry.Key "rejected: $Reason"; continue }
			$Texts[$Entry.Key] = (Format-SelfXText $Entry.Text)
		}
	return $Result
}

Function Set-SelfXTextOverride
{
	<#
	.SYNOPSIS
		Writes accepted override texts into the loaded language document (in memory only; no file is changed).
	.DESCRIPTION
		Texts is the result of Read-SelfXTextOverride. Every key was checked against $Script:SelfXTextOverrideKeyPattern and against
		the bundled texts; a text that the language file does not have yet (an untranslated text) is added. Returns the number of texts set.
	#>
	param(
		[System.Xml.XmlDocument]$Document,
		$Texts
	)
	If(($Document -eq $null) -or ($Document.DocumentElement -eq $null) -or ($Texts -eq $null)) { return 0 }
	$Root = $Document.DocumentElement
	$Count = 0
	foreach($Key in @($Texts.Keys))
		{
			If("$Key" -notmatch $Script:SelfXTextOverrideKeyPattern) { continue }
			$Parts = "$Key".Split('/')
			$Parent = $Root
			$Path = New-Object System.Collections.Generic.List[object]
			If(($Parts[0] -eq 'UI') -or ($Parts[0] -eq 'SystemInfo')) { $Path.Add(@($Parts[0], $null)); $Path.Add(@($Parts[1], $null)) }
			ElseIf($Parts[0] -eq 'Category') { $Path.Add(@('Catalog', $null)); $Path.Add(@('Categories', $null)); $Path.Add(@('Category', $Parts[1])) }
			ElseIf($Parts[0] -eq 'Message') { $Path.Add(@('Catalog', $null)); $Path.Add(@('Messages', $null)); $Path.Add(@('Message', $Parts[1])) }
			Else { $Path.Add(@('Catalog', $null)); $Path.Add(@('Actions', $null)); $Path.Add(@('Action', $Parts[1])); $Path.Add(@($Parts[2], $null)) }
			foreach($Step in $Path)
				{
					$Child = $null
					foreach($Candidate in $Parent.ChildNodes)
						{
							If(($Candidate.NodeType -eq 'Element') -and ($Candidate.LocalName -ceq $Step[0]) -and (($Step[1] -eq $null) -or ($Candidate.GetAttribute('Id') -ceq $Step[1]))) { $Child = $Candidate; break }
						}
					If($Child -eq $null)
						{
							$Child = $Document.CreateElement($Step[0])
							If($Step[1] -ne $null) { [void]$Child.SetAttribute('Id', $Step[1]) }
							[void]$Parent.AppendChild($Child)
						}
					$Parent = $Child
				}
			$Parent.InnerText = [string]$Texts[$Key]
			$Count++
		}
	return $Count
}

Function Import-SelfXTextOverride
{
	<#
	.SYNOPSIS
		Applies the text override of the company to the loaded language, when the file Texts\<culture>.xml exists.
	.DESCRIPTION
		Called by Initialize-SelfXLanguage after the bundled language file is loaded (class Code; the override is class Config). The
		override belongs to the culture of the file that was loaded, for example Texts\de.xml for de-CH. Without the folder or
		the file nothing happens. Everything that is not accepted is ignored and written to the log (Write-SelfXLog, when it is
		loaded): the id and the reason, never a text. Returns an object with File, Applied and Problems.
	#>
	param(
		[string]$TextOverrideFolder,
		[string]$Culture,
		[string[]]$LanguageFolder
	)
	$Info = [pscustomobject]@{ File = $null; Applied = 0; Problems = @() }
	If([string]::IsNullOrWhiteSpace($TextOverrideFolder) -or ($Script:SelfX_Language -eq $null) -or -not (Test-SelfXLanguageName $Culture)) { return $Info }
	$Path = Join-Path $TextOverrideFolder "$Culture.xml"
	If(-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Info }
	$Info.File = $Path
	# Reference: the selected bundled language, English, German (base language); German is read only when it is a different file.
	$BaseDocument = $null
	If($Culture -ne 'de') { $BaseDocument = Read-SelfXLanguageFile -Path (Find-SelfXLanguageFile -LanguageFolder $LanguageFolder -Name 'de') }
	$Reference = Get-SelfXTextReference -Document @($Script:SelfX_Language, $Script:SelfX_LanguageFallback, $BaseDocument)
	$Override = Read-SelfXTextOverride -Path $Path -Culture $Culture -Reference $Reference
	If($Override.Loaded) { $Info.Applied = Set-SelfXTextOverride -Document $Script:SelfX_Language -Texts $Override.Texts }
	$Info.Problems = $Override.Problems.ToArray()
	If(Get-Command -Name Write-SelfXLog -ErrorAction SilentlyContinue)
		{
			Write-SelfXLog ("Text override {0}.xml: {1} texts applied, {2} entries ignored or rejected." -f $Culture, $Info.Applied, $Info.Problems.Count) $(If($Info.Problems.Count -gt 0) { 'Warning' } Else { 'Info' })
			foreach($Problem in $Info.Problems)
				{
					$Where = $(If($Problem.Key) { " '$($Problem.Key)'" } Else { '' })
					Write-SelfXLog ("Text override {0}.xml{1}: {2}" -f $Culture, $Where, $Problem.Message) 'Warning'
				}
		}
	return $Info
}

Function Initialize-SelfXLanguage
{
	<#
	.SYNOPSIS
		Selects and loads the language file. Returns an object with Culture, Name, FlowDirection and File.
	.PARAMETER LanguageFolder
		Folders with the language files, searched in this order (App\Languages, then Config\Languages).
	.PARAMETER Language
		"Auto" or empty = Windows display language, otherwise a culture name such as "de" or "fr-CH".
	.PARAMETER TextOverrideFolder
		Optional folder with text overrides of the company (Config\Texts, see Get-SelfXTextOverrideFolder). After the bundled file is
		loaded, Texts\<culture>.xml of the loaded file replaces single texts (Import-SelfXTextOverride). Without it nothing is overridden.
	#>
	param(
		[string[]]$LanguageFolder,
		[string]$Language = 'Auto',
		[string]$TextOverrideFolder = ''
	)

	$Culture = [System.Globalization.CultureInfo]::CurrentUICulture
	If((-not [string]::IsNullOrWhiteSpace($Language)) -and ($Language.Trim() -ne 'Auto'))
		{
			Try { $Culture = [System.Globalization.CultureInfo]::GetCultureInfo($Language.Trim()) }
			Catch { $Culture = [System.Globalization.CultureInfo]::CurrentUICulture }
		}

	$Script:SelfX_LanguageFallback = Read-SelfXLanguageFile -Path (Find-SelfXLanguageFile -LanguageFolder $LanguageFolder -Name 'en')
	$Script:SelfX_Language = $null
	$Selected_File = $null

	foreach($Name in (Get-SelfXCultureCandidates -Culture $Culture))
		{
			$Path = Find-SelfXLanguageFile -LanguageFolder $LanguageFolder -Name $Name
			$Document = Read-SelfXLanguageFile -Path $Path
			If($Document -ne $null)
				{
					$Script:SelfX_Language = $Document
					$Selected_File = $Path
					break
				}
		}

	If($Script:SelfX_Language -eq $null)
		{
			# No file for the language: German is the base language, English the fallback if de.xml is missing.
			$Selected_File = Find-SelfXLanguageFile -LanguageFolder $LanguageFolder -Name 'de'
			$Script:SelfX_Language = Read-SelfXLanguageFile -Path $Selected_File
			If($Script:SelfX_Language -eq $null)
				{
					$Script:SelfX_Language = $Script:SelfX_LanguageFallback
					$Selected_File = Find-SelfXLanguageFile -LanguageFolder $LanguageFolder -Name 'en'
				}
		}

	$Root = $null
	If($Script:SelfX_Language -ne $null) { $Root = $Script:SelfX_Language.DocumentElement }

	$Flow = 'LeftToRight'
	If(($Root -ne $null) -and ($Root.GetAttribute('FlowDirection') -eq 'RightToLeft')) { $Flow = 'RightToLeft' }

	$Culture_Name = 'de'
	If(($Root -ne $null) -and $Root.GetAttribute('Culture')) { $Culture_Name = $Root.GetAttribute('Culture') }

	# Optional text overrides of the company: class Config, loaded after the bundled file (class Code), never the other way round.
	$Override = Import-SelfXTextOverride -TextOverrideFolder $TextOverrideFolder -Culture $Culture_Name -LanguageFolder $LanguageFolder

	return [pscustomobject]@{
		Culture       = $Culture_Name
		Name          = $(If($Root -ne $null){ $Root.GetAttribute('NativeName') } Else { 'Deutsch' })
		FlowDirection = $Flow
		File          = $Selected_File
		WindowsCulture = $Culture.Name
		TextOverrideFile    = $Override.File
		TextOverrideApplied = $Override.Applied
	}
}

Function Get-SelfXLanguageNode
{
	<#
	.SYNOPSIS
		Returns the text of a node in the selected language, then in English, else $null.
	#>
	param([string]$XPath)
	foreach($Document in @($Script:SelfX_Language, $Script:SelfX_LanguageFallback))
		{
			If($Document -eq $null) { continue }
			$Node = $Document.SelectSingleNode($XPath)
			If(($Node -ne $null) -and (-not [string]::IsNullOrWhiteSpace($Node.InnerText)))
				{
					return (Format-SelfXText $Node.InnerText)
				}
		}
	return $null
}

Function Format-SelfXText
{
	<#
	.SYNOPSIS
		Removes the indentation that XML formatting adds to multi-line texts and trims the text.
	#>
	param([string]$Text)
	If($Text -eq $null) { return $null }
	$Lines = $Text -split "\r?\n" | ForEach-Object { $_.Trim() }
	return (($Lines -join "`r`n").Trim())
}

Function Get-SelfXString
{
	<#
	.SYNOPSIS
		Returns a user interface text (UI section). {0}, {1} ... are replaced by the arguments.
	.EXAMPLE
		Get-SelfXString 'Action_Success_Text' 'Restart Teams'
	#>
	param(
		[string]$Id,
		[Parameter(ValueFromRemainingArguments = $true)]
		[object[]]$Arguments
	)
	$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/UI/$Id"
	If($Text -eq $null) { $Text = $Id }
	If(($Arguments -ne $null) -and ($Arguments.Count -gt 0))
		{
			# A broken placeholder in a translation must not stop the GUI: show the text without formatting
			Try { $Text = [string]::Format($Text, [object[]]$Arguments) } Catch {}
		}
	return $Text
}

Function Get-SelfXSystemInfoTexts
{
	<#
	.SYNOPSIS
		Returns all texts of the SystemInfo section as hashtable (English values completed by the selected language).
	#>
	$Texts = @{}
	foreach($Document in @($Script:SelfX_LanguageFallback, $Script:SelfX_Language))
		{
			If($Document -eq $null) { continue }
			$Section = $Document.SelectSingleNode('/SelfX_Language/SystemInfo')
			If($Section -eq $null) { continue }
			foreach($Node in $Section.ChildNodes)
				{
					If(($Node.NodeType -eq 'Element') -and (-not [string]::IsNullOrWhiteSpace($Node.InnerText)))
						{
							$Texts[$Node.LocalName] = Format-SelfXText $Node.InnerText
						}
				}
		}
	return $Texts
}

Function Get-SelfXCategoryName
{
	<#
	.SYNOPSIS
		Returns the display name of a category Id, or the Id itself if no translation exists.
	#>
	param([string]$Id)
	$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/Catalog/Categories/Category[@Id='$Id']"
	If($Text -eq $null) { return $Id }
	return $Text
}

Function Get-SelfXCatalogField
{
	<#
	.SYNOPSIS
		Returns the localized text of one field (Name, Explanation, Alerte_MSG) of a catalogue action.
	.DESCRIPTION
		Order: translation of the action, translation of the referenced message (Ref attribute),
		English base text of the message in Issues_List.xml, English base text of the action.
	#>
	param(
		[System.Xml.XmlElement]$Action,
		[string]$Field,
		[System.Xml.XmlDocument]$Catalog
	)
	$Id = $Action.GetAttribute('Id')
	$Node = $Action.SelectSingleNode($Field)
	$Ref = $null
	If($Node -ne $null) { $Ref = $Node.GetAttribute('Ref') }

	If($Id)
		{
			$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/Catalog/Actions/Action[@Id='$Id']/$Field"
			If($Text -ne $null) { return $Text }
		}
	If($Ref)
		{
			$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/Catalog/Messages/Message[@Id='$Ref']"
			If($Text -ne $null) { return $Text }
			$Base = $Catalog.SelectSingleNode("/Actions/Messages/Message[@Id='$Ref']")
			If($Base -ne $null) { return (Format-SelfXText $Base.InnerText) }
			return $null
		}
	If($Node -ne $null) { return (Format-SelfXText $Node.InnerText) }
	return $null
}

Function Get-SelfXLocalizedActions
{
	<#
	.SYNOPSIS
		Converts the actions of one catalogue section into objects with localized texts.
	.DESCRIPTION
		Category contains the localized display name (used in the list and the filter), CategoryId the
		original Id. Script, Link, Context, Requires, TerminalServer, Disruptive, Post_Action and Buttons are taken unchanged from the catalogue.
	.PARAMETER Section
		Quick_Solution (simplified view) or Detailed_Solution (detailed view).
	#>
	param(
		[System.Xml.XmlDocument]$Catalog,
		[ValidateSet('Quick_Solution', 'Detailed_Solution')]
		[string]$Section
	)
	$Result = New-Object System.Collections.Generic.List[object]
	foreach($Action in $Catalog.SelectNodes("/Actions/$Section/Action"))
		{
			$Category_Id = ([string]$Action.Category).Trim()
			$Result.Add([pscustomobject]@{
				Name        = Get-SelfXCatalogField -Action $Action -Field 'Name' -Catalog $Catalog
				Category    = Get-SelfXCategoryName -Id $Category_Id
				Explanation = Get-SelfXCatalogField -Action $Action -Field 'Explanation' -Catalog $Catalog
				Buttons     = ([string]$Action.Buttons).Trim()
				Script      = ([string]$Action.Script).Trim()
				Link        = ([string]$Action.Link).Trim()
				Alerte_MSG  = Get-SelfXCatalogField -Action $Action -Field 'Alerte_MSG' -Catalog $Catalog
				Context     = ([string]$Action.Context).Trim()
				Requires    = ([string]$Action.Requires).Trim()
				TerminalServer = ([string]$Action.TerminalServer).Trim()
				Disruptive  = ([string]$Action.Disruptive).Trim()
				Post_Action = ([string]$Action.Post_Action).Trim()
				CategoryId  = $Category_Id
				Id          = $Action.GetAttribute('Id')
			})
		}
	return $Result
}

Function Get-SelfXButtonText
{
	<#
	.SYNOPSIS
		Translates a button token of the catalogue (Ok, Cancel, Yes, No) into the selected language.
	#>
	param([string]$Token)
	$Token = "$Token".Trim()
	If($Token -eq '') { return $Token }
	$Key = 'Button_' + $Token.Substring(0, 1).ToUpperInvariant() + $Token.Substring(1).ToLowerInvariant()
	$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/UI/$Key"
	If($Text -eq $null) { return $Token }
	return $Text
}
