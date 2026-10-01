'use client';

import { useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

/**
 * Versión a nivel de organización de WorkOrderRealtimeRefresh — para
 * vistas de lista/Operations Command Center donde la compañía
 * necesita ver CUALQUIER work order propio cambiar de estado (ej.
 * "technician en route") sin refrescar a mano. Misma estrategia:
 * Realtime como mecanismo primario, polling de 30s como red de
 * seguridad si el canal no conecta.
 */
const FALLBACK_POLL_MS = 30_000;

export function OrganizationRealtimeRefresh({ organizationId }: { organizationId: string }) {
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
      .channel(`org-work-orders-${organizationId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'work_orders', filter: `organization_id=eq.${organizationId}` },
        () => refresh(),
      )
      .subscribe();

    function startFallback() {
      if (fallbackInterval) return;
      fallbackInterval = setInterval(() => {
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
  }, [organizationId, router]);

  return null;
}
