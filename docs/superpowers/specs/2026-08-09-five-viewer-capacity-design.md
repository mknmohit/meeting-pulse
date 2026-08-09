# Five-viewer capacity and owner controls

This supersedes the earlier three-viewer capacity decision.

## Context

Meeting Pulse currently lets a persistent pairing code leave only one active
viewer binding for an owner device. A successful claim revokes every existing
binding for that device. The owner already has a viewer list and a soft
`revoke_viewer` action, while the database retention job removes old terminal
rows.

The product should allow five people or devices to watch one meeting status
at the same time. No viewer read should write a last-used or heartbeat value.
When a fourth distinct viewer claims the persistent link, the oldest active
binding is removed so the new viewer can connect. Active bindings older than
30 days expire based on their existing `created_at` value. The owner must be
able to see active viewers, revoke access, and permanently delete a selected
viewer binding.

## Goals

- Allow at most five active viewer bindings per owner device.
- Admit a sixth distinct claim by removing the oldest active binding.
- Avoid adding or updating a last-used, heartbeat, or activity column.
- Expire active bindings 30 days after pairing age, using `created_at`.
- Clean expired and terminal viewer rows through the database cleanup path.
- Let the owner list active viewers and either soft-revoke or hard-delete one.
- Preserve persistent pairing links, link rotation, whole-link revocation,
  viewer privacy, and the existing anonymous-auth model.

## Non-goals

- Do not delete anonymous Supabase `auth.users` records from an owner RPC.
- Do not add Realtime, viewer presence, client-side capacity counting, or
  viewer-side activity writes.
- Do not change the status projection or expose viewer identifiers to viewers.
- Do not change link rotation: rotation still revokes the code and all active
  bindings for the device.
- Do not change `revoke_all_viewers`: it remains the whole-device soft revoke.

## Considered approaches

### 1. Database-enforced oldest-first capacity (selected)

Serialize claims per device, expire bindings older than 30 days, then hard-delete
the oldest active binding when a distinct claim would exceed five. The existing
`created_at` field is the deterministic ordering key. This is race-safe, needs
no new activity column, and makes the sixth claim succeed, but the first
viewer may be displaced even if they are still watching.

### 2. Hard cap with sixth-claim rejection

Return a capacity error at five active bindings and require the owner to
remove a viewer. This avoids surprise displacement but does not satisfy the
requested automatic sixth-claim behavior.

### 3. Client-side counting

Count viewers in the Mac app before allowing a claim. This cannot enforce a
shared limit under concurrent claims and would be bypassable by a direct RPC
caller, so it is rejected.

## Design

### Database capacity and claim flow

The consolidated baseline migration keeps the `viewers` schema unchanged and
defines the capacity as an RPC invariant:

1. `claim_pairing_code` resolves and locks the target device for the
   transaction using a device-scoped advisory lock.
2. It hard-deletes active bindings whose `created_at` is at least 30 days old.
3. It preserves the existing rule that one viewer identity can have only one
   active device binding by soft-revoking that identity's active bindings on
   other devices.
4. If the claimant is not already active on the target device and five active
   bindings remain, it hard-deletes the active row with the smallest
   `created_at`. `viewer_user_id` is a deterministic tie-breaker.
5. It inserts or reactivates the target binding and returns `{ "ok": true }`.

The device lock makes simultaneous claims for different persistent-code rows
of the same device observe the same count. Re-claiming an already active
binding does not displace another viewer. A displaced or expired viewer is not
logged out of Supabase; its next `get_paired_status()` call returns the
existing unpaired projection.

The migration also removes any pre-existing active rows beyond the first five
per device, ordered by `created_at`, and removes already-expired active rows.
This is the one-time database cleanup for data created under earlier behavior.

### Active reads and cleanup

`get_paired_status()` only considers a viewer binding active when:

- `revoked_at is null`;
- its device is not revoked; and
- `created_at` is newer than the 30-day binding lifetime.

It does not update the row. `list_viewers()` applies the same active and age
filters and returns only owner-visible active rows. The owner UI can therefore
render the actual available slots without relying on client-side filtering.

`mp_run_retention_cleanup()` gains an active-expired deletion step and reports
the number of rows removed. Existing cleanup remains in place for revoked
viewer rows older than 90 days, terminal pairing codes older than 30 days,
expired unclaimed legacy codes, expired throttle rows, and orphaned revoked
devices. The scheduled job remains the eventual cleanup path; claim and read
paths enforce expiration immediately.

### Owner controls

Keep `revoke_viewer(viewer_user_id)` as the immediate soft-revoke operation.
Add an owner-only `delete_viewer(viewer_user_id)` RPC that deletes the selected
binding for the current device. It must not delete an auth user or rows for
another device.

Extend the Mac transport and action protocols with hard deletion. The Sharing
section will:

- show active viewers only, with their pairing age;
- state that up to five viewers can watch at once;
- keep the existing `Remove` action for soft revoke;
- add a separately confirmed `Delete` action for permanent row deletion;
- refresh the active list after either action.

Whole-link rotation and stop-sharing confirmations continue to use their
existing behavior and remain distinct from per-viewer controls.

### Viewer behavior

The viewer web app needs no new capacity UI. A successful sixth claim returns
success to the new viewer. The displaced viewer's next 30-second read becomes
unpaired and shows the existing pairing screen. The persistent code remains
usable, so that viewer can pair again later and may displace the oldest
currently active binding.

## Error handling

- Claim serialization failures propagate as normal RPC errors; no
  success-shaped fallback is added.
- Expired or revoked code behavior remains the generic invalid-code response.
- An expired/displaced viewer receives `paired: false`, without a device or
  eviction reason.
- Owner list, revoke, and delete failures use the existing viewer-load/action
  error state.
- Hard delete is scoped by the owner device and silently affects zero rows if
  the selected binding no longer exists; the owner refreshes the list.

## Verification

### Database tests

Extend pgTAP coverage for:

- five distinct active claims succeeding for one device;
- a sixth claim deleting the oldest binding and leaving exactly five active
  rows;
- a re-claim by an existing active viewer not displacing another viewer;
- concurrent claims remaining capped at three;
- active bindings at least 30 days old being unavailable to reads and claims;
- hard deletion removing only the owner-selected binding;
- list results containing active, non-expired rows only;
- existing rotation, revoke, RLS, throttle, recovery, and hash-only behavior.

### Mac app tests

Cover the new transport/action surface and Sharing section behavior:

- active viewer list remains bounded to the database response;
- soft revoke refreshes the list;
- hard delete invokes the separate RPC and refreshes the list;
- delete confirmation targets the selected viewer;
- viewer-capacity copy is present.

### Acceptance

On a real deployment:

- pair five separate browsers/devices and verify all five read status;
- pair a sixth device and verify the oldest pairing becomes unpaired;
- verify the owner sees five active rows and can remove or delete one;
- verify a deleted/revoked viewer can re-pair with the persistent link;
- verify a binding older than 30 days is no longer readable and is removed by
  the retention job;
- verify no viewer read changes a last-used field because none exists.

## Rollout

1. Apply the additive capacity/cleanup migration.
2. Deploy the owner transport and Sharing controls.
3. Run the Supabase and Mac test suites.
4. Verify the five-device, sixth-claim, owner-removal, and 30-day cleanup
   acceptance cases.
