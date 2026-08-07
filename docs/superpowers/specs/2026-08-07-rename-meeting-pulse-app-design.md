# Meeting Pulse app rename design

## Context

The macOS app is currently branded `MeetingPulse`, but the desired public name
is `Meeting Pulse`. The repository contains a native macOS app, a static viewer,
release tooling, and documentation. The app's bundle identifier and local
storage identifiers are deliberately stable because macOS Accessibility
permissions and existing user data depend on them.

## Goals

- Show `Meeting Pulse` in every user-facing native-app and viewer surface.
- Build the installed application as `/Applications/Meeting Pulse.app`.
- Preserve the existing bundle identifier:
  `com.techdevix.meetingpulse`.
- Preserve the Xcode project, target, scheme, Swift type/source filenames, and
  `MeetingPulse`-based keychain, support, and log paths.
- Rebuild the app locally and install the resulting bundle in `/Applications`.

## Non-goals

- Renaming the Xcode project, target, scheme, source files, or internal Swift
  identifiers.
- Migrating existing Application Support, log, or Keychain paths.
- Changing signing identities, bundle identifiers, backend configuration, or
  notarization credentials.
- Running a notarized release build when the local signing configuration and
  credentials are not available.

## Chosen approach

Use a public-name rename. Update public copy and bundle metadata, and change
the built product filename to `Meeting Pulse.app`, while retaining
`MeetingPulse` everywhere it is an internal compatibility identifier. This
avoids invalidating Accessibility permission or orphaning existing local
settings while still making the installed app visibly match the requested
name.

The project target and scheme remain `MeetingPulse`. The product reference and
scheme buildable product are changed to `Meeting Pulse.app`, and Debug and
Release build settings set `PRODUCT_NAME` to `Meeting Pulse`. The bundle
identifier remains unchanged.

## Rename surfaces

Update the following public surfaces:

- `CFBundleDisplayName` and `CFBundleName` in the app's `Info.plist`.
- Native window titles, menu actions, quit text, onboarding copy, setup errors,
  and accessibility labels.
- Viewer titles and user-facing configuration/status errors.
- Release/install labels and directly related README, product, copy, security,
  and operations documentation.

Keep the following unchanged:

- `MeetingPulse.xcodeproj`, the `MeetingPulse` target and scheme, and the
  `MeetingPulseApp` Swift type/source filename.
- `com.techdevix.meetingpulse`.
- `~/Library/Application Support/MeetingPulse`,
  `~/Library/Logs/MeetingPulse`, and related Keychain service/path names.
- Internal typealiases and identifiers whose only purpose is code compatibility
  rather than user-visible branding.

## Build and installation flow

1. Copy `mac-app/Config.xcconfig.example` to the ignored
   `mac-app/Config.xcconfig` for a local placeholder-config build. No secrets
   are added.
2. Run the existing Xcode project with the `MeetingPulse` scheme in Release
   configuration, using the repository's established code-signing-disabled
   local-build mode.
3. Locate the generated `Meeting Pulse.app` bundle in the derived-data build
   products.
4. If `/Applications/Meeting Pulse.app` already exists, replace only that
   exact app bundle. If the build fails, do not touch the existing install.
5. Verify the installed bundle's display name and bundle identifier with
   `plutil`, and verify the final path exists.
6. Remove the temporary ignored `mac-app/Config.xcconfig` if it was created by
   this flow.

The notarization script is not part of this local install because its required
Developer ID, team, notary profile, and real configuration are not present.

## Validation and failure handling

- Search native and viewer UI sources for stale user-facing `MeetingPulse`
  labels; remaining matches must be limited to documented internal identifiers,
  compatibility paths, or technical names.
- Build the app successfully with `xcodebuild`.
- Confirm `CFBundleDisplayName` and `CFBundleName` are `Meeting Pulse`.
- Confirm `CFBundleIdentifier` remains `com.techdevix.meetingpulse`.
- Confirm `/Applications/Meeting Pulse.app` exists after installation.
- Stop before replacement if the build fails or the generated app bundle cannot
  be located.
- Do not broadly delete files or change unrelated repository state.
