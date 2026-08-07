# Release setup

Meeting Pulse releases are Developer ID signed, notarized, stapled DMGs. The
bundle identifier and signing identity are stable because macOS binds the
Accessibility grant to both.

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
