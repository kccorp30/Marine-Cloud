"use client";
import {useEffect,useState} from 'react';
import {useCommandCopy} from './LocaleProvider';
interface InstallPrompt extends Event {prompt:()=>Promise<void>;userChoice:Promise<{outcome:string}>;}
export function InstallApp(){
 const {locale}=useCommandCopy();const es=locale==='es';const [prompt,setPrompt]=useState<InstallPrompt|null>(null);const [installed,setInstalled]=useState(true);const [help,setHelp]=useState(false);
 useEffect(()=>{if('serviceWorker' in navigator)navigator.serviceWorker.register('/install-worker.js').catch(()=>{});setInstalled(window.matchMedia('(display-mode: standalone)').matches || !!(navigator as Navigator & {standalone?:boolean}).standalone);const ready=(e:Event)=>{e.preventDefault();setPrompt(e as InstallPrompt);};const done=()=>setInstalled(true);window.addEventListener('beforeinstallprompt',ready);window.addEventListener('appinstalled',done);return()=>{window.removeEventListener('beforeinstallprompt',ready);window.removeEventListener('appinstalled',done);};},[]);
 if(installed)return null;
 return <div className="text-sm"><button type="button" className="w-full text-gold py-3 rounded-xl border border-white/15" onClick={async()=>{if(prompt){await prompt.prompt();const result=await prompt.userChoice;if(result.outcome==='accepted')setInstalled(true);setPrompt(null);}else setHelp(!help);}}>{es?'＋ Instalar Marine Cloud':'＋ Install Marine Cloud'}</button>{help&&<p role="status" className="text-cool-gray mt-3 leading-relaxed">{es?'En iPhone abre Compartir y elige “Agregar a inicio”. En Android abre el menú del navegador y elige “Instalar aplicación” o “Agregar a pantalla principal”.':'On iPhone, open Share and choose “Add to Home Screen”. On Android, open the browser menu and choose “Install app” or “Add to Home screen”.'}</p>}</div>;
}
