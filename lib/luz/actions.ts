'use server';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';

function followupInfrastructureReady(){
  return !!process.env.RESEND_API_KEY && !!process.env.CRON_SECRET;
}

export async function scheduleFollowups(form:FormData){
  if(!followupInfrastructureReady()) return {error:'Luz follow-up needs RESEND_API_KEY and CRON_SECRET on the server. Inbound reply routing is optional; without it, follow-up still stops when the estimate is approved/declined.'};
  const db=await createClient();
  const {error}=await db.rpc('schedule_estimate_followups',{
    p_estimate:form.get('estimateId'),
    p_message:form.get('messageId'),
    p_days:Number(form.get('days')),
    p_count:Number(form.get('count'))
  });
  if(error)return {error:error.message};
  revalidatePath('/luz');
  revalidatePath(`/estimates/${String(form.get('estimateId')||'')}`);
  return {success:true};
}
export async function stopFollowups(form:FormData){
  const db=await createClient();
  const {error}=await db.rpc('stop_estimate_followups',{p_estimate:form.get('estimateId')});
  if(error)return {error:error.message};
  revalidatePath('/luz');
  return {success:true};
}
