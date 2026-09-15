'use client';

import { listQueue, updateQueueItemStatus, removeQueueItem, type QueueItem } from './queue';
import { addWorkNote, addMeasurement, addProgressUpdate, submitChecklistResponse, initiateMediaUpload, confirmMediaUpload } from '@/lib/technician/actions';
import { createClient } from '@/lib/supabase/client';

// Procesa la cola offline contra el servidor, EN ORDEN de creación
// (listQueue() ya devuelve ordenado — importa para checklist, donde
// una corrección posterior debe aplicarse después de la original).
//
// Cada item usa su propio id como client_generated_id — el servidor
// ya es idempotente para eso. Para fotos específicamente, el path de
// Storage también es determinístico (ver initiateMediaUpload), así
// que reintentar nunca sube el mismo archivo dos veces a rutas
// distintas ni deja objetos huérfanos.
export async function syncQueue(): Promise<{ synced: number; failed: number }> {
  const items = await listQueue();
  const pending = items.filter((i) => i.status === 'pending' || i.status === 'failed');

  let synced = 0;
  let failed = 0;

  for (const item of pending) {
    await updateQueueItemStatus(item.id, 'syncing');
    try {
      const result = await syncOne(item);
      if (result?.error) {
        await updateQueueItemStatus(item.id, 'failed', result.error);
        failed++;
      } else {
        // Solo se saca de la cola cuando el servidor confirmó éxito
        // real — para fotos, eso significa Storage Y media_assets
        // los DOS, no solo uno de los dos pasos.
        await removeQueueItem(item.id);
        synced++;
      }
    } catch (err) {
      await updateQueueItemStatus(item.id, 'failed', err instanceof Error ? err.message : 'Sync failed');
      failed++;
    }
  }

  return { synced, failed };
}

async function syncOne(item: QueueItem): Promise<{ error?: string; success?: boolean } | void> {
  switch (item.type) {
    case 'note':
      return addWorkNote({
        workOrderId: item.workOrderId,
        appointmentId: item.payload.appointmentId,
        body: item.payload.body,
        noteType: item.payload.noteType,
        visibility: 'internal',
        clientGeneratedId: item.id,
      });

    case 'measurement':
      return addMeasurement({
        workOrderId: item.workOrderId,
        vesselId: item.payload.vesselId,
        appointmentId: item.payload.appointmentId,
        measurementType: item.payload.measurementType,
        value: item.payload.value,
        unit: item.payload.unit,
        label: item.payload.label,
        clientGeneratedId: item.id,
      });

    case 'progress_update':
      return addProgressUpdate({
        workOrderId: item.workOrderId,
        appointmentId: item.payload.appointmentId,
        body: item.payload.body,
        customerVisible: item.payload.customerVisible,
        clientGeneratedId: item.id,
      });

    case 'checklist_response':
      // Idempotencia vs. corrección intencional (item 3 del brief):
      // el servidor usa (work_order_id, client_generated_id) como
      // target de upsert — NO (work_order_id, template_item_id). Un
      // reintento del MISMO item de cola (mismo id) nunca duplica.
      // Una respuesta nueva y distinta para el mismo ítem (otro
      // client_generated_id, encolada después) crea una fila NUEVA a
      // propósito — la lectura decide cuál es "la vigente" (la más
      // reciente por completed_at, ver migración 038), nunca se pisa
      // en la escritura. Por eso listQueue() ordena por createdAt:
      // si se sincronizan fuera de orden, importa cuál se ve última.
      return submitChecklistResponse({
        workOrderId: item.workOrderId,
        appointmentId: item.payload.appointmentId,
        templateItemId: item.payload.templateItemId,
        responseValue: item.payload.responseValue,
        clientGeneratedId: item.id,
      });

    case 'photo':
      return syncPhoto(item);

    default: {
      // Exhaustividad de TypeScript — si se agrega un tipo nuevo a
      // QueueItem sin agregar su case acá, esto no compila.
      const _exhaustive: never = item;
      return { error: 'Unknown queue item type' };
    }
  }
}

// El handler que faltaba (item 1 del brief): sube el Blob real a
// vessel-media, y SOLO llama a confirmMediaUpload si el upload de
// Storage tuvo éxito. Si cualquiera de los dos pasos falla, el item
// vuelve a 'failed' con el Blob todavía en IndexedDB — el próximo
// reintento repite ambos pasos contra el MISMO path determinístico,
// sin duplicar ni perder el archivo.
async function syncPhoto(item: Extract<QueueItem, { type: 'photo' }>): Promise<{ error?: string; success?: boolean } | void> {
  const initResult = await initiateMediaUpload(item.workOrderId, item.payload.category, item.payload.mimeType, item.id);
  if ('error' in initResult && initResult.error) return { error: initResult.error };
  if (!('path' in initResult) || !initResult.path || !initResult.token) return { error: 'Could not prepare upload.' };

  const supabase = createClient();
  const { error: uploadError } = await supabase.storage.from('vessel-media').uploadToSignedUrl(initResult.path, initResult.token, item.blob);
  if (uploadError) return { error: `Upload failed: ${uploadError.message}` };

  return confirmMediaUpload({
    workOrderId: item.workOrderId,
    vesselId: item.payload.vesselId,
    appointmentId: item.payload.appointmentId,
    storagePath: initResult.path,
    category: item.payload.category,
    mimeType: item.payload.mimeType,
    sizeBytes: item.payload.sizeBytes,
    caption: item.payload.caption,
    visibility: item.payload.visibility,
    capturedAt: item.payload.capturedAt,
    clientGeneratedId: item.id,
  });
}
