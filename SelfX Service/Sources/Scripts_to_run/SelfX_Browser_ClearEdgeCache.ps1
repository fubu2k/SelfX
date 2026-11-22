<#
.SYNOPSIS
    Close Microsoft Edge and clear its cache (cache only).

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Closes the msedge.exe processes of the user's
    session, waits two seconds and removes only the cache folders (Cache, Code Cache, GPUCache) of the
    Default profile under LOCALAPPDATA\Microsoft\Edge\User Data. Cookies, history, saved passwords,
    autofill data, bookmarks, extensions and other profiles are not touched, so the user stays signed in.
    Folders that are links (junctions or symbolic links) are skipped and logged, so the action never
    deletes outside the Edge profile. Open Edge windows close without saving session state; unsaved
    input on websites is lost. Does not close WebView2 applications (msedgewebview2.exe).
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = done (also when Edge is not installed); exit 1 = at least one item could not be removed.

.NOTES
    Name    : SelfX_Browser_ClearEdgeCache.ps1
    Package : SelfX Service
    Context : User
    Version : 2.8.2

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.2    2026-11-22  fubu2k               Initial version (cache only, Default profile, own session)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# Close Edge first (own session only) so open cache handles are released.
$session = (Get-Process -Id $PID).SessionId
$processes = @(Get-Process -Name msedge -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
$processes | Stop-Process -Force -ErrorAction SilentlyContinue
Write-SelfXLog "Closed $($processes.Count) Edge process(es)."
Start-Sleep -Seconds 2

$profilePath = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default'
$failed = 0
if (Test-Path -LiteralPath $profilePath) {
	# Fixed list of cache folders; nothing else is removed.
	foreach ($cacheName in @('Cache', 'Code Cache', 'GPUCache')) {
		$path = Join-Path $profilePath $cacheName
		if (-not (Test-Path -LiteralPath $path)) { continue }
		try {
			if ((Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
				$failed++
				Write-SelfXLog "Skipped $cacheName : it is a link, not a normal folder." Warning
				continue
			}
			Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction Stop
			Write-SelfXLog "Removed $cacheName."
		} catch {
			$failed++
			Write-SelfXLog "Could not remove $cacheName : $($_.Exception.Message)" Warning
		}
	}
} else {
	Write-SelfXLog "No Edge Default profile found ($profilePath)."
}
Write-SelfXLog "Finished, $failed item(s) not removed."
if ($failed) { exit 1 }
exit 0
