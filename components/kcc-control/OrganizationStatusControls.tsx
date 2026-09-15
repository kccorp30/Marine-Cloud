'use client';

import { useTransition, useState } from 'react';
import { setOrganizationStatusAction } from '@/lib/kcc-control/actions';

export function OrganizationStatusControls({ organizationId, currentStatus }: { organizationId: string; currentStatus: string }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function change(status: string) {
    setError(null);
    startTransition(async () => {
      const res = await setOrganizationStatusAction(organizationId, status);
      if (res?.error) setError(res.error);
    });
  }

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        {currentStatus !== 'active' && (
          <button type="button" disabled={pending} onClick={() => change('active')} className="text-[10px] font-mono uppercase bg-emerald-500/80 text-white px-3 py-1.5 rounded-sm">
            Activate
          </button>
        )}
        {currentStatus !== 'suspended' && (
          <button type="button" disabled={pending} onClick={() => change('suspended')} className="text-[10px] font-mono uppercase bg-red-500/80 text-white px-3 py-1.5 rounded-sm">
            Suspend
          </button>
        )}
        {currentStatus !== 'inactive' && (
          <button type="button" disabled={pending} onClick={() => change('inactive')} className="text-[10px] font-mono uppercase border border-white/15 text-cool-gray px-3 py-1.5 rounded-sm">
            Mark Inactive
          </button>
        )}
      </div>
      {error && <p className="text-xs text-red-400">{error}</p>}
      {currentStatus === 'suspended' && (
        <p className="text-xs text-red-400">Suspended — members lose normal operational access until reactivated. Historical data is preserved.</p>
      )}
    </div>
  );
}
