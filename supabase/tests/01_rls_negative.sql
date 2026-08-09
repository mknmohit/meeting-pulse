begin;

select plan(15);

create temporary table fixture (
  owner_a uuid,
  owner_b uuid,
  viewer uuid,
  device_a uuid
);
grant all on fixture to authenticated, anon;

insert into fixture (owner_a, owner_b, viewer)
values (tests.create_user(), tests.create_user(), tests.create_user());

select tests.become((select owner_a from fixture));
update fixture
set device_a = (public.register_device(repeat('a', 64))->>'device_id')::uuid;

select tests.become((select viewer from fixture));
select is(
  (select count(*)::integer from public.current_status),
  0,
  'viewer cannot select current_status'
);
select is(
  (select count(*)::integer from public.devices),
  0,
  'viewer cannot select devices'
);
select throws_ok(
  $$ update public.current_status
     set state = 'busy'
     where device_id = (select device_a from fixture) $$,
  '42501',
  'permission denied for table current_status',
  'viewer cannot update current_status'
);
select throws_ok(
  $$ select count(*) from public.pairing_codes $$,
  '42501',
  'permission denied for table pairing_codes',
  'clients cannot select pairing_codes'
);
select throws_ok(
  $$ select count(*) from public.pairing_attempts_global $$,
  '42501',
  'permission denied for table pairing_attempts_global',
  'clients cannot select global throttle state'
);
select throws_ok(
  $$ select public.mp_throttle_check() $$,
  '42501',
  'permission denied for function mp_throttle_check',
  'clients cannot execute throttle helper'
);
select throws_ok(
  $$ select public.mp_hash_code(concat('123', '45', '678', '90')) $$,
  '42501',
  'permission denied for function mp_hash_code',
  'clients cannot execute hash helper'
);

select tests.become((select owner_a from fixture));
select is(
  (select count(*)::integer
   from public.devices
   where owner_user_id = (select owner_b from fixture)),
  0,
  'owner A cannot select owner B device'
);
select throws_ok(
  $$ insert into public.current_status (device_id, state)
     values ((select device_a from fixture), 'busy') $$,
  '42501',
  'permission denied for table current_status',
  'owners cannot insert status directly'
);

select tests.become_anon();
select throws_ok(
  $$ select public.get_paired_status() $$,
  '42501',
  'permission denied for function get_paired_status',
  'anon cannot execute viewer status RPC'
);

select tests.become((select owner_a from fixture));
select is(
  (public.register_device(repeat('a', 64))->>'device_id')::uuid,
  (select device_a from fixture),
  'register_device is idempotent'
);
select throws_ok(
  $$ select tests.insert_device(
       (select owner_a from fixture),
       repeat('b', 64)
     ) $$,
  '23505',
  'duplicate key value violates unique constraint "devices_one_active_per_owner"',
  'one active device is enforced per owner'
);

select tests.insert_viewer(
  (select device_a from fixture),
  (select viewer from fixture)
);
select throws_ok(
  $$ select tests.insert_viewer(
       tests.insert_device(
         (select owner_b from fixture),
         repeat('c', 64)
       ),
       (select viewer from fixture)
     ) $$,
  '23505',
  'duplicate key value violates unique constraint "viewers_one_active_per_viewer"',
  'one active pairing is enforced per viewer'
);

select tests.become((select viewer from fixture));
select throws_ok(
  $$ select public.delete_viewer((select viewer from fixture)) $$,
  '42704',
  'no_device',
  'viewers cannot hard-delete a binding'
);

select is(
  (
    select r.rolbypassrls
    from pg_roles r
    join pg_proc p on p.proowner = r.oid
    where p.proname = 'publish_status'
    limit 1
  ),
  true,
  'definer role bypasses RLS explicitly'
);

select * from finish();
rollback;
