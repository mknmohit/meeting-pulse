# Meeting Pulse Launchpad visibility design

## Context

`Meeting Pulse.app` is installed at `/Applications/Meeting Pulse.app` and
LaunchServices can find the bundle, but the app's `Info.plist` sets
`LSUIElement` to true. That identifies it as a menu-bar-only agent, so macOS
does not present it in Launchpad, the Dock, or Command-Tab.

## Goals

- Make the existing `Meeting Pulse.app` visible in Launchpad.
- Make the app available in the Dock and Command-Tab as a normal macOS app.
- Preserve the menu-bar controls and all application behavior.
- Preserve the bundle identifier `com.techdevix.meetingpulse`, Accessibility
  permission identity, and existing Application Support, log, and Keychain
  paths.
- Rebuild and reinstall the updated app at `/Applications/Meeting Pulse.app`.

## Non-goals

- Adding a separate launcher app.
- Changing the SwiftUI scene structure, menu-bar status logic, or app data
  storage.
- Changing the bundle identifier, signing identity, backend configuration, or
  persisted user data.

## Chosen approach

Convert the existing bundle from an agent app to a normal app by setting
`LSUIElement` to false. Keep the existing `MenuBarExtra`, so the app continues
to expose its menu-bar interface while also gaining a regular application
presence. This is the smallest change that makes the requested app-list entry
possible without introducing a second bundle or a new launch path.

The expected user-visible trade-off is that the app will now have a Dock icon
and appear in Command-Tab in addition to Launchpad.

## Build and installation flow

1. Change `LSUIElement` in `mac-app/MeetingPulse/Info.plist` from true to false.
2. Copy `mac-app/Config.xcconfig.example` to the ignored
   `mac-app/Config.xcconfig` for the local placeholder-config build.
3. Build the Release configuration with the existing `MeetingPulse` scheme and
   code signing disabled, as in the previous local build.
4. Replace only `/Applications/Meeting Pulse.app` after a successful build.
5. Register the installed bundle explicitly with macOS LaunchServices.
6. If Launchpad retains stale state, restart only the Dock process identified by
   its exact PID so Launchpad reloads its app list.
7. Remove the temporary ignored `mac-app/Config.xcconfig` created for the build.

The bundle identifier and internal `MeetingPulse` storage names remain
unchanged. The local build remains unsigned and uses placeholder configuration;
this task does not add signing credentials or notarization.

## Validation and failure handling

- Build the renamed normal-app bundle successfully with `xcodebuild`.
- Confirm the installed plist has `LSUIElement` set to false.
- Confirm the installed display name is `Meeting Pulse` and the bundle
  identifier remains `com.techdevix.meetingpulse`.
- Confirm `/Applications/Meeting Pulse.app` is indexed by LaunchServices.
- Confirm the old `/Applications/MeetingPulse.app` path is absent.
- Do not replace the installed app if the build or bundle metadata validation
  fails.
- Run the existing MPSupport package tests and viewer checks after the rebuild.
