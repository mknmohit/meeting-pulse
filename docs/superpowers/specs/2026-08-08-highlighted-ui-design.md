# Meeting Pulse highlighted UI design

**Date:** 2026-08-08

**Status:** Approved by delegated autonomous execution

## Goal

Improve the highlighted mode selector and lower sidebar surface in the Station
window without changing the existing labels, actions, data flow, or app
information architecture. The controls should read as a quiet signal
instrument: the current mode and publishing state should be obvious at a
glance, while the rest of the rail stays calm.

## Scope

Production changes are limited to:

- `mac-app/Packages/MPUI/Sources/MPUI/Mast/ModeControl.swift`
- `mac-app/Packages/MPUI/Sources/MPUI/Station/StationWindow.swift`
- `mac-app/Packages/MPUI/Sources/MPUI/Mast/PublishRail.swift`

No route, store, action protocol, copy catalogue, or backend behavior changes
are included. No production files are deleted.

## Visual direction

Use a component-scope Hallmark treatment inside the existing marine-enamel
system:

- Reuse `MPColor`, `MPFont`, `MPSpace`, and `MPRadius`; do not add a second
  palette or font system.
- Keep the sidebar as a persistent 288pt rail.
- Remove the default macOS `List` selection treatment from the navigation
  surface.
- Treat navigation and publishing as one anchored lower-left signal dock, not
  two unrelated surfaces.
- Use brass only as a signal accent: selected mode, active navigation marker,
  focus/attention states, and non-idle publish status.
- Avoid gradients, decorative blobs, extra cards, and new copy.
- Keep motion cut: selection changes do not introduce decorative animation.

## Components

### Mode control

Replace the default segmented `Picker` presentation with a three-cell
`HStack` of buttons. Each cell keeps the existing `Busy`, `Automatic`, and
`Available` labels and invokes the same `PulseActions` calls through the
existing binding logic.

The outer rail is a single dark inset surface. Cells share equal width and a
stable height. The selected cell uses an opaque brass fill with adaptive
ground-colored text, giving the current mode a stronger signal than the
current grey system segment. Unselected cells remain quiet but retain hover,
pressed, keyboard focus, and selected accessibility states. The duration menu
below remains unchanged in behavior and only inherits the improved vertical
rhythm.

### Sidebar navigation

Replace the default `List` with a `ScrollView` and explicit vertical stack of
navigation buttons. This keeps selection binding and section routing unchanged
while making row height, inset, icon alignment, and active treatment
deterministic.

Each row uses the current symbol and title. The selected row receives a low
contrast brass wash and a narrow leading brass marker; the icon and title gain
weight without adding a second container or an icon tile. Each row retains
keyboard focus and a selected accessibility trait.

The rows sit inside one quiet `groundRail` dock surface with a stable inset and
hairline boundary. This makes the lower-left navigation read as a deliberate
instrument panel while preserving the existing four destinations and their
vertical order.

### Publishing footer

Keep `PublishRail` anchored below navigation, but turn the bare line into a
two-layer status track: a muted base track plus the existing state-colored fill.
The footer gets a quiet top separator and stable vertical padding so the line
reads as progress rather than an isolated rule. Add a state-specific SF Symbol
beside the existing label so “Published just now” is an explicit completed
state, while offline, retrying, superseded, never-published, and publishing
states remain distinguishable without relying on color alone. Existing publish
labels and width mapping remain unchanged.

## Data flow and error handling

No new state or I/O is introduced. Mode buttons continue to call
`setBusy`, `setAvailable`, or `clearOverride`; the duration menu continues to
call the existing duration actions. Navigation continues to assign
`store.section`. Publish rendering remains a pure projection of
`PulseStore.publishState`, `store.isOnline`, and the contrast environment.

Async action failures continue through the existing action/store paths. The
visual treatment must not imply success while publishing or hide retry/offline
states.

## Accessibility

- Preserve the visible labels and add selected traits to custom mode and
  navigation buttons.
- Keep the native keyboard focus path; custom styling must not remove focus
  indication.
- Keep the publish footer's state understandable from its text, not color
  alone.
- Maintain system contrast support by using the existing contrast-aware brass
  variants.
- Keep hit areas large enough for comfortable macOS pointer and keyboard use.

## Verification

- Run the existing MPUI package tests.
- Build the MPUI visual review target and inspect the dark watch screen at the
  screenshot size.
- Check selected/unselected mode states, each navigation selection, and publish
  labels for published, retrying, offline, and superseded states.
- Inspect the combined lower-left dock in both dark and light appearance.
- Confirm no unrelated files are changed.
