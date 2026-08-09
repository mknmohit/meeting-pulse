# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

Two surfaces ship together. The **viewer** is `web`: a static page opened on a phone or laptop browser. The **owner app** is native macOS (Swift 6, SwiftUI `MenuBarExtra`, macOS 14+), which follows macOS Human Interface Guidelines rather than this file's web guidance. Where the two disagree, the native surface follows the platform.

## Stack

Decided in the specification, not delegated.

- Viewer: Astro with `output: "static"`, TypeScript strict, plain HTML/CSS/TS components, no UI framework, `supabase-js`, deployed to Cloudflare Pages on a custom subdomain.
- Owner app: Swift 6, SwiftUI `MenuBarExtra` with AppKit where required, Swift Package Manager, `supabase-swift`, macOS 14.0 minimum, Universal 2, App Sandbox disabled (required for Accessibility inspection), Developer ID signed and notarized.
- Backend: Supabase (Postgres, anonymous auth, row level security, `SECURITY DEFINER` RPCs). No Realtime. No custom server.

## Users

**The owner.** Works from home on a Mac. Spends the day in Google Meet calls in Chrome and Slack Huddles in the native Slack app. The owner installs the app once, grants Accessibility permission, and then wants to never think about it again. The owner is technical. The owner is the only person who ever sees the menu-bar surface.

**The viewer.** A paired person who is not technical and does not want to be. The viewer opens one page on a phone to answer a single question: is the owner on a call right now? The viewer checks it in the two seconds before reaching out. The viewer may check it many times a day or twice a week. The viewer will not read instructions, will not troubleshoot, and will abandon the product permanently if it is ever confidently wrong.

The viewer is the primary user of the web surface. Everything on that page is for the viewer.

## Product Purpose

Meeting Pulse answers one question for one viewer: is the owner on a call right now?

The macOS app watches Chrome and Slack through Accessibility APIs and publishes a single word to a private page. The owner can also set the state by hand for a chosen duration, and can flag "you can call anyway" while busy.

Success is that the viewer stops guessing and stops interrupting meetings, and that the owner stops being interrupted without ever having to update anything manually.

Failure is a confident wrong answer. A page that says Available while the owner is in a meeting is worse than no product, because it destroys the trust that makes the viewer check at all. The system is designed to fail closed: anything unknown, stale, or permission-blocked becomes "Status unavailable", never a guessed "Available".

## Positioning

A local macOS agent that detects arbitrary Google Meet calls in Chrome and native Slack Huddles without an extension, a bot, OAuth, or calendar access, and publishes only an availability state.

Neighboring products cannot truthfully copy this combination. Calendar-based status is wrong for impromptu calls. Slack status covers only Slack. Meet APIs cover only scheduled Meet events the API can see. The detection happens on the owner's own machine by reading window structure, which is why it works for any call the owner joins by any means.

## Constraints

These are product truth, not implementation preference. They must survive every future design decision.

**The privacy boundary is the product.** Only these values ever leave the Mac: the state (`available`, `busy`, `unavailable`), a `call_okay` boolean, an optional owner display name of at most 80 characters, and freshness timestamps. Never a meeting title, URL, participant, platform, duration, microphone or camera state, audio, video, screenshot, or screen content. Screen Recording permission is never requested.

**The viewer must never learn how the state was produced.** "Busy" must look identical whether it came from a detected meeting or from the owner pressing Set Busy. Override metadata and device identifiers are not readable by the viewer. Revealing that the owner manually set Busy is more socially loaded than the meeting data the product refuses to send.

**Fail closed, always.** Unknown detector state, missing permission, or a heartbeat older than three minutes renders "Status unavailable", never "Available".

**Not realtime.** Change-triggered writes, a 60-second owner heartbeat, and 30-second viewer polling while the page is visible and focused. Expected delay is roughly the poll interval. The design must not imply live-ness it does not have.

**The viewer's clock cannot be trusted.** Freshness is computed entirely from server-supplied timestamps.

**Open source, no committed secrets.** All deployment values are injected at build time with no fallbacks. MIT licensed.

**Cost stays inside free tiers** for one owner and one viewer.

## Accessibility

The viewer is used on a phone by a non-technical person, sometimes one-handed, sometimes in a dark room at night, sometimes in bright daylight.

- WCAG 2.2 AA: contrast at least 4.5:1 for body text, 3:1 for large text.
- State is never conveyed by color alone. It must survive greyscale and every common form of color blindness.
- Touch targets at least 44 by 44 CSS pixels.
- Visible keyboard focus.
- `prefers-color-scheme` and `prefers-reduced-motion` are both honored.
- The state region announces changes politely to screen readers.
- Legible and usable at 320 pixels wide.
- No third-party scripts except the pairing captcha, and only on the pairing screen. No analytics, no third-party fonts.

## Terminology

Fixed vocabulary. The same word means the same thing in the app, the page, the database, and the docs.

| Term | Meaning |
|---|---|
| Owner | The person running the Mac app |
| Viewer | The paired person reading the status page |
| Available / Busy / Status unavailable | The only three states the viewer ever sees |
| Call okay | The owner's flag that calling is fine despite being busy |
| Override | A manual Busy or Available set by the owner, with an expiry |
| Pairing code | The 10-character code that links one viewer to one owner until the owner rotates or revokes it |
| Recovery phrase | The 26-character secret that reattaches a device after local identity loss |
| Stale | Last heartbeat older than three minutes, which renders as Status unavailable |

## Open decisions

- Public wordmark treatment beyond the product name "Meeting Pulse".
- Whether the viewer surface later supports more than one viewer per owner.
