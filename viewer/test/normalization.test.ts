import { describe, expect, it } from 'vitest';
import {
  isPairingCode,
  normalizePairingCode,
  pairingCodeFromHash,
} from '../src/lib/pairingCode';

describe('pairing code normalization', () => {
  it('maps confusables before stripping', () => {
    expect(normalizePairingCode('i-l-o-u 012')).toBe('1101012');
    expect(normalizePairingCode('abcde-fghjk')).toBe('ABCDEFGHJK');
  });

  it('accepts exactly ten canonical characters', () => {
    expect(isPairingCode('1234567890')).toBe(true);
    expect(isPairingCode(['12345', '67890'].join('-'))).toBe(true);
    expect(isPairingCode('1234')).toBe(false);
  });

  it('reads a valid code from a URL fragment', () => {
    expect(pairingCodeFromHash('#code=abcde-fghjk')).toBe('ABCDEFGHJK');
    expect(pairingCodeFromHash('#other=value')).toBeNull();
    expect(pairingCodeFromHash('#code=1234')).toBeNull();
  });
});
