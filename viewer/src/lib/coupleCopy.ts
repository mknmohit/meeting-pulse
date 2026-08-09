import type { DisplayState } from './freshness';
import meeting from './coupleCopyData/meeting.json';
import callOkay from './coupleCopyData/call-okay.json';
import unavailable from './coupleCopyData/unavailable.json';

export type CoupleDisplayState = Exclude<DisplayState, 'unpaired'>;

export const COUPLE_MODE_BANKS = {
  meeting,
  callOkay,
  generic: unavailable,
} as const satisfies Record<CoupleDisplayState, readonly string[]>;
