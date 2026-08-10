# Meeting Pulse social preview image design

## Context

The Astro landing site currently uses a product screenshot as the default
Open Graph and Twitter image. Screenshots are useful on the page but are not
legible or emotionally specific enough when rendered as a small social link
preview. Meeting Pulse should be recognizable as a native macOS app that lets
someone close to the host know whether a call can wait.

## Goal

Create one reliable, branded social preview image for the Meeting Pulse
landing site that:

- communicates the host-to-loved-one use case within a quick glance;
- remains readable at common social preview sizes;
- uses the existing Meeting Pulse visual identity;
- avoids exposing real meeting content or implying calendar access; and
- works across Open Graph and Twitter/X consumers.

## Selected direction

Use a static 1200 x 630 PNG with a warm two-surface composition:

- The left side carries the Meeting Pulse label and the headline
  “A small signal for your people.”
- The right side shows a compact native macOS host card with “In a meeting”
  handing off to a private guest viewer card with “Call okay”.
- A restrained arrow connects the two surfaces to make the product flow
  understandable without additional copy.
- The palette uses the existing coral brand mark, warm off-white surfaces,
  muted navy text, and green status accents.
- Safe margins and large type preserve legibility when a platform crops or
  scales the image. The cards contain only illustrative status text.

This is preferred over a screenshot-only treatment because product UI text
becomes too small at preview size, and over SVG-only delivery because social
crawlers do not consistently render SVG Open Graph images.

## Landing-site integration

Add the asset at:

`landing/public/images/meeting-pulse-social-preview.png`

Update `landing/src/layouts/BaseLayout.astro` so the asset is the default
image for all pages. Keep the existing `image` prop as an escape hatch for
future page-specific previews. The metadata should include:

- `og:image` pointing to the absolute site URL for the new PNG;
- `og:image:alt` describing the host app and private guest viewer;
- `og:image:width` of `1200`;
- `og:image:height` of `630`;
- `twitter:card` set to `summary_large_image`;
- `twitter:image` and `twitter:image:alt` matching the same asset and
  description.

No runtime image generation or network request is required.

## Validation

Run the existing landing checks:

1. `npm run check`
2. `npm run build`

Inspect the generated `dist` output to confirm the PNG is copied and the
homepage HTML contains the absolute image URL, dimensions, and alt text. The
working tree must retain any unrelated user edits.

## Out of scope

- Reworking the landing page’s visual system or copy outside the social
  metadata.
- Creating separate previews for every landing page.
- Adding a new image-processing dependency or runtime image endpoint.
