# Meeting Pulse menu bar and Dock visibility design

**Date:** 2026-08-08

**Status:** Approved design

## Context

Meeting Pulse currently behaves as an accessory application. `LSUIElement` is
enabled in the bundle and both Xcode configurations, and
`MeetingPulseApp.init()` requests the `.accessory` activation policy. This
keeps the menu-bar item alive but prevents the app from having a visible Dock
icon. The native UI path also renders a status-specific mast icon instead of
the full Heart Thread mark.

The requested behavior is:

- show the Meeting Pulse Heart Thread logo in the menu bar;
- show the existing Meeting Pulse app icon in the Dock;
- let a Dock window close without stopping the menu-bar process;
- let Dock Quit and the menu-bar Quit fully terminate the app.

## Goals

- Keep one Meeting Pulse process for the menu bar, windows, and Dock presence.
- Use the existing full-color `AppIcon` asset for the Dock.
- Use the existing Heart Thread renderer for both native and legacy menu-bar
  paths, preserving the state dot and accessibility semantics.
- Preserve the existing graceful termination and final-publish behavior.
- Keep normal macOS window lifecycle behavior: closing a window does not quit
  the application.

## Non-goals

- Do not add a launcher bundle, helper process, or separate status-bar app.
- Do not replace `MenuBarExtra` with a custom `NSStatusItem`.
- Do not change the status reducer, backend payload, pairing flow, or storage.
- Do not redesign the app icon or create a second Dock-specific asset.
- Do not intercept or suppress Dock Quit.

## Considered approaches

### A. Make the existing app a normal macOS app (selected)

Set `LSUIElement` to false, remove the `LSUIElement = YES` build-setting
overrides, and request `.regular` at startup. Keep the existing SwiftUI
`MenuBarExtra`, windows, and graceful termination delegate. This adds no second
process and uses the standard AppKit window and Dock lifecycle.

### B. Add a separate launcher bundle

Keep the current accessory app and add a normal Dock-visible launcher that
activates it. This preserves the current agent identity but adds another
bundle, lifecycle coordination, packaging work, and memory overhead.

### C. Replace `MenuBarExtra` with a custom status item

Use an AppKit delegate to own an `NSStatusItem`, Dock policy, windows, and
termination directly. This provides maximum control but duplicates native menu
behavior and increases the risk of lifecycle regressions.

Approach A is selected because it is the smallest single-process change and
directly matches macOS behavior for window close versus application quit.

## Architecture and data flow

1. `Info.plist` declares `LSUIElement` as false, and the Debug and Release
   target settings stop overriding it to true.
2. `MeetingPulseApp.init()` requests `NSApplication.shared` activation policy
   `.regular`. If AppKit rejects the request, the app logs a concise
   diagnostic through the existing native logging path.
3. The existing `MenuBarExtra` remains the menu-bar entry point. Its window
   scenes and `MeetingPulseAppDelegate` remain in the same process.
4. `NativeMenuBarLabel` selects the current state from `PulseStore` when the
   native UI flag is enabled and from `OwnerAppModel` otherwise. Both paths
   render `HeartThreadMenuIcon`.
5. `HeartThreadMenuIcon` continues to draw the full Heart Thread mark and uses
   the state-derived dot color and accessibility label. Reduced-motion
   behavior and the stable accessibility identifier remain unchanged.
6. The existing asset catalog and `CFBundleIconName = AppIcon` provide the Dock
   icon. No new asset registration is needed.

## Lifecycle behavior

- Clicking the red close button on a Meeting Pulse window closes that window
  only. The `MenuBarExtra` and its process remain available.
- Choosing Quit from the Dock sends the normal application termination request.
  The existing delegate runs its graceful termination handler and then exits.
- Choosing Quit Meeting Pulse from the menu bar follows the same graceful
  termination path and exits.
- No custom termination cancellation or second process is introduced.

## Error handling

- A failed `.regular` activation-policy request is logged explicitly. The
  app does not claim that Dock visibility was established when AppKit rejected
  the request.
- Existing termination failures continue to propagate through the current
  graceful-quit path. This change does not add broad catches or silent
  fallbacks.
- Bundle validation must pass before an installed app is replaced.

## Validation

### Build and metadata

- Build the existing MeetingPulse target with its normal Debug or Release
  configuration.
- Inspect the built bundle and confirm `LSUIElement` is false,
  `CFBundleIconName` is `AppIcon`, and the asset catalog is present.
- Run the existing macOS package tests and viewer checks relevant to the
  current branch.

### Acceptance matrix

- Launch Meeting Pulse and confirm the full Heart Thread mark is visible in
  the menu bar in the current state.
- Confirm the full-color Meeting Pulse icon is visible in the Dock.
- Open a Meeting Pulse window, close it from the window controls, and confirm
  the menu-bar item remains available.
- Choose Quit from the Dock and confirm the process and menu-bar item exit.
- Relaunch, choose Quit Meeting Pulse from the menu bar, and confirm graceful
  termination still runs.
- Confirm VoiceOver still receives the existing status label and the
  accessibility identifier remains stable.
