'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import {Drawer} from '@/components/smart/Drawer';
import {NotificationInbox} from './NotificationInbox';
import {useCommandCopy} from '@/components/ui/LocaleProvider';
import { createClient } from '@/lib/supabase/client';
import { setMuted } from '@/lib/notifications/sound-service';
import { NotificationPreferencesControl } from './NotificationPreferencesControl';
import type { NotificationPreferences } from '@/lib/notifications/preferences';

// =========================================================
// components/notifications/NotificationBell.tsx — Phase 9 final fix
// =========================================================
// BUG REAL: la versión anterior solo escuchaba INSERT y hacía
// unreadCount++ localmente — un UPDATE (marcar leído, reconocer,
// marcar todo leído) nunca actualizaba el badge en tiempo real, y la
// aritmética local podía desincronizarse de la base real (ej. tras
// una reconexión que se perdió eventos). Ahora cada evento relevante
// (INSERT o UPDATE) dispara una RECONCILIACIÓN real — un COUNT
// autoritativo contra la base, nunca aritmética local — y lo mismo
// al reconectar.
// =========================================================
export function NotificationBell({ userId, initialUnreadCount, locale, notificationPreferences }: { userId: string; initialUnreadCount: number; locale: 'en' | 'es'; notificationPreferences: NotificationPreferences }) {
  const {t}=useCommandCopy();
  const [unreadCount, setUnreadCount] = useState(initialUnreadCount);
  const [flash, setFlash] = useState(false);
  const supabaseRef = useRef(createClient());

  useEffect(() => { setMuted(!notificationPreferences.soundEnabled); }, [notificationPreferences.soundEnabled]);

  const reconcileUnreadCount = useCallback(async () => {
    const { count } = await supabaseRef.current
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .eq('recipient_user_id', userId)
      .is('read_at', null);
    setUnreadCount(count ?? 0);
  }, [userId]);

  const handleInsert = useCallback(
    (payload: any) => {
      const notif = payload.new;
      setFlash(true);
      setTimeout(() => setFlash(false), 1200);
      reconcileUnreadCount();
    },
    [reconcileUnreadCount]
  );

  useEffect(() => {
    const supabase = supabaseRef.current;
    const channel = supabase
      .channel(`notifications:${userId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `recipient_user_id=eq.${userId}` },
        handleInsert
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'notifications', filter: `recipient_user_id=eq.${userId}` },
        () => reconcileUnreadCount()
      )
      .subscribe((status) => {
        // Al (re)conectar, el estado autoritativo siempre viene de la
        // base — nunca se confía en lo que haya quedado en memoria
        // durante la desconexión.
        if (status === 'SUBSCRIBED') reconcileUnreadCount();
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId, handleInsert, reconcileUnreadCount]);

  return (
    <Drawer title={t.notifications} label={<span className="relative inline-flex items-center justify-center" aria-label={t.notifications}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        className={`w-5 h-5 text-cool-gray transition-transform ${flash ? 'scale-110' : ''}`}
      >
        <path strokeLinecap="round" strokeLinejoin="round" d="M15 17h5l-1.4-1.4A2 2 0 0 1 18 14.2V11a6 6 0 1 0-12 0v3.2a2 2 0 0 1-.6 1.4L4 17h5m6 0v1a3 3 0 1 1-6 0v-1m6 0H9" />
      </svg>
      {unreadCount > 0 && (
        <span className="absolute top-0 right-0 min-w-[16px] h-4 px-1 rounded-full bg-gold text-navy text-[9px] font-mono font-bold flex items-center justify-center">
          {unreadCount > 9 ? '9+' : unreadCount}
        </span>
      )}
    </span>}>
      <div className="space-y-4">
        <NotificationPreferencesControl initialSoundEnabled={notificationPreferences.soundEnabled} initialMotionEnabled={notificationPreferences.motionEnabled} locale={locale} />
        <NotificationInbox key={unreadCount}/>
      </div>
    </Drawer>
  );
}
