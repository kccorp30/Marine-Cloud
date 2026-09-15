'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function manuallyRouteLeadAction(formData: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('manually_route_lead', {
    p_lead_id: formData.get('leadId') as string,
    p_organization_id: formData.get('organizationId') as string,
  });
  if (error) {
    logger.warn('manuallyRouteLeadAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/website-leads');
  return {};
}

export async function retryLeadConversionAction(leadId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('convert_website_lead', { p_lead_id: leadId });
  if (error) {
    logger.warn('retryLeadConversionAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/website-leads');
  return {};
}
