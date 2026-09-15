import 'server-only';
import { createClient } from '@/lib/supabase/server';
import { getEffectiveWarrantyStatus } from './effective-status';

export interface WarrantyQueueRow {
  id: string;
  status: string;
  effectiveStatus: string;
  coverageType: string;
  startsAt: string | null;
  endsAt: string | null;
  workOrderId: string;
  workOrderTitle: string | null;
  customerName: string | null;
  vesselName: string | null;
  openClaimCount: number;
}

export interface ClaimQueueRow {
  id: string;
  status: string;
  reason: string;
  submittedAt: string;
  warrantyId: string;
  workOrderId: string;
  customerName: string | null;
  vesselName: string | null;
}

/** Vista operacional cross-work-order para staff/KCC — nunca escaneada por el customer (RLS ya lo impide, esto además solo se llama desde páginas gateadas por rol). */
export async function getWarrantyQueue(filter?: { status?: string; organizationId?: string }): Promise<WarrantyQueueRow[]> {
  const supabase = await createClient();
  let query = supabase
    .from('warranties')
    .select('id, status, coverage_type, starts_at, ends_at, work_order:work_orders(id, title), customer:customers(first_name, last_name), vessel:vessels(name)')
    .order('ends_at', { ascending: true })
    .limit(200);

  if (filter?.organizationId) query = query.eq('organization_id', filter.organizationId);
  // Nunca filtrar por status crudo en la base — 'active' almacenado
  // puede estar realmente vencido sin un cron. El filtro real se
  // aplica después, sobre el estado EFECTIVO calculado en memoria.

  const { data } = await query;
  const warranties = data ?? [];

  const { data: claimCounts } = await supabase
    .from('warranty_claims')
    .select('warranty_id')
    .in('status', ['submitted', 'under_review'])
    .in(
      'warranty_id',
      warranties.map((w: any) => w.id),
    );

  const countsByWarranty = new Map<string, number>();
  for (const c of claimCounts ?? []) {
    countsByWarranty.set(c.warranty_id, (countsByWarranty.get(c.warranty_id) ?? 0) + 1);
  }

  const rows = warranties.map((w: any) => {
    const wo = Array.isArray(w.work_order) ? w.work_order[0] : w.work_order;
    const customer = Array.isArray(w.customer) ? w.customer[0] : w.customer;
    const vessel = Array.isArray(w.vessel) ? w.vessel[0] : w.vessel;
    return {
      id: w.id,
      status: w.status,
      effectiveStatus: getEffectiveWarrantyStatus(w.status, w.ends_at),
      coverageType: w.coverage_type,
      startsAt: w.starts_at,
      endsAt: w.ends_at,
      workOrderId: wo?.id ?? w.work_order_id,
      workOrderTitle: wo?.title ?? null,
      customerName: customer ? `${customer.first_name ?? ''} ${customer.last_name ?? ''}`.trim() : null,
      vesselName: vessel?.name ?? null,
      openClaimCount: countsByWarranty.get(w.id) ?? 0,
    };
  });

  return filter?.status ? rows.filter((r) => r.effectiveStatus === filter.status) : rows;
}

export async function getClaimsQueue(filter?: { status?: string }): Promise<ClaimQueueRow[]> {
  const supabase = await createClient();
  let query = supabase
    .from('warranty_claims')
    .select('id, status, reason, submitted_at, warranty_id, original_work_order_id, customer:customers(first_name, last_name), vessel:vessels(name)')
    .order('submitted_at', { ascending: false })
    .limit(200);

  if (filter?.status) query = query.eq('status', filter.status);

  const { data } = await query;
  return (data ?? []).map((c: any) => {
    const customer = Array.isArray(c.customer) ? c.customer[0] : c.customer;
    const vessel = Array.isArray(c.vessel) ? c.vessel[0] : c.vessel;
    return {
      id: c.id,
      status: c.status,
      reason: c.reason,
      submittedAt: c.submitted_at,
      warrantyId: c.warranty_id,
      workOrderId: c.original_work_order_id,
      customerName: customer ? `${customer.first_name ?? ''} ${customer.last_name ?? ''}`.trim() : null,
      vesselName: vessel?.name ?? null,
    };
  });
}
