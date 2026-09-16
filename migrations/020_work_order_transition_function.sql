-- =========================================================
-- 020_work_order_transition_function.sql — Marine Cloud Phase 1
-- =========================================================

-- ---------------------------------------------------------
-- Catálogo de reglas de transición — MVP: fijo, no personalizable
-- por compañía todavía (decisión ya tomada, evita sobre-ingeniería
-- de un motor BPMN genérico antes de tiempo).
-- ---------------------------------------------------------
insert into work_order_transition_rules (from_status, to_status, allowed_roles) values
  ('request_received','triage', array['company_admin','manager','kcc_admin']),
  ('request_received','cancelled', array['company_admin','manager','kcc_admin','company_owner']),
  ('triage','estimate', array['company_admin','manager','kcc_admin']),
  ('triage','cancelled', array['company_admin','manager','kcc_admin']),
  ('estimate','awaiting_approval', array['company_admin','manager','kcc_admin']),
  ('awaiting_approval','scheduled', array['company_admin','manager','kcc_admin','customer']),
  ('awaiting_approval','cancelled', array['company_admin','manager','kcc_admin','customer']),
  ('scheduled','technician_assigned', array['company_admin','manager','kcc_admin']),
  ('scheduled','cancelled', array['company_admin','manager','kcc_admin','customer']),
  ('technician_assigned','en_route', array['technician','company_admin','manager','kcc_admin']),
  ('technician_assigned','cancelled', array['company_admin','manager','kcc_admin']),
  ('en_route','checked_in', array['technician','company_admin','manager','kcc_admin']),
  ('checked_in','diagnosis', array['technician','company_admin','manager','kcc_admin']),
  ('diagnosis','work_in_progress', array['technician','company_admin','manager','kcc_admin']),
  ('diagnosis','waiting_parts', array['technician','company_admin','manager','kcc_admin']),
  ('work_in_progress','waiting_parts', array['technician','company_admin','manager','kcc_admin']),
  ('waiting_parts','work_in_progress', array['technician','company_admin','manager','kcc_admin']),
  ('work_in_progress','waiting_customer_approval', array['technician','company_admin','manager','kcc_admin']),
  ('waiting_customer_approval','work_in_progress', array['customer','company_admin','manager','kcc_admin']),
  ('work_in_progress','quality_control', array['technician','company_admin','manager','kcc_admin']),
  ('quality_control','work_in_progress', array['company_admin','manager','kcc_admin']),
  ('quality_control','invoice', array['company_admin','manager','kcc_admin']),
  ('invoice','payment', array['company_admin','manager','kcc_admin','customer']),
  ('payment','completed', array['company_admin','manager','kcc_admin']),
  ('completed','warranty', array['company_admin','manager','kcc_admin']);

-- ---------------------------------------------------------
-- transition_work_order() — ÚNICO camino autorizado para cambiar
-- current_status.
-- ---------------------------------------------------------
create or replace function transition_work_order(
  p_work_order_id uuid,
  p_to_status text,
  p_reason text default null
)
returns work_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wo work_orders;
  v_org_id uuid;
  v_from_status text;
  v_actor_role text;
  v_rule_exists boolean;
begin
  select * into v_wo from work_orders where id = p_work_order_id;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;

  v_org_id := v_wo.organization_id;
  v_from_status := v_wo.current_status;

  if not (is_org_member(v_org_id) or is_kcc_admin()) then
    raise exception 'not authorized for this organization';
  end if;

  select role into v_actor_role from organization_memberships
  where profile_id = auth.uid() and organization_id = v_org_id and status = 'active'
  limit 1;

  if is_kcc_admin() and v_actor_role is null then
    v_actor_role := 'kcc_admin';
  end if;

  select exists (
    select 1 from work_order_transition_rules
    where from_status = v_from_status
      and to_status = p_to_status
      and active = true
      and v_actor_role = any(allowed_roles)
  ) into v_rule_exists;

  if not v_rule_exists then
    raise exception 'transition from % to % not allowed for role %', v_from_status, p_to_status, coalesce(v_actor_role,'none');
  end if;

  update work_orders
  set current_status = p_to_status,
      closed_at = case when p_to_status in ('completed','cancelled') then now() else closed_at end
  where id = p_work_order_id
  returning * into v_wo;

  insert into work_order_status_history (work_order_id, organization_id, from_status, to_status, actor_profile_id, reason)
  values (p_work_order_id, v_org_id, v_from_status, p_to_status, auth.uid(), p_reason);

  perform log_domain_event(
    v_org_id, 'WORK_ORDER_STATUS_CHANGED', 'work_order', p_work_order_id,
    jsonb_build_object('from_status', v_from_status, 'to_status', p_to_status, 'reason', p_reason)
  );

  perform log_audit_event(
    v_org_id, 'work_orders', p_work_order_id, 'STATUS_TRANSITION',
    jsonb_build_object('status', v_from_status), jsonb_build_object('status', p_to_status)
  );

  return v_wo;
end;
$$;

revoke execute on function transition_work_order(uuid, text, text) from public, anon;
grant execute on function transition_work_order(uuid, text, text) to authenticated;
