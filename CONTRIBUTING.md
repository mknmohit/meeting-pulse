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
identities. Each build needs its own macOS Accessibility permission grant.
Keep the release bundle identifier and signing identity stable. Changing either
silently revokes the permission on installed copies.

## Checks

Run the checks that apply to your change from the repository root:

```sh
cd viewer && pnpm run check && pnpm run lint && pnpm test
```

Swift packages are tested independently:

```sh
for package in MPCore MPSupport MPDetection MPSync; do
  (cd "mac-app/Packages/$package" && swift test)
done
```

Run secret scanning before opening a pull request:

```sh
gitleaks detect --no-git
```
