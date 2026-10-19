export const COUPLE_MODE_STORAGE_KEY = 'meetingpulse.viewer.couple-mode.v1';
export const COUPLE_MODE_NAME_TOKEN = '{{name}}';

type StorageLike = Pick<Storage, 'getItem' | 'setItem'>;

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
