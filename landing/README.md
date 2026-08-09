# Meeting Pulse landing site

This directory contains the public Astro marketing site. It is separate from
the private viewer app.

## Local development

```sh
npm install
npm run dev
```

## Cloudflare Pages

- Build command: `npm run build`
- Build directory: `dist`
- Environment variables:
  - `SITE_URL=https://your-marketing-subdomain.example`
  - `PUBLIC_VIEWER_URL=https://your-viewer-subdomain.example`

`SITE_URL` is used for canonical URLs, Open Graph URLs, `robots.txt`,
`llms.txt`, and the generated sitemap. Set it to the final marketing origin
before deploying.

`PUBLIC_VIEWER_URL` is the live viewer origin (e.g. `https://app.meeting-pulse.techdevix.com`).
It powers the "Open viewer" button in the header and the homepage CTA.
Leave it empty in local development if you do not want the link to render.

## Product assets

`SCREENSHOT-AUDIT.md` records which light/dark product screenshot pairs are
used on the public site and which are intentionally held back.
