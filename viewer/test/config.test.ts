import { describe, expect, it } from 'vitest';
import {
  ConfigurationError,
  requireConfiguration,
  requiredUrl,
  requiredUrls,
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

  it('rejects missing origin lists', () => {
    expect(() => requiredUrls('PUBLIC_STATUS_ORIGINS', undefined)).toThrow(
      'PUBLIC_STATUS_ORIGINS is missing',
    );
  });

  it('rejects placeholders', () => {
    expect(() =>
      requireConfiguration(
        'PUBLIC_STATUS_ORIGINS',
        'https://status.example.com',
      ),
    ).toThrow('PUBLIC_STATUS_ORIGINS is still a placeholder');
  });

  it('accepts a concrete value', () => {
    expect(
      requireConfiguration('PUBLIC_STATUS_ORIGINS', 'https://status.test'),
    ).toBe('https://status.test');
  });

  it('validates and normalizes multiple HTTPS origins', () => {
    expect(
      requiredUrls(
        'PUBLIC_STATUS_ORIGINS',
        ' https://status.test/, https://status.example.net ',
      ),
    ).toEqual(['https://status.test', 'https://status.example.net']);
  });

  it('removes duplicate normalized origins while preserving order', () => {
    expect(
      requiredUrls(
        'PUBLIC_STATUS_ORIGINS',
        'https://status.test,https://status.test/',
      ),
    ).toEqual(['https://status.test']);
  });

  it('rejects empty origin entries', () => {
    expect(() =>
      requiredUrls(
        'PUBLIC_STATUS_ORIGINS',
        'https://status.test,,https://status.example.net',
      ),
    ).toThrow('PUBLIC_STATUS_ORIGINS contains an empty URL');
  });

  it('rejects malformed and non-HTTPS origins', () => {
    expect(() => requiredUrl('PUBLIC_STATUS_ORIGINS', 'not-a-url')).toThrow(
      'PUBLIC_STATUS_ORIGINS is malformed',
    );
    expect(() =>
      requiredUrl('PUBLIC_STATUS_ORIGINS', 'http://status.test'),
    ).toThrow('PUBLIC_STATUS_ORIGINS must use https');
  });
});
