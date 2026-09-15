'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function activateWarrantyAction(workOrderId: string, durationDays: number, coverageType: string, coverageNotes: string | null) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('activate_warranty', {
    p_work_order_id: workOrderId,
    p_duration_days: durationDays,
    p_coverage_type: coverageType,
    p_coverage_notes: coverageNotes,
  });
  if (error) {
    logger.warn('activateWarrantyAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  return {};
}

export async function submitWarrantyClaimAction(warrantyId: string, reason: string, description: string | null, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('submit_warranty_claim', { p_warranty_id: warrantyId, p_reason: reason, p_description: description });
  if (error) {
    logger.warn('submitWarrantyClaimAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  return {};
}

export async function reviewWarrantyClaimAction(claimId: string, decision: 'approved' | 'rejected', decisionReason: string | null, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('review_warranty_claim', { p_claim_id: claimId, p_decision: decision, p_decision_reason: decisionReason });
  if (error) {
    logger.warn('reviewWarrantyClaimAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  return {};
}

export async function createCorrectiveWorkOrderAction(claimId: string, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('create_corrective_work_order_from_claim', { p_claim_id: claimId, p_title: null, p_description: null });
  if (error) {
    logger.warn('createCorrectiveWorkOrderAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  revalidatePath('/warranty');
  return {};
}

export async function markClaimUnderReviewAction(claimId: string, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('mark_warranty_claim_under_review', { p_claim_id: claimId });
  if (error) {
    logger.warn('markClaimUnderReviewAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  revalidatePath('/warranty');
  return {};
}

export async function resolveClaimAction(claimId: string, notes: string | null, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('resolve_warranty_claim', { p_claim_id: claimId, p_resolution_notes: notes });
  if (error) {
    logger.warn('resolveClaimAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  revalidatePath('/warranty');
  return {};
}

export async function cancelClaimAction(claimId: string, reason: string | null, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('cancel_warranty_claim', { p_claim_id: claimId, p_reason: reason });
  if (error) {
    logger.warn('cancelClaimAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  revalidatePath('/warranty');
  return {};
}
