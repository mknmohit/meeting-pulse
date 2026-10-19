import { GoTrueClient } from '@supabase/auth-js';
import { CONFIG } from '../config';

const projectRef = new URL(CONFIG.supabaseUrl).hostname.split('.')[0] ?? '';

export const auth = new GoTrueClient({
  url: `${CONFIG.supabaseUrl}/auth/v1`,
  headers: {
    apikey: CONFIG.supabaseAnonKey,
  },
  // Keep the storage key used by createClient so existing viewers stay paired.
  storageKey: `sb-${projectRef}-auth-token`,
  persistSession: true,
  autoRefreshToken: true,
  detectSessionInUrl: false,
});

export type RpcResult<T> = {
  data: T | null;
  error: Error | null;
};

export class SupabaseRpcError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = 'SupabaseRpcError';
    this.status = status;
  }
}

async function rpc<T = unknown>(
  functionName: string,
  params: Record<string, unknown> = {},
): Promise<RpcResult<T>> {
  const sessionResult = await auth.getSession();
  if (sessionResult.error) {
    return { data: null, error: sessionResult.error };
  }
  const session = sessionResult.data.session;
  if (!session) {
    return {
      data: null,
      error: new SupabaseRpcError(
        'Meeting Pulse: an authenticated session is required.',
        401,
      ),
    };
  }

  const endpoint = new URL(
    `rest/v1/rpc/${encodeURIComponent(functionName)}`,
    `${CONFIG.supabaseUrl}/`,
  );
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${session.access_token}`,
      'Content-Type': 'application/json',
      'Content-Profile': 'public',
      apikey: CONFIG.supabaseAnonKey,
    },
    body: JSON.stringify(params),
  });
  const text = await response.text();
  let body: unknown = null;
  if (text) {
    try {
      body = JSON.parse(text) as unknown;
    } catch {
      if (response.ok) {
        return {
          data: null,
          error: new SupabaseRpcError(
            `Meeting Pulse: ${functionName} returned an invalid response.`,
            response.status,
          ),
        };
      }
      body = text;
    }
  }

  if (!response.ok) {
    return {
      data: null,
      error: new SupabaseRpcError(
        rpcErrorMessage(body, functionName, response.status),
        response.status,
      ),
    };
  }
  return { data: body as T, error: null };
}

function rpcErrorMessage(
  body: unknown,
  functionName: string,
  status: number,
): string {
  if (
    typeof body === 'object' &&
    body !== null &&
    'message' in body &&
    typeof body.message === 'string' &&
    body.message.trim()
  ) {
    return body.message;
  }
  return `Meeting Pulse: ${functionName} failed with status ${status}.`;
}

export const supabase = {
  auth,
  rpc,
};
