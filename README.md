# Jellyfin Companion

A small Windows desktop app that combines a Jellyfin server address finder with playback-aware auto sleep or shutdown. Built for Windows 10/11 with Windows PowerShell 5.1 and Windows Forms; no extra runtime is required. Normal use does not require administrator access, though managed PCs can restrict network or power operations.

## Features

- Find your server's Wi-Fi or Ethernet address, copy it, or open Jellyfin.
- Refresh network addresses every ten seconds, including when switching networks or using a phone hotspot.
- Choose **Sleep** or **Shut down**, then start or stop a five-minute playback-idle timer in the same window.
- Avoid triggering sleep while Jellyfin reports playback on any device. Paused sessions and connected devices that are only browsing count as idle.
- At five minutes idle, disconnect Wi-Fi and request the selected Windows power action. Sleep preserves open applications; shutdown closes them.
- Reset the countdown on a Jellyfin API error or a long monitoring interruption.
- Store your API key encrypted for the current Windows account, outside the repository.

## Run

### Download the Windows app

Download **JellyfinCompanion.exe** from [Releases](https://github.com/PraneetMaddimsetty2011/jellyfin-companion/releases/latest) and double-click it. No source checkout or separate runtime installation is needed on a standard Windows 10/11 PC. Monitoring starts **off**.

The executable bundles the reviewed application scripts and runs them with Windows PowerShell 5.1. It extracts its versioned app files under `%LOCALAPPDATA%\JellyfinCompanion\app`; your encrypted key and settings stay in the parent folder. It does not install a service or startup task. A new download can replace the old executable without deleting your settings.

The app is currently unsigned, so Windows may display an unknown-publisher warning. Download only from this repository's Releases page and compare the SHA-256 checksum with the accompanying `SHA256SUMS.txt`.

### Run from source

1. Install and start Jellyfin Server on this Windows PC.
2. Use GitHub's **Code > Download ZIP**, extract it into a permanent folder, or clone the repository. Do not launch it from inside the ZIP.
3. Double-click **Start.cmd**. Alternatively, run **Install.ps1** with Windows PowerShell to add a **Jellyfin Companion** desktop shortcut:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
   ```

4. Open **Connection settings**, enter a local server URL and an API key from **Jellyfin Dashboard > API Keys**, then click **Test and save**. The default is `http://localhost:8096`; a standard local Jellyfin network configuration is detected automatically.
5. Use the address at the top to connect any device on the same network. Choose **Sleep** or **Shut down**, then click **Start auto sleep** or **Start auto shutdown** before leaving.

Opening the app normally selects **Sleep** and leaves monitoring **off**, so you can check your address without starting a timer. The action selector is locked while monitoring; click Stop before changing it. Keep the window open or minimized while monitoring. Closing it stops monitoring. To start with monitoring enabled:

```powershell
powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File .\JellyfinCompanion.ps1 -StartMonitoring
```

For auto shutdown, add `-PowerAction Shutdown` to that command. Without `-StartMonitoring`, this option only selects the action and does not arm it. The UI choice is not saved between launches; Sleep remains the default.

Save your work before starting auto shutdown. It uses `shutdown.exe /s /t 0` without `/f`, so apps with unsaved work may block shutdown. It does not force-close those apps. Wi-Fi has already disconnected by the time Windows receives the request.

After the sleep action, monitoring stays off when the PC wakes. Reconnect Wi-Fi if needed, then start monitoring again. Wi-Fi profiles are preserved; the adapter is not disabled. The app does not install a Windows startup task.

## Behavior and limits

- Playback is checked every five seconds, so the action can occur a few seconds after the five-minute mark.
- Activity in other PC apps does not reset the timer. This is a Jellyfin playback timer, not a keyboard/mouse idle timer.
- Playback detection depends on clients reporting their current state to Jellyfin. A client that leaves a stale playing state may keep the PC awake until Jellyfin clears it.
- A connection or authentication failure resets the countdown and keeps the PC awake.
- The final action disconnects each connected Wi-Fi adapter with `netsh wlan disconnect`, then calls `Application.SetSuspendState(Suspend, true, false)` for Sleep or `shutdown.exe /s /t 0` for Shut down. Ethernet-only PCs skip Wi-Fi disconnection. If a connected Wi-Fi adapter cannot disconnect, neither power action is requested.
- Windows and drivers ultimately control power transitions and wake events. The app does not change system power policies or override the PC's existing automatic sleep timeout. Configure that timeout appropriately if it is shorter than your viewing session.
- The address finder checks local listening ports; it cannot verify firewall access from your phone. The displayed address is for the local network, not a public internet endpoint.
- Only local HTTP(S) server URLs are accepted. Redirects are not followed when sending an API key.

## Existing installations

If you previously used the standalone Jellyfin Auto Sleep app on the same Windows account, import its encrypted key during installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -ImportLegacyKey
```

Close the standalone monitor before starting auto sleep in Companion. The original API key can retain its original name in Jellyfin; no new credential is required.

## Local data

Settings, the encrypted credential, activity logs, and diagnostic state live in `%LOCALAPPDATA%\JellyfinCompanion`. They are never needed in Git and are excluded by `.gitignore`. Do not commit keys, diagnostics, private IP addresses, Wi-Fi names, or screenshots of your local configuration.

To remove the app, close it and remove its desktop shortcut, repository folder, and local data folder. Revoke its API key in Jellyfin if no other app uses it.

## Validation

Run the regression tests with **Windows PowerShell 5.1**, which also runs the app:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Core.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Settings.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Http.Tests.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\JellyfinCompanion.ps1 -Check
```

`-Check` requires a configured server and key; it reports connectivity without arming sleep. Core tests cover multiple-session JSON parsing, active and paused playback, timer thresholds, errors, monitoring gaps, and the Wi-Fi-before-sleep action order using mocks. HTTP tests run an isolated loopback fixture with a synthetic key to check real request/response parsing, authentication headers, API errors, and redirect rejection. Tests never disconnect Wi-Fi or sleep the PC.

For a UI smoke test, use `-SmokeTest -DiagnosticsPath <temporary-folder>`. It opens the window with monitoring disabled, writes a local rendering and state file, then closes. Keep those outputs private because they contain your current network address.

## Source layout

- `JellyfinCompanion.ps1`: combined desktop window and monitoring loop.
- `src/Core.ps1`: network discovery, playback decisions, JSON parsing, and sleep action.
- `src/Settings.ps1`: local connection settings and encrypted credential storage.
- `Install.ps1`: optional desktop shortcut and legacy-key migration.
- `Build.ps1` and `launcher/Program.cs`: build the single-file Windows launcher from source, using the .NET Framework compiler included with Windows.
- `tests/`: tests without network or power side effects (except the separate, explicit `-Check` command).

For an isolated first-run check, supply `-DataDirectory <empty-temporary-folder>` with the UI smoke test. Installation also supports `-DataDirectory` and `-ShortcutDirectory` overrides for testing without changing the normal desktop shortcut.

## Privacy and license

No personal configuration or API key is included. Every user sets up their own connection. There is no telemetry or automatic upload. See [PRIVACY.md](PRIVACY.md) for local storage and diagnostic details, and [TESTING.md](TESTING.md) for the release checks and their limits.

Licensed under the [MIT License](LICENSE), so anyone can use, modify, and redistribute the code. This is an independent utility, not an official Jellyfin project.

## Build the executable

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

The build writes `dist/JellyfinCompanion.exe` and `dist/SHA256SUMS.txt`. Only the main script, two source modules, and a generated icon are embedded. No local credentials, configuration, logs, or screenshots are bundled. If a built executable is available, the installer copies it into the local app data directory and makes a desktop shortcut to it; otherwise, it creates the source-script shortcut.

Executable options: `--start`, `--action Sleep|Shutdown`, `--data-directory <folder>`, `--check`, and `--smoke-test --diagnostics <folder>`. Test modes ignore `--start` and never enable a power action.
