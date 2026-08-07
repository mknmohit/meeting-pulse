create table public.devices (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete set null,
  display_name text,
  recovery_hash text not null,
  instance_nonce uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint devices_display_name_len
    check (display_name is null or char_length(display_name) <= 80),
  constraint devices_recovery_hash_shape
    check (recovery_hash ~ '^[0-9a-f]{64}$')
);

create unique index devices_one_active_per_owner
  on public.devices(owner_user_id)
  where revoked_at is null and owner_user_id is not null;

create unique index devices_recovery_hash_key
  on public.devices(recovery_hash);

create table public.current_status (
  device_id uuid primary key references public.devices(id) on delete cascade,
  state text not null check (state in ('available', 'busy', 'unavailable')),
  call_okay boolean not null default false,
  screen_sharing text check (screen_sharing in ('yes', 'no', 'unavailable')),
  override_mode text check (override_mode in ('busy', 'available')),
  override_expires_at timestamptz,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  schema_version integer not null default 1
);

create table public.pairing_codes (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.devices(id) on delete cascade,
  code_hash text not null unique,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint pairing_codes_hash_shape
    check (code_hash ~ '^[0-9a-f]{64}$')
);

create index pairing_codes_device_idx on public.pairing_codes(device_id);
create index pairing_codes_live_idx on public.pairing_codes(expires_at)
  where claimed_at is null and revoked_at is null;

create table public.viewers (
  device_id uuid not null references public.devices(id) on delete cascade,
  viewer_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (device_id, viewer_user_id)
);

create unique index viewers_one_active_per_viewer
  on public.viewers(viewer_user_id)
  where revoked_at is null;

create index viewers_viewer_idx
  on public.viewers(viewer_user_id)
  where revoked_at is null;

create table public.pairing_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  attempt_count integer not null default 0
);

create table public.pairing_attempts_global (
  id boolean primary key default true check (id),
  window_started_at timestamptz not null default now(),
  failure_count integer not null default 0
);

insert into public.pairing_attempts_global (id)
values (true)
on conflict do nothing;
