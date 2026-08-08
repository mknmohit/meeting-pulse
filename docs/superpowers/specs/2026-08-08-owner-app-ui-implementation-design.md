# Meeting Pulse owner app UI implementation design

**Date:** 2026-08-08

**Status:** Approved for implementation

**Source contract:** `docs/06-owner-app-ui-plan-file.md`

## Goal

Replace the monolithic native macOS owner app surface with the attachment's
seven-phase `MPUI` migration. The owner gets a Station window that keeps the
published signal visible, a reduced six-item menu bar, focused sections for
watching and account tasks, and explicit recovery and failure states. The
viewer, backend schema, RPCs, and published payload contract remain unchanged.

## Architecture

`MeetingPulseApp` becomes a small SwiftUI scene shell. It owns one
`OwnerRuntime` and one main-actor `PulseStore`, injects them through environment
values, and declares the menu bar, Station, onboarding, pairing, settings,
recovery, and diagnostics scenes.

The new `MPUI` package owns the owner-facing state adapters, action protocol,
design tokens, copy bindings, shared components, Station sections, menu bar,
onboarding, and auxiliary windows. It depends on the existing `MPCore`,
`MPSync`, `MPDetection`, and `MPSupport` packages.

Existing package contracts remain the default integration boundary. MPUI adds
adapters for the repository's current `PairingCodeResult`, `ViewerRecord`,
`StatusTransport`, reducer, detection scheduler, permission coordinator, and
override store. Core package APIs change only where the attachment explicitly
requires a shared conformance or value, such as
`ManualOverride.Duration: Identifiable & Hashable` and the staleness constant.

`MPSupport` owns launch state, copy catalogue, feature-flag support, and
idempotent migration helpers without importing MPUI. The old app shell remains
available behind the `ui.macNative` flag so setting it to `false` can launch the
legacy path during the rollout window.

## Station and interaction model

The Station uses the approved split composition. A persistent 288pt left
column contains the mast, reason line, mode control, Calls are okay toggle,
publish rail, and four section rows. The right column contains the active
grouped form.

The mast mirrors the viewer's board:

- Busy with calls not okay uses the cone face and `In a meeting`.
- Busy with calls okay uses the pennant face and the call-okay copy.
- Every other owner-reachable result uses the bare mast and
  `Meeting status unavailable`.

Shape and words carry state independently of color. Appearance-aware color
sets, contrast variants, system typography, and system controls provide the
native macOS presentation.

The four Station sections are:

- **Watch:** permission status, Google Meet and Slack huddle source rows,
  scheduler readings, publishing cadence, and superseded state.
- **Sharing:** link creation empty state, code and URL actions, rotation and
  revocation confirmations, and a refreshable paired-viewers list.
- **This Mac:** trimmed display name with a 600ms debounce, login item,
  install-location recovery, recovery phrase access, and delete confirmation.
- **Privacy:** read-only sourced explanations of what leaves the Mac, what the
  viewer sees, and what never leaves the Mac.

The reduced menu bar keeps Set busy with seven duration choices, Set available,
Back to automatic while an override is active, Calls are okay, Open Meeting
Pulse, and Quit Meeting Pulse.

Onboarding has three steps. Step 2 opens Accessibility settings, watches the
permission stream, displays the sourced waiting and granted copy, then advances
once to Step 3. The recovery window fetches the phrase on demand, holds it only
in local view state, auto-hides it after 60 seconds, and resets the timer on
keyboard, click, or accessibility focus interaction.

## State and data flow

`OwnerRuntime` retains the existing sync coordinator, status transport,
detection scheduler, permission coordinator, network monitor, launch
coordinator, recovery service, keychain, and override store. It projects their
streams into `PulseStore`.

`PulseStore` stores view-facing inputs and exposes derived `effective`, mast
face, headline, reason, reachability, loading, and launch state. It never
performs I/O. Views call the `PulseActions` protocol, not concrete services.

Heartbeat cadence is 60 seconds by default, 30 seconds while an override is
active, and 300 seconds while the Station is closed without an override.
Manual actions update the store immediately, publish asynchronously, and roll
back the local optimistic state when publication fails. `StatusPayload` keeps
its existing fields and `screenSharing` remains `nil` at every call site.

Unknown detector readings, missing Accessibility permission, stale data,
network loss, and superseded publishing fail closed. They never become an
available viewer result. Delete everything clears remote and local state,
stops the runtime, and enters an explicit setup-required state rather than
leaving a dead menu bar process.

The migration reads the existing display name, pairing code, recovery secret,
and telemetry identity, writes them into the current stores, and records an
idempotent sentinel under the Meeting Pulse application-support directory.

## Copy and accessibility rules

Every visible string resolves through `MPString` and is backed by
`docs/copy/deck.md`. Render code contains no new literal copy, banned status
vocabulary, curly quotes, or em/en dashes. The empty display-name predicate is
`displayName.isEmpty`.

Decorative mast shapes are hidden from VoiceOver. The mast is exposed as one
composite label containing the face, headline, and reason. Keyboard navigation
reaches all controls, section shortcuts use Command plus 1 through 4, and
reduced motion skips state animations. Increase Contrast selects the darker
brass variants.

## Verification and handoff

The implementation adds focused MPUI tests for:

- reducer-to-face parity and the 180-second staleness constant
- optimistic override rollback
- duration iteration and reduced menu item counts
- sourced-copy and banned-word gates
- onboarding auto-advance and recovery auto-hide/reset
- display-name emptiness and migration idempotence
- contrast variants and payload invariants

The project gains lint checks for raw render strings, banned words, em/en
dashes, forbidden optional-name comparisons, and parity markers. Validation
uses the existing Swift package tests, Xcode project/package resolution,
MeetingPulse build and test scheme, and the attachment's manual matrix. Real
device checks remain explicitly `NOT RUN` until a signed macOS release can be
exercised.

Create the 36 decision-record stubs at the concrete paths in the attachment
and the visual-review evidence structure without changing the viewer or
backend surfaces.
