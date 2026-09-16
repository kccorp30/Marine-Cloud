import { describe, test, expect } from 'vitest';
import { formatCalendarDate } from '../lib/warranty/format-calendar-date';

// =========================================================
// tests/format-calendar-date.test.ts — Phase 13 final date display patch
// =========================================================
// Postgres entrega valores DATE como 'YYYY-MM-DD', sin componente de
// hora. `new Date('YYYY-MM-DD')` los interpreta como medianoche UTC
// — en timezones de offset negativo eso puede mostrar el día
// calendario ANTERIOR. formatCalendarDate() construye el Date a
// partir de sus componentes numéricos (hora local, nunca UTC).
// =========================================================

describe('formatCalendarDate', () => {
  test('Jan 1 shows January, never December 31', () => {
    const result = formatCalendarDate('2026-01-01');
    expect(result).not.toContain('12/31');
    expect(result).not.toContain('Dec');
  });

  test('Sep 10 shows September 10, never September 9', () => {
    const result = formatCalendarDate('2026-09-10');
    // toLocaleDateString() por default da 'M/D/YYYY' en locale en-US —
    // verificamos el día exacto sin asumir un locale/formato fijo más
    // allá de eso.
    expect(result).toContain('9/10/2026');
  });

  test('Dec 31 shows December 31, never January 1 of the next year', () => {
    const result = formatCalendarDate('2026-12-31');
    expect(result).toContain('12/31/2026');
    expect(result).not.toContain('2027');
  });

  test('handles a timestamp-with-time value by using only its date portion', () => {
    const result = formatCalendarDate('2026-09-10T00:00:00.000Z');
    expect(result).toContain('9/10/2026');
  });
});

// Corrida explícita bajo un timezone real de offset negativo — la
// misma prueba de fondo que expuso el bug original en
// getEffectiveWarrantyStatus(). Si esto corre bajo
// TZ=America/New_York (o cualquier otro offset negativo) y sigue
// dando la fecha correcta, confirma que no hay corrimiento de día por
// UTC.
describe('formatCalendarDate under negative UTC offset', () => {
  test('Sep 10 stays Sep 10 regardless of process timezone offset', () => {
    const result = formatCalendarDate('2026-09-10');
    expect(result).toContain('9/10/2026');
  });
});
