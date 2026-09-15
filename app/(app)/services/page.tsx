import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { createService } from '@/lib/services/actions';
import { ActiveToggle } from '@/components/services/ActiveToggle';
import { QcRequiredToggle } from '@/components/services/QcRequiredToggle';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';

interface ServiceRow {
  id: string;
  name: string;
  description: string | null;
  active: boolean;
  base_price: number | null;
  pricing_type: string | null;
  qc_required: boolean;
  warranty_enabled: boolean;
  warranty_duration_days: number | null;
}

export default async function ServicesPage() {
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const actorRole = session.memberships.find((m) => m.organization_id === activeOrgId)?.role;
  const canManage = actorRole === 'company_owner' || actorRole === 'company_admin' || actorRole === 'manager';

  const supabase = await createClient();
  const { data: services } = await supabase
    .from('service_catalog')
    .select('id, name, description, active, base_price, pricing_type, qc_required, warranty_enabled, warranty_duration_days')
    .eq('organization_id', activeOrgId)
    .order('display_order')
    .returns<ServiceRow[]>();

  return (
    <div className="max-w-2xl space-y-8">
      <PageTitle>Services</PageTitle>

      {canManage && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">Add Service</div>
          <form action={createService} className="space-y-3">
            <Field label="Name">
              <input name="name" required className={inputClass} />
            </Field>
            <Field label="Description (optional)">
              <input name="description" className={inputClass} />
            </Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Base price (optional)">
                <input name="basePrice" type="number" step="0.01" className={inputClass} />
              </Field>
              <Field label="Pricing type (optional)">
                <input name="pricingType" placeholder="e.g. flat, hourly" className={inputClass} />
              </Field>
            </div>
            <label className="flex items-center gap-2 text-xs text-cool-gray">
              <input type="checkbox" name="qcRequired" />
              Require quality control before invoicing
            </label>
            <label className="flex items-center gap-2 text-xs text-cool-gray">
              <input type="checkbox" name="warrantyEnabled" />
              Warranty enabled for this service
            </label>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Warranty duration (days, optional)">
                <input name="warrantyDurationDays" type="number" className={inputClass} />
              </Field>
              <Field label="Coverage notes (optional)">
                <input name="warrantyCoverageNotes" className={inputClass} />
              </Field>
            </div>
            <SubmitButton>Add Service</SubmitButton>
          </form>
        </Card>
      )}

      <div className="space-y-2">
        {(services ?? []).map((s) => (
          <Card key={s.id} className="flex items-center justify-between">
            <div>
              <div className="text-sm font-semibold">{s.name}</div>
              {s.description && <div className="text-xs text-cool-gray mt-0.5">{s.description}</div>}
              {s.base_price != null && (
                <div className="text-xs text-cool-gray mt-0.5">
                  ${s.base_price} {s.pricing_type && `· ${s.pricing_type}`}
                </div>
              )}
            </div>
            {canManage ? (
              <div className="flex flex-col gap-1 items-end">
                <ActiveToggle serviceId={s.id} active={s.active} />
                <QcRequiredToggle serviceId={s.id} qcRequired={s.qc_required} />
                {s.warranty_enabled && <span className="font-mono text-[9px] uppercase text-cool-gray">Warranty {s.warranty_duration_days ?? '?'}d</span>}
              </div>
            ) : (
              <span className="font-mono text-[9px] uppercase text-cool-gray">{s.active ? 'Active' : 'Inactive'}</span>
            )}
          </Card>
        ))}
        {(!services || services.length === 0) && <p className="text-sm text-cool-gray">No services in the catalog yet.</p>}
      </div>
    </div>
  );
}
