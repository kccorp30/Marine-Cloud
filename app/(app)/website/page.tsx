import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getLocale } from '@/lib/i18n/server';
import { workspaceCopy } from '@/lib/i18n/workspace-copy';
import { PageTitle } from '@/components/ui/primitives';
import { getWebsiteOverview, getWebsiteUrl } from '@/lib/website/data';
import { LIST_ENTITIES } from '@/lib/website/content-model';

export default async function WebsiteStudioPage() {
  const session = await getSessionContext();
  if (!session.isKccAdmin) redirect('/dashboard');

  const locale = await getLocale();
  const t = workspaceCopy[locale] as Record<string, string>;
  const [overview, siteUrl] = await Promise.all([getWebsiteOverview(), Promise.resolve(getWebsiteUrl())]);

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <PageTitle>{t['website.title']}</PageTitle>
          <p className="-mt-4 max-w-2xl text-sm text-cool-gray">{t['website.subtitle']}</p>
        </div>
        {siteUrl && (
          <a href={siteUrl} target="_blank" rel="noreferrer" className="command-button">
            {t['website.action.openSite']} ↗
          </a>
        )}
      </div>

      {!overview.ready && (
        <div role="status" className="rounded-xl border border-amber-400/30 bg-amber-400/5 p-5 text-sm text-amber-100">
          <p className="font-semibold">{t['website.notReady.title']}</p>
          <p className="mt-1 text-amber-100/80">{t['website.notReady.detail']}</p>
        </div>
      )}

      {/* Leads — la razón de ser del sitio */}
      <section className="grid gap-4 md:grid-cols-3">
        <div className="premium-card rounded-xl p-5">
          <p className="command-kicker">{t['website.leads.last30']}</p>
          <p className="mt-2 font-display text-4xl font-bold text-gold">{overview.leads.last30}</p>
        </div>
        <Link href="/website-leads?status=needs_routing" className="premium-card rounded-xl p-5 hover:border-gold/40">
          <p className="command-kicker">{t['website.leads.needsRouting']}</p>
          <p className="mt-2 font-display text-4xl font-bold text-marine-white">{overview.leads.needsRouting}</p>
          <p className="mt-2 text-xs text-gold">{t['website.leads.open']} →</p>
        </Link>
        <div className="premium-card rounded-xl p-5">
          <p className="command-kicker">{t['website.leads.byCampaign']}</p>
          {overview.leads.byCampaign.length === 0 ? (
            <p className="mt-3 text-xs text-cool-gray">{t['website.leads.none']}</p>
          ) : (
            <ul className="mt-3 space-y-1.5 text-sm">
              {overview.leads.byCampaign.map((c) => (
                <li key={c.campaign || '__direct'} className="flex justify-between gap-3">
                  <span className="truncate">{c.campaign || t['website.leads.direct']}</span>
                  <span className="font-mono text-gold">{c.count}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </section>

      {/* Contenido */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <Link href="/website/settings" className="premium-card rounded-xl p-5 hover:border-gold/40">
          <p className="font-display text-lg font-semibold">{t['website.entity.settings']}</p>
          <p className="mt-1 text-xs text-cool-gray">{t['website.entityHelp.settings']}</p>
        </Link>
        {LIST_ENTITIES.map((key) => (
          <Link key={key} href={`/website/${key}`} className="premium-card rounded-xl p-5 hover:border-gold/40">
            <p className="font-display text-lg font-semibold">{t[`website.entity.${key}`]}</p>
            <p className="mt-1 text-xs text-cool-gray">{t[`website.entityHelp.${key}`]}</p>
            <p className="mt-4 font-mono text-[10px] uppercase tracking-wider text-cool-gray">
              <span className="text-emerald-300">
                {overview.counts[key].published} {t['website.status.published']}
              </span>
              {' · '}
              {overview.counts[key].draft} {t['website.status.draft']}
            </p>
          </Link>
        ))}
      </section>
    </div>
  );
}
