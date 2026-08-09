# Changelog

## 0.0.2 - 2026-08-10

Cross-desktop meeting detection, detection reliability hardening, and the
public Meeting Pulse marketing site, with the repository prepared for public
open-source distribution.

### macOS app

- Adds cross-Space meeting detection: confirmed Google Meet and Slack Huddle
  states stay active during normal Space transitions, and a Space change
  triggers a rescan so a confirmed meeting is not lost when the owner switches
  back to the originating Space with the same Chrome tab already selected.
- Adds bounded Slack Huddle start and stop debouncing so short Slack window
  recreation and microphone-warm periods do not flap the busy state.
- Rewrites the AX snapshot reconstruction so nested descendants retain their
  parent relationship, restoring the tab, window, and control nodes the
  selectors need on Chromium and Slack trees.
- Seeds the detection scheduler from current detector state at startup and
  after every explicit sample request, so a meeting that is already active
  when Meeting Pulse launches no longer leaves the scheduler at `unknown`.
- Keeps Accessibility as the only required permission and continues to fail
  closed on permission loss, unreadable trees, and truncated or unrecognized
  structures.
- Reduces AX snapshot retention so large subtrees are not duplicated for the
  lifetime of a scan.

### Viewer

- No behavioral changes. The viewer continues to receive only `state`,
  `call_okay`, the optional display name, and freshness timestamps, and
  continues to fail closed on stale, malformed, revoked, offline, or
  unavailable input.

### Marketing site

- Adds a public Astro-based Meeting Pulse marketing site under `landing/`
  with an index, features, how-it-works, FAQ, privacy, open-source, and
  download pages, plus documented installation, accessibility permission,
  pairing, recovery, and troubleshooting guides.
- Exposes an `llms.txt` and `robots.txt` from the marketing site for LLM and
  crawler indexing.
- The marketing site ships a complete dark and light screenshot set of the
  menu-bar, onboarding, pairing, recovery, diagnostics, and Station windows,
  and the viewer call-okay, couple-mode, named-meeting, offline, pairing, and
  status-unavailable states.

### Open source preparation

- Adds `.github/` with a CI workflow, issue and PR templates, `CODEOWNERS`,
  and a Dependabot configuration. CI runs the viewer checks on Node 22.12,
  builds and tests the Swift packages on `macos-14` with Xcode 16.2, and
  runs the repository lint (gitleaks and copy check) on every push and pull
  request.
- Adds `CODE_OF_CONDUCT.md` (Contributor Covenant v2.1), `SUPPORT.md` to
  route questions versus bugs versus security, an `.editorconfig` to stop
  drive-by formatting drift, and `docs/PUBLIC-ARCHITECTURE.md` for
  newcomers.
- Replaces owner pronouns in technical prose with "the owner" / "the viewer"
  and rewrites the no-purchase-screen decision so the rule is scoped to
  today as a single-owner utility rather than a permanent policy.

### Privacy and distribution

- No privacy posture changes. Detection still uses Accessibility only and
  still sends only state, `call_okay`, the optional display name, and
  freshness timestamps.
- The local `0.0.2` DMGs are ad-hoc signed and not notarized; first launch on
  a fresh Mac requires Finder's one-time Open action or quarantine removal.

### Release assets

The assets below were rebuilt from commit `c583d48`:

| Architecture | Downloadable asset | SHA-256 |
|---|---|---|
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.2-Apple-Silicon-arm64.dmg` | `74890b22edd70237d414d2be86cd34935d4229b8f2bff8a880cc8b56745392b1` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.2-Intel-x86_64.dmg` | `aeaecdc0791b62867cea3409a4bf16744b779f0d5b4a975df85e65d5a9e946c4` |

Both images are compressed, ad-hoc signed, and verified with `hdiutil`.

## 0.0.1 - 2026-08-09

Initial Meeting Pulse release for local macOS distribution.

### macOS app

- Runs as a Swift 6 menu-bar application on macOS 14 or newer.
- Detects Google Meet meetings in Chrome and native Slack Huddles through
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
- Supports up to five active viewer pairings with owner-side viewer deletion.
- Supports couple-mode copy and viewer presentation alongside the standard
  status copy.
- The local `0.0.1` DMGs are ad-hoc signed and not notarized; first launch on a
  fresh Mac requires Finder's one-time Open action or quarantine removal.

### Release assets

The assets below were rebuilt from commit `ae347e2`:

| Architecture | Downloadable asset | SHA-256 |
|---|---|---|
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.1-Apple-Silicon-arm64.dmg` | `3e6ab802652985ceef5714430e50da83b8602b330354620a4cf1562135c2bc94` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.1-Intel-x86_64.dmg` | `e980014ea28624167c39fa4d747563ce50a96f589f1e0d2090fadeb343a78b77` |

Both images are compressed, ad-hoc signed, and verified with `hdiutil`.
