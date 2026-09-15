'use client';

import { useState, useTransition } from 'react';
import {
  assignSubscriptionAction,
  extendTrialAction,
  cancelSubscriptionAction,
  grantComplimentaryAction,
  removeComplimentaryAction,
  archiveOrganizationAction,
  reactivateOrganizationAction,
  changeSubscriptionPlanAction,
  grantGracePeriodAction,
  endGracePeriodAction,
} from '@/lib/subscriptions/actions';
import type { SubscriptionRow, PlanOption } from '@/lib/subscriptions/data';

export function CommercialSection({
  organizationId,
  organizationStatus,
  subscription,
  plans,
}: {
  organizationId: string;
  organizationStatus: string;
  subscription: SubscriptionRow | null;
  plans: PlanOption[];
}) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [section, setSection] = useState<'none' | 'setup' | 'extend' | 'complimentary' | 'cancel' | 'archive' | 'changePlan' | 'grace'>('none');

  // Commercial Setup — sin suscripción todavía
  const [planId, setPlanId] = useState(plans[0]?.id ?? '');
  const [billingCycle, setBillingCycle] = useState('weekly');
  const [trialDays, setTrialDays] = useState('14');
  const [noTrial, setNoTrial] = useState(false);
  const [complimentary, setComplimentary] = useState(false);
  const [complimentaryReason, setComplimentaryReason] = useState('');

  const [extendDays, setExtendDays] = useState('7');
  const [cancelImmediately, setCancelImmediately] = useState(true);
  const [reasonText, setReasonText] = useState('');
  const [priceOverride, setPriceOverride] = useState('');
  const [customTerms, setCustomTerms] = useState('');
  const [graceDays, setGraceDays] = useState('7');

  function run(fn: () => Promise<{ error?: string } | undefined>) {
    setError(null);
    startTransition(async () => {
      const res = await fn();
      if (res?.error) setError(res.error);
      else setSection('none');
    });
  }

  return (
    <div className="space-y-4">
      <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold">Commercial / Billing</div>

      {subscription ? (
        <div className="text-sm space-y-1">
          <div>
            Plan: {subscription.planName} ({subscription.billingCycle})
          </div>
          <div>Status: {subscription.effectiveStatus}</div>
          {subscription.priceSnapshot !== null && !subscription.complimentary && (
            <div>
              Negotiated price: {subscription.currency} {subscription.priceSnapshot}
              <span className="text-[10px] text-cool-gray"> (this company's actual agreed price — never changes when the plan catalog price changes)</span>
            </div>
          )}
          {subscription.complimentary && <div className="text-cool-gray">Complimentary — {subscription.complimentaryReason}</div>}
          {subscription.customTerms && <div className="text-cool-gray">Custom terms: {subscription.customTerms}</div>}
          {subscription.trialEndsAt && <div className="text-cool-gray">Trial ends: {new Date(subscription.trialEndsAt).toLocaleString()}</div>}
          {subscription.effectiveStatus === 'grace_period' && subscription.gracePeriodEndsAt && (
            <div className="text-amber-400">
              Grace until {new Date(subscription.gracePeriodEndsAt).toLocaleString()} — after this, access becomes restricted (past_due). Not caused by any payment provider in this phase.
            </div>
          )}
          {subscription.cancelledAt && <div className="text-red-400">Cancelled: {new Date(subscription.cancelledAt).toLocaleString()}</div>}
        </div>
      ) : (
        <p className="text-sm text-cool-gray">No commercial subscription set up yet.</p>
      )}

      {error && <p className="text-xs text-red-400">{error}</p>}

      <div className="flex flex-wrap gap-2 text-[9px] font-mono uppercase">
        {!subscription && (
          <button type="button" onClick={() => setSection('setup')} className="border border-gold-dim text-gold px-2 py-1 rounded-sm">
            Commercial Setup
          </button>
        )}
        {subscription?.effectiveStatus === 'trialing' && (
          <button type="button" onClick={() => setSection('extend')} className="border border-gold-dim text-gold px-2 py-1 rounded-sm">
            Extend Trial
          </button>
        )}
        {subscription && (
          <button type="button" onClick={() => setSection('changePlan')} className="border border-gold-dim text-gold px-2 py-1 rounded-sm">
            Change Plan
          </button>
        )}
        {subscription && !subscription.complimentary && (
          <button type="button" onClick={() => setSection('complimentary')} className="border border-gold-dim text-gold px-2 py-1 rounded-sm">
            Grant Complimentary
          </button>
        )}
        {subscription?.complimentary && (
          <button type="button" disabled={pending} onClick={() => run(() => removeComplimentaryAction(organizationId))} className="border border-gold-dim text-gold px-2 py-1 rounded-sm">
            Remove Complimentary
          </button>
        )}
        {subscription && subscription.effectiveStatus !== 'cancelled' && (
          <button type="button" onClick={() => setSection('cancel')} className="border border-red-500/30 text-red-400 px-2 py-1 rounded-sm">
            Cancel Subscription
          </button>
        )}
        {subscription && subscription.effectiveStatus === 'grace_period' ? (
          <button type="button" disabled={pending} onClick={() => run(() => endGracePeriodAction(organizationId, 'past_due', 'Grace period ended manually'))} className="border border-gold-dim text-gold px-2 py-1 rounded-sm">
            End Grace Period
          </button>
        ) : (
          subscription && (
            <button type="button" onClick={() => setSection('grace')} className="border border-gold-dim text-gold px-2 py-1 rounded-sm">
              Grant Grace Period
            </button>
          )
        )}
        {organizationStatus !== 'archived' ? (
          <button type="button" onClick={() => setSection('archive')} className="border border-red-500/30 text-red-400 px-2 py-1 rounded-sm">
            Archive Company
          </button>
        ) : (
          <button type="button" disabled={pending} onClick={() => run(() => reactivateOrganizationAction(organizationId, null))} className="border border-gold-dim text-gold px-2 py-1 rounded-sm">
            Reactivate
          </button>
        )}
      </div>

      {section === 'setup' && (
        <div className="space-y-2 border border-white/10 rounded-sm p-3">
          <select value={planId} onChange={(e) => setPlanId(e.target.value)} className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2">
            {plans.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
          <select value={billingCycle} onChange={(e) => setBillingCycle(e.target.value)} className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2">
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
            <option value="annual">Annual</option>
            <option value="custom">Custom</option>
          </select>
          <label className="flex items-center gap-2 text-xs text-cool-gray">
            <input type="checkbox" checked={noTrial} onChange={(e) => setNoTrial(e.target.checked)} />
            No trial — activate immediately
          </label>
          {!noTrial && <input type="number" value={trialDays} onChange={(e) => setTrialDays(e.target.value)} placeholder="Trial days" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />}
          <label className="flex items-center gap-2 text-xs text-cool-gray">
            <input type="checkbox" checked={complimentary} onChange={(e) => setComplimentary(e.target.checked)} />
            Complimentary access (no charge)
          </label>
          {complimentary && (
            <input
              value={complimentaryReason}
              onChange={(e) => setComplimentaryReason(e.target.value)}
              placeholder="Reason (required)"
              className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
            />
          )}
          {!complimentary && (
            <input value={priceOverride} onChange={(e) => setPriceOverride(e.target.value)} placeholder="Price override (optional — leave blank to use catalog price)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          )}
          <input value={customTerms} onChange={(e) => setCustomTerms(e.target.value)} placeholder="Commercial notes / custom terms (optional)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <button
            type="button"
            disabled={pending || !planId}
            onClick={() =>
              run(() =>
                assignSubscriptionAction({
                  organizationId,
                  planId,
                  billingCycle,
                  trialDays: noTrial ? null : Number(trialDays),
                  priceOverride: priceOverride ? Number(priceOverride) : null,
                  complimentary,
                  complimentaryReason: complimentary ? complimentaryReason : null,
                  customTerms: customTerms || null,
                }),
              )
            }
            className="text-sm bg-gold text-navy px-4 py-2 rounded-sm"
          >
            Activate Commercial Setup
          </button>
        </div>
      )}

      {section === 'extend' && (
        <div className="space-y-2 border border-white/10 rounded-sm p-3">
          <input type="number" value={extendDays} onChange={(e) => setExtendDays(e.target.value)} placeholder="Days to extend" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <button
            type="button"
            disabled={pending}
            onClick={() => run(() => extendTrialAction(organizationId, new Date(Date.now() + Number(extendDays) * 86400000).toISOString(), reasonText || null))}
            className="text-sm bg-gold text-navy px-4 py-2 rounded-sm"
          >
            Extend Trial
          </button>
        </div>
      )}

      {section === 'changePlan' && (
        <div className="space-y-2 border border-white/10 rounded-sm p-3">
          <select value={planId} onChange={(e) => setPlanId(e.target.value)} className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2">
            {plans.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
          <select value={billingCycle} onChange={(e) => setBillingCycle(e.target.value)} className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2">
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
            <option value="annual">Annual</option>
            <option value="custom">Custom</option>
          </select>
          <input
            value={priceOverride}
            onChange={(e) => setPriceOverride(e.target.value)}
            placeholder="Negotiated price override (optional — leave blank to use catalog price)"
            className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2"
          />
          <p className="text-[10px] text-cool-gray">An override only changes this company's negotiated price — it never edits the plan catalog.</p>
          <button
            type="button"
            disabled={pending || !planId}
            onClick={() => run(() => changeSubscriptionPlanAction(organizationId, planId, billingCycle, priceOverride ? Number(priceOverride) : null))}
            className="text-sm bg-gold text-navy px-4 py-2 rounded-sm"
          >
            Change Plan (effective immediately)
          </button>
        </div>
      )}

      {section === 'grace' && (
        <div className="space-y-2 border border-white/10 rounded-sm p-3">
          <input type="number" value={graceDays} onChange={(e) => setGraceDays(e.target.value)} placeholder="Grace period length (days)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <input value={reasonText} onChange={(e) => setReasonText(e.target.value)} placeholder="Reason" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <p className="text-[10px] text-cool-gray">This is a manual grace period, not triggered by any payment provider — Phase 15 will handle real payment failures.</p>
          <button
            type="button"
            disabled={pending}
            onClick={() => run(() => grantGracePeriodAction(organizationId, new Date(Date.now() + Number(graceDays) * 86400000).toISOString(), reasonText || null))}
            className="text-sm bg-gold text-navy px-4 py-2 rounded-sm"
          >
            Grant Grace Period
          </button>
        </div>
      )}

      {section === 'complimentary' && (
        <div className="space-y-2 border border-white/10 rounded-sm p-3">
          <input value={complimentaryReason} onChange={(e) => setComplimentaryReason(e.target.value)} placeholder="Reason (required)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <button type="button" disabled={pending || !complimentaryReason.trim()} onClick={() => run(() => grantComplimentaryAction(organizationId, complimentaryReason))} className="text-sm bg-gold text-navy px-4 py-2 rounded-sm">
            Grant Complimentary Access
          </button>
        </div>
      )}

      {section === 'cancel' && (
        <div className="space-y-2 border border-white/10 rounded-sm p-3">
          <label className="flex items-center gap-2 text-xs text-cool-gray">
            <input type="checkbox" checked={cancelImmediately} onChange={(e) => setCancelImmediately(e.target.checked)} />
            Cancel immediately (uncheck for end-of-period)
          </label>
          <input value={reasonText} onChange={(e) => setReasonText(e.target.value)} placeholder="Reason (optional)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <button type="button" disabled={pending} onClick={() => run(() => cancelSubscriptionAction(organizationId, cancelImmediately, reasonText || null))} className="text-sm bg-red-500/20 text-red-400 px-4 py-2 rounded-sm">
            Confirm Cancellation
          </button>
        </div>
      )}

      {section === 'archive' && (
        <div className="space-y-2 border border-white/10 rounded-sm p-3">
          <input value={reasonText} onChange={(e) => setReasonText(e.target.value)} placeholder="Reason (required)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <p className="text-xs text-cool-gray">Data is preserved. Operational access is disabled. This can be reversed later.</p>
          <button type="button" disabled={pending || !reasonText.trim()} onClick={() => run(() => archiveOrganizationAction(organizationId, reasonText))} className="text-sm bg-red-500/20 text-red-400 px-4 py-2 rounded-sm">
            Confirm Archive
          </button>
        </div>
      )}
    </div>
  );
}
