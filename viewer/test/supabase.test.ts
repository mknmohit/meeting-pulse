import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  getSession: vi.fn(),
}));

vi.mock('@supabase/auth-js', () => ({
  GoTrueClient: class {
    getSession = mocks.getSession;
  },
}));

vi.mock('../src/config', () => ({
  CONFIG: {
    supabaseUrl: 'https://project123456.supabase.co',
    supabaseAnonKey: 'publishable-key',
  },
}));

import { supabase } from '../src/lib/supabase';

describe('lightweight Supabase RPC client', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
    mocks.getSession.mockResolvedValue({
      data: { session: { access_token: 'access-token' } },
      error: null,
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  it('sends the authenticated RPC request and parses its response', async () => {
    const fetchMock = vi.mocked(fetch);
    fetchMock.mockResolvedValue(
      new Response(JSON.stringify({ paired: false }), { status: 200 }),
    );

    await expect(supabase.rpc('get_paired_status')).resolves.toEqual({
      data: { paired: false },
      error: null,
    });

    const call = fetchMock.mock.calls[0];
    if (!call) {
      throw new Error('RPC request was not sent.');
    }
    const [url, init] = call;
    expect(String(url)).toBe(
      'https://project123456.supabase.co/rest/v1/rpc/get_paired_status',
    );
    expect(init?.method).toBe('POST');
    expect(init?.body).toBe('{}');
    const headers = new Headers(init?.headers);
    expect(headers.get('Authorization')).toMatch(/^Bearer .+/u);
    expect(headers.get('apikey')).toBe('publishable-key');
  });

  it('returns an explicit error without fetching when no session exists', async () => {
    mocks.getSession.mockResolvedValue({
      data: { session: null },
      error: null,
    });

    await expect(supabase.rpc('get_paired_status')).resolves.toMatchObject({
      data: null,
      error: {
        message: 'Meeting Pulse: an authenticated session is required.',
        status: 401,
      },
    });
    expect(fetch).not.toHaveBeenCalled();
  });

  it('preserves the RPC error message for failed responses', async () => {
    vi.mocked(fetch).mockResolvedValue(
      new Response(JSON.stringify({ message: 'invalid_code' }), {
        status: 400,
      }),
    );

    await expect(
      supabase.rpc('claim_pairing_code', { p_code: 'bad' }),
    ).resolves.toMatchObject({
      data: null,
      error: {
        message: 'invalid_code',
        status: 400,
      },
    });
  });
});
