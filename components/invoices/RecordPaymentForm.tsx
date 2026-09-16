'use client';

import { useState, useTransition } from 'react';
import { recordManualPaymentAction } from '@/lib/invoices/actions';
import { Field, inputClass } from '@/components/ui/primitives';

const METHODS = ['zelle', 'cash', 'bank_transfer', 'check', 'other_manual'];

export function RecordPaymentForm({ invoiceId, balanceDue }: { invoiceId: string; balanceDue: number }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  return (
    <form
      action={(formData) => {
        setError(null);
        startTransition(async () => {
          const res = await recordManualPaymentAction(formData);
          if (res?.error) setError(res.error);
        });
      }}
      className="space-y-3"
    >
      <input type="hidden" name="invoiceId" value={invoiceId} />
      <div className="grid grid-cols-2 gap-3">
        <Field label="Amount">
          <input name="amount" type="number" step="0.01" max={balanceDue} required className={inputClass} />
        </Field>
        <Field label="Method">
          <select name="method" required className={inputClass} defaultValue="zelle">
            {METHODS.map((m) => (
              <option key={m} value={m} className="bg-navy">
                {m.replace('_', ' ')}
              </option>
            ))}
          </select>
        </Field>
      </div>
      <Field label="Reference (optional)">
        <input name="reference" className={inputClass} placeholder="Confirmation #, check #, etc." />
      </Field>
      <Field label="Notes (optional)">
        <input name="notes" className={inputClass} />
      </Field>
      {error && <p className="text-xs text-red-400">{error}</p>}
      <button type="submit" disabled={pending} className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
        {pending ? 'Recording…' : 'Record Payment'}
      </button>
    </form>
  );
}
