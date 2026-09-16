import 'server-only';
import { createClient } from '@/lib/supabase/server';

export interface CommercialDashboardData {
  counts: Record<string, number>;
  trialsExpiringSoon: Array<{ organizationId: string; organizationName: string; trialEndsAt: string; daysLeft: number }>;
  planDistribution: Array<{ planName: string; active: number; trialing: number; complimentary: number; inactiveOrCancelled: number }>;
  // Normalizado a un equivalente SEMANAL — fórmula documentada y
  // determinística: monthly/4.345 (semanas promedio/mes),
  // annual/52.14 (semanas/año). Nunca se suman precios crudos de
  // ciclos distintos. Excluye complimentary/cancelled/archived/
  // trial (pipeline, no contratado activo) y organizaciones demo.
  contractedRecurringWeeklyEquivalent: number;
  currency: string;
}

const WEEKS_PER_MONTH = 4.345;
const WEEKS_PER_YEAR = 52.14;

export async function getCommercialDashboardData(): Promise<CommercialDashboardData> {
  const supabase = await createClient();

  const { data: subs } = await supabase
    .from('organization_subscription_effective')
    .select('effective_status, billing_cycle, price_snapshot, currency, complimentary, plan:subscription_plans(name), organization:organizations(id, name, status)');

  const { data: archivedOrgs } = await supabase.from('organizations').select('id').eq('status', 'archived');

  const counts: Record<string, number> = {
    trialing: 0,
    active: 0,
    trial_expired: 0,
    grace_period: 0,
    past_due: 0,
    cancelled: 0,
    complimentary: 0,
  };

  const planCounts = new Map<string, { active: number; trialing: number; complimentary: number; inactiveOrCancelled: number }>();
  let contractedRecurringWeekly = 0;
  let currency = 'USD';
  const expiringSoon: CommercialDashboardData['trialsExpiringSoon'] = [];

  for (const s of subs ?? []) {
    const org = Array.isArray(s.organization) ? s.organization[0] : s.organization;
    const plan = Array.isArray(s.plan) ? s.plan[0] : s.plan;
    if (!org) continue;

    if (counts[s.effective_status] !== undefined) counts[s.effective_status] += 1;

    if (plan?.name) {
      const bucket = planCounts.get(plan.name) ?? { active: 0, trialing: 0, complimentary: 0, inactiveOrCancelled: 0 };
      if (s.complimentary) bucket.complimentary += 1;
      else if (s.effective_status === 'active' || s.effective_status === 'grace_period') bucket.active += 1;
      else if (s.effective_status === 'trialing') bucket.trialing += 1;
      else bucket.inactiveOrCancelled += 1;
      planCounts.set(plan.name, bucket);
    }

    // Contratado activo real: nunca complimentary/cancelled/archived/trial/trial_expired/past_due —
    // solo 'active' y 'grace_period' representan compromiso comercial en vigor.
    if ((s.effective_status === 'active' || s.effective_status === 'grace_period') && !s.complimentary && s.price_snapshot !== null && org.status !== 'archived') {
      currency = s.currency ?? currency;
      if (s.billing_cycle === 'weekly') contractedRecurringWeekly += s.price_snapshot;
      else if (s.billing_cycle === 'monthly') contractedRecurringWeekly += s.price_snapshot / WEEKS_PER_MONTH;
      else if (s.billing_cycle === 'annual') contractedRecurringWeekly += s.price_snapshot / WEEKS_PER_YEAR;
      // 'custom' se excluye del total normalizado — no tiene un
      // ciclo determinístico real, se muestra aparte si hace falta.
    }
  }

  counts.archived = archivedOrgs?.length ?? 0;

  // Trials venciendo en los próximos 7 días — deep-link real a la
  // sección Commercial de cada compañía.
  const { data: expiringTrials } = await supabase
    .from('organization_subscription_effective')
    .select('trial_ends_at, organization:organizations(id, name)')
    .eq('effective_status', 'trialing')
    .not('trial_ends_at', 'is', null)
    .lte('trial_ends_at', new Date(Date.now() + 7 * 86400000).toISOString())
    .order('trial_ends_at', { ascending: true });

  for (const t of expiringTrials ?? []) {
    const org = Array.isArray(t.organization) ? t.organization[0] : t.organization;
    if (!org || !t.trial_ends_at) continue;
    const daysLeft = Math.max(0, Math.ceil((new Date(t.trial_ends_at).getTime() - Date.now()) / 86400000));
    expiringSoon.push({ organizationId: org.id, organizationName: org.name, trialEndsAt: t.trial_ends_at, daysLeft });
  }

  return {
    counts,
    trialsExpiringSoon: expiringSoon,
    planDistribution: Array.from(planCounts.entries()).map(([planName, counts]) => ({ planName, ...counts })),
    contractedRecurringWeeklyEquivalent: Math.round(contractedRecurringWeekly * 100) / 100,
    currency,
  };
}
