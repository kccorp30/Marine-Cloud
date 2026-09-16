'use server';
import {createClient} from '@/lib/supabase/server';
import {getSessionContext} from '@/lib/auth/session';
import {getActiveOrganizationId} from '@/lib/auth/active-org';
import {revalidatePath} from 'next/cache';
export async function recordExpense(form:FormData){
 const session=await getSessionContext();const org=await getActiveOrganizationId(session.memberships);const db=await createClient();
 const {error}=await db.from('company_expenses').insert({organization_id:org,description:String(form.get('description')??'').trim(),amount:Number(form.get('amount')),currency:form.get('currency'),category:form.get('category'),paid_on:form.get('paidOn'),reference:form.get('reference'),idempotency_key:form.get('idempotencyKey'),created_by:session.userId});
 if(error&&error.code!=='23505')return {error:error.message};revalidatePath('/finances');return {};
}
