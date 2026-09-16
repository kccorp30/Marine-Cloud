import type { EntityMediaItem } from '@/lib/media/entity-media';

export function EntityMediaGallery({ items, title = 'Photos' }: { items: EntityMediaItem[]; title?: string }) {
  if (!items.length) return null;
  return (
    <section className="media-gallery-shell">
      <div className="flex items-center justify-between gap-3 mb-4">
        <div><p className="command-kicker">VISUAL CONTEXT</p><h3 className="text-lg font-semibold mt-1">{title}</h3></div>
        <span className="media-count">{items.length}</span>
      </div>
      <div className="media-gallery-grid">
        {items.map((item) => (
          <a key={item.id} href={item.url} target="_blank" rel="noreferrer" className="media-gallery-item">
            <img src={item.url} alt={item.caption || 'Marine service photo'} loading="lazy" />
            <span className="media-gallery-overlay">
              <small>{item.category.replaceAll('_', ' ')}</small>
              {item.caption && <strong>{item.caption}</strong>}
            </span>
          </a>
        ))}
      </div>
    </section>
  );
}
