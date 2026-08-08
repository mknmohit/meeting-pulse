alter table public.pairing_codes
  alter column expires_at drop not null;

drop index if exists public.pairing_codes_live_idx;

create index pairing_codes_active_idx
  on public.pairing_codes(device_id)
  where revoked_at is null;

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
    and revoked_at is null;

  update public.viewers
  set revoked_at = now()
  where device_id = v_device
    and revoked_at is null;

  insert into public.pairing_codes (device_id, code_hash, expires_at)
  values (v_device, p_code_hash, null)
  returning id into v_id;

  return v_id;
end;
$$;

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
    and revoked_at is null;
  get diagnostics v_count = row_count;

  update public.viewers
  set revoked_at = now()
  where device_id = v_device
    and revoked_at is null;

  return v_count;
end;
$$;

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
  set claimed_at = coalesce(claimed_at, now())
  where code_hash = public.mp_hash_code(p_code)
    and revoked_at is null
    and (expires_at is null or expires_at > now())
  returning device_id into v_device;

  if v_device is null then
    perform public.mp_record_failure();
    return jsonb_build_object('ok', false, 'reason', 'invalid_code');
  end if;

  update public.viewers
  set revoked_at = now()
  where device_id = v_device
    and revoked_at is null;

  update public.viewers
  set revoked_at = now()
  where viewer_user_id = v_uid
    and revoked_at is null;

  insert into public.viewers (device_id, viewer_user_id)
  values (v_device, v_uid)
  on conflict (device_id, viewer_user_id)
  do update set revoked_at = null;

  return jsonb_build_object('ok', true);
end;
$$;
