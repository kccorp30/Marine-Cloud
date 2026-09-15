'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getSessionContext } from '@/lib/auth/session';
import { logger } from '@/lib/logger';

// Perfil — pasa por update_company_profile() (migración 055), la
// única puerta de escritura sobre organizations. slug/status/etc.
// quedan estructuralmente inalcanzables porque la función ni los
// acepta como parámetro.
export async function updateCompanyProfile(formData: FormData) {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  if (!activeOrgId) return;

  const supabase = await createClient();
  const { error } = await supabase.rpc('update_company_profile', {
    p_organization_id: activeOrgId,
    p_name: (formData.get('name') as string) || null,
    p_phone: (formData.get('phone') as string) || null,
    p_email: (formData.get('email') as string) || null,
  });
  if (error) {
    logger.warn('updateCompanyProfile failed', { message: error.message });
    return;
  }
  revalidatePath('/company-settings');
}

// Settings (timezone/currency/locale/units) — RLS directa
// (staff_update_settings) ya alcanza acá, no hay campos sensibles
// como en organizations.
export async function updateCompanySettings(formData: FormData) {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  if (!activeOrgId) return;

  const supabase = await createClient();
  const { error } = await supabase
    .from('organization_settings')
    .update({
      timezone: formData.get('timezone') as string,
      currency: formData.get('currency') as string,
      locale: formData.get('locale') as string,
      units_system: formData.get('unitsSystem') as string,
    })
    .eq('organization_id', activeOrgId);
  if (error) {
    logger.warn('updateCompanySettings failed', { message: error.message });
    return;
  }
  revalidatePath('/company-settings');
}

export async function createLocation(formData: FormData) {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const name = formData.get('name') as string;
  if (!activeOrgId || !name) return;

  const supabase = await createClient();
  const { error } = await supabase.from('organization_locations').insert({
    organization_id: activeOrgId,
    name,
    address: (formData.get('address') as string) || null,
    marina_name: (formData.get('marinaName') as string) || null,
    is_primary: false,
  });
  if (error) {
    logger.warn('createLocation failed', { message: error.message });
    return;
  }
  revalidatePath('/company-settings');
}
