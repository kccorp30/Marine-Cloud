import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {getSessionContext} from '@/lib/auth/session';
import {getActiveOrganizationId} from '@/lib/auth/active-org';
import {getLocale} from '@/lib/i18n/server';
import {stopFollowups} from '@/lib/luz/actions';
import {ActionForm} from '@/components/ui/ActionForm';
export default async function LuzPage(){
 const session=await getSessionContext();const org=await getActiveOrganizationId(session.memberships);const role=session.memberships.find(m=>m.organization_id===org)?.role;
 if(!session.isKccAdmin&&!['company_owner','company_admin'].includes(role??''))redirect('/dashboard');
 const locale=await getLocale();const es=locale==='es';const db=await createClient();
 let query=db.from('luz_estimate_followups').select('id,estimate_id,sequence,due_at,status,reason,estimate:estimates(estimate_number,customer:customers(first_name,last_name))').order('due_at',{ascending:false}).limit(100);if(!session.isKccAdmin)query=query.eq('organization_id',org);
 const {data:jobs,error}=await query;const enabled=!!process.env.RESEND_API_KEY&&!!process.env.CRON_SECRET;
 return <div className="max-w-5xl space-y-6"><header className="flex gap-5 items-center"><span className="luz-orb" aria-hidden="true">✦</span><div><h1 className="text-3xl font-semibold">Luz</h1><p className="text-cool-gray">{es?'Seguimiento de clientes y acciones pendientes':'Customer follow-up & pending actions'}</p></div></header>
 <section className="premium-card rounded-2xl p-5"><p className={enabled?'text-emerald-300':'text-amber-200'}>{enabled?(es?'Envíos automáticos habilitados':'Automatic sending enabled'):(es?'Activación de correo, respuestas y programador pendiente':'Email, replies and scheduler activation pending')}</p><p className="text-sm text-cool-gray mt-3">{es?'Activa Luz después de enviar un estimado. Puedes programar hasta dos recordatorios y detenerlos aquí. Las respuestas del cliente aparecen en su conversación.':'Enable Luz after emailing an estimate. Schedule up to two reminders and stop them here. Customer replies appear in their conversation.'}</p><div className="flex gap-4 mt-4"><Link className="command-action" href="/estimates">{es?'Revisar estimados':'Review estimates'}</Link><Link className="py-3 text-gold" href="/communications">{es?'Conversaciones →':'Conversations →'}</Link></div></section>
 <section className="premium-card rounded-2xl p-5"><h2 className="text-xl font-semibold mb-4">{es?'Actividad de Luz':'Luz activity'}</h2>{error?<p role="alert">{es?'No se pudo cargar la actividad.':'Could not load activity.'}</p>:!jobs?.length?<p className="text-cool-gray">{es?'Todavía no hay seguimientos programados.':'No follow-ups scheduled yet.'}</p>:jobs.map((j:any)=>{const e=Array.isArray(j.estimate)?j.estimate[0]:j.estimate;const customer=e?.customer;return <div key={j.id} className="py-4 border-b border-white/10 flex flex-wrap justify-between gap-4"><div><Link className="font-semibold text-gold" href={`/estimates/${j.estimate_id}`}>{e?.estimate_number} · {customer?.first_name} {customer?.last_name}</Link><p className="text-sm text-cool-gray">{new Date(j.due_at).toLocaleString(locale)} · {j.status}</p>{j.reason&&<p className="text-xs mt-2">{j.reason}</p>}</div>{j.status==='scheduled'&&<ActionForm action={stopFollowups}><input type="hidden" name="estimateId" value={j.estimate_id}/><button className="py-3 text-amber-200">{es?'Detener seguimiento':'Stop follow-up'}</button></ActionForm>}</div>})}</section></div>;
}
