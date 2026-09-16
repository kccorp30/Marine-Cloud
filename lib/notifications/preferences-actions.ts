'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { logger } from '@/lib/logger';

export async function updateNotificationPreferencesAction(input: {
  soundEnabled: boolean;
  motionEnabled: boolean;
}) {
  const session = await getSessionContext();
  const supabase = await createClient();
  const { error } = await supabase.from('notification_preferences').upsert({
    profile_id: session.userId,
    sound_enabled: input.soundEnabled,
    motion_enabled: input.motionEnabled,
    updated_at: new Date().toISOString(),
  });
  if (error) {
    logger.warn('updateNotificationPreferencesAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/notifications');
  return { ok: true };
}
