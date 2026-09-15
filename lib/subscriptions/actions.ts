'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

export async function createPlanAction(input: {
  code: string;
  name: string;
  description: string | null;
  weeklyPrice: number | null;
  monthlyPrice: number | null;
  annualPrice: number | null;
  trialDefaultDays: number | null;
  isPublic: boolean;
  isCustom: boolean;
}) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('create_subscription_plan', {
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
  });
  if (error) {
    logger.warn('createPlanAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/subscription-plans');
  return {};
}

export async function assignSubscriptionAction(input: {
  organizationId: string;
  planId: string;
  billingCycle: string;
  trialDays: number | null;
  priceOverride: number | null;
  complimentary: boolean;
  complimentaryReason: string | null;
  customTerms: string | null;
}) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('assign_organization_subscription', {
    p_organization_id: input.organizationId,
    p_plan_id: input.planId,
    p_billing_cycle: input.billingCycle,
    p_trial_days: input.trialDays,
    p_price_override: input.priceOverride,
    p_complimentary: input.complimentary,
    p_complimentary_reason: input.complimentaryReason,
    p_custom_terms: input.customTerms,
  });
  if (error) {
    logger.warn('assignSubscriptionAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${input.organizationId}`);
  return {};
}

export async function extendTrialAction(organizationId: string, newTrialEndsAt: string, reason: string | null) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('extend_organization_trial', { p_organization_id: organizationId, p_new_trial_ends_at: newTrialEndsAt, p_reason: reason });
  if (error) {
    logger.warn('extendTrialAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  revalidatePath('/billing');
  return {};
}

export async function cancelSubscriptionAction(organizationId: string, immediately: boolean, reason: string | null) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('cancel_subscription', { p_organization_id: organizationId, p_immediately: immediately, p_reason: reason });
  if (error) {
    logger.warn('cancelSubscriptionAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function grantComplimentaryAction(organizationId: string, reason: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('grant_complimentary_access', { p_organization_id: organizationId, p_reason: reason });
  if (error) {
    logger.warn('grantComplimentaryAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function removeComplimentaryAction(organizationId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('remove_complimentary_access', { p_organization_id: organizationId });
  if (error) {
    logger.warn('removeComplimentaryAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function archiveOrganizationAction(organizationId: string, reason: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('archive_organization', { p_organization_id: organizationId, p_reason: reason });
  if (error) {
    logger.warn('archiveOrganizationAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  revalidatePath('/companies');
  return {};
}

export async function reactivateOrganizationAction(organizationId: string, reason: string | null) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('reactivate_organization', { p_organization_id: organizationId, p_reason: reason });
  if (error) {
    logger.warn('reactivateOrganizationAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  revalidatePath('/companies');
  return {};
}

export async function selectPlanAction(organizationId: string, planId: string, billingCycle: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('select_organization_plan', { p_organization_id: organizationId, p_plan_id: planId, p_billing_cycle: billingCycle });
  if (error) {
    logger.warn('selectPlanAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath('/billing');
  return {};
}

export async function grantGracePeriodAction(organizationId: string, graceEndsAt: string, reason: string | null) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('grant_subscription_grace_period', { p_organization_id: organizationId, p_grace_ends_at: graceEndsAt, p_reason: reason });
  if (error) {
    logger.warn('grantGracePeriodAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function endGracePeriodAction(organizationId: string, resultingStatus: string, reason: string | null) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('end_subscription_grace_period', { p_organization_id: organizationId, p_resulting_status: resultingStatus, p_reason: reason });
  if (error) {
    logger.warn('endGracePeriodAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  return {};
}

export async function changeSubscriptionPlanAction(organizationId: string, newPlanId: string, billingCycle: string, priceOverride: number | null) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('change_subscription_plan', { p_organization_id: organizationId, p_new_plan_id: newPlanId, p_billing_cycle: billingCycle, p_price_override: priceOverride });
  if (error) {
    logger.warn('changeSubscriptionPlanAction failed', { message: error.message });
    return { error: error.message };
  }
  revalidatePath(`/companies/${organizationId}`);
  revalidatePath('/billing');
  return {};
}
