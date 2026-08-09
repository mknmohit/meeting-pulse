# Meeting Pulse

Meeting Pulse is a privacy-first macOS menu-bar app and static viewer for one
question: **is he in a meeting right now?**

The macOS app watches Google Meet meetings in Chrome and native Slack Huddles
through Accessibility APIs. The viewer reads only the latest trustworthy
availability state from Supabase. Meeting titles, URLs, participants, audio,
video, screenshots, screen contents, camera state, and microphone state never
leave the Mac. Screen Recording is not requested, and the product has no
analytics or telemetry; diagnostics stay on the Mac.

## What ships

### macOS app

- Google Meet detection in Chrome and Slack Huddle detection in the native
  Slack app.
- Fail-closed state reduction: unknown, stale, or permission-blocked input is
  `Status unavailable`, never an assumed `Available`.
- Menu-bar state and connection health, with launch-at-login support.
- Manual Busy or Available overrides with expiry, plus an independent
  `Call okay` flag.
- Pairing links and codes, viewer rotation and revocation, and viewer
  management.
- Recovery phrase rebind for moving the owner identity to another Mac.
- Inline anonymous authentication and Turnstile protection for pairing.
- Accessibility permission guidance, diagnostics export, local reset, and
  remote-data deletion.

### Viewer

- Static Astro site with no server runtime.
- Pairing by link fragment or normalized ten-character code.
- Anonymous Supabase session restoration with Turnstile on first pairing.
- Large, accessible status display with optional owner name and call-okay copy.
- Server-time freshness handling, a 30-second focused-tab poller, and manual
  refresh.
- Offline, revoked-pairing, malformed-response, and stale-state handling.
- Responsive light/dark UI with reduced-motion support and no analytics.

## Requirements

- macOS 14 or newer for the owner app.
- Xcode with Swift 6 support and the macOS SDK.
- Node.js 22.12 or newer and pnpm for the viewer.
- Python 3 with `Pillow` and `ds_store` for the Finder-styled DMG helper.

The app requires Accessibility permission for Chrome and Slack inspection. It
does not require Screen Recording permission. Copy the example configuration
files before building:

```sh
cp mac-app/Config.xcconfig.example mac-app/Config.xcconfig
cp viewer/.env.example viewer/.env
```

Fill in the local Supabase, Turnstile, and viewer-origin values. The example
files are templates; there are no production fallbacks.

## Build the macOS app locally

The architecture-specific scripts cross-compile the requested target on any
Mac whose Xcode toolchain supports it. Each script builds the optimized
`Release` configuration, disables debug information, creates an ad-hoc signed
DMG, verifies the artifact, and replaces `/Applications/Meeting Pulse.app`
only after a successful build.

Apple silicon build:

```sh
./mac-app/Tools/build-release-arm64.sh
```

Output:
`build/dmg/Meeting-Pulse-0.0.1-Apple-Silicon-arm64.dmg`

Intel build:

```sh
./mac-app/Tools/build-release-x86_64.sh
```

Output:
`build/dmg/Meeting-Pulse-0.0.1-Intel-x86_64.dmg`

To build the DMG without replacing the installed app:

```sh
MP_RELEASE_INSTALL=0 ./mac-app/Tools/build-release-arm64.sh
MP_RELEASE_INSTALL=0 ./mac-app/Tools/build-release-x86_64.sh
```

These local DMGs are ad-hoc signed and not notarized. On a fresh Mac, move the
app to Applications and use Finder's **Open** action once, or remove the
quarantine attribute after verifying the artifact:

```sh
xattr -dr com.apple.quarantine "/Applications/Meeting Pulse.app"
```

For a fast unsigned/ad-hoc development build:

```sh
make mac-local-build
open "build/local/Build/Products/Debug/Meeting Pulse.app"
```

## Build and test the viewer

Use a real `.env` for a deployment build, or copy `.env.ci` for a
shape-valid local build with fake values:

```sh
cd viewer
pnpm install --frozen-lockfile
cp .env.ci .env
pnpm run check
pnpm run lint
pnpm test
pnpm run build
```

The generated static site is in `viewer/dist/`.

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) for the complete setup, test matrix,
privacy rules, and pull-request checklist. In short: configure from the
example files, keep changes focused, run the checks for the surface you
changed, update relevant documentation, and never commit local configuration,
tokens, pairing codes, recovery phrases, diagnostics, or meeting content.

## Privacy and storage

The owner app publishes only `state`, `call_okay`, an optional display name,
and freshness timestamps. Local identity and session values are stored in the
owner-only
`~/Library/Application Support/MeetingPulse/secrets.plist`; they are not
encrypted, placed in Keychain, or synchronized through iCloud. See
[`SECURITY.md`](SECURITY.md) and [`docs/setup/operations.md`](docs/setup/operations.md)
for the storage and uninstall details.

## License

This project is licensed under the MIT License.
