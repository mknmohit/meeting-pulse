-- Auto-cleanup for stale/terminal rows.
-- Active pairings (viewers.revoked_at is null on a non-revoked device) MUST survive
-- any amount of owner/viewer inactivity. Only terminal rows are deleted, and
-- `devices` is only deleted when soft-revoked and no viewer row references it.

do $$
begin
  if not exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) then
    begin
      create extension pg_cron with schema extensions;
    exception when insufficient_privilege or feature_not_supported then
      raise notice 'pg_cron not available; skipping extension install. Run mp_run_retention_cleanup() from an Edge Function or external scheduler.';
    end;
  end if;
end;
$$;

create or replace function public.mp_run_retention_cleanup()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_codes   integer := 0;
  v_viewers integer := 0;
  v_atts    integer := 0;
  v_global  integer := 0;
  v_devices integer := 0;
begin
  -- 1. Terminal pairing_codes: a claimed or revoked code is a one-time event.
  --    Holding it past 30 days serves no purpose and could collide on the unique
  --    code_hash index if the owner generates a fresh code that hashes the same.
  delete from public.pairing_codes pc
  where (pc.claimed_at is not null or pc.revoked_at is not null)
    and coalesce(pc.claimed_at, pc.revoked_at) < now() - interval '30 days';
  get diagnostics v_codes = row_count;

  -- 2. Soft-revoked viewers older than 90 days. Active viewers (revoked_at is
  --    null) are NEVER touched -- they are the persistent pairing.
  delete from public.viewers v
  where v.revoked_at is not null
    and v.revoked_at < now() - interval '90 days';
  get diagnostics v_viewers = row_count;

  -- 3. Per-user throttle counters past their 15-minute window. The window
  --    logic in mp_throttle_check() already resets these; stale rows are dead
  --    weight that can only block a fresh user's first pairing attempt if the
  --    PK slot is somehow revisited -- but since user_id is the PK it never
  --    is, so deleting is safe.
  delete from public.pairing_attempts pa
  where now() - pa.window_started_at >= interval '15 minutes';
  get diagnostics v_atts = row_count;

  -- 4. Global throttle counter is a singleton; reset in place rather than
  --    delete so the row always exists for the FOR UPDATE in mp_throttle_check.
  update public.pairing_attempts_global
  set failure_count = 0,
      window_started_at = now()
  where now() - window_started_at >= interval '1 hour';
  get diagnostics v_global = row_count;

  -- 5. Devices that are soft-revoked AND no viewer (active or revoked) still
  --    references them. Active devices (revoked_at is null) are NEVER deleted
  --    here -- they are the owner's registered publisher.
  delete from public.devices d
  where d.revoked_at is not null
    and d.revoked_at < now() - interval '90 days'
    and not exists (
      select 1 from public.viewers v where v.device_id = d.id
    );
  get diagnostics v_devices = row_count;

  return jsonb_build_object(
    'pairing_codes_deleted', v_codes,
    'revoked_viewers_deleted', v_viewers,
    'stale_pairing_attempts_deleted', v_atts,
    'global_throttle_reset', v_global,
    'orphan_revoked_devices_deleted', v_devices,
    'ran_at', now()
  );
end;
$$;

revoke execute on function public.mp_run_retention_cleanup() from public;
grant execute on function public.mp_run_retention_cleanup() to service_role;

-- Schedule daily at 03:15 UTC. cron.schedule is idempotent on (jobname) so
-- re-running this migration will replace the existing job cleanly. Only run
-- when pg_cron is installed on the target project; otherwise the operator can
-- invoke mp_run_retention_cleanup() from an Edge Function on its own schedule.
do $$
begin
  if exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) then
    perform cron.schedule(
      'mp_retention_cleanup_daily',
      '15 3 * * *',
      $cron$ select public.mp_run_retention_cleanup(); $cron$
    );
  end if;
end;
$$;