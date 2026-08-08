# Station-inline Turnstile verification

**Date:** 2026-08-08

**Status:** Design approved; spec review pending

## Summary

Meeting Pulse will stop presenting Cloudflare Turnstile in a separate AppKit
panel. The existing Station window will be the only first-run surface. During
the first authenticated registration, Turnstile will appear as a compact status
rail inside the Watch setup checklist, alongside the private viewer-link step.
When the token and registration complete, the rail will disappear with the
existing motion tokens and the checklist content will close the resulting
space smoothly.

The authentication and Supabase security flow will not change. First
registration remains automatic because the owner must have an authenticated
device before Meeting Pulse can publish status. A cached valid session means
later launches do not show Turnstile.

## Context and root cause

`AppLaunchCoordinator.start()` creates a `WKTurnstileProvider` for a first
registration and passes its WebView to `showTurnstile()`. That method creates a
titled `NSPanel`, centers it, activates the app, and keeps it alive until
runtime startup succeeds. The Station-first setup change removed the old
onboarding route but did not remove this independent authentication surface.

The current provider already owns the Cloudflare bridge and returns a token
through `TurnstileGate`. Only the presentation boundary is wrong.

## Goals

- Have no Turnstile modal, panel, sheet, or separate verification window.
- Open Station automatically when first registration needs user interaction.
- Render the existing Turnstile WebView inside the Watch setup content.
- Keep the verification context near the private viewer-link setup step.
- Hide the verification rail automatically after a successful token and
  registration.
- Animate both the widget removal and the surrounding content collapse.
- Keep retry behavior inline and explicit when verification or startup fails.
- Preserve the current authenticated Supabase and RLS behavior.
- Keep the later-launch path free of Cloudflare UI when the cached session is
  valid.

## Non-goals

- Removing Turnstile or weakening Supabase authentication and captcha checks.
- Changing Supabase RPCs, grants, RLS policies, pairing-code semantics, or
  recovery security.
- Moving registration behind the "Do this later" action. Publishing requires an
  authenticated device and must remain reliable after setup is deferred.
- Redesigning the Station sidebar, mast, or non-Watch sections.
- Deleting the legacy onboarding source files.

## User experience

### First registration

1. The launch coordinator loads configuration and checks for an existing local
   device registration.
2. When registration is missing, it creates the existing WebKit provider,
   attaches its WebView to the main-screen presentation state, and opens Station
   before awaiting runtime startup.
3. Watch shows the existing setup checklist. The private-link row gains a
   compact verification rail with the native Turnstile widget and a short
   progress message.
4. The runtime waits for the normal Turnstile token, anonymous session, and
   device registration. No second window is opened.
5. After successful registration, the WebView is removed and the rail collapses
   using the existing quick motion. The checklist remains in place, ready for
   the owner to create a private viewer link or defer it.

The verification is visually associated with the link setup because that is
the owner's first network connection task, but it is not deferred until the
link button. Deferring authentication would leave the core status publisher
unable to publish after the owner chooses "Do this later".

### Cached session

When the local device registration and a valid Supabase session already exist,
the coordinator uses the unavailable provider as it does today. No WebView,
verification rail, or Cloudflare content is attached to Station.

### Failure and retry

If Turnstile, anonymous sign-in, registration, or the rest of startup fails,
the WebView is removed and the existing inline Watch failure banner remains the
source of truth. Its retry action recreates the provider and presentation state,
opens no panel, and reruns the first-registration launch sequence. No token or
credential is displayed or logged. Recovery flows remain outside this change.

## Architecture

### Presentation state

`PulseStore` will expose a small main-actor presentation state for the
Turnstile surface:

- hidden, with no WebView attached;
- verifying, with the provider WebView attached;
- failed, with the normal setup failure banner handling the message.

The WebView handle is UI-only state and is never sent to the server or included
in `StatusPayload`. The state is cleared after success, failure, and retry
cleanup so a stale WebView cannot remain in the Station.

### SwiftUI host

MPUI will add a small `NSViewRepresentable` adapter that hosts the existing
`WKWebView` in a native SwiftUI view. The adapter will not own the provider,
token continuation, or authentication lifecycle. It only mounts and updates
the WebView supplied by the app target.

The Watch section will render a compact status rail in the private-link setup
row when the store is verifying. The rail will use the existing spacing,
typography, colour, and motion tokens. It will reserve only the compact widget
height, use a stable accessibility label, and remove itself with a combined
opacity and height transition. Reduced-motion users will receive the same state
change without animated movement.

### Launch lifecycle

`AppLaunchCoordinator` will:

- remove `turnstilePanel` and `showTurnstile`;
- create and retain `WKTurnstileProvider` only for a missing registration;
- attach the provider's WebView and set the store to verifying;
- invoke a Station opener before awaiting `OwnerRuntime.start()`;
- clear the WebView and set the store hidden after successful startup;
- clear the presentation state during retry and failure cleanup.

`WKTurnstileProvider`, `TurnstileGate`, `AuthSessionBootstrap`, and the
Supabase transport contract remain responsible for token acquisition and
authentication. They do not present windows.

### Bundled HTML

`Resources/turnstile.html` will keep the same explicit Turnstile script and
message bridge, but its layout will be compact enough for an embedded rail:
no viewport-height grid, no modal-sized padding, and a bounded widget region.
The page will continue to report success, expiry, and failure through the
existing `meetingPulse` message handler.

## Error handling and accessibility

- A missing or invalid Turnstile resource remains a visible inline launch
  failure.
- A failed token or expired challenge never falls back to unauthenticated
  requests.
- The verification widget remains keyboard reachable and has a concise
  accessible status message.
- The compact rail will not use colour alone to communicate progress or
  completion.
- `accessibilityReduceMotion` disables the collapse animation while preserving
  the final layout.
- The existing setup failure headline, detail, and retry action remain inline
  in Watch.

## Implementation boundaries

Expected production changes:

- `mac-app/MeetingPulse/MeetingPulseApp.swift`
  - remove the panel lifecycle;
  - attach the provider to Station state;
  - open Station before first-registration startup blocks on Turnstile.
- `mac-app/Packages/MPSync/Sources/MPSync/TurnstileGate.swift`
  - keep provider ownership and token behavior unchanged unless a small
    presentation-safe accessor is required.
- `mac-app/Packages/MPUI/Sources/MPUI/Store/PulseStore.swift`
  - add the main-actor Turnstile presentation state.
- `mac-app/Packages/MPUI/Sources/MPUI/Components/`
  - add the WebKit host/compact status rail using existing tokens.
- `mac-app/Packages/MPUI/Sources/MPUI/Sections/WatchSection.swift`
  - place the rail in the private-link setup content.
- `mac-app/MeetingPulse/Resources/turnstile.html`
  - compact the embedded document layout.

Expected validation changes:

- MPUI tests for verifying-to-hidden and failure/retry presentation state.
- Existing MPSync Turnstile and auth bootstrap tests.
- Existing MPUI, MPSupport, and MPDetection test targets.
- Local macOS build and MPUI visual review for setup, dark mode, and reduced
  motion.

No Supabase migration or unauthenticated code path is part of this change.
