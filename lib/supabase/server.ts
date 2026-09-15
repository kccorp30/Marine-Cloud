import 'server-only';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

// A propósito usa la ANON key, no la service role — Marine Cloud
// depende de RLS para la seguridad de cada usuario real (a diferencia
// del sitio web, que solo escribe leads server-side con service role
// porque no tiene usuarios logueados). Aquí, cada request actúa CON
// la identidad del usuario autenticado, vía su sesión/cookie — así
// las políticas RLS que acabamos de probar aplican de verdad.
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet: { name: string; value: string; options?: Record<string, unknown> }[]) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
        } catch {
          // Se llama desde un Server Component sin poder escribir cookies —
          // el middleware ya se encarga de refrescar la sesión en ese caso.
        }
      },
    },
  });
}
