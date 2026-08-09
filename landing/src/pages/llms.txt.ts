import type { APIRoute } from "astro";

export const GET: APIRoute = ({ site }) => {
  const origin = (site?.toString() || "http://localhost:4321").replace(/\/$/, "");
  const body = `# Meeting Pulse

Meeting Pulse is an MIT-licensed open-source macOS menu-bar app paired with a private browser viewer. It answers whether the owner is in a meeting before someone calls.

## Product

- Native owner app for macOS 14 or later.
- Local detection for supported Google Meet in Chrome and native Slack Huddles.
- Private viewer with a small availability state and optional call-okay message.
- Manual Busy or Available controls for the owner.
- Explicit unavailable, stale, offline, and revoked states.

## Privacy boundary

Meeting Pulse does not publish meeting titles, URLs, participants, audio, video, screenshots, OCR, or screen contents to viewers. It does not require a browser extension, Slack bot, OAuth, calendar access, or Screen Recording.

## Canonical pages

- [Home](${origin}/)
- [Features](${origin}/features/)
- [How it works](${origin}/how-it-works/)
- [Privacy](${origin}/privacy/)
- [Download](${origin}/download/)
- [FAQ](${origin}/faq/)
- [Open source](${origin}/open-source/)
- [Docs](${origin}/docs/)
- [GitHub](https://github.com/mknmohit/meeting-pulse)
`;

  return new Response(body, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
};
