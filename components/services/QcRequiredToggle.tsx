'use client';

import { useTransition } from 'react';
import { toggleServiceQcRequired } from '@/lib/services/actions';

export function QcRequiredToggle({ serviceId, qcRequired }: { serviceId: string; qcRequired: boolean }) {
  const [pending, startTransition] = useTransition();
  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => startTransition(() => toggleServiceQcRequired(serviceId, !qcRequired))}
      className={'font-mono text-[9px] uppercase tracking-[0.06em] px-2 py-1 rounded-sm border ' + (qcRequired ? 'border-gold-dim text-gold' : 'border-white/15 text-cool-gray')}
    >
      QC {qcRequired ? 'Required' : 'Not Required'}
    </button>
  );
}
