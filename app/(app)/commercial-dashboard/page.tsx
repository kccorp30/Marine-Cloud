import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getSessionContext } from '@/lib/auth/session';
import { getCommercialDashboardData } from '@/lib/kcc-control/commercial-dashboard-data';
import { PageTitle, Card } from '@/components/ui/primitives';

const STATUS_LABEL: Record<string, string> = {
  trialing: 'Active Trials',
  active: 'Active Subscriptions',
  trial_expired: 'Trial Expired',
  grace_period: 'Grace Period',
  past_due: 'Past Due',
  cancelled: 'Cancelled',
  complimentary: 'Complimentary',
  archived: 'Archived Companies',
};

export default async function CommercialDashboardPage() {
  const session = await getSessionContext();
  if (!session.isKccAdmin) redirect('/dashboard');

  const data = await getCommercialDashboardData();
  const needsAttention = data.counts.trial_expired + data.counts.past_due + data.trialsExpiringSoon.length;

  return (
    <div className="max-w-2xl space-y-6">
      <PageTitle>Commercial Dashboard</PageTitle>

      <Card>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-2">Contracted Recurring Value</div>
        <div className="text-2xl font-medium">
          {data.currency} {data.contractedRecurringWeeklyEquivalent.toLocaleString()} / week (equivalent)
        </div>
        <p className="text-[10px] text-cool-gray mt-1">
          Normalized across billing cycles (monthly ÷ 4.345, annual ÷ 52.14 weeks) — not a sum of raw prices. Excludes complimentary, cancelled, archived, and trialing accounts. This is
          contracted value, not collected revenue — no payment provider exists yet in Phase 14.
        </p>
      </Card>

      {needsAttention > 0 && (
        <Card className="border-amber-500/30">
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-amber-400 mb-2">Commercial Attention Required ({needsAttention})</div>
          <p className="text-xs text-cool-gray">{data.counts.trial_expired} trial(s) expired, {data.counts.past_due} past due, {data.trialsExpiringSoon.length} trial(s) expiring within 7 days.</p>
        </Card>
      )}

      <Card>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Subscription Status</div>
        <div className="grid grid-cols-2 gap-3">
          {Object.entries(STATUS_LABEL).map(([key, label]) => (
            <div key={key} className="text-sm">
              <span className="text-cool-gray">{label}:</span> <span className="font-medium">{data.counts[key] ?? 0}</span>
            </div>
          ))}
        </div>
      </Card>

      {data.trialsExpiringSoon.length > 0 && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Trials Expiring Soon</div>
          <div className="space-y-2">
            {data.trialsExpiringSoon.map((t) => (
              <Link key={t.organizationId} href={`/companies/${t.organizationId}`} className="block text-sm hover:text-gold">
                {t.organizationName} — {t.daysLeft} day(s) left
              </Link>
            ))}
          </div>
        </Card>
      )}

      <Card>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Plan Distribution</div>
        <div className="space-y-2">
          {data.planDistribution.map((p) => (
            <div key={p.planName} className="text-sm">
              <div className="flex justify-between">
                <span>{p.planName}</span>
                <span className="text-cool-gray">{p.active + p.trialing + p.complimentary + p.inactiveOrCancelled} total</span>
              </div>
              <div className="text-[10px] text-cool-gray">
                {p.active} active · {p.trialing} trialing · {p.complimentary} complimentary · {p.inactiveOrCancelled} inactive/cancelled
              </div>
            </div>
          ))}
          {data.planDistribution.length === 0 && <p className="text-sm text-cool-gray">No active subscriptions yet.</p>}
        </div>
      </Card>
    </div>
  );
}
