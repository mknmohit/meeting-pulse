# Station status controls and override reliability

**Date:** 2026-08-09

**Status:** Approved design

## Context

The native Station already has a manual Busy/Automatic/Available control in the
Mast sidebar, but it is easy to miss and the Available action does not expose
the same duration choices as Busy in the menu-bar path. The control also
launches independent asynchronous mutations. A rapid Busy -> Automatic -> Busy
sequence can therefore finish out of order and leave the persisted override
different from the owner's last selection.

The owner needs one obvious place in Station to set either manual state, choose
how long it lasts, return to automatic detection, and understand when the
override will end.

## Goals

- Make manual status controls discoverable in the Watch detail.
- Offer the same seven fixed durations for Busy and Available.
- Add a Custom duration editor using hours and minutes.
- Validate Custom durations from one minute through 24 hours.
- Make the latest status intent win when actions are tapped quickly.
- Keep the Mast as a compact, read-only status and countdown summary.
- Preserve automatic detector precedence, expiry persistence, and menu-bar
  behavior.
- Keep all control text native, keyboard reachable, and aligned with the
  existing MPUI tokens.

## Non-goals

- Do not change the viewer payload or reveal that a status was set manually.
- Do not change detector rules, reducer precedence, or stale-state behavior.
- Do not add a new persistence format. The persisted override already stores
  wall-clock creation and expiry dates, which are sufficient for Custom.
- Do not add notifications or a second countdown timer.
- Do not redesign Sharing, This Mac, Privacy, or onboarding.
- Do not change the existing seven presets or the 30-minute default.

## Considered approaches

### A. Keep the Mast control and polish it

This is the smallest code change, but it leaves the primary action in a narrow
sidebar area that is easy to overlook and gives no room for a clear Custom
editor.

### B. Put the full control in Watch and keep a Mast summary (selected)

Watch is the Station's status source of truth, so it can provide a focused
status group with enough space for explicit actions and validation. The Mast
continues to show the live plate, reason, and countdown while the user browses
other sections, but it no longer owns mutation controls. This avoids duplicate
actions and gives the owner one reliable place to change state.

### C. Duplicate controls in Watch and Mast

This makes actions available everywhere, but creates two interaction surfaces
that can disagree during asynchronous updates and increases the accessibility
and testing surface without adding product capability.

Approach B is selected because it improves discoverability and clarity while
keeping the status summary persistent and avoiding duplicate mutation paths.

## Experience

### Watch status group

After the live Watch surface is available, a `Status` group appears before the
permission and detector groups. It contains:

1. A summary row showing `Busy`, `Available`, or `Watching automatically`.
2. A live detail line derived from the same `overrideExpiry` projection used by
   the Mast. Timed overrides show the localized end time and remaining time;
   indefinite overrides say they last until cleared.
3. A duration picker with the existing seven presets and a `Custom...` option.
4. Explicit `Set busy` and `Set available` buttons that apply the selected
   duration.
5. `Back to automatic` while an override is active.

The Custom editor uses native numeric fields or steppers for hours and minutes.
Hours are limited to 0-24 and minutes to 0-59. A value of 24 hours must have
zero minutes; 0 hours and 0 minutes is invalid. The Set actions are disabled
for invalid or out-of-range values, and the control explains the one-minute to
24-hour limit.

The setup checklist remains focused on permission and pairing. It does not
show actions that cannot be used until the live runtime is ready.

### Mast summary

`MastView` keeps the plate, the periodic reason line, and `Calls are okay`.
The reason line remains the live source for the status summary:

- `Busy until <time> - <remaining> remaining`
- `Available until <time> - <remaining> remaining`
- `Busy until you clear it`
- `Available until you clear it`
- `Watching automatically`

The mode buttons and duration picker are removed from the Mast so users do not
have two ways to mutate the same state.

## Architecture and data flow

### Duration model

`ManualOverride.Duration` keeps its seven preset values and gains a
`custom(minutes:)` value for Station-created durations. `allCases` remains the
seven fixed presets so the legacy menu-bar menus do not accidentally expose an
invalid placeholder. Station adds its own Custom option and passes a validated
minute count to the shared action API.

Duration validation is centralized in `ManualOverride.Duration` and enforced
again by `ManualOverrideStore.set`. A Custom duration is never persisted as a
separate field; only its calculated expiry is persisted. This keeps restart,
clock-rollback, and expiry behavior identical for presets and Custom.

### Station control component

Add a focused MPUI component for the Watch status group. It owns only transient
form state for the selected duration and Custom hours/minutes. It reads
`PulseStore.mode`, `preferredDuration`, `overrideExpiry`, and `lastError`, and
invokes `PulseActions.setBusy`, `setAvailable`, or `clearOverride`.

`PulseStore` remains the presentation source of truth. The component does not
write persistence or calculate deadlines itself. The existing pure
`ReasonLineBuilder` remains responsible for countdown copy and receives the
current render time from `TimelineView`.

### Ordered override mutations

All native status mutations share one serial operation tail in `OwnerRuntime`.
Each new Set or Clear operation is appended before it awaits, then waits for
the previous operation to finish. A failed operation does not prevent the next
one from running. This guarantees that the final persisted value follows the
owner's action order:

```text
Busy(30m) -> Automatic -> Busy(30m)
        set -> clear -> set
        final persisted value = Busy(30m)
```

`AppPulseActions` updates the visible mode immediately for responsiveness and
tracks a mutation generation. An older failure cannot roll back a newer
selection. Successful runtime operations continue to update the Store through
the existing model path; failed current operations restore the last confirmed
state and expose the existing network error.

Expiry callbacks are also guarded against stale work. When the expiry callback
arrives, the runtime checks the override store's current value before clearing
the model. If a newer override has already been installed, the old nil
callback is ignored. The existing monotonic expiry task remains authoritative
and removes the persisted file before publishing the automatic transition.

### Available behavior

Set available uses exactly the same action and duration path as Set busy. It
sets the effective state to Available while the override is active, suppresses
automatic detector changes through the existing reducer precedence, publishes
the override metadata to the owner transport, and returns to automatic when
cleared or expired.

Changing from Available to Busy replaces the current override rather than
stacking another timer. Changing the duration while an override is active
replaces its expiry from the moment of the new action.

## Error handling and accessibility

- Runtime and persistence failures use the dedicated `PulseError.override`
  presentation and do not report success.
- Invalid Custom values cannot reach the persistence or transport layers.
- The latest action remains enabled while an earlier action is in flight;
  visible progress copy may say `Updating...`, and stale completions cannot
  overwrite the latest selection.
- Automatic detection remains fail-closed while a clear-triggered sample is
  pending; no code maps unknown detector state to Available.
- Buttons have native focus rings, labels, and keyboard activation.
- The Custom fields expose numeric labels and the range guidance to VoiceOver.
- The control uses existing `MPGroup`, `MPRow`, `MPFont`, `MPSpace`, `MPRadius`,
  and motion/reduced-motion conventions.

## Validation

- Extend MPCore duration tests for Custom values, valid bounds, and invalid
  values.
- Extend MPSupport override-store tests for Custom persistence and rejection of
  invalid durations.
- Add a focused ordered-mutation test for Set -> Clear -> Set and for a stale
  expiry callback not clearing a newer override.
- Add MPUI tests for the Watch status control's action wiring, current-mode
  summary, duration choices, and Custom validation.
- Preserve the existing reason-line tests for timed, indefinite, automatic,
  permission, sync, and viewer-link states.
- Run the existing MPCore, MPSupport, MPUI, and local macOS build checks.
- Inspect the Station in the existing visual review target with Busy, Available,
  Automatic, Custom, expiry, and error states.
