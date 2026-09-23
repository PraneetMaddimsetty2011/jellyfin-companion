$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Core.ps1')
    function Assert($Ok, $Label) { if (-not $Ok) { throw "FAILED: $Label" }; Write-Output "PASS: $Label" }
    $playing = [pscustomobject]@{ NowPlayingItem=@{Id='test'}; PlayState=@{IsPaused=$false} }
    $paused = [pscustomobject]@{ NowPlayingItem=@{Id='test'}; PlayState=@{IsPaused=$true} }
    $browsing = [pscustomobject]@{ NowPlayingItem=$null; PlayState=@{} }
    Assert ((Get-IdleDecision @() 0 $null $null).Remaining -eq 300) 'fresh launch starts at five minutes'
    Assert ((Get-IdleDecision @() 299 0 295).Mode -eq 'Idle') 'no early sleep'
    Assert ((Get-IdleDecision @() 300 0 295).Mode -eq 'Due') 'sleep becomes due at five minutes'
    Assert ((Get-IdleDecision @($paused,$playing) 300 0 295).Mode -eq 'Playing') 'any playing device prevents sleep'
    Assert ($null -eq (Get-IdleDecision @($playing) 100 0 95).IdleSince) 'resuming playback resets countdown'
    Assert ((Get-IdleDecision @($paused,$browsing) 300 0 295).Mode -eq 'Due') 'paused and browsing sessions count as idle'
    Assert ((Get-IdleDecision @() 300 0 295 $false).Mode -eq 'Unavailable') 'API failure blocks sleep'
    Assert ((Get-IdleDecision @() 600 0 295).Remaining -eq 300) 'sleep or monitoring gap resets countdown'
    Assert ((Get-IdleDecision @() 305 $null 300).Remaining -eq 300) 'recovery earns a fresh five minutes'
    $steps = New-Object 'System.Collections.Generic.List[string]'
    Invoke-IdlePowerAction -Action Sleep -DisconnectWifi { $steps.Add('wifi') } -SuspendComputer { $steps.Add('sleep') }
    Assert (($steps -join ',') -eq 'wifi,sleep') 'Wi-Fi disconnect happens before sleep (mocked)'
    $steps.Clear()
    $caught=$false
    try { Invoke-IdlePowerAction -Action Sleep -DisconnectWifi { throw 'mock Wi-Fi error' } -SuspendComputer { $steps.Add('sleep') } } catch { $caught=$true }
    Assert ($caught -and $steps.Count -eq 0) 'Wi-Fi failure stops the action (mocked)'
    $idleSessions=@(ConvertFrom-JellyfinSessions '[{"Id":"phone","PlayState":{"IsPaused":false}},{"Id":"browser","PlayState":{"IsPaused":false}}]')
    Assert ($idleSessions.Count -eq 2) 'multiple JSON sessions are separate devices in Windows PowerShell'
    Assert ((Get-IdleDecision $idleSessions 300 0 295).Mode -eq 'Due') 'two connected but nonplaying devices do not block sleep'
    $mixedSessions=@(ConvertFrom-JellyfinSessions '[{"Id":"phone","PlayState":{"IsPaused":false}},{"Id":"browser","NowPlayingItem":{"Id":"test"},"PlayState":{"IsPaused":false}}]')
    Assert ((Get-IdleDecision $mixedSessions 300 0 295).Playing -eq 1) 'real playback among multiple JSON sessions keeps PC awake'
    $pausedSessions=@(ConvertFrom-JellyfinSessions '[{"Id":"phone","NowPlayingItem":{"Id":"test"},"PlayState":{"IsPaused":true}},{"Id":"browser","PlayState":{"IsPaused":false}}]')
    Assert ((Get-IdleDecision $pausedSessions 300 0 295).Mode -eq 'Due') 'paused plus idle JSON sessions allow sleep'
    $emptySessions=@(ConvertFrom-JellyfinSessions '[]')
    Assert ($emptySessions.Count -eq 0) 'empty JSON response has zero sessions'
    Assert ((Get-IdleDecision $emptySessions 300 0 295).Mode -eq 'Due') 'no connected devices allows sleep'

$disconnected=New-Object 'System.Collections.Generic.List[string]'
$adapters=@(
    [pscustomobject]@{Name='Ethernet';NetworkInterfaceType='Ethernet';OperationalStatus='Up'},
    [pscustomobject]@{Name='Wireless A';NetworkInterfaceType='Wireless80211';OperationalStatus='Up'},
    [pscustomobject]@{Name='Wireless B';NetworkInterfaceType='Wireless80211';OperationalStatus='Down'}
)
Disconnect-ConnectedWifi -Adapters $adapters -Disconnect {param($name);$disconnected.Add($name)}
Assert (($disconnected -join ',') -eq 'Wireless A') 'only connected Wi-Fi interfaces are disconnected (mocked)'
$disconnected.Clear()
Disconnect-ConnectedWifi -Adapters @($adapters[0]) -Disconnect {param($name);$disconnected.Add($name)}
Assert ($disconnected.Count -eq 0) 'Ethernet-only PC skips Wi-Fi disconnection (mocked)'
$rejected=$false
try {ConvertFrom-JellyfinSessions '[null]'} catch {$rejected=$true}
Assert $rejected 'malformed session cannot be treated as zero playback'

$powerSteps=New-Object 'System.Collections.Generic.List[string]'
Invoke-IdlePowerAction -Action Shutdown -DisconnectWifi {$powerSteps.Add('wifi')} -SuspendComputer {throw 'Sleep must not run'} -ShutdownComputer {$powerSteps.Add('shutdown')}
Assert (($powerSteps -join ',') -eq 'wifi,shutdown') 'shutdown mode disconnects Wi-Fi then shuts down, never sleeps (mocked)'
$powerSteps.Clear()
Invoke-IdlePowerAction -Action Sleep -DisconnectWifi {$powerSteps.Add('wifi')} -SuspendComputer {$powerSteps.Add('sleep')} -ShutdownComputer {throw 'Shutdown must not run'}
Assert (($powerSteps -join ',') -eq 'wifi,sleep') 'sleep mode never invokes shutdown (mocked)'
$powerSteps.Clear(); $failed=$false
try {Invoke-IdlePowerAction -Action Shutdown -DisconnectWifi {throw 'mock failure'} -ShutdownComputer {$powerSteps.Add('shutdown')}} catch {$failed=$true}
Assert ($failed -and $powerSteps.Count -eq 0) 'failed Wi-Fi disconnect blocks shutdown (mocked)'
$invalidAction=$false
try {Invoke-IdlePowerAction -Action Restart -DisconnectWifi {throw 'Must not execute'}} catch {$invalidAction=$true}
Assert $invalidAction 'unsupported power action is rejected'
