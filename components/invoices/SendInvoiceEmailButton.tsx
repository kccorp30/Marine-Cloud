'use client';

import { useState, useTransition } from 'react';
import { sendInvoiceEmailAction } from '@/lib/communications/actions';

export function SendInvoiceEmailButton({ invoiceId }: { invoiceId: string }) {
  const [pending, startTransition] = useTransition();
  const [open, setOpen] = useState(false);
  const [intro, setIntro] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  if (sent) return <p className="text-xs text-emerald-400">Sent to customer.</p>;

  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
        Email to Customer
      </button>
    );
  }

  return (
    <div className="space-y-2">
      <textarea
        value={intro}
        onChange={(e) => setIntro(e.target.value)}
        rows={3}
        placeholder="Optional personal note (the invoice number, total, and balance are added automatically)"
        className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
      />
      {error && <p className="text-xs text-red-400">{error}</p>}
      <div className="flex gap-3">
        <button
          type="button"
          disabled={pending}
          onClick={() => {
            setError(null);
            const formData = new FormData();
            formData.set('invoiceId', invoiceId);
            formData.set('customIntro', intro);
            formData.set('idempotencyKey', crypto.randomUUID());
            startTransition(async () => {
              const res = await sendInvoiceEmailAction(formData);
              if (res?.error) {
                setError(res.error);
                return;
              }
              setSent(true);
            });
          }}
          className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm"
        >
          {pending ? 'Sending…' : 'Send'}
        </button>
        <button type="button" onClick={() => setOpen(false)} className="text-[10px] font-mono uppercase text-cool-gray px-3 py-1.5">
          Cancel
        </button>
      </div>
    </div>
  );
}
