import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getLocale } from '@/lib/i18n/server';
import { workspaceCopy } from '@/lib/i18n/workspace-copy';
import { PageTitle } from '@/components/ui/primitives';
import { ENTITIES, displayValue, isEntityKey } from '@/lib/website/content-model';
import { getEntity, getReferenceOptions, getWebsiteUrl } from '@/lib/website/data';
import { saveWebsiteContent } from '@/lib/website/actions';
import { ContentEditor } from '@/components/website/ContentEditor';
import { PublishControls } from '@/components/website/PublishControls';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function WebsiteEntityEditPage({ params }: { params: Promise<{ entity: string; id: string }> }) {
  const session = await getSessionContext();
  if (!session.isKccAdmin) redirect('/dashboard');

  const { entity, id } = await params;
  if (!isEntityKey(entity) || entity === 'settings') notFound();

  const isNew = id === 'new';
  if (!isNew && !UUID.test(id)) notFound();

  const locale = await getLocale();
  const t = workspaceCopy[locale] as Record<string, string>;
  const def = ENTITIES[entity];

  const [row, references] = await Promise.all([isNew ? Promise.resolve(null) : getEntity(entity, id), getReferenceOptions(locale)]);
  if (!isNew && !row) notFound();

  const siteUrl = getWebsiteUrl();
  const publicPath = row ? def.publicPath?.(row) ?? null : null;
  const title = row ? displayValue(row[def.titleField], locale) : t[`website.new.${entity}`];

  return (
    <div className="max-w-5xl space-y-6">
      <nav className="font-mono text-[10px] uppercase tracking-[0.12em] text-cool-gray">
        <Link href="/website" className="hover:text-gold">
          {t['website.title']}
        </Link>
        <span className="mx-2">/</span>
        <Link href={`/website/${entity}`} className="hover:text-gold">
          {t[`website.entity.${entity}`]}
        </Link>
        <span className="mx-2">/</span>
        <span className="text-marine-white">{isNew ? t['website.action.new'] : t['website.action.edit']}</span>
      </nav>

      <PageTitle>{title || '—'}</PageTitle>

      <div className="grid gap-6 lg:grid-cols-[1fr_18rem]">
        <ContentEditor
          entity={entity}
          row={row}
          references={references}
          action={saveWebsiteContent.bind(null, entity, isNew ? null : id)}
        />

        <aside className="space-y-4 lg:sticky lg:top-6 lg:self-start">
          {row ? (
            <PublishControls
              entity={entity}
              id={row.id}
              published={Boolean(row.published)}
              publicUrl={siteUrl && publicPath ? `${siteUrl}${publicPath}` : null}
            />
          ) : (
            <div className="premium-card rounded-xl p-5 text-xs text-cool-gray leading-relaxed">{t['website.publish.newHelp']}</div>
          )}
          {entity === 'testimonials' && (
            <div className="rounded-xl border border-gold/20 bg-gold/5 p-4 text-xs text-cool-gray leading-relaxed">
              {t['website.testimonials.policy']}
            </div>
          )}
          {entity === 'landing-pages' && (
            <div className="rounded-xl border border-gold/20 bg-gold/5 p-4 text-xs text-cool-gray leading-relaxed">
              {t['website.landing.adsHelp']}
            </div>
          )}
        </aside>
      </div>
    </div>
  );
}
