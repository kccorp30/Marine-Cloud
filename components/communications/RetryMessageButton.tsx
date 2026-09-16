'use client';

import { useState, useTransition } from 'react';
import { retryFailedMessageAction } from '@/lib/communications/actions';

export function RetryMessageButton({ messageId, conversationId }: { messageId: string; conversationId: string }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [retried, setRetried] = useState(false);

  if (retried) return null;

  return (
    <div className="mt-2">
      <button
        type="button"
        disabled={pending}
        onClick={() => {
          setError(null);
          const formData = new FormData();
          formData.set('messageId', messageId);
          formData.set('conversationId', conversationId);
          startTransition(async () => {
            const res = await retryFailedMessageAction(formData);
            if (res?.error) {
              setError(res.error);
              return;
            }
            setRetried(true);
          });
        }}
        className="text-[9px] font-mono uppercase border border-red-500/30 text-red-400 px-2 py-1 rounded-sm"
      >
        {pending ? 'Retrying…' : 'Retry Send'}
      </button>
      {error && <p className="text-xs text-red-400 mt-1">{error}</p>}
    </div>
  );
}
