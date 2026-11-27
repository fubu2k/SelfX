<#
.SYNOPSIS
    Checks the SelfX language files for completeness and errors.

.DESCRIPTION
    Compares every file in Sources\Languages (or only the files given with -Culture) with the English
    reference en.xml and the action catalogue Issues_List.xml and reports:
      - files that are not valid XML or have a wrong root element / Culture attribute
      - missing or unknown texts in the UI and SystemInfo sections
      - missing or unknown categories, shared messages and actions of the catalogue
      - placeholders ({0}, {1:D2} ...) that differ from the English text
      - a different number of "|" separators in SystemInfo_Export_Filter

    The Copilot prompts (Copilot_Prompt_User / Copilot_Prompt_Admin) exist in en and de only. Every other language uses the English
    prompt on purpose: it tells Copilot to answer in the language of the problem description (Test-CopilotFacts.ps1 checks the files).
    Missing texts are warnings (SelfX shows the English text instead). Wrong placeholders, unknown
    Ids and invalid files are errors. The script only reads files; it changes nothing.

    Text overrides: every file Texts\<culture>.xml (next to the Sources folder content, in the package Config\Texts) is checked with the
    same functions that SelfX uses at start (Localization.ps1: Read-SelfXTextOverride). Errors: a file name that is no culture
    name, a file that is a link, too large, not valid XML (a DTD is refused), has another root element or Culture, and a text that
    SelfX would reject (empty, longer than 1500 characters, markup, control characters, other placeholders than the bundled text).
    Warnings: a text id that no bundled file knows (SelfX ignores it and writes it to the log) and a file without a bundled
    language file of the same name (it is never used).

.PARAMETER SourcesFolder
    Sources folder of the package. Default: the Sources folder next to this script.

.PARAMETER TextsFolder
    Folder with the text overrides. Default: the folder Texts next to the Languages folder. A missing folder is not an error.

.PARAMETER Culture
    Optional list of cultures to check, for example de, fr. Default: all files (language files and text overrides).

.EXAMPLE
    .\Test-LanguageFiles.ps1
    .\Test-LanguageFiles.ps1 -Culture de, it

.NOTES
    Name    : Test-LanguageFiles.ps1
    Package : SelfX Service
    Context : Packaging tool (run by the administrator before building the package; not installed)
    Version : 3.1.0
    Exit code: 0 = no errors, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.2.0    2026-10-28  Wolfgang Baeck       Initial version
    3.1.0    2026-11-27  fubu2k               Checks the text overrides Texts\<culture>.xml with the functions of Localization.ps1 (TextsFolder)
#>
param(
	[string]$SourcesFolder = (Join-Path $PSScriptRoot 'Sources'),
	[string]$TextsFolder = (Join-Path $SourcesFolder 'Texts'),
	[string[]]$Culture
)

$LanguageFolder = Join-Path $SourcesFolder 'Languages'
# The same functions as SelfX uses at start (Test-SelfXLanguageName, Read-SelfXTextOverride): this check cannot differ from the loader.
. (Join-Path $SourcesFolder 'Localization.ps1')

Function Read-Xml([string]$Path)
{
	$Document = New-Object System.Xml.XmlDocument
	$Document.Load($Path)
	return $Document
}

Function Get-Placeholders([string]$Text)
{
	# Sorted list of {n} / {n:format} placeholders, used to compare a translation with the English text
	return (([regex]::Matches("$Text", '\{\d+(:[^}]*)?\}') | ForEach-Object { $_.Value } | Sort-Object) -join ' ')
}

Function Get-Section([System.Xml.XmlDocument]$Document, [string]$XPath)
{
	# Element name -> text of all child elements of a section
	$Table = @{}
	$Node = $Document.SelectSingleNode($XPath)
	If($Node -ne $null)
		{
			foreach($Child in $Node.ChildNodes)
				{
					If($Child.NodeType -eq 'Element') { $Table[$Child.LocalName] = $Child.InnerText }
				}
		}
	return $Table
}

Function Get-IdTable([System.Xml.XmlDocument]$Document, [string]$XPath)
{
	# Id attribute -> element, for categories, messages and actions
	$Table = @{}
	foreach($Node in $Document.SelectNodes($XPath)) { $Table[$Node.GetAttribute('Id')] = $Node }
	return $Table
}

$Reference = Read-Xml (Join-Path $LanguageFolder 'en.xml')
$Catalog = Read-Xml (Join-Path $SourcesFolder 'Issues_List.xml')

$Reference_UI = Get-Section $Reference '/SelfX_Language/UI'
$Reference_SystemInfo = Get-Section $Reference '/SelfX_Language/SystemInfo'
$Reference_Categories = Get-IdTable $Reference '/SelfX_Language/Catalog/Categories/Category'
$Catalog_Messages = Get-IdTable $Catalog '/Actions/Messages/Message'
$Catalog_Actions = Get-IdTable $Catalog '/Actions/*/Action'

$Files = Get-ChildItem -LiteralPath $LanguageFolder -Filter '*.xml' | Sort-Object Name
If($Culture) { $Files = $Files | Where-Object { $Culture -contains $_.BaseName } }

$Total_Errors = 0
$Results = foreach($File in $Files)
	{
		$Errors = New-Object System.Collections.Generic.List[string]
		$Warnings = New-Object System.Collections.Generic.List[string]
		Try
			{
				$Document = Read-Xml $File.FullName
			}
		Catch
			{
				$Errors.Add("Invalid XML: $($_.Exception.Message)")
				$Document = $null
			}

		If($Document -ne $null)
			{
				$Root = $Document.DocumentElement
				If($Root.LocalName -ne 'SelfX_Language') { $Errors.Add("Root element must be SelfX_Language") }
				If($Root.GetAttribute('Culture') -ne $File.BaseName) { $Errors.Add("Culture attribute '$($Root.GetAttribute('Culture'))' does not match the file name") }
				If(@('LeftToRight', 'RightToLeft') -notcontains $Root.GetAttribute('FlowDirection')) { $Errors.Add("FlowDirection must be LeftToRight or RightToLeft") }
				Try { [void][System.Globalization.CultureInfo]::GetCultureInfo($File.BaseName) } Catch { $Errors.Add("'$($File.BaseName)' is not a known culture name") }

				# UI and SystemInfo texts: same element names and placeholders as en.xml
				foreach($Pair in @(@('/SelfX_Language/UI', $Reference_UI), @('/SelfX_Language/SystemInfo', $Reference_SystemInfo)))
					{
						$Texts = Get-Section $Document $Pair[0]
						foreach($Key in $Pair[1].Keys)
							{
								If($Key -like 'Copilot_Prompt_*' -and $File.BaseName -ne 'de') { continue }
								If((-not $Texts.ContainsKey($Key)) -or [string]::IsNullOrWhiteSpace($Texts[$Key])) { $Warnings.Add("Missing text $($Pair[0])/$Key"); continue }
								If((Get-Placeholders $Texts[$Key]) -ne (Get-Placeholders $Pair[1][$Key])) { $Errors.Add("Placeholders differ in $Key") }
							}
						foreach($Key in $Texts.Keys) { If(-not $Pair[1].ContainsKey($Key)) { $Errors.Add("Unknown text $($Pair[0])/$Key") } }
					}
				$Filter = $Document.SelectSingleNode('/SelfX_Language/UI/SystemInfo_Export_Filter')
				If(($Filter -ne $null) -and (($Filter.InnerText.Split('|').Count) -ne ($Reference_UI['SystemInfo_Export_Filter'].Split('|').Count)))
					{
						$Errors.Add("SystemInfo_Export_Filter must keep the same number of '|' separators")
					}

				# Catalogue: categories, shared messages and actions
				$Categories = Get-IdTable $Document '/SelfX_Language/Catalog/Categories/Category'
				foreach($Id in $Reference_Categories.Keys) { If(-not $Categories.ContainsKey($Id)) { $Warnings.Add("Missing category $Id") } }
				foreach($Id in $Categories.Keys) { If(-not $Reference_Categories.ContainsKey($Id)) { $Errors.Add("Unknown category $Id") } }

				If($File.BaseName -ne 'en')
					{
						$Messages = Get-IdTable $Document '/SelfX_Language/Catalog/Messages/Message'
						foreach($Id in $Catalog_Messages.Keys) { If(-not $Messages.ContainsKey($Id)) { $Warnings.Add("Missing message $Id") } }
						foreach($Id in $Messages.Keys) { If(-not $Catalog_Messages.ContainsKey($Id)) { $Errors.Add("Unknown message $Id") } }

						$Actions = Get-IdTable $Document '/SelfX_Language/Catalog/Actions/Action'
						foreach($Id in $Catalog_Actions.Keys)
							{
								If(-not $Actions.ContainsKey($Id)) { $Warnings.Add("Missing action $Id"); continue }
								foreach($Field in 'Name', 'Explanation', 'Alerte_MSG')
									{
										# Fields that use a shared message (Ref) need no own translation
										$Base = $Catalog_Actions[$Id].SelectSingleNode($Field)
										If(($Base -eq $null) -or $Base.GetAttribute('Ref')) { continue }
										$Node = $Actions[$Id].SelectSingleNode($Field)
										If(($Node -eq $null) -or [string]::IsNullOrWhiteSpace($Node.InnerText)) { $Warnings.Add("Missing $Field of action $Id") }
									}
							}
						foreach($Id in $Actions.Keys) { If(-not $Catalog_Actions.ContainsKey($Id)) { $Errors.Add("Unknown action $Id") } }
					}
			}

		$Total_Errors += $Errors.Count
		foreach($Message in $Errors) { Write-Host "[$($File.BaseName)] ERROR   $Message" -ForegroundColor Red }
		foreach($Message in $Warnings) { Write-Host "[$($File.BaseName)] WARNING $Message" -ForegroundColor Yellow }

		[pscustomobject]@{
			Culture    = $File.BaseName
			NativeName = $(If($Document -ne $null) { $Document.DocumentElement.GetAttribute('NativeName') })
			Direction  = $(If($Document -ne $null) { $Document.DocumentElement.GetAttribute('FlowDirection') })
			Errors     = $Errors.Count
			Warnings   = $Warnings.Count
		}
	}

$Results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

# Text overrides: Texts\<culture>.xml
If(Test-Path -LiteralPath $TextsFolder -PathType Container)
	{
		$English = Read-SelfXLanguageFile -Path (Join-Path $LanguageFolder 'en.xml')
		$German = Read-SelfXLanguageFile -Path (Join-Path $LanguageFolder 'de.xml')
		$TextFiles = @(Get-ChildItem -LiteralPath $TextsFolder -File -Force | Sort-Object Name)
		If($Culture) { $TextFiles = @($TextFiles | Where-Object { $Culture -contains $_.BaseName }) }
		$TextResults = foreach($File in $TextFiles)
			{
				$Errors = New-Object System.Collections.Generic.List[string]
				$Warnings = New-Object System.Collections.Generic.List[string]
				$Applied = 0
				If(($File.Extension -cne '.xml') -or -not (Test-SelfXLanguageName $File.BaseName))
					{
						$Errors.Add("'$($File.Name)' is not a text override: the file name must be <culture>.xml, for example de.xml (the package build refuses the file)")
					}
				Else
					{
						$Bundled = Read-SelfXLanguageFile -Path (Join-Path $LanguageFolder "$($File.BaseName).xml")
						If($Bundled -eq $null) { $Warnings.Add("There is no bundled language file '$($File.BaseName).xml': the override is never used") }
						$Reference = Get-SelfXTextReference -Document @($Bundled, $English, $German)
						$Override = Read-SelfXTextOverride -Path $File.FullName -Culture $File.BaseName -Reference $Reference
						$Applied = $Override.Texts.Count
						foreach($Problem in $Override.Problems)
							{
								$Where = $(If($Problem.Key) { " $($Problem.Key):" } Else { '' })
								If($Problem.Kind -eq 'Unknown') { $Warnings.Add("$Where $($Problem.Message)".Trim()) }
								Else { $Errors.Add("$Where $($Problem.Message)".Trim()) }
							}
					}
				$Total_Errors += $Errors.Count
				foreach($Message in $Errors) { Write-Host "[Texts\$($File.BaseName)] ERROR   $Message" -ForegroundColor Red }
				foreach($Message in $Warnings) { Write-Host "[Texts\$($File.BaseName)] WARNING $Message" -ForegroundColor Yellow }
				[pscustomobject]@{ TextOverride = $File.Name; Accepted = $Applied; Errors = $Errors.Count; Warnings = $Warnings.Count }
			}
		If(@($TextResults).Count -gt 0) { $TextResults | Format-Table -AutoSize | Out-String -Width 200 | Write-Host }
	}
If($Total_Errors -gt 0) { exit 1 }
exit 0
