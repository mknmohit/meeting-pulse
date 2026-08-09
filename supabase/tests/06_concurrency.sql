select plan(3);

create temporary table fixture (
  owner_id uuid,
  viewer_a uuid,
  viewer_b uuid,
  recovery_hash text,
  device_id uuid
);
grant all on fixture to authenticated, anon;
insert into fixture (owner_id, viewer_a, viewer_b, recovery_hash)
values (
  tests.create_user(),
  tests.create_user(),
  tests.create_user(),
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
);

select dblink_connect_u(
  'register_a',
  'host=127.0.0.1 port=5432 dbname=postgres user=supabase_admin password=postgres'
);
select dblink_connect_u(
  'register_b',
  'host=127.0.0.1 port=5432 dbname=postgres user=supabase_admin password=postgres'
);

select dblink_exec(
  'register_a',
  format(
    'set role authenticated; set request.jwt.claims = %L',
    json_build_object(
      'sub', (select owner_id from fixture),
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text
  )
);
select dblink_exec(
  'register_b',
  format(
    'set role authenticated; set request.jwt.claims = %L',
    json_build_object(
      'sub', (select owner_id from fixture),
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text
  )
);
select dblink_send_query(
  'register_a',
  format(
    'select public.register_device(%L)::text',
    (select recovery_hash from fixture)
  )
);
select dblink_send_query(
  'register_b',
  format(
    'select public.register_device(%L)::text',
    (select recovery_hash from fixture)
  )
);
create temporary table registrations (result jsonb);
insert into registrations
select result::jsonb
from dblink_get_result('register_a') as response(result text);
insert into registrations
select result::jsonb
from dblink_get_result('register_b') as response(result text);
select is(
  (select count(distinct result->>'device_id')::integer from registrations),
  1,
  'concurrent registration returns one device id'
);

select tests.become((select owner_id from fixture));
update fixture
set device_id = (
  public.register_device(
    (select recovery_hash from fixture)
  )->>'device_id'
)::uuid;
select public.create_pairing_code(
  'c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646'
);

select dblink_connect_u(
  'claim_a',
  'host=127.0.0.1 port=5432 dbname=postgres user=supabase_admin password=postgres'
);
select dblink_connect_u(
  'claim_b',
  'host=127.0.0.1 port=5432 dbname=postgres user=supabase_admin password=postgres'
);
select dblink_exec(
  'claim_a',
  format(
    'set role authenticated; set request.jwt.claims = %L',
    json_build_object(
      'sub', (select viewer_a from fixture),
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text
  )
);
select dblink_exec(
  'claim_b',
  format(
    'set role authenticated; set request.jwt.claims = %L',
    json_build_object(
      'sub', (select viewer_b from fixture),
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text
  )
);
select dblink_send_query(
  'claim_a',
  $$ select public.claim_pairing_code(concat('123', '45', '678', '90'))::text $$
);
select dblink_send_query(
  'claim_b',
  $$ select public.claim_pairing_code(concat('123', '45', '678', '90'))::text $$
);
create temporary table claims (result jsonb);
insert into claims
select result::jsonb
from dblink_get_result('claim_a') as response(result text);
insert into claims
select result::jsonb
from dblink_get_result('claim_b') as response(result text);
select is(
  (select count(*)::integer from claims where (result->>'ok')::boolean),
  2,
  'concurrent persistent claims both succeed'
);
select tests.become((select owner_id from fixture));
select is(
  (select count(*)::integer
   from public.list_viewers()
   where revoked_at is null),
  2,
  'concurrent claims leave both viewers active'
);

select dblink_disconnect('register_a');
select dblink_disconnect('register_b');
select dblink_disconnect('claim_a');
select dblink_disconnect('claim_b');

select * from finish();
