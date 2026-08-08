# Remove publish progress bar

**Date:** 2026-08-09

**Status:** Design approved; implementation pending

## Summary

Remove the visual progress bar shown above the publish status in the Meeting
Pulse sidebar. The existing status icon, relative-time label such as
`Published just now`, spacing around that row, and the top divider remain
unchanged.

## Scope

`PublishRail` currently renders a `GeometryReader` with two rounded rectangles
before the status row. That view and its width calculation are the only
production changes needed. Publish state, sync state, labels, icons, and
publishing behavior remain unchanged.

## Design

Delete the progress-bar `GeometryReader` from the `VStack` and remove the
`railWidth(total:)` helper because it will no longer have a caller. Keep the
status `HStack`, its existing styling, and the top divider overlay in place.
No model, networking, or persistence code changes are required.

## Accessibility and error handling

The status row remains the source of truth for publishing state and continues
to expose its existing icon and text. Removing the decorative progress bar does
not alter status communication, state transitions, or error handling.

## Validation

Run the existing MPUI package tests with:

```sh
swift test --package-path mac-app/Packages/MPUI
```
