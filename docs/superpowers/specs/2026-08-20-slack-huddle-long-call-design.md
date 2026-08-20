# Slack Huddle long-call status design

## Problem

The Slack Huddle detector can report `Meeting status unavailable` with the
reason `A window looked like a call. Not sure enough.` during a Huddle that
continues for a long time. The Slack latch currently expires an anchor after
the shared four-hour `maxLatchDuration`. Expiration emits `.unknown`, even
when Slack is still running and the confirmed Huddle session has not ended.

The menu-bar copy is correct for an unknown observation, but the detector is
losing a confirmed active session rather than observing a definitive Huddle
end.

## Goals

- Keep a confirmed Slack Huddle reported as active for its full duration,
  including beyond four hours.
- Preserve the existing menu-bar copy: active Slack Huddles continue to show
  `In a meeting`.
- End the active result only on positive, source-specific end evidence:
  Slack exits, or an authoritative completed scan confirms that the dedicated
  Huddle window is gone after the existing recreation grace.
- Preserve the independent Google Meet safety-valve behavior.
- Keep the change isolated to Slack detection and its tests.

## Non-goals

- Change the status vocabulary or menu-bar strings.
- Change Google Meet latch behavior.
- Treat an open, focused, minimized, or recently used Slack window as a
  Huddle.
- Add a new Slack API, permission, network request, or audio signal.
- Remove the scheduler's two-sample end-settle rule.

## Current behavior

`SlackHuddleDetector` confirms a Huddle from a dedicated `AXStandardWindow`
whose title begins with `Huddle:` and which contains the Huddle toolbar and
`Leave Huddle` button. It stores a `{ processIdentifier, windowID,
confirmedAt }` anchor in `SlackHuddleLatch`.

The detector samples every five seconds while active. Strong confirmation
refreshes the anchor. If strong selectors are temporarily absent, the latch
uses visibility and recreation grace rules. Regardless of the current scan,
the latch first checks the anchor age against `maxLatchDuration` and changes
to `.unknown` when the age exceeds four hours. That unknown observation flows
through `StatusReducer` as an unavailable status with the untrusted-source
reason.

## Proposed behavior

### Session confirmation and maintenance

1. A non-empty set of strong Huddle anchors starts or refreshes the active
   session.
2. While a session is latched:
   - Slack not running clears the latch and emits `.sourceAbsent`.
   - Strong anchors refresh the session and emit `.active`.
   - A readable dedicated Huddle window with temporarily missing controls
     keeps the session `.active`; the window is established liveness evidence
     after confirmation.
   - An incomplete or unreadable scan keeps the existing session `.active`
     instead of turning it into `.unknown`.
3. Slack Huddle sessions do not expire because of elapsed time. The Slack
   latch does not apply `maxLatchDuration`; the Meet latch keeps its existing
   safety valve.

### Session release

1. A completed authoritative scan with no dedicated Huddle window enters the
   existing recreation grace period.
2. If the Huddle window returns during that grace, the active session remains
   active and strong selectors can refresh it.
3. If the grace expires without a Huddle window, the latch releases to
   `.inactive`; the scheduler still requires its configured two consecutive
   non-active samples before publishing the end.
4. Slack termination remains an immediate `.sourceAbsent` release.

The Huddle window remains the primary signal for liveness and end detection.
Slack's ordinary main window, focus state, Huddles row, and start button remain
non-signals.

## Data flow

```text
AX snapshot
  -> SlackSelectors
       -> strong anchors + Huddle-window presence + scan completeness
  -> SlackHuddleDetector visibility/recreation-grace policy
  -> SlackHuddleLatch
       -> active / inactive / sourceAbsent
  -> DetectionScheduler end settling
  -> StatusReducer
       -> busy while active, available after a settled end
```

The public observation and status models remain unchanged. Because a live
Slack Huddle remains `.active`, `StatusReducer` continues to select
`confirmedActiveSource`, and the UI does not need a new branch or copy.

## Error handling

- Permission denial and detector invalidation continue to clear the latch and
  publish `.unknown` with the existing permission health.
- Slack absence continues to map to `.sourceAbsent`.
- A scan error or incomplete tree during a confirmed Huddle is treated as a
  transient observation gap and preserves the latched `.active` result.
- A completed authoritative scan that finds a Huddle window but cannot find
  its controls is not treated as an end; the existing window is still present.
- No path introduced by this change converts uncertainty into `.inactive` or
  `.available`.

This deliberately favors preserving a known-busy result over interrupting a
confirmed long Huddle. A future detector redesign can add a separate,
user-visible health signal without weakening the active-session boundary.

## Tests

Add or update MPDetection tests to prove:

1. A confirmed Slack Huddle remains `.active` after the previous four-hour
   latch duration.
2. A latched Huddle remains `.active` when the scan is incomplete or
   unavailable.
3. A Huddle window with temporarily missing controls remains `.active`.
4. Window recreation grace still preserves the Huddle and then releases it
   after an authoritative absence.
5. Slack termination clears the latch to `.sourceAbsent`.
6. The detector integration path remains active during a long-running sample.
7. Meet's existing max-duration expiry remains `.unknown`.
8. Existing menu-bar reason and headline tests continue to assert the generic
   `In a meeting` active copy and the unchanged untrusted copy for genuinely
   unknown observations.

## Acceptance criteria

- A confirmed Slack Huddle lasting longer than four hours never becomes
  unavailable solely because of elapsed time.
- A definitive Huddle end still reaches available after the existing settle
  behavior.
- Slack and Meet detector tests pass, including the existing safety-valve
  regression.
- No UI strings or status model cases change.
