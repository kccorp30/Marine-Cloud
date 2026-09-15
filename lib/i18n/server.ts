import 'server-only';
import { cookies } from 'next/headers';
import { createClient } from '@/lib/supabase/server';
import type { Locale } from './dictionary';
import { DEFAULT_LOCALE } from './dictionary';

const COOKIE_NAME = 'kcc_locale';

/**
 * Resuelve el idioma efectivo: cookie primero (funciona pre-auth, ej.
 * en /login), perfil del usuario si está logueado y no hay cookie
 * explícita todavía. Fallback siempre inglés — nunca español
 * hardcodeado, en particular para el customer portal.
 */
export async function getLocale(): Promise<Locale> {
  const cookieStore = await cookies();
  const cookieValue = cookieStore.get(COOKIE_NAME)?.value;
  if (cookieValue === 'en' || cookieValue === 'es') return cookieValue;

  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (user) {
      const { data } = await supabase.from('profiles').select('preferred_language').eq('id', user.id).single();
      if (data?.preferred_language === 'en' || data?.preferred_language === 'es') return data.preferred_language;
    }
  } catch {
    // Sin sesión o sin acceso a profiles — cae al default, nunca rompe la página.
  }

  return DEFAULT_LOCALE;
}

export const LOCALE_COOKIE_NAME = COOKIE_NAME;
