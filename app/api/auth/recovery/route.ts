import { NextRequest, NextResponse } from 'next/server';
import { createClient as createServiceClient } from '@/lib/supabase/service';
import { getEmailProvider } from '@/lib/email/resend';
import { renderDirectRecoveryEmail } from '@/lib/email/auth-templates';
import { getSiteUrl } from '@/lib/auth/site-url';

const FROM = process.env.AUTH_FROM_EMAIL || process.env.RESEND_FROM_EMAIL || process.env.EMAIL_FROM_ADDRESS || 'KCC Marine Cloud <notifications@kccorpglobal.com>';

export async function POST(request: NextRequest) {
  let body: { email?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid request.' }, { status: 400 });
  }

  const email = body.email?.trim().toLowerCase();
  if (!email || !email.includes('@')) {
    return NextResponse.json({ error: 'Enter a valid email address.' }, { status: 400 });
  }

  const service = createServiceClient();
  const { data: profile } = await service.from('profiles').select('id').eq('email', email).maybeSingle();

  // Enumeration-safe: unknown emails get the same success response.
  if (!profile) return NextResponse.json({ ok: true });

  const { data, error } = await service.auth.admin.generateLink({
    type: 'recovery',
    email,
    options: { redirectTo: `${getSiteUrl()}/reset-password` },
  });

  if (error || !data?.properties?.hashed_token) {
    return NextResponse.json({ error: 'Could not create a secure recovery link.' }, { status: 500 });
  }

  const confirmUrl = `${getSiteUrl()}/auth/confirm?token_hash=${encodeURIComponent(data.properties.hashed_token)}&type=${encodeURIComponent(
    data.properties.verification_type,
  )}&next=${encodeURIComponent('/reset-password')}`;

  let provider;
  try {
    provider = getEmailProvider();
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Email delivery is not configured.' },
      { status: 503 },
    );
  }

  const result = await provider.sendEmail({
    to: email,
    from: FROM,
    subject: 'Reset your KCC Marine Cloud password',
    text: `Use this secure link to reset your KCC Marine Cloud password:\n\n${confirmUrl}\n\nIf you did not request this, you can ignore this email.`,
    html: renderDirectRecoveryEmail(confirmUrl),
  });

  if (!result.success) {
    return NextResponse.json({ error: result.error || 'Email delivery failed.' }, { status: 502 });
  }

  return NextResponse.json({ ok: true });
}
