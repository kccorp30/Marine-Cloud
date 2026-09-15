import 'server-only';
import { createClient } from '@/lib/supabase/server';

export type AssistanceStatus = 'open' | 'accepted' | 'started' | 'resolved' | 'escalated';

export interface AssistanceRequestDTO {
  id: string;
  workOrderId: string;
  workOrderTitle: string | null;
  vesselName: string | null;
  requestingTechnicianName: string | null;
  technicianPhone: string | null;
  technicianAvatar: string | null;
  currentJobStatus: string | null;
  category: string;
  urgency: string;
  notes: string | null;
  status: AssistanceStatus;
  acceptedByName: string | null;
  acceptedAt: string | null;
  startedAt: string | null;
  resolvedAt: string | null;
  escalatedAt: string | null;
  resolutionNotes: string | null;
  createdAt: string;
}

function mapRow(r: any): AssistanceRequestDTO {
  const wo = Array.isArray(r.work_order) ? r.work_order[0] : r.work_order;
  const vessel = Array.isArray(r.vessel) ? r.vessel[0] : r.vessel;
  const tech = Array.isArray(r.technician) ? r.technician[0] : r.technician;
  const acceptedBy = Array.isArray(r.accepted_by_profile) ? r.accepted_by_profile[0] : r.accepted_by_profile;
  return {
    id: r.id,
    workOrderId: r.work_order_id,
    workOrderTitle: wo?.title ?? null,
    vesselName: vessel?.name ?? null,
    requestingTechnicianName: tech?.full_name ?? null,
    technicianPhone: tech?.phone ?? null,
    technicianAvatar: tech?.avatar_url ?? null,
    currentJobStatus: r.current_job_status,
    category: r.category,
    urgency: r.urgency,
    notes: r.notes,
    status: r.status,
    acceptedByName: acceptedBy?.full_name ?? null,
    acceptedAt: r.accepted_at,
    startedAt: r.started_at,
    resolvedAt: r.resolved_at,
    escalatedAt: r.escalated_at,
    resolutionNotes: r.resolution_notes,
    createdAt: r.created_at,
  };
}

const SELECT_FIELDS = `
  id, work_order_id, current_job_status, category, urgency, notes, status,
  accepted_at, started_at, resolved_at, escalated_at, resolution_notes, created_at,
  work_order:work_orders(title),
  vessel:vessels(name),
  technician:profiles!kcc_assistance_requests_requesting_technician_id_fkey(full_name,phone,avatar_url),
  accepted_by_profile:profiles!kcc_assistance_requests_accepted_by_fkey(full_name)
`;

/** Cola de KCC admin — abiertos/en curso primero. */
export async function getOpenAssistanceRequests(): Promise<AssistanceRequestDTO[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from('kcc_assistance_requests')
    .select(SELECT_FIELDS)
    .in('status', ['open', 'accepted', 'started'])
    .order('created_at', { ascending: true });
  return (data ?? []).map(mapRow);
}

/** Historial (resueltos/escalados) — para la consola de KCC admin. */
export async function getResolvedAssistanceRequests(): Promise<AssistanceRequestDTO[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from('kcc_assistance_requests')
    .select(SELECT_FIELDS)
    .in('status', ['resolved', 'escalated'])
    .order('created_at', { ascending: false })
    .limit(30);
  return (data ?? []).map(mapRow);
}

/** Vista del propio técnico — sus pedidos. */
export async function getMyAssistanceRequests(): Promise<AssistanceRequestDTO[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from('kcc_assistance_requests')
    .select(SELECT_FIELDS)
    .order('created_at', { ascending: false })
    .limit(20);
  return (data ?? []).map(mapRow);
}
