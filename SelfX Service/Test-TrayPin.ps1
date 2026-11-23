<#
.SYNOPSIS
    Test of Set-TrayIconPromoted (SelfX_Tray.ps1): the Windows 11 notification area entry of the icon is set to IsPromoted = 1.

.DESCRIPTION
    Uses a temporary key under HKCU:\Software (never the real HKCU:\Control Panel\NotifyIconSettings), so the test changes
    nothing on the device. Context: user.

.NOTES
    Name    : Test-TrayPin.ps1
    Package : SelfX Service (build and test only; not shipped)
    Version : 1.0.0
#>
$ErrorActionPreference = 'Stop'
$script:errors = New-Object System.Collections.Generic.List[string]
$script:checks = 0
function Assert-Equal($Actual, $Expected, $Message) {
	$script:checks++
	if ($Actual -ne $Expected) { $script:errors.Add("$Message (expected '$Expected', got '$Actual')") }
}
function Get-FunctionText($Path, $Name) {
	$parseErrors = $null
	$ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
	Assert-Equal @($parseErrors).Count 0 'SelfX_Tray.ps1 parses'
	$definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }.GetNewClosure(), $true)
	Assert-Equal ($null -ne $definition) $true "SelfX_Tray.ps1 defines $Name"
	if (-not $definition) { $script:errors | ForEach-Object { Write-Output "FAIL: $_" }; exit 1 }
	return $definition.Extent.Text
}
# Dot-sourced here (script scope), not inside a function, so the function stays visible.
. ([scriptblock]::Create((Get-FunctionText (Join-Path $PSScriptRoot 'Sources\SelfX_Tray.ps1') 'Set-TrayIconPromoted')))
function Write-SelfXLog { param([string]$Message, [string]$Level = 'Info') }

$root = 'HKCU:\Software\SelfXTrayPinTest_' + [guid]::NewGuid().ToString('N')
try {
	$exe = 'C:\Program Files\PowerShell\7\pwsh.exe'
	New-Item -Path "$root\1" -Force | Out-Null
	New-ItemProperty -Path "$root\1" -Name ExecutablePath -Value $exe -PropertyType String | Out-Null
	New-Item -Path "$root\2" -Force | Out-Null
	New-ItemProperty -Path "$root\2" -Name ExecutablePath -Value 'C:\Other\other.exe' -PropertyType String | Out-Null
	New-Item -Path "$root\3" -Force | Out-Null
	New-ItemProperty -Path "$root\3" -Name ExecutablePath -Value $exe.ToUpperInvariant() -PropertyType String | Out-Null
	New-ItemProperty -Path "$root\3" -Name IsPromoted -Value 1 -PropertyType DWord | Out-Null
	New-Item -Path "$root\4" -Force | Out-Null

	Assert-Equal (Set-TrayIconPromoted -ExecutablePath $exe -SettingsKey $root) 2 'two entries of the program are found (case-insensitive)'
	Assert-Equal ([int](Get-ItemProperty -Path "$root\1").IsPromoted) 1 'the entry of the program is promoted'
	Assert-Equal ((Get-ItemProperty -Path "$root\1").PSObject.Properties['IsPromoted'].TypeNameOfValue) 'System.Int32' 'IsPromoted is a DWORD'
	Assert-Equal ($null -eq (Get-ItemProperty -Path "$root\2").PSObject.Properties['IsPromoted']) $true 'an entry of another program is not changed'
	Assert-Equal ($null -eq (Get-ItemProperty -Path "$root\4").PSObject.Properties['IsPromoted']) $true 'an entry without a path is not changed'
	Assert-Equal (Set-TrayIconPromoted -ExecutablePath $exe -SettingsKey $root) 2 'a second call is harmless'
	Assert-Equal (Set-TrayIconPromoted -ExecutablePath 'C:\Missing\none.exe' -SettingsKey $root) 0 'no matching entry returns 0'
	Assert-Equal (Set-TrayIconPromoted -ExecutablePath '' -SettingsKey $root) 0 'an empty path returns 0'
	Assert-Equal (Set-TrayIconPromoted -ExecutablePath $exe -SettingsKey ($root + '_missing')) 0 'a missing settings key returns 0'
}
finally {
	Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:errors.Count -gt 0) {
	$script:errors | ForEach-Object { Write-Output "FAIL: $_" }
	Write-Output "$($script:errors.Count) of $($script:checks) checks failed."
	exit 1
}
Write-Output "All $($script:checks) checks passed."
exit 0
