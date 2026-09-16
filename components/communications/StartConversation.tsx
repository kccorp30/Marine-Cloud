"use client";
import {useState,useTransition} from 'react';
import {useRouter} from 'next/navigation';
import {createConversationAction} from '@/lib/communications/actions';
import {useCommandCopy} from '@/components/ui/LocaleProvider';
export function StartConversation({organizationId,customerId,vessels}:{organizationId:string;customerId:string;vessels:{id:string;name:string}[]}) {
 const {locale}=useCommandCopy();const es=locale==='es';const router=useRouter();const [error,setError]=useState('');const [pending,start]=useTransition();
 return <form onSubmit={e=>{e.preventDefault();const data=new FormData(e.currentTarget);start(async()=>{setError('');try{const r=await createConversationAction(data);if(r.error)setError(r.error);else if(r.conversationId)router.push(`/communications/${r.conversationId}`);}catch{setError(es?'No se pudo abrir la conversación.':'Could not open the conversation.');}});}} className="space-y-3">
 <input type="hidden" name="organizationId" value={organizationId}/><input type="hidden" name="customerId" value={customerId}/>
 <label className="block">{es?'Asunto':'Subject'}<input required name="subject" className="w-full rounded-xl p-3 bg-white/5 border border-white/15"/></label>
 <label className="block">{es?'Embarcación':'Vessel'}<select name="vesselId" className="w-full rounded-xl p-3 bg-navy border border-white/15"><option value="">{es?'Consulta general':'General inquiry'}</option>{vessels.map(v=><option key={v.id} value={v.id}>{v.name}</option>)}</select></label>
 <button disabled={pending} className="command-action">{pending?(es?'Abriendo…':'Opening…'):(es?'Escribir al cliente':'Write to customer')}</button>{error&&<p role="alert" className="text-red-300">{error}</p>}
 </form>;
}
