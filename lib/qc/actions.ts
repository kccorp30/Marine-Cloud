'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function startQcSubmissionAction(workOrderId: string, items: Array<{ label: string; required: boolean }>) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('start_qc_submission', { p_work_order_id: workOrderId, p_items: items.map((it, i) => ({ ...it, sortOrder: i })) });
  if (error) {
    logger.warn('startQcSubmissionAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  return {};
}

export async function setQcItemResultAction(itemId: string, result: string, notes: string | null, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('set_qc_item_result', { p_item_id: itemId, p_result: result, p_notes: notes, p_media_asset_id: null });
  if (error) {
    logger.warn('setQcItemResultAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  return {};
}

export async function submitQcForReviewAction(submissionId: string, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('submit_qc_for_review', { p_submission_id: submissionId });
  if (error) {
    logger.warn('submitQcForReviewAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  return {};
}

export async function passQcSubmissionAction(submissionId: string, notes: string | null, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('pass_qc_submission', { p_submission_id: submissionId, p_notes: notes });
  if (error) {
    logger.warn('passQcSubmissionAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  return {};
}

export async function failQcSubmissionAction(submissionId: string, failureReason: string, notes: string | null, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('fail_qc_submission', { p_submission_id: submissionId, p_failure_reason: failureReason, p_notes: notes });
  if (error) {
    logger.warn('failQcSubmissionAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  return {};
}

export async function attachQcEvidenceAction(itemId: string, mediaAssetId: string, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('attach_qc_evidence', { p_item_id: itemId, p_media_asset_id: mediaAssetId });
  if (error) {
    logger.warn('attachQcEvidenceAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  return {};
}
