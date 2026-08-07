# Viewer favicon design

**Date:** 2026-08-08

**Status:** Approved for implementation

## Goal

Give the static Astro viewer the same recognizable Heart Thread identity as the
macOS app. The current viewer ships the Astro starter favicon, so browser tabs
and bookmarks do not identify Meeting Pulse.

## Chosen approach

Reuse the editable vector artwork already used by the macOS app:
`mac-app/MeetingPulse/Resources/heart-thread.svg`.

The viewer will keep a browser-friendly SVG favicon and add an ICO favicon for
user agents that request `/favicon.ico`. Both files will use the same Heart
Thread artwork and color palette rather than introducing a separate viewer
logo. The existing public asset paths will be replaced in place so generated
build output does not retain the Astro mark.

## Implementation

1. Replace `viewer/public/favicon.svg` with the Heart Thread SVG artwork.
2. Generate `viewer/public/favicon.ico` from the same artwork at standard
   16px and 32px sizes, preserving transparency and the rounded-square mark.
3. Add explicit `<link rel="icon">` declarations for the SVG and ICO files in
   `viewer/src/layouts/Base.astro`, which is shared by the viewer page.

No runtime code, state behavior, routes, or dependencies change. The favicon is
served as a static public asset and is available in both development and
production builds.

## Error handling and compatibility

There is no runtime failure path: browsers that support SVG can use the vector
asset, while browsers that do not can fall back to the ICO asset. The ICO is
kept as a real multi-size icon file rather than relying on a file extension
alone.

## Validation

- Run the viewer's existing `pnpm check` and `pnpm build` commands.
- Confirm the production build contains both favicon assets.
- Confirm the HTML head includes links to both favicon formats.

## Out of scope

- Redesigning the Heart Thread artwork.
- Adding Apple touch icons, web app manifests, or platform-specific theme
  metadata.
- Changing the macOS app icon or menu-bar icon.
