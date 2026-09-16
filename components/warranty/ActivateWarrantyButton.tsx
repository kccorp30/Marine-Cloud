'use client';

import { useState, useTransition } from 'react';
import { activateWarrantyAction } from '@/lib/warranty/actions';

export function ActivateWarrantyButton({
  workOrderId,
  serviceDefault,
}: {
  workOrderId: string;
  // Términos reales configurados en service_catalog para el servicio
  // de este work order — nunca un valor inventado. Si no hay
  // service_id o el servicio no tiene warranty configurada, queda
  // null y el staff debe ingresar la duración explícitamente.
  serviceDefault: { durationDays: number; coverageNotes: string | null } | null;
}) {
  const [open, setOpen] = useState(false);
  const [days, setDays] = useState(serviceDefault ? String(serviceDefault.durationDays) : '');
  const [notes, setNotes] = useState(serviceDefault?.coverageNotes ?? '');
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
        Activate Warranty
      </button>
    );
  }

  return (
    <div className="space-y-2">
      {serviceDefault ? (
        <p className="text-xs text-cool-gray">Using this service's configured warranty terms — override below if needed.</p>
      ) : (
        <p className="text-xs text-cool-gray">This service has no configured warranty terms. Enter the coverage duration explicitly.</p>
      )}
      <input
        type="number"
        value={days}
        onChange={(e) => setDays(e.target.value)}
        placeholder="Duration (days)"
        className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
      />
      <input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Coverage notes (optional)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
      {error && <p className="text-xs text-red-400">{error}</p>}
      <div className="flex gap-2">
        <button
          type="button"
          disabled={pending || !days}
          onClick={() => {
            setError(null);
            startTransition(async () => {
              const res = await activateWarrantyAction(workOrderId, Number(days), 'workmanship', notes || null);
              if (res?.error) {
                setError(res.error);
                return;
              }
              setOpen(false);
            });
          }}
          className="text-sm bg-gold text-navy px-4 py-2 rounded-sm"
        >
          Activate
        </button>
        <button type="button" onClick={() => setOpen(false)} className="text-sm text-cool-gray px-4 py-2">
          Cancel
        </button>
      </div>
    </div>
  );
}
