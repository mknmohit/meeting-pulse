# Local macOS Release Packaging Design

## Scope

Meeting Pulse needs a repeatable local distribution path for release `0.0.1`.
The path must produce separate `arm64` and `x86_64` DMGs without an Apple
Developer Program account, install the validated app into `/Applications`, and
document the resulting Gatekeeper limitation. The root README and contribution
documentation also need to describe the current macOS app and Astro viewer
instead of the earlier project-phase placeholder.

The GitHub release is a draft built from the current committed `HEAD`. Existing
working-tree changes are intentionally excluded from its tag and release
assets. The release bundle version is patched to `0.0.1` during packaging
without changing the tagged source metadata.

## Packaging architecture

The existing DMG helper remains the single source of truth for Finder layout
and image creation. It is parameterized so it can package either target
architecture and version instead of assuming the arm64 local build and
`0.1.0`.

Three shell entrypoints form the local workflow:

- `mac-app/Tools/build-release.sh` builds an explicit target architecture,
  applies Release optimization and no-debug-info overrides, patches the
  bundle version, validates the app, invokes the DMG helper, and installs the
  app.
- `mac-app/Tools/build-release-arm64.sh` calls the shared helper with `arm64`.
- `mac-app/Tools/build-release-x86_64.sh` calls the shared helper with
  `x86_64`.

The entrypoints do not inspect or restrict the host architecture. Xcode is
asked to build the requested target architecture, so either Mac can produce
either asset when its installed toolchain supports it.

Release builds use:

- Xcode `Release` configuration.
- Whole-module Swift compilation and `-O`.
- Dead-code stripping and installed-product stripping.
- Disabled testability and debug-information generation.
- Explicit `ARCHS` and `ONLY_ACTIVE_ARCH`.
- Ad-hoc code signing only; no Developer ID identity, notarization, or
  telemetry is introduced.

The helper stages a validated app, creates
`Meeting-Pulse-0.0.1-arm64.dmg` or
`Meeting-Pulse-0.0.1-x86_64.dmg`, verifies the image, and replaces
`/Applications/Meeting Pulse.app` only after the build succeeds. A failed
install leaves the existing application in place. The DMG welcome page states
that ad-hoc builds require a one-time Finder `Open` action or quarantine
removal; they cannot provide trusted double-click installation without
notarization.

## Documentation

The root README becomes the navigation point for:

- Product purpose, architecture, and privacy boundary.
- macOS app and viewer feature inventory.
- macOS, Xcode, Node, and pnpm prerequisites.
- Configuration from the committed example files.
- Separate arm64 and x86_64 local build commands and output paths.
- Viewer production build and test commands.
- Contribution workflow and safety rules.

`CONTRIBUTING.md` contains the detailed contributor workflow, architecture
build commands, viewer checks, Swift package checks, and pull-request hygiene.
`viewer/README.md` is replaced with project-specific Astro instructions.
`docs/setup/release.md` distinguishes local ad-hoc distribution from future
Developer ID/notarized distribution. A `CHANGELOG.md` records the `0.0.1`
features and the draft release's distribution status.

No documentation mentions plans to make the repository public.

## Release workflow

1. Validate the shell and Python helpers and run the existing repository checks.
2. Build and install both architecture variants from the working tree to
   verify the scripts.
3. Export `git archive HEAD` into a temporary directory, copy only the ignored
   local `Config.xcconfig` and the packaging helpers needed for the release,
   and build both DMGs there.
4. Verify each DMG's architecture, bundle version, checksum, and `hdiutil`
   image integrity.
5. Create draft GitHub release `v0.0.1` at the current committed `HEAD` with
   both DMGs and the changelog as release notes.

No reset, stash, rebase, forced ref update, or unrelated working-tree cleanup
is part of this workflow.

## Error handling and validation

The scripts fail on missing configuration, missing tools, unsupported target
architectures, failed Xcode builds, missing app output, version/architecture
mismatches, DMG creation errors, or failed verification. The installer uses a
staged replacement and does not hide errors. Existing signing/notarization
automation remains available for a future trusted release and is not used for
the local `0.0.1` draft.
