// =========================================================
// lib/warranty/format-calendar-date.ts — Phase 13 final date display patch
// =========================================================
// Único formateador para valores DATE puros ('YYYY-MM-DD') en la UI
// de warranty. Postgres entrega estos valores sin componente de
// hora — `new Date('YYYY-MM-DD')` los interpreta como medianoche
// UTC, lo que puede mostrar el día calendario ANTERIOR en timezones
// de offset negativo. Se construye el Date a partir de sus
// componentes numéricos (interpretados como hora LOCAL, nunca UTC).
//
// Este helper es SOLO para valores DATE (starts_at, ends_at). Nunca
// usarlo para timestamps reales (submitted_at, created_at,
// reviewed_at, etc.) — esos siguen su formato de fecha-hora normal.
// =========================================================

export function formatCalendarDate(date: string): string {
  const [year, month, day] = date.slice(0, 10).split('-').map(Number);
  const localDate = new Date(year, month - 1, day);
  return localDate.toLocaleDateString();
}
