-- =========================================================
-- 226_change_subscription_plan.sql — Marine Cloud Phase 14
-- =========================================================
-- Regla determinística elegida: cambio de plan INMEDIATO, nunca
-- prorrateo (pertenece a Phase 15). Reusa el patrón de supersede.
-- =========================================================

create or replace function change_subscription_plan(
  p_organization_id uuid, p_new_plan_id uuid, p_billing_cycle text, p_price_override numeric default null
)
returns organization_subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current organization_subscriptions%rowtype;
  v_new_plan subscription_plans%rowtype;
  v_effective_price numeric;
  v_new_sub organization_subscriptions%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can change a subscription plan';
  end if;
  if p_billing_cycle not in ('weekly', 'monthly', 'annual', 'custom') then
    raise exception 'invalid billing cycle: %', p_billing_cycle;
  end if;

  select * into v_current from organization_subscriptions where organization_id = p_organization_id and superseded_at is null for update;
  if v_current.id is null then
    raise exception 'no current subscription for this organization';
  end if;

  select * into v_new_plan from subscription_plans where id = p_new_plan_id;
  if v_new_plan.id is null then
    raise exception 'plan not found';
  end if;

  v_effective_price := coalesce(
    p_price_override,
    case p_billing_cycle
      when 'weekly' then v_new_plan.weekly_price
      when 'monthly' then v_new_plan.monthly_price
      when 'annual' then v_new_plan.annual_price
      else null
    end
  );

  update organization_subscriptions set superseded_at = now(), updated_at = now() where id = v_current.id;

  insert into organization_subscriptions (
    organization_id, plan_id, status, billing_cycle, currency, price_snapshot,
    subscription_started_at, current_period_started_at,
    complimentary, complimentary_reason, price_override, created_by
  )
  values (
    p_organization_id, p_new_plan_id,
    case when v_current.complimentary then 'complimentary' else 'active' end,
    p_billing_cycle, v_new_plan.currency, v_effective_price, now(), now(),
    v_current.complimentary, v_current.complimentary_reason, p_price_override is not null, auth.uid()
  )
  returning * into v_new_sub;

  perform log_domain_event(p_organization_id, 'SUBSCRIPTION_PLAN_CHANGED', 'organization', p_organization_id,
    jsonb_build_object('previous_subscription_id', v_current.id, 'previous_plan_id', v_current.plan_id, 'new_subscription_id', v_new_sub.id, 'new_plan_id', p_new_plan_id));
  perform log_audit_event(p_organization_id, 'organization_subscription', v_new_sub.id, 'plan_changed', to_jsonb(v_current), to_jsonb(v_new_sub));

  return v_new_sub;
end;
$$;

revoke execute on function change_subscription_plan(uuid, uuid, text, numeric) from public, anon, authenticated;
grant execute on function change_subscription_plan(uuid, uuid, text, numeric) to authenticated;
