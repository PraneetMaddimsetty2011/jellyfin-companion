# Jellyfin Companion

A small Windows desktop app that combines a Jellyfin server address finder with playback-aware auto sleep. Built for Windows 10/11 with Windows PowerShell 5.1 and Windows Forms; no extra runtime is required. Normal use does not require administrator access, though managed PCs can restrict network or power operations.

## Features

- Find your server's Wi-Fi or Ethernet address, copy it, or open Jellyfin.
- Refresh network addresses every ten seconds, including when switching networks or using a phone hotspot.
- Start or stop a five-minute playback-idle timer in the same window.
- Avoid triggering sleep while Jellyfin reports playback on any device. Paused sessions and connected devices that are only browsing count as idle.
- At five minutes idle, disconnect Wi-Fi and request immediate Windows sleep. Open applications remain open.
- Reset the countdown on a Jellyfin API error or a long monitoring interruption.
- Store your API key encrypted for the current Windows account, outside the repository.

## Run

1. Install and start Jellyfin Server on this Windows PC.
2. Use GitHub's **Code > Download ZIP**, extract it into a permanent folder, or clone the repository. Do not launch it from inside the ZIP.
3. Double-click **Start.cmd**. Alternatively, run **Install.ps1** with Windows PowerShell to add a **Jellyfin Companion** desktop shortcut:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
   ```

4. Open **Connection settings**, enter a local server URL and an API key from **Jellyfin Dashboard > API Keys**, then click **Test and save**. The default is `http://localhost:8096`; a standard local Jellyfin network configuration is detected automatically.
5. Use the address at the top to connect your phone on the same network. Click **Start auto sleep** before leaving.

Opening the app normally leaves auto sleep **off**, so you can check your address without starting a sleep timer. Keep the window open or minimized while monitoring. Closing it stops monitoring. To start with monitoring enabled:

```powershell
powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File .\JellyfinCompanion.ps1 -StartMonitoring
```

After the sleep action, monitoring stays off when the PC wakes. Reconnect Wi-Fi if needed, then start monitoring again. Wi-Fi profiles are preserved; the adapter is not disabled. The app does not install a Windows startup task.

## Behavior and limits

- Playback is checked every five seconds, so the action can occur a few seconds after the five-minute mark.
- Activity in other PC apps does not reset the timer. This is a Jellyfin playback timer, not a keyboard/mouse idle timer.
- Playback detection depends on clients reporting their current state to Jellyfin. A client that leaves a stale playing state may keep the PC awake until Jellyfin clears it.
- A connection or authentication failure resets the countdown and keeps the PC awake.
- The final action disconnects each connected Wi-Fi adapter with `netsh wlan disconnect`, then calls `Application.SetSuspendState(Suspend, true, false)`. Ethernet-only PCs skip Wi-Fi disconnection. If a connected Wi-Fi adapter cannot disconnect, sleep is not requested.
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
- `tests/`: tests without network or power side effects (except the separate, explicit `-Check` command).

For an isolated first-run check, supply `-DataDirectory <empty-temporary-folder>` with the UI smoke test. Installation also supports `-DataDirectory` and `-ShortcutDirectory` overrides for testing without changing the normal desktop shortcut.

## Privacy and license

No personal configuration or API key is included. Every user sets up their own connection. There is no telemetry or automatic upload. See [PRIVACY.md](PRIVACY.md) for local storage and diagnostic details, and [TESTING.md](TESTING.md) for the release checks and their limits.

Licensed under the [MIT License](LICENSE), so anyone can use, modify, and redistribute the code. This is an independent utility, not an official Jellyfin project.
