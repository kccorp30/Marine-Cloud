'use client';
import {useState} from 'react';
import {deactivateTeamMember} from '@/lib/team/actions';
import {useCommandCopy} from '@/components/ui/LocaleProvider';
import {workspaceCopy} from '@/lib/i18n/workspace-copy';
import {useRouter} from 'next/navigation';
export function DeactivateMember({id}:{id:string}){const {locale}=useCommandCopy();const t=workspaceCopy[locale];const [confirm,setConfirm]=useState(false);const [pending,setPending]=useState(false);const [error,setError]=useState('');const router=useRouter();return <div>{!confirm?<button className="kcc-action" onClick={()=>setConfirm(true)}>{t.deactivate}</button>:<div className="space-y-3"><p className="text-sm">{t.deactivateHelp}</p><button className="kcc-action" disabled={pending} onClick={async()=>{setPending(true);setError('');try{const result=await deactivateTeamMember(id);if(result?.error)setError(result.error);else{setConfirm(false);router.refresh();}}catch{setError(t.saved==='Saved'?'Could not update access.':'No se pudo actualizar el acceso.');}finally{setPending(false);}}}>{pending?'…':t.confirm}</button><button className="kcc-action" disabled={pending} onClick={()=>setConfirm(false)}>{t.cancel}</button></div>}{error&&<p role="alert" className="text-red-300">{error}</p>}</div>;}
