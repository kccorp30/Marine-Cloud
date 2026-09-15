import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getWarrantyQueue, getClaimsQueue } from '@/lib/warranty/queue-data';
import { formatCalendarDate } from '@/lib/warranty/format-calendar-date';
import { PageTitle, Card } from '@/components/ui/primitives';

export default async function WarrantyQueuePage({ searchParams }: { searchParams: Promise<{ tab?: string; status?: string }> }) {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const activeMembership = session.memberships.find((m) => m.organization_id === activeOrgId);
  const actorRole = session.isKccAdmin ? 'kcc_admin' : activeMembership?.role;

  // Solo staff con autoridad operativa (nunca customer/technician) —
  // mismo patrón de gateo ya usado en website-leads y companies.
  if (!session.isKccAdmin && !['company_owner', 'company_admin', 'manager'].includes(actorRole ?? '')) {
    redirect('/dashboard');
  }

  const { tab, status } = await searchParams;
  const activeTab = tab === 'claims' ? 'claims' : 'warranties';

  // KCC Admin ve cross-organización (autoridad de plataforma ya
  // existente) — staff de organización ve solo la suya, RLS lo
  // refuerza igual en la capa de datos.
  const orgFilter = session.isKccAdmin ? undefined : activeOrgId;

  const [warranties, claims] = await Promise.all([
    activeTab === 'warranties' ? getWarrantyQueue({ status, organizationId: orgFilter ?? undefined }) : Promise.resolve([]),
    activeTab === 'claims' ? getClaimsQueue({ status }) : Promise.resolve([]),
  ]);

  return (
    <div className="max-w-2xl space-y-6">
      <PageTitle>Warranty & Claims</PageTitle>

      <div className="flex gap-3 text-[10px] font-mono uppercase">
        <Link href="/warranty" className={activeTab === 'warranties' ? 'text-gold' : 'text-cool-gray'}>
          Warranties
        </Link>
        <Link href="/warranty?tab=claims" className={activeTab === 'claims' ? 'text-gold' : 'text-cool-gray'}>
          Claims
        </Link>
      </div>

      {activeTab === 'warranties' && (
        <div className="flex gap-3 flex-wrap text-[10px] font-mono uppercase">
          <Link href="/warranty" className={!status ? 'text-gold' : 'text-cool-gray'}>
            All
          </Link>
          <Link href="/warranty?status=active" className={status === 'active' ? 'text-gold' : 'text-cool-gray'}>
            Active
          </Link>
          <Link href="/warranty?status=expired" className={status === 'expired' ? 'text-gold' : 'text-cool-gray'}>
            Expired
          </Link>
          <Link href="/warranty?status=voided" className={status === 'voided' ? 'text-gold' : 'text-cool-gray'}>
            Voided
          </Link>
        </div>
      )}

      {activeTab === 'claims' && (
        <div className="flex gap-3 flex-wrap text-[10px] font-mono uppercase">
          <Link href="/warranty?tab=claims" className={!status ? 'text-gold' : 'text-cool-gray'}>
            All
          </Link>
          <Link href="/warranty?tab=claims&status=submitted" className={status === 'submitted' ? 'text-gold' : 'text-cool-gray'}>
            Submitted
          </Link>
          <Link href="/warranty?tab=claims&status=under_review" className={status === 'under_review' ? 'text-gold' : 'text-cool-gray'}>
            Under Review
          </Link>
          <Link href="/warranty?tab=claims&status=approved" className={status === 'approved' ? 'text-gold' : 'text-cool-gray'}>
            Approved
          </Link>
          <Link href="/warranty?tab=claims&status=rejected" className={status === 'rejected' ? 'text-gold' : 'text-cool-gray'}>
            Rejected
          </Link>
          <Link href="/warranty?tab=claims&status=in_progress" className={status === 'in_progress' ? 'text-gold' : 'text-cool-gray'}>
            In Progress
          </Link>
          <Link href="/warranty?tab=claims&status=resolved" className={status === 'resolved' ? 'text-gold' : 'text-cool-gray'}>
            Resolved
          </Link>
          <Link href="/warranty?tab=claims&status=cancelled" className={status === 'cancelled' ? 'text-gold' : 'text-cool-gray'}>
            Cancelled
          </Link>
        </div>
      )}

      <div className="space-y-2">
        {activeTab === 'warranties' &&
          warranties.map((w) => (
            <Card key={w.id}>
              <Link href={`/work-orders/${w.workOrderId}`} className="block space-y-1">
                <div className="flex items-center justify-between">
                  <span className="text-sm">{w.customerName ?? 'Unknown customer'}</span>
                  <span className="font-mono text-[9px] uppercase text-cool-gray">{w.effectiveStatus}</span>
                </div>
                <div className="text-xs text-cool-gray">
                  {w.vesselName} · {w.workOrderTitle}
                </div>
                {w.endsAt && <div className="text-xs text-cool-gray">Coverage ends {formatCalendarDate(w.endsAt)}</div>}
                {w.openClaimCount > 0 && <div className="text-xs text-gold">{w.openClaimCount} open claim(s)</div>}
              </Link>
            </Card>
          ))}
        {activeTab === 'warranties' && warranties.length === 0 && <p className="text-sm text-cool-gray">No warranties match this filter.</p>}

        {activeTab === 'claims' &&
          claims.map((c) => (
            <Card key={c.id}>
              <Link href={`/work-orders/${c.workOrderId}`} className="block space-y-1">
                <div className="flex items-center justify-between">
                  <span className="text-sm">{c.reason}</span>
                  <span className="font-mono text-[9px] uppercase text-cool-gray">{c.status.replace('_', ' ')}</span>
                </div>
                <div className="text-xs text-cool-gray">
                  {c.customerName} · {c.vesselName}
                </div>
                <div className="text-xs text-cool-gray">Submitted {new Date(c.submittedAt).toLocaleDateString()}</div>
              </Link>
            </Card>
          ))}
        {activeTab === 'claims' && claims.length === 0 && <p className="text-sm text-cool-gray">No claims match this filter.</p>}
      </div>
    </div>
  );
}
