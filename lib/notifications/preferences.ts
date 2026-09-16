import 'server-only';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';

export interface NotificationPreferences {
  soundEnabled: boolean;
  motionEnabled: boolean;
}

export async function getNotificationPreferences(): Promise<NotificationPreferences> {
  const session = await getSessionContext();
  const supabase = await createClient();
  const { data } = await supabase
    .from('notification_preferences')
    .select('sound_enabled,motion_enabled')
    .eq('profile_id', session.userId)
    .maybeSingle();

  return {
    soundEnabled: data?.sound_enabled ?? true,
    motionEnabled: data?.motion_enabled ?? true,
  };
}
