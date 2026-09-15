'use client';

import { useState, useTransition } from 'react';
import { translateDraftAction } from '@/lib/communications/actions';

/**
 * Luz's estimate-writing surface. It only drafts copy; sending remains behind
 * the existing estimate preview/fingerprint flow and the official email RPC.
 */
export function LuzEstimateCopy({ value, onApply }: { value: string; onApply: (value: string) => void }) {
  const [pending, startTransition] = useTransition();
  const [draft, setDraft] = useState<string | null>(null);
  const [error, setError] = useState('');

  function polish() {
    setError('');
    const form = new FormData();
    form.set('sourceText', value.trim());
    form.set('targetLanguage', 'en');
    form.set('mode', 'professional');
    startTransition(async () => {
      const result = await translateDraftAction(form);
      if (result.error) {
        setError(result.error);
        return;
      }
      if (result.result?.tokensPreserved === false) {
        setError('Luz detected a number or identifier change. Review the draft manually.');
        return;
      }
      setDraft(result.result?.translatedText ?? null);
    });
  }

  return (
    <div className="mt-3 rounded-2xl border border-cyan-300/20 bg-cyan-300/[0.04] p-3">
      <div className="flex items-center justify-between gap-3">
        <p className="text-xs font-semibold uppercase tracking-[0.18em] text-cyan-200">✦ Luz · Estimate concierge</p>
        <button type="button" className="text-xs text-cyan-200 hover:text-white disabled:opacity-50" disabled={pending || !value.trim()} onClick={polish}>
          {pending ? 'Preparing…' : 'Polish message'}
        </button>
      </div>
      <p className="mt-1 text-xs text-cool-gray">Luz improves tone and clarity without changing prices, IDs or technical facts.</p>
      {error && <p role="alert" className="mt-2 text-xs text-amber-200">{error}</p>}
      {draft && (
        <div className="mt-3 space-y-2">
          <p className="whitespace-pre-wrap rounded-xl border border-white/10 bg-black/10 p-3 text-sm text-slate-100">{draft}</p>
          <button type="button" className="text-xs text-gold hover:text-white" onClick={() => onApply(draft)}>Use Luz’s draft</button>
        </div>
      )}
    </div>
  );
}
