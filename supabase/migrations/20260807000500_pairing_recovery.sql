create or replace function public.mp_normalize_code(p_code text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    translate(upper(coalesce(p_code, '')), 'ILOU', '1101'),
    '[^0-9A-HJKMNP-TV-Z]',
    '',
    'g'
  )
$$;

create or replace function public.mp_hash_code(p_code text)
returns text
language sql
immutable
set search_path = public, extensions, pg_temp
as $$
  select encode(
    extensions.digest(public.mp_normalize_code(p_code), 'sha256'),
    'hex'
  )
$$;

revoke execute on function public.mp_normalize_code(text) from public;
revoke execute on function public.mp_hash_code(text) from public;

create or replace function public.mp_throttle_check()
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
  v_now timestamptz := now();
  v_count integer;
  v_window timestamptz;
begin
  if v_uid is null then
    raise exception 'unauthenticated' using errcode = '28000';
  end if;

  select failure_count, window_started_at
  into v_count, v_window
  from public.pairing_attempts_global
  where id = true
  for update;

  if v_now - v_window >= interval '1 hour' then
    update public.pairing_attempts_global
    set window_started_at = v_now, failure_count = 0
    where id = true;
  elsif v_count >= 100 then
    return false;
  end if;

  insert into public.pairing_attempts (user_id, window_started_at, attempt_count)
  values (v_uid, v_now, 0)
  on conflict (user_id) do nothing;

  select attempt_count, window_started_at
  into v_count, v_window
  from public.pairing_attempts
  where user_id = v_uid
  for update;

  if v_now - v_window >= interval '15 minutes' then
    update public.pairing_attempts
    set window_started_at = v_now, attempt_count = 1
    where user_id = v_uid;
  elsif v_count >= 5 then
    return false;
  else
    update public.pairing_attempts
    set attempt_count = attempt_count + 1
    where user_id = v_uid;
  end if;

  return true;
end;
$$;

revoke execute on function public.mp_throttle_check() from public;

create or replace function public.mp_record_failure()
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.pairing_attempts_global
  set failure_count = failure_count + 1
  where id = true
$$;

revoke execute on function public.mp_record_failure() from public;

create or replace function public.claim_pairing_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
  v_device uuid;
begin
  if v_uid is null then
    raise exception 'unauthenticated' using errcode = '28000';
  end if;

  if not public.mp_throttle_check() then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  if char_length(public.mp_normalize_code(p_code)) <> 10 then
    perform public.mp_record_failure();
    return jsonb_build_object('ok', false, 'reason', 'invalid_code');
  end if;

  update public.pairing_codes
  set claimed_at = now()
  where code_hash = public.mp_hash_code(p_code)
    and claimed_at is null
    and revoked_at is null
    and expires_at > now()
  returning device_id into v_device;

  if v_device is null then
    perform public.mp_record_failure();
    return jsonb_build_object('ok', false, 'reason', 'invalid_code');
  end if;

  update public.viewers
  set revoked_at = now()
  where viewer_user_id = v_uid
    and revoked_at is null
    and device_id <> v_device;

  insert into public.viewers (device_id, viewer_user_id)
  values (v_device, v_uid)
  on conflict (device_id, viewer_user_id)
  do update set revoked_at = null;

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.claim_pairing_code(text) from public;
grant execute on function public.claim_pairing_code(text) to authenticated;

create or replace function public.rebind_device(p_recovery_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
  v_nonce uuid;
  v_existing uuid;
  v_viewers integer;
  v_published integer;
begin
  if v_uid is null then
    raise exception 'unauthenticated' using errcode = '28000';
  end if;
  if not public.mp_throttle_check() then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  select id
  into v_id
  from public.devices
  where recovery_hash = public.mp_hash_code(p_recovery_secret)
    and revoked_at is null
  for update;

  if v_id is null then
    perform public.mp_record_failure();
    return jsonb_build_object('ok', false, 'reason', 'invalid_recovery_secret');
  end if;

  select id
  into v_existing
  from public.devices
  where owner_user_id = v_uid
    and revoked_at is null
    and id <> v_id
  for update;

  if v_existing is not null then
    select count(*) into v_viewers
    from public.viewers
    where device_id = v_existing
      and revoked_at is null;

    select count(*) into v_published
    from public.current_status
    where device_id = v_existing
      and state <> 'unavailable';

    if v_viewers > 0 or v_published > 0 then
      raise exception 'rebind_would_orphan' using errcode = '23505';
    end if;
    delete from public.devices where id = v_existing;
  end if;

  update public.devices
  set owner_user_id = v_uid, instance_nonce = gen_random_uuid()
  where id = v_id
  returning instance_nonce into v_nonce;

  return jsonb_build_object(
    'device_id', v_id,
    'instance_nonce', v_nonce
  );
end;
$$;

revoke execute on function public.rebind_device(text) from public;
grant execute on function public.rebind_device(text) to authenticated;
