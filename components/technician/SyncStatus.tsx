'use client';

import { useEffect, useState } from 'react';
import { syncQueue } from '@/lib/offline/sync';
import { listQueue } from '@/lib/offline/queue';

// Vive en el layout de la app — visible en cualquier pantalla, no
// solo en el detalle de un work order, porque la cola puede tener
// items de más de un trabajo.
export function SyncStatus() {
  const [pendingCount, setPendingCount] = useState(0);
  const [failedCount, setFailedCount] = useState(0);
  const [syncing, setSyncing] = useState(false);

  async function refreshCounts() {
    const items = await listQueue();
    setPendingCount(items.filter((i) => i.status === 'pending' || i.status === 'syncing').length);
    setFailedCount(items.filter((i) => i.status === 'failed').length);
  }

  async function runSync() {
    setSyncing(true);
    await syncQueue();
    await refreshCounts();
    setSyncing(false);
  }

  useEffect(() => {
    refreshCounts();
    const onOnline = () => runSync();
    window.addEventListener('online', onOnline);
    const interval = setInterval(refreshCounts, 15000);
    return () => {
      window.removeEventListener('online', onOnline);
      clearInterval(interval);
    };
  }, []);

  if (pendingCount === 0 && failedCount === 0) return null;

  return (
    <div className="fixed bottom-3 left-3 right-3 z-40 max-w-md mx-auto">
      <div
        className={`flex items-center justify-between px-3 py-2 rounded-sm text-[11px] ${
          failedCount > 0 ? 'bg-red-500/15 border border-red-500/30 text-red-300' : 'bg-amber-500/15 border border-amber-500/30 text-amber-300'
        }`}
      >
        <span>
          {syncing
            ? 'Syncing…'
            : failedCount > 0
              ? `${failedCount} item(s) failed to sync — will retry`
              : `${pendingCount} item(s) queued offline`}
        </span>
        {!syncing && (
          <button onClick={runSync} className="uppercase tracking-[0.06em] underline">
            Retry now
          </button>
        )}
      </div>
    </div>
  );
}
