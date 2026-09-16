import type { TimelineEntry } from '@/lib/data/timeline';
import { Card } from '@/components/ui/primitives';

export function Timeline({ entries }: { entries: TimelineEntry[] }) {
  return (
    <Card>
      <div className="font-mono text-[10px] uppercase tracking-[0.15em] text-gold-dim mb-4">Activity</div>
      {entries.length === 0 ? (
        <p className="text-xs text-cool-gray">No activity yet.</p>
      ) : (
        <ol className="relative pl-4 space-y-4">
          <span className="absolute left-0 top-1.5 bottom-1.5 w-px bg-gradient-to-b from-gold-dim via-white/10 to-transparent" />
          {entries.map((entry, i) => (
            <li key={entry.id} className="relative animate-fade-up" style={{ animationDelay: `${Math.min(i, 8) * 40}ms` }}>
              {i === 0 ? (
                <span className="absolute -left-[17px] top-1 flex h-2.5 w-2.5">
                  <span className="animate-pulse-soft absolute inline-flex h-full w-full rounded-full bg-gold opacity-60" />
                  <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-gold shadow-glow-gold" />
                </span>
              ) : (
                <span className="absolute -left-[15px] top-1.5 w-1.5 h-1.5 rounded-full bg-gold-dim/60" />
              )}
              <div className="flex items-baseline justify-between gap-2">
                <span className="text-sm font-medium text-marine-white">{entry.title}</span>
                <span className="font-mono text-[9px] text-cool-gray whitespace-nowrap">
                  {new Date(entry.occurredAt).toLocaleString(undefined, {
                    month: 'short',
                    day: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit',
                  })}
                </span>
              </div>
              {entry.detail && <div className="text-xs text-cool-gray mt-0.5">{entry.detail}</div>}
              {entry.actorName && <div className="text-[10px] text-cool-gray/70 mt-0.5">by {entry.actorName}</div>}
            </li>
          ))}
        </ol>
      )}
    </Card>
  );
}

// "latest-update timestamps" reales, no decorativos — usado en listas
// (Today, Work Orders) para mostrar "hace X" a partir de
// work_orders.last_activity_at, que se actualiza solo vía trigger
// sobre domain_events (nunca lo escribe la aplicación).
export function RelativeTime({ date }: { date: string | null }) {
  if (!date) return null;
  const diffMs = Date.now() - new Date(date).getTime();
  const diffMin = Math.floor(diffMs / 60000);

  let label: string;
  if (diffMin < 1) label = 'just now';
  else if (diffMin < 60) label = `${diffMin}m ago`;
  else if (diffMin < 1440) label = `${Math.floor(diffMin / 60)}h ago`;
  else label = `${Math.floor(diffMin / 1440)}d ago`;

  return <span className="text-[10px] text-cool-gray/70">{label}</span>;
}
