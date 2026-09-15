import {SmartProfile,ContactActions} from '@/components/smart/Profile';
import {getLocale} from '@/lib/i18n/server';
import {workspaceCopy} from '@/lib/i18n/workspace-copy';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { assignTechnician, createAppointment } from '@/lib/work-orders/actions';
import { Card, PageTitle, Field, inputClass, SubmitButton, StatusBadge } from '@/components/ui/primitives';
import { TransitionButtons } from '@/components/work-orders/TransitionButtons';
import { TechnicianActionPanel } from '@/components/technician/TechnicianActionPanel';
import { RequestAssistanceButton } from '@/components/kcc-assistance/RequestAssistanceButton';
import { TechnicianTrackingControl } from '@/components/tracking/TechnicianTrackingControl';
import { TrackingStatusPanel } from '@/components/tracking/TrackingStatusPanel';
import { QcPanel } from '@/components/qc/QcPanel';
import { getQcSubmissionsForWorkOrder, getCanReviewQc, getWorkOrderMediaForQc } from '@/lib/qc/data';
import { WarrantyCard } from '@/components/warranty/WarrantyCard';
import { getWarrantyForWorkOrder } from '@/lib/warranty/data';
import { ActivateWarrantyButton } from '@/components/warranty/ActivateWarrantyButton';
import { Timeline } from '@/components/work-orders/Timeline';
import { getWorkOrderTimeline } from '@/lib/data/timeline';
import { CustomerTracking } from '@/components/work-orders/CustomerTracking';
import { getCustomerWorkOrderTracking } from '@/lib/work-orders/customer-tracking';
import { TrackingAutoRefresh } from '@/components/work-orders/TrackingAutoRefresh';
import { createDepositInvoiceAction, createInvoiceAction } from '@/lib/invoices/actions';

export default async function WorkOrderDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const locale=await getLocale();const copy=workspaceCopy[locale];
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const activeMembership = session.memberships.find((m) => m.organization_id === activeOrgId);
  const actorRole = session.isKccAdmin ? 'kcc_admin' : activeMembership?.role;
  const isStaff = actorRole ? ['kcc_admin', 'company_owner', 'company_admin', 'manager'].includes(actorRole) : false;

  const supabase = await createClient();

  const { data: wo } = await supabase
    .from('work_orders')
    .select('*, customer:customers(first_name, last_name, email, phone), vessel:vessels(name, hin, make, model)')
    .eq('id', id)
    .single();

  if (!wo) notFound();

  const [{ data: assignments }, { data: appointments }, { data: rules }, timeline, { data: activeCheckIns }] = await Promise.all([
    supabase
      .from('assignments')
      .select('id, status, role_on_job, technician_profile_id, technician:profiles(full_name,avatar_url,phone)')
      .eq('work_order_id', id)
      .eq('status', 'active'),
    supabase.from('appointments').select('id, scheduled_start, status, purpose').eq('work_order_id', id).order('scheduled_start'),
    supabase
      .from('work_order_transition_rules')
      .select('to_status, allowed_roles')
      .eq('from_status', wo.current_status)
      .eq('active', true),
    getWorkOrderTimeline(id),
    // Estado operativo REAL del técnico — derivado de un check-in sin
    // checkout, no una etiqueta decorativa. La ubicación (lat/lng)
    // solo existe mientras el check-in sigue activo — se deja de
    // mostrar apenas hace check-out (comportamiento de "location solo
    // en contexto de servicio activo" decidido en Phase 0).
    supabase.from('check_ins').select('technician_profile_id, checked_in_at, latitude, longitude').eq('work_order_id', id).is('checked_out_at', null),
  ]);

  // Solo se muestran los botones de transición que tu rol realmente
  // puede ejecutar — la función de la base rechaza igual si alguien
  // intenta forzar otra, esto es solo para no mostrar botones inútiles.
  const allowedTransitions = (rules ?? [])
    .filter((r: any) => actorRole && r.allowed_roles.includes(actorRole))
    .map((r: any) => r.to_status);

  const technicians = isStaff
    ? (
        await supabase
          .from('organization_memberships')
          .select('profile_id, profile:profiles(full_name)')
          .eq('organization_id', activeOrgId)
          .eq('role', 'technician')
          .eq('status', 'active')
      ).data
    : [];

  // Datos específicos del panel del técnico — solo se piden si el
  // actor es technician (evita queries innecesarias para staff/customer).
  const isTechnician = actorRole === 'technician';
  const isCustomer = actorRole === 'customer';
  const trackingData = isCustomer ? await getCustomerWorkOrderTracking(id) : null;

  // QC: solo se pide si el work order está en QC o ya tuvo actividad
  // — evita queries innecesarias para trabajos que nunca la usaron.
  const qcSubmissions = !isCustomer ? await getQcSubmissionsForWorkOrder(id) : [];
  const canReviewQc = !isCustomer && activeOrgId ? await getCanReviewQc(activeOrgId) : false;
  const qcAvailableMedia = !isCustomer && qcSubmissions.some((s) => s.status === 'draft') ? await getWorkOrderMediaForQc(id) : [];

  // Warranty: puede existir para cualquier rol que tenga acceso al
  // work order (RLS ya filtra qué customer puede verla).
  const warranty = await getWarrantyForWorkOrder(id);
  const canReviewWarrantyClaims = !isCustomer;

  // Default real de warranty desde service_catalog — nunca un valor
  // inventado. Casi siempre null hoy porque work_orders.service_id no
  // se popula todavía en ningún camino de creación real (documentado
  // en docs/PHASE-13-REPORT.md) — el staff sigue pudiendo activar con
  // términos explícitos.
  let warrantyServiceDefault: { durationDays: number; coverageNotes: string | null } | null = null;
  if (!warranty && wo.service_id) {
    const { data: svc } = await supabase.from('service_catalog').select('warranty_enabled, warranty_duration_days, warranty_coverage_notes').eq('id', wo.service_id).maybeSingle();
    if (svc?.warranty_enabled && svc.warranty_duration_days) {
      warrantyServiceDefault = { durationDays: svc.warranty_duration_days, coverageNotes: svc.warranty_coverage_notes };
    }
  }
  // Estimate accionable de este work order — cierra el gap real de
  // que el customer viera "esperando tu aprobación" en el tracking
  // sin ningún link para realmente revisar/aprobar. RLS ya filtra a
  // lo propio del customer.
  const actionableEstimate = isCustomer
    ? (
        await supabase
          .from('estimates')
          .select('id, estimate_number, current_version:estimate_versions!fk_estimates_current_version(total, status)')
          .eq('work_order_id', id)
          .in('status', ['sent', 'viewed'])
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle()
      ).data
    : null;
  let activeCheckInId: string | null = null;
  let activeTimeEntryId: string | null = null;
  let checklistItems: { id: string; label: string; response_type: string; completed: boolean }[] = [];
  const currentAppointmentId = appointments && appointments.length > 0 ? appointments[appointments.length - 1].id : null;

  if (isTechnician) {
    const [{ data: checkIn }, { data: timeEntry }, { data: templates }, { data: responses }] = await Promise.all([
      supabase
        .from('check_ins')
        .select('id')
        .eq('work_order_id', id)
        .eq('technician_profile_id', session.userId)
        .is('checked_out_at', null)
        .maybeSingle(),
      supabase
        .from('time_entries')
        .select('id')
        .eq('work_order_id', id)
        .eq('technician_profile_id', session.userId)
        .eq('status', 'active')
        .maybeSingle(),
      supabase
        .from('checklist_template_items')
        .select('id, label, response_type, template:checklist_templates(active)')
        .eq('organization_id', activeOrgId),
      supabase.from('checklist_responses').select('template_item_id').eq('work_order_id', id),
    ]);

    activeCheckInId = checkIn?.id ?? null;
    activeTimeEntryId = timeEntry?.id ?? null;

    const respondedIds = new Set((responses ?? []).map((r: any) => r.template_item_id));
    checklistItems = (templates ?? [])
      .filter((t: any) => t.template?.active)
      .map((t: any) => ({ id: t.id, label: t.label, response_type: t.response_type, completed: respondedIds.has(t.id) }));
  }

  let financialSummary: { authorized_total: number; invoiced_total: number; paid_total: number; remaining_invoiceable: number; deposit_required: boolean; deposit_amount: number; deposit_satisfied: boolean } | null = null;
  if (isStaff) {
    const { data } = await supabase.rpc('get_work_order_financial_summary', { p_work_order_id: id });
    financialSummary = data;
  }

  return (
    <div className="max-w-3xl">
      <div className="flex items-center justify-between mb-2">
        <PageTitle>{wo.title}</PageTitle>
        <StatusBadge status={wo.current_status} />
      </div>
      <p className="text-xs text-cool-gray mb-8">
        {wo.customer?.first_name} {wo.customer?.last_name} · {wo.vessel?.name || 'Unnamed Vessel'}
        {wo.vessel?.hin && ` · HIN ${wo.vessel.hin}`}
      </p>

      {wo.description && <Card className="mb-6">{wo.description}</Card>}

      {isStaff && financialSummary && financialSummary.authorized_total > 0 && (
        <Card className="mb-6">
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Financial Summary</div>
          <div className="grid grid-cols-2 gap-y-1 text-sm">
            <span className="text-cool-gray">Authorized</span>
            <span className="text-right font-mono">${financialSummary.authorized_total.toFixed(2)}</span>
            <span className="text-cool-gray">Invoiced</span>
            <span className="text-right font-mono">${financialSummary.invoiced_total.toFixed(2)}</span>
            <span className="text-cool-gray">Paid</span>
            <span className="text-right font-mono">${financialSummary.paid_total.toFixed(2)}</span>
            <span className="text-cool-gray">Remaining to Invoice</span>
            <span className="text-right font-mono">${financialSummary.remaining_invoiceable.toFixed(2)}</span>
            {financialSummary.deposit_required && (
              <>
                <span className="text-cool-gray">Deposit</span>
                <span className={`text-right font-mono ${financialSummary.deposit_satisfied ? 'text-emerald-400' : 'text-gold'}`}>
                  {financialSummary.deposit_satisfied ? 'Satisfied' : `$${financialSummary.deposit_amount.toFixed(2)} due`}
                </span>
              </>
            )}
          </div>
        </Card>
      )}

      {isStaff && financialSummary && financialSummary.remaining_invoiceable > 0 && (
        <Card className="mb-6">
          <div className="flex gap-3 flex-wrap">
            {financialSummary.deposit_required && (
              <form action={createDepositInvoiceAction.bind(null, id)}>
                <button type="submit" className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
                  Create Deposit Invoice
                </button>
              </form>
            )}
            <form action={createInvoiceAction}>
              <input type="hidden" name="workOrderId" value={id} />
              <input type="hidden" name="invoiceType" value="final" />
              <button type="submit" className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
                Invoice Remaining Balance
              </button>
            </form>
          </div>
        </Card>
      )}

      <div className="space-y-4 mb-6">{(assignments??[]).map((assignment:any)=>{const tech=Array.isArray(assignment.technician)?assignment.technician[0]:assignment.technician;return tech&&<SmartProfile key={assignment.id} name={tech.full_name||copy.technician} photo={tech.avatar_url} subtitle={copy.technician} status={<StatusBadge status={wo.current_status} locale={locale}/>}/>})}</div>
      {wo.customer&&<div className="mb-6"><ContactActions phone={wo.customer.phone} email={wo.customer.email} labels={copy}/></div>}
      {isTechnician && (
        <div className="mb-8">
          <TechnicianActionPanel
            workOrderId={wo.id}
            vesselId={wo.vessel_id}
            appointmentId={currentAppointmentId}
            currentStatus={wo.current_status}
            activeCheckInId={activeCheckInId}
            activeTimeEntryId={activeTimeEntryId}
            checklistItems={checklistItems}
          />
        </div>
      )}

      {isTechnician && (assignments ?? []).some((a: any) => a.technician_profile_id === session.userId) && (
        <Card className="mb-8">
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Need Help?</div>
          <RequestAssistanceButton workOrderId={wo.id} />
        </Card>
      )}

      {isTechnician && (assignments ?? []).some((a: any) => a.technician_profile_id === session.userId) && wo.current_status === 'en_route' && (
        <div className="mb-8">
          <TechnicianTrackingControl workOrderId={wo.id} canTrack />
        </div>
      )}

      {isCustomer && trackingData && (
        <>
          <CustomerTracking tracking={trackingData} />
          <TrackingAutoRefresh />
          {['technician_assigned','en_route','checked_in'].includes(wo.current_status) && (
            <Card className="mb-8">
              <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Technician Location</div>
              <TrackingStatusPanel workOrderId={wo.id} />
            </Card>
          )}
        </>
      )}

      {isCustomer && actionableEstimate && (
        <Link href={`/estimates/${actionableEstimate.id}`}>
          <Card className="border-gold bg-gold/[0.06] hover:bg-gold/[0.1] transition-colors mb-8 flex items-center justify-between">
            <div>
              <div className="font-mono text-[9px] uppercase tracking-[0.08em] text-gold mb-1">Estimate {actionableEstimate.estimate_number}</div>
              <div className="text-sm font-semibold">Ready for your review</div>
            </div>
            <span className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold whitespace-nowrap">Review Estimate →</span>
          </Card>
        </Link>
      )}

      {!isCustomer && ['technician_assigned','en_route','checked_in'].includes(wo.current_status) && (
        <Card className="mb-8">
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Technician Location</div>
          <TrackingStatusPanel workOrderId={wo.id} />
        </Card>
      )}

      {!isCustomer && (wo.current_status === 'quality_control' || qcSubmissions.length > 0) && (
        <Card className="mb-8">
          <QcPanel
            workOrderId={wo.id}
            submissions={qcSubmissions}
            canStart={isTechnician ? (assignments ?? []).some((a: any) => a.technician_profile_id === session.userId) : true}
            canReview={canReviewQc}
            availableMedia={qcAvailableMedia}
          />
        </Card>
      )}

      {warranty && (
        <Card className="mb-8">
          <WarrantyCard warranty={warranty} isCustomer={isCustomer} canReview={canReviewWarrantyClaims} />
        </Card>
      )}

      {!warranty && !isCustomer && (wo.current_status === 'completed' || wo.current_status === 'warranty') && (
        <Card className="mb-8">
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Warranty</div>
          <ActivateWarrantyButton workOrderId={wo.id} serviceDefault={warrantyServiceDefault} />
        </Card>
      )}

      {!isTechnician && allowedTransitions.length > 0 && (
        <div className="mb-8">
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Move Status</div>
          <TransitionButtons workOrderId={wo.id} allowedTransitions={allowedTransitions} />
        </div>
      )}

      {isStaff && (
        <Card className="mb-8">
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Assign Technician</div>
          <form action={assignTechnician} className="flex gap-3 items-end flex-wrap">
            <input type="hidden" name="workOrderId" value={wo.id} />
            <div className="flex-1 min-w-[180px]">
              <Field label="Technician">
                <select name="technicianProfileId" required className={inputClass}>
                  <option value="">Select…</option>
                  {(technicians ?? []).map((t: any) => (
                    <option key={t.profile_id} value={t.profile_id} className="bg-navy">
                      {t.profile?.full_name || t.profile_id}
                    </option>
                  ))}
                </select>
              </Field>
            </div>
            <SubmitButton>Assign</SubmitButton>
          </form>
        </Card>
      )}

      <Card className="mb-8">
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">{isCustomer ? 'Your Technician' : 'Assigned Technicians'}</div>
        {(assignments ?? []).length === 0 ? (
          <p className="text-xs text-cool-gray">No technician assigned yet.</p>
        ) : (
          <ul className="space-y-2">
            {assignments!.map((a: any) => {
              const activeCheckIn = (activeCheckIns ?? []).find((c: any) => c.technician_profile_id === a.technician_profile_id);
              return (
                <li key={a.id} className="text-sm flex items-center justify-between">
                  <span>
                    {a.technician?.full_name || 'Unknown'} {a.role_on_job && `— ${a.role_on_job}`}
                  </span>
                  {activeCheckIn ? (
                    <span className="font-mono text-[9px] uppercase tracking-[0.06em] text-gold border border-gold-dim px-2 py-0.5 rounded-sm">
                      On site
                      {isStaff && activeCheckIn.latitude != null && ` · ${activeCheckIn.latitude.toFixed(3)}, ${activeCheckIn.longitude.toFixed(3)}`}
                    </span>
                  ) : (
                    <span className="font-mono text-[9px] uppercase tracking-[0.06em] text-cool-gray">Off site</span>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </Card>

      {isStaff && (
        <Card className="mb-8">
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Schedule Visit</div>
          <form action={createAppointment} className="flex gap-3 items-end flex-wrap">
            <input type="hidden" name="workOrderId" value={wo.id} />
            <div className="flex-1 min-w-[200px]">
              <Field label="Scheduled Start">
                <input name="scheduledStart" type="datetime-local" required className={inputClass} />
              </Field>
            </div>
            <div className="flex-1 min-w-[160px]">
              <Field label="Purpose (optional)">
                <input name="purpose" className={inputClass} />
              </Field>
            </div>
            <SubmitButton>Schedule</SubmitButton>
          </form>
        </Card>
      )}

      <Card className="mb-8">
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">{isCustomer ? 'Scheduled Visit' : 'Visits'}</div>
        {(appointments ?? []).length === 0 ? (
          <p className="text-xs text-cool-gray">No visits scheduled.</p>
        ) : (
          <ul className="space-y-2">
            {appointments!.map((a: any) => (
              <li key={a.id} className="text-sm flex justify-between">
                <span>{new Date(a.scheduled_start).toLocaleString()}</span>
                <span className="text-cool-gray text-xs">{a.purpose || a.status}</span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Timeline entries={timeline} />
    </div>
  );
}
