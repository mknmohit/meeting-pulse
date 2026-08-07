import { ConfigurationError, required } from './lib/configValidation';

const SUPABASE_HOST = /^[a-z0-9-]{8,}\.supabase\.co$/;
const JWT_SEGMENTS = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const PUBLISHABLE_KEY = /^sb_publishable_[A-Za-z0-9_-]+$/;

function requiredUrl(name: string, value: string | undefined): string {
  const raw = required(name, value);
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new ConfigurationError(name, 'is malformed');
  }
  if (parsed.protocol !== 'https:') {
    throw new ConfigurationError(name, 'must use https');
  }
  if (name === 'PUBLIC_SUPABASE_URL' && !SUPABASE_HOST.test(parsed.hostname)) {
    throw new ConfigurationError(name, 'must point to a Supabase host');
  }
  return parsed.toString().replace(/\/$/, '');
}

const supabaseUrl = requiredUrl(
  'PUBLIC_SUPABASE_URL',
  import.meta.env.PUBLIC_SUPABASE_URL,
);
const supabaseAnonKey = required(
  'PUBLIC_SUPABASE_ANON_KEY',
  import.meta.env.PUBLIC_SUPABASE_ANON_KEY,
);
if (
  !JWT_SEGMENTS.test(supabaseAnonKey) &&
  !PUBLISHABLE_KEY.test(supabaseAnonKey)
) {
  throw new ConfigurationError(
    'PUBLIC_SUPABASE_ANON_KEY',
    'must be a legacy JWT or an sb_publishable key',
  );
}

export const CONFIG = {
  supabaseUrl,
  supabaseAnonKey,
  statusOrigin: requiredUrl(
    'PUBLIC_STATUS_ORIGIN',
    import.meta.env.PUBLIC_STATUS_ORIGIN,
  ),
  turnstileSiteKey: required(
    'PUBLIC_TURNSTILE_SITE_KEY',
    import.meta.env.PUBLIC_TURNSTILE_SITE_KEY,
  ),
} as const;

export const SUPPORTED_SCHEMA_VERSION = 1;
export const POLL_INTERVAL_MS = 30_000;
export const STALE_AFTER_SECONDS = 180;
