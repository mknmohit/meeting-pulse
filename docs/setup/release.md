# Release setup

Meeting Pulse has two local distribution modes:

1. An ad-hoc signed, optimized DMG for local testing and direct distribution.
2. A Developer ID signed, notarized, stapled DMG for trusted distribution.

The first mode does not require an Apple Developer Program account. It cannot
remove Gatekeeper's first-launch warning on another Mac.

## Local ad-hoc release

Create the ignored app configuration first:

```sh
cp mac-app/Config.xcconfig.example mac-app/Config.xcconfig
```

Build the Apple silicon asset:

```sh
./mac-app/Tools/build-release-arm64.sh
```

Build the Intel asset:

```sh
./mac-app/Tools/build-release-x86_64.sh
```

Both commands can run on either host architecture when the installed Xcode
toolchain supports the requested target. They:

- build the Xcode `Release` configuration with whole-module Swift
  optimization;
- disable testability and debug-information generation;
- strip the installed product and dead code;
- add no analytics or telemetry to the release build;
- patch the built bundle to version `0.0.3` and build `1`;
- ad-hoc sign and verify the app;
- create and verify a compressed DMG; and
- replace `/Applications/Meeting Pulse.app` only after all checks pass.

The assets are:

```text
build/dmg/Meeting-Pulse-0.0.3-Apple-Silicon-arm64.dmg
build/dmg/Meeting-Pulse-0.0.3-Intel-x86_64.dmg
```

The 0.0.3 macOS app assets were built from the release tree after the recovery
startup fix and verified before publication.

| Architecture | File | SHA-256 |
|---|---|---|
| Apple Silicon (`arm64`) | `Meeting-Pulse-0.0.3-Apple-Silicon-arm64.dmg` | `4f8b85afc7586989349c07fc01e86467b904e38014b8e6663c179c44cd17742c` |
| Intel (`x86_64`) | `Meeting-Pulse-0.0.3-Intel-x86_64.dmg` | `c1ac17730325d1d2eb2b7723d7905fbf7a5b768a72bb95d46d0dffda2669cf8b` |

Both assets pass `hdiutil verify` and contain only their named target
architecture.

To create the DMG without changing the installed app:

```sh
MP_RELEASE_INSTALL=0 ./mac-app/Tools/build-release-arm64.sh
MP_RELEASE_INSTALL=0 ./mac-app/Tools/build-release-x86_64.sh
```

The DMGs are ad-hoc signed and not notarized. On a fresh Mac, move the app to
`/Applications`, then use Finder's right-click **Open** action once. If needed,
remove the quarantine attribute only after verifying the artifact:

```sh
xattr -dr com.apple.quarantine "/Applications/Meeting Pulse.app"
```

Do not describe these artifacts as notarized or trusted releases.

## GitHub release

The `v0.0.3` release uses the current committed `HEAD`, not uncommitted
working-tree changes. After building and verifying both assets, a maintainer
can create it with:

```sh
gh release create v0.0.3 \
  --target HEAD \
  --title "Meeting Pulse 0.0.3" \
  --notes-file CHANGELOG.md \
  build/dmg/Meeting-Pulse-0.0.3-Apple-Silicon-arm64.dmg \
  build/dmg/Meeting-Pulse-0.0.3-Intel-x86_64.dmg
```

The release notes must retain the ad-hoc/no-notarization warning.

## Trusted Developer ID release

Install the pinned Xcode toolchain, configure a `notarytool` keychain profile,
and create `mac-app/Config.xcconfig` from the example file. Then set:

```sh
export MP_SIGN_IDENTITY='Developer ID Application: ...'
export MP_TEAM_ID='...'
export MP_NOTARY_PROFILE='...'
./mac-app/Tools/notarize.sh
```

The script fails if a required value or local configuration is missing. It
archives, exports, creates the DMG, signs it, submits it to `notarytool`,
staples the ticket, and runs `spctl`.

Keep the release bundle identifier `com.techdevix.meetingpulse` and signing
identity stable. macOS binds the Accessibility permission grant to both.
