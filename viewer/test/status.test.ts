import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
}));

vi.mock('../src/lib/supabase', () => ({
  supabase: {
    rpc: mocks.rpc,
  },
}));

import { fetchPairedStatus } from '../src/lib/status';

function response(state: string) {
  return {
    paired: true,
    display_name: 'Owner',
    state,
    call_okay: false,
    last_seen_at: '2026-08-08T08:47:15.350809+00:00',
    server_now: '2026-08-08T09:12:28.850685+00:00',
    schema_version: 1,
  };
}

describe('paired status normalization', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it.each(['available', 'busy', 'unavailable'])(
    'preserves the supported %s state',
    async (state) => {
      mocks.rpc.mockResolvedValue({
        data: response(state),
        error: null,
      });

      await expect(fetchPairedStatus()).resolves.toMatchObject({
        paired: true,
        state,
      });
    },
  );

  it('normalizes an unknown state to unavailable', async () => {
    mocks.rpc.mockResolvedValue({
      data: response('future_state'),
      error: null,
    });

    await expect(fetchPairedStatus()).resolves.toMatchObject({
      paired: true,
      state: 'unavailable',
    });
  });
});
