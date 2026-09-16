'use client';

import Link from 'next/link';
import { useState } from 'react';
import { Drawer } from '@/components/smart/Drawer';
import { useCommandCopy } from '@/components/ui/LocaleProvider';
import { acknowledgeNotificationAction, markNotificationReadAction } from '@/lib/notifications/actions';
import type { NotificationDTO } from '@/lib/notifications/data';

export function NotificationItem({
  notification: n,
  deepLink,
  severityLabel,
}: {
  notification: NotificationDTO;
  deepLink: string | null;
  severityLabel: string;
}) {
  const { t, locale } = useCommandCopy();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');
  const [read, setRead] = useState(Boolean(n.readAt));
  const [ack, setAck] = useState(Boolean(n.acknowledgedAt));

  async function update(acknowledge: boolean) {
    setPending(true);
    setError('');
    const result = acknowledge
      ? await acknowledgeNotificationAction(n.id)
      : await markNotificationReadAction(n.id);
    if (result?.error) setError(result.error);
    else {
      setRead(true);
      if (acknowledge) setAck(true);
    }
    setPending(false);
  }

  const icon = n.severity === 'critical' ? '!' : n.severity === 'urgent' ? '↑' : n.severity === 'action_required' ? '✦' : '·';

  return (
    <article className={`notification-card severity-${n.severity} ${read ? 'is-read' : 'is-unread'}`}>
      <div className="notification-card-icon" aria-hidden="true">{icon}</div>
      <div className="min-w-0 flex-1">
        <div className="notification-card-meta">
          <span>{severityLabel}</span>
          <time>{new Date(n.createdAt).toLocaleString(locale)}</time>
        </div>
        <h2>{n.title}</h2>
        {n.body && <p>{n.body}</p>}
        <div className="notification-card-actions">
          {deepLink && <Link className="notification-action-primary" href={deepLink}>{t.open} →</Link>}
          {!read && <button disabled={pending} onClick={() => update(false)}>{t.read}</button>}
          {n.acknowledgementRequired && !ack && <button disabled={pending} onClick={() => update(true)}>{t.acknowledge}</button>}
          {ack && <span className="notification-ack">✓ {t.acknowledged}</span>}
          <Drawer label={t.details} title={n.title}>
            <div className="space-y-6">
              <p className="kcc-eyebrow">{severityLabel}</p>
              <p className="whitespace-pre-wrap leading-relaxed">{n.body || n.title}</p>
              <time className="text-sm text-cool-gray">{new Date(n.createdAt).toLocaleString(locale)}</time>
              {deepLink && <Link className="kcc-action" href={deepLink}>{t.open} →</Link>}
            </div>
          </Drawer>
        </div>
        {error && <p role="alert" className="text-xs text-red-300 mt-2">{error}</p>}
      </div>
      {!read && <span className="notification-unread-dot" aria-label={t.unread} />}
    </article>
  );
}
