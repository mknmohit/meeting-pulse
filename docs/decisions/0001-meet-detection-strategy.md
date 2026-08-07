# Decision 0001: Google Meet detection strategy

## Gate G1 result

Spike S1 was run twice against Google Chrome `151.0.7922.76` on macOS. The
second run covered a fresh active call, background tab, app background,
minimization, clean end, two simultaneous calls, and notification watching.
The observed fallback-ladder result is **rung 2**:

> Q1 = no for the active-call surface when the Meet tab is backgrounded, Q2 =
> yes for a stable tab-strip entry, and Q3 = yes because closing that tab
> removes the entry while the Chrome window remains.

The active-call controls were visible in the Meet `AXWebArea` in the main
Chrome window. When another tab or another app was frontmost, the active-call
web area and controls were no longer readable, but the Meet tab entry remained
observable. The direct foreground algorithm therefore confirms a session, and
the latch maintains it from tab and window liveness. When the window was
minimized, the web area and controls remained readable.

The controls were below the plan's original application-level depth-14 sample
on this Chrome build. The tool now defaults to depth 20. The detector must
find the candidate `AXWebArea` first and then scan that subtree, so its
per-subtree depth cap remains bounded rather than relying on a global depth
20 traversal.

## Observed selectors

All selectors are scoped to one module and are versioned by this decision.

### Strong confirmation

- An `AXWebArea` with role description `HTML content` in a Chrome window.
- A descendant `AXGroup` with role description `region`, subrole
  `AXLandmarkRegion`, and description `Call controls`.
- Descendant `AXButton` elements with role description `button` and
  descriptions `Leave call` and `Share screen`.

No useful `AXIdentifier` was exposed in the captures. The descriptions are
treated as corroborating signals, never as a title-only confirmation. A
missing, localized, or otherwise unrecognized signal produces `unknown`.

### Liveness

- `_AXUIElementGetWindow` is available and returned stable `CGWindowID` values
  during repeated traversals. The main Chrome window number stayed stable while
  its tab list changed.
- The tab strip exposes `AXRadioButton` elements with subrole `AXTabButton`.
- The tab identity is the normalized, locally hashed tab description. The
  traversal path is not used because it changes when tabs move.
- Closing the Meet tab removed its tab entry while the Chrome window remained.

The anchor is therefore `{ windowID, hashedTabIdentity, confirmedAt }`. The
hash never leaves the Mac.

The two-call capture found two independent anchors, window numbers 4367 and
1719. Ending the call on one window left exactly one `Leave call` control and
the other window's anchor. The latch must therefore keep a set, not one
anchor.

## PWA support

No Chrome-installed Meet PWA was present in `/Applications` or
`~/Applications` during the spike. The MVP detector supports the observed
`com.google.Chrome` family only. A PWA is manual-only until a future spike
observes its bundle and AX tree. It is never guessed as a Chrome call.

## Notifications

The development watcher received `AXWindowCreated`, `AXValueChanged`,
`AXSelectedChildrenChanged`, and `AXUIElementDestroyed` events while Chrome
changed. Exact latency was not measured, so safety samples remain mandatory.

## Conservative boundaries

The detector must emit `unknown` when it cannot read the active-call surface
or verify the anchored window and tab. A missing liveness signal is never
treated as an ended call. The clean end capture removed the call-controls
region while leaving the Meet web area and tab entry, so end detection must
require positive end evidence or a missing anchor, not merely a missing
control.
