"use client";
import {useEffect,useState,useTransition} from 'react';
import {useRouter} from 'next/navigation';
import {changeShift} from '@/lib/payroll/actions';
import {useCommandCopy} from '@/components/ui/LocaleProvider';
export interface Shift {id:string;started_at:string;paused_at:string|null;break_seconds:number;pay_type:string|null;pay_rate:number|null;currency:string|null;}
export function ShiftClock({shift,locked=false}:{shift:Shift|null;locked?:boolean}){
 const {locale}=useCommandCopy();const es=locale==='es';const router=useRouter();const [now,setNow]=useState(Date.now());const [pending,start]=useTransition();const [error,setError]=useState('');const [confirmEnd,setConfirmEnd]=useState(false);
 useEffect(()=>{const timer=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(timer);},[]);
 const seconds=shift?Math.max(0,Math.floor(((shift.paused_at?Date.parse(shift.paused_at):now)-Date.parse(shift.started_at))/1000-Number(shift.break_seconds))):0;
 const time=[Math.floor(seconds/3600),Math.floor(seconds%3600/60),seconds%60].map(n=>String(n).padStart(2,'0')).join(':');
 function run(action:string){start(async()=>{setError('');try{const r=await changeShift(action);if(r.error)setError(r.error);else{setConfirmEnd(false);router.refresh();}}catch{setError(es?'No se pudo actualizar el reloj.':'Could not update the clock.');}});}
 return <section className={`premium-card rounded-2xl p-5 ${locked?'max-w-xl mx-auto my-10':'mb-5'}`}>
 <div className="flex flex-wrap justify-between items-center gap-4"><div><p className="text-gold text-sm">{es?'Mi jornada':'My workday'}</p><p className="font-display text-3xl tabular-nums" suppressHydrationWarning>{time}</p>{shift?.pay_rate!=null&&shift.currency&&<p className="text-sm text-cool-gray">{new Intl.NumberFormat(locale,{style:'currency',currency:shift.currency}).format(shift.pay_rate)} / {shift.pay_type==='daily'?(es?'día':'day'):(es?'hora':'hour')}</p>}</div>
 <div className="flex flex-wrap gap-3">{!shift?<button className="command-action" disabled={pending} onClick={()=>run('start')}>{es?'Iniciar mi día':'Start my day'}</button>:<><button className="command-action" disabled={pending} onClick={()=>run(shift.paused_at?'resume':'pause')}>{shift.paused_at?(es?'Continuar':'Resume'):(es?'Pausa':'Pause')}</button><button disabled={pending} onClick={()=>setConfirmEnd(!confirmEnd)}>{es?'Finalizar día':'End day'}</button></>}</div></div>
 {locked&&<p className="mt-4 text-cool-gray">{es?'Inicia tu jornada para abrir tus trabajos. Tu reloj continuará aunque cierres la aplicación.':'Start your workday to open your jobs. Your clock continues when you close the app.'}</p>}
 {confirmEnd&&<div className="mt-4 border-t border-white/10 pt-4"><p>{es?'¿Finalizar la jornada? Usa Pausa si vas a continuar trabajando hoy.':'End your workday? Use Pause if you will continue working today.'}</p><button className="command-action mt-3" disabled={pending} onClick={()=>run('end')}>{es?'Confirmar cierre':'Confirm end'}</button></div>}
 {pending&&<p role="status">{es?'Actualizando…':'Updating…'}</p>}{error&&<p role="alert" className="text-red-300 mt-3">{error}</p>}
 </section>;
}
