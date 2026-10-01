'use client';

import { useState, useRef, useCallback, useEffect } from 'react';
import { createClient } from '@/lib/supabase/client';

// =========================================================
// useTechnicianTracking — extraído de TechnicianTrackingControl
// (Phase 12) para que MissionHero pueda iniciar tracking como parte
// de la MISMA acción de START ROUTE, sin duplicar la lógica de
// throttling/watchPosition ni las RPCs (start_technician_tracking,
// pause/resume/stop_technician_tracking, submit_technician_location
// — todas se preservan tal cual, nunca un sistema paralelo).
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

export type TrackingUiState = 'inactive' | 'active' | 'paused' | 'permission_denied' | 'signal_lost' | 'starting';

export function useTechnicianTracking(workOrderId: string) {
  const [uiState, setUiState] = useState<TrackingUiState>('inactive');
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

  const beginWatching = useCallback(
    (currentSessionId: string) => {
      const watchId = navigator.geolocation.watchPosition(
        (pos) => handlePosition(currentSessionId, pos),
        (geoError) => setUiState(geoError.code === geoError.PERMISSION_DENIED ? 'permission_denied' : 'signal_lost'),
        { enableHighAccuracy: true, maximumAge: 10_000, timeout: 20_000 },
      );
      watchIdRef.current = watchId;
    },
    [handlePosition],
  );

  /**
   * Inicia el tracking real — llamado directamente por START ROUTE
   * en MissionHero, nunca un botón separado. Pide permiso de
   * geolocalización PRIMERO (falla rápido y honesto si se niega,
   * antes de tocar ningún estado del work order), crea/reutiliza la
   * sesión de tracking (start_technician_tracking ya es idempotente),
   * y arranca watchPosition inmediatamente con el primer punto.
   */
  const start = useCallback(async (): Promise<{ success: boolean; permissionDenied?: boolean; error?: string }> => {
    setError(null);
    setUiState('starting');
    if (!('geolocation' in navigator)) {
      setUiState('inactive');
      setError('This device does not support location sharing.');
      return { success: false, error: 'This device does not support location sharing.' };
    }

    const { data: session, error: startError } = await supabase.rpc('start_technician_tracking', { p_work_order_id: workOrderId });
    if (startError || !session) {
      setUiState('inactive');
      setError(startError?.message ?? 'Could not start tracking.');
      return { success: false, error: startError?.message };
    }
    setSessionId(session.id);
    beginWatching(session.id);
    setUiState('active');
    return { success: true };
  }, [workOrderId, supabase, beginWatching]);

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
      setError(resumeError.message);
      setUiState('inactive');
      setSessionId(null);
      return;
    }
    beginWatching(sessionId);
    setUiState('active');
  }, [sessionId, supabase, beginWatching]);

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

  // Al montar: si ya existe una sesión activa/pausada para este work
  // order (ej. arrancada por START ROUTE en otra vista, o la misma
  // vista tras un remount), la detecta y retoma el watchPosition en
  // vez de mostrar "Start Tracking" de nuevo — nunca dos sesiones
  // para el mismo work order.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from('technician_tracking_sessions')
        .select('id, status')
        .eq('work_order_id', workOrderId)
        .in('status', ['active', 'paused'])
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (cancelled || !data) return;
      setSessionId(data.id);
      if (data.status === 'active') {
        beginWatching(data.id);
        setUiState('active');
      } else {
        setUiState('paused');
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workOrderId]);

  // Re-afirma el watch al volver a foreground — mismo comportamiento
  // best-effort ya documentado en Phase 12, nunca garantiza tracking
  // en background real.
  useEffect(() => {
    function handleVisibility() {
      if (document.visibilityState === 'visible' && sessionId && watchIdRef.current === null && uiState === 'active') {
        beginWatching(sessionId);
      }
    }
    document.addEventListener('visibilitychange', handleVisibility);
    return () => document.removeEventListener('visibilitychange', handleVisibility);
  }, [sessionId, uiState, beginWatching]);

  useEffect(() => {
    return () => {
      if (watchIdRef.current !== null) navigator.geolocation.clearWatch(watchIdRef.current);
      if (signalLostTimeoutRef.current) clearTimeout(signalLostTimeoutRef.current);
    };
  }, []);

  return { uiState, sessionId, lastSentAt, error, start, pause, resume, stop };
}
