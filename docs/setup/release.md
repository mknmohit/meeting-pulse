# Release setup

Meeting Pulse public releases are Developer ID signed, notarized, stapled DMGs.
The bundle identifier and signing identity are stable because macOS binds the
Accessibility grant to both.

## Local-only build without Apple Developer Program

An Apple Developer Program subscription is not required for local development.
Use the repository's local build helper:

```sh
make mac-local-build
open "build/local/Build/Products/Debug/Meeting Pulse.app"
```

This produces an ad-hoc signed app by default. It does not produce a DMG, does
not pass notarization, and must not be distributed as a public release. macOS
may show an Open Anyway prompt and may require a fresh Accessibility grant
after each rebuild.

Meeting Pulse stores its local session, recovery, identity, nonce, and pairing
values in
`~/Library/Application Support/MeetingPulse/secrets.plist`. The file is
owner-only but not encrypted. The first launch after the storage change deletes
legacy Meeting Pulse Keychain items and starts setup again without migrating
their values. No Keychain prompt is expected.

For the optimized local artifact installed by the current project:

```sh
make mac-local-release
open "build/local-release/Build/Products/Release/Meeting Pulse.app"
```

The Release configuration uses whole-module compilation and `-O`; it is still
ad-hoc signed and remains local-only.

To skip ad-hoc signing:

```sh
MP_LOCAL_SIGNING=none make mac-local-build
```

Use this path for local UI review, detector development, and personal testing.
The bundle identifier remains `com.techdevix.meetingpulse` so future
Developer ID builds can retain the documented product identity.

## Local release

Install the pinned Xcode 16.2 toolchain, configure a notarytool keychain profile, and create a
local `mac-app/Config.xcconfig` from the example file. Then set:

```sh
export MP_SIGN_IDENTITY='Developer ID Application: ...'
export MP_TEAM_ID='...'
export MP_NOTARY_PROFILE='...'
./mac-app/Tools/notarize.sh
```

The script fails if any required value or local configuration is missing. It
archives, exports, creates the DMG, signs it, submits it to notarytool,
staples the ticket, and runs `spctl`.

GitHub-hosted release automation is currently disabled. Releases must be
created locally with the steps above.
