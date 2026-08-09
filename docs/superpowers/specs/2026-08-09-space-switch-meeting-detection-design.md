# Cross-Space meeting detection design

**Date:** 2026-08-09

**Status:** Approved for implementation

## Problem

Meeting Pulse currently treats a completed Accessibility scan as authoritative
even when macOS has moved the target app to another Space. Chromium and Slack
can expose only windows in the current Space, so a confirmed Meet tab or Slack
Huddle window temporarily disappears from the AX tree during a Space switch.
The detectors then emit `inactive` or `unknown`, and the owner status stops
being busy. Returning to the original Space with the same tab selected may not
produce a Chrome AX notification, so the detector does not rescan until the user
changes tabs.

This is a visibility problem, not meeting-end evidence.

## Research conclusion

The requested repositories and additional open-source implementations were
reviewed, including `obsidian-meeting-detector`, `meetily`,
`Mostrom-LLC/meeting-detector`, `locus`, `record-huddle`, Hammerspoon, yabai,
AltTab, and OptTab.

- `NSWorkspace.activeSpaceDidChangeNotification` is the correct public
  Space-change trigger, but it carries no meeting state.
- Accessibility has no public “window belongs to Space N” attribute.
- `CGWindowListCopyWindowInfo` can provide local metadata but is not a
  reliable modern Space-membership contract; `kCGWindowWorkspace` is
  deprecated.
- ScreenCaptureKit with `onScreenWindowsOnly: false` is the strongest public
  cross-Space window-presence signal, but requires Screen Recording permission.
- Private SkyLight/CGS APIs can map windows to Spaces but are unsupported and
  fragile across macOS releases.
- Existing open-source Slack capture code uses a roughly four-second start
  debounce and sixteen-second stop debounce because Slack recreates Huddle
  windows during UI changes.

Meeting Pulse will keep Accessibility as its only permission. Uncertainty is
handled conservatively rather than by adding a broader capture API.

## Goals and non-goals

### Goals

1. Keep a confirmed Google Meet and Slack Huddle active during normal Space
   transitions and short Slack window recreation periods.
2. Trigger a rescan when switching Spaces, including when the Meet tab is
   already selected on return.
3. Prevent a temporary off-Space AX omission from becoming `inactive` or
   `available`.
4. Preserve positive end detection and immediate app-termination handling.
5. Keep detection local, bounded, and compatible with the existing memory and
   privacy constraints.

### Non-goals

- Screen Recording or microphone permissions.
- Private SkyLight/CGS APIs.
- Title-only Slack or Chrome detection.
- Changing the remote status schema, viewer freshness, or manual overrides.
- Guaranteeing exact meeting-end detection while the source window remains
  permanently inaccessible on another Space. That case becomes unavailable
  after the continuity bound.

## Approaches considered

### 1. Space notification plus per-source continuity latches (chosen)

Observe the public Space-change notification, debounce and resample both
detectors, and keep previously confirmed sessions active through a bounded
visibility gap. Meet retains its existing window/tab anchor. Slack gains a
small latch keyed by Slack PID and Huddle window ID. This requires no new
permission, directly addresses both reported cases, and fails closed after the
bound.

### 2. CGWindowList metadata corroboration

Use owner PID and window ID metadata from `CGWindowListCopyWindowInfo` to
distinguish a hidden window from a closed window. This can improve evidence
when available, but it cannot prove call state, has inconsistent cross-Space
behavior, and must not rely on deprecated `kCGWindowWorkspace`. It remains a
possible future corroborator, not the source of truth.

### 3. ScreenCaptureKit or private SkyLight enumeration

ScreenCaptureKit can enumerate windows across Spaces when Screen Recording is
granted, while private SkyLight APIs can expose Space membership without a
user-facing prompt. Both expand risk: one changes the privacy contract and the
other depends on unsupported OS internals. Neither is appropriate for this
fix.

## Architecture

```text
NSWorkspace activeSpaceDidChange
              │
              ▼
      WorkspaceSpaceChangeSource
              │  debounce 300 ms + settle resample
              ▼
       DetectionScheduler
          │           │
          ▼           ▼
   Meet continuity  Slack continuity
       latch           latch
          └──────┬──────┘
                 ▼
         StatusReducer / sync
```

### Space-change source

Add an injected `SpaceChangeSource` seam with a live implementation backed by
`NSWorkspace.shared.notificationCenter` and a fixture implementation for tests.
The scheduler starts and stops the observer with its own lifecycle.

Each notification:

1. Marks both detectors as entering a Space-transition visibility state.
2. Coalesces additional notifications.
3. Requests a sample after approximately 300 ms.
4. Requests a second sample approximately 700 ms later, after AX trees have
   repopulated.

The notification is never treated as evidence that a meeting exists or ended.

### Meet continuity

Extend Meet evidence with a visibility confidence:

- `authoritative`: normal AX scan; current tree may establish active or
  inactive.
- `transitionGrace`: a previously confirmed anchor is temporarily absent
  during the bounded Space transition; retain active.
- `unavailable`: the grace bound expired without re-observation; return
  `unknown`, retain the anchor for a future positive re-observation.

The existing `{windowID, hashed tab identity}` anchor and multi-call support
remain unchanged. A strong Meet scan clears transition state immediately.
Chrome termination still releases to inactive. The existing four-hour latch
expiry remains a final safety valve and returns `unknown`.

### Slack continuity

Add a `SlackHuddleLatch` value type keyed by Slack PID and Huddle window ID.
It accepts active evidence only from the existing dedicated standard window,
Huddle title, toolbar, and Leave Huddle control.

- A strong observation creates or refreshes the latch.
- During Space transition or short Slack window recreation, a missing AX window
  retains active for the same bounded grace.
- Slack termination releases to `sourceAbsent`.
- A settled, authoritative scan with no Huddle releases to inactive.
- A Space-transition grace expiry returns `unknown`; a Slack-only window
  recreation grace expires back to authoritative end evaluation so a genuine
  Huddle end can settle to inactive.

The scheduler continues to apply the existing two-sample end settling after a
detector has produced authoritative non-active evidence.

### Detector protocol

Add a `spaceDidChange()` lifecycle hook to the detector seam. The scheduler
calls it for both sources; Slack uses it to enter latch grace and Meet uses it
to update visibility confidence. Test detectors implement the hook without
platform dependencies.

## Error handling and privacy

- Space changes without a prior active session do not change status.
- Accessibility denial remains `unknown`.
- App termination remains `sourceAbsent` and may settle to available.
- Missing AX windows during transition remain active only within the bounded
  continuity window; after that they are `unknown`.
- No window title, URL, participant, audio, video, screenshot, or screen
  content leaves the Mac.
- No new TCC permission is requested.

## Testing

Add focused tests for:

1. Space-change notification coalescing and the two resample points.
2. Meet active continuity when Chrome’s current-space snapshot has no live
   anchor.
3. Meet transition expiry becoming unknown rather than inactive.
4. Slack active continuity when its Huddle window is temporarily absent.
5. Slack termination and authoritative end behavior.
6. Returning to a Space with the Meet tab already selected reactivating from
   the resample without an AX tab-switch event.
7. Scheduler behavior with no active source and no Space event.

Run the existing MPDetection tests, the macOS Debug/Release builds, and the
live AX probe on a Mac with Chrome and Slack. Real Space-switch acceptance
remains a manual test because the OS compositor and application trees must be
involved.
