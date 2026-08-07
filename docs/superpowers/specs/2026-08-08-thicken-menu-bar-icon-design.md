# Thicker menu-bar icon design

**Date:** 2026-08-08

**Status:** Approved design

## Goal

Make the Meeting Pulse menu-bar Heart Thread mark visually match the heavier neighboring macOS menu-bar icons while keeping the existing status behavior and accessibility semantics.

## Chosen approach

Tune the existing `HeartThreadMenuIcon` SwiftUI drawing in `mac-app/MeetingPulse/MeetingPulseApp.swift`. This is the smallest change and avoids changing the app icon asset, state model, or menu interactions.

Use the selected **Balanced** treatment:

- Increase the rendered label from 20x20 to approximately 22x22 points.
- Increase the heart symbol's size and weight.
- Increase the upper thread and lower wave stroke widths modestly.
- Slightly enlarge and reposition the status dot to stay optically aligned with the larger mark.

The three state colors, state-derived accessibility labels, stable accessibility identifier, reduce-motion handling, and existing `.menu` `MenuBarExtra` style remain unchanged.

## Validation

Build the macOS target and run the existing package tests. Confirm visually that the icon is slightly larger and heavier than the current mark without crowding adjacent system icons. Confirm that `busy`, `available`, and `unavailable` still use their existing dot colors and spoken labels.

## Out of scope

- Replacing the SF Symbol or introducing a new vector asset.
- Changing the app icon, menu contents, status reducer, sync transport, or state model.
- Adding animation beyond the existing short dot transition.
