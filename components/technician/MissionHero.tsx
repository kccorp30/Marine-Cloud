'use client';

import { useState, useTransition } from 'react';
import { startRoute, checkIn } from '@/lib/technician/actions';
import { transitionWorkOrder } from '@/lib/work-orders/actions';
import { useTechnicianTracking } from '@/lib/tracking/useTechnicianTracking';
import type { Locale } from '@/lib/i18n/dictionary';
import { workspaceCopy } from '@/lib/i18n/workspace-copy';

interface MissionHeroProps {
  workOrderId: string;
  vesselId: string;
  appointmentId: string | null;
  currentStatus: string;
  vesselName: string;
  customerName: string | null;
  serviceLabel: string | null;
  serviceAddress: string | null;
  beforePhotoCount: number;
  beforePhotoMinimum: number;
  locale: Locale;
}

const MISSION_STATUSES = ['technician_assigned', 'en_route', 'checked_in', 'diagnosis'];

function buildExternalNavUrl(address: string): { apple: string; google: string } {
  const encoded = encodeURIComponent(address);
  return {
    apple: `https://maps.apple.com/?daddr=${encoded}`,
    google: `https://www.google.com/maps/dir/?api=1&destination=${encoded}`,
  };
}

export function MissionHero(props: MissionHeroProps) {
  const { workOrderId, appointmentId, currentStatus, vesselName, customerName, serviceLabel, serviceAddress, beforePhotoCount, beforePhotoMinimum, locale } = props;

  const t = workspaceCopy[locale];
  const [pending, startTransition] = useTransition();
  const tracking = useTechnicianTracking(workOrderId);
  const [locationDegraded, setLocationDegraded] = useState(false);

  /**
   * START ROUTE real: una sola acción de usuario que (1) pide permiso
   * de geolocalización primero — falla rápido y honesto si se niega,
   * (2) transiciona el work order a en_route vía la RPC existente,
   * (3) arranca la sesión de tracking + watchPosition inmediatamente.
   * Nunca dos botones separados. Si el permiso de ubicación se niega,
   * la transición de estado SIGUE ocurriendo (el técnico realmente
   * está saliendo), pero se muestra un estado degradado claro y
   * nunca se finge que el tracking está activo.
   */
  async function handleStartRoute() {
    setError(null);
    setLocationDegraded(false);
    startTransition(async () => {
      let permissionGranted = true;
      if ('geolocation' in navigator) {
        permissionGranted = await new Promise<boolean>((resolve) => {
          navigator.geolocation.getCurrentPosition(
            () => resolve(true),
            () => resolve(false),
            { timeout: 8000 },
          );
        });
      } else {
        permissionGranted = false;
      }

      const routeResult = await startRoute(workOrderId);
      if (routeResult && 'error' in routeResult && routeResult.error) {
        setError(routeResult.error);
        return;
      }

      if (!permissionGranted) {
        setLocationDegraded(true);
        return;
      }

      const trackingResult = await tracking.start();
      if (!trackingResult.success) {
        // La transición de estado ya ocurrió — el tracking es un
        // best-effort adicional, nunca bloquea el START ROUTE en sí.
        setLocationDegraded(true);
      }
    });
  }
  const [error, setError] = useState<string | null>(null);

  if (!MISSION_STATUSES.includes(currentStatus)) return null;

  function run(fn: () => Promise<{ error?: string; success?: boolean } | void>) {
    setError(null);
    startTransition(async () => {
      const result = await fn();
      if (result && 'error' in result && result.error) setError(result.error);
    });
  }

  const beforeReady = beforePhotoCount >= beforePhotoMinimum;
  const customerFirstName = customerName?.split(' ')[0] ?? null;

  // Luz es contextual al estado real — nunca decorativa, nunca
  // inventa información. Cada mensaje se deriva directamente del
  // status actual del work order, vía el diccionario centralizado.
  function luzMessage(): string {
    switch (currentStatus) {
      case 'technician_assigned':
        return t['technicianMission.luzAssigned'];
      case 'en_route':
        return `${customerFirstName ?? t.customer} ${t['technicianMission.luzEnRoute']}`;
      case 'checked_in':
        return t['technicianMission.luzArrived'];
      case 'diagnosis':
        return beforeReady ? t['technicianMission.luzDocComplete'] : `${beforePhotoCount} / ${beforePhotoMinimum} ${t['technicianMission.requiredPhotos']}`;
      default:
        return '';
    }
  }

  return (
    <div className="relative overflow-hidden glass-strong rounded-xl p-6 mb-6 shadow-premium animate-fade-up">
      <div className="absolute -top-24 -right-24 w-64 h-64 rounded-full bg-gold/[0.07] blur-3xl pointer-events-none" />

      <div className="relative">
        <div className="flex items-center justify-between mb-4">
          <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-gold-dim">
            {currentStatus === 'en_route' ? t['technicianMission.enRoute'] : t['technicianMission.todaysMission']}
          </span>
          {currentStatus === 'en_route' && tracking.uiState === 'active' && (
            <span className="inline-flex items-center gap-1.5 text-[10px] font-mono uppercase text-emerald-400">
              <span className="relative flex h-2 w-2">
                <span className="animate-pulse-soft absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
                <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-400" />
              </span>
              {t['technicianMission.live']}
            </span>
          )}
          {currentStatus === 'en_route' && tracking.uiState === 'permission_denied' && (
            <span className="text-[10px] font-mono uppercase text-amber-400">{t['technicianMission.locationUnavailable']}</span>
          )}
          {currentStatus === 'en_route' && tracking.uiState === 'signal_lost' && (
            <span className="text-[10px] font-mono uppercase text-amber-400">{t['technicianMission.signalLost']}</span>
          )}
        </div>

        <h2 className="font-display text-xl font-semibold text-marine-white">{vesselName}</h2>
        <div className="text-sm text-cool-gray mt-1 space-y-0.5">
          {customerName && <div>{customerName}</div>}
          {serviceLabel && <div>{serviceLabel}</div>}
          {serviceAddress && <div className="text-cool-gray/80">{serviceAddress}</div>}
        </div>

        <div className="mt-4 flex items-start gap-2.5 bg-white/[0.03] border border-white/[0.06] rounded-lg p-3">
          <span className="text-gold text-sm mt-0.5">✦</span>
          <p className="text-xs text-marine-white/90 leading-relaxed">{luzMessage()}</p>
        </div>

        {error && (
          <p className="mt-3 text-xs text-red-400" role="alert">
            {error === 'service location required — this vessel has no service address or marina on file'
              ? t['technicianMission.serviceLocationMissing']
              : error}
          </p>
        )}

        {currentStatus === 'technician_assigned' && (
          <>
            <button
              type="button"
              disabled={pending}
              onClick={handleStartRoute}
              className="mt-5 w-full bg-gold-sheen text-navy font-bold text-[13px] uppercase tracking-[0.08em] py-4 rounded-lg shadow-glow-gold hover:brightness-110 active:scale-[0.99] transition-all duration-150 disabled:opacity-40"
            >
              {pending ? t['technicianMission.starting'] : t['technicianMission.startRoute']}
            </button>
            {locationDegraded && (
              <p className="mt-2 text-xs text-amber-400">{t['technicianMission.locationDegraded']}</p>
            )}
          </>
        )}

        {currentStatus === 'en_route' && (
          <div className="mt-5 space-y-2.5">
            <button
              type="button"
              disabled={pending || !appointmentId}
              onClick={() => {
                if (!appointmentId) return;
                if (navigator.geolocation) {
                  navigator.geolocation.getCurrentPosition(
                    (pos) => run(() => checkIn(appointmentId, workOrderId, { lat: pos.coords.latitude, lng: pos.coords.longitude })),
                    () => run(() => checkIn(appointmentId, workOrderId)),
                    { timeout: 8000 },
                  );
                } else {
                  run(() => checkIn(appointmentId, workOrderId));
                }
              }}
              className="w-full bg-gold-sheen text-navy font-bold text-[13px] uppercase tracking-[0.08em] py-4 rounded-lg shadow-glow-gold hover:brightness-110 active:scale-[0.99] transition-all duration-150 disabled:opacity-40"
            >
              {pending ? t['technicianMission.arriving'] : t['technicianMission.arrived']}
            </button>
            {serviceAddress && (
              <div className="grid grid-cols-2 gap-2">
                <a
                  href={buildExternalNavUrl(serviceAddress).apple}
                  target="_blank"
                  rel="noreferrer"
                  className="text-center text-[11px] font-mono uppercase text-cool-gray border border-white/10 rounded-md py-2.5 hover:border-gold-dim/40 transition-colors"
                >
                  {t['technicianMission.appleMaps']}
                </a>
                <a
                  href={buildExternalNavUrl(serviceAddress).google}
                  target="_blank"
                  rel="noreferrer"
                  className="text-center text-[11px] font-mono uppercase text-cool-gray border border-white/10 rounded-md py-2.5 hover:border-gold-dim/40 transition-colors"
                >
                  {t['technicianMission.googleMaps']}
                </a>
              </div>
            )}
          </div>
        )}

        {currentStatus === 'checked_in' && (
          <button
            type="button"
            disabled={pending}
            onClick={() => run(() => transitionWorkOrder(workOrderId, 'diagnosis', 'Before-work documentation started'))}
            className="mt-5 w-full bg-gold-sheen text-navy font-bold text-[13px] uppercase tracking-[0.08em] py-4 rounded-lg shadow-glow-gold hover:brightness-110 active:scale-[0.99] transition-all duration-150 disabled:opacity-40"
          >
            {pending ? t['technicianMission.starting'] : t['technicianMission.beforeWorkCheck']}
          </button>
        )}

        {currentStatus === 'diagnosis' && (
          <div className="mt-5 space-y-3">
            <div className="flex items-center justify-between">
              <span className="font-mono text-[10px] uppercase tracking-[0.08em] text-cool-gray">
                {beforePhotoCount} / {beforePhotoMinimum} {t['technicianMission.requiredPhotos']}
              </span>
              {beforeReady && <span className="text-[10px] font-mono uppercase text-emerald-400">✓ {t['technicianMission.complete']}</span>}
            </div>
            <div className="h-1.5 rounded-full bg-white/[0.06] overflow-hidden">
              <div
                className="h-full bg-gold-sheen transition-all duration-300"
                style={{ width: `${Math.min(100, (beforePhotoCount / beforePhotoMinimum) * 100)}%` }}
              />
            </div>
            <button
              type="button"
              onClick={() => {
                window.location.hash = '#evidence';
                document.getElementById('technician-actions')?.scrollIntoView({ behavior: 'smooth' });
                window.dispatchEvent(new HashChangeEvent('hashchange'));
              }}
              className="w-full border border-gold-dim text-gold font-semibold text-[13px] uppercase tracking-[0.06em] py-3.5 rounded-lg hover:bg-gold/[0.06] transition-colors duration-150"
            >
              {t['technicianMission.openCamera']}
            </button>
            <button
              type="button"
              disabled={pending || !beforeReady}
              onClick={() => run(() => transitionWorkOrder(workOrderId, 'work_in_progress', 'Documentation complete — work started'))}
              className="w-full bg-gold-sheen text-navy font-bold text-[13px] uppercase tracking-[0.08em] py-4 rounded-lg shadow-glow-gold hover:brightness-110 active:scale-[0.99] transition-all duration-150 disabled:opacity-30 disabled:grayscale"
            >
              {pending ? t['technicianMission.starting'] : t['technicianMission.startJob']}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
