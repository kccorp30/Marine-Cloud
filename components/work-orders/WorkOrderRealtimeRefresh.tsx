'use client';

import { useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

/**
 * Reemplaza el polling de 30s como mecanismo PRIMARIO de
 * actualización — se suscribe a cambios reales de Supabase Realtime
 * en la fila exacta del work order Y en las tablas relacionadas más
 * relevantes (item 7 del brief), TODO en UN SOLO canal — nunca un
 * canal por tabla, para no multiplicar conexiones ni crear loops de
 * refresco. Realtime respeta RLS — nunca expone datos que esta
 * persona no podría leer igual con un SELECT normal.
 *
 * technician_locations se deja DELIBERADAMENTE fuera de este canal:
 * cambia cada ~15s durante tracking activo, y disparar un
 * router.refresh() completo de la página con esa frecuencia sería
 * exactamente el "refresh loop" que el brief pide evitar —
 * TrackingStatusPanel ya tiene su propio mecanismo más liviano para
 * la ubicación en vivo.
 *
 * El polling de 30s se mantiene como RED DE SEGURIDAD (no mecanismo
 * principal) — si el canal de Realtime se cae o nunca conecta (red
 * restrictiva, proxy, etc.), la página igual se mantiene
 * razonablemente al día sin depender de que el usuario refresque a
 * mano.
 */
const FALLBACK_POLL_MS = 30_000;

export function WorkOrderRealtimeRefresh({ workOrderId }: { workOrderId: string }) {
  const router = useRouter();
  const lastRefreshRef = useRef(Date.now());

  useEffect(() => {
    const supabase = createClient();
    let fallbackInterval: ReturnType<typeof setInterval> | null = null;

    function refresh() {
      lastRefreshRef.current = Date.now();
      router.refresh();
    }

    const channel = supabase
      .channel(`work-order-${workOrderId}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'work_orders', filter: `id=eq.${workOrderId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'assignments', filter: `work_order_id=eq.${workOrderId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'media_assets', filter: `work_order_id=eq.${workOrderId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'progress_updates', filter: `work_order_id=eq.${workOrderId}` }, () => refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments', filter: `work_order_id=eq.${workOrderId}` }, () => refresh())
      .subscribe();

    function startFallback() {
      if (fallbackInterval) return;
      fallbackInterval = setInterval(() => {
        // Solo refresca por el respaldo si Realtime no actualizó
        // recientemente — evita duplicar refrescos cuando el canal
        // sí está funcionando bien.
        if (Date.now() - lastRefreshRef.current >= FALLBACK_POLL_MS) refresh();
      }, FALLBACK_POLL_MS);
    }
    function stopFallback() {
      if (fallbackInterval) clearInterval(fallbackInterval);
      fallbackInterval = null;
    }
    function handleVisibility() {
      if (document.visibilityState === 'visible') startFallback();
      else stopFallback();
    }

    if (document.visibilityState === 'visible') startFallback();
    document.addEventListener('visibilitychange', handleVisibility);

    return () => {
      stopFallback();
      document.removeEventListener('visibilitychange', handleVisibility);
      supabase.removeChannel(channel);
    };
  }, [workOrderId, router]);

  return null;
}
