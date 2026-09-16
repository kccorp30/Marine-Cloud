import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { createClient as createServiceClient } from '@/lib/supabase/service';
import { logger } from '@/lib/logger';

/**
 * Best-effort durable credential marker.
 *
 * Supabase Auth accepting a password is the authority. This route must never
 * lock a valid user out just because a new profile column has not yet been
 * migrated or a secondary persistence write fails.
 */
export async function POST() {
  const sessionClient = await createClient();
  const {
    data: { user },
  } = await sessionClient.auth.getUser();

  if (!user) return NextResponse.json({ error: 'Authentication required.' }, { status: 401 });

  const service = createServiceClient();
  const now = new Date().toISOString();

  // Auth metadata is the migration-independent source used by route guards.
  const authUpdate = await service.auth.admin.updateUserById(user.id, {
    user_metadata: {
      ...(user.user_metadata ?? {}),
      password_setup_required: false,
      password_setup_complete: true,
    },
  });

  if (authUpdate.error) {
    logger.warn('Could not persist credential state in auth metadata', {
      userId: user.id,
      message: authUpdate.error.message,
    });
    return NextResponse.json({ error: 'Could not finalize account credentials.' }, { status: 500 });
  }

  // Keep the profile marker for reporting/backwards compatibility, but do not
  // make successful authentication depend on this secondary write.
  const { error: profileError } = await service
    .from('profiles')
    .upsert(
      { id: user.id, email: user.email?.trim().toLowerCase() ?? null, password_set_at: now },
      { onConflict: 'id' },
    );

  if (profileError) {
    logger.warn('Credential profile marker could not be persisted', {
      userId: user.id,
      message: profileError.message,
    });
  }

  return NextResponse.json({ ok: true, profileMarkerPersisted: !profileError });
}
