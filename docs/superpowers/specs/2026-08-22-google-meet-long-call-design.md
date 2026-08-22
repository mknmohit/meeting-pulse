# Google Meet long-call status design

## Problem

The Google Meet detector uses a four-hour latch safety valve. When a
confirmed Meet anchor reaches 14,400 seconds, `MeetLatch` clears the anchor and
returns `.unknown`. The status reducer correctly maps that uncertainty to
`Meeting status unavailable`, even when the same Meet call is still active.
The owner remains in automatic mode, so the accompanying `Watching
automatically` copy is expected but the status transition is not.

The detector can later recover when a strong Meet scan or a matching live tab
is observed again. The fix must prevent elapsed time alone from invalidating a
confirmed call while retaining conservative end detection.

## Goals

- Keep a confirmed Google Meet call active for its full duration, including
  beyond four hours.
- Preserve active status through temporary control or scan gaps when the
  anchored Chrome window and Meet tab can still be verified.
- Release only from positive evidence: a confirmed post-call state, the
  anchored tab disappearing or changing, the anchored window closing, or Chrome
  terminating.
- Continue to fail closed when the anchor cannot be verified, by emitting
  `.unknown` and publishing the existing unavailable state.
- Preserve the current automatic mode, menu-bar copy, viewer copy, status
  vocabulary, sync cadence, and privacy boundary.

## Non-goals

- Do not add a Chrome extension, Meet API, permission, network request, or
  meeting-content inspection.
- Do not change Slack Huddle detection.
- Do not change the scheduler's active sampling interval or two-sample end
  settling.
- Do not treat an open Chrome window, a Meet-looking title, or an unverified
  tab as proof of an active meeting.
- Do not change UI strings or backend payloads.

## Current behavior

`GoogleMeetDetector` gathers strong Meet anchors from a readable `AXWebArea`
with call controls and correlates them with a Chrome tab entry. After a call is
confirmed, `MeetLatch` maintains it from strong confirmation or a matching
Chrome window and tab. The latch currently checks each anchor's
`confirmedAt` against a hard-coded four-hour duration before evaluating current
evidence. Expiration returns `.unknown`, which flows through
`StatusReducer` to the unavailable status.

`DetectionTuning.maxLatchDuration` is not used to configure this path; the
detector supplies the four-hour value directly. Keeping that unused setting
would make the new behavior misleading.

## Proposed behavior

### Meet latch policy

Make latch expiration an explicit optional policy in `MeetLatch.apply`.
Production Google Meet detection passes no expiration, so elapsed time cannot
clear a Meet anchor. The anchor's confirmation timestamp may remain part of the
local value type for diagnostics and identity continuity, but it is not a
production deadline.

With expiration disabled, the existing evidence order remains:

1. Chrome not running clears the Meet anchors and returns `.inactive`.
2. Strong Meet anchors replace the current anchor set and return `.active`.
3. Transition grace preserves `.active` while the active-space tree is
   temporarily unavailable.
4. A verified matching window and tab preserve `.active`.
5. An unavailable visibility state or incomplete scan returns `.unknown`
   without clearing anchors.
6. A completed authoritative scan with no matching anchor clears the anchors
   and returns `.inactive`.

The scheduler still applies its configured end-settle count before an inactive
or source-absent result changes the published effective status. An unknown
result remains immediately unavailable rather than being converted to
available.

### Recovery after a temporary gap

If a sample cannot verify the anchor, the detector may publish unavailable.
Later strong confirmation or verified liveness automatically returns the
observation to `.active`, and the existing sync path publishes the corrected
busy state. No manual refresh or mode change is required.

## Components and edits

- `MPDetection/MeetLatch.swift`
  - Accept an optional expiration duration.
  - Apply the age check only when a duration is supplied.
  - Leave positive end evidence and fail-closed handling unchanged.
- `MPDetection/SourceDetectors.swift`
  - Remove the hard-coded four-hour Meet duration and invoke the latch with
    expiration disabled.
- `MPDetection/DetectionScheduler.swift`
  - Remove `maxLatchDuration` from `DetectionTuning` because no production
    detector consumes it.
  - Keep timer tuning and active/idle scheduling unchanged.
- `MPDetection` tests
  - Add a regression that advances beyond four hours while a matching live tab
    remains and asserts `.active`.
  - Add detector coverage showing a temporary `.unknown` can recover to
    `.active`.
  - Retain coverage that a closed or navigated tab releases after a completed
    authoritative scan.
  - If the optional latch-expiration hook remains, keep one focused unit test
    proving an explicitly supplied duration still fails closed to `.unknown`;
    production behavior must not use it.
- Detection documentation
  - Update the authoritative Meet detection specification and implementation
    notes to remove the production four-hour cutoff and describe positive
    liveness/end evidence.

No changes are needed in `StatusReducer`, `SyncCoordinator`, the owner UI, the
viewer, Supabase, or user-facing strings.

## Data flow

```text
Chrome AX snapshot
  -> MeetSelectors
       -> strong anchors + live anchors + scan completeness
  -> GoogleMeetDetector visibility policy
  -> MeetLatch (no production time expiry)
       -> active / unknown / inactive / sourceAbsent
  -> DetectionScheduler end settling
  -> StatusReducer
  -> SyncCoordinator heartbeat and change-triggered publish
```

## Error handling

- Permission revocation continues to invalidate the latch and publish
  `.unknown` with permission-denied health.
- A missing or terminated Chrome process continues to release to
  `.sourceAbsent`/`.inactive` as currently defined.
- Incomplete or unreadable Accessibility data never becomes `.inactive` or
  `.available`.
- A tab/window that cannot be positively verified remains unavailable until a
  later sample provides strong or liveness evidence.
- Strong confirmation and verified liveness remain local-only; no meeting title,
  URL, participant, or AX content is synchronized.

## Tests and acceptance criteria

The existing MPDetection test suite must prove:

1. A confirmed Meet call remains `.active` after 14,400 seconds when its
   anchored Chrome window and tab are still present.
2. A temporary unavailable observation can recover to `.active` after a later
   strong or liveness-confirming sample.
3. Closing or navigating away from the anchored tab still releases to
   `.inactive` after authoritative evidence and normal scheduler settling.
4. Explicitly configured latch expiration, if retained as a reusable policy,
   returns `.unknown` rather than `.inactive`; Google Meet does not configure
   that policy.
5. Existing presenter-control, background-tab, multiple-window, permission,
   and scheduler behavior remains green.

Acceptance is met when an active Google Meet lasting longer than four hours
does not become unavailable solely because of elapsed time, while a definitive
Meet end still reaches the existing available result after settling.
