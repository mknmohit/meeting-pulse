# Meeting Pulse

Meeting Pulse is a private macOS menu-bar app and browser page for one simple
question: is he on a call right now?

The Mac watches Chrome Google Meet calls and native Slack Huddles through
Accessibility APIs. The viewer receives only the current availability state,
the call-okay flag, an optional display name, and freshness timestamps. Meeting
details, URLs, participants, audio, video, screenshots, and screen contents
never leave the Mac. Screen Recording is not requested.

## Status

This repository is being built in phases. Chrome and Slack detection start
with empirical spikes before detector work begins. The viewer and backend
configuration require injected values; there are no production fallbacks.

Spike S1 selected the latched Chrome strategy: foreground Meet controls confirm
a call, and a Chrome window plus its tab-strip entry maintain the latch while
the call is in the background. Chrome-installed Meet PWAs are manual-only
until their Accessibility tree is measured.

Spike S2 selected Slack's dedicated Huddle window: its leave control confirms
the Huddle, and the window remains observable while Slack is unfocused or
minimized. Slack's ordinary main window is never treated as a Huddle.

## Repository

- `mac-app/` contains the native macOS app and Swift packages.
- `viewer/` contains the static Astro viewer.
- `supabase/` contains migrations and database tests.
- `docs/` contains the specification, implementation plan, decisions, and
  copy deck.

See `CONTRIBUTING.md` for local setup and checks. See `SECURITY.md` for the
signing and Accessibility permission constraint.
