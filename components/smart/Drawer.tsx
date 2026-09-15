'use client';
import {useRef, useId} from 'react';
import {useCommandCopy} from '@/components/ui/LocaleProvider';
export function Drawer({label,title,children}:{label:React.ReactNode;title:string;children:React.ReactNode}){
 const ref=useRef<HTMLDialogElement>(null);const id=useId();const {t}=useCommandCopy();
 return <><button type="button" className="kcc-action" onClick={()=>ref.current?.showModal()}>{label}</button><dialog ref={ref} className="kcc-drawer" aria-labelledby={id} onClick={e=>{if(e.target===e.currentTarget)ref.current?.close();}}><div className="kcc-drawer-inner"><header><h2 id={id}>{title}</h2><button type="button" className="kcc-icon-button" aria-label={t.close} onClick={()=>ref.current?.close()}>×</button></header>{children}</div></dialog></>;
}
