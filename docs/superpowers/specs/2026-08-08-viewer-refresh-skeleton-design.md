# Viewer refresh skeleton

## Context

On a browser refresh, the viewer's server-rendered pairing section is visible
before the client script runs. The viewer then starts asynchronous session and
status restoration. A user who is already paired can therefore see the
"Enter the code" screen briefly before the paired board is rendered.

The viewer already has separate pairing and board states, persistent Supabase
sessions, and a poller that performs the first read during boot. The fix should
remove only the initial paint race and preserve those existing flows.

## Goals

- Show a shimmer/skeleton loading shell on the initial paint.
- Keep the pairing form and board hidden until the first auth/status read
  settles.
- Reveal the existing pairing form only when no session is present.
- Reveal the existing board for paired status results and paired-session fetch
  failures.
- Preserve hash-based auto-claim, persistent sessions, polling, refresh, and
  current error handling after initialization.

## Non-goals

- Do not change Supabase session persistence or pairing RPC behavior.
- Do not add a new loading route, client framework, or storage mechanism.
- Do not change the viewer's paired status copy or polling interval.
- Do not hide the pairing form after the initial hydration has completed.

## Considered approaches

1. **Initial hydration gate with shimmer skeleton (selected).** Keep the
   server-rendered loading shell visible, hide both content sections, and
   reveal the appropriate section after the first read settles. This directly
   fixes the pre-script flash and makes loading intentional.
2. **CSS-only concealment.** Hide the pairing form until JavaScript reveals it.
   This is a smaller change, but it provides no explicit loading state and
   leaves the initial UI ambiguous.
3. **Client-side session restoration before rendering.** Read browser session
   state before choosing a view. This duplicates Supabase behavior, cannot
   resolve the paired status synchronously, and still needs a loading fallback.

## Design

### Initial markup and visual state

Add a loading section to the viewer page with a concise loading label and
shimmer blocks that match the page's existing dark station styling. The
loading section is visible in server-rendered HTML. Add `hidden` to both the
board and pairing sections so the pairing form cannot be painted before
JavaScript executes.

The loading shell should:

- occupy the first viewport without shifting the page when it is removed;
- use the existing color tokens and a short, looping shimmer animation;
- honor `prefers-reduced-motion` by disabling the animation;
- expose an accessible loading label without exposing the hidden pairing form.

### Hydration state

`boot()` will track whether the initial read has settled. Its renderer will
keep the loading section visible and both content sections hidden while that
flag is false. Once the first read completes, the renderer will hide the
loading section and apply the current display-state rules:

- no Supabase session: show the pairing form;
- paired status: show the board;
- paired-session status fetch failure: show the neutral board with existing
  offline/error presentation;
- subsequent polling or manual refresh: use the current board/pairing behavior
  without re-entering the loading state.

The first `read()` will mark hydration complete in a `finally` block so both
successful responses and errors leave the page usable. The existing early
return for a missing session remains intact; the final hydration render runs
after that return.

### Data flow

```text
server HTML
  -> loading shell visible; board and pairing hidden
  -> boot()
  -> initial read: restore Supabase session and fetch paired status
  -> hydration settles
  -> hide loading shell
  -> reveal pairing form or paired board
  -> existing poller and manual refresh continue
```

Hash-based auto-claim remains available during boot. It still claims the code,
clears the fragment only after success, and relies on the persisted anonymous
session afterward. The loading shell prevents the initial pairing markup from
flashing while that flow starts.

## Failure handling

- A missing session resolves to the existing pairing form after the skeleton
  disappears.
- A paired session with a failed status read remains on the neutral board and
  uses the current offline/error copy.
- A failed hash claim leaves the fragment available for retry and reveals the
  existing pairing UI once initial hydration settles.
- No failure path reveals a stale or partially initialized pairing form before
  the first read has completed.

## Verification

Add focused viewer coverage for the hydration transition:

- loading is the only visible state before the initial read settles;
- a confirmed no-session result reveals pairing;
- a confirmed paired result reveals the board;
- an initial read error reveals the neutral board rather than pairing when the
  session is known to exist;
- later polling and refresh do not re-show the skeleton.

Run the existing viewer test, type-check, lint, and build commands. On a real
refresh with a persisted paired session, the acceptance criterion is that the
pairing form is never visible before the paired board or neutral board appears.
