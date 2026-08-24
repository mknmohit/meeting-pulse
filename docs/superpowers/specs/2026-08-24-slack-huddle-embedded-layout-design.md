# Slack Huddle embedded-layout detection design

**Date:** 2026-08-24

**Status:** Approved for implementation

## Problem

The current Slack detector only confirms a Huddle from a dedicated standard
window whose title starts with `Huddle:`. The current Slack release can render
an active Huddle inside the ordinary channel window instead. That window
contains the `Huddles actions` toolbar and a `Leave Huddle` button, but its
title is a normal Slack channel title, so the detector reports Slack as
inactive and the status is not updated to busy.

## Goals

- Recognize active Huddles in both the legacy dedicated-window layout and the
  current embedded channel-window layout.
- Keep detection strict enough that an idle Huddles row or
  `Start huddle with ...` control cannot confirm a Huddle.
- Preserve the existing active-session latch, long-call behavior, recreation
  grace, end settling, status vocabulary, and publication flow.
- Keep all detection local to the Accessibility tree.

## Non-goals

- Do not add Slack APIs, permissions, network requests, audio signals, or UI
  strings.
- Do not treat Slack being open, focused, recently used, or showing a Huddles
  row as an active Huddle.
- Do not change Google Meet detection or shared status-reduction behavior.

## Selector design

`SlackSelectors` will define one Huddle-window predicate used by presence and
confirmation:

1. The node is an `AXWindow` with `AXStandardWindow` subrole.
2. It is a candidate when either its normalized title starts with `huddle:`
   (legacy dedicated window) or it contains both:
   - an `AXToolbar` described as `Huddle window actions` or `Huddles actions`;
   - an `AXButton` with button role description and description `Leave Huddle`
     (case and whitespace normalized).

The toolbar and leave control must be descendants of the same window. The
existing exact label matching and normalization remain in use. A titled
dedicated window with temporarily missing controls retains the existing
liveness behavior. An embedded channel window is a candidate only while the
toolbar/leave pair is present; if that pair disappears, it follows the
existing recreation grace rather than gaining a broader heuristic. Neither
layout can create a new strong anchor without both controls.

Strong anchors continue to use the process identifier and candidate window
number. The detector's `huddleWindowPresent` value will use the unified
candidate set, so embedded Huddles participate in the existing recreation
grace and end detection.

## Data flow

```text
Slack AX snapshot
  -> SlackSelectors (dedicated or embedded active window)
  -> SlackHuddleDetector
  -> SlackHuddleLatch (.active / .inactive / .sourceAbsent)
  -> DetectionScheduler
  -> StatusReducer (.busy)
  -> SyncCoordinator publication and menu-bar/viewer state
```

No public observation or status model changes are required.

## Error handling

- Permission denial and unreadable/incomplete scans retain current health and
  fail-closed behavior.
- Slack termination remains `.sourceAbsent`.
- A Huddle is confirmed only by the strict toolbar/leave pair.
- A missing candidate window follows the existing recreation grace and
  scheduler end-settling rules; no new immediate end path is introduced.
- No uncertain or ordinary Slack state becomes `.active`.

## Tests

Add selector fixtures/tests for:

- an embedded active Huddle in a normal standard channel window;
- the existing dedicated Huddle window;
- an idle Huddles row and start-huddle button without the active pair;
- a toolbar or leave control alone without its required counterpart.

Add detector coverage proving the embedded snapshot becomes `.active`, remains
active through the existing grace/latch behavior, and reaches `.inactive` after
the embedded controls disappear and the existing grace expires. Preserve the
long-running Huddle and Slack termination regressions.

## Acceptance criteria

- While the current Slack embedded Huddle controls are present, the detector
  reports `.active` and the app publishes the existing busy status.
- The legacy dedicated Huddle window remains recognized.
- Ordinary Slack and start-huddle UI do not trigger busy status.
- Ending an embedded Huddle still settles through the existing grace and
  debounce behavior.
- No status strings, privacy boundaries, or Meet behavior change.
