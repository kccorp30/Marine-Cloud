'use server';
import {z} from 'zod';
import {getSessionContext} from '@/lib/auth/session';
import {createClient} from '@/lib/supabase/server';
import {revalidatePath} from 'next/cache';
export async function configureCompanyEmail(form:FormData){
 const session=await getSessionContext();if(!session.isKccAdmin)return {error:'Only KCC Admin can configure senders.'};
 const sender=z.string().email().safeParse(form.get('sender'));if(!sender.success)return {error:'Enter a valid sender email.'};
 const enabled=form.get('enabled')==='on';let verified=false;
 if(enabled){
  if(!process.env.RESEND_API_KEY)return {error:'Configure the email provider on the server first.'};
  try{const response=await fetch('https://api.resend.com/domains',{headers:{Authorization:`Bearer ${process.env.RESEND_API_KEY}`},signal:AbortSignal.timeout(10000)});if(!response.ok){
    const providerBody=await response.text().catch(()=> '');
    if(response.status===401||response.status===403)return {error:'Resend rechazó la API key (401/403). Verifica que la RESEND_API_KEY de producción pertenezca a la misma cuenta donde está verificado kccorpglobal.com.'};
    return {error:`Resend no pudo verificar el dominio (HTTP ${response.status}). Revisa la API key y el estado del proveedor.${providerBody?` Detalle: ${providerBody.slice(0,180)}`:''}`};
  }
  const result=await response.json();const domain=sender.data.split('@')[1].toLowerCase();verified=Array.isArray(result.data)&&result.data.some((d:{name:string;status:string;capabilities?:{sending?:string}})=>d.name.toLowerCase()===domain&&d.status==='verified'&&d.capabilities?.sending!=='disabled');if(!verified)return {error:'Verify this sender domain in Resend before enabling it.'};
  }catch{return {error:'Could not reach the email provider.'};}
 }
 const db=await createClient();const org=String(form.get('organizationId')??'');const {error}=await db.rpc('set_email_provider_state',{p_organization_id:org,p_sender_email:sender.data,p_verification_status:verified?'verified':'unverified',p_enabled:enabled});
 if(error)return {error:error.message};revalidatePath(`/companies/${org}`);revalidatePath('/company-settings');return {};
}
