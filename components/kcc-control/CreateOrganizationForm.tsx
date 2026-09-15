"use client";

import { BILLING_PAUSED } from "@/lib/launch/config";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createOrganizationAction } from "@/lib/kcc-control/actions";
import type { PlanOption } from "@/lib/subscriptions/data";

export function CreateOrganizationForm({ plans }: { plans: PlanOption[] }) {
  const [pending, startTransition] = useTransition();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<{ organizationId: string; emailSent?: boolean; emailError?: string } | null>(null);
  const [noTrial, setNoTrial] = useState(false);
  const [complimentary, setComplimentary] = useState(false);
  const router = useRouter();

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="auth-primary-button !w-auto !px-4 !py-2.5"
      >
        + New Company
      </button>
    );
  }

  return (
    <div className="relative overflow-hidden premium-card rounded-2xl p-5 sm:p-6 space-y-4">
      <div className="font-mono text-[10px] uppercase tracking-[0.14em] text-gold">
        New Company
      </div>
      {error && <div className="auth-alert"><span>!</span><p>{error}</p></div>}
      {created && (
        <div className="rounded-2xl border border-amber-400/20 bg-amber-400/[.06] p-4 animate-fade-up">
          <div className="flex items-start gap-3">
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-amber-300/10 text-amber-300">!</span>
            <div className="min-w-0">
              <p className="text-sm font-medium text-marine-white">Company created — invitation needs attention</p>
              <p className="mt-1 text-xs leading-relaxed text-cool-gray">{created.emailError || 'The owner email could not be delivered. The company was not duplicated and the pending invitation can be resent safely.'}</p>
              <button type="button" onClick={() => router.push(`/companies/${created.organizationId}`)} className="mt-3 rounded-xl border border-gold/25 bg-gold/[.08] px-4 py-2 text-[10px] font-mono uppercase tracking-[.1em] text-gold hover:bg-gold/[.13] transition">Open company & resend →</button>
            </div>
          </div>
        </div>
      )}
      <form
        action={(formData) => {
          setError(null);
          setCreated(null);
          startTransition(async () => {
            const res = await createOrganizationAction(formData);
            if (res?.error) {
              setError(res.error);
              return;
            }
            if (res.organizationId) {
              if (res.emailSent === false) {
                setCreated({ organizationId: res.organizationId, emailSent: false, emailError: res.emailError });
                return;
              }
              setOpen(false);
              router.push(`/companies/${res.organizationId}`);
            }
          });
        }}
        className="space-y-3"
      >
        <div className="grid grid-cols-2 gap-3">
          <input
            name="name"
            required
            placeholder="Company name"
            className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          <input
            name="legalName"
            placeholder="Legal name (optional)"
            className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
        </div>
        <div className="grid grid-cols-3 gap-3">
          <input
            name="timezone"
            defaultValue="America/New_York"
            placeholder="Timezone"
            className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          <input
            name="currency"
            defaultValue="USD"
            placeholder="Currency"
            className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          <input
            name="locale"
            defaultValue="en"
            placeholder="Locale"
            className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <input
            name="locationName"
            placeholder="Primary location name"
            className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          <input
            name="locationAddress"
            placeholder="Address"
            className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
        </div>
        <input
          name="ownerEmail"
          type="email"
          placeholder="Owner email (invites them as company_owner)"
          className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
        />

        {!BILLING_PAUSED && (
          <>
            <div className="font-mono text-[9px] uppercase text-gold pt-2">
              Commercial Setup
            </div>
            <div className="grid grid-cols-2 gap-3">
              <select
                name="planId"
                required
                className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
              >
                {plans.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
              <select
                name="billingCycle"
                defaultValue="weekly"
                className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
              >
                <option value="weekly">Weekly</option>
                <option value="monthly">Monthly</option>
                <option value="annual">Annual</option>
                <option value="custom">Custom</option>
              </select>
            </div>
            <label className="flex items-center gap-2 text-xs text-cool-gray">
              <input
                type="checkbox"
                name="noTrial"
                checked={noTrial}
                onChange={(e) => setNoTrial(e.target.checked)}
                disabled={complimentary}
              />
              No trial — activate immediately
            </label>
            {!noTrial && !complimentary && (
              <input
                name="trialDays"
                type="number"
                defaultValue="14"
                placeholder="Trial days"
                className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
              />
            )}
            <label className="flex items-center gap-2 text-xs text-cool-gray">
              <input
                type="checkbox"
                name="complimentary"
                checked={complimentary}
                onChange={(e) => setComplimentary(e.target.checked)}
              />
              Complimentary access (no charge)
            </label>
            {complimentary && (
              <input
                name="complimentaryReason"
                placeholder="Reason (required)"
                className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
              />
            )}
            <input
              name="customTerms"
              placeholder="Commercial notes (optional)"
              className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
            />
          </>
        )}
        <div className="flex gap-2">
          <button
            type="submit"
            disabled={pending}
            className="auth-primary-button !w-auto !px-5 !py-2.5"
          >
            <span>{pending ? "Creating secure workspace…" : "Create Company"}</span><span>→</span>
          </button>
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="rounded-xl px-4 py-2.5 text-[10px] font-mono uppercase text-cool-gray hover:text-marine-white hover:bg-white/[.04] transition"
          >
            Cancel
          </button>
        </div>
      </form>
    </div>
  );
}
