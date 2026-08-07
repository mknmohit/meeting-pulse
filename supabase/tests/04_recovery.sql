begin;

select plan(6);

create temporary table fixture (
  owner_a uuid,
  owner_b uuid,
  viewer_id uuid,
  device_id uuid,
  nonce_a uuid,
  nonce_b uuid
);
grant all on fixture to authenticated, anon;
insert into fixture (owner_a, owner_b, viewer_id)
values (tests.create_user(), tests.create_user(), tests.create_user());

select tests.become((select owner_a from fixture));
update fixture
set device_id = (
  public.register_device(
    '5ebd2ee945a5b53c173654f6950da9bcfb84bee4ee41f0100464236aec51f67c'
  )->>'device_id'
)::uuid,
nonce_a = (
  public.register_device(
    '5ebd2ee945a5b53c173654f6950da9bcfb84bee4ee41f0100464236aec51f67c'
  )->>'instance_nonce'
)::uuid;

select tests.insert_viewer(
  (select device_id from fixture),
  (select viewer_id from fixture)
);

select tests.become((select owner_b from fixture));
select is(
  (public.rebind_device(concat('RECOV', '12345'))->>'device_id')::uuid,
  (select device_id from fixture),
  'rebind keeps the same device id'
);
update fixture
set nonce_b = (
  select instance_nonce
  from public.devices
  where id = device_id
);
select isnt(
  (select nonce_b from fixture),
  (select nonce_a from fixture),
  'rebind rotates the instance nonce'
);

select tests.become((select viewer_id from fixture));
select is(
  (public.get_paired_status()->>'paired')::boolean,
  true,
  'viewer pairing survives rebind'
);

select tests.become((select owner_b from fixture));
select tests.set_global_failures(0);
select is(
  public.rebind_device(concat('WRONG', 'SECRET')),
  '{"ok": false, "reason": "invalid_recovery_secret"}'::jsonb,
  'wrong recovery secret fails'
);
select is(
  tests.global_failures(),
  1,
  'wrong recovery secret records a global failure'
);

create temporary table orphan_fixture (
  owner_id uuid,
  viewer_id uuid,
  existing_device uuid,
  target_device uuid
);
grant all on orphan_fixture to authenticated, anon;
insert into orphan_fixture (owner_id, viewer_id)
values (tests.create_user(), tests.create_user());
select tests.become((select owner_id from orphan_fixture));
update orphan_fixture
set existing_device = (
  public.register_device(
    '6ab3f78a9f51c9ad828385940fc677f7d5ac0a733e51f388bc208616205ea145'
  )->>'device_id'
)::uuid;
select tests.insert_viewer(
  (select existing_device from orphan_fixture),
  (select viewer_id from orphan_fixture)
);
update orphan_fixture
set target_device = tests.insert_device(
  null,
  '86b9c527b5809eed61f58a609ead0297ecffec9d65ca74bc11595ca209bb944a'
);
select throws_ok(
  $$ select public.rebind_device(concat('REBIN', '12345')) $$,
  '23505',
  'rebind_would_orphan',
  'rebind refuses to orphan an existing paired device'
);

select * from finish();
rollback;
