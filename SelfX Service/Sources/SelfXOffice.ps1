<#
.SYNOPSIS
    Helper functions for the Office actions: find the program of an Office app and close it in the own session.

.DESCRIPTION
    Dot-sourced by scripts in Scripts_to_run that run in the user context. Nothing is read from or changed on the
    device when the file is loaded; the functions only read the registry and the process list and close processes of
    the own Windows session.

    Get-SelfXOfficeAppPath finds the program file of classic Outlook, Word or Excel independent of the Office
    version, the bitness (32 or 64 bit) and the installation type (Click-to-Run or MSI). Sources, in this order:
      1. the path of the running process (given by the caller),
      2. the App Paths registration of the program (64 bit and 32 bit view of the registry),
      3. InstallRoot\Path of the app under HKLM\SOFTWARE\Microsoft\Office\<version> (every version found, newest first,
         64 bit and 32 bit view).
    A program is never searched for in PATH or in the current directory. Every candidate is checked
    (Test-SelfXOfficeProgramPath): rooted local path, expected file name, below Program Files (64 bit, 32 bit),
    an existing file that is not a link. The first candidate that passes is returned; otherwise $null.

    Get-SelfXOfficeLicenseFolder lists the folders of the Office license tokens of the signed-in user
    (%LOCALAPPDATA%\Microsoft\Office\Licenses and \Microsoft\Office\<version>\Licensing, every version folder
    that exists). It only reads; it does not delete anything.

    Stop-SelfXOfficeApp closes classic Outlook, Word or Excel of the own session and returns the checked program path for the
    restart actions, which start the app again themselves (this file starts nothing). The path comes from the closed process or the
    registry and must pass Test-SelfXOfficeProgramPath; if no path passes, nothing is closed.

    Get-SelfXOwnSessionProcess and Close-SelfXOwnSessionProcess only touch processes of the Windows session of the
    caller, so other users on a multi-user device are not affected.

.NOTES
    Name    : SelfXOffice.ps1
    Package : SelfX Service
    Context : Dot-sourced by scripts in Scripts_to_run (user context); also loaded by tests
    Version : 2.8.19

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.0    2026-11-23  fubu2k               Initial version (program path independent of version and bitness, own-session processes).
    2.8.4    2026-11-23  fubu2k               Get-SelfXOfficeLicenseFolder (folders of the Office license tokens, independent of the version)
    2.8.19   2026-11-23  fubu2k               Stop-SelfXOfficeApp (shared by the Outlook, Word and Excel restart actions; program path is checked)
#>

$Script:SelfXOfficeApps = @{
	Outlook = @{ Exe = 'OUTLOOK.EXE'; Key = 'Outlook' }
	Word    = @{ Exe = 'WINWORD.EXE'; Key = 'Word' }
	Excel   = @{ Exe = 'EXCEL.EXE'; Key = 'Excel' }
}

function Get-SelfXTrustedProgramFolder {
	# Program Files folders of this device (64 bit, 32 bit); only administrators can write there.
	$folders = foreach ($value in $env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) {
		if ($value) { "$value".TrimEnd('\') }
	}
	@($folders | Select-Object -Unique)
}

function Test-SelfXOfficeProgramPath {
	# $true when the path is a usable program file of the given name below a Program Files folder.
	param([string]$Path, [Parameter(Mandatory = $true)][string]$ExeName)
	$text = "$Path".Trim().Trim('"')
	if (-not $text -or $text.Length -gt 520) { return $false }
	if ($text -match '[\x00-\x1F"<>|*?]') { return $false }
	if (-not [IO.Path]::IsPathRooted($text) -or $text.StartsWith('\\')) { return $false }
	try { $full = [IO.Path]::GetFullPath($text) } catch { return $false }
	if ([IO.Path]::GetFileName($full) -ine $ExeName) { return $false }
	$inside = $false
	foreach ($folder in (Get-SelfXTrustedProgramFolder)) {
		if ($full.StartsWith($folder + '\', [StringComparison]::OrdinalIgnoreCase)) { $inside = $true }
	}
	if (-not $inside) { return $false }
	$item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
	if (-not $item -or $item.PSIsContainer) { return $false }
	if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
	return $true
}

function Get-SelfXOfficeAppPath {
	# Full path of the program of the Office app, or $null when no valid one is found.
	param(
		[Parameter(Mandatory = $true)][ValidateSet('Outlook', 'Word', 'Excel')][string]$Application,
		[string]$ProcessPath
	)
	$app = $Script:SelfXOfficeApps[$Application]
	$candidates = New-Object System.Collections.Generic.List[string]
	if ($ProcessPath) { $candidates.Add($ProcessPath) }
	foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths') {
		$value = (Get-ItemProperty -LiteralPath "$root\$($app.Exe)" -ErrorAction SilentlyContinue).'(default)'
		if ($value) { $candidates.Add("$value") }
	}
	foreach ($officeRoot in 'HKLM:\SOFTWARE\Microsoft\Office', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office') {
		$versions = @(Get-ChildItem -LiteralPath $officeRoot -ErrorAction SilentlyContinue |
			ForEach-Object { $_.PSChildName } |
			Where-Object { $_ -match '^\d{1,3}\.\d{1,3}$' } |
			Sort-Object { [version]$_ } -Descending)
		foreach ($version in $versions) {
			$installRoot = (Get-ItemProperty -LiteralPath "$officeRoot\$version\$($app.Key)\InstallRoot" -ErrorAction SilentlyContinue).Path
			if ($installRoot) { $candidates.Add((Join-Path "$installRoot".Trim().Trim('"') $app.Exe)) }
		}
	}
	foreach ($candidate in $candidates) {
		if (Test-SelfXOfficeProgramPath -Path $candidate -ExeName $app.Exe) { return [IO.Path]::GetFullPath($candidate.Trim().Trim('"')) }
	}
	return $null
}

function Get-SelfXOwnSessionProcess {
	# Processes with the given name(s) in the Windows session of the caller.
	param([Parameter(Mandatory = $true)][string[]]$Name)
	$session = (Get-Process -Id $PID).SessionId
	@(Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
}

function Close-SelfXOwnSessionProcess {
	# Asks the process(es) to close, waits GraceSeconds, then ends what is left and waits up to TimeoutSeconds.
	# Returns $true when no such process of the own session is running any more.
	param(
		[Parameter(Mandatory = $true)][string[]]$Name,
		[int]$GraceSeconds = 10,
		[int]$TimeoutSeconds = 30
	)
	$running = @(Get-SelfXOwnSessionProcess -Name $Name)
	if (-not $running.Count) { return $true }
	foreach ($process in $running) { try { [void]$process.CloseMainWindow() } catch { } }
	for ($i = 0; $i -lt $GraceSeconds -and (Get-SelfXOwnSessionProcess -Name $Name).Count; $i++) { Start-Sleep -Seconds 1 }
	$left = @(Get-SelfXOwnSessionProcess -Name $Name)
	if ($left.Count) { $left | Stop-Process -Force -ErrorAction Stop }
	for ($i = 0; $i -lt $TimeoutSeconds -and (Get-SelfXOwnSessionProcess -Name $Name).Count; $i++) { Start-Sleep -Seconds 1 }
	return (-not (Get-SelfXOwnSessionProcess -Name $Name).Count)
}

function Get-SelfXOfficeLicenseFolder {
	# Existing folders with the Office license tokens of the signed-in user, independent of the Office version:
	# Licenses (shared computer activation and vNext, Office 2019 / 2021 / 2024 / Microsoft 365 Apps) and
	# <version>\Licensing for every version folder (16.0, 15.0, ...). Only folders below LOCALAPPDATA are returned.
	param([string]$LocalAppData = $env:LOCALAPPDATA)
	if (-not $LocalAppData -or -not [IO.Path]::IsPathRooted($LocalAppData)) { return @() }
	$officeRoot = Join-Path $LocalAppData 'Microsoft\Office'
	$folders = New-Object System.Collections.Generic.List[string]
	$folders.Add((Join-Path $officeRoot 'Licenses'))
	foreach ($directory in @(Get-ChildItem -LiteralPath $officeRoot -Directory -ErrorAction SilentlyContinue)) {
		if ($directory.Name -match '^\d{1,3}\.\d{1,3}$') { $folders.Add((Join-Path $directory.FullName 'Licensing')) }
	}
	@($folders | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
}

function Stop-SelfXOfficeApp {
	# Ends the app in the own session at once (unsaved input is lost, as the action tells the user) and waits up to TimeoutSeconds.
	# Returns an object (WasRunning, ProcessCount, Path). Path is the checked program path the caller starts again; the helper itself
	# starts nothing. Nothing is changed when the app is not running. Throws when no valid program path is known (nothing is closed
	# then) or the app does not close.
	param(
		[Parameter(Mandatory = $true)][ValidateSet('Outlook', 'Word', 'Excel')][string]$Application,
		[ValidateRange(1, 120)][int]$TimeoutSeconds = 30
	)
	$app = $Script:SelfXOfficeApps[$Application]
	$name = [IO.Path]::GetFileNameWithoutExtension($app.Exe)
	$running = @(Get-SelfXOwnSessionProcess -Name $name)
	if (-not $running.Count) { return [pscustomobject]@{ WasRunning = $false; ProcessCount = 0; Path = $null } }
	# The path is read before the process ends; it is used only if it passes the check (otherwise the registry is used).
	$processPath = $running | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path
	$path = Get-SelfXOfficeAppPath -Application $Application -ProcessPath $processPath
	if (-not $path) { throw "The program path of $Application could not be determined; $Application was not closed." }
	$running | Stop-Process -Force -ErrorAction Stop
	for ($i = 0; $i -lt $TimeoutSeconds -and (Get-SelfXOwnSessionProcess -Name $name).Count; $i++) { Start-Sleep -Seconds 1 }
	if ((Get-SelfXOwnSessionProcess -Name $name).Count) { throw "$Application is still running after $TimeoutSeconds seconds; it was not restarted." }
	return [pscustomobject]@{ WasRunning = $true; ProcessCount = $running.Count; Path = $path }
}
