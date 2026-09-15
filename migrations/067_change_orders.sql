-- =========================================================
-- 067_change_orders.sql — Marine Cloud Phase 6
-- =========================================================
-- Un change order ES una estimate (type='change_order') — reusa
-- exactamente el mismo motor de versiones/líneas/envío/aprobación/
-- rechazo/revisión ya construido. Solo la CREACIÓN es distinta:
-- numeración CO-, y parent_estimate_id apunta a la estimate original
-- aprobada del mismo work order (nunca se reescribe esa original).
--
-- Verificado con el ejemplo del brief: original $2500 aprobado,
-- CO-001 +$450, CO-002 +$200 -> total autorizado agregado $3150.00
-- exacto, y la estimate original nunca cambió su total ($2500.00
-- intacto). Técnico y customer ajeno bloqueados de crear un CO.
-- =========================================================

create or replace function create_change_order(
  p_work_order_id uuid,
  p_title text default null,
  p_customer_message text default null,
  p_valid_until date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders%rowtype;
  v_parent_estimate_id uuid;
  v_estimate_id uuid;
  v_version_id uuid;
  v_currency text;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;
  if not (is_kcc_admin() or is_org_staff(v_wo.organization_id)) then
    raise exception 'not authorized to create change orders';
  end if;

  select id into v_parent_estimate_id from estimates
  where work_order_id = p_work_order_id and type = 'estimate' and status = 'approved'
  order by created_at desc limit 1;

  select currency into v_currency from organization_settings where organization_id = v_wo.organization_id;
  v_currency := coalesce(v_currency, 'USD');

  insert into estimates (organization_id, customer_id, vessel_id, work_order_id, estimate_number, type, parent_estimate_id, status, currency, created_by)
  values (v_wo.organization_id, v_wo.customer_id, v_wo.vessel_id, p_work_order_id,
    generate_estimate_number(v_wo.organization_id, 'change_order'), 'change_order', v_parent_estimate_id, 'draft', v_currency, auth.uid())
  returning id into v_estimate_id;

  insert into estimate_versions (organization_id, estimate_id, version_number, status, title, customer_message, currency, valid_until, created_by)
  values (v_wo.organization_id, v_estimate_id, 1, 'draft', p_title, p_customer_message, v_currency, p_valid_until, auth.uid())
  returning id into v_version_id;

  update estimates set current_version_id = v_version_id where id = v_estimate_id;

  perform log_domain_event(v_wo.organization_id, 'CHANGE_ORDER_CREATED', 'estimate', v_estimate_id,
    jsonb_build_object('work_order_id', p_work_order_id, 'parent_estimate_id', v_parent_estimate_id));

  return v_estimate_id;
end;
$$;

revoke execute on function create_change_order(uuid, text, text, date) from public, anon;
grant execute on function create_change_order(uuid, text, text, date) to authenticated;

create or replace function get_work_order_authorized_total(p_work_order_id uuid)
returns numeric
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(sum(ev.total), 0)
  from estimates e
  join estimate_versions ev on ev.id = e.current_version_id
  where e.work_order_id = p_work_order_id and e.status = 'approved';
$$;

revoke execute on function get_work_order_authorized_total(uuid) from public, anon;
grant execute on function get_work_order_authorized_total(uuid) to authenticated;
