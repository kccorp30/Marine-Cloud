-- =========================================================
-- 024_fix_transition_authorization_and_locking.sql
-- =========================================================
-- CRÍTICO: transition_work_order() nunca validaba que un technician
-- estuviera REALMENTE asignado al work order, ni que un customer
-- fuera REALMENTE el dueño — solo verificaba membership + que el rol
-- apareciera en allowed_roles. Un technician o customer del mismo
-- tenant podía transicionar un work order ajeno conociendo el UUID,
-- porque SECURITY DEFINER evita la garantía normal de RLS/SELECT.
--
-- También se agrega SELECT ... FOR UPDATE para evitar que dos
-- transiciones concurrentes validen contra el mismo estado anterior.
-- =========================================================

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
  -- Lock de fila — evita que dos transiciones concurrentes lean el
  -- mismo current_status "viejo" y produzcan historial inconsistente.
  select * into v_wo from work_orders where id = p_work_order_id for update;
  if v_wo.id is null then
    raise exception 'work order not found';
  end if;

  v_org_id := v_wo.organization_id;
  v_from_status := v_wo.current_status;

  -- ---------------------------------------------------------
  -- Autorización de RECURSO (no solo de rol) — esto es lo que faltaba.
  -- ---------------------------------------------------------
  if is_kcc_admin() then
    v_actor_role := 'kcc_admin';  -- acceso global, según transition rules
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

    -- company_owner/company_admin/manager: membership activo en la
    -- organización ya es suficiente (staff opera sobre todo el tenant).
  end if;

  -- ---------------------------------------------------------
  -- Solo AHORA, con el acceso al recurso ya confirmado, se valida la
  -- transición en sí contra el catálogo de reglas.
  -- ---------------------------------------------------------
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

-- CREATE OR REPLACE preserva los grants existentes (mismo OID), pero
-- los reafirmamos explícitamente para no depender de esa suposición.
revoke execute on function transition_work_order(uuid, text, text) from public, anon;
grant execute on function transition_work_order(uuid, text, text) to authenticated;
