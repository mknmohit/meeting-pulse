export type State = 'available' | 'busy' | 'unavailable';
export type DisplayState = State | 'unpaired';

export const SUPPORTED_SCHEMA_VERSION = 1;
export const STALE_AFTER_SECONDS = 180;

export type PairedStatusLike = {
  paired: boolean;
  state: State;
  schemaVersion: number;
  displayName: string | null;
  callOkay: boolean;
};

export type Reading = {
  status: PairedStatusLike & {
    serverNow: string;
    lastSeenAt: string;
  };
  serverAgeAtFetchSec: number;
  fetchedAtMonotonic: number;
};

export function readingFromStatus(
  status: Reading['status'],
  fetchedAtMonotonic: number,
): Reading {
  const serverAgeAtFetchSec =
    (Date.parse(status.serverNow) - Date.parse(status.lastSeenAt)) / 1000;
  return { status, serverAgeAtFetchSec, fetchedAtMonotonic };
}

export function currentAgeSeconds(
  reading: Reading,
  nowMonotonic: number,
): number {
  return (
    reading.serverAgeAtFetchSec +
    (nowMonotonic - reading.fetchedAtMonotonic) / 1000
  );
}

export function effectiveDisplayState(
  reading: Reading | null,
  nowMonotonic: number,
): DisplayState {
  if (!reading) {
    return 'unavailable';
  }
  if (!reading.status.paired) {
    return 'unpaired';
  }
  if (reading.status.schemaVersion > SUPPORTED_SCHEMA_VERSION) {
    return 'unavailable';
  }
  const age = currentAgeSeconds(reading, nowMonotonic);
  if (!Number.isFinite(age) || age < 0 || age > STALE_AFTER_SECONDS) {
    return 'unavailable';
  }
  return reading.status.state;
}

export function checkedLabel(elapsedSeconds: number): string {
  if (!Number.isFinite(elapsedSeconds) || elapsedSeconds < 0) {
    return 'Checked a while ago';
  }
  if (elapsedSeconds < 5) {
    return 'Checked just now';
  }
  if (elapsedSeconds < 60) {
    return `Checked ${Math.floor(elapsedSeconds)} seconds ago`;
  }
  const minutes = Math.floor(elapsedSeconds / 60);
  if (minutes === 1) {
    return 'Checked 1 minute ago';
  }
  if (minutes < 10) {
    return `Checked ${minutes} minutes ago`;
  }
  return 'Checked a while ago';
}
