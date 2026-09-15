-- =========================================================
-- 259_extend_update_plan_trial_days.sql — Phase 14 lifecycle consistency
-- =========================================================
-- update_subscription_plan() no soportaba editar trial_default_days.
-- Verificado con datos reales: name/description/status/is_public/
-- trial_default_days todos editables en una sola llamada.
-- =========================================================

create or replace function update_subscription_plan(
  p_plan_id uuid, p_name text default null, p_description text default null,
  p_weekly_price numeric default null, p_monthly_price numeric default null, p_annual_price numeric default null,
  p_status text default null, p_is_public boolean default null, p_trial_default_days int default null
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
    is_public = coalesce(p_is_public, is_public), trial_default_days = coalesce(p_trial_default_days, trial_default_days),
    updated_at = now()
  where id = p_plan_id
  returning * into v_after;

  perform log_audit_event(null, 'subscription_plan', p_plan_id, 'plan_updated', to_jsonb(v_before), to_jsonb(v_after));

  return v_after;
end;
$$;
