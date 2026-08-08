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

## Dock icon visibility refinement

The Dock icon mirrors the station window's visibility rather than the app's
launch-time activation policy. Specifically:

- At launch, before the station window appears, the app uses the
  `.accessory` activation policy, so no Dock icon is visible.
- When the station window is on screen, `DockVisibilityCoordinator` flips the
  activation policy to `.regular` so the Dock icon appears.
- When the station window closes, the coordinator flips back to `.accessory`
  so the Dock icon disappears. This avoids the "ghost" Dock icon that
  previously remained after the station closed and could not reopen the
  window.
- The `MenuBarExtra` is unaffected by activation policy, so the menu-bar
  item stays available in either mode.
- The coordinator reads `PulseStore.stationVisible`, which
  `StationWindow.onAppear` / `.onDisappear` already maintain.

This is a refinement of the launch-time `.regular` policy described in
"Architecture and data flow" step 2. The bundle metadata, asset catalog,
window scenes, and graceful termination flow are unchanged.

### Launching from Launchpad and Dock-icon reopens

Because the Dock icon now depends on the station window, the app must surface
the station whenever the user activates the app from the Dock or from
Launchpad. Otherwise the menu-bar process spawns (or re-activates) without a
window, and the user sees a Dock icon with no content behind it.

- `MeetingPulseAppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)`
  calls `pulseActions?.openStation()` whenever Dock / Launchpad activation
  reopens the app. Returning `true` tells AppKit the reopen was handled so the
  default window-restoration path does not interfere.
- The `NativeMenuBarLabel.task` always calls `actions.openStation()` after
  the menu-bar task wires the opener, so cold launches from Launchpad also
  surface the station.
- The delegate receives the `AppPulseActions` instance via `MeetingPulseApp.init`,
  which sets `appDelegate.pulseActions = _actions.wrappedValue` immediately
  after the actions are constructed. This keeps the Dock behavior wired
  before `applicationDidFinishLaunching` fires.

### Open Station flips activation policy synchronously

When the station window opens while the app is still in `.accessory` mode
(initial state at launch), AppKit orders the window beneath whatever app
launched Meeting Pulse (Launchpad, Finder, the Dock, etc.). The window is
technically on screen but visually hidden.

`AppPulseActions.openStation()` therefore flips the activation policy to
`.regular` *before* opening the window:

1. Set `store.stationVisible = true` so the `DockVisibilityCoordinator`
   observer sees the change and reapplies `.regular` on its next tick.
2. Call `NSApplication.shared.setActivationPolicy(.regular)` directly so the
   policy is already `.regular` by the time SwiftUI presents the window.
3. The window opener also calls `NSApp.activate(ignoringOtherApps: true)` so
   the station takes focus instead of politely asking for it.

### Station view owns the activation policy flip

`StationWindow.onAppear` and `.onDisappear` flip the activation policy
synchronously, in addition to updating `store.stationVisible`. This keeps the
Dock icon in lockstep with the window regardless of which close path the user
takes:

- Red close button — `.onDisappear` fires when the window closes; the
  synchronous `setActivationPolicy(.accessory)` removes the Dock icon in the
  same frame instead of waiting for the next runloop tick (the observer is a
  safety net rather than the primary path).
- Cmd+Q — `applicationShouldTerminate` calls `closeStation()`, which
  synchronously flips the policy to `.accessory`. The window then closes,
  `.onDisappear` fires, and the policy flip is re-asserted (no-op via
  `lastPolicy`).
- Menu-bar Quit — fully terminates the app, so the policy flip is irrelevant.

The `DockVisibilityCoordinator` observer continues to run as a safety net for
visibility changes that bypass the view callbacks (defense in depth), but the
view callbacks are the primary source of truth.

  ### Cmd+Q closes the station, not the app

  The menu-bar app must keep running so the user can reopen the station later.
  Cmd+Q is therefore scoped to closing the station window. The explicit
  "Quit Meeting Pulse" menu item is the only path that fully terminates the
  app.

  - `MeetingPulseAppDelegate.applicationShouldTerminate(_:)` checks
    `pulseActions?.isStationVisible` and `pulseActions?.requestedQuitFromMenu`.
    When the station is on screen and the user did **not** invoke the menu-bar
    Quit, the delegate calls `closeStation()` and returns `.terminateCancel`.
    The Dock icon disappears via the synchronous flip in `closeStation()` (and
    is re-asserted by `StationWindow.onDisappear`); the menu-bar item stays.
  - `AppPulseActions.closeStation()` walks `NSApp.windows` and calls
    `performClose(nil)` on the window whose title matches
    `MPString.station.windowTitle`. It also flips the activation policy to
    `.accessory` synchronously. `performClose` is asynchronous — the window
    `.onDisappear` callback does not fire until the next runloop tick. Setting
    `.accessory` directly in `closeStation` keeps the Dock icon in lockstep
    with the window: pressing Cmd+Q closes the station and removes the Dock
    icon in the same frame. `StationWindow.onDisappear` (which fires on the
    next runloop tick) reaffirms `store.stationVisible = false` and re-asserts
    `.accessory`; the observer's subsequent application is a no-op via
    `lastPolicy`.
  - `AppPulseActions.quit()` sets `requestedQuitFromMenu = true` before
    calling `NSApp.terminate(nil)`. The delegate honors this flag and skips
    the interception, so the menu-bar Quit always terminates the app.
  - When the station is hidden, the Dock icon is gone and the app is in
    `.accessory` mode. Cmd+Q then routes to whatever app the user has focused
    (the menu-bar app is no longer foreground). The delegate falls through
    to the existing graceful-quit path for the rare case where the user does
    focus the menu bar and press Cmd+Q.

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
