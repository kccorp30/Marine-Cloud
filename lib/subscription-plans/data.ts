import 'server-only';
import { createClient } from '@/lib/supabase/server';
import { CORE_MODULE_KEYS } from './shared';
import type { PlanManagementRow } from './shared';

export { CORE_MODULE_KEYS } from './shared';
export type { PlanManagementRow } from './shared';

export async function getAllPlansForManagement(): Promise<PlanManagementRow[]> {
  const supabase = await createClient();
  const { data: plans } = await supabase
    .from('subscription_plans')
    .select('id, code, name, description, status, currency, weekly_price, monthly_price, annual_price, trial_default_days, is_public, is_custom')
    .order('sort_order', { ascending: true });

  if (!plans || plans.length === 0) return [];

  const planIds = plans.map((p) => p.id);
  const [{ data: entitlementRows }, { data: subCounts }] = await Promise.all([
    supabase.from('plan_module_entitlements').select('plan_id, module_key, enabled').in('plan_id', planIds),
    supabase.from('organization_subscriptions').select('plan_id').in('plan_id', planIds).is('superseded_at', null),
  ]);

  const countByPlan = new Map<string, number>();
  for (const s of subCounts ?? []) {
    countByPlan.set(s.plan_id, (countByPlan.get(s.plan_id) ?? 0) + 1);
  }

  return plans.map((p) => {
    const entitlements: Record<string, boolean> = {};
    for (const key of CORE_MODULE_KEYS) entitlements[key] = false;
    for (const row of entitlementRows ?? []) {
      if (row.plan_id === p.id) entitlements[row.module_key] = row.enabled;
    }
    return {
      id: p.id,
      code: p.code,
      name: p.name,
      description: p.description,
      status: p.status,
      currency: p.currency,
      weeklyPrice: p.weekly_price,
      monthlyPrice: p.monthly_price,
      annualPrice: p.annual_price,
      trialDefaultDays: p.trial_default_days,
      isPublic: p.is_public,
      isCustom: p.is_custom,
      activeSubscriptionCount: countByPlan.get(p.id) ?? 0,
      entitlements,
    };
  });
}
