'use client';

import { useState, useTransition } from 'react';
import { createCompensationAgreementAction, deactivateCompensationAgreementAction } from '@/lib/kcc-control/actions';
import type { CompensationAgreementRow } from '@/lib/kcc-control/company-data';

export function CompensationPanel({
  organizationId,
  currentAgreement,
  history,
}: {
  organizationId: string;
  currentAgreement: CompensationAgreementRow | null;
  history: CompensationAgreementRow[];
}) {
  const [pending, startTransition] = useTransition();
  const [open, setOpen] = useState(false);
  const [type, setType] = useState('percentage');
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="space-y-3">
      {currentAgreement ? (
        <div className="bg-white/[0.03] border border-gold/30 rounded-sm p-4">
          <div className="font-mono text-[9px] uppercase text-gold mb-1">Current Agreement</div>
          <div className="text-sm">
            {currentAgreement.compensationType === 'percentage'
              ? `${currentAgreement.percentageRate}%`
              : `$${currentAgreement.fixedAmount} fixed`}{' '}
            <span className="text-cool-gray">
              · effective {new Date(currentAgreement.effectiveFrom).toLocaleDateString()}
              {currentAgreement.effectiveUntil ? ` – ${new Date(currentAgreement.effectiveUntil).toLocaleDateString()}` : ' – ongoing'}
            </span>
          </div>
          {currentAgreement.notes && <p className="text-xs text-cool-gray mt-1">{currentAgreement.notes}</p>}
          <button
            type="button"
            disabled={pending}
            onClick={() => startTransition(async () => { await deactivateCompensationAgreementAction(currentAgreement.id, organizationId); })}
            className="mt-2 text-[10px] font-mono uppercase text-red-400"
          >
            Deactivate
          </button>
        </div>
      ) : (
        <p className="text-sm text-cool-gray">No active compensation agreement.</p>
      )}

      {history.length > 0 && (
        <div>
          <div className="font-mono text-[9px] uppercase text-cool-gray mb-2">History</div>
          <div className="space-y-1">
            {history.map((a) => (
              <div key={a.id} className={`text-xs ${a.active ? 'text-gold' : 'text-cool-gray'}`}>
                {a.compensationType === 'percentage' ? `${a.percentageRate}%` : `$${a.fixedAmount} fixed`} —{' '}
                {new Date(a.effectiveFrom).toLocaleDateString()}
                {a.effectiveUntil ? ` – ${new Date(a.effectiveUntil).toLocaleDateString()}` : ' – ongoing'}
                {!a.active && ' (inactive)'}
              </div>
            ))}
          </div>
        </div>
      )}

      {!open ? (
        <button type="button" onClick={() => setOpen(true)} className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
          + New Agreement
        </button>
      ) : (
        <form
          action={(formData) => {
            setError(null);
            startTransition(async () => {
              const res = await createCompensationAgreementAction(formData);
              if (res?.error) {
                setError(res.error);
                return;
              }
              setOpen(false);
            });
          }}
          className="space-y-2 bg-white/[0.03] border border-white/10 rounded-sm p-4"
        >
          <input type="hidden" name="organizationId" value={organizationId} />
          <select name="compensationType" value={type} onChange={(e) => setType(e.target.value)} className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5">
            <option value="percentage" className="bg-navy">Percentage</option>
            <option value="fixed" className="bg-navy">Fixed</option>
          </select>
          {type === 'percentage' ? (
            <input name="percentageRate" type="number" step="0.001" min="0" max="100" placeholder="Rate %" required className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2 w-full" />
          ) : (
            <input name="fixedAmount" type="number" step="0.01" min="0" placeholder="Fixed amount" required className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2 w-full" />
          )}
          <div className="grid grid-cols-2 gap-2">
            <input name="effectiveFrom" type="date" required className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
            <input name="effectiveUntil" type="date" placeholder="Optional end date" className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          </div>
          <textarea name="notes" rows={2} placeholder="Notes (optional)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          {error && <p className="text-xs text-red-400">{error}</p>}
          <div className="flex gap-2">
            <button type="submit" disabled={pending} className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
              Create
            </button>
            <button type="button" onClick={() => setOpen(false)} className="text-[10px] font-mono uppercase text-cool-gray px-3 py-1.5">
              Cancel
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
