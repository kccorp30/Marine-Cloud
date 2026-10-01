'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getLocale } from '@/lib/i18n/server';
import { workspaceCopy } from '@/lib/i18n/workspace-copy';
import { ENTITIES, isEntityKey, type EntityKey } from './content-model';
import { parseEntityForm } from './parse';
import { notifyWebsiteContentChanged } from './revalidate';

// =========================================================
// Escrituras del editor del sitio web.
//
// Dos puertas, a propósito:
//   1. getSessionContext().isKccAdmin → error claro e inmediato.
//   2. RLS (is_kcc_admin) en cada tabla → la puerta que de verdad
//      importa: aunque alguien llame esta acción a mano, la base
//      rechaza la escritura si no es KCC Admin.
// Nunca se usa la service role acá.
// =========================================================

type Result = { error?: string; redirectTo?: string } | void;

async function copy() {
  const locale = await getLocale();
  return workspaceCopy[locale] as Record<string, string>;
}

function friendlyDbError(t: Record<string, string>, error: { code?: string; message?: string }): string {
  const msg = error.message ?? '';
  if (error.code === '23505') return t['website.error.duplicate'];
  if (error.code === '23514' && msg.includes('publish_requires_consent')) return t['website.error.consentRequired'];
  if (error.code === '23514') return t['website.error.invalid'];
  if (error.code === '42501' || /row-level security/i.test(msg)) return t['website.error.forbidden'];
  if (error.code === '42P01' || error.code === 'PGRST205' || /does not exist|schema cache/i.test(msg)) return t['website.error.notReady'];
  return t['website.error.generic'];
}

async function requireAdmin(t: Record<string, string>): Promise<string | null> {
  const session = await getSessionContext();
  return session.isKccAdmin ? null : t['website.error.forbidden'];
}

function afterWrite(entity: EntityKey, id?: string) {
  revalidatePath('/website');
  revalidatePath(`/website/${entity}`);
  if (id) revalidatePath(`/website/${entity}/${id}`);
}

export async function saveWebsiteContent(entity: string, id: string | null, formData: FormData): Promise<Result> {
  const t = await copy();
  if (!isEntityKey(entity)) return { error: t['website.error.generic'] };
  const denied = await requireAdmin(t);
  if (denied) return { error: denied };

  const parsed = parseEntityForm(entity, formData);
  if (!parsed.ok) {
    const lines = Object.entries(parsed.errors).map(
      ([field, code]) => `${t[`website.field.${field}`] ?? field}: ${t[`website.validation.${code}`] ?? code}`,
    );
    return { error: `${t['website.error.checkFields']} ${lines.join(' · ')}` };
  }

  const def = ENTITIES[entity];
  const supabase = await createClient();

  if (def.singleton) {
    const { error } = await supabase.from(def.table).update(parsed.values).eq('id', true);
    if (error) return { error: friendlyDbError(t, error) };
    afterWrite(entity);
    await notifyWebsiteContentChanged();
    return;
  }

  if (id) {
    const { error } = await supabase.from(def.table).update(parsed.values).eq('id', id);
    if (error) return { error: friendlyDbError(t, error) };
    afterWrite(entity, id);
    await notifyWebsiteContentChanged();
    return;
  }

  // Todo registro nuevo nace como BORRADOR: nada sale al sitio sin un
  // "Publicar" explícito.
  const { data, error } = await supabase
    .from(def.table)
    .insert({ ...parsed.values, published: false })
    .select('id')
    .single();
  if (error) return { error: friendlyDbError(t, error) };
  afterWrite(entity, data.id);
  return { redirectTo: `/website/${entity}/${data.id}` };
}

export async function setWebsiteContentPublished(entity: string, id: string, published: boolean): Promise<Result> {
  const t = await copy();
  if (!isEntityKey(entity) || !ENTITIES[entity].publishable) return { error: t['website.error.generic'] };
  const denied = await requireAdmin(t);
  if (denied) return { error: denied };

  const supabase = await createClient();
  const { error } = await supabase.from(ENTITIES[entity].table).update({ published }).eq('id', id);
  if (error) return { error: friendlyDbError(t, error) };
  afterWrite(entity, id);
  await notifyWebsiteContentChanged();
}

export async function deleteWebsiteContent(entity: string, id: string): Promise<Result> {
  const t = await copy();
  if (!isEntityKey(entity) || ENTITIES[entity].singleton) return { error: t['website.error.generic'] };
  const denied = await requireAdmin(t);
  if (denied) return { error: denied };

  const supabase = await createClient();
  const { error } = await supabase.from(ENTITIES[entity].table).delete().eq('id', id);
  if (error) return { error: friendlyDbError(t, error) };
  afterWrite(entity);
  await notifyWebsiteContentChanged();
  return { redirectTo: `/website/${entity}` };
}
