# Meeting detection reliability and memory design

**Date:** 2026-08-09

**Status:** Approved for autonomous implementation

## Context

Meeting Pulse currently uses macOS Accessibility snapshots to detect Google Meet
in Chrome and native Slack Huddles. The recent snapshot-memory change introduced
an invalid tree reconstruction: a pre-order traversal is stitched back
together by assuming every node's direct children are contiguous, but nested
descendants occupy that range too. The unused `parentIndex` is evidence that
the intended parent relationship was never applied. Chrome and Slack trees can
therefore lose the tab, window, or control node that the selectors need.

There is also a scheduler bootstrap gap. Each detector performs its first
sample before `DetectionScheduler` subscribes to its observation stream. The
first observation is lost, and later samples only emit when the detector's
value changes. A meeting that is already active when Meeting Pulse starts can
therefore leave the scheduler at `unknown` indefinitely.

Finally, `AXNode` stores a flattened array of complete `AXNode` values at every
node. That retains repeated references to large subtrees for the lifetime of a
snapshot and creates avoidable allocation pressure during selector scans.

## Research findings

The online review covered the requested repositories and additional open-source
detectors:

- [obsidian-meeting-detector](https://github.com/yut0takagi/obsidian-meeting-detector)
  polls browser tabs and process presence. Its Google Meet match is useful as a
  fallback but treats a matching tab as active without call-state
  corroboration.
- [meetily](https://github.com/Zackriya-Solutions/meetily) exposes explicit
  recording commands; current community code does not implement meeting
  detection. Its advertised auto-join behavior is a Pro feature.
- [Mostrom-LLC/meeting-detector](https://github.com/Mostrom-LLC/meeting-detector)
  combines browser identity with recent TCC/media signals and uses stale-signal
  expiry and debounced lifecycle events.
- [vinitkumargoel/locus](https://github.com/vinitkumargoel/locus) uses
  `NSWorkspace` reconciliation plus per-process CoreAudio activity with a
  short start debounce.
- [goyan/record-huddle](https://github.com/goyan/record-huddle) finds Slack
  Huddle windows through ScreenCaptureKit and uses asymmetric start/stop
  debouncing because Slack can keep the microphone warm after a huddle ends.
- [f18m/macos-meeting-detector-mqtt](https://github.com/f18m/macos-meeting-detector-mqtt)
  demonstrates that a global microphone-running flag is only a corroborating
  signal; it does not identify a platform or meeting.

The strongest common design is an identity-specific signal, a bounded scan,
and an explicit lifecycle state machine. Meeting Pulse will keep its existing
Accessibility-only privacy boundary rather than adding microphone, audio, or
Screen Recording permissions.

## Goals and non-goals

### Goals

1. Detect a confirmed Google Meet call in Chrome while the Meet tab is
   foreground, background, or the window is not focused.
2. Detect an active native Slack Huddle through its dedicated huddle window and
   controls, including common title/label variants.
3. Seed the scheduler from detector state at startup and after every explicit
   sample request, so no initial or unchanged observation is lost.
4. Preserve fail-closed behavior: permission loss, unreadable trees, and
   truncated/unrecognized structures remain `unknown`, never `inactive`.
5. Bound snapshot work and reduce retained/transient memory without retaining
   meeting titles, URLs, participants, audio, screenshots, or screen contents.

### Non-goals

- AppleScript browser automation or browser extensions.
- Microphone/audio capture or CoreAudio activity as a source of truth.
- ScreenCaptureKit or Screen Recording permission.
- Calendar, process-name-only, focused-app-only, or browser-tab-only
  detection.
- Replacing the existing status reducer, sync protocol, or viewer behavior.

## Approaches considered

### 1. Repair the Accessibility pipeline (chosen)

Restore a correct bounded AX tree builder, make descendant traversal
on-demand, broaden only the structural Meet/Slack predicates that are known to
vary, and seed scheduler state explicitly. This preserves the product's
permission and privacy contract, fixes both likely regressions, and has the
lowest idle resource cost.

### 2. Add microphone/process corroboration

Use `NSWorkspace` and per-process CoreAudio activity as a second signal, with
debounce and expiry. This can reject stale Meet tabs and improve some native
app cases, but it introduces new permission/availability assumptions and is
not sufficient for Slack by itself. It is deliberately not part of this fix.

### 3. Use ScreenCaptureKit for Slack windows and browser automation for Meet

Window enumeration is a proven Slack fallback and AppleScript can identify
Meet URLs, but this adds Screen Recording/Automation prompts, larger runtime
surface area, and more idle work. It conflicts with Meeting Pulse's documented
Accessibility-only boundary.

## Architecture and data flow

```text
AXRunLoopHost (one CFRunLoop thread)
        │
        ├── bounded AXSnapshot value tree
        │       └── on-demand traversal
        │
        ├── GoogleMeetDetector ──┐
        └── SlackHuddleDetector ─┤
                                  ▼
                         DetectionScheduler
                         ├── current-state bootstrap
                         ├── event/poll sampling
                         └── end settling
                                  ▼
                           StatusReducer / sync
```

### Snapshot representation

`AXNode` will retain only its own attributes and direct `children`. The stored
flattened `descendants` array will be removed; a bounded iterative visitor and
an on-demand compatibility accessor will preserve traversal behavior without
retaining duplicate subtree values. Selectors will use the visitor directly,
so a scan does not allocate a full flattened copy.

The AX builder will use a depth-limited, element-limited traversal that
preserves direct-child relationships. A depth cap of 20 and the existing
3,000-element detector budget remain the live defaults. Attribute strings remain
bounded to the existing 120-character limit. Any AX error continues to mark a
scan degraded; it is never converted to `inactive`.

### Google Meet

The detector will continue to require a Chrome-family process and a strong
in-call structural match:

- an `AXWebArea` representing Meet;
- the in-call call-controls region;
- leave-call/leave-meeting and share/present controls; and
- a matching tab-strip entry in the same window.

Matching is case-insensitive and whitespace-normalized, with narrowly scoped
known label variants. The latch continues to key on window ID plus a hashed tab
identity, supports multiple simultaneous calls, maintains an anchored tab when
the web area is backgrounded, and expires to `unknown` rather than guessing.

### Slack Huddles

The detector will inspect only the native Slack bundle. A candidate must be a
standard Slack window whose title identifies a Huddle (case-insensitive
contains/prefix matching), and it must expose a huddle-specific leave/end
control. Toolbar descriptions are accepted as corroboration but are not the
only signal, because Slack/Electron accessibility labels vary between releases.
Slack being open, focused, or recently used remains insufficient.

### Scheduler bootstrap

The scheduler will attach stream consumers before detector startup and also
ingest each detector's `currentObservation` after `start()` and after an
explicit sample request. This makes startup state deterministic even when a
detector emitted before a consumer was ready and keeps unchanged samples
visible to the scheduler. Existing two-sample end settling remains in the
scheduler only.

## Error handling and privacy

- Accessibility denial publishes `.unknown` with permission health.
- An absent Chrome/Slack process publishes `.sourceAbsent`.
- A complete scan with no source-specific match publishes `.inactive`.
- A failed, truncated, or unrecognized relevant scan publishes `.unknown`.
- No detector stores or publishes URLs, meeting names, participants, audio,
  video, screenshots, or screen contents.
- No new privacy permission is requested.

## Testing and validation

Add focused tests for:

1. scheduler startup with detectors whose first active/inactive samples occur
   before stream consumption;
2. unchanged detector state being ingested after an explicit sample;
3. nested AX trees preserving all direct children and descendant traversal;
4. Meet control/tab variants and background-tab liveness;
5. Slack Huddle title and leave-control variants;
6. malformed/incomplete scans remaining `unknown`.

Run the existing MPDetection Swift package tests, then the existing macOS
debug/release build command when the local Xcode toolchain is available. Use
the existing `axdump`/`axhost-probe` tools for a real-machine smoke check; no
fixture or diagnostic output may contain raw meeting content.

