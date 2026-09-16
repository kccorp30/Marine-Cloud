import { getNotifications, getNotificationDeepLink } from '@/lib/notifications/data';
import { getNotificationPreferences } from '@/lib/notifications/preferences';
import { getLocale } from '@/lib/i18n/server';
import { NotificationItem } from '@/components/notifications/NotificationItem';
import { NotificationPreferencesControl } from '@/components/notifications/NotificationPreferencesControl';
import { MarkAllReadButton } from '@/components/notifications/MarkAllReadButton';

const SEVERITY_LABEL: Record<string, string> = {
  info: 'Info',
  action_required: 'Action Required',
  urgent: 'Urgent',
  critical: 'Critical',
};

export default async function NotificationsPage({ searchParams }: { searchParams: Promise<{ filter?: string }> }) {
  const { filter } = await searchParams;
  const activeFilter = filter === 'unread' || filter === 'action' ? filter : undefined;
  const [notifications, preferences, locale] = await Promise.all([
    getNotifications(activeFilter),
    getNotificationPreferences(),
    getLocale(),
  ]);
  const es = locale === 'es';
  const actionCount = notifications.filter((n) => ['action_required', 'urgent', 'critical'].includes(n.severity) && !n.readAt).length;
  const criticalCount = notifications.filter((n) => ['urgent', 'critical'].includes(n.severity) && !n.readAt).length;

  return (
    <div className="command-stack max-w-5xl space-y-6">
      <section className="notification-center-hero">
        <div className="notification-center-orb" aria-hidden="true">✦</div>
        <div className="min-w-0 flex-1">
          <p className="eyebrow">LUZ · {es ? 'CENTRO DE ATENCIÓN' : 'ATTENTION CENTER'}</p>
          <h1>{es ? 'Lo importante, primero.' : 'Important things first.'}</h1>
          <p>{es ? 'Las novedades que requieren acción permanecen visibles hasta que alguien las atienda.' : 'Operational events that need action stay visible until somebody handles them.'}</p>
        </div>
        <div className="notification-center-stats">
          <div><strong>{actionCount}</strong><span>{es ? 'por atender' : 'need action'}</span></div>
          <div className={criticalCount ? 'has-critical' : ''}><strong>{criticalCount}</strong><span>{es ? 'urgentes' : 'urgent'}</span></div>
        </div>
      </section>

      <div className="grid lg:grid-cols-[1fr_300px] gap-5 items-start">
        <section className="space-y-3">
          <div className="flex items-center justify-between gap-4 flex-wrap">
            <div className="notification-filter-rail">
              <a href="/notifications" className={!activeFilter ? 'is-active' : ''}>{es ? 'Todas' : 'All'}</a>
              <a href="/notifications?filter=unread" className={activeFilter === 'unread' ? 'is-active' : ''}>{es ? 'Sin leer' : 'Unread'}</a>
              <a href="/notifications?filter=action" className={activeFilter === 'action' ? 'is-active' : ''}>{es ? 'Requieren acción' : 'Action required'}</a>
            </div>
            <MarkAllReadButton />
          </div>

          <div className="space-y-2">
            {notifications.map((n) => (
              <NotificationItem key={n.id} notification={n} deepLink={getNotificationDeepLink(n)} severityLabel={SEVERITY_LABEL[n.severity] ?? n.severity} />
            ))}
            {notifications.length === 0 && (
              <div className="notification-empty-state">
                <div>✓</div>
                <h2>{es ? 'Todo está bajo control' : 'Everything is under control'}</h2>
                <p>{es ? 'No hay novedades en esta vista.' : 'There are no events in this view.'}</p>
              </div>
            )}
          </div>
        </section>

        <aside className="space-y-4 lg:sticky lg:top-3">
          <NotificationPreferencesControl initialSoundEnabled={preferences.soundEnabled} initialMotionEnabled={preferences.motionEnabled} locale={locale} />
          <div className="notification-luz-note">
            <span>✦</span>
            <div><b>LUZ</b><p>{es ? 'Las alertas urgentes tienen prioridad visual. El sonido y el movimiento son opcionales; la alerta nunca desaparece hasta ser atendida o marcada como vista.' : 'Urgent alerts receive visual priority. Sound and motion are optional; the event stays available until it is handled or marked seen.'}</p></div>
          </div>
        </aside>
      </div>
    </div>
  );
}
