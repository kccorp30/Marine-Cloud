-- =========================================================
-- 191_qc_invoice_gate.sql — Marine Cloud Phase 13
-- =========================================================
-- El gate más importante de la fase: transition_work_order() rechaza
-- específicamente quality_control -> invoice si
-- work_orders.qc_required=true y no existe una qc_submission
-- status='passed'. Nunca confía en ocultar el botón de UI.
-- Verificado con datos reales: bloqueado sin QC pasado, permitido tras
-- pasar, y flujo normal intacto cuando qc_required=false.
-- =========================================================

create or replace function transition_work_order(p_work_order_id uuid, p_to_status text, p_reason text DEFAULT NULL::text)
 RETURNS work_orders
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_wo work_orders;
  v_org_id uuid;
  v_from_status text;
  v_actor_role text;
  v_rule_exists boolean;
  v_has_passed_qc boolean;
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

  if v_from_status = 'quality_control' and p_to_status = 'invoice' and v_wo.qc_required then
    select exists (
      select 1 from qc_submissions where work_order_id = p_work_order_id and status = 'passed'
    ) into v_has_passed_qc;
    if not v_has_passed_qc then
      raise exception 'this work order requires a passed QC submission before it can be invoiced';
    end if;
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
$function$;
