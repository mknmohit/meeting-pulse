begin;

select plan(9);

create temporary table fixture (
  owner_id uuid,
  viewer_id uuid,
  device_id uuid
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
)::uuid;
select public.create_pairing_code(
  'c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646'
);

select tests.become((select viewer_id from fixture));
select is(
  public.claim_pairing_code(concat('123', '45', '678', '90')),
  '{"ok": true}'::jsonb,
  'valid persistent code claims'
);
select is(
  public.claim_pairing_code(concat('123', '45', '678', '90')),
  '{"ok": true}'::jsonb,
  'persistent code can be reused'
);
select is(
  (tests.code_expiry(
    'c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646'
  ) is null),
  true,
  'persistent code has no expiry'
);

select tests.become((select owner_id from fixture));
select is(
  public.rotate_pairing_codes(),
  1,
  'rotation revokes the active code'
);
select tests.become((select viewer_id from fixture));
select is(
  public.claim_pairing_code(concat('123', '45', '678', '90')),
  '{"ok": false, "reason": "invalid_code"}'::jsonb,
  'rotated code is generic'
);

select tests.become((select owner_id from fixture));
select public.create_pairing_code(
  'f57cbf1e3e471b25db4b8ad0844df41b2dae9c7d1944944d128e49294d412f66'
);
select tests.revoke_code(
  'f57cbf1e3e471b25db4b8ad0844df41b2dae9c7d1944944d128e49294d412f66'
);
select tests.become((select viewer_id from fixture));
select is(
  public.claim_pairing_code(concat('AB', 'CDE', 'FG', 'HJK')),
  '{"ok": false, "reason": "invalid_code"}'::jsonb,
  'revoked code is generic'
);

select tests.become((select owner_id from fixture));
select public.create_pairing_code(
  '84d9c4b849506b6d8f8075a9000e7e0a254be71060ea889fad3c88395988f4fc'
);
select tests.expire_code(
  '84d9c4b849506b6d8f8075a9000e7e0a254be71060ea889fad3c88395988f4fc'
);
select tests.become((select viewer_id from fixture));
select is(
  public.claim_pairing_code(concat('00000', '00000')),
  '{"ok": false, "reason": "invalid_code"}'::jsonb,
  'expired code is generic'
);

select tests.advance_user_window((select viewer_id from fixture));
select is(
  public.claim_pairing_code(concat('not', 'a-code')),
  '{"ok": false, "reason": "invalid_code"}'::jsonb,
  'garbage code is generic'
);
select is(
  (
    select tests.count_code_hash(concat('12345', '67890'))
  ),
  0,
  'raw code is never stored as a hash'
);

select * from finish();
rollback;
