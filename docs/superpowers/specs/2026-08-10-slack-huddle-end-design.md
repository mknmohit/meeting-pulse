# Slack Huddle end detection design

**Date:** 2026-08-10

**Status:** Approved for implementation

## Problem

After a Slack Huddle ends, the dedicated Slack Huddle window can disappear or
be recreated. Meeting Pulse intentionally gives Slack a short recreation grace
period, but the current state machine returns that grace to `authoritative`
without recording that the absence was already evaluated. The next poll starts
the same grace again, so the detector oscillates between `active` and
`unknown` instead of settling to `inactive`.

## Design

Keep the existing 20-second grace for one transient Slack window disappearance,
but make it one-shot for each absence episode:

1. A confirmed Huddle creates an active latch and clears the consumed-grace
   marker.
2. The first authoritative sample with Slack running, no Huddle window, and an
   active latch enters `recreationGrace`.
3. If a strong Huddle reappears before the deadline, the latch remains active
   and the marker resets.
4. If the deadline expires without a Huddle, transition back to authoritative
   **and consume the grace in the same sample**. The latch then releases to
   `inactive`, allowing the existing scheduler end settling to publish
   available.
5. Subsequent absent samples cannot restart the grace because the latch is
   empty and the grace marker is consumed.
6. An actual Space change starts the separate `transitionGrace` path and
   resets the recreation marker. Space-transition expiry remains fail-closed
   (`unknown`) because the target window may still be on another Space.

No new permissions, telemetry, window-title uploads, or detection sources are
introduced.

## Error handling

- Slack termination remains `sourceAbsent`.
- Accessibility failure remains `unknown`.
- A real Huddle end settles to `inactive` after the one-shot recreation grace
  and the scheduler’s existing two-sample end debounce.
- A Space visibility ambiguity never becomes `inactive` solely from a missing
  AX window.

## Tests

Add a detector regression that samples an active Huddle, observes its window
disappear, advances past the recreation grace, verifies `inactive`, and samples
again to prove the grace does not restart. Preserve the existing Space
continuity tests that require `unknown` after a Space-transition grace expires.

