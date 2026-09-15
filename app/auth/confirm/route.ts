import type { EmailOtpType } from '@supabase/supabase-js';
import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { safeInternalPath } from '@/lib/auth/site-url';

/**
 * Server-side Supabase email-link confirmation.
 * Exchanges token_hash for a cookie-backed session before continuing.
 * This avoids implicit-flow fragments that a Server Component cannot read.
 */
export async function GET(request: NextRequest) {
  const tokenHash = request.nextUrl.searchParams.get('token_hash');
  const type = request.nextUrl.searchParams.get('type') as EmailOtpType | null;
  const next = safeInternalPath(request.nextUrl.searchParams.get('next'), '/');

  if (!tokenHash || !type) {
    return NextResponse.redirect(new URL('/login?auth_error=missing_token', request.url));
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type });

  if (error) {
    const url = new URL('/login', request.url);
    url.searchParams.set('auth_error', 'invalid_or_expired_link');
    return NextResponse.redirect(url);
  }

  return NextResponse.redirect(new URL(next, request.url));
}
