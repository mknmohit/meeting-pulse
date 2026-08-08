# Contributing to Meeting Pulse

## Development setup

Meeting Pulse has a static Astro viewer, Supabase migrations, and Swift package
logic for the macOS app. Copy the committed example configuration files before
running a local build:

- `viewer/.env.example` is a human-facing template and must not build.
- `viewer/.env.ci` contains shape-valid, fake values for reproducible local
  builds.
- `mac-app/Config.xcconfig.example` is copied to the ignored
  `mac-app/Config.xcconfig`.

Never commit local configuration, tokens, pairing codes, recovery phrases,
diagnostic exports, or meeting content.

Development builds and release builds carry different code-signing
identities. Each build needs its own macOS Accessibility permission grant. If
you do not have an Apple Developer Program account, use the local-only build
below. It can be ad-hoc signed or unsigned, but it cannot be notarized or
distributed as a trusted release.

Keep the release bundle identifier and signing identity stable. Changing either
silently revokes the permission on installed copies.

### Local build without Apple Developer Program

The repository includes a local build path that does not require a team ID,
Developer ID certificate, or notarization profile:

```sh
make mac-local-build
open "build/local/Build/Products/Debug/Meeting Pulse.app"
```

The default build uses an ad-hoc signature. To build without signing at all:

```sh
MP_LOCAL_SIGNING=none make mac-local-build
```

For an optimized local artifact, use the Release configuration:

```sh
make mac-local-release
open "build/local-release/Build/Products/Release/Meeting Pulse.app"
```

macOS may require an Accessibility grant again after a local rebuild because
unsigned and ad-hoc signatures are not stable release identities. Do not upload
these bundles or present them as notarized releases.

## Checks

Run the checks that apply to your change from the repository root:

```sh
cd viewer && pnpm run check && pnpm run lint && pnpm test
```

Swift packages are tested independently:

```sh
for package in MPCore MPSupport MPDetection MPSync MPUI; do
  (cd "mac-app/Packages/$package" && swift test)
done
```

Run secret scanning before opening a pull request:

```sh
gitleaks detect --no-git
```
