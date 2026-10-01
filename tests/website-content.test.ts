import { describe, it, expect } from 'vitest';
import { ENTITIES, SERVICE_CATEGORIES, SERVICE_ICONS, siteMediaUrl, displayValue } from '@/lib/website/content-model';
import { parseEntityForm, slugify } from '@/lib/website/parse';
import { workspaceCopy } from '@/lib/i18n/workspace-copy';

function fd(entries: Record<string, string>) {
  const f = new FormData();
  for (const [k, v] of Object.entries(entries)) f.set(k, v);
  return f;
}

describe('website content parsing', () => {
  it('builds a localized service row and normalizes the slug', () => {
    const r = parseEntityForm(
      'services',
      fd({
        'title.en': 'Marine Electrical',
        'title.es': 'Electricidad marina',
        slug: '  Marine-Electrical ',
        category: 'electrical',
        icon: 'bolt',
        'benefits.en': 'Fewer breakdowns\nSafer wiring',
        'benefits.es': 'Menos fallas',
        featured: 'on',
        sort_order: '10',
      }),
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.values.title).toEqual({ en: 'Marine Electrical', es: 'Electricidad marina' });
    expect(r.values.slug).toBe('marine-electrical');
    // las listas se emparejan por línea; un idioma puede tener menos entradas
    expect(r.values.benefits).toEqual([{ en: 'Fewer breakdowns', es: 'Menos fallas' }, { en: 'Safer wiring' }]);
    expect(r.values.featured).toBe(true);
    expect(r.values.sort_order).toBe(10);
    expect(r.values.hero_image_path).toBeNull();
  });

  it('requires English for required localized fields (Spanish stays optional)', () => {
    const r = parseEntityForm('services', fd({ 'title.es': 'Solo español', slug: 'x', category: 'electrical', icon: 'bolt' }));
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.errors.title).toBe('required');
  });

  it('rejects slugs and landing paths that would break URLs', () => {
    const bad = parseEntityForm('services', fd({ 'title.en': 'A', slug: 'bad slug!', category: 'electrical', icon: 'bolt' }));
    expect(!bad.ok && bad.errors.slug).toBe('invalid_slug');

    const okPath = parseEntityForm('landing-pages', fd({ internal_name: 'FB Oct', path: '/Offers/Marine-Electrical/', 'headline.en': 'H' }));
    expect(okPath.ok && okPath.values.path).toBe('offers/marine-electrical');

    const badPath = parseEntityForm('landing-pages', fd({ internal_name: 'x', path: 'offers//double', 'headline.en': 'H' }));
    expect(!badPath.ok && badPath.errors.path).toBe('invalid_path');
  });

  it('only accepts image paths produced by the uploader (no external URLs, no traversal)', () => {
    const base = { 'title.en': 'A', slug: 'a', category: 'electrical', icon: 'bolt' };
    const good = parseEntityForm('services', fd({ ...base, hero_image_path: 'services/0b7a6f2e-1c2d-4e5f-8a9b-0c1d2e3f4a5b.jpg' }));
    expect(good.ok).toBe(true);
    for (const evil of ['https://evil.example/x.jpg', '../vessel-media/secret.jpg', 'services/../../x.jpg', 'services/not-a-uuid.jpg']) {
      const r = parseEntityForm('services', fd({ ...base, hero_image_path: evil }));
      expect(!r.ok && r.errors.hero_image_path).toBe('invalid_image');
    }
  });

  it('rejects options and references that are not in the model', () => {
    const r = parseEntityForm('services', fd({ 'title.en': 'A', slug: 'a', category: 'plumbing', icon: 'bolt' }));
    expect(!r.ok && r.errors.category).toBe('invalid_option');
    const ref = parseEntityForm('landing-pages', fd({ internal_name: 'x', path: 'a', 'headline.en': 'H', service_id: "1' or 1=1" }));
    expect(!ref.ok && ref.errors.service_id).toBe('invalid_option');
  });

  it('validates contact settings and never invents trust numbers', () => {
    const bad = parseEntityForm('settings', fd({ company_name: 'KCCORP', email: 'nope', whatsapp: '+1 305' }));
    expect(!bad.ok && bad.errors.email).toBe('invalid_email');
    expect(!bad.ok && bad.errors.whatsapp).toBe('invalid_whatsapp');

    const empty = parseEntityForm('settings', fd({ company_name: 'KCCORP' }));
    expect(empty.ok).toBe(true);
    if (!empty.ok) return;
    // vacío = oculto en el sitio, nunca un número por defecto
    expect(empty.values.years_in_business).toBeNull();
    expect(empty.values.jobs_completed).toBeNull();
  });

  it('keeps testimonial ratings within 1–5', () => {
    const r = parseEntityForm('testimonials', fd({ author_name: 'Ana', 'quote.en': 'Great', rating: '7' }));
    expect(!r.ok && r.errors.rating).toBe('out_of_range');
  });

  it('slugify produces valid slugs from Spanish titles', () => {
    expect(slugify('Mantenimiento Eléctrico de Embarcaciones')).toBe('mantenimiento-electrico-de-embarcaciones');
  });
});

describe('website helpers', () => {
  it('builds public media URLs only for the site-media bucket', () => {
    expect(siteMediaUrl('https://x.supabase.co/', 'services/a b.jpg')).toBe(
      'https://x.supabase.co/storage/v1/object/public/site-media/services/a%20b.jpg',
    );
    expect(siteMediaUrl('https://x.supabase.co', null)).toBeNull();
  });

  it('displayValue falls back to English when Spanish is missing', () => {
    expect(displayValue({ en: 'Hello' }, 'es')).toBe('Hello');
    expect(displayValue({ en: 'Hello', es: 'Hola' }, 'es')).toBe('Hola');
  });
});

describe('website editor i18n coverage', () => {
  // Cada etiqueta que dibuja el editor sale del diccionario. Si alguien
  // agrega un campo al modelo y olvida traducirlo, este test falla.
  const required: string[] = [];
  for (const def of Object.values(ENTITIES)) {
    required.push(`website.entity.${def.key}`);
    for (const f of def.fields) {
      required.push(`website.field.${f.name}`, `website.group.${f.group}`);
    }
  }
  for (const c of SERVICE_CATEGORIES) required.push(`website.option.category.${c}`);
  for (const i of SERVICE_ICONS) required.push(`website.option.icon.${i}`);
  for (const code of ['required', 'too_long', 'invalid_slug', 'invalid_path', 'invalid_option', 'invalid_number', 'out_of_range', 'invalid_date', 'invalid_email', 'invalid_whatsapp', 'invalid_image'])
    required.push(`website.validation.${code}`);

  for (const locale of ['en', 'es'] as const) {
    it(`has every editor label in ${locale}`, () => {
      const table = workspaceCopy[locale] as Record<string, string>;
      const missing = [...new Set(required)].filter((k) => !table[k]);
      expect(missing).toEqual([]);
    });
  }
});
