'use client';

import { useState, useTransition } from 'react';
import { selectPlanAction } from '@/lib/subscriptions/actions';
import type { PlanOption } from '@/lib/subscriptions/data';

export function PlanSelector({ organizationId, plans }: { organizationId: string; plans: PlanOption[] }) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function choose(planId: string, cycle: 'weekly' | 'monthly' | 'annual') {
    setError(null);
    startTransition(async () => {
      const res = await selectPlanAction(organizationId, planId, cycle);
      if (res?.error) setError(res.error);
    });
  }

  return (
    <div className="space-y-4">
      {plans.map((plan) => (
        <div key={plan.id} className="border border-white/10 rounded-sm p-3 space-y-2">
          <div className="text-sm font-medium">{plan.name}</div>
          {plan.description && <div className="text-xs text-cool-gray">{plan.description}</div>}
          <div className="flex gap-2 flex-wrap">
            {plan.weeklyPrice !== null && (
              <button type="button" disabled={pending} onClick={() => choose(plan.id, 'weekly')} className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
                {plan.currency} {plan.weeklyPrice}/week
              </button>
            )}
            {plan.monthlyPrice !== null && (
              <button type="button" disabled={pending} onClick={() => choose(plan.id, 'monthly')} className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
                {plan.currency} {plan.monthlyPrice}/month
              </button>
            )}
            {plan.annualPrice !== null && (
              <button type="button" disabled={pending} onClick={() => choose(plan.id, 'annual')} className="text-[10px] font-mono uppercase border border-gold-dim text-gold px-3 py-1.5 rounded-sm">
                {plan.currency} {plan.annualPrice}/year
              </button>
            )}
          </div>
        </div>
      ))}
      {error && <p className="text-xs text-red-400">{error}</p>}
    </div>
  );
}
