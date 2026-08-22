# Contributing to Meeting Pulse

Meeting Pulse has a native macOS owner app, a static Astro viewer, and
Supabase migrations. Keep the privacy boundary and the fail-closed state model
intact when changing any of them.

## Before you start

Install:

- macOS 14 or newer.
- Xcode with Swift 6 support.
- Node.js 22.12 or newer and pnpm.
- Python 3 with `Pillow` and `ds_store` for DMG creation.
- `gitleaks` for the repository secret scan.

Copy local configuration from the committed templates:

```sh
cp mac-app/Config.xcconfig.example mac-app/Config.xcconfig
cp viewer/.env.example viewer/.env
```

Use real deployment values only when you need to exercise a real Supabase
project. For a local viewer build with fake, shape-valid values:

```sh
cp viewer/.env.ci viewer/.env
```

Never commit local configuration, tokens, pairing codes, recovery phrases,
diagnostic exports, or meeting content.

## Build the macOS app

The architecture-specific scripts can cross-compile either target on any Mac
with a compatible Xcode toolchain. They build the optimized `Release`
configuration, disable debug information, create an ad-hoc signed DMG, verify
it, and replace `/Applications/Meeting Pulse.app` only after the build
succeeds.

```sh
./mac-app/Tools/build-release-arm64.sh
./mac-app/Tools/build-release-x86_64.sh
```

The DMGs are written to:

```text
build/dmg/Meeting-Pulse-0.0.6-Apple-Silicon-arm64.dmg
build/dmg/Meeting-Pulse-0.0.6-Intel-x86_64.dmg
```

To create an artifact without replacing the installed app:

```sh
MP_RELEASE_INSTALL=0 ./mac-app/Tools/build-release-arm64.sh
MP_RELEASE_INSTALL=0 ./mac-app/Tools/build-release-x86_64.sh
```

These builds are not notarized. Gatekeeper requires a one-time Finder
right-click **Open** action on a fresh Mac, or an explicit quarantine removal
after the DMG has been verified. An ad-hoc build must not be described as a
trusted notarized release.

For a faster development build:

```sh
make mac-local-build
open "build/local/Build/Products/Debug/Meeting Pulse.app"
```

The default local build is ad-hoc signed. To skip signing:

```sh
MP_LOCAL_SIGNING=none make mac-local-build
```

Each development or release signature has its own Accessibility permission
grant. Keep the bundle identifier `com.techdevix.meetingpulse` stable.

## Build and test the viewer

From `viewer/`:

```sh
pnpm install --frozen-lockfile
pnpm run check
pnpm run lint
pnpm test
pnpm run format:check
pnpm run build
```

The build reads required values from `.env`; missing or malformed values must
fail rather than fall back to a production project.

## Test Swift packages

Run the package suites from the repository root:

```sh
for package in MPCore MPSupport MPDetection MPSync MPUI; do
  (cd "mac-app/Packages/$package" && swift test)
done
```

Run the repository lint and secret scan when applicable:

```sh
make lint
gitleaks detect --no-git
```

Changes involving Accessibility, sleep/wake, pairing, or real meetings also
need the relevant manual scenarios in `docs/acceptance-0.1.md`. Unit tests do
not turn an unperformed real-device scenario into a pass.

## Contribution workflow

1. Start from the current default branch and create a focused feature or fix
   branch.
2. Read `PRODUCT.md`, `docs/02-meetingpulse-spec.md`, and the relevant copy or
   decision document before changing behavior.
3. Make the smallest complete change. Keep user-facing copy in
   `docs/copy/deck.md` and record new architectural decisions in
   `docs/decisions/`.
4. Run the checks for the native, viewer, database, or documentation surface
   you changed.
5. Review `git diff` for secrets, generated files, unrelated edits, and
   accidental changes to the privacy boundary.
6. Open a pull request with a concise summary, the checks that passed, and any
   manual scenarios that still need a real Mac, phone, browser, or meeting.

Prefer focused commits and explain behavior changes. Do not change signing
identities, the bundle identifier, retention behavior, or state semantics
without updating the corresponding security, specification, and acceptance
documentation.
