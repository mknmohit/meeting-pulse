# Live manual override countdown

**Date:** 2026-08-09

**Status:** Approved design

## Context

The menu bar can set Busy or Available for a fixed duration. The Station
already derives a remaining-minute message from `overrideExpiry`, but that
message is calculated only when the view is recomputed. It therefore does not
visibly count down while the Station remains open, and the menu bar does not
make the endpoint clear enough at a glance.

The owner wants the menu bar and Station to communicate the end of a timed
override without adding another timer or persistence format.

## Goals

- Keep the menu bar message compact while a timed Busy or Available override is
  active.
- Show the localized end time and a full remaining minutes/hours description in
  the Station.
- Refresh both presentations while they are visible.
- Apply the same compact menu-bar behavior to the legacy menu-bar path.
- Preserve the existing automatic, indefinite, setup, error, and expiry
  behavior.

## Non-goals

- Do not change the available duration choices or their defaults.
- Do not add backend fields, database migrations, or a new persisted timer.
- Do not replace the monotonic expiry task in `ManualOverrideStore`.
- Do not change the menu-bar icon artwork or status-color mapping.
- Do not add notifications when an override expires.

## Considered approaches

### A. Shared derived countdown (selected)

Use the existing wall-clock expiry as the source of truth and compute display
copy from it at render time. A small presentation parameter distinguishes the
compact menu-bar copy from the detailed Station copy. SwiftUI
`TimelineView` refreshes the derived text about every 30 seconds while a
surface is visible. This adds no observable ticking state and keeps expiry
ownership in `ManualOverrideStore`.

### B. Store-level remaining value

Add a published remaining-seconds value and a task that updates it. This makes
the value available to every consumer, but introduces another lifecycle,
restart, and cancellation path for state that is already derivable from the
stored expiry.

### C. Fixed end time only

Format the expiry once as a clock time. This is simple, but it does not meet the
request for a visible remaining minutes/hours value in the Station.

Approach A is selected because it reuses the existing expiry contract, keeps
the UI live without a second timer owner, and limits the behavioral change to
the two requested surfaces.

## Experience and copy

For a timed override, the menu bar uses a compact status line:

- `Busy - 29m`
- `Available - 1h 29m`

The Station Mast uses a detailed status line with the user's localized short
time format:

- `Busy until 1:34 AM - 29 minutes remaining`
- `Available until 2:34 AM - 1 hour 29 minutes remaining`

Remaining units use ceiling so the UI never claims less time than is actually
left. A value below one minute is presented as `less than a minute remaining`.
An override without an expiry keeps the existing `Busy until you clear it` or
`Available until you clear it` copy. All non-override reason-line priorities
remain unchanged.

## Architecture and data flow

1. `overrideExpiry` remains the source of truth in the native `PulseStore`, and
   `ManualOverride.expiresAtWall` remains the source of truth for the legacy
   model. No sync payload or persistence shape changes.
2. Extend the existing `ReasonLineBuilder` with a presentation surface and a
   `now` input. Its shared duration formatter produces compact menu-bar copy
   and detailed Station copy from the same expiry.
3. Keep `PulseStore.reasonLine` as the Station-facing default and add a
   menu-bar-facing projection that uses the compact surface. Existing callers
   that need the current generic/diagnostic reason behavior continue to use the
   default projection.
4. Render the native `MenuBarContent` and `MastView` reason lines inside a
   periodic `TimelineView`. The timeline passes its current date to the pure
   projection; it does not mutate `PulseStore`.
5. Update the legacy `MenuBarView` to feed its manual override through the same
   compact projection. Its existing connection and action rows remain
   unchanged.
6. When the existing `ManualOverrideStore` expiry task clears an override,
   the current `overrideDidChange` path resets the mode and both surfaces return
   to automatic copy.

## Error handling and edge cases

- A missing expiry is treated as an indefinite override and uses the existing
  copy.
- Remaining time is clamped at the lower display boundary; negative durations
  are never shown.
- If an expiry crosses a local time-zone or daylight-saving transition, the
  end time is formatted from the current locale at render time while the
  existing expiry task remains authoritative.
- If the runtime or sync path fails, existing error state and rollback behavior
  remain responsible for the visible status. The countdown projection does not
  swallow or reinterpret those errors.
- At expiry, the existing automatic transition wins over stale timeline text.

## Accessibility and visual behavior

- Countdown text remains real text in both surfaces, so VoiceOver receives the
  same remaining duration a sighted user sees.
- The menu bar keeps its existing headline, action order, and compact width.
- The Station keeps its existing Mast location, font, color, line limit, and
  reduced-motion behavior.
- No color, icon, animation, or menu ordering changes are introduced.

## Validation

- Add pure formatter tests for timed Busy and Available values on both
  presentation surfaces, including hour formatting, the sub-minute boundary,
  indefinite overrides, and expired values.
- Preserve the existing reason-line priority tests for permission, sync,
  viewer-link, and automatic states.
- Build and run the existing MPCore, MPSupport, and MPUI package tests.
- Inspect the native Station and menu-bar dropdown in the existing visual
  review target, including a timed override while the Station remains open.
- Verify that the legacy menu-bar path still renders its existing controls and
  the compact timed line.
