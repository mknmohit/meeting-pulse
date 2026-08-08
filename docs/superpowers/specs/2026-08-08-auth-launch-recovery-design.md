# Auth launch recovery and diagnostics

**Date:** 2026-08-08

**Status:** Design selected for implementation

## Summary

Meeting Pulse currently accepts any non-nil cached Supabase session without
validating it. If that session is expired, invalid, or belongs to an earlier
project configuration, the first owner RPC can arrive without a valid
authenticated identity and fail with `unauthenticated`. The launch coordinator
then replaces every non-configuration failure with the generic configuration
message, which hides the actionable cause.

The fix will validate or rebuild the anonymous session before owner RPCs, keep
configuration errors distinct from runtime launch errors, and add an inline
retry action to the Watch banner. The retry will clean up the partially started
runtime and rerun the existing launch sequence without requiring an app
relaunch.

## Goals

- Make first launch recover from stale or invalid cached Supabase sessions.
- Preserve the existing Turnstile-protected anonymous-auth flow.
- Keep Supabase RPCs restricted to authenticated users.
- Show the actual non-configuration launch error in the Station Watch banner.
- Let the owner retry a failed launch from Station.
- Keep launch cleanup explicit so retries do not duplicate tasks, monitors, or
  Turnstile panels.
- Add focused regression coverage for session recovery, error mapping, and
  retry behavior.

## Non-goals

- Changing Supabase grants, RLS policies, or database functions.
- Adding a service-role key or an unauthenticated RPC path.
- Redesigning the Station window or adding a separate diagnostics window.
- Changing detector rules, status reduction, or pairing semantics.
- Displaying access tokens, refresh tokens, or other secret values in the UI or
  logs.

## Root cause

`SupabaseStatusTransport.ensureSession()` currently returns immediately when
`client.auth.currentSession` is non-nil. That property may contain an expired
session and does not guarantee that the refresh token is valid. Supabase's REST
adapter attempts to obtain a valid token for each request and silently omits
the authorization header when token retrieval fails. The server then sees a
request without `auth.uid()` and returns the `28000` `unauthenticated` error.

`AppLaunchCoordinator.start()` handles `AppConfiguration.ConfigurationError`
with a useful detail, but maps every other error to
`MPString.error.genericSetup`. This makes authentication, storage, Turnstile,
and network failures appear to be missing configuration.

## Architecture

### Session bootstrap

`SupabaseStatusTransport.ensureSession()` will:

1. Request `client.auth.session`, which returns a valid session or refreshes an
   expired one.
2. If that request fails, request a fresh Turnstile token and call
   `signInAnonymously(captchaToken:)`.
3. Request `client.auth.session` again after anonymous sign-in to verify that
   the authenticated session is available to subsequent RPC requests.

The existing session storage and Turnstile gate remain unchanged. The method
will not expose or log token values.

The native Turnstile WebView will use the first configured viewer origin as its
document base URL. The previous hard-coded `https://localhost` origin can be
rejected by a production Turnstile site key restricted to the viewer domain,
which causes the otherwise valid auth recovery path to fail with
`TurnstileError.unavailable`.

The custom Supabase auth storage will honor the configured
`meetingpulse.auth` storage key and ignore Supabase's legacy migration keys.
Treating every requested key as the same secret allowed the SDK's legacy
cleanup migration to delete a freshly stored session before verification.

### Launch retry

`AppLaunchCoordinator` will expose a main-actor retry operation for the
existing `model` and `PulseStore`. Before restarting it will:

- cancel the permission observation task;
- stop and clear any partially created `OwnerRuntime`;
- close and clear the Turnstile panel;
- reset the launch state to `.starting`;
- invoke `start(model:store:)`.

The single-instance lock remains owned by the coordinator while the app is
running. A retry is ignored unless the coordinator is currently in
`.setupRequired`, preventing concurrent launch attempts.

`AppPulseActions` will receive a configured retry closure alongside its
existing window-opening closure. `PulseActions` will expose
`retryLaunch() async`, and `WatchSection` will pass that action to the
configuration/runtime-failure banner.

### Error presentation

Configuration validation failures continue to use their existing full
configuration message and headline. Other launch failures will use the full
`String(describing:)` value as the banner detail and a distinct
“Meeting Pulse couldn't start.” headline. This keeps server error codes such as
`28000` visible instead of reducing them to a generic configuration message. No
error path will display credentials or session tokens.

The retry action will use the existing banner link treatment and a concise
`Try again` label. The banner remains inline at the top of Watch, so the owner
does not lose the setup context or need to find another window.

## Error handling

- A valid cached session proceeds without a new Turnstile challenge.
- An expired or invalid cached session falls back to anonymous sign-in.
- A failed Turnstile or anonymous sign-in request remains a visible launch
  failure and can be retried.
- A failed owner RPC remains a visible launch failure and can be retried.
- Configuration failures still identify the exact configuration file/key.
- Retry cleanup is idempotent and does not clear local secrets or pairing data.
- If retry succeeds, `setupFailure` is cleared and the normal runtime state is
  restored.

## Testing

- Add transport tests proving a stale cached session is validated and that
  anonymous sign-in is used after validation failure.
- Add launch-coordinator tests for error-detail mapping and retry cleanup/state
  transitions using injected or existing test seams.
- Add MPUI coverage that the failure banner exposes the retry action without
  changing the existing setup checklist behavior.
- Run the existing MPSync, MPSupport, and MPUI test targets.
- Run the existing local macOS build with the configured
  `mac-app/Config.xcconfig`.

## Implementation boundaries

Expected production changes:

- `mac-app/Packages/MPSync/Sources/MPSync/SupabaseStatusTransport.swift`
- `mac-app/MeetingPulse/MeetingPulseApp.swift`
- `mac-app/MeetingPulse/AppPulseActions.swift`
- `mac-app/Packages/MPUI/Sources/MPUI/Store/PulseActions.swift`
- `mac-app/Packages/MPUI/Sources/MPUI/Sections/WatchSection.swift`
- `mac-app/Packages/MPSupport/Sources/MPSupport/Strings.swift`

Expected test changes are limited to the matching MPSync, MPUI, and app-support
test targets. No database migration or permission change is required.
