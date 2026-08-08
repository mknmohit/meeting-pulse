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

An operator may review devices whose `current_status.last_seen_at` is older
than 90 days and remove them after confirming that the owner no longer needs
the pairing. Do not prune an active device based only on viewer inactivity.

## Free-tier pausing

Supabase may pause an inactive free project. An installed owner heartbeat
keeps an active project from looking idle. After a long uninstall, resume the
project in the Supabase dashboard before asking the owner to pair again.

## Second Mac transfer

Do not install a second publisher with a new anonymous identity. Use the
recovery phrase on the replacement Mac to call `rebind_device`. The old Mac
will receive `superseded` on its next publish and must stop.
