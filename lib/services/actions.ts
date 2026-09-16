'use server';

import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getSessionContext } from '@/lib/auth/session';
import { logger } from '@/lib/logger';

const ServiceSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  basePrice: z.string().optional(),
  pricingType: z.string().optional(),
  qcRequired: z.string().optional(),
  warrantyEnabled: z.string().optional(),
  warrantyDurationDays: z.string().optional(),
  warrantyCoverageNotes: z.string().optional(),
});

// La RLS (staff_write_service_catalog_*) ya exige is_org_staff — este
// action no agrega autorización propia, solo arma el insert/update.
export async function createService(formData: FormData) {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const parsed = ServiceSchema.safeParse({
    name: formData.get('name'),
    description: formData.get('description') || undefined,
    basePrice: formData.get('basePrice') || undefined,
    pricingType: formData.get('pricingType') || undefined,
    qcRequired: formData.get('qcRequired') || undefined,
    warrantyEnabled: formData.get('warrantyEnabled') || undefined,
    warrantyDurationDays: formData.get('warrantyDurationDays') || undefined,
    warrantyCoverageNotes: formData.get('warrantyCoverageNotes') || undefined,
  });
  if (!parsed.success || !activeOrgId) return;

  const supabase = await createClient();
  const { error } = await supabase.from('service_catalog').insert({
    organization_id: activeOrgId,
    name: parsed.data.name,
    description: parsed.data.description,
    base_price: parsed.data.basePrice ? Number(parsed.data.basePrice) : null,
    pricing_type: parsed.data.pricingType || null,
    qc_required: parsed.data.qcRequired === 'on',
    warranty_enabled: parsed.data.warrantyEnabled === 'on',
    warranty_duration_days: parsed.data.warrantyDurationDays ? Number(parsed.data.warrantyDurationDays) : null,
    warranty_coverage_notes: parsed.data.warrantyCoverageNotes || null,
    active: true,
    display_order: 0,
  });
  if (error) {
    logger.warn('createService failed', { message: error.message });
    return;
  }
  revalidatePath('/services');
}

export async function toggleServiceActive(serviceId: string, nextActive: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.from('service_catalog').update({ active: nextActive }).eq('id', serviceId);
  if (error) {
    logger.warn('toggleServiceActive failed', { message: error.message });
    return;
  }
  revalidatePath('/services');
}

export async function toggleServiceQcRequired(serviceId: string, nextValue: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.from('service_catalog').update({ qc_required: nextValue }).eq('id', serviceId);
  if (error) {
    logger.warn('toggleServiceQcRequired failed', { message: error.message });
    return;
  }
  revalidatePath('/services');
}

export async function updateService(formData: FormData) {
  const serviceId = formData.get('serviceId') as string;
  const parsed = ServiceSchema.safeParse({
    name: formData.get('name'),
    description: formData.get('description') || undefined,
    basePrice: formData.get('basePrice') || undefined,
    pricingType: formData.get('pricingType') || undefined,
  });
  if (!parsed.success || !serviceId) return;

  const supabase = await createClient();
  const { error } = await supabase
    .from('service_catalog')
    .update({
      name: parsed.data.name,
      description: parsed.data.description,
      base_price: parsed.data.basePrice ? Number(parsed.data.basePrice) : null,
      pricing_type: parsed.data.pricingType || null,
    })
    .eq('id', serviceId);
  if (error) {
    logger.warn('updateService failed', { message: error.message });
    return;
  }
  revalidatePath('/services');
}
