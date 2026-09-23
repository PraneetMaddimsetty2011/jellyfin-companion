function Get-DefaultServerUrl {
    $port = 8096; $scheme = 'http'; $baseUrl = ''
    $path = Join-Path $env:ProgramData 'Jellyfin\Server\config\network.xml'
    if (Test-Path -LiteralPath $path) {
        try {
            [xml]$xml = Get-Content -LiteralPath $path -Raw
            $network = $xml.NetworkConfiguration
            if ($network.InternalHttpPort) { $port = [int]$network.InternalHttpPort }
            if ($network.EnableHttps -eq 'true' -and $network.RequireHttps -eq 'true') {
                $scheme = 'https'; $port = [int]$network.InternalHttpsPort
            }
            $baseUrl = ([string]$network.BaseUrl).Trim('/')
        } catch { }
    }
    $url = '{0}://localhost:{1}' -f $scheme, $port
    if ($baseUrl) { $url += '/' + $baseUrl }
    return $url
}

function Assert-LocalServerUrl {
    param([string]$Url)
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http','https') -or -not $uri.IsLoopback -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Use a local HTTP(S) Jellyfin URL, such as http://localhost:8096.'
    }
}

function Initialize-CompanionSettings {
    param([string]$DataDirectory)
    New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
    $script:CompanionData = $DataDirectory
    $script:ServerUrl = Get-DefaultServerUrl
    $script:ApiKey = $null
    # Load this even when a saved config is corrupt, so the settings dialog can repair it.
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
    $configPath = Join-Path $DataDirectory 'config.json'
    if (Test-Path -LiteralPath $configPath) {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        Assert-LocalServerUrl $config.ServerUrl
        $script:ServerUrl = $config.ServerUrl.TrimEnd('/')
    }
    $keyPath = Join-Path $DataDirectory 'api-key.dpapi'
    if (Test-Path -LiteralPath $keyPath) {
        $secure = (Get-Content -LiteralPath $keyPath -Raw).Trim() | ConvertTo-SecureString
        $script:ApiKey = [System.Net.NetworkCredential]::new('', $secure).Password
    }
}

function Get-ServerSessions {
    param([string]$Url = $script:ServerUrl, [string]$ApiKey = $script:ApiKey)
    Assert-LocalServerUrl $Url
    if (-not $ApiKey) { throw 'Set up your Jellyfin API key first.' }
    $response = Invoke-WebRequest -Uri ($Url.TrimEnd('/') + '/Sessions') -Headers @{
        Authorization = ('MediaBrowser Token="' + $ApiKey + '"')
    } -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction Stop
    ConvertFrom-JellyfinSessions -Json $response.Content
}

function Save-CompanionSettings {
    param([string]$Url, [string]$ApiKey)
    Assert-LocalServerUrl $Url
    # Validate the new settings before replacing the current saved credential.
    $null = @(Get-ServerSessions -Url $Url -ApiKey $ApiKey)
    $encrypted = ConvertTo-SecureString $ApiKey -AsPlainText -Force | ConvertFrom-SecureString
    Set-Content -LiteralPath (Join-Path $script:CompanionData 'api-key.dpapi') -Value $encrypted
    @{ ServerUrl = $Url.TrimEnd('/') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:CompanionData 'config.json')
    $script:ServerUrl = $Url.TrimEnd('/')
    $script:ApiKey = $ApiKey
}

function Write-CompanionLog {
    param([string]$Message)
    try {
        Add-Content -LiteralPath (Join-Path $script:CompanionData 'activity.log') -Value ((Get-Date -Format o) + ' ' + $Message)
    } catch { }
}
