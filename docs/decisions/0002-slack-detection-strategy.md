# Decision 0002: Slack Huddle detection strategy

## Gate G2 result

Spike S2 was run against Slack `4.51.180` on macOS. A reliable signal exists,
so Slack Huddle auto-detection ships in the MVP.

The signal is a dedicated Huddle window. Slack's ordinary main window,
focused state, `Huddles` row, and `Start huddle with ...` button are not
signals of an active Huddle.

## Observed selectors

All selectors are scoped to one module and are versioned by this decision.

### Strong confirmation

- A second `AXWindow` with an `AXStandardWindow` subrole and a title beginning
  with `Huddle:`.
- Inside that window, an `AXWebArea` with the same Huddle title.
- An `AXToolbar` described as `Huddle window actions` or `Huddles actions`.
- A descendant `AXButton` described as `Leave Huddle`.

No `AXIdentifier` was exposed. The detector requires the dedicated Huddle
window plus the leave control. A missing or localized signal produces
`unknown`; it never falls back to "Slack is open" or "Slack was recently used".

The main Slack window also exposed `Leave huddle` / `Leave Huddle` while the
Huddle was active. That is corroboration only. The dedicated window is the
primary signal because it remains distinct from normal Slack content.

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

The detector emits `.unknown` if the dedicated Huddle window or leave control
cannot be read. It never treats an open, focused, minimized, or recently used
Slack window as a Huddle. If a future Slack release removes the dedicated
window signal, Slack becomes manual-only until another empirical spike finds a
replacement.
