<#
.SYNOPSIS
    Tests the version text of the Citrix Workspace app in the system information (Sources\SystemInfo.ps1).

.DESCRIPTION
    Pure checks of ConvertTo-SelfXCitrixWorkspaceText with simulated program list entries: not installed, current app,
    several entries (the highest version wins), other Citrix products with a similar name (Environment Management agent,
    browser) are ignored, the Receiver is not recognized, missing or odd versions, control characters, long values.
    Nothing is read from the device.

.NOTES
    Name    : Test-CitrixInfo.ps1
    Package : SelfX Service
    Context : Build machine / CI (any user)
    Version : 2.8.25

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.25   2026-11-24  fubu2k               Initial version.
#>
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:errors = New-Object System.Collections.Generic.List[string]
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($env:SELFX_TEST_TRACE) { [Console]::Out.WriteLine("ok: $Message") }
	if ("$Actual" -cne "$Expected") { $script:errors.Add("$Message : expected '$Expected', got '$Actual'.") }
}
. (Join-Path $PSScriptRoot 'Sources\SystemInfo.ps1')
function E($Name, $Version) { [pscustomobject]@{ DisplayName = $Name; DisplayVersion = $Version } }

Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @()) '' 'Empty list: not installed'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @((E 'Microsoft Edge' '130.0'), (E 'Notepad++' '8.7'))) '' 'Other programs: not installed'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @((E 'Citrix Workspace 2409' '24.9.10.64'))) '24.9.10.64 (Citrix Workspace 2409)' 'Workspace app: version and name'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @((E 'Citrix Workspace 2402 LTSR' '24.2.1000.12'))) '24.2.1000.12 (Citrix Workspace 2402 LTSR)' 'LTSR release'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @((E 'Citrix Workspace 2402 LTSR' '24.2.1000.12'), (E 'Citrix Workspace 2409' '24.9.10.64'))) '24.9.10.64 (Citrix Workspace 2409)' 'Two entries: the highest version wins'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @((E 'Citrix Workspace 2409' '24.9.10.64'), (E 'Citrix Workspace Environment Management Agent' '2411.0.0.1'))) '24.9.10.64 (Citrix Workspace 2409)' 'Environment Management agent is ignored'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @((E 'Citrix Workspace Browser' '130.1.2'))) '' 'Citrix browser alone: not the app'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @((E 'Citrix Receiver 4.12' '14.12.0.18020'))) '' 'Receiver is not recognized'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @((E 'Citrix Workspace 2409' ''))) 'Citrix Workspace 2409' 'No version: only the name'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @((E 'Citrix Workspace 2409' 'abc'))) 'abc (Citrix Workspace 2409)' 'Odd version text is kept'
Assert-Equal (ConvertTo-SelfXCitrixWorkspaceText -Entries @($null, (E $null $null), (E 'Citrix Workspace 2409' '24.9.10.64'))) '24.9.10.64 (Citrix Workspace 2409)' 'Empty entries are skipped'
$odd = ConvertTo-SelfXCitrixWorkspaceText -Entries @((E "Citrix Workspace`r`n2409" "24.9`t10"))
Assert-Equal ($odd -match '[\x00-\x1F]') $false 'Control characters are removed'
$long = ConvertTo-SelfXCitrixWorkspaceText -Entries @((E ('Citrix Workspace ' + ('x' * 200)) ('1.' * 40)))
Assert-Equal ($long.Length -le 100) $true 'Long values are shortened'

if ($script:errors.Count) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
