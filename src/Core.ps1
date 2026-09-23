function Get-IdleDecision {
    param($Sessions, [double]$Now, $IdleSince, $PreviousCheck, [bool]$Healthy = $true)
    if (-not $Healthy) { return @{ Mode='Unavailable'; IdleSince=$null; Remaining=300; Playing=0 } }
    $playing = @($Sessions | Where-Object { $null -ne $_.NowPlayingItem -and $_.PlayState.IsPaused -ne $true }).Count
    if ($playing -gt 0) { return @{ Mode='Playing'; IdleSince=$null; Remaining=300; Playing=$playing } }
    # A suspended PC or stalled monitor must earn a fresh five minutes of observed idle.
    if ($null -eq $IdleSince -or ($null -ne $PreviousCheck -and ($Now - $PreviousCheck) -gt 20)) { $IdleSince=$Now }
    $remaining = [Math]::Max(0, [Math]::Ceiling(300 - ($Now - $IdleSince)))
    return @{ Mode=$(if ($remaining -eq 0) {'Due'} else {'Idle'}); IdleSince=$IdleSince; Remaining=$remaining; Playing=0 }
}

function Disconnect-ConnectedWifi {
    param(
        [object[]]$Adapters = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces(),
        [scriptblock]$Disconnect = {
            param([string]$InterfaceName)
            $null = & "$env:SystemRoot\System32\netsh.exe" wlan disconnect ("interface=" + $InterfaceName) 2>&1
            if ($LASTEXITCODE -ne 0) { throw 'Windows could not disconnect Wi-Fi. The power action was not requested.' }
        }
    )
    foreach ($adapter in $Adapters) {
        if ($adapter.NetworkInterfaceType -eq 'Wireless80211' -and $adapter.OperationalStatus -eq 'Up') {
            & $Disconnect $adapter.Name
        }
    }
}

function Invoke-IdlePowerAction {
    param(
        [ValidateSet('Sleep','Shutdown')][string]$Action = 'Sleep',
        [scriptblock]$DisconnectWifi = {
            Disconnect-ConnectedWifi
        },
        [scriptblock]$SuspendComputer = {
            $accepted = [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $true, $false)
            if (-not $accepted) { throw 'Windows rejected the sleep request.' }
        },
        [scriptblock]$ShutdownComputer = {
            # /t 0 without /f permits applications with unsaved work to block shutdown.
            & "$env:SystemRoot\System32\shutdown.exe" /s /t 0 /d p:0:0 /c 'Jellyfin has had no playback for five minutes.'
            if ($LASTEXITCODE -ne 0) { throw 'Windows rejected the shutdown request.' }
        }
    )
    & $DisconnectWifi
    if ($Action -eq 'Shutdown') { & $ShutdownComputer } else { & $SuspendComputer }
}
function ConvertFrom-JellyfinSessions {
    param([string]$Json)
    if ($Json -notmatch '^\s*\[') { throw 'Unexpected Jellyfin session response.' }
    # Windows PowerShell 5.1 returns JSON arrays as a single pipeline object.
    # Assign first, then enumerate the parsed array on this function's output.
    $parsed = ConvertFrom-Json -InputObject $Json
    foreach ($item in $parsed) {
        if ($null -eq $item -or -not $item.Id) { throw 'Invalid Jellyfin session.' }
        $item
    }
}
function Get-JellyfinAddresses {
    $port = 8096
    $scheme = 'http'
    $baseUrl = ''
    $config = Join-Path $env:ProgramData 'Jellyfin\Server\config\network.xml'
    if (Test-Path -LiteralPath $config) {
        try {
            [xml]$settings = Get-Content -LiteralPath $config -Raw -ErrorAction Stop
            $network = $settings.NetworkConfiguration
            if ($network.InternalHttpPort) { $port = [int]$network.InternalHttpPort }
            if ($network.EnableHttps -eq 'true' -and $network.RequireHttps -eq 'true') {
                $scheme = 'https'
                $port = [int]$network.InternalHttpsPort
            }
            $baseUrl = ([string]$network.BaseUrl).Trim('/')
        } catch { }
    }
    $wifiName = ''
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = Join-Path $env:SystemRoot 'System32\netsh.exe'
        $startInfo.Arguments = 'wlan show interfaces'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        if ($process.WaitForExit(2000)) {
            $wifiOutput = $outputTask.Result
            if ($wifiOutput -match '(?m)^\s*SSID\s*:\s*(.+?)\s*$') { $wifiName = $Matches[1].Trim() }
        } else { $process.Kill() }
        $process.Dispose()
    } catch { }
    $listeners = @([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners())
    foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.OperationalStatus -ne 'Up' -or $adapter.NetworkInterfaceType -eq 'Loopback') { continue }
        $properties = $adapter.GetIPProperties()
        $hasGateway = @($properties.GatewayAddresses | Where-Object {
            $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0'
        }).Count -gt 0
        if (-not $hasGateway) { continue }
        foreach ($address in $properties.UnicastAddresses) {
            $ip = $address.Address.ToString()
            if ($address.Address.AddressFamily -ne 'InterNetwork' -or $ip.StartsWith('169.254.')) { continue }
            $name = $adapter.Name
            $priority = 1
            if ($adapter.NetworkInterfaceType -eq 'Wireless80211') {
                $priority = 0
                if ($wifiName) { $name = $wifiName }
            }
            $url = '{0}://{1}:{2}' -f $scheme, $ip, $port
            if ($baseUrl) { $url += '/' + $baseUrl }
            $listening = @($listeners | Where-Object {
                $_.Port -eq $port -and $_.Address.ToString() -in @($ip, '0.0.0.0', '::')
            }).Count -gt 0
            [pscustomobject]@{
                Network = $name
                Adapter = $adapter.Name
                Address = $ip
                Url = $url
                Listening = $listening
                Priority = $priority
                Display = '{0}  -  {1}' -f $name, $ip
            }
        }
    }
}
