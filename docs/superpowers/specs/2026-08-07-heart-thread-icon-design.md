# Meeting Pulse Heart Thread icon design

**Date:** 2026-08-07

**Status:** Approved design

## Goal

Give Meeting Pulse a recognizable, personal visual identity that connects the product to the relationship it protects: a private heartbeat between two people. The selected direction is **Heart Thread**, a heart outline crossed by a continuous pulse/thread, with a small status dot at the end of the thread.

The design covers both macOS surfaces:

- A full-color application icon for Finder, Launchpad, installers, and the Dock.
- A compact menu-bar icon that communicates the effective owner state without drawing attention or consuming meaningful CPU or battery.

## Visual language

The app icon uses the selected Heart Thread artwork:

- A rounded-square macOS icon silhouette.
- A single solid coral-rose background (`#F47770`) with enough contrast for light and dark Finder surfaces.
- A white heart outline as the primary silhouette.
- A muted pink thread behind the heart and a warm gold pulse/thread crossing the lower heart.
- A small mint-green dot at the end of the thread as the active signal accent.
- Transparent corners outside the rounded square; no white matte is baked into the PNG renditions.
- No text, initials, meeting-platform logos, or state-specific artwork in the app icon.

The artwork must be drawn as clean geometric paths with rounded caps and joins. The heart remains recognizable at 16 px, and the thread must not collapse into a noisy ECG trace at small sizes. The app icon is static; it is a brand mark, not a live status indicator. Do not add gradients, glows, bloom, or drop shadows.

## Menu-bar behavior

The menu-bar icon reuses the Heart Thread silhouette in a compact custom SwiftUI view rather than the current generic SF Symbols. The icon is rendered at the natural menu-bar label size and keeps the thread open enough to remain legible on both light and dark menu bars.

The menu-bar label has one small state dot. The dot is the only changing visual element:

| Effective state | Dot treatment | Meaning |
|---|---|---|
| `busy` | Mint/green | A meeting signal is active. |
| `available` | Rose/pink | No meeting signal is active. |
| `unavailable` | Muted gray | Meeting status cannot be trusted. |

The menu-bar menu text remains the authoritative status cue and must expose the same state in words. The icon must include an accessibility label such as “Meeting Pulse, meeting active” or “Meeting Pulse, status unavailable”; color is never the only way to learn the state.

There is no infinite horizontal movement, repeating pulse, `TimelineView`, display-link loop, or timer-driven animation. On a state change, only the dot uses a short ease-in/ease-out color transition of about 180 ms. This preserves the premium feel while keeping the background app idle between detector and sync work.

The `callOkay` flag does not create another icon state. It remains a menu item and status line so the three-state model stays unambiguous.

## Implementation boundaries

### App icon asset

Create a macOS `AppIcon.appiconset` under `mac-app/MeetingPulse/Assets.xcassets` with the required 1x and 2x sizes for 16, 32, 128, 256, and 512 point icons. Generate all sizes from one source vector so the heart and thread preserve the same proportions. Wire the asset catalog to the target through `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

The source artwork should remain available beside the asset catalog as an editable vector source. Generated raster files are build inputs, not hand-edited per size.

### Menu-bar view

Replace `StatusIcon` in `MeetingPulseApp.swift` with a small reusable `HeartThreadMenuIcon` view. It should:

- Draw the heart/thread with SwiftUI `Path` or `Canvas`, without loading an image for every state update.
- Accept `MeetingPulseState` and derive the dot color from the state in one place.
- Use the existing `MenuBarExtra` label and preserve the `.menu` style.
- Apply a short transition only when the state changes.
- Expose an accessibility label and a stable accessibility identifier for UI tests.

The view must not change the existing reducer or status transport. It is a presentation-only change over the existing `MPCore.State` value.

### Project integration

Add the asset catalog to the Xcode project resources and set the target app-icon build setting for Debug and Release. Keep the menu-bar mark in Swift source so it can respond to state without storing three colored bitmap variants.

## Accessibility and contrast

- The heart/thread silhouette and dot must remain visible in both menu-bar appearances.
- The menu text states “Available”, “Busy”, or “Status unavailable” in words.
- Accessibility labels describe the state and do not depend on color.
- The color transition respects `accessibilityReduceMotion`; when reduced motion is enabled, update the dot without animation.
- The icon must not imply that green means permission or network health; unavailable is explicitly gray and verbalized.

## Validation

The implementation is complete when:

1. Finder/Dock show the Heart Thread app icon at all required macOS sizes.
2. The menu bar no longer shows the generic circle/triangle/mountain SF Symbols.
3. `available`, `busy`, and `unavailable` render the correct dot colors and spoken labels.
4. A state change produces at most one short dot transition and no repeating animation or timer.
5. `callOkay` does not alter the icon state.
6. Existing menu-bar controls and status behavior remain unchanged.
7. The macOS target builds for both configured architectures, and the existing package tests remain green.

## Out of scope

- Redesigning the viewer page or its state colors.
- Adding a live pulse animation to the Dock icon or app icon.
- Introducing a new state for “busy but call okay”.
- Adding meeting-platform-specific artwork.
- Changing detector, reducer, sync, or privacy behavior.
