'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getSessionContext } from '@/lib/auth/session';
import { logger } from '@/lib/logger';
import { emailCompanyOperationalAlert } from '@/lib/notifications/operational-email';

export async function createEstimate(formData: FormData) {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const supabase = await createClient();

  const vesselId = formData.get('vesselId') as string;
  // El customer nunca se toma de un campo del formulario — se deriva
  // del vessel elegido, server-side, para no depender de que el
  // cliente lo mande correcto (ni de JS para poblarlo).
  const { data: vessel } = await supabase.from('vessels').select('current_customer_id').eq('id', vesselId).eq('organization_id', activeOrgId).maybeSingle();
  if (!vessel?.current_customer_id) {
    return {error:'Select a vessel with an assigned customer.'};
  }

  const { data: estimateId, error } = await supabase.rpc('create_draft_estimate', {
    p_organization_id: activeOrgId,
    p_customer_id: vessel.current_customer_id,
    p_vessel_id: vesselId,
    p_work_order_id: (formData.get('workOrderId') as string) || null,
    p_service_request_id: null,
    p_title: (formData.get('title') as string) || null,
    p_customer_message: (formData.get('customerMessage') as string) || null,
    p_valid_until: (formData.get('validUntil') as string) || null,
  });

  if (error || !estimateId) {
    return {error:error?.message || 'Could not create the estimate.'};
  }
  return {redirectTo:`/estimates/${estimateId}`};
}

export async function createChangeOrderAction(formData: FormData) {
  const workOrderId = formData.get('workOrderId') as string;
  const supabase = await createClient();
  const { data: estimateId, error } = await supabase.rpc('create_change_order', {
    p_work_order_id: workOrderId,
    p_title: (formData.get('title') as string) || null,
    p_customer_message: (formData.get('customerMessage') as string) || null,
    p_valid_until: (formData.get('validUntil') as string) || null,
  });
  if (error || !estimateId) {
    logger.warn('createChangeOrderAction failed', { message: error?.message });
    return;
  }
  redirect(`/estimates/${estimateId}`);
}

export async function addLineItem(formData: FormData) {
  const versionId = formData.get('versionId') as string;
  const supabase = await createClient();
  const { error } = await supabase.rpc('add_estimate_line_item', {
    p_estimate_version_id: versionId,
    p_line_type: formData.get('lineType') as string,
    p_description: formData.get('description') as string,
    p_quantity: Number(formData.get('quantity')),
    p_unit_price: Number(formData.get('unitPrice')),
    p_service_catalog_id: null,
    p_customer_visible: formData.get('customerVisible') === 'on',
    p_sort_order: 0,
  });
  if (error) return { error: error.message };
  revalidatePath(`/estimates/${formData.get('estimateId')}`);
}

export async function removeLineItem(estimateId: string, lineItemId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('remove_estimate_line_item', { p_line_item_id: lineItemId });
  if (error) logger.warn('removeLineItem failed', { message: error.message });
  revalidatePath(`/estimates/${estimateId}`);
}

export async function updateVersionDetails(formData: FormData) {
  const estimateId = formData.get('estimateId') as string;
  const versionId = formData.get('versionId') as string;
  const supabase = await createClient();
  const { error } = await supabase.rpc('update_estimate_version_details', {
    p_estimate_version_id: versionId,
    p_title: (formData.get('title') as string) || null,
    p_customer_message: (formData.get('customerMessage') as string) || null,
    p_tax: formData.get('tax') ? Number(formData.get('tax')) : null,
    p_valid_until: (formData.get('validUntil') as string) || null,
  });
  if (error) return { error: error.message };
  revalidatePath(`/estimates/${estimateId}`);
}

export async function sendEstimateAction(estimateId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('send_estimate', { p_estimate_id: estimateId });
  if (error) {
    logger.warn('sendEstimateAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/estimates/${estimateId}`);
  return {};
}

export async function reviseEstimateAction(estimateId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('revise_estimate', { p_estimate_id: estimateId });
  if (error) logger.warn('reviseEstimateAction failed', { message: error.message });
  revalidatePath(`/estimates/${estimateId}`);
}

export async function cancelEstimateAction(estimateId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('cancel_estimate', { p_estimate_id: estimateId });
  if (error) logger.warn('cancelEstimateAction failed', { message: error.message });
  revalidatePath(`/estimates/${estimateId}`);
}

export async function convertToWorkOrderAction(estimateId: string) {
  const supabase = await createClient();
  const { data: workOrderId, error } = await supabase.rpc('activate_approved_estimate_work_order', { p_estimate_id: estimateId });
  if (error || !workOrderId) {
    logger.warn('convertToWorkOrderAction failed', { message: error?.message });
    return;
  }
  redirect(`/work-orders/${workOrderId}`);
}

export async function approveEstimateAction(formData: FormData) {
  const versionId = formData.get('versionId') as string;
  const estimateId = formData.get('estimateId') as string;
  const note = (formData.get('note') as string) || null;
  const supabase = await createClient();
  const { error } = await supabase.rpc('approve_estimate', { p_estimate_version_id: versionId, p_customer_note: note });
  if (error) {
    logger.warn('approveEstimateAction failed', { message: error.message });
    return { error: error.message };
  }
  const { data: approved } = await supabase
    .from('estimates')
    .select('organization_id,estimate_number,vessel:vessels(name),customer:customers(first_name,last_name)')
    .eq('id', estimateId)
    .maybeSingle();
  if (approved?.organization_id) {
    const customer = Array.isArray(approved.customer) ? approved.customer[0] : approved.customer;
    const vessel = Array.isArray(approved.vessel) ? approved.vessel[0] : approved.vessel;
    void emailCompanyOperationalAlert({
      organizationId: approved.organization_id,
      eventKey: `estimate-approved:${estimateId}`,
      title: 'Estimate approved — ready to schedule',
      body: `${approved.estimate_number ?? 'Estimate'} was approved by ${[customer?.first_name, customer?.last_name].filter(Boolean).join(' ') || 'the customer'}${vessel?.name ? ` for ${vessel.name}` : ''}. Open Marine Cloud to create/open the work order and assign a technician.`,
      actionPath: `/estimates/${estimateId}`,
      actionLabel: 'Continue approved job',
    });
  }
  revalidatePath(`/estimates/${estimateId}`);
  revalidatePath('/customer');
  revalidatePath('/company');
  return {};
}

export async function declineEstimateAction(formData: FormData) {
  const versionId = formData.get('versionId') as string;
  const estimateId = formData.get('estimateId') as string;
  const note = (formData.get('note') as string) || null;
  const supabase = await createClient();
  const { error } = await supabase.rpc('decline_estimate', { p_estimate_version_id: versionId, p_customer_note: note });
  if (error) {
    logger.warn('declineEstimateAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/estimates/${estimateId}`);
  revalidatePath('/customer');
  return {};
}

export async function markViewedAction(versionId: string) {
  const supabase = await createClient();
  await supabase.rpc('mark_estimate_viewed', { p_estimate_version_id: versionId });
}
