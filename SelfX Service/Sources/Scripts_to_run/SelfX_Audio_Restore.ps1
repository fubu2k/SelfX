<#
.SYNOPSIS
    Switch the sound of the default playback device on again (unmute, minimum volume 30 %).

.DESCRIPTION
    Runs non-interactively in the context of the signed-in user (no administrator rights, no SelfX service). Loads
    SelfXAudio.dll from the install folder after its SHA256 was checked against SelfX.Code.json (SelfXAudio.ps1) and calls
    [SelfX.SelfXAudio]::Restore(30): a muted default playback device is unmuted, a volume below 30 % is raised to 30 %, a higher
    volume stays as it is. The legacy script pressed the mute key (SendKeys), which toggles: an audible device became silent.
    Nothing is toggled here. The microphone, the default device, drivers, services and the registry are not changed, no
    process is started and nothing from the caller is used. The result (muted before, volume before and after) is logged.
    Logs to the user log of SelfX (SelfXLog.ps1).
    Exit 0 = the sound is on (also when nothing had to be changed); exit 1 = the library did not pass the check or the
    audio service could not be reached, for example no playback device exists.

.NOTES
    Name    : SelfX_Audio_Restore.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.18

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard, mute key through SendKeys)
    2.8.18   2026-11-23  fubu2k               Core Audio through SelfXAudio.dll: unmute and minimum volume, no toggle, no SendKeys
#>

# Logging (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; Write-Output "Sound could not be switched on: $($_.Exception.Message)"; exit 1 }

$MinimumVolumePercent = 30
$installFolder = Split-Path -Parent $PSScriptRoot
. (Join-Path $installFolder 'SelfXAudio.ps1')
Import-SelfXAudio -InstallFolder $installFolder
$result = [SelfX.SelfXAudio]::Restore($MinimumVolumePercent)
Write-SelfXLog "Default playback device: muted before $($result.WasMuted), volume $($result.VolumeBeforePercent) % -> $($result.VolumeAfterPercent) % (unmuted $($result.Unmuted), raised $($result.VolumeRaised))."
Write-Output "Sound is on (volume $($result.VolumeAfterPercent) %)."
exit 0
