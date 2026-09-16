'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function addLocationAction(formData: FormData) {
  const organizationId = formData.get('organizationId') as string;
  const supabase = await createClient();
  const { error } = await supabase.from('organization_locations').insert({
    organization_id: organizationId,
    name: formData.get('name') as string,
    address: (formData.get('address') as string) || null,
    is_primary: false,
  });
  if (error) {
    logger.warn('addLocationAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function setPrimaryLocationAction(locationId: string, organizationId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('set_primary_location', { p_location_id: locationId });
  if (error) {
    logger.warn('setPrimaryLocationAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function editLocationAction(formData: FormData) {
  const organizationId = formData.get('organizationId') as string;
  const supabase = await createClient();
  const { error } = await supabase.rpc('edit_location', {
    p_location_id: formData.get('locationId') as string,
    p_name: (formData.get('name') as string) || null,
    p_address: (formData.get('address') as string) || null,
    p_marina_name: null,
  });
  if (error) {
    logger.warn('editLocationAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function deactivateLocationAction(locationId: string, organizationId: string, newPrimaryId?: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('deactivate_location', {
    p_location_id: locationId,
    p_new_primary_id: newPrimaryId || null,
  });
  if (error) {
    logger.warn('deactivateLocationAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}
