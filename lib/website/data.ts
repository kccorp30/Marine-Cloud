import 'server-only';
import { createClient } from '@/lib/supabase/server';
import { ENTITIES, LIST_ENTITIES, displayValue, type EntityKey } from './content-model';

// Lecturas del editor del sitio. Siempre con la sesión del usuario:
// RLS (is_kcc_admin) es la puerta real; las páginas además redirigen a
// quien no sea KCC Admin, pero nunca dependemos solo de eso.

export type ContentRow = Record<string, any> & { id: string };

export async function listEntity(entity: Exclude<EntityKey, 'settings'>): Promise<ContentRow[]> {
  const def = ENTITIES[entity];
  const supabase = await createClient();
  let query = supabase.from(def.table).select('*');
  for (const o of def.orderBy) query = query.order(o.column, { ascending: o.ascending, nullsFirst: false });
  const { data, error } = await query;
  if (error) {
    console.error('[website] list failed', entity, error.message);
    return [];
  }
  return (data ?? []) as ContentRow[];
}

export async function getEntity(entity: Exclude<EntityKey, 'settings'>, id: string): Promise<ContentRow | null> {
  const def = ENTITIES[entity];
  const supabase = await createClient();
  const { data } = await supabase.from(def.table).select('*').eq('id', id).maybeSingle();
  return (data as ContentRow) ?? null;
}

export async function getSiteSettings(): Promise<Record<string, any> | null> {
  const supabase = await createClient();
  const { data } = await supabase.from('site_settings').select('*').eq('id', true).maybeSingle();
  return data ?? null;
}

export interface ReferenceOption {
  id: string;
  label: string;
  published: boolean;
}

/** Opciones para los selectores de referencia (servicio, proyecto, testimonio). */
export async function getReferenceOptions(locale: 'en' | 'es'): Promise<Record<string, ReferenceOption[]>> {
  const supabase = await createClient();
  const [services, projects, testimonials] = await Promise.all([
    supabase.from('site_services').select('id, title, published').order('sort_order'),
    supabase.from('site_projects').select('id, title, published').order('sort_order'),
    supabase.from('site_testimonials').select('id, author_name, published').order('sort_order'),
  ]);
  return {
    services: (services.data ?? []).map((r: any) => ({ id: r.id, label: displayValue(r.title, locale), published: r.published })),
    projects: (projects.data ?? []).map((r: any) => ({ id: r.id, label: displayValue(r.title, locale), published: r.published })),
    testimonials: (testimonials.data ?? []).map((r: any) => ({ id: r.id, label: r.author_name, published: r.published })),
  };
}

export interface WebsiteOverview {
  /** false = las tablas del sitio todavía no existen en la base. */
  ready: boolean;
  counts: Record<(typeof LIST_ENTITIES)[number], { published: number; draft: number }>;
  leads: {
    last30: number;
    needsRouting: number;
    byCampaign: { campaign: string; count: number }[];
  };
}

export async function getWebsiteOverview(): Promise<WebsiteOverview> {
  const supabase = await createClient();
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

  const countResults = await Promise.all(
    LIST_ENTITIES.map(async (key) => {
      const { data, error } = await supabase.from(ENTITIES[key].table).select('published');
      return { key, rows: (data ?? []) as { published: boolean }[], error };
    }),
  );

  // Si la tabla no existe, PostgREST responde un error de relación
  // inexistente. No es un fallo de la app: la migración aún no se aplicó.
  const ready = countResults.every((r) => !r.error);

  const counts = Object.fromEntries(
    countResults.map(({ key, rows }) => [
      key,
      { published: rows.filter((r) => r.published).length, draft: rows.filter((r) => !r.published).length },
    ]),
  ) as WebsiteOverview['counts'];

  const [{ data: recent }, { count: needsRouting }] = await Promise.all([
    supabase.from('leads').select('utm_campaign, campaign').gte('created_at', since).limit(1000),
    supabase.from('leads').select('id', { count: 'exact', head: true }).eq('conversion_status', 'needs_routing'),
  ]);

  const byCampaignMap = new Map<string, number>();
  for (const l of recent ?? []) {
    const name = (l as any).utm_campaign || (l as any).campaign || '';
    byCampaignMap.set(name, (byCampaignMap.get(name) ?? 0) + 1);
  }
  const byCampaign = [...byCampaignMap.entries()]
    .map(([campaign, count]) => ({ campaign, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 6);

  return {
    ready,
    counts,
    leads: { last30: (recent ?? []).length, needsRouting: needsRouting ?? 0, byCampaign },
  };
}

/** URL pública del sitio (servidor). Sin configurar = sin enlaces "Ver en el sitio". */
export function getWebsiteUrl(): string | null {
  const url = process.env.WEBSITE_URL?.trim();
  return url ? url.replace(/\/+$/, '') : null;
}
