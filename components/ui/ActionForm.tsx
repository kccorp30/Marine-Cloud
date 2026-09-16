"use client";
import { createPortal } from "react-dom";
import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useCommandCopy } from "./LocaleProvider";

export function ActionForm({ action, children, className = "", resetOnSuccess = false }: {
  action: (data: FormData) => Promise<{ error?: string; redirectTo?: string } | void>;
  children: React.ReactNode; className?: string; resetOnSuccess?: boolean;
}) {
  const [pending, setPending] = useState(false);
  const [mounted, setMounted] = useState(false);
  const [result, setResult] = useState<{error?: string; ok?: boolean}>({});
  const {locale} = useCommandCopy();
  const router = useRouter();
  useEffect(() => { setMounted(true); }, []);
  useEffect(()=>{if(!result.ok)return;const timer=setTimeout(()=>setResult({}),5000);return()=>clearTimeout(timer);},[result.ok]);
  return <form className={className} onSubmit={async event => {
    event.preventDefault(); if (pending) return;
    const form = event.currentTarget; const data = new FormData(form);
    setPending(true); setResult({});
    try {
      const response = await action(data);
      if (response?.error) setResult({error: response.error});
      else { setResult({ok:true}); if(resetOnSuccess) form.reset(); const section=form.closest("details");if(section)section.open=false; form.closest("dialog")?.close(); if(response?.redirectTo)router.push(response.redirectTo);router.refresh(); }
    } catch { setResult({error: locale === 'es' ? 'No se pudo guardar. Revisa tu conexión e inténtalo nuevamente.' : 'Could not save. Check your connection and try again.'}); }
    finally { setPending(false); }
  }}>
    {mounted && result.ok && createPortal(<div role="status" className="fixed bottom-6 left-4 right-4 sm:left-auto sm:right-6 z-[100] rounded-2xl border border-emerald-300/30 bg-[#092b28] text-emerald-100 px-5 py-4 shadow-2xl">{locale==='es'?'✓ Guardado correctamente.':'✓ Saved successfully.'}</div>,document.body)}
    <fieldset disabled={pending} className="contents">{children}</fieldset>
    <div aria-live="polite" className="col-span-full text-sm">
      {pending && <p>{locale === 'es' ? 'Guardando…' : 'Saving…'}</p>}
      {result.error && <p role="alert" className="text-red-300">{result.error}</p>}
      {result.ok && <p className="text-emerald-300">{locale === 'es' ? 'Guardado correctamente.' : 'Saved successfully.'}</p>}
    </div>
  </form>;
}
