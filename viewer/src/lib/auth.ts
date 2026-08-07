import { supabase } from './supabase';

export async function ensureSession(captchaToken?: string): Promise<void> {
  const { data } = await supabase.auth.getSession();
  if (data.session) {
    return;
  }
  const result = captchaToken
    ? await supabase.auth.signInAnonymously({ options: { captchaToken } })
    : await supabase.auth.signInAnonymously();
  const { error } = result;
  if (error) {
    throw error;
  }
}

export async function clearSession(): Promise<void> {
  const { error } = await supabase.auth.signOut({ scope: 'local' });
  if (error) {
    throw error;
  }
}
