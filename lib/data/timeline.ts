import 'server-only';
import { createClient } from '@/lib/supabase/server';

// Mapeo event_type → título humano. Deliberadamente NO decorativo —
// cada entrada del timeline viene de un domain_event real, nunca de
// un estado calculado en la UI. Si un tipo de evento no está en este
// mapa, se muestra tal cual (fallback seguro, nunca oculta un evento
// real por falta de traducción).
const EVENT_TITLES: Record<string, string> = {
  WORK_ORDER_CREATED: 'Work order created',
  WORK_ORDER_STATUS_CHANGED: 'Status changed',
  TECHNICIAN_ASSIGNED: 'Technician assigned',
  TECHNICIAN_UNASSIGNED: 'Technician unassigned',
  TECHNICIAN_EN_ROUTE: 'Technician en route',
  TECHNICIAN_CHECKED_IN: 'Technician checked in',
  TECHNICIAN_CHECKED_OUT: 'Technician checked out',
  TECHNICIAN_WORK_STARTED: 'Work started',
  APPOINTMENT_CREATED: 'Visit scheduled',
  APPOINTMENT_RESCHEDULED: 'Visit rescheduled',
  TIME_ENTRY_STARTED: 'Timer started',
  TIME_ENTRY_STOPPED: 'Timer stopped',
  WORK_NOTE_ADDED: 'Note added',
  MEDIA_ADDED: 'Photo added',
  MEASUREMENT_RECORDED: 'Measurement recorded',
  CHECKLIST_UPDATED: 'Checklist updated',
  PROGRESS_UPDATE_ADDED: 'Progress update',
};

export interface TimelineEntry {
  id: string;
  eventType: string;
  title: string;
  occurredAt: string;
  actorName: string | null;
  detail: string | null;
}

// La query no filtra por rol — RLS (migración 040) ya devuelve
// exactamente lo que ese usuario puede ver. Esta función solo
// proyecta lo que llegó a texto legible, nunca decide qué ocultar.
export async function getWorkOrderTimeline(workOrderId: string): Promise<TimelineEntry[]> {
  const supabase = await createClient();

  const { data } = await supabase
    .from('domain_events')
    .select('id, event_type, occurred_at, payload, actor:profiles(full_name)')
    .eq('work_order_id', workOrderId)
    .order('occurred_at', { ascending: true });

  return (data ?? []).map((e: any) => ({
    id: e.id,
    eventType: e.event_type,
    title: EVENT_TITLES[e.event_type] ?? e.event_type.replace(/_/g, ' ').toLowerCase(),
    occurredAt: e.occurred_at,
    actorName: e.actor?.full_name ?? null,
    detail: buildDetail(e.event_type, e.payload),
  }));
}

function buildDetail(eventType: string, payload: Record<string, unknown> | null): string | null {
  if (!payload) return null;
  switch (eventType) {
    case 'WORK_ORDER_STATUS_CHANGED':
      return payload.to_status ? `→ ${String(payload.to_status).replace(/_/g, ' ')}` : null;
    case 'MEASUREMENT_RECORDED':
      return payload.label ? `${payload.label}: ${payload.value} ${payload.unit}` : null;
    default:
      return null;
  }
}
