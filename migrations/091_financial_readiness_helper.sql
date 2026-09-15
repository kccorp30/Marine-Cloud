-- =========================================================
-- 091_financial_readiness_helper.sql — Marine Cloud Phase 7
-- =========================================================
-- Helper de solo lectura: ¿este work order está listo financieramente
-- para arrancar, según require_deposit_before_start de la
-- organización? No modifica transition_work_order() — esa función es
-- central a las 6 fases anteriores; modificarla directamente
-- arriesgaba romper regresiones extensas ya probadas. Se deja
-- disponible para que staff/UI/Luz (fases futuras) lo consulten antes
-- de decidir avanzar — la salida que el propio brief ofrece
-- explícitamente cuando el gating es demasiado invasivo.
-- Verificado: false con depósito parcial, true una vez satisfecho.
-- =========================================================

create or replace function is_work_order_financially_ready_to_start(p_work_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_wo work_orders%rowtype;
  v_settings organization_payment_settings%rowtype;
  v_summary work_order_financial_summary;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_wo.organization_id) or is_customer_of_work_order(p_work_order_id)) then
    raise exception 'not authorized';
  end if;

  select * into v_settings from organization_payment_settings where organization_id = v_wo.organization_id;
  if coalesce(v_settings.require_deposit_before_start, false) is not true then
    return true;
  end if;

  v_summary := get_work_order_financial_summary(p_work_order_id);
  return v_summary.deposit_satisfied;
end;
$$;

revoke execute on function is_work_order_financially_ready_to_start(uuid) from public, anon;
grant execute on function is_work_order_financially_ready_to_start(uuid) to authenticated;
