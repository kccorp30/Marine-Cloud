-- =========================================================
-- 027_fix_audit_event_internal_calls.sql
-- =========================================================
-- Bug funcional real: log_audit_event() exige is_org_staff() O
-- is_kcc_admin() para escribir — correcto para llamadas DIRECTAS vía
-- RPC, pero transition_work_order() la invoca también en nombre de
-- un technician o customer YA AUTORIZADO por su propia lógica interna
-- (is_assigned_to_work_order / is_customer_of_work_order). Esa
-- re-validación de "staff" rechazaba al technician/customer y rompía
-- la transición completa con una excepción.
--
-- Solución: separar el INSERT interno (nunca expuesto por RPC, solo
-- lo usan otras funciones SECURITY DEFINER que ya hicieron su propia
-- autorización) de la función pública log_audit_event() (que sigue
-- validando "staff" para cualquiera que la llame directo vía RPC).
-- =========================================================

create or replace function log_audit_event_internal(
  p_organization_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_action text,
  p_before jsonb default null,
  p_after jsonb default null,
  p_actor_profile_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into audit_events (organization_id, actor_profile_id, entity_type, entity_id, action, before, after)
  values (p_organization_id, coalesce(p_actor_profile_id, auth.uid()), p_entity_type, p_entity_id, p_action, p_before, p_after)
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function log_audit_event_internal(uuid, text, uuid, text, jsonb, jsonb, uuid) from public, anon, authenticated;

create or replace function log_audit_event(
  p_organization_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_action text,
  p_before jsonb default null,
  p_after jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_organization_id is null then
    if not is_kcc_admin() then
      raise exception 'not authorized to log cross-tenant audit events';
    end if;
  else
    if not (is_org_staff(p_organization_id) or is_kcc_admin()) then
      raise exception 'not authorized to log audit events for this organization';
    end if;
  end if;

  return log_audit_event_internal(p_organization_id, p_entity_type, p_entity_id, p_action, p_before, p_after);
end;
$$;

revoke execute on function log_audit_event(uuid, text, uuid, text, jsonb, jsonb) from public, anon;
grant execute on function log_audit_event(uuid, text, uuid, text, jsonb, jsonb) to authenticated;

-- transition_work_order() ahora llama a la función INTERNA (ya hizo
-- su propia autorización de recurso, no necesita que log_audit_event
-- la revalide como "staff").
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
  select * into v_wo from work_orders where id = p_work_order_id for update;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;

  v_org_id := v_wo.organization_id;
  v_from_status := v_wo.current_status;

  if is_kcc_admin() then
    v_actor_role := 'kcc_admin';
  else
    select role into v_actor_role from organization_memberships
    where profile_id = auth.uid() and organization_id = v_org_id and status = 'active'
    limit 1;

    if v_actor_role is null then
      raise exception 'not authorized for this organization';
    end if;

    if v_actor_role = 'technician' and not is_assigned_to_work_order(p_work_order_id) then
      raise exception 'technician is not assigned to this work order';
    end if;

    if v_actor_role = 'customer' and not is_customer_of_work_order(p_work_order_id) then
      raise exception 'customer does not own this work order';
    end if;
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

  perform log_audit_event_internal(
    v_org_id, 'work_orders', p_work_order_id, 'STATUS_TRANSITION',
    jsonb_build_object('status', v_from_status), jsonb_build_object('status', p_to_status)
  );

  return v_wo;
end;
$$;

revoke execute on function transition_work_order(uuid, text, text) from public, anon;
grant execute on function transition_work_order(uuid, text, text) to authenticated;
