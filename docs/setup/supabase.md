# Supabase setup

Meeting Pulse uses Supabase Anonymous Auth, Postgres `SECURITY DEFINER` RPCs,
and deny-by-default RLS. Realtime is not used.

## Local development

Install the Supabase CLI and Docker Desktop, then run:

```sh
supabase start
supabase db reset
supabase test db
```

The local config enables anonymous sign-ins and disables Realtime. The project
uses a squashed baseline migration,
`supabase/migrations/20260809000100_initial_schema.sql`, plus forward-only
follow-up migrations such as
`supabase/migrations/20260824000100_performance_indexes.sql`. Together they
create the tables, policies, RPCs, grants, retention cleanup, five-viewer
capacity, and indexes for the hot viewer and retention paths. The local seed is
intentionally empty. Keep the baseline for future fresh deployments; an empty
database still needs a reproducible schema definition.

## Hosted project

1. Create the project in the region nearest the owner.
2. Enable Anonymous sign-ins under Auth providers.
3. Enable Turnstile under Auth abuse protection and store the secret key in
   Supabase settings.
4. Put only the project URL and publishable anon key in local client
   configuration.
5. Keep the service-role key in the operator secret store. It never belongs in
   migrations, fixtures, the Mac app, or the viewer bundle.

The viewer reads only `get_paired_status()`. Clients do not receive table
grants for pairing codes, viewer rows, throttle state, or override metadata.

## Gate G3

The current local suite covers the fourteen RLS-negative cases, pairing,
throttling, recovery, viewer projection, normalization, and the two-session
concurrency checks. The concurrency helper uses a local-only superuser test
URL and grants dblink only inside the test session. See
`docs/decisions/0006-concurrency-test-harness.md`.
