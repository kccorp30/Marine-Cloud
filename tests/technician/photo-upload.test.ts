import { describe, it, expect, vi } from 'vitest';
import { attemptOnlinePhotoUpload } from '@/lib/technician/photo-upload';

const baseParams = {
  workOrderId: 'wo-1',
  vesselId: 'vessel-1',
  appointmentId: null,
  category: 'before',
  file: new Blob(['fake-bytes'], { type: 'image/jpeg' }),
  mimeType: 'image/jpeg',
  sizeBytes: 11,
  capturedAt: '2026-01-01T10:00:00.000Z',
  clientGeneratedId: 'photo-id-A',
};

describe('attemptOnlinePhotoUpload — identity threading', () => {
  it('A: uses the SAME client_generated_id for initiate, and if confirmMediaUpload fails, queueLocally receives that exact same id — not a new one', async () => {
    const initiateMediaUpload = vi.fn(async (_wo, _cat, _mime, id: string) => ({
      success: true as const,
      path: `org/wo/before/${id}.jpg`, // path determinístico, derivado del id — igual que el server action real
      token: 'fake-token',
      vesselId: 'vessel-1',
    }));
    const uploadToSignedUrl = vi.fn(async () => ({ error: null }));
    const confirmMediaUpload = vi.fn(async () => ({ error: 'DB write failed' })); // falla el paso de confirmación
    const queueLocally = vi.fn(async (_id: string) => true);

    const result = await attemptOnlinePhotoUpload(baseParams, {
      initiateMediaUpload,
      confirmMediaUpload,
      uploadToSignedUrl,
      queueLocally,
    });

    expect(result.outcome).toBe('queued');

    // La afirmación central del bug reportado: los TRES pasos deben
    // haber usado exactamente 'photo-id-A' — nunca un id generado de nuevo.
    expect(initiateMediaUpload).toHaveBeenCalledWith('wo-1', 'before', 'image/jpeg', 'photo-id-A');
    expect(confirmMediaUpload).toHaveBeenCalledWith(expect.objectContaining({ clientGeneratedId: 'photo-id-A' }));
    expect(queueLocally).toHaveBeenCalledWith('photo-id-A');
    expect(queueLocally).toHaveBeenCalledTimes(1);
  });

  it('A (variant): if the Storage upload itself fails, queueLocally also receives the same id used for initiate', async () => {
    const initiateMediaUpload = vi.fn(async (_wo, _cat, _mime, id: string) => ({
      success: true as const,
      path: `org/wo/before/${id}.jpg`,
      token: 'fake-token',
      vesselId: 'vessel-1',
    }));
    const uploadToSignedUrl = vi.fn(async () => ({ error: { message: 'network error' } }));
    const confirmMediaUpload = vi.fn(async () => ({ success: true as const }));
    const queueLocally = vi.fn(async (_id: string) => true);

    await attemptOnlinePhotoUpload(baseParams, { initiateMediaUpload, confirmMediaUpload, uploadToSignedUrl, queueLocally });

    expect(queueLocally).toHaveBeenCalledWith('photo-id-A');
    expect(confirmMediaUpload).not.toHaveBeenCalled(); // nunca se llega a confirmar si el upload de Storage falló
  });

  it('B: retrying the exact same logical operation (same clientGeneratedId passed in) produces the exact same deterministic Storage path both times', async () => {
    const requestedPaths: string[] = [];
    const initiateMediaUpload = vi.fn(async (_wo, cat, _mime, id: string) => {
      const path = `org/wo/${cat}/${id}.jpg`;
      requestedPaths.push(path);
      return { success: true as const, path, token: 'fake-token', vesselId: 'vessel-1' };
    });
    const uploadToSignedUrl = vi.fn(async () => ({ error: null }));
    // Primer intento: falla confirmMediaUpload. Segundo intento (retry): confirma bien.
    const confirmMediaUpload = vi
      .fn()
      .mockResolvedValueOnce({ error: 'transient DB error' })
      .mockResolvedValueOnce({ success: true });
    const queueLocally = vi.fn(async (_id: string) => true);

    // Primer intento (falla, se encola)
    await attemptOnlinePhotoUpload(baseParams, { initiateMediaUpload, confirmMediaUpload, uploadToSignedUrl, queueLocally });
    // Reintento — PhotoPanel reusa el MISMO clientGeneratedId guardado en su estado
    await attemptOnlinePhotoUpload(baseParams, { initiateMediaUpload, confirmMediaUpload, uploadToSignedUrl, queueLocally });

    expect(requestedPaths).toHaveLength(2);
    expect(requestedPaths[0]).toBe(requestedPaths[1]); // MISMO path las dos veces — ningún objeto huérfano
    expect(requestedPaths[0]).toBe('org/wo/before/photo-id-A.jpg');
  });

  it('confirms successfully when everything succeeds, without ever touching the queue', async () => {
    const initiateMediaUpload = vi.fn(async (_wo, _cat, _mime, id: string) => ({
      success: true as const,
      path: `org/wo/before/${id}.jpg`,
      token: 'fake-token',
      vesselId: 'vessel-1',
    }));
    const uploadToSignedUrl = vi.fn(async () => ({ error: null }));
    const confirmMediaUpload = vi.fn(async () => ({ success: true as const }));
    const queueLocally = vi.fn(async (_id: string) => true);

    const result = await attemptOnlinePhotoUpload(baseParams, { initiateMediaUpload, confirmMediaUpload, uploadToSignedUrl, queueLocally });

    expect(result.outcome).toBe('confirmed');
    expect(queueLocally).not.toHaveBeenCalled();
  });

  it('D: caption is threaded through to confirmMediaUpload', async () => {
    const initiateMediaUpload = vi.fn(async (_wo, _cat, _mime, id: string) => ({
      success: true as const,
      path: `org/wo/before/${id}.jpg`,
      token: 'fake-token',
      vesselId: 'vessel-1',
    }));
    const uploadToSignedUrl = vi.fn(async () => ({ error: null }));
    const confirmMediaUpload = vi.fn(async () => ({ success: true as const }));
    const queueLocally = vi.fn(async (_id: string) => true);

    await attemptOnlinePhotoUpload(
      { ...baseParams, caption: 'Corroded terminal, before repair' },
      { initiateMediaUpload, confirmMediaUpload, uploadToSignedUrl, queueLocally },
    );

    expect(confirmMediaUpload).toHaveBeenCalledWith(expect.objectContaining({ caption: 'Corroded terminal, before repair' }));
  });
});
