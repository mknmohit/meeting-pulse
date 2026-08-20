# Meeting Pulse — Design Specification v2.0

**Product:** Meeting Pulse
**Date:** 2026-08-07
**Supersedes:** "Meeting Status Companion — Design Specification" (2026-08-07, v1)
**Status:** Authoritative. Implementation-ready.
**Audience:** An implementation LLM or engineer building the MVP.
**Companion documents:** `01-spec-audit-report.md` (what changed and why), `03-implementation-plan.md` (how to build it)

> **Rule of precedence.** This document is authoritative over v1. Where this document is silent, v1 applies. Any change to §3 (goals), §4 (state model), §6 (privacy boundary), the no-extension requirement, or the non-realtime sync model requires revisiting this specification.
>
> **Storage amendment (2026-08-08).** The local secret-storage portions of this
> document are superseded by
> `docs/superpowers/specs/2026-08-08-no-keychain-storage-design.md`.

---

## 1. Summary

Meeting Pulse is a lightweight native macOS menu-bar application that detects whether its owner is currently in a Google Meet call in Chrome or a Slack Huddle in the native Slack app. It publishes only a small availability state to a paired Supabase backend. A private web page, opened by the viewer, reads that state periodically.

The project is open source. Deployment configuration is injectable, secrets stay out of source control, and tooling is reproducible and reviewable.

The MVP exposes **no** meeting title, platform, participants, duration, microphone state, camera state, screen-sharing state, calendar data, audio, video, or meeting content.

The owner can rely on automatic detection or apply a manual Busy/Available
override. A manual override expires at a user-selected time, defaulting to 30
minutes. Station also accepts a custom duration from 1 minute through 24 hours
alongside the fixed presets. The `call okay` note is independent of the
Busy/Available state.

---

## 2. Context and product hypothesis

*(Unchanged from v1 §2.)*

The owner uses Google Meet in Chrome and Slack Huddles in the native Slack app for nearly all meetings. The viewer needs a low-friction way to decide whether calling is appropriate. The first stage is a single-owner utility, not a public SaaS. It should be small, inexpensive, privacy-preserving, and structured so it can later become a couples/family availability product.

A preliminary market scan found adjacent features but no obvious product matching this exact combination: arbitrary Chrome Google Meet participation, native Slack Huddles, a macOS local agent, and a private family-facing status page. Google Calendar and Slack statuses remain platform-specific, and official APIs do not reliably provide a single instant cross-platform signal for every call the user joins. This is a product hypothesis, not a claim that no competitor exists; broader validation is required before commercialization.

---

## 3. Goals

### 3.1 MVP goals

1. Detect Google Meet call start and end in Chrome.
2. Detect Slack Huddle start and end in the native Slack macOS app.
3. Run as a low-memory menu-bar background app launched at login.
4. Provide one-click manual Busy/Available override with expiry.
5. Provide a separate `call okay` toggle while Busy.
6. Pair one private viewer using a code, without email or password.
7. Let the owner optionally provide a display name that the paired viewer can see.
8. Show the latest trustworthy state in a browser page with a manual refresh control.
9. Avoid realtime subscriptions; use change-triggered writes, a small heartbeat, and focused-tab viewer polling.
10. **Fail closed:** unknown, stale, or permission-blocked state becomes `Status unavailable`, never a guessed `Available`.
11. Keep backend cost within the free tier for personal use.
12. Keep the repository safe and straightforward for other contributors to build, test, configure, and review.
13. **(new)** Survive local identity loss without orphaning the device or forcing the viewer to re-pair.
14. **(new)** Be correct when the viewer's device clock is wrong.

### 3.2 Non-goals for the MVP

Chrome extension · Slack bot or workspace install · Google OAuth / Meet API · Slack OAuth · calendar integration · meeting title, duration, participant, or platform display · screen-sharing detection · microphone/camera detection · native iPhone/Android app · push notifications, SMS, or calling · multi-user accounts, teams, billing, analytics, or status history · recording or analyzing meeting audio/video · screen capture or OCR as the first detection mechanism · Mac App Store distribution (technically impossible, see §5.4).

---

## 4. State model and user experience

### 4.1 The state model — three states and one flag

**CHANGED (audit C1).** v1 §1 listed `Busy - call okay` alongside the three states, implying four. It is not a state.

The published model is exactly:

```
state      : enum { "available", "busy", "unavailable" }   -- required
call_okay  : boolean                                        -- required, default false
```

- `available` — the owner is confirmed not to be in a detected meeting.
- `busy` — the owner is confirmed to be in a detected meeting, **or** has manually set Busy.
- `unavailable` — the app cannot provide a fresh, trustworthy state. Rendered to the viewer as **"Status unavailable"**.

`call_okay` is **independent** of `state`. It is published always for the
owner app and remains hidden from the viewer.

The viewer has two paired renderings, while the owner app retains the full
internal state model:

| `state` | Viewer shows |
|---|---|
| `busy` | **In a meeting** |
| `available` | **Meeting status unavailable** |
| `unavailable` | **Meeting status unavailable** |

### 4.2 Owner first run

1. Launch Meeting Pulse.
2. The app explains that it needs **Accessibility** permission to inspect only Chrome and Slack UI state, and states plainly what it does *not* read.
3. If permission is missing, the app opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
4. The app reports detector health separately for Chrome and Slack.
5. The app offers an optional owner display-name field.
6. The app offers "Launch at login" (`SMAppService.mainApp`).
7. The app generates and displays the **device recovery phrase** once (§8.6), with a "I have saved this" confirmation and a "show again" menu item.
8. The menu-bar icon shows the effective state and connection health.

Meeting Pulse does **not** request Screen Recording. A diagnostic message must state explicitly that Screen Recording is not used and not requested. A later version may add it only if Accessibility inspection cannot support a required state.

### 4.3 Menu-bar controls

- Current effective state: Available, Busy, or Status unavailable.
- Automatic-mode indicator, or the active override and its remaining time.
- `Set Busy` ▸ duration submenu.
- `Set Available` ▸ duration submenu.
- `Clear override`.
- `Call okay` toggle (checkable).
- `Refresh and publish now` — **owner-side**: takes an immediate local detector sample, recomputes the effective state, and publishes it. (The viewer's `Refresh now` is unrelated: it re-reads the last published row and cannot wake or command the Mac.)
- `Edit display name…`.
- `Pairing` ▸ create viewer link · copy code/link · rotate viewer link · revoke viewer · revoke all viewers.
- `Recovery` ▸ show recovery phrase · rebind this device…
- Detector health for Google Meet and Slack Huddles.
- Last successful sync time.
- `Diagnostics` ▸ permission status · network status · export sanitized diagnostics.
- `Reset & delete remote data…` (§8.7).
- `Quit`.

**Duration presets (audit C2):** 15 minutes · **30 minutes (default)** · 45 minutes · 1 hour · 2 hours · 4 hours · Until I clear it.

### 4.4 Viewer page

A small responsive Astro static build with TypeScript, hosted on Cloudflare Pages at a configurable custom subdomain. The personal deployment origin used in documentation examples is `https://og.techdevix.com`; this value is **build-time configuration**, never a source-code default (§5.6).

**First visit**
1. The viewer opens the shared viewer link, or enters the pairing code.
2. The page solves a Cloudflare **Turnstile** challenge and creates or restores an anonymous Supabase Auth session. *(Turnstile is new — audit A5.)*
3. The page claims the persistent code through the protected
   `claim_pairing_code` RPC and removes the URL fragment after success.
4. The resulting viewer session persists in browser storage.

**Returning visit**
1. Restore the anonymous session.
2. Fetch the paired device's current status.
3. Poll every 30 seconds **only while the page is visible and focused**.
4. Pause polling when the tab is hidden or the window is unfocused.
5. Fetch immediately when the page becomes visible and focused again.
6. `Refresh now` triggers an immediate fetch regardless of the timer.

**The page shows**
- Large state label: In a meeting or Meeting status unavailable.
- Owner display name above the state, when configured and non-blank.
- Last checked time (derived from a monotonic local timer, §9.3).
- `Refresh now` button.
- A clear explanation when the state is unavailable, when the pairing is revoked, or when the browser is offline.
- A path to enter a new code if the session is cleared or revoked.

The viewer never sees meeting source, title, duration, participant data, override metadata, device identifiers, or local diagnostics.

---

## 5. Platform, tooling, and repository standards

### 5.1 Component map

```text
Meeting Pulse.app (macOS menu bar)
  PermissionCoordinator · AppConfiguration · GoogleMeetDetector · SlackHuddleDetector
  DetectionScheduler · StatusReducer · ManualOverrideStore · DeviceProfileStore
  SupabaseStatusTransport · KeychainStore · MenuBarViewModel · DiagnosticsLog

Supabase
  Anonymous Auth (Turnstile-protected) · Postgres · RLS (deny-by-default)
  SECURITY DEFINER RPCs · PostgREST via Swift and JS clients · no Realtime

Viewer (Astro static → Cloudflare Pages)
  supabase-js · pairing flow · status fetch · visibility/focus-gated 30 s polling
  manual refresh · server-time staleness
```

### 5.2 Native app technology — **CHANGED (audit A9)**

| Setting | Value | Rationale |
|---|---|---|
| Minimum deployment target | **macOS 14.0 (Sonoma)** | `MenuBarExtra` (13+), `SMAppService` (13+), Observation `@Observable` (14+) are all load-bearing |
| Language | **Swift 6.0**, strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`) | |
| Toolchain | **Xcode 16.x**, pinned in `.xcode-version` and CI | |
| Architectures | **Universal 2** (`arm64` + `x86_64`) from the first release | Marginal cost; removes a class of bug reports |
| UI | SwiftUI `MenuBarExtra`; AppKit only where required | |
| Build system | Swift Package Manager for logic modules; Xcode project for the app shell | Lets the reducer/detector packages be tested without a GUI host |
| Backend client | `supabase-swift` | |
| Concurrency | `async`/`await`, actors, structured cancellation | |

Do **not** use Electron. Do **not** use Tauri for the MVP.

### 5.3 Viewer technology

TypeScript (`strict: true`) · Astro with `output: "static"` · plain HTML/CSS/TS components (no UI framework) · `supabase-js` v2 · Cloudflare Pages with a custom domain. Do **not** introduce Next.js, SSR, or any server runtime.

### 5.4 macOS entitlements, signing, and distribution — **NEW (audit A8)**

These are hard platform constraints, not preferences.

| Item | Value | Why |
|---|---|---|
| **App Sandbox** | **Disabled** | `AXUIElementCopyAttributeValue` against another process is impossible inside the sandbox |
| **Mac App Store** | **Impossible.** Explicitly out of scope | The Store requires the sandbox |
| Hardened Runtime | **Enabled** | Required for notarization |
| `LSUIElement` | `true` | Menu-bar only; no Dock icon, no main window |
| Signing | **Developer ID Application**, one stable identity, stable bundle id `com.techdevix.meetingpulse` | The Accessibility TCC grant is keyed to signature + bundle id. **Changing either silently revokes the user's grant.** Record this in `SECURITY.md` |
| Notarization | `notarytool submit --wait` then `stapler staple` | |
| Distribution | Signed, notarized, stapled **DMG** attached to a GitHub Release | |
| Updates | Manual DMG for the MVP. Sparkle deferred to Phase 2, subject to the stable-identity constraint | |

Development builds carry a different signature from release builds, so **both need their own Accessibility grant** during development. Document this in `CONTRIBUTING.md`.

### 5.5 Single-instance guard — **NEW (audit B14)**

At launch, enumerate `NSRunningApplication.runningApplications(withBundleIdentifier:)`. If another instance is running, activate it and terminate self. Two instances would double-publish and cause visible state flapping.

### 5.6 Configuration and open-source standards

All deployment-specific values are supplied through configuration and never hardcoded.

**macOS app** reads the Supabase host, public anon/publishable key, Turnstile
site key, and viewer scheme/host list from an ignored local `Config.xcconfig`
or CI build settings. Commit only `Config.xcconfig.example` with placeholders.

**Viewer** reads, at build time:

| Variable | Required | Secret | Purpose |
|---|---|---|---|
| `PUBLIC_SUPABASE_URL` | yes | no | Supabase project URL |
| `PUBLIC_SUPABASE_ANON_KEY` | yes | no | Publishable anon key |
| `PUBLIC_STATUS_ORIGINS` | yes | no | Comma-separated public origins for docs/links; first is canonical |
| `PUBLIC_TURNSTILE_SITE_KEY` | yes | no | Turnstile widget key |

Commit only `.env.example`. **Missing or malformed required configuration must fail the build or startup with a clear setup error. Never fall back to a production project, a developer's project, or an invented default** — including `og.techdevix.com`, which appears only in documentation prose (audit B18).

The Supabase **service-role key** may exist only in local/CI secret storage. It must never appear in the Mac app, the viewer bundle, migrations, fixtures, or logs.

Pairing codes, auth tokens, recovery phrases, and generated local config are excluded from version control by `.gitignore`, and enforced by `gitleaks` in CI and a pre-commit hook.

**License: MIT** (audit B17). `LICENSE`, `README.md`, `CONTRIBUTING.md`, and `SECURITY.md` are required at the repo root.

Tooling: `swift-format` + Swift Testing for the app; `tsc --noEmit`, `astro check`, Prettier, ESLint, and a committed `pnpm-lock.yaml` for the viewer. CI runs formatting, static/type checks, tests, secret scanning, and the viewer production build on every pull request. Never log environment values, tokens, pairing codes, recovery phrases, or private UI text.

---

## 6. Status logic

### 6.1 Inputs

Google Meet observation · Slack Huddle observation · detector health · manual override state and expiry · `call_okay` · app lifecycle and network health · Accessibility permission status.

### 6.2 Observation model — **CHANGED (audit C5)**

The observation case `not_available` is renamed **`sourceAbsent`**, because `not_available` and the published state `unavailable` differ by one underscore and mean opposite things — the direct cause of audit finding A10.

```swift
enum SourceObservation: Sendable, Equatable {
    case active          // confirmed active meeting/huddle in this source
    case inactive        // source is readable and confirmed to have no active meeting
    case unknown         // source is relevant but its state cannot be trusted
    case sourceAbsent    // the app is not installed / not running / not applicable
}
```

**`unknown` must never be coerced to `inactive`.**

`sourceAbsent` means we positively know the source cannot host a meeting right now (Chrome is not running, Slack is not installed). A missing Accessibility permission, an unreadable UI tree, or an unrecognized UI state is **`unknown`**, not `sourceAbsent`.

Keep the contract forward-compatible: a future observation may carry `screen_sharing ∈ {yes, no, unavailable}`; the MVP reducer and viewer ignore it.

### 6.3 Detector contract

```swift
protocol MeetingDetector: Actor {
    nonisolated var sourceIdentifier: SourceID { get }   // .googleMeet | .slackHuddle
    func start() async
    func stop() async
    func requestSample() async -> SourceObservation
    var currentObservation: SourceObservation { get }
    var health: DetectorHealth { get }                    // .ok | .degraded(code) | .permissionDenied | .absent
    var observationStream: AsyncStream<SourceObservation> { get }
}
```

### 6.4 The reducer — **CHANGED (audit A2, A10)**

v1 stated five rules as an unordered set, producing undefined behaviour in common situations. The reducer is now a **single ordered total function**.

```
effectiveState(meet, slack, health, override, now) -> State

STEP 1  If an override exists and override.expiresAt > now (or expiresAt == nil):
            return override.state          // "busy" or "available"
            // An explicit user action wins over everything, including
            // permission failures. The owner asserted this deliberately.

STEP 2  If meet == .active OR slack == .active:
            return .busy
            // A CONFIRMED meeting outranks an unknown in the OTHER source.
            // Downgrading confirmed-busy to unavailable because an unrelated
            // source is unreadable would produce a LESS safe answer: it invites
            // the viewer to call and check. This is the correct reading of
            // Goal 10 ("never a guessed Available").

STEP 3  If Accessibility permission is not granted:
            return .unavailable

STEP 4  If meet == .unknown OR slack == .unknown:
            return .unavailable

STEP 5  Otherwise every source is .inactive or .sourceAbsent:
            return .available
            // Includes the all-absent case: Chrome closed and Slack closed
            // means we positively know he is not in a Meet call or a Huddle.
            // This is the machine's resting state every morning.
```

**Full decision table** (automatic mode, permission granted). Rows = Meet, columns = Slack. This table is the unit-test fixture; all 16 cells are mandatory test cases.

| Meet ↓ / Slack → | `active` | `inactive` | `unknown` | `sourceAbsent` |
|---|---|---|---|---|
| **`active`** | busy | busy | busy | busy |
| **`inactive`** | busy | available | unavailable | available |
| **`unknown`** | busy | unavailable | unavailable | unavailable |
| **`sourceAbsent`** | busy | available | unavailable | **available** |

With permission **not** granted, every cell whose result is not reached by STEP 1 or STEP 2 becomes `unavailable` (STEP 3), i.e. the entire table collapses to: `busy` where any source is `active`, `unavailable` elsewhere.

`call_okay` never affects `state`. It is passed through unchanged.

### 6.5 Manual override — **CHANGED (audit B1, B2, C2)**

```swift
struct ManualOverride: Codable, Sendable {
    let state: State          // .busy | .available
    let createdAt: Date
    let expiresAt: Date?      // nil == "Until I clear it"
}
```

- **Presets:** 15 m · **30 m (default)** · 45 m · 1 h · 2 h · 4 h · Until I clear it.
- **Persistence (B1):** written to `~/Library/Application Support/MeetingPulse/override.json` on every change. On launch the override is reloaded and re-evaluated; if `expiresAt <= now` it is discarded and automatic mode resumes. Without this, quitting during a 2-hour Busy silently reverts to automatic.
- **Expiry timer (B2):** a dedicated cancellable `Task` sleeps until `expiresAt`, then clears the override, recomputes, and **publishes immediately**. Without this the viewer would keep showing the expired state for up to one heartbeat interval.
- **Clock changes:** the expiry task is re-armed on wake and on significant time change (`NSSystemClockDidChangeNotification`).
- Setting `Set Available` while a meeting is detected is honoured — an explicit user action, not an automatic inference.

### 6.6 Detection scheduler

The app must never stop local monitoring, because it has to detect the *next* meeting after the current one ends.

| Mode | Behaviour |
|---|---|
| **Idle** | Register AX and app-lifecycle notifications. Low-power safety sample every **20 s** (`idleSampleInterval`). Re-evaluate immediately when Chrome or Slack changes. |
| **Candidate/Active** | Re-evaluate immediately on events. Safety sample every **5 s** (`activeSampleInterval`). Require **two consecutive** inactive observations before declaring a meeting ended (`endSettleCount = 2`). Return to Idle after the reducer confirms the end. |

All three values are configuration, not literals, and must be tunable without a rebuild (read from `Defaults` with the above fallbacks) so they can be adjusted during detector validation.

---

## 7. Detection

### 7.1 Shared rules

- Use semantic Accessibility roles, subroles, and identifiers. Never screen coordinates, never screenshots, never OCR.
- All selector/matching logic for a source lives in **one** module, so a Chrome or Slack UI change is a single-file fix.
- On failure, emit a **stable diagnostic code** naming which expected signal was missing (e.g. `MEET_NO_CALL_CONTROLS`, `SLACK_NO_HUDDLE_WINDOW`). Never log the UI text, URL, or title itself.
- Never treat audio activity alone as proof of a call. Never treat a title alone as proof of a call.

### 7.2 Google Meet detector — base algorithm

1. Locate Chrome via `NSRunningApplication` (bundle id `com.google.Chrome`); if absent → `sourceAbsent`.
2. If Accessibility is not trusted → `unknown`.
3. Walk Chrome's AX windows and locate a Meet page identity (Meet URL or equivalent page identity in the `AXWebArea`).
4. Confirm the **in-call** state via stable call controls / accessibility labels — not merely an open Meet tab.
5. Treat a lobby, pre-join screen, or the Meet landing page as **`inactive`**.
6. Detect end when call controls disappear, the call page leaves the active state, or the tab/window closes.
7. Any AX error, unreadable tree, or unrecognized structure → **`unknown`** (never `inactive`).

### 7.3 Google Meet — the latched session model — **NEW (audit A3, the project's top risk)**

**The problem.** The owner switches tabs and apps during calls. Chromium does not reliably expose the rendered AX tree of a non-visible tab; a backgrounded Meet tab's `AXWebArea` may disappear entirely. Under §7.2 alone, switching tabs makes the call controls vanish, which yields `unknown`, which yields `Status unavailable` — during exactly the moments the product exists to cover.

**The design.** Separate **confirmation** (strong, needs foreground) from **maintenance** (weak, always observable).

```
State machine: idle → confirming → latchedActive → releasing → idle

CONFIRM   (idle → latchedActive)
  Requires STRONG evidence: Meet page identity + in-call controls present
  in a readable AXWebArea. Normally satisfied at join, when the tab is
  foreground. Emits .active and records the latch anchor:
  { chromeWindowRef, tabIdentity, confirmedAt }.

MAINTAIN  (latchedActive)
  While latched, emit .active as long as WEAK liveness holds:
    L1. The anchored Chrome window still exists, AND
    L2. A tab-strip entry matching the anchored tab identity still exists.
  Re-run STRONG confirmation opportunistically whenever the Meet tab is
  foreground again; a successful re-confirm refreshes the anchor.

RELEASE   (latchedActive → releasing → idle)
  Release on POSITIVE end evidence:
    R1. Strong re-observation shows Meet page identity but NO call controls
        (he hung up and is looking at the "You left the call" screen), OR
    R2. The anchored tab entry disappears (tab closed or navigated away), OR
    R3. The anchored Chrome window closes, OR
    R4. Chrome terminates.
  Apply the two-consecutive-sample settle rule (§6.6) before emitting .inactive.

SAFETY VALVE
  maxLatchDuration (default 4 h, configurable). On expiry the latch releases
  to .unknown — NOT .inactive — so a wedged latch degrades to
  "Status unavailable", never to a false "Available".
```

**Optional corroboration (Phase 1.5, off by default).** A CoreAudio "input device in use" check may *strengthen* the latch (it can extend maintenance) but may **never** create a latch on its own and may never be the sole basis for `active`. It reads a boolean device-in-use flag only — no audio is captured, buffered, or analysed. Requires no permission. Ship it disabled behind `enableAudioCorroboration`.

**Spike S1 is a hard gate.** Before any downstream work, empirically determine on the installed Chrome:
- Q1: Does the Meet `AXWebArea` persist when the tab is backgrounded?
- Q2: Does the tab-strip expose a stable per-tab element with an identifiable title while backgrounded?
- Q3: Does the window's AX tree change observably when the Meet tab is closed?

**Fallback ladder, in order:**
1. Q1 = yes → the base algorithm in §7.2 is sufficient; the latch becomes a robustness bonus.
2. Q1 = no, Q2 = yes → the latched model above ships as designed. **This is the expected outcome.**
3. Q1 = no, Q2 = no, Q3 = yes → latch maintained on window-level liveness only; `maxLatchDuration` drops to 2 h; accuracy is reduced and this must be stated in the README.
4. All no → **Google Meet auto-detection is cut from the MVP.** Meet becomes manual-only, the Slack detector ships alone, and the README states the limitation plainly. Do not ship a detector that guesses.

### 7.4 Slack Huddle detector

1. Locate Slack via `NSRunningApplication` (bundle id `com.tinyspeck.slackmacgap`); if absent → `sourceAbsent`.
2. Inspect the Slack window and relevant AX descendants.
3. Confirm a live Huddle through a stable huddle-specific state, a dedicated huddle window, or a leave control.
4. **Never** treat Slack being open, focused, active, or recently used as a Huddle.
5. Detect end when an authoritative scan confirms that the dedicated Huddle
   window is gone after recreation grace, or Slack exits.
6. Before a Huddle is confirmed, any AX error or unrecognized structure →
   `unknown`.
7. After confirmation, the dedicated Huddle window is liveness evidence. The
   Slack latch has no elapsed-time expiry; temporary control or AX-scan gaps
   preserve `active`, and release requires authoritative end evidence after
   recreation grace. The Meet latch's `maxLatchDuration` safety valve does not
   apply to Slack Huddles.
Slack is an Electron app, so AX exposure may be less stable than a native UI. **Spike S2** is a hard gate with the same discipline as S1; if no reliable signal exists, the detector must surface `unknown` and Slack becomes manual-only. Slack often uses a **separate huddle window**, which is usually more observable than in-tab content — check this first in S2.

### 7.5 Environment observation — **NEW (audit B13)**

| Event | API | Response |
|---|---|---|
| App launch/terminate | `NSWorkspace.shared.notificationCenter` — `didLaunchApplicationNotification`, `didTerminateApplicationNotification` | Re-sample the affected detector |
| Window/focus change | `AXObserver` on the target pid — `kAXFocusedWindowChangedNotification`, `kAXWindowCreatedNotification`, `kAXUIElementDestroyedNotification` | Re-sample |
| System sleep | `NSWorkspace` `willSleepNotification` | Cancel timers; publish nothing (freshness will lapse naturally) |
| System wake | `NSWorkspace` `didWakeNotification` | Full re-sample of both detectors, re-arm the override expiry task, publish immediately |
| Network change | `NWPathMonitor` | On regain: flush the retry queue and publish immediately |
| Accessibility grant change | **No notification exists.** Poll `AXIsProcessTrusted()` every **5 s** | On transition, update health, recompute, publish |
| Clock change | `NSSystemClockDidChangeNotification` | Re-arm the override expiry task |

---

## 8. Backend (Supabase)

Supabase provides the managed backend; no always-on custom server is required. Anonymous Auth · Postgres · deny-by-default RLS · `SECURITY DEFINER` RPCs · PostgREST via the Swift and JS clients · **no Realtime**. Edge Functions only if a later requirement cannot be met safely in SQL.

### 8.1 Security posture

1. **RLS is enabled on every table, with no permissive policy that any client can reach directly for writes.**
2. All writes go through `SECURITY DEFINER` RPCs that (a) verify `auth.uid()` ownership, (b) validate every field server-side, (c) assign all timestamps from `now()`, never from client input.
3. All RPCs set `SET search_path = public, pg_temp` to prevent search-path hijacking.
4. No client can enumerate devices, read arbitrary status rows, or update status directly.
5. Viewers receive **no** table `SELECT` grant (audit A7) — they read only through `get_paired_status()`.

### 8.2 Schema

```sql
devices
  id                  uuid  primary key default gen_random_uuid()
  owner_user_id       uuid  not null references auth.users(id) on delete cascade
  display_name        text  null                    -- trimmed, <= 80 chars
  recovery_hash       text  not null                -- sha256 hex of the recovery secret
  created_at          timestamptz not null default now()
  revoked_at          timestamptz null

  -- audit B4: exactly one active device per owner
  unique index devices_one_active_per_owner
    on devices(owner_user_id) where revoked_at is null

current_status
  device_id           uuid  primary key references devices(id) on delete cascade
  state               text  not null check (state in ('available','busy','unavailable'))
  call_okay           boolean not null default false
  screen_sharing      text  null check (screen_sharing in ('yes','no','unavailable'))
  override_mode       text  null check (override_mode in ('busy','available'))
  override_expires_at timestamptz null
  last_seen_at        timestamptz not null default now()
  updated_at          timestamptz not null default now()
  schema_version      integer not null default 1

pairing_codes
  id            uuid primary key default gen_random_uuid()
  device_id     uuid not null references devices(id) on delete cascade
  code_hash     text not null unique          -- sha256 hex of the normalized code
  expires_at    timestamptz null                 -- NULL for the active persistent code
  claimed_at    timestamptz null
  revoked_at    timestamptz null
  created_at    timestamptz not null default now()
  index on (device_id)

viewers
  device_id      uuid not null references devices(id) on delete cascade
  viewer_user_id uuid not null references auth.users(id) on delete cascade
  created_at     timestamptz not null default now()
  revoked_at     timestamptz null
  primary key (device_id, viewer_user_id)
  index on (viewer_user_id)                   -- audit C7: the RPC's actual lookup direction

  -- At most five active bindings per owner device; older bindings expire by age.

pairing_attempts                               -- internal; NO client grant
  viewer_user_id     uuid primary key references auth.users(id) on delete cascade
  window_started_at  timestamptz not null
  attempt_count      integer not null default 0

pairing_attempts_ip                            -- internal; NO client grant (audit A5)
  ip                 inet primary key
  window_started_at  timestamptz not null
  attempt_count      integer not null default 0

pairing_attempts_global                        -- internal; single row, id = true
  id                 boolean primary key default true check (id)
  window_started_at  timestamptz not null
  failure_count      integer not null default 0
```

`screen_sharing` is reserved for Phase 2 and is always written `null` in the MVP.

`display_name` is optional owner-controlled profile metadata: trimmed, ≤ 80 characters, stored on `devices` and not on the live status row. The viewer renders it as **text** (`textContent`, never `innerHTML`). A blank name is valid and hidden on the viewer page.

### 8.3 Pairing flow

1. The Mac authenticates anonymously.
2. The Mac calls `register_device(recovery_hash)` if it has no device.
3. The Mac generates a high-entropy code locally, sends only `sha256(normalize(code))` to `create_pairing_code`.
4. The owner shares the raw code directly or inside a viewer URL fragment.
5. The viewer authenticates anonymously (Turnstile-gated) and calls `claim_pairing_code(raw_code)`.
6. The RPC normalizes, hashes, looks up, verifies expiry/revocation, applies the three-layer throttle, links the viewer to the device, enforces the five-viewer capacity, records the first claim, and returns success. **It does not return the device id** to the client. A persistent code remains reusable until the owner rotates or revokes it.
7. The owner publishes via `publish_status`; the viewer reads via `get_paired_status`.

**The raw code is never stored in Postgres and never logged.**

### 8.4 RPC surface — **CHANGED (audit A7, B7)**

All are `SECURITY DEFINER`, `SET search_path = public, pg_temp`, and revoke `EXECUTE` from `public` while granting it to `authenticated`.

| RPC | Caller | Signature | Returns | Notes |
|---|---|---|---|---|
| `register_device` | owner | `(p_recovery_hash text)` | `uuid` | Idempotent per owner; errors if an active device exists |
| `publish_status` | owner | `(p_state text, p_call_okay boolean, p_override_mode text, p_override_expires_at timestamptz, p_screen_sharing text)` | `timestamptz` (`last_seen_at`) | Upsert; validates enums; `last_seen_at = updated_at = now()`; used for both changes and heartbeats |
| `update_device_profile` | owner | `(p_display_name text)` | `void` | Trims, enforces ≤ 80, rejects control characters; accepts no other column |
| `create_pairing_code` | owner | `(p_code_hash text)` | `uuid` | Revokes the owner's other active codes first |
| `rotate_pairing_codes` | owner | `()` | `integer` | Revokes all active codes and viewer bindings; returns the code count |
| `revoke_viewer` | owner | `(p_viewer_user_id uuid)` | `void` | |
| `delete_viewer` | owner | `(p_viewer_user_id uuid)` | `void` | Hard-deletes one binding; never deletes the auth user |
| `revoke_all_viewers` | owner | `()` | `integer` | |
| `list_viewers` | owner | `()` | `setof (viewer_user_id uuid, created_at timestamptz, revoked_at timestamptz)` | Active, non-expired rows for the owner UI; at most five |
| `rebind_device` | owner | `(p_recovery_secret text)` | `uuid` | §8.6; throttled like a claim |
| `delete_device` | owner | `()` | `void` | §8.7; cascades |
| `claim_pairing_code` | viewer | `(p_code text)` | `jsonb {ok, reason}` | §8.5; generic failure reason |
| `get_paired_status` | viewer | `()` | `jsonb` | **The only viewer read.** Returns exactly `{ display_name, state, call_okay, last_seen_at, server_now, schema_version }` |

`get_paired_status()` deliberately omits `device_id`, `override_mode`, and `override_expires_at`. It returns `{ "paired": false }` when the viewer has no active pairing, so a revoked viewer gets a clear, non-enumerating answer.

Viewer bindings expire 30 days after `created_at`; reads and owner lists treat
older active rows as unpaired before the scheduled cleanup deletes them. A
fourth distinct claim hard-deletes the oldest active binding for that device.

### 8.5 Pairing code security — **CHANGED (audit A5, B12, B15)**

**Code format.** Crockford Base32 alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (no I, L, O, U), **10 characters = 50 bits** of entropy, generated from `SecRandomCopyBytes`, displayed as `XXXXXXXXXX`.

**Normalization** before hashing, on both sides, identically: uppercase; strip all non-alphabet characters (so hyphens and spaces are irrelevant); map `I`→`1`, `L`→`1`, `O`→`0` (Crockford's standard confusables). Reject any code whose normalized length ≠ 10.

**Hashing:** `sha256` hex of the normalized code. A fast hash is correct here — 50 bits of entropy makes offline brute force infeasible, and a slow KDF would add RPC latency for no gain.

**Lifetime:** A code remains active until the owner manually rotates or
revokes it. Creating a replacement revokes the previous active code. A
successful claim records `claimed_at` for audit purposes but does not consume a
persistent code.

**Three-layer throttle.** All windows are **fixed 15-minute tumbling windows**: on an attempt, if `now() - window_started_at >= interval`, reset `window_started_at = now()` and the counter to 0, then increment (audit B15).

| Layer | Key | Limit | Bypassable by minting anon users? |
|---|---|---|---|
| Per-viewer | `viewer_user_id` | 5 / 15 min | Yes — this is why the other two exist |
| Per-IP | `inet_client_addr()` | 20 / hour | Partly |
| **Global circuit breaker** | singleton row | **100 failures / hour → all claims rejected for the remainder of the window** | **No** |

**Turnstile.** Anonymous sign-in requires a Cloudflare Turnstile token (native Supabase Auth support), which prices out the anon-user-minting bypass.

**Oracle suppression.** Invalid, expired, and revoked all return the identical
`{ ok: false, reason: "invalid_code" }`. Rate limiting returns
`{ ok: false, reason: "rate_limited" }` and may be shown distinctly. Detailed
internal reason codes may be recorded server-side only. The claim path must not
return early on the first failing check. It evaluates all checks, then decides.

### 8.6 Device recovery — **NEW (audit A4)**

Anonymous identity is only as durable as the local refresh token. Losing it (Keychain reset, re-image, restore to new hardware, long offline period) would otherwise orphan the device and every viewer paired to it, permanently and irreversibly.

1. At `register_device`, the Mac generates **32 random bytes** and derives a **26-character Crockford Base32 recovery phrase** shown as `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-X`.
2. Only `sha256(normalize(phrase))` is stored, as `devices.recovery_hash`.
3. The phrase is stored locally in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`, **not** iCloud-synchronized) and is displayable on demand from `Recovery ▸ Show recovery phrase`. First run requires an explicit "I have saved this" confirmation.
4. `rebind_device(p_recovery_secret)` looks up the hash, and if the device is not revoked, updates `devices.owner_user_id` to the current `auth.uid()`. **All viewer pairings survive.** Throttled identically to claims and rate-limited per calling user.
5. The phrase is never logged, never published, never sent to the viewer, and is excluded from the diagnostics export.

### 8.7 Deletion and reset — **NEW (audit B5)**

`Reset & delete remote data…` calls `delete_device()`, which deletes the device row; `ON DELETE CASCADE` removes `current_status`, `pairing_codes`, and `viewers`. The Mac then clears the Keychain entries, the local override, and the local profile, and returns to first-run state. Paired viewers subsequently receive `{ "paired": false }` and are shown the re-pair screen.

---

## 9. Synchronization

The MVP deliberately avoids realtime.

### 9.1 Owner writes

- Immediately on an effective-state change.
- Immediately after a manual override change or a `call_okay` change.
- Immediately when an override expires (§6.5).
- Once per **60 s** as a heartbeat while healthy.
- After sleep/wake, network recovery, permission change, or detector-health change.
- `screen_sharing` is always `null` in the MVP.
- Display-name changes go through `update_device_profile` and do not require a status write.

### 9.2 Retry policy — **NEW (audit B11)**

| Parameter | Value |
|---|---|
| Base delay | 1 s |
| Multiplier | 2× |
| Maximum delay | 60 s |
| Jitter | Full jitter — `random(0, min(cap, base × 2^attempt))` |
| Heartbeat/state publishes | Retry indefinitely at the 60 s cap; coalesce so only the **latest** state is ever sent |
| User-initiated actions | Maximum 5 attempts, then surface an error in the menu bar |
| Never | Never report a successful sync when the write failed. `lastSuccessfulSync` updates only on a 2xx |

A network failure **does not change the owner's local state**; it changes remote freshness and shows a local sync warning.

### 9.3 Viewer reads and freshness — **CHANGED (audit A6)**

Reads occur: on load · immediately after pairing · every **30 s** while visible **and** focused · immediately on regaining visibility+focus · immediately on `Refresh now`. Polling is paused while hidden or unfocused; no background process is required.

**Staleness must be computed entirely from server-sourced values.** `get_paired_status()` returns `server_now` from the same statement as `last_seen_at`:

```ts
const ageSeconds = (Date.parse(r.server_now) - Date.parse(r.last_seen_at)) / 1000;
const stale = ageSeconds > 180;              // 3 missed 60 s heartbeats
const display = stale ? "unavailable" : r.state;
```

The browser's wall clock is **never** compared against a server timestamp. The "last checked" label is derived from `performance.now()` elapsed since the fetch completed — a monotonic local timer, immune to clock changes.

Rationale: a slow browser clock would otherwise show a stale `Available` indefinitely, which is exactly the guessed-Available that Goal 10 forbids.

On a failed read the page must **not** make an optimistic meeting claim; it
keeps the previous value visibly marked as not-just-refreshed, and after 180 s
of failure shows `Meeting status unavailable`.

Expected end-to-end update delay: roughly the 30 s poll interval plus network latency. This is not a realtime product.

### 9.4 Schema version handling — **NEW (audit B3)**

The viewer knows `SUPPORTED_SCHEMA_VERSION = 1`. If
`schema_version > SUPPORTED_SCHEMA_VERSION`, it renders `Meeting status
unavailable` rather than misinterpreting fields. If it is lower, apply
documented defaults.

### 9.5 Viewer presentation requirements — **NEW (audit B10)**

The primary user is a non-technical person on a phone.

- **WCAG 2.2 AA**: contrast ≥ 4.5:1; state is conveyed by **text and shape**, never colour alone; a visible focus ring; a ≥ 44×44 px `Refresh now` hit target.
- `aria-live="polite"` on the state region so a state change is announced.
- `prefers-color-scheme` for light/dark; `prefers-reduced-motion` respected (no spinner animation when set).
- Offline (`navigator.onLine === false` or a fetch failure): the neutral
  `Meeting status unavailable` message with no state guessing.
- No layout shift between states; reserve the display-name slot.
- The page must be usable and legible at 320 px width.
- No analytics, no third-party scripts, no fonts fetched from third-party origins. (Turnstile is the sole third-party script, and only on the pairing screen.)

---

## 10. Security, privacy, and observability

### 10.1 Privacy boundary (unchanged from v1, plus two closures)

TLS everywhere · Supabase Auth sessions only, never a service-role key in the app or browser · RLS on all access · store only the optional display name, state, `call_okay`, override metadata (**owner-visible only**), and freshness timestamps · never upload meeting titles, URLs, participant names, audio, video, screenshots, OCR text, or screen contents · pairing codes hashed at rest · codes expire and rotate · viewer and device revocation supported · logs redacted · Accessibility treated as sensitive and used only against Chrome and Slack · **Screen Recording never requested** · no device identifier in any public or enumerable URL · no deployment values committed.

**Closed in v2:** override metadata is no longer readable by the viewer (A7), and the device id is no longer returned to the viewer (A7).

### 10.2 Threat model summary

| Threat | Control |
|---|---|
| Pairing-code guessing | 50-bit code, 10-min TTL, single use, three-layer throttle, Turnstile |
| Anon-user minting to bypass throttles | Global circuit breaker + Turnstile |
| Viewer enumeration of other devices | No table grants; RPC-only reads scoped by `auth.uid()` |
| Client clock manipulation | All timestamps server-assigned; staleness computed server-side |
| Malicious client writing status | Writes only via ownership-verifying `SECURITY DEFINER` RPCs |
| Local identity loss | Recovery secret + `rebind_device` |
| Secret leakage into the public repo | `.gitignore` + `gitleaks` in CI and pre-commit + `.example` files only |
| Search-path hijacking of DEFINER functions | `SET search_path = public, pg_temp` on every RPC |
| Log leakage of private UI text | Category/code-only logging + a redaction unit test |

### 10.3 Logging and diagnostics — **NEW (audit B6)**

- `OSLog`, subsystem `com.techdevix.meetingpulse`, categories `detection`, `reducer`, `sync`, `permission`, `pairing`.
- A rotating file log at `~/Library/Logs/MeetingPulse/meetingpulse.log`, ≤ 5 MB per file, ≤ 3 files, **7-day retention**.
- **Never logged:** URLs, window/tab titles, UI text, display names, pairing codes, recovery phrases, tokens, Supabase keys, `auth.uid()` values.
- **Logged:** observation category, diagnostic code, health transitions, publish outcome + HTTP status, retry counts, timings.
- A **redaction unit test** feeds a synthetic log line containing every forbidden value class and asserts none survives the redactor.
- `Export diagnostics…` writes a sanitized bundle (app version, macOS version, Chrome/Slack versions, permission status, detector health history, last sync outcomes, redacted log tail) to a user-chosen path, after showing the user exactly what it contains.

---

## 11. Errors, performance, and acceptance

### 11.1 Error handling

| Failure | Behaviour |
|---|---|
| Accessibility permission missing | Clear permission state in the menu; opens System Settings on request; publishes `unavailable` (unless an override is active, §6.4 STEP 1). Never silently falls back to Available |
| Detector UI change | `unknown` + a stable diagnostic code; reducer publishes `unavailable`; the menu bar names the source needing attention. Errors are never blanket-caught and swallowed |
| Supabase/network failure | The local state machine keeps running; bounded backoff per §9.2; `lastSuccessfulSync` recorded; never a false success |
| Crash / force quit / sleep | The viewer derives `unavailable` once the heartbeat goes stale. On restart or wake, both sources are re-sampled and a fresh state is published before normal heartbeats resume |
| Multiple simultaneous sources | Any confirmed active source yields Busy. Source identity is local-diagnostics-only and never transmitted |
| Pairing failure | Generic `invalid_code` for invalid/expired/claimed/revoked; a distinct `rate_limited` message; detailed reasons stay server-side |
| Viewer revoked | `get_paired_status()` returns `{paired:false}`; the page shows the re-pair screen with a plain explanation |

### 11.2 Performance constraints

- Idle memory ≤ **80 MB** RSS after warm-up.
- Idle CPU < **1%** average over a 10-minute sample.
- No continuous audio/video processing. No screen capture.
- Detector sampling is cancellable; no unbounded timers or tasks.
- Viewer polling fetches one small row.

If a dependency violates these, remove or replace it before adding features.

### 11.3 Latency bounds — **CLARIFIED (audit C4)**

| Path | Bound |
|---|---|
| Confirmed start → local menu-bar state, **when an AX event fires** | ≤ 5 s |
| Confirmed start → local state, **no AX event (safety sample only)** | ≤ 20 s (`idleSampleInterval`) + publish latency |
| Confirmed end → local state | Two-sample settle (≈ 4 s in active mode) |
| Local state → focused viewer | ≤ 30 s (next poll), or immediate on `Refresh now` |
| Heartbeat loss → `Status unavailable` on the viewer | ≤ 180 s + the next read (≤ 210 s) |

### 11.4 Performance measurement method — **NEW (audit B9)**

Run on the target Apple Silicon Mac, release build, after a 5-minute warm-up with Chrome and Slack open and no meeting in progress:

```bash
# Memory: footprint reports phys_footprint, the number Activity Monitor shows
footprint -a "Meeting Pulse"  # PASS if phys_footprint <= 80 MB

# CPU: 10-minute sample
top -l 60 -s 10 -pid $(pgrep -x "Meeting Pulse") -stats cpu | \
  awk '/^[0-9]/{s+=$1;n++} END{print "avg cpu%", s/n}'
# PASS if avg <= 1.0
```

Record both numbers in the release notes. A regression of > 20% between releases blocks the release.

### 11.5 Acceptance criteria

1. A confirmed start is reflected in the local menu-bar state within the §11.3 bounds.
2. A confirmed end is reflected locally after the two-sample settle rule.
3. A focused, visible viewer sees a changed state on the next 30 s read, or immediately on `Refresh now`.
4. A stale or failed heartbeat produces `Status unavailable` within 180 s plus the next read.
5. No meeting details or media leave the Mac. *(Verified by a network-capture test, plan §7.4.)*
6. A viewer cannot read an unpaired device.
7. An unpaired or revoked viewer cannot write status.
8. The app meets the §11.2 targets measured per §11.4.
9. **(new)** A viewer whose device clock is off by ±6 hours displays the correct state.
10. **(new)** Deleting and restoring the Mac's Keychain entry, then entering the recovery phrase, restores the device with the existing viewer pairing intact.
11. **(new)** The reducer's full 4×4 decision table (§6.4) passes as unit tests, including the permission-denied collapse.

---

## 12. Testing

### 12.1 Unit tests (reducer)

All 16 cells of the §6.4 table · the permission-denied collapse · override busy/available · every fixed duration preset including the 30-minute default and "until cleared" · custom duration bounds · override persistence across a simulated relaunch · override expiry firing an immediate publish · clear-override returning to automatic · `call_okay` independence · the two-consecutive-sample end rule · stale-heartbeat derivation · `unknown` is never coerced to `inactive`.

### 12.2 Detector tests

Recorded, **sanitized** AX snapshots or test doubles. Never store real meeting content, URLs, titles, or credentials.

Meet pre-join · Meet active call · Meet leave/end · tab closed / navigated away · multiple Chrome windows and tabs · **Meet tab backgrounded (latch maintained)** · **latch released on tab close** · **`maxLatchDuration` expiry → `unknown`, not `inactive`** · Slack open without a Huddle · Slack active Huddle · Huddle end · Slack minimized/background · app not installed · app not running · Accessibility denied · unexpected/missing labels.

### 12.3 Integration tests (local or test Supabase project)

Anonymous Mac auth · device registration · one-active-device-per-owner enforcement · pairing-code creation and hashing · valid claim · expired / revoked / already-claimed claims all returning identical generic errors · **per-viewer, per-IP, and global throttles** · **`rebind_device` preserving viewer pairings** · **`delete_device` cascading** · RLS: owner write allowed, viewer table read denied, unauthorized device write blocked · viewer read via `get_paired_status` only · revocation · status update and heartbeat · **`server_now` staleness with a client clock skewed ±6 h** · viewer manual refresh · visibility/focus-gated polling · blank / non-blank / edited / removed display names · viewer text escaping (inject `<img src=x onerror=...>` as the display name and assert it renders as literal text) · the 80-character limit · **`schema_version` ahead of the client** · missing/malformed configuration failing clearly with no fallback · `.example` files containing placeholders only · the log-redaction test.

### 12.4 Real-device acceptance matrix

1. Scheduled Meet in Chrome · 2. Impromptu Meet link · 3. Joining someone else's link · 4. Leaving Meet normally · 5. Closing Meet/Chrome unexpectedly · 6. Slack Huddle start · 7. Slack Huddle end · 8. Huddle while Slack is unfocused · 9. Switching tabs/windows during Meet · **9b. Switching to another *app* for 10 minutes during a Meet call (the latch test)** · 10. Manual Busy with no meeting · 11. Manual Available during a detected meeting · 12. `call_okay` while Busy · 13. Restart and launch at login · 14. Sleep/wake · 15. Network loss and recovery · 16. Removing and restoring Accessibility permission · 17. Viewer page closed/reopened · 18. Pairing revoke and rotation · 19. Viewer `Refresh now` fetches immediately · 20. Polling pauses while hidden/unfocused and resumes with an immediate fetch · **21. Recovery-phrase rebind after clearing the Keychain** · **22. Viewer on a phone with the clock set 6 hours wrong** · **23. Override expiring while the Mac is asleep**.

---

## 13. Future extensions

Design the interfaces now; do **not** implement in the MVP: meeting started/ended timestamps · current duration · richer last-checked data · screen-sharing state · multiple viewers with per-contact permissions · a native mobile viewer · calendar and official platform integrations · more providers · optional notifications · authenticated accounts and billing · status history and analytics.

**Screen sharing (Phase 2).** Inspect Meet for a presentation state or stop-presenting control, and Slack for a screen-share state or stop-sharing control. A generic macOS-wide signal is not the source of truth, and ScreenCaptureKit must not be used to capture or analyse the screen. A missing signal is `unavailable`, never `no`. The `screen_sharing` column already exists. Phase 2 requires real-device tests for Meet entire-screen/window/tab modes plus Slack share and stop-share transitions. The viewer may then show `Screen sharing: Yes/No/Unavailable` below the main state.

---

## 14. Resolved decisions

Every "open decision" from v1 §12 is now closed. These are binding.

| Question (v1 §12) | Resolution |
|---|---|
| Minimum macOS target | **14.0**, Universal 2, Xcode 16.x / Swift 6.0 |
| Exact AX labels/roles | Determined empirically by **Spikes S1 and S2**; isolated to one module per detector |
| Cloudflare Pages project & DNS | Project `meetingpulse-viewer`; `PUBLIC_STATUS_ORIGINS` is required build config with no default. `og.techdevix.com` appears only as a documentation example |
| Code alphabet and length | **Crockford Base32, 10 chars, 50 bits**, shown `XXXXXXXXXX` |
| RPC only, or an Edge Function | **Postgres RPC only.** Turnstile is verified by Supabase Auth natively; no Edge Function is needed |
| Heartbeat interval | **60 s**, stale at **180 s**; viewer polls **30 s** when focused. Revisit after real-world use |
| Universal binary in v1 | **Yes** |
| License | **MIT** |

**New decisions introduced by v2:** App Sandbox disabled and MAS distribution ruled out (§5.4) · reducer precedence `override > busy > unknown > available` (§6.4) · latched Meet detection gated on S1 (§7.3) · device recovery secret (§8.6) · three-layer pairing throttle with Turnstile (§8.5) · viewer reads via `get_paired_status()` only (§8.4) · server-time staleness (§9.3).
