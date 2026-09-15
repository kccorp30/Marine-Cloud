'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function markNotificationReadAction(notificationId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('mark_notification_read', { p_notification_id: notificationId });
  if (error) {
    logger.warn('markNotificationReadAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/notifications');
  return {};
}

export async function markAllNotificationsReadAction() {
  const supabase = await createClient();
  const { error } = await supabase.rpc('mark_all_notifications_read');
  if (error) {
    logger.warn('markAllNotificationsReadAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/notifications');
  return {};
}

export async function acknowledgeNotificationAction(notificationId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('acknowledge_notification', { p_notification_id: notificationId });
  if (error) {
    logger.warn('acknowledgeNotificationAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/notifications');
  return {};
}

export async function loadNotificationInbox(){
 const {getNotifications,getNotificationDeepLink}=await import('./data');
 const rows=await getNotifications();
 return rows.slice(0,12).map(notification=>({notification,deepLink:getNotificationDeepLink(notification)}));
}
