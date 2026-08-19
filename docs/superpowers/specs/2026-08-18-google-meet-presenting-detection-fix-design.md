# Google Meet presenting detection fix

**Date:** 2026-08-18

**Status:** Approved for implementation

## Context

Meeting Pulse was running before an active Google Meet call but reported no
confirmed meeting. A live Accessibility probe of the current Chrome tree found
the expected Meet web area, tab, call-controls region, and `Leave call` button.
It did not find a `Share screen` button because another participant was
presenting. Instead, Meet exposed a dynamic presenter-status button whose label
ends with `is presenting`.

The current selector requires the exact `Share screen` label. That makes a
valid active call fail strong confirmation, so the detector produces a
non-active observation despite the call-controls and leave-call evidence.

## Goals and non-goals

### Goals

- Detect an active Meet call when Meet replaces the share control with a
  presenter-status control.
- Support the known English labels used by the current Meet Accessibility tree:
  `Share screen`, `Share your screen`, `Present now`, and `Stop presenting`.
- Keep dynamic presenter-status labels ending in `is presenting` local to the
  detector.
- Preserve the existing strong confirmation, tab/window anchoring, polling,
  latch, scheduler, privacy, and fail-closed behavior.
- Add regression tests for each supported label shape and a leave-call-only
  negative case.

### Non-goals

- Browser URL or tab-only detection.
- Reading or publishing meeting names, participant names, URLs, audio, video,
  or screen content.
- New Accessibility, Automation, Screen Recording, microphone, or audio
  permissions.
- Changes to the scheduler, latches, status reducer, sync protocol, or viewer.
- General localization support beyond the existing English selector contract.

## Chosen approach

Keep the existing strong Meet selector and broaden only its presentation
signal. A candidate remains valid only when its Meet web area contains:

1. The existing call-controls landmark region.
2. A button with the existing `Leave call` label.
3. A button with a recognized presentation signal.

Presentation signals are normalized with the existing case-insensitive,
whitespace-collapsing helper. Exact accepted labels are:

- `Share screen`
- `Share your screen`
- `Present now`
- `Stop presenting`

A non-empty normalized label ending in `is presenting` is also accepted for the
dynamic state exposed when another participant is presenting. The selector
continues to require an `AXButton` with the normalized role description
`button`, and it continues to reject a page with only a Meet tab title or a
leave control.

This is narrower and safer than accepting any button in the controls region,
while avoiding the privacy and false-positive risks of browser URL fallback.

## Architecture and data flow

No component boundaries change. `MeetSelectors.hasCallControls` will expose the
expanded presentation predicate to the existing `strongAnchors` flow:

```text
Chrome AX snapshot
        |
        v
Meet web area + call controls + leave + presentation signal
        |
        v
existing {windowID, hashed tab identity} anchor
        |
        v
GoogleMeetDetector -> DetectionScheduler -> status reducer/sync
```

The presentation label is used only during the in-memory selector pass. The
detector publishes only `.active`, `.inactive`, `.unknown`, or
`.sourceAbsent`, as it does today. Existing event-triggered sampling,
five-second active polling, tab/window liveness, latch expiry, and two-sample
end settling remain unchanged.

If the AX scan is incomplete or the presentation signal is not recognized, the
detector retains its current fail-closed behavior. A missing match cannot
become an active call, and an unreadable scan cannot become a confident
available state.

## Testing and validation

Add focused selector fixtures for:

- `Present now`
- `Share your screen`
- `Stop presenting`
- `A presenter is presenting`
- Case and whitespace normalization for the accepted labels
- A Meet web area with `Leave call` but no presentation signal, which remains
  unconfirmed

Run the existing MPDetection Swift package tests. Re-run the existing
`axhost-probe` against Chrome while a Meet call is active and someone is
presenting, verifying that the live tree has the expected controls and that
the detector's updated selector confirms it. No diagnostic output or fixture
may retain raw meeting content.
