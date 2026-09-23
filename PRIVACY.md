# Privacy

Jellyfin Companion runs on the Windows PC hosting Jellyfin. It has no analytics,
telemetry, cloud account, automatic update service, or automatic uploads.

## What stays on your PC

- The API key is encrypted using Windows protection for the current user and
  saved under `%LOCALAPPDATA%\JellyfinCompanion` by default. It is not bundled
  with the source or distributed to other users. Each user supplies their own key.
- The server URL and settings are saved in that same local folder.
- The app reads network adapters, the current Wi-Fi name, and local listening
  ports to display your server address. Those values appear only in the local UI
  unless you explicitly copy or share them.
- Playback data is requested from the configured loopback HTTP(S) Jellyfin
  endpoint. API requests do not follow redirects. The app displays counts, not
  media titles or Jellyfin usernames.
- Runtime diagnostics contain status, timestamps, and device counts. Optional
  UI smoke-test files include the network name/address and must be kept private.

The **Open Jellyfin** button intentionally opens your selected local network
address in your browser. Copying an address places it on your clipboard.

## Limits

Windows credential encryption protects the saved key from other accounts; it
does not protect it from malware or someone running as your Windows user.
Jellyfin API keys can be powerful. Keep yours private and revoke it in Jellyfin
if exposed. The app does not read the Jellyfin database or another app's login
session. Importing a key from the old standalone monitor requires the explicit
`Install.ps1 -ImportLegacyKey` option.

Do not attach unredacted screenshots, credentials, local config files, or full
diagnostics to public issues. `.gitignore` reduces accidental staging but cannot
prevent intentional force-adds or remove data from previous commits. Review
both staged files and Git history before publishing a fork.

The public repository exposes its GitHub owner and commit authors' GitHub
identities. That public attribution is separate from private application data.
