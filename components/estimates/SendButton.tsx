'use client';

import { useState, useTransition } from 'react';
import { sendEstimateAction } from '@/lib/estimates/actions';

export function SendButton({ estimateId }: { estimateId: string }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  return (
    <div>
      <button
        type="button"
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            setError(null);
            const res = await sendEstimateAction(estimateId);
            if (res?.error) setError(res.error);
          })
        }
        className="text-[10px] font-mono uppercase tracking-[0.06em] bg-gold text-navy px-3 py-1.5 rounded-sm"
      >
        {pending ? 'Sending…' : 'Send to Customer'}
      </button>
      {error && <p className="text-xs text-red-400 mt-2">{error}</p>}
    </div>
  );
}
