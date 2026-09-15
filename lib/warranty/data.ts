import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface WarrantyClaimRow {
  id: string;
  status: string;
  reason: string;
  description: string | null;
  submittedAt: string;
  decisionReason: string | null;
  claimWorkOrderId: string | null;
}

export interface WarrantyRow {
  id: string;
  workOrderId: string;
  status: 'draft' | 'active' | 'expired' | 'voided';
  coverageType: string;
  coverageNotes: string | null;
  startsAt: string | null;
  endsAt: string | null;
  claims: WarrantyClaimRow[];
}

export async function getWarrantyForWorkOrder(workOrderId: string): Promise<WarrantyRow | null> {
  const supabase = await createClient();
  const { data: warranty } = await supabase
    .from('warranties')
    .select('id, work_order_id, status, coverage_type, coverage_notes, starts_at, ends_at')
    .eq('work_order_id', workOrderId)
    .maybeSingle();

  if (!warranty) return null;

  const { data: claims } = await supabase
    .from('warranty_claims')
    .select('id, status, reason, description, submitted_at, decision_reason, claim_work_order_id')
    .eq('warranty_id', warranty.id)
    .order('submitted_at', { ascending: false });

  return {
    id: warranty.id,
    workOrderId: warranty.work_order_id,
    status: warranty.status,
    coverageType: warranty.coverage_type,
    coverageNotes: warranty.coverage_notes,
    startsAt: warranty.starts_at,
    endsAt: warranty.ends_at,
    claims: (claims ?? []).map((c) => ({
      id: c.id,
      status: c.status,
      reason: c.reason,
      description: c.description,
      submittedAt: c.submitted_at,
      decisionReason: c.decision_reason,
      claimWorkOrderId: c.claim_work_order_id,
    })),
  };
}
