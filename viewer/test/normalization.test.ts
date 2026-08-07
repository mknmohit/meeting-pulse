import { describe, expect, it } from 'vitest';
import { isPairingCode, normalizePairingCode } from '../src/lib/pairingCode';

describe('pairing code normalization', () => {
  it('maps confusables before stripping', () => {
    expect(normalizePairingCode('i-l-o-u 012')).toBe('1101012');
    expect(normalizePairingCode('abcde-fghjk')).toBe('ABCDEFGHJK');
  });

  it('accepts exactly ten canonical characters', () => {
    expect(isPairingCode(['12345', '67890'].join('-'))).toBe(true);
    expect(isPairingCode('1234')).toBe(false);
  });
});
