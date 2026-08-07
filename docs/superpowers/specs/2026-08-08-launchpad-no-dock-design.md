# Meeting Pulse Launchpad without Dock visibility design

## Context

`Meeting Pulse.app` must remain visible in Launchpad so it has a convenient
launch path, but its Dock icon is not useful for this menu-bar utility. The
bundle currently keeps `LSUIElement` false so Launchpad can list it, and the
SwiftUI app does not yet override its runtime activation policy.

## Goals

- Keep `Meeting Pulse.app` listed in Launchpad.
- Hide the running app from the Dock.
- Hide the running app from Command-Tab as a consequence of accessory policy.
- Preserve the menu-bar item and all existing app behavior.
- Preserve the bundle identifier, Accessibility identity, and persisted data
  paths.

## Non-goals

- Reverting `LSUIElement` to true, which would remove the Launchpad entry.
- Adding a second launcher bundle.
- Changing the app's scenes, status logic, signing, or storage.

## Chosen approach

Keep `LSUIElement` false in `Info.plist` so LaunchServices and Launchpad treat
the bundle as a normal launchable application. In `MeetingPulseApp.init`, call
`NSApplication.shared.setActivationPolicy(.accessory)` before starting the
launch coordinator. AppKit's accessory policy removes the Dock and
Command-Tab presence while retaining the menu-bar interface.

If AppKit rejects the policy change, log a concise diagnostic through the
existing native logging path rather than silently treating the change as
successful. The app remains launchable and the failure is observable for
troubleshooting.

## Build and installation flow

1. Add the startup activation-policy call and failure diagnostic.
2. Build the Release configuration with the existing `MeetingPulse` scheme,
   temporary placeholder configuration, and code signing disabled.
3. Validate the generated bundle still has `LSUIElement` false and the
   unchanged bundle identifier.
4. Replace only `/Applications/Meeting Pulse.app`.
5. Re-register the installed bundle with LaunchServices and refresh the Dock
   process if needed so Launchpad retains the entry.
6. Remove the temporary ignored `mac-app/Config.xcconfig`.

## Validation and failure handling

- Run the existing Xcode build and MPSupport tests.
- Run the existing viewer checks.
- Launch the installed app and verify its process is running with the
  accessory activation policy; the menu-bar app must remain available.
- Verify no Dock-visible app process/icon is created while the app runs.
- Verify LaunchServices still lists `/Applications/Meeting Pulse.app`.
- Confirm the bundle identifier remains `com.techdevix.meetingpulse`.
- Stop before replacing the installed app if the build or metadata validation
  fails.
