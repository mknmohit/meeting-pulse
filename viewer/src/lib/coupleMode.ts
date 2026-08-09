import { COUPLE_MODE_BANKS, type CoupleDisplayState } from './coupleCopy';

export const COUPLE_MODE_STORAGE_KEY = 'meetingpulse.viewer.couple-mode.v1';
export const COUPLE_MODE_NAME_TOKEN = '{{name}}';

type StorageLike = Pick<Storage, 'getItem' | 'setItem'>;
export type RandomIndex = (length: number) => number;

export function readCoupleMode(
  storage: StorageLike | undefined = browserStorage(),
): boolean {
  if (!storage) {
    return false;
  }
  try {
    return storage.getItem(COUPLE_MODE_STORAGE_KEY) === 'true';
  } catch {
    return false;
  }
}

export function writeCoupleMode(
  enabled: boolean,
  storage: StorageLike | undefined = browserStorage(),
): boolean {
  if (!storage) {
    return false;
  }
  try {
    storage.setItem(COUPLE_MODE_STORAGE_KEY, String(enabled));
    return true;
  } catch {
    return false;
  }
}

export function selectCouplePhrase(
  displayState: CoupleDisplayState,
  ownerName: string | null | undefined,
  randomIndex: RandomIndex = randomIndexFor,
): string {
  const trimmedName = ownerName?.trim() ?? '';
  const bank = COUPLE_MODE_BANKS[displayState];
  const candidates = trimmedName
    ? bank
    : bank.filter((phrase) => !phrase.includes(COUPLE_MODE_NAME_TOKEN));
  if (candidates.length === 0) {
    throw new Error(`Meeting Pulse: no Couple mode copy for ${displayState}.`);
  }
  const index = randomIndex(candidates.length);
  const phrase = candidates[index];
  if (
    phrase === undefined ||
    !Number.isInteger(index) ||
    index < 0 ||
    index >= candidates.length
  ) {
    throw new Error(
      'Meeting Pulse: Couple mode copy selector returned an invalid index.',
    );
  }
  return trimmedName
    ? phrase.replaceAll(COUPLE_MODE_NAME_TOKEN, trimmedName)
    : phrase;
}

function browserStorage(): StorageLike | undefined {
  if (typeof window === 'undefined') {
    return undefined;
  }
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

function randomIndexFor(length: number): number {
  if (length <= 0) {
    throw new Error('Meeting Pulse: cannot choose from an empty copy bank.');
  }
  const values = new Uint32Array(1);
  if (globalThis.crypto?.getRandomValues) {
    globalThis.crypto.getRandomValues(values);
    const value = values[0];
    if (value === undefined) {
      throw new Error('Meeting Pulse: random source returned no value.');
    }
    return value % length;
  }
  return Math.floor(Math.random() * length);
}
