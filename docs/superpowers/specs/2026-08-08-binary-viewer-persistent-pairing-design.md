# Binary viewer and persistent pairing

## Context

Meeting Pulse currently exposes the full internal status model to the viewer:
Available, Busy, and Status unavailable. Pairing codes expire after ten
minutes, which forces the viewer to re-enter a code when the initial pairing
does not happen immediately.

The product only needs to answer one question for the viewer: whether the
owner is currently in a meeting. The owner still needs the existing manual
controls and the detector must still observe meeting end transitions so that
the viewer can leave the meeting state.

## Goals

- Render exactly two paired-viewer messages:
  - `In a meeting` when the effective internal state is `busy`;
  - `Meeting status unavailable` for every other effective result, including
    confirmed inactive, unavailable, stale, offline, and unsupported schema.
- Keep the owner name, last-checked line, and manual refresh control.
- Hide call-okay, source, override, and other internal status details from the
  viewer.
- Make one pairing code persistent until the owner manually rotates or
  revokes it.
- Generate a shareable viewer link containing the code in a URL fragment.
- Keep up to five active viewer devices per owner device.
- Preserve the existing internal status model, owner controls, fail-closed
  sync behavior, anonymous auth, polling, and privacy boundary.

## Non-goals

- Do not remove Meet or Slack end detection from the Mac app.
- Do not remove manual Busy/Available overrides or the call-okay control from
  the owner app.
- Do not replace the internal three-state database model with a boolean.
- Do not add Realtime, a new authentication service, or unbounded viewer
  capacity.
- Do not put the raw pairing code in database columns, query strings, request
  paths, analytics, or logs.

## Considered approaches

1. **Persistent pairing code plus share link.** Reuse the current pairing
   table and RPC surface, remove automatic expiry, and place the normalized
   code in a fragment such as `VIEWER_ORIGIN/#code=CODE`. This gives the
   simplest wife-facing flow while retaining manual code entry as a fallback.
   The code is a bearer secret until rotation.
2. **Persistent pairing code only.** This has the smallest surface area, but
   requires manual entry again after browser storage is cleared and does not
   provide a convenient share action.
3. **Separate high-entropy link token and fallback code.** This provides the
   strongest credential separation, but requires a new token table, RPCs, and
   owner UI that are unnecessary for the one-owner MVP.

The selected approach is persistent pairing code plus share link. The link is
the primary sharing method, with manual code entry retained for recovery.

## Design

### Viewer projection

The Mac and database continue to publish:

```text
state      : available | busy | unavailable
call_okay  : boolean
last_seen  : server timestamp
```

The viewer maps the effective result at the presentation boundary:

| Internal/effective result | Paired viewer |
| --- | --- |
| `busy`, fresh | `In a meeting` |
| `available`, fresh | `Meeting status unavailable` |
| `unavailable` or stale | `Meeting status unavailable` |
| offline fetch or too-new schema | `Meeting status unavailable` |

This deliberately avoids telling the viewer that the owner is free when a
meeting was not detected. A detected meeting still changes the display to
`In a meeting`; the end transition publishes a non-busy state and returns the
display to the neutral message.

The paired page keeps the optional owner name, the large status message, the
server-derived last-checked label, and manual refresh. It does not render
call-okay, detection source, override metadata, or separate unavailable/offline
headlines. The unpaired screen remains necessary for first connection and
recovery.

The viewer continues focused/visible polling and server-time freshness
calculation. "Not listening for idle scenarios" applies to the viewer's
presentation, not to the Mac detector: the detector must sample after a call
ends to publish the transition away from `busy`.

### Persistent pairing lifecycle

There is one active pairing code for a device:

1. The owner selects **Create viewer link**.
2. The Mac generates a normalized ten-character code and stores its raw value
   in Keychain.
3. The owner app creates the link from the configured viewer origin:
   `VIEWER_ORIGIN/#code=CODE`.
4. The owner can copy the link or the code at any time.
5. The viewer reads the fragment, solves Turnstile on first claim, restores or
   creates its anonymous session, and calls `claim_pairing_code`.
6. After a successful claim, the viewer removes the fragment with
   `history.replaceState` and relies on the persisted anonymous session.
7. If browser storage is cleared, opening the saved link repeats the claim
   without requiring the owner to create another code.
8. **Rotate viewer link** revokes the active code and all viewer bindings, then
   creates a replacement. **Stop sharing** invalidates the code and all active
   viewer bindings without creating a replacement.

The pairing window has no countdown or automatic regeneration. Rotation and
revocation are explicit owner actions with confirmation.

### Database and RPC behavior

The current `pairing_codes` table remains the source of truth:

- `expires_at` becomes nullable; newly created persistent codes use `NULL`.
- `claimed_at` remains an audit timestamp and no longer makes a persistent
  code unusable.
- `create_pairing_code` revokes every active code for the device before
  inserting the new persistent row.
- `claim_pairing_code` accepts a non-revoked persistent row whose expiry is
  null, records the first claim, and remains reusable.
- A successful claim keeps up to five active viewer bindings for the device.
  Claims are serialized per device; a sixth distinct claim hard-deletes the
  oldest binding by `created_at` before creating the new binding.
- Active viewer bindings expire 30 days after `created_at`. Reads and owner
  lists ignore expired bindings immediately, and retention cleanup deletes them.
- The owner can soft-revoke a viewer or hard-delete its binding without
  deleting the anonymous auth user.
- `rotate_pairing_codes` revokes every active code and viewer binding for the
  device, including previously claimed codes and sessions.
- Expiring legacy rows remain invalid when their non-null expiry is in the
  past.

The database continues to store only the SHA-256 hash of the normalized code.
The existing throttling and Turnstile protection remain in place for claims.
Status reads continue through `get_paired_status`; no viewer client receives
device identifiers or pairing metadata.

The Mac configuration gains a required viewer origin used only for link
generation. It is injected through the ignored local configuration file and
has no hardcoded production fallback.

### Data flow

```text
Meet/Slack AX detection
  -> reducer (existing internal state and controls)
  -> publish_status (existing RPC)
  -> get_paired_status (existing viewer read)
  -> freshness check
  -> two-message viewer projection

Owner creates persistent code
  -> hashed pairing_codes row
  -> Keychain raw code
  -> viewer-origin fragment link
  -> Turnstile + anonymous session
  -> claim_pairing_code
  -> persisted viewer session
```

No meeting title, URL, participant, platform, duration, audio, video,
screenshot, or recovery secret is published to Supabase. The raw pairing code
is intentionally shared only through the owner-controlled link/code flow; it
is never stored server-side or written to logs.

## Failure handling

- Unknown, permission-blocked, stale, offline, and malformed states never map
  to `In a meeting`; they use the neutral `Meeting status unavailable`
  message.
- A revoked or invalid link returns to the unpaired screen with a request for
  a new link/code.
- A link fragment is cleared only after a successful claim.
- A failed claim leaves the fragment available for retry and does not create a
  false paired state.
- A rotated code invalidates old links and active viewer sessions on the next
  claim/read; the new link is required to restore access.
- If the owner loses local Keychain identity, the existing recovery flow
  remains unchanged.

## Verification

### Database

Add pgTAP coverage for:

- persistent code creation with no expiry;
- repeated successful claims of the same active code;
- rotation invalidating a previously claimed code;
- rotation and revoke invalidating both code and viewer binding;
- five active viewer bindings per device and oldest-first sixth-claim
  eviction;
- legacy expired-code rejection;
- hash-only storage and existing throttle/RLS negatives.

### Viewer

Add tests for:

- `busy` mapping to `In a meeting`;
- every non-busy state and freshness failure mapping to
  `Meeting status unavailable`;
- owner-name rendering;
- hidden call-okay/source/override details;
- fragment normalization, automatic claim, successful fragment removal, and
  retry after a failed claim;
- persistent session reload after the original link is gone.

### Mac app and acceptance

Add tests for pairing-secret persistence and link construction. On a real
machine, verify:

- active Meet or Huddle shows `In a meeting`;
- ending it returns to `Meeting status unavailable`;
- the page remains paired after ten minutes and a reload;
- opening the saved link after browser storage is cleared re-pairs;
- rotating the link rejects the old link and accepts the new one;
- the viewer never shows a confident free/available message during permission,
  network, or freshness failures.

## Rollout

1. Apply the additive pairing migration and RPC changes.
2. Ship the Mac app's persistent code, Keychain, link, and rotation UI.
3. Ship the viewer's two-message projection and fragment auto-claim.
4. Run the database tests, viewer tests, and real-device acceptance matrix.

## Amendment: multiple viewer hosts

The owner may publish the same viewer through more than one domain. The Mac
configuration uses a scheme and a comma-separated host list:

```text
MP_VIEWER_SCHEME = https
MP_VIEWER_HOSTS = meeting-pulse.techdevix.com,og.techdevix.com
```

The scheme and hosts remain separate because `//` starts a comment in
`Config.xcconfig`. The app trims each host, rejects empty entries, duplicate
hosts, query strings, fragments, and unsupported schemes, then constructs one
validated URL per host.

The pairing window shows the hosts as equal choices. Each copy action produces
the same persistent `#code=` fragment on its selected host. The database,
viewer authentication, persistent code, and rotation behavior do not change.
Both domains use the same viewer build and Supabase project.

Tests cover one and multiple hosts, whitespace normalization, duplicate and
malformed entries, and link generation for every configured host.
