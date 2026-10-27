# Changelog

## 0.0.9 - 2026-10-27

Google Meet picture-in-picture disconnect and Slack huddle end fixes.

### macOS app

- Recovers the correct status after a Google Meet call is ended from the
  picture-in-picture popover. Ending a call that way left the app stuck on
  `Meeting status unavailable` instead of returning to no call. The Meet page
  is now read once per scan without re-reading the application root, which
  used to abort the whole scan and report the call as unreadable. A Meet page
  that is still readable but shows no call controls is now treated as
  positive evidence that the call ended, and an unreadable scan resolves on
  its own instead of staying unavailable. A single uncertain reading no longer
  overrides a call that was just detected, and a detected call now needs two
  agreeing readings before it is cleared.
- Updates the Slack huddle status much faster when a huddle ends. Leaving a
  huddle previously took around 30 seconds to change from `In a meeting` to no
  call. The window-recreation grace period is now 5 seconds instead of 20, so
  a huddle that is gone is reported in roughly 10 to 15 seconds, while a
  huddle window that is momentarily missing is still given time to come back.
- Keeps the Google Meet and Slack huddle detection improvements shipped with
  0.0.8, along with the automatic reconnect after a long internet outage and
  the correct status for meetings that run for hours. The source for those
  changes is included in this release.

### Privacy and distribution

- No new permissions, network requests, or privacy surface. Detection still
  runs locally and only the status is published.
- Ships optimized, ad-hoc signed arm64 and x86_64 DMGs. These local artifacts
  are not notarized and require Finder's one-time Open action on a fresh Mac.

### Release assets

| Architecture | Downloadable asset | SHA-256 |
| --- | --- | --- |
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.9-Apple-Silicon-arm64.dmg` | `2b4e181e8cac342e7e56ca51977c0c09f94321d35d8b694c235489b90485267d` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.9-Intel-x86_64.dmg` | `2aeb9fd2e76378e6ffa97a358d31e03cf54a73183aceff21932402cfe90b57f4` |

## 0.0.8 - 2026-10-27

Reconnect, long-meeting status, and detection accuracy release.

### macOS app

- Recovers automatically after a long internet outage. The app no longer
  needs a restart when the network comes back: a stalled publish is abandoned
  after a deadline, the retry backoff is reset when connectivity returns, and
  a launch that failed while offline is retried automatically.
- Keeps the correct status for meetings that run for hours. Long calls grow
  the accessibility tree, which used to exhaust the scan budget and report
  the call as unavailable. The scan is now breadth-first, budgeted per
  window, and a truncated scan keeps the call active instead of dropping it.
  The status heartbeat also stays inside the viewer's 180-second freshness
  window, and a refresh that fails no longer replaces the signed-in identity,
  so the device keeps publishing after an hour.
- Improves Google Meet detection. The call is confirmed from the leave
  control plus other in-call controls, the `Call controls` landmark is no
  longer required, and the tab strip and web areas are matched in a second
  pass so a call is recognized even when the web area title is not a Meet
  title.
- Improves Slack Huddle detection. The detached window titled `Huddle` is
  recognized, the toolbar may be described as `Huddle actions`,
  `Huddle controls`, or `Huddle toolbar`, the leave control accepts
  `Leave the huddle` and `End huddle`, and a window titled `Huddles` is
  ignored as a list view.

### Privacy and distribution

- No new permissions, network requests, or privacy surface. Detection still
  runs locally and only the status is published.
- Ships optimized, ad-hoc signed arm64 and x86_64 DMGs. These local artifacts
  are not notarized and require Finder's one-time Open action on a fresh Mac.

### Release assets

| Architecture | Downloadable asset | SHA-256 |
| --- | --- | --- |
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.8-Apple-Silicon-arm64.dmg` | `c2196bf45f6e930dbe08834914b38793043643eef0d4665696367ea2babacf6c` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.8-Intel-x86_64.dmg` | `dd641d92a8418bf44a3c575e11938b6cdd8622b5d9efeab7382ef940b61e3ea0` |

## 0.0.7 - 2026-08-24

Slack Huddle embedded-layout detection fix.

### macOS app

- Recognizes active Slack Huddles rendered inside a standard channel window
  through the `Huddles actions` toolbar and `Leave Huddle` control.
- Retains support for the legacy dedicated Huddle window and excludes ordinary
  Slack activity, the Huddles row, and `Start huddle with ...`.
- Preserves long-running Huddle continuity, recreation grace, end settling, and
  the existing `In a meeting` status copy.

### Privacy and distribution

- No new permissions, network requests, or privacy surface.
- Ships optimized, ad-hoc signed arm64 and x86_64 DMGs. These local artifacts
  are not notarized and require Finder's one-time Open action on a fresh Mac.

### Release assets

| Architecture | Downloadable asset | SHA-256 |
| --- | --- | --- |
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.7-Apple-Silicon-arm64.dmg` | `789a9d449bd9a75c8a70b4fea0c1300525fc54fa141798123581391c7122905d` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.7-Intel-x86_64.dmg` | `815d465bef550aa120a401bd14211c320c4517f9d301af1c4fad827e9a54565e` |

## 0.0.6 - 2026-08-22

Google Meet long-call detection fix.

### macOS app

- Keeps a confirmed Google Meet status active beyond four hours while the
  anchored Chrome window and tab remain verifiable.
- Preserves the unavailable state for incomplete or unverified Accessibility
  evidence and still releases after positive Meet end evidence.

### Release assets

| Architecture | Downloadable asset | SHA-256 |
| --- | --- | --- |
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.6-Apple-Silicon-arm64.dmg` | `73e378bffb0102962086ee19df96ba64a2aed177bef1a70c48899b3f72b6a591` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.6-Intel-x86_64.dmg` | `8f89de46dc3194d600940ac28352a01dc9339e80170446e5336484d57fce647a` |

## 0.0.5 - 2026-08-20

Slack Huddle long-call detection fix.

### macOS app

- Keeps a confirmed Slack Huddle busy for its full duration instead of
  expiring the detector latch after four hours.
- Preserves the busy state through temporary Accessibility control and scan
  gaps, while still releasing after authoritative Huddle end evidence.
- Keeps the existing `In a meeting` menu-bar copy and Google Meet safety-valve
  behavior unchanged.

### Privacy and distribution

- No new permissions, network requests, or privacy surface.
- Ships optimized, ad-hoc signed arm64 and x86_64 DMGs. These local artifacts
  are not notarized and require Finder's one-time Open action on a fresh Mac.

### Release assets

| Architecture | Downloadable asset | SHA-256 |
| --- | --- | --- |
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.5-Apple-Silicon-arm64.dmg` | `7738b6cd81eb9db6e6982544e0ed995b4293ce6af7621e55895a5c1151e438ba` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.5-Intel-x86_64.dmg` | `7a0f155fc7951bff9f7c7d23ce6ef3c4c8b6b490a11d34f06b5fe722bc5ff3ea` |

## 0.0.4 - 2026-08-19

Google Meet detection compatibility fix for calls where another participant is
presenting.

### macOS app

- Recognizes Meet's presenter-status Accessibility control and known present or
  share labels instead of requiring the exact `Share screen` label.
- Retains the existing call-controls and `Leave call` confirmation requirements
  so tab-only or title-only matches are still rejected.
- Adds regression coverage for presenter-status, presentation-label variants,
  normalization, and the leave-call-only negative case.

### Privacy and distribution

- No new permissions or privacy surface. Presentation labels are processed only
  in memory and are never published, logged, or synchronized.
- Ships optimized, ad-hoc signed arm64 and x86_64 DMGs. These local artifacts are
  not notarized and require Finder's one-time Open action on a fresh Mac.

### Release assets

| Architecture | Downloadable asset | SHA-256 |
| --- | --- | --- |
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.4-Apple-Silicon-arm64.dmg` | `4e5dd0c0b00a8f1e622e6f779878823e53760cab25a9137077e469ed2efd2058` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.4-Intel-x86_64.dmg` | `2f2f0e86421defee718e7ab7fa32ce929cb2ca2c4aa1137f7a16e8bac30a5a13` |

## 0.0.3 - 2026-08-14

Recovery startup hardening for anonymous auth identity changes.

### macOS app

- Detects the exact duplicate recovery-hash conflict caused when a stored
  device is started with a replacement anonymous auth session.
- Automatically uses the protected recovery rebind flow so the existing device
  and viewer links are preserved.
- Accepts the actual successful `rebind_device` response shape while still
  requiring both returned device identifiers.

### Tests and distribution

- Adds regression coverage for duplicate recovery registration and successful
  rebind response decoding.
- Ships optimized, ad-hoc signed arm64 and x86_64 DMGs. These local artifacts
  are not notarized and require Finder's one-time Open action on a fresh Mac.

### Release assets

| Architecture | Downloadable asset | SHA-256 |
| --- | --- | --- |
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.3-Apple-Silicon-arm64.dmg` | `4f8b85afc7586989349c07fc01e86467b904e38014b8e6663c179c44cd17742c` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.3-Intel-x86_64.dmg` | `c1ac17730325d1d2eb2b7723d7905fbf7a5b768a72bb95d46d0dffda2669cf8b` |

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
- Hardens Slack Huddle end detection by tracking whether the start-of-meeting
  recreation grace has already been consumed in the current visible session,
  so a second window recreation after the latch has settled can no longer
  re-arm a busy state that already ended.
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
- Adds a `PUBLIC_VIEWER_URL` setting and an "Open viewer" header button so the
  landing site links directly to the live viewer origin.

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

The macOS app assets were rebuilt from commit `4e3c2e5` and verified against
the current `41160d3` tree. No Swift, build, or asset-producing source has
changed since the build, so the published DMGs remain the latest macOS app
artifacts. The two intervening commits (`a11dea8`, `41160d3`) only update the
landing-site copy, social preview image, and design documentation.

| Architecture | Downloadable asset | SHA-256 |
| --- | --- | --- |
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.2-Apple-Silicon-arm64.dmg` | `a7a0cb0eb1fdd1d1142bfd0ed591284402dd7455ef4387e5a981aaaa4cd48bb2` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.2-Intel-x86_64.dmg` | `cedd53cb1975ef49e212402a8a14c45a52f9b849f51fa8365833fe5f237bfe2c` |

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
| --- | --- | --- |
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.1-Apple-Silicon-arm64.dmg` | `3e6ab802652985ceef5714430e50da83b8602b330354620a4cf1562135c2bc94` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.1-Intel-x86_64.dmg` | `e980014ea28624167c39fa4d747563ce50a96f589f1e0d2090fadeb343a78b77` |

Both images are compressed, ad-hoc signed, and verified with `hdiutil`.
