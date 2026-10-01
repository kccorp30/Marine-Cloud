// "latest-update timestamps" reales, no decorativos — usado en listas
// (Today, Work Orders, Vessels) para mostrar "hace X" a partir de
// work_orders.last_activity_at, que se actualiza solo vía trigger
// sobre domain_events (nunca lo escribe la aplicación).
//
// Vivía en components/work-orders/Timeline.tsx junto a un segundo
// feed que el Work Story unificado reemplazó. Se movió acá para que
// quede UNA sola implementación de timeline en el repo.
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
