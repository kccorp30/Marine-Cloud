import 'server-only';
import { createClient } from '@/lib/supabase/server';

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

const SUPPORTED_DEEP_LINK_TYPES: Record<string, (id: string) => string> = {
  work_order: (id) => `/work-orders/${id}`,
  vessel: (id) => `/vessels/${id}`,
  invoice: (id) => `/invoices/${id}`,
  estimate: (id) => `/estimates/${id}`,
  kcc_assistance_request: () => `/kcc-assistance`,
};

/** Nunca inventa un link — si el tipo de entidad no es soportado, devuelve null. */
export function getNotificationDeepLink(n: Pick<NotificationDTO, 'relatedEntityType' | 'relatedEntityId'>): string | null {
  if (!n.relatedEntityType || !n.relatedEntityId) return null;
  const builder = SUPPORTED_DEEP_LINK_TYPES[n.relatedEntityType];
  return builder ? builder(n.relatedEntityId) : null;
}

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

export async function getNotifications(filter?: 'unread' | 'action'): Promise<NotificationDTO[]> {
  const supabase = await createClient();
  let query = supabase
    .from('notifications')
    .select('id, event_type, severity, title, body, related_entity_type, related_entity_id, read_at, acknowledgement_required, acknowledged_at, created_at')
    .order('created_at', { ascending: false })
    .limit(50);

  if (filter === 'unread') query = query.is('read_at', null);
  if (filter === 'action') query = query.in('severity', ['action_required', 'urgent', 'critical']);

  const { data } = await query;
  return (data ?? []).map(mapRow);
}

export async function getUnreadNotificationCount(): Promise<number> {
  const supabase = await createClient();
  const { count } = await supabase.from('notifications').select('id', { count: 'exact', head: true }).is('read_at', null);
  return count ?? 0;
}
