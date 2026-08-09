# Meeting Pulse viewer

The viewer is a static Astro site. It runs in the browser and shows the latest
trustworthy status published by the paired macOS owner app. It does not expose
meeting source, title, duration, participants, override metadata, or device
identifiers.

## Requirements

- Node.js 22.12 or newer.
- pnpm.

## Configuration

Copy the template and fill in the required build-time values:

```sh
cp .env.example .env
```

Required variables:

- `PUBLIC_SUPABASE_URL`
- `PUBLIC_SUPABASE_ANON_KEY`
- `PUBLIC_STATUS_ORIGINS`
- `PUBLIC_TURNSTILE_SITE_KEY`

There are no source-code or production fallbacks. `.env.ci` contains fake
shape-valid values for local checks and must not be used as a deployment
configuration.

## Commands

Run from this directory:

```sh
pnpm install --frozen-lockfile
pnpm run dev
pnpm run check
pnpm run lint
pnpm test
pnpm run format:check
pnpm run build
pnpm run preview
```

The production build is written to `dist/`.

## Viewer behavior

- First pairing accepts a shared link fragment or a normalized ten-character
  code.
- Turnstile protects anonymous Supabase session creation and pairing claims.
- Returning visitors restore their anonymous session from browser storage.
- Status polling runs every 30 seconds only while the page is visible and
  focused.
- `Refresh now` performs an immediate fetch.
- Freshness is computed from server timestamps; stale, malformed, revoked, or
  offline states fail closed.
- Couple mode is an optional viewer-local preference. When enabled, it selects
  one curated phrase for the current status and keeps it stable until reload or
  a status change.
- The page supports responsive light/dark presentation, reduced motion, visible
  focus, screen-reader announcements, and color-independent state cues.
