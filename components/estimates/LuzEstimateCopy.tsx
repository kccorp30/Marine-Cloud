'use client';

import { useState, useTransition } from 'react';
import { luzEstimateMessageAction } from '@/lib/communications/actions';

type Tone = 'professional' | 'warm' | 'concise';

type Context = {
  customerName?: string | null;
  vesselName?: string | null;
  estimateNumber?: string | null;
  services?: string[];
  language?: 'en' | 'es';
};

export function LuzEstimateCopy({
  value,
  onApply,
  context,
}: {
  value: string;
  onApply: (value: string) => void;
  context: Context;
}) {
  const [pending, startTransition] = useTransition();
  const [draft, setDraft] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [tone, setTone] = useState<Tone>('professional');
  const es = context.language === 'es';

  function generate(nextTone: Tone = tone) {
    setTone(nextTone);
    setError('');
    const form = new FormData();
    form.set('existingMessage', value.trim());
    form.set('customerName', context.customerName ?? '');
    form.set('vesselName', context.vesselName ?? '');
    form.set('estimateNumber', context.estimateNumber ?? '');
    form.set('services', (context.services ?? []).join('\n'));
    form.set('language', context.language ?? 'en');
    form.set('tone', nextTone);

    startTransition(async () => {
      const result = await luzEstimateMessageAction(form);
      if (result.error) {
        setError(result.error);
        return;
      }
      setDraft(result.result?.message ?? null);
    });
  }

  return (
    <div className="luz-estimate-assistant mt-3 overflow-hidden rounded-2xl border border-cyan-300/20 bg-[radial-gradient(circle_at_top_right,rgba(36,166,255,.14),transparent_42%),rgba(4,18,39,.72)]">
      <div className="flex flex-wrap items-center justify-between gap-3 p-4">
        <div className="flex items-center gap-3">
          <span className="luz-orb !h-9 !w-9 !min-w-9" aria-hidden="true">✦</span>
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-cyan-100">Luz · Estimate Concierge</p>
            <p className="mt-1 text-xs text-cool-gray">
              {es ? 'Genera o mejora el mensaje usando los datos reales de este estimado.' : 'Generate or improve the note using the real details in this estimate.'}
            </p>
          </div>
        </div>
        <button
          type="button"
          className="kcc-action min-w-[150px]"
          disabled={pending}
          onClick={() => generate(tone)}
        >
          {pending ? (es ? 'Luz está escribiendo…' : 'Luz is writing…') : value.trim() ? (es ? 'Mejorar con Luz' : 'Improve with Luz') : (es ? 'Generar con Luz' : 'Generate with Luz')}
        </button>
      </div>

      <div className="flex flex-wrap gap-2 border-t border-white/10 px-4 py-3">
        {([
          ['professional', es ? 'Profesional' : 'Professional'],
          ['warm', es ? 'Cálido' : 'Warm'],
          ['concise', es ? 'Directo' : 'Concise'],
        ] as [Tone, string][]).map(([key, label]) => (
          <button
            key={key}
            type="button"
            disabled={pending}
            onClick={() => generate(key)}
            className={`rounded-full border px-3 py-1.5 text-xs transition ${tone === key ? 'border-cyan-300/50 bg-cyan-300/10 text-cyan-100' : 'border-white/10 text-cool-gray hover:border-white/25 hover:text-white'}`}
          >
            {label}
          </button>
        ))}
      </div>

      {error && <p role="alert" className="mx-4 mb-4 rounded-xl border border-amber-300/20 bg-amber-300/5 p-3 text-xs text-amber-100">{error}</p>}
      {draft && (
        <div className="border-t border-white/10 p-4">
          <p className="mb-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-cyan-200">{es ? 'Borrador de Luz' : 'Luz draft'}</p>
          <p className="whitespace-pre-wrap rounded-xl border border-white/10 bg-black/15 p-4 text-sm leading-relaxed text-slate-100">{draft}</p>
          <div className="mt-3 flex flex-wrap gap-3">
            <button type="button" className="kcc-action" onClick={() => { onApply(draft); setDraft(null); }}>
              {es ? 'Usar este mensaje' : 'Use this message'}
            </button>
            <button type="button" className="rounded-xl px-3 py-2 text-xs text-cyan-100 hover:bg-white/5" disabled={pending} onClick={() => generate(tone)}>
              {es ? 'Generar otra versión' : 'Generate another version'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
