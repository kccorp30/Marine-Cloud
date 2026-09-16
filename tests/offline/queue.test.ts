import { describe, it, expect, beforeEach } from 'vitest';
import { enqueue, listQueue, updateQueueItemStatus, removeQueueItem } from '@/lib/offline/queue';
import 'fake-indexeddb/auto';
import { IDBFactory } from 'fake-indexeddb';

// Cada test arranca con una IndexedDB limpia — si no reseteamos,
// los tests se contaminan entre sí (misma DB persistida en memoria
// durante toda la corrida de vitest).
beforeEach(() => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (globalThis as any).indexedDB = new IDBFactory();
});

describe('offline queue', () => {
  it('enqueues a note and lists it back as pending', async () => {
    const result = await enqueue({
      id: 'note-1',
      type: 'note',
      workOrderId: 'wo-1',
      payload: { appointmentId: null, body: 'Test note', noteType: 'diagnostic' },
    });
    expect(result).toEqual({ success: true });

    const items = await listQueue();
    expect(items).toHaveLength(1);
    expect(items[0].status).toBe('pending');
    expect(items[0].type).toBe('note');
  });

  it('stores a real Blob for photo items, not a data URL string', async () => {
    const blob = new Blob(['fake-image-bytes'], { type: 'image/jpeg' });
    await enqueue({
      id: 'photo-1',
      type: 'photo',
      workOrderId: 'wo-1',
      blob,
      payload: {
        vesselId: 'vessel-1',
        appointmentId: null,
        category: 'before',
        mimeType: 'image/jpeg',
        sizeBytes: blob.size,
        visibility: 'internal',
        capturedAt: new Date().toISOString(),
      },
    });

    const items = await listQueue();
    expect(items).toHaveLength(1);
    const photoItem = items[0];
    if (photoItem.type !== 'photo') throw new Error('expected photo item');
    expect(photoItem.blob).toBeInstanceOf(Blob);
    expect(photoItem.blob.type).toBe('image/jpeg');
  });

  it('preserves captured_at as the capture time, not enqueue time', async () => {
    const capturedAt = '2026-01-01T12:00:00.000Z'; // deliberately in the past
    const blob = new Blob(['x'], { type: 'image/png' });
    await enqueue({
      id: 'photo-2',
      type: 'photo',
      workOrderId: 'wo-1',
      blob,
      payload: {
        vesselId: 'vessel-1',
        appointmentId: null,
        category: 'diagnosis',
        mimeType: 'image/png',
        sizeBytes: blob.size,
        visibility: 'internal',
        capturedAt,
      },
    });

    const items = await listQueue();
    const photoItem = items.find((i) => i.id === 'photo-2');
    if (!photoItem || photoItem.type !== 'photo') throw new Error('expected photo item');
    expect(photoItem.payload.capturedAt).toBe(capturedAt);
  });

  it('returns queue items ordered by creation time (oldest first)', async () => {
    await enqueue({ id: 'a', type: 'note', workOrderId: 'wo-1', payload: { appointmentId: null, body: 'first', noteType: 'general' } });
    await new Promise((r) => setTimeout(r, 5));
    await enqueue({ id: 'b', type: 'note', workOrderId: 'wo-1', payload: { appointmentId: null, body: 'second', noteType: 'general' } });

    const items = await listQueue();
    expect(items.map((i) => i.id)).toEqual(['a', 'b']);
  });

  it('updates item status and preserves the error message on failure', async () => {
    await enqueue({ id: 'note-x', type: 'note', workOrderId: 'wo-1', payload: { appointmentId: null, body: 'x', noteType: 'general' } });
    await updateQueueItemStatus('note-x', 'failed', 'network error');

    const items = await listQueue();
    expect(items[0].status).toBe('failed');
    expect(items[0].error).toBe('network error');
  });

  it('never silently discards a failed item — it stays in the queue until explicitly removed', async () => {
    await enqueue({ id: 'note-y', type: 'note', workOrderId: 'wo-1', payload: { appointmentId: null, body: 'y', noteType: 'general' } });
    await updateQueueItemStatus('note-y', 'failed', 'boom');

    let items = await listQueue();
    expect(items).toHaveLength(1);

    // Solo un removeQueueItem() explícito (que en producción solo se
    // llama tras confirmación real del servidor) lo saca de la cola.
    await removeQueueItem('note-y');
    items = await listQueue();
    expect(items).toHaveLength(0);
  });

  it('C: enqueue() returns a real {error} — not {success:true} — when local persistence genuinely fails, for every documentation type', async () => {
    // Rompe IndexedDB a propósito — simula el dispositivo sin poder
    // persistir localmente (cuota llena, DB corrupta, etc.). Los 4
    // paneles (Note/Measurement/Progress/Checklist) dependen de que
    // enqueue() jamás mienta sobre esto — es exactamente lo que
    // permite que NUNCA cierren el panel como si hubiera guardado.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (globalThis as any).indexedDB = {
      open: () => {
        throw new Error('simulated device storage failure');
      },
    };

    const noteResult = await enqueue({ id: 'n1', type: 'note', workOrderId: 'wo-1', payload: { appointmentId: null, body: 'x', noteType: 'general' } });
    expect('error' in noteResult).toBe(true);
    expect('success' in noteResult).toBe(false);

    const measurementResult = await enqueue({
      id: 'm1',
      type: 'measurement',
      workOrderId: 'wo-1',
      payload: { vesselId: 'v1', appointmentId: null, measurementType: 'reading', value: 12, unit: 'V', label: 'Bank 1' },
    });
    expect('error' in measurementResult).toBe(true);

    const progressResult = await enqueue({
      id: 'p1',
      type: 'progress_update',
      workOrderId: 'wo-1',
      payload: { appointmentId: null, body: 'update', customerVisible: false },
    });
    expect('error' in progressResult).toBe(true);

    const checklistResult = await enqueue({
      id: 'c1',
      type: 'checklist_response',
      workOrderId: 'wo-1',
      payload: { appointmentId: null, templateItemId: 'item-1', responseValue: { result: 'pass' } },
    });
    expect('error' in checklistResult).toBe(true);
  });
});
