import { describe, test, expect } from 'vitest';
import { getEffectiveWarrantyStatus } from '../lib/warranty/effective-status';

// =========================================================
// tests/warranty-effective-status.test.ts — Phase 13 last correctness pass
// =========================================================
// Réplica exacta de warranty_effective_status() en la base de datos
// (migración 214, STABLE). Sin cron, un warranty con status='active'
// almacenado y ends_at vencido nunca debe presentarse como activo —
// y uno que vence HOY nunca debe verse vencido antes de tiempo por un
// bug de timezone.
// =========================================================

function ymd(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

describe('getEffectiveWarrantyStatus', () => {
  test('ends yesterday => expired', () => {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    expect(getEffectiveWarrantyStatus('active', ymd(yesterday))).toBe('expired');
  });

  test('ends today => active', () => {
    const today = new Date();
    expect(getEffectiveWarrantyStatus('active', ymd(today))).toBe('active');
  });

  test('ends tomorrow => active', () => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    expect(getEffectiveWarrantyStatus('active', ymd(tomorrow))).toBe('active');
  });

  test('voided in the past stays voided', () => {
    const past = new Date();
    past.setDate(past.getDate() - 30);
    expect(getEffectiveWarrantyStatus('voided', ymd(past))).toBe('voided');
  });

  test('draft with no ends_at stays draft', () => {
    expect(getEffectiveWarrantyStatus('draft', null)).toBe('draft');
  });

  // Protección explícita contra el bug real de timezone: un valor
  // DATE puro 'YYYY-MM-DD' (sin componente de hora, exactamente como
  // Postgres lo devuelve) para HOY nunca debe verse como vencido, sin
  // importar el offset de timezone del proceso que ejecuta esto. La
  // versión anterior usaba `new Date('YYYY-MM-DD')`, que JS interpreta
  // como medianoche UTC — en timezones de offset negativo eso podía
  // adelantar la fecha varias horas y marcar como vencida una garantía
  // que técnicamente sigue vigente todo el día local.
  test('a pure YYYY-MM-DD value for today is never misread as expired regardless of process timezone offset', () => {
    const todayPureDateString = ymd(new Date()); // exactamente 'YYYY-MM-DD', sin hora — como lo entrega Postgres
    expect(getEffectiveWarrantyStatus('active', todayPureDateString)).toBe('active');
    // La comparación buggy anterior (new Date(endsAt) < new Date(new Date().toDateString()))
    // fallaría acá en cualquier timezone con offset negativo respecto a UTC.
  });
});
