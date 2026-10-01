'use client';

import { useTechnicianTracking } from '@/lib/tracking/useTechnicianTracking';

// =========================================================
// TechnicianTrackingControl — Phase 12, refactorizado
// =========================================================
// Ahora es un wrapper delgado sobre useTechnicianTracking (mismo
// hook que MissionHero usa para arrancar el tracking como parte de
// START ROUTE). Si el técnico ya inició tracking desde MissionHero,
// este componente lo detecta automáticamente (el hook chequea la
// sesión activa/pausada al montar) y muestra los controles de
// pausar/detener — nunca ofrece "Start Tracking" como una segunda
// acción separada mientras ya hay una sesión real en curso.
// Best-effort, documentado: no hay garantía de tracking en
// background real cuando la pantalla se bloquea o el tab se
// suspende — ver docs/PHASE-12-REPORT.md.
// =========================================================

export function TechnicianTrackingControl({ workOrderId, canTrack }: { workOrderId: string; canTrack: boolean }) {
  const { uiState, lastSentAt, error, start, pause, resume, stop } = useTechnicianTracking(workOrderId);

  if (!canTrack) return null;

  return (
    <div className="bg-white/[0.03] border border-white/10 rounded-sm p-4 space-y-2">
      <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold">Live Location Sharing</div>

      {(uiState === 'inactive' || uiState === 'starting') && (
        <button type="button" disabled={uiState === 'starting'} onClick={start} className="text-sm bg-gold text-navy px-4 py-2 rounded-sm disabled:opacity-50">
          {uiState === 'starting' ? 'Starting…' : 'Start Tracking'}
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
