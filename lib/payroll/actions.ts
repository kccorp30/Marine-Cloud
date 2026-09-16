'use server';
import {revalidatePath} from 'next/cache';
import {createClient} from '@/lib/supabase/server';
import {getSessionContext} from '@/lib/auth/session';
import {getActiveOrganizationId} from '@/lib/auth/active-org';
export async function savePayTerms(form:FormData){
 const session=await getSessionContext();const org=await getActiveOrganizationId(session.memberships);
 const db=await createClient();const {error}=await db.rpc('save_technician_pay_terms',{p_org:org,p_profile:form.get('profileId'),p_type:form.get('payType'),p_rate:Number(form.get('payRate')),p_currency:form.get('currency'),p_cycle:form.get('payCycle'),p_anchor:form.get('cycleAnchor')});
 if(error)return {error:error.message};revalidatePath('/team');revalidatePath(`/team/${form.get('profileId')}`);return {};
}
export async function changeShift(action:string){
 const session=await getSessionContext();const org=await getActiveOrganizationId(session.memberships);
 const db=await createClient();const {error}=await db.rpc('change_technician_shift',{p_org:org,p_action:action});
 if(error)return {error:error.message};revalidatePath('/', 'layout');return {};
}
export async function recordPay(form:FormData){const db=await createClient();const {error}=await db.rpc('record_technician_payment',{p_shift:form.get('shiftId'),p_reference:form.get('reference')});if(error)return {error:error.message};revalidatePath('/team','layout');revalidatePath('/finances');return {};}
