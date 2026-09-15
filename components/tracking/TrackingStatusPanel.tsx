'use client';

import { useEffect, useState, useCallback, useMemo } from 'react';
import {useCommandCopy} from '@/components/ui/LocaleProvider';
import { createClient } from '@/lib/supabase/client';

// =========================================================
// TrackingStatusPanel — Phase 12
// =========================================================
// Realtime is convenience only — on mount, reconnect, and tab
// restore this always re-fetches the authoritative latest point via
// get_work_order_tracking_status() rather than trusting subscription
// memory (brief section 14). Stale/offline locations are NEVER
// presented as live — the freshness label always reflects the
// server's own classification (LIVE/STALE/OFFLINE, section 16),
// never re-derived independently here.
//
// Map: lightweight static OSM tile image (no new map SDK dependency)
// plus a deep link to the device's native maps app — see
// docs/PHASE-12-REPORT.md for the rationale.
// =========================================================

interface TrackingStatus {
  trackingStatus: 'unavailable' | 'active_no_location_yet' | 'active';
  freshness?: 'live' | 'stale' | 'offline';
  latitude?: number;
  longitude?: number;
  accuracyMeters?: number;
  recordedAt?: string;
  secondsAgo?: number;
}

const FRESHNESS_LABEL: Record<string, string> = {
  live: 'Live',
  stale: 'Last known location',
  offline: 'Location unavailable',
};

export function TrackingStatusPanel({ workOrderId }: { workOrderId: string }) {
  const {locale}=useCommandCopy();const es=locale==='es';
  const [status, setStatus] = useState<TrackingStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const supabase = useMemo(() => createClient(), []);

  const fetchStatus = useCallback(async () => {
    const { data, error } = await supabase.rpc('get_work_order_tracking_status', { p_work_order_id: workOrderId });
    if (!error && data) setStatus(data as TrackingStatus);
    else setStatus(null);
    setLoading(false);
  }, [supabase, workOrderId]);

  useEffect(() => {
    fetchStatus();

    // Realtime is a convenience nudge to re-fetch — never the source
    // of truth by itself.
    const channel = supabase
      .channel(`tracking-${workOrderId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'technician_locations', filter: `work_order_id=eq.${workOrderId}` }, () => {
        fetchStatus();
      })
      .subscribe();

    function handleVisibility() {
      if (document.visibilityState === 'visible') fetchStatus();
    }
    document.addEventListener('visibilitychange', handleVisibility);
    window.addEventListener('online', fetchStatus);

    // Poll fallback every 30s in case realtime silently drops —
    // authoritative fetch either way.
    const interval = setInterval(fetchStatus, 30_000);

    return () => {
      supabase.removeChannel(channel);
      document.removeEventListener('visibilitychange', handleVisibility);
      window.removeEventListener('online', fetchStatus);
      clearInterval(interval);
    };
  }, [fetchStatus, supabase, workOrderId]);

  if (loading) return <div className="text-sm text-cool-gray">{es?'Cargando ubicación…':'Loading tracking status…'}</div>;

  if (!status || status.trackingStatus === 'unavailable') {
    return <div className="text-sm text-cool-gray">{es?'La ubicación no se está compartiendo para esta orden.':'Location sharing is not active for this work order.'}</div>;
  }

  if (status.trackingStatus === 'active_no_location_yet') {
    return <div className="text-sm text-cool-gray">{es?'Seguimiento iniciado. Esperando la primera ubicación.':'Tracking started. Waiting for the first location update.'}</div>;
  }

  const isLive = status.freshness === 'live';

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <span className={`font-mono text-[10px] uppercase ${isLive ? 'text-emerald-400' : 'text-cool-gray'}`}>{FRESHNESS_LABEL[status.freshness ?? 'offline']}</span>
        {typeof status.secondsAgo === 'number' && !isLive && <span className="text-xs text-cool-gray">Updated {Math.round(status.secondsAgo / 60)} min ago</span>}
      </div>

      {typeof status.latitude === 'number' && typeof status.longitude === 'number' && Number.isFinite(status.latitude) && Number.isFinite(status.longitude) && (
        <>
          <iframe title="Technician location map" loading="lazy" referrerPolicy="no-referrer" className="w-full h-80 rounded-2xl border border-white/15" src={`https://www.openstreetmap.org/export/embed.html?bbox=${encodeURIComponent([status.longitude-0.015,status.latitude-0.01,status.longitude+0.015,status.latitude+0.01].join(','))}&layer=mapnik&marker=${encodeURIComponent(`${status.latitude},${status.longitude}`)}`} />
          {status.recordedAt && <p className="text-xs text-cool-gray">{new Date(status.recordedAt).toLocaleString()}</p>}
          <a
            href={`https://www.google.com/maps?q=${status.latitude},${status.longitude}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-[10px] font-mono uppercase text-gold"
          >
            {es?'Abrir mapa →':'Open in Maps →'}
          </a>
        </>
      )}
    </div>
  );
}
