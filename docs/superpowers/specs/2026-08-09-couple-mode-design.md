# Couple mode for the viewer

**Date:** 2026-08-09
**Status:** Approved design

## Context

The viewer is a single status board for a paired person who wants to know
whether the owner can be interrupted. The current board already maps the
trusted status projection to three display outcomes:

| Display outcome | Existing meaning |
| --- | --- |
| `meeting` | The owner is in a meeting and calling should wait |
| `callOkay` | The owner is in a meeting but calling is okay |
| `generic` | The status is unavailable or cannot be trusted |

The viewer currently renders an optional owner name above the signal shape and
also uses the name in some existing headlines. The new mode must remove only
the standalone name line above the shape. Existing named headlines remain
unchanged when the mode is off.

## Goals

- Add a viewer-local, opt-in mode named `Couple mode`.
- Keep the mode off by default and preserve the current viewer experience when
  it is off.
- Persist the mode choice in versioned browser storage.
- Pick a new curated phrase on page load, reload, or reopen when the mode is
  enabled.
- Pick a new phrase when the effective display outcome changes, but not on the
  freshness ticker or an ordinary poll that leaves the outcome unchanged.
- Maintain separate, hardcoded viewer-side phrase banks for all three display
  outcomes, targeting 360 reviewed phrases per bank.
- Use original English and Hinglish phrases with affectionate language that
  feels natural, homie, romantic, and clear about the underlying status.
- Allow a reviewed subset of phrases to include the owner name when it improves
  the line. Skip those phrases if no owner name is available.
- Remove the standalone owner-name line from both normal mode and Couple mode.
- Keep the existing card structure, state colors, background, status semantics,
  freshness handling, pairing flow, and fail-closed behavior.
- Keep the signal shape smaller in Couple mode so longer phrases have room.

## Non-goals

- No Supabase setting, owner-app setting, API field, or server-side copy.
- No change to the authoritative `available | busy | unavailable` state model.
- No change to the existing color mapping or status projection.
- No phrase rotation on the one-second ticker or every 30-second poll.
- No claim that an unavailable status means the owner is available.
- No scraped or copied phrase library.
- No separate visual identity or replacement of the harbour signal board.
- No emojis or decorative symbols added to the copy.

## Chosen approach

Use a persisted viewer-local preference and a state-aware phrase selector:

1. The viewer reads a versioned `Couple mode` preference from local storage.
2. The existing reading and freshness code projects the API response to the
   current display outcome.
3. When Couple mode is enabled, the board selects one phrase from the bank for
   that outcome and renders it with `textContent`.
4. The selected phrase remains stable until the page reloads or the effective
   display outcome changes.
5. When Couple mode is disabled, the existing canonical headline and supporting
   copy render exactly as they do today.

This keeps the feature private to the viewer, avoids a network dependency, and
does not create a second status pipeline.

## Surface and interaction

The paired viewer rail will contain:

- the existing checked-time sentence;
- the existing `Check again` button;
- a labeled `Couple mode` switch with an explicit on/off state.

The switch will be a button with `role="switch"` and an `aria-checked` value.
It will have a minimum 44 by 44 CSS pixel target and a visible keyboard focus
ring. The accessible label will communicate both the feature name and its
current state. The switch will not rely on color alone.

The preference key will be `meetingpulse.viewer.couple-mode.v1`. Invalid,
missing, or unavailable storage will leave the mode off. Storage failures will
not affect status reads, pairing, or board rendering.

The existing `data-name` presentation above the signal shape will be removed
from the page markup and element lookup. The owner name remains available to
the status-aware headline code and to reviewed name-aware Couple mode phrases.

## Visual behavior

Couple mode inherits the established enamel signal-board visual language:

- the plate size, placement, radius, shadow, background, and state color remain
  unchanged;
- the same cone, pennant, or mast continues to communicate the display
  outcome;
- the signal shape becomes smaller only while Couple mode is enabled;
- the headline and supporting text use the available content width and remain
  readable at the 320 px minimum;
- the existing state-change repaint and reduced-motion rules remain in force;
- turning the mode off immediately restores the canonical status copy.

The mode does not animate the page on load and does not add decorative motion.
If a status transition changes the display outcome, the existing repaint can
cover the phrase change. A mode toggle itself only changes copy and layout
state.

## Curated copy system

Create one dedicated viewer-side module containing three typed banks:

- `meeting`: affectionate lines that still mean "please wait";
- `callOkay`: affectionate lines that clearly mean "you can call";
- `generic`: affectionate lines that acknowledge that the status is not
  trustworthy or currently visible without implying availability.

Each phrase entry will carry its text and, when needed, a name-aware rendering
function or placeholder marker. Name interpolation will happen as plain text,
never as HTML.

The target is exactly 360 lines per bank when the quality review is complete.
The count is a target, not permission to keep a weak line. Any rejected line
will be replaced with a better original line before shipping.

The copy pass will:

- research affectionate vocabulary and usage from reliable public references;
- distinguish Hindi, Hinglish, and English meanings before using a term;
- avoid terms whose meaning, spelling, or tone is uncertain;
- use affectionate words in context instead of repeating a word as decoration;
- vary rhythm and intimacy without manufacturing awkward rhymes;
- keep meeting lines from inviting interruption;
- keep call-okay lines from sounding like a prohibition;
- keep generic lines honest about uncertainty;
- manually read every line for grammar, meaning, tone, and status accuracy;
- remove duplicates, near-duplicates, filler, and lines that sound unnatural.

Research will inform vocabulary only. The shipped lines will be newly authored
and will not reproduce web copy.

## Data flow

```text
status RPC
  -> existing response normalization
  -> existing freshness and display-state projection
  -> Couple mode preference
  -> state-specific phrase selection when enabled
  -> existing board headline/supporting targets
```

The selector will receive the display outcome, the optional owner name, and a
random source. It will filter out name-aware entries when no name exists,
choose one remaining entry, and return a fully rendered string. The random
choice will use the browser crypto random source where available and will not
be used for security decisions.

The selector will re-run only when:

- the first usable board render occurs;
- the page is reopened or reloaded;
- the Couple mode preference changes from off to on;
- the effective display outcome changes.

It will not re-run for a freshness-label update, a repeated poll result, or a
server timestamp update that leaves the display outcome unchanged.

## Failure and accessibility handling

- Missing or malformed preference storage keeps Couple mode off.
- An empty or malformed phrase bank is a build/test failure, not a silent
  runtime success path.
- A name-aware phrase is never selected without a valid trimmed owner name.
- The canonical copy remains the fallback whenever Couple mode is off or a
  phrase selection cannot be completed.
- The existing polite live region continues to announce the visible headline.
- All visible status meaning remains available as text and shape, not color
  alone.
- No status, freshness, pairing, or offline error changes its existing
  semantics.

## Verification and acceptance

Add focused viewer tests for:

- the switch defaulting off when no preference exists;
- preference persistence and invalid-storage fallback;
- removal of the standalone name line;
- canonical copy remaining unchanged with Couple mode off;
- phrase selection for all three display outcomes with a name and without one;
- phrase stability across repeated renders of the same outcome;
- phrase replacement after an effective outcome change;
- no phrase replacement on repeated polls with the same outcome;
- exact phrase-bank counts, non-empty strings, duplicate detection, and valid
  name-aware entries.

Run the existing viewer `check`, lint, formatting, test, and build commands.
Perform a browser smoke check at a desktop viewport and at 320 px wide. Run
the Impeccable detector once over the changed UI targets after implementation.

The feature is accepted when Couple mode is opt-in and viewer-local, the
canonical off-mode board is unchanged apart from removing the standalone name
line, each display outcome has a reviewed phrase bank, status semantics remain
honest, and all existing viewer behavior continues to pass.
