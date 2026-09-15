'use client';

import { useState, useTransition } from 'react';
import { transitionWorkOrder } from '@/lib/work-orders/actions';

export function TransitionButtons({
  workOrderId,
  allowedTransitions,
}: {
  workOrderId: string;
  allowedTransitions: string[];
}) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function handleClick(toStatus: string) {
    setError(null);
    startTransition(async () => {
      const result = await transitionWorkOrder(workOrderId, toStatus);
      if (result?.error) setError(result.error);
    });
  }

  if (allowedTransitions.length === 0) {
    return <p className="text-xs text-cool-gray">No transitions available for your role at this status.</p>;
  }

  return (
    <div>
      <div className="flex flex-wrap gap-2">
        {allowedTransitions.map((status) => (
          <button
            key={status}
            disabled={isPending}
            onClick={() => handleClick(status)}
            className="border border-gold-dim text-gold text-[10.5px] uppercase tracking-[0.08em] px-3 py-2 rounded-sm hover:bg-gold hover:text-navy transition-colors disabled:opacity-40"
          >
            → {status.replace(/_/g, ' ')}
          </button>
        ))}
      </div>
      {error && (
        <p className="text-xs text-red-400 mt-3" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
