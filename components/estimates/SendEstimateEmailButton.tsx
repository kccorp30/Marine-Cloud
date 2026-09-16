"use client";
import {ActionForm} from "@/components/ui/ActionForm";
import {scheduleFollowups} from "@/lib/luz/actions";
import { useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useCommandCopy } from '@/components/ui/LocaleProvider';
import { previewEstimateEmailAction, publishAndEmailEstimateAction } from '@/lib/communications/actions';

type Preview = { issues:string[]; html:string; fingerprint:string; recipient:string|null; subject:string; canSend:boolean };
export function SendEstimateEmailButton({estimateId,publishDraft=false}:{estimateId:string;publishDraft?:boolean}) {
  const {locale} = useCommandCopy(); const es=locale==='es'; const router=useRouter();
  const [open,setOpen]=useState(false); const [intro,setIntro]=useState('');
  const [preview,setPreview]=useState<Preview|null>(null); const [error,setError]=useState('');
  const [messageId,setMessageId]=useState<string|null>(null);
  const [sent,setSent]=useState(false); const [pending,setPending]=useState(false);
  async function start(fn:()=>Promise<void>){if(pending)return;setPending(true);try{await fn();}finally{setPending(false);}}
  const key=useRef<string|null>(null);
  return <section className="space-y-4">
    {sent && <p role="status" className="text-emerald-300">{es?'Correo aceptado por el proveedor. Consulta la entrega en el historial de comunicación.':'Email accepted by the provider. Check delivery in communication history.'}</p>}
    {sent && messageId && <details className="rounded-xl border border-blue-300/20 p-4"><summary className="cursor-pointer text-gold">{es?'Luz · Seguimiento automático':'Luz · Automatic follow-up'}</summary><ActionForm action={scheduleFollowups} className="space-y-3 mt-3"><input type="hidden" name="estimateId" value={estimateId}/><input type="hidden" name="messageId" value={messageId}/><p className="text-sm text-cool-gray">{es?'Envía recordatorios mientras el estimado esté pendiente. Se detienen al recibir respuesta.':'Send reminders while the estimate is pending. They stop when the customer replies.'}</p><label className="block">{es?'Intervalo (días)':'Interval (days)'}<input name="days" type="number" min="1" max="30" defaultValue="3" required className="bg-white/5 border border-white/15 rounded-xl p-2 ml-3 w-20"/></label><label className="block">{es?'Máximo de recordatorios':'Maximum reminders'}<select name="count" defaultValue="2" className="bg-navy border border-white/15 rounded-xl p-2 ml-3"><option value="1">1</option><option value="2">2</option></select></label><button className="command-action">{es?'Activar seguimiento de Luz':'Enable Luz follow-up'}</button></ActionForm></details>}
    {!open ? <button className="command-action" onClick={()=>{setOpen(true);setSent(false);}}>{es?'Revisar y enviar estimado':'Review & email estimate'}</button> : <>
      <label className="block text-sm">{es?'Mensaje personal (opcional)':'Personal note (optional)'}<textarea className="mt-2 w-full rounded-xl bg-white/5 border border-white/15 p-3" rows={3} value={intro} disabled={pending} onChange={e=>{setIntro(e.target.value);setPreview(null);key.current=null;}}/></label>
      <div className="flex flex-wrap gap-3">
        <button className="command-action" disabled={pending} onClick={()=>start(async()=>{setError('');try{const r=await previewEstimateEmailAction(estimateId,intro);if(r.error)setError(r.error);else if(r.preview){setPreview(r.preview);key.current ??= crypto.randomUUID();}}catch{setError(es?'No se pudo cargar la vista previa.':'Could not load preview.');}})}>{pending?(es?'Procesando…':'Processing…'):(es?'Vista previa del correo':'Preview email')}</button>
        <button disabled={pending} onClick={()=>setOpen(false)}>{es?'Cerrar':'Close'}</button>
      </div>
      {preview && <div className="space-y-3">
        <p className="text-sm break-words">{es?'Para':'To'}: {preview.recipient || '—'}<br/>{preview.subject}</p>
        <iframe title={es?'Vista previa del correo del cliente':'Customer email preview'} srcDoc={preview.html} sandbox="" className="w-full h-[520px] rounded-xl bg-white" />
        {!preview.canSend && <p role="alert" className="text-amber-200">{preview.issues.join(' ')}</p>}
        <button className="command-action" disabled={pending || !preview.canSend} onClick={()=>start(async()=>{
          setError('');const data=new FormData();data.set('estimateId',estimateId);data.set('customIntro',intro);data.set('fingerprint',preview.fingerprint);data.set('idempotencyKey',key.current ??= crypto.randomUUID());
          try{const r=await publishAndEmailEstimateAction(data);if(r?.error){setError(r.error);setPreview(null);}else{setSent(true);if(r && 'messageId' in r)setMessageId(String(r.messageId));setOpen(false);key.current=null;router.refresh();}}catch{setError(es?'No se pudo confirmar el envío. Revisa el historial antes de reintentar.':'Could not confirm sending. Check history before retrying.');}
        })}>{pending?(es?'Enviando…':'Sending…'):(es?(publishDraft?'Publicar y enviar correo':'Enviar correo'):(publishDraft?'Publish & send email':'Send email'))}</button>
      </div>}
    </>}
    {error && <p role="alert" className="text-red-300 text-sm">{error}</p>}
  </section>;
}
