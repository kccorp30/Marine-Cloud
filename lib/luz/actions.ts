'use server';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
export async function scheduleFollowups(form:FormData){
 if(process.env.LUZ_FOLLOWUPS_ENABLED!=='true'||!process.env.RESEND_INBOUND_DOMAIN||!process.env.RESEND_API_KEY)return {error:'Automatic follow-up requires the email provider, inbound replies and scheduled worker to be enabled.'};
 const db=await createClient();const {error}=await db.rpc('schedule_estimate_followups',{p_estimate:form.get('estimateId'),p_message:form.get('messageId'),p_days:Number(form.get('days')),p_count:Number(form.get('count'))});
 if(error)return {error:error.message};revalidatePath('/luz');return {};
}
export async function stopFollowups(form:FormData){const db=await createClient();const {error}=await db.rpc('stop_estimate_followups',{p_estimate:form.get('estimateId')});if(error)return {error:error.message};revalidatePath('/luz');return {};}
