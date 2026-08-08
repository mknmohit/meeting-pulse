import { describe, expect, it } from 'vitest';
import {
  currentAgeSeconds,
  effectiveDisplayState,
  readingFromStatus,
} from '../src/lib/freshness';

function reading(
  overrides: Partial<Parameters<typeof readingFromStatus>[0]> = {},
) {
  return readingFromStatus(
    {
      paired: true,
      state: 'available',
      callOkay: false,
      displayName: null,
      schemaVersion: 1,
      serverNow: '2026-08-07T10:00:00.000Z',
      lastSeenAt: '2026-08-07T09:59:00.000Z',
      ...overrides,
    },
    1_000,
  );
}

describe('server-time freshness', () => {
  it('shows the meeting state only for a fresh busy reading', () => {
    expect(effectiveDisplayState(reading({ state: 'busy' }), 1_000)).toBe(
      'meeting',
    );
    expect(effectiveDisplayState(reading(), 1_000)).toBe('generic');
    expect(
      effectiveDisplayState(reading({ state: 'unavailable' }), 1_000),
    ).toBe('generic');
  });

  it('shows the call-okay state when busy and call_okay is true', () => {
    expect(
      effectiveDisplayState(
        reading({ state: 'busy', callOkay: true }),
        1_000,
      ),
    ).toBe('callOkay');
    expect(
      effectiveDisplayState(
        reading({ state: 'busy', callOkay: false }),
        1_000,
      ),
    ).toBe('meeting');
  });

  it('ignores the browser wall clock', () => {
    const value = reading();
    expect(effectiveDisplayState(value, 1_000)).toBe('generic');
    expect(effectiveDisplayState(value, 121_001)).toBe('generic');
  });

  it('ages while later fetches fail', () => {
    const value = reading();
    expect(currentAgeSeconds(value, 2_000)).toBe(61);
    expect(effectiveDisplayState(value, 121_000)).toBe('generic');
    expect(effectiveDisplayState(value, 122_000)).toBe('generic');
  });

  it('fails closed on malformed or negative age', () => {
    expect(
      effectiveDisplayState(
        reading({
          serverNow: 'not-a-date',
        }),
        1_000,
      ),
    ).toBe('generic');
    expect(
      effectiveDisplayState(
        reading({
          lastSeenAt: '2026-08-07T10:01:00.000Z',
        }),
        1_000,
      ),
    ).toBe('generic');
  });

  it('fails closed on a newer schema and stale boundary', () => {
    expect(effectiveDisplayState(reading({ schemaVersion: 2 }), 1_000)).toBe(
      'generic',
    );
    expect(effectiveDisplayState(reading(), 121_000)).toBe('generic');
    expect(effectiveDisplayState(reading(), 122_000)).toBe('generic');
  });
});
