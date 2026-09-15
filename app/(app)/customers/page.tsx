import {ActionForm} from '@/components/ui/ActionForm';
import {getLocale} from '@/lib/i18n/server';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { createCustomer } from '@/lib/work-orders/actions';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';

export default async function CustomersPage() {
  const locale=await getLocale();const es=locale==='es';
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);
  const activeMembership = session.memberships.find((m) => m.organization_id === activeOrgId);
  const canCreate = session.isKccAdmin || ['company_owner', 'company_admin', 'manager'].includes(activeMembership?.role ?? '');

  const supabase = await createClient();
  // Sin .eq('organization_id', ...) explícito no hace falta filtrar a
  // mano — RLS ya devuelve solo lo que este usuario puede ver. Se
  // agrega igual para que la UI muestre la organización activa
  // específicamente, no "todo lo que ves" si sos kcc_admin.
  const { data: customers } = await supabase
    .from('customers')
    .select('id, first_name, last_name, email, phone, status, created_at')
    .eq('organization_id', activeOrgId)
    .order('created_at', { ascending: false });

  return (
    <div className="max-w-4xl">
      <PageTitle>Customers</PageTitle>

      {canCreate && (
        <details className="premium-card rounded-2xl p-5 mb-6"><summary className="text-gold cursor-pointer font-semibold">{es?"+ Agregar cliente":"+ Add customer"}</summary><div className="pt-4">
          <ActionForm resetOnSuccess action={createCustomer} className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Field label="First Name">
              <input name="firstName" required className={inputClass} />
            </Field>
            <Field label="Last Name">
              <input name="lastName" required className={inputClass} />
            </Field>
            <Field label="Email (optional)">
              <input name="email" type="email" className={inputClass} />
            </Field>
            <Field label="Phone (optional)">
              <input name="phone" className={inputClass} />
            </Field>
            <div className="sm:col-span-2">
              <SubmitButton>Create Customer</SubmitButton>
            </div>
          </ActionForm>
        </div></details>
      )}

      <div className="grid sm:grid-cols-2 gap-4">
        {(customers ?? []).map((c) => (
          <Link key={c.id} href={`/customers/${c.id}`}>
            <Card className="h-full flex items-start gap-4 hover:border-gold/40 transition-colors !rounded-2xl">
              <div className="w-14 h-14 shrink-0 rounded-2xl bg-white/5 border border-white/10 grid place-items-center text-xl text-gold">{c.first_name?.slice(0,1)}{c.last_name?.slice(0,1)}</div>
              <div>
                <div className="text-sm font-semibold">
                  {c.first_name} {c.last_name}
                </div>
                <div className="text-xs text-cool-gray">{c.email || '—'}</div><div className="text-xs text-cool-gray mt-1">{c.phone}</div><p className="text-gold text-xs mt-4">{es?'Estimados · Servicios · Conversaciones →':'Estimates · Services · Conversations →'}</p>
              </div>
              
            </Card>
          </Link>
        ))}
        {(!customers || customers.length === 0) && <p className="text-sm text-cool-gray">No customers yet.</p>}
      </div>
    </div>
  );
}
