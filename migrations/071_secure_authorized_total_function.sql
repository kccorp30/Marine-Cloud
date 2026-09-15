-- =========================================================
-- 071_secure_authorized_total_function.sql — Phase 6 hardening
-- =========================================================
-- BUG REAL: get_work_order_authorized_total() no validaba nada del
-- que llama — cualquier authenticated podía pasar cualquier
-- work_order_id y recibir el monto comercial, cruzando tenant. Se
-- agrega el mismo chequeo que ya usa el resto del sistema: kcc_admin,
-- staff de la organización, o el customer dueño de ese work order.
-- Technician NO recibe totales comerciales. Verificado con 5
-- escenarios reales: staff propio (PASS), customer propio (PASS),
-- customer ajeno (bloqueado), staff de otro tenant (bloqueado),
-- técnico no relacionado (bloqueado).
-- =========================================================

create or replace function get_work_order_authorized_total(p_work_order_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_wo work_orders%rowtype;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;

  if not (
    is_kcc_admin()
    or is_org_staff(v_wo.organization_id)
    or is_customer_of_work_order(p_work_order_id)
  ) then
    raise exception 'not authorized';
  end if;

  return coalesce((
    select sum(ev.total)
    from estimates e
    join estimate_versions ev on ev.id = e.current_version_id
    where e.work_order_id = p_work_order_id and e.status = 'approved'
  ), 0);
end;
$$;

revoke execute on function get_work_order_authorized_total(uuid) from public, anon;
grant execute on function get_work_order_authorized_total(uuid) to authenticated;
