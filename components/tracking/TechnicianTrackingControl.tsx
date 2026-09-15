'use client';

import { useState, useRef, useCallback, useEffect } from 'react';
import { createClient } from '@/lib/supabase/client';

// =========================================================
// TechnicianTrackingControl — Phase 12
// =========================================================
// Best-effort browser GPS tracking. Honest about limitations: no
// guaranteed background tracking when the screen locks, the tab is
// backgrounded, or the OS suspends the page — see docs/PHASE-12-REPORT.md
// section on PWA/browser reality. Update strategy: watchPosition
// reports whenever the browser has a new fix, but we only actually
// SEND to the server when either (a) at least 15s have passed since
// the last send, or (b) the position moved more than ~25m — whichever
// comes first. This avoids flooding the server on dense GPS updates
// while staying responsive to real movement, without hardcoding an
// aggressive fixed interval.
// =========================================================

const MIN_SEND_INTERVAL_MS = 15_000;
const MIN_MOVEMENT_METERS = 25;

function haversineMeters(lat1: number, lon1: number, lat2: number, lon2: number) {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

type UiState = 'inactive' | 'active' | 'paused' | 'permission_denied' | 'signal_lost';

export function TechnicianTrackingControl({ workOrderId, canTrack }: { workOrderId: string; canTrack: boolean }) {
  const [uiState, setUiState] = useState<UiState>('inactive');
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [lastSentAt, setLastSentAt] = useState<Date | null>(null);
  const [error, setError] = useState<string | null>(null);
  const watchIdRef = useRef<number | null>(null);
  const lastSentRef = useRef<{ lat: number; lng: number; at: number } | null>(null);
  const signalLostTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const supabase = createClient();

  const sendLocation = useCallback(
    async (currentSessionId: string, pos: GeolocationPosition) => {
      const { latitude, longitude, accuracy, heading, speed } = pos.coords;
      const { error: rpcError } = await supabase.rpc('submit_technician_location', {
        p_session_id: currentSessionId,
        p_latitude: latitude,
        p_longitude: longitude,
        p_accuracy_meters: accuracy ?? null,
        p_heading_degrees: heading ?? null,
        p_speed_mps: speed ?? null,
        p_recorded_at: new Date(pos.timestamp).toISOString(),
      });
      if (rpcError) {
        console.error('[tracking] submit_technician_location failed', rpcError.message);
        return;
      }
      lastSentRef.current = { lat: latitude, lng: longitude, at: Date.now() };
      setLastSentAt(new Date());
      setUiState('active');
      if (signalLostTimeoutRef.current) clearTimeout(signalLostTimeoutRef.current);
      signalLostTimeoutRef.current = setTimeout(() => setUiState('signal_lost'), 60_000);
    },
    [supabase],
  );

  const handlePosition = useCallback(
    (currentSessionId: string, pos: GeolocationPosition) => {
      const last = lastSentRef.current;
      const now = Date.now();
      if (!last) {
        void sendLocation(currentSessionId, pos);
        return;
      }
      const elapsed = now - last.at;
      const moved = haversineMeters(last.lat, last.lng, pos.coords.latitude, pos.coords.longitude);
      if (elapsed >= MIN_SEND_INTERVAL_MS || moved >= MIN_MOVEMENT_METERS) {
        void sendLocation(currentSessionId, pos);
      }
    },
    [sendLocation],
  );

  const start = useCallback(async () => {
    setError(null);
    if (!('geolocation' in navigator)) {
      setError('This device does not support location sharing.');
      return;
    }

    const { data: session, error: startError } = await supabase.rpc('start_technician_tracking', { p_work_order_id: workOrderId });
    if (startError || !session) {
      setError(startError?.message ?? 'Could not start tracking.');
      return;
    }
    setSessionId(session.id);

    const watchId = navigator.geolocation.watchPosition(
      (pos) => handlePosition(session.id, pos),
      (geoError) => {
        if (geoError.code === geoError.PERMISSION_DENIED) {
          setUiState('permission_denied');
        } else {
          setUiState('signal_lost');
        }
      },
      { enableHighAccuracy: true, maximumAge: 10_000, timeout: 20_000 },
    );
    watchIdRef.current = watchId;
    setUiState('active');
  }, [workOrderId, supabase, handlePosition]);

  const pause = useCallback(async () => {
    if (!sessionId) return;
    if (watchIdRef.current !== null) {
      navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }
    const { error: pauseError } = await supabase.rpc('pause_technician_tracking', { p_session_id: sessionId });
    if (pauseError) {
      setError(pauseError.message);
      return;
    }
    setUiState('paused');
  }, [sessionId, supabase]);

  const resume = useCallback(async () => {
    if (!sessionId) return;
    setError(null);
    const { error: resumeError } = await supabase.rpc('resume_technician_tracking', { p_session_id: sessionId });
    if (resumeError) {
      // La sesión pudo haber quedado inválida (organización suspendida,
      // asignación removida, work order ya no en_route) — nunca se
      // reanuda a ciegas, el técnico debe iniciar una sesión nueva.
      setError(resumeError.message);
      setUiState('inactive');
      setSessionId(null);
      return;
    }
    const watchId = navigator.geolocation.watchPosition(
      (pos) => handlePosition(sessionId, pos),
      (geoError) => setUiState(geoError.code === geoError.PERMISSION_DENIED ? 'permission_denied' : 'signal_lost'),
      { enableHighAccuracy: true, maximumAge: 10_000, timeout: 20_000 },
    );
    watchIdRef.current = watchId;
    setUiState('active');
  }, [sessionId, supabase, handlePosition]);

  const stop = useCallback(async () => {
    if (watchIdRef.current !== null) {
      navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }
    if (signalLostTimeoutRef.current) clearTimeout(signalLostTimeoutRef.current);
    if (sessionId) {
      await supabase.rpc('stop_technician_tracking', { p_session_id: sessionId });
    }
    setSessionId(null);
    setUiState('inactive');
    lastSentRef.current = null;
  }, [sessionId, supabase]);

  // Best-effort: re-affirm intent to keep tracking on tab restore —
  // watchPosition itself may have been suspended by the OS/browser
  // while backgrounded. This does not guarantee continuous background
  // tracking (see docs/PHASE-12-REPORT.md) — it just resumes cleanly
  // once the tab is foregrounded again.
  useEffect(() => {
    function handleVisibility() {
      if (document.visibilityState === 'visible' && sessionId && watchIdRef.current === null) {
        const watchId = navigator.geolocation.watchPosition(
          (pos) => handlePosition(sessionId, pos),
          () => setUiState('signal_lost'),
          { enableHighAccuracy: true, maximumAge: 10_000, timeout: 20_000 },
        );
        watchIdRef.current = watchId;
      }
    }
    document.addEventListener('visibilitychange', handleVisibility);
    return () => document.removeEventListener('visibilitychange', handleVisibility);
  }, [sessionId, handlePosition]);

  useEffect(() => {
    return () => {
      if (watchIdRef.current !== null) navigator.geolocation.clearWatch(watchIdRef.current);
      if (signalLostTimeoutRef.current) clearTimeout(signalLostTimeoutRef.current);
    };
  }, []);

  if (!canTrack) return null;

  return (
    <div className="bg-white/[0.03] border border-white/10 rounded-sm p-4 space-y-2">
      <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold">Live Location Sharing</div>

      {uiState === 'inactive' && (
        <button type="button" onClick={start} className="text-sm bg-gold text-navy px-4 py-2 rounded-sm">
          Start Tracking
        </button>
      )}

      {uiState === 'active' && (
        <div className="space-y-2">
          <p className="text-sm text-emerald-400">Tracking active — customer can see your location.</p>
          {lastSentAt && <p className="text-xs text-cool-gray">Last location sent: {lastSentAt.toLocaleTimeString()}</p>}
          <div className="flex gap-2">
            <button type="button" onClick={pause} className="text-sm border border-gold-dim text-gold px-4 py-2 rounded-sm">
              Pause
            </button>
            <button type="button" onClick={stop} className="text-sm border border-gold-dim text-gold px-4 py-2 rounded-sm">
              Stop Tracking
            </button>
          </div>
        </div>
      )}

      {uiState === 'paused' && (
        <div className="space-y-2">
          <p className="text-sm text-cool-gray">Tracking paused — customer no longer sees your location.</p>
          <div className="flex gap-2">
            <button type="button" onClick={resume} className="text-sm bg-gold text-navy px-4 py-2 rounded-sm">
              Resume
            </button>
            <button type="button" onClick={stop} className="text-sm border border-gold-dim text-gold px-4 py-2 rounded-sm">
              Stop Tracking
            </button>
          </div>
        </div>
      )}

      {uiState === 'signal_lost' && (
        <div className="space-y-2">
          <p className="text-sm text-amber-400">Signal temporarily lost — will resume automatically.</p>
          <button type="button" onClick={stop} className="text-sm border border-gold-dim text-gold px-4 py-2 rounded-sm">
            Stop Tracking
          </button>
        </div>
      )}

      {uiState === 'permission_denied' && <p className="text-sm text-red-400">Location permission denied. Enable it in your browser settings to share your route.</p>}

      {error && <p className="text-xs text-red-400">{error}</p>}
    </div>
  );
}
