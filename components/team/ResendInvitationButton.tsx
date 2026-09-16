'use client';

import { useState, useTransition } from 'react';
import { resendInvitation } from '@/lib/team/actions';

export function ResendInvitationButton({ invitationId }: { invitationId: string }) {
  const [pending, startTransition] = useTransition();
  const [state, setState] = useState<'idle' | 'sent' | 'error'>('idle');
  const [message, setMessage] = useState('');

  return (
    <div className="relative">
      <button
        type="button"
        disabled={pending}
        onClick={() => {
          setState('idle');
          startTransition(async () => {
            const result = await resendInvitation(invitationId);
            if ('error' in result && result.error) {
              setState('error');
              setMessage(result.error);
            } else if (result.emailSent) {
              setState('sent');
              setMessage('Invitation delivered');
            } else {
              setState('error');
              setMessage(result.emailError || 'Email delivery failed');
            }
          });
        }}
        className="rounded-lg border border-gold/20 bg-gold/[.055] px-2.5 py-1.5 text-[9px] font-mono uppercase tracking-[.08em] text-gold transition hover:border-gold/40 hover:bg-gold/[.1] disabled:opacity-40"
      >
        {pending ? 'Sending…' : state === 'sent' ? 'Sent ✓' : 'Resend'}
      </button>
      {state === 'error' && (
        <div className="absolute right-0 top-full z-30 mt-2 w-72 rounded-xl border border-red-300/15 bg-[#101823] p-3 text-[10px] leading-relaxed text-red-200 shadow-2xl">
          {message}
        </div>
      )}
    </div>
  );
}
