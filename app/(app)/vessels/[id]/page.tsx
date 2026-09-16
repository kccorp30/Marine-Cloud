import {SmartProfile} from '@/components/smart/Profile';
import {Drawer} from '@/components/smart/Drawer';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { Card, PageTitle, StatusBadge } from '@/components/ui/primitives';
import { RelativeTime } from '@/components/work-orders/Timeline';

interface VesselDetail {
  id: string;
  name: string | null;
  hin: string | null;
  make: string | null;
  model: string | null;
  year: number | null;
  vessel_type: string | null;
  length: number | null;
  marina: string | null;
  status: string;
  customer: { first_name: string; last_name: string } | { first_name: string; last_name: string }[] | null;
}

interface VesselSystem {
  id: string;
  system_type: string;
  manufacturer: string | null;
  model: string | null;
}

interface VesselWorkOrder {
  id: string;
  title: string;
  current_status: string;
  last_activity_at: string | null;
  created_at: string;
}

// Antes no existía — la lista de vessels no tenía a dónde llevar al
// hacer click, para NINGÚN rol (no era un gap solo de customer). RLS
// ya resuelve qué tanto puede ver cada uno; esta página no agrega
// ninguna lógica de rol propia — el botón de Request Service es
// visible para cualquiera (staff/kcc_admin nunca lo van a usar
// realmente porque no tienen un customer propio, pero no hace daño
// mostrarlo, y evita tener que ramificar por rol acá también).
export default async function VesselDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const isCustomer = session.memberships.find((m) => m.organization_id === activeOrgId)?.role === 'customer';

  const { data: vessel } = await supabase
    .from('vessels')
    .select('id, name, hin, make, model, year, vessel_type, length, marina, status, customer:customers(first_name, last_name)')
    .eq('id', id)
    .maybeSingle<VesselDetail>();

  if (!vessel) notFound(); // RLS ya filtró — sin distinguir "no existe" de "no autorizado"

  const { data: systems } = await supabase
    .from('vessel_systems')
    .select('id, system_type, manufacturer, model, status')
    .eq('vessel_id', id)
    .order('system_type')
    .returns<VesselSystem[]>();

  const { data: workOrders } = await supabase
    .from('work_orders')
    .select('id, title, current_status, last_activity_at, created_at')
    .eq('vessel_id', id)
    .order('created_at', { ascending: false })
    .returns<VesselWorkOrder[]>();

  const customerRecord = Array.isArray(vessel.customer) ? vessel.customer[0] : vessel.customer;
  const customerName = customerRecord ? `${customerRecord.first_name} ${customerRecord.last_name}` : null;

  return (
    <div className="max-w-6xl">
      <div className="flex items-start justify-between gap-4 mb-1">
        <PageTitle>{vessel.name || `${vessel.make ?? ''} ${vessel.model ?? ''}`.trim() || 'Unnamed Vessel'}</PageTitle>
        {isCustomer && (
          <Link href={`/request-service?vesselId=${vessel.id}`}>
            <span className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold border border-gold-dim px-3 py-1.5 rounded-sm whitespace-nowrap inline-block">
              Request Service
            </span>
          </Link>
        )}
      </div>
      <p className="text-xs text-cool-gray mb-8">
        {[vessel.make, vessel.model, vessel.year].filter(Boolean).join(' · ') || 'No make/model on file'}
        {customerName && ` · ${customerName}`}
      </p>

      <SmartProfile name={vessel.name||[vessel.make,vessel.model].filter(Boolean).join(" ")||"—"} subtitle="Vessel Passport"><p>{customerName}</p><p translate="no">{vessel.hin}</p><p>{vessel.marina}</p></SmartProfile>
      <Card className="my-6">
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Vessel Details</div>
        <dl className="grid grid-cols-2 gap-y-2 text-sm">
          {vessel.hin && (
            <>
              <dt className="text-cool-gray">HIN</dt>
              <dd>{vessel.hin}</dd>
            </>
          )}
          {vessel.vessel_type && (
            <>
              <dt className="text-cool-gray">Type</dt>
              <dd className="capitalize">{vessel.vessel_type}</dd>
            </>
          )}
          {vessel.length && (
            <>
              <dt className="text-cool-gray">Length</dt>
              <dd>{vessel.length} ft</dd>
            </>
          )}
          {vessel.marina && (
            <>
              <dt className="text-cool-gray">Marina</dt>
              <dd>{vessel.marina}</dd>
            </>
          )}
          <dt className="text-cool-gray">Status</dt>
          <dd className="capitalize">{vessel.status}</dd>
        </dl>
      </Card>

      {systems && systems.length > 0 && (
        <Card className="mb-6">
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Systems</div>
          <div className="space-y-3">
            {systems.map((s) => (
              <div key={s.id} className="flex items-center justify-between text-sm"><Drawer label={s.system_type.replace(/_/g," ")} title={[s.manufacturer,s.model].filter(Boolean).join(" ")||s.system_type}><p>{[s.manufacturer,s.model].filter(Boolean).join(" ")||"—"}</p></Drawer>
                <span className="capitalize">{s.system_type.replace(/_/g, ' ')}</span>
                <span className="text-cool-gray text-xs">{[s.manufacturer, s.model].filter(Boolean).join(' ') || '—'}</span>
              </div>
            ))}
          </div>
        </Card>
      )}

      <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Service History</div>
      <div className="space-y-2">
        {(workOrders ?? []).map((wo) => (
          <Link key={wo.id} href={`/work-orders/${wo.id}`}>
            <Card className="flex items-center justify-between hover:border-gold/40 transition-colors">
              <div className="text-sm font-semibold">{wo.title}</div>
              <div className="text-right">
                <StatusBadge status={wo.current_status} />
                <div className="mt-1">
                  <RelativeTime date={wo.last_activity_at ?? wo.created_at} />
                </div>
              </div>
            </Card>
          </Link>
        ))}
        {(!workOrders || workOrders.length === 0) && <p className="text-sm text-cool-gray">No service history yet.</p>}
      </div>
    </div>
  );
}
