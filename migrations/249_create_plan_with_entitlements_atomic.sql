-- =========================================================
-- 249_create_plan_with_entitlements_atomic.sql — Phase 14 absolute final closure
-- =========================================================
-- create_subscription_plan_with_entitlements(): crea plan +
-- entitlements iniciales en una sola transacción — reusa
-- create_subscription_plan() tal cual existe. set_plan_module_
-- entitlement(): RPC trusted para alternar un módulo, auditado.
-- Verificado con datos reales: plan nuevo con módulos seleccionados
-- funciona de inmediato, módulo omitido queda denegado, el toggle
-- afecta a organizaciones ya en el plan de forma inmediata.
-- =========================================================

create or replace function create_subscription_plan_with_entitlements(
  p_code text, p_name text, p_description text, p_currency text,
  p_weekly_price numeric, p_monthly_price numeric, p_annual_price numeric,
  p_trial_default_days int, p_is_public boolean, p_is_custom boolean,
  p_module_keys text[]
)
returns subscription_plans
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan subscription_plans%rowtype;
  v_module text;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can create subscription plans';
  end if;

  v_plan := create_subscription_plan(p_code, p_name, p_description, p_currency, p_weekly_price, p_monthly_price, p_annual_price, p_trial_default_days, p_is_public, p_is_custom);

  if p_module_keys is not null then
    foreach v_module in array p_module_keys loop
      insert into plan_module_entitlements (plan_id, module_key, enabled) values (v_plan.id, v_module, true)
      on conflict (plan_id, module_key) do update set enabled = true;
    end loop;
  end if;

  perform log_audit_event(null, 'subscription_plan', v_plan.id, 'plan_entitlements_configured_at_creation', null, jsonb_build_object('modules', p_module_keys));

  return v_plan;
end;
$$;

revoke execute on function create_subscription_plan_with_entitlements(text, text, text, text, numeric, numeric, numeric, int, boolean, boolean, text[]) from public, anon, authenticated;
grant execute on function create_subscription_plan_with_entitlements(text, text, text, text, numeric, numeric, numeric, int, boolean, boolean, text[]) to authenticated;

create or replace function set_plan_module_entitlement(p_plan_id uuid, p_module_key text, p_enabled boolean)
returns plan_module_entitlements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entitlement plan_module_entitlements%rowtype;
  v_before boolean;
begin
  if not is_kcc_admin() then
    raise exception 'only KCC platform staff can manage plan entitlements';
  end if;
  if not exists (select 1 from subscription_plans where id = p_plan_id) then
    raise exception 'plan not found';
  end if;

  select enabled into v_before from plan_module_entitlements where plan_id = p_plan_id and module_key = p_module_key;

  insert into plan_module_entitlements (plan_id, module_key, enabled) values (p_plan_id, p_module_key, p_enabled)
  on conflict (plan_id, module_key) do update set enabled = p_enabled
  returning * into v_entitlement;

  perform log_audit_event(null, 'plan_module_entitlement', v_entitlement.id, 'entitlement_toggled',
    jsonb_build_object('enabled', v_before), jsonb_build_object('enabled', p_enabled, 'module_key', p_module_key, 'plan_id', p_plan_id));

  return v_entitlement;
end;
$$;

revoke execute on function set_plan_module_entitlement(uuid, text, boolean) from public, anon, authenticated;
grant execute on function set_plan_module_entitlement(uuid, text, boolean) to authenticated;
