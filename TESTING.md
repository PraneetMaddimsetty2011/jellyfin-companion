# Publication validation

The public release is validated on Windows with Windows PowerShell 5.1.
These checks do not require or distribute the maintainer's API key or network
configuration.

## Automated tests

Run all three scripts from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Core.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Settings.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Http.Tests.ps1
```

The 46 checks cover:

- Five-minute thresholds, playback resets, paused and browsing sessions,
  multiple-session JSON parsing, malformed sessions, and monitoring gaps.
- Wi-Fi-before-sleep action order, failure handling, connected-adapter selection,
  and Ethernet-only operation using injected actions rather than real power changes.
- Sleep versus shutdown routing, Wi-Fi-before-shutdown ordering, failure blocking,
  and rejection of unsupported actions, all without executing a real power action.
- Local URL validation, encrypted credential round trips in an isolated temporary
  directory, and recovery from corrupt settings.
- Real loopback HTTP requests against a local test fixture with synthetic
  credentials, including authentication headers, base paths, multiple devices,
  paused playback, 401 errors, malformed replies, and refused redirects.

## Clean first-run validation

The release is also checked from a separate source-only directory with no saved
credentials. The UI must show the server-address section and prompt for an API
key without arming sleep. The installer is exercised with temporary data and
shortcut directories; its shortcut must point at the copied application.

The existing local Jellyfin integration can be checked separately with `-Check`.
That command does not enable auto sleep. Its raw output is private and is not
part of the release.

## Publication privacy checks

Before changing repository visibility, review:

- All reachable Git commits, file blobs, branches, tags, and commit identities.
- Current staged source and the source-only download for keys, machine-specific
  paths, network identifiers, screenshots, diagnostics, and personal email.
- GitHub issues, comments, releases, Actions runs and artifacts, and other
  repository surfaces that become visible with the source.
- `.gitignore` coverage for credentials, configuration, diagnostics, images,
  archives, and local shortcut files.

Commit attribution uses a GitHub no-reply address. The public GitHub owner and
author identity remain visible; private runtime data is not included.

## Limits

Tests do not actually disconnect a network, put the test PC to sleep, or shut it down. The
operating-system calls and their order are reviewed and tested with mocks;
successful sleep and wake depend on the target machine's drivers and policies.
Testing in an isolated data folder is not the same as testing every supported
Windows version or a fresh virtual machine. No claim is made that a scan can
prove the absence of every possible secret; keep reviewing future changes and
never upload unredacted local diagnostics.
