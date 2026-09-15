'use client';

import { useState, useTransition } from 'react';
import { inviteCustomerPortalAccess } from '@/lib/customers/portal-actions';

export function CustomerPortalAccessButton({ customerId, alreadyLinked }: { customerId: string; alreadyLinked: boolean }) {
  const [pending, startTransition] = useTransition();
  const [result, setResult] = useState<Awaited<ReturnType<typeof inviteCustomerPortalAccess>> | null>(null);

  if (alreadyLinked) {
    return (
      <span className="inline-flex items-center gap-2 rounded-xl border border-emerald-300/15 bg-emerald-300/[.055] px-3 py-2 text-[10px] uppercase tracking-[.08em] text-emerald-300">
        <span className="h-1.5 w-1.5 rounded-full bg-emerald-300 shadow-[0_0_12px_rgba(110,231,183,.65)]" /> Portal active
      </span>
    );
  }

  return (
    <div className="relative">
      <button
        type="button"
        disabled={pending}
        onClick={() => startTransition(async () => setResult(await inviteCustomerPortalAccess(customerId)))}
        className="kcc-action"
      >
        {pending ? 'Preparing access…' : 'Enable customer portal →'}
      </button>
      {result && 'error' in result && result.error && (
        <div className="absolute right-0 top-full z-20 mt-2 w-80 rounded-2xl border border-red-300/15 bg-[#101823] p-3 text-[11px] text-red-200 shadow-2xl">
          {result.error}
        </div>
      )}
      {result && 'emailSent' in result && result.emailSent && (
        <div className="absolute right-0 top-full z-20 mt-2 w-80 rounded-2xl border border-emerald-300/15 bg-[#101823] p-3 text-[11px] text-emerald-200 shadow-2xl">
          Invitation delivered. The customer will create a password once, then sign in normally with email + password.
        </div>
      )}
      {result && 'manualUrl' in result && result.manualUrl && !result.emailSent && (
        <div className="absolute right-0 top-full z-20 mt-2 w-96 max-w-[85vw] rounded-2xl border border-amber-300/20 bg-[#101823] p-3 text-[11px] text-amber-100 shadow-2xl">
          <p>{result.emailError || 'Email delivery failed. You can resend without duplicating the account.'}</p>
          <details className="mt-2"><summary className="cursor-pointer text-gold">Emergency manual link</summary><code className="mt-2 block break-all text-[9px] text-gold/75">{result.manualUrl}</code></details>
        </div>
      )}
    </div>
  );
}
