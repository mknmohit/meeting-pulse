# Thicker menu-bar icon design

**Date:** 2026-08-08

**Status:** Approved design

## Goal

Make the Meeting Pulse menu-bar Heart Thread mark visually match the heavier neighboring macOS menu-bar icons while keeping the existing status behavior and accessibility semantics.

## Chosen approach

Keep `HeartThreadMenuIcon` as the state and accessibility boundary, but render its label as one composed `NSImage` in `mac-app/MeetingPulse/MeetingPulseApp.swift`. macOS `MenuBarExtra` preserves the base image representation but does not reliably retain layered SwiftUI drawing views in the status item.

Use the selected **Balanced** treatment, preserving the geometry from `mac-app/MeetingPulse/Resources/heart-thread.svg`:

- Render the logo paths in a 24-point coordinate scale inside a 22x22 point image.
- Keep the heart as the primary white/label-color outline, with the muted upper thread and gold lower wave from the logo.
- Draw the state dot at the logo's upper-right endpoint and keep its existing state colors.

The three state colors, state-derived accessibility labels, stable accessibility identifier, reduce-motion handling, and existing `.menu` `MenuBarExtra` style remain unchanged.

## Validation

Build the macOS target and run the existing package tests. Confirm visually that the single rendered image is slightly larger and heavier than the current mark without crowding adjacent system icons. Confirm that `busy`, `available`, and `unavailable` still use their existing dot colors and spoken labels.

## Out of scope

- Changing the app icon or introducing a new app-icon asset.
- Changing the app icon, menu contents, status reducer, sync transport, or state model.
- Adding animation beyond the existing short dot transition.
