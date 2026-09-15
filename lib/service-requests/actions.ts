'use server';

import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { logger } from '@/lib/logger';

const CreateServiceRequestSchema = z.object({
  vesselId: z.string().uuid(),
  serviceCategory: z.string().optional(),
  title: z.string().min(1),
  description: z.string().optional(),
  urgency: z.enum(['low', 'normal', 'high', 'urgent']).default('normal'),
  preferredDate: z.string().optional(),
  preferredWindow: z.string().optional(),
});

// El INSERT sigue yendo directo a la tabla — la RLS de INSERT
// (customer_insert_service_requests) ya exige que customer_id sea el
// propio y que el vessel realmente le pertenezca, y un INSERT no
// tiene el problema de "qué columnas cambiaron" que sí tenía UPDATE
// (no hay un estado previo que alguien pueda alterar de más).
export async function createServiceRequest(formData: FormData) {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  if (!activeOrgId) throw new Error('No active organization.');

  const parsed = CreateServiceRequestSchema.safeParse({
    vesselId: formData.get('vesselId'),
    serviceCategory: formData.get('serviceCategory') || undefined,
    title: formData.get('title'),
    description: formData.get('description') || undefined,
    urgency: formData.get('urgency') || 'normal',
    preferredDate: formData.get('preferredDate') || undefined,
    preferredWindow: formData.get('preferredWindow') || undefined,
  });
  if (!parsed.success) {
    logger.warn('createServiceRequest validation failed');
    return;
  }

  const supabase = await createClient();
  const { data: customer } = await supabase.from('customers').select('id').eq('profile_id', session.userId).maybeSingle();
  if (!customer) throw new Error('No customer record for this account.');

  const { error } = await supabase.from('service_requests').insert({
    organization_id: activeOrgId,
    customer_id: customer.id,
    vessel_id: parsed.data.vesselId,
    service_category: parsed.data.serviceCategory,
    title: parsed.data.title,
    description: parsed.data.description,
    urgency: parsed.data.urgency,
    preferred_date: parsed.data.preferredDate || null,
    preferred_window: parsed.data.preferredWindow,
    client_generated_id: crypto.randomUUID(),
    created_by: session.userId,
  });

  if (error) {
    logger.warn('createServiceRequest insert failed', { message: error.message });
    return;
  }

  revalidatePath('/customer');
  revalidatePath('/work-orders');
  redirect('/customer');
}

// ---------------------------------------------------------
// Todas las mutaciones de ciclo de vida a partir de acá pasan por
// funciones SECURITY DEFINER (migración 054) — no queda ningún
// UPDATE directo a la tabla, ni para customer ni para staff. Cada
// función toca exactamente las columnas de su transición, sin
// importar qué mande el cliente.
// ---------------------------------------------------------

export async function cancelServiceRequest(requestId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('cancel_service_request', { p_request_id: requestId });
  if (error) {
    logger.warn('cancelServiceRequest failed', { message: error.message });
    return;
  }
  revalidatePath('/customer');
}

export async function acceptServiceRequest(requestId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('accept_service_request', { p_request_id: requestId });
  if (error) {
    logger.warn('acceptServiceRequest failed', { message: error.message });
    return;
  }
  revalidatePath('/service-requests');
}

export async function declineServiceRequest(formData: FormData) {
  const requestId = formData.get('requestId') as string;
  const reason = (formData.get('reason') as string) || null;
  const supabase = await createClient();
  const { error } = await supabase.rpc('decline_service_request', { p_request_id: requestId, p_reason: reason });
  if (error) {
    logger.warn('declineServiceRequest failed', { message: error.message });
    return;
  }
  revalidatePath('/service-requests');
}

export async function convertServiceRequest(requestId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('convert_service_request_to_work_order', { p_request_id: requestId });
  if (error) {
    logger.warn('convertServiceRequest failed', { message: error.message });
    return;
  }
  revalidatePath('/service-requests');
  revalidatePath('/work-orders');
}
