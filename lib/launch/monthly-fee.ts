'use server';
import {getSessionContext} from '@/lib/auth/session';
import {createClient} from '@/lib/supabase/server';
import {getLaunchPlan} from './plan';
import {revalidatePath} from 'next/cache';
export async function setMonthlyFee(form:FormData){
 const session=await getSessionContext();if(!session.isKccAdmin)return {error:'Only KCC Admin can set company fees.'};
 const amount=Number(form.get('amount'));const terms=String(form.get('terms')??'').trim();const org=String(form.get('organizationId')??'');
 if(!Number.isFinite(amount)||amount<=0||amount>9999999||!terms)return {error:'Enter a valid amount and payment terms.'};
 const db=await createClient();const {data:company}=await db.from('organizations').select('status').eq('id',org).maybeSingle();if(company?.status!=='active')return {error:'The company must be active.'};
 const {data:current,error:readError}=await db.from('organization_subscriptions').select('plan_id,currency,billing_cycle,price_snapshot,custom_terms,complimentary,status').eq('organization_id',org).is('superseded_at',null).maybeSingle();
 if(readError)return {error:readError.message};
 if(current&&current.currency!=='USD')return {error:'This company uses another currency. Update its commercial configuration first.'};
 if(current?.billing_cycle==='monthly'&&Number(current.price_snapshot)===amount&&current.custom_terms===terms&&!current.complimentary&&current.status==='active')return {};
 let planId=current?.plan_id;
 if(!planId){const plan=await getLaunchPlan(db);if(plan.error)return {error:plan.error};planId=plan.id;}
 const {error}=await db.rpc('assign_organization_subscription',{p_organization_id:org,p_plan_id:planId,p_billing_cycle:'monthly',p_trial_days:null,p_price_override:amount,p_complimentary:false,p_complimentary_reason:null,p_custom_terms:terms});
 if(error)return {error:error.message};revalidatePath(`/companies/${org}`);revalidatePath('/billing');return {};
}
export async function manageMonthlyCharge(form:FormData){
 const db=await createClient();const org=String(form.get('organizationId')??'');
 const {error}=await db.rpc('manage_monthly_charge',{p_org:org,p_month:form.get('month')?`${form.get('month')}-01`:null,p_due:form.get('dueOn')||null,p_charge:form.get('chargeId')||null,p_reference:form.get('reference')||null});
 if(error)return {error:error.message};revalidatePath(`/companies/${org}`);revalidatePath('/billing');return {};
}
