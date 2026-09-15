import {SmartProfile} from '@/components/smart/Profile';
import Link from 'next/link';
import {notFound} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {getSessionContext} from '@/lib/auth/session';
import {getActiveOrganizationId} from '@/lib/auth/active-org';
import {getLocale} from '@/lib/i18n/server';
import {getTechnicianDay} from '@/lib/technician/day-data';
import {savePayTerms,recordPay} from '@/lib/payroll/actions';
import {ActionForm} from '@/components/ui/ActionForm';
import {Field,inputClass,SubmitButton,StatusBadge} from '@/components/ui/primitives';
export default async function TechnicianDetail({params}:{params:Promise<{profileId:string}>}){
 const {profileId}=await params;const session=await getSessionContext();const org=await getActiveOrganizationId(session.memberships);if(!org)notFound();
 const role=session.memberships.find(m=>m.organization_id===org)?.role;
 const manage=session.isKccAdmin||['company_owner','company_admin'].includes(role??'');
 if(!manage&&session.userId!==profileId)notFound();
 const locale=await getLocale();const es=locale==='es';const db=await createClient();
 const {data:membership}=await db.from('organization_memberships').select('profile:profiles(full_name,avatar_url,phone)').eq('organization_id',org).eq('profile_id',profileId).eq('role','technician').eq('status','active').maybeSingle();if(!membership)notFound();
 const profile=Array.isArray(membership.profile)?membership.profile[0]:membership.profile;
 const [{data:terms,error:termsError},{data:shifts,error:shiftsError},day]=await Promise.all([
 db.from('technician_pay_terms').select('*').eq('organization_id',org).eq('profile_id',profileId).maybeSingle(),
 db.from('technician_shifts').select('*').eq('organization_id',org).eq('profile_id',profileId).order('started_at',{ascending:false}).limit(60),getTechnicianDay(profileId,org)]);
 const payments=await db.from('technician_payments').select('shift_id,reference,paid_at').eq('organization_id',org).eq('profile_id',profileId);
 const paid=new Map((payments.data??[]).map(p=>[p.shift_id,p]));
 return <div className="max-w-5xl space-y-6">
 <Link href="/team" className="text-gold">← {es?'Equipo':'Team'}</Link>
 <SmartProfile name={profile?.full_name||(es?'Técnico':'Technician')} photo={profile?.avatar_url} subtitle={es?'Operación y remuneración':'Operations & compensation'}><p>{profile?.phone}</p><p>{day.jobs.length} {es?'trabajos asignados':'assigned jobs'}</p></SmartProfile>
 <section className="premium-card p-5 rounded-2xl"><h2 className="text-lg font-semibold mb-3">{es?'Trabajos asignados':'Assigned jobs'}</h2>{day.jobs.map(job=><Link className="flex justify-between items-center gap-3 py-3 border-b border-white/10" key={`${job.id}-${job.appointmentId}`} href={`/work-orders/${job.id}`}><span>{job.vessel||job.title}<small className="block text-cool-gray">{job.title}</small></span><StatusBadge status={job.status} locale={locale}/></Link>)}{!day.jobs.length&&<p className="text-cool-gray">{es?'Sin trabajos activos.':'No active jobs.'}</p>}</section>
 {termsError||shiftsError?<p role="alert" className="text-amber-200">{es?'Jornada y remuneración pendientes de habilitación.':'Workday and compensation setup is pending.'}</p>:<>
 <details className="premium-card p-5 rounded-2xl"><summary className="font-semibold cursor-pointer">{es?'Condiciones de pago':'Payment terms'} · {terms?`${terms.currency} ${terms.pay_rate}`:'—'}</summary>
 {manage?<ActionForm action={savePayTerms} className="grid sm:grid-cols-2 gap-4 mt-4"><input type="hidden" name="profileId" value={profileId}/>
 <Field label={es?'Modalidad':'Pay basis'}><select className={inputClass} name="payType" defaultValue={terms?.pay_type||'hourly'}><option value="hourly">{es?'Por hora':'Hourly'}</option><option value="daily">{es?'Por día':'Daily'}</option></select></Field>
 <Field label={es?'Tarifa':'Rate'}><input className={inputClass} name="payRate" type="number" min="0" max="9999999" step="0.01" required defaultValue={terms?.pay_rate??''}/></Field>
 <Field label={es?'Moneda':'Currency'}><select className={inputClass} name="currency" defaultValue={terms?.currency||'USD'}>{['USD','COP','DOP','EUR'].map(c=><option key={c}>{c}</option>)}</select></Field>
 <Field label={es?'Frecuencia de pago':'Pay frequency'}><select className={inputClass} name="payCycle" defaultValue={terms?.pay_cycle||'weekly'}><option value="weekly">{es?'Semanal':'Weekly'}</option><option value="biweekly">{es?'Cada 14 días':'Every 14 days'}</option><option value="monthly">{es?'Mensual':'Monthly'}</option></select></Field>
 <Field label={es?'Inicio del ciclo':'Cycle start'}><input className={inputClass} name="cycleAnchor" type="date" required defaultValue={terms?.cycle_anchor??''}/></Field><div className="self-end"><SubmitButton>{es?'Guardar condiciones':'Save terms'}</SubmitButton></div><p className="text-xs text-cool-gray col-span-full">{es?'Los cambios aplican a nuevas jornadas. Los importes son brutos, antes de deducciones.':'Changes apply to new workdays. Amounts are gross, before deductions.'}</p>
 </ActionForm>:<p className="mt-3">{terms?`${terms.pay_type} · ${terms.pay_cycle}`:(es?'La compañía aún no ha configurado tu tarifa.':'Your company has not configured your rate yet.')}</p>}</details>
 <section className="premium-card p-5 rounded-2xl"><h2 className="text-lg font-semibold">{es?'Historial de jornadas':'Workday history'}</h2><p className="text-xs text-cool-gray mb-4">{es?'Últimas 60 jornadas. Tiempo de jornada, sin sumar nuevamente las horas de cada orden.':'Latest 60 workdays. Shift time only; job time entries are not added again.'}</p>
 {(shifts??[]).map(s=><div key={s.id} className="grid grid-cols-3 gap-3 py-3 border-b border-white/10 text-sm"><span>{s.work_date}</span><span>{s.ended_at?`${(Number(s.paid_seconds)/3600).toFixed(2)} h`:(s.paused_at?(es?'En pausa':'Paused'):(es?'En jornada':'On shift'))}</span><span className="text-right">{s.gross_amount!=null&&s.currency?new Intl.NumberFormat(locale,{style:'currency',currency:s.currency}).format(s.gross_amount):'—'}</span>{paid.has(s.id)?<p className="col-span-full text-emerald-300 text-xs">{es?'Pago registrado':'Payment recorded'} · {paid.get(s.id)?.reference}</p>:manage&&s.ended_at&&s.gross_amount!=null&&!payments.error?<details className="col-span-full"><summary className="cursor-pointer text-gold">{es?'Registrar pago de jornada':'Record workday payment'}</summary><ActionForm action={recordPay} className="flex flex-wrap gap-3"><input type="hidden" name="shiftId" value={s.id}/><input name="reference" required minLength={3} placeholder={es?'Referencia del pago':'Payment reference'} className="p-3 bg-white/5 rounded-xl border border-white/15"/><button className="command-action">{es?'Confirmar pago completo':'Confirm full payment'}</button></ActionForm></details>:null}</div>)}{!shifts?.length&&<p>{es?'Aún no hay jornadas.':'No workdays yet.'}</p>}</section>
 </>}
 </div>;
}
