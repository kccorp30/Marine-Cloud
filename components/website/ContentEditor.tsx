'use client';

import { useState } from 'react';
import { ActionForm } from '@/components/ui/ActionForm';
import { inputClass } from '@/components/ui/primitives';
import { useCommandCopy } from '@/components/ui/LocaleProvider';
import { workspaceCopy } from '@/lib/i18n/workspace-copy';
import { ENTITIES, type EntityKey, type FieldDef, type LocaleValue } from '@/lib/website/content-model';
import { slugify } from '@/lib/website/parse';
import { ImageField } from './ImageField';

// Formulario único del editor del sitio: se dibuja a partir del modelo
// de contenido. Ningún tipo de contenido tiene un formulario propio.

export interface ReferenceOptions {
  [entity: string]: { id: string; label: string; published: boolean }[];
}

const GROUP_ORDER: FieldDef['group'][] = ['main', 'sales', 'content', 'media', 'trust', 'contact', 'tracking', 'seo'];

export function ContentEditor({
  entity,
  row,
  references,
  action,
}: {
  entity: EntityKey;
  row: Record<string, any> | null;
  references: ReferenceOptions;
  action: (data: FormData) => Promise<{ error?: string; redirectTo?: string } | void>;
}) {
  const { locale } = useCommandCopy();
  const t = workspaceCopy[locale] as Record<string, string>;
  const def = ENTITIES[entity];
  const isNew = !row;

  // Sugerencia de slug a partir del título mientras el registro es
  // nuevo y el usuario no tocó el slug a mano.
  const [slugTouched, setSlugTouched] = useState(!isNew);
  const [slug, setSlug] = useState<string>(row?.slug ?? '');

  const groups = GROUP_ORDER.map((g) => ({ group: g, fields: def.fields.filter((f) => f.group === g) })).filter(
    (g) => g.fields.length > 0,
  );

  return (
    <ActionForm action={action} className="space-y-6">
      {groups.map(({ group, fields }) => (
        <section key={group} className="premium-card rounded-xl p-5 space-y-5">
          <h2 className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim">{t[`website.group.${group}`]}</h2>
          {fields.map((field) => (
            <FieldInput
              key={field.name}
              field={field}
              entity={entity}
              value={row?.[field.name]}
              t={t}
              references={references}
              slugState={
                field.type === 'slug'
                  ? { value: slug, onChange: (v) => { setSlug(v); setSlugTouched(true); } }
                  : undefined
              }
              onTitleChange={
                field.name === def.titleField && field.type === 'localeText' && !slugTouched && def.fields.some((f) => f.type === 'slug')
                  ? (en) => setSlug(slugify(en))
                  : undefined
              }
            />
          ))}
        </section>
      ))}

      <div className="sticky bottom-4 z-10 flex justify-end">
        <button type="submit" className="command-button shadow-2xl">
          {isNew ? t['website.action.createDraft'] : t['website.action.save']}
        </button>
      </div>
    </ActionForm>
  );
}

function FieldInput({
  field,
  entity,
  value,
  t,
  references,
  slugState,
  onTitleChange,
}: {
  field: FieldDef;
  entity: EntityKey;
  value: any;
  t: Record<string, string>;
  references: ReferenceOptions;
  slugState?: { value: string; onChange: (v: string) => void };
  onTitleChange?: (en: string) => void;
}) {
  const label = `${t[`website.field.${field.name}`] ?? field.name}${field.required ? ' *' : ''}`;
  const help = t[`website.help.${field.name}`];
  const id = `f-${field.name}`;

  const wrap = (control: React.ReactNode) => (
    <div>
      <label htmlFor={id} className="block font-mono text-[10px] uppercase tracking-[0.1em] text-cool-gray mb-1.5">
        {label}
      </label>
      {control}
      {help && <p className="mt-1.5 text-xs text-cool-gray/80 leading-relaxed">{help}</p>}
    </div>
  );

  switch (field.type) {
    case 'text':
      return wrap(<input id={id} name={field.name} defaultValue={value ?? ''} maxLength={field.max} className={inputClass} />);

    case 'slug':
    case 'path':
      return wrap(
        slugState ? (
          <input
            id={id}
            name={field.name}
            value={slugState.value}
            onChange={(e) => slugState.onChange(e.target.value)}
            maxLength={field.max}
            className={`${inputClass} font-mono`}
            autoCapitalize="none"
            spellCheck={false}
          />
        ) : (
          <input
            id={id}
            name={field.name}
            defaultValue={value ?? ''}
            maxLength={field.max}
            className={`${inputClass} font-mono`}
            autoCapitalize="none"
            spellCheck={false}
          />
        ),
      );

    case 'localeText':
    case 'localeTextarea': {
      const v = (value ?? {}) as LocaleValue;
      const Multi = field.type === 'localeTextarea';
      return wrap(
        <div className="grid gap-3 md:grid-cols-2">
          {(['en', 'es'] as const).map((lang) => (
            <div key={lang}>
              <span className="mb-1 block text-[10px] text-cool-gray/70">{t[`website.lang.${lang}`]}</span>
              {Multi ? (
                <textarea
                  id={lang === 'en' ? id : undefined}
                  name={`${field.name}.${lang}`}
                  defaultValue={v[lang] ?? ''}
                  maxLength={field.max}
                  rows={field.max && field.max > 600 ? 8 : 4}
                  className={inputClass}
                />
              ) : (
                <input
                  id={lang === 'en' ? id : undefined}
                  name={`${field.name}.${lang}`}
                  defaultValue={v[lang] ?? ''}
                  maxLength={field.max}
                  className={inputClass}
                  onChange={lang === 'en' && onTitleChange ? (e) => onTitleChange(e.target.value) : undefined}
                />
              )}
            </div>
          ))}
        </div>,
      );
    }

    case 'localeList': {
      const items = (Array.isArray(value) ? value : []) as LocaleValue[];
      return wrap(
        <div className="grid gap-3 md:grid-cols-2">
          {(['en', 'es'] as const).map((lang) => (
            <div key={lang}>
              <span className="mb-1 block text-[10px] text-cool-gray/70">{t[`website.lang.${lang}`]}</span>
              <textarea
                id={lang === 'en' ? id : undefined}
                name={`${field.name}.${lang}`}
                defaultValue={items.map((i) => i[lang] ?? '').join('\n')}
                rows={5}
                className={inputClass}
                placeholder={t['website.placeholder.onePerLine']}
              />
            </div>
          ))}
        </div>,
      );
    }

    case 'textList':
      return wrap(
        <textarea
          id={id}
          name={field.name}
          defaultValue={(Array.isArray(value) ? value : []).join('\n')}
          rows={4}
          className={inputClass}
          placeholder={t['website.placeholder.onePerLine']}
        />,
      );

    case 'image':
      return wrap(
        <ImageField
          name={field.name}
          folder={entity}
          initialPath={value ?? null}
          labels={{
            upload: t['website.image.upload'],
            replace: t['website.image.replace'],
            remove: t['website.image.remove'],
            uploading: t['website.image.uploading'],
            tooLarge: t['website.image.tooLarge'],
            badType: t['website.image.badType'],
            failed: t['website.image.failed'],
            hint: t['website.image.hint'],
          }}
        />,
      );

    case 'select':
      return wrap(
        <select id={id} name={field.name} defaultValue={value ?? field.options?.[0] ?? ''} className={inputClass}>
          {field.options?.map((o) => (
            <option key={o} value={o}>
              {t[`website.option.${field.name}.${o}`] ?? o}
            </option>
          ))}
        </select>,
      );

    case 'reference': {
      const options = references[field.ref ?? ''] ?? [];
      return wrap(
        <select id={id} name={field.name} defaultValue={value ?? ''} className={inputClass}>
          <option value="">{t['website.option.none']}</option>
          {options.map((o) => (
            <option key={o.id} value={o.id}>
              {o.label}
              {o.published ? '' : ` (${t['website.status.draft']})`}
            </option>
          ))}
        </select>,
      );
    }

    case 'boolean':
      return (
        <label className="flex items-start gap-3 cursor-pointer">
          <input
            type="checkbox"
            name={field.name}
            defaultChecked={Boolean(value)}
            className="mt-1 h-4 w-4 accent-[#d6b467]"
          />
          <span>
            <span className="block text-sm text-marine-white">{t[`website.field.${field.name}`] ?? field.name}</span>
            {help && <span className="mt-1 block text-xs text-cool-gray/80 leading-relaxed">{help}</span>}
          </span>
        </label>
      );

    case 'number':
      return wrap(
        <input
          id={id}
          name={field.name}
          type="number"
          inputMode="numeric"
          min={field.min}
          step={1}
          defaultValue={value ?? ''}
          className={`${inputClass} max-w-[12rem]`}
        />,
      );

    case 'date':
      return wrap(<input id={id} name={field.name} type="date" defaultValue={value ?? ''} className={`${inputClass} max-w-[14rem]`} />);
  }
}
