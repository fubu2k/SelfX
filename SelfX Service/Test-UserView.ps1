<#
.SYNOPSIS
    Tests the user view (-UserView) of the device log collector: what a normal user never sees in the report.

.DESCRIPTION
    Takes the functions Protect-UserViewText, Hide-OtherUsers, Test-ForeignUserSid, Get-EventSummary and Test-TrustedLogFile and the two
    patterns out of Sources\Scripts_to_run\Collect-DeviceLogs.ps1 (the collector itself is never run) and checks
    them with made-up data: e-mail addresses (UPN) become <hidden>, SIDs of other users become <other user> (the own
    SID stays), event message texts are replaced in the user view and unchanged for administrators. A static check
    makes sure that every area that must not be part of the user report (enrollment account, Autopilot / ESP
    registry values, process command lines, Intune Management Extension, Teams installer and crash report contents,
    other users' ESP phases and Win32Apps keys) is guarded by the user view switch in the collector. Nothing is read
    from the device; only the owner/link test of the Teams installer logs (N9) creates and removes a temporary folder. Runs in PowerShell 7 and Windows PowerShell 5.1:
    pwsh -NoProfile -File .\Test-UserView.ps1

.NOTES
    Name    : Test-UserView.ps1
    Package : SelfX Service
    Context : Packaging test (run by the administrator or the CI before building the package; not installed)
    Version : 2.8.22
    Exit code: 0 = all checks passed, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.20   2026-11-23  fubu2k               Initial version (finding M3: user view of the device logs).
    2.8.22   2026-11-23  fubu2k               Tests for the trusted Teams installer logs (finding N9).
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ("$Actual" -ne "$Expected") { $script:errors.Add("$Message (expected '$Expected', found '$Actual')") }
}

$collector = Join-Path $PSScriptRoot 'Sources\Scripts_to_run\Collect-DeviceLogs.ps1'
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { $collector = Join-Path $PSScriptRoot 'Sources/Scripts_to_run/Collect-DeviceLogs.ps1' }
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($collector, [ref]$tokens, [ref]$parseErrors)
Assert-Equal @($parseErrors).Count 0 'Collect-DeviceLogs.ps1 parses'

# Load only the needed functions and the two patterns, never the rest of the collector.
foreach ($name in 'Protect-UserViewText', 'Hide-OtherUsers', 'Test-ForeignUserSid', 'Get-EventSummary', 'Test-TrustedLogFile') {
	$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
	Assert-Equal ($null -ne $definition) $true "Collect-DeviceLogs.ps1 defines $name"
	if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
	. ([scriptblock]::Create($definition.Extent.Text))
}
foreach ($variable in '$script:UserViewMailPattern', '$script:UserViewSidPattern') {
	$assignment = $ast.Find({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq $variable }, $true)
	Assert-Equal ($null -ne $assignment) $true "Collect-DeviceLogs.ps1 defines $variable"
	if (-not $assignment) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
	. ([scriptblock]::Create($assignment.Extent.Text))
}

$ownSid = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
$otherSid = 'S-1-5-21-1111111111-2222222222-3333333333-1002'
$entraOther = 'S-1-12-1-1234567890-1234567890-1234567890-1234567890'
$script:CallerSid = $ownSid
$script:OtherUserPattern = $null
$UserView = [switch]::new($true)

# 1. Protect-UserViewText: addresses and SIDs
Assert-Equal (Protect-UserViewText 'UPN=alice@contoso.com; x') 'UPN=<hidden>; x' 'e-mail address (UPN) is hidden'
Assert-Equal (Protect-UserViewText "a.b-c_d+tag@sub.contoso.co.uk and o'neil@contoso.de") '<hidden> and <hidden>' 'several addresses, sub domains, apostrophe'
Assert-Equal (Protect-UserViewText "profile $ownSid ok") "profile $ownSid ok" 'the own SID stays'
Assert-Equal (Protect-UserViewText "profile $otherSid ok") 'profile <other user> ok' 'SID of another local or domain user is hidden'
Assert-Equal (Protect-UserViewText "Win32Apps\$entraOther\app") 'Win32Apps\<other user>\app' 'SID of another Entra user is hidden'
Assert-Equal (Protect-UserViewText $ownSid.ToLowerInvariant()) $ownSid.ToLowerInvariant() 'the own SID is recognized without regard to case'
Assert-Equal (Protect-UserViewText 'S-1-5-18 and S-1-5-32-544') 'S-1-5-18 and S-1-5-32-544' 'well-known SIDs stay'
Assert-Equal (Protect-UserViewText 'Computer DEVICE01, 10.0.0.1, 0x80070005') 'Computer DEVICE01, 10.0.0.1, 0x80070005' 'other text stays unchanged'
Assert-Equal (Protect-UserViewText '') '' 'empty text'
Assert-Equal (Protect-UserViewText $null) '' 'null text'

# 2. Hide-OtherUsers: profile names and the new protection layer; administrators are unchanged
$script:OtherUserPattern = [regex]::new('(?<![\w-])(bob)(?![\w-])', 'IgnoreCase')
$UserView = [switch]::new($true)
Assert-Equal (Hide-OtherUsers "C:\Users\bob\x alice@contoso.com $otherSid") 'C:\Users\<other user>\x <hidden> <other user>' 'user view: name, address and SID'
$UserView = [switch]::new($false)
Assert-Equal (Hide-OtherUsers "alice@contoso.com $otherSid") "alice@contoso.com $otherSid" 'administrator: no address or SID filter'
$script:OtherUserPattern = $null
$UserView = [switch]::new($true)

# 3. Test-ForeignUserSid
Assert-Equal (Test-ForeignUserSid "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\$otherSid\app_1") $true 'key of another user'
Assert-Equal (Test-ForeignUserSid "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\$entraOther\app_1") $true 'key of another Entra user'
Assert-Equal (Test-ForeignUserSid "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\$ownSid\app_1") $false 'own key'
Assert-Equal (Test-ForeignUserSid 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\00000000-0000-0000-0000-000000000000\app_1') $false 'device key'
Assert-Equal (Test-ForeignUserSid 'Device') $false 'ESP device phase'
Assert-Equal (Test-ForeignUserSid $otherSid) $true 'ESP phase of another user'
Assert-Equal (Test-ForeignUserSid "$ownSid\x $otherSid") $true 'own and foreign SID in one path'

# 4. Get-EventSummary: no message text in the user view
function Get-WinEvent {
	param($FilterHashtable, $MaxEvents, $ErrorAction)
	return @([pscustomobject]@{ TimeCreated = [datetime]'2026-11-20 08:00:00'; Id = 762; LevelDisplayName = 'Error'; ProviderName = 'Provider'; Message = 'SECRET-MESSAGE alice@contoso.com C:\Users\alice\f.docx' })
}
$Days = 7
$UserView = [switch]::new($true)
$out = @(Get-EventSummary -LogName 'System' -Level $null -Max 5)
Assert-Equal $out.Count 2 'user view: header and one event'
Assert-Equal ($out[1] -like '*id=762*Provider*') $true 'user view: time, id, level and provider remain'
Assert-Equal (($out -join "`n") -match 'SECRET|alice|contoso|C:\\') $false 'user view: no message text'
$out = @(Get-EventSummary -LogName 'System' -Level $null -Max 5 -MessageLike 'SECRET')
Assert-Equal $out.Count 2 'user view: the message filter still works'
Assert-Equal (($out -join "`n") -match 'SECRET-MESSAGE|alice@') $false 'user view: no message text with a message filter'
$UserView = [switch]::new($false)
$out = @(Get-EventSummary -LogName 'System' -Level $null -Max 5)
Assert-Equal ($out[1] -like '*SECRET-MESSAGE*') $true 'administrator: the message text stays'

# 4b. N9: Teams installer logs are only used when the file is trusted (owner, links). Needs Windows (owner, junction);
# creates and removes a temporary folder in the temp directory of the running account.
if ($PSVersionTable.PSEdition -ne 'Core' -or $IsWindows) {
	$trustRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfXTrust_' + [guid]::NewGuid().ToString('N'))
	$null = New-Item -ItemType Directory -Path $trustRoot
	try {
		$plain = Join-Path $trustRoot 'teams.log'
		Set-Content -LiteralPath $plain -Value 'x'
		# The owner of a new file is the account or, for an elevated process, the Administrators group: read it instead of assuming it.
		$me = (Get-Acl -LiteralPath $plain).GetOwner([Security.Principal.SecurityIdentifier]).Value
		Assert-Equal (Test-TrustedLogFile -File (Get-Item -LiteralPath $plain) -Root $trustRoot -TrustedOwnerSids @($me)) $true 'N9: file of a trusted owner is trusted'
		Assert-Equal (Test-TrustedLogFile -File (Get-Item -LiteralPath $plain) -Root $trustRoot -TrustedOwnerSids @('S-1-5-21-1-2-3-9999')) $false 'N9: file of another owner is not trusted'
		$linked = Join-Path $trustRoot 'teams-link.log'
		& cmd.exe /c mklink /H "$linked" "$plain" | Out-Null
		if (Test-Path -LiteralPath $linked) {
			Assert-Equal (Test-TrustedLogFile -File (Get-Item -LiteralPath $linked -Force) -Root $trustRoot -TrustedOwnerSids @($me)) $false 'N9: hard link is not trusted'
		}
		$target = Join-Path $trustRoot 'target'
		$null = New-Item -ItemType Directory -Path $target
		Set-Content -LiteralPath (Join-Path $target 'teams.log') -Value 'x'
		$junction = Join-Path $trustRoot 'junction'
		& cmd.exe /c mklink /J "$junction" "$target" | Out-Null
		if (Test-Path -LiteralPath $junction) {
			Assert-Equal (Test-TrustedLogFile -File (Get-Item -LiteralPath (Join-Path $junction 'teams.log') -Force) -Root $trustRoot -TrustedOwnerSids @($me)) $false 'N9: file below a junction is not trusted'
			(Get-Item -LiteralPath $junction -Force).Delete()
		}
	}
	finally { Remove-Item -LiteralPath $trustRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

# 5. Static check of the collector: every area is guarded by the user view
$text = [IO.File]::ReadAllText($collector)
function Test-Pattern($Pattern, $Message) { Assert-Equal ([regex]::IsMatch($text, $Pattern)) $true $Message }
Test-Pattern "(?s)Invoke-Safe 'Autopilot registry' \{\s*if \(\`$UserView\) \{[^}]*\breturn\s*\}\s*Get-RegistryTree" 'Autopilot registry values are omitted before they are read'
Test-Pattern "(?s)Invoke-Safe 'ESP tracking' \{\s*if \(\`$UserView\) \{[^}]*\breturn\s*\}\s*Get-RegistryTree" 'raw ESP tracking tree is omitted before it is read'
Test-Pattern "(?s)Invoke-Safe 'Enrollments' \{.*?if \(\`$UserView\) \{.*?UPN=\(administrators only\).*?continue\s*\}.*?\`$values\.UPN" 'enrollment: the user view prints no UPN and no ids and continues before the full line'
Assert-Equal ([regex]::Matches($text, '\\FirstSync"').Count) 1 'FirstSync tree is read in one place only (after the user view branch)'
Test-Pattern "ESPTrackingInfo' -and \(-not \`$UserView -or -not \(Test-ForeignUserSid \`$_\.PSChildName\)\)" 'ESP phases of other users are skipped'
Test-Pattern "\`$shownProfileName = if \(\`$UserView\) \{ '\(administrators only\)' \}" 'Autopilot profile name is hidden'
Test-Pattern "if \(\`$UserView\) \{ \`$cmd = '\(administrators only\)' \}" 'process command lines are hidden'
Test-Pattern "(?s)if \(-not \`$app\.Id\) \{ continue \}\s*if \(\`$UserView\) \{[^}]*continue \}" 'IME log lines of failed apps are omitted'
Test-Pattern "(?s)Invoke-Safe 'IME filtered' \{\s*if \(\`$UserView\) \{[^}]*\breturn\s*\}" 'IME log contents are omitted'
Test-Pattern 'if \(\$UserView -and \(Test-ForeignUserSid \$key\.Name\)\) \{ continue \}' 'Win32Apps keys of other users are skipped'
Test-Pattern "(?s)\`$wer = Join-Path.*?if \(\`$UserView\) \{[^}]*break \}" 'crash report contents are omitted'
Test-Pattern "(?s)if \(\`$UserView -and \`$logs\.Count\).*?foreach \(\`$log in @\(\`$logs \| Select-Object -First 2\)\) \{\s*if \(\`$UserView\) \{ break \}" 'Teams installer log contents are omitted'
Test-Pattern 'Write-Host "  \$\(Hide-OtherUsers \$finding\)"' 'console output of the findings passes through the filter'
Test-Pattern 'function Add-Line \{ param\(\[string\]\$Text\) \$writer\.WriteLine\(\(Hide-OtherUsers \$Text\)\) \}' 'every report line passes through Hide-OtherUsers'
Test-Pattern 'function Add-FileTail \{\s*param[^\r\n]*\s*Add-Line ''''\s*#[^\r\n]*\s*if \(\$UserView\) \{[^}]*return \}' 'file tails (IME, CBS, DISM, setup, Windows Update) are omitted'
Test-Pattern 'function Add-FilteredLines \{\s*param[^\r\n]*\s*if \(\$UserView\) \{[^}]*return \}' 'filtered log lines are omitted'
Test-Pattern "\`$ScriptVersion = '1\.3\.5'" 'script version 1.3.5'
Test-Pattern "(?s)Invoke-Safe 'Teams bootstrapper logs'.*?Test-TrustedLogFile -File \`$candidate -Root \`$folder -TrustedOwnerSids \`$trustedOwners" 'Teams installer logs: only trusted files (owner, links) are listed and read'

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $script:checks checks failed."
	exit 1
}
Write-Output "PASS: $script:checks checks. The user view hides accounts, tenant data, command lines, log contents, event texts and other users."
exit 0
