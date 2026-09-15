'use client';

import { useTransition } from 'react';
import { toggleServiceActive } from '@/lib/services/actions';

export function ActiveToggle({ serviceId, active }: { serviceId: string; active: boolean }) {
  const [pending, startTransition] = useTransition();
  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => startTransition(() => toggleServiceActive(serviceId, !active))}
      className={
        'font-mono text-[9px] uppercase tracking-[0.06em] px-2 py-1 rounded-sm border ' +
        (active ? 'border-gold-dim text-gold' : 'border-white/15 text-cool-gray')
      }
    >
      {active ? 'Active' : 'Inactive'}
    </button>
  );
}
