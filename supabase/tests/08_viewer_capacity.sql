begin;

select plan(25);

create temporary table fixture (
  owner_id uuid,
  device_id uuid,
  viewer_a uuid,
  viewer_b uuid,
  viewer_c uuid,
  viewer_d uuid,
  viewer_e uuid,
  viewer_f uuid
);
grant all on fixture to authenticated, anon;

insert into fixture (
  owner_id,
  viewer_a,
  viewer_b,
  viewer_c,
  viewer_d,
  viewer_e,
  viewer_f
)
values (
  tests.create_user(),
  tests.create_user(),
  tests.create_user(),
  tests.create_user(),
  tests.create_user(),
  tests.create_user(),
  tests.create_user()
);

select tests.become((select owner_id from fixture));
update fixture
set device_id = (
  public.register_device(repeat('8', 64))->>'device_id'
)::uuid;
select public.create_pairing_code(
  '7619ee8cea49187f309616e30ecf54be072259b43760f1f550a644945d5572f2'
);

select tests.become((select viewer_a from fixture));
select is(
  public.claim_pairing_code('9876543210'),
  '{"ok": true}'::jsonb,
  'first viewer claims the persistent code'
);

select tests.become((select viewer_b from fixture));
select is(
  public.claim_pairing_code('9876543210'),
  '{"ok": true}'::jsonb,
  'second viewer claims the persistent code'
);

select tests.become((select viewer_c from fixture));
select is(
  public.claim_pairing_code('9876543210'),
  '{"ok": true}'::jsonb,
  'third viewer claims the persistent code'
);

select tests.become((select viewer_d from fixture));
select is(
  public.claim_pairing_code('9876543210'),
  '{"ok": true}'::jsonb,
  'fourth viewer claims the persistent code'
);

select tests.become((select viewer_e from fixture));
select is(
  public.claim_pairing_code('9876543210'),
  '{"ok": true}'::jsonb,
  'fifth viewer claims the persistent code'
);

select tests.become((select owner_id from fixture));
select is(
  (select count(*)::integer from public.list_viewers()),
  5,
  'five active viewers are listed'
);

select tests.become((select viewer_f from fixture));
select is(
  public.claim_pairing_code('9876543210'),
  '{"ok": true}'::jsonb,
  'sixth viewer claims by evicting the oldest binding'
);

select tests.become((select owner_id from fixture));
select is(
  (select count(*)::integer from public.list_viewers()),
  5,
  'sixth claim keeps the active count at five'
);
select is(
  (select count(*)::integer
   from public.list_viewers()
   where viewer_user_id = (select viewer_a from fixture)),
  0,
  'oldest viewer is no longer active'
);
select is(
  (select count(*)::integer
   from public.list_viewers()
   where viewer_user_id = (select viewer_b from fixture)),
  1,
  'second viewer remains active'
);
select is(
  (select count(*)::integer
   from public.list_viewers()
   where viewer_user_id = (select viewer_c from fixture)),
  1,
  'third viewer remains active'
);
select is(
  (select count(*)::integer
   from public.list_viewers()
   where viewer_user_id = (select viewer_d from fixture)),
  1,
  'fourth viewer is active'
);
select is(
  (select count(*)::integer
   from public.list_viewers()
   where viewer_user_id = (select viewer_e from fixture)),
  1,
  'fifth viewer remains active'
);
select is(
  (select count(*)::integer
   from public.list_viewers()
   where viewer_user_id = (select viewer_f from fixture)),
  1,
  'sixth viewer is active'
);

select tests.become((select viewer_c from fixture));
select is(
  public.claim_pairing_code('9876543210'),
  '{"ok": true}'::jsonb,
  'an active viewer can re-claim without displacement'
);

select tests.become((select owner_id from fixture));
select is(
  (select count(*)::integer from public.list_viewers()),
  5,
  're-claiming an active viewer keeps five active rows'
);

select public.delete_viewer((select viewer_c from fixture));
select is(
  (select count(*)::integer from public.list_viewers()),
  4,
  'owner hard-delete removes the selected viewer binding'
);
select is(
  (select count(*)::integer
   from public.list_viewers()
   where viewer_user_id = (select viewer_d from fixture)),
  1,
  'owner hard-delete leaves other viewers active'
);

select tests.become((select viewer_c from fixture));
select is(
  public.claim_pairing_code('9876543210'),
  '{"ok": true}'::jsonb,
  'a hard-deleted viewer can use the persistent code again'
);

select tests.become((select owner_id from fixture));
select tests.age_viewer(
  (select device_id from fixture),
  (select viewer_b from fixture),
  31
);

select tests.become((select viewer_b from fixture));
select is(
  public.get_paired_status()->>'paired',
  'false',
  'a binding older than 30 days is unavailable to the viewer'
);

select tests.become((select owner_id from fixture));
select is(
  (select count(*)::integer from public.list_viewers()),
  4,
  'expired active bindings are omitted from the owner list'
);
select tests.insert_expired_code(
  (select device_id from fixture),
  repeat('d', 64)
);
create temporary table cleanup_result (result jsonb);
insert into cleanup_result
select tests.run_retention_cleanup();
select is(
  ((select result from cleanup_result)->>'expired_viewers_deleted')::integer,
  1,
  'retention cleanup deletes expired active bindings'
);
select is(
  ((select result from cleanup_result)->>'pairing_codes_deleted')::integer,
  1,
  'retention cleanup deletes expired unclaimed codes'
);

select tests.become((select viewer_b from fixture));
select is(
  public.claim_pairing_code('9876543210'),
  '{"ok": true}'::jsonb,
  'an expired viewer can pair again with the persistent code'
);

select tests.become((select owner_id from fixture));
select is(
  (select count(*)::integer from public.list_viewers()),
  5,
  're-pairing after cleanup restores the capacity'
);

select * from finish();
rollback;
