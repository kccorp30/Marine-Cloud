'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function requestKccAssistanceAction(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('request_kcc_assistance', {
    p_work_order_id: formData.get('workOrderId') as string,
    p_category: formData.get('category') as string,
    p_urgency: formData.get('urgency') as string,
    p_notes: (formData.get('notes') as string) || null,
  });
  if (error) {
    logger.warn('requestKccAssistanceAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/kcc-assistance');
  return {};
}

export async function acceptKccAssistanceAction(requestId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('accept_kcc_assistance', { p_request_id: requestId });
  if (error) {
    logger.warn('acceptKccAssistanceAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/kcc-assistance');
  return {};
}

export async function startKccAssistanceAction(requestId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('start_kcc_assistance', { p_request_id: requestId });
  if (error) {
    logger.warn('startKccAssistanceAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/kcc-assistance');
  return {};
}

export async function resolveKccAssistanceAction(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('resolve_kcc_assistance', {
    p_request_id: formData.get('requestId') as string,
    p_resolution_notes: (formData.get('resolutionNotes') as string) || null,
  });
  if (error) {
    logger.warn('resolveKccAssistanceAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/kcc-assistance');
  return {};
}

export async function escalateKccAssistanceAction(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('escalate_kcc_assistance', {
    p_request_id: formData.get('requestId') as string,
    p_resolution_notes: (formData.get('resolutionNotes') as string) || null,
  });
  if (error) {
    logger.warn('escalateKccAssistanceAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/kcc-assistance');
  return {};
}
