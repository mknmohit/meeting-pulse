alter table public.devices enable row level security;
alter table public.current_status enable row level security;
alter table public.pairing_codes enable row level security;
alter table public.viewers enable row level security;
alter table public.pairing_attempts enable row level security;
alter table public.pairing_attempts_global enable row level security;

create policy devices_owner_select on public.devices
  for select to authenticated
  using (owner_user_id = (select auth.uid()));

create policy current_status_owner_select on public.current_status
  for select to authenticated
  using (exists (
    select 1
    from public.devices d
    where d.id = current_status.device_id
      and d.owner_user_id = (select auth.uid())
  ));
