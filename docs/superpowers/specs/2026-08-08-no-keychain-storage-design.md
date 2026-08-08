# Meeting Pulse local secret storage design

**Date:** 2026-08-08

**Status:** Approved for autonomous implementation

## Goal

Stop storing Meeting Pulse data in Keychain. Store the existing `SecretStore`
values in an owner-only file under Application Support, remove the legacy
Keychain items without migrating them, and make the app run onboarding again
with a fresh local identity.

## Scope

The replacement covers every current `SecretKey`:

- Supabase refresh token
- device recovery phrase
- device ID
- device instance nonce
- pairing code

Non-secret preferences, including the display name and login-item preference,
remain in their existing stores.

## Storage

`LocalSecretStore` will implement the existing synchronous `SecretStore`
protocol. It will use:

```
~/Library/Application Support/MeetingPulse/secrets.plist
```

The containing directory is created with owner-only permissions (`0700`) and
the file is written with owner read/write permissions (`0600`). Values remain
plain data on disk; this is intentionally less safe than Keychain, but gives
the requested simpler behavior without a Keychain prompt. The store writes
atomically and synchronizes access with a lock so callers can continue using
the current synchronous protocol safely.

Missing files and missing keys return `.missing`. Invalid or unreadable files
and filesystem failures are thrown rather than being treated as missing
credentials. Saving replaces one key without dropping the others; deleting the
last key removes the file.

## One-time reset

The first launch after this change runs an idempotent legacy cleanup:

1. Delete all generic-password items for the legacy service
   `com.techdevix.meetingpulse.auth`.
2. Do not read, migrate, or copy any values from Keychain.
3. Clear `setup.completed` so onboarding is shown again.
4. Record a reset sentinel in UserDefaults so later launches do not reset a
   completed setup.

A missing legacy service is success. Other deletion failures surface as a
   launch/setup error. Existing non-secret preferences remain intact.

The old migration path that copied recovery material into a secret store will
not run. The new local store starts empty, so the app registers a new device
and requires the user to complete setup again.

## Integration

`MeetingPulseApp` constructs `LocalSecretStore` after the legacy cleanup and
injects it into `RecoveryService`, `PairingService`, and
`SupabaseStatusTransport`. The transport accepts `any SecretStore` instead of a
concrete Keychain implementation. The old `KeychainStore` and
Keychain-specific runtime error/copy paths are removed; the cleanup helper is
the only remaining Security-framework use and only deletes legacy entries.

Delete-everything continues to clear the injected store. Runtime behavior for
missing device identity remains explicit: the fresh setup registers a new
identity instead of silently treating storage errors as missing data.

## Validation

Add focused tests for:

- missing, save/read, overwrite, delete, and empty-store behavior
- atomic persistence and owner-only file permissions
- malformed store data producing an error
- legacy cleanup success, not-found, failure, and idempotence
- the transport accepting an arbitrary `SecretStore`
- no remaining runtime Keychain storage references

Update security, release, operations, acceptance, and user-facing error copy
to describe the local file and the setup reset rather than Keychain prompts.
