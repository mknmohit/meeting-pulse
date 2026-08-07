import type { State } from './freshness';
import { supabase } from './supabase';

export type PairedStatus = {
  paired: boolean;
  displayName: string | null;
  state: State;
  callOkay: boolean;
  lastSeenAt: string;
  serverNow: string;
  schemaVersion: number;
};

type RawPairedStatus = {
  paired?: boolean;
  display_name?: string | null;
  state?: string;
  call_okay?: boolean;
  last_seen_at?: string;
  server_now?: string;
  schema_version?: number;
};

export async function fetchPairedStatus(): Promise<PairedStatus> {
  const { data, error } = await supabase.rpc('get_paired_status');
  if (error) {
    throw error;
  }
  return normalizeStatus(data as RawPairedStatus);
}

function normalizeStatus(raw: RawPairedStatus): PairedStatus {
  if (!raw.paired) {
    return {
      paired: false,
      displayName: null,
      state: 'unavailable',
      callOkay: false,
      lastSeenAt: '',
      serverNow: '',
      schemaVersion: 1,
    };
  }
  if (
    (raw.state !== 'available' &&
      raw.state !== 'busy' &&
      raw.state !== 'unavailable') ||
    typeof raw.call_okay !== 'boolean' ||
    typeof raw.last_seen_at !== 'string' ||
    typeof raw.server_now !== 'string' ||
    typeof raw.schema_version !== 'number'
  ) {
    throw new Error('Meeting Pulse: status response is malformed.');
  }
  return {
    paired: true,
    displayName: raw.display_name?.trim() || null,
    state: raw.state,
    callOkay: raw.call_okay,
    lastSeenAt: raw.last_seen_at,
    serverNow: raw.server_now,
    schemaVersion: raw.schema_version,
  };
}
