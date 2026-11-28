<#
.SYNOPSIS
    Tests tools\Intune\Detect-SelfXHealth.ps1 (Intune Remediations detection script for the SelfX device status).

.DESCRIPTION
    Isolated: the product type of Windows and the owner of the cache are replaced in the test (functions Get-SelfXDetectProductType and
    Get-SelfXDetectOwnerSid of the script), every file is written below the system temp folder, nothing on the device is changed.
    Checks:
      - static: the script parses, uses no syntax of PowerShell 7 only, is plain ASCII, has no parameter, reads XML without DTD and
        calls no command that changes the device;
      - the cache: missing, older than two intervals (interval from Health_Config.xml), time in the future, broken JSON, empty, larger
        than 60000 bytes, untrusted owner, behind a link (junction), Health_Config.xml with DTD, SelfX not installed, Windows Server;
      - the line: exactly one line, at most 2000 characters also with many apps and check types, worst status per type, failed apps
        with code, Stalled, invalid app IDs and check types left out, no name and no detail text of a row (no user name, no path);
      - exit codes: 1 for Error and for every unusable cache, 0 for OK, Pending and Unknown;
      - one run of the script as its own process (read only): one line, at most 2000 characters, exit code 0 or 1.
    Works in Windows PowerShell 5.1 and PowerShell 7.

.NOTES
    Name    : Test-SelfXHealthDetection.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 3.1.0
    Exit code: 0 = all tests passed, 1 = at least one failed

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-28  fubu2k               Initial version
#>
$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = Join-Path $ScriptFolder 'Intune\Detect-SelfXHealth.ps1'
$hostExe = (Get-Process -Id $PID).Path

$script:Failed = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  PASS $Name" } else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}

Write-Host 'Static checks'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Target, [ref]$tokens, [ref]$parseErrors)
Assert (@($parseErrors).Count -eq 0) 'the script parses in this PowerShell'
Assert (@($ast.FindAll({ param($node) $node.GetType().Name -in 'TernaryExpressionAst', 'PipelineChainAst' }, $true)).Count -eq 0) 'no ternary operator and no pipeline chain operators'
$text = [IO.File]::ReadAllText($Target)
Assert (-not ($text -match '\?\?=?|ForEach-Object\s+-Parallel')) 'no ?? and no ForEach-Object -Parallel'
Assert (@([IO.File]::ReadAllBytes($Target) | Where-Object { $_ -gt 127 }).Count -eq 0) 'plain ASCII (no byte order mark needed)'
Assert ($null -eq $ast.ParamBlock) 'no parameter block: nothing from outside chooses a path'
Assert ($text.Contains('DtdProcessing]::Prohibit') -and $text.Contains('XmlResolver = $null')) 'Health_Config.xml is read without DTD'
$commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
$changing = @($commands | Where-Object { $_ -match '^(Set|New|Remove|Move|Copy|Rename|Clear|Start|Stop|Restart|Invoke|Add)-' -and $_ -notin @('New-Object', 'New-SelfXDetectResult', 'Invoke-SelfXHealthDetection') })
Assert ($changing.Count -eq 0) "no command that changes the device ($($changing -join ', '))"
Assert (-not ($text -match 'Invoke-Expression|Add-Type|Start-Process')) 'no Invoke-Expression, Add-Type or Start-Process'

. $Target

$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXDetectTest_' + [guid]::NewGuid().ToString('N'))
$data = Join-Path $temp 'ProgramData\SelfX'
$install = Join-Path $temp 'Program Files\SelfX'
$cacheFolder = Join-Path $data 'Cache'
$cache = Join-Path $cacheFolder 'Health.json'
$config = Join-Path $install 'Config'
$now = [datetime]::UtcNow
$script:ProductType = 'WinNT'
$script:Owner = 'S-1-5-18'
function Get-SelfXDetectProductType { return $script:ProductType }
function Get-SelfXDetectOwnerSid { param([string]$Path) if ($script:Owner -eq 'real') { return (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value } return $script:Owner }
function Write-TestCache {
    param([string]$Json, [int]$AgeMinutes = 1)
    [IO.File]::WriteAllText($cache, $Json, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::SetLastWriteTimeUtc($cache, $now.AddMinutes(-$AgeMinutes))
}
function Invoke-Test { return (Invoke-SelfXHealthDetection -DataRoot $data -InstallRoot $install -Now $now) }
$appA = '0a1b2c3d-0000-4000-8000-00000000000a'
$appB = '0a1b2c3d-0000-4000-8000-00000000000b'

try {
    New-Item -ItemType Directory -Path $cacheFolder, $config -Force | Out-Null

    Write-Host 'Windows and installation'
    $script:ProductType = 'ServerNT'
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Unavailable | Windows 11 only' -and $r.ExitCode -eq 1) 'Windows Server: Windows 11 only, exit 1'
    $script:ProductType = 'WinNT'
    Remove-Item -LiteralPath $config -Recurse -Force
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Unavailable | SelfX is not installed' -and $r.ExitCode -eq 1) 'no Config folder: not installed, exit 1'
    New-Item -ItemType Directory -Path $config -Force | Out-Null

    Write-Host 'Status cache'
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Unavailable | status cache missing' -and $r.ExitCode -eq 1) 'cache missing, exit 1'
    Write-TestCache '[{"Id":"IME","Name":"","Status":"OK","Detail":"x"}]' -AgeMinutes 31
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Unavailable | status cache is older than 30 minutes (two intervals of the background checks)' -and $r.ExitCode -eq 1) 'cache older than 2 x 15 minutes, exit 1'
    [IO.File]::WriteAllText((Join-Path $config 'Health_Config.xml'), '<HealthConfig><Background IntervalMinutes="60"/></HealthConfig>')
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX OK | IME=OK' -and $r.ExitCode -eq 0) 'interval 60 from Health_Config.xml: 31 minutes is fresh, OK, exit 0'
    Write-TestCache '[{"Id":"IME","Name":"","Status":"OK","Detail":"x"}]' -AgeMinutes 121
    $r = Invoke-Test
    Assert ($r.Line -like '*older than 120 minutes*' -and $r.ExitCode -eq 1) 'interval 60: 121 minutes is too old'
    [IO.File]::WriteAllText((Join-Path $config 'Health_Config.xml'), '<HealthConfig><Background IntervalMinutes="2"/></HealthConfig>')
    Write-TestCache '[{"Id":"IME","Name":"","Status":"OK","Detail":"x"}]' -AgeMinutes 29
    Assert ((Invoke-Test).ExitCode -eq 0) 'interval out of range (2): default 15 is used'
    [IO.File]::WriteAllText((Join-Path $config 'Health_Config.xml'), '<?xml version="1.0"?><!DOCTYPE HealthConfig [<!ENTITY e "x">]><HealthConfig><Background IntervalMinutes="&e;"/></HealthConfig>')
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Unavailable | Health_Config.xml cannot be read' -and $r.ExitCode -eq 1) 'Health_Config.xml with DTD is refused, exit 1'
    Remove-Item -LiteralPath (Join-Path $config 'Health_Config.xml') -Force
    Write-TestCache '[{"Id":"IME","Name":"","Status":"OK","Detail":"x"}]' -AgeMinutes -30
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Unavailable | status cache has a time in the future' -and $r.ExitCode -eq 1) 'time in the future, exit 1'
    Write-TestCache 'not json {"Id":'
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Unavailable | status cache is not valid JSON' -and $r.ExitCode -eq 1) 'broken JSON, exit 1'
    [IO.File]::WriteAllBytes($cache, [byte[]]@(0xC3, 0x28))
    Assert ((Invoke-Test).Line -eq 'SelfX Unavailable | status cache is not valid JSON') 'invalid UTF-8 is not valid JSON'
    Write-TestCache ''
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Unavailable | status cache is empty or larger than 60000 bytes' -and $r.ExitCode -eq 1) 'empty cache, exit 1'
    Write-TestCache ('[{"Id":"IME","Status":"OK","Detail":"' + ('a' * 60000) + '"}]')
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Unavailable | status cache is empty or larger than 60000 bytes' -and $r.ExitCode -eq 1) 'cache larger than 60000 bytes, exit 1'
    Write-TestCache '[]'
    Assert ((Invoke-Test).Line -eq 'SelfX Unavailable | status cache has no results') 'empty list: no results, exit 1'
    Write-TestCache '[{"Id":"IME","Status":"OK"}]'
    foreach ($owner in @('S-1-5-21-1000000000-1000000000-1000000000-1001', 'S-1-5-32-545', 'S-1-1-0', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) {
        $script:Owner = $owner
        $r = Invoke-Test
        Assert ($r.Line -eq 'SelfX Unavailable | status cache has an untrusted owner' -and $r.ExitCode -eq 1) "owner $owner is not trusted, exit 1"
    }
    $script:Owner = 'S-1-5-32-544'
    Assert ((Invoke-Test).ExitCode -eq 0) 'owner Administrators is trusted'
    # The real owner check on the open file (the test file belongs to the user that runs the test).
    $script:Owner = 'real'
    $r = Invoke-Test
    $realOwner = (Get-Acl -LiteralPath $cache).GetOwner([Security.Principal.SecurityIdentifier]).Value
    Assert (($r.ExitCode -eq 0) -eq ($realOwner -in @('S-1-5-18', 'S-1-5-32-544'))) "real owner check on the open file ($realOwner)"
    $script:Owner = 'S-1-5-18'

    # A link: the folder Cache is a junction to another folder with a valid cache.
    $elsewhere = Join-Path $temp 'Elsewhere'
    New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
    Move-Item -LiteralPath $cache -Destination (Join-Path $elsewhere 'Health.json')
    Remove-Item -LiteralPath $cacheFolder -Force
    $junction = $true
    try { New-Item -ItemType Junction -Path $cacheFolder -Target $elsewhere | Out-Null } catch { $junction = $false }
    if ($junction) {
        $r = Invoke-Test
        Assert ($r.Line -eq 'SelfX Unavailable | status cache is behind a link' -and $r.ExitCode -eq 1) 'cache folder is a junction, exit 1'
        [IO.Directory]::Delete($cacheFolder)
    } else { Write-Host '  SKIP junction (could not be created)' }
    if (Test-Path -LiteralPath $cacheFolder) { Remove-Item -LiteralPath $cacheFolder -Recurse -Force }
    New-Item -ItemType Directory -Path $cacheFolder -Force | Out-Null

    Write-Host 'Line and exit code'
    Write-TestCache '{"Id":"IME","Name":"","Status":"OK","Detail":"x"}'
    Assert ((Invoke-Test).Line -eq 'SelfX OK | IME=OK') 'a single row written as an object'
    $rows = @(
        [ordered]@{ Id = 'Disk'; Name = 'C:'; Status = 'OK'; Detail = 'C:\Users\jdoe has 10 GB free' },
        [ordered]@{ Id = 'IME'; Name = ''; Status = 'OK'; Detail = 'running' },
        [ordered]@{ Id = 'Disk'; Name = 'D:'; Status = 'Pending'; Detail = 'x' },
        [ordered]@{ Id = 'Updates'; Name = ''; Status = 'Pending'; Detail = '2 updates' },
        [ordered]@{ Id = 'Custom'; Name = 'jdoe check'; Status = 'Evil'; Detail = 'user jdoe@contoso.com' },
        [ordered]@{ Id = 'Bad;Id=OK'; Name = ''; Status = 'Error'; Detail = 'x' },
        [ordered]@{ Id = 'Applications'; Name = ''; Status = 'Error'; Detail = 'App of jdoe failed'; Apps = @(
                [ordered]@{ Id = $appA; Name = 'Tool of jdoe'; Problem = 'Failed'; Code = '0x87d1041c' },
                [ordered]@{ Id = $appB; Name = 'B'; Problem = 'Stalled'; Code = '' },
                [ordered]@{ Id = $appA.ToUpperInvariant(); Name = 'dup'; Problem = 'Failed'; Code = '0x87D1041C' },
                [ordered]@{ Id = '..\..\Windows'; Name = 'x'; Problem = 'Failed'; Code = '0x80070643' },
                [ordered]@{ Id = '0a1b2c3d-0000-4000-8000-00000000000c'; Name = 'x'; Problem = 'Failed'; Code = 'C:\Users\jdoe' },
                [ordered]@{ Id = '0a1b2c3d-0000-4000-8000-00000000000d'; Name = 'x'; Problem = 'Other'; Code = '0x80070643' }) }
    )
    Write-TestCache (ConvertTo-Json -InputObject $rows -Depth 5 -Compress)
    $r = Invoke-Test
    Assert ($r.Line -eq "SelfX Error | IME=OK; Applications=Error; Disk=Pending; Updates=Pending; Custom=Unknown | FailedApps=${appA}:0x87D1041C, ${appB}:Stalled, 0a1b2c3d-0000-4000-8000-00000000000c:-") "worst status per type in a fixed order, apps with code ($($r.Line))"
    Assert ($r.ExitCode -eq 1) 'a row with Error: exit 1'
    Assert (-not ($r.Line -cmatch 'jdoe|contoso|Users|Tool|C:|running')) 'no name, no detail text, no user name, no path in the line'
    Assert (-not $r.Line.Contains('Bad')) 'a check type with other characters is left out'
    Write-TestCache '[{"Id":"IME","Status":"OK"},{"Id":"Updates","Status":"Pending"},{"Id":"Compliance","Status":"Unknown"}]'
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Pending | IME=OK; Compliance=Unknown; Updates=Pending' -and $r.ExitCode -eq 0) 'Pending and Unknown: exit 0'
    Write-TestCache '[{"Id":"Collection","Name":"","Status":"Unknown","Detail":"Invalid Health_Config.xml root."}]'
    $r = Invoke-Test
    Assert ($r.Line -eq 'SelfX Error | Collection=Error' -and $r.ExitCode -eq 1) 'a failed collection is Error, exit 1'

    # Many apps and many check types: the line stays within 2000 characters.
    $manyApps = @(1..150 | ForEach-Object { [ordered]@{ Id = ('0a1b2c3d-0000-4000-8000-{0:x12}' -f $_); Name = 'n'; Problem = 'Failed'; Code = '0x80070643' } })
    $manyRows = @([ordered]@{ Id = 'Applications'; Status = 'Error'; Apps = $manyApps }) + @(1..60 | ForEach-Object { [ordered]@{ Id = ('Check' + [char](65 + ($_ % 26)) + [char](65 + [int][Math]::Floor($_ / 26)) + ('x' * 20)); Status = 'OK' } })
    Write-TestCache (ConvertTo-Json -InputObject $manyRows -Depth 5 -Compress)
    $r = Invoke-Test
    Assert ($r.Line.Length -le 2000) "line with 150 apps and 60 types has at most 2000 characters ($($r.Line.Length))"
    Assert ($r.Line -match '\(\+\d+ more\)$') 'the apps that do not fit are counted'
    Assert (-not $r.Line.Contains("`n")) 'exactly one line'
    $fewTypes = @([ordered]@{ Id = 'Applications'; Status = 'Error'; Apps = $manyApps })
    Write-TestCache (ConvertTo-Json -InputObject $fewTypes -Depth 5 -Compress)
    $r = Invoke-Test
    Assert (([regex]::Matches($r.Line, ':0x80070643')).Count -eq 20 -and $r.Line.EndsWith('(+130 more)')) 'at most 20 apps, the others counted'
    Assert ((New-SelfXDetectResult -Line ('x' * 3000) -ExitCode 0).Line.Length -eq 2000) 'every line is cut at 2000 characters'

    Write-Host 'Own process (read only, the real paths of this device)'
    $output = @(& $hostExe -NoProfile -ExecutionPolicy Bypass -File $Target)
    $code = $LASTEXITCODE
    Assert ($output.Count -eq 1) "exactly one line of output ($($output.Count))"
    Assert ("$($output[0])".Length -le 2000 -and "$($output[0])".StartsWith('SelfX ')) "the line starts with SelfX and has at most 2000 characters ($($output[0]))"
    Assert ($code -in 0, 1) "exit code 0 or 1 ($code)"
}
finally {
    if (Test-Path -LiteralPath $cacheFolder) {
        $item = Get-Item -LiteralPath $cacheFolder -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($cacheFolder) }
    }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

if ($script:Failed) { Write-Host "FAILED: $script:Failed test(s)." -ForegroundColor Red; exit 1 }
Write-Host 'PASS: Detect-SelfXHealth.ps1 reads the status cache only when it is safe and writes one line without personal data.'
exit 0
