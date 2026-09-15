'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function createPlanWithEntitlementsAction(input: {
  code: string;
  name: string;
  description: string | null;
  weeklyPrice: number | null;
  monthlyPrice: number | null;
  annualPrice: number | null;
  trialDefaultDays: number | null;
  isPublic: boolean;
  isCustom: boolean;
  moduleKeys: string[];
}) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('create_subscription_plan_with_entitlements', {
    p_code: input.code,
    p_name: input.name,
    p_description: input.description,
    p_currency: 'USD',
    p_weekly_price: input.weeklyPrice,
    p_monthly_price: input.monthlyPrice,
    p_annual_price: input.annualPrice,
    p_trial_default_days: input.trialDefaultDays,
    p_is_public: input.isPublic,
    p_is_custom: input.isCustom,
    p_module_keys: input.moduleKeys,
  });
  if (error) {
    logger.warn('createPlanWithEntitlementsAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/subscription-plans');
  return {};
}

export async function updatePlanAction(input: {
  planId: string;
  name?: string;
  description?: string;
  weeklyPrice?: number | null;
  monthlyPrice?: number | null;
  annualPrice?: number | null;
  status?: string;
  isPublic?: boolean;
  trialDefaultDays?: number | null;
}) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('update_subscription_plan', {
    p_plan_id: input.planId,
    p_name: input.name ?? null,
    p_description: input.description ?? null,
    p_weekly_price: input.weeklyPrice ?? null,
    p_monthly_price: input.monthlyPrice ?? null,
    p_annual_price: input.annualPrice ?? null,
    p_status: input.status ?? null,
    p_is_public: input.isPublic ?? null,
    p_trial_default_days: input.trialDefaultDays ?? null,
  });
  if (error) {
    logger.warn('updatePlanAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/subscription-plans');
  return {};
}

export async function togglePlanEntitlementAction(planId: string, moduleKey: string, enabled: boolean) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('set_plan_module_entitlement', { p_plan_id: planId, p_module_key: moduleKey, p_enabled: enabled });
  if (error) {
    logger.warn('togglePlanEntitlementAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/subscription-plans');
  return {};
}

export async function archivePlanAction(planId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('update_subscription_plan', { p_plan_id: planId, p_status: 'archived' });
  if (error) {
    logger.warn('archivePlanAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/subscription-plans');
  return {};
}
