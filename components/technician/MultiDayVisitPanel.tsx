'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { finishTodaysVisit, startContinuationRoute, checkIn } from '@/lib/technician/actions';
import { useTechnicianTracking } from '@/lib/tracking/useTechnicianTracking';
import type { Locale } from '@/lib/i18n/dictionary';
import { workspaceCopy } from '@/lib/i18n/workspace-copy';

// =========================================================
// MULTI-DÍA — dos caras de la MISMA orden, nunca una orden nueva
// =========================================================
// A) En sitio y trabajando  → FINISH TODAY'S VISIT
// B) Orden ya en progreso, sin check-in abierto (= el técnico se fue
//    y vuelve otro día) → CONTINUE MISSION · Día N
//
// Ningún camino completa el work order ni toca current_status a mano:
// finish_todays_visit() y technician_start_continuation_route() son
// las únicas puertas, y ambas ya validan asignación y estado del lado
// del servidor.
// =========================================================

export interface PreviousVisitSummary {
  summary: string | null;
  outcome: string | null;
  finishedAt: string | null;
}

interface MultiDayVisitPanelProps {
  workOrderId: string;
  currentStatus: string;
  /** Check-in abierto del técnico actual, si está en sitio ahora. */
  hasOpenCheckIn: boolean;
  /** Visitas ya cerradas bajo esta orden — define el número de día. */
  completedVisits: number;
  previousVisit: PreviousVisitSummary | null;
  /** Próxima cita agendada (la que se usa para hacer check-in al volver). */
  nextAppointmentId: string | null;
  serviceAddress: string | null;
  locale: Locale;
}

const CONTINUATION_STATUSES = ['work_in_progress', 'waiting_parts', 'waiting_customer_approval'];

const OUTCOMES = [
  'continue_tomorrow',
  'waiting_parts',
  'waiting_approval',
  'return_scheduled',
  'access_weather',
  'other',
] as const;

// El backend exige fecha para return_scheduled; acá se refleja la
// misma regla para no mandar una llamada que se sabe que va a fallar.
const OUTCOME_REQUIRES_DATE: Record<string, boolean> = { return_scheduled: true };

export function MultiDayVisitPanel(props: MultiDayVisitPanelProps) {
  const {
    workOrderId,
    currentStatus,
    hasOpenCheckIn,
    completedVisits,
    previousVisit,
    nextAppointmentId,
    serviceAddress,
    locale,
  } = props;

  const t = workspaceCopy[locale] as Record<string, string>;
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const [outcome, setOutcome] = useState<string>('continue_tomorrow');
  const [summary, setSummary] = useState('');
  const [nextVisit, setNextVisit] = useState('');
  const [locationDegraded, setLocationDegraded] = useState(false);
  const tracking = useTechnicianTracking(workOrderId);
  const router = useRouter();

  const inProgress = CONTINUATION_STATUSES.includes(currentStatus);
  if (!inProgress) return null;

  // ---------- A) Cerrar la visita de hoy ----------
  if (hasOpenCheckIn && currentStatus === 'work_in_progress') {
    const needsDate = OUTCOME_REQUIRES_DATE[outcome] === true;
    const canSubmit = summary.trim().length > 0 && (!needsDate || nextVisit.length > 0);

    return (
      <section className="rounded-2xl border border-amber-400/25 bg-amber-400/5 p-5">
        <h3 className="text-sm font-semibold text-amber-200">{t['multiDay.finishVisitTitle']}</h3>
        <p className="mt-1 text-xs text-cool-gray">{t['multiDay.finishVisitHelp']}</p>

        {!open ? (
          <button type="button" className="kcc-action mt-4 w-full" onClick={() => setOpen(true)}>
            {t['multiDay.finishVisit']}
          </button>
        ) : (
          <div className="mt-4 space-y-4">
            <div>
              <label className="command-kicker block mb-2" htmlFor="visit-outcome">
                {t['multiDay.outcome']}
              </label>
              <select
                id="visit-outcome"
                className="w-full rounded-lg border border-white/15 bg-white/5 px-3 py-2 text-sm"
                value={outcome}
                onChange={(e) => setOutcome(e.target.value)}
              >
                {OUTCOMES.map((o) => (
                  <option key={o} value={o}>
                    {t[`workStory.outcome.${o}`] ?? o}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="command-kicker block mb-2" htmlFor="visit-summary">
                {t['multiDay.summary']}
              </label>
              <textarea
                id="visit-summary"
                rows={3}
                required
                className="w-full rounded-lg border border-white/15 bg-white/5 px-3 py-2 text-sm"
                placeholder={t['multiDay.summaryPlaceholder']}
                value={summary}
                onChange={(e) => setSummary(e.target.value)}
              />
            </div>

            <div>
              <label className="command-kicker block mb-2" htmlFor="visit-next">
                {needsDate ? t['multiDay.nextVisitRequired'] : t['multiDay.nextVisitOptional']}
              </label>
              <input
                id="visit-next"
                type="datetime-local"
                className="w-full rounded-lg border border-white/15 bg-white/5 px-3 py-2 text-sm"
                value={nextVisit}
                onChange={(e) => setNextVisit(e.target.value)}
              />
            </div>

            {error && (
              <p role="alert" className="text-sm text-red-300">
                {error}
              </p>
            )}

            <div className="flex gap-3">
              <button
                type="button"
                className="kcc-action flex-1"
                disabled={pending || !canSubmit}
                onClick={() => {
                  setError(null);
                  startTransition(async () => {
                    // La sesión de tracking se detiene también en la
                    // base; acá se corta el watchPosition del device
                    // para no seguir gastando GPS tras cerrar la visita.
                    const result = await finishTodaysVisit({
                      workOrderId,
                      outcome,
                      summary,
                      nextVisitStart: nextVisit ? new Date(nextVisit).toISOString() : null,
                    });
                    if (result && 'error' in result && result.error) {
                      setError(result.error);
                      return;
                    }
                    await tracking.stop().catch(() => undefined);
                    setOpen(false);
                    setSummary('');
                    setNextVisit('');
                    router.refresh();
                  });
                }}
              >
                {pending ? '…' : t['multiDay.confirmFinish']}
              </button>
              <button type="button" className="kcc-action" disabled={pending} onClick={() => setOpen(false)}>
                {t.cancel}
              </button>
            </div>
          </div>
        )}
      </section>
    );
  }

  // ---------- B) Volver otro día ----------
  if (completedVisits < 1) return null; // todavía no hubo una visita cerrada: nada que continuar

  const dayNumber = completedVisits + 1;

  return (
    <section className="rounded-2xl border border-gold/25 bg-gold/5 p-5">
      <div className="flex items-baseline justify-between gap-3">
        <h3 className="text-sm font-semibold text-gold">{t['multiDay.continueMission']}</h3>
        <span className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim">
          {t['multiDay.day']} {dayNumber}
        </span>
      </div>

      {previousVisit && (
        <div className="mt-4 rounded-xl border border-white/10 bg-white/5 p-4">
          <p className="command-kicker">{t['multiDay.previousVisit']}</p>
          {previousVisit.outcome && (
            <p className="mt-2 text-xs text-amber-300/90">
              {t[`workStory.outcome.${previousVisit.outcome}`] ?? previousVisit.outcome}
            </p>
          )}
          {previousVisit.summary && (
            <p className="mt-2 text-sm leading-relaxed whitespace-pre-line">{previousVisit.summary}</p>
          )}
          {previousVisit.finishedAt && (
            <time className="mt-2 block text-[10px] text-cool-gray/70">
              {new Date(previousVisit.finishedAt).toLocaleString(locale, {
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit',
              })}
            </time>
          )}
        </div>
      )}

      {!serviceAddress && (
        <p className="mt-4 text-xs text-amber-300">{t['technicianMission.serviceLocationMissing']}</p>
      )}
      {locationDegraded && (
        <p className="mt-3 text-xs text-amber-300">{t['technicianMission.locationDegraded']}</p>
      )}
      {error && (
        <p role="alert" className="mt-3 text-sm text-red-300">
          {error}
        </p>
      )}

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <button
          type="button"
          className="kcc-action"
          disabled={pending || !serviceAddress || tracking.uiState === 'active'}
          onClick={() => {
            setError(null);
            setLocationDegraded(false);
            startTransition(async () => {
              // Igual que el START ROUTE del día 1: permiso primero,
              // después el evento, después el tracking real. Si el
              // permiso se niega no se finge que hay tracking.
              let granted = true;
              if ('geolocation' in navigator) {
                granted = await new Promise<boolean>((resolve) => {
                  navigator.geolocation.getCurrentPosition(
                    () => resolve(true),
                    () => resolve(false),
                    { enableHighAccuracy: true, timeout: 10000 },
                  );
                });
              }
              const result = await startContinuationRoute(workOrderId);
              if (result && 'error' in result && result.error) {
                setError(result.error);
                return;
              }
              if (granted) {
                try {
                  await tracking.start();
                } catch {
                  setLocationDegraded(true);
                }
              } else {
                setLocationDegraded(true);
              }
              router.refresh();
            });
          }}
        >
          {tracking.uiState === 'active' ? t['technicianMission.live'] : t['technicianMission.startRoute']}
        </button>

        <button
          type="button"
          className="kcc-action"
          disabled={pending || !nextAppointmentId}
          onClick={() => {
            setError(null);
            startTransition(async () => {
              if (!nextAppointmentId) return;
              const coords = await new Promise<{ lat: number; lng: number } | undefined>((resolve) => {
                if (!('geolocation' in navigator)) return resolve(undefined);
                navigator.geolocation.getCurrentPosition(
                  (p) => resolve({ lat: p.coords.latitude, lng: p.coords.longitude }),
                  () => resolve(undefined),
                  { enableHighAccuracy: true, timeout: 10000 },
                );
              });
              const result = await checkIn(nextAppointmentId, workOrderId, coords);
              if (result && 'error' in result && result.error) {
                setError(result.error);
                return;
              }
              router.refresh();
            });
          }}
        >
          {t['technicianMission.arrived']}
        </button>
      </div>

      {!nextAppointmentId && (
        <p className="mt-3 text-xs text-cool-gray">{t['multiDay.noNextVisit']}</p>
      )}
    </section>
  );
}
