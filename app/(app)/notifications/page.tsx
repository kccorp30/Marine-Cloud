import { getNotifications, getNotificationDeepLink } from '@/lib/notifications/data';
import { NotificationItem } from '@/components/notifications/NotificationItem';
import { MarkAllReadButton } from '@/components/notifications/MarkAllReadButton';
import { Card, PageTitle } from '@/components/ui/primitives';

const SEVERITY_LABEL: Record<string, string> = {
  info: 'Info',
  action_required: 'Action Required',
  urgent: 'Urgent',
  critical: 'Critical',
};

export default async function NotificationsPage({ searchParams }: { searchParams: Promise<{ filter?: string }> }) {
  const { filter } = await searchParams;
  const activeFilter = filter === 'unread' || filter === 'action' ? filter : undefined;
  const notifications = await getNotifications(activeFilter);

  return (
    <div className="max-w-2xl space-y-6">
      <div className="flex items-center justify-between">
        <PageTitle>Notifications</PageTitle>
        <MarkAllReadButton />
      </div>

      <div className="flex gap-3 text-[10px] font-mono uppercase">
        <a href="/notifications" className={!activeFilter ? 'text-gold' : 'text-cool-gray'}>All</a>
        <a href="/notifications?filter=unread" className={activeFilter === 'unread' ? 'text-gold' : 'text-cool-gray'}>Unread</a>
        <a href="/notifications?filter=action" className={activeFilter === 'action' ? 'text-gold' : 'text-cool-gray'}>Action Required</a>
      </div>

      <div className="space-y-2">
        {notifications.map((n) => (
          <NotificationItem key={n.id} notification={n} deepLink={getNotificationDeepLink(n)} severityLabel={SEVERITY_LABEL[n.severity] ?? n.severity} />
        ))}
        {notifications.length === 0 && (
          <Card>
            <p className="text-sm text-cool-gray">No notifications.</p>
          </Card>
        )}
      </div>
    </div>
  );
}
