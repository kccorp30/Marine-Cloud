import 'server-only';

/**
 * Canonical application URL used for security-sensitive auth links.
 * Production must never silently fall back to localhost.
 */
export function getSiteUrl(): string {
  let url = process.env.NEXT_PUBLIC_SITE_URL || process.env.VERCEL_PROJECT_PRODUCTION_URL || process.env.VERCEL_URL;

  if (!url) {
    if (process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test') {
      return 'http://localhost:3000';
    }
    throw new Error('NEXT_PUBLIC_SITE_URL is required in production for authentication links.');
  }

  if (!/^https?:\/\//i.test(url)) url = `https://${url}`;
  return url.replace(/\/+$/, '');
}

export function safeInternalPath(value: string | null | undefined, fallback = '/dashboard'): string {
  if (!value || !value.startsWith('/') || value.startsWith('//')) return fallback;
  return value;
}
