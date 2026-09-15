import 'server-only';
import { createClient as createSupabaseClient } from '@supabase/supabase-js';

// =========================================================
// lib/supabase/service.ts — Marine Cloud Phase 8 hardening
// =========================================================
// Cliente con la SERVICE ROLE KEY — bypasea RLS a nivel de Postgres,
// pero las funciones RPC sensibles (process_email_webhook_event, etc.)
// igual exigen is_platform_trusted_actor() explícitamente, que
// reconoce el JWT de service_role. Nunca usar este cliente en una
// ruta que reciba input directo de un usuario sin autorización propia
// — solo para rutas de plataforma de confianza como este webhook.
// =========================================================

export function createClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error('Service role client requires NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.');
  }

  return createSupabaseClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
