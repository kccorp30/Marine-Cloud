import { StatusTimeline } from "@/components/ui/StatusTimeline";
import { getLocale } from "@/lib/i18n/server";
import { dictionary } from "@/lib/i18n/dictionary";

import { UiText } from "@/components/ui/UiText";
import type { CustomerWorkOrderTracking } from "@/lib/work-orders/customer-tracking";
import { Card } from "@/components/ui/primitives";

// Mobile-first, premium, sin animaciones vistosas — pedido explícito
// del brief. El estado NUNCA se comunica solo por color (cada etapa
// también tiene texto: "Completed"/"Current"/"Upcoming" para lectores
// de pantalla, aria-current en la etapa activa).
export async function CustomerTracking({
  tracking,
}: {
  tracking: CustomerWorkOrderTracking;
}) {
  const locale = await getLocale();
  const statusLabel =
    (dictionary[locale].status as Record<string, string>)[
      tracking.currentStatus
    ] || tracking.currentStatus;
  const {
    stages,
    subStatus,
    isPaused,
    isCancelled,
    lastActivityAt,
    technician,
    appointment,
    progressUpdates,
  } = tracking;

  if (isCancelled) {
    return (
      <Card className="mb-6 border-red-500/30 bg-red-500/[0.04]">
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-red-400 mb-2">
          {" "}
          <UiText text="Service Cancelled" />{" "}
        </div>
        <p className="text-sm text-cool-gray">
          {locale === "es" ? statusLabel : subStatus}
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-4 mb-8">
      {/* A. TRACKER PRINCIPAL */}
      <Card>
        <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-4">
          {" "}
          <UiText text="Service Journey" />{" "}
        </div>
        <StatusTimeline
          locale={locale}
          status={tracking.currentStatus}
          events={tracking.recordedStages}
        />
      </Card>

      {/* B. TARJETA DE ESTADO ACTUAL */}
      <Card>
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-sm font-semibold text-marine-white">
              {statusLabel}
              {isPaused && (
                <span className="ml-2 font-mono text-[9px] uppercase tracking-[0.06em] text-amber-400 border border-amber-400/40 px-1.5 py-0.5 rounded-sm align-middle">
                  {" "}
                  <UiText text="Waiting" />{" "}
                </span>
              )}
            </div>
            <p className="text-xs text-cool-gray mt-1.5 leading-relaxed">
              {locale === "es" ? statusLabel : subStatus}
            </p>
          </div>
        </div>
        {lastActivityAt && (
          <div className="mt-3 pt-3 border-t border-white/5 font-mono text-[9.5px] uppercase tracking-[0.06em] text-cool-gray/70">
            {" "}
            <UiText text="Last updated" />{" "}
            {new Date(lastActivityAt).toLocaleString(undefined, {
              month: "short",
              day: "numeric",
              hour: "2-digit",
              minute: "2-digit",
            })}
          </div>
        )}
      </Card>

      {/* C. TÉCNICO ASIGNADO */}
      {technician && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
            {" "}
            <UiText text="Your Technician" />{" "}
          </div>
          <div className="flex items-center gap-3">
            {technician.avatarUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={technician.avatarUrl}
                alt=""
                className="w-10 h-10 rounded-full object-cover"
              />
            ) : (
              <div className="w-10 h-10 rounded-full bg-white/[0.06] flex items-center justify-center font-mono text-xs text-cool-gray">
                {technician.name.charAt(0)}
              </div>
            )}
            <span className="text-sm font-medium">{technician.name}</span>
          </div>
        </Card>
      )}

      {/* D. CITA / VISITA */}
      {appointment && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
            {" "}
            <UiText text="Appointment" />{" "}
          </div>
          <div className="text-sm">
            {new Date(appointment.scheduledStart).toLocaleString(undefined, {
              weekday: "long",
              month: "short",
              day: "numeric",
              hour: "2-digit",
              minute: "2-digit",
            })}
          </div>
          <div className="font-mono text-[9.5px] uppercase tracking-[0.06em] text-cool-gray mt-1">
            {appointment.status.replace(/_/g, " ")}
          </div>
        </Card>
      )}

      {/* E. PROGRESS UPDATES VISIBLES */}
      {progressUpdates.length > 0 && (
        <Card>
          <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold mb-3">
            {" "}
            <UiText text="Progress Updates" />{" "}
          </div>
          <ul className="space-y-4">
            {progressUpdates.map((u) => (
              <li key={u.id} className="border-l-2 border-gold/40 pl-3">
                {u.body && (
                  <p className="text-sm text-marine-white">{u.body}</p>
                )}
                {u.photoUrls.length > 0 && (
                  <div className="flex gap-2 mt-2 overflow-x-auto">
                    {u.photoUrls.map((url) => (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        key={url}
                        src={url}
                        alt=""
                        className="w-20 h-20 rounded-sm object-cover shrink-0"
                      />
                    ))}
                  </div>
                )}
                <div className="font-mono text-[9px] uppercase tracking-[0.06em] text-cool-gray/70 mt-1.5">
                  {new Date(u.createdAt).toLocaleDateString(undefined, {
                    month: "short",
                    day: "numeric",
                  })}
                </div>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}
