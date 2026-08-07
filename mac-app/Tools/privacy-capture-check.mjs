import { readFileSync } from 'node:fs';

const inputPath = process.argv[2];
if (!inputPath) {
  throw new Error('Usage: node mac-app/Tools/privacy-capture-check.mjs <requests.json>');
}

const requests = JSON.parse(readFileSync(inputPath, 'utf8'));
if (!Array.isArray(requests)) {
  throw new Error('The capture must be a JSON array of request records.');
}

const allowedKeys = new Set([
  'state',
  'call_okay',
  'override_mode',
  'override_expires_at',
  'screen_sharing',
  'last_seen_at',
  'updated_at',
  'display_name',
  'p_state',
  'p_call_okay',
  'p_instance_nonce',
  'p_override_mode',
  'p_override_expires_at',
  'p_screen_sharing',
  'p_display_name',
  'p_recovery_hash',
  'p_code_hash',
]);
const forbidden = [
  /meet\.google\.com/iu,
  /https?:\/\//iu,
  /@/u,
  /participant/iu,
  /window title/iu,
  /screen content/iu,
  /microphone audio/iu,
];

for (const [index, request] of requests.entries()) {
  const body = request?.body;
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new Error(`Request ${index} has no JSON object body.`);
  }
  for (const key of Object.keys(body)) {
    if (!allowedKeys.has(key)) {
      throw new Error(`Request ${index} contains forbidden field ${key}.`);
    }
  }
  const serialized = JSON.stringify(body);
  for (const pattern of forbidden) {
    if (pattern.test(serialized)) {
      throw new Error(`Request ${index} contains forbidden meeting data.`);
    }
  }
}

console.log(`Privacy capture passed for ${requests.length} requests.`);
