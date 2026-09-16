'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { logger, safeErrorResponse } from '@/lib/logger';
import { ALLOWED_MEDIA_MIME_TYPES, MAX_MEDIA_SIZE_BYTES, ALLOWED_MEDIA_CATEGORIES } from './media-validation';

// ---------------------------------------------------------
// Estado del work order — SIEMPRE vía transition_work_order() /
// technician_start_route(), nunca UPDATE directo (item 3 del brief:
// "Never bypass the state machine from the UI").
// ---------------------------------------------------------
export async function startRoute(workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('technician_start_route', { p_work_order_id: workOrderId });
  if (error) {
    logger.warn('startRoute rejected', { workOrderId, error: error.message });
    return { error: error.message };
  }
  revalidatePath(`/work-orders/${workOrderId}`);
  revalidatePath('/today');
  return { success: true };
}

export async function checkIn(appointmentId: string, workOrderId: string, coords?: { lat: number; lng: number }) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('technician_check_in', {
    p_appointment_id: appointmentId,
    p_latitude: coords?.lat ?? null,
    p_longitude: coords?.lng ?? null,
    p_device_metadata: { userAgent: 'pwa' },
  });
  if (error) return safeErrorResponse(error, 'Could not check in.');
  revalidatePath(`/work-orders/${workOrderId}`);
  return { success: true };
}

export async function checkOut(checkInId: string, workOrderId: string, closingNote?: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('technician_check_out', { p_check_in_id: checkInId, p_closing_note: closingNote ?? null });
  if (error) return safeErrorResponse(error, 'Could not check out.');
  revalidatePath(`/work-orders/${workOrderId}`);
  return { success: true };
}

// ---------------------------------------------------------
// Timer — start/stop vía función, nunca insert directo del cliente
// para el timestamp de inicio.
// ---------------------------------------------------------
export async function startTimer(workOrderId: string, appointmentId: string | null, clientGeneratedId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('start_time_entry', {
    p_work_order_id: workOrderId,
    p_appointment_id: appointmentId,
    p_entry_type: 'work',
    p_client_generated_id: clientGeneratedId,
  });
  if (error) return safeErrorResponse(error, 'Could not start timer.');
  revalidatePath(`/work-orders/${workOrderId}`);
  return { success: true, timeEntryId: data?.id };
}

export async function stopTimer(timeEntryId: string, workOrderId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('stop_time_entry', { p_time_entry_id: timeEntryId });
  if (error) return safeErrorResponse(error, 'Could not stop timer.');
  revalidatePath(`/work-orders/${workOrderId}`);
  return { success: true };
}

// ---------------------------------------------------------
// Documentación de campo — insert directo, protegido por RLS
// (is_assigned_to_work_order) + client_generated_id para idempotencia
// offline. Todas devuelven {success} o {error}, nunca lanzan.
// ---------------------------------------------------------
export async function addWorkNote(input: {
  workOrderId: string;
  appointmentId?: string | null;
  body: string;
  noteType: 'general' | 'diagnostic' | 'progress' | 'internal' | 'customer_update';
  visibility: 'internal' | 'customer_visible' | 'kcc_only';
  clientGeneratedId: string;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: 'Not authenticated.' };

  const { error } = await supabase.from('work_notes').upsert(
    {
      organization_id: (await supabase.from('work_orders').select('organization_id').eq('id', input.workOrderId).single()).data?.organization_id,
      work_order_id: input.workOrderId,
      appointment_id: input.appointmentId ?? null,
      technician_profile_id: user.id,
      body: input.body,
      note_type: input.noteType,
      visibility: input.visibility,
      client_generated_id: input.clientGeneratedId,
    },
    { onConflict: 'work_order_id,client_generated_id', ignoreDuplicates: true },
  );

  if (error) return safeErrorResponse(error, 'Could not save note.');
  revalidatePath(`/work-orders/${input.workOrderId}`);
  return { success: true };
}

export async function addMeasurement(input: {
  workOrderId: string;
  vesselId: string;
  appointmentId?: string | null;
  measurementType: string;
  value: number;
  unit: string;
  label?: string;
  clientGeneratedId: string;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: 'Not authenticated.' };

  const { data: wo } = await supabase.from('work_orders').select('organization_id').eq('id', input.workOrderId).single();

  const { error } = await supabase.from('measurements').upsert(
    {
      organization_id: wo?.organization_id,
      vessel_id: input.vesselId,
      work_order_id: input.workOrderId,
      appointment_id: input.appointmentId ?? null,
      technician_profile_id: user.id,
      measurement_type: input.measurementType,
      value: input.value,
      unit: input.unit,
      label: input.label ?? null,
      client_generated_id: input.clientGeneratedId,
    },
    { onConflict: 'work_order_id,client_generated_id', ignoreDuplicates: true },
  );

  if (error) return safeErrorResponse(error, 'Could not save measurement.');
  revalidatePath(`/work-orders/${input.workOrderId}`);
  return { success: true };
}

export async function addProgressUpdate(input: {
  workOrderId: string;
  appointmentId?: string | null;
  body: string;
  customerVisible: boolean;
  clientGeneratedId: string;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: 'Not authenticated.' };

  const { data: wo } = await supabase.from('work_orders').select('organization_id').eq('id', input.workOrderId).single();

  const { error } = await supabase.from('progress_updates').upsert(
    {
      organization_id: wo?.organization_id,
      work_order_id: input.workOrderId,
      appointment_id: input.appointmentId ?? null,
      technician_profile_id: user.id,
      body: input.body,
      customer_visible: input.customerVisible,
      client_generated_id: input.clientGeneratedId,
    },
    { onConflict: 'work_order_id,client_generated_id', ignoreDuplicates: true },
  );

  if (error) return safeErrorResponse(error, 'Could not save progress update.');
  revalidatePath(`/work-orders/${input.workOrderId}`);
  return { success: true };
}

export async function submitChecklistResponse(input: {
  workOrderId: string;
  appointmentId?: string | null;
  templateItemId: string;
  responseValue: Record<string, unknown>;
  clientGeneratedId: string;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: 'Not authenticated.' };

  const { data: wo } = await supabase.from('work_orders').select('organization_id').eq('id', input.workOrderId).single();

  // Clave de idempotencia real: (work_order_id, client_generated_id) —
  // NO (work_order_id, template_item_id). Un reintento (mismo
  // client_generated_id) nunca duplica; una corrección intencional
  // (nuevo client_generated_id sobre el mismo ítem) crea una fila
  // NUEVA a propósito — "cuál es la respuesta vigente" se resuelve en
  // la lectura (la más reciente), nunca pisando la anterior en la
  // escritura. Ver migración 038.
  const { error } = await supabase.from('checklist_responses').upsert(
    {
      organization_id: wo?.organization_id,
      work_order_id: input.workOrderId,
      appointment_id: input.appointmentId ?? null,
      template_item_id: input.templateItemId,
      technician_profile_id: user.id,
      response_value: input.responseValue,
      client_generated_id: input.clientGeneratedId,
    },
    { onConflict: 'work_order_id,client_generated_id', ignoreDuplicates: true },
  );

  if (error) return safeErrorResponse(error, 'Could not save checklist response.');
  revalidatePath(`/work-orders/${input.workOrderId}`);
  return { success: true };
}

// ---------------------------------------------------------
// Media — signed upload URL + confirmación (mismo patrón de dos pasos
// que el sitio web: nunca se sube directo con una key expuesta).
// ---------------------------------------------------------
export async function initiateMediaUpload(workOrderId: string, category: string, mimeType: string, clientGeneratedId: string) {
  if (!ALLOWED_MEDIA_MIME_TYPES.includes(mimeType)) return { error: `Unsupported file type: ${mimeType}` };
  if (!ALLOWED_MEDIA_CATEGORIES.includes(category)) return { error: `Unsupported category: ${category}` };

  const supabase = await createClient();
  const { data: wo } = await supabase.from('work_orders').select('organization_id, vessel_id').eq('id', workOrderId).single();
  if (!wo) return { error: 'Work order not found.' };

  // Ruta DETERMINÍSTICA basada en client_generated_id — no un UUID
  // aleatorio nuevo cada vez. Esto es lo que hace seguro un reintento
  // (item 1 del brief): reintentar sube al MISMO path, nunca crea un
  // objeto huérfano en Storage de un intento anterior fallido.
  const ext = mimeType.split('/')[1] || 'bin';
  const path = `${wo.organization_id}/${workOrderId}/${category}/${clientGeneratedId}.${ext}`;

  // upsert:true — reintentar el mismo path no falla por "ya existe".
  const { data, error } = await supabase.storage.from('vessel-media').createSignedUploadUrl(path, { upsert: true });
  if (error) return safeErrorResponse(error, 'Could not prepare upload.');

  return { success: true, path, token: data.token, vesselId: wo.vessel_id };
}

export async function confirmMediaUpload(input: {
  workOrderId: string;
  vesselId: string;
  appointmentId?: string | null;
  storagePath: string;
  category: string;
  mimeType: string;
  sizeBytes?: number;
  caption?: string;
  visibility: 'internal' | 'customer_visible' | 'kcc_only';
  capturedAt: string;
  clientGeneratedId: string;
}) {
  // Misma validación que initiateMediaUpload — el path online y el
  // path de sync offline pasan los DOS por acá, ninguno se salta esto.
  if (!ALLOWED_MEDIA_MIME_TYPES.includes(input.mimeType)) return { error: `Unsupported file type: ${input.mimeType}` };
  if (!ALLOWED_MEDIA_CATEGORIES.includes(input.category)) return { error: `Unsupported category: ${input.category}` };
  if (input.sizeBytes && input.sizeBytes > MAX_MEDIA_SIZE_BYTES) return { error: 'File exceeds the 25MB limit.' };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: 'Not authenticated.' };

  const { data: wo } = await supabase.from('work_orders').select('organization_id').eq('id', input.workOrderId).single();

  const { error } = await supabase.from('media_assets').upsert(
    {
      organization_id: wo?.organization_id,
      vessel_id: input.vesselId,
      work_order_id: input.workOrderId,
      appointment_id: input.appointmentId ?? null,
      uploaded_by: user.id,
      category: input.category,
      // captured_at = cuando el técnico sacó la foto, viene del
      // cliente (item 6 del brief) — NUNCA now(), que reflejaría el
      // momento de sincronización, no de captura real.
      captured_at: input.capturedAt,
      storage_path: input.storagePath,
      mime_type: input.mimeType,
      size_bytes: input.sizeBytes ?? null,
      caption: input.caption ?? null,
      // Default seguro y explícito (item 8 del brief): nunca
      // customer_visible automáticamente — el técnico tiene que
      // elegirlo a propósito.
      visibility: input.visibility ?? 'internal',
      client_generated_id: input.clientGeneratedId,
    },
    { onConflict: 'work_order_id,client_generated_id', ignoreDuplicates: true },
  );

  if (error) return safeErrorResponse(error, 'Could not save media record.');
  revalidatePath(`/work-orders/${input.workOrderId}`);
  return { success: true };
}
