// =========================================================
// lib/warranty/effective-status.ts — Phase 13 last correctness pass
// =========================================================
// Único lugar donde se deriva el estado de PRESENTACIÓN de una
// garantía — replica exacta de warranty_effective_status() (SQL,
// migración 214) en la base de datos. Sin infraestructura de cron,
// warranties.status puede quedar 'active' aunque ends_at ya haya
// pasado — esta función es la que TODA la UI debe usar para mostrar/
// filtrar, nunca el status crudo directamente.
//
// BUG REAL corregido en este cierre: la versión anterior comparaba
// `new Date(endsAt) < new Date(new Date().toDateString())` — para un
// valor DATE tipo 'YYYY-MM-DD', JS parsea la fecha ISO como UTC
// medianoche. En timezones de offset negativo (la mayoría de EE.UU.),
// eso podía hacer que una garantía que vence HOY se viera vencida
// horas antes de que realmente terminara el día local. Esto es una
// regla de negocio de FECHA DE CALENDARIO, nunca una comparación de
// timestamp — se corrige comparando strings YYYY-MM-DD normalizados
// directamente, sin construir objetos Date para la comparación.
// =========================================================

export type WarrantyStatus = 'draft' | 'active' | 'expired' | 'voided';

/** Fecha local de hoy como YYYY-MM-DD — nunca vía Date parsing de un string ISO, que se interpretaría como UTC. */
function todayCalendarDate(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** Normaliza cualquier valor de fecha (ya sea 'YYYY-MM-DD' puro o un ISO con hora) a solo su porción de calendario, sin construir un Date. */
function toCalendarDate(value: string): string {
  return value.slice(0, 10);
}

export function getEffectiveWarrantyStatus(status: string, endsAt: string | null): WarrantyStatus {
  if (status === 'active' && endsAt && toCalendarDate(endsAt) < todayCalendarDate()) {
    return 'expired';
  }
  return status as WarrantyStatus;
}
