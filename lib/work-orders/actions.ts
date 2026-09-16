'use server';

import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getSessionContext } from '@/lib/auth/session';
import { logger, safeErrorResponse } from '@/lib/logger';
import { emailUserOperationalAlert } from '@/lib/notifications/operational-email';

async function getOrgContext() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  if (!activeOrgId) throw new Error('No active organization.');
  return { session, activeOrgId };
}

// ---------------------------------------------------------
// Customers
// ---------------------------------------------------------
const CreateCustomerSchema = z.object({
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  email: z.string().email().optional().or(z.literal('')),
  phone: z.string().optional(),
  preferredContactMethod: z.enum(['phone', 'email', 'whatsapp']).optional(),
});

export async function createCustomer(formData: FormData) {
  const { activeOrgId, session } = await getOrgContext();
  const parsed = CreateCustomerSchema.safeParse({
    firstName: formData.get('firstName'),
    lastName: formData.get('lastName'),
    email: formData.get('email'),
    phone: formData.get('phone'),
    preferredContactMethod: formData.get('preferredContactMethod') || undefined,
  });
  if (!parsed.success) {
    return {error:'Check the customer name, email and phone.'};
  }

  const supabase = await createClient();
  const { error } = await supabase.from('customers').insert({
    organization_id: activeOrgId,
    first_name: parsed.data.firstName,
    last_name: parsed.data.lastName,
    email: parsed.data.email || null,
    phone: parsed.data.phone || null,
    preferred_contact_method: parsed.data.preferredContactMethod || null,
    created_by: session.userId,
  });

  if (error) {
    return safeErrorResponse(error, 'Could not create customer.');
  }
  revalidatePath('/customers');
  return {};
}

// ---------------------------------------------------------
// Vessels
// ---------------------------------------------------------
const CreateVesselSchema = z.object({
  customerId: z.string().uuid(),
  name: z.string().optional(),
  hin: z.string().optional(),
  make: z.string().optional(),
  model: z.string().optional(),
  year: z.coerce.number().int().min(1900).max(2100).optional(),
});

export async function createVessel(formData: FormData) {
  const { activeOrgId, session } = await getOrgContext();
  const parsed = CreateVesselSchema.safeParse({
    customerId: formData.get('customerId'),
    name: formData.get('name'),
    hin: formData.get('hin'),
    make: formData.get('make'),
    model: formData.get('model'),
    year: formData.get('year') || undefined,
  });
  if (!parsed.success) {
    return {error:'Check the vessel details and customer.'};
  }

  const supabase = await createClient();
  const { data: vessel, error } = await supabase
    .from('vessels')
    .insert({
      organization_id: activeOrgId,
      current_customer_id: parsed.data.customerId,
      name: parsed.data.name || null,
      hin: parsed.data.hin || null,
      make: parsed.data.make || null,
      model: parsed.data.model || null,
      year: parsed.data.year || null,
      created_by: session.userId,
    })
    .select('id')
    .single();

  if (error || !vessel) {
    return safeErrorResponse(error, 'Could not create vessel.');
  }

  // Registra la relación de ownership inicial — nunca se infiere solo
  // de current_customer_id, la historia vive en su propia tabla.
  await supabase.from('vessel_ownership_history').insert({
    organization_id: activeOrgId,
    vessel_id: vessel.id,
    customer_id: parsed.data.customerId,
  });

  revalidatePath('/vessels');
  return {redirectTo:`/vessels/${vessel.id}`};
}

// ---------------------------------------------------------
// Work Orders
// ---------------------------------------------------------
const CreateWorkOrderSchema = z.object({
  customerId: z.string().uuid(),
  vesselId: z.string().uuid(),
  serviceId: z.string().uuid().optional().or(z.literal('')),
  title: z.string().min(1),
  description: z.string().optional(),
  priority: z.enum(['low', 'normal', 'high', 'urgent']).default('normal'),
});

export async function createWorkOrder(formData: FormData) {
  const { activeOrgId, session } = await getOrgContext();
  const parsed = CreateWorkOrderSchema.safeParse({
    customerId: formData.get('customerId'),
    vesselId: formData.get('vesselId'),
    serviceId: formData.get('serviceId') || undefined,
    title: formData.get('title'),
    description: formData.get('description'),
    priority: formData.get('priority') || 'normal',
  });
  if (!parsed.success) {
    return {error:'Check customer, vessel and service details.'};
  }

  const supabase = await createClient();
  const { data: wo, error } = await supabase
    .from('work_orders')
    .insert({
      organization_id: activeOrgId,
      customer_id: parsed.data.customerId,
      vessel_id: parsed.data.vesselId,
      service_id: parsed.data.serviceId || null,
      title: parsed.data.title,
      description: parsed.data.description || null,
      priority: parsed.data.priority,
      created_by: session.userId,
    })
    .select('id')
    .single();

  if (error || !wo) {
    return safeErrorResponse(error, 'Could not create work order.');
  }
  revalidatePath('/work-orders');
  return {redirectTo:`/work-orders/${wo.id}`};
}

// Transición controlada — llama al ÚNICO camino autorizado (la
// función de la base de datos), nunca hace UPDATE directo.
export async function transitionWorkOrder(workOrderId: string, toStatus: string, reason?: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('transition_work_order', {
    p_work_order_id: workOrderId,
    p_to_status: toStatus,
    p_reason: reason || null,
  });

  if (error) {
    logger.warn('transition_work_order rejected', { workOrderId, toStatus, error: error.message });
    return { error: error.message };
  }

  revalidatePath(`/work-orders/${workOrderId}`);
  return { success: true };
}

// ---------------------------------------------------------
// Appointments
// ---------------------------------------------------------
const CreateAppointmentSchema = z.object({
  workOrderId: z.string().uuid(),
  scheduledStart: z.string().min(1),
  purpose: z.string().optional(),
});

export async function createAppointment(formData: FormData) {
  const { activeOrgId } = await getOrgContext();
  const parsed = CreateAppointmentSchema.safeParse({
    workOrderId: formData.get('workOrderId'),
    scheduledStart: formData.get('scheduledStart'),
    purpose: formData.get('purpose'),
  });
  if (!parsed.success) {
    logger.warn('createAppointment validation failed');
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.from('appointments').insert({
    organization_id: activeOrgId,
    work_order_id: parsed.data.workOrderId,
    scheduled_start: new Date(parsed.data.scheduledStart).toISOString(),
    purpose: parsed.data.purpose || null,
  });

  if (error) {
    safeErrorResponse(error, 'Could not create appointment.');
  }
  revalidatePath(`/work-orders/${parsed.data.workOrderId}`);
}

// ---------------------------------------------------------
// Assignments
// ---------------------------------------------------------
const AssignTechnicianSchema = z.object({
  workOrderId: z.string().uuid(),
  technicianProfileId: z.string().uuid(),
  appointmentId: z.string().uuid().optional().or(z.literal('')),
});

export async function assignTechnician(formData: FormData) {
  const { activeOrgId, session } = await getOrgContext();
  const parsed = AssignTechnicianSchema.safeParse({
    workOrderId: formData.get('workOrderId'),
    technicianProfileId: formData.get('technicianProfileId'),
    appointmentId: formData.get('appointmentId') || undefined,
  });
  if (!parsed.success) {
    logger.warn('assignTechnician validation failed');
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.from('assignments').insert({
    organization_id: activeOrgId,
    work_order_id: parsed.data.workOrderId,
    technician_profile_id: parsed.data.technicianProfileId,
    appointment_id: parsed.data.appointmentId || null,
    assigned_by: session.userId,
  });

  if (error) {
    safeErrorResponse(error, 'Could not assign technician.');
  }
  const { data: job } = await supabase.from('work_orders').select('title,vessel:vessels(name)').eq('id', parsed.data.workOrderId).maybeSingle();
  const vessel = Array.isArray(job?.vessel) ? job?.vessel[0] : job?.vessel;
  void emailUserOperationalAlert({
    userId: parsed.data.technicianProfileId,
    eventKey: `assignment:${parsed.data.workOrderId}:${parsed.data.technicianProfileId}`,
    title: 'New job assigned',
    body: `${job?.title ?? 'A work order'}${vessel?.name ? ` · ${vessel.name}` : ''} has been assigned to you. Review the job card before starting your route.`,
    actionPath: `/work-orders/${parsed.data.workOrderId}`,
    actionLabel: 'Open job card',
  });
  revalidatePath(`/work-orders/${parsed.data.workOrderId}`);
  revalidatePath('/today');
}


// ---------------------------------------------------------
// Phase 3 — atomic dispatch mission
// Creates/reuses the appointment, assigns/reassigns the technician and
// advances scheduled -> technician_assigned through the canonical DB RPC.
// ---------------------------------------------------------
const DispatchWorkOrderSchema = z.object({
  workOrderId: z.string().uuid(),
  technicianProfileId: z.string().uuid(),
  scheduledStart: z.string().min(1),
  purpose: z.string().max(500).optional(),
});

export async function dispatchWorkOrderAction(formData: FormData) {
  const parsed = DispatchWorkOrderSchema.safeParse({
    workOrderId: formData.get('workOrderId'),
    technicianProfileId: formData.get('technicianProfileId'),
    scheduledStart: formData.get('scheduledStart'),
    purpose: formData.get('purpose') || undefined,
  });
  if (!parsed.success) return { error: 'Choose a technician and schedule before dispatching.' };

  const supabase = await createClient();
  const scheduled = new Date(parsed.data.scheduledStart);
  if (Number.isNaN(scheduled.getTime())) return { error: 'Choose a valid schedule.' };

  const { data, error } = await supabase.rpc('dispatch_work_order', {
    p_work_order_id: parsed.data.workOrderId,
    p_technician_profile_id: parsed.data.technicianProfileId,
    p_scheduled_start: scheduled.toISOString(),
    p_purpose: parsed.data.purpose || null,
  });
  if (error) return safeErrorResponse(error, 'Could not dispatch this job.');

  const { data: job } = await supabase
    .from('work_orders')
    .select('title,vessel:vessels(name),customer:customers(first_name,last_name)')
    .eq('id', parsed.data.workOrderId)
    .maybeSingle();
  const vessel = Array.isArray(job?.vessel) ? job?.vessel[0] : job?.vessel;
  void emailUserOperationalAlert({
    userId: parsed.data.technicianProfileId,
    eventKey: `dispatch:${parsed.data.workOrderId}:${parsed.data.technicianProfileId}:${scheduled.toISOString()}`,
    title: 'New mission assigned',
    body: `${job?.title ?? 'A work order'}${vessel?.name ? ` · ${vessel.name}` : ''} is ready. Review the mission card, customer details and route before departure.`,
    actionPath: `/work-orders/${parsed.data.workOrderId}`,
    actionLabel: 'Open mission',
  });

  revalidatePath(`/work-orders/${parsed.data.workOrderId}`);
  revalidatePath('/company');
  revalidatePath('/today');
  return { redirectTo: `/work-orders/${parsed.data.workOrderId}`, dispatch: data };
}

// ---------------------------------------------------------
// Cancelar cita — RLS (staff_write_appointments_update) exige
// is_org_staff, este action no agrega autorización propia.
// ---------------------------------------------------------
export async function cancelAppointment(appointmentId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from('appointments').update({ status: 'cancelled' }).eq('id', appointmentId);
  if (error) {
    safeErrorResponse(error, 'Could not cancel appointment.');
  }
  revalidatePath('/schedule');
}

// ---------------------------------------------------------
// Reprogramar cita — mismo RLS que crear/cancelar
// (staff_write_appointments_update, is_org_staff). El trigger
// trg_emit_appointment_event (Phase 1/2) sigue emitiendo
// APPOINTMENT_RESCHEDULED automáticamente al cambiar scheduled_start
// — este action no duplica esa lógica, solo hace el UPDATE.
// ---------------------------------------------------------
const RescheduleAppointmentSchema = z.object({
  appointmentId: z.string().uuid(),
  scheduledStart: z.string().min(1),
});

export async function rescheduleAppointment(formData: FormData) {
  const parsed = RescheduleAppointmentSchema.safeParse({
    appointmentId: formData.get('appointmentId'),
    scheduledStart: formData.get('scheduledStart'),
  });
  if (!parsed.success) {
    logger.warn('rescheduleAppointment validation failed');
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from('appointments')
    .update({ scheduled_start: new Date(parsed.data.scheduledStart).toISOString() })
    .eq('id', parsed.data.appointmentId);
  if (error) {
    safeErrorResponse(error, 'Could not reschedule appointment.');
  }
  revalidatePath('/schedule');
}

// Crear cita desde /schedule (a diferencia de createAppointment, que
// se usa desde el detalle de un work order específico) — mismo
// insert, mismo RLS, solo un punto de entrada distinto.
const CreateScheduleAppointmentSchema = z.object({
  workOrderId: z.string().uuid(),
  scheduledStart: z.string().min(1),
  purpose: z.string().optional(),
});

export async function createScheduleAppointment(formData: FormData) {
  const { activeOrgId } = await getOrgContext();
  const parsed = CreateScheduleAppointmentSchema.safeParse({
    workOrderId: formData.get('workOrderId'),
    scheduledStart: formData.get('scheduledStart'),
    purpose: formData.get('purpose'),
  });
  if (!parsed.success) {
    logger.warn('createScheduleAppointment validation failed');
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.from('appointments').insert({
    organization_id: activeOrgId,
    work_order_id: parsed.data.workOrderId,
    scheduled_start: new Date(parsed.data.scheduledStart).toISOString(),
    purpose: parsed.data.purpose || null,
  });
  if (error) {
    safeErrorResponse(error, 'Could not create appointment.');
  }
  revalidatePath('/schedule');
}
