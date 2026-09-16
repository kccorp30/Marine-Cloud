-- =========================================================
-- 222_subscription_plan_rpcs.sql — Marine Cloud Phase 14
-- =========================================================
-- create_subscription_plan/update_subscription_plan: solo kcc_admin.
-- Editar precios NUNCA muta suscripciones ya existentes.
-- Verificado con datos reales: plan creado, edición de precio no
-- muta el snapshot congelado.
-- =========================================================

create or replace function create_subscription_plan(
  p_code text, p_name text, p_description text, p_currency text,
  p_weekly_price numeric, p_monthly_price numeric, p_annual_price numeric,
  p_trial_default_days int, p_is_public boolean, p_is_custom boolean
)
returns subscription_plans
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan subscription_plans%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can create subscription plans';
  end if;

  insert into subscription_plans (code, name, description, currency, weekly_price, monthly_price, annual_price, trial_default_days, is_public, is_custom, created_by)
  values (p_code, p_name, p_description, coalesce(p_currency, 'USD'), p_weekly_price, p_monthly_price, p_annual_price, p_trial_default_days, coalesce(p_is_public, true), coalesce(p_is_custom, false), auth.uid())
  returning * into v_plan;

  perform log_audit_event(null, 'subscription_plan', v_plan.id, 'plan_created', null, to_jsonb(v_plan));

  return v_plan;
end;
$$;

revoke execute on function create_subscription_plan(text, text, text, text, numeric, numeric, numeric, int, boolean, boolean) from public, anon, authenticated;
grant execute on function create_subscription_plan(text, text, text, text, numeric, numeric, numeric, int, boolean, boolean) to authenticated;

create or replace function update_subscription_plan(
  p_plan_id uuid, p_name text default null, p_description text default null,
  p_weekly_price numeric default null, p_monthly_price numeric default null, p_annual_price numeric default null,
  p_status text default null, p_is_public boolean default null
)
returns subscription_plans
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before subscription_plans%rowtype;
  v_after subscription_plans%rowtype;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can edit subscription plans';
  end if;

  select * into v_before from subscription_plans where id = p_plan_id;
  if v_before.id is null then
    raise exception 'plan not found';
  end if;
  if p_status is not null and p_status not in ('active', 'inactive', 'archived') then
    raise exception 'invalid status: %', p_status;
  end if;

  update subscription_plans set
    name = coalesce(p_name, name), description = coalesce(p_description, description),
    weekly_price = coalesce(p_weekly_price, weekly_price), monthly_price = coalesce(p_monthly_price, monthly_price),
    annual_price = coalesce(p_annual_price, annual_price), status = coalesce(p_status, status),
    is_public = coalesce(p_is_public, is_public), updated_at = now()
  where id = p_plan_id
  returning * into v_after;

  perform log_audit_event(null, 'subscription_plan', p_plan_id, 'plan_updated', to_jsonb(v_before), to_jsonb(v_after));

  return v_after;
end;
$$;

revoke execute on function update_subscription_plan(uuid, text, text, numeric, numeric, numeric, text, boolean) from public, anon, authenticated;
grant execute on function update_subscription_plan(uuid, text, text, numeric, numeric, numeric, text, boolean) to authenticated;
