
-- Fresh baseline for the empty Meeting Pulse Supabase project.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."claim_pairing_code"("p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_uid uuid := (select auth.uid());
  v_device uuid;
  v_now timestamptz := clock_timestamp();
  v_target_active boolean;
  v_active_count integer;
  v_viewer_capacity constant integer := 5;
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
  set claimed_at = coalesce(claimed_at, v_now)
  where code_hash = public.mp_hash_code(p_code)
    and revoked_at is null
    and (expires_at is null or expires_at > v_now)
  returning device_id into v_device;

  if v_device is null then
    perform public.mp_record_failure();
    return jsonb_build_object('ok', false, 'reason', 'invalid_code');
  end if;

  -- Claims for one owner device must observe and enforce one shared capacity.
  perform pg_advisory_xact_lock(hashtextextended(v_device::text, 0));

  delete from public.viewers
  where device_id = v_device
    and revoked_at is null
    and created_at <= v_now - interval '30 days';

  select exists (
    select 1
    from public.viewers
    where device_id = v_device
      and viewer_user_id = v_uid
      and revoked_at is null
  )
  into v_target_active;

  update public.viewers
  set revoked_at = v_now
  where viewer_user_id = v_uid
    and revoked_at is null
    and device_id <> v_device;

  if not v_target_active then
    select count(*)::integer
    into v_active_count
    from public.viewers
    where device_id = v_device
      and revoked_at is null;

    if v_active_count >= v_viewer_capacity then
      with ranked as (
        select
          device_id,
          viewer_user_id,
          row_number() over (
            order by created_at asc, viewer_user_id asc
          ) as position
        from public.viewers
        where device_id = v_device
          and revoked_at is null
      )
      delete from public.viewers v
      using ranked
      where v.device_id = ranked.device_id
        and v.viewer_user_id = ranked.viewer_user_id
        and ranked.position <= v_active_count - (v_viewer_capacity - 1);
    end if;
  end if;

  insert into public.viewers (device_id, viewer_user_id, created_at)
  values (v_device, v_uid, v_now)
  on conflict (device_id, viewer_user_id) do nothing;

  update public.viewers
  set revoked_at = null,
      created_at = case
        when revoked_at is null then created_at
        else v_now
      end
  where device_id = v_device
    and viewer_user_id = v_uid;

  return jsonb_build_object('ok', true);
end;
$$;


ALTER FUNCTION "public"."claim_pairing_code"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_pairing_code"("p_code_hash" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
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
$_$;


ALTER FUNCTION "public"."create_pairing_code"("p_code_hash" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_device"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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


ALTER FUNCTION "public"."delete_device"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_viewer"("p_viewer_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_device uuid := public.mp_current_device_id();
begin
  if v_device is null then
    raise exception 'no_device' using errcode = '42704';
  end if;

  delete from public.viewers
  where device_id = v_device
    and viewer_user_id = p_viewer_user_id;
end;
$$;


ALTER FUNCTION "public"."delete_viewer"("p_viewer_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_paired_status"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_uid uuid := (select auth.uid());
  v_now timestamptz := now();
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'unauthenticated' using errcode = '28000';
  end if;

  select jsonb_build_object(
    'paired', true,
    'display_name', d.display_name,
    'state', cs.state,
    'call_okay', cs.call_okay,
    'last_seen_at', cs.last_seen_at,
    'server_now', v_now,
    'schema_version', cs.schema_version
  )
  into v_result
  from public.viewers v
  join public.devices d on d.id = v.device_id
  join public.current_status cs on cs.device_id = d.id
  where v.viewer_user_id = v_uid
    and v.revoked_at is null
    and v.created_at > v_now - interval '30 days'
    and d.revoked_at is null
  order by v.created_at desc
  limit 1;

  return coalesce(
    v_result,
    jsonb_build_object('paired', false, 'server_now', v_now)
  );
end;
$$;


ALTER FUNCTION "public"."get_paired_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_viewers"() RETURNS TABLE("viewer_user_id" "uuid", "created_at" timestamp with time zone, "revoked_at" timestamp with time zone)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  select v.viewer_user_id, v.created_at, v.revoked_at
  from public.viewers v
  where v.device_id = public.mp_current_device_id()
    and v.revoked_at is null
    and v.created_at > now() - interval '30 days'
  order by v.created_at asc, v.viewer_user_id asc
$$;


ALTER FUNCTION "public"."list_viewers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mp_current_device_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  select id
  from public.devices
  where owner_user_id = (select auth.uid())
    and revoked_at is null
  limit 1
$$;


ALTER FUNCTION "public"."mp_current_device_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mp_hash_code"("p_code" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public', 'extensions', 'pg_temp'
    AS $$
  select encode(
    extensions.digest(public.mp_normalize_code(p_code), 'sha256'),
    'hex'
  )
$$;


ALTER FUNCTION "public"."mp_hash_code"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mp_normalize_code"("p_code" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select regexp_replace(
    translate(upper(coalesce(p_code, '')), 'ILOU', '1101'),
    '[^0-9A-HJKMNP-TV-Z]',
    '',
    'g'
  )
$$;


ALTER FUNCTION "public"."mp_normalize_code"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mp_record_failure"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  update public.pairing_attempts_global
  set failure_count = failure_count + 1
  where id = true
$$;


ALTER FUNCTION "public"."mp_record_failure"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mp_run_retention_cleanup"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_codes           integer := 0;
  v_expired_viewers integer := 0;
  v_viewers         integer := 0;
  v_atts            integer := 0;
  v_global          integer := 0;
  v_devices         integer := 0;
begin
  -- Active bindings expire by pairing age, not by viewer read activity.
  delete from public.viewers v
  where v.revoked_at is null
    and v.created_at <= now() - interval '30 days';
  get diagnostics v_expired_viewers = row_count;

  -- Terminal pairing codes are retained only for a bounded audit window.
  delete from public.pairing_codes pc
  where (
    (
      (pc.claimed_at is not null or pc.revoked_at is not null)
      and coalesce(pc.claimed_at, pc.revoked_at) < now() - interval '30 days'
    )
    or (
      pc.expires_at is not null
      and pc.expires_at <= now()
      and pc.claimed_at is null
      and pc.revoked_at is null
    )
  );
  get diagnostics v_codes = row_count;

  -- Soft-revoked viewer rows are no longer useful after the retention window.
  delete from public.viewers v
  where v.revoked_at is not null
    and v.revoked_at < now() - interval '90 days';
  get diagnostics v_viewers = row_count;

  delete from public.pairing_attempts pa
  where now() - pa.window_started_at >= interval '15 minutes';
  get diagnostics v_atts = row_count;

  update public.pairing_attempts_global
  set failure_count = 0,
      window_started_at = now()
  where now() - window_started_at >= interval '1 hour';
  get diagnostics v_global = row_count;

  delete from public.devices d
  where d.revoked_at is not null
    and d.revoked_at < now() - interval '90 days'
    and not exists (
      select 1 from public.viewers v where v.device_id = d.id
    );
  get diagnostics v_devices = row_count;

  return jsonb_build_object(
    'expired_viewers_deleted', v_expired_viewers,
    'pairing_codes_deleted', v_codes,
    'revoked_viewers_deleted', v_viewers,
    'stale_pairing_attempts_deleted', v_atts,
    'global_throttle_reset', v_global,
    'orphan_revoked_devices_deleted', v_devices,
    'ran_at', now()
  );
end;
$$;


ALTER FUNCTION "public"."mp_run_retention_cleanup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mp_throttle_check"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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


ALTER FUNCTION "public"."mp_throttle_check"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."publish_status"("p_state" "text", "p_call_okay" boolean, "p_instance_nonce" "uuid", "p_override_mode" "text" DEFAULT NULL::"text", "p_override_expires_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_screen_sharing" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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


ALTER FUNCTION "public"."publish_status"("p_state" "text", "p_call_okay" boolean, "p_instance_nonce" "uuid", "p_override_mode" "text", "p_override_expires_at" timestamp with time zone, "p_screen_sharing" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rebind_device"("p_recovery_secret" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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


ALTER FUNCTION "public"."rebind_device"("p_recovery_secret" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_device"("p_recovery_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
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
$_$;


ALTER FUNCTION "public"."register_device"("p_recovery_hash" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_all_viewers"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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


ALTER FUNCTION "public"."revoke_all_viewers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_viewer"("p_viewer_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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


ALTER FUNCTION "public"."revoke_viewer"("p_viewer_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rotate_pairing_codes"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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


ALTER FUNCTION "public"."rotate_pairing_codes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_device_profile"("p_display_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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


ALTER FUNCTION "public"."update_device_profile"("p_display_name" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."current_status" (
    "device_id" "uuid" NOT NULL,
    "state" "text" NOT NULL,
    "call_okay" boolean DEFAULT false NOT NULL,
    "screen_sharing" "text",
    "override_mode" "text",
    "override_expires_at" timestamp with time zone,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "schema_version" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "current_status_override_mode_check" CHECK (("override_mode" = ANY (ARRAY['busy'::"text", 'available'::"text"]))),
    CONSTRAINT "current_status_screen_sharing_check" CHECK (("screen_sharing" = ANY (ARRAY['yes'::"text", 'no'::"text", 'unavailable'::"text"]))),
    CONSTRAINT "current_status_state_check" CHECK (("state" = ANY (ARRAY['available'::"text", 'busy'::"text", 'unavailable'::"text"])))
);


ALTER TABLE "public"."current_status" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_user_id" "uuid",
    "display_name" "text",
    "recovery_hash" "text" NOT NULL,
    "instance_nonce" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone,
    CONSTRAINT "devices_display_name_len" CHECK ((("display_name" IS NULL) OR ("char_length"("display_name") <= 80))),
    CONSTRAINT "devices_recovery_hash_shape" CHECK (("recovery_hash" ~ '^[0-9a-f]{64}$'::"text"))
);


ALTER TABLE "public"."devices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pairing_attempts" (
    "user_id" "uuid" NOT NULL,
    "window_started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "attempt_count" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."pairing_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pairing_attempts_global" (
    "id" boolean DEFAULT true NOT NULL,
    "window_started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "failure_count" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "pairing_attempts_global_id_check" CHECK ("id")
);


ALTER TABLE "public"."pairing_attempts_global" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pairing_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_id" "uuid" NOT NULL,
    "code_hash" "text" NOT NULL,
    "expires_at" timestamp with time zone,
    "claimed_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pairing_codes_hash_shape" CHECK (("code_hash" ~ '^[0-9a-f]{64}$'::"text"))
);


ALTER TABLE "public"."pairing_codes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."viewers" (
    "device_id" "uuid" NOT NULL,
    "viewer_user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone
);


ALTER TABLE "public"."viewers" OWNER TO "postgres";


ALTER TABLE ONLY "public"."current_status"
    ADD CONSTRAINT "current_status_pkey" PRIMARY KEY ("device_id");



ALTER TABLE ONLY "public"."devices"
    ADD CONSTRAINT "devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pairing_attempts_global"
    ADD CONSTRAINT "pairing_attempts_global_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pairing_attempts"
    ADD CONSTRAINT "pairing_attempts_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."pairing_codes"
    ADD CONSTRAINT "pairing_codes_code_hash_key" UNIQUE ("code_hash");



ALTER TABLE ONLY "public"."pairing_codes"
    ADD CONSTRAINT "pairing_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."viewers"
    ADD CONSTRAINT "viewers_pkey" PRIMARY KEY ("device_id", "viewer_user_id");



CREATE UNIQUE INDEX "devices_one_active_per_owner" ON "public"."devices" USING "btree" ("owner_user_id") WHERE (("revoked_at" IS NULL) AND ("owner_user_id" IS NOT NULL));



CREATE UNIQUE INDEX "devices_recovery_hash_key" ON "public"."devices" USING "btree" ("recovery_hash");



CREATE INDEX "pairing_codes_active_idx" ON "public"."pairing_codes" USING "btree" ("device_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "pairing_codes_device_idx" ON "public"."pairing_codes" USING "btree" ("device_id");



CREATE UNIQUE INDEX "viewers_one_active_per_viewer" ON "public"."viewers" USING "btree" ("viewer_user_id") WHERE ("revoked_at" IS NULL);



ALTER TABLE ONLY "public"."current_status"
    ADD CONSTRAINT "current_status_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."devices"
    ADD CONSTRAINT "devices_owner_user_id_fkey" FOREIGN KEY ("owner_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pairing_attempts"
    ADD CONSTRAINT "pairing_attempts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pairing_codes"
    ADD CONSTRAINT "pairing_codes_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."viewers"
    ADD CONSTRAINT "viewers_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."viewers"
    ADD CONSTRAINT "viewers_viewer_user_id_fkey" FOREIGN KEY ("viewer_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."current_status" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "current_status_owner_select" ON "public"."current_status" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."devices" "d"
  WHERE (("d"."id" = "current_status"."device_id") AND ("d"."owner_user_id" = ( SELECT "auth"."uid"() AS "uid"))))));



ALTER TABLE "public"."devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "devices_owner_select" ON "public"."devices" FOR SELECT TO "authenticated" USING (("owner_user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."pairing_attempts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pairing_attempts_global" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pairing_codes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."viewers" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_pairing_code"("p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_pairing_code"("p_code" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."claim_pairing_code"("p_code" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_pairing_code"("p_code_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_pairing_code"("p_code_hash" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."create_pairing_code"("p_code_hash" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."delete_device"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_device"() TO "service_role";
GRANT ALL ON FUNCTION "public"."delete_device"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."delete_viewer"("p_viewer_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_viewer"("p_viewer_user_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."delete_viewer"("p_viewer_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_paired_status"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_paired_status"() TO "service_role";
GRANT ALL ON FUNCTION "public"."get_paired_status"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."list_viewers"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."list_viewers"() TO "service_role";
GRANT ALL ON FUNCTION "public"."list_viewers"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."mp_current_device_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mp_current_device_id"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."mp_hash_code"("p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mp_hash_code"("p_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mp_normalize_code"("p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mp_normalize_code"("p_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mp_record_failure"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mp_record_failure"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."mp_run_retention_cleanup"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mp_run_retention_cleanup"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."mp_throttle_check"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mp_throttle_check"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."publish_status"("p_state" "text", "p_call_okay" boolean, "p_instance_nonce" "uuid", "p_override_mode" "text", "p_override_expires_at" timestamp with time zone, "p_screen_sharing" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."publish_status"("p_state" "text", "p_call_okay" boolean, "p_instance_nonce" "uuid", "p_override_mode" "text", "p_override_expires_at" timestamp with time zone, "p_screen_sharing" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."publish_status"("p_state" "text", "p_call_okay" boolean, "p_instance_nonce" "uuid", "p_override_mode" "text", "p_override_expires_at" timestamp with time zone, "p_screen_sharing" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."rebind_device"("p_recovery_secret" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rebind_device"("p_recovery_secret" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."rebind_device"("p_recovery_secret" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."register_device"("p_recovery_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_device"("p_recovery_hash" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."register_device"("p_recovery_hash" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."revoke_all_viewers"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_all_viewers"() TO "service_role";
GRANT ALL ON FUNCTION "public"."revoke_all_viewers"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."revoke_viewer"("p_viewer_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_viewer"("p_viewer_user_id" "uuid") TO "service_role";
GRANT ALL ON FUNCTION "public"."revoke_viewer"("p_viewer_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."rotate_pairing_codes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rotate_pairing_codes"() TO "service_role";
GRANT ALL ON FUNCTION "public"."rotate_pairing_codes"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_device_profile"("p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_device_profile"("p_display_name" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."update_device_profile"("p_display_name" "text") TO "authenticated";



GRANT ALL ON TABLE "public"."current_status" TO "service_role";
GRANT SELECT ON TABLE "public"."current_status" TO "authenticated";



GRANT ALL ON TABLE "public"."devices" TO "service_role";
GRANT SELECT ON TABLE "public"."devices" TO "authenticated";



GRANT ALL ON TABLE "public"."pairing_attempts" TO "service_role";



GRANT ALL ON TABLE "public"."pairing_attempts_global" TO "service_role";



GRANT ALL ON TABLE "public"."pairing_codes" TO "service_role";



GRANT ALL ON TABLE "public"."viewers" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";

insert into public.pairing_attempts_global (id)
values (true)
on conflict do nothing;

do $$
begin
  if not exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) then
    begin
      create extension pg_cron with schema extensions;
    exception when insufficient_privilege or feature_not_supported then
      raise notice 'pg_cron not available; retention cleanup must be scheduled externally.';
    end;
  end if;
end;
$$;

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




