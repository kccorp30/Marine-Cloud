'use client';

import { useState, useTransition } from 'react';
import { createPlanWithEntitlementsAction } from '@/lib/subscription-plans/actions';
import { CORE_MODULE_KEYS } from '@/lib/subscription-plans/shared';

export function PlanCreateForm() {
  const [open, setOpen] = useState(false);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [modules, setModules] = useState<string[]>(['work_orders']);

  function toggleModule(key: string) {
    setModules((prev) => (prev.includes(key) ? prev.filter((m) => m !== key) : [...prev, key]));
  }

  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
        + New Plan
      </button>
    );
  }

  return (
    <div className="bg-white/[0.03] border border-white/10 rounded-sm p-5 space-y-3">
      <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-gold">New Subscription Plan</div>
      {error && <p className="text-xs text-red-400">{error}</p>}
      <form
        action={(formData) => {
          setError(null);
          startTransition(async () => {
            const res = await createPlanWithEntitlementsAction({
              code: formData.get('code') as string,
              name: formData.get('name') as string,
              description: (formData.get('description') as string) || null,
              weeklyPrice: formData.get('weeklyPrice') ? Number(formData.get('weeklyPrice')) : null,
              monthlyPrice: formData.get('monthlyPrice') ? Number(formData.get('monthlyPrice')) : null,
              annualPrice: formData.get('annualPrice') ? Number(formData.get('annualPrice')) : null,
              trialDefaultDays: formData.get('trialDefaultDays') ? Number(formData.get('trialDefaultDays')) : null,
              isPublic: formData.get('isPublic') === 'on',
              isCustom: formData.get('isCustom') === 'on',
              moduleKeys: modules,
            });
            if (res?.error) {
              setError(res.error);
              return;
            }
            setOpen(false);
          });
        }}
        className="space-y-3"
      >
        <div className="grid grid-cols-2 gap-3">
          <input name="code" required placeholder="Plan code (e.g. GROWTH)" className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <input name="name" required placeholder="Display name" className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
        </div>
        <input name="description" placeholder="Description (optional)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
        <div className="grid grid-cols-3 gap-3">
          <input name="weeklyPrice" type="number" step="0.01" placeholder="Weekly price" className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <input name="monthlyPrice" type="number" step="0.01" placeholder="Monthly price" className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
          <input name="annualPrice" type="number" step="0.01" placeholder="Annual price" className="text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
        </div>
        <input name="trialDefaultDays" type="number" placeholder="Default trial days (optional)" className="w-full text-sm bg-white/[0.04] border border-white/10 rounded-sm px-3 py-2" />
        <label className="flex items-center gap-2 text-xs text-cool-gray">
          <input type="checkbox" name="isPublic" defaultChecked />
          Public — company owners/admins can self-select this plan
        </label>
        <label className="flex items-center gap-2 text-xs text-cool-gray">
          <input type="checkbox" name="isCustom" />
          Custom — negotiated terms only, never shown in self-service selection
        </label>

        <div className="font-mono text-[9px] uppercase text-gold pt-2">Included Modules</div>
        <p className="text-[10px] text-cool-gray">
          A module with no explicit entitlement is denied by default. Select everything this plan should include — nothing is assumed.
        </p>
        <div className="grid grid-cols-2 gap-2">
          {CORE_MODULE_KEYS.map((key) => (
            <label key={key} className="flex items-center gap-2 text-xs text-cool-gray">
              <input type="checkbox" checked={modules.includes(key)} onChange={() => toggleModule(key)} />
              {key.replace('_', ' ')}
            </label>
          ))}
        </div>

        <div className="flex gap-2 pt-2">
          <button type="submit" disabled={pending} className="text-[10px] font-mono uppercase bg-gold text-navy px-3 py-1.5 rounded-sm">
            {pending ? 'Creating…' : 'Create Plan'}
          </button>
          <button type="button" onClick={() => setOpen(false)} className="text-[10px] font-mono uppercase text-cool-gray px-3 py-1.5">
            Cancel
          </button>
        </div>
      </form>
    </div>
  );
}
