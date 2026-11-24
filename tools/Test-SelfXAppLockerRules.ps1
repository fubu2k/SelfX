<#
.SYNOPSIS
    Tests tools\New-SelfXAppLockerRules.ps1 (AppLocker hash rules for the programs) with copies of a Windows program.

.DESCRIPTION
    Isolated: works in a temporary folder, changes no repository file and no AppLocker policy of the computer. The script is
    always started in Windows PowerShell 5.1 (powershell.exe), also when this test runs in PowerShell 7, the way
    Build-SelfXBinaries.ps1 does it. Skipped (exit code 0) when the AppLocker cmdlets are not available. Checks that the rules
    apply to the SID S-1-1-0 (not to the localized name "Everyone"), that every file gets one rule, that paths with spaces
    work and that a missing file, an empty list and a wrong output folder are refused without leaving an output file.

.NOTES
    Name    : Test-SelfXAppLockerRules.ps1
    Package : tools
    Context : Build machine / CI (any user)
    Version : 1.0.0
    Exit code: 0 = all tests passed or skipped, 1 = at least one failed
#>
$ErrorActionPreference = 'Stop'
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
$rulesScript = Join-Path $ScriptFolder 'New-SelfXAppLockerRules.ps1'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$script:Failed = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "  PASS $Name" } else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}
function Invoke-Rules {
    param([string]$PathList, [string]$OutputFile)
    $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $rulesScript -PathList $PathList -OutputFile $OutputFile -RuleNamePrefix 'SelfX test' 2>&1 | Out-String
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Output = $output.Trim() }
}

Write-Host 'Build script'
$build = Get-Content -LiteralPath (Join-Path $ScriptFolder 'Build-SelfXBinaries.ps1') -Raw
Assert ($build -notmatch '-User\s+Everyone') 'Build-SelfXBinaries.ps1 does not use the localized name Everyone'
Assert ($build -match 'New-SelfXAppLockerRules\.ps1') 'Build-SelfXBinaries.ps1 uses New-SelfXAppLockerRules.ps1'

$probe = & $windowsPowerShell -NoProfile -Command "if (@(Get-Command Get-AppLockerFileInformation, New-AppLockerPolicy -ErrorAction SilentlyContinue).Count -eq 2) { 'yes' } else { 'no' }"
if ("$probe".Trim() -ne 'yes') {
    Write-Host '  SKIP the AppLocker cmdlets are not available on this computer'
    if ($script:Failed -gt 0) { exit 1 }
    exit 0
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('SelfX Rules Test ' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $source = Join-Path $env:SystemRoot 'System32\whoami.exe'
    $one = Join-Path $work 'One Program.exe'
    $two = Join-Path $work 'Two.dll'
    Copy-Item -LiteralPath $source -Destination $one
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\kernel32.dll') -Destination $two
    $out = Join-Path $work 'rules.xml'

    Write-Host 'Rules'
    $result = Invoke-Rules -PathList "$one|$two" -OutputFile $out
    Assert ($result.Exit -eq 0) "two files (one path with spaces): exit code 0 ($($result.Output))"
    Assert (Test-Path -LiteralPath $out -PathType Leaf) 'output file is written'
    if (Test-Path -LiteralPath $out) {
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($out)
        $rules = @($document.SelectNodes('//FileHashRule'))
        Assert ($rules.Count -eq 2) 'one hash rule per file'
        Assert (@($rules | Where-Object { $_.GetAttribute('UserOrGroupSid') -ne 'S-1-1-0' }).Count -eq 0) 'all rules apply to the SID S-1-1-0'
        Assert (@($rules | Where-Object { $_.GetAttribute('Action') -ne 'Allow' }).Count -eq 0) 'all rules are Allow rules'
        Assert (@($rules | Where-Object { $_.GetAttribute('Name') -notlike 'SelfX test*' }).Count -eq 0) 'rule names start with the prefix'
        $bytes = [IO.File]::ReadAllBytes($out)
        Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'file is UTF-8 without BOM'
    }

    Write-Host 'Refused input'
    $bad = Join-Path $work 'bad.xml'
    $result = Invoke-Rules -PathList "$one|$(Join-Path $work 'missing.exe')" -OutputFile $bad
    Assert ($result.Exit -eq 1 -and $result.Output -match 'File not found') 'a missing file is refused with a message'
    Assert (-not (Test-Path -LiteralPath $bad)) 'no output file after an error'
    $result = Invoke-Rules -PathList '|' -OutputFile $bad
    Assert ($result.Exit -eq 1 -and $result.Output -match 'No program file') 'an empty list is refused'
    $result = Invoke-Rules -PathList $one -OutputFile (Join-Path $work 'no-folder\rules.xml')
    Assert ($result.Exit -eq 1) 'an output folder that does not exist is refused'
}
finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

if ($script:Failed -gt 0) { Write-Host "$script:Failed test(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed.'
exit 0
