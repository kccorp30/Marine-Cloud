import Link from 'next/link';
import {headers} from 'next/headers';
import {createClient} from '@/lib/supabase/server';
import {getSessionContext} from '@/lib/auth/session';
import {getActiveOrganizationId} from '@/lib/auth/active-org';
import {getLocale} from '@/lib/i18n/server';
import {ShiftClock} from '@/components/technician/ShiftClock';
import {dayKey} from '@/lib/technician/day-plan';
// A template re-renders on navigation; layouts can remain cached by the router.
// This is a workday UX gate. Data authorization remains in existing RLS/RPCs.
export default async function OperationalTemplate({children}:{children:React.ReactNode}){
 const session=await getSessionContext();const org=await getActiveOrganizationId(session.memberships);
 const roles=session.memberships.filter(m=>m.organization_id===org).map(m=>m.role);
 if(session.isKccAdmin||!roles.includes('technician')||roles.some(r=>['company_owner','company_admin','manager'].includes(r))||!org)return children;
 const db=await createClient();const locale=await getLocale();const es=locale==='es';const pathname=(await headers()).get('x-kcc-path')||'';
 const exempt=['/profile','/kcc-assistance','/notifications',`/team/${session.userId}`].some(p=>pathname===p||pathname.startsWith(p+'/'));
 const {data:shift,error}=await db.from('technician_shifts').select('id,started_at,paused_at,break_seconds,pay_type,pay_rate,currency').eq('organization_id',org).eq('profile_id',session.userId).is('ended_at',null).maybeSingle();
 if(exempt)return <>{!error&&shift&&<ShiftClock shift={shift}/>} {children}</>;
 if(error)return <section className="premium-card rounded-2xl p-6"><p role="alert">{es?'No se pudo cargar tu jornada. Contacta a tu compañía para habilitarla.':'Could not load your workday. Contact your company to enable it.'}</p><Link href="/kcc-assistance" className="text-gold inline-block py-3">{es?'Asistencia →':'Assistance →'}</Link></section>;
 if(!shift){const {data:settings}=await db.from('organization_settings').select('timezone').eq('organization_id',org).single();
 if(settings?.timezone){const {data:closed}=await db.from('technician_shifts').select('id').eq('organization_id',org).eq('profile_id',session.userId).eq('work_date',dayKey(new Date(),settings.timezone)).not('ended_at','is',null).maybeSingle();if(closed)return <section className="premium-card p-6 rounded-2xl"><h1 className="text-2xl">{es?'Jornada finalizada':'Workday completed'}</h1><p className="mt-3 text-cool-gray">{es?'Tu jornada quedó registrada. Si necesitas corregirla, contacta a tu compañía.':'Your workday is recorded. Contact your company if it needs a correction.'}</p><Link className="text-gold inline-block py-3" href={`/team/${session.userId}`}>{es?'Ver mis horas y pagos →':'View my hours & payments →'}</Link></section>;}}
 return <><ShiftClock shift={shift} locked={!shift||!!shift.paused_at}/>{shift&&!shift.paused_at?children:null}</>;
}
