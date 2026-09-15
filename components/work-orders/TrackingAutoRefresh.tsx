'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

// ESTRATEGIA DE ACTUALIZACIÓN (Phase 3B) — no se implementó Supabase
// Realtime todavía a propósito: hacerlo bien requiere canales
// conscientes de RLS, gestión de suscripción/desconexión del lado del
// cliente, y decidir qué tablas emiten (work_orders, domain_events,
// assignments, progress_updates) — alcance real aparte, no algo para
// sumar "de paso" a esta entrega.
//
// En su lugar: refresco liviano por intervalo, NO polling frágil —
// se pausa completo cuando la pestaña no está visible (Page
// Visibility API), un solo timer, se limpia siempre al desmontar.
// `router.refresh()` vuelve a pedir los Server Components (incluida
// getCustomerWorkOrderTracking), no hace fetch manual paralelo.
//
// CAMINO A REALTIME: cuando se implemente, este componente es
// exactamente el punto de reemplazo — en vez del setInterval, un
// canal de Supabase Realtime suscripto a UPDATE en work_orders y
// INSERT en domain_events/progress_updates filtrado por
// work_order_id, llamando a router.refresh() en cada evento en vez
// de cada N segundos. El resto de la página (DTO, RLS, componente
// visual) no cambia nada.
const REFRESH_INTERVAL_MS = 30_000;

export function TrackingAutoRefresh() {
  const router = useRouter();

  useEffect(() => {
    let intervalId: ReturnType<typeof setInterval> | null = null;

    function start() {
      if (intervalId) return;
      intervalId = setInterval(() => router.refresh(), REFRESH_INTERVAL_MS);
    }
    function stop() {
      if (intervalId) clearInterval(intervalId);
      intervalId = null;
    }

    function handleVisibility() {
      if (document.visibilityState === 'visible') start();
      else stop();
    }

    if (document.visibilityState === 'visible') start();
    document.addEventListener('visibilitychange', handleVisibility);

    return () => {
      stop();
      document.removeEventListener('visibilitychange', handleVisibility);
    };
  }, [router]);

  return null;
}
