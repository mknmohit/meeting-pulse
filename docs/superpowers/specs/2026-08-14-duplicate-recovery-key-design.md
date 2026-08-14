# Duplicate Recovery-Key Recovery Design

## Problem

When the anonymous auth session expires or is replaced, startup keeps the local
device registration and recovery phrase but receives a new auth user ID. The
startup path calls `register_device` with the stored recovery hash. Because that
hash already belongs to the existing device row, Postgres rejects the attempted
insert with `23505` on `devices_recovery_hash_key`, and the app displays the raw
database error instead of recovering.

## Goals

- Recover the existing device automatically when this exact conflict occurs.
- Preserve the device ID and all viewer pairings.
- Store the newly returned instance nonce before publishing again.
- Keep normal registration idempotent and keep recovery protected by Turnstile,
  throttling, and the existing `rebind_device` RPC.
- Leave unrelated database and recovery failures explicit.

## Approach

`SupabaseStatusTransport.registerDevice` will translate only a PostgREST
`23505` whose message identifies `devices_recovery_hash_key` into a typed
`recoveryHashConflict` transport error. Other `23505` errors and all other
errors will continue through the existing error path.

`RecoveryService.registerStoredDevice` will catch that typed error and invoke
the existing `rebindDevice` operation with the stored raw recovery phrase.
`rebindDevice` obtains the recovery Turnstile token, ensures the current
anonymous session, calls `rebind_device`, and saves the returned device ID and
rotated nonce. The success response from `rebind_device` contains only
`device_id` and `instance_nonce`; the client treats the optional `ok` field as
absent on success and requires both IDs. The caller receives the recovered
registration and startup continues normally.

The database schema and RPCs do not change. In particular, `register_device`
will not become an implicit rebind: recovery remains an explicit,
rate-limited, Turnstile-protected operation.

## Error handling

- Exact recovery-hash conflict: automatic protected rebind.
- Missing or malformed stored phrase: existing recovery error.
- Turnstile failure, invalid phrase, throttling, or `rebind_would_orphan`:
  propagate the existing typed/remote error and show the launch error banner.
- Any unrelated registration error: propagate unchanged.
- No local secrets are deleted during the automatic recovery path.

## Tests

Extend the MPSync recovery tests so a fake transport can report the typed
recovery-hash conflict and record a rebind call. Assert that the stored phrase
is passed to rebind, the recovered registration is returned, and the local
device identity is saved. Keep the existing normal registration test behavior
unchanged. Run the MPSync test suite and the relevant Supabase database tests
if the local database is available.

## Scope

This change is limited to registration error classification and recovery
fallback. It does not alter viewer behavior, database constraints, recovery
phrase format, or the explicit manual recovery UI.
