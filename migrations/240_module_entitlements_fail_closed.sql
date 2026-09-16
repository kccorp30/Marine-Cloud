-- =========================================================
-- 240_module_entitlements_fail_closed.sql — Phase 14 true final closure
-- =========================================================
-- BUG REAL DE SEGURIDAD: organization_has_module_access() usaba
-- coalesce(v_entitlement, true) — sin fila, el módulo quedaba
-- PERMITIDO. Corregido a fail-closed: enabled=true->permitido,
-- enabled=false O sin fila->denegado. kcc_admin conserva bypass.
-- customers/vessels quedan como datos base del producto, nunca
-- gateados por plan (decisión explícita).
-- Verificado con datos reales: true permite, false bloquea, sin fila
-- bloquea, kcc_admin bypass, cambio de plan recalcula entitlement.
-- =========================================================

create or replace function organization_has_module_access(p_organization_id uuid, p_module_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_plan_id uuid;
  v_entitlement boolean;
begin
  if is_kcc_admin() then
    return true;
  end if;
  if not organization_has_active_access(p_organization_id) then
    return false;
  end if;
  select plan_id into v_plan_id from organization_subscriptions where organization_id = p_organization_id and superseded_at is null;
  if v_plan_id is null then
    return false;
  end if;
  select enabled into v_entitlement from plan_module_entitlements where plan_id = v_plan_id and module_key = p_module_key;
  return coalesce(v_entitlement, false);
end;
$$;

insert into plan_module_entitlements (plan_id, module_key, enabled)
select sp.id, m.module_key, true
from subscription_plans sp
cross join (values ('work_orders'), ('service_requests'), ('estimates'), ('tracking'), ('warranty'), ('communications')) as m(module_key)
where sp.status = 'active'
on conflict (plan_id, module_key) do nothing;
