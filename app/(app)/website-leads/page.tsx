import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getWebsiteLeads, getWebsiteLeadCounts, getActiveOrganizationsForRouting } from '@/lib/kcc-control/website-leads-data';
import { WebsiteLeadCard } from '@/components/kcc-control/WebsiteLeadCard';
import { PageTitle } from '@/components/ui/primitives';

export default async function WebsiteLeadsPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const session = await getSessionContext();
  if (!session.isKccAdmin) redirect('/dashboard');

  const { status } = await searchParams;
  const [leads, counts, organizations] = await Promise.all([
    getWebsiteLeads({ conversionStatus: status }),
    getWebsiteLeadCounts(),
    getActiveOrganizationsForRouting(),
  ]);

  return (
    <div className="max-w-2xl space-y-6">
      <PageTitle>Website Leads</PageTitle>

      <div className="flex gap-3 flex-wrap text-[10px] font-mono uppercase">
        <Link href="/website-leads" className={!status ? 'text-gold' : 'text-cool-gray'}>
          All ({Object.values(counts).reduce((a, b) => a + b, 0)})
        </Link>
        <Link href="/website-leads?status=needs_routing" className={status === 'needs_routing' ? 'text-gold' : 'text-cool-gray'}>
          Needs Routing ({counts.needs_routing ?? 0})
        </Link>
        <Link href="/website-leads?status=converted" className={status === 'converted' ? 'text-gold' : 'text-cool-gray'}>
          Converted ({counts.converted ?? 0})
        </Link>
        <Link href="/website-leads?status=failed" className={status === 'failed' ? 'text-gold' : 'text-cool-gray'}>
          Failed ({counts.failed ?? 0})
        </Link>
        <Link href="/website-leads?status=not_converted" className={status === 'not_converted' ? 'text-gold' : 'text-cool-gray'}>
          Pending ({counts.not_converted ?? 0})
        </Link>
      </div>

      <div className="space-y-2">
        {leads.map((lead) => (
          <WebsiteLeadCard key={lead.id} lead={lead} organizations={organizations} />
        ))}
        {leads.length === 0 && <p className="text-sm text-cool-gray">No website leads match this filter.</p>}
      </div>
    </div>
  );
}
