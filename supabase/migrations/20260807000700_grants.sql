revoke all on table public.devices from anon;
revoke all on table public.current_status from anon;
revoke all on table public.pairing_codes from anon;
revoke all on table public.viewers from anon;
revoke all on table public.pairing_attempts from anon;
revoke all on table public.pairing_attempts_global from anon;

grant select on public.devices to authenticated;
grant select on public.current_status to authenticated;

revoke execute on all functions in schema public from public;

grant execute on function public.register_device(text) to authenticated;
grant execute on function public.publish_status(
  text, boolean, uuid, text, timestamptz, text
) to authenticated;
grant execute on function public.update_device_profile(text) to authenticated;
grant execute on function public.create_pairing_code(text) to authenticated;
grant execute on function public.rotate_pairing_codes() to authenticated;
grant execute on function public.revoke_viewer(uuid) to authenticated;
grant execute on function public.revoke_all_viewers() to authenticated;
grant execute on function public.list_viewers() to authenticated;
grant execute on function public.rebind_device(text) to authenticated;
grant execute on function public.delete_device() to authenticated;
grant execute on function public.claim_pairing_code(text) to authenticated;
grant execute on function public.get_paired_status() to authenticated;
