-- =========================================================
-- 220_subscription_effective_status.sql — Marine Cloud Phase 14
-- =========================================================
-- Mismo patrón que warranty_effective_status() — nunca depende de un
-- cron. STABLE (depende de now()), nunca IMMUTABLE.
-- =========================================================

create or replace function subscription_effective_status(
  p_status text,
  p_trial_ends_at timestamptz,
  p_grace_period_ends_at timestamptz,
  p_complimentary boolean
)
returns text
language sql
stable
as $$
  select case
    when p_complimentary then 'complimentary'
    when p_status = 'cancelled' then 'cancelled'
    when p_status = 'trialing' and p_trial_ends_at is not null and p_trial_ends_at < now() then 'trial_expired'
    when p_status = 'grace_period' and p_grace_period_ends_at is not null and p_grace_period_ends_at < now() then 'past_due'
    else p_status
  end;
$$;

create or replace view organization_subscription_effective as
select
  os.*,
  subscription_effective_status(os.status, os.trial_ends_at, os.grace_period_ends_at, os.complimentary) as effective_status
from organization_subscriptions os
where os.superseded_at is null;
