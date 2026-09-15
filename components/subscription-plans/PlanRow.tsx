'use client';

import { useState, useTransition } from 'react';
import { updatePlanAction, togglePlanEntitlementAction, archivePlanAction } from '@/lib/subscription-plans/actions';
import { CORE_MODULE_KEYS } from '@/lib/subscription-plans/shared';
import type { PlanManagementRow } from '@/lib/subscription-plans/shared';

const STATUS_COLOR: Record<string, string> = { active: 'text-emerald-400', inactive: 'text-cool-gray', archived: 'text-red-400' };

export function PlanRow({ plan }: { plan: PlanManagementRow }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [weekly, setWeekly] = useState(plan.weeklyPrice?.toString() ?? '');
  const [monthly, setMonthly] = useState(plan.monthlyPrice?.toString() ?? '');
  const [annual, setAnnual] = useState(plan.annualPrice?.toString() ?? '');
  const [name, setName] = useState(plan.name);
  const [description, setDescription] = useState(plan.description ?? '');
  const [status, setStatus] = useState(plan.status);
  const [isPublic, setIsPublic] = useState(plan.isPublic);
  const [trialDays, setTrialDays] = useState(plan.trialDefaultDays?.toString() ?? '');

  function run(fn: () => Promise<{ error?: string } | undefined>) {
    setError(null);
    startTransition(async () => {
      const res = await fn();
      if (res?.error) setError(res.error);
    });
  }

  return (
    <div className="border border-white/10 rounded-sm p-4 space-y-2">
      <div className="flex items-center justify-between">
        <div>
          <span className="text-sm font-medium">{plan.name}</span>
          <span className="text-[10px] text-cool-gray ml-2">({plan.code})</span>
        </div>
        <div className="flex items-center gap-2">
          {plan.isCustom && <span className="font-mono text-[9px] uppercase text-cool-gray">Custom</span>}
          {!plan.isPublic && <span className="font-mono text-[9px] uppercase text-cool-gray">Private</span>}
          <span className={`font-mono text-[9px] uppercase ${STATUS_COLOR[plan.status] ?? 'text-cool-gray'}`}>{plan.status}</span>
        </div>
      </div>

      {plan.description && <p className="text-xs text-cool-gray">{plan.description}</p>}
      <div className="text-xs text-cool-gray">
        {/* Precio de catálogo — nunca el precio negociado de una company específica, eso vive en organization_subscriptions.price_snapshot */}
        Catalog price: {plan.weeklyPrice !== null && `${plan.currency} ${plan.weeklyPrice}/wk`} {plan.monthlyPrice !== null && `· ${plan.currency} ${plan.monthlyPrice}/mo`}{' '}
        {plan.annualPrice !== null && `· ${plan.currency} ${plan.annualPrice}/yr`}
        {plan.trialDefaultDays !== null && ` · ${plan.trialDefaultDays}-day default trial`}
      </div>
      <div className="text-xs text-cool-gray">{plan.activeSubscriptionCount} organization(s) currently on this plan</div>

      {error && <p className="text-xs text-red-400">{error}</p>}

      <div className="font-mono text-[9px] uppercase text-gold pt-1">Modules</div>
      <div className="grid grid-cols-3 gap-1.5">
        {CORE_MODULE_KEYS.map((key) => (
          <button
            key={key}
            type="button"
            disabled={pending}
            onClick={() => run(() => togglePlanEntitlementAction(plan.id, key, !plan.entitlements[key]))}
            className={`text-[9px] font-mono uppercase px-2 py-1 rounded-sm border ${plan.entitlements[key] ? 'border-gold-dim text-gold' : 'border-white/10 text-cool-gray'}`}
          >
            {key.replace('_', ' ')}
          </button>
        ))}
      </div>
      <p className="text-[9px] text-cool-gray">Toggling a module takes effect immediately for every organization currently on this plan.</p>

      <div className="flex gap-2 pt-2 text-[9px] font-mono uppercase">
        <button type="button" onClick={() => setEditing((v) => !v)} className="border border-gold-dim text-gold px-2 py-1 rounded-sm">
          {editing ? 'Close' : 'Edit Plan'}
        </button>
        {plan.status !== 'archived' && (
          <button type="button" disabled={pending} onClick={() => run(() => archivePlanAction(plan.id))} className="border border-red-500/30 text-red-400 px-2 py-1 rounded-sm">
            Archive
          </button>
        )}
      </div>

      {editing && (
        <div className="space-y-2 border border-white/10 rounded-sm p-3">
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Name" className="w-full text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5" />
          <input value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Description" className="w-full text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5" />
          <div className="grid grid-cols-3 gap-2">
            <input value={weekly} onChange={(e) => setWeekly(e.target.value)} placeholder="Weekly" className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5" />
            <input value={monthly} onChange={(e) => setMonthly(e.target.value)} placeholder="Monthly" className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5" />
            <input value={annual} onChange={(e) => setAnnual(e.target.value)} placeholder="Annual" className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5" />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <input value={trialDays} onChange={(e) => setTrialDays(e.target.value)} placeholder="Default trial days" className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5" />
            <select value={status} onChange={(e) => setStatus(e.target.value)} className="text-xs bg-white/[0.04] border border-white/10 rounded-sm px-2 py-1.5">
              <option value="active">Active</option>
              <option value="inactive">Inactive</option>
              <option value="archived">Archived</option>
            </select>
          </div>
          <label className="flex items-center gap-2 text-xs text-cool-gray">
            <input type="checkbox" checked={isPublic} onChange={(e) => setIsPublic(e.target.checked)} />
            Public — company owners/admins can self-select this plan
          </label>
          <p className="text-[9px] text-cool-gray">
            Editing catalog pricing never changes the negotiated price already snapshotted on an existing company's subscription.
          </p>
          <button
            type="button"
            disabled={pending}
            onClick={() =>
              run(() =>
                updatePlanAction({
                  planId: plan.id,
                  name: name || undefined,
                  description,
                  weeklyPrice: weekly ? Number(weekly) : null,
                  monthlyPrice: monthly ? Number(monthly) : null,
                  annualPrice: annual ? Number(annual) : null,
                  status,
                  isPublic,
                  trialDefaultDays: trialDays ? Number(trialDays) : null,
                }),
              )
            }
            className="text-[9px] font-mono uppercase bg-gold text-navy px-2 py-1 rounded-sm"
          >
            Save Pricing
          </button>
        </div>
      )}
    </div>
  );
}
