'use client';

import { useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

// =========================================================
// components/kcc-assistance/AssistanceRealtimeListener.tsx — Phase 9 final fix
// =========================================================
// BUG REAL: kcc_assistance_requests ya estaba en la publicación de
// supabase_realtime, pero ninguna UI se suscribía — publicar una
// tabla no es lo mismo que consumirla. Este componente no mantiene
// estado propio (evita el mismo problema de aritmética frágil que
// tenía la campanita) — ante cualquier INSERT/UPDATE relevante, pide
// al servidor los datos autoritativos vía router.refresh(). RLS ya
// filtra qué filas llegan a cada usuario incluso en la conexión
// realtime — este componente no decide visibilidad, solo dispara el
// refetch.
// =========================================================
export function AssistanceRealtimeListener({ mode, organizationId, technicianId }: { mode: 'admin' | 'org' | 'technician'; organizationId?: string; technicianId?: string }) {
  const router = useRouter();
  const supabaseRef = useRef(createClient());

  useEffect(() => {
    const supabase = supabaseRef.current;
    // kcc_admin ve pedidos de TODAS las organizaciones — sin filtro
    // de canal, RLS server-side ya decide qué fila realmente le
    // llega (nunca al revés: el filtro del canal no es el control de
    // seguridad).
    const filter = mode === 'admin' ? undefined : mode === 'org' ? `organization_id=eq.${organizationId}` : `requesting_technician_id=eq.${technicianId}`;

    let builder = supabase.channel(`kcc-assistance:${mode}:${organizationId ?? technicianId ?? 'all'}`);
    builder = filter
      ? builder.on('postgres_changes', { event: '*', schema: 'public', table: 'kcc_assistance_requests', filter }, () => router.refresh())
      : builder.on('postgres_changes', { event: '*', schema: 'public', table: 'kcc_assistance_requests' }, () => router.refresh());
    const channel = builder.subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [mode, organizationId, technicianId, router]);

  return null;
}
