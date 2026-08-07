import {
  ConfigurationError,
  required,
  requiredUrl,
  requiredUrls,
} from './lib/configValidation';

const SUPABASE_HOST = /^[a-z0-9-]{8,}\.supabase\.co$/;
const JWT_SEGMENTS = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const PUBLISHABLE_KEY = /^sb_publishable_[A-Za-z0-9_-]+$/;

const supabaseUrl = requiredUrl(
  'PUBLIC_SUPABASE_URL',
  import.meta.env.PUBLIC_SUPABASE_URL,
);
if (!SUPABASE_HOST.test(new URL(supabaseUrl).hostname)) {
  throw new ConfigurationError(
    'PUBLIC_SUPABASE_URL',
    'must point to a Supabase host',
  );
}
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

const statusOrigins = requiredUrls(
  'PUBLIC_STATUS_ORIGINS',
  import.meta.env.PUBLIC_STATUS_ORIGINS,
);

export const CONFIG = {
  supabaseUrl,
  supabaseAnonKey,
  statusOrigin: statusOrigins[0],
  statusOrigins,
  turnstileSiteKey: required(
    'PUBLIC_TURNSTILE_SITE_KEY',
    import.meta.env.PUBLIC_TURNSTILE_SITE_KEY,
  ),
} as const;

export const SUPPORTED_SCHEMA_VERSION = 1;
export const POLL_INTERVAL_MS = 30_000;
export const STALE_AFTER_SECONDS = 180;
