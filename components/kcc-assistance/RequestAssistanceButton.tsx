'use client';

import { useState, useTransition } from 'react';
import { requestKccAssistanceAction } from '@/lib/kcc-assistance/actions';

const CATEGORIES = ['parts', 'technical', 'access', 'safety', 'scheduling', 'other'];

export function RequestAssistanceButton({ workOrderId }: { workOrderId: string }) {
  const [pending, startTransition] = useTransition();
  const [open, setOpen] = useState(false);
  const [category, setCategory] = useState('technical');
  const [urgency, setUrgency] = useState('normal');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  if (sent) return <p className="text-xs text-emerald-400">Assistance requested — KCC has been notified.</p>;

  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="text-[10px] font-mono uppercase border border-red-500/30 text-red-400 px-3 py-1.5 rounded-sm">
        Request KCC Assistance
      </button>
    );
  }

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-2 gap-2">
        <select value={category} onChange={(e) => setCategory(e.target.value)} className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5">
          {CATEGORIES.map((c) => (
            <option key={c} value={c} className="bg-navy">{c}</option>
          ))}
        </select>
        <select value={urgency} onChange={(e) => setUrgency(e.target.value)} className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5">
          <option value="normal" className="bg-navy">Normal</option>
          <option value="high" className="bg-navy">High</option>
          <option value="critical" className="bg-navy">Critical</option>
        </select>
      </div>
      <textarea
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        rows={3}
        placeholder="What do you need help with?"
        className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
      />
      {error && <p className="text-xs text-red-400">{error}</p>}
      <div className="flex gap-2">
        <button
          type="button"
          disabled={pending}
          onClick={() => {
            setError(null);
            const formData = new FormData();
            formData.set('workOrderId', workOrderId);
            formData.set('category', category);
            formData.set('urgency', urgency);
            formData.set('notes', notes);
            startTransition(async () => {
              const res = await requestKccAssistanceAction(formData);
              if (res?.error) {
                setError(res.error);
                return;
              }
              setSent(true);
            });
          }}
          className="text-[10px] font-mono uppercase bg-red-500/80 text-white px-3 py-1.5 rounded-sm"
        >
          {pending ? 'Sending…' : 'Send Request'}
        </button>
        <button type="button" onClick={() => setOpen(false)} className="text-[10px] font-mono uppercase text-cool-gray px-3 py-1.5">
          Cancel
        </button>
      </div>
    </div>
  );
}
