begin;

select plan(8);

create temporary table fixture (
  owner_id uuid,
  viewer_id uuid,
  device_id uuid,
  nonce uuid
);
grant all on fixture to authenticated, anon;
insert into fixture (owner_id, viewer_id)
values (tests.create_user(), tests.create_user());

select tests.become((select owner_id from fixture));
update fixture
set device_id = (
  public.register_device(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  )->>'device_id'
)::uuid,
nonce = (
  public.register_device(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  )->>'instance_nonce'
)::uuid;
select public.update_device_profile('Alice');
select public.publish_status(
  'busy',
  true,
  (select nonce from fixture),
  'busy',
  now() + interval '30 minutes',
  null
);
select public.create_pairing_code(
  'c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646'
);

select tests.become((select viewer_id from fixture));
select public.claim_pairing_code(concat('12345', '67890'));
select is(
  (public.get_paired_status()->>'paired')::boolean,
  true,
  'paired viewer receives a status'
);
select is(
  public.get_paired_status()->>'state',
  'busy',
  'viewer receives the current state'
);
select is(
  (public.get_paired_status()->>'call_okay')::boolean,
  true,
  'viewer receives call okay'
);
select is(
  (select count(*)::integer from jsonb_object_keys(public.get_paired_status())),
  7,
  'viewer projection has exactly seven keys'
);
select is(
  public.get_paired_status() ? 'device_id',
  false,
  'viewer projection omits device id'
);
select is(
  public.get_paired_status() ? 'override_mode',
  false,
  'viewer projection omits override metadata'
);
select ok(
  (
    public.get_paired_status()->>'server_now'
  )::timestamptz >= (
    public.get_paired_status()->>'last_seen_at'
  )::timestamptz,
  'server_now is not older than last_seen_at'
);

select tests.become((select owner_id from fixture));
select public.revoke_viewer((select viewer_id from fixture));
select tests.become((select viewer_id from fixture));
select is(
  (public.get_paired_status()->>'paired')::boolean,
  false,
  'revoked viewer receives an unpaired projection'
);

select * from finish();
rollback;
