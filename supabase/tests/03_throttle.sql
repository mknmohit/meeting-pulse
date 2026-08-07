begin;

select plan(4);

create temporary table fixture (
  viewer_id uuid
);
grant all on fixture to authenticated, anon;
insert into fixture values (tests.create_user());

select tests.become((select viewer_id from fixture));
select is(
  public.claim_pairing_code(concat('bad', 'code-1')),
  '{"ok": false, "reason": "invalid_code"}'::jsonb,
  'first invalid attempt is generic'
);
select public.claim_pairing_code(concat('bad', 'code-2'));
select public.claim_pairing_code(concat('bad', 'code-3'));
select public.claim_pairing_code(concat('bad', 'code-4'));
select public.claim_pairing_code(concat('bad', 'code-5'));
select is(
  public.claim_pairing_code(concat('bad', 'code-6')),
  '{"ok": false, "reason": "rate_limited"}'::jsonb,
  'sixth attempt is rate limited'
);

select tests.advance_user_window((select viewer_id from fixture));
select is(
  public.claim_pairing_code(concat('bad', 'code-7')),
  '{"ok": false, "reason": "invalid_code"}'::jsonb,
  'new tumbling window allows another attempt'
);

select tests.set_global_failures(100);
select tests.become(tests.create_user());
select is(
  public.claim_pairing_code(concat('bad', 'code-8')),
  '{"ok": false, "reason": "rate_limited"}'::jsonb,
  'global circuit breaker blocks a new anonymous identity'
);

select * from finish();
rollback;
