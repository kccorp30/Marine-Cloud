import 'server-only';
import { createClient } from '@/lib/supabase/server';
import { createClient as createServiceClient } from '@/lib/supabase/service';

export type EntityMediaType = 'service_request' | 'estimate' | 'conversation';
export type EntityMediaVisibility = 'customer_visible' | 'internal';
export type EntityMediaCategory = 'reference' | 'damage' | 'diagnosis' | 'before' | 'progress' | 'after' | 'document';

export interface EntityMediaItem {
  id: string;
  organizationId: string;
  entityType: EntityMediaType;
  entityId: string;
  vesselId: string | null;
  uploadedBy: string;
  uploadedByRole: string;
  visibility: EntityMediaVisibility;
  category: EntityMediaCategory;
  caption: string | null;
  mimeType: string;
  sizeBytes: number | null;
  createdAt: string;
  url: string;
}

export const ENTITY_MEDIA_MAX_BYTES = 12 * 1024 * 1024;
export const ENTITY_MEDIA_ALLOWED_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']);

function safeExt(file: File) {
  const byType: Record<string, string> = {
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic', 'image/heif': 'heif',
  };
  return byType[file.type] || 'bin';
}

export function validateEntityImage(file: File) {
  if (!file || file.size <= 0) return 'Choose an image first.';
  if (!ENTITY_MEDIA_ALLOWED_TYPES.has(file.type)) return 'Use JPG, PNG, WebP, HEIC or HEIF.';
  if (file.size > ENTITY_MEDIA_MAX_BYTES) return 'Each image must be 12 MB or smaller.';
  return null;
}

export async function uploadEntityMedia(input: {
  organizationId: string;
  entityType: EntityMediaType;
  entityId: string;
  vesselId?: string | null;
  uploadedBy: string;
  uploadedByRole: 'customer' | 'staff' | 'technician' | 'kcc_admin';
  visibility?: EntityMediaVisibility;
  category?: EntityMediaCategory;
  caption?: string | null;
  file: File;
}) {
  const validation = validateEntityImage(input.file);
  if (validation) throw new Error(validation);

  const service = createServiceClient();
  const mediaId = crypto.randomUUID();
  const ext = safeExt(input.file);
  const path = `${input.organizationId}/${input.entityType}/${input.entityId}/${mediaId}.${ext}`;
  const bytes = new Uint8Array(await input.file.arrayBuffer());
  const { error: storageError } = await service.storage.from('portal-media').upload(path, bytes, {
    contentType: input.file.type,
    upsert: false,
    cacheControl: '3600',
  });
  if (storageError) throw new Error(`Could not upload image: ${storageError.message}`);

  const { error: rowError } = await service.from('entity_media_attachments').insert({
    id: mediaId,
    organization_id: input.organizationId,
    entity_type: input.entityType,
    entity_id: input.entityId,
    vessel_id: input.vesselId || null,
    uploaded_by: input.uploadedBy,
    uploaded_by_role: input.uploadedByRole,
    visibility: input.visibility ?? 'customer_visible',
    category: input.category ?? 'reference',
    caption: input.caption?.trim() || null,
    storage_path: path,
    mime_type: input.file.type,
    size_bytes: input.file.size,
  });
  if (rowError) {
    await service.storage.from('portal-media').remove([path]);
    throw new Error(`Could not save image: ${rowError.message}`);
  }
  return mediaId;
}

export async function listEntityMedia(entityType: EntityMediaType, entityId: string): Promise<EntityMediaItem[]> {
  const db = await createClient();
  const { data, error } = await db
    .from('entity_media_attachments')
    .select('id,organization_id,entity_type,entity_id,vessel_id,uploaded_by,uploaded_by_role,visibility,category,caption,storage_path,mime_type,size_bytes,created_at')
    .eq('entity_type', entityType)
    .eq('entity_id', entityId)
    .is('deleted_at', null)
    .order('created_at', { ascending: false });
  if (error || !data?.length) return [];

  const service = createServiceClient();
  return Promise.all(data.map(async (row: any) => {
    const { data: signed } = await service.storage.from('portal-media').createSignedUrl(row.storage_path, 60 * 60);
    return {
      id: row.id,
      organizationId: row.organization_id,
      entityType: row.entity_type,
      entityId: row.entity_id,
      vesselId: row.vessel_id,
      uploadedBy: row.uploaded_by,
      uploadedByRole: row.uploaded_by_role,
      visibility: row.visibility,
      category: row.category,
      caption: row.caption,
      mimeType: row.mime_type,
      sizeBytes: row.size_bytes == null ? null : Number(row.size_bytes),
      createdAt: row.created_at,
      url: signed?.signedUrl ?? '',
    } as EntityMediaItem;
  }));
}
