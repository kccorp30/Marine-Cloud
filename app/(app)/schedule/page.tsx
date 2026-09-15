import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { cancelAppointment, createScheduleAppointment } from '@/lib/work-orders/actions';
import { RescheduleControl } from '@/components/work-orders/RescheduleControl';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';

interface AppointmentRow {
  id: string;
  scheduled_start: string;
  status: string;
  work_order: { id: string; title: string; vessel: { name: string | null } | { name: string | null }[] | null; customer: { first_name: string; last_name: string } | { first_name: string; last_name: string }[] | null } | { id: string; title: string }[] | null;
}

function dayBounds(dateStr: string) {
  const start = new Date(dateStr + 'T00:00:00');
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return { start, end };
}

function fmtDateParam(d: Date) {
  return d.toISOString().slice(0, 10);
}

export default async function SchedulePage({ searchParams }: { searchParams: Promise<{ date?: string }> }) {
  const { date } = await searchParams;
  const targetDate = date || fmtDateParam(new Date());
  const { start, end } = dayBounds(targetDate);

  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);

  const supabase = await createClient();
  const { data: appointments } = await supabase
    .from('appointments')
    .select('id, scheduled_start, status, work_order:work_orders(id, title, vessel:vessels(name), customer:customers(first_name, last_name))')
    .eq('organization_id', activeOrgId)
    .gte('scheduled_start', start.toISOString())
    .lt('scheduled_start', end.toISOString())
    .order('scheduled_start')
    .returns<AppointmentRow[]>();

  // Técnico asignado por work order — consulta separada y mergeada
  // acá, ya que el embedding de PostgREST no filtra bien assignments
  // activas dentro del mismo select anidado.
  const workOrderIds = (appointments ?? [])
    .map((a) => (Array.isArray(a.work_order) ? a.work_order[0]?.id : a.work_order?.id))
    .filter((id): id is string => Boolean(id));
  const { data: activeAssignments } =
    workOrderIds.length > 0
      ? await supabase
          .from('assignments')
          .select('work_order_id, technician:profiles(full_name)')
          .in('work_order_id', workOrderIds)
          .eq('status', 'active')
      : { data: [] };
  const technicianByWorkOrder = new Map<string, string>();
  for (const a of activeAssignments ?? []) {
    const tech = Array.isArray(a.technician) ? a.technician[0] : a.technician;
    if (tech?.full_name) technicianByWorkOrder.set(a.work_order_id, tech.full_name);
  }

  // Work orders schedulables — mismo criterio "asignable" que ya usa
  // el dashboard de /company, para no ofrecer citas sobre trabajos ya
  // cerrados/cancelados.
  const { data: schedulableWorkOrders } = await supabase
    .from('work_orders')
    .select('id, title')
    .eq('organization_id', activeOrgId)
    .not('current_status', 'in', '(completed,cancelled,warranty)')
    .order('created_at', { ascending: false })
    .limit(50);

  const prevDate = new Date(start);
  prevDate.setDate(prevDate.getDate() - 1);
  const nextDate = new Date(start);
  nextDate.setDate(nextDate.getDate() + 1);

  return (
    <div className="max-w-2xl">
      <div className="flex items-center justify-between mb-1">
        <PageTitle>Schedule</PageTitle>
        <div className="flex items-center gap-3">
          <Link href={`/schedule?date=${fmtDateParam(prevDate)}`} className="text-cool-gray text-sm">
            ←
          </Link>
          <span className="text-sm font-mono">{start.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}</span>
          <Link href={`/schedule?date=${fmtDateParam(nextDate)}`} className="text-cool-gray text-sm">
            →
          </Link>
        </div>
      </div>
      {targetDate !== fmtDateParam(new Date()) && (
        <Link href="/schedule" className="text-[10px] font-mono uppercase text-gold">
          Jump to today
        </Link>
      )}

      <Card className="mt-6 mb-6">
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">New Appointment</div>
        <form action={createScheduleAppointment} className="flex gap-3 items-end flex-wrap">
          <div className="flex-1 min-w-[200px]">
            <Field label="Work Order">
              <select name="workOrderId" required className={inputClass}>
                <option value="">Select…</option>
                {(schedulableWorkOrders ?? []).map((wo) => (
                  <option key={wo.id} value={wo.id} className="bg-navy">
                    {wo.title}
                  </option>
                ))}
              </select>
            </Field>
          </div>
          <div className="min-w-[200px]">
            <Field label="Date & Time">
              <input name="scheduledStart" type="datetime-local" required className={inputClass} />
            </Field>
          </div>
          <div className="min-w-[140px]">
            <Field label="Purpose (optional)">
              <input name="purpose" className={inputClass} />
            </Field>
          </div>
          <SubmitButton>Schedule</SubmitButton>
        </form>
      </Card>

      <div className="space-y-2">
        {(appointments ?? []).map((a) => {
          const wo = Array.isArray(a.work_order) ? a.work_order[0] : a.work_order;
          const vessel = wo && 'vessel' in wo ? (Array.isArray(wo.vessel) ? wo.vessel[0] : wo.vessel) : null;
          const customer = wo && 'customer' in wo ? (Array.isArray(wo.customer) ? wo.customer[0] : wo.customer) : null;
          return (
            <Card key={a.id} className="flex items-center justify-between flex-wrap gap-2">
              <div>
                <span className="font-mono text-xs text-gold mr-3">
                  {new Date(a.scheduled_start).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })}
                </span>
                <Link href={wo ? `/work-orders/${wo.id}` : '#'} className="text-sm font-semibold hover:text-gold">
                  {wo?.title ?? 'Work Order'}
                </Link>
                <div className="text-xs text-cool-gray mt-0.5">
                  {vessel?.name ?? '—'} {customer && `· ${customer.first_name} ${customer.last_name}`}
                  {wo && technicianByWorkOrder.get(wo.id) && ` · ${technicianByWorkOrder.get(wo.id)}`}
                </div>
              </div>
              <div className="flex items-center gap-3">
                <span className="font-mono text-[9px] uppercase text-cool-gray">{a.status}</span>
                {a.status === 'scheduled' && (
                  <>
                    <RescheduleControl appointmentId={a.id} currentStart={a.scheduled_start} />
                    <form action={cancelAppointment.bind(null, a.id)}>
                      <button type="submit" className="text-[10px] font-mono uppercase text-red-400 hover:underline">
                        Cancel
                      </button>
                    </form>
                  </>
                )}
              </div>
            </Card>
          );
        })}
        {(!appointments || appointments.length === 0) && <p className="text-sm text-cool-gray">Nothing scheduled for this day.</p>}
      </div>
    </div>
  );
}
