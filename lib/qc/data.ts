import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface QcItemRow {
  id: string;
  label: string;
  result: 'pending' | 'pass' | 'fail' | 'not_applicable';
  notes: string | null;
  required: boolean;
  evidence: Array<{ id: string; mediaAssetId: string; storagePath: string }>;
}

export interface WorkOrderMediaOption {
  id: string;
  storagePath: string;
  category: string;
}

/** Media del work order disponible para adjuntar como evidencia — solo interna/staff, nunca escaneada por el customer. */
export async function getWorkOrderMediaForQc(workOrderId: string): Promise<WorkOrderMediaOption[]> {
  const supabase = await createClient();
  const { data } = await supabase.from('media_assets').select('id, storage_path, category').eq('work_order_id', workOrderId).order('created_at', { ascending: false }).limit(50);
  return (data ?? []).map((m) => ({ id: m.id, storagePath: m.storage_path, category: m.category }));
}

export interface QcSubmissionRow {
  id: string;
  status: 'draft' | 'submitted' | 'passed' | 'failed' | 'cancelled';
  submittedBy: string | null;
  reviewedBy: string | null;
  failureReason: string | null;
  notes: string | null;
  createdAt: string;
  items: QcItemRow[];
}

/** Devuelve todas las submissions de QC de un work order, más recientes primero — la activa (draft/submitted) y el historial de fallos previos. */
export async function getQcSubmissionsForWorkOrder(workOrderId: string): Promise<QcSubmissionRow[]> {
  const supabase = await createClient();
  const { data: submissions } = await supabase
    .from('qc_submissions')
    .select('id, status, submitted_by, reviewed_by, failure_reason, notes, created_at')
    .eq('work_order_id', workOrderId)
    .order('created_at', { ascending: false });

  if (!submissions || submissions.length === 0) return [];

  const { data: items } = await supabase
    .from('qc_submission_items')
    .select('id, qc_submission_id, label, result, notes, required')
    .in(
      'qc_submission_id',
      submissions.map((s) => s.id),
    )
    .order('sort_order', { ascending: true });

  const itemIds = (items ?? []).map((i) => i.id);
  const { data: evidence } =
    itemIds.length > 0
      ? await supabase.from('qc_evidence').select('id, qc_submission_item_id, media_asset_id, media_assets(storage_path)').in('qc_submission_item_id', itemIds)
      : { data: [] as any[] };

  return submissions.map((s) => ({
    id: s.id,
    status: s.status,
    submittedBy: s.submitted_by,
    reviewedBy: s.reviewed_by,
    failureReason: s.failure_reason,
    notes: s.notes,
    createdAt: s.created_at,
    items: (items ?? [])
      .filter((i) => i.qc_submission_id === s.id)
      .map((i) => ({
        id: i.id,
        label: i.label,
        result: i.result,
        notes: i.notes,
        required: i.required,
        evidence: (evidence ?? [])
          .filter((e: any) => e.qc_submission_item_id === i.id)
          .map((e: any) => ({ id: e.id, mediaAssetId: e.media_asset_id, storagePath: Array.isArray(e.media_assets) ? e.media_assets[0]?.storage_path : e.media_assets?.storage_path })),
      })),
  }));
}

export async function getCanReviewQc(organizationId: string): Promise<boolean> {
  const supabase = await createClient();
  const { data } = await supabase.rpc('can_review_qc', { p_organization_id: organizationId });
  return Boolean(data);
}
