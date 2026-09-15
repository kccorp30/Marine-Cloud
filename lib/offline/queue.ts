'use client';

import { openOfflineDb } from './db';

export type QueueItemStatus = 'pending' | 'syncing' | 'synced' | 'failed';

// ---------------------------------------------------------
// Unión discriminada — cada tipo de cola tiene EXACTAMENTE el payload
// que su handler de sync necesita. Ya no existe un Record<string,
// unknown> genérico que permita encolar algo sin implementación real
// (el bug señalado: time_entry_start/stop declarados pero nunca
// manejados). Si se agrega un tipo nuevo acá, TypeScript obliga a
// agregarle su caso en sync.ts — no puede quedar a medias otra vez.
// ---------------------------------------------------------

interface QueueItemBase {
  id: string; // = client_generated_id, viaja tal cual al servidor
  workOrderId: string;
  status: QueueItemStatus;
  createdAt: string;
  error?: string;
}

export interface NoteQueueItem extends QueueItemBase {
  type: 'note';
  payload: {
    appointmentId: string | null;
    body: string;
    noteType: 'general' | 'diagnostic' | 'progress' | 'internal' | 'customer_update';
  };
}

export interface MeasurementQueueItem extends QueueItemBase {
  type: 'measurement';
  payload: {
    vesselId: string;
    appointmentId: string | null;
    measurementType: string;
    value: number;
    unit: string;
    label: string;
  };
}

export interface ProgressUpdateQueueItem extends QueueItemBase {
  type: 'progress_update';
  payload: {
    appointmentId: string | null;
    body: string;
    customerVisible: boolean;
  };
}

export interface ChecklistResponseQueueItem extends QueueItemBase {
  type: 'checklist_response';
  payload: {
    appointmentId: string | null;
    templateItemId: string;
    responseValue: Record<string, unknown>;
  };
}

// Foto — lleva el Blob real (IndexedDB lo guarda nativo vía structured
// clone, no hace falta base64). capturedAt es el momento en que el
// técnico sacó/eligió la foto, NO cuando se sincroniza (item 6 del
// brief — importa para el timeline futuro).
export interface PhotoQueueItem extends QueueItemBase {
  type: 'photo';
  blob: Blob;
  payload: {
    vesselId: string;
    appointmentId: string | null;
    category: string;
    mimeType: string;
    sizeBytes: number;
    caption?: string;
    visibility: 'internal' | 'customer_visible' | 'kcc_only';
    capturedAt: string;
  };
}

export type QueueItem = NoteQueueItem | MeasurementQueueItem | ProgressUpdateQueueItem | ChecklistResponseQueueItem | PhotoQueueItem;

// Omit normal NO distribuye sobre uniones discriminadas (gotcha
// conocido de TS) — sin esto, TypeScript perdía la conexión entre
// type:'photo' y el campo blob al llamar enqueue(). Con este tipo sí
// se preserva cuál variante de la unión corresponde.
type DistributiveOmit<T, K extends keyof any> = T extends unknown ? Omit<T, K> : never;

// ---------------------------------------------------------
// Política explícita (item 4 del brief): el timer NUNCA se encola.
// Cambios de estado de timer requieren conexión real — afectan
// horas/nómina, son demasiado sensibles a conflicto para offline en
// v1. No existe ningún tipo de cola para timer — no es que esté
// "sin implementar", es imposible de encolar por diseño de tipos.
// ---------------------------------------------------------

export async function enqueue(item: DistributiveOmit<QueueItem, 'status' | 'createdAt'>): Promise<{ success: true } | { error: string }> {
  try {
    const db = await openOfflineDb();
    const tx = db.transaction('queue', 'readwrite');
    tx.objectStore('queue').put({ ...item, status: 'pending' as const, createdAt: new Date().toISOString() });
    await new Promise<void>((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
    return { success: true };
  } catch (err) {
    // Item 1 del brief: si el almacenamiento local también falla
    // (cuota llena, etc.), hay que decírselo claro al usuario — nunca
    // asumir que "quedó en la cola" sin haberlo confirmado.
    const message =
      err instanceof DOMException && err.name === 'QuotaExceededError'
        ? 'Device storage is full — could not save locally.'
        : 'Could not save locally on this device.';
    return { error: message };
  }
}

export async function listQueue(): Promise<QueueItem[]> {
  const db = await openOfflineDb();
  const items = await new Promise<QueueItem[]>((resolve, reject) => {
    const tx = db.transaction('queue', 'readonly');
    const request = tx.objectStore('queue').getAll();
    request.onsuccess = () => resolve(request.result as QueueItem[]);
    request.onerror = () => reject(request.error);
  });
  // Orden de creación — importa para checklist (una corrección
  // posterior debe aplicarse DESPUÉS de la respuesta original, nunca
  // al revés si se sincronizan fuera de orden).
  return items.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

export async function updateQueueItemStatus(id: string, status: QueueItemStatus, error?: string): Promise<void> {
  const db = await openOfflineDb();
  const tx = db.transaction('queue', 'readwrite');
  const store = tx.objectStore('queue');
  const getReq = store.get(id);
  return new Promise((resolve, reject) => {
    getReq.onsuccess = () => {
      const item = getReq.result;
      if (item) {
        item.status = status;
        if (error) item.error = error;
        store.put(item);
      }
    };
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

// Nunca se descartan solos — solo se quitan de la cola cuando el sync
// confirma éxito real en el servidor.
export async function removeQueueItem(id: string): Promise<void> {
  const db = await openOfflineDb();
  const tx = db.transaction('queue', 'readwrite');
  tx.objectStore('queue').delete(id);
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}
