import { describe, expect, it } from 'vitest';
import {
  ConfigurationError,
  requireConfiguration,
} from '../src/lib/configValidation';

describe('configuration validation', () => {
  it('rejects missing values', () => {
    expect(() =>
      requireConfiguration('PUBLIC_SUPABASE_URL', undefined),
    ).toThrow('PUBLIC_SUPABASE_URL is missing');
  });

  it('rejects empty values', () => {
    expect(() => requireConfiguration('PUBLIC_SUPABASE_URL', '  ')).toThrow(
      ConfigurationError,
    );
  });

  it('rejects placeholders', () => {
    expect(() =>
      requireConfiguration(
        'PUBLIC_STATUS_ORIGIN',
        'https://status.example.com',
      ),
    ).toThrow('PUBLIC_STATUS_ORIGIN is still a placeholder');
  });

  it('accepts a concrete value', () => {
    expect(
      requireConfiguration('PUBLIC_STATUS_ORIGIN', 'https://status.test'),
    ).toBe('https://status.test');
  });
});
