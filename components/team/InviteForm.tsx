'use client';

import { useState, useTransition } from 'react';
import { inviteTeamMember } from '@/lib/team/actions';
import { inputClass, Field } from '@/components/ui/primitives';

const ALL_INVITABLE_ROLES = ['company_owner', 'company_admin', 'manager', 'technician'] as const;
const SELF_SERVICE_ROLES = ['company_admin', 'manager', 'technician'] as const;

type InviteResult = {
  manualUrl?: string;
  error?: string;
  emailSent?: boolean;
  emailError?: string;
  rateLimited?: boolean;
};

export function InviteForm({
  canInviteAdminLevel,
  organizationId,
  isKccAdmin = false,
}: {
  canInviteAdminLevel: boolean;
  organizationId?: string;
  isKccAdmin?: boolean;
}) {
  const [pending, startTransition] = useTransition();
  const [result, setResult] = useState<InviteResult | null>(null);
  const roles = isKccAdmin ? ALL_INVITABLE_ROLES : SELF_SERVICE_ROLES;

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-sm font-medium text-marine-white">Invite a team member</p>
          <p className="mt-1 text-[11px] text-cool-gray">They activate once by email, create a password, then sign in normally from any device.</p>
        </div>
        <span className="auth-live-pill shrink-0"><i /> Secure invite</span>
      </div>

      <form
        action={(formData) => {
          setResult(null);
          startTransition(async () => setResult(await inviteTeamMember(formData)));
        }}
        className="grid gap-3 lg:grid-cols-[1fr_1.25fr_.8fr_auto] lg:items-end"
      >
        {organizationId && <input type="hidden" name="organizationId" value={organizationId} />}
        <Field label="Full name">
          <input name="fullName" type="text" className={inputClass} placeholder="Optional" />
        </Field>
        <Field label="Email">
          <input name="email" type="email" required className={inputClass} placeholder="name@company.com" />
        </Field>
        <Field label="Role">
          <select name="role" required className={inputClass} defaultValue="">
            <option value="" disabled>Select…</option>
            {roles.filter((r) => canInviteAdminLevel || (r !== 'company_admin' && r !== 'company_owner')).map((r) => (
              <option key={r} value={r} className="bg-navy">{r.replace(/_/g, ' ')}</option>
            ))}
          </select>
        </Field>
        <button type="submit" disabled={pending} className="auth-primary-button !w-auto !min-w-[132px] !px-5 !py-3.5">
          <span>{pending ? 'Sending…' : 'Send invite'}</span><span>→</span>
        </button>
      </form>

      {result?.error && (
        <div className="auth-alert"><span>!</span><p>{result.error}</p></div>
      )}

      {result?.emailSent && (
        <div className="rounded-2xl border border-emerald-300/15 bg-emerald-300/[.055] p-4 text-xs text-emerald-100 animate-fade-up">
          <div className="flex items-center gap-3"><span className="grid h-8 w-8 place-items-center rounded-full bg-emerald-300/10 text-emerald-300">✓</span><div><p className="font-medium">Invitation delivered</p><p className="mt-1 text-emerald-100/55">The secure activation link was accepted by the email provider.</p></div></div>
        </div>
      )}

      {result?.manualUrl && !result.emailSent && (
        <div className="rounded-2xl border border-amber-400/20 bg-amber-400/[.055] p-4 animate-fade-up">
          <p className="text-xs font-medium text-marine-white">Invitation created, delivery failed</p>
          <p className="mt-1 text-[11px] leading-relaxed text-cool-gray">
            {result.rateLimited ? 'The email provider is rate limited. Wait, then use Resend — the workspace and account were not duplicated.' : result.emailError || 'Use Resend after checking email configuration.'}
          </p>
          <details className="mt-3">
            <summary className="cursor-pointer text-[10px] font-mono uppercase tracking-[.1em] text-gold">Emergency manual link</summary>
            <code className="mt-2 block break-all rounded-xl border border-white/[.06] bg-black/20 p-3 text-[10px] text-gold/80">{result.manualUrl}</code>
          </details>
        </div>
      )}
    </div>
  );
}
