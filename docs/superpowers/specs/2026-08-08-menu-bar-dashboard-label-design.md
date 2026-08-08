# Menu Bar Dashboard Label Design

**Date:** 2026-08-08

**Status:** Approved design

## Context

The menu bar currently includes an `Open Meeting Pulse` item. Its action opens
the main status window, not the settings window. The label is therefore more
brand-oriented than destination-oriented, and the requested wording is
clearer.

## Goals

- Rename the menu bar item to `Open Dashboard`.
- Preserve its existing behavior of opening the main status window.
- Keep the legacy menu bar path unchanged.

## Non-goals

- Do not redirect the item to the settings window.
- Do not rename the internal `openStation` action or window identifier.
- Do not change menu ordering, status controls, quit behavior, or other copy.

## Chosen approach

Update the shared `MPString.MenuBar.openStation` value from `Open Meeting
Pulse` to `Open Dashboard`. The active native menu bar content uses this value,
so the visible label changes while the action routing remains untouched. The
legacy menu bar view uses its own `This Mac` entry and is not changed.

Alternative approaches were considered:

- Renaming the internal action symbol as well would add code churn without
  changing user-visible behavior.
- Updating only the native path would leave the legacy path inconsistent.

## Architecture and data flow

The existing native menu item continues to call `openStation()`.
`AppPulseActions` still routes that action to the `station` window. The legacy
`MenuBarView` remains unchanged. Only the shared display string changes.

## Error handling

No new failure path is introduced. Existing window-opening behavior and error
handling remain unchanged.

## Validation

- Search the macOS menu bar sources for the old `Open Meeting Pulse` label and
  confirm it is no longer used for the menu bar item.
- Run the existing macOS package tests or the smallest existing test/build
  command that covers the changed Swift sources.
