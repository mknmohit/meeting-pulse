# Decision 0002: Slack Huddle detection strategy

## Gate G2 result

Spike S2 was run against Slack `4.51.180` on macOS. A reliable signal exists,
so Slack Huddle auto-detection ships in the MVP.

Follow-up capture against Slack `4.51.191` found the same strong controls
embedded in a standard channel window, so both layouts are supported.

The signal is either a dedicated Huddle window or an embedded Huddle surface
in a standard Slack window. Slack's ordinary main window, focused state,
`Huddles` row, and `Start huddle with ...` button are not signals of an active
Huddle.

## Observed selectors

All selectors are scoped to one module and are versioned by this decision.

### Strong confirmation

- A second `AXWindow` with an `AXStandardWindow` subrole and a title beginning
  with `Huddle:`.
- Inside that window, an `AXWebArea` with the same Huddle title.
- An `AXToolbar` described as `Huddle window actions` or `Huddles actions`.
- A descendant `AXButton` described as `Leave Huddle`.
- In Slack releases that embed the Huddle in the channel window, an
  `AXStandardWindow` with the same toolbar and leave-button pair is sufficient
  even when its title is an ordinary channel title.

No `AXIdentifier` was exposed. The detector requires the Huddle toolbar and
leave control in the same standard window; the dedicated-window title remains
an additional signal for the legacy layout. A missing or localized signal
produces `unknown`; it never falls back to "Slack is open" or "Slack was
recently used".

The main Slack window exposed `Leave huddle` / `Leave Huddle` while the Huddle
was active. In the embedded layout, its `Huddles actions` toolbar and
`Leave Huddle` button form the primary signal. The dedicated window remains
supported as the primary signal for the legacy layout.

### Liveness

The dedicated Huddle window had window number `4467`; the main Slack window
had window number `1241`. Both window numbers and the leave control persisted
when Slack was unfocused and when the Huddle window was minimized.

The Huddle window and all leave controls disappeared after ending the Huddle,
while the main window remained and exposed `Start huddle with ...` again.

The anchor is `{ windowID, confirmedAt }`. The window title is local
diagnostic context only and never leaves the Mac.

## App discovery and absence

Slack is discovered by bundle identifier `com.tinyspeck.slackmacgap`. When
Slack was quit, the AX tool reported no running application for that bundle.
That maps to `sourceAbsent`, not an active or inactive Huddle.

## Notifications

The idle watch run did not emit a useful Huddle transition event, so exact
notification latency is not claimed. Safety sampling and app lifecycle
resampling remain mandatory. The detector must not depend on a notification
that was not observed.

## Conservative boundaries

Before confirmation, an unreadable Huddle signal or a missing member of the
toolbar/leave pair produces `.unknown`. After confirmation, a readable
dedicated window is liveness evidence, so a temporary control or AX-scan gap
preserves `.active`; an embedded window with a missing pair follows the
existing recreation grace. The detector never treats an open, focused,
minimized, or recently used Slack window as a Huddle. If a future Slack release
removes both supported signals, Slack becomes manual-only until another
empirical spike finds a replacement.

## Amendment: current window titles and toolbar labels

Later Slack builds title the detached Huddle window `Huddle` without the
trailing subject, and a window titled `Huddles` is a list view rather than a
live Huddle. The strategy is amended as follows.

- A window title is a Huddle window when it is `Huddle`, starts with
  `Huddle:`, `Huddle -`, `Huddle with`, or `Huddle/`. A title of `Huddles` or
  `Huddles ...` is explicitly rejected, because it is the Huddle list.
- The toolbar description may be `Huddle window actions`, `Huddles actions`,
  `Huddle actions`, `Huddle controls`, or `Huddle toolbar`.
- The leave control is matched on the description or the title attribute and
  accepts `Leave Huddle`, `Leave the huddle`, and `End huddle`.
- Confirmation requires the leave control plus a Huddle window title or a
  Huddle toolbar. The leave button alone is never sufficient, so a stray
  `Leave` button in another part of Slack cannot start a Huddle.

## Amendment: long-running huddles

A Huddle that runs for a long time grows the Slack accessibility tree. The
Slack detector therefore uses the same breadth-first traversal, per-window
element budget, per-role attribute pruning, and graceful truncation as the
Meet detector (see Decision 0001). A truncated scan keeps the partial tree
and reports `scanCompleted == false`; the latch keeps the Huddle `active`
when a live anchor is still present and returns `unknown` only when no anchor
can be read at all.

## Amendment: faster and recoverable huddle ends

Leaving a Slack Huddle took around thirty seconds for the app to report "no
meeting". The end path was a twenty second window-recreation grace followed by
a two sample settle, and the detector could additionally sit in a permanent
`.unavailable` state after a space change. The strategy is amended as follows.

### Shorter recreation grace

The recreation grace is shortened from twenty seconds to five. It only exists
to absorb the brief window churn that Slack produces while the Huddle window
is rebuilt, and five seconds is comfortably longer than that churn. The end
settle then needs two agreeing samples, so a Huddle end is published roughly
ten to fifteen seconds after the user leaves.

### Recoverable unavailability

A space change expires the transition grace and used to leave the detector
permanently `.unavailable`, which surfaced as "unavailable" until the app was
restarted. `.unavailable` is now recoverable. When the Huddle window is still
present the state resolves to `.active`, and when the scan completed and the
window is gone it resolves to `.inactive`. A forty-five second backstop
resolves any remaining ambiguity in favour of "no meeting".

### Unknown is not a vote

The scheduler treats `.unknown` as "this sample could not tell" rather than as
an observation: it never flips a confirmed `.active` Huddle on its own and
never cancels an end that is already settling (see Decision 0001). A definite
end still requires two agreeing samples.

### The title-only hold stays unbounded

The detached Huddle window may keep its `Huddle` title after the user leaves,
because Slack keeps the window around for a while. The title-only hold is
therefore deliberately unbounded for a long-running Huddle; the controls and
the window themselves are what end it, not the title.

