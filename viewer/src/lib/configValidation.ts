const PLACEHOLDER = /YOUR_|example\.com/i;

export class ConfigurationError extends Error {
  constructor(
    public readonly key: string,
    message: string,
  ) {
    super(
      `Meeting Pulse: ${key} ${message}. There is deliberately no default.`,
    );
    this.name = 'ConfigurationError';
  }
}

export function requireConfiguration(
  name: string,
  value: string | undefined,
): string {
  if (!value?.trim()) {
    throw new ConfigurationError(name, 'is missing');
  }
  if (PLACEHOLDER.test(value)) {
    throw new ConfigurationError(name, 'is still a placeholder');
  }
  return value.trim();
}

export function requiredUrl(name: string, value: string | undefined): string {
  const raw = requireConfiguration(name, value);
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new ConfigurationError(name, 'is malformed');
  }
  if (parsed.protocol !== 'https:') {
    throw new ConfigurationError(name, 'must use https');
  }
  return parsed.toString().replace(/\/$/, '');
}

export function requiredUrls(
  name: string,
  value: string | undefined,
): [string, ...string[]] {
  const raw = requireConfiguration(name, value);
  const entries = raw.split(',').map((entry) => entry.trim());
  if (entries.some((entry) => !entry)) {
    throw new ConfigurationError(name, 'contains an empty URL');
  }
  const unique = [...new Set(entries.map((entry) => requiredUrl(name, entry)))];
  const [first, ...rest] = unique;
  if (!first) {
    throw new ConfigurationError(name, 'must include at least one URL');
  }
  return [first, ...rest];
}

export const required = requireConfiguration;
