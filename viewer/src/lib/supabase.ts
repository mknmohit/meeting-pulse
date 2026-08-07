import { createClient } from '@supabase/supabase-js';
import { CONFIG } from '../config';

export const supabase = createClient(
  CONFIG.supabaseUrl,
  CONFIG.supabaseAnonKey,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
    },
  },
);
