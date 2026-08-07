const PLACEHOLDER = /YOUR_|example\.com/i;

export class ConfigurationError extends Error {
  constructor(
    public readonly key: string,
    message: string,
  ) {
    super(`Meeting Pulse: ${key} ${message}. There is deliberately no default.`);
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

export const required = requireConfiguration;
