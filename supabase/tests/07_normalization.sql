begin;

select plan(50);

create temporary table fixture (
  input text not null,
  normalized text not null,
  sha256 text not null
);

\ir generated_normalization_values.sql.in

select is(
  public.mp_normalize_code(input),
  normalized,
  'normalizes ' || quote_literal(input)
)
from fixture
order by input, normalized;

select is(
  public.mp_hash_code(input),
  sha256,
  'hashes ' || quote_literal(input)
)
from fixture
order by input, normalized;

select * from finish();
rollback;
