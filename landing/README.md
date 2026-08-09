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
- Environment variable: `SITE_URL=https://your-marketing-subdomain.example`

`SITE_URL` is used for canonical URLs, Open Graph URLs, `robots.txt`,
`llms.txt`, and the generated sitemap. Set it to the final marketing origin
before deploying.

## Product assets

`SCREENSHOT-AUDIT.md` records which light/dark product screenshot pairs are
used on the public site and which are intentionally held back.
