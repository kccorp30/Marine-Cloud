-- =========================================================
-- 223_assign_organization_subscription.sql — Marine Cloud Phase 14
-- =========================================================
-- Commercial Setup real — solo kcc_admin. trial_days>0 -> 'trialing'
-- con fechas server-side reales. complimentary=true -> 'complimentary',
-- nunca $0 fake payment. Sin trial y sin complimentary -> 'active'
-- (NUNCA implica pago real — Phase 14 no cobra; billing_provider/
-- provider_subscription_id quedan NULL siempre). price_snapshot
-- congela el precio real según billing_cycle.
-- Verificado con datos reales: trial de 14 días, price_snapshot
-- correcto, activación sin trial concede acceso sin fabricar pago.
-- =========================================================

create or replace function assign_organization_subscription(
  p_organization_id uuid, p_plan_id uuid, p_billing_cycle text,
  p_trial_days int default null, p_price_override numeric default null,
  p_complimentary boolean default false, p_complimentary_reason text default null, p_custom_terms text default null
)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan subscription_plans%rowtype;
  v_effective_price numeric;
  v_status text;
  v_trial_started timestamptz;
  v_trial_ends timestamptz;
  v_period_started timestamptz;
  v_sub organization_subscriptions%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can assign a commercial subscription';
  end if;
  if not exists (select 1 from organizations where id = p_organization_id) then
    raise exception 'organization not found';
  end if;
  if p_billing_cycle not in ('weekly', 'monthly', 'annual', 'custom') then
    raise exception 'invalid billing cycle: %', p_billing_cycle;
  end if;

  select * into v_plan from subscription_plans where id = p_plan_id;
  if v_plan.id is null then
    raise exception 'plan not found';
  end if;

  if p_complimentary then
    if p_complimentary_reason is null or trim(p_complimentary_reason) = '' then
      raise exception 'a reason is required for complimentary access';
    end if;
    v_status := 'complimentary';
    v_effective_price := null;
  elsif p_trial_days is not null and p_trial_days > 0 then
    v_status := 'trialing';
    v_trial_started := now();
    v_trial_ends := now() + (p_trial_days || ' days')::interval;
  else
    v_status := 'active';
    v_period_started := now();
  end if;

  if not p_complimentary then
    v_effective_price := coalesce(
      p_price_override,
      case p_billing_cycle
        when 'weekly' then v_plan.weekly_price
        when 'monthly' then v_plan.monthly_price
        when 'annual' then v_plan.annual_price
        else null
      end
    );
  end if;

  update organization_subscriptions set superseded_at = now(), updated_at = now()
  where organization_id = p_organization_id and superseded_at is null;

  insert into organization_subscriptions (
    organization_id, plan_id, status, billing_cycle, currency, price_snapshot,
    trial_started_at, trial_ends_at, subscription_started_at, current_period_started_at,
    complimentary, complimentary_reason, custom_terms, price_override, created_by
  )
  values (
    p_organization_id, p_plan_id, v_status, p_billing_cycle, v_plan.currency, v_effective_price,
    v_trial_started, v_trial_ends, v_period_started, v_period_started,
    p_complimentary, p_complimentary_reason, p_custom_terms, p_price_override is not null, auth.uid()
  )
  returning * into v_sub;

  perform log_domain_event(p_organization_id,
    case when v_status = 'trialing' then 'SUBSCRIPTION_TRIAL_STARTED' else 'SUBSCRIPTION_ACTIVATED' end,
    'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_sub.id, 'plan_id', p_plan_id, 'status', v_status));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_sub.id, 'subscription_assigned', null, to_jsonb(v_sub));

  return v_sub;
end;
$$;

revoke execute on function assign_organization_subscription(uuid, uuid, text, int, numeric, boolean, text, text) from public, anon, authenticated;
grant execute on function assign_organization_subscription(uuid, uuid, text, int, numeric, boolean, text, text) to authenticated;
