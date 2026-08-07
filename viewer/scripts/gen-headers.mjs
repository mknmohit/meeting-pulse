import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const envPath = resolve(root, '.env');

function readEnvFile() {
  try {
    return readFileSync(envPath, 'utf8')
      .split(/\r?\n/u)
      .reduce((values, line) => {
        const match = line.match(/^([A-Z0-9_]+)=(.*)$/u);
        if (match?.[1] && match[2] !== undefined) {
          values[match[1]] = match[2].trim().replace(/^(['"])(.*)\1$/u, '$2');
        }
        return values;
      }, {});
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return {};
    }
    throw error;
  }
}

const env = { ...readEnvFile(), ...process.env };
const supabaseUrl = env.PUBLIC_SUPABASE_URL;
if (!supabaseUrl?.trim() || /YOUR_|example\.com/u.test(supabaseUrl)) {
  throw new Error(
    'Meeting Pulse: PUBLIC_SUPABASE_URL is missing or still a placeholder. There is deliberately no default.',
  );
}

let origin;
try {
  origin = new URL(supabaseUrl);
} catch {
  throw new Error('Meeting Pulse: PUBLIC_SUPABASE_URL is malformed.');
}
if (origin.protocol !== 'https:') {
  throw new Error('Meeting Pulse: PUBLIC_SUPABASE_URL must use https.');
}

const headers = `/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  Permissions-Policy: geolocation=(), microphone=(), camera=(), interest-cohort=()
  Cross-Origin-Opener-Policy: same-origin
  Content-Security-Policy: default-src 'none'; script-src 'self' https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; connect-src 'self' ${origin.origin}; style-src 'self'; img-src 'self' data:; font-src 'self'; base-uri 'none'; form-action 'none'
`;

mkdirSync(resolve(root, 'public'), { recursive: true });
writeFileSync(resolve(root, 'public/_headers'), headers, 'utf8');
