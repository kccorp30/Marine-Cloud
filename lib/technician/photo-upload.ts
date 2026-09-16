// Extraído de PhotoPanel a propósito — permite testear el hilo de
// identidad (clientGeneratedId reusado en TODOS los pasos) sin
// necesitar renderizar el componente React. El bug reportado era
// exactamente esto: queueLocally() generaba un id NUEVO en vez de
// reusar el que ya se había usado para initiateMediaUpload/Storage.

export interface AttemptPhotoUploadParams {
  workOrderId: string;
  vesselId: string;
  appointmentId: string | null;
  category: string;
  file: File | Blob;
  mimeType: string;
  sizeBytes: number;
  caption?: string;
  capturedAt: string;
  clientGeneratedId: string; // ÚNICO id para toda la operación — se pasa desde afuera, nunca se genera acá adentro
}

type InitiateResult = { success: true; path: string; token: string; vesselId: string } | { error: string };
type ConfirmResult = { success?: boolean; error?: string };

export interface AttemptPhotoUploadDeps {
  initiateMediaUpload: (workOrderId: string, category: string, mimeType: string, clientGeneratedId: string) => Promise<InitiateResult>;
  confirmMediaUpload: (input: {
    workOrderId: string;
    vesselId: string;
    appointmentId: string | null;
    storagePath: string;
    category: string;
    mimeType: string;
    sizeBytes: number;
    caption?: string;
    visibility: 'internal' | 'customer_visible' | 'kcc_only';
    capturedAt: string;
    clientGeneratedId: string;
  }) => Promise<ConfirmResult | void>;
  uploadToSignedUrl: (path: string, token: string, file: File | Blob) => Promise<{ error: { message: string } | null }>;
  queueLocally: (clientGeneratedId: string) => Promise<boolean>;
}

export type AttemptPhotoUploadResult =
  | { outcome: 'confirmed' }
  | { outcome: 'queued'; reason: string }
  | { outcome: 'failed'; error: string };

export async function attemptOnlinePhotoUpload(
  params: AttemptPhotoUploadParams,
  deps: AttemptPhotoUploadDeps,
): Promise<AttemptPhotoUploadResult> {
  const { clientGeneratedId } = params;

  const initResult = await deps.initiateMediaUpload(params.workOrderId, params.category, params.mimeType, clientGeneratedId);
  if ('error' in initResult) return { outcome: 'failed', error: initResult.error };

  const { error: uploadError } = await deps.uploadToSignedUrl(initResult.path, initResult.token, params.file);
  if (uploadError) {
    // Falla de red subiendo el binario — se encola con el MISMO id
    // ya usado para pedir la signed URL, nunca uno nuevo.
    const queued = await deps.queueLocally(clientGeneratedId);
    return queued
      ? { outcome: 'queued', reason: 'Upload failed — saved locally and queued for retry.' }
      : { outcome: 'failed', error: 'Upload failed and could not save locally.' };
  }

  const confirmResult = await deps.confirmMediaUpload({
    workOrderId: params.workOrderId,
    vesselId: params.vesselId,
    appointmentId: params.appointmentId,
    storagePath: initResult.path,
    category: params.category,
    mimeType: params.mimeType,
    sizeBytes: params.sizeBytes,
    caption: params.caption,
    visibility: 'internal',
    capturedAt: params.capturedAt,
    clientGeneratedId,
  });

  if (confirmResult && 'error' in confirmResult && confirmResult.error) {
    // El binario YA subió a Storage con este id — el reintento
    // encolado debe usar el MISMO id para que el path determinístico
    // (derivado del id) sea idéntico, y el retry solo repita el paso
    // de confirmación sin volver a subir ni duplicar el archivo.
    const queued = await deps.queueLocally(clientGeneratedId);
    return queued
      ? { outcome: 'queued', reason: 'Could not save photo record — queued for retry.' }
      : { outcome: 'failed', error: 'Could not save record and could not save locally.' };
  }

  return { outcome: 'confirmed' };
}
