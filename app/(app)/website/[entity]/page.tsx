import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getLocale } from '@/lib/i18n/server';
import { workspaceCopy } from '@/lib/i18n/workspace-copy';
import { PageTitle, EmptyState } from '@/components/ui/primitives';
import { ENTITIES, displayValue, isEntityKey, siteMediaUrl } from '@/lib/website/content-model';
import { getReferenceOptions, getSiteSettings, getWebsiteUrl, listEntity } from '@/lib/website/data';
import { saveWebsiteContent } from '@/lib/website/actions';
import { ContentEditor } from '@/components/website/ContentEditor';

export default async function WebsiteEntityPage({ params }: { params: Promise<{ entity: string }> }) {
  const session = await getSessionContext();
  if (!session.isKccAdmin) redirect('/dashboard');

  const { entity } = await params;
  if (!isEntityKey(entity)) notFound();

  const locale = await getLocale();
  const t = workspaceCopy[locale] as Record<string, string>;
  const def = ENTITIES[entity];

  // ---------- Ajustes: una sola fila, se edita directo ----------
  if (entity === 'settings') {
    const [settings, references] = await Promise.all([getSiteSettings(), getReferenceOptions(locale)]);
    const siteUrl = getWebsiteUrl();
    return (
      <div className="max-w-4xl space-y-6">
        <Breadcrumb t={t} current={t['website.entity.settings']} />
        <div className="flex flex-wrap items-end justify-between gap-3">
          <PageTitle>{t['website.entity.settings']}</PageTitle>
          {siteUrl && (
            <a href={siteUrl} target="_blank" rel="noreferrer" className="text-sm text-gold">
              {t['website.action.viewOnSite']} ↗
            </a>
          )}
        </div>
        <p className="-mt-4 text-sm text-cool-gray">{t['website.entityHelp.settings']}</p>
        {settings ? (
          <ContentEditor
            entity="settings"
            row={settings}
            references={references}
            action={saveWebsiteContent.bind(null, 'settings', null)}
          />
        ) : (
          <EmptyState title={t['website.notReady.title']} detail={t['website.notReady.detail']} />
        )}
      </div>
    );
  }

  // ---------- Listas ----------
  const rows = await listEntity(entity);
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  const imageField = def.fields.find((f) => f.type === 'image')?.name;

  return (
    <div className="max-w-4xl space-y-6">
      <Breadcrumb t={t} current={t[`website.entity.${entity}`]} />
      <div className="flex flex-wrap items-end justify-between gap-3">
        <PageTitle>{t[`website.entity.${entity}`]}</PageTitle>
        <Link href={`/website/${entity}/new`} className="command-button">
          + {t[`website.new.${entity}`]}
        </Link>
      </div>
      <p className="-mt-4 text-sm text-cool-gray">{t[`website.entityHelp.${entity}`]}</p>

      {rows.length === 0 ? (
        <EmptyState
          title={t['website.empty.title']}
          detail={t[`website.empty.${entity}`]}
          action={
            <Link href={`/website/${entity}/new`} className="command-button">
              + {t[`website.new.${entity}`]}
            </Link>
          }
        />
      ) : (
        <ul className="space-y-3">
          {rows.map((row) => {
            const thumb = imageField ? siteMediaUrl(supabaseUrl, row[imageField]) : null;
            return (
              <li key={row.id}>
                <Link
                  href={`/website/${entity}/${row.id}`}
                  className="premium-card flex items-center gap-4 rounded-xl p-4 hover:border-gold/40"
                >
                  {thumb ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={thumb} alt="" className="h-14 w-20 shrink-0 rounded-md object-cover" />
                  ) : (
                    <span className="grid h-14 w-20 shrink-0 place-items-center rounded-md border border-white/10 text-cool-gray">
                      ◇
                    </span>
                  )}
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-medium">{displayValue(row[def.titleField], locale) || '—'}</span>
                    <span className="block truncate font-mono text-[10px] text-cool-gray">
                      {def.publicPath?.(row) ?? row.author_detail ?? ''}
                    </span>
                  </span>
                  <span
                    className={`shrink-0 rounded-full px-2.5 py-0.5 font-mono text-[9px] uppercase tracking-wider ${
                      row.published ? 'text-emerald-300 border border-emerald-300/30' : 'text-cool-gray border border-white/10'
                    }`}
                  >
                    {row.published ? t['website.status.published'] : t['website.status.draft']}
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function Breadcrumb({ t, current }: { t: Record<string, string>; current: string }) {
  return (
    <nav className="font-mono text-[10px] uppercase tracking-[0.12em] text-cool-gray">
      <Link href="/website" className="hover:text-gold">
        {t['website.title']}
      </Link>
      <span className="mx-2">/</span>
      <span className="text-marine-white">{current}</span>
    </nav>
  );
}
