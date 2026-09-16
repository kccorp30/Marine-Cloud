'use client';

import { useState, useTransition } from 'react';
import { updateNotificationPreferencesAction } from '@/lib/notifications/preferences-actions';
import { setMuted } from '@/lib/notifications/sound-service';

export function NotificationPreferencesControl({
  initialSoundEnabled,
  initialMotionEnabled,
  locale,
}: {
  initialSoundEnabled: boolean;
  initialMotionEnabled: boolean;
  locale: 'en' | 'es';
}) {
  const [sound, setSound] = useState(initialSoundEnabled);
  const [motion, setMotion] = useState(initialMotionEnabled);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState('');
  const es = locale === 'es';

  function persist(nextSound: boolean, nextMotion: boolean) {
    setError('');
    setMuted(!nextSound);
    document.documentElement.dataset.kccMotion = nextMotion ? 'on' : 'off';
    startTransition(async () => {
      const result = await updateNotificationPreferencesAction({
        soundEnabled: nextSound,
        motionEnabled: nextMotion,
      });
      if (result?.error) setError(result.error);
    });
  }

  return (
    <section className="notification-preferences">
      <div>
        <p className="notification-preferences-title">{es ? 'Experiencia de alertas' : 'Alert experience'}</p>
        <p className="notification-preferences-copy">{es ? 'Controla sonido y movimiento sin perder alertas críticas.' : 'Control sound and motion without hiding critical alerts.'}</p>
      </div>
      <div className="notification-preferences-actions">
        <button
          type="button"
          className={`notification-pref-toggle ${sound ? 'is-on' : ''}`}
          disabled={pending}
          onClick={() => { const next = !sound; setSound(next); persist(next, motion); }}
          aria-pressed={sound}
        >
          <span aria-hidden="true">{sound ? '♪' : '×'}</span>{es ? 'Sonido' : 'Sound'}
        </button>
        <button
          type="button"
          className={`notification-pref-toggle ${motion ? 'is-on' : ''}`}
          disabled={pending}
          onClick={() => { const next = !motion; setMotion(next); persist(sound, next); }}
          aria-pressed={motion}
        >
          <span aria-hidden="true">✦</span>{es ? 'Movimiento' : 'Motion'}
        </button>
      </div>
      {error && <p role="alert" className="text-[10px] text-red-300 mt-2">{error}</p>}
    </section>
  );
}
