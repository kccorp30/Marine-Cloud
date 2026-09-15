'use client';

// =========================================================
// lib/notifications/sound-service.ts — Marine Cloud Phase 9
// =========================================================
// Único lugar que reproduce sonido de notificaciones — ningún
// componente individual debe tocar audio directamente (tal como
// exige docs/notification-architecture-plan.md). IDs de sonido
// configurables, nunca hardcodeados en componentes.
//
// Respeta: mute del usuario (localStorage), y usa el severity/
// event_type de la notificación para elegir el sonido — nunca
// asume. Sin archivos de audio reales en este entorno: usa
// WebAudio para generar un tono simple y distintivo por sonido,
// documentado como limitación (ver reporte final).
// =========================================================

export type SoundId = 'notification_info' | 'action_required' | 'kcc_assistance_request' | 'urgent' | 'critical';

const MUTE_STORAGE_KEY = 'kcc_notifications_muted';

// Frecuencia/duración distintas por sonido — tono generado, no un
// archivo de audio real (no hay assets de sonido en este entorno).
const SOUND_PROFILES: Record<SoundId, { frequency: number; duration: number; pulses: number }> = {
  notification_info: { frequency: 440, duration: 0.12, pulses: 1 },
  action_required: { frequency: 523, duration: 0.15, pulses: 2 },
  kcc_assistance_request: { frequency: 880, duration: 0.2, pulses: 3 },
  urgent: { frequency: 660, duration: 0.18, pulses: 3 },
  critical: { frequency: 880, duration: 0.25, pulses: 4 },
};

export function isMuted(): boolean {
  if (typeof window === 'undefined') return true;
  return window.localStorage.getItem(MUTE_STORAGE_KEY) === 'true';
}

export function setMuted(muted: boolean): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(MUTE_STORAGE_KEY, muted ? 'true' : 'false');
}

/** Elige el sonido correcto para una notificación — la única función que debe decidir esto. */
export function resolveSoundId(eventType: string, severity: string): SoundId {
  if (eventType === 'KCC_ASSISTANCE_REQUESTED') return 'kcc_assistance_request';
  if (severity === 'critical') return 'critical';
  if (severity === 'urgent') return 'urgent';
  if (severity === 'action_required') return 'action_required';
  return 'notification_info';
}

/**
 * Reproduce el sonido — respeta mute. No respeta "horas silenciosas"
 * todavía (no hay preferencia de usuario para eso en este proyecto
 * más allá del mute simple) — documentado como limitación.
 */
export function playNotificationSound(soundId: SoundId): void {
  if (typeof window === 'undefined') return;
  if (isMuted()) return;

  try {
    const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();
    const profile = SOUND_PROFILES[soundId];

    let startTime = ctx.currentTime;
    for (let i = 0; i < profile.pulses; i++) {
      const oscillator = ctx.createOscillator();
      const gain = ctx.createGain();
      oscillator.frequency.value = profile.frequency;
      oscillator.type = 'sine';
      gain.gain.setValueAtTime(0.15, startTime);
      gain.gain.exponentialRampToValueAtTime(0.001, startTime + profile.duration);
      oscillator.connect(gain);
      gain.connect(ctx.destination);
      oscillator.start(startTime);
      oscillator.stop(startTime + profile.duration);
      startTime += profile.duration + 0.08;
    }
  } catch {
    // El audio nunca debe romper la UI si falla — se ignora en silencio.
  }
}
