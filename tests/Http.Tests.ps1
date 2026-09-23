$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Core.ps1')
. (Join-Path $PSScriptRoot '..\src\Settings.ps1')
function Assert($Ok,$Label) {if (-not $Ok) {throw "FAILED: $Label"}; Write-Output "PASS: $Label"}
# Real loopback HTTP, synthetic credentials, no dependency on a user's Jellyfin server.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public sealed class CompanionHttpFixture : IDisposable {
    private readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    private readonly Thread thread;
    private volatile bool stopped;
    public volatile string Mode = "idle";
    public volatile string LastAuthorization;
    public volatile string LastPath;
    public int Port {get {return ((IPEndPoint)listener.LocalEndpoint).Port;}}
    public CompanionHttpFixture() {
        listener.Start(); thread = new Thread(Serve); thread.IsBackground = true; thread.Start();
    }
    private void Serve() {
        while (!stopped) {
            try {
                using (var client = listener.AcceptTcpClient())
                using (var stream = client.GetStream())
                using (var reader = new StreamReader(stream, Encoding.ASCII, false, 1024, true)) {
                    client.ReceiveTimeout = 3000;
                    var request = reader.ReadLine();
                    LastPath = request == null ? "" : request.Split(' ')[1];
                    string line;
                    LastAuthorization = "";
                    while (!string.IsNullOrEmpty(line = reader.ReadLine())) {
                        if (line.StartsWith("Authorization:", StringComparison.OrdinalIgnoreCase))
                            LastAuthorization = line.Substring(14).Trim();
                    }
                    string status = "200 OK", extra = "", body;
                    switch (Mode) {
                        case "playing": body = "[{\"Id\":\"a\"},{\"Id\":\"b\",\"NowPlayingItem\":{\"Id\":\"test\"},\"PlayState\":{\"IsPaused\":false}}]"; break;
                        case "paused": body = "[{\"Id\":\"b\",\"NowPlayingItem\":{\"Id\":\"test\"},\"PlayState\":{\"IsPaused\":true}}]"; break;
                        case "unauthorized": status = "401 Unauthorized"; body = "{}"; break;
                        case "redirect": status = "302 Found"; extra = "Location: http://127.0.0.1:9/never-send-key\r\n"; body = ""; break;
                        case "invalid": body = "{\"unexpected\":true}"; break;
                        default: body = "[{\"Id\":\"a\"},{\"Id\":\"b\"}]"; break;
                    }
                    byte[] data = Encoding.UTF8.GetBytes(body);
                    byte[] header = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + "\r\nContent-Type: application/json\r\nContent-Length: " + data.Length + "\r\nConnection: close\r\n" + extra + "\r\n");
                    stream.Write(header, 0, header.Length); stream.Write(data, 0, data.Length);
                }
            } catch {if (stopped) return;}
        }
    }
    public void Dispose() {stopped = true; listener.Stop(); thread.Join(3000);}
}
'@
$fixture=New-Object CompanionHttpFixture
try {
    $url='http://127.0.0.1:'+$fixture.Port+'/base'
    $sessions=@(Get-ServerSessions -Url $url -ApiKey 'synthetic-test-key')
    Assert ($sessions.Count -eq 2) 'real HTTP response preserves two separate idle sessions'
    Assert ((Get-IdleDecision $sessions 300 0 295).Mode -eq 'Due') 'idle HTTP sessions reach the five-minute threshold'
    Assert ($fixture.LastPath -eq '/base/Sessions') 'base URL is retained in the request path'
    Assert ($fixture.LastAuthorization -eq 'MediaBrowser Token="synthetic-test-key"') 'key is sent in authorization header, not URL'
    $fixture.Mode='playing'
    $sessions=@(Get-ServerSessions -Url $url -ApiKey 'synthetic-test-key')
    Assert ((Get-IdleDecision $sessions 300 0 295).Playing -eq 1) 'playing device from real HTTP prevents sleep'
    $fixture.Mode='paused'
    $sessions=@(Get-ServerSessions -Url $url -ApiKey 'synthetic-test-key')
    Assert ((Get-IdleDecision $sessions 300 0 295).Mode -eq 'Due') 'paused HTTP session permits the idle timer'
    foreach ($mode in @('unauthorized','invalid','redirect')) {
        $fixture.Mode=$mode; $rejected=$false
        try {$null=@(Get-ServerSessions -Url $url -ApiKey 'synthetic-test-key')} catch {$rejected=$true}
        Assert $rejected "$mode HTTP response is rejected rather than treated as idle"
    }
} finally {$fixture.Dispose()}
