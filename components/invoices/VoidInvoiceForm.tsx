'use client';

import { useState, useTransition } from 'react';
import { voidInvoiceAction } from '@/lib/invoices/actions';

export function VoidInvoiceForm({ invoiceId }: { invoiceId: string }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [open, setOpen] = useState(false);

  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="text-[10px] font-mono uppercase border border-red-500/30 text-red-400 px-3 py-1.5 rounded-sm">
        Void Invoice
      </button>
    );
  }

  return (
    <div className="space-y-2">
      <input
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="Reason (required)"
        className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
      />
      {error && <p className="text-xs text-red-400">{error}</p>}
      <div className="flex gap-3">
        <button
          type="button"
          disabled={pending || !reason.trim()}
          onClick={() => {
            setError(null);
            const formData = new FormData();
            formData.set('invoiceId', invoiceId);
            formData.set('reason', reason);
            startTransition(async () => {
              const res = await voidInvoiceAction(formData);
              if (res?.error) setError(res.error);
            });
          }}
          className="text-[10px] font-mono uppercase border border-red-500/40 text-red-400 px-3 py-1.5 rounded-sm"
        >
          {pending ? 'Voiding…' : 'Confirm Void'}
        </button>
        <button type="button" onClick={() => setOpen(false)} className="text-[10px] font-mono uppercase text-cool-gray px-3 py-1.5">
          Cancel
        </button>
      </div>
    </div>
  );
}
