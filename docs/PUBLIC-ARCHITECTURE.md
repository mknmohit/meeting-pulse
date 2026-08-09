# Architecture (public overview)

Meeting Pulse ships in three pieces, each on its own timeline and its own
release process. Read this first if you are new to the codebase.

## The three pieces

### 1. macOS owner app (`mac-app/`)

A native Swift 6 app (SwiftUI `MenuBarExtra`, macOS 14+, Xcode 16.2).
Lives in the menu bar. Watches Chrome and Slack through Accessibility APIs,
computes an availability state, and writes it to Supabase.

Modular Swift Package layout under `mac-app/Packages/`:

- `MPCore` — types, reducer, models, schema versioning
- `MPSupport` — non-UI helpers (logging, identity, copy strings)
- `MPDetection` — Chrome + Slack inspectors
- `MPSync` — Supabase client, publish pipeline, overrides
- `MPUI` — SwiftUI surfaces (menu bar, settings, onboarding)

App-sandbox is intentionally off so the Accessibility inspector can read
window structure. Code signing is Developer ID, notarized.

### 2. Viewer (`viewer/`)

A static Astro site deployed to Cloudflare Pages. TypeScript, pnpm, Vitest.
Single page that resolves the owner's status from a Supabase RPC and renders
one of three states. `display_name`, optional `call_okay`, freshness
timestamps — that is the entire data surface it ever sees.

Build pipeline runs locally with `pnpm install && pnpm run build`. There is
no server runtime; if you add one, you have violated the spec.

### 3. Backend (`supabase/`)

Supabase project. Postgres schema, Row Level Security policies, RPCs for
status reads, a single cron-driven cleanup job. Migrations are committed
and apply forward only. The viewer reaches the database over HTTPS through
the anon key, which can read only the row the pairing code authorizes.

RLS is the privacy boundary on the backend side. Pairing codes and recovery
phrases never leave the owner's machine and never appear in any HTTP
request the viewer makes.

## How they communicate

```
  ┌────────────────────┐     accessibility      ┌─────────────────────┐
  │ macOS owner app    │  ───────────────────►  │  Chrome / Slack     │
  │ (menu-bar, native) │  ◄───────────────────  │  on the same Mac    │
  └─────────┬──────────┘                        └─────────────────────┘
            │ writes status, display_name,
            │ call_okay, freshness timestamps
            ▼
   ┌────────────────────┐         ┌─────────────────────┐
   │    Supabase        │ ◄────── │  Viewer (Astro)     │
   │  (Postgres + RLS)  │  HTTPS  │  static, on phone   │
   └────────────────────┘  anon   └─────────────────────┘
                                key
```

End-to-end, only this ever crosses the network:

- The owner app writes a status row on change, plus a 60-second heartbeat.
- The viewer polls the database every 30 seconds while visible and focused,
  reads one row, and renders it.

There is no realtime channel. There are no webhooks. There is no third-party
service between the Mac and the phone.

## Privacy boundary

The privacy boundary is the product. From `PRODUCT.md`:

> Only these values ever leave the Mac: the state (`available`, `busy`,
> `unavailable`), a `call_okay` boolean, an optional owner display name of
> at most 80 characters, and freshness timestamps. Never a meeting title,
> URL, participant, platform, duration, microphone or camera state, audio,
> video, screenshot, or screen content. Screen Recording permission is
> never requested.

Every change to the system must be checked against this sentence.

## Failure model

Unknown detector state, missing permission, or a heartbeat older than three
minutes renders "Status unavailable", never "Available". This is the
fail-closed rule. The system is designed so that the only way the page can
say "Available" is if a fresh heartbeat arrived in the last three minutes
and the detector can read at least one source.

The owner can always force "Busy" by hand and force "Available" by hand
(also with expiry). The hand override beats detector ambiguity: the system
trusts the owner's deliberate assertion more than its own uncertainty.

## Build order, end to end

1. `cd viewer && pnpm install && pnpm run build` — static bundle in `dist/`.
2. `cd mac-app && open Meeting\ Pulse.xcodeproj` — build and run the menu
   bar app. Configure `Config.xcconfig` from `Config.xcconfig.example`
   before signing.
3. `cd supabase && supabase start` — local stack. Apply migrations and
   load seed data.
4. Pair a phone with the owner app, then open the viewer URL on the phone.

## Repository layout

```
.
├── README.md                      ← entry point
├── CONTRIBUTING.md                ← how to contribute
├── SECURITY.md                    ← how to report vulnerabilities
├── CODE_OF_CONDUCT.md             ← community norms
├── SUPPORT.md                     ← where to ask questions
├── LICENSE                        ← MIT
├── PRODUCT.md                     ← what the product is
├── docs/
│   ├── PUBLIC-ARCHITECTURE.md     ← this file
│   ├── setup/                     ← how to get it running
│   ├── copy/                      ← user-facing strings source
│   ├── decisions/                 ← ADRs
│   └── *.md                       ← spec, plan, UI plan
├── .github/                       ← issue templates, CI, CODEOWNERS
├── viewer/                        ← Astro viewer
├── mac-app/                       ← Swift owner app
├── supabase/                      ← schema, RPCs, tests
└── Makefile                       ← repo-wide lint targets
```

## What is not part of the public repo

- `Config.xcconfig` — live configuration, gitignored
- `viewer/.env` — live Supabase keys, gitignored
- `.superpowers/` — local brainstorming tooling runtime state, gitignored
- `landing/` — marketing pages in progress, untracked
- `DESIGN.md` — internal design notes, gitignored

See `.gitignore` for the full list.
