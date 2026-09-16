-- =========================================================
-- 233_plan_price_validation_constraints.sql — Phase 14 final integrity
-- =========================================================
-- Constraints reales a nivel de base de datos. select_organization_plan()
-- rechaza planes custom aunque se marquen public por accidente, y
-- rechaza ciclos sin precio configurado. assign_organization_subscription()
-- valida override/trial_days negativos y calcula current_period_ends_at
-- real desde el arranque.
-- Verificado con datos reales: precio negativo rechazado por
-- constraint, plan custom-marcado-public rechazado de self-service,
-- ciclo sin precio configurado rechazado.
-- =========================================================

alter table subscription_plans add constraint chk_plan_prices_nonnegative
  check (
    (weekly_price is null or weekly_price >= 0) and
    (monthly_price is null or monthly_price >= 0) and
    (annual_price is null or annual_price >= 0) and
    (trial_default_days is null or trial_default_days >= 0)
  );

alter table organization_subscriptions add constraint chk_price_snapshot_nonnegative
  check (price_snapshot is null or price_snapshot >= 0);

alter table organization_subscriptions add constraint chk_trial_dates_order
  check (trial_started_at is null or trial_ends_at is null or trial_ends_at > trial_started_at);

alter table organization_subscriptions add constraint chk_period_dates_order
  check (current_period_started_at is null or current_period_ends_at is null or current_period_ends_at > current_period_started_at);

create or replace function select_organization_plan(p_organization_id uuid, p_plan_id uuid, p_billing_cycle text)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_role text;
  v_plan subscription_plans%rowtype;
  v_current organization_subscriptions%rowtype;
  v_effective_price numeric;
  v_current_effective text;
  v_new_sub organization_subscriptions%rowtype;
begin
  select role into v_actor_role from organization_memberships
  where profile_id = auth.uid() and organization_id = p_organization_id and status = 'active';
  if v_actor_role not in ('company_owner', 'company_admin') then
    raise exception 'only the company owner/admin can select a plan for their own organization';
  end if;
  if p_billing_cycle not in ('weekly', 'monthly', 'annual') then
    raise exception 'invalid billing cycle for self-service plan selection: %', p_billing_cycle;
  end if;

  select * into v_plan from subscription_plans where id = p_plan_id;
  if v_plan.id is null or v_plan.is_public is not true or v_plan.status != 'active' or v_plan.is_custom = true then
    raise exception 'this plan is not available for self-service selection';
  end if;

  v_effective_price := case p_billing_cycle
    when 'weekly' then v_plan.weekly_price
    when 'monthly' then v_plan.monthly_price
    when 'annual' then v_plan.annual_price
  end;
  if v_effective_price is null then
    raise exception 'this plan does not have a configured price for the % billing cycle', p_billing_cycle;
  end if;

  select * into v_current from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_current.id is not null then
    v_current_effective := subscription_effective_status(v_current.status, v_current.trial_ends_at, v_current.grace_period_ends_at, v_current.complimentary, v_current.cancel_at_period_end, v_current.current_period_ends_at);
    if v_current_effective not in ('trial_expired', 'cancelled') then
      raise exception 'a plan can only be self-selected when there is no active subscription or the trial has expired/subscription was cancelled (current effective status: %)', v_current_effective;
    end if;
    update organization_subscriptions set superseded_at = now(), updated_at = now() where id = v_current.id;
  end if;

  insert into organization_subscriptions (organization_id, plan_id, status, billing_cycle, currency, price_snapshot, subscription_started_at, current_period_started_at, created_by)
  values (p_organization_id, p_plan_id, 'active', p_billing_cycle, v_plan.currency, v_effective_price, now(), now(), auth.uid())
  returning * into v_new_sub;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_ACTIVATED', 'organization', p_organization_id,
    jsonb_build_object('subscription_id', v_new_sub.id, 'plan_id', p_plan_id, 'self_service', true));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_new_sub.id, 'plan_self_selected', null, to_jsonb(v_new_sub));

  return v_new_sub;
end;
$$;

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
  if p_price_override is not null and p_price_override < 0 then
    raise exception 'price override cannot be negative';
  end if;
  if p_trial_days is not null and p_trial_days < 0 then
    raise exception 'trial days cannot be negative';
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
    current_period_ends_at,
    complimentary, complimentary_reason, custom_terms, price_override, created_by
  )
  values (
    p_organization_id, p_plan_id, v_status, p_billing_cycle, v_plan.currency, v_effective_price,
    v_trial_started, v_trial_ends, v_period_started, v_period_started,
    case when v_period_started is not null then calculate_period_end(v_period_started, p_billing_cycle) else null end,
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
