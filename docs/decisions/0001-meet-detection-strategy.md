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

## Amendment: long-running calls and localized controls

A call that runs for a long time grows the Meet accessibility tree: chat
messages, participant rows, and menu content accumulate under the same web
area. The first implementation spent its whole element budget walking that
growing tree depth-first and then failed the entire snapshot with
`treeTooLarge`, so the latch dropped to `unknown` and the app reported
"unavailable" for meetings that were still running. The strategy is amended
as follows.

### Breadth-first traversal with per-window budgets

- The tree is walked breadth-first so the shallow call controls and the tab
  strip are reached before the budget is spent on deep page content.
- Each top-level window receives its own element budget
  (`min(maxElements, max(maxElements / windowCount, 2_000))`), so one busy
  window can no longer starve the others.
- A window-discovery pass reads only roles and children and does not descend
  into a window, which keeps discovery cheap for applications that expose
  many windows.
- Attributes are read per role: containers read the full attribute set, list
  and row roles read title and description, text roles read the title, and
  every other role reads nothing. Each attribute read is an XPC round trip,
  so pruning is what keeps a scan inside its latency budget.

### Graceful truncation

A scan that exhausts its budget keeps the partial tree instead of discarding
the snapshot. The snapshot then reports `scanCompleted == false`, which the
latch treats as "not disproved": a truncated scan that still finds a live
anchor keeps the call `active`, and a truncated scan that finds no anchor at
all returns `unknown`. The call is only ended by positive end evidence or a
missing anchor, as required above.

### Broadened call-control signals

Confirmation no longer depends on the `Call controls` landmark region, which
is not exposed by every Chrome build or localization.

- The leave control is matched on the description or the title attribute and
  accepts `Leave call`, `Leave the call`, `Leave meeting`, `End call`, and
  `Ends the current call`.
- Confirmation requires the leave control plus at least one other in-call
  control (`Share screen`, `Turn on microphone`, and similar call-only
  labels, or a control whose description ends with `is presenting`).
- A web area is accepted when it is hosted by a window that also exposes a
  Meet tab, even when the web area title is not a Meet title. In that case
  the identity falls back to a local hash of the web area title, which is
  still stable for the lifetime of the call and never leaves the Mac.
- The tab strip is scanned before the web areas, so the anchor survives even
  when the call surface itself is not readable.

## Amendment: readable surface as positive end evidence

Ending a Google Meet call from the picture-in-picture popover left the app
stuck on "Meeting status unavailable". The unified log showed a single Meet
sample of `unknown` — the call controls had already gone, but the snapshot was
taken while Chrome was still tearing the surface down — and one such sample was
enough to surface "unavailable". The strategy is amended as follows.

### A readable surface is end evidence

The Meet web area keeps exposing its rendered content even while Chrome is in
the background, so a web area that is still present and still readable but no
longer carries any call control is positive evidence that the call is over.
That is the normal end of a call: the page is still there, the controls are
not. The detector therefore computes two independent surface facts:

- `meetSurfaceReadable` — a Meet web area was found and its children were
  actually read (`childCount > 0`).
- `meetSurfaceAbsent` — the scan completed and no Meet web area and no Meet
  tab entry remain at all.

A readable surface with no call controls ends the call. An absent surface ends
the call. Only a surface that is present but unreadable stays ambiguous, and
that ambiguity is resolved by the backstop below.

### Unknown is not a vote

The scheduler no longer lets a single `.unknown` sample flip a confirmed
`.active` call to `.unknown`. `.unknown` means "this sample could not tell",
so it never publishes on its own and never cancels an end that is already
settling. It becomes visible only after it repeats while the value is not
`.active`. A definite end still needs two agreeing samples, so a transient
miss neither hides a running call nor invents a finished one.

### Recoverable unavailability

A space change expires the transition grace after twenty seconds and used to
put the detector permanently into `.unavailable`, which the latch reported as
`.unknown` and the app rendered as "unavailable" for the rest of the session.
`.unavailable` is now recoverable: when the scan completed and the surface is
readable or absent, the call resolves to a definite end instead of staying
unknown. A forty-five second backstop resolves any remaining ambiguity in
favour of "no meeting", so the state always converges.

### The application root is read once

The snapshot builder used to read the `kAXChildren` attribute of the
application root twice — once to count children and once to enqueue them. The
application root is not exempt from the benign-failure rules, so a transient
`kAXErrorCannotComplete` on that second read discarded the whole snapshot and
reported the scan as incomplete, which the latch reads as "not disproved" and
keeps the call active, or as unknown when no anchor was found. The root's
children are now read exactly once: the root payload carries the child count
and the traversal continues from the already-read children.

### Volatile tab identity

Every Chrome tab carries a ` - Memory usage - N.N MB` suffix on both its title
and its description, so the hashed tab identity changes continuously and can
no longer be used to match a previously confirmed call to a tab. The identity
is deliberately left volatile: a stable identity would pin a tab as "the call"
forever, and the end of a call is proven by the readable surface instead.

