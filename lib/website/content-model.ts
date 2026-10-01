// =========================================================
// MODELO DE CONTENIDO DEL SITIO WEB
// =========================================================
// Una sola definición por tipo de contenido. De acá salen:
//   * el formulario del editor (components/website/ContentEditor)
//   * la validación del servidor (lib/website/actions)
//   * las columnas que se leen (lib/website/data)
// Agregar un campo nuevo = agregarlo acá + la columna en la base.
// Nunca hay un formulario escrito a mano por tipo que se pueda
// desincronizar de la validación.
//
// Este archivo NO es server-only: lo usa también el editor en el
// navegador. No debe importar nada del servidor ni contener secretos.
// =========================================================

export type FieldType =
  | 'text' // texto simple, un solo idioma
  | 'slug' // identificador de URL: minúsculas, números y guiones
  | 'path' // ruta de landing: como slug pero permite "/"
  | 'localeText' // {en, es} — una línea
  | 'localeTextarea' // {en, es} — párrafo
  | 'localeList' // [{en, es}] — una entrada por línea
  | 'textList' // string[] — una entrada por línea
  | 'image' // ruta dentro del bucket público site-media
  | 'select'
  | 'reference' // id de otra entidad del sitio
  | 'boolean'
  | 'number'
  | 'date';

export type EntityKey = 'services' | 'landing-pages' | 'projects' | 'testimonials' | 'settings';

export interface FieldDef {
  name: string;
  type: FieldType;
  required?: boolean;
  /** Para 'select'. */
  options?: readonly string[];
  /** Para 'reference'. */
  ref?: Exclude<EntityKey, 'settings'>;
  /** Límite de caracteres por idioma / valor. */
  max?: number;
  /** Para 'number'. */
  min?: number;
  /** Agrupa campos en el editor (clave i18n website.group.<group>). */
  group: 'main' | 'content' | 'media' | 'sales' | 'tracking' | 'seo' | 'trust' | 'contact';
}

export interface EntityDef {
  key: EntityKey;
  table: string;
  /** Campo que se muestra como nombre del registro en las listas. */
  titleField: string;
  /** true = tiene columna `published` y se publica/despublica. */
  publishable: boolean;
  /** Fila única (site_settings). */
  singleton?: boolean;
  /** Orden de la lista. */
  orderBy: { column: string; ascending: boolean }[];
  fields: FieldDef[];
  /** Ruta pública en el sitio para "Ver en el sitio". */
  publicPath?: (row: Record<string, any>) => string | null;
}

export const SERVICE_CATEGORIES = ['electrical', 'maintenance', 'electronics', 'other'] as const;
export const SERVICE_ICONS = ['bolt', 'radar', 'pulse', 'compass', 'speaker', 'bulb', 'battery', 'pump', 'wrench'] as const;

export const SLUG_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
export const PATH_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*(\/[a-z0-9]+(-[a-z0-9]+)*)*$/;

export const ENTITIES: Record<EntityKey, EntityDef> = {
  services: {
    key: 'services',
    table: 'site_services',
    titleField: 'title',
    publishable: true,
    orderBy: [
      { column: 'sort_order', ascending: true },
      { column: 'created_at', ascending: true },
    ],
    publicPath: (row) => (row.slug ? `/services/${row.slug}` : null),
    fields: [
      { name: 'title', type: 'localeText', required: true, max: 90, group: 'main' },
      { name: 'slug', type: 'slug', required: true, max: 80, group: 'main' },
      { name: 'category', type: 'select', options: SERVICE_CATEGORIES, required: true, group: 'main' },
      { name: 'icon', type: 'select', options: SERVICE_ICONS, required: true, group: 'main' },
      { name: 'summary', type: 'localeTextarea', max: 280, group: 'content' },
      { name: 'body', type: 'localeTextarea', max: 4000, group: 'content' },
      { name: 'benefits', type: 'localeList', max: 160, group: 'sales' },
      { name: 'hero_image_path', type: 'image', group: 'media' },
      { name: 'featured', type: 'boolean', group: 'main' },
      { name: 'sort_order', type: 'number', min: 0, group: 'main' },
      { name: 'seo_title', type: 'localeText', max: 70, group: 'seo' },
      { name: 'seo_description', type: 'localeTextarea', max: 170, group: 'seo' },
    ],
  },
  'landing-pages': {
    key: 'landing-pages',
    table: 'site_landing_pages',
    titleField: 'internal_name',
    publishable: true,
    orderBy: [{ column: 'created_at', ascending: false }],
    publicPath: (row) => (row.path ? `/${row.path}` : null),
    fields: [
      { name: 'internal_name', type: 'text', required: true, max: 120, group: 'main' },
      { name: 'path', type: 'path', required: true, max: 120, group: 'main' },
      { name: 'service_id', type: 'reference', ref: 'services', group: 'main' },
      { name: 'headline', type: 'localeText', required: true, max: 110, group: 'sales' },
      { name: 'subheadline', type: 'localeTextarea', max: 300, group: 'sales' },
      { name: 'offer', type: 'localeText', max: 140, group: 'sales' },
      { name: 'bullets', type: 'localeList', max: 140, group: 'sales' },
      { name: 'cta_label', type: 'localeText', max: 40, group: 'sales' },
      { name: 'hero_image_path', type: 'image', group: 'media' },
      { name: 'project_id', type: 'reference', ref: 'projects', group: 'trust' },
      { name: 'testimonial_id', type: 'reference', ref: 'testimonials', group: 'trust' },
      { name: 'utm_source', type: 'text', max: 60, group: 'tracking' },
      { name: 'utm_campaign', type: 'text', max: 120, group: 'tracking' },
    ],
  },
  projects: {
    key: 'projects',
    table: 'site_projects',
    titleField: 'title',
    publishable: true,
    orderBy: [
      { column: 'sort_order', ascending: true },
      { column: 'completed_on', ascending: false },
    ],
    publicPath: (row) => (row.slug ? `/projects/${row.slug}` : null),
    fields: [
      { name: 'title', type: 'localeText', required: true, max: 110, group: 'main' },
      { name: 'slug', type: 'slug', required: true, max: 80, group: 'main' },
      { name: 'service_id', type: 'reference', ref: 'services', group: 'main' },
      { name: 'vessel_type', type: 'text', max: 80, group: 'main' },
      { name: 'location', type: 'text', max: 80, group: 'main' },
      { name: 'completed_on', type: 'date', group: 'main' },
      { name: 'problem', type: 'localeTextarea', max: 1200, group: 'content' },
      { name: 'solution', type: 'localeTextarea', max: 1600, group: 'content' },
      { name: 'result', type: 'localeTextarea', max: 1200, group: 'content' },
      { name: 'before_image_path', type: 'image', group: 'media' },
      { name: 'after_image_path', type: 'image', group: 'media' },
      { name: 'featured', type: 'boolean', group: 'main' },
      { name: 'sort_order', type: 'number', min: 0, group: 'main' },
    ],
  },
  testimonials: {
    key: 'testimonials',
    table: 'site_testimonials',
    titleField: 'author_name',
    publishable: true,
    orderBy: [
      { column: 'sort_order', ascending: true },
      { column: 'created_at', ascending: false },
    ],
    fields: [
      { name: 'author_name', type: 'text', required: true, max: 80, group: 'main' },
      { name: 'author_detail', type: 'text', max: 120, group: 'main' },
      { name: 'quote', type: 'localeTextarea', required: true, max: 700, group: 'content' },
      { name: 'rating', type: 'number', min: 1, group: 'content' },
      { name: 'service_id', type: 'reference', ref: 'services', group: 'main' },
      { name: 'consent_confirmed', type: 'boolean', group: 'trust' },
      { name: 'featured', type: 'boolean', group: 'main' },
      { name: 'sort_order', type: 'number', min: 0, group: 'main' },
    ],
  },
  settings: {
    key: 'settings',
    table: 'site_settings',
    titleField: 'company_name',
    publishable: false,
    singleton: true,
    orderBy: [],
    publicPath: () => '/',
    fields: [
      { name: 'company_name', type: 'text', required: true, max: 80, group: 'main' },
      { name: 'tagline', type: 'localeText', max: 120, group: 'main' },
      { name: 'hero_headline', type: 'localeText', max: 110, group: 'sales' },
      { name: 'hero_subheadline', type: 'localeTextarea', max: 300, group: 'sales' },
      { name: 'primary_cta_label', type: 'localeText', max: 40, group: 'sales' },
      { name: 'response_promise', type: 'localeText', max: 120, group: 'sales' },
      { name: 'hero_image_path', type: 'image', group: 'media' },
      { name: 'phone', type: 'text', max: 30, group: 'contact' },
      { name: 'whatsapp', type: 'text', max: 15, group: 'contact' },
      { name: 'email', type: 'text', max: 120, group: 'contact' },
      { name: 'service_areas', type: 'textList', max: 60, group: 'contact' },
      { name: 'years_in_business', type: 'number', min: 0, group: 'trust' },
      { name: 'jobs_completed', type: 'number', min: 0, group: 'trust' },
    ],
  },
};

export const LIST_ENTITIES = ['services', 'landing-pages', 'projects', 'testimonials'] as const satisfies readonly EntityKey[];

export function isEntityKey(value: string): value is EntityKey {
  return Object.prototype.hasOwnProperty.call(ENTITIES, value);
}

export type LocaleValue = { en?: string; es?: string };

/** Texto legible de un valor localizado o simple, para listas. */
export function displayValue(value: unknown, locale: 'en' | 'es'): string {
  if (value == null) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'object' && !Array.isArray(value)) {
    const v = value as LocaleValue;
    return (locale === 'es' ? v.es || v.en : v.en || v.es) || '';
  }
  return String(value);
}

/** URL pública de una imagen del bucket site-media (bucket público). */
export function siteMediaUrl(supabaseUrl: string, path: string | null | undefined): string | null {
  if (!path) return null;
  const clean = path.replace(/^\/+/, '');
  return `${supabaseUrl.replace(/\/+$/, '')}/storage/v1/object/public/site-media/${clean
    .split('/')
    .map(encodeURIComponent)
    .join('/')}`;
}
