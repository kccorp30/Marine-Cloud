import { ENTITIES, PATH_PATTERN, SLUG_PATTERN, type EntityKey, type FieldDef, type LocaleValue } from './content-model';

// =========================================================
// FormData → fila de la base, validada contra el modelo de contenido.
// Función pura (sin red, sin base) para poder testearla aislada.
// La base vuelve a validar con sus CHECK constraints: esto es para dar
// errores claros por campo antes de llegar ahí, no la única defensa.
// =========================================================

export type FieldErrorCode =
  | 'required'
  | 'too_long'
  | 'invalid_slug'
  | 'invalid_path'
  | 'invalid_option'
  | 'invalid_number'
  | 'out_of_range'
  | 'invalid_date'
  | 'invalid_email'
  | 'invalid_whatsapp'
  | 'invalid_image';

export type ParseResult =
  | { ok: true; values: Record<string, unknown> }
  | { ok: false; errors: Record<string, FieldErrorCode> };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Rutas que genera el propio uploader: "<carpeta>/<uuid>.<ext>"
const IMAGE_PATH = /^[a-z-]+\/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|avif)$/i;
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const WHATSAPP = /^[0-9]{8,15}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

function str(formData: FormData, key: string): string {
  const v = formData.get(key);
  return typeof v === 'string' ? v.trim() : '';
}

function lines(value: string): string[] {
  return value
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
}

function localeFrom(formData: FormData, name: string): LocaleValue {
  const out: LocaleValue = {};
  const en = str(formData, `${name}.en`);
  const es = str(formData, `${name}.es`);
  if (en) out.en = en;
  if (es) out.es = es;
  return out;
}

export function parseEntityForm(entity: EntityKey, formData: FormData): ParseResult {
  const def = ENTITIES[entity];
  const values: Record<string, unknown> = {};
  const errors: Record<string, FieldErrorCode> = {};

  for (const field of def.fields) {
    const result = parseField(field, formData);
    if ('error' in result) errors[field.name] = result.error;
    else values[field.name] = result.value;
  }

  // Reglas que dependen de un campo concreto, no del tipo.
  if (entity === 'settings') {
    const email = values.email as string | null;
    if (email && !EMAIL.test(email)) errors.email = 'invalid_email';
    const wa = values.whatsapp as string | null;
    if (wa && !WHATSAPP.test(wa)) errors.whatsapp = 'invalid_whatsapp';
  }
  if (entity === 'testimonials') {
    const rating = values.rating as number | null;
    if (rating != null && (rating < 1 || rating > 5)) errors.rating = 'out_of_range';
  }

  return Object.keys(errors).length ? { ok: false, errors } : { ok: true, values };
}

function parseField(field: FieldDef, formData: FormData): { value: unknown } | { error: FieldErrorCode } {
  const { name, type, required, max } = field;

  switch (type) {
    case 'text':
    case 'slug':
    case 'path': {
      // Las rutas y slugs se normalizan a minúsculas y sin "/" sobrantes
      // para que el usuario no tenga que adivinar el formato exacto.
      let v = str(formData, name);
      if (type !== 'text') v = v.toLowerCase().replace(/^\/+|\/+$/g, '');
      if (!v) return required ? { error: 'required' } : { value: null };
      if (max && v.length > max) return { error: 'too_long' };
      if (type === 'slug' && !SLUG_PATTERN.test(v)) return { error: 'invalid_slug' };
      if (type === 'path' && !PATH_PATTERN.test(v)) return { error: 'invalid_path' };
      return { value: v };
    }

    case 'localeText':
    case 'localeTextarea': {
      const v = localeFrom(formData, name);
      // El inglés es el idioma principal del sitio: obligatorio si el
      // campo es requerido. El español es siempre opcional.
      if (required && !v.en) return { error: 'required' };
      if (max && ((v.en?.length ?? 0) > max || (v.es?.length ?? 0) > max)) return { error: 'too_long' };
      return { value: v };
    }

    case 'localeList': {
      const en = lines(str(formData, `${name}.en`));
      const es = lines(str(formData, `${name}.es`));
      const n = Math.max(en.length, es.length);
      const items: LocaleValue[] = [];
      for (let i = 0; i < n; i++) {
        const item: LocaleValue = {};
        if (en[i]) item.en = en[i];
        if (es[i]) item.es = es[i];
        if (max && ((item.en?.length ?? 0) > max || (item.es?.length ?? 0) > max)) return { error: 'too_long' };
        items.push(item);
      }
      if (required && items.length === 0) return { error: 'required' };
      return { value: items };
    }

    case 'textList': {
      const items = lines(str(formData, name));
      if (max && items.some((i) => i.length > max)) return { error: 'too_long' };
      if (required && items.length === 0) return { error: 'required' };
      return { value: items };
    }

    case 'image': {
      const v = str(formData, name);
      if (!v) return required ? { error: 'required' } : { value: null };
      // Solo se aceptan rutas que generó el uploader del editor: nunca
      // una URL externa arbitraria ni "../" que apunte a otro bucket.
      if (!IMAGE_PATH.test(v)) return { error: 'invalid_image' };
      return { value: v };
    }

    case 'select': {
      const v = str(formData, name);
      if (!v) return required ? { error: 'required' } : { value: null };
      if (!field.options?.includes(v)) return { error: 'invalid_option' };
      return { value: v };
    }

    case 'reference': {
      const v = str(formData, name);
      if (!v) return required ? { error: 'required' } : { value: null };
      if (!UUID.test(v)) return { error: 'invalid_option' };
      return { value: v };
    }

    case 'boolean':
      return { value: formData.get(name) === 'on' || formData.get(name) === 'true' };

    case 'number': {
      const raw = str(formData, name);
      if (!raw) return required ? { error: 'required' } : { value: null };
      if (!/^-?\d+$/.test(raw)) return { error: 'invalid_number' };
      const n = Number(raw);
      if (field.min != null && n < field.min) return { error: 'out_of_range' };
      return { value: n };
    }

    case 'date': {
      const v = str(formData, name);
      if (!v) return required ? { error: 'required' } : { value: null };
      if (!DATE.test(v) || Number.isNaN(Date.parse(v))) return { error: 'invalid_date' };
      return { value: v };
    }
  }
}

/** Convierte un texto libre en un slug válido (para sugerirlo al crear). */
export function slugify(input: string): string {
  return input
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}
