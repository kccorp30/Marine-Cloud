import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface SubscriptionRow {
  id: string;
  planId: string;
  planName: string;
  planCode: string;
  status: string;
  effectiveStatus: string;
  billingCycle: string;
  currency: string;
  priceSnapshot: number | null;
  trialStartedAt: string | null;
  trialEndsAt: string | null;
  subscriptionStartedAt: string | null;
  currentPeriodEndsAt: string | null;
  gracePeriodEndsAt: string | null;
  cancelAtPeriodEnd: boolean;
  cancelledAt: string | null;
  cancellationReason: string | null;
  complimentary: boolean;
  complimentaryReason: string | null;
  customTerms: string | null;
}

export async function getCurrentSubscription(organizationId: string): Promise<SubscriptionRow | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from('organization_subscription_effective')
    .select('*, plan:subscription_plans(id, code, name)')
    .eq('organization_id', organizationId)
    .maybeSingle();

  if (!data) return null;
  const plan = Array.isArray(data.plan) ? data.plan[0] : data.plan;

  return {
    id: data.id,
    planId: data.plan_id,
    planName: plan?.name ?? 'Unknown plan',
    planCode: plan?.code ?? '',
    status: data.status,
    effectiveStatus: data.effective_status,
    billingCycle: data.billing_cycle,
    currency: data.currency,
    priceSnapshot: data.price_snapshot,
    trialStartedAt: data.trial_started_at,
    trialEndsAt: data.trial_ends_at,
    subscriptionStartedAt: data.subscription_started_at,
    currentPeriodEndsAt: data.current_period_ends_at,
    gracePeriodEndsAt: data.grace_period_ends_at,
    cancelAtPeriodEnd: data.cancel_at_period_end,
    cancelledAt: data.cancelled_at,
    cancellationReason: data.cancellation_reason,
    complimentary: data.complimentary,
    complimentaryReason: data.complimentary_reason,
    customTerms: data.custom_terms,
  };
}

export interface PlanOption {
  id: string;
  code: string;
  name: string;
  description: string | null;
  weeklyPrice: number | null;
  monthlyPrice: number | null;
  annualPrice: number | null;
  currency: string;
}

/** Solo planes públicos y activos — nunca custom/complimentary/ocultos, para el selector que ve la company. */
export async function getPublicPlans(): Promise<PlanOption[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from('subscription_plans')
    .select('id, code, name, description, weekly_price, monthly_price, annual_price, currency')
    .eq('is_public', true)
    .eq('status', 'active')
    .order('sort_order', { ascending: true });

  return (data ?? []).map((p) => ({
    id: p.id,
    code: p.code,
    name: p.name,
    description: p.description,
    weeklyPrice: p.weekly_price,
    monthlyPrice: p.monthly_price,
    annualPrice: p.annual_price,
    currency: p.currency,
  }));
}

/** Todos los planes (incluidos custom/inactivos) — solo para kcc_admin, RLS ya lo restringe igual. */
export async function getAllPlans(): Promise<PlanOption[]> {
  const supabase = await createClient();
  const { data } = await supabase.from('subscription_plans').select('id, code, name, description, weekly_price, monthly_price, annual_price, currency').order('sort_order', { ascending: true });

  return (data ?? []).map((p) => ({
    id: p.id,
    code: p.code,
    name: p.name,
    description: p.description,
    weeklyPrice: p.weekly_price,
    monthlyPrice: p.monthly_price,
    annualPrice: p.annual_price,
    currency: p.currency,
  }));
}
