create schema if not exists tests;
create extension if not exists dblink with schema extensions;
grant execute on function dblink_connect_u(text, text) to authenticated;
grant execute on function dblink_disconnect(text) to authenticated;
grant execute on function dblink_exec(text, text) to authenticated;
grant execute on function dblink_send_query(text, text) to authenticated;
grant execute on function dblink_get_result(text) to authenticated;

create or replace function tests.create_user()
returns uuid
language sql
security definer
set search_path = public, auth, tests, pg_temp
as $$
  insert into auth.users (
    id,
    aud,
    role,
    instance_id,
    email,
    is_anonymous
  )
  values (
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    '00000000-0000-0000-0000-000000000000',
    null,
    true
  )
  returning id
$$;

create or replace function tests.become(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'authenticated', false);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_uid,
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text,
    false
  );
end;
$$;

create or replace function tests.become_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'anon', false);
  perform set_config('request.jwt.claims', '', false);
end;
$$;

create or replace function tests.insert_device(
  p_owner uuid,
  p_recovery_hash text
)
returns uuid
language sql
security definer
set search_path = public, auth, tests, pg_temp
as $$
  insert into public.devices (owner_user_id, recovery_hash)
  values (p_owner, p_recovery_hash)
  returning id
$$;

create or replace function tests.insert_viewer(
  p_device uuid,
  p_viewer uuid
)
returns void
language sql
security definer
set search_path = public, auth, tests, pg_temp
as $$
  insert into public.viewers (device_id, viewer_user_id)
  values (p_device, p_viewer)
$$;

create or replace function tests.expire_code(p_code_hash text)
returns void
language sql
security definer
set search_path = public, auth, tests, pg_temp
as $$
  update public.pairing_codes
  set expires_at = now() - interval '1 second'
  where code_hash = p_code_hash
$$;

create or replace function tests.revoke_code(p_code_hash text)
returns void
language sql
security definer
set search_path = public, auth, tests, pg_temp
as $$
  update public.pairing_codes
  set revoked_at = now()
  where code_hash = p_code_hash
$$;

create or replace function tests.advance_user_window(p_uid uuid)
returns void
language sql
security definer
set search_path = public, auth, tests, pg_temp
as $$
  update public.pairing_attempts
  set window_started_at = now() - interval '16 minutes'
  where user_id = p_uid
$$;

create or replace function tests.set_global_failures(p_count integer)
returns void
language sql
security definer
set search_path = public, auth, tests, pg_temp
as $$
  update public.pairing_attempts_global
  set failure_count = p_count,
      window_started_at = now()
  where id = true
$$;

create or replace function tests.count_code_hash(p_value text)
returns integer
language sql
security definer
set search_path = public, auth, tests, pg_temp
as $$
  select count(*)::integer
  from public.pairing_codes
  where code_hash = p_value
$$;

create or replace function tests.global_failures()
returns integer
language sql
security definer
set search_path = public, auth, tests, pg_temp
as $$
  select failure_count from public.pairing_attempts_global where id = true
$$;

grant usage on schema tests to authenticated, anon;
grant execute on all functions in schema tests to authenticated, anon;

select plan(0);
