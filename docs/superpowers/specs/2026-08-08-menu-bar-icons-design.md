# Menu Bar Option Icons — Design

## Goal

Add a SF Symbol next to every actionable option in the macOS menu bar dropdown so people can scan and pick the right control at a glance. Keep the existing copy and accessibility labels unchanged.

## Scope

- The native menu bar dropdown (`MPUI.MenuBarContent`, shown when `FeatureFlag.macNative` is on).
- The legacy menu bar dropdown (`MenuBarView` in `MeetingPulse/MeetingPulseApp.swift`) — matches the native layout, so it gets the same icons for parity.
- The menu bar **status icon** itself (the heart-thread glyph) is **out of scope** — it already carries state.

## Icon Mapping

| Menu option | Action | SF Symbol |
| --- | --- | --- |
| Set busy (submenu) | Override status to busy | `moon.fill` |
| Set available | Override status to available | `checkmark.circle` |
| Back to automatic | Clear override | `arrow.uturn.backward` |
| Calls are okay | Toggle (calls-okay flag) | `phone.fill` |
| Open Dashboard | Open main Station window | `rectangle.grid.2x2` |
| Quit Meeting Pulse | Quit app | `power` |

Each `Button` and `Toggle` becomes a SwiftUI `Label(text, systemImage:)`. The submenu uses a `Menu` whose title is the same string; macOS already shows the item with just the chevron, so no icon is needed there.

## Implementation

1. In `MenuBarContent.swift`, wrap each `Button` and `Toggle` in `Label { Text(...) } icon: { Image(systemName: ...) }`.
2. In `MenuBarView.swift` (legacy path), do the same for the matching buttons.
3. Skip the status headline + reason line at the top — they're read-only display, not actions.
4. Keep existing accessibility; `Label` already merges the title into the accessibility label.

## Strings / Bindings

- Existing copy strings remain unchanged.
- Add no new compiled strings; SF Symbol names are code-side identifiers.
- No regenerated bindings needed.

## Testing

- `swift build` `mac-app/Packages/MPUI` and `mac-app/MeetingPulse` to confirm nothing breaks.
- `swift test mac-app/Packages/MPUI` — existing menu tests should still pass because the option count and labels are unchanged.
- Visual: open the menu bar dropdown in the running app and verify each row has a symbol. (Manual; no automated snapshot in this branch.)

## Out of Scope

- New icons beyond the actionable items listed.
- Changing the menu bar status glyph.
- Replacing legacy `MenuBarView` with the native path.
