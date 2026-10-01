import 'server-only';

// Avisa al sitio público que el contenido cambió, para que vuelva a
// generar sus páginas al instante en vez de esperar su refresco
// automático (cada 5 minutos, ver kccorp-web).
//
// Nunca rompe un guardado: si el sitio no está configurado o no
// responde, el cambio YA quedó en la base y el sitio lo tomará en su
// siguiente refresco. Solo se registra en el log del servidor.
//
// El secreto viaja en un header, solo de servidor a servidor. No lleva
// prefijo NEXT_PUBLIC_: nunca llega al navegador.
export async function notifyWebsiteContentChanged(paths: string[] = ['/']): Promise<'sent' | 'skipped' | 'failed'> {
  const baseUrl = process.env.WEBSITE_URL?.trim().replace(/\/+$/, '');
  const secret = process.env.WEBSITE_REVALIDATE_SECRET?.trim();
  if (!baseUrl || !secret) return 'skipped';

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 4000);
  try {
    const res = await fetch(`${baseUrl}/api/revalidate`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-revalidate-secret': secret },
      body: JSON.stringify({ paths }),
      signal: controller.signal,
      cache: 'no-store',
    });
    if (!res.ok) {
      console.warn('[website] revalidate rejected', res.status);
      return 'failed';
    }
    return 'sent';
  } catch (err) {
    console.warn('[website] revalidate unreachable', err instanceof Error ? err.message : err);
    return 'failed';
  } finally {
    clearTimeout(timer);
  }
}
