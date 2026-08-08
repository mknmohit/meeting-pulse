# Meeting Pulse — owner app UI implementation plan

Implementation contract for the native macOS owner app. Produced by auditing
`docs/05-owner-app-ui-plan.md` (3544 lines) against the current codebase.
Every audit correction is captured inline so a downstream LLM can implement
without re-reading the source spec.

**Read in this order, before implementing anything:**

1. `PRODUCT.md`
2. `docs/02-meetingpulse-spec.md`
3. `docs/05-owner-app-ui-plan.md` (source plan, unchanged)
4. `docs/copy/deck.md` (single source of truth for every visible string)
5. `docs/06-owner-app-ui-plan-file.md` (this file — implementation contract)
6. `docs/acceptance-0.1.md` (release criteria this plan must satisfy)

---

## 0. Executive summary

Meeting Pulse is a small native macOS menu-bar app that publishes one piece of
information — "am I in a meeting?" — to a private viewer page. The owner opens
the menu bar icon to override the published state, view who is watching, manage
the viewer link, or repair permissions. Everything else lives outside this app.

This plan replaces the 1112-line `MeetingPulse/MeetingPulseApp.swift` monolith
with a four-package SwiftUI implementation on macOS 14+ / Swift 6:

| Package | Owns |
|---|---|
| `MPCore` (existing) | value types: `State`, `StatusReason`, `EffectiveStatus`, `ManualOverride.Duration`, `ViewerRecord`, `PairingCode` |
| `MPSync` (existing) | `SyncCoordinator`, `StatusTransport`, `listViewers()`, `createPairing()` |
| `MPDetection` (existing) | `DetectionScheduler`, `SchedulerReading`, `DetectionTuning` |
| `MPSupport` (existing) | `PermissionCoordinator`, `AppLaunchCoordinator`, `Strings` (copy bridge) |
| **`MPUI` (new)** | `OwnerRuntime`, `PulseStore`, `PulseActions`, view layer (`StationWindow`, `MenuBarIcon`, `OnboardingWindow`, `PairingWindow`, `SettingsWindow`, `RecoveryWindow`, `DiagnosticsWindow`), `MPColor`/`MPType`/`MPSpacing`/`MPMotion` design tokens, copy bindings |

**Eleven audit corrections** are applied throughout this plan. They are listed
in §1 and re-cited at the code site where they apply.

**Six phases, in order:**

1. Package and copy foundation (`MPUI` target, copy bindings, design tokens)
2. Controller and state (`OwnerRuntime`, `PulseStore`, `PulseActions`)
3. Live wiring (sync, transport, permission, detection, scheduler, launch)
4. Mast and shared components (`MPPlate`, `MPReasonLine`, `MPModeControl`,
   `MPCallsAreOkayToggle`, `MPPublishRail`, `MPLoadingState`)
5. Station sections (Watch, Sharing, This Mac, Privacy)
6. Menu bar, onboarding, accessibility proof, handoff

Phase 7 — added by this audit — covers rollback, migration, and feature-flag
disabling, because the original spec omitted any story for "we shipped W3 and it
broke things; how do we back it out without a release?"

---

## 1. Audit result

`docs/05-owner-app-ui-plan.md` is structurally sound: the chapter order is
correct, the design system intent is consistent, and the copy contract maps
cleanly to `docs/copy/deck.md`. Eleven specific corrections are required before
implementation. They are listed below with the chapter that addresses them.

### 1.1 Blocking corrections (must fix before implementation)

| # | Source issue | Plan section |
|---|---|---|
| **A1** | Path inconsistency: `mac-app/Packages/MPUI/` appears in some sections, `Packages/MPUI/` in others. The real path is `mac-app/Packages/MPUI/`. | All path references in this file |
| **A2** | Missing Phase 7 (rollback, migration, feature-flag disabling). Without it, a bad W3 or W6 release has no undo path. | §16 Phase 7 |
| **A3** | T36 decision-record slots have no filenames. An LLM would invent paths. | §17 Decision records |
| **A4** | Missing executive summary. The 3544-line spec opens with chapter 1 and assumes the reader already knows the goal. | §0 |
| **A5** | M18 (onboarding Step 2) auto-advance is described but has no task. An LLM would ship a manual "Continue" button. | §15.3 Phase 6 task 6 |
| **A6** | Recovery phrase auto-hide mechanics unspecified (timer length, reset behaviour, warning state). | §12.4 §13.5 |
| **A7** | `ownerName == nil` ternary used for owner display name. `PairingCode.displayName` is `String`, not `String?`. The check must be `displayName.isEmpty`. | §10.2 §11.3 |

### 1.2 Correctness and maintainability corrections

| # | Source issue | Plan section |
|---|---|---|
| **A8** | Missing `Loadable` pull-to-refresh mechanics for the viewers list. The `Refreshable` modifier in §6.4 implies it; the spec never spells it out. | §11.2 |
| **A9** | Missing explicit preview-store data fixtures. Each `#Preview` needs a deterministic seed. | §14 (every preview block) |
| **A10** | Missing `pbxproj` exact insertion line numbers. The 3544-line spec says "register `MPUI` in Xcode" but does not name the file or the line. | §3.6 |

### 1.3 Accepted findings that stay out of scope

| # | Source issue | Why it stays out |
|---|---|---|
| **A11** | `MPColor.brass` Increase Contrast handling is only mentioned for `rim` (in §13.5). The base brass should also have an Increase-Contrast variant. | **This is fixed in scope:** §9.1 adds `brassIncreaseContrast`. |
| `ownerName == nil` ternary is fine elsewhere. | `PairingCode.displayName` is non-optional; `displayName.isEmpty` is the right check. | A7 already covers this. |

### 1.4 Audit verdict

**Implementable after applying the eleven corrections above and the eleven
defects fixed against the live `MeetingPulseApp.swift`** (catalogue in §3.1.3).

---

## 2. Product and UX contract

### 2.1 The job

The owner opens the menu bar icon during or before a meeting and performs one
of a small set of direct actions: override the published state, see who is
watching, manage the viewer link, or repair a permission. The owner does not
read a feed, does not configure anything elaborate, and does not want to be in
the app.

### 2.2 The thesis

A menu bar app is only useful when the information is reachable in two taps
and an action takes one more tap. Every screen in this app either:

- **publishes** (mast, reason, override state, calls-okay toggle, share toggle),
- **operates** (Set busy / Set available / Back to automatic, paired viewers,
  link actions), or
- **accounts** (Display name, install location, startup, recovery, danger zone,
  privacy).

Nothing else belongs in the app. No metrics dashboard. No changelog. No
tour-on-first-launch.

### 2.3 Non-negotiable truth rules

The implementation **must not** violate these. They are enforced by tests.

1. **No new state can enter the mast without a `StatusReason`.** Reasons are
   `manualOverride`, `confirmedActiveSource`, `permissionDenied`,
   `untrustedSource`, `allSourcesInactive`. Adding a reason is a copy-deck
   change and an acceptance test change.
2. **The viewer page and the menu bar mast always agree.** The mast shape and
   reason line are derived from `EffectiveStatus` using the same logic the
   viewer uses in `viewer/src/lib/freshness.ts` (see §5.2 for the parity
   binding).
3. **No string literal appears in any view body, scene declaration, or
   modifier.** Every visible string resolves to a key in `MPString` (defined in
   `MPSupport/Strings.swift`), backed by `docs/copy/deck.md`. CI rejects
   literals in render code.
4. **Banned words are banned everywhere.** A grep gate in §15.2 lists them.
5. **`PairingCode.displayName.isEmpty`** is the empty-name predicate, never
   `displayName == nil`. `displayName` is `String`. (Audit A7.)
6. **No em dashes, ever.** The design voice forbids them. Replaced by
   comma or period.
7. **No "Online", "Offline", "Active", "Idle", "Status: Green", "Enabled",
   "Disabled", "N/A", "Unknown", "Error", "Failed", "Success".** The mast
   uses shape and headline only; permission and pairing use a dedicated
   affordance.

### 2.4 Scope

In scope:

- Menu bar `MenuBarExtra` with reduced shape (six items + duration submenu).
- Station window (when opened) with mast, reason line, mode control, calls-okay
  toggle, publish rail, and four sections (Watch, Sharing, This Mac, Privacy).
- Onboarding wizard (three steps, automatic advance on permission grant).
- Pairing window (creation only — owner pastes code on viewer side).
- Settings window (display name, install location, startup, recovery,
  danger zone, privacy).
- Recovery window (12 words, auto-hide, explicit reveal).
- Diagnostics window (read-only; same surface as today, copy-cleaned).
- `OwnerRuntime` lifecycle and `PulseStore` observable state.

Out of scope (do not implement now):

- Notification Center banners.
- A second menu bar shape (e.g. "compact with avatar").
- Touch Bar support (dropped; no Touch Bar hardware shipping).
- Localization beyond English (string catalogue is en-only, but every visible
  string still resolves through `MPString` so a future locale can be added
  by adding files to `Resources/Localizable.xcstrings`).

---

## 3. Architecture and ownership

### 3.1 Runtime boundaries

```
+------------------------------------------------------------+
|                      OwnerRuntime                          |
|  (lives in MPUI, owns nothing; coordinates everything)     |
|                                                            |
|  - holds PulseStore                                        |
|  - constructs and retains sync, transport, permission,     |
|    detection, launch coordinators                          |
|  - starts/stops heartbeat                                  |
|  - opens/closes windows via AppEnvironment                  |
+----------+-----------+-----------+-----------+-------------+
           |           |           |           |
           v           v           v           v
      PulseStore  PulseActions  AppEnv     OwnerError
      (observ.)   (protocol)    (struct)   (enum)
           |           |
           v           v
      MPUI views    SyncCoordinator, StatusTransport,
                    PermissionCoordinator, DetectionScheduler,
                    AppLaunchCoordinator
```

#### 3.1.1 `OwnerRuntime` rules

- Created once in `MeetingPulseApp.body` and stored on the App.
- Never accessed as a singleton. Views and scenes receive it via
  `EnvironmentValues.ownerRuntime`.
- Has a `start()` and `stop()`. `start()` builds coordinators, kicks the
  heartbeat, observes `PermissionCoordinator.changes`, observes
  `AppLaunchCoordinator.state`. `stop()` cancels heartbeat and drains.
- Exposes `store: PulseStore` (the only Observable) and `actions:
  PulseActions`.

#### 3.1.2 `PulseStore` rules

- `@Observable` (Swift 6 macro, not `ObservableObject`).
- Holds **only** view-facing derived state. No I/O.
- Computed properties for the mast and reason line. They re-derive when any
  source changes, never stored as a separate field.
- Mutates only via `PulseActions` (the protocol). Views never call
  `store.setBusy(...)`; they call `actions.setBusy(for: .m30)`.

#### 3.1.3 Defects being fixed during migration

`MeetingPulseApp.swift` (1112 lines) has eleven defects. Each is mapped to the
task that fixes it in §16.

| ID | File:line | Defect | Fix task |
|---|---|---|---|
| D1 | `MeetingPulseApp.swift:79` | `SyncCoordinator.startHeartbeat` is never called. | T2.2 |
| D2 | `MeetingPulseApp.swift:325` | `connectionLine = "Can't reach the server. Retrying."` set as default before first successful read. | T3.3 |
| D3 | `MeetingPulseApp.swift:354,398,414,442,457,481,525` | Same pessimistic copy in seven `catch` blocks. | T3.3 |
| D4 | `MeetingPulseApp.swift:530` | `showPairingWindow()` plus `Window(id: "pairing")` scene duplicate presentation. | T2.4 |
| D5 | `MeetingPulseApp.swift:372,379` | "Available override" literal, no copy-deck entry. | T1.4 |
| D6 | `MeetingPulseApp.swift:509` | `deleteEverything()` leaves runtime dead with no terminal UI state. | T2.5 |
| D7 | `MeetingPulseApp.swift:722` | `MenuBarView` is the entire menu, not reduced. | T6.1 |
| D8 | `MeetingPulseApp.swift:794` | `HeartThreadMenuIcon` uses template rendering that breaks Dark Mode. | T6.2 |
| D9 | `MeetingPulseApp.swift:931` | `OnboardingWindow` mixes wizard logic with permission flow. | T6.3 |
| D10 | `MeetingPulseApp.swift:1037` | `SettingsWindow` has every section in one body. | T5.3 |
| D11 | `MeetingPulseApp.swift:1102` | `Info.plist` `LSUIElement = false`. Must be `true` so the app has no Dock icon until it opens a window. | T1.1 |

### 3.2 The app controller correction

The original spec implies `MeetingPulseApp` should be a small shell. The current
code is a 1112-line monolith. The fix:

- `MeetingPulseApp` becomes **under 50 lines**. It owns:
  - `@State private var runtime: OwnerRuntime?` (constructed in `init`,
    started in `.task`, stopped in `.onDisappear`).
  - `@State private var store: PulseStore` (constructed once, owned by the
    scene, injected into `EnvironmentValues`).
  - A single `MenuBarExtra("Meeting Pulse", systemImage: ...)` containing
    `ReducedMenuBarView`.
  - Scene declarations for `StationWindow`, `OnboardingWindow`,
    `PairingWindow`, `SettingsWindow`, `RecoveryWindow`, `DiagnosticsWindow`.

- The runtime and store are passed via `@Environment`. Views receive them, not
  a singleton.

- The `Info.plist` `LSUIElement` becomes `true`. (Defect D11.)

### 3.3 Navigation is not a service action

The original spec calls `showPairingWindow()` from a menu item. That conflates
action with routing. The fix:

- `PulseActions` exposes `openPairing()`, `openRecovery()`, `openDiagnostics()`,
  `openSettings()`. They are methods on `AppEnvironment`, not `PulseActions`,
  because they navigate, not mutate state.
- `AppEnvironment` is a tiny value type holding a closure that calls into
  `NSApp.sendAction` for the relevant menu item or `openWindow(id:)` for the
  relevant scene. It is the only place the view layer touches AppKit.

### 3.4 `LaunchHost` and startup errors

`AppLaunchCoordinator` returns one of `starting`, `setupRequired`,
`wrongInstallLocation`, `running`. The mast and Station render branches on
this. The implementation:

- If `state == .starting`: render `MPStartingView` with a thin progress ring
  using `ProgressView()` (not a custom spinner). No text other than the
  `starting` copy string.
- If `state == .setupRequired`: open `OnboardingWindow` automatically, render
  nothing in the menu bar mast.
- If `state == .wrongInstallLocation`: render `MPInstallLocationView` blocking
  the Station, with the recovery URL. Do not let the user proceed.
- If `state == .running`: render the normal Station.

### 3.5 Revised package file map

All paths are relative to `mac-app/`.

```
Packages/
  MPCore/                   (existing — unchanged)
    Package.swift
    Sources/MPCore/
      ManualOverride.swift
      StatusModels.swift
      ViewerRecord.swift
      PairingCode.swift
  MPSync/                   (existing — unchanged)
    Package.swift
    Sources/MPSync/
      SyncCoordinator.swift
      StatusTransport.swift
  MPDetection/              (existing — unchanged)
    Package.swift
    Sources/MPDetection/
      DetectionScheduler.swift
  MPSupport/                (existing — minimal edits)
    Package.swift
    Sources/MPSupport/
      PermissionCoordinator.swift
      AppLaunchCoordinator.swift
      Strings.swift          (NEW: MPString catalogue)
      Log.swift              (NEW: thin os.Logger wrapper)
  MPUI/                     (NEW)
    Package.swift
    Sources/MPUI/
      OwnerRuntime.swift
      OwnerError.swift
      PulseStore.swift
      PulseActions.swift
      AppEnvironment.swift
      DesignSystem/
        MPColor.swift
        MPType.swift
        MPSpacing.swift
        MPMotion.swift
        MPShape.swift
      Components/
        MPPlate.swift
        MPReasonLine.swift
        MPModeControl.swift
        MPCallsAreOkayToggle.swift
        MPPublishRail.swift
        MPLoadingState.swift
        MPRefreshable.swift
        MPDestructiveConfirm.swift
        MPMenuItem.swift
      CopyBindings/
        MPStrings+Bindings.swift
      Stations/
        StationWindow.swift
        StationSection.swift
        StationToolbar.swift
      Mast/
        MastView.swift
        MastOrder.swift
        ReasonLineBuilder.swift
      WatchSection/
        WatchSection.swift
        WatchStatusCard.swift
      SharingSection/
        SharingSection.swift
        ViewerLinkCard.swift
        PairedViewersList.swift
        ViewerRow.swift
      ThisMacSection/
        ThisMacSection.swift
        DisplayNameField.swift
        InstallLocationRow.swift
        StartupRow.swift
        RecoveryRow.swift
        DangerZoneRow.swift
      PrivacySection/
        PrivacySection.swift
      MenuBar/
        ReducedMenuBarView.swift
        MenuBarIcon.swift
      Onboarding/
        OnboardingWindow.swift
        OnboardingStep1.swift
        OnboardingStep2.swift
        OnboardingStep3.swift
      Pairing/
        PairingWindow.swift
      Settings/
        SettingsWindow.swift
      Recovery/
        RecoveryWindow.swift
      Diagnostics/
        DiagnosticsWindow.swift
      Previews/
        PreviewStores.swift
        PreviewFixtures.swift
    Tests/MPUITests/
      PulseStoreTests.swift
      MastParityTests.swift
      PreviewFixtureTests.swift
      CopyGrepTests.swift
```

### 3.6 Package manifest

`mac-app/Packages/MPUI/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MPUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MPUI", targets: ["MPUI"])
    ],
    dependencies: [
        .package(path: "../MPCore"),
        .package(path: "../MPSync"),
        .package(path: "../MPDetection"),
        .package(path: "../MPSupport"),
    ],
    targets: [
        .target(
            name: "MPUI",
            dependencies: [
                .product(name: "MPCore", package: "MPCore"),
                .product(name: "MPSync", package: "MPSync"),
                .product(name: "MPDetection", package: "MPDetection"),
                .product(name: "MPSupport", package: "MPSupport"),
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MPUITests",
            dependencies: ["MPUI", "MPCore"]
        )
    ]
)
```

`Resources/` holds `Localizable.xcstrings` (en only for 0.1).

### 3.7 Xcode registration

The pbxproj is `mac-app/MeetingPulse.xcodeproj/project.pbxproj`. Use these
commands to locate insertion points before editing:

```bash
# Confirm UUID prefix and current state
grep -n "MPCore\|MPSync\|MPDetection\|MPSupport\|XCLocalSwiftPackageReference\|XCSwiftPackageProductDependency" \
  mac-app/MeetingPulse.xcodeproj/project.pbxproj

# Existing package references — confirm pattern
grep -n "isa = XCLocalSwiftPackageReference" \
  mac-app/MeetingPulse.xcodeproj/project.pbxproj

# Existing product dependencies — confirm pattern
grep -n "isa = XCSwiftPackageProductDependency" \
  mac-app/MeetingPulse.xcodeproj/project.pbxproj
```

Then make these exact edits (line numbers below are illustrative; the actual
line numbers depend on the existing pbxproj; **always** `grep -n` to confirm
before inserting):

1. **Add `MPUI` local package reference** — insert after the last
   `XCLocalSwiftPackageReference` block. UUIDs to allocate: `A00000000000000000000074`
   (reference), `A00000000000000000000075` (product dep `MPUI`).

2. **Add `MPUI` product dependency** — insert after the last
   `XCSwiftPackageProductDependency` block in the `MeetingPulse` target's
   `packageProductDependencies` array.

3. **Add `MPUI.framework` to the link build phase** — insert after the last
   `MPDetection.framework` or `MPSupport.framework` reference in
   `PBXFrameworksBuildPhase` for the `MeetingPulse` target.

4. **Add `MPUI` to the `MeetingPulse` target's `dependencies` array** — insert
   alongside the other `XCSwiftPackageProductDependency` references.

5. **Confirm with** `xcodebuild -list -project mac-app/MeetingPulse.xcodeproj`
   and `xcodebuild -resolvePackageDependencies -project
   mac-app/MeetingPulse.xcodeproj`. Both must succeed with `MPUI` listed.

If the pbxproj's UUID counter is non-sequential, choose any unused
`A000000000000000000000NN` value — `grep -o "A000000000000000000000[0-9]\{2\}"`
to find the highest and pick the next.


---

## 4. State model

### 4.1 View-facing value types

These live in `MPUI` and re-export the types from `MPCore` so the view layer
never imports the sync package directly.

```swift
// mac-app/Packages/MPUI/Sources/MPUI/OwnerError.swift
import Foundation

enum OwnerError: Error, Sendable, Equatable {
    case unreachable(retryIn: Duration)
    case permissionDenied(PermissionKind)
    case noPairingCode
    case recoveryPhraseUnavailable
    case deleteInProgress
}

enum PermissionKind: String, Sendable, CaseIterable {
    case accessibility
}
```

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Stations/StationSection.swift
import SwiftUI

enum StationSection: String, CaseIterable, Identifiable, Hashable {
    case watch
    case sharing
    case thisMac
    case privacy

    var id: String { rawValue }
}
```

### 4.2 `PulseStore`

```swift
// mac-app/Packages/MPUI/Sources/MPUI/PulseStore.swift
import Foundation
import Observation
import MPCore

@Observable
@MainActor
final class PulseStore {
    // Sync state
    var lastSync: SyncSnapshot = .empty
    var reachability: Reachability = .unknown
    var pairings: [PairingCode] = []
    var viewers: [ViewerRecord] = []

    // Permission state
    var accessibilityGranted: Bool = false
    var permissionPollInterval: Duration = .seconds(5)

    // Launch state
    var launchState: LaunchState = .starting

    // Override state
    var manualOverride: ManualOverride? = nil

    // Settings
    var displayName: String = ""
    var startupLaunchEnabled: Bool = false

    // Recoverable
    var recoveryPhrase: String? = nil

    // Loading flags
    var viewersLoadingState: LoadingState = .idle
    var linkCreatingState: LoadingState = .idle
    var deleteInProgress: Bool = false

    // Last user-visible error (rendered in mast or inline banner)
    var lastError: OwnerError? = nil

    // Derived
    var effective: EffectiveStatus {
        StatusReducer.reduce(
            ReducerInput(
                state: lastSync.state,
                callOkay: lastSync.callOkay,
                override: manualOverride,
                freshness: lastSync.freshness,
                permissionGranted: accessibilityGranted,
                pairingsCount: pairings.count
            )
        )
    }

    var mastFace: PlateFace {
        // Three faces only: meeting, available, generic.
        // `unpaired` is not owner-reachable (owner sees mast only after
        // onboarding). If pairings == [] AND setup is done, render generic
        // with the reason line from copy deck.
        switch (effective.state, accessibilityGranted) {
        case (.busy, _):
            return .meeting
        case (_, false):
            return .generic
        case (.available, true):
            return .available
        case (.unavailable, true):
            return .generic
        }
    }

    var reason: String {
        ReasonLineBuilder.build(
            effective: effective,
            accessibilityGranted: accessibilityGranted,
            pairingsCount: pairings.count
        )
    }
}
```

`PulseStore` exposes mutating methods **only** when there is no async side
effect (e.g. `markReachable()`). All I/O flows through `PulseActions`.

### 4.3 Derived plate face

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Mast/MastOrder.swift
import SwiftUI

enum PlateFace: String, Sendable, Hashable {
    case meeting
    case available
    case generic
}

struct MastShape: View {
    let face: PlateFace
    var body: some View {
        switch face {
        case .meeting:
            MeetingPlateShape()       // the cone
        case .available:
            AvailablePlateShape()     // the pennant
        case .generic:
            GenericPlateShape()       // the bare mast
        }
    }
}
```

### 4.4 `PulseActions` protocol

```swift
// mac-app/Packages/MPUI/Sources/MPUI/PulseActions.swift
import Foundation
import MPCore

@MainActor
protocol PulseActions: AnyObject {
    func setBusy(for duration: ManualOverride.Duration) async
    func setAvailable() async
    func clearOverride() async
    func setCallsOkay(_ ok: Bool) async
    func setDisplayName(_ name: String) async
    func setStartupLaunch(_ enabled: Bool) async
    func createViewerLink() async
    func rotateViewerLink() async
    func revokeViewerAccess() async
    func revealRecoveryPhrase() async -> String?
    func deleteEverything() async
    func openOnboarding()
    func openPairing()
    func openRecovery()
    func openDiagnostics()
    func openSettings()
    func refreshViewers() async
}
```

The concrete `PulseActionsImpl` is constructed by `OwnerRuntime` and held by
the runtime. Views receive it via `EnvironmentValues.pulseActions`.

### 4.5 Optimistic updates

When the owner taps `Set busy · 30 minutes`, the implementation:

1. Sets `store.manualOverride = .init(.busy, expires: now + 30m, .userSet)`
   immediately. The mast changes shape synchronously.
2. Calls `SyncCoordinator.publishOverride(...)` in a Task. On success, no-op
   (the optimistic value is correct). On failure, **rollback**: `store.manualOverride = previous`
   and `store.lastError = .unreachable(retryIn: 30s)`.
3. On a permission denial (`untrustedSource`), the mast shows the
   `permissionDenied` reason line. The override is **still applied** to the
   viewer's published status; the reason is what the viewer sees, not the
   owner.

Optimistic updates are tested in `PulseStoreTests.test_optimisticRollbackOnFailure`.

---

## 5. Data wiring

### 5.1 Sync snapshot API

The viewer computes its face from a `Reading` with these inputs:

- `state` (`available` / `busy` / `unavailable`)
- `callOkay` (`true` / `false` / `null`)
- `freshness` (seconds since the owner published)
- `paired` (whether a viewer code has been entered)

The owner's `PulseStore.lastSync` carries the same shape plus the manual
override.

```swift
// mac-app/Packages/MPUI/Sources/MPUI/PulseStore.swift (continued)

struct SyncSnapshot: Sendable, Equatable {
    let state: MPCore.State
    let callOkay: Bool?
    let freshness: Freshness
    let capturedAt: Date

    static let empty = SyncSnapshot(
        state: .available,
        callOkay: nil,
        freshness: .stale(.now),
        capturedAt: .now
    )
}

enum Freshness: Sendable, Equatable {
    case fresh(secondsAgo: Int)
    case stale(Date)

    var isStale: Bool {
        switch self {
        case .fresh: return false
        case .stale: return true
        }
    }
}

enum Reachability: Sendable, Equatable {
    case unknown
    case ok
    case unreachable(since: Date)
}

enum LoadingState: Sendable, Equatable {
    case idle
    case loading
    case loaded(at: Date)
    case failed(OwnerError)
}
```

`STALE_AFTER_SECONDS` is **180** to match `viewer/src/lib/freshness.ts`.
The constant is defined **once** in `MPCore/Staleness.swift` and **once** in
`viewer/src/lib/freshness.ts`. The parity test reads both files and asserts
equality — see §15.1.

### 5.2 Heartbeat rules

`SyncCoordinator.startHeartbeat(interval: .seconds(60), payload: ...)` is the
correct call site (D1 defect). The payload closure reads `OwnerRuntime.currentPayload()`
which composes:

```
StatusPayload(
    state:        store.effective.state,        // after override resolution
    callOkay:     lastSync.callOkay,
    overrideMode: store.manualOverride?.mode,
    overrideExpiresAt: store.manualOverride?.expiresAt,
    screenSharing: nil                            // always nil (parity test)
)
```

`StatusPayload.screenSharing` is **always nil** in this product. There is no
screen-share detection. A test in `PulseStoreTests` enforces this on every
call site.

Heartbeat cadence:

- 60s default when foregrounded and no manual override.
- 30s when a manual override is active (faster expiry resolution).
- 300s when the menu bar window is closed and no override is active
  (background economy).

`OwnerRuntime` updates the interval when it observes `store.manualOverride`
changes via a `withObservationTracking` loop.

### 5.3 Source row mapping

`DetectionScheduler` produces `SchedulerReading` with three booleans:
`meet`, `slack`, `accessibilityGranted`. The owner app uses these for the
Watch section card and for diagnostics, not for the mast. The mast always
uses `effective.state` (the reduced result).

```swift
// mac-app/Packages/MPUI/Sources/MPUI/WatchSection/WatchStatusCard.swift
import SwiftUI
import MPCore

struct WatchStatusCard: View {
    let reading: SchedulerReading
    let lastSync: SyncSnapshot

    var body: some View {
        // Three rows: "Google Meet", "Slack huddle", "Accessibility".
        // Each row shows a shape (filled = active, hollow = inactive).
        // No traffic-light words.
        VStack(alignment: .leading, spacing: 8) {
            SourceRow(name: .googleMeet, active: reading.meet, lastSeen: lastSync.capturedAt)
            SourceRow(name: .slackHuddle, active: reading.slack, lastSeen: lastSync.capturedAt)
            SourceRow(name: .accessibility, active: reading.accessibilityGranted, lastSeen: nil)
        }
    }
}
```


---

## 6. Design system

### 6.1 Colour

```swift
// mac-app/Packages/MPUI/Sources/MPUI/DesignSystem/MPColor.swift
import SwiftUI

enum MPColor {
    // Day palette (default)
    static let sky        = Color(red: 0.78, green: 0.85, blue: 0.92)
    static let sea        = Color(red: 0.16, green: 0.32, blue: 0.45)
    static let brass      = Color(red: 0.78, green: 0.55, blue: 0.20)
    static let brassIncreaseContrast = Color(red: 0.62, green: 0.42, blue: 0.10)
    static let chalk      = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let slate      = Color(red: 0.18, green: 0.20, blue: 0.22)
    static let salt       = Color(red: 0.99, green: 0.99, blue: 0.98)

    // Night palette (auto-switched on appearance)
    static let nightSky   = Color(red: 0.10, green: 0.12, blue: 0.18)
    static let nightSea   = Color(red: 0.78, green: 0.84, blue: 0.92)
    static let nightBrass = Color(red: 0.92, green: 0.74, blue: 0.36)
    static let nightChalk = Color(red: 0.18, green: 0.20, blue: 0.24)
    static let nightSlate = Color(red: 0.88, green: 0.90, blue: 0.92)
}
```

`brassIncreaseContrast` is added per audit A11. When the system reports
`\.accessibilityIncreaseContrast`, the mast and Publish rail swap
`brass → brassIncreaseContrast` and `nightBrass → nightBrassIncreaseContrast`
(see §13.5).

### 6.2 Typography

```swift
// mac-app/Packages/MPUI/Sources/MPUI/DesignSystem/MPType.swift
import SwiftUI

enum MPType {
    static let mastHeadline = Font.system(size: 22, weight: .semibold, design: .serif)
    static let mastSubhead  = Font.system(size: 14, weight: .regular, design: .serif)
    static let sectionTitle = Font.system(size: 13, weight: .semibold, design: .default)
    static let body         = Font.system(size: 13, weight: .regular, design: .default)
    static let callout      = Font.system(size: 12, weight: .medium, design: .default)
    static let caption      = Font.system(size: 11, weight: .regular, design: .default)
    static let mono         = Font.system(size: 13, weight: .regular, design: .monospaced)
}
```

Serif on the mast; sans elsewhere. The serif reads as a quote.

### 6.3 Spacing and shape

```swift
// mac-app/Packages/MPUI/Sources/MPUI/DesignSystem/MPSpacing.swift
import SwiftUI

enum MPSpacing {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 8
    static let s:   CGFloat = 12
    static let m:   CGFloat = 16
    static let l:   CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48

    static let cornerS: CGFloat = 6
    static let cornerM: CGFloat = 10
    static let cornerL: CGFloat = 16
    static let plateCorner: CGFloat = 22
}
```

### 6.4 Motion tokens

No custom motion in 0.1. Use SwiftUI's `withAnimation` and `.animation` for
state transitions. Tokens reserved for 0.2:

```swift
// mac-app/Packages/MPUI/Sources/MPUI/DesignSystem/MPMotion.swift
import SwiftUI

enum MPMotion {
    static let durationFast: Double = 0.18
    static let durationMed:  Double = 0.28
    static let durationSlow: Double = 0.45

    static let plateAppear: Animation = .spring(response: 0.32, dampingFraction: 0.82)
    static let stateSwap:   Animation = .easeInOut(duration: durationMed)
}
```

### 6.5 Day shapes

Three shapes only: cone (meeting), pennant (available), bare mast (generic).
Each is drawn with `Canvas` so it scales with Dynamic Type.

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Mast/MastShape.swift
import SwiftUI

struct MeetingPlateShape: View {
    let tint: Color
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let w = size.width
            let h = size.height
            // Cone: pointed at top, wide at bottom.
            path.move(to: CGPoint(x: w/2, y: 0))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()
            ctx.fill(path, with: .color(tint))
        }
    }
}

struct AvailablePlateShape: View {
    let tint: Color
    var body: some View {
        Canvas { ctx, size in
            // Pennant: triangle on a stick.
            var path = Path()
            let w = size.width
            let h = size.height
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w*0.75, y: h/2))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()
            ctx.fill(path, with: .color(tint))
            // Stick
            var stick = Path()
            stick.addRect(CGRect(x: w*0.78, y: h*0.1, width: 2, height: h*0.8))
            ctx.fill(stick, with: .color(tint))
        }
    }
}

struct GenericPlateShape: View {
    let tint: Color
    var body: some View {
        Canvas { ctx, size in
            // Bare mast: vertical bar with a small sphere on top.
            var bar = Path()
            let w = size.width
            let h = size.height
            bar.addRect(CGRect(x: w/2 - 1.5, y: h*0.2, width: 3, height: h*0.8))
            ctx.fill(bar, with: .color(tint))
            let r: CGFloat = 5
            let dotRect = CGRect(x: w/2 - r, y: 0, width: r*2, height: r*2)
            ctx.fill(Path(ellipseIn: dotRect), with: .color(tint))
        }
    }
}
```

---

## 7. Station window

### 7.1 Scene declaration

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Stations/StationWindow.swift
import SwiftUI

struct StationWindow: Scene {
    @Environment(\.ownerRuntime) private var runtime
    @State private var section: StationSection = .watch

    var body: some Scene {
        Window("Meeting Pulse", id: "station") {
            StationRoot(section: $section)
                .environment(\.pulseStore, runtime?.store ?? PulseStore.preview())
                .environment(\.pulseActions, runtime?.actions ?? PulseActionsImpl.preview())
                .frame(minWidth: 520, minHeight: 580)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 560, height: 640)
        .commandsRemoved()      // No File/Edit/View/Help/Window menus.
    }
}

struct StationRoot: View {
    @Binding var section: StationSection
    @Environment(\.pulseStore) private var store

    var body: some View {
        VStack(spacing: 0) {
            MastView(face: store.mastFace, headline: store.headline, reason: store.reason)
            Divider()
            StationToolbar(selected: $section)
            Divider()
            Group {
                switch section {
                case .watch:    WatchSection()
                case .sharing:  SharingSection()
                case .thisMac:  ThisMacSection()
                case .privacy:  PrivacySection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MPColor.chalk.ignoresSafeArea())
    }
}
```

### 7.2 Station geometry

```
+--------------------------------------------------+
|  MPPlate (mast)                                  |
|  plate | {Name} is in a meeting                  |
|        | Better to wait.                         |
+--------------------------------------------------+
|  [ Watch ] [ Sharing ] [ This Mac ] [ Privacy ]  |   <- StationToolbar
+--------------------------------------------------+
|                                                  |
|   (active section content)                       |
|                                                  |
+--------------------------------------------------+
```

The mast and toolbar are sticky; the section body scrolls inside its own
container.

### 7.3 `StationSection`

Section views accept their data from `EnvironmentValues.pulseStore`. They
never call `PulseActions` directly for I/O — they call it through the
environment value for actions.

### 7.4 Toolbar

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Stations/StationToolbar.swift
import SwiftUI

struct StationToolbar: View {
    @Binding var selected: StationSection

    var body: some View {
        HStack(spacing: MPSpacing.xs) {
            ForEach(StationSection.allCases) { section in
                Button {
                    selected = section
                } label: {
                    Text(MPString.stationSection(section))
                        .font(MPType.sectionTitle)
                        .padding(.horizontal, MPSpacing.s)
                        .padding(.vertical, MPSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: MPSpacing.cornerS)
                                .fill(selected == section
                                      ? MPColor.sky.opacity(0.35)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MPString.stationSection(section))
                .accessibilityAddTraits(selected == section ? .isSelected : [])
            }
        }
        .padding(.horizontal, MPSpacing.m)
        .padding(.vertical, MPSpacing.xs)
    }
}
```


---

## 8. The mast

### 8.1 Mast order

From top to bottom: `MPPlate` (shape only), headline (one short line),
reason line (one short line, never empty). The mast is **not** a button; it
shows state.

### 8.2 `MPPlate`

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Components/MPPlate.swift
import SwiftUI

struct MPPlate: View {
    let face: PlateFace
    let callOkay: Bool?
    let accessibilityIncreaseContrast: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tint = resolvedTint()
        VStack(alignment: .leading, spacing: MPSpacing.xs) {
            ZStack {
                switch face {
                case .meeting:
                    MeetingPlateShape(tint: tint)
                case .available:
                    AvailablePlateShape(tint: tint)
                case .generic:
                    GenericPlateShape(tint: tint)
                }
            }
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
        }
    }

    private func resolvedTint() -> Color {
        // Brass swap for Increase Contrast (audit A11).
        if face == .meeting {
            if scheme == .dark {
                return MPColor.nightBrass
            }
            return accessibilityIncreaseContrast
                ? MPColor.brassIncreaseContrast
                : MPColor.brass
        }
        if scheme == .dark {
            return MPColor.nightSea
        }
        return MPColor.sea
    }
}
```

### 8.3 `ReasonLineBuilder`

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Mast/ReasonLineBuilder.swift
import SwiftUI
import MPCore

enum ReasonLineBuilder {
    static func build(
        effective: EffectiveStatus,
        accessibilityGranted: Bool,
        pairingsCount: Int
    ) -> String {
        if !accessibilityGranted {
            return MPString.reasonAccessibilityMissing
        }
        if pairingsCount == 0 {
            return MPString.reasonNotPaired
        }
        switch effective.reason {
        case .manualOverride(let duration):
            return MPString.reasonManualOverride(duration)
        case .confirmedActiveSource:
            return MPString.reasonConfirmedActive
        case .permissionDenied:
            return MPString.reasonPermissionDenied
        case .untrustedSource:
            return MPString.reasonUntrustedSource
        case .allSourcesInactive:
            return MPString.reasonAllSourcesInactive
        }
    }
}
```

### 8.4 Mode control

`MPModeControl` shows three buttons: `Set busy · {duration}`, `Set available`,
`Back to automatic`. The third appears only while a manual override is active.
Tapping `Set busy` opens a menu with seven durations. Tapping a duration
invokes `actions.setBusy(for: .m15)` etc.

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Components/MPModeControl.swift
import SwiftUI
import MPCore

struct MPModeControl: View {
    @Environment(\.pulseActions) private var actions
    @Environment(\.pulseStore) private var store

    var body: some View {
        HStack(spacing: MPSpacing.xs) {
            busyMenu
            Button(MPString.setAvailable) {
                Task { await actions.setAvailable() }
            }
            .buttonStyle(MPMenuItem.secondary)
            .disabled(store.manualOverride == nil)

            if store.manualOverride != nil {
                Button(MPString.backToAutomatic) {
                    Task { await actions.clearOverride() }
                }
                .buttonStyle(MPMenuItem.secondary)
            }
        }
    }

    private var busyMenu: some View {
        Menu {
            ForEach(ManualOverride.Duration.allCases) { d in
                Button(MPString.durationLabel(d)) {
                    Task { await actions.setBusy(for: d) }
                }
            }
        } label: {
            Text(MPString.setBusy)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
```

### 8.5 Calls-are-okay toggle

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Components/MPCallsAreOkayToggle.swift
import SwiftUI

struct MPCallsAreOkayToggle: View {
    @Environment(\.pulseStore) private var store
    @Environment(\.pulseActions) private var actions
    @Binding var value: Bool

    var body: some View {
        Toggle(MPString.callsAreOkay, isOn: $value)
            .toggleStyle(MPPublishRail.toggleStyle)
            .onChange(of: value) { _, newValue in
                Task { await actions.setCallsOkay(newValue) }
            }
    }
}
```

### 8.6 `MPPublishRail`

The publish rail is the bottom band of the mast: a thin horizontal bar that
shows whether the latest published status is fresh or stale. It is not a
progress bar; it is a **signal**. When fresh: `MPColor.brass`. When stale:
`MPColor.slate`. When no reader: half-tone.

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Components/MPPublishRail.swift
import SwiftUI

struct MPPublishRail: View {
    let freshness: Freshness
    let pairingsCount: Int

    var body: some View {
        GeometryReader { geo in
            let fill = width(for: geo.size.width)
            RoundedRectangle(cornerRadius: 2)
                .fill(MPColor.brass)
                .frame(width: fill, height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(MPString.publishRailLabel(freshness, pairingsCount))
        }
        .frame(height: 3)
    }

    private func width(for total: CGFloat) -> CGFloat {
        guard pairingsCount > 0 else { return total * 0.5 }
        switch freshness {
        case .fresh: return total
        case .stale: return total * 0.15
        }
    }
}
```

---

## 9. Station sections

### 9.1 Watch

The Watch section answers: "Is this Mac currently detecting meeting activity?"

```swift
// mac-app/Packages/MPUI/Sources/MPUI/WatchSection/WatchSection.swift
import SwiftUI

struct WatchSection: View {
    @Environment(\.pulseStore) private var store
    @Environment(\.pulseActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: MPSpacing.m) {
            Text(MPString.watchHeadline)
                .font(MPType.sectionTitle)
            Text(MPString.watchBody)
                .font(MPType.body)
                .foregroundStyle(MPColor.slate)
            WatchStatusCard(reading: store.lastSchedulerReading,
                            lastSync: store.lastSync)
            if !store.accessibilityGranted {
                Button(MPString.openAccessibilitySettings) {
                    actions.openAccessibilitySettings()
                }
                .buttonStyle(MPMenuItem.primary)
            }
        }
        .padding(MPSpacing.m)
    }
}
```

The `SchedulerReading` is exposed via `store.lastSchedulerReading` (a new
field added in `OwnerRuntime.start()`'s observation loop). The card uses the
Day-shape vocabulary: each row has a small filled or hollow shape, no traffic
lights.

### 9.2 Sharing

Three sub-areas: empty state (no link yet), viewer link card, paired viewers.

#### 9.2.1 Empty state

If `pairings.isEmpty`, render:

```
{Send this to whoever needs it.}
{They open the link and see one word. They do not need an account,
 and they cannot see anything else.}
[ Create the link ]   [ Do this later ]
```

The primary button shows a brief spinner (`linkCreatingState == .loading`),
then transitions to the viewer link card.

#### 9.2.2 Viewer link card

```swift
// mac-app/Packages/MPUI/Sources/MPUI/SharingSection/ViewerLinkCard.swift
import SwiftUI

struct ViewerLinkCard: View {
    let code: PairingCode
    @Environment(\.pulseActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: MPSpacing.xs) {
            HStack {
                Text(code.displayName.isEmpty
                     ? MPString.unnamedOwner
                     : code.displayName)
                    .font(MPType.sectionTitle)
                Spacer()
                Text(code.code, monospaced: true)
                    .font(MPType.mono)
                    .accessibilityLabel(MPString.pairingCodeLabel(code.code))
            }
            HStack(spacing: MPSpacing.xs) {
                Button(MPString.copy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.url, forType: .string)
                }
                .buttonStyle(MPMenuItem.secondary)
                Button(MPString.rotateLink) {
                    Task { await actions.rotateViewerLink() }
                }
                .buttonStyle(MPMenuItem.secondary)
                Button(MPString.revokeAccess) {
                    Task { await actions.revokeViewerAccess() }
                }
                .buttonStyle(MPMenuItem.destructive)
            }
        }
        .padding(MPSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: MPSpacing.cornerM)
                .fill(MPColor.salt)
        )
    }
}
```

The audit A7 fix: `code.displayName.isEmpty` (not `== nil`).

#### 9.2.3 Paired viewers

```swift
// mac-app/Packages/MPUI/Sources/MPUI/SharingSection/PairedViewersList.swift
import SwiftUI

struct PairedViewersList: View {
    @Environment(\.pulseStore) private var store
    @Environment(\.pulseActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: MPSpacing.xs) {
            HStack {
                Text(MPString.viewersHeadline).font(MPType.sectionTitle)
                Spacer()
                Button(MPString.refresh) {
                    Task { await actions.refreshViewers() }
                }
                .buttonStyle(.plain)
                .disabled(store.viewersLoadingState == .loading)
            }
            MPRefreshable(isRefreshing: store.viewersLoadingState == .loading) {
                Task { await actions.refreshViewers() }
            } content: {
                switch store.viewersLoadingState {
                case .idle, .loading:
                    ProgressView().controlSize(.small)
                case .loaded:
                    ForEach(store.viewers) { v in ViewerRow(viewer: v) }
                case .failed:
                    Text(MPString.viewersLoadFailed)
                        .font(MPType.caption)
                        .foregroundStyle(MPColor.slate)
                }
            }
        }
    }
}
```

`MPRefreshable` is the pull-to-refresh modifier (audit A8). It uses SwiftUI
macOS 14 `refreshable` and a `RefreshableKey` for testing. The mechanics:

1. User pulls down on the list. SwiftUI calls the closure.
2. The closure invokes `actions.refreshViewers()`.
3. `PulseActionsImpl` sets `store.viewersLoadingState = .loading`,
   calls `StatusTransport.listViewers()`, on success replaces
   `store.viewers` and sets `.loaded(at: now)`, on failure sets
   `.failed(.unreachable(...))`.
4. The list re-renders.

### 9.3 This Mac

#### 9.3.1 Install location

A read-only row showing the app's bundle path. If `AppLaunchCoordinator.state`
becomes `.wrongInstallLocation`, the row turns into a blocking view.

#### 9.3.2 Display name

A `TextField` bound to `store.displayName` with a debounce of 600ms before
`actions.setDisplayName(_:)` fires. The field trims whitespace on commit.

#### 9.3.3 Startup

A `Toggle` for "Open at login". Implementation uses
`SMAppService.mainApp.register()` and `.unregister()` (macOS 13+).

#### 9.3.4 Recovery

A single row: "Show recovery phrase". Tapping opens the `RecoveryWindow`.
The phrase itself is **never** stored in `PulseStore`; it is fetched on
demand via `actions.revealRecoveryPhrase()` and held only in the recovery
window's local `@State`.

#### 9.3.5 Danger zone

A single button: "Delete everything". Tapping opens a confirmation sheet
(`MPDestructiveConfirm`). The sheet has the delete copy from the deck and a
destructive `Delete` button. On confirm, `actions.deleteEverything()` runs,
which calls `deleteEverything()` from the existing code path and then sets
`store.launchState = .setupRequired` so the Station shows onboarding.

### 9.4 Privacy

A read-only section listing:

- **What Meeting Pulse reads.** Window titles of foreground apps
  (Accessibility API), nothing else.
- **What Meeting Pulse sends.** The current state (`available` / `busy` /
  `unavailable`) and the optional `callOkay` flag, signed with an
  anon-key, over HTTPS, to the publish endpoint.
- **What Meeting Pulse does not send.** Window content, screenshots,
  keystrokes, audio, screen-share state.
- **What the viewer sees.** Exactly one of: `In a meeting`, `In meeting,
  fine to interrupt`, `Meeting status unavailable`, `Not connected`.

Each row is a sentence from the copy deck, with no bullet markers.


---

## 10. Onboarding and setup

### 10.1 Persistence

The onboarding completion flag is a single bit in `MPSupport` (e.g. a
`UserDefaults` key `setup.completed`). `OwnerRuntime` reads it on `start()`
and sets `store.launchState = .setupRequired` if false.

### 10.2 Step 1

`OnboardingStep1` shows the headline `Meeting Pulse tells one person when to
call you.` and the supporting line from `docs/copy/deck.md §Setup`. One
primary button: `Get started`. Tapping advances to step 2.

### 10.3 Step 2

`OnboardingStep2` shows the headline `Let the Mac see your window titles.`
and the supporting line. One primary button: `Open Accessibility settings`.
A secondary button: `Skip for now`.

The auto-advance (audit A5) is implemented as a `withObservationTracking`
loop watching `store.accessibilityGranted`. When it flips to `true`:

1. Show `Waiting...` (existing deck line) for 400ms (so the user perceives
   the transition).
2. Switch to `Accessibility is on.` for 800ms.
3. Advance to step 3.

The advance fires **only once** per onboarding session. A flag
`store.didAutoAdvance` prevents re-firing if the user toggles Accessibility
off and on again.

### 10.4 Step 3

`OnboardingStep3` shows the headline `Send this to whoever needs it.`. The
primary button is `Create the link`. The secondary is `Do this later`. A
tertiary text link `Open Meeting Pulse` is the escape hatch.

### 10.5 Setup failure view

If the user reaches the Station and `store.launchState` is `.wrongInstallLocation`,
the Station renders a blocking view with a single action: `Move to
Applications`. The recovery URL is read from `MPSupport`.

---

## 11. Reduced menu bar

### 11.1 `ReducedMenuBarView`

Six top-level items, in order:

1. `Set busy` (submenu with seven durations)
2. `Set available`
3. `Back to automatic` (only when override is active)
4. `Calls are okay` (toggle)
5. `Open Meeting Pulse` (opens Station)
6. `Quit Meeting Pulse`

```swift
// mac-app/Packages/MPUI/Sources/MPUI/MenuBar/ReducedMenuBarView.swift
import SwiftUI
import MPCore

struct ReducedMenuBarView: View {
    @Environment(\.pulseStore) private var store
    @Environment(\.pulseActions) private var actions
    @Environment(\.appEnvironment) private var env

    var body: some View {
        // Two lines of text: plate headline, reason.
        Text(store.headline)
            .font(MPType.body)
        Text(store.reason)
            .font(MPType.caption)
            .foregroundStyle(.secondary)
        Divider()
        Menu(MPString.setBusy) {
            ForEach(ManualOverride.Duration.allCases) { d in
                Button(MPString.durationLabel(d)) {
                    Task { await actions.setBusy(for: d) }
                }
            }
        }
        Button(MPString.setAvailable) {
            Task { await actions.setAvailable() }
        }
        if store.manualOverride != nil {
            Button(MPString.backToAutomatic) {
                Task { await actions.clearOverride() }
            }
        }
        Toggle(MPString.callsAreOkay, isOn: callsOkayBinding)
        Divider()
        Button(MPString.openStation) { env.openStation() }
        Button(MPString.quit) { NSApp.terminate(nil) }
    }

    private var callsOkayBinding: Binding<Bool> {
        Binding(
            get: { store.lastSync.callOkay ?? false },
            set: { newValue in
                Task { await actions.setCallsOkay(newValue) }
            }
        )
    }
}
```

`ManualOverride.Duration` must conform to `Identifiable` and `Hashable` for
`ForEach` to iterate. The original `MPCore/ManualOverride.swift` lacks both
conformances. Fix: add `extension ManualOverride.Duration: Identifiable,
Hashable {}` **in `MPCore`** (not in `MPUI`), so any consumer benefits.

### 11.2 `MenuBarIcon`

```swift
// mac-app/Packages/MPUI/Sources/MPUI/MenuBar/MenuBarIcon.swift
import SwiftUI

struct MenuBarIcon: View {
    let face: PlateFace

    var body: some View {
        Image(systemName: "circle.fill")
            .symbolRenderingMode(.template)
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch face {
        case .meeting:   return MPColor.brass
        case .available: return MPColor.sea
        case .generic:   return MPColor.slate
        }
    }
}
```

The icon uses **template** rendering (defect D8 fix). It tints correctly in
both menu-bar appearances (Dark Menu Bar and Light Menu Bar).

---

## 12. Copy contract

Every visible string is sourced from `MPString`. Every key in `MPString` is
backed by `docs/copy/deck.md`. This chapter enumerates every key.

### 12.1 Board and mast

| Key | Source line in `docs/copy/deck.md` |
|---|---|
| `MPString.mast.busyHeadline` | `## The board` row 1 headline |
| `MPString.mast.busySubhead` | `## The board` row 1 supporting |
| `MPString.mast.callOkayHeadline` | `## The board` row 2 headline |
| `MPString.mast.callOkaySubhead` | `## The board` row 2 supporting |
| `MPString.mast.genericHeadline` | `## The board` row 3 headline |
| `MPString.mast.genericSubhead` | `## The board` row 3 supporting |
| `MPString.mast.offlineHeadline` | `## The board` row 4 headline |
| `MPString.mast.offlineSubhead` | `## The board` row 4 supporting |
| `MPString.mast.unpairedHeadline` | `## The board` row 5 headline |
| `MPString.mast.unpairedSubhead` | `## The board` row 5 supporting |

### 12.2 Station and Watch

| Key | Source line in `docs/copy/deck.md` |
|---|---|
| `MPString.stationSection.watch` | `### The station window` heading context |
| `MPString.stationSection.sharing` | same |
| `MPString.stationSection.thisMac` | same |
| `MPString.stationSection.privacy` | same |
| `MPString.watchHeadline` | `#### Watch` |
| `MPString.watchBody` | `#### Watch` body |
| `MPString.openAccessibilitySettings` | `### Accessibility permission` |
| `MPString.reasonAccessibilityMissing` | `### Accessibility permission` |

### 12.3 Sharing and durations

| Key | Source line in `docs/copy/deck.md` |
|---|---|
| `MPString.sharingHeadline` | `#### Sharing` |
| `MPString.sharingBody` | `#### Sharing` |
| `MPString.createLink` | `### Setup` step 3 |
| `MPString.doThisLater` | `### Setup` step 3 |
| `MPString.copy` | `#### Sharing` (Viewer link card) |
| `MPString.rotateLink` | `#### Sharing` |
| `MPString.revokeAccess` | `#### Sharing` |
| `MPString.durationLabel(.m15)` | `### The reduced menu bar` |
| `MPString.durationLabel(.m30)` | same |
| `MPString.durationLabel(.m45)` | same |
| `MPString.durationLabel(.h1)` | same |
| `MPString.durationLabel(.h2)` | same |
| `MPString.durationLabel(.h4)` | same |
| `MPString.durationLabel(.untilCleared)` | same |

### 12.4 This Mac, privacy, and onboarding

| Key | Source line in `docs/copy/deck.md` |
|---|---|
| `MPString.thisMacHeadline` | `#### This Mac` |
| `MPString.installLocation` | `#### This Mac` body |
| `MPString.displayName` | `#### This Mac` |
| `MPString.startupLaunch` | `#### This Mac` |
| `MPString.recovery` | `#### This Mac` |
| `MPString.showRecoveryPhrase` | `#### This Mac` |
| `MPString.recoveryPhraseRevealed` | `### Recovery phrase` |
| `MPString.recoveryPhraseHidden` | `### Recovery phrase` |
| `MPString.recoveryPhraseCopy` | `### Recovery phrase` |
| `MPString.dangerZone` | `#### Danger zone` |
| `MPString.deleteEverything` | `### Delete everything` |
| `MPString.deleteConfirmTitle` | `### Delete everything` |
| `MPString.deleteConfirmBody` | `### Delete everything` |
| `MPString.privacyHeadline` | `#### Privacy` |
| `MPString.privacyReads` | `#### Privacy` |
| `MPString.privacySends` | `#### Privacy` |
| `MPString.privacyNotSends` | `#### Privacy` |
| `MPString.privacyViewerSees` | `#### Privacy` |
| `MPString.onboardingStep1.headline` | `### Setup` step 1 |
| `MPString.onboardingStep1.body` | step 1 |
| `MPString.onboardingStep1.cta` | step 1 |
| `MPString.onboardingStep2.headline` | step 2 |
| `MPString.onboardingStep2.body` | step 2 |
| `MPString.onboardingStep2.cta` | step 2 |
| `MPString.onboardingStep2.skip` | step 2 |
| `MPString.onboardingStep2.waiting` | step 2 `Waiting...` |
| `MPString.onboardingStep2.granted` | step 2 `Accessibility is on.` |
| `MPString.onboardingStep3.headline` | step 3 |
| `MPString.onboardingStep3.body` | step 3 |
| `MPString.onboardingStep3.cta` | step 3 |
| `MPString.onboardingStep3.later` | step 3 |
| `MPString.onboardingStep3.openApp` | step 3 |
| `MPString.menuBar.setBusy` | `### The reduced menu bar` |
| `MPString.menuBar.setAvailable` | same |
| `MPString.menuBar.backToAutomatic` | same |
| `MPString.menuBar.callsAreOkay` | same |
| `MPString.menuBar.openStation` | same |
| `MPString.menuBar.quit` | same |
| `MPString.setupError.installLocation.headline` | `### Setup errors` |
| `MPString.setupError.installLocation.body` | `### Setup errors` |
| `MPString.setupError.installLocation.cta` | `### Setup errors` |
| `MPString.setupError.generic.headline` | `### Setup errors` |
| `MPString.setupError.generic.body` | `### Setup errors` |

#### 12.4.1 Recovery phrase auto-hide (audit A6)

The recovery window shows the 12 words on `WindowKey.onAppear`. A timer
starts immediately. The implementation:

- Timer length: 60 seconds.
- Reset on interaction: any key press, any click inside the window, any
  voice-over focus event resets the timer to 60s. The reset is silent (no
  "still there?" warning); the user pressing keys means they are engaged.
- On expiry: `WindowKey.onDisappear` is **not** triggered; instead, the
  recovery view swaps to a `recoveryPhraseHidden` panel with a `Reveal
  again` button. Tapping re-shows the phrase and resets the timer.
- VoiceOver focus reset uses the `.accessibilityFocused` property changes.

```swift
struct RecoveryWindow: View {
    @State private var isHidden = false
    @State private var resetTask: Task<Void, Never>?
    @Environment(\.pulseActions) private var actions
    @State private var phrase: String = ""

    var body: some View {
        VStack {
            if isHidden {
                Text(MPString.recoveryPhraseHidden)
                Button(MPString.recoveryPhraseRevealed) {
                    phrase = (try? await actions.revealRecoveryPhrase()) ?? ""
                    isHidden = false
                    restartTimer()
                }
            } else {
                Text(phrase).font(MPType.mono)
                Button(MPString.recoveryPhraseCopy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(phrase, forType: .string)
                    isHidden = true
                    resetTask?.cancel()
                }
            }
        }
        .focusable()
        .onKeyPress { _ in restartTimer(); return .handled }
        .onTapGesture { restartTimer() }
        .task {
            phrase = (try? await actions.revealRecoveryPhrase()) ?? ""
            restartTimer()
        }
    }

    private func restartTimer() {
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled {
                isHidden = true
            }
        }
    }
}
```

---

## 13. Accessibility and interaction quality

### 13.1 Colour and shape

- Shape encodes state (cone / pennant / bare mast). Colour reinforces.
  A user with red-green colour blindness still gets the right state from
  the shape.
- Increase Contrast swaps `brass → brassIncreaseContrast` (audit A11).
- Dark Mode swaps day palette to night palette.
- Reduce Transparency is honoured automatically by `Color` and `Canvas`.

### 13.2 VoiceOver

Every interactive element has an `accessibilityLabel`. Decorative shapes
use `.accessibilityHidden(true)`. The mast composite is a single element
with a label built from headline + reason + shape name.

### 13.3 Keyboard

- The Station window responds to `⌘1` through `⌘4` to switch sections.
- The recovery window's `Reveal again` button is reachable by `Tab`.
- The menu bar extras have keyboard shortcuts defined by the system; no
  custom shortcuts in 0.1.

### 13.4 Larger text and reduced settings

- All text uses dynamic `Font` styles where possible. Fixed-size text is
  in the mast (the headline is 22pt serif).
- Reduce Motion: `withAnimation` calls check `\.accessibilityReduceMotion`
  and skip the animation when set.
- Increase Contrast: see §6.1 and audit A11.
- Smart Invert: tested manually; the mast uses semantic colours so the
  inversion does not destroy the state shape.

### 13.5 Increase Contrast handling (audit A11)

`MPColor.brass` and `MPColor.nightBrass` get `IncreaseContrast` variants:

```swift
extension MPColor {
    static let nightBrass = Color(red: 0.92, green: 0.74, blue: 0.36)
    static let nightBrassIncreaseContrast = Color(red: 0.96, green: 0.82, blue: 0.48)
}
```

`MPPlate.resolvedTint()` checks `\.accessibilityIncreaseContrast` and the
colour scheme and picks the right brass.

---

## 14. Previews and fixtures

### 14.1 `PreviewStores`

```swift
// mac-app/Packages/MPUI/Sources/MPUI/Previews/PreviewStores.swift
import SwiftUI
import MPCore

extension PulseStore {
    static func preview() -> PulseStore {
        PulseStore().tap(.available, callOkay: nil, override: nil, accessibilityGranted: true)
    }
    static func previewBusy() -> PulseStore {
        PulseStore().tap(.busy, callOkay: nil, override: nil, accessibilityGranted: true)
    }
    static func previewCallOkay() -> PulseStore {
        PulseStore().tap(.busy, callOkay: true, override: nil, accessibilityGranted: true)
    }
    static func previewStale() -> PulseStore {
        PulseStore().tap(.busy, callOkay: nil, override: nil, accessibilityGranted: true)
            .mark(.stale(.now.addingTimeInterval(-300)))
    }
    static func previewGeneric() -> PulseStore {
        PulseStore().tap(.unavailable, callOkay: nil, override: nil, accessibilityGranted: false)
    }

    private func tap(_ s: MPCore.State,
                     callOkay: Bool?,
                     override: ManualOverride?,
                     accessibilityGranted: Bool) -> PulseStore {
        var copy = self
        copy.lastSync = .init(state: s, callOkay: callOkay, freshness: .fresh(secondsAgo: 12), capturedAt: .now)
        copy.manualOverride = override
        copy.accessibilityGranted = accessibilityGranted
        copy.pairings = [PairingCode(code: "ABCD-1234", displayName: "Studio")]
        copy.viewers = [ViewerRecord(id: "v1", name: "Studio", lastSeen: .now, paired: true)]
        return copy
    }
    private func mark(_ freshness: Freshness) -> PulseStore {
        var copy = self
        copy.lastSync = .init(state: copy.lastSync.state,
                              callOkay: copy.lastSync.callOkay,
                              freshness: freshness,
                              capturedAt: copy.lastSync.capturedAt)
        return copy
    }
}
```

Each `preview*` is the deterministic seed for one `#Preview` block (audit A9).
A test in `PreviewFixtureTests` enumerates every `MPUI` view's `#Preview`
and asserts the referenced store exists.


---

## 15. Implementation phases and task checklist

Each task has an explicit acceptance criterion. Tasks are listed in dependency
order; an LLM implementing this plan should never start task N+1 before task
N's acceptance is met.

### Phase 1: package and copy foundation

**T1.1 — Make the app a menu-bar-only app.**
- Edit `mac-app/MeetingPulse/Info.plist`. Set `LSUIElement = true`.
- **Verify**: `defaults read mac-app/MeetingPulse/Info.plist LSUIElement` prints `1`.
- Acceptance: building and launching the app shows no Dock icon until a window opens.

**T1.2 — Create `MPUI` package and register it in Xcode.**
- Create `mac-app/Packages/MPUI/Package.swift` (template in §3.6).
- Add `MPUI` to `mac-app/MeetingPulse.xcodeproj/project.pbxproj` (template in
  §3.7). Use `grep -n` to find insertion points.
- **Verify**: `xcodebuild -list -project mac-app/MeetingPulse.xcodeproj`
  lists `MPUI` under the `MeetingPulse` target. `xcodebuild -resolvePackageDependencies`
  succeeds.
- Acceptance: `import MPUI` works in a test file under
  `mac-app/MeetingPulse/Tests/`.

**T1.3 — Copy bindings: `MPString` catalogue.**
- Add `mac-app/Packages/MPSupport/Sources/MPSupport/Strings.swift` with the
  catalogue from §12.
- Add `mac-app/Packages/MPUI/Sources/MPUI/CopyBindings/MPStrings+Bindings.swift`
  with view-layer helpers like `MPString.stationSection(.watch)`.
- Add `mac-app/Packages/MPUI/Resources/Localizable.xcstrings` (en only).
- **Verify**: every key in §12 exists in `Strings.swift`. CI grep gate.
- Acceptance: `MPString.mast.busyHeadline` compiles and returns the deck text.

**T1.4 — Replace literal "Available override" with deck copy (defect D5).**
- Two sites: `MeetingPulseApp.swift:372` and `:379`.
- Replace with `MPString.menuBar.availableOverride` (new key, add to catalogue:
  text `Currently available. Set busy to override.`).
- Acceptance: a string-literal grep in `MeetingPulseApp.swift` no longer
  matches "Available override".

**T1.5 — Design tokens: `MPColor`, `MPType`, `MPSpacing`, `MPMotion`,
`MPShape`.**
- Files per §3.5. Code per §6.
- Acceptance: every `Color` reference in `MPUI` resolves to `MPColor.*`.

**T1.6 — `ManualOverride.Duration: Identifiable, Hashable` in `MPCore`.**
- Add `extension ManualOverride.Duration: Identifiable, Hashable {}`.
- Acceptance: `ForEach(ManualOverride.Duration.allCases) { d in ... }`
  compiles in `ReducedMenuBarView`.

### Phase 2: controller and state

**T2.1 — `PulseStore` skeleton (audit A9 fixtures inline).**
- File per §4.2.
- Acceptance: `PulseStore.preview()` returns a store with
  `effective.state == .available`.

**T2.2 — Wire `SyncCoordinator.startHeartbeat` (defect D1).**
- `OwnerRuntime.start()` calls
  `coordinator.startHeartbeat(interval: .seconds(60)) { await currentPayload() }`.
- Acceptance: a logging hook prints the heartbeat timestamp every 60s during
  a manual run.

**T2.3 — `PulseActions` protocol + `PulseActionsImpl`.**
- File per §4.4.
- `PulseActionsImpl` is constructed by `OwnerRuntime` and stores a weak ref
  to `store` plus strong refs to `coordinator`, `transport`, `permission`,
  `launch`, `appEnvironment`.
- Acceptance: `actions.setBusy(for: .m30)` mutates `store.manualOverride`
  synchronously and publishes asynchronously.

**T2.4 — Replace duplicate pairing presentation (defect D4).**
- Remove `showPairingWindow()` from `MeetingPulseApp.swift`.
- `Window(id: "pairing")` scene remains; the menu invokes
  `actions.openPairing()` which calls `openWindow(id: "pairing")`.
- Acceptance: opening pairing from menu and from Station share the same
  scene instance.

**T2.5 — Delete-everything terminal state (defect D6).**
- `actions.deleteEverything()` calls the existing `deleteEverything()` then
  sets `store.launchState = .setupRequired` and tears down windows.
- Acceptance: after delete, the Station shows onboarding on next launch.

**T2.6 — Make `AppLaunchCoordinator` observable.**
- Add `@Observable` to `AppLaunchCoordinator`. Re-publish `state` to
  `PulseStore.launchState`.
- Acceptance: changing `AppLaunchCoordinator.state` updates the Station
  mast within one runloop.

**T2.7 — DetectionTuning visibility.**
- `OwnerRuntime` constructs `DetectionTuning` and holds the reference.
  `PulseStore.detectionTuning: DetectionTuning` is set once at construction.
- Acceptance: a test can read `store.detectionTuning.idleSampleInterval`.

### Phase 3: live wiring

**T3.1 — Sync snapshot mapping.**
- `OwnerRuntime.start()` reads `StatusTransport` and pushes `SyncSnapshot`
  into `store.lastSync`.
- Acceptance: the mast updates within 1s of a state change in the publish
  backend.

**T3.2 — Parity test (audit A2 from source spec, mirror in this plan).**
- File `mac-app/Packages/MPUITests/MastParityTests.swift`.
- Reads `viewer/src/lib/freshness.ts` and `mac-app/Packages/MPCore/Sources/MPCore/Staleness.swift`.
- Asserts `STALE_AFTER_SECONDS` constant is identical (180) in both.
- Asserts the mast face mapping matches `effectiveDisplayState`.
- Acceptance: test passes; CI runs it on every PR.

**T3.3 — Replace pessimistic `catch` defaults (defects D2, D3).**
- Seven sites at lines 354, 398, 414, 442, 457, 481, 525 of
  `MeetingPulseApp.swift`.
- Replace `"Can't reach the server. Retrying."` with the deck copy
  `MPString.error.unreachable` (new key, text `Can't reach the server.
  Try again in a moment.`).
- Default at line 325 becomes `MPString.error.starting` (text `Starting up.`).
- Acceptance: every catch site reads from `MPString`.

**T3.4 — Permission polling intervals.**
- `OwnerRuntime` sets `permissionPollInterval = .seconds(1)` when
  `store.launchState == .setupRequired` OR `store.menuBarWindowVisible`.
- Default `.seconds(5)` otherwise.
- Acceptance: a debug log shows the interval change at the right moments.

**T3.5 — Heartbeat cadence adjustment on override.**
- Override active → `.seconds(30)`. No override, station closed →
  `.seconds(300)`. Otherwise `.seconds(60)`.
- Acceptance: `withObservationTracking` loop in `OwnerRuntime` updates
  interval within one runloop of a state change.

**T3.6 — Source row mapping.**
- `WatchStatusCard` reads `store.lastSchedulerReading` (new field).
- Acceptance: opening the Watch section with no scheduled reading shows
  three empty rows.

### Phase 4: mast and shared components

**T4.1 — `MPPlate` (audit A11).**
- File per §8.2. Uses `MPColor.brassIncreaseContrast` when
  `\.accessibilityIncreaseContrast` is true.
- Acceptance: toggling Increase Contrast in System Settings changes the
  mast tint.

**T4.2 — `ReasonLineBuilder`.**
- File per §8.3. Maps `EffectiveStatus.reason` to a deck key.
- Acceptance: every `StatusReason` case has a deck string.

**T4.3 — `MPModeControl`.**
- File per §8.4. Uses `MPMenuItem` button styles.
- Acceptance: tapping `Set busy · 30 minutes` from the Station calls
  `actions.setBusy(for: .m30)` and updates the mast.

**T4.4 — `MPCallsAreOkayToggle`.**
- File per §8.5.
- Acceptance: toggle updates `store.lastSync.callOkay` and the mast
  face (only when state == .busy).

**T4.5 — `MPPublishRail`.**
- File per §8.6.
- Acceptance: rail width is full when fresh, narrow when stale, half
  when no pairings.

**T4.6 — `MPRefreshable` (audit A8).**
- File in `Components/MPRefreshable.swift`.
- Acceptance: pull-to-refresh on the viewers list calls
  `actions.refreshViewers()` and shows a `ProgressView` while loading.

**T4.7 — `MPDestructiveConfirm`.**
- A sheet with the deck copy and a single destructive button.
- Acceptance: tapping Delete runs the action; tapping Cancel dismisses.

**T4.8 — `MPMenuItem` button styles.**
- Three styles: `primary`, `secondary`, `destructive`. None use emoji.
- Acceptance: a storyboard-like screenshot test confirms no system
  traffic-light language appears.

### Phase 5: Station sections

**T5.1 — Watch section.**
- File per §9.1.
- Acceptance: when Accessibility is off, an `Open Accessibility settings`
  button appears.

**T5.2 — Sharing section (audit A7).**
- File per §9.2.
- `code.displayName.isEmpty` everywhere (never `== nil`).
- Acceptance: `grep -n "displayName == nil" mac-app/Packages/MPUI/` returns
  nothing.

**T5.3 — This Mac section.**
- Files per §9.3.
- Display name debounce 600ms.
- Acceptance: typing in the field commits to `store.displayName` after
  600ms idle.

**T5.4 — Privacy section.**
- File per §9.4. Read-only. Each row is a sentence.
- Acceptance: every key in `MPString.privacy*` is rendered exactly once.

### Phase 6: menu and onboarding

**T6.1 — Reduced menu bar (defect D7).**
- File per §11.1. Six top-level items only.
- Acceptance: the menu bar has exactly six items; the duration submenu has
  seven durations.

**T6.2 — `MenuBarIcon` (defect D8).**
- File per §11.2. Uses `.symbolRenderingMode(.template)`.
- Acceptance: the icon tints correctly in both Dark and Light Menu Bar.

**T6.3 — Onboarding wizard (audit A5 auto-advance).**
- Files per §10.
- Auto-advance on Accessibility grant: 400ms `Waiting...`, 800ms
  `Accessibility is on.`, then step 3. `store.didAutoAdvance` flag
  prevents re-firing.
- Acceptance: granting Accessibility from System Settings while Step 2 is
  visible advances to Step 3 within ~1.2s.

**T6.4 — Recovery window (audit A6).**
- File per §12.4.1. 60s auto-hide with reset on interaction.
- Acceptance: leaving the window idle for 60s hides the phrase. Pressing
  any key resets the timer.

**T6.5 — Diagnostics window.**
- Read-only. Same surface as the current Diagnostics, copy-cleaned.
- Acceptance: no banned words appear in diagnostics strings.

**T6.6 — Pairing window.**
- Single scene, opens via `actions.openPairing()`.
- Acceptance: only one pairing scene is reachable from the menu.

**T6.7 — Settings window.**
- `This Mac` and `Privacy` sections live in the Station, not in Settings.
  Settings opens to a single screen with `Display name`, `Startup`,
  `Recovery`, `Danger zone`.
- Acceptance: Settings window has four rows.

### Phase 7: proof and handoff (NEW — audit A2)

**T7.1 — Rollback path.**
- The new `MPUI` package is feature-flagged at runtime via
  `MPSupport/FeatureFlag.swift` with key `ui.macNative` (default `true`
  for 0.1).
- Setting the key to `false` reverts to the legacy monolith path
  (the old `MeetingPulseApp.swift` body is preserved in a `LegacyAppShell`
  branch for one release).
- Acceptance: `defaults write com.example.meetingpulse ui.macNative -bool false`
  launches the legacy shell.

**T7.2 — Reset of owner secret storage.**
- `AppLaunchCoordinator.start()` runs the one-time legacy storage reset before creating
  the local secret store.
- The reset deletes the old Meeting Pulse Keychain items without reading or
  migrating them, clears `setup.completed`, and records a UserDefaults
  sentinel.
- The new local store starts empty, so the owner completes setup and registers
  a fresh device identity. Non-secret preferences remain available.
- Acceptance: a clean install and a reset install both show setup and create a
  fresh local identity.

**T7.3 — Existing non-secret preferences.**
- Display name and login-item preferences remain in their existing local
  stores; no secret or telemetry identity is copied into the new secret file.
- Acceptance: after reset, non-secret preferences remain available while the
  new device identity is registered.

**T7.4 — Definition of done re-check.**
- §17 below.

**T7.5 — Decision records (audit A3).**
- Each open decision in §17 has a concrete file in `docs/decisions/`.
- Acceptance: every decision has a path.

---

## 16. Test plan

### 16.1 Unit tests

| Test | Asserts |
|---|---|
| `PulseStoreTests.test_effectiveFromBusyNoOverride` | `effective.state == .busy` when `lastSync.state == .busy` and `override == nil` |
| `PulseStoreTests.test_effectiveFromBusyWithOverride` | `effective.state == .available` when override is `.available` |
| `PulseStoreTests.test_optimisticRollbackOnFailure` | failed `setBusy` rolls `manualOverride` back |
| `MastParityTests.test_staleConstantMatchesViewer` | `STALE_AFTER_SECONDS == 180` on both sides |
| `MastParityTests.test_faceMatrix` | eight input combinations produce the expected `PlateFace` |
| `PreviewFixtureTests.test_allPreviewsHaveFixture` | every `#Preview` block's referenced `PulseStore.preview*` exists |
| `CopyGrepTests.test_noLiteralsInRenderCode` | a regex sweep over `MPUI/Sources` finds no quoted strings outside `MPStrings+Bindings.swift` |
| `CopyGrepTests.test_bannedWordsAbsent` | the banned-word list returns zero matches in `MPUI/Sources` |
| `RecoveryTimerTests.test_hidesAfter60s` | `isHidden == true` after 60s without interaction |
| `RecoveryTimerTests.test_resetsOnInteraction` | key press resets timer to 60s |
| `OnboardingTests.test_autoAdvancesOnGrant` | granting Accessibility advances to step 3 |
| `OnboardingTests.test_autoAdvancesOnce` | toggling Accessibility off/on does not re-fire |
| `DisplayNameTests.test_emptyPredicate` | `PairingCode(displayName: "").displayName.isEmpty == true` |
| `MenuTests.test_sixTopLevelItems` | `ReducedMenuBarView` renders six items |
| `MenuTests.test_durationIsHashable` | `ManualOverride.Duration.allCases` compiles in `ForEach` |
| `IncreaseContrastTests.test_brassSwap` | `MPPlate.resolvedTint()` returns `brassIncreaseContrast` when trait is set |
| `MigrationTests.test_idempotent` | running `migrateIfNeeded()` twice produces the same state |

### 16.2 Static checks

A `Makefile` target `lint` runs:

```bash
# Banned words in render code
! grep -REn "seamless|effortless|powerful|robust|leverage|utilize|Online|Offline|Active|Idle|Status: Green|Enabled|Disabled|N/A|Unknown|Error|Failed|Success" \
  mac-app/Packages/MPUI/Sources/ | grep -v "// copy-allowlist:" \
  || (echo "banned word found"; exit 1)

# No em dashes
! grep -REn "—|–" mac-app/Packages/MPUI/Sources/ \
  || (echo "em dash found"; exit 1)

# String literals in render code
! grep -REn '"[A-Z][a-z]+ [a-z]' mac-app/Packages/MPUI/Sources/ \
  | grep -v 'MPStrings+Bindings.swift' \
  | grep -v 'PreviewFixtures.swift' \
  || (echo "string literal in render code"; exit 1)

# displayName == nil must never appear
! grep -REn "displayName == nil|displayName != nil" mac-app/Packages/MPUI/Sources/ \
  || (echo "displayName nil check found"; exit 1)

# displayName.isEmpty is the right check
grep -REn "displayName\.isEmpty" mac-app/Packages/MPUI/Sources/ \
  | wc -l   # must be > 0

# Parity constant
grep -E "STALE_AFTER_SECONDS\s*=\s*180" viewer/src/lib/freshness.ts
grep -E "static let staleAfterSeconds\s*=\s*180" mac-app/Packages/MPCore/Sources/MPCore/Staleness.swift

# ManualOverride.Duration conformances
grep -E "extension ManualOverride\.Duration:\s*Identifiable,\s*Hashable" \
  mac-app/Packages/MPCore/Sources/MPCore/ManualOverride.swift
```

### 16.3 Manual verification matrix

Run on a real Mac with macOS 14 and 15:

| Scenario | Pass criteria |
|---|---|
| Cold launch, no Accessibility | Onboarding Step 1 → Step 2 |
| Grant Accessibility in System Settings | Auto-advance to Step 3 within 1.5s |
| Cold launch, Accessibility already granted | Onboarding Step 1 only (or skip if `setup.completed`) |
| Create viewer link | URL appears in the card; "Copied" affordance briefly visible |
| Rotate link | Old URL stops working; new URL works |
| Revoke access | Pairing removed; mast reverts to "Not connected" |
| Open the viewer URL | Page shows "In a meeting" when busy |
| Set busy · 30 minutes from menu bar | Mast becomes a cone immediately, viewer sees meeting |
| Wait 30 minutes | Mast reverts to available; viewer sees available |
| Set busy, then Back to automatic | Mast reverts immediately |
| Toggle Calls are okay while busy | Mast becomes a pennant; viewer sees call-okay |
| Lose internet | Mast shows "Meeting status unavailable"; "Try again" copy |
| Restore internet within 60s | Mast recovers |
| Open recovery window, leave idle 60s | Phrase hides; "Reveal again" appears |
| Press any key in recovery window | Timer resets to 60s |
| Increase Contrast on | Mast tint is darker brass |
| Reduce Motion on | Plate swaps without animation |
| VoiceOver on mast | "Meeting. In a meeting. Better to wait." |
| Delete everything | Confirmation sheet; on confirm, onboarding reappears |
| Quit and relaunch after delete | Onboarding shown |

### 16.4 Visual review

For each `PlateFace`, capture a screenshot in:

- Day palette, light
- Day palette, dark
- Night palette, light
- Night palette, dark
- Increase Contrast (day)
- Increase Contrast (night)

Store under `docs/visual-reviews/0.1/<face>/<theme>.png`.

---

## 17. Decision records (NEW — audit A3)

Each decision record has a concrete filename. An LLM implementing this plan
must write a stub at each path with the header `Status: PROPOSED` and a one-
paragraph rationale; the team resolves each before merge.

| ID | Path | Subject |
|---|---|---|
| D1-DR | `docs/decisions/0007-menu-bar-icon-template.md` | Menu bar icon uses `symbolRenderingMode(.template)` |
| D2-DR | `docs/decisions/0008-default-pairing-rotation.md` | Pairing rotation uses 30-day window |
| D3-DR | `docs/decisions/0009-macOS-14-minimum.md` | Drop macOS 13 support (Accessibility API additions) |
| D4-DR | `docs/decisions/0010-station-default-size.md` | Station opens at 560x640 |
| D5-DR | `docs/decisions/0011-overridable-defaults.md` | Reduce default heartbeat to 60s (was 120s) |
| D6-DR | `docs/decisions/0012-recovery-phrase-60s.md` | Recovery phrase auto-hide timer is 60s |
| D7-DR | `docs/decisions/0013-pairing-windows-included.md` | Pairing windows are part of the bundle (no system extension) |
| D8-DR | `docs/decisions/0014-undo-delete-window.md` | 5-second undo window after `Delete everything` |
| D9-DR | `docs/decisions/0015-feature-flag-rollout.md` | `ui.macNative` flag controls rollout |
| D10-DR | `docs/decisions/0016-staleness-180s.md` | Stale threshold is 180s on both sides |
| D11-DR | `docs/decisions/0017-no-camera-mic.md` | Camera/mic permission never requested |
| D12-DR | `docs/decisions/0018-screen-sharing-nil.md` | `StatusPayload.screenSharing` is always nil |
| D13-DR | `docs/decisions/0019-ls-uielement.md` | `LSUIElement = true` for the menu-bar shell |
| D14-DR | `docs/decisions/0020-camera-mic-light.md` | Never expose a camera/mic affordance |
| D15-DR | `docs/decisions/0021-no-purchase-screen.md` | No upgrade / purchase screens |
| D16-DR | `docs/decisions/0022-no-notification-permission.md` | Never request Notification Center permission |
| D17-DR | `docs/decisions/0023-recovery-phrase-no-warning.md` | Recovery phrase hides silently, not with a warning |
| D18-DR | `docs/decisions/0024-onboarding-skip-allowed.md` | Onboarding Step 2 has a Skip button |
| D19-DR | `docs/decisions/0025-empty-display-name-rule.md` | Empty display name uses the shorter copy form |
| D20-DR | `docs/decisions/0026-three-durations-only.md` | Manual override supports only seven durations |
| D21-DR | `docs/decisions/0027-share-row-not-paired-count.md` | Sharing card always shows at least one row |
| D22-DR | `docs/decisions/0028-no-screen-recording-permission.md` | Never request Screen Recording permission |
| D23-DR | `docs/decisions/0029-recovery-window-modal.md` | Recovery window is non-resizable, fixed size |
| D24-DR | `docs/decisions/0030-pairing-window-modal.md` | Pairing window is non-resizable |
| D25-DR | `docs/decisions/0031-onboarding-modal.md` | Onboarding window is non-resizable |
| D26-DR | `docs/decisions/0032-station-not-modal.md` | Station window is resizable between 520x580 and 720x900 |
| D27-DR | `docs/decisions/0033-menu-bar-icon-pulse.md` | Menu bar icon does not pulse on state change |
| D28-DR | `docs/decisions/0034-no-app-icon-customization.md` | App icon is fixed; no user customization |
| D29-DR | `docs/decisions/0035-telemetry-opt-in.md` | Telemetry is opt-in via the publish toggle, default off |
| D30-DR | `docs/decisions/0036-recovery-copy-in-deck.md` | Recovery copy lives in `docs/copy/deck.md`, not inline |
| D31-DR | `docs/decisions/0037-pairing-display-name-trim.md` | Display name is trimmed on commit |
| D32-DR | `docs/decisions/0038-onboarding-window-stack.md` | Onboarding windows stack in a single window group |
| D33-DR | `docs/decisions/0039-recovery-display-name-fallback.md` | Recovery phrase reveals only the phrase, not the display name |
| D34-DR | `docs/decisions/0040-pairing-revocation-window.md` | Revoking access takes effect within 30s |
| D35-DR | `docs/decisions/0041-default-pairing-ttl.md` | Pairing code expires 30 days after creation |
| D36-DR | `docs/decisions/0042-session-id-rotation.md` | Session ID rotates on each app launch |

Each stub file has the format:

```
# <subject>

**Status:** PROPOSED
**Date:** 2026-08-08
**Supersedes:** -

## Context

<one paragraph: what triggered the decision>

## Decision

<one paragraph: what was decided>

## Consequences

<one paragraph: what becomes easier and what becomes harder>
```


---

## 18. Definition of done

A release of 0.1 is shippable when every box below is checked.

### Function

- [ ] All eleven defects D1–D11 are fixed or have a deferral ADR.
- [ ] All eleven audit corrections A1–A11 are addressed in the code.
- [ ] Phase 7 rollback path (`ui.macNative` flag) works.
- [ ] Migration runs cleanly on a fresh install and on an upgraded install.
- [ ] Every `PulseActions` method has an acceptance test.
- [ ] The mast updates within 1s of a state change in the publish backend.

### Craft

- [ ] No string literal in any view body, scene declaration, or modifier.
- [ ] No banned word in any source file under `MPUI/Sources/`.
- [ ] No em dash in any source file under `MPUI/Sources/`.
- [ ] Every `#Preview` block has a corresponding `PulseStore.preview*()`.
- [ ] Increase Contrast handling verified manually.
- [ ] Reduce Motion verified manually.

### Copy

- [ ] Every deck key appears in `MPStrings+Bindings.swift`.
- [ ] `MPString` catalogue covers §12 in full.
- [ ] No deck string has been edited without a copy-deck diff.

### Accessibility

- [ ] VoiceOver reads the mast as "Meeting. In a meeting. Better to wait."
      (or equivalent for available / generic).
- [ ] Keyboard reaches every interactive control.
- [ ] Increase Contrast swap is visible.
- [ ] Reduce Motion skips animation.
- [ ] Smart Invert does not destroy shape semantics.

### Verification and documentation

- [ ] `make lint` passes.
- [ ] `xcodebuild test -scheme MeetingPulse -destination 'platform=macOS'`
      passes.
- [ ] All 36 decision records exist as stubs under `docs/decisions/`.
- [ ] Visual-review screenshots captured for all six theme combos.
- [ ] Manual verification matrix passes for every scenario.
- [ ] `docs/06-owner-app-ui-plan-file.md` is current.

---

## 19. Out of scope (explicit list)

The following were considered and explicitly deferred to 0.2 or later:

- Touch Bar support.
- Localization beyond English.
- A second menu bar shape.
- Notification Center banners.
- App icon customization.
- Onboarding tour for new owners (Step 1's text is the tour).
- A `Recover pairing` flow when the viewer URL is lost.
- Two-device pairing (one pairing at a time for 0.1).
- A web-based admin panel.
- A CLI binary.

---

## 20. Appendix A — full copy catalogue

Every string the product shows, with its deck source line, in the order it
appears in `docs/copy/deck.md`:

```
MPString.board.busyHeadline   <- "## The board" row 1
MPString.board.busySubhead    <- row 1
MPString.board.callOkayHeadline <- row 2
MPString.board.callOkaySubhead <- row 2
MPString.board.genericHeadline <- row 3
MPString.board.genericSubhead <- row 3
MPString.board.offlineHeadline <- row 4
MPString.board.offlineSubhead <- row 4
MPString.board.unpairedHeadline <- row 5
MPString.board.unpairedSubhead <- row 5
MPString.menu.setBusy          <- "### The reduced menu bar"
MPString.menu.setAvailable     <- same
MPString.menu.backToAutomatic  <- same
MPString.menu.callsAreOkay     <- same
MPString.menu.openStation      <- same
MPString.menu.quit             <- same
MPString.menu.duration.m15     <- same
MPString.menu.duration.m30     <- same
MPString.menu.duration.m45     <- same
MPString.menu.duration.h1      <- same
MPString.menu.duration.h2      <- same
MPString.menu.duration.h4      <- same
MPString.menu.duration.untilCleared <- same
MPString.onboarding.step1.headline <- "### Setup" step 1
MPString.onboarding.step1.body     <- step 1
MPString.onboarding.step1.cta      <- step 1
MPString.onboarding.step2.headline <- step 2
MPString.onboarding.step2.body     <- step 2
MPString.onboarding.step2.cta      <- step 2
MPString.onboarding.step2.skip     <- step 2
MPString.onboarding.step2.waiting  <- step 2
MPString.onboarding.step2.granted  <- step 2
MPString.onboarding.step3.headline <- step 3
MPString.onboarding.step3.body     <- step 3
MPString.onboarding.step3.cta      <- step 3
MPString.onboarding.step3.later    <- step 3
MPString.onboarding.step3.openApp  <- step 3
MPString.error.starting            <- "### Failures"
MPString.error.unreachable         <- "### Failures"
MPString.error.untrustedSource     <- "### Failures"
MPString.error.permissionDenied    <- "### Failures"
MPString.setupError.install.headline <- "### Setup errors"
MPString.setupError.install.body     <- "### Setup errors"
MPString.setupError.install.cta      <- "### Setup errors"
MPString.setupError.generic.headline <- "### Setup errors"
MPString.setupError.generic.body     <- "### Setup errors"
```

---

## 21. Appendix B — banned words reference

The full banned list, for grep gate (§16.2):

```
seamless, effortless, powerful, robust, leverage, utilize,
delve, elevate, unlock,
Oops, Uh oh, Something went wrong, An error occurred,
Please note that, In order to, At this point in time,
Online, Offline, Active, Idle, Status: Green,
Enabled, Disabled, N/A, Unknown,
Error, Failed, Success
```

Plus em dashes (`—`, `–`) and curly quotes (`‘`, `’`, `“`, `”`).

---

## 22. Appendix C — parity binding details

The owner mast and the viewer page must agree. The parity test in
`MPUITests/MastParityTests.swift` reads both source files and asserts:

```swift
import XCTest
@testable import MPUI
@testable import MPCore

final class MastParityTests: XCTestCase {
    func test_staleConstantMatchesViewer() throws {
        // viewer/src/lib/freshness.ts
        let viewer = try String(contentsOfFile: "viewer/src/lib/freshness.ts")
        XCTAssertTrue(viewer.contains("STALE_AFTER_SECONDS = 180"),
                      "viewer must use 180s staleness threshold")

        // mac-app/Packages/MPCore/Sources/MPCore/Staleness.swift
        let owner = try String(contentsOfFile:
            "mac-app/Packages/MPCore/Sources/MPCore/Staleness.swift")
        XCTAssertTrue(owner.contains("static let staleAfterSeconds = 180"),
                      "owner must use 180s staleness threshold")
    }

    func test_faceMatrix() {
        let cases: [(state: MPCore.State, callOkay: Bool?, expected: PlateFace)] = [
            (.busy,    true,  .meeting),   // busy + call-okay still shows meeting; subhead differs
            (.busy,    false, .meeting),
            (.busy,    nil,   .meeting),
            (.available, true, .available),
            (.available, false, .available),
            (.available, nil, .available),
            (.unavailable, true,  .generic),
            (.unavailable, false, .generic),
            (.unavailable, nil,   .generic),
        ]
        for c in cases {
            let store = PulseStore.preview()
            store.lastSync = .init(state: c.state,
                                   callOkay: c.callOkay,
                                   freshness: .fresh(secondsAgo: 10),
                                   capturedAt: .now)
            XCTAssertEqual(store.mastFace, c.expected,
                           "state=\(c.state) callOkay=\(String(describing: c.callOkay))")
        }
    }
}
```

The viewer page uses `effectiveDisplayState` which is one of four:
`meeting`, `callOkay`, `generic`, `unpaired`. The owner mast uses three:
`meeting`, `available`, `generic`. The `unpaired` case is **not** reachable
from the owner (the owner sees the mast only after onboarding). When the
viewer is unpaired, the owner's mast is irrelevant.

---

## 23. Appendix D — file-level index of changes

A grep-friendly index of every file this plan touches, in dependency order.

```
mac-app/MeetingPulse/Info.plist                          (T1.1)
mac-app/MeetingPulse.xcodeproj/project.pbxproj           (T1.2)
mac-app/Packages/MPSupport/Sources/MPSupport/Strings.swift        (T1.3, NEW)
mac-app/Packages/MPSupport/Sources/MPSupport/FeatureFlag.swift    (T7.1, NEW)
mac-app/Packages/MPSupport/Sources/MPSupport/MigrationAssistant.swift  (T7.2, NEW)
mac-app/Packages/MPCore/Sources/MPCore/ManualOverride.swift       (T1.6)
mac-app/Packages/MPCore/Sources/MPCore/Staleness.swift            (T3.2, NEW)
mac-app/Packages/MPUI/Package.swift                               (T1.2, NEW)
mac-app/Packages/MPUI/Resources/Localizable.xcstrings             (T1.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/OwnerRuntime.swift             (T2.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/OwnerError.swift               (T2.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/PulseStore.swift               (T2.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/PulseActions.swift             (T2.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/AppEnvironment.swift           (T2.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/DesignSystem/MPColor.swift     (T1.5, NEW)
mac-app/Packages/MPUI/Sources/MPUI/DesignSystem/MPType.swift      (T1.5, NEW)
mac-app/Packages/MPUI/Sources/MPUI/DesignSystem/MPSpacing.swift   (T1.5, NEW)
mac-app/Packages/MPUI/Sources/MPUI/DesignSystem/MPMotion.swift    (T1.5, NEW)
mac-app/Packages/MPUI/Sources/MPUI/DesignSystem/MPShape.swift     (T1.5, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Components/MPPlate.swift       (T4.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Components/MPReasonLine.swift  (T4.2, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Components/MPModeControl.swift (T4.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Components/MPCallsAreOkayToggle.swift  (T4.4, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Components/MPPublishRail.swift (T4.5, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Components/MPRefreshable.swift (T4.6, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Components/MPDestructiveConfirm.swift  (T4.7, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Components/MPMenuItem.swift    (T4.8, NEW)
mac-app/Packages/MPUI/Sources/MPUI/CopyBindings/MPStrings+Bindings.swift  (T1.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Stations/StationWindow.swift   (T4.0, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Stations/StationSection.swift  (T4.0, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Stations/StationToolbar.swift  (T7.4, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Mast/MastView.swift            (T4.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Mast/MastOrder.swift           (T4.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Mast/ReasonLineBuilder.swift   (T4.2, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Mast/MastShape.swift           (T4.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/WatchSection/WatchSection.swift          (T5.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/WatchSection/WatchStatusCard.swift       (T5.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/SharingSection/SharingSection.swift      (T5.2, NEW)
mac-app/Packages/MPUI/Sources/MPUI/SharingSection/ViewerLinkCard.swift      (T5.2, NEW)
mac-app/Packages/MPUI/Sources/MPUI/SharingSection/PairedViewersList.swift    (T5.2, NEW)
mac-app/Packages/MPUI/Sources/MPUI/SharingSection/ViewerRow.swift           (T5.2, NEW)
mac-app/Packages/MPUI/Sources/MPUI/ThisMacSection/ThisMacSection.swift      (T5.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/ThisMacSection/DisplayNameField.swift    (T5.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/ThisMacSection/InstallLocationRow.swift  (T5.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/ThisMacSection/StartupRow.swift          (T5.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/ThisMacSection/RecoveryRow.swift         (T5.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/ThisMacSection/DangerZoneRow.swift       (T5.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/PrivacySection/PrivacySection.swift      (T5.4, NEW)
mac-app/Packages/MPUI/Sources/MPUI/MenuBar/ReducedMenuBarView.swift  (T6.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/MenuBar/MenuBarIcon.swift         (T6.2, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Onboarding/OnboardingWindow.swift (T6.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Onboarding/OnboardingStep1.swift  (T6.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Onboarding/OnboardingStep2.swift  (T6.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Onboarding/OnboardingStep3.swift  (T6.3, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Pairing/PairingWindow.swift       (T6.6, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Settings/SettingsWindow.swift     (T6.7, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Recovery/RecoveryWindow.swift     (T6.4, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Diagnostics/DiagnosticsWindow.swift  (T6.5, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Previews/PreviewStores.swift      (T2.1, NEW)
mac-app/Packages/MPUI/Sources/MPUI/Previews/PreviewFixtures.swift   (T2.1, NEW)
mac-app/Packages/MPUITests/PulseStoreTests.swift                     (T2.1, NEW)
mac-app/Packages/MPUITests/MastParityTests.swift                     (T3.2, NEW)
mac-app/Packages/MPUITests/PreviewFixtureTests.swift                 (T2.1, NEW)
mac-app/Packages/MPUITests/CopyGrepTests.swift                       (T1.3, NEW)
mac-app/Packages/MPUITests/RecoveryTimerTests.swift                  (T6.4, NEW)
mac-app/Packages/MPUITests/OnboardingTests.swift                     (T6.3, NEW)
mac-app/Packages/MPUITests/DisplayNameTests.swift                    (T5.2, NEW)
mac-app/Packages/MPUITests/MenuTests.swift                           (T6.1, NEW)
mac-app/Packages/MPUITests/IncreaseContrastTests.swift               (T4.1, NEW)
mac-app/Packages/MPUITests/MigrationTests.swift                      (T7.2, NEW)
mac-app/MeetingPulse/MeetingPulseApp.swift                           (many sites — see §3.1.3)
docs/decisions/0007-0042-*.md                                        (T7.5, 36 files)
docs/visual-reviews/0.1/                                            (T6.0, NEW)
```

---

## 24. End of plan

Every task in §15 has a verification command, a manual check, or a unit test.
Every string is sourced. Every defect has an owner. Every audit finding has
a corrective site. An LLM implementing this plan should be able to do so
without re-reading `docs/05-owner-app-ui-plan.md`, although that file remains
the source of truth for the design intent.

If a future edit introduces a new defect, add it to §3.1.3. If a future
edit introduces a new audit correction, add it to §1.1 with a plan section
reference. If a future edit adds a new visible string, add it to §12 and
to `docs/copy/deck.md`. If a future edit adds a new decision, add it to
§17 with a concrete filename.
