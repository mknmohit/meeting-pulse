import { describe, expect, it } from 'vitest';

describe('Supabase publishable key configuration', () => {
  it('accepts the modern publishable-key shape', () => {
    expect(
      /^sb_publishable_[A-Za-z0-9_-]+$/.test('sb_publishable_ci_key'),
    ).toBe(true);
  });
});
