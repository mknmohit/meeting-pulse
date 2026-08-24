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
