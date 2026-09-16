import {ActionForm} from '@/components/ui/ActionForm';
import {Drawer} from '@/components/smart/Drawer';
import {getLocale} from '@/lib/i18n/server';
import {workspaceCopy} from '@/lib/i18n/workspace-copy';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { createVessel } from '@/lib/work-orders/actions';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';

export default async function VesselsPage() {
  const t=workspaceCopy[await getLocale()];
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const activeMembership = session.memberships.find((m) => m.organization_id === activeOrgId);
  const canCreate = session.isKccAdmin || ['company_owner', 'company_admin', 'manager'].includes(activeMembership?.role ?? '');

  const supabase = await createClient();
  const { data: vessels } = await supabase
    .from('vessels')
    .select('id, name, hin, make, model, year, status, customer:customers(first_name, last_name)')
    .eq('organization_id', activeOrgId)
    .order('created_at', { ascending: false });

  const { data: customers } = canCreate
    ? await supabase.from('customers').select('id, first_name, last_name').eq('organization_id', activeOrgId)
    : { data: [] };

  return (
    <div className="max-w-4xl">
      <PageTitle>{t.vessel}</PageTitle>

      {canCreate && (
        <div className="mb-6"><Drawer label={t.newVessel} title={t.newVessel}>
          <ActionForm action={createVessel} className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Field label="Customer">
              <select name="customerId" required className={inputClass}>
                <option value="">Select…</option>
                {(customers ?? []).map((c) => (
                  <option key={c.id} value={c.id} className="bg-navy">
                    {c.first_name} {c.last_name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Vessel Name">
              <input name="name" className={inputClass} />
            </Field>
            <Field label="HIN">
              <input name="hin" className={inputClass} />
            </Field>
            <Field label="Make">
              <input name="make" className={inputClass} />
            </Field>
            <Field label="Model">
              <input name="model" className={inputClass} />
            </Field>
            <Field label="Year">
              <input name="year" type="number" className={inputClass} />
            </Field>
            <div className="sm:col-span-2">
              <SubmitButton>Create Vessel</SubmitButton>
            </div>
          </ActionForm>
        </Drawer></div>
      )}

      <div className="kcc-record-grid">
        {(vessels ?? []).map((v: any) => (
          <Link key={v.id} href={`/vessels/${v.id}`}>
            <Card className="flex items-center justify-between hover:border-gold/40 transition-colors">
              <div>
                <div className="text-sm font-semibold">{v.name || `${v.make ?? ''} ${v.model ?? ''}`.trim() || 'Unnamed Vessel'}</div>
                <div className="text-xs text-cool-gray">
                  {v.hin && `HIN ${v.hin} · `}
                  {v.customer ? `${v.customer.first_name} ${v.customer.last_name}` : '—'}
                </div>
              </div>
              <span className="font-mono text-[9px] uppercase text-cool-gray">{v.status}</span>
            </Card>
          </Link>
        ))}
        {(!vessels || vessels.length === 0) && <p className="text-sm text-cool-gray">No vessels yet.</p>}
      </div>
    </div>
  );
}
