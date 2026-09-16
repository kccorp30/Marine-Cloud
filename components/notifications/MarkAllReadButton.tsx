'use client';

import { useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { markAllNotificationsReadAction } from '@/lib/notifications/actions';

export function MarkAllReadButton() {
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          await markAllNotificationsReadAction();
          router.refresh();
        });
      }}
      className="text-[10px] font-mono uppercase text-cool-gray hover:text-gold"
    >
      Mark all read
    </button>
  );
}
