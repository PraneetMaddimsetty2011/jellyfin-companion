$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Settings.ps1')
function Assert($Ok,$Label) {if (-not $Ok) {throw "FAILED: $Label"}; Write-Output "PASS: $Label"}
foreach ($url in @('http://localhost:8096','https://127.0.0.1:8920/jellyfin','http://[::1]:8096')) {
    Assert-LocalServerUrl $url
}
Write-Output 'PASS: local HTTP and HTTPS URLs, IPv6, and base paths are supported'
foreach ($url in @('http://example.com','file:///C:/test','http://name:password@localhost:8096','http://localhost:8096?api_key=test','http://localhost:8096/#fragment','not a url')) {
    $rejected=$false
    try {Assert-LocalServerUrl $url} catch {$rejected=$true}
    Assert $rejected 'unsafe or nonlocal URL is rejected'
}
# Verify credential persistence using a synthetic key in an isolated temporary folder.
$testDirectory=Join-Path ([IO.Path]::GetTempPath()) ('JellyfinCompanionTest-'+[Guid]::NewGuid().ToString('N'))
try {
    Initialize-CompanionSettings $testDirectory
    # Mock only the validation request: no real server, credential, or power action is used.
    function Get-ServerSessions {param([string]$Url,[string]$ApiKey); if ($ApiKey -ne 'synthetic-test-key') {throw 'Unexpected test key'}}
    Save-CompanionSettings 'http://localhost:8096' 'synthetic-test-key'
    $stored=Get-Content -LiteralPath (Join-Path $testDirectory 'api-key.dpapi') -Raw
    Assert (-not $stored.Contains('synthetic-test-key')) 'saved key is not plaintext'
    $script:ApiKey=$null
    Initialize-CompanionSettings $testDirectory
    Assert ($script:ApiKey -eq 'synthetic-test-key') 'encrypted key loads in this Windows account'
    Assert ($script:ServerUrl -eq 'http://localhost:8096') 'connection settings persist'
} finally {
    # Only these known test files are removed; no recursive deletion is used.
    foreach ($name in @('api-key.dpapi','config.json')) {
        $path=Join-Path $testDirectory $name
        if (Test-Path -LiteralPath $path) {Remove-Item -LiteralPath $path}
    }
    if (Test-Path -LiteralPath $testDirectory) {Remove-Item -LiteralPath $testDirectory}
}
