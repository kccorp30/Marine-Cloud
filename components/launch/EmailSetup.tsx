import {createClient} from '@/lib/supabase/server';
import {getLocale} from '@/lib/i18n/server';
import {ActionForm} from '@/components/ui/ActionForm';
import {configureCompanyEmail} from '@/lib/email/setup-action';
export async function EmailSetup({organizationId}:{organizationId:string}){
 const locale=await getLocale();const es=locale==='es';const db=await createClient();const {data}=await db.from('organization_email_settings').select('sender_email,enabled').eq('organization_id',organizationId).maybeSingle();
 return <details className="premium-card rounded-2xl p-5"><summary className="cursor-pointer font-semibold">{es?'Correo de la compañía':'Company email'} · {data?.enabled?(es?'Habilitado':'Enabled'):(es?'Pendiente':'Pending')}</summary><ActionForm action={configureCompanyEmail} className="space-y-4 mt-4"><input type="hidden" name="organizationId" value={organizationId}/><label className="block">{es?'Remitente':'Sender'}<input type="email" name="sender" required defaultValue={data?.sender_email??''} className="w-full p-3 mt-2 bg-white/5 border border-white/15 rounded-xl"/></label><label className="flex gap-3"><input type="checkbox" name="enabled" defaultChecked={data?.enabled??false}/>{es?'Habilitar envíos':'Enable sending'}</label><p className="text-sm text-cool-gray">{es?'El dominio se verifica con el proveedor antes de habilitar los envíos.':'The domain is checked with the provider before sending is enabled.'}</p><button className="command-action">{es?'Verificar y guardar':'Verify & save'}</button></ActionForm></details>;
}
