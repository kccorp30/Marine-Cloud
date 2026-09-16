import 'server-only';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';

export type NotificationSeverity = 'info' | 'action_required' | 'urgent' | 'critical';

export interface NotificationDTO {
  id: string;
  eventType: string;
  severity: NotificationSeverity;
  title: string;
  body: string | null;
  relatedEntityType: string | null;
  relatedEntityId: string | null;
  readAt: string | null;
  acknowledgementRequired: boolean;
  acknowledgedAt: string | null;
  createdAt: string;
}

export { getNotificationDeepLink } from './deep-link';
import { getNotificationDeepLink } from './deep-link';

function mapRow(n: any): NotificationDTO {
  return {
    id: n.id,
    eventType: n.event_type,
    severity: n.severity,
    title: n.title,
    body: n.body,
    relatedEntityType: n.related_entity_type,
    relatedEntityId: n.related_entity_id,
    readAt: n.read_at,
    acknowledgementRequired: n.acknowledgement_required,
    acknowledgedAt: n.acknowledged_at,
    createdAt: n.created_at,
  };
}

/**
 * Defense in depth: even though RLS already limits notifications, every read is explicitly
 * recipient-scoped. That makes it impossible for a broad UI query to mix company/customer/
 * technician inboxes if a policy changes later.
 */
export async function getNotifications(filter?: 'unread' | 'action'): Promise<NotificationDTO[]> {
  const session = await getSessionContext();
  const supabase = await createClient();
  let query = supabase
    .from('notifications')
    .select('id, event_type, severity, title, body, related_entity_type, related_entity_id, read_at, acknowledgement_required, acknowledged_at, created_at')
    .eq('recipient_user_id', session.userId)
    .order('created_at', { ascending: false })
    .limit(50);

  if (filter === 'unread') query = query.is('read_at', null);
  if (filter === 'action') query = query.in('severity', ['action_required', 'urgent', 'critical']);

  const { data } = await query;
  return (data ?? []).map(mapRow);
}

export async function getUnreadNotificationCount(): Promise<number> {
  const session = await getSessionContext();
  const supabase = await createClient();
  const { count } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('recipient_user_id', session.userId)
    .is('read_at', null);
  return count ?? 0;
}
