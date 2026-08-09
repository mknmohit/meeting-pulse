# Operations runbook

## Uninstall

1. Open Meeting Pulse and choose `Delete everything…`.
2. Confirm the destructive prompt by typing `delete`.
3. Quit Meeting Pulse.
4. Drag the app to the Trash.
5. Remove `~/Library/Application Support/MeetingPulse`.
6. Remove `~/Library/Logs/MeetingPulse`.

Deleting local files without deleting remote data leaves the device and viewer
pairing on the server.

## Anonymous Auth cleanup

`delete_device()` removes the device graph and the local throttle row. It does
not delete the `auth.users` row because the Auth Admin API requires the
service-role key. An operator may remove the anonymous user from the Supabase
dashboard or Auth Admin API after confirming the device is deleted.

Never put the service-role key in the app, viewer, migrations, fixtures, or
logs.

## Retention

The baseline migration `20260809000100_initial_schema.sql` defines
`public.mp_run_retention_cleanup()`, scheduled daily at 03:15 UTC via
`pg_cron` (when the extension is enabled on the project). It deletes stale
viewer bindings and terminal rows:

On migration, active bindings older than 30 days and any active rows beyond
the first five per device are cleaned immediately.

- `pairing_codes` rows that are claimed or revoked for 30+ days, plus expired
  unclaimed legacy codes.
- active `viewers` rows whose pairing `created_at` is 30+ days old.
- `viewers` rows with `revoked_at` older than 90 days.
- `pairing_attempts` rows whose 15-minute throttle window has expired.
- `pairing_attempts_global` counter reset in place when its 1-hour window
  has expired (not deleted, since it is a singleton).
- `devices` rows that are soft-revoked AND no longer referenced by any
  viewer (active or revoked), older than 90 days.

Active devices are never pruned by the cleanup. Viewer bindings survive until
their 30-day pairing lifetime, the owner calls `revoke_viewer`,
`delete_viewer`, `revoke_all_viewers`, or a sixth claim
evicts the oldest binding. The persistent code itself survives until the owner
calls `create_pairing_code` or `rotate_pairing_codes`.

If `pg_cron` is not enabled on the target project, the migration skips
scheduling and an operator should invoke
`select public.mp_run_retention_cleanup();` from a Supabase Edge Function
on its own cron trigger, or run it manually from the SQL editor.

## Free-tier pausing

Supabase may pause an inactive free project. An installed owner heartbeat
keeps an active project from looking idle. After a long uninstall, resume the
project in the Supabase dashboard before asking the owner to pair again.

## Second Mac transfer

Do not install a second publisher with a new anonymous identity. Use the
recovery phrase on the replacement Mac to call `rebind_device`. The old Mac
will receive `superseded` on its next publish and must stop.
