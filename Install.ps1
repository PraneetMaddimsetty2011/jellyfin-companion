param([switch]$ImportLegacyKey)
$ErrorActionPreference = 'Stop'
$dataDirectory = Join-Path $env:LOCALAPPDATA 'JellyfinCompanion'
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
if ($ImportLegacyKey) {
    $oldKey = Join-Path $env:LOCALAPPDATA 'JellyfinIdleShutdown\api-key.dpapi'
    $newKey = Join-Path $dataDirectory 'api-key.dpapi'
    if ((Test-Path -LiteralPath $oldKey) -and -not (Test-Path -LiteralPath $newKey)) {
        Copy-Item -LiteralPath $oldKey -Destination $newKey
    }
}
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Jellyfin Companion.lnk'
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcut.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'JellyfinCompanion.ps1') + '"'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'Jellyfin server address and playback-aware Wi-Fi disconnect / auto sleep.'
$shortcut.IconLocation = Join-Path $env:SystemRoot 'System32\shell32.dll,14'
$shortcut.Save()
Write-Output "Installed desktop shortcut: $shortcutPath"
Write-Output 'Open it and click Start auto sleep when ready. No startup task is installed.'
