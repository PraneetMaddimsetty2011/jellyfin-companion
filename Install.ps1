param([switch]$ImportLegacyKey,
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'JellyfinCompanion'),
    [string]$ShortcutDirectory = ([Environment]::GetFolderPath('Desktop')))
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
if ($ImportLegacyKey) {
    $oldKey = Join-Path $env:LOCALAPPDATA 'JellyfinIdleShutdown\api-key.dpapi'
    $newKey = Join-Path $dataDirectory 'api-key.dpapi'
    if ((Test-Path -LiteralPath $oldKey) -and -not (Test-Path -LiteralPath $newKey)) {
        Copy-Item -LiteralPath $oldKey -Destination $newKey
    }
}
New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
$shortcutPath = Join-Path $ShortcutDirectory 'Jellyfin Companion.lnk'
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcut.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'JellyfinCompanion.ps1') + '" -DataDirectory "' + $DataDirectory + '"'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'Jellyfin server address and playback-aware auto sleep or shutdown.'
$shortcut.IconLocation = Join-Path $env:SystemRoot 'System32\shell32.dll,14'
$shortcut.Save()
Write-Output "Installed desktop shortcut: $shortcutPath"
Write-Output 'Open it, choose Sleep or Shut down, then click Start when ready. No startup task is installed.'
