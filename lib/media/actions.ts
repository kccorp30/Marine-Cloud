'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { uploadEntityMedia, validateEntityImage, type EntityMediaCategory } from '@/lib/media/entity-media';

function photos(formData: FormData) {
  return formData.getAll('photos').filter((v): v is File => v instanceof File && v.size > 0).slice(0, 5);
}

function mediaRole(role: string | undefined, isKccAdmin: boolean) {
  if (isKccAdmin) return 'kcc_admin' as const;
  if (role === 'customer') return 'customer' as const;
  if (role === 'technician') return 'technician' as const;
  return 'staff' as const;
}

export async function uploadEstimateMediaAction(formData: FormData) {
  const estimateId = String(formData.get('estimateId') || '');
  const caption = String(formData.get('caption') || '').trim() || null;
  const category = String(formData.get('category') || 'reference') as EntityMediaCategory;
  const files = photos(formData);
  if (!estimateId || !files.length) return { error: 'Choose at least one photo.' };

  const session = await getSessionContext();
  const org = await getActiveOrganizationId(session.memberships);
  const role = session.memberships.find((m) => m.organization_id === org)?.role;
  if (!org || !(session.isKccAdmin || ['company_owner','company_admin','manager'].includes(role || ''))) return { error: 'Not authorized.' };
  const db = await createClient();
  const { data: estimate } = await db.from('estimates').select('id,organization_id,vessel_id').eq('id', estimateId).eq('organization_id', org).maybeSingle();
  if (!estimate) return { error: 'Estimate not found.' };

  try {
    for (const file of files) {
      const invalid = validateEntityImage(file); if (invalid) return { error: invalid };
      await uploadEntityMedia({ organizationId: org, entityType: 'estimate', entityId: estimate.id, vesselId: estimate.vessel_id, uploadedBy: session.userId, uploadedByRole: mediaRole(role, session.isKccAdmin), visibility: 'customer_visible', category, caption, file });
    }
    revalidatePath(`/estimates/${estimateId}`);
    return { success: true };
  } catch (e) { return { error: e instanceof Error ? e.message : 'Could not upload estimate photos.' }; }
}

export async function uploadConversationMediaAction(formData: FormData) {
  const conversationId = String(formData.get('conversationId') || '');
  const caption = String(formData.get('caption') || '').trim() || null;
  const files = photos(formData);
  if (!conversationId || !files.length) return { error: 'Choose at least one photo.' };
  const session = await getSessionContext();
  const org = await getActiveOrganizationId(session.memberships);
  const role = session.memberships.find((m) => m.organization_id === org)?.role;
  if (!org) return { error: 'No active organization.' };
  const db = await createClient();
  const { data: conversation } = await db.from('conversations').select('id,organization_id,vessel_id').eq('id', conversationId).eq('organization_id', org).maybeSingle();
  if (!conversation) return { error: 'Conversation not found or not authorized.' };
  try {
    for (const file of files) {
      const invalid = validateEntityImage(file); if (invalid) return { error: invalid };
      await uploadEntityMedia({ organizationId: org, entityType: 'conversation', entityId: conversation.id, vesselId: conversation.vessel_id, uploadedBy: session.userId, uploadedByRole: mediaRole(role, session.isKccAdmin), visibility: 'customer_visible', category: 'reference', caption, file });
    }
    revalidatePath(`/communications/${conversationId}`);
    revalidatePath('/messages');
    return { success: true };
  } catch (e) { return { error: e instanceof Error ? e.message : 'Could not upload support photos.' }; }
}
