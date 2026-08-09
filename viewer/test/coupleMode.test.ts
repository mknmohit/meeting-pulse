import { describe, expect, it } from 'vitest';
import { COUPLE_MODE_BANKS } from '../src/lib/coupleCopy';
import {
  COUPLE_MODE_NAME_TOKEN,
  COUPLE_MODE_STORAGE_KEY,
  readCoupleMode,
  selectCouplePhrase,
  writeCoupleMode,
} from '../src/lib/coupleMode';

describe('Couple mode copy', () => {
  it('keeps three reviewed banks with 360 unique ASCII phrases each', () => {
    for (const bank of Object.values(COUPLE_MODE_BANKS)) {
      expect(bank).toHaveLength(360);
      expect(new Set(bank).size).toBe(bank.length);
      expect(
        bank.filter((phrase) => phrase.includes(COUPLE_MODE_NAME_TOKEN)),
      ).toHaveLength(30);
      expect(bank.every((phrase) => phrase.trim().length > 0)).toBe(true);
      expect(bank.every((phrase) => !/[—–]/u.test(phrase))).toBe(true);
      expect(bank.every((phrase) => /^[\x00-\x7F]*$/u.test(phrase))).toBe(true);
      expect(
        bank.every((phrase) => {
          const wordCount = phrase.trim().split(/\s+/u).length;
          return wordCount >= 12 && wordCount <= 20;
        }),
      ).toBe(true);
      expect(bank.every((phrase) => !/\bjaan(?:u)?\b/i.test(phrase))).toBe(
        true,
      );
    }
  });

  it('keeps unavailable copy general, honest, and personally warm', () => {
    const forbidden =
      /\b(offline|asleep|available|free to|in a meeting|okay to call|call me|ring me|laptop|app|heartbeat|permission|network|safe|away)\b/i;
    const affectionate =
      /\b(love|my love|darling|honey|baby|babe|sweetheart|sona|shona|pyaar|piya|sajan|saathi|sanam|mehboob|natkhat|shararti|nautanki|dramebaaz|bakbak|buddhu|pagal|ullu|gadha|shaitaan|our|shared|little check|small note|next (words|conversation|exchange))\b/i;

    expect(
      COUPLE_MODE_BANKS.generic.every(
        (phrase) => !forbidden.test(phrase) && affectionate.test(phrase),
      ),
    ).toBe(true);
  });

  it('does not select name-aware copy without an owner name', () => {
    for (const displayState of ['meeting', 'callOkay', 'generic'] as const) {
      const availablePhrases = COUPLE_MODE_BANKS[displayState].filter(
        (phrase) => !phrase.includes(COUPLE_MODE_NAME_TOKEN),
      );
      for (let index = 0; index < availablePhrases.length; index += 1) {
        const phrase = selectCouplePhrase(displayState, null, () => index);
        expect(phrase).not.toContain(COUPLE_MODE_NAME_TOKEN);
      }
    }
  });

  it('renders a name-aware phrase with plain text substitution', () => {
    for (const displayState of ['meeting', 'callOkay', 'generic'] as const) {
      const bank = COUPLE_MODE_BANKS[displayState];
      const nameIndex = bank.findIndex((phrase) =>
        phrase.includes(COUPLE_MODE_NAME_TOKEN),
      );
      expect(nameIndex).toBeGreaterThanOrEqual(0);
      const phrase = selectCouplePhrase(
        displayState,
        ' Alex ',
        () => nameIndex,
      );
      expect(phrase).toContain('Alex');
      expect(phrase).not.toContain(COUPLE_MODE_NAME_TOKEN);
    }
  });
});

describe('Couple mode preference', () => {
  it('defaults off and persists the viewer-local choice', () => {
    const values = new Map<string, string>();
    const storage = {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => {
        values.set(key, value);
      },
    };

    expect(readCoupleMode(storage)).toBe(false);
    expect(writeCoupleMode(true, storage)).toBe(true);
    expect(values.get(COUPLE_MODE_STORAGE_KEY)).toBe('true');
    expect(readCoupleMode(storage)).toBe(true);
    expect(writeCoupleMode(false, storage)).toBe(true);
    expect(readCoupleMode(storage)).toBe(false);
  });

  it('fails closed when browser storage throws', () => {
    const storage = {
      getItem: () => {
        throw new Error('blocked');
      },
      setItem: () => {
        throw new Error('blocked');
      },
    };

    expect(readCoupleMode(storage)).toBe(false);
    expect(writeCoupleMode(true, storage)).toBe(false);
  });
});
