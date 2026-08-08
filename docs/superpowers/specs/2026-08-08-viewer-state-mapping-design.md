# Viewer status-state mapping

**Date:** 2026-08-08  
**Status:** Approved design

## Context

The `get_paired_status` RPC publishes a status projection containing `state`,
`call_okay`, freshness timestamps, and schema metadata. The authoritative
published state model is exactly:

```text
available | busy | unavailable
```

Supabase enforces this set in `current_status` and `publish_status`. The macOS
owner app uses the same three cases, and the viewer already declares the same
TypeScript union.

The viewer intentionally has a binary user-facing status:

| API state | Viewer rendering |
| --- | --- |
| `busy`, `call_okay: false` | Meeting |
| `busy`, `call_okay: true` | Meeting, but okay to call |
| `available` | Meeting status unavailable |
| `unavailable` | Meeting status unavailable |

The viewer also uses the neutral rendering for stale readings, unsupported
newer schemas, malformed freshness timestamps, and fetch failures. This is the
fail-closed behavior defined by the product specification.

## Goals

- Keep the supported state model explicit and consistent at the viewer
  boundary.
- Verify that all three supported API states map to the intended viewer
  behavior.
- Treat an unknown future API state as `unavailable` rather than allowing it to
  become an accidental positive status.
- Preserve validation of all other required response fields.

## Non-goals

- Do not add a fourth viewer state for "busy but call okay"; `call_okay` remains
  a flag on `busy`.
- Do not expose the distinction between `available` and `unavailable` in the
  current viewer copy.
- Do not change Supabase constraints, the RPC response shape, freshness
  thresholds, polling, pairing, or owner-app behavior.
- Do not clear a valid previous reading on ordinary network failure; existing
  freshness aging remains responsible for failing that reading closed.

## Considered approaches

1. **Tests and documentation only.** This confirms current behavior but leaves
   unknown future states dependent on strict response rejection.
2. **Normalize unknown states to `unavailable` at the viewer response
   boundary (selected).** This preserves the typed three-state model and
   immediately fails closed when a compatible backend adds a state.
3. **Reject unknown states and retain the prior reading.** This is strict, but
   can keep an old busy state visible until it ages out after a malformed
   response.

The selected approach best matches the product's fail-closed requirement while
keeping the change local to the viewer's external-data normalization.

## Design

### Response normalization

`viewer/src/lib/status.ts` will keep validating required booleans, timestamps,
and schema metadata. It will normalize the raw `state` string as follows:

- `available` remains `available`.
- `busy` remains `busy`.
- `unavailable` remains `unavailable`.
- Any other string, missing value, or future state becomes `unavailable`.

The normalized result still satisfies the existing `State` union, so the
freshness and board layers do not need a second state vocabulary.

### Viewer mapping

`viewer/src/lib/freshness.ts` remains the single display projection:

- only a fresh `busy` reading reaches a positive display;
- `call_okay` selects between the meeting and call-okay copy;
- every other valid state reaches `generic`, which renders
  `Meeting status unavailable`.

No markup or CSS changes are required.

### Tests

Add focused coverage for:

- `available` resolving to the generic neutral display;
- `unavailable` resolving to the generic neutral display;
- fresh `busy` with `callOkay: false` resolving to the meeting display;
- fresh `busy` with `callOkay: true` resolving to the call-okay display;
- an unknown raw API state normalizing to `unavailable` and therefore the
  generic display.

Existing malformed-field validation and freshness tests remain unchanged.

## Failure and accessibility handling

An unknown state cannot produce a meeting or call-okay rendering. It is
converted to `unavailable`, then follows the existing neutral copy and
accessible headline path. Network errors continue to age the last valid
reading rather than silently changing polling or pairing behavior.

## Acceptance

The implementation is complete when the viewer has one explicit source of
truth for `available`, `busy`, and `unavailable`; all supported mappings are
covered by tests; an unknown API state renders the neutral unavailable view;
and the existing viewer checks, tests, lint, formatting, and production build
remain passing.
