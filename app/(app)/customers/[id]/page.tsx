import {SmartProfile,ContactActions} from '@/components/smart/Profile';
import {workspaceCopy} from '@/lib/i18n/workspace-copy';
import { StartConversation } from '@/components/communications/StartConversation';
import { getLocale } from '@/lib/i18n/server';
import { StatusBadge } from '@/components/ui/primitives';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getSessionContext } from '@/lib/auth/session';
import { getActiveOrganizationId } from '@/lib/auth/active-org';
import { getConversationList } from '@/lib/communications/data';
import { createConversationAction } from '@/lib/communications/actions';
import { Card, PageTitle, Field, inputClass, SubmitButton } from '@/components/ui/primitives';
import { CustomerPortalAccessButton } from '@/components/customers/CustomerPortalAccessButton';

export default async function CustomerDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const locale = await getLocale(); const es = locale === 'es'; const t=workspaceCopy[locale];
  const session = await getSessionContext();
  const activeOrgId = await getActiveOrganizationId(session.memberships);

  const supabase = await createClient();
  const { data: customer } = await supabase
    .from('customers')
    .select('id, first_name, last_name, email, phone, status, created_at, profile_id')
    .eq('id', id).eq('organization_id',activeOrgId)
    .maybeSingle();

  if (!customer) notFound();

  const { data: vessels } = await supabase.from('vessels').select('id, name').eq('current_customer_id', id);
  const [{data: estimates}, {data: orders}, {data: invoices}] = await Promise.all([
    supabase.from('estimates').select('id,estimate_number,status,current_version:estimate_versions!fk_estimates_current_version(total,currency)').eq('customer_id',id).eq('organization_id',activeOrgId).order('created_at',{ascending:false}).throwOnError(),
    supabase.from('work_orders').select('id,title,current_status').eq('customer_id',id).eq('organization_id',activeOrgId).order('created_at',{ascending:false}).throwOnError(),
    supabase.from('invoices').select('id,invoice_number,status').eq('customer_id',id).eq('organization_id',activeOrgId).order('created_at',{ascending:false}).throwOnError()
  ]);
  const conversations = await getConversationList(activeOrgId!, id);

  return (
    <div className="max-w-5xl space-y-6">
      <SmartProfile name={`${customer.first_name} ${customer.last_name}`} subtitle={t.customer} status={<StatusBadge status={customer.status} locale={locale}/>}><p>{customer.email}</p><p>{customer.phone}</p><p>{t.customerSince}: {new Date(customer.created_at).toLocaleDateString(locale)}</p><p className="text-xs text-cool-gray">{t.customerId}: <span translate="no">{customer.id}</span></p></SmartProfile>
      <div className="flex flex-wrap gap-3 items-center"><ContactActions phone={customer.phone} email={customer.email} labels={t}/><Link className="kcc-action" href={`/estimates?customer=${id}`}>{es?'Crear estimado':'Create estimate'}</Link><Link className="kcc-action" href={`/work-orders?customer=${id}`}>{t.newOrder}</Link><CustomerPortalAccessButton customerId={id} alreadyLinked={Boolean(customer.profile_id)} /></div>
      <div className="grid md:grid-cols-2 gap-5">
        <section className="premium-card p-5 rounded-2xl"><h2 className="text-lg font-semibold mb-4">{es?'Estimados y aprobaciones':'Estimates & approvals'}</h2>
          {(estimates ?? []).map(e=>{const v=Array.isArray(e.current_version)?e.current_version[0]:e.current_version;return <Link className="flex justify-between gap-3 py-3 border-b border-white/10" key={e.id} href={`/estimates/${e.id}`}><span>{e.estimate_number}<small className="block text-cool-gray">{v?new Intl.NumberFormat(locale,{style:'currency',currency:v.currency}).format(v.total):'—'}</small></span><StatusBadge status={e.status} locale={locale}/></Link>})}
          {!estimates?.length&&<p className="text-cool-gray">{es?'Aún no hay estimados.':'No estimates yet.'}</p>}
          <Link className="inline-block mt-4 text-gold" href={`/estimates?customer=${id}`}>{es?'Crear estimado →':'Create estimate →'}</Link>
        </section>
        <section className="premium-card p-5 rounded-2xl"><h2 className="text-lg font-semibold mb-4">{es?'Servicios y progreso':'Services & progress'}</h2>
          {(orders??[]).map(o=><Link className="flex justify-between gap-3 py-3 border-b border-white/10" key={o.id} href={`/work-orders/${o.id}`}><span>{o.title}</span><StatusBadge status={o.current_status} locale={locale}/></Link>)}
          {!orders?.length&&<p className="text-cool-gray">{es?'Sin servicios registrados.':'No services recorded.'}</p>}
        </section>
      </div>
      <details className="premium-card rounded-2xl p-5"><summary className="cursor-pointer font-semibold">{es?'Embarcaciones y facturas':'Vessels & invoices'}</summary><div className="grid sm:grid-cols-2 gap-5 mt-4"><div>{(vessels??[]).map(v=><Link className="block py-3 text-gold" key={v.id} href={`/vessels/${v.id}`}>{v.name} →</Link>)}</div><div>{(invoices??[]).map(i=><Link className="flex justify-between gap-3 py-3" key={i.id} href={`/invoices/${i.id}`}>{i.invoice_number}<StatusBadge status={i.status} locale={locale}/></Link>)}</div></div></details>

      <div>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">{t.contactHistory}</div>
        <div className="space-y-2">
          {conversations.map((c) => (
            <Link key={c.id} href={`/communications/${c.id}`}>
              <Card className="hover:border-gold/40 transition-colors">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-sm font-semibold">{c.subject ?? 'Conversation'}</div>
                    {c.lastMessagePreview && <div className="text-xs text-cool-gray/70 mt-1 truncate">{c.lastMessagePreview}</div>}
                  </div>
                  {c.lastMessageAt && <div className="text-[10px] text-cool-gray shrink-0 ml-3">{new Date(c.lastMessageAt).toLocaleDateString()}</div>}
                </div>
              </Card>
            </Link>
          ))}
          {conversations.length === 0 && <p className="text-sm text-cool-gray">{t.noHistory}</p>}
        </div>

        <details className="premium-card p-5 rounded-2xl mt-4"><summary className="cursor-pointer font-semibold text-gold">{es?'Nueva conversación':'New conversation'}</summary><div className="pt-4"><StartConversation organizationId={activeOrgId!} customerId={id} vessels={vessels ?? []}/></div></details>
      </div>
    </div>
  );
}
