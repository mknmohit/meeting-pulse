# Menu Bar Indicator Color Design

**Date:** 2026-08-08

**Status:** Approved design

## Goal

Make the menu bar status indicator communicate the meeting and call-readiness
state through its existing status dot:

- Green when a meeting is active and calls are not marked okay.
- Blue when a meeting is active and calls are marked okay.
- Pinkish-red when no meeting is active but availability is known.
- Neutral gray when the state is unavailable or stale.

The Heart Thread mark itself keeps its current white, muted-thread, and gold-wave
styling.

## Chosen approach

Extend the existing `HeartThreadMenuIcon` in
`mac-app/MeetingPulse/MeetingPulseApp.swift` with a `callsOkay` input. The
existing `NativeMenuBarLabel` supplies the state, freshness, and call-readiness
value from the active data path:

- Native MPUI path: `PulseStore.effectiveState`, `PulseStore.isFresh`, and
  `PulseStore.callsOkay`. A stale native snapshot is presented as
  `.unavailable`.
- Legacy path: `OwnerAppModel.state` and `OwnerAppModel.callOkay`.

Keep the current native `NSImage` renderer, dot outline, opacity behavior,
one-shot state animation, accessibility label, and stable accessibility
identifier. Only the dot fill color mapping changes.

## State mapping

The color mapping is total and ordered by state:

| State | Calls okay | Dot color |
| --- | --- | --- |
| `busy` | `true` | Blue |
| `busy` | `false` | Existing green |
| `available` | either | Existing pinkish-red |
| `unavailable` | either | Existing neutral gray |

The `busy + callsOkay` combination takes precedence over the normal busy
color. No new status or persistence field is introduced. Existing native
freshness data drives stale snapshots to the neutral/unavailable presentation;
the legacy path retains its current state semantics.

## Error handling

No new error path is required. When the app cannot determine a usable state,
the existing unavailable state and neutral color remain visible. The renderer
will not silently map an unknown condition to the active-meeting colors.

## Validation

Add focused tests for the four state/color cases and preserve the existing stale
state behavior. Build the macOS target and run the existing package tests that
cover the modified Swift sources. Verify that accessibility semantics and the
legacy/native data paths remain unchanged.

## Non-goals

- Do not recolor the full Heart Thread mark.
- Do not change the status reducer, sync payload, persistence, or menu contents.
- Do not replace the current `NSImage` menu bar renderer.
- Do not add a new shared indicator-state abstraction for this local mapping.
