// =========================================================
// lib/subscriptions/trial-countdown.ts — Marine Cloud Phase 14
// =========================================================
// Único lugar donde se deriva el texto de cuenta regresiva del trial
// — nunca calculado independientemente en múltiples componentes.
// trial_ends_at es un timestamptz real (no un DATE puro), así que la
// comparación de milisegundos es correcta acá — a diferencia del bug
// de Phase 13, esto no sufre el problema de parseo de 'YYYY-MM-DD'
// como UTC porque siempre trabajamos con un timestamp completo.
// =========================================================

export function getTrialCountdownLabel(trialEndsAt: string | null): string | null {
  if (!trialEndsAt) return null;
  const endsAt = new Date(trialEndsAt).getTime();
  const now = Date.now();
  const msRemaining = endsAt - now;

  if (msRemaining <= 0) return 'Trial expired';

  const daysRemaining = Math.ceil(msRemaining / (1000 * 60 * 60 * 24));

  if (daysRemaining <= 0) return 'Trial expired';
  if (daysRemaining === 1) return 'Trial ends tomorrow';
  return `${daysRemaining} days left`;
}
