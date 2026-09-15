/// <reference types="react-dom/canary" />
"use client";
import {useFormStatus} from 'react-dom';
import {useCommandCopy} from './LocaleProvider';
export function PendingSubmit({children}:{children:React.ReactNode}){const {pending}=useFormStatus();const {locale}=useCommandCopy();return <button type="submit" disabled={pending} aria-busy={pending} className="command-action">{pending?(locale==='es'?'Guardando…':'Saving…'):children}</button>;}
