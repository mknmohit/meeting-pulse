# Decision 0005: CI anon-key shape

## Context

The implementation plan's `.env.ci` example uses `******` for the Supabase
anon key, while the same plan requires configuration loading to reject any
anon key that is not three base64url segments. Accepting the placeholder would
make a malformed deployment configuration look valid.

## Decision

Use `ci.anon.key` in `viewer/.env.ci`. It has the required three-segment
shape, contains no real credential, and still lets CI prove that a
shape-valid build succeeds. The human `.env.example` remains placeholder-only
and must fail the build.

## Consequence

The viewer keeps one validation rule in local development, CI, and production:
required values must be present, non-placeholder, and structurally valid.
