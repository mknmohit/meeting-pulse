# Meeting Pulse marketing site design

**Date:** 2026-08-09  
**Status:** Approved for autonomous implementation

## Brief

Create a public, static, multi-page Astro marketing site for Meeting Pulse. The site will live in `landing/` and deploy to Cloudflare Pages. It must explain the macOS owner app and private viewer, use the supplied product screenshots, support light/dark mode with system-default detection and localStorage persistence, make open-source status and GitHub discoverable, and remain responsive from 320px upward.

## Product truth

Meeting Pulse is a privacy-first macOS menu-bar app paired with a private browser viewer. It answers one practical question: whether the owner is in a meeting before someone calls.

Approved claims for the public site:

- The owner app is macOS-native and uses macOS Accessibility APIs to detect Google Meet in Chrome and native Slack Huddles.
- The product does not require a browser extension, Slack bot, OAuth, calendar access, Screen Recording, screenshots, OCR, or meeting-content uploads.
- The viewer exposes a small availability signal rather than meeting titles, links, participants, audio, video, or screen contents.
- The system fails closed. Stale, uncertain, offline, revoked, or permission-blocked states are shown as unavailable or not connected rather than guessed as available.
- Owners can use automatic detection or manual Busy/Available controls, and can publish a separate “Call okay” signal.
- The project is MIT-licensed open source.
- The current product has a native macOS owner surface and a static browser viewer.

The site must not claim realtime updates, universal call detection, guaranteed accuracy, pricing, testimonials, customer counts, or notarized distribution. The public site should avoid unresolved implementation details such as secret storage lifetime and code lifetime.

## Goals and success criteria

1. A first-time visitor understands the owner-to-viewer flow within one screen.
2. A visitor can reach the macOS download path, GitHub repository, privacy explanation, and docs in one click from the header or footer.
3. The supplied dark/light screenshots are used as product proof, with meaningful alt text and no fabricated browser chrome.
4. Every public page has unique metadata, a canonical URL derived from a configurable site origin, semantic headings, and internal links.
5. The static build works without a server runtime, analytics, client-side framework, or required external service.
6. Theme preference is automatic on first visit, persists explicit user choices in localStorage, and is available from every page.
7. The UI remains usable at 320px, 375px, 414px, and 768px without horizontal scrolling or wrapped clickable labels.
8. Content reads like a careful product owner wrote it: plain, specific, privacy-forward, and honest about uncertainty.

## Information architecture

The marketing site is separate from `viewer/`. The viewer remains a product surface and is not part of this public sitemap.

```text
Homepage (/)
├── Features (/features)
├── How it works (/how-it-works)
├── Privacy (/privacy)
├── Download (/download)
├── FAQ (/faq)
├── Open source (/open-source)
└── Docs (/docs)
    ├── Install on macOS (/docs/install-macos)
    ├── Accessibility permission (/docs/accessibility-permission)
    ├── Pair a viewer (/docs/pairing)
    ├── Recovery (/docs/recovery)
    └── Troubleshooting (/docs/troubleshooting)
```

Header navigation uses the brand wordmark, Product links, Learn links, GitHub, and a Download CTA. The private viewer is not a primary navigation item. The footer repeats the high-value product, learn, project, and legal links without becoming a dense sitemap.

Internal linking:

- Home links to Features, How it works, Privacy, Download, and Open source.
- How it works links to integration details, pairing docs, Privacy, and Troubleshooting.
- Features links to How it works, Download, and relevant docs.
- Privacy links to Accessibility permission, Security/support guidance, and FAQ.
- Download links to Install on macOS, Open source, and Troubleshooting.
- Every docs page links to Download, Pairing, Privacy, and the next relevant doc.
- Every indexable page has at least two contextual internal links.

## Page content

### Homepage

Workbench structure: the product screenshots do most of the explaining. The hero uses the seed line “Meeting Pulse tells one person when to call you.” It is followed by a direct explanation, a two-surface owner/viewer visual, a four-step workflow, a privacy boundary section, a failure-state trust note, and a single final Download CTA.

Planned sections:

1. Hero: outcome, short explanation, Download and GitHub actions.
2. Product proof: menu-bar owner screenshot paired with viewer screenshot.
3. Workflow: detect locally, publish a small signal, check the private viewer, respect unavailable states.
4. Feature tour: automatic detection, manual controls, private pairing, recovery.
5. Privacy: what the Mac reads for detection and what never leaves it.
6. Open source: MIT license, public repository, support links.
7. Final CTA: Download Meeting Pulse for macOS.

### Interior pages

- **Features:** focused descriptions of detection, manual controls, private viewer, pairing/recovery, and trust states.
- **How it works:** an explicit four-stage sequence from local detection to viewer polling, with boundaries and stale-state explanation.
- **Privacy:** direct data boundary, permissions explanation, and “never uploads” list.
- **Download:** macOS 14+, Universal 2 context, GitHub release path, and a clear note that release signing/notarization status belongs to the release artifact.
- **FAQ:** visible question-and-answer blocks covering setup, Accessibility permission, viewer privacy, integrations, stale state, and open source.
- **Open source:** MIT license, GitHub, architecture overview, contribution/support links.
- **Docs:** compact index to the five setup and troubleshooting pages.
- **Docs detail pages:** task-oriented instructions with breadcrumbs and next-step links. Avoid exposing internal implementation plans wholesale.

## Visual direction

- **Genre:** modern-minimal.
- **Macrostructure:** Workbench. Product captures are the primary proof and the page is a guided tour rather than a generic feature-card stack.
- **Theme:** Cobalt-inspired cool near-white/cool charcoal system with one measured cobalt accent. Light and dark values preserve hue and shift lightness/chroma only.
- **Typography:** a geometric display role paired with a readable sans body role, with a mono outlier used only for tiny status labels and code-like metadata. Font declarations are tokenized and can fall back to local system faces.
- **Navigation:** N5 floating pill on wide screens, reduced to a compact header with a menu disclosure on narrow screens.
- **Footer:** Ft5 statement treatment on marketing pages, with the sentence “A small signal before a big interruption.” followed by compact grouped links. Docs pages use the same links but keep the closing line shorter.
- **Layout:** left-biased, screenshot-led, with an offset two-column proof section and a four-stage workflow. Avoid a uniform three-card grid and centered-everything composition.
- **Imagery:** use real supplied screenshots only. Use `<figure>` captions and alt text. Do not draw fake browser bars, phone frames, or traffic-light chrome around images.
- **Motion:** one restrained reveal-once sequence using opacity and transform only, plus small CTA/menu transitions. Respect `prefers-reduced-motion`.

## Theme behavior

The root document exposes `data-theme="light"` or `data-theme="dark"`:

1. If localStorage contains `meeting-pulse-theme`, apply that value before paint.
2. Otherwise, use `prefers-color-scheme`.
3. The theme control offers Light, Dark, and System. Selecting Light or Dark persists it. Selecting System removes the override and follows the OS.
4. The inline bootstrap is tiny and defensive. A malformed localStorage value falls back to the system query.
5. Screenshot pairs are selected with `<picture>` and CSS media queries so each image follows the active system theme. The site remains readable if the user explicitly selects a theme after page load.

## Technical architecture

The site is a plain Astro static build:

- Shared `BaseLayout.astro` owns metadata, canonical URL, Open Graph/Twitter tags, JSON-LD injection, theme bootstrap, skip link, and global stylesheet loading.
- Shared `Header.astro`, `Footer.astro`, `ThemeToggle.astro`, `ScreenshotFigure.astro`, `Breadcrumbs.astro`, and `PageIntro.astro` keep repeated surfaces consistent.
- Page content lives in `.astro` routes under `landing/src/pages/`.
- Global styles and tokens live in `landing/src/styles/tokens.css` and `landing/src/styles/global.css`.
- Small client behavior is plain TypeScript in `landing/src/scripts/site.ts`; no React runtime is required.
- Product screenshots remain under `landing/public/images/product-screens/`.
- Build configuration uses an environment-provided `SITE_URL`; local development falls back to `http://localhost:4321` only for development output.
- `@astrojs/sitemap` generates the indexable sitemap from `SITE_URL`.
- `robots.txt` references the sitemap and allows normal search/AI citation crawlers.
- `llms.txt` provides a concise, agent-readable product definition and links to canonical public pages.

No pricing page is included until pricing exists. No comparison pages are included until independent competitor research supports fair, substantive copy.

## SEO and AEO

Every route gets a unique title and description, a self-referencing canonical, `og:type`, `og:title`, `og:description`, `og:url`, and a social image path using a product screenshot or branded fallback. Pages use one `h1`, logical heading order, descriptive links, and direct answer paragraphs near section starts.

JSON-LD:

- `Organization` and `WebSite` site-wide.
- `SoftwareApplication` on the homepage when the public repository/download URL is verified.
- `WebPage` and `BreadcrumbList` on interior pages.
- `FAQPage` on the FAQ page only for visible questions and answers.
- `HowTo` on setup docs only when the steps are visible and complete.

The site will not add ratings, offers, reviews, or invented authors. The viewer is excluded from the marketing sitemap and marked `noindex` in its own app, not exposed as an indexable marketing route.

## Accessibility and responsive behavior

- Semantic `header`, `nav`, `main`, `section`, `article`, `figure`, and `footer` landmarks.
- One visible skip link, visible `:focus-visible` rings, minimum 44px controls, and keyboard-operable theme/menu controls.
- Images include width/height and meaningful alt text.
- Color never carries status meaning alone. State labels include text and shape/mark.
- Root uses `overflow-x: clip`; image grids use `minmax(0, 1fr)`.
- Clickable labels use `white-space: nowrap`; narrow nav collapses instead of wrapping.
- Section headings collapse to one column on small screens.
- Reduced motion disables spatial reveals and leaves opacity-only transitions.

## Validation

Run the existing project checks where applicable:

- `npm run build` from `landing/`.
- `npm run check` or `astro check` if exposed by the landing package.
- Static inspection of generated routes, `robots.txt`, sitemap, `llms.txt`, and JSON-LD.
- Browser check at 320px, 375px, 414px, 768px, and a desktop width for overflow, navigation, theme persistence, image pairing, and keyboard focus.

