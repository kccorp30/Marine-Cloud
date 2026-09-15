import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { acceptServiceRequest, declineServiceRequest, convertServiceRequest } from '@/lib/service-requests/actions';
import { Card, PageTitle } from '@/components/ui/primitives';

interface ServiceRequestRow {
  id: string;
  title: string;
  description: string | null;
  service_category: string | null;
  urgency: string;
  status: string;
  created_at: string;
  customer: { first_name: string; last_name: string } | { first_name: string; last_name: string }[] | null;
  vessel: { name: string | null } | { name: string | null }[] | null;
}

// RLS (staff_review_service_requests / read_service_requests) es lo
// que realmente restringe esto a staff/kcc_admin — un customer que
// intentara entrar acá no vería ninguna fila de otro, y esta página
// no está en su nav.
export default async function ServiceRequestsPage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const supabase = await createClient();

  const { data: requests } = await supabase
    .from('service_requests')
    .select('id, title, description, service_category, urgency, status, created_at, customer:customers(first_name, last_name), vessel:vessels(name)')
    .eq('organization_id', activeOrgId)
    .in('status', ['submitted', 'under_review', 'accepted'])
    .order('created_at', { ascending: false })
    .returns<ServiceRequestRow[]>();

  return (
    <div className="max-w-3xl">
      <PageTitle>Service Requests</PageTitle>
      <div className="space-y-3">
        {(requests ?? []).map((r) => {
          const customer = Array.isArray(r.customer) ? r.customer[0] : r.customer;
          const vessel = Array.isArray(r.vessel) ? r.vessel[0] : r.vessel;
          return (
            <Card key={r.id}>
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="text-sm font-semibold">{r.title}</div>
                  <div className="text-xs text-cool-gray mt-0.5">
                    {customer ? `${customer.first_name} ${customer.last_name}` : '—'} · {vessel?.name || 'Unnamed Vessel'}
                    {r.service_category && ` · ${r.service_category}`}
                  </div>
                  {r.description && <p className="text-xs text-cool-gray mt-2">{r.description}</p>}
                </div>
                <span className="font-mono text-[9px] uppercase tracking-[0.06em] text-gold whitespace-nowrap">{r.urgency}</span>
              </div>

              <div className="flex flex-wrap gap-2 mt-4">
                {r.status !== 'accepted' && (
                  <form action={acceptServiceRequest.bind(null, r.id)}>
                    <button type="submit" className="text-[10px] font-mono uppercase tracking-[0.06em] border border-white/15 px-3 py-1.5 rounded-sm hover:border-gold">
                      Accept
                    </button>
                  </form>
                )}
                <form action={convertServiceRequest.bind(null, r.id)}>
                  <button type="submit" className="text-[10px] font-mono uppercase tracking-[0.06em] bg-gold text-navy px-3 py-1.5 rounded-sm">
                    Convert to Work Order
                  </button>
                </form>
                <form action={declineServiceRequest} className="flex items-center gap-2">
                  <input type="hidden" name="requestId" value={r.id} />
                  <input name="reason" placeholder="Reason (optional)" className="text-[11px] bg-white/[0.04] border border-white/10 px-2 py-1.5 rounded-sm" />
                  <button type="submit" className="text-[10px] font-mono uppercase tracking-[0.06em] border border-red-500/30 text-red-400 px-3 py-1.5 rounded-sm">
                    Decline
                  </button>
                </form>
              </div>
            </Card>
          );
        })}
        {(!requests || requests.length === 0) && <p className="text-sm text-cool-gray">No pending service requests.</p>}
      </div>
    </div>
  );
}
