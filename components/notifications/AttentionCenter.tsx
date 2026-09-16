'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { acknowledgeNotificationAction, markNotificationReadAction } from '@/lib/notifications/actions';
import { getNotificationDeepLink } from '@/lib/notifications/deep-link';
import { playNotificationSound, resolveSoundId, setMuted } from '@/lib/notifications/sound-service';

interface AttentionRow {
  id: string;
  eventType: string;
  severity: 'info' | 'action_required' | 'urgent' | 'critical';
  title: string;
  body: string | null;
  relatedEntityType: string | null;
  relatedEntityId: string | null;
  acknowledgementRequired: boolean;
  acknowledgedAt: string | null;
  createdAt: string;
}

const severityWeight = { info: 0, action_required: 1, urgent: 2, critical: 3 } as const;

function mapRow(n: any): AttentionRow {
  return {
    id: n.id,
    eventType: n.event_type,
    severity: n.severity,
    title: n.title,
    body: n.body,
    relatedEntityType: n.related_entity_type,
    relatedEntityId: n.related_entity_id,
    acknowledgementRequired: n.acknowledgement_required,
    acknowledgedAt: n.acknowledged_at,
    createdAt: n.created_at,
  };
}

export function AttentionCenter({
  userId,
  locale,
  soundEnabled,
  motionEnabled,
}: {
  userId: string;
  locale: 'en' | 'es';
  soundEnabled: boolean;
  motionEnabled: boolean;
}) {
  const es = locale === 'es';
  const supabaseRef = useRef(createClient());
  const [rows, setRows] = useState<AttentionRow[]>([]);
  const [toast, setToast] = useState<AttentionRow | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const reconcile = useCallback(async () => {
    const { data } = await supabaseRef.current
      .from('notifications')
      .select('id,event_type,severity,title,body,related_entity_type,related_entity_id,acknowledgement_required,acknowledged_at,created_at')
      .eq('recipient_user_id', userId)
      .is('read_at', null)
      .in('severity', ['action_required', 'urgent', 'critical'])
      .order('created_at', { ascending: false })
      .limit(6);
    const mapped = (data ?? []).map(mapRow).sort((a, b) => {
      const delta = severityWeight[b.severity] - severityWeight[a.severity];
      return delta || +new Date(b.createdAt) - +new Date(a.createdAt);
    });
    setRows(mapped);
  }, [userId]);

  useEffect(() => {
    setMuted(!soundEnabled);
    document.documentElement.dataset.kccMotion = motionEnabled ? 'on' : 'off';
  }, [soundEnabled, motionEnabled]);

  useEffect(() => {
    reconcile();
    const supabase = supabaseRef.current;
    const channel = supabase
      .channel(`attention-center:${userId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `recipient_user_id=eq.${userId}` },
        (payload) => {
          const next = mapRow(payload.new);
          playNotificationSound(resolveSoundId(next.eventType, next.severity));
          if (next.severity === 'info') {
            setToast(next);
            window.setTimeout(() => setToast((current) => current?.id === next.id ? null : current), 5200);
          }
          reconcile();
        },
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'notifications', filter: `recipient_user_id=eq.${userId}` },
        () => reconcile(),
      )
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [userId, reconcile]);

  const primary = rows[0] ?? null;
  const remaining = Math.max(0, rows.length - 1);
  const primaryLink = useMemo(() => primary ? getNotificationDeepLink(primary) : null, [primary]);

  async function resolve(row: AttentionRow, acknowledge = false) {
    setBusyId(row.id);
    try {
      if (acknowledge && row.acknowledgementRequired) await acknowledgeNotificationAction(row.id);
      else await markNotificationReadAction(row.id);
      await reconcile();
    } finally {
      setBusyId(null);
    }
  }

  return (
    <>
      {primary && (
        <aside className={`attention-center attention-center-${primary.severity}`} aria-live="polite">
          <div className="attention-center-beacon" aria-hidden="true"><span /></div>
          <div className="min-w-0 flex-1">
            <div className="attention-center-meta">
              <span>✦ LUZ</span>
              <span>{primary.severity === 'critical' ? (es ? 'CRÍTICO' : 'CRITICAL') : primary.severity === 'urgent' ? (es ? 'URGENTE' : 'URGENT') : (es ? 'REQUIERE ACCIÓN' : 'ACTION REQUIRED')}</span>
              {remaining > 0 && <span>+{remaining}</span>}
            </div>
            <h3>{primary.title}</h3>
            {primary.body && <p>{primary.body}</p>}
          </div>
          <div className="attention-center-actions">
            {primaryLink && <Link href={primaryLink} className="attention-primary-action">{es ? 'Abrir' : 'Open'} →</Link>}
            <button disabled={busyId === primary.id} onClick={() => resolve(primary, primary.acknowledgementRequired)} className="attention-secondary-action">
              {primary.acknowledgementRequired ? (es ? 'Atendido' : 'Acknowledge') : (es ? 'Visto' : 'Mark seen')}
            </button>
          </div>
        </aside>
      )}

      {toast && (
        <div className={`notification-live-toast toast-${toast.severity}`} role="status">
          <div className="notification-toast-orb" aria-hidden="true">✦</div>
          <div className="min-w-0 flex-1">
            <small>{toast.severity.replace('_', ' ')}</small>
            <strong>{toast.title}</strong>
            {toast.body && <p>{toast.body}</p>}
          </div>
          <button type="button" aria-label={es ? 'Cerrar' : 'Close'} onClick={() => setToast(null)}>×</button>
        </div>
      )}
    </>
  );
}
