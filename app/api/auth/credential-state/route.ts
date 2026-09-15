import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createClient as createServiceClient } from '@/lib/supabase/service';

/**
 * Called only after Supabase has successfully accepted a password (either a
 * password sign-in or auth.updateUser({ password })). No password is sent to
 * this endpoint. The cookie-backed session identifies the user, and the
 * service client only records durable credential-state for that exact user.
 */
export async function POST() {
  const sessionClient = await createClient();
  const {
    data: { user },
  } = await sessionClient.auth.getUser();

  if (!user) return NextResponse.json({ error: 'Authentication required.' }, { status: 401 });

  const service = createServiceClient();
  const now = new Date().toISOString();
  // Upsert also repairs a rare legacy/stale Auth user that exists without
  // the profile row normally created by the auth.users trigger.
  const { error } = await service
    .from('profiles')
    .upsert(
      { id: user.id, email: user.email?.trim().toLowerCase() ?? null, password_set_at: now },
      { onConflict: 'id' },
    )
    .select('id')
    .single();

  if (error) return NextResponse.json({ error: 'Could not finalize account credentials.' }, { status: 500 });

  await service.auth.admin.updateUserById(user.id, {
    user_metadata: { ...(user.user_metadata ?? {}), password_setup_complete: true },
  });

  return NextResponse.json({ ok: true });
}
