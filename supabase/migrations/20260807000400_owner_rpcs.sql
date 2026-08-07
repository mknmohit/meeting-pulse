create or replace function public.mp_current_device_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id
  from public.devices
  where owner_user_id = (select auth.uid())
    and revoked_at is null
  limit 1
$$;

revoke execute on function public.mp_current_device_id() from public;

create or replace function public.register_device(p_recovery_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
  v_nonce uuid;
begin
  if v_uid is null then
    raise exception 'unauthenticated' using errcode = '28000';
  end if;
  if p_recovery_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_recovery_hash' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));

  select id, instance_nonce
  into v_id, v_nonce
  from public.devices
  where owner_user_id = v_uid
    and revoked_at is null;

  if v_id is null then
    insert into public.devices (owner_user_id, recovery_hash)
    values (v_uid, p_recovery_hash)
    returning id, instance_nonce into v_id, v_nonce;

    insert into public.current_status (device_id, state, call_okay)
    values (v_id, 'unavailable', false);
  end if;

  return jsonb_build_object(
    'device_id', v_id,
    'instance_nonce', v_nonce
  );
end;
$$;

revoke execute on function public.register_device(text) from public;
grant execute on function public.register_device(text) to authenticated;

create or replace function public.publish_status(
  p_state text,
  p_call_okay boolean,
  p_instance_nonce uuid,
  p_override_mode text default null,
  p_override_expires_at timestamptz default null,
  p_screen_sharing text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device uuid := public.mp_current_device_id();
  v_nonce uuid;
  v_now timestamptz := now();
begin
  if v_device is null then
    raise exception 'no_device' using errcode = '42704';
  end if;
  if p_state not in ('available', 'busy', 'unavailable') then
    raise exception 'invalid_state' using errcode = '22023';
  end if;
  if p_override_mode is not null
    and p_override_mode not in ('busy', 'available') then
    raise exception 'invalid_override_mode' using errcode = '22023';
  end if;
  if p_screen_sharing is not null
    and p_screen_sharing not in ('yes', 'no', 'unavailable') then
    raise exception 'invalid_screen_sharing' using errcode = '22023';
  end if;

  select instance_nonce into v_nonce
  from public.devices
  where id = v_device;

  if v_nonce is distinct from p_instance_nonce then
    return jsonb_build_object('superseded', true, 'last_seen_at', null);
  end if;

  insert into public.current_status as cs (
    device_id,
    state,
    call_okay,
    screen_sharing,
    override_mode,
    override_expires_at,
    last_seen_at,
    updated_at,
    schema_version
  )
  values (
    v_device,
    p_state,
    coalesce(p_call_okay, false),
    p_screen_sharing,
    p_override_mode,
    p_override_expires_at,
    v_now,
    v_now,
    1
  )
  on conflict (device_id) do update set
    state = excluded.state,
    call_okay = excluded.call_okay,
    screen_sharing = excluded.screen_sharing,
    override_mode = excluded.override_mode,
    override_expires_at = excluded.override_expires_at,
    last_seen_at = v_now,
    updated_at = v_now;

  return jsonb_build_object('superseded', false, 'last_seen_at', v_now);
end;
$$;

revoke execute on function public.publish_status(
  text, boolean, uuid, text, timestamptz, text
) from public;
grant execute on function public.publish_status(
  text, boolean, uuid, text, timestamptz, text
) to authenticated;

create or replace function public.update_device_profile(p_display_name text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device uuid := public.mp_current_device_id();
  v_name text;
begin
  if v_device is null then
    raise exception 'no_device' using errcode = '42704';
  end if;

  v_name := btrim(coalesce(p_display_name, ''));
  if v_name ~ '[[:cntrl:]]' then
    raise exception 'display_name_control_character' using errcode = '22023';
  end if;
  if char_length(v_name) > 80 then
    raise exception 'display_name_too_long' using errcode = '22023';
  end if;
  if v_name = '' then
    v_name := null;
  end if;

  update public.devices
  set display_name = v_name
  where id = v_device;
end;
$$;

revoke execute on function public.update_device_profile(text) from public;
grant execute on function public.update_device_profile(text) to authenticated;

create or replace function public.create_pairing_code(p_code_hash text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device uuid := public.mp_current_device_id();
  v_id uuid;
begin
  if v_device is null then
    raise exception 'no_device' using errcode = '42704';
  end if;
  if p_code_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_code_hash' using errcode = '22023';
  end if;

  update public.pairing_codes
  set revoked_at = now()
  where device_id = v_device
    and claimed_at is null
    and revoked_at is null;

  insert into public.pairing_codes (device_id, code_hash, expires_at)
  values (v_device, p_code_hash, now() + interval '10 minutes')
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.create_pairing_code(text) from public;
grant execute on function public.create_pairing_code(text) to authenticated;

create or replace function public.rotate_pairing_codes()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device uuid := public.mp_current_device_id();
  v_count integer;
begin
  if v_device is null then
    raise exception 'no_device' using errcode = '42704';
  end if;

  update public.pairing_codes
  set revoked_at = now()
  where device_id = v_device
    and claimed_at is null
    and revoked_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.rotate_pairing_codes() from public;
grant execute on function public.rotate_pairing_codes() to authenticated;

create or replace function public.revoke_viewer(p_viewer_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device uuid := public.mp_current_device_id();
begin
  if v_device is null then
    raise exception 'no_device' using errcode = '42704';
  end if;
  update public.viewers
  set revoked_at = now()
  where device_id = v_device
    and viewer_user_id = p_viewer_user_id
    and revoked_at is null;
end;
$$;

revoke execute on function public.revoke_viewer(uuid) from public;
grant execute on function public.revoke_viewer(uuid) to authenticated;

create or replace function public.revoke_all_viewers()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device uuid := public.mp_current_device_id();
  v_count integer;
begin
  if v_device is null then
    raise exception 'no_device' using errcode = '42704';
  end if;
  update public.viewers
  set revoked_at = now()
  where device_id = v_device
    and revoked_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.revoke_all_viewers() from public;
grant execute on function public.revoke_all_viewers() to authenticated;

create or replace function public.list_viewers()
returns table (
  viewer_user_id uuid,
  created_at timestamptz,
  revoked_at timestamptz
)
language sql
security definer
set search_path = public, pg_temp
as $$
  select v.viewer_user_id, v.created_at, v.revoked_at
  from public.viewers v
  where v.device_id = public.mp_current_device_id()
  order by v.created_at asc
$$;

revoke execute on function public.list_viewers() from public;
grant execute on function public.list_viewers() to authenticated;

create or replace function public.delete_device()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
  v_device uuid := public.mp_current_device_id();
begin
  if v_device is not null then
    delete from public.devices where id = v_device;
  end if;
  delete from public.pairing_attempts where user_id = v_uid;
end;
$$;

revoke execute on function public.delete_device() from public;
grant execute on function public.delete_device() to authenticated;
