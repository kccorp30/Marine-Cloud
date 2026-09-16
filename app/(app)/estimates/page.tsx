import {ActionForm} from '@/components/ui/ActionForm';
import Link from 'next/link';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { createClient } from '@/lib/supabase/server';
import { getEstimateList } from '@/lib/estimates/data';
import { createEstimate } from '@/lib/estimates/actions';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';

const STATUS_OPTIONS = ['draft', 'sent', 'viewed', 'approved', 'declined', 'expired', 'superseded', 'cancelled'];

const STATUS_COLOR: Record<string, string> = {
  draft: 'text-cool-gray',
  sent: 'text-gold',
  viewed: 'text-gold',
  approved: 'text-emerald-400',
  declined: 'text-red-400',
  expired: 'text-red-400',
  superseded: 'text-cool-gray/60',
  cancelled: 'text-cool-gray/60',
};

export default async function EstimatesListPage({ searchParams }: { searchParams: Promise<{ status?: string; type?: string; customer?:string; vessel?:string }> }) {
  const { status, type, customer, vessel } = await searchParams;
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const actorRole = session.memberships.find((m) => m.organization_id === activeOrgId)?.role;
  const isCustomer = actorRole === 'customer';
  const canCreate = ['company_owner', 'company_admin', 'manager', 'kcc_admin'].includes(actorRole ?? '');

  const estimates = await getEstimateList(activeOrgId!, { status, type });

  let customerVessels: { id: string; name: string | null; customer_id: string }[] = [];
  if (canCreate) {
    const supabase = await createClient();
    const { data } = await supabase.from('vessels').select('id, name, current_customer_id').eq('organization_id', activeOrgId).limit(200);
    customerVessels = (data ?? []).map((v: any) => ({ id: v.id, name: v.name, customer_id: v.current_customer_id }));
  }

  return (
    <div className="max-w-4xl space-y-8">
      <PageTitle>{isCustomer ? 'Estimates' : 'Estimates & Change Orders'}</PageTitle>

      {canCreate && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">New Estimate</div>
          <ActionForm action={createEstimate} className="flex gap-3 items-end flex-wrap">
            <div className="min-w-[220px]">
              <Field label="Vessel">
                <select name="vesselId" required className={inputClass} defaultValue={vessel && customerVessels.some(v=>v.id===vessel)?vessel:undefined}>
                  <option value="">Select…</option>
                  {customerVessels.filter(v=>!customer||v.customer_id===customer).map((v) => (
                    <option key={v.id} value={v.id} className="bg-navy">
                      {v.name ?? 'Unnamed Vessel'}
                    </option>
                  ))}
                </select>
              </Field>
            </div>
            <div className="flex-1 min-w-[200px]">
              <Field label="Title (optional)">
                <input name="title" className={inputClass} />
              </Field>
            </div>
            <SubmitButton>Create Draft</SubmitButton>
          </ActionForm>
        </Card>
      )}

      {!isCustomer && (
        <form method="GET" className="flex gap-3 flex-wrap items-end">
          <div className="min-w-[160px]">
            <Field label="Status">
              <select name="status" defaultValue={status ?? ''} className={inputClass}>
                <option value="">All</option>
                {STATUS_OPTIONS.map((s) => (
                  <option key={s} value={s} className="bg-navy">
                    {s}
                  </option>
                ))}
              </select>
            </Field>
          </div>
          <div className="min-w-[160px]">
            <Field label="Type">
              <select name="type" defaultValue={type ?? ''} className={inputClass}>
                <option value="">All</option>
                <option value="estimate" className="bg-navy">Estimates</option>
                <option value="change_order" className="bg-navy">Change Orders</option>
              </select>
            </Field>
          </div>
          <SubmitButton>Filter</SubmitButton>
          {(status || type) && (
            <Link href="/estimates" className="text-[10px] font-mono uppercase text-cool-gray hover:text-gold pb-2.5">
              Clear
            </Link>
          )}
        </form>
      )}

      <div className="space-y-2">
        {estimates.map((e) => (
          <Link key={e.id} href={`/estimates/${e.id}`}>
            <Card className="flex items-center justify-between flex-wrap gap-2 hover:border-gold/40 transition-colors">
              <div>
                <div className="text-sm font-semibold">
                  {e.estimateNumber} {e.type === 'change_order' && <span className="text-cool-gray font-normal">· Change Order</span>}
                </div>
                <div className="text-xs text-cool-gray mt-0.5">
                  {!isCustomer && e.customerName && `${e.customerName} · `}
                  {e.vesselName ?? '—'}
                </div>
              </div>
              <div className="text-right">
                <div className="text-sm font-mono">${e.total.toFixed(2)}</div>
                <span className={`font-mono text-[9px] uppercase ${STATUS_COLOR[e.status] ?? 'text-cool-gray'}`}>{e.status}</span>
              </div>
            </Card>
          </Link>
        ))}
        {estimates.length === 0 && <p className="text-sm text-cool-gray">No estimates yet.</p>}
      </div>
    </div>
  );
}
