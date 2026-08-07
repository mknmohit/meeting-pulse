create or replace function public.get_paired_status()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
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
    'server_now', now(),
    'schema_version', cs.schema_version
  )
  into v_result
  from public.viewers v
  join public.devices d on d.id = v.device_id
  join public.current_status cs on cs.device_id = d.id
  where v.viewer_user_id = v_uid
    and v.revoked_at is null
    and d.revoked_at is null
  order by v.created_at desc
  limit 1;

  return coalesce(
    v_result,
    jsonb_build_object('paired', false, 'server_now', now())
  );
end;
$$;

revoke execute on function public.get_paired_status() from public;
grant execute on function public.get_paired_status() to authenticated;
