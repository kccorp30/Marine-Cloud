'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { useCommandCopy } from '@/components/ui/LocaleProvider';
import { workspaceCopy } from '@/lib/i18n/workspace-copy';
import { setWebsiteContentPublished, deleteWebsiteContent } from '@/lib/website/actions';

// Estado de publicación + acciones de un registro. Publicar es un
// paso explícito y separado de "Guardar": así Alejo puede corregir el
// texto que escribió Claude tranquilo, sin que salga al sitio a medias.
export function PublishControls({
  entity,
  id,
  published,
  publicUrl,
}: {
  entity: string;
  id: string;
  published: boolean;
  publicUrl: string | null;
}) {
  const { locale } = useCommandCopy();
  const t = workspaceCopy[locale] as Record<string, string>;
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const router = useRouter();

  function run(fn: () => Promise<{ error?: string; redirectTo?: string } | void>) {
    setError(null);
    start(async () => {
      const result = await fn();
      if (result && 'error' in result && result.error) {
        setError(result.error);
        return;
      }
      if (result && 'redirectTo' in result && result.redirectTo) router.push(result.redirectTo);
      router.refresh();
    });
  }

  return (
    <div className="premium-card rounded-xl p-5 space-y-4">
      <div className="flex items-center justify-between gap-3">
        <span
          className={`rounded-full px-3 py-1 font-mono text-[10px] uppercase tracking-wider ${
            published ? 'bg-emerald-400/10 text-emerald-300 border border-emerald-300/30' : 'bg-white/5 text-cool-gray border border-white/10'
          }`}
        >
          {published ? t['website.status.published'] : t['website.status.draft']}
        </span>
        {published && publicUrl && (
          <a href={publicUrl} target="_blank" rel="noreferrer" className="text-sm text-gold">
            {t['website.action.viewOnSite']} ↗
          </a>
        )}
      </div>

      <p className="text-xs text-cool-gray leading-relaxed">
        {published ? t['website.publish.liveHelp'] : t['website.publish.draftHelp']}
      </p>

      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          className={published ? 'kcc-action' : 'command-button'}
          disabled={pending}
          onClick={() => run(() => setWebsiteContentPublished(entity, id, !published))}
        >
          {pending ? '…' : published ? t['website.action.unpublish'] : t['website.action.publish']}
        </button>

        {!confirmDelete ? (
          <button type="button" className="kcc-action text-red-300" disabled={pending} onClick={() => setConfirmDelete(true)}>
            {t['website.action.delete']}
          </button>
        ) : (
          <>
            <button
              type="button"
              className="kcc-action text-red-300"
              disabled={pending}
              onClick={() => run(() => deleteWebsiteContent(entity, id))}
            >
              {t['website.action.confirmDelete']}
            </button>
            <button type="button" className="kcc-action" disabled={pending} onClick={() => setConfirmDelete(false)}>
              {t.cancel}
            </button>
          </>
        )}
      </div>

      {error && (
        <p role="alert" className="text-sm text-red-300">
          {error}
        </p>
      )}
    </div>
  );
}
