# Changelog

## 0.0.1 - 2026-08-09

Initial Meeting Pulse release for local macOS distribution.

### macOS app

- Runs as a Swift 6 menu-bar application on macOS 14 or newer.
- Detects Google Meet calls in Chrome and native Slack Huddles through
  Accessibility APIs.
- Uses a fail-closed reducer with available, busy, and unavailable states.
- Publishes changes and a lightweight heartbeat without Realtime subscriptions.
- Supports launch at login, an Accessibility permission flow, and a single
  installed instance.
- Provides manual Busy and Available overrides with expiry.
- Provides an independent `Call okay` flag while busy.
- Supports optional owner display name editing.
- Creates viewer links and pairing codes, lists viewers, and supports rotation,
  revocation, and revoke-all operations.
- Supports recovery-phrase rebind when the owner moves to another Mac.
- Uses anonymous auth and Turnstile for protected pairing and recovery flows.
- Includes local diagnostics, permission and network status, reset, and remote
  data deletion controls.
- Stores local identity and session values in an owner-only Application Support
  file instead of Keychain or iCloud.

### Viewer

- Ships as a static Astro site with strict TypeScript.
- Accepts pairing links and normalized ten-character pairing codes.
- Creates or restores an anonymous Supabase session and claims a pairing code.
- Displays the owner's name when configured and renders busy/call-okay copy.
- Polls every 30 seconds only while the page is visible and focused.
- Supports immediate manual refresh.
- Computes freshness from server timestamps and fails closed for stale,
  malformed, revoked, offline, or unavailable states.
- Includes responsive light/dark presentation, reduced-motion support, keyboard
  focus, screen-reader announcements, and color-independent state cues.
- Uses no analytics or third-party scripts outside the pairing captcha.

### Privacy and distribution

- Sends only state, `call_okay`, optional display name, and freshness timestamps.
- Does not send meeting titles, URLs, participants, audio, video, screenshots,
  screen contents, camera state, or microphone state.
- Does not request Screen Recording permission.
- Provides separate optimized `arm64` and `x86_64` Release DMGs.
- The local `0.0.1` DMGs are ad-hoc signed and not notarized; first launch on a
  fresh Mac requires Finder's one-time Open action or quarantine removal.
