param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not (Test-Path -LiteralPath $compiler)) {$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
if(-not (Test-Path -LiteralPath $compiler)){throw 'The Windows .NET Framework C# compiler was not found.'}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class CompanionIconHandle { [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle); }'
$bitmap=New-Object System.Drawing.Bitmap(64,64)
$graphics=[System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode='AntiAlias'
$graphics.Clear([System.Drawing.Color]::FromArgb(16,21,30))
$pen=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(104,220,232),6)
$pen.StartCap='Round'; $pen.EndCap='Round'
$graphics.DrawArc($pen,15,16,34,34,-45,270)
$graphics.DrawLine($pen,32,11,32,31)
$iconPath=Join-Path $OutputDirectory 'App.ico'
$handle=$bitmap.GetHicon()
$icon=[System.Drawing.Icon]::FromHandle($handle)
$stream=[IO.File]::Create($iconPath)
try {$icon.Save($stream)} finally {$stream.Dispose();$icon.Dispose();[CompanionIconHandle]::DestroyIcon($handle) | Out-Null;$pen.Dispose();$graphics.Dispose();$bitmap.Dispose()}
$exe=Join-Path $OutputDirectory 'JellyfinCompanion.exe'
$compilerArgs=@('/nologo','/target:winexe','/platform:anycpu','/optimize+','/debug-',('/out:'+$exe),('/win32icon:'+$iconPath),'/reference:System.Windows.Forms.dll',
    ('/resource:'+(Join-Path $PSScriptRoot 'JellyfinCompanion.ps1')+',JellyfinCompanion.ps1'),
    ('/resource:'+(Join-Path $PSScriptRoot 'src\Core.ps1')+',Core.ps1'),
    ('/resource:'+(Join-Path $PSScriptRoot 'src\Settings.ps1')+',Settings.ps1'),
    ('/resource:'+$iconPath+',App.ico'),(Join-Path $PSScriptRoot 'launcher\Program.cs'))
& $compiler @compilerArgs
if($LASTEXITCODE -ne 0){throw 'Executable build failed.'}
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'),($hash+'  JellyfinCompanion.exe'+"`n"))
Write-Output "Built: $exe"
Write-Output "SHA256: $hash"
