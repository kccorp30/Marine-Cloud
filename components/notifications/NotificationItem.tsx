'use client';
import {useState} from 'react';
import Link from 'next/link';
import {Drawer} from '@/components/smart/Drawer';
import {useCommandCopy} from '@/components/ui/LocaleProvider';
import {workspaceCopy} from '@/lib/i18n/workspace-copy';
import {markNotificationReadAction,acknowledgeNotificationAction} from '@/lib/notifications/actions';
import type {NotificationDTO} from '@/lib/notifications/data';
export function NotificationItem({notification:n,deepLink,severityLabel}:{notification:NotificationDTO;deepLink:string|null;severityLabel:string}){
 const {locale}=useCommandCopy();const t=workspaceCopy[locale];const [read,setRead]=useState(!!n.readAt);const [ack,setAck]=useState(!!n.acknowledgedAt);const [pending,setPending]=useState(false);const [error,setError]=useState('');
 async function update(acknowledge:boolean){setPending(true);setError('');try{const result=await(acknowledge?acknowledgeNotificationAction(n.id):markNotificationReadAction(n.id));if(result.error)setError(result.error);else{setRead(true);if(acknowledge)setAck(true);}}catch{setError(locale==='es'?'No se pudo guardar.':'Could not save.');}finally{setPending(false);}}
 return <article className="kcc-section"><div className="flex justify-between gap-3 text-xs text-cool-gray"><span>{severityLabel} · {read?t.read:t.unread}</span><time>{new Date(n.createdAt).toLocaleString(locale)}</time></div><h2 className="text-base font-semibold mt-2">{n.title}</h2>{n.body&&<p className="text-sm text-cool-gray mt-2 line-clamp-2">{n.body}</p>}<div className="mt-3"><Drawer label={t.details} title={n.title}><div className="space-y-6"><p className="kcc-eyebrow">{severityLabel}</p><p className="whitespace-pre-wrap leading-relaxed">{n.body||n.title}</p><time className="text-sm text-cool-gray">{new Date(n.createdAt).toLocaleString(locale)}</time>{deepLink&&<Link className="kcc-action" href={deepLink}>{t.open} →</Link>}<div className="kcc-actions">{!read&&<button disabled={pending} className="kcc-action" onClick={()=>update(false)}>{t.read}</button>}{n.acknowledgementRequired&&!ack&&<button disabled={pending} className="kcc-action" onClick={()=>update(true)}>{t.acknowledge}</button>}{ack&&<span className="text-emerald-300">{t.acknowledged}</span>}</div>{error&&<p role="alert">{error}</p>}</div></Drawer></div></article>;
}
